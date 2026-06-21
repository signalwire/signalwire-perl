#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_fabric_tokens_full_mock.py
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

# FabricTokens: subscriber / guest / invite / embed tokens under /api/fabric.
# Perl method names differ from route IDs (e.g. create_invite_token hits
# fabric.create_subscriber_invite_token).

subtest 'TestFabricTokensSuccess' => sub {
    subtest 'test_create_subscriber_token' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->tokens->create_subscriber_token(reference => 'sub-1001');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST');
        is($last->{path}, '/api/fabric/subscribers/tokens', 'path');
        is($last->{matched_route}, 'fabric.create_subscriber_token', 'matched route');
        is($last->{body}{reference}, 'sub-1001', 'reference forwarded');
    };

    subtest 'test_refresh_subscriber_token' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->tokens->refresh_subscriber_token(token => 't-1');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST');
        is($last->{path}, '/api/fabric/subscribers/tokens/refresh', 'path');
        is($last->{matched_route}, 'fabric.refresh_subscriber_token', 'matched route');
    };

    subtest 'test_create_invite_token' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->tokens->create_invite_token(email => 'a@b.c');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST');
        is($last->{path}, '/api/fabric/subscriber/invites', 'path');
        is($last->{matched_route}, 'fabric.create_subscriber_invite_token', 'matched route');
    };

    subtest 'test_create_guest_token' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->tokens->create_guest_token(allowed_addresses => ['addr-1']);
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST');
        is($last->{path}, '/api/fabric/guests/tokens', 'path');
        is($last->{matched_route}, 'fabric.create_subscriber_guest_token', 'matched route');
    };

    subtest 'test_create_embed_token' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->tokens->create_embed_token(embed_id => 'e-1');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST');
        is($last->{path}, '/api/fabric/embeds/tokens', 'path');
        is($last->{matched_route}, 'fabric.create_embeds_token', 'matched route');
    };
};

subtest 'TestFabricTokensErrors' => sub {
    subtest 'test_create_subscriber_token_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.create_subscriber_token', 422, { error => 'reference required' });
        my $ok = eval { $client->fabric->tokens->create_subscriber_token(); 1 };
        my $e = $@;
        ok(!$ok, 'raised'); isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.create_subscriber_token', 'matched route');
        is($last->{response_status}, 422, 'journaled 422');
    };

    subtest 'test_refresh_subscriber_token_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.refresh_subscriber_token', 404, { error => 'token not found' });
        my $ok = eval { $client->fabric->tokens->refresh_subscriber_token(token => 'missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised'); isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.refresh_subscriber_token', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_create_invite_token_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.create_subscriber_invite_token', 422, { error => 'email required' });
        my $ok = eval { $client->fabric->tokens->create_invite_token(); 1 };
        my $e = $@;
        ok(!$ok, 'raised'); isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.create_subscriber_invite_token', 'matched route');
        is($last->{response_status}, 422, 'journaled 422');
    };

    subtest 'test_create_guest_token_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.create_subscriber_guest_token', 422, { error => 'bad input' });
        my $ok = eval { $client->fabric->tokens->create_guest_token(); 1 };
        my $e = $@;
        ok(!$ok, 'raised'); isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.create_subscriber_guest_token', 'matched route');
        is($last->{response_status}, 422, 'journaled 422');
    };

    subtest 'test_create_embed_token_server_error' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.create_embeds_token', 500, { error => 'internal' });
        my $ok = eval { $client->fabric->tokens->create_embed_token(embed_id => 'e-1'); 1 };
        my $e = $@;
        ok(!$ok, 'raised'); isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 500, 'status 500');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.create_embeds_token', 'matched route');
        is($last->{response_status}, 500, 'journaled 500');
    };
};

done_testing();
