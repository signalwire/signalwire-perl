#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_relay_queues_full_mock.py
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

my $BASE = '/api/relay/rest/queues';

# -------------------- Success --------------------

subtest 'test_list' => sub {
    my $client = MockTest::client();
    my $body = $client->queues->list();
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, $BASE, 'path');
    is($last->{matched_route}, 'relay-rest.list_queues', 'matched route');
};

subtest 'test_create' => sub {
    my $client = MockTest::client();
    my $body = $client->queues->create(name => 'support');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, $BASE, 'path');
    is($last->{matched_route}, 'relay-rest.create_queue', 'matched route');
    is(($last->{body} || {})->{name}, 'support', 'name forwarded');
};

subtest 'test_get' => sub {
    my $client = MockTest::client();
    my $body = $client->queues->get('q-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/q-1", 'path');
    is($last->{matched_route}, 'relay-rest.get_queue', 'matched route');
};

subtest 'test_update' => sub {
    my $client = MockTest::client();
    my $body = $client->queues->update('q-1', name => 'renamed');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'PUT', 'PUT');
    is($last->{path}, "$BASE/q-1", 'path');
    is($last->{matched_route}, 'relay-rest.update_queue', 'matched route');
    is(($last->{body} || {})->{name}, 'renamed', 'name forwarded');
};

subtest 'test_delete' => sub {
    my $client = MockTest::client();
    $client->queues->delete_resource('q-1');
    my $last = MockTest::journal_last();
    is($last->{method}, 'DELETE', 'DELETE');
    is($last->{path}, "$BASE/q-1", 'path');
    is($last->{matched_route}, 'relay-rest.delete_queue', 'matched route');
};

subtest 'test_list_members' => sub {
    my $client = MockTest::client();
    my $body = $client->queues->list_members('q-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/q-1/members", 'path');
    is($last->{matched_route}, 'relay-rest.list_queue_members', 'matched route');
};

subtest 'test_get_next_member' => sub {
    my $client = MockTest::client();
    my $body = $client->queues->get_next_member('q-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/q-1/members/next", 'path');
    is($last->{matched_route}, 'relay-rest.retrieve_next_queue_member', 'matched route');
};

subtest 'test_get_member' => sub {
    my $client = MockTest::client();
    my $body = $client->queues->get_member('q-1', 'm-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/q-1/members/m-1", 'path');
    is($last->{matched_route}, 'relay-rest.retrieve_queue_member', 'matched route');
};

# -------------------- Errors --------------------

subtest 'test_list_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.list_queues', 500, { error => 'internal' });
    my $ok = eval { $client->queues->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.list_queues', 'matched route');
    is($last->{response_status}, 500, 'journaled 500');
};

subtest 'test_create_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.create_queue', 422, { error => 'name required' });
    my $ok = eval { $client->queues->create(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.create_queue', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

subtest 'test_get_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.get_queue', 404, { error => 'nope' });
    my $ok = eval { $client->queues->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.get_queue', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.update_queue', 404, { error => 'nope' });
    my $ok = eval { $client->queues->update('missing', name => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.update_queue', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.delete_queue', 404, { error => 'nope' });
    my $ok = eval { $client->queues->delete_resource('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.delete_queue', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_list_members_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.list_queue_members', 404, { error => 'nope' });
    my $ok = eval { $client->queues->list_members('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.list_queue_members', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_get_next_member_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.retrieve_next_queue_member', 404, { error => 'empty' });
    my $ok = eval { $client->queues->get_next_member('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.retrieve_next_queue_member', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_get_member_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.retrieve_queue_member', 404, { error => 'nope' });
    my $ok = eval { $client->queues->get_member('missing', 'm-1'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.retrieve_queue_member', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

done_testing();
