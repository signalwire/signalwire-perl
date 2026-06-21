#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_relay_number_groups_full_mock.py
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

my $BASE = '/api/relay/rest/number_groups';
my $MEMBERSHIPS = '/api/relay/rest/number_group_memberships';

# -------------------- Success --------------------

subtest 'test_list' => sub {
    my $client = MockTest::client();
    my $body = $client->number_groups->list();
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, $BASE, 'path');
    is($last->{matched_route}, 'relay-rest.list_number_groups', 'matched route');
};

subtest 'test_create' => sub {
    my $client = MockTest::client();
    my $body = $client->number_groups->create(name => 'group-a');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, $BASE, 'path');
    is($last->{matched_route}, 'relay-rest.create_number_group', 'matched route');
    is(($last->{body} || {})->{name}, 'group-a', 'name forwarded');
};

subtest 'test_get' => sub {
    my $client = MockTest::client();
    my $body = $client->number_groups->get('ng-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/ng-1", 'path');
    is($last->{matched_route}, 'relay-rest.retrieve_number_group', 'matched route');
};

subtest 'test_update' => sub {
    my $client = MockTest::client();
    my $body = $client->number_groups->update('ng-1', name => 'renamed');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'PUT', 'PUT');
    is($last->{path}, "$BASE/ng-1", 'path');
    is($last->{matched_route}, 'relay-rest.update_number_group', 'matched route');
    is(($last->{body} || {})->{name}, 'renamed', 'name forwarded');
};

subtest 'test_delete' => sub {
    my $client = MockTest::client();
    $client->number_groups->delete_resource('ng-1');
    my $last = MockTest::journal_last();
    is($last->{method}, 'DELETE', 'DELETE');
    is($last->{path}, "$BASE/ng-1", 'path');
    is($last->{matched_route}, 'relay-rest.delete_number_group', 'matched route');
};

subtest 'test_list_memberships' => sub {
    my $client = MockTest::client();
    my $body = $client->number_groups->list_memberships('ng-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/ng-1/number_group_memberships", 'path');
    is($last->{matched_route}, 'relay-rest.list_number_group_memberships', 'matched route');
};

subtest 'test_add_membership' => sub {
    my $client = MockTest::client();
    my $body = $client->number_groups->add_membership('ng-1', phone_number_id => 'pn-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, "$BASE/ng-1/number_group_memberships", 'path');
    is($last->{matched_route}, 'relay-rest.create_number_group_membership', 'matched route');
    is(($last->{body} || {})->{phone_number_id}, 'pn-1', 'phone_number_id forwarded');
};

subtest 'test_get_membership' => sub {
    my $client = MockTest::client();
    my $body = $client->number_groups->get_membership('ngm-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$MEMBERSHIPS/ngm-1", 'path');
    is($last->{matched_route}, 'relay-rest.retrieve_number_group_membership', 'matched route');
};

subtest 'test_delete_membership' => sub {
    my $client = MockTest::client();
    $client->number_groups->delete_membership('ngm-1');
    my $last = MockTest::journal_last();
    is($last->{method}, 'DELETE', 'DELETE');
    is($last->{path}, "$MEMBERSHIPS/ngm-1", 'path');
    is($last->{matched_route}, 'relay-rest.delete_number_group_membership', 'matched route');
};

# -------------------- Errors --------------------

subtest 'test_list_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.list_number_groups', 500, { error => 'internal' });
    my $ok = eval { $client->number_groups->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.list_number_groups', 'matched route');
    is($last->{response_status}, 500, 'journaled 500');
};

subtest 'test_create_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.create_number_group', 422, { error => 'name required' });
    my $ok = eval { $client->number_groups->create(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.create_number_group', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

subtest 'test_get_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.retrieve_number_group', 404, { error => 'nope' });
    my $ok = eval { $client->number_groups->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.retrieve_number_group', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.update_number_group', 404, { error => 'nope' });
    my $ok = eval { $client->number_groups->update('missing', name => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.update_number_group', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.delete_number_group', 404, { error => 'nope' });
    my $ok = eval { $client->number_groups->delete_resource('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.delete_number_group', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_list_memberships_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.list_number_group_memberships', 404, { error => 'nope' });
    my $ok = eval { $client->number_groups->list_memberships('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.list_number_group_memberships', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_add_membership_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.create_number_group_membership', 422, { error => 'bad' });
    my $ok = eval { $client->number_groups->add_membership('ng-1'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.create_number_group_membership', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

subtest 'test_get_membership_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.retrieve_number_group_membership', 404, { error => 'nope' });
    my $ok = eval { $client->number_groups->get_membership('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.retrieve_number_group_membership', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_membership_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.delete_number_group_membership', 404, { error => 'nope' });
    my $ok = eval { $client->number_groups->delete_membership('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.delete_number_group_membership', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

done_testing();
