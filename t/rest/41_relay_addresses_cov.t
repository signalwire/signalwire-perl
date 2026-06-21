#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_relay_addresses_full_mock.py
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

my $BASE = '/api/relay/rest/addresses';

# -------------------- Success --------------------

subtest 'test_list' => sub {
    my $client = MockTest::client();
    my $body = $client->addresses->list();
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, $BASE, 'path');
    is($last->{matched_route}, 'relay-rest.list_addresses', 'matched route');
};

subtest 'test_create' => sub {
    my $client = MockTest::client();
    my $body = $client->addresses->create(name => 'HQ');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, $BASE, 'path');
    is($last->{matched_route}, 'relay-rest.create_address', 'matched route');
    is(($last->{body} || {})->{name}, 'HQ', 'name forwarded');
};

subtest 'test_get' => sub {
    my $client = MockTest::client();
    my $body = $client->addresses->get('addr-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/addr-1", 'path');
    is($last->{matched_route}, 'relay-rest.get_address', 'matched route');
};

subtest 'test_delete' => sub {
    my $client = MockTest::client();
    $client->addresses->delete('addr-1');
    my $last = MockTest::journal_last();
    is($last->{method}, 'DELETE', 'DELETE');
    is($last->{path}, "$BASE/addr-1", 'path');
    is($last->{matched_route}, 'relay-rest.delete_address', 'matched route');
};

# -------------------- Errors --------------------

subtest 'test_list_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.list_addresses', 500, { error => 'internal' });
    my $ok = eval { $client->addresses->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.list_addresses', 'matched route');
    is($last->{response_status}, 500, 'journaled 500');
};

subtest 'test_create_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.create_address', 422, { error => 'name required' });
    my $ok = eval { $client->addresses->create(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.create_address', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

subtest 'test_get_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.get_address', 404, { error => 'nope' });
    my $ok = eval { $client->addresses->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.get_address', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.delete_address', 404, { error => 'nope' });
    my $ok = eval { $client->addresses->delete('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.delete_address', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

done_testing();
