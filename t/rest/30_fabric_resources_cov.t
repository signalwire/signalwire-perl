#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_fabric_resources_full_mock.py
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

# resources = generic cross-type resource (GenericResources):
#   list / get / delete / list_addresses + assign_phone_route / assign_domain_application.
# addresses = read-only FabricAddresses: list / get.
# assign_phone_route is deprecated and carps (Carp::carp -> warning, not death).

subtest 'TestFabricResourcesSuccess' => sub {
    subtest 'test_list' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->resources->list();
        is(ref $body, 'HASH', 'hashref');
        ok(exists $body->{data}, 'data present');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/fabric/resources', 'path');
        is($last->{matched_route}, 'fabric.list_resources', 'matched route');
    };

    subtest 'test_get' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->resources->get('res-1');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/fabric/resources/res-1', 'path');
        is($last->{matched_route}, 'fabric.get_resource', 'matched route');
    };

    subtest 'test_delete' => sub {
        my $client = MockTest::client();
        $client->fabric->resources->delete('res-1');
        my $last = MockTest::journal_last();
        is($last->{method}, 'DELETE', 'DELETE');
        is($last->{path}, '/api/fabric/resources/res-1', 'path');
        is($last->{matched_route}, 'fabric.delete_resource', 'matched route');
    };

    subtest 'test_list_addresses' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->resources->list_addresses('res-1');
        ok(ref $body eq 'HASH' || ref $body eq 'ARRAY', 'hashref or arrayref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/fabric/resources/res-1/addresses', 'path');
        is($last->{matched_route}, 'fabric.list_resource_addresses', 'matched route');
    };

    subtest 'test_assign_phone_route' => sub {
        my $client = MockTest::client();
        my $body;
        {
            local $SIG{__WARN__} = sub {};    # swallow the deprecation carp
            $body = $client->fabric->resources->assign_phone_route(
                'res-1', phone_number => '+15551230000',
            );
        }
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST');
        is($last->{path}, '/api/fabric/resources/res-1/phone_routes', 'path');
        is($last->{matched_route}, 'fabric.assign_resource_phone_route', 'matched route');
    };

    subtest 'test_assign_domain_application' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->resources->assign_domain_application(
            'res-1', domain => 'example.test',
        );
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST');
        is($last->{path}, '/api/fabric/resources/res-1/domain_applications', 'path');
        is($last->{matched_route}, 'fabric.assign_resource_domain_application', 'matched route');
    };
};

subtest 'TestFabricAddressesSuccess' => sub {
    subtest 'test_list' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->addresses->list();
        ok(ref $body eq 'HASH' || ref $body eq 'ARRAY', 'hashref or arrayref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/fabric/addresses', 'path');
        is($last->{matched_route}, 'fabric.list_fabric_addresses', 'matched route');
    };

    subtest 'test_get' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->addresses->get('addr-1');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/fabric/addresses/addr-1', 'path');
        is($last->{matched_route}, 'fabric.get_fabric_address', 'matched route');
    };
};

subtest 'TestFabricResourcesErrors' => sub {
    subtest 'test_list_server_error' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.list_resources', 500, { error => 'internal' });
        my $ok = eval { $client->fabric->resources->list(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 500, 'status 500');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.list_resources', 'matched route');
        is($last->{response_status}, 500, 'journaled 500');
    };

    subtest 'test_get_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.get_resource', 404, { error => 'not found' });
        my $ok = eval { $client->fabric->resources->get('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.get_resource', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_delete_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.delete_resource', 404, { error => 'not found' });
        my $ok = eval { $client->fabric->resources->delete('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.delete_resource', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_list_addresses_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.list_resource_addresses', 404, { error => 'not found' });
        my $ok = eval { $client->fabric->resources->list_addresses('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.list_resource_addresses', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_assign_phone_route_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.assign_resource_phone_route', 422, { error => 'bad target' });
        my $ok = eval {
            local $SIG{__WARN__} = sub {};
            $client->fabric->resources->assign_phone_route('res-1', phone_number => '+15551230000');
            1;
        };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.assign_resource_phone_route', 'matched route');
        is($last->{response_status}, 422, 'journaled 422');
    };

    subtest 'test_assign_domain_application_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.assign_resource_domain_application', 422, { error => 'bad domain' });
        my $ok = eval {
            $client->fabric->resources->assign_domain_application('res-1', domain => 'bad');
            1;
        };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.assign_resource_domain_application', 'matched route');
        is($last->{response_status}, 422, 'journaled 422');
    };
};

subtest 'TestFabricAddressesErrors' => sub {
    subtest 'test_list_server_error' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.list_fabric_addresses', 500, { error => 'internal' });
        my $ok = eval { $client->fabric->addresses->list(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 500, 'status 500');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.list_fabric_addresses', 'matched route');
        is($last->{response_status}, 500, 'journaled 500');
    };

    subtest 'test_get_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fabric.get_fabric_address', 404, { error => 'not found' });
        my $ok = eval { $client->fabric->addresses->get('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'fabric.get_fabric_address', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };
};

done_testing();
