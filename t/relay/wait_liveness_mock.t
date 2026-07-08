#!/usr/bin/env perl
# WAIT-LIVENESS (GATE_ENFORCEMENT_PLAN §B1): the DOCUMENTED wait pattern must
# COMPLETE, not hang. Before the pump fix, Action::wait / Call::wait_for slept
# without driving the client's read loop, so the awaited event never arrived —
# the documented `answer; play; $action->wait` hung the full timeout and
# returned undef. This test drives the PUBLIC pattern verbatim (NO private
# _pump_until helper) with a short deadline and asserts it resolves quickly.

use strict;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';
use Test::More;
use FindBin ();
use lib "$FindBin::Bin/../lib";
use Time::HiRes qw(time);

use RelayMockTest;
use SignalWire::Relay::Client;

my $client = RelayMockTest::client( contexts => ['default'] );
$client->connect;

my $captured;
$client->on_call(
    sub {
        my ($call) = @_;
        $captured = $call;
    }
);

# Step 1 — deliver ONLY the created state so on_call fires and we get the call
# object. The 'answered' transition is sent SEPARATELY (step 2) so it can't be
# consumed before wait_for's listener is registered.
RelayMockTest::inbound_call(
    call_id     => 'wl-call-1',
    auto_states => ['created'],
);

my $deadline = time() + 2;
while ( !defined $captured && time() < $deadline ) {
    $client->_read_once;
}
ok( defined $captured, 'on_call delivered the call object' )
    or BAIL_OUT('no inbound call — mock harness problem, not the wait fix');

# Step 2 — push the 'answered' state event AFTER we hold the call, then call
# the DOCUMENTED public wait_for. With the pump fix it must resolve via its own
# internal _read_once; without the fix (bare sleep) it hangs to the timeout and
# returns undef.
RelayMockTest::push_frame(
    {   jsonrpc => '2.0',
        id      => 'evt-wl-answered',
        method  => 'signalwire.event',
        params  => {
            event_type => 'calling.call.state',
            params     => {
                call_id    => 'wl-call-1',
                call_state => 'answered',
            },
        },
    }
);

my $wf_start = time();
my $event    = $captured->wait_for(
    event_type => 'calling.call.state',
    predicate  => sub ($e) {
        my $s = $e->can('call_state') ? $e->call_state : '';
        return defined $s && $s eq 'answered';
    },
    timeout => 3,
);
my $elapsed = time() - $wf_start;

ok( defined $event, 'wait_for resolved the answered event (did not hang/undef)' );
cmp_ok( $elapsed, '<', 2.5,
    sprintf( 'wait_for completed in %.2fs, well under the 3s timeout', $elapsed ) );

$client->disconnect;
done_testing;
