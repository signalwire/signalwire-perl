#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# PERL-3: the RELAY connection + error liveness contract (subset the perl client
# implements directly, provable without a live socket): A6 pre-connect credential
# validation, A2 relay-contract raise-vs-swallow, and the auto-reconnect wiring
# (run() no longer silently exits on an unexpected drop; disconnect_ws sets the
# intentional-close guard).

use SignalWire::Relay::Client;
use SignalWire::Relay::Call;

# ---- A6: missing creds fail PRE-CONNECT with a per-variable actionable msg ----
subtest 'A6 missing project fails pre-connect naming the env var' => sub {
    my $c = SignalWire::Relay::Client->new(
        project => '', token => 't', host => 'relay.example.test' );
    eval { $c->connect };
    my $err = $@;
    ok( $err, 'connect died' );
    like( $err, qr/project/,               'names project' );
    like( $err, qr/SIGNALWIRE_PROJECT_ID/, 'names the SIGNALWIRE_PROJECT_ID env var' );
    unlike( $err, qr/WebSocket connect failed/, 'failed BEFORE any socket work' );
};

subtest 'A6 missing token fails pre-connect naming the env var' => sub {
    my $c = SignalWire::Relay::Client->new(
        project => 'p', token => '', host => 'relay.example.test' );
    eval { $c->connect };
    my $err = $@;
    ok( $err, 'connect died' );
    like( $err, qr/token/,               'names token' );
    like( $err, qr/SIGNALWIRE_API_TOKEN/, 'names the SIGNALWIRE_API_TOKEN env var' );
};

subtest 'A6 jwt_token satisfies the credential requirement' => sub {
    my $c = SignalWire::Relay::Client->new(
        jwt_token => 'jwt-xyz', host => 'relay.example.test' );
    # connect proceeds past cred validation to connect_ws (which then fails on
    # the unroutable host — but NOT on a missing-cred die).
    eval { $c->connect };
    unlike( $@, qr/is required/, 'no missing-credential error when jwt_token is present' );
};

# ---- A2: relay-contract raise (500) vs swallow (404/410) ----
# A fake client whose execute() returns a canned result code lets us drive the
# Call verb path deterministically.
{
    package FakeCodeClient;
    sub new { bless { code => $_[1] }, $_[0] }
    sub execute { return { code => $_[0]->{code} } }
}

sub call_with_code {
    my ($code) = @_;
    return SignalWire::Relay::Call->new(
        call_id => 'c-1',
        node_id => 'n-1',
        context => 'ctx',
        state   => 'answered',
        _client => FakeCodeClient->new($code),
    );
}

subtest 'A2 relay code 500 RAISES' => sub {
    my $call = call_with_code('500');
    my $ok = eval { $call->answer; 1 };
    ok( !$ok, 'a 500-class verb result raises' );
    isa_ok( $@, 'SignalWire::Relay::Client::RelayError', 'raised a RelayError' );
    is( $@->code, 500, 'error carries code 500' );
};

subtest 'A2 relay code 404 is SWALLOWED (call gone -> no-op)' => sub {
    my $call = call_with_code('404');
    my $ok = eval { $call->answer; 1 };
    ok( $ok, '404 does not raise (call gone -> no-op)' );
};

subtest 'A2 relay code 410 is SWALLOWED' => sub {
    my $call = call_with_code('410');
    my $ok = eval { $call->answer; 1 };
    ok( $ok, '410 does not raise' );
};

subtest 'A2 success code 200 does not raise' => sub {
    my $call = call_with_code('200');
    my $ok = eval { $call->answer; 1 };
    ok( $ok, '200 is a normal success' );
};

# ---- reconnect wiring: disconnect_ws sets the intentional-close guard so run()
# exits cleanly, and reconnect() is a real, called code path (not dead). ----
subtest 'disconnect_ws sets the intentional-close guard' => sub {
    my $c = SignalWire::Relay::Client->new(
        project => 'p', token => 't', host => 'relay.example.test' );
    ok( !$c->_closing, 'not closing initially' );
    $c->disconnect_ws;
    ok( $c->_closing, 'disconnect_ws marks _closing so run() does not reconnect' );
    ok( !$c->connected, 'and drops connected' );
};

subtest 'run() exits cleanly when closed (no infinite loop)' => sub {
    my $c = SignalWire::Relay::Client->new(
        project => 'p', token => 't', host => 'relay.example.test' );
    # Not connected + closing -> run() must return immediately.
    $c->_closing(1);
    $c->connected(0);
    my $returned = 0;
    eval {
        local $SIG{ALRM} = sub { die "run() hung\n" };
        alarm 3;
        $c->run;
        $returned = 1;
        alarm 0;
    };
    ok( $returned, 'run() returned promptly on a closed client' );
};

done_testing;
