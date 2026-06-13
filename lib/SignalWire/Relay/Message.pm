package SignalWire::Relay::Message;
use strict;
use warnings;
use Moo;
# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
use Scalar::Util ();
use Carp ();

use SignalWire::Relay::Constants qw(MESSAGE_TERMINAL_STATES);
use SignalWire::Relay::MessageState ();

# --- isa constraint helpers (coderefs; no extra deps). Each dies on a
# bad value so construction / accessor-writes fail fast. Moo skips isa on
# default values, so these only police caller-supplied input. ---
my $NonEmptyStr = sub {
    Carp::croak("must be a non-empty string")
        unless defined $_[0] && !ref $_[0] && length $_[0];
};
my $Num = sub {
    Carp::croak("must be a number")
        unless defined $_[0] && !ref $_[0] && Scalar::Util::looks_like_number($_[0]);
};
my $ArrayRef = sub {
    Carp::croak("must be an arrayref") unless ref $_[0] eq 'ARRAY';
};
my $CodeRef = sub {
    Carp::croak("must be a coderef") unless ref $_[0] eq 'CODE';
};

has 'message_id'  => ( is => 'ro', required => 1, isa => $NonEmptyStr );
has 'context'     => ( is => 'rw', default => sub { '' } );
has 'direction'   => ( is => 'rw', default => sub { '' } );
has 'from_number' => ( is => 'rw', default => sub { '' } );
has 'to_number'   => ( is => 'rw', default => sub { '' } );
has 'body'        => ( is => 'rw', default => sub { '' } );
has 'media'       => ( is => 'rw', default => sub { [] }, isa => $ArrayRef );
has 'segments'    => ( is => 'rw', default => sub { 0 }, isa => $Num );
has 'state'       => ( is => 'rw', default => sub { '' } );
has 'reason'      => ( is => 'rw', default => sub { '' } );
has 'tags'        => ( is => 'rw', default => sub { [] }, isa => $ArrayRef );

has 'completed' => ( is => 'rw', default => sub { 0 } );
has 'result'    => ( is => 'rw', default => sub { undef } );

has '_on_completed' => ( is => 'rw', default => sub { undef } );
has '_on_event'     => ( is => 'rw', default => sub { [] }, isa => $ArrayRef );

# Check if message has reached a terminal state
sub is_done ($self) {
    return $self->completed;
}

# --- Typed state accessors (parity alongside the string `state`) ---
#
# `state` stays the canonical bare-string accessor (Python parity). These
# add the SignalWire::Relay::MessageState-backed view. Perl has no enum
# object, so current_state returns the same wire string `state` does — it
# is the typed COMPANION to the MessageState predicates.

# current_state — the message's delivery state as the MessageState-typed
# view. Same wire string as ->state (the constants ARE the wire strings);
# paired with MessageState->is_state / ->is_terminal.
sub current_state ($self) {
    return $self->state;
}

# is_terminal — true when the message's current state is a terminal
# delivery state (MessageState terminal set = { delivered, undelivered,
# failed }). Delegates to MessageState so the terminal definition lives in
# one place; returns false (never dies) on an unknown/forward-compat state.
#
# Distinct from is_done: is_done reports the resolved/`completed` flag set
# by dispatch_event, whereas is_terminal classifies the current `state`
# string itself via the MessageState vocabulary.
sub is_terminal ($self) {
    return SignalWire::Relay::MessageState->is_terminal($self->state);
}

# Register on_completed callback
sub on_completed ($self, $cb = undef) {
    if ($cb) {
        $CodeRef->($cb);
        $self->_on_completed($cb);
        if ($self->completed) {
            eval { $cb->($self) };
            warn "Message on_completed callback error: $@" if $@;
        }
        return $self;
    }
    return $self->_on_completed;
}

# Register event listener
sub on ($self, $cb) {
    $CodeRef->($cb);
    push @{$self->_on_event}, $cb;
    return $self;
}

# Blocking wait
sub wait ($self, %opts) {
    my $timeout = $opts{timeout} || 30;
    my $start = time();
    while (!$self->completed && (time() - $start) < $timeout) {
        select(undef, undef, undef, 0.1);
    }
    return $self->result;
}

# Handle a messaging.state event
sub dispatch_event ($self, $event) {

    my $message_state = $event->can('message_state') ? $event->message_state : '';
    $self->state($message_state) if $message_state;

    # Update fields from event
    $self->reason($event->reason) if $event->can('reason') && $event->reason;

    # Fire event callbacks
    for my $cb (@{$self->_on_event}) {
        eval { $cb->($self, $event) };
        warn "Message event callback error: $@" if $@;
    }

    # Check for terminal state
    if (MESSAGE_TERMINAL_STATES->{$message_state}) {
        $self->completed(1);
        $self->result($event);
        if (my $cb = $self->_on_completed) {
            eval { $cb->($self) };
            warn "Message on_completed callback error: $@" if $@;
        }
    }
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Relay::Message - a RELAY outbound/inbound SMS message handle

=head1 SYNOPSIS

    use SignalWire::Relay::Message;

    my $msg = SignalWire::Relay::Message->new( message_id => $id );

    $msg->on_completed(sub ($m) { print "final state: ", $m->state, "\n"; });
    $msg->on(sub ($m, $event) { ... });   # per-event listener

    my $final = $msg->wait( timeout => 30 );  # blocks until terminal

=head1 DESCRIPTION

L<SignalWire::Relay::Message> tracks the lifecycle of a single RELAY
message. It mirrors the Python reference's message handle: a message is
created with a C<message_id>, accumulates state from C<messaging.state>
events via L</dispatch_event>, and resolves when it reaches a terminal
state (see L<SignalWire::Relay::Constants/MESSAGE_TERMINAL_STATES>).

Construction fails fast on bad input: C<message_id> must be a non-empty
string, C<media> / C<tags> must be arrayrefs, and C<segments> must be a
number (Moo C<isa> constraints).

=head1 METHODS

=head2 is_done

    my $bool = $msg->is_done;

True once the message has reached a terminal state (the resolved
C<completed> flag set by L</dispatch_event>).

=head2 current_state

    my $state = $msg->current_state;

The message's delivery state as the L<SignalWire::Relay::MessageState>-typed
view. Returns the same wire string as C<state> (the MessageState constants
B<are> the wire strings); pair it with
C<< SignalWire::Relay::MessageState->is_state >> / C<< ->is_terminal >>.

=head2 is_terminal

    my $bool = $msg->is_terminal;

True when the message's current C<state> string is a terminal delivery
state (C<delivered>, C<undelivered>, or C<failed>). Delegates to
L<SignalWire::Relay::MessageState>; returns false (never dies) on an
unknown/forward-compatible state. Distinct from L</is_done>, which reports
the resolved C<completed> flag rather than classifying the C<state> string.

=head2 on_completed

    $msg->on_completed($cb);   # register; returns $self
    my $cb = $msg->on_completed;  # no-arg: get the registered callback

Register a callback invoked once with C<$msg> when the message completes.
If the message is already complete, the callback fires immediately. The
callback must be a coderef.

=head2 on

    $msg->on($cb);   # returns $self

Register a per-event listener invoked as C<< $cb->($msg, $event) >> for
every dispatched event. The callback must be a coderef.

=head2 wait

    my $result = $msg->wait( timeout => 30 );

Block (polling) until the message completes or C<timeout> seconds elapse
(default 30), then return the terminal event.

=head2 dispatch_event

    $msg->dispatch_event($event);

Apply a C<messaging.state> event: update C<state>/C<reason>, fire event
listeners, and resolve the message if the new state is terminal. Normally
called by L<SignalWire::Relay::Client>, not user code.

=head1 SEE ALSO

L<SignalWire::Relay::Client>, L<SignalWire::Relay::Event>,
L<SignalWire::Relay::Constants>, L<SignalWire::Relay::MessageState>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
