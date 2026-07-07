package SignalWire::Relay::Call;
use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
use Carp        ();
use Time::HiRes ();

use SignalWire::Relay::Action;
use SignalWire::Relay::Constants qw(CALL_TERMINAL_STATES ACTION_TERMINAL_STATES);
use SignalWire::Relay::CallState ();

# isa: call_id is the required correlation key — a bad construction must
# die immediately rather than yield a call the server can never route.
my $NonEmptyStr = sub {
    Carp::croak("must be a non-empty string")
        unless defined $_[0] && !ref $_[0] && length $_[0];
};
my $HashRef = sub {
    Carp::croak("must be a hashref") unless ref $_[0] eq 'HASH';
};
my $ArrayRef = sub {
    Carp::croak("must be an arrayref") unless ref $_[0] eq 'ARRAY';
};

has 'call_id'     => ( is => 'ro', required => 1, isa => $NonEmptyStr );
has 'node_id'     => ( is => 'rw', default  => sub { '' } );
has 'tag'         => ( is => 'ro', default  => sub { '' } );
has 'state'       => ( is => 'rw', default  => sub { 'created' } );
has 'device'      => ( is => 'rw', default  => sub { {} }, isa => $HashRef );
has 'end_reason'  => ( is => 'rw', default  => sub { '' } );
has 'peer'        => ( is => 'rw', default  => sub { {} }, isa => $HashRef );
has 'context'     => ( is => 'rw', default  => sub { '' } );
has 'dial_winner' => ( is => 'rw', default  => sub { 0 } );

has '_client'   => ( is => 'rw', default => sub { undef } );
has '_actions'  => ( is => 'rw', default => sub { {} }, isa => $HashRef );    # control_id => Action
has '_on_event' => ( is => 'rw', default => sub { [] }, isa => $ArrayRef );   # event callbacks

# Helper to generate a UUID-like control_id
sub _generate_uuid {
    my @hex = map { sprintf( '%02x', int( rand(256) ) ) } 1 .. 16;
    $hex[6] = sprintf( '%02x', ( hex( $hex[6] ) & 0x0f ) | 0x40 );
    $hex[8] = sprintf( '%02x', ( hex( $hex[8] ) & 0x3f ) | 0x80 );
    return join( '-',
        join( '', @hex[ 0 .. 3 ] ),
        join( '', @hex[ 4 .. 5 ] ),
        join( '', @hex[ 6 .. 7 ] ),
        join( '', @hex[ 8 .. 9 ] ),
        join( '', @hex[ 10 .. 15 ] ),
    );
}

sub _base_params ($self) {
    return (
        node_id => $self->node_id,
        call_id => $self->call_id,
    );
}

sub _execute ( $self, $method, %extra ) {
    my $client = $self->_client;
    die "No client attached to call" unless $client;
    my %params = ( $self->_base_params, %extra );
    return $client->execute( $method, \%params );
}

# Start an action-based method: creates the Action, registers it, executes the RPC
sub _start_action ( $self, $method, $action_class, %extra ) {
    my $control_id = _generate_uuid();
    my %params     = ( $self->_base_params, control_id => $control_id, %extra );

    my $action = $action_class->new(
        control_id => $control_id,
        call_id    => $self->call_id,
        node_id    => $self->node_id,
        _client    => $self->_client,
    );
    $self->_actions->{$control_id} = $action;

    my $client = $self->_client;
    if ($client) {
        my $result = $client->execute( $method, \%params );

        # If call is gone (404/410), resolve action immediately
        if ( ref $result eq 'HASH' && $result->{code} && $result->{code} =~ /^(404|410)$/ ) {
            $action->_resolve(undef);
        }
    }

    return $action;
}

# --- Event dispatch ---

sub dispatch_event ( $self, $event ) {
    my $event_type = $event->event_type // '';

    # Update call state from state events
    if ( $event_type eq 'calling.call.state' ) {
        my $new_state = $event->call_state // '';
        $self->state($new_state);
        $self->end_reason( $event->end_reason ) if $event->can('end_reason') && $event->end_reason;
        $self->peer( $event->peer )
            if $event->can('peer') && ref $event->peer eq 'HASH' && %{ $event->peer };

        # If call ended, resolve all pending actions
        if ( CALL_TERMINAL_STATES->{$new_state} ) {
            $self->_resolve_all_actions;
        }
    } elsif ( $event_type eq 'calling.call.connect' ) {
        $self->peer( $event->peer ) if $event->can('peer');
    }

    # Route to action by control_id
    my $control_id = $event->can('control_id') ? $event->control_id : '';
    if ( $control_id && exists $self->_actions->{$control_id} ) {
        my $action = $self->_actions->{$control_id};

        # The action decides whether to consume the event. play_and_collect's
        # CollectAction filters calling.call.play events out entirely so they
        # neither dispatch nor terminally resolve.
        my $consumed = 1;
        if ( $action->can('_should_consume_event') ) {
            $consumed = $action->_should_consume_event($event);
        }
        if ($consumed) {
            $action->_handle_event($event);

            # Check if action reached terminal state — but only for events
            # the action consumed, AND only if the action hasn't already
            # decided to resolve itself in _handle_event (e.g. Detect on
            # first detect payload).
            unless ( $action->completed ) {
                my $terminal     = ACTION_TERMINAL_STATES->{$event_type} // {};
                my $action_state = $event->can('state') ? ( $event->state // '' ) : '';
                if ( $terminal->{$action_state} ) {
                    $action->_resolve($event);
                }
            }
            if ( $action->completed ) {
                delete $self->_actions->{$control_id};
            }
        }
    }

    # Fire registered event callbacks
    for my $cb ( @{ $self->_on_event } ) {
        eval { $cb->( $self, $event ) };
        warn "Call event callback error: $@" if $@;
    }
    return;
}

# Register an event listener
sub on ( $self, $cb ) {
    Carp::croak("on() callback must be a coderef") unless ref $cb eq 'CODE';
    push @{ $self->_on_event }, $cb;
    return $self;
}

# --- Typed state accessors (parity alongside the string `state`) ---
#
# `state` stays the canonical bare-string accessor (Python parity). These
# add the SignalWire::Relay::CallState-backed view: a named entry point for
# reading the lifecycle state and asking whether the call has terminated,
# without the caller hard-coding the 'ended' literal. Perl has no enum
# object, so current_state returns the same wire string `state` does — it
# is the typed COMPANION to the CallState predicates, not a different value.

# current_state — the call's lifecycle state as the CallState-typed view.
# Same wire string as ->state (the constants ARE the wire strings); paired
# with CallState->is_state / ->is_terminal for membership/terminality.
sub current_state ($self) {
    return $self->state;
}

# is_terminal — true once the call has reached a terminal lifecycle state
# (CallState terminal set = { ended }). Delegates to CallState so the
# terminal definition lives in one place; returns false (never dies) on an
# unknown/forward-compat state.
sub is_terminal ($self) {
    return SignalWire::Relay::CallState->is_terminal( $self->state );
}

# --- Blocking state waits (parity with Python Call.wait_for*) ---
#
# The Perl RELAY client is thread/loop-driven and updates ->state from
# dispatch_event as `calling.call.state` frames arrive. These helpers block
# (polling, like Action->wait) until the call reaches a target lifecycle
# state, returning immediately if the call is already at or past it. States
# are ordered created < ringing < answered < ending < ended; a call already
# at/past the target resolves with a synthetic state event (mirrors Python's
# Call._wait_for_state short-circuit).

my @_CALL_STATE_ORDER = qw(created ringing answered ending ended);

sub _state_rank ( $self, $state ) {
    for my $i ( 0 .. $#_CALL_STATE_ORDER ) {
        return $i if $_CALL_STATE_ORDER[$i] eq ( $state // '' );
    }
    return -1;
}

sub _synthetic_state_event ($self) {
    require SignalWire::Relay::Event;
    return SignalWire::Relay::Event::CallState->new(
        event_type => 'calling.call.state',
        call_state => $self->state,
        params     => { call_state => $self->state },
    );
}

# wait_for(event_type => $type, predicate => sub, timeout => $secs)
# Block until the first matching event arrives (or the timeout elapses),
# returning the event (or undef on timeout). For state events the predicate
# is evaluated against the live ->state as dispatch_event updates it; a
# one-shot listener captures non-state events. Mirrors Python
# Call.wait_for(event_type, predicate=None, timeout=None).
sub wait_for ( $self, %opts ) {
    my $event_type = $opts{event_type} // '';
    my $predicate  = $opts{predicate};
    my $timeout    = $opts{timeout} // 30;

    my $captured;
    my $listener = sub ( $call, $event ) {
        return if defined $captured;
        return unless ( $event->event_type // '' ) eq $event_type;
        return if $predicate && !$predicate->($event);
        $captured = $event;
    };
    $self->on($listener);

    my $start = time();
    while ( !defined $captured && ( time() - $start ) < $timeout ) {
        Time::HiRes::sleep(0.05);
    }
    return $captured;
}

sub _wait_for_state ( $self, $target, $timeout ) {
    return $self->_synthetic_state_event
        if $self->_state_rank( $self->state ) >= $self->_state_rank($target);
    return $self->wait_for(
        event_type => 'calling.call.state',
        predicate  => sub ($e) {
            my $s = $e->can('call_state') ? $e->call_state : '';
            return defined $s && $s eq $target;
        },
        timeout => $timeout,
    );
}

sub wait_for_answered ( $self, %opts ) {
    return $self->_wait_for_state( 'answered', $opts{timeout} // 30 );
}

sub wait_for_ringing ( $self, %opts ) {
    return $self->_wait_for_state( 'ringing', $opts{timeout} // 30 );
}

sub wait_for_ending ( $self, %opts ) {
    return $self->_wait_for_state( 'ending', $opts{timeout} // 30 );
}

sub wait_for_ended ( $self, %opts ) {
    return $self->_wait_for_state( 'ended', $opts{timeout} // 30 );
}

# Human-readable representation (parity with Python Call.__repr__).
sub to_string ($self) {
    return sprintf( 'Call(call_id=%s, state=%s)', $self->call_id // '', $self->state // '', );
}

# Resolve all pending actions (e.g., on call ended or call-gone)
sub _resolve_all_actions ($self) {
    for my $action ( values %{ $self->_actions } ) {
        $action->_resolve(undef) unless $action->completed;
    }
    $self->_actions( {} );
    return;
}

# --- Simple fire-and-response methods ---

sub answer ( $self, %opts ) {
    return $self->_execute( 'calling.answer', %opts );
}

sub hangup ( $self, %opts ) {
    return $self->_execute( 'calling.end', %opts );
}

sub pass ($self) {
    return $self->_execute('calling.pass');
}

sub connect ( $self, %opts ) {
    return $self->_execute( 'calling.connect', %opts );
}

sub disconnect ($self) {
    return $self->_execute('calling.disconnect');
}

sub hold ($self) {
    return $self->_execute('calling.hold');
}

sub unhold ($self) {
    return $self->_execute('calling.unhold');
}

sub denoise ($self) {
    return $self->_execute('calling.denoise');
}

sub denoise_stop ($self) {
    return $self->_execute('calling.denoise.stop');
}

sub transfer ( $self, %opts ) {
    return $self->_execute( 'calling.transfer', %opts );
}

sub join_conference ( $self, %opts ) {
    return $self->_execute( 'calling.join_conference', %opts );
}

sub leave_conference ( $self, %opts ) {
    return $self->_execute( 'calling.leave_conference', %opts );
}

sub echo ( $self, %opts ) {
    return $self->_execute( 'calling.echo', %opts );
}

sub bind_digit ( $self, %opts ) {
    return $self->_execute( 'calling.bind_digit', %opts );
}

sub clear_digit_bindings ( $self, %opts ) {
    return $self->_execute( 'calling.clear_digit_bindings', %opts );
}

sub live_transcribe ( $self, %opts ) {
    return $self->_execute( 'calling.live_transcribe', %opts );
}

sub live_translate ( $self, %opts ) {
    return $self->_execute( 'calling.live_translate', %opts );
}

sub join_room ( $self, %opts ) {
    return $self->_execute( 'calling.join_room', %opts );
}

sub leave_room ( $self, %opts ) {

    # Python parity: Call.leave_room(**kwargs). Forwards any caller-provided
    # kwargs to the Relay leave_room dispatch (slurpy hash on the Perl side
    # ≡ **kwargs on the Python side).
    return $self->_execute( 'calling.leave_room', %opts );
}

sub amazon_bedrock ( $self, %opts ) {
    return $self->_execute( 'calling.amazon_bedrock', %opts );
}

sub ai_message ( $self, %opts ) {
    return $self->_execute( 'calling.ai_message', %opts );
}

sub ai_hold ( $self, %opts ) {
    return $self->_execute( 'calling.ai_hold', %opts );
}

sub ai_unhold ( $self, %opts ) {
    return $self->_execute( 'calling.ai_unhold', %opts );
}

sub user_event ( $self, %opts ) {
    return $self->_execute( 'calling.user_event', %opts );
}

sub queue_enter ( $self, %opts ) {
    return $self->_execute( 'calling.queue.enter', %opts );
}

sub queue_leave ( $self, %opts ) {
    return $self->_execute( 'calling.queue.leave', %opts );
}

sub refer ( $self, %opts ) {
    return $self->_execute( 'calling.refer', %opts );
}

sub send_digits ( $self, %opts ) {
    return $self->_execute( 'calling.send_digits', %opts );
}

# --- Action-based methods (control_id tracking) ---

sub play ( $self, %opts ) {
    return $self->_start_action( 'calling.play', 'SignalWire::Relay::Action::Play', %opts );
}

# --- Play convenience: typed wrappers over play() ---
#
# These restore the legacy call->play_tts(text => ...) ergonomics so
# callers don't hand-build the { type => "...", params => {...} } media
# shape. Each delegates to play() with the exact RELAY media object
# (see RELAY_IMPLEMENTATION_GUIDE.md "Media Objects"). Optional params
# are only included when the caller supplies them, so the wire shape
# carries no undef keys.

sub play_tts ( $self, $text, %opts ) {
    my %tts = ( text => $text );
    $tts{language} = $opts{language} if defined $opts{language};
    $tts{gender}   = $opts{gender}   if defined $opts{gender};
    $tts{voice}    = $opts{voice}    if defined $opts{voice};
    my @play = ( play => [ { type => 'tts', params => \%tts } ] );
    push @play, ( volume       => $opts{volume} )       if defined $opts{volume};
    push @play, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->play(@play);
}

sub play_audio ( $self, $url, %opts ) {
    my @play = ( play => [ { type => 'audio', params => { url => $url } } ] );
    push @play, ( volume       => $opts{volume} )       if defined $opts{volume};
    push @play, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->play(@play);
}

sub play_silence ( $self, $duration, %opts ) {
    my @play = ( play => [ { type => 'silence', params => { duration => $duration } } ] );
    push @play, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->play(@play);
}

sub play_ringtone ( $self, $name, %opts ) {
    my %rt = ( name => $name );
    $rt{duration} = $opts{duration} if defined $opts{duration};
    my @play = ( play => [ { type => 'ringtone', params => \%rt } ] );
    push @play, ( volume       => $opts{volume} )       if defined $opts{volume};
    push @play, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->play(@play);
}

sub record ( $self, %opts ) {
    return $self->_start_action( 'calling.record', 'SignalWire::Relay::Action::Record', %opts );
}

sub detect ( $self, %opts ) {
    return $self->_start_action( 'calling.detect', 'SignalWire::Relay::Action::Detect', %opts );
}

# --- Detect convenience: typed wrappers over detect() ---
#
# Build the RELAY detect object { type => "...", params => {...} } and
# forward to detect(). The optional timeout is a sibling of `detect` in
# the calling.detect params, not inside the detect object — same as
# Python's Call.detect_*.

sub detect_digit ( $self, %opts ) {
    my %params;
    $params{digits} = $opts{digits} if defined $opts{digits};
    my @args = ( detect => { type => 'digit', params => \%params } );
    push @args, ( timeout      => $opts{timeout} )      if defined $opts{timeout};
    push @args, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->detect(@args);
}

sub detect_answering_machine ( $self, %opts ) {
    my %params;

    # Only the AMD knobs the caller actually provided land in params; the
    # server fills the rest from its defaults.
    for my $key (
        qw(
        initial_timeout end_silence_timeout machine_voice_threshold
        machine_words_threshold detect_interruptions detect_message_end
        )
        )
    {
        $params{$key} = $opts{$key} if defined $opts{$key};
    }
    my @args = ( detect => { type => 'machine', params => \%params } );
    push @args, ( timeout      => $opts{timeout} )      if defined $opts{timeout};
    push @args, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->detect(@args);
}

sub detect_fax ( $self, %opts ) {
    my %params;
    $params{tone} = $opts{tone} if defined $opts{tone};
    my @args = ( detect => { type => 'fax', params => \%params } );
    push @args, ( timeout      => $opts{timeout} )      if defined $opts{timeout};
    push @args, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->detect(@args);
}

sub collect ( $self, %opts ) {
    return $self->_start_action( 'calling.collect', 'SignalWire::Relay::Action::StandaloneCollect',
        %opts );
}

sub play_and_collect ( $self, %opts ) {
    return $self->_start_action( 'calling.play_and_collect', 'SignalWire::Relay::Action::Collect',
        %opts );
}

# --- Prompt convenience: typed media over play_and_collect() ---
#
# Play a TTS / audio prompt and collect input in one call. The `collect`
# hashref is passed through verbatim (see RELAY guide "Collect Object");
# only the play media is built from the typed args.

sub prompt_tts ( $self, $text, $collect, %opts ) {
    my %tts = ( text => $text );
    $tts{language} = $opts{language} if defined $opts{language};
    $tts{gender}   = $opts{gender}   if defined $opts{gender};
    $tts{voice}    = $opts{voice}    if defined $opts{voice};
    my @args = (
        play    => [ { type => 'tts', params => \%tts } ],
        collect => $collect,
    );
    push @args, ( volume       => $opts{volume} )       if defined $opts{volume};
    push @args, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->play_and_collect(@args);
}

sub prompt_audio ( $self, $url, $collect, %opts ) {
    my @args = (
        play    => [ { type => 'audio', params => { url => $url } } ],
        collect => $collect,
    );
    push @args, ( volume       => $opts{volume} )       if defined $opts{volume};
    push @args, ( on_completed => $opts{on_completed} ) if defined $opts{on_completed};
    return $self->play_and_collect(@args);
}

sub send_fax ( $self, %opts ) {
    my $action =
        $self->_start_action( 'calling.send_fax', 'SignalWire::Relay::Action::Fax', %opts );
    return $action;
}

sub receive_fax ( $self, %opts ) {
    my $control_id = _generate_uuid();
    my %params     = ( $self->_base_params, control_id => $control_id, %opts );

    my $action = SignalWire::Relay::Action::Fax->new(
        control_id => $control_id,
        call_id    => $self->call_id,
        node_id    => $self->node_id,
        _client    => $self->_client,
        _fax_type  => 'receive',
    );
    $self->_actions->{$control_id} = $action;

    my $client = $self->_client;
    if ($client) {
        my $result = $client->execute( 'calling.receive_fax', \%params );
        if ( ref $result eq 'HASH' && $result->{code} && $result->{code} =~ /^(404|410)$/ ) {
            $action->_resolve(undef);
        }
    }

    return $action;
}

sub tap ( $self, %opts ) {
    return $self->_start_action( 'calling.tap', 'SignalWire::Relay::Action::Tap', %opts );
}

sub stream ( $self, %opts ) {
    return $self->_start_action( 'calling.stream', 'SignalWire::Relay::Action::Stream', %opts );
}

sub pay ( $self, %opts ) {
    return $self->_start_action( 'calling.pay', 'SignalWire::Relay::Action::Pay', %opts );
}

sub transcribe ( $self, %opts ) {
    return $self->_start_action( 'calling.transcribe', 'SignalWire::Relay::Action::Transcribe',
        %opts );
}

sub ai ( $self, %opts ) {
    return $self->_start_action( 'calling.ai', 'SignalWire::Relay::Action::AI', %opts );
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Relay::Call - a RELAY call handle and its call-control verbs

=head1 SYNOPSIS

    # Calls are produced by SignalWire::Relay::Client, not constructed
    # directly:
    $call->answer;
    $call->play_tts( text => 'Hello', voice => 'en-US-Neural2-A' );

    my $rec = $call->record( record => { ... } );  # returns an Action
    $rec->on_completed(sub ($a) { ... });

    $call->on(sub ($c, $event) { ... });   # raw event listener
    $call->hangup;

=head1 DESCRIPTION

L<SignalWire::Relay::Call> is the Perl port of the Python reference's call
object. It models one RELAY call: it carries call state, demultiplexes
incoming events (updating state, routing to the right
L<SignalWire::Relay::Action> by C<control_id>, and firing listeners), and
exposes the full set of call-control verbs.

Construction fails fast: C<call_id> is required and must be a non-empty
string; C<device> / C<peer> must be hashrefs (Moo C<isa> constraints).
These objects are created by L<SignalWire::Relay::Client>.

=head2 Fire-and-response verbs

C<answer>, C<hangup>, C<pass>, C<connect>, C<disconnect>, C<hold>,
C<unhold>, C<denoise>, C<denoise_stop>, C<transfer>, C<join_conference>,
C<leave_conference>, C<echo>, C<bind_digit>, C<clear_digit_bindings>,
C<live_transcribe>, C<live_translate>, C<join_room>, C<leave_room>,
C<amazon_bedrock>, C<ai_message>, C<ai_hold>, C<ai_unhold>, C<user_event>,
C<queue_enter>, C<queue_leave>, C<refer>, C<send_digits>. Each forwards
its keyword arguments to the matching RELAY method.

=head2 Action-based verbs

C<play>, C<record>, C<detect>, C<collect>, C<play_and_collect>,
C<send_fax>, C<receive_fax>, C<tap>, C<stream>, C<pay>, C<transcribe>,
C<ai> — each returns a L<SignalWire::Relay::Action> subclass that tracks a
C<control_id> and resolves when the operation completes.

=head2 Typed convenience wrappers

C<play_tts>, C<play_audio>, C<play_silence>, C<play_ringtone> build the
RELAY media object and delegate to C<play>. C<detect_digit>,
C<detect_answering_machine>, C<detect_fax> build the detect object and
delegate to C<detect>. C<prompt_tts> / C<prompt_audio> play a prompt and
collect input via C<play_and_collect>.

=head2 Events

=over 4

=item * C<on($cb)> — register a listener invoked as
C<< $cb->($call, $event) >> for every dispatched event. The callback must
be a coderef.

=item * C<dispatch_event($event)> — apply an incoming event (normally
called by the client).

=back

=head2 Typed state

C<state> remains the canonical bare-string accessor. These add the
L<SignalWire::Relay::CallState>-backed view:

=over 4

=item * C<current_state> — the call's lifecycle state as the CallState-typed
view. Returns the same wire string as C<state> (the CallState constants
B<are> the wire strings); pair it with
C<< SignalWire::Relay::CallState->is_state >> /
C<< ->is_terminal >> for membership and terminality.

=item * C<is_terminal> — true once the call has reached a terminal lifecycle
state (C<ended>). Delegates to L<SignalWire::Relay::CallState> so the
terminal definition lives in one place; returns false (never dies) on an
unknown/forward-compatible state.

=back

=head1 SEE ALSO

L<SignalWire::Relay::Client>, L<SignalWire::Relay::Action>,
L<SignalWire::Relay::Event>, L<SignalWire::Relay::Constants>,
L<SignalWire::Relay::CallState>, L<SignalWire::Relay::Device>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
