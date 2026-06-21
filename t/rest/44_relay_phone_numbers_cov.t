#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_relay_phone_numbers_full_mock.py
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

my $BASE = '/api/relay/rest/phone_numbers';

# -------------------- Success --------------------

subtest 'test_list' => sub {
    my $client = MockTest::client();
    my $body = $client->phone_numbers->list();
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, $BASE, 'path');
    is($last->{matched_route}, 'relay-rest.list_phone_numbers', 'matched route');
};

subtest 'test_search' => sub {
    my $client = MockTest::client();
    my $body = $client->phone_numbers->search(area_code => '512');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/search", 'path');
    is($last->{matched_route}, 'relay-rest.search_available_phone_numbers', 'matched route');
};

subtest 'test_purchase' => sub {
    my $client = MockTest::client();
    my $body = $client->phone_numbers->create(number => '+15551230000');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, $BASE, 'path');
    is($last->{matched_route}, 'relay-rest.purchase_phone_number', 'matched route');
    is(($last->{body} || {})->{number}, '+15551230000', 'number forwarded');
};

subtest 'test_get' => sub {
    my $client = MockTest::client();
    my $body = $client->phone_numbers->get('pn-1001');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/pn-1001", 'path');
    is($last->{matched_route}, 'relay-rest.retrieve_phone_number', 'matched route');
};

subtest 'test_update' => sub {
    my $client = MockTest::client();
    my $body = $client->phone_numbers->update('pn-1001', name => 'main line');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'PUT', 'PUT');
    is($last->{path}, "$BASE/pn-1001", 'path');
    is($last->{matched_route}, 'relay-rest.update_phone_number', 'matched route');
    is(($last->{body} || {})->{name}, 'main line', 'name forwarded');
};

subtest 'test_release' => sub {
    my $client = MockTest::client();
    $client->phone_numbers->delete_resource('pn-1001');
    my $last = MockTest::journal_last();
    is($last->{method}, 'DELETE', 'DELETE');
    is($last->{path}, "$BASE/pn-1001", 'path');
    is($last->{matched_route}, 'relay-rest.release_phone_number', 'matched route');
};

# -------------------- Errors --------------------

subtest 'test_list_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.list_phone_numbers', 500, { error => 'internal' });
    my $ok = eval { $client->phone_numbers->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.list_phone_numbers', 'matched route');
    is($last->{response_status}, 500, 'journaled 500');
};

subtest 'test_search_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.search_available_phone_numbers', 500, { error => 'internal' });
    my $ok = eval { $client->phone_numbers->search(area_code => '512'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.search_available_phone_numbers', 'matched route');
    is($last->{response_status}, 500, 'journaled 500');
};

subtest 'test_purchase_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.purchase_phone_number', 422, { error => 'number required' });
    my $ok = eval { $client->phone_numbers->create(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.purchase_phone_number', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

subtest 'test_get_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.retrieve_phone_number', 404, { error => 'nope' });
    my $ok = eval { $client->phone_numbers->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.retrieve_phone_number', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.update_phone_number', 404, { error => 'nope' });
    my $ok = eval { $client->phone_numbers->update('missing', name => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.update_phone_number', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_release_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.release_phone_number', 404, { error => 'nope' });
    my $ok = eval { $client->phone_numbers->delete_resource('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.release_phone_number', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

done_testing();
