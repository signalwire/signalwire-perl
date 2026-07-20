#!/usr/bin/env perl
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# wait-liveness-dump.pl — the Perl port's WAIT-LIVENESS dump program for the
# cross-port liveness differ (porting-sdk/scripts/diff_port_wait_liveness.py).
#
# For each wait_liveness_corpus case it drives a real Action-returning Call verb
# (play / record), arms a DEFERRED completing event to be delivered delay_ms after
# wait() begins (through the SAME dispatch path the real socket read drives —
# Call::dispatch_event, pumped by the client's _read_once inside Action::wait), then
# measures t_wait_start / t_return and derives the deterministic LIVENESS
# CLASSIFICATION:
#
#   { blocked_until_event, returned_after_event, completed_state, timed_out }
#
# A wait() that is a NO-OP returns at t~=0  -> blocked_until_event=false -> RED.
# A wait() that HANGS blows the deadline    -> timed_out=true            -> RED.
# A correct wait() blocks until the event then returns -> the golden -> GREEN.
#
# The classification (not raw ms) is the comparable artifact, so the golden is
# deterministic while the timing that produces it is real and unfakeable. It prints
# ONE JSON object mapping case-id -> classification to stdout; only stdout carries
# JSON. Mirrors diff_port_wait_liveness.py's _run_liveness for python.
#
# Run from the signalwire-perl repo root:
#
#     perl -Ilib bin/wait-liveness-dump.pl

use strict;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use FindBin qw($RealBin);
use File::Spec;
use Time::HiRes ();
use JSON ();

use lib File::Spec->catdir( $RealBin, File::Spec->updir, 'lib' );

use SignalWire::Relay::Call;
use SignalWire::Relay::Event;

my $NODE = 'node-abc';
my $CALL = 'call-xyz';

# Liveness deadline + tolerance — MUST match diff_port_wait_liveness.py
# (DEADLINE_S / BLOCK_TOL_MS) so the port's classification lines up with the
# oracle's. A wait() outliving DEADLINE_S is HUNG; BLOCK_TOL_MS is how much earlier
# than delay_ms a return may be and still count as "blocked" (scheduler jitter).
use constant DEADLINE_S   => 5.0;
use constant BLOCK_TOL_MS => 40;

# The deferred-event delay (matches wait_liveness_corpus.DELAY_MS).
use constant DELAY_MS => 150;

# ----------------------------------------------------------------------------
# LivenessClient — a minimal client the Action's wait() pumps via _read_once.
# execute() succeeds (so _start_action proceeds). _read_once is the deferred-event
# source: once wall-clock reaches the armed emit-time, it delivers the terminal
# event ONCE through Call::dispatch_event (the exact code path a real socket read
# drives), then advances a hair. Before that time it just yields the CPU briefly
# (like the real client's select() timeout) so wait() genuinely BLOCKS — a no-op
# wait that never pumps this loop returns before the event and is caught as RED.
# ----------------------------------------------------------------------------
{
    package LivenessClient;
    use Moo;

    has '_call'       => ( is => 'rw', default => sub { undef } );
    has '_emit_at'    => ( is => 'rw', default => sub { undef } );
    has '_terminal'   => ( is => 'rw', default => sub { {} } );
    has '_control_id' => ( is => 'rw', default => sub { undef } );
    has '_emitted'    => ( is => 'rw', default => sub { 0 } );

    sub execute ( $self, $method, $params ) {
        return { code => '200' };
    }

    sub arm ( $self, $call, $emit_at, $terminal, $control_id ) {
        $self->_call($call);
        $self->_emit_at($emit_at);
        $self->_terminal($terminal);
        $self->_control_id($control_id);
        $self->_emitted(0);
        return;
    }

    sub _read_once ($self) {
        if ( !$self->_emitted && defined $self->_emit_at
            && Time::HiRes::time() >= $self->_emit_at )
        {
            $self->_emitted(1);
            my $t = $self->_terminal;
            my $event = SignalWire::Relay::Event->parse_event(
                $t->{event_type},
                {
                    call_id    => $CALL,
                    control_id => $self->_control_id,
                    state      => $t->{state},
                },
            );
            $self->_call->dispatch_event($event);
            return;
        }
        # Not yet time — behave like the real client's select() timeout so the
        # wait loop blocks rather than hot-spins.
        Time::HiRes::sleep(0.005);
        return;
    }
}

# The corpus (mirrors wait_liveness_corpus.CORPUS): id, verb, verb args, terminal.
# NOTE: play() takes `play => [...]`, record() takes `record => {...}` — the Perl
# idiom for the Python `media` / `audio` kwargs; the wire-shape parity is proven by
# WIRE-RELAY, not here. Here we only need a real Action-returning verb to wait on.
my @CORPUS = (
    {
        id       => 'live_play_wait',
        verb     => 'play',
        args     => [ play => [ { type => 'audio', params => { url => 'https://x/a.mp3' } } ] ],
        terminal => { event_type => 'calling.call.play', state => 'finished' },
    },
    {
        id       => 'live_record_wait',
        verb     => 'record',
        args     => [ record => { format => 'mp3' } ],
        terminal => { event_type => 'calling.call.record', state => 'finished' },
    },
    # NESTED wait: wait() called from inside an on_completed callback (re-entrant
    # _read_once). The first action's completion callback starts a SECOND action ON
    # THE SAME CLIENT and waits on it — so the inner wait() re-enters the SAME
    # client's _read_once WHILE the outer wait()'s _read_once → dispatch_event →
    # callback frame is still on the Perl stack. This is the REAL same-client
    # re-entrancy: a wait() with shared/guarded loop state or a single-shot pump on
    # the one client object deadlocks or early-returns here (a synthetic second
    # client would NOT exercise that path). Proves the P0 wait fix holds under the
    # documented nested-wait pattern (wait inside on_call).
    {
        id       => 'live_nested_wait',
        verb     => 'play',
        args     => [ play => [ { type => 'audio', params => { url => 'https://x/a.mp3' } } ] ],
        terminal => { event_type => 'calling.call.play', state => 'finished' },
        nested   => {
            verb     => 'record',
            args     => [ record => { format => 'mp3' } ],
            terminal => { event_type => 'calling.call.record', state => 'finished' },
        },
    },
);

# classify_liveness — MUST match diff_port_wait_liveness.classify_liveness.
sub classify_liveness ( $delay_ms, $t_wait_start, $t_return, $completed_state, $timed_out ) {
    if ( $timed_out || !defined $t_return ) {
        return {
            blocked_until_event  => JSON::false,
            returned_after_event => JSON::false,
            completed_state      => '',
            timed_out            => JSON::true,
        };
    }
    my $elapsed_ms = ( $t_return - $t_wait_start ) * 1000.0;
    my $blocked = $elapsed_ms >= ( $delay_ms - BLOCK_TOL_MS );
    return {
        blocked_until_event  => $blocked ? JSON::true : JSON::false,
        returned_after_event => JSON::true,
        completed_state      => $completed_state,
        timed_out            => JSON::false,
    };
}

# Build a fresh Call whose client is a LivenessClient. state='answered' so
# _start_action proceeds (not ENDED). An existing $client may be passed to build
# a SECOND call that SHARES that client -- the nested case uses this so the inner
# action's wait() pumps the SAME client's _read_once re-entrantly (see below).
sub _make_call {
    my ($client) = @_;
    $client //= LivenessClient->new;
    my $call = SignalWire::Relay::Call->new(
        call_id => $CALL,
        node_id => $NODE,
        context => 'ctx',
        state   => 'answered',
        _client => $client,
    );
    return ( $call, $client );
}

# _drive_one — start a verb, arm the deferred completing event delay_ms after wait()
# begins, wait, and return (t_wait_start, t_return|undef, completed_state, timed_out).
# The optional on_started callback runs right after the action starts (used to arm the
# NESTED inner wait from inside the outer action's on_completed).
sub _drive_one ( $call, $client, $case, $on_completed = undef ) {
    my $verb   = $case->{verb};
    my $action = $call->$verb( @{ $case->{args} } );

    $action->on_completed($on_completed) if $on_completed;

    my $emit_at = Time::HiRes::time() + ( DELAY_MS / 1000.0 );
    $client->arm( $call, $emit_at, $case->{terminal}, $action->control_id );

    my $t_wait_start = Time::HiRes::time();
    my $result       = $action->wait( timeout => DEADLINE_S );
    my $t_return     = Time::HiRes::time();

    my $timed_out = $action->completed ? 0 : 1;
    my $completed_state = '';
    if ( !$timed_out && defined $result && ref $result && $result->can('state') ) {
        $completed_state = $result->state // '';
    }
    return ( $t_wait_start, ( $timed_out ? undef : $t_return ), $completed_state, $timed_out );
}

my %out;
for my $case (@CORPUS) {
    if ( $case->{nested} ) {
        # Outer play; when it completes, its on_completed starts+waits a record.
        my ( $call, $client ) = _make_call();
        my $inner = $case->{nested};
        my ( $iws, $irt, $istate, $ito );
        my $on_completed = sub ($outer_action) {
            # Re-entrant on the SAME client: a second call SHARING the outer's
            # client drives the inner action, whose wait() re-enters that one
            # client's _read_once — all from WITHIN the outer wait()'s
            # _read_once → dispatch → callback frame. Re-arming the shared client
            # (the outer already emitted, so _emitted is reset) points its
            # deferred-event slot at the inner call. This is the genuine
            # same-client _read_once re-entrancy, not a synthetic second client.
            my ( $icall, $iclient ) = _make_call($client);
            ( $iws, $irt, $istate, $ito ) = _drive_one( $icall, $iclient, $inner );
        };
        my ( $ows, $ort, $ostate, $oto ) =
            _drive_one( $call, $client, $case, $on_completed );
        # The nested case passes iff BOTH waits blocked-until-event and returned.
        # Fold the two into one classification: timed_out if EITHER hung; blocked
        # only if BOTH blocked; state from the inner (last) completion.
        my $outer = classify_liveness( DELAY_MS, $ows, $ort, $ostate, $oto );
        my $inner_c =
            defined $iws
            ? classify_liveness( DELAY_MS, $iws, $irt, $istate, $ito )
            : { blocked_until_event => JSON::false, returned_after_event => JSON::false,
                completed_state => '', timed_out => JSON::true };
        my $timed_out = ( $outer->{timed_out} == JSON::true || $inner_c->{timed_out} == JSON::true );
        if ($timed_out) {
            $out{ $case->{id} } = {
                blocked_until_event  => JSON::false,
                returned_after_event => JSON::false,
                completed_state      => '',
                timed_out            => JSON::true,
            };
        } else {
            my $both_blocked =
                ( $outer->{blocked_until_event} == JSON::true
                  && $inner_c->{blocked_until_event} == JSON::true );
            $out{ $case->{id} } = {
                blocked_until_event  => $both_blocked ? JSON::true : JSON::false,
                returned_after_event => JSON::true,
                completed_state      => $inner_c->{completed_state},
                timed_out            => JSON::false,
            };
        }
        next;
    }

    my ( $call, $client ) = _make_call();
    my ( $ws, $rt, $state, $to ) = _drive_one( $call, $client, $case );
    $out{ $case->{id} } = classify_liveness( DELAY_MS, $ws, $rt, $state, $to );
}

print JSON->new->canonical->encode( \%out ), "\n";
