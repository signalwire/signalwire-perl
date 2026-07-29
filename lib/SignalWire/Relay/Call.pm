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
use SignalWire::Core::Random     ();

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

has 'call_id' => ( is => 'ro', required => 1, isa => $NonEmptyStr );
has 'node_id' => ( is => 'rw', default  => sub { '' } );
has 'tag'     => ( is => 'ro', default  => sub { '' } );
has 'state'   => ( is => 'rw', default  => sub { 'created' } );
has 'device'  => ( is => 'rw', default  => sub { {} }, isa => $HashRef );

# project_id / direction / segment_id are caller-supplied construction params
# the reference records on Call (relay/call.py:341-353) and populates from the
# `calling.call.receive` / `calling.call.state` / dial-leg wire frames
# (relay/client.py:1068-1071, :1152, :1206). Perl accepted none of them, so a
# handler could not tell an inbound call from an outbound leg, could not read
# the project the call belongs to, and could not correlate segments.
has 'project_id' => ( is => 'rw', default => sub { '' } );
has 'direction'  => ( is => 'rw', default => sub { '' } );
has 'segment_id' => ( is => 'rw', default => sub { '' } );

has 'end_reason'  => ( init_arg => undef, is      => 'rw', default => sub { '' } );
has 'peer'        => ( init_arg => undef, is      => 'rw', default => sub { {} }, isa => $HashRef );
has 'context'     => ( is       => 'rw',  default => sub { '' } );
has 'dial_winner' => ( init_arg => undef, is      => 'rw', default => sub { 0 } );

has '_client' => ( is => 'rw', default => sub { undef } );
has '_actions' => ( init_arg => undef, is => 'rw', default => sub { {} }, isa => $HashRef )
    ;    # control_id => Action
has '_on_event' => ( init_arg => undef, is => 'rw', default => sub { [] }, isa => $ArrayRef )
    ;    # event callbacks

# Helper to generate a UUID-like control_id
sub _generate_uuid {
    return SignalWire::Core::Random::_random_uuid4();
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
    my $result = $client->execute( $method, \%params );
    return _apply_a2_contract( $self, $method, $result );
}

# A2 relay-contract (the documented behavior — only "call gone" is swallowed):
# a verb RPC whose result carries a non-2xx `code` is a server-side status. A
# 404/410 means the call no longer exists, so the verb is a no-op (swallowed,
# returns the result). ANY OTHER non-2xx code (e.g. 500) is a real server-side
# failure the caller MUST see, so it RAISES a RelayError. Mirrors the python
# reference (relay/call.py _execute: swallow 404/410, raise everything else).
sub _apply_a2_contract ( $self, $method, $result ) {
    return $result unless ref $result eq 'HASH';
    my $code = $result->{code};
    return $result unless defined $code && $code =~ /^[0-9]+$/;
    return $result if $code >= 200 && $code < 300;     # success
    return $result if $code == 404 || $code == 410;    # call gone -> swallow (no-op)

    # Real server-side failure -> raise, so a caller's eval sees it.
    my $message = $result->{message} // $result->{error} // "RELAY $method failed";
    die SignalWire::Relay::Client::RelayError->new(
        code    => $code,
        message => "$message (code=$code)",
    );
}

# Start an action-based method: creates the Action, registers it, executes the RPC
sub _start_action ( $self, $method, $action_class, %extra ) {
    my $control_id = _generate_uuid();
    my %params     = ( $self->_base_params, control_id => $control_id, %extra );

    # The Action derives call_id / node_id / client from the call handle, the
    # same way the reference's Action.__init__(call, control_id, ...) does.
    my $action = $action_class->new(
        call       => $self,
        control_id => $control_id,
    );
    $self->_actions->{$control_id} = $action;

    my $client = $self->_client;
    if ($client) {
        my $result = $client->execute( $method, \%params );

        # A2 contract: a 500-class result raises (server-side failure the caller
        # must see); 404/410 (call gone) resolves the action as a no-op. On a
        # raise, drop the just-registered action so it is not left dangling.
        my $ok = eval { _apply_a2_contract( $self, $method, $result ); 1 };
        unless ($ok) {
            my $err = $@;
            delete $self->_actions->{$control_id};
            die $err;
        }
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

    # PUMP the event loop while waiting: the listener only fires when a frame
    # is read and dispatched (inside the client's _read_once), so a bare sleep
    # here would never capture the awaited event and wait_for would hang the
    # full timeout, returning undef. _read_once select()s with its own 0.1s
    # timeout. (Fallback sleep only when no client is attached.)
    my $client = $self->_client;
    my $start  = time();
    while ( !defined $captured && ( time() - $start ) < $timeout ) {
        if ($client) {
            $client->_read_once;
        } else {
            Time::HiRes::sleep(0.05);
        }
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

sub live_transcribe ( $self, $action, %opts ) {
    return $self->_execute( 'calling.live_transcribe', action => $action, %opts );
}

sub live_translate ( $self, $action, %opts ) {
    return $self->_execute( 'calling.live_translate', action => $action, %opts );
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
        call          => $self,
        control_id    => $control_id,
        method_prefix => 'receive_fax',
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

=head2 Call identity attributes

Each of these is settable at construction and readable back, matching the
Python reference's C<Call.__init__>. L<SignalWire::Relay::Client> populates
them from the C<calling.call.receive> / C<calling.call.state> / dial-leg
frames, so an C<on_call> handler can read them directly.

=over 4

=item C<call_id>

The RELAY call correlation id (required, non-empty).

=item C<node_id>

The RELAY node handling this call.

=item C<project_id>

The SignalWire project the call belongs to. Defaults to the client's own
C<project> when the frame omits it.

=item C<context>

The RELAY context (protocol) the call arrived on.

=item C<direction>

C<"inbound"> for a received call, C<"outbound"> for a dialed leg.

=item C<segment_id>

The call-segment correlation id, empty when the frame omits it.

=item C<tag>

The dial tag correlating a leg to its originating C<calling.dial>.

=item C<state>

The call's lifecycle state; updated as C<calling.call.state> events arrive.

=item C<device>

The device hashref (type plus C<from_number> / C<to_number> params).

=back

=head2 Fire-and-response verbs

Each sends its RELAY method with the call's C<node_id>/C<call_id> plus the
caller's keyword arguments, and returns the server's decoded result hashref.
All of them apply the A2 relay contract: a result carrying C<code> 404 or 410
means the call is already gone, so the verb is a silent no-op; any other
non-2xx C<code> raises a C<SignalWire::Relay::Client::RelayError>.

=over 4

=item C<answer(%opts)>

Answer an inbound call (C<calling.answer>).

=item C<hangup(%opts)>

End the call (C<calling.end>). C<%opts> may carry a C<reason>.

=item C<pass()>

Decline the call so another consumer in the same context may take it
(C<calling.pass>). Takes no arguments.

=item C<connect(%opts)>

Dial one or more peer devices and bridge them to this call
(C<calling.connect>). The C<devices> argument is the serial/parallel nested
arrayref the RELAY guide describes.

=item C<disconnect()>

Tear down the current peer bridge (C<calling.disconnect>), leaving this leg
up. Takes no arguments.

=item C<hold()> / C<unhold()>

Place the call on hold and take it off again (C<calling.hold> /
C<calling.unhold>). Neither takes arguments.

=item C<denoise()> / C<denoise_stop()>

Start and stop server-side background-noise suppression
(C<calling.denoise> / C<calling.denoise.stop>). Neither takes arguments.

=item C<transfer(%opts)>

Hand the call off to another destination (C<calling.transfer>), ending this
SDK's control of it.

=item C<join_conference(%opts)> / C<leave_conference(%opts)>

Join and leave a named conference (C<calling.join_conference> /
C<calling.leave_conference>).

=item C<join_room(%opts)> / C<leave_room(%opts)>

Join and leave a video room (C<calling.join_room> / C<calling.leave_room>).

=item C<echo(%opts)>

Echo the call's own audio back to it (C<calling.echo>) — a media-path
diagnostic.

=item C<bind_digit(%opts)> / C<clear_digit_bindings(%opts)>

Register a DTMF digit that raises an event when pressed, and clear every
such binding (C<calling.bind_digit> / C<calling.clear_digit_bindings>).

=item C<live_transcribe($action, %opts)> / C<live_translate($action, %opts)>

Control live transcription and translation
(C<calling.live_transcribe> / C<calling.live_translate>). C<$action> is
positional and is sent as the C<action> parameter (e.g. C<start> / C<stop>).

=item C<amazon_bedrock(%opts)>

Attach an Amazon Bedrock agent to the call (C<calling.amazon_bedrock>).
This is its own RELAY method, not C<calling.ai> with an engine argument.

=item C<ai_message(%opts)> / C<ai_hold()> / C<ai_unhold()>

Inject a message into a running AI session, and hold/unhold that session
(C<calling.ai_message> / C<calling.ai_hold> / C<calling.ai_unhold>).
C<ai_hold> and C<ai_unhold> accept keyword arguments but normally take none.

=item C<user_event(%opts)>

Emit an application-defined event onto the call (C<calling.user_event>).

=item C<queue_enter(%opts)> / C<queue_leave(%opts)>

Place the call into a queue and remove it (C<calling.queue.enter> /
C<calling.queue.leave>).

=item C<refer(%opts)>

Send a SIP REFER (C<calling.refer>).

=item C<send_digits(%opts)>

Send a DTMF string out on the call (C<calling.send_digits>).

=back

=head2 Action-based verbs

Each starts a long-running operation and returns a
L<SignalWire::Relay::Action> subclass immediately, B<without> blocking. The
Action carries a generated C<control_id>, is registered on the call so
incoming events route to it, and resolves when the operation reaches a
terminal state — call C<< ->wait >> or C<< ->on_completed >> on it. If the
call is already gone (404/410) the Action resolves at once; any other
non-2xx result raises and the Action is not left registered.

=over 4

=item C<play(%opts)>

Play a media list (C<calling.play>). C<play> is an arrayref of RELAY media
objects. Returns a C<::Play> action.

=item C<record(%opts)>

Start recording (C<calling.record>). Returns a C<::Record> action whose
C<url>, C<duration> and C<size> are populated on completion.

=item C<detect(%opts)>

Run a detector (C<calling.detect>). Returns a C<::Detect> action that
resolves on the first detect payload.

=item C<collect(%opts)>

Collect digits or speech with no prompt (C<calling.collect>). Returns a
C<::StandaloneCollect> action.

=item C<play_and_collect(%opts)>

Play a prompt and collect input in one operation
(C<calling.play_and_collect>). Returns a C<::Collect> action, which
deliberately filters C<calling.call.play> events out so a finished prompt
does not resolve the collect.

=item C<send_fax(%opts)> / C<receive_fax(%opts)>

Send and receive a fax (C<calling.send_fax> / C<calling.receive_fax>).
Both return a C<::Fax> action; C<receive_fax> constructs it with
C<method_prefix> C<receive_fax> so its stop verb targets the right method.

=item C<tap(%opts)> / C<stream(%opts)>

Start media tapping and media streaming (C<calling.tap> /
C<calling.stream>). Return C<::Tap> and C<::Stream> actions, both
stop-verb-only.

=item C<pay(%opts)>

Run a payment collection flow (C<calling.pay>). Returns a C<::Pay> action.

=item C<transcribe(%opts)>

Start transcription (C<calling.transcribe>). Returns a C<::Transcribe>
action, stop-verb-only.

=item C<ai(%opts)>

Attach an AI agent to the call (C<calling.ai>). Returns an C<::AI> action,
stop-verb-only.

=back

=head2 Typed convenience wrappers

These build the RELAY media/detect object for you and delegate to the verb
above. Optional parameters are included only when you actually supply them,
so the emitted wire object carries no C<undef> keys.

=over 4

=item C<play_tts($text, %opts)>

Play synthesized speech. Sends C<< { type => 'tts', params => { text => $text } } >>
to C<play>; C<language>, C<gender> and C<voice> are folded into the TTS
params when given, and C<volume> / C<on_completed> are passed to C<play> as
siblings of the media list.

=item C<play_audio($url, %opts)>

Play the audio file at C<$url> (C<< { type => 'audio' } >>). Accepts
C<volume> and C<on_completed>.

=item C<play_silence($duration, %opts)>

Play C<$duration> seconds of silence (C<< { type => 'silence' } >>).
Accepts C<on_completed>. Note it takes no C<volume>.

=item C<play_ringtone($name, %opts)>

Play the named ringtone (C<< { type => 'ringtone' } >>). Accepts
C<duration>, C<volume> and C<on_completed>.

=item C<detect_digit(%opts)>

Detect DTMF (C<< { type => 'digit' } >>). C<digits> narrows which digits
count. C<timeout> is a sibling of the detect object, not one of its params.

=item C<detect_answering_machine(%opts)>

Run answering-machine detection (C<< { type => 'machine' } >>). Only the
AMD knobs you pass are sent — C<initial_timeout>, C<end_silence_timeout>,
C<machine_voice_threshold>, C<machine_words_threshold>,
C<detect_interruptions>, C<detect_message_end> — and the server defaults the
rest.

=item C<detect_fax(%opts)>

Detect fax tones (C<< { type => 'fax' } >>). C<tone> selects which tone.

=item C<prompt_tts($text, $collect, %opts)> / C<prompt_audio($url, $collect, %opts)>

Play a TTS or audio prompt and collect input, via C<play_and_collect>.
C<$collect> is passed through verbatim as the RELAY collect object; only the
play media is built for you. Both accept C<volume> and C<on_completed>.

=back

=head2 Blocking state waits

=over 4

=item C<wait_for(%opts)>

Block until the first event matching C<event_type> arrives (optionally
filtered by a C<predicate> coderef), returning that event, or C<undef> if
C<timeout> (default 30s) elapses first. This B<pumps the client's read loop>
while it waits — a bare sleep would never see the event, because listeners
only fire as frames are dispatched.

=item C<wait_for_ringing(%opts)>, C<wait_for_answered(%opts)>, C<wait_for_ending(%opts)>, C<wait_for_ended(%opts)>

Block until the call reaches that lifecycle state, honouring C<timeout>
(default 30s). States are ordered
C<created> E<lt> C<ringing> E<lt> C<answered> E<lt> C<ending> E<lt> C<ended>,
and a call already at or B<past> the requested state returns immediately with
a synthetic state event rather than waiting for one that will never come
again.

=back

=head2 Events

=over 4

=item * C<on($cb)> — register a listener invoked as
C<< $cb->($call, $event) >> for every dispatched event. The callback must
be a coderef. Returns C<$self> so calls chain. A callback that dies is
warned about, not fatal — one bad listener cannot break dispatch.

=item * C<dispatch_event($event)> — apply an incoming event (normally
called by the client). Updates C<state>/C<end_reason>/C<peer> from state
frames, resolves every pending action once the call reaches a terminal
state, routes the event to the action owning its C<control_id>, then fires
the C<on> listeners.

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

=head2 Diagnostics

=over 4

=item C<to_string()>

A human-readable C<Call(call_id=..., state=...)> summary, the Perl
counterpart of the reference's C<__repr__>.

=back

=head1 SEE ALSO

L<SignalWire::Relay::Client>, L<SignalWire::Relay::Action>,
L<SignalWire::Relay::Event>, L<SignalWire::Relay::Constants>,
L<SignalWire::Relay::CallState>, L<SignalWire::Relay::Device>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
