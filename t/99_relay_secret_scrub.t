#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# PERL-7 / PSDK-5 SECRET-SCRUB: the RELAY client must never emit live
# credentials (project/token/jwt_token) or the server's authorization_state
# re-auth blob verbatim in its debug frame logs. The _send ("SEND: ...") and
# _handle_message ("RECV: ...") debug sites route the frame through
# _scrub_frame, which masks those key VALUES while keeping the frame diagnostic.

use SignalWire::Relay::Client;

# ---- _scrub_frame masks the credential values, preserves structure ----
subtest '_scrub_frame masks credential + authorization_state values' => sub {
    my $frame = join '', (
        '{"jsonrpc":"2.0","method":"signalwire.connect","params":',
        '{"authentication":{"project":"PJ-TESTLEAK","token":"PT-TESTLEAK"},',
        '"authorization_state":"AENC-TESTLEAK","jwt_token":"JWT-TESTLEAK"},"id":"1"}'
    );
    my $out = SignalWire::Relay::Client::_scrub_frame($frame);

    unlike( $out, qr/PJ-TESTLEAK/,   'project value masked' );
    unlike( $out, qr/PT-TESTLEAK/,   'token value masked' );
    unlike( $out, qr/AENC-TESTLEAK/, 'authorization_state value masked' );
    unlike( $out, qr/JWT-TESTLEAK/,  'jwt_token value masked' );

    like( $out, qr/"\*\*\*"/, 'masked values become "***"' );
    # Structure / non-credential content survives so the frame stays diagnostic.
    like( $out, qr/signalwire\.connect/, 'method preserved' );
    like( $out, qr/"id":"1"/,            'id preserved' );
};

subtest '_scrub_frame is a no-op on a credential-free frame' => sub {
    my $frame = '{"jsonrpc":"2.0","method":"calling.play","params":{"call_id":"c-1"},"id":"7"}';
    is( SignalWire::Relay::Client::_scrub_frame($frame),
        $frame, 'no credential keys -> unchanged' );
};

subtest '_scrub_frame handles undef' => sub {
    is( SignalWire::Relay::Client::_scrub_frame(undef), '', 'undef -> empty string' );
};

# ---- the _send debug log routes through the scrub (no raw creds) ----
subtest '_send debug log does not leak credentials' => sub {
    local $ENV{SIGNALWIRE_LOG_LEVEL};    # (level is fixed at logger build; see below)

    my $client = SignalWire::Relay::Client->new(
        project => 'PJ-TESTLEAK',
        token   => 'PT-TESTLEAK',
        host    => 'relay.example.test',
    );

    my $captured = '';
    open( my $olderr, '>&', \*STDERR ) or die "dup: $!";
    close(STDERR);
    open( STDERR, '>', \$captured ) or die "redirect: $!";

    # Force the package logger to debug for the duration of this drive so the
    # SEND site actually emits (the logger caches its level at construction).
    my $logger = SignalWire::Logging->get_logger('relay_client');
    my $prev   = $logger->level;
    $logger->level('debug');

    $client->_send(
        {
            jsonrpc => '2.0',
            id      => 'x',
            method  => 'signalwire.connect',
            params  => { authentication => { project => 'PJ-TESTLEAK', token => 'PT-TESTLEAK' } },
        }
    );

    $logger->level($prev);
    close(STDERR);
    open( STDERR, '>&', $olderr ) or die "restore: $!";
    close($olderr);

    like( $captured, qr/SEND:/, 'SEND frame was logged at debug' );
    unlike( $captured, qr/PJ-TESTLEAK/, 'project not leaked in SEND log' );
    unlike( $captured, qr/PT-TESTLEAK/, 'token not leaked in SEND log' );
};

done_testing;
