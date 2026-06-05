package SignalWire::Relay::Action;
use strict;
use warnings;
use Moo;
# Subroutine signatures (Perl 5.20+; floor 5.026). Must follow `use Moo;`
# — Moo's import re-enables the default warning set, which would otherwise
# un-silence experimental::signatures.
use feature 'signatures';
no warnings 'experimental::signatures';
use Scalar::Util ();
use Carp ();

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
has 'call_id'    => ( is => 'ro', default => sub { '' } );
has 'node_id'    => ( is => 'ro', default => sub { '' } );
has 'state'      => ( is => 'rw', default => sub { 'created' } );
has 'completed'  => ( is => 'rw', default => sub { 0 } );  # boolean
has 'result'     => ( is => 'rw', default => sub { undef } );
has 'events'     => ( is => 'rw', default => sub { [] }, isa => $ArrayRef );
has 'payload'    => ( is => 'rw', default => sub { {} }, isa => $HashRef ); # latest event payload

has '_on_completed' => ( is => 'rw', default => sub { undef } );
has '_client'       => ( is => 'rw', default => sub { undef } );

# Register on_completed callback
sub on_completed ($self, $cb = undef) {
    if ($cb) {
        $self->_on_completed($cb);
        # If already done, fire immediately
        if ($self->completed) {
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

# Blocking wait using select() polling loop
sub wait ($self, %opts) {
    my $timeout = $opts{timeout} || 30;
    my $start = time();
    while (!$self->completed && (time() - $start) < $timeout) {
        select(undef, undef, undef, 0.1);  # sleep 100ms
    }
    return $self->result;
}

# Called by event dispatch when an event is received for this action
sub _handle_event ($self, $event) {
    push @{$self->events}, $event;
    $self->payload($event->params // {});

    my $state = $event->can('state') ? $event->state : '';
    $self->state($state) if $state;
}

# Mark the action as completed with a result
sub _resolve ($self, $result) {
    return if $self->completed;
    $self->completed(1);
    $self->result($result);

    if (my $cb = $self->_on_completed) {
        eval { $cb->($self) };
        warn "on_completed callback error: $@" if $@;
    }
}

# Send a sub-command on this action (e.g., play.stop, record.pause)
sub _execute_subcommand ($self, $method) {
    my $client = $self->_client;
    return unless $client;
    return $client->execute($method, {
        node_id    => $self->node_id,
        call_id    => $self->call_id,
        control_id => $self->control_id,
    });
}

# Stop the action
sub stop ($self) {
    return if $self->completed;
    return $self->_execute_subcommand($self->_stop_method);
}

# Override in subclasses
sub _stop_method { return '' }

# --- PlayAction ---
package SignalWire::Relay::Action::Play;
use Moo;
no warnings 'experimental::signatures';  # re-silence: use Moo re-enabled it
extends 'SignalWire::Relay::Action';

sub _stop_method { 'calling.play.stop' }

sub pause ($self) {
    return $self->_execute_subcommand('calling.play.pause');
}

sub resume ($self) {
    return $self->_execute_subcommand('calling.play.resume');
}

sub volume ($self, $vol) {
    my $client = $self->_client;
    return unless $client;
    return $client->execute('calling.play.volume', {
        node_id    => $self->node_id,
        call_id    => $self->call_id,
        control_id => $self->control_id,
        volume     => $vol,
    });
}

# --- RecordAction ---
package SignalWire::Relay::Action::Record;
use Moo;
no warnings 'experimental::signatures';  # re-silence: use Moo re-enabled it
extends 'SignalWire::Relay::Action';

sub _stop_method { 'calling.record.stop' }

sub pause ($self, %opts) {
    my $client = $self->_client;
    return unless $client;
    my $params = {
        node_id    => $self->node_id,
        call_id    => $self->call_id,
        control_id => $self->control_id,
    };
    $params->{behavior} = $opts{behavior} if $opts{behavior};
    return $client->execute('calling.record.pause', $params);
}

sub resume ($self) {
    return $self->_execute_subcommand('calling.record.resume');
}

# Result accessors
sub url      { $_[0]->payload->{url}      // '' }
sub duration { $_[0]->payload->{duration}  // 0 }
sub size     { $_[0]->payload->{size}      // 0 }

# --- DetectAction ---
package SignalWire::Relay::Action::Detect;
use Moo;
no warnings 'experimental::signatures';  # re-silence: use Moo re-enabled it
extends 'SignalWire::Relay::Action';

sub _stop_method { 'calling.detect.stop' }

sub detect_result { $_[0]->payload->{detect} // {} }

# Detect resolves on the FIRST `params.detect` payload (the actual
# detection result), not on a state(finished). Mirror Python's
# ``DetectAction._check_event``.
sub _handle_event ($self, $event) {
    $self->SUPER::_handle_event($event);
    return if $self->completed;
    my $params = $event->params // {};
    if (ref $params eq 'HASH'
        && ref $params->{detect} eq 'HASH'
        && %{$params->{detect}})
    {
        $self->_resolve($event);
    }
}

# --- CollectAction (used by play_and_collect) ---
package SignalWire::Relay::Action::Collect;
use Moo;
no warnings 'experimental::signatures';  # re-silence: use Moo re-enabled it
extends 'SignalWire::Relay::Action';

# play_and_collect's stop verb is calling.play_and_collect.stop, not
# calling.collect.stop. The standalone collect uses StandaloneCollect
# below.
sub _stop_method { 'calling.play_and_collect.stop' }

sub start_input_timers ($self) {
    return $self->_execute_subcommand('calling.collect.start_input_timers');
}

sub collect_result { $_[0]->payload->{result} // {} }

# Override event handling: for play_and_collect, ignore play events
# (play(finished) must NOT resolve a play_and_collect; only the collect
# terminal event should — see RELAY_IMPLEMENTATION_GUIDE). Resolves on a
# calling.call.collect event that carries a result, or a state in the
# terminal-state map.
sub _handle_event ($self, $event) {
    # Defense-in-depth: even if a caller hands us a play event (e.g. the
    # legacy unit test that drives the action directly), we drop it so
    # state doesn't update.
    if (($event->event_type // '') eq 'calling.call.play') {
        return;
    }
    $self->SUPER::_handle_event($event);
    return if $self->completed;
    if ($event->event_type eq 'calling.call.collect') {
        my $params = $event->params // {};
        my $result = ref $params eq 'HASH' ? $params->{result} : undef;
        if (ref $result eq 'HASH' && %$result) {
            $self->_resolve($event);
        }
    }
}

# Filter calling.call.play events: Call's dispatcher consults this method
# before handing the event to the action so play events neither dispatch
# nor (more importantly) trigger terminal-state auto-resolve.
sub _should_consume_event ($self, $event) {
    return 0 if ($event->event_type // '') eq 'calling.call.play';
    return 1;
}

# --- StandaloneCollectAction ---
package SignalWire::Relay::Action::StandaloneCollect;
use Moo;
extends 'SignalWire::Relay::Action::Collect';

# Standalone collect uses calling.collect.stop, not the
# play_and_collect.stop variant.
sub _stop_method { 'calling.collect.stop' }

# --- FaxAction ---
package SignalWire::Relay::Action::Fax;
use Moo;
no warnings 'experimental::signatures';  # re-silence: use Moo re-enabled it
extends 'SignalWire::Relay::Action';

has '_fax_type' => ( is => 'ro', default => sub { 'send' } );

sub _stop_method ($self) {
    return $self->_fax_type eq 'receive'
        ? 'calling.receive_fax.stop'
        : 'calling.send_fax.stop';
}

sub fax_result { $_[0]->payload->{fax} // {} }

# --- TapAction ---
package SignalWire::Relay::Action::Tap;
use Moo;
extends 'SignalWire::Relay::Action';

sub _stop_method { 'calling.tap.stop' }

# --- StreamAction ---
package SignalWire::Relay::Action::Stream;
use Moo;
extends 'SignalWire::Relay::Action';

sub _stop_method { 'calling.stream.stop' }

# --- PayAction ---
package SignalWire::Relay::Action::Pay;
use Moo;
extends 'SignalWire::Relay::Action';

sub _stop_method { 'calling.pay.stop' }

sub pay_result { $_[0]->payload->{result} // {} }

# --- TranscribeAction ---
package SignalWire::Relay::Action::Transcribe;
use Moo;
extends 'SignalWire::Relay::Action';

sub _stop_method { 'calling.transcribe.stop' }

# --- AIAction ---
package SignalWire::Relay::Action::AI;
use Moo;
extends 'SignalWire::Relay::Action';

sub _stop_method { 'calling.ai.stop' }

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Relay::Action - handles for long-running RELAY call operations

=head1 SYNOPSIS

    # Actions are returned by SignalWire::Relay::Call methods, not
    # constructed directly:
    my $action = $call->play_async( url => $url );   # ::Action::Play

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

=item * C<on_completed($cb)> — register a completion callback (fires
immediately if already done); no-arg form returns the registered
callback.

=item * C<is_done> — true once resolved.

=item * C<wait(timeout =E<gt> $secs)> — block (polling) until resolved or
the timeout elapses (default 30s), then return the result.

=item * C<stop> — send the subclass's stop verb unless already done.

=back

=head2 Subclasses

Each subclass overrides the stop verb and adds result accessors:

=over 4

=item * B<::Play> — C<pause>, C<resume>, C<volume($vol)>.

=item * B<::Record> — C<pause(behavior =E<gt> ...)>, C<resume>, and the
C<url> / C<duration> / C<size> result accessors.

=item * B<::Detect> — C<detect_result>; resolves on the first
C<params.detect> payload.

=item * B<::Collect> / B<::StandaloneCollect> — C<start_input_timers>,
C<collect_result>; filters stray C<calling.call.play> events.

=item * B<::Fax> — C<fax_result>; stop verb depends on C<_fax_type>.

=item * B<::Tap>, B<::Stream>, B<::Transcribe>, B<::AI> — stop-verb-only
specialisations.

=item * B<::Pay> — C<pay_result>.

=back

=head1 SEE ALSO

L<SignalWire::Relay::Call>, L<SignalWire::Relay::Client>,
L<SignalWire::Relay::Event>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
