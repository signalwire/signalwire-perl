#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_fabric_ai_agents_full_mock.py
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

# ai_agents is a plain FabricResource CRUD at /api/fabric/resources/ai_agents:
# list / create / get / update (PATCH) / delete, plus list_addresses.
# Perl CRUD delete is delete_resource (only GenericResources has a 'delete' alias).

subtest 'TestFabricAIAgentsSuccess' => sub {
    subtest 'test_list' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->ai_agents->list();
        is(ref $body, 'HASH', 'hashref');
        ok(exists $body->{data}, "data present");
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/fabric/resources/ai_agents', 'path');
        is($last->{matched_route}, 'fabric.list_ai_agents', 'matched route');
    };

    subtest 'test_create' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->ai_agents->create(name => 'agent-alpha');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST');
        is($last->{path}, '/api/fabric/resources/ai_agents', 'path');
        is($last->{matched_route}, 'fabric.create_ai_agent', 'matched route');
        is($last->{body}{name}, 'agent-alpha', 'name forwarded');
    };

    subtest 'test_get' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->ai_agents->get('aa-1001');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/fabric/resources/ai_agents/aa-1001', 'path');
        is($last->{matched_route}, 'fabric.get_ai_agent', 'matched route');
    };

    subtest 'test_update' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->ai_agents->update('aa-1001', name => 'renamed');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'PATCH', 'PATCH');
        is($last->{path}, '/api/fabric/resources/ai_agents/aa-1001', 'path');
        is($last->{matched_route}, 'fabric.update_ai_agent', 'matched route');
        is($last->{body}{name}, 'renamed', 'name forwarded');
    };

    subtest 'test_delete' => sub {
        my $client = MockTest::client();
        $client->fabric->ai_agents->delete_resource('aa-1001');
        my $last = MockTest::journal_last();
        is($last->{method}, 'DELETE', 'DELETE');
        is($last->{path}, '/api/fabric/resources/ai_agents/aa-1001', 'path');
        is($last->{matched_route}, 'fabric.delete_ai_agent', 'matched route');
    };

    subtest 'test_list_addresses' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->ai_agents->list_addresses('aa-1001');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/fabric/resources/ai_agents/aa-1001/addresses', 'path');
        is($last->{matched_route}, 'fabric.list_ai_agent_addresses', 'matched route');
    };
};

subtest 'TestFabricAIAgentsErrors' => sub {
    subtest 'test_list_server_error' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.list_ai_agents', 500, { error => 'internal' });
        my $ok = eval { $client->fabric->ai_agents->list(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 500, 'status 500');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.list_ai_agents', 'matched route');
        is($last->{response_status}, 500, 'journaled 500');
    };

    subtest 'test_create_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.create_ai_agent', 422, { error => 'name required' });
        my $ok = eval { $client->fabric->ai_agents->create(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.create_ai_agent', 'matched route');
        is($last->{response_status}, 422, 'journaled 422');
    };

    subtest 'test_get_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.get_ai_agent', 404, { error => 'not found' });
        my $ok = eval { $client->fabric->ai_agents->get('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.get_ai_agent', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_update_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.update_ai_agent', 404, { error => 'not found' });
        my $ok = eval { $client->fabric->ai_agents->update('missing', name => 'x'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.update_ai_agent', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_delete_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.delete_ai_agent', 404, { error => 'not found' });
        my $ok = eval { $client->fabric->ai_agents->delete_resource('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.delete_ai_agent', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_list_addresses_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.list_ai_agent_addresses', 404, { error => 'not found' });
        my $ok = eval { $client->fabric->ai_agents->list_addresses('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.list_ai_agent_addresses', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };
};

done_testing();
