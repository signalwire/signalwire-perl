#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_relay_verified_callers_full_mock.py
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

my $BASE = '/api/relay/rest/verified_caller_ids';

# -------------------- Success --------------------

subtest 'test_list' => sub {
    my $client = MockTest::client();
    my $body = $client->verified_callers->list();
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, $BASE, 'path');
    is($last->{matched_route}, 'relay-rest.list_verified_caller_ids', 'matched route');
};

subtest 'test_create' => sub {
    my $client = MockTest::client();
    my $body = $client->verified_callers->create(phone_number => '+15551112222');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, $BASE, 'path');
    is($last->{matched_route}, 'relay-rest.create_verified_caller_id', 'matched route');
    is(($last->{body} || {})->{phone_number}, '+15551112222', 'phone_number forwarded');
};

subtest 'test_get' => sub {
    my $client = MockTest::client();
    my $body = $client->verified_callers->get('vc-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/vc-1", 'path');
    is($last->{matched_route}, 'relay-rest.retrieve_verified_caller_id', 'matched route');
};

subtest 'test_update' => sub {
    my $client = MockTest::client();
    my $body = $client->verified_callers->update('vc-1', name => 'renamed');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'PUT', 'PUT');
    is($last->{path}, "$BASE/vc-1", 'path');
    is($last->{matched_route}, 'relay-rest.update_verified_caller_id', 'matched route');
    is(($last->{body} || {})->{name}, 'renamed', 'name forwarded');
};

subtest 'test_delete' => sub {
    my $client = MockTest::client();
    $client->verified_callers->delete_resource('vc-1');
    my $last = MockTest::journal_last();
    is($last->{method}, 'DELETE', 'DELETE');
    is($last->{path}, "$BASE/vc-1", 'path');
    is($last->{matched_route}, 'relay-rest.delete_verified_caller_id', 'matched route');
};

subtest 'test_redial_verification' => sub {
    my $client = MockTest::client();
    my $body = $client->verified_callers->redial_verification('vc-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, "$BASE/vc-1/verification", 'path');
    is($last->{matched_route}, 'relay-rest.redial_verification_call', 'matched route');
};

subtest 'test_submit_verification' => sub {
    my $client = MockTest::client();
    my $body = $client->verified_callers->submit_verification('vc-1', verification_code => '123456');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'PUT', 'PUT');
    is($last->{path}, "$BASE/vc-1/verification", 'path');
    is($last->{matched_route}, 'relay-rest.validate_verification_code', 'matched route');
    is(($last->{body} || {})->{verification_code}, '123456', 'verification_code forwarded');
};

# -------------------- Errors --------------------

subtest 'test_list_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.list_verified_caller_ids', 500, { error => 'internal' });
    my $ok = eval { $client->verified_callers->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.list_verified_caller_ids', 'matched route');
    is($last->{response_status}, 500, 'journaled 500');
};

subtest 'test_create_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.create_verified_caller_id', 422, { error => 'bad' });
    my $ok = eval { $client->verified_callers->create(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.create_verified_caller_id', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

subtest 'test_get_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.retrieve_verified_caller_id', 404, { error => 'nope' });
    my $ok = eval { $client->verified_callers->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.retrieve_verified_caller_id', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.update_verified_caller_id', 404, { error => 'nope' });
    my $ok = eval { $client->verified_callers->update('missing', name => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.update_verified_caller_id', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.delete_verified_caller_id', 404, { error => 'nope' });
    my $ok = eval { $client->verified_callers->delete_resource('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.delete_verified_caller_id', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_redial_verification_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.redial_verification_call', 404, { error => 'nope' });
    my $ok = eval { $client->verified_callers->redial_verification('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.redial_verification_call', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_submit_verification_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.validate_verification_code', 422, { error => 'wrong code' });
    my $ok = eval { $client->verified_callers->submit_verification('vc-1', verification_code => '000000'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.validate_verification_code', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

done_testing();
