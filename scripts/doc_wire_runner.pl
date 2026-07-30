#!/usr/bin/env perl
# doc_wire_runner.pl — the DOC-WIRE fixture runner for signalwire-perl.
#
# The DOC-WIRE gate (porting-sdk scripts/doc_wire.py) spawns mock_signalwire in
# FLAG mode, exports MOCK_SIGNALWIRE_PORT, then runs THIS command; it then reads
# the mock journal and fails on any journaled wire_violations. Our only job is to
# DRIVE the documented REST calls against that mock so it journals what the
# documented fixtures actually put on the wire.
#
# We replay the wire-bearing REST calls the README / rest/README.md /
# rest/docs/*.md quickstarts teach — the exact named args the docs show — so a
# doc lie such as `area_code =>` (spec `areacode`) or a flat
# `{ type => 'tts', text => ... }` play item (spec nests `params => { text }`)
# surfaces as a journaled violation and fails the gate. The blocking
# agent/relay quickstarts are covered by EXAMPLES-RUN, not here.
#
# Client construction reuses t/lib/MockTest.pm, which probes the already-running
# MOCK_SIGNALWIRE_PORT mock and reuses it (it does NOT spawn a second mock when
# one is already healthy on that port), exactly as the generated REST wire tests do.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../t/lib";
use MockTest;

my $port = $ENV{MOCK_SIGNALWIRE_PORT};
if ( !$port ) {
    print STDERR "doc_wire_runner: MOCK_SIGNALWIRE_PORT not set\n";
    exit 2;
}

my $client  = MockTest::client();
my $call_id = 'call-doc-wire';

# --- README.md + rest/README.md quickstart (region: rest) --------------------
$client->fabric->ai_agents->create(
    name   => 'Support Bot',
    prompt => { text => 'You are helpful.' },
);
$client->calling->play( $call_id, play => [ { type => 'tts', params => { text => 'Hello!' } } ] );
$client->phone_numbers->search( areacode => '512' );
$client->datasphere->documents->search( query_string => 'billing policy' );

# --- rest/docs/namespaces.md phone-number search (areacode + number_type) ----
$client->phone_numbers->search( areacode => '512', number_type => 'local' );

# --- rest/docs/calling.md play (nested params => { text }, volume) -----------
$client->calling->play(
    $call_id,
    play   => [ { type => 'tts', params => { text => 'Hello!' } } ],
    volume => 5.0,
);

# --- rest/docs/namespaces.md datasphere search (tags + count) ---------------
$client->datasphere->documents->search(
    query_string => 'How do I reset my password?',
    tags         => ['support'],
    count        => 5,
);

print "doc_wire_runner: replayed documented REST fixtures against the mock\n";
exit 0;
