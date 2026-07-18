#!/usr/bin/env perl
# Mock-backed unit tests translated from
# signalwire-python/tests/unit/rest/test_fabric_mock.py.
#
# Closes the audit gaps that the legacy test_fabric.py leaves open:
# addresses, generic resources operations, SIP-endpoint sub-resources on
# subscribers, the call-flows / conference-rooms addresses sub-paths, the
# full FabricTokens surface, and the CxmlApplications.create deliberate
# failure path.

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use MockTest;

# ---- Fabric Addresses (read-only top-level resource) --------------------

subtest 'TestFabricAddresses' => sub {
    subtest 'test_list_returns_data_collection' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->addresses->list();
        is(ref $body, 'HASH', 'expected hashref');
        ok(exists $body->{data},
            "missing 'data' in body keys: " . join(',', sort keys %$body));
        is(ref $body->{data}, 'ARRAY', 'data is arrayref');

        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET recorded');
        is($last->{path}, '/api/fabric/addresses', 'path matches');
        is($last->{matched_route}, 'fabric.list_fabric_addresses',
            'matched route is fabric.list_fabric_addresses');
    };

    subtest 'test_get_uses_address_id' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->addresses->get('addr-9001');
        is(ref $body, 'HASH', 'expected hashref');

        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET recorded');
        is($last->{path}, '/api/fabric/addresses/addr-9001', 'path matches');
        isnt($last->{matched_route}, undef, 'matched_route set');
    };
};

# ---- CxmlApplicationsResource.create — deliberate die ------------------

subtest 'TestCxmlApplicationsCreate' => sub {
    subtest 'test_create_not_implemented' => sub {
        # cXML applications cannot be created via the API. The generated
        # CxmlApplications class is a BaseResource with NO create method, so
        # there is no create route and nothing can hit the wire.
        my $client = MockTest::client();
        ok(!$client->fabric->cxml_applications->can('create'),
            'cxml_applications has no create method');

        my $before = scalar @{ MockTest::journal_all() };
        eval { $client->fabric->cxml_applications->create(name => 'never_built') };
        my $after = scalar @{ MockTest::journal_all() };
        is($after, $before, 'create added no journal entries (nothing hit the wire)');
    };
};

# ---- CallFlowsResource.list_addresses — singular 'call_flow' subpath ---

subtest 'TestCallFlowsAddresses' => sub {
    subtest 'test_list_addresses_uses_singular_path' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->call_flows->list_addresses('cf-1');
        is(ref $body, 'HASH', 'expected hashref');
        ok(exists $body->{data} && ref $body->{data} eq 'ARRAY',
            'data is arrayref');

        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET recorded');
        # singular 'call_flow' (NOT 'call_flows') in the addresses sub-path.
        is($last->{path}, '/api/fabric/resources/call_flow/cf-1/addresses',
            'singular call_flow in path');
        isnt($last->{matched_route}, undef, 'matched_route set');
    };
};

# ---- ConferenceRoomsResource.list_addresses — singular subpath ----------

subtest 'TestConferenceRoomsAddresses' => sub {
    subtest 'test_list_addresses_uses_singular_path' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->conference_rooms->list_addresses('cr-1');
        is(ref $body, 'HASH', 'expected hashref');
        ok(exists $body->{data}, 'has data key');

        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET recorded');
        # singular 'conference_room'.
        is($last->{path}, '/api/fabric/resources/conference_room/cr-1/addresses',
            'singular conference_room in path');
        isnt($last->{matched_route}, undef, 'matched_route set');
    };
};

# ---- Subscribers — SIP endpoint per-id ops -----------------------------

subtest 'TestSubscribersSipEndpointOps' => sub {
    subtest 'test_get_sip_endpoint' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->subscribers->get_sip_endpoint(
            'sub-1', 'ep-1',
        );
        is(ref $body, 'HASH', 'expected hashref');

        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET recorded');
        is($last->{path},
            '/api/fabric/resources/subscribers/sub-1/sip_endpoints/ep-1',
            'path matches');
        isnt($last->{matched_route}, undef, 'matched_route set');
    };

    subtest 'test_update_sip_endpoint_uses_patch' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->subscribers->update_sip_endpoint(
            'sub-1', 'ep-1', username => 'renamed',
        );
        is(ref $body, 'HASH', 'expected hashref');

        my $last = MockTest::journal_last();
        is($last->{method}, 'PATCH', 'PATCH recorded');
        is($last->{path},
            '/api/fabric/resources/subscribers/sub-1/sip_endpoints/ep-1',
            'path matches');
        is(ref $last->{body}, 'HASH', 'body is hashref');
        is($last->{body}{username}, 'renamed', 'username forwarded');
    };

    subtest 'test_delete_sip_endpoint' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->subscribers->delete_sip_endpoint(
            'sub-1', 'ep-1',
        );
        is(ref $body, 'HASH', 'delete returns hashref');

        my $last = MockTest::journal_last();
        is($last->{method}, 'DELETE', 'DELETE recorded');
        is($last->{path},
            '/api/fabric/resources/subscribers/sub-1/sip_endpoints/ep-1',
            'path matches');
        isnt($last->{matched_route}, undef, 'matched_route set');
    };
};

# ---- FabricTokens — every token-creation endpoint ----------------------

subtest 'TestFabricTokens' => sub {
    subtest 'test_create_invite_token' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->tokens->create_invite_token(
            address_id => 'addr-1',
        );
        is(ref $body, 'HASH', 'expected hashref');

        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST recorded');
        # subscriber/invites uses the singular 'subscriber' path segment.
        is($last->{path}, '/api/fabric/subscriber/invites', 'path matches');
        is(ref $last->{body}, 'HASH', 'body is hashref');
        is($last->{body}{address_id}, 'addr-1', 'address_id forwarded');
    };

    subtest 'test_create_embed_token' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->tokens->create_embed_token(
            token => 'embed-tok-1',
        );
        is(ref $body, 'HASH', 'expected hashref');

        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST recorded');
        is($last->{path}, '/api/fabric/embeds/tokens', 'path matches');
        is(ref $last->{body}, 'HASH', 'body is hashref');
        is($last->{body}{token}, 'embed-tok-1', 'token forwarded');
    };

    subtest 'test_refresh_subscriber_token' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->tokens->refresh_subscriber_token(
            refresh_token => 'abc-123',
        );
        is(ref $body, 'HASH', 'expected hashref');

        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST recorded');
        is($last->{path}, '/api/fabric/subscribers/tokens/refresh',
            'path matches');
        is(ref $last->{body}, 'HASH', 'body is hashref');
        is($last->{body}{refresh_token}, 'abc-123', 'refresh_token forwarded');
    };
};

# ---- GenericResources — generic /api/fabric/resources operations -------

subtest 'TestGenericResources' => sub {
    subtest 'test_list_returns_data_collection' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->resources->list();
        is(ref $body, 'HASH', 'expected hashref');
        # /api/fabric/resources returns data array.
        ok(exists $body->{data} && ref $body->{data} eq 'ARRAY',
            'data is arrayref');

        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET recorded');
        is($last->{path}, '/api/fabric/resources', 'path matches');
        isnt($last->{matched_route}, undef, 'matched_route set');
    };

    subtest 'test_get_returns_single_resource' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->resources->get('res-1');
        is(ref $body, 'HASH', 'expected hashref');

        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET recorded');
        is($last->{path}, '/api/fabric/resources/res-1', 'path matches');
    };

    subtest 'test_delete' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->resources->delete('res-2');
        is(ref $body, 'HASH', 'delete returns hashref');

        my $last = MockTest::journal_last();
        is($last->{method}, 'DELETE', 'DELETE recorded');
        is($last->{path}, '/api/fabric/resources/res-2', 'path matches');
        isnt($last->{matched_route}, undef, 'matched_route set');
    };

    subtest 'test_list_addresses' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->resources->list_addresses('res-3');
        is(ref $body, 'HASH', 'expected hashref');
        ok(exists $body->{data} && ref $body->{data} eq 'ARRAY',
            'data is arrayref');

        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET recorded');
        is($last->{path}, '/api/fabric/resources/res-3/addresses',
            'path matches');
    };

    subtest 'test_assign_domain_application' => sub {
        my $client = MockTest::client();
        my $body = $client->fabric->resources->assign_domain_application(
            'res-4', domain_application_id => 'da-7',
        );
        is(ref $body, 'HASH', 'expected hashref');

        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST recorded');
        is($last->{path}, '/api/fabric/resources/res-4/domain_applications',
            'path matches');
        is(ref $last->{body}, 'HASH', 'body is hashref');
        is($last->{body}{domain_application_id}, 'da-7',
            'domain_application_id forwarded');
    };
};

done_testing();
