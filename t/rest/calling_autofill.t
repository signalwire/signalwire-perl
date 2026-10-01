#!/usr/bin/env perl
# calling command-dispatch markup over the live mock:
#   * x-sdk-autofill: uuid4 — a control_id the caller omits is generated (the RELAY
#     client's control_id idiom); one the caller passes is sent unchanged.
#   * x-sdk-compat-kwargs — calling.record `audio` is sent INTO params.record.audio.
# Mirrors the python reference's generated Calling.play / Calling.record.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

my $UUID4 = qr/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/;

subtest 'play without control_id gets a generated uuid4' => sub {
    my $client = MockTest::client();
    $client->calling->play( 'call-1', play => [ { type => 'tts', params => { text => 'hi' } } ] );
    my $body = MockTest::journal_last()->{body};
    is( $body->{command}, 'calling.play', 'command' );
    is( $body->{id},      'call-1',       'call id' );
    like( $body->{params}{control_id}, $UUID4, 'control_id autofilled with a uuid4' );
};

subtest 'a caller-supplied control_id is sent unchanged' => sub {
    my $client = MockTest::client();
    $client->calling->play(
        'call-1',
        control_id => 'ctl-1',
        play       => [ { type => 'tts', params => { text => 'hi' } } ],
    );
    is( MockTest::journal_last()->{body}{params}{control_id}, 'ctl-1', 'control_id kept' );
};

subtest 'record audio is sent into params.record.audio' => sub {
    my $client = MockTest::client();
    $client->calling->record( 'call-1', audio => { format => 'wav' } );
    my $params = MockTest::journal_last()->{body}{params};
    is_deeply( $params->{record}, { audio => { format => 'wav' } }, 'nested into record.audio' );
    ok( !exists $params->{audio}, 'no top-level audio key' );
    like( $params->{control_id}, $UUID4, 'control_id autofilled' );
};

done_testing();
