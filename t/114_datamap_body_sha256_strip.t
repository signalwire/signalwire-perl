#!/usr/bin/env perl
# DataMap.body (sends `params`), validate_webhook_signature_sha256, and
# strip_control_chars(@args) (last argument is the event hashref).
use strict;
use warnings;
use Test::More;

use SignalWire::DataMap;
use SignalWire::Security::WebhookValidator
    qw(validate_webhook_signature validate_webhook_signature_sha256);
use SignalWire::Core::LoggingConfig ();

subtest 'DataMap body sets the webhook params field' => sub {
    my $dm  = SignalWire::DataMap->new('lookup');
    my $ret = $dm->webhook( 'POST', 'https://api.example.com/x' )->body( { q => '${args.q}' } );
    is( $ret, $dm, 'chains' );
    my $wh = $dm->to_swaig_function->{data_map}{webhooks}[0];
    is_deeply( $wh->{params}, { q => '${args.q}' }, 'body lands under params' );
    ok( !exists $wh->{body}, 'no body key on the wire' );

    my $err = do {
        local $@;
        eval { SignalWire::DataMap->new('x')->body( {} ) };
        $@;
    };
    like( $err, qr/Must add webhook before setting body/, 'dies without a webhook' );
};

# porting-sdk/webhooks.md Vector A, signed with SHA-256 (python hmac reference).
my $KEY    = 'PSKtest1234567890abcdef';
my $URL    = 'https://example.ngrok.io/webhook';
my $BODY   = '{"event":"call.state","params":{"call_id":"abc-123","state":"answered"}}';
my $SHA256 = '2a29f8a92b11df39da80c3b185fd62173d49c294184da585ff951eae4433571c';
my $SHA1   = 'c3c08c1fefaf9ee198a100d5906765a6f394bf0f';

subtest 'validate_webhook_signature_sha256' => sub {
    is( validate_webhook_signature_sha256( $KEY, $SHA256, $URL, $BODY ), 1, 'positive vector' );
    is( validate_webhook_signature( $KEY, $SHA1, $URL, $BODY ),
        1, 'sha1 vector still valid on sha1' );
    is( validate_webhook_signature_sha256( $KEY, $SHA1, $URL, $BODY ),
        0, 'sha1 digest not accepted as sha256' );
    ( my $tampered = $BODY ) =~ s/answered/ringing/;
    is( validate_webhook_signature_sha256( $KEY, $SHA256, $URL, $tampered ), 0, 'tampered body' );
    is( validate_webhook_signature_sha256( 'wrong-key', $SHA256, $URL, $BODY ), 0, 'wrong key' );
    is( validate_webhook_signature_sha256( $KEY, '',    $URL, $BODY ), 0, 'empty signature' );
    is( validate_webhook_signature_sha256( $KEY, undef, $URL, $BODY ), 0, 'missing signature' );
    my $err = do {
        local $@;
        eval { validate_webhook_signature_sha256( '', 'ab', $URL, $BODY ) };
        $@;
    };
    like( $err, qr/signing_key is required/, 'missing key croaks' );
    $err = do {
        local $@;
        eval { validate_webhook_signature_sha256( $KEY, 'ab', $URL, {} ) };
        $@;
    };
    like( $err, qr/raw_body must be a string/, 'parsed body croaks' );
};

subtest 'strip_control_chars takes the event as its last argument' => sub {
    my $event = { msg => "a\x1b[31mb\x00c", n => 5 };
    my $out   = SignalWire::Core::LoggingConfig::strip_control_chars($event);
    is( $out,        $event,    'single-arg form returns the same hashref' );
    is( $out->{msg}, 'a[31mbc', 'control chars stripped' );

    my $ev2 = { event => "x\x07y" };
    my $o2  = SignalWire::Core::LoggingConfig::strip_control_chars( 'logger', 'info', $ev2 );
    is( $o2,           $ev2, 'processor form uses the last argument' );
    is( $ev2->{event}, 'xy', 'stripped in processor form' );

    my $err = do {
        local $@;
        eval { SignalWire::Core::LoggingConfig::strip_control_chars() };
        $@;
    };
    like( $err, qr/requires the event dict/, 'no arguments dies' );
};

done_testing;
