package SignalWire::Relay::Action;
use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
use Scalar::Util ();
use Carp         ();
use Time::HiRes  ();

# Base Action class for long-running RELAY operations.
# Tracks control_id, completion state, and supports blocking wait.

# isa constraint: control_id is the required correlation key and must be a
# non-empty string so a bad construction dies immediately rather than
# silently producing an action the server can never match.
my $NonEmptyStr = sub {
    Carp::croak("must be a non-empty string")
        unless defined $_[0] && !ref $_[0] && length $_[0];
};
my $ArrayRef = sub {
    Carp::croak("must be an arrayref") unless ref $_[0] eq 'ARRAY';
};
my $HashRef = sub {
    Carp::croak("must be a hashref") unless ref $_[0] eq 'HASH';
};

has 'control_id' => ( is => 'ro', required => 1, isa => $NonEmptyStr );

# The Call this action belongs to. This is the reference's construction
# contract — ``Action.__init__(call, control_id, terminal_event,
# terminal_states)`` (relay/call.py:75-82) stores ``self.call = call`` and
# reads the call's identity off it. Perl now takes the same handle instead of
# the three separately-passed identity fields it used to accept, so the
# constructor surface matches the reference and the identity can never
# disagree with the call it came from.
has 'call' => ( is => 'ro', default => sub { undef }, weak_ref => 1 );

# Identity + transport, DERIVED from ``call`` (never constructor arguments):
# the reference reads these through ``self.call``, so there is nothing for a
# caller to supply and no way for them to drift from the owning call.
#
# These are SNAPSHOTTED EAGERLY in BUILD, not derived lazily on first use. The
# reference keeps a STRONG back-reference (``self.call = call``,
# relay/call.py:82) and relies on Python's cycle collector to reclaim the
# Call <-> Action cycle. Perl refcounts, so ``call`` must stay ``weak_ref`` or
# the cycle leaks (``Call._actions`` holds every Action strongly). But a weak
# handle plus LAZY derivation loses the identity outright the moment the Call
# goes out of scope, and every control-op then silently no-ops on its
# ``return unless $client`` guard — so the perfectly ordinary
# ``$call->play(...)->stop`` emitted NO frame, and neither did pause / resume /
# volume. Reading the fields while the handle is guaranteed alive keeps the
# cycle broken AND makes an Action outlive its Call exactly as the reference's
# does.
has 'call_id' => ( init_arg => undef, is => 'rw', default => sub { '' } );
has 'node_id' => ( init_arg => undef, is => 'rw', default => sub { '' } );
has '_client' => ( init_arg => undef, is => 'rw', default => sub { undef } );

sub BUILD ( $self, $args ) {
    my $call = $self->call or return;
    $self->call_id( $call->call_id // '' );
    $self->node_id( $call->node_id // '' );
    $self->_client( $call->_client );
    return;
}

# Live state, written by the event pipeline (_check_event/_resolve), exactly
# as the reference sets self.result / self.completed after construction.
has 'state'     => ( init_arg => undef, is => 'rw', default => sub { 'created' } );
has 'completed' => ( init_arg => undef, is => 'rw', default => sub { 0 } );           # boolean
has 'result'    => ( init_arg => undef, is => 'rw', default => sub { undef } );
has 'events'    => ( init_arg => undef, is => 'rw', default => sub { [] }, isa => $ArrayRef );
has 'payload' => ( init_arg => undef, is => 'rw', default => sub { {} }, isa => $HashRef )
    ;    # latest event payload

has '_on_completed' => ( init_arg => undef, is => 'rw', default => sub { undef } );

# Register on_completed callback
sub on_completed ( $self, $cb = undef ) {
    if ($cb) {
        $self->_on_completed($cb);

        # If already done, fire immediately
        if ( $self->completed ) {
            eval { $cb->($self) };
            warn "on_completed callback error: $@" if $@;
        }
        return $self;
    }
    return $self->_on_completed;
}

# Check if the action is done
sub is_done ($self) {
    return $self->completed;
}

# Blocking wait: PUMP the event loop until the action completes or the
# deadline passes. The completion flag only flips when a frame is read and
# dispatched, and dispatch happens inside the client's _read_once — so a bare
# sleep here would never see the completing event and the documented pattern
# (answer; play; $action->wait) would hang the full timeout and return undef.
# _read_once select()s with its own 0.1s timeout, so this both waits and
# advances the loop. (Fallback sleep only when no client is attached — e.g. a
# detached/unit-constructed action — so it never hot-spins.)
sub wait ( $self, %opts ) {
    my $timeout = $opts{timeout} || 30;
    my $start   = time();
    my $client  = $self->_client;
    while ( !$self->completed && ( time() - $start ) < $timeout ) {
        if ($client) {
            $client->_read_once;
        } else {
            Time::HiRes::sleep(0.1);
        }
    }
    return $self->result;
}

# Called by event dispatch when an event is received for this action
sub _handle_event ( $self, $event ) {
    push @{ $self->events }, $event;
    $self->payload( $event->params // {} );

    my $state = $event->can('state') ? $event->state : '';
    $self->state($state) if $state;
    return;
}

# Mark the action as completed with a result
sub _resolve ( $self, $result ) {
    return if $self->completed;
    $self->completed(1);
    $self->result($result);

    if ( my $cb = $self->_on_completed ) {
        eval { $cb->($self) };
        warn "on_completed callback error: $@" if $@;
    }
    return;
}

# Send a sub-command on this action (e.g., play.stop, record.pause)
sub _execute_subcommand ( $self, $method ) {
    my $client = $self->_client;
    return unless $client;
    return $client->execute(
        $method,
        {
            node_id    => $self->node_id,
            call_id    => $self->call_id,
            control_id => $self->control_id,
        }
    );
}

# Stop the action
sub stop ($self) {
    return if $self->completed;
    return $self->_execute_subcommand( $self->_stop_method );
}

# Override in subclasses
sub _stop_method { return '' }

# --- PlayAction ---
package SignalWire::Relay::Action::Play;
use Moo;
extends 'SignalWire::Relay::Action';

sub _stop_method { return 'calling.play.stop' }

sub pause ( $self, $behavior = undef ) {
    my $client = $self->_client;
    return unless $client;
    my $params = {
        node_id    => $self->node_id,
        call_id    => $self->call_id,
        control_id => $self->control_id,
    };
    $params->{behavior} = $behavior if defined $behavior;
    return $client->execute( 'calling.play.pause', $params );
}

sub resume ($self) {
    return $self->_execute_subcommand('calling.play.resume');
}

sub volume ( $self, $volume ) {
    my $client = $self->_client;
    return unless $client;
    return $client->execute(
        'calling.play.volume',
        {
            node_id    => $self->node_id,
            call_id    => $self->call_id,
            control_id => $self->control_id,
            volume     => $volume,
        }
    );
}

# --- RecordAction ---
package SignalWire::Relay::Action::Record;
use Moo;
extends 'SignalWire::Relay::Action';

sub _stop_method { return 'calling.record.stop' }

sub pause ( $self, %opts ) {
    my $client = $self->_client;
    return unless $client;
    my $params = {
        node_id    => $self->node_id,
        call_id    => $self->call_id,
        control_id => $self->control_id,
    };
    $params->{behavior} = $opts{behavior} if $opts{behavior};
    return $client->execute( 'calling.record.pause', $params );
}

sub resume ($self) {
    return $self->_execute_subcommand('calling.record.resume');
}

# Result accessors
sub url      { my ($self) = @_; return $self->payload->{url}      // '' }
sub duration { my ($self) = @_; return $self->payload->{duration} // 0 }
sub size     { my ($self) = @_; return $self->payload->{size}     // 0 }

# --- DetectAction ---
package SignalWire::Relay::Action::Detect;
use Moo;
extends 'SignalWire::Relay::Action';

sub _stop_method { return 'calling.detect.stop' }

sub detect_result { my ($self) = @_; return $self->payload->{detect} // {} }

# Detect resolves on the FIRST `params.detect` payload (the actual
# detection result), not on a state(finished). Mirror Python's
# ``DetectAction._check_event``.
sub _handle_event ( $self, $event ) {
    $self->SUPER::_handle_event($event);
    return if $self->completed;
    my $params = $event->params // {};
    if (   ref $params eq 'HASH'
        && ref $params->{detect} eq 'HASH'
        && %{ $params->{detect} } )
    {
        $self->_resolve($event);
    }
    return;
}

# --- CollectAction (used by play_and_collect) ---
package SignalWire::Relay::Action::Collect;
use Moo;
extends 'SignalWire::Relay::Action';

# play_and_collect's stop verb is calling.play_and_collect.stop, not
# calling.collect.stop. The standalone collect uses StandaloneCollect
# below.
sub _stop_method { return 'calling.play_and_collect.stop' }

# play_and_collect wraps an embedded play, so the collect action exposes the
# same play controls (pause/resume/volume) the reference projects onto
# CollectAction — they act on the embedded play leg.
sub pause ( $self, $behavior = undef ) {
    my $client = $self->_client;
    return unless $client;
    my $params = {
        node_id    => $self->node_id,
        call_id    => $self->call_id,
        control_id => $self->control_id,
    };
    $params->{behavior} = $behavior if defined $behavior;
    return $client->execute( 'calling.play_and_collect.pause', $params );
}

sub resume ($self) {
    return $self->_execute_subcommand('calling.play_and_collect.resume');
}

sub volume ( $self, $volume ) {
    my $client = $self->_client;
    return unless $client;
    return $client->execute(
        'calling.play_and_collect.volume',
        {
            node_id    => $self->node_id,
            call_id    => $self->call_id,
            control_id => $self->control_id,
            volume     => $volume,
        }
    );
}

sub start_input_timers ($self) {
    return $self->_execute_subcommand('calling.collect.start_input_timers');
}

sub collect_result { my ($self) = @_; return $self->payload->{result} // {} }

# Override event handling: for play_and_collect, ignore play events
# (play(finished) must NOT resolve a play_and_collect; only the collect
# terminal event should — see RELAY_IMPLEMENTATION_GUIDE). Resolves on a
# calling.call.collect event that carries a result, or a state in the
# terminal-state map.
sub _handle_event ( $self, $event ) {

    # Defense-in-depth: even if a caller hands us a play event (e.g. the
    # legacy unit test that drives the action directly), we drop it so
    # state doesn't update.
    if ( ( $event->event_type // '' ) eq 'calling.call.play' ) {
        return;
    }
    $self->SUPER::_handle_event($event);
    return if $self->completed;
    if ( $event->event_type eq 'calling.call.collect' ) {
        my $params = $event->params // {};
        my $result = ref $params eq 'HASH' ? $params->{result} : undef;
        if ( ref $result eq 'HASH' && %$result ) {
            $self->_resolve($event);
        }
    }
    return;
}

# Filter calling.call.play events: Call's dispatcher consults this method
# before handing the event to the action so play events neither dispatch
# nor (more importantly) trigger terminal-state auto-resolve.
sub _should_consume_event ( $self, $event ) {
    return 0 if ( $event->event_type // '' ) eq 'calling.call.play';
    return 1;
}

# --- StandaloneCollectAction ---
package SignalWire::Relay::Action::StandaloneCollect;
use Moo;
extends 'SignalWire::Relay::Action::Collect';

# Standalone collect uses calling.collect.stop, not the
# play_and_collect.stop variant.
sub _stop_method { return 'calling.collect.stop' }

# --- FaxAction ---
package SignalWire::Relay::Action::Fax;
use Moo;
extends 'SignalWire::Relay::Action';

# The stop-verb prefix (``send_fax`` / ``receive_fax``), set per instance at
# construction. This IS the reference's contract — ``FaxAction.__init__(call,
# control_id, method_prefix)`` (relay/call.py:275) — so it stays a constructor
# argument under the reference's name.
has 'method_prefix' => ( is => 'ro', default => sub { 'send_fax' } );

sub _stop_method ($self) {
    return 'calling.' . $self->method_prefix . '.stop';
}

sub fax_result { my ($self) = @_; return $self->payload->{fax} // {} }

# --- TapAction ---
package SignalWire::Relay::Action::Tap;
use Moo;
extends 'SignalWire::Relay::Action';

sub _stop_method { return 'calling.tap.stop' }

# --- StreamAction ---
package SignalWire::Relay::Action::Stream;
use Moo;
extends 'SignalWire::Relay::Action';

sub _stop_method { return 'calling.stream.stop' }

# --- PayAction ---
package SignalWire::Relay::Action::Pay;
use Moo;
extends 'SignalWire::Relay::Action';

sub _stop_method { return 'calling.pay.stop' }

sub pay_result { my ($self) = @_; return $self->payload->{result} // {} }

# --- TranscribeAction ---
package SignalWire::Relay::Action::Transcribe;
use Moo;
extends 'SignalWire::Relay::Action';

sub _stop_method { return 'calling.transcribe.stop' }

# --- AIAction ---
package SignalWire::Relay::Action::AI;
use Moo;
extends 'SignalWire::Relay::Action';

sub _stop_method { return 'calling.ai.stop' }

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Relay::Action - handles for long-running RELAY call operations

=head1 SYNOPSIS

    # Actions are returned by SignalWire::Relay::Call methods, not
    # constructed directly:
    my $action = $call->play_audio( $url );          # ::Action::Play

    $action->on_completed(sub ($a) { print "done: ", $a->state, "\n"; });
    my $result = $action->wait( timeout => 30 );      # block until done
    $action->stop unless $action->is_done;

=head1 DESCRIPTION

L<SignalWire::Relay::Action> is the base class for every long-running
RELAY operation (play, record, detect, collect, fax, tap, stream, pay,
transcribe, AI). It tracks the C<control_id> correlation key, accumulates
events, exposes the latest C<payload>, and resolves when the operation
reaches a terminal state — mirroring the Python reference's action
objects.

Construction fails fast: C<control_id> must be a non-empty string,
C<events> must be an arrayref, and C<payload> must be a hashref (Moo
C<isa> constraints). These objects are normally created by
L<SignalWire::Relay::Call>, not by user code.

=head2 Base methods

=over 4

=item C<on_completed($cb)>

Register a completion callback, invoked as C<< $cb->($action) >>, and
return C<$self>. If the action has B<already> resolved the callback fires
immediately rather than never. A callback that dies is warned about, not
fatal. Called with no argument it is a getter and returns the currently
registered callback.

=item C<is_done()>

True once the action has resolved.

=item C<wait(timeout =E<gt> $secs)>

Block until the action resolves or C<timeout> (default 30s) elapses, then
return the action's result — which is C<undef> on timeout, and also
C<undef> for an action resolved without one. This B<pumps the client's read
loop> while waiting: completion only flips as frames are dispatched, so a
bare sleep would hang the full timeout and return nothing. With no client
attached (a detached or unit-constructed action) it falls back to sleeping
so it never hot-spins.

=item C<stop()>

Send the subclass's stop verb, or do nothing if the action has already
completed. Returns C<undef> when no client is attached.

=back

=head2 Subclasses

Each subclass overrides the stop verb, and several add control methods and
result accessors. Every result accessor reads the B<latest event payload>,
so it is only meaningful once the action has resolved; each returns an
empty default rather than C<undef> when its key is absent.

=over 4

=item B<::Play> — stop verb C<calling.play.stop>

=over 4

=item C<pause($behavior)>

Pause playback. C<$behavior> is B<positional> here and is sent only when
defined.

=item C<resume()>

Resume playback.

=item C<volume($volume)>

Set playback volume.

=back

=item B<::Record> — stop verb C<calling.record.stop>

=over 4

=item C<pause(%opts)>

Pause recording. Note C<behavior> is a B<named> option here, unlike
C<::Play::pause>'s positional argument, and it is gated on truthiness
rather than definedness — so an empty-string behavior is dropped.

=item C<resume()>

Resume recording.

=item C<url()>, C<duration()>, C<size()>

The recording's URL, duration and size from the completion payload,
defaulting to C<''>, 0 and 0.

=back

=item B<::Detect> — stop verb C<calling.detect.stop>

=over 4

=item C<detect_result()>

The detection result hashref (empty hashref if absent). This action
resolves on the B<first> non-empty C<params.detect> payload rather than
waiting for a terminal state.

=back

=item B<::Collect> — stop verb C<calling.play_and_collect.stop>

Returned by C<play_and_collect>. Because that verb wraps an embedded play,
it exposes the play controls too — they act on the embedded play leg and
use the C<play_and_collect> method family, not C<play>.

=over 4

=item C<pause($behavior)>, C<resume()>, C<volume($volume)>

Control the embedded play leg
(C<calling.play_and_collect.pause>/C<.resume>/C<.volume>).

=item C<start_input_timers()>

Start the collect input timers (C<calling.collect.start_input_timers>).

=item C<collect_result()>

The collect result hashref (empty hashref if absent).

=back

This action deliberately B<filters out> C<calling.call.play> events, so a
finished prompt neither updates its state nor terminally resolves the
collect. B<::StandaloneCollect> inherits all of the above but overrides the
stop verb to C<calling.collect.stop>.

=item B<::Fax> — stop verb depends on C<method_prefix>

=over 4

=item C<method_prefix>

Constructor attribute, C<send_fax> or C<receive_fax>, which selects the
stop verb C<calling.E<lt>prefixE<gt>.stop>.

=item C<fax_result()>

The fax result hashref (empty hashref if absent).

=back

=item B<::Pay> — stop verb C<calling.pay.stop>

=over 4

=item C<pay_result()>

The payment result hashref (empty hashref if absent).

=back

=item B<::Tap>, B<::Stream>, B<::Transcribe>, B<::AI>

Stop-verb-only specialisations (C<calling.tap.stop>,
C<calling.stream.stop>, C<calling.transcribe.stop>, C<calling.ai.stop>).
They add no methods of their own.

=back

=head1 SEE ALSO

L<SignalWire::Relay::Call>, L<SignalWire::Relay::Client>,
L<SignalWire::Relay::Event>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
