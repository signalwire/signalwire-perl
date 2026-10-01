#!/usr/bin/env perl
# Real-server smoke — plan a-bar 6.5.
#
# The ONLY check that catches mock<->production drift the AUTHORITATIVE_SPEC_SOURCING
# program hasn't closed yet: it hits the REAL SignalWire platform, not the mock.
# Opt-in and creds-gated, so it is a clean no-op without secrets:
#   * SWSDK_LIVE_TESTS=1 must be set (the shared cross-port opt-in convention), AND
#   * SIGNALWIRE_PROJECT_ID / SIGNALWIRE_API_TOKEN / SIGNALWIRE_SPACE must be present.
# Absent either, the file skips cleanly (never fails) — so it is safe on any fork /
# secret-less run.
#
# Coverage (deliberately minimal — a liveness probe, not a parity suite):
#   1. auth + one REST list         (RestClient -> phone_numbers -> list)
#   2. one SWML render              (SWMLService -> render_swml, no network)
#   3. one RELAY connect            (Relay::Client -> connect_ws + authenticate)
use strict;
use warnings;
use Test::More;

BEGIN {
    plan skip_all => 'live smoke is opt-in: set SWSDK_LIVE_TESTS=1 to enable'
        unless $ENV{SWSDK_LIVE_TESTS};
}

my $project = $ENV{SIGNALWIRE_PROJECT_ID};
my $token   = $ENV{SIGNALWIRE_API_TOKEN};
my $space   = $ENV{SIGNALWIRE_SPACE};

plan skip_all => 'live smoke needs SIGNALWIRE_PROJECT_ID / SIGNALWIRE_API_TOKEN / SIGNALWIRE_SPACE'
    unless $project && $token && $space;

# 1. REST: auth + one list against the real API.
subtest 'REST list against the real platform' => sub {
    require SignalWire::REST::RestClient;
    my $client = SignalWire::REST::RestClient->new(
        project => $project,
        token   => $token,
        host    => $space,
    );
    my $res = eval { $client->phone_numbers->list };
    ok( !$@,          'phone_numbers->list did not die' ) or diag("REST error: $@");
    ok( defined $res, 'phone_numbers->list returned a defined response' );
};

# 2. SWML render (no network — proves the document renders end-to-end).
subtest 'SWML render' => sub {
    require SignalWire::SWML::Service;
    my $svc  = SignalWire::SWML::Service->new;
    my $swml = eval { $svc->render_swml };
    ok( !$@,           'render_swml did not die' ) or diag("SWML error: $@");
    ok( defined $swml, 'render_swml returned a document' );
};

# 3. RELAY connect against the real platform.
subtest 'RELAY connect' => sub {
    require SignalWire::Relay::Client;
    my $client = SignalWire::Relay::Client->new(
        project  => $project,
        token    => $token,
        host     => $space,
        contexts => ['default'],
    );
    my $ok = eval {
        $client->connect_ws;
        $client->authenticate;
        1;
    };
    ok( $ok, 'RELAY connect_ws + authenticate succeeded' ) or diag("RELAY error: $@");
    eval { $client->disconnect } if $client->can('disconnect');
};

done_testing;
