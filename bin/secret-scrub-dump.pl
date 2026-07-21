#!/usr/bin/env perl
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# secret-scrub-dump.pl — the Perl port's SECRET-SCRUB behavioral dump program
# for the cross-port secret-scrub differ
# (porting-sdk/scripts/diff_port_secret_scrub.py, corpus secret_scrub_corpus.py).
#
# The contract (mirrors the python oracle's build_oracle): with
# SIGNALWIRE_LOG_LEVEL=debug, drive the RELAY client through the two frame-logging
# sites carrying the fixture sentinels —
#
#   * OUTBOUND signalwire.connect (authentication.project=PJ-TESTLEAK,
#     token=PT-TESTLEAK) through _send  -> the "SEND: ..." debug log.
#   * INBOUND signalwire.authorization.state event (authorization_state=
#     AENC-TESTLEAK) through _handle_message -> the "RECV: ..." debug log.
#
# — CAPTURE this process's own STDERR (the logger writes there) across those
# calls, and for each sentinel print {leaked: bool} = whether the sentinel string
# appears verbatim in the captured debug output. A correctly-scrubbing client
# masks all three -> every {leaked:false}. A client that dumps the raw frame at
# debug leaks the sentinel -> {leaked:true} -> reds.
#
# Only stdout carries JSON (the outer differ command runs this with 2>/dev/null,
# so any residual real stderr is discarded — the leak analysis is done in-process
# against the STDERR we capture here). Deterministic: no socket, no timing.
#
# Run from the signalwire-perl repo root:
#
#     SIGNALWIRE_LOG_LEVEL=debug perl -Ilib bin/secret-scrub-dump.pl

use strict;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use FindBin qw($RealBin);
use File::Spec;
use JSON ();

use lib File::Spec->catdir( $RealBin, File::Spec->updir, 'lib' );

# The logger reads SIGNALWIRE_LOG_LEVEL at logger-construction time, so force
# debug BEFORE the client module (and its package-scoped logger) loads.
$ENV{SIGNALWIRE_LOG_LEVEL} = 'debug';

use SignalWire::Relay::Client;
use SignalWire::Relay::Event;

# The fixture sentinels — byte-identical to secret_scrub_corpus.py.
my $PROJECT             = 'PJ-TESTLEAK';
my $TOKEN               = 'PT-TESTLEAK';
my $AUTHORIZATION_STATE = 'AENC-TESTLEAK';

# ---------------------------------------------------------------------------
# Capture THIS process's STDERR (where SignalWire::Logging writes) into a
# scalar across the two logging drives. We redirect the STDERR filehandle to an
# in-memory string so the logger's real ->debug output is what we analyze.
# ---------------------------------------------------------------------------
my $captured = '';
{
    # A client that is NEVER connected — _send with no socket just logs and
    # returns (no wire write), which is exactly the SEND-site log we need.
    my $client = SignalWire::Relay::Client->new(
        project => $PROJECT,
        token   => $TOKEN,
        host    => 'relay.example.test',
    );

    open( my $olderr, '>&', \*STDERR ) or die "dup STDERR: $!";
    close(STDERR);
    open( STDERR, '>', \$captured ) or die "redirect STDERR: $!";

    # 1) OUTBOUND connect frame through the real _send (the SEND: debug site).
    #    Carries authentication.project/token — the F3.1 credential leak.
    my $connect = {
        jsonrpc => '2.0',
        id      => 'ssc-connect',
        method  => 'signalwire.connect',
        params  => {
            authentication => { project => $PROJECT, token => $TOKEN },
            project        => $PROJECT,
            token          => $TOKEN,
        },
    };
    eval { $client->_send($connect); 1 } or do { print {$olderr} "send err: $@" };

    # 2) INBOUND authorization.state event through the real _handle_message (the
    #    RECV: debug site). Carries the authorization_state re-auth blob — F3.2.
    my $auth_state_frame = JSON->new->canonical->encode(
        {
            jsonrpc => '2.0',
            method  => 'signalwire.event',
            params  => {
                event_type => 'signalwire.authorization.state',
                params     => { authorization_state => $AUTHORIZATION_STATE },
            },
        }
    );
    eval { $client->_handle_message($auth_state_frame); 1 }
        or do { print {$olderr} "recv err: $@" };

    # Restore STDERR.
    close(STDERR);
    open( STDERR, '>&', $olderr ) or die "restore STDERR: $!";
    close($olderr);
}

# Per-sentinel classification: leaked iff the sentinel appears verbatim in the
# captured debug output.
my %out = (
    project => { leaked => ( index( $captured, $PROJECT ) >= 0 ) ? JSON::true : JSON::false },
    token   => { leaked => ( index( $captured, $TOKEN ) >= 0 )   ? JSON::true : JSON::false },
    authorization_state =>
        { leaked => ( index( $captured, $AUTHORIZATION_STATE ) >= 0 ) ? JSON::true : JSON::false },
);

print JSON->new->canonical->encode( \%out ), "\n";
