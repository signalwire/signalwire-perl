#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_fabric_subscribers_full_mock.py
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

# Subscribers: PUT-update CRUD (+addresses) at /api/fabric/resources/subscribers,
# AND a nested sip_endpoints CRUD (PATCH-update). Perl CRUD delete is delete_resource.

my $SUB = 'sub-1001';
my $EP  = 'ep-2002';

subtest 'TestFabricSubscribersSuccess' => sub {
    subtest 'test_list' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->subscribers->list();
        is(ref $body, 'HASH', 'hashref');
        ok(exists $body->{data}, 'data present');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/fabric/resources/subscribers', 'path');
        is($last->{matched_route}, 'fabric.list_subscribers', 'matched route');
    };

    subtest 'test_create' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->subscribers->create(email => 'a@b.c');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST');
        is($last->{path}, '/api/fabric/resources/subscribers', 'path');
        is($last->{matched_route}, 'fabric.create_subscriber', 'matched route');
        is($last->{body}{email}, 'a@b.c', 'email forwarded');
    };

    subtest 'test_get' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->subscribers->get($SUB);
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, "/api/fabric/resources/subscribers/$SUB", 'path');
        is($last->{matched_route}, 'fabric.get_subscriber', 'matched route');
    };

    subtest 'test_update' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->subscribers->update($SUB, email => 'x@y.z');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'PUT', 'PUT');
        is($last->{path}, "/api/fabric/resources/subscribers/$SUB", 'path');
        is($last->{matched_route}, 'fabric.update_subscriber', 'matched route');
        is($last->{body}{email}, 'x@y.z', 'email forwarded');
    };

    subtest 'test_delete' => sub {
        my $client = MockTest::client();
        $client->fabric->subscribers->delete_resource($SUB);
        my $last = MockTest::journal_last();
        is($last->{method}, 'DELETE', 'DELETE');
        is($last->{path}, "/api/fabric/resources/subscribers/$SUB", 'path');
        is($last->{matched_route}, 'fabric.delete_subscriber', 'matched route');
    };

    subtest 'test_list_addresses' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->subscribers->list_addresses($SUB);
        ok(ref $body eq 'HASH' || ref $body eq 'ARRAY', 'hashref or arrayref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, "/api/fabric/resources/subscribers/$SUB/addresses", 'path');
        is($last->{matched_route}, 'fabric.list_subscriber_addresses', 'matched route');
    };
};

subtest 'TestFabricSubscriberSipEndpointsSuccess' => sub {
    subtest 'test_list' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->subscribers->list_sip_endpoints($SUB);
        ok(ref $body eq 'HASH' || ref $body eq 'ARRAY', 'hashref or arrayref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, "/api/fabric/resources/subscribers/$SUB/sip_endpoints", 'path');
        is($last->{matched_route}, 'fabric.list_subscriber_sip_endpoints', 'matched route');
    };

    subtest 'test_create' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->subscribers->create_sip_endpoint($SUB, username => 'alice');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST');
        is($last->{path}, "/api/fabric/resources/subscribers/$SUB/sip_endpoints", 'path');
        is($last->{matched_route}, 'fabric.create_subscriber_sip_endpoint', 'matched route');
        is($last->{body}{username}, 'alice', 'username forwarded');
    };

    subtest 'test_get' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->subscribers->get_sip_endpoint($SUB, $EP);
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, "/api/fabric/resources/subscribers/$SUB/sip_endpoints/$EP", 'path');
        is($last->{matched_route}, 'fabric.get_subscriber_sip_endpoint', 'matched route');
    };

    subtest 'test_update' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->subscribers->update_sip_endpoint($SUB, $EP, username => 'bob');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'PATCH', 'PATCH');
        is($last->{path}, "/api/fabric/resources/subscribers/$SUB/sip_endpoints/$EP", 'path');
        is($last->{matched_route}, 'fabric.update_subscriber_sip_endpoint', 'matched route');
        is($last->{body}{username}, 'bob', 'username forwarded');
    };

    subtest 'test_delete' => sub {
        my $client = MockTest::client();
        $client->fabric->subscribers->delete_sip_endpoint($SUB, $EP);
        my $last = MockTest::journal_last();
        is($last->{method}, 'DELETE', 'DELETE');
        is($last->{path}, "/api/fabric/resources/subscribers/$SUB/sip_endpoints/$EP", 'path');
        is($last->{matched_route}, 'fabric.delete_subscriber_sip_endpoint', 'matched route');
    };
};

subtest 'TestFabricSubscribersErrors' => sub {
    subtest 'test_list_server_error' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.list_subscribers', 500, { error => 'internal' });
        my $ok = eval { $client->fabric->subscribers->list(); 1 };
        my $e = $@;
        ok(!$ok, 'raised'); isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 500, 'status 500');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.list_subscribers', 'matched route');
        is($last->{response_status}, 500, 'journaled 500');
    };

    subtest 'test_create_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.create_subscriber', 422, { error => 'email required' });
        my $ok = eval { $client->fabric->subscribers->create(); 1 };
        my $e = $@;
        ok(!$ok, 'raised'); isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.create_subscriber', 'matched route');
        is($last->{response_status}, 422, 'journaled 422');
    };

    subtest 'test_get_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.get_subscriber', 404, { error => 'not found' });
        my $ok = eval { $client->fabric->subscribers->get('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised'); isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.get_subscriber', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_update_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.update_subscriber', 404, { error => 'not found' });
        my $ok = eval { $client->fabric->subscribers->update('missing', email => 'x@y.z'); 1 };
        my $e = $@;
        ok(!$ok, 'raised'); isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.update_subscriber', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_delete_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.delete_subscriber', 404, { error => 'not found' });
        my $ok = eval { $client->fabric->subscribers->delete_resource('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised'); isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.delete_subscriber', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_list_addresses_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.list_subscriber_addresses', 404, { error => 'not found' });
        my $ok = eval { $client->fabric->subscribers->list_addresses('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised'); isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.list_subscriber_addresses', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };
};

subtest 'TestFabricSubscriberSipEndpointsErrors' => sub {
    subtest 'test_list_server_error' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.list_subscriber_sip_endpoints', 500, { error => 'internal' });
        my $ok = eval { $client->fabric->subscribers->list_sip_endpoints($SUB); 1 };
        my $e = $@;
        ok(!$ok, 'raised'); isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 500, 'status 500');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.list_subscriber_sip_endpoints', 'matched route');
        is($last->{response_status}, 500, 'journaled 500');
    };

    subtest 'test_create_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.create_subscriber_sip_endpoint', 422, { error => 'username required' });
        my $ok = eval { $client->fabric->subscribers->create_sip_endpoint($SUB); 1 };
        my $e = $@;
        ok(!$ok, 'raised'); isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.create_subscriber_sip_endpoint', 'matched route');
        is($last->{response_status}, 422, 'journaled 422');
    };

    subtest 'test_get_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.get_subscriber_sip_endpoint', 404, { error => 'not found' });
        my $ok = eval { $client->fabric->subscribers->get_sip_endpoint($SUB, 'missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised'); isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.get_subscriber_sip_endpoint', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_update_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.update_subscriber_sip_endpoint', 404, { error => 'not found' });
        my $ok = eval { $client->fabric->subscribers->update_sip_endpoint($SUB, 'missing', username => 'bob'); 1 };
        my $e = $@;
        ok(!$ok, 'raised'); isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.update_subscriber_sip_endpoint', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_delete_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.delete_subscriber_sip_endpoint', 404, { error => 'not found' });
        my $ok = eval { $client->fabric->subscribers->delete_sip_endpoint($SUB, 'missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised'); isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.delete_subscriber_sip_endpoint', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };
};

done_testing();
