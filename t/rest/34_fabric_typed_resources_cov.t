#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_fabric_typed_resources_full_mock.py
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

# Typed fabric resource families that are plain CRUD(+addresses) wrappers.
#  - PUT-update CRUD(+addresses): swml_scripts, relay_applications,
#    freeswitch_connectors, cxml_scripts, sip_endpoints
#  - PATCH-update CRUD(+addresses): cxml_webhooks, swml_webhooks (create warns)
#  - sip_gateways: PATCH CRUD (no addresses route — see GAP)
#  - cxml_applications: read/update(PUT)/delete(+addresses); create dies
#  - call_flows: PUT CRUD + custom call_flow/{id}/addresses|versions
#  - conference_rooms: PUT CRUD + custom conference_room/{id}/addresses
#
# Perl CRUD delete is delete_resource (only GenericResources has a 'delete' alias).

my $BASE = '/api/fabric/resources';
my $ID   = 'rid-1001';

# Drive list/create/get/update/delete (+addresses) and assert each canonical route.
sub crud_success {
    my (%a) = @_;
    my ($rget, $base, $update_method, $prefix, $addresses)
        = @a{qw(rget base update_method prefix addresses)};
    $addresses = 1 unless defined $addresses;

    my $r = $rget->();
    my $body = $r->list();
    ok(ref $body eq 'HASH' || ref $body eq 'ARRAY', "$prefix list shape");
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', "$prefix list GET");
    is($last->{path}, $base, "$prefix list path");
    is($last->{matched_route}, "fabric.list_${prefix}s", "$prefix list route");

    $body = $r->create(name => 'thing');
    is(ref $body, 'HASH', "$prefix create hashref");
    $last = MockTest::journal_last();
    is($last->{method}, 'POST', "$prefix create POST");
    is($last->{path}, $base, "$prefix create path");
    is($last->{matched_route}, "fabric.create_${prefix}", "$prefix create route");
    is($last->{body}{name}, 'thing', "$prefix create body");

    $body = $r->get($ID);
    is(ref $body, 'HASH', "$prefix get hashref");
    $last = MockTest::journal_last();
    is($last->{method}, 'GET', "$prefix get GET");
    is($last->{path}, "$base/$ID", "$prefix get path");
    is($last->{matched_route}, "fabric.get_${prefix}", "$prefix get route");

    $body = $r->update($ID, name => 'renamed');
    is(ref $body, 'HASH', "$prefix update hashref");
    $last = MockTest::journal_last();
    is($last->{method}, $update_method, "$prefix update method");
    is($last->{path}, "$base/$ID", "$prefix update path");
    is($last->{matched_route}, "fabric.update_${prefix}", "$prefix update route");
    is($last->{body}{name}, 'renamed', "$prefix update body");

    $r->delete_resource($ID);
    $last = MockTest::journal_last();
    is($last->{method}, 'DELETE', "$prefix delete DELETE");
    is($last->{path}, "$base/$ID", "$prefix delete path");
    is($last->{matched_route}, "fabric.delete_${prefix}", "$prefix delete route");

    if ($addresses) {
        $body = $r->list_addresses($ID);
        ok(ref $body eq 'HASH' || ref $body eq 'ARRAY', "$prefix addresses shape");
        $last = MockTest::journal_last();
        is($last->{method}, 'GET', "$prefix addresses GET");
        is($last->{path}, "$base/$ID/addresses", "$prefix addresses path");
        is($last->{matched_route}, "fabric.list_${prefix}_addresses", "$prefix addresses route");
    }
}

# Drive a representative error per CRUD route and assert HttpClient::Error.
sub crud_errors {
    my (%a) = @_;
    my ($rget, $prefix, $addresses) = @a{qw(rget prefix addresses)};
    $addresses = 1 unless defined $addresses;

    _err($rget, "fabric.list_${prefix}s", 500, sub { $_[0]->list() });
    _err($rget, "fabric.create_${prefix}", 422, sub { $_[0]->create() });
    _err($rget, "fabric.get_${prefix}", 404, sub { $_[0]->get('missing') });
    _err($rget, "fabric.update_${prefix}", 404, sub { $_[0]->update('missing', name => 'x') });
    _err($rget, "fabric.delete_${prefix}", 404, sub { $_[0]->delete_resource('missing') });
    if ($addresses) {
        _err($rget, "fabric.list_${prefix}_addresses", 404, sub { $_[0]->list_addresses('missing') });
    }
}

# Arm a scenario, invoke, assert it raised with the right status + journaled route.
sub _err {
    my ($rget, $route, $status, $call) = @_;
    my $r = $rget->();
    MockTest::scenario_set($route, $status, { error => 'x' });
    my $ok = eval { $call->($r); 1 };
    my $e = $@;
    ok(!$ok, "$route raised");
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, $status, "$route status $status");
    my $last = MockTest::journal_last();
    is($last->{matched_route}, $route, "$route matched route");
    is($last->{response_status}, $status, "$route journaled $status");
}

subtest 'TestFabricPutResourceFamilies' => sub {
    for my $f (
        ['swml_scripts',         'swml_script'],
        ['relay_applications',   'relay_application'],
        ['freeswitch_connectors','freeswitch_connector'],
        ['cxml_scripts',         'cxml_script'],
        ['sip_endpoints',        'sip_endpoint'],
    ) {
        my ($accessor, $prefix) = @$f;
        subtest "test_$accessor" => sub {
            crud_success(
                rget => sub { MockTest::client()->fabric->$accessor },
                base => "$BASE/$accessor", update_method => 'PUT', prefix => $prefix,
            );
        };
        subtest "test_${accessor}_errors" => sub {
            crud_errors(
                rget => sub { MockTest::client()->fabric->$accessor },
                prefix => $prefix,
            );
        };
    }
};

subtest 'TestFabricPatchResourceFamilies' => sub {
    # cxml_webhooks + swml_webhooks: PATCH CRUD(+addresses); create() carps.
    for my $f (
        ['cxml_webhooks', 'cxml_webhook'],
        ['swml_webhooks', 'swml_webhook'],
    ) {
        my ($accessor, $prefix) = @$f;
        subtest "test_$accessor" => sub {
            # create (deprecation carp swallowed)
            my $client = MockTest::client();
            {
                local $SIG{__WARN__} = sub {};
                $client->fabric->$accessor->create(name => 'thing');
            }
            my $last = MockTest::journal_last();
            is($last->{method}, 'POST', "$prefix create POST");
            is($last->{path}, "$BASE/$accessor", "$prefix create path");
            is($last->{matched_route}, "fabric.create_${prefix}", "$prefix create route");

            # remaining CRUD (list/get/update/delete/addresses)
            $client->fabric->$accessor->list();
            is(MockTest::journal_last()->{matched_route}, "fabric.list_${prefix}s", "$prefix list route");
            $client->fabric->$accessor->get($ID);
            is(MockTest::journal_last()->{matched_route}, "fabric.get_${prefix}", "$prefix get route");
            $client->fabric->$accessor->update($ID, name => 'x');
            $last = MockTest::journal_last();
            is($last->{method}, 'PATCH', "$prefix update PATCH");
            is($last->{matched_route}, "fabric.update_${prefix}", "$prefix update route");
            $client->fabric->$accessor->delete_resource($ID);
            is(MockTest::journal_last()->{matched_route}, "fabric.delete_${prefix}", "$prefix delete route");
            $client->fabric->$accessor->list_addresses($ID);
            is(MockTest::journal_last()->{matched_route}, "fabric.list_${prefix}_addresses", "$prefix addresses route");
        };

        subtest "test_${accessor}_errors" => sub {
            crud_errors(
                rget => sub { MockTest::client()->fabric->$accessor },
                prefix => $prefix,
            );
            # create error (deprecation carp + raise)
            my $r = MockTest::client()->fabric->$accessor;
            MockTest::scenario_set("fabric.create_${prefix}", 422, { error => 'bad' });
            my $ok = eval {
                local $SIG{__WARN__} = sub {};
                $r->create(name => 'thing');
                1;
            };
            my $e = $@;
            ok(!$ok, "$prefix create raised");
            isa_ok($e, 'SignalWire::REST::HttpClient::Error');
            is($e->status_code, 422, "$prefix create status 422");
            my $last = MockTest::journal_last();
            is($last->{matched_route}, "fabric.create_${prefix}", "$prefix create route");
            is($last->{response_status}, 422, "$prefix create journaled 422");
        };
    }
};

subtest 'TestFabricSipGateways' => sub {
    # PATCH CRUD, NO addresses route reachable (accepted GAP per python note).
    subtest 'test_crud' => sub {
        crud_success(
            rget => sub { MockTest::client()->fabric->sip_gateways },
            base => "$BASE/sip_gateways", update_method => 'PATCH',
            prefix => 'sip_gateway', addresses => 0,
        );
    };
    subtest 'test_crud_errors' => sub {
        crud_errors(
            rget => sub { MockTest::client()->fabric->sip_gateways },
            prefix => 'sip_gateway', addresses => 0,
        );
    };
};

subtest 'TestFabricCxmlApplications' => sub {
    # read/update(PUT)/delete(+addresses); create dies (not a canonical route).
    subtest 'test_read_update_delete' => sub {
        my $client = MockTest::client();
        my $r = $client->fabric->cxml_applications;

        my $body = $r->list();
        ok(ref $body eq 'HASH' || ref $body eq 'ARRAY', 'list shape');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'list GET');
        is($last->{path}, "$BASE/cxml_applications", 'list path');
        is($last->{matched_route}, 'fabric.list_cxml_applications', 'list route');

        $r->get($ID);
        $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'get GET');
        is($last->{matched_route}, 'fabric.get_cxml_application', 'get route');

        $r->update($ID, name => 'x');
        $last = MockTest::journal_last();
        is($last->{method}, 'PUT', 'update PUT');
        is($last->{matched_route}, 'fabric.update_cxml_application', 'update route');

        $r->delete_resource($ID);
        $last = MockTest::journal_last();
        is($last->{method}, 'DELETE', 'delete DELETE');
        is($last->{matched_route}, 'fabric.delete_cxml_application', 'delete route');

        $r->list_addresses($ID);
        $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'addresses GET');
        is($last->{matched_route}, 'fabric.list_cxml_application_addresses', 'addresses route');
    };

    subtest 'test_create_not_implemented' => sub {
        my $client = MockTest::client();
        my $ok = eval { $client->fabric->cxml_applications->create(name => 'x'); 1 };
        my $e = $@;
        ok(!$ok, 'create dies');
        like($e, qr/cXML applications cannot/, 'error mentions cXML applications cannot');
    };

    subtest 'test_errors' => sub {
        my $rget = sub { MockTest::client()->fabric->cxml_applications };
        _err($rget, 'fabric.list_cxml_applications', 500, sub { $_[0]->list() });
        _err($rget, 'fabric.get_cxml_application', 404, sub { $_[0]->get('missing') });
        _err($rget, 'fabric.update_cxml_application', 404, sub { $_[0]->update('missing', name => 'x') });
        _err($rget, 'fabric.delete_cxml_application', 404, sub { $_[0]->delete_resource('missing') });
        _err($rget, 'fabric.list_cxml_application_addresses', 404, sub { $_[0]->list_addresses('missing') });
    };
};

subtest 'TestFabricCallFlows' => sub {
    # PUT CRUD + custom call_flow/{id}/addresses|versions (SINGULAR segment).
    subtest 'test_crud' => sub {
        my $client = MockTest::client();
        my $r = $client->fabric->call_flows;
        $r->list();
        is(MockTest::journal_last()->{matched_route}, 'fabric.list_call_flows', 'list route');
        $r->create(name => 'cf');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'create POST');
        is($last->{matched_route}, 'fabric.create_call_flow', 'create route');
        $r->get($ID);
        is(MockTest::journal_last()->{matched_route}, 'fabric.get_call_flow', 'get route');
        $r->update($ID, name => 'x');
        $last = MockTest::journal_last();
        is($last->{method}, 'PUT', 'update PUT');
        is($last->{matched_route}, 'fabric.update_call_flow', 'update route');
        $r->delete_resource($ID);
        is(MockTest::journal_last()->{matched_route}, 'fabric.delete_call_flow', 'delete route');
    };

    subtest 'test_custom_subpaths' => sub {
        my $client = MockTest::client();
        my $r = $client->fabric->call_flows;
        $r->list_addresses($ID);
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'addresses GET');
        is($last->{path}, "$BASE/call_flow/$ID/addresses", 'addresses singular path');
        is($last->{matched_route}, 'fabric.list_call_flow_addresses', 'addresses route');

        $r->list_versions($ID);
        $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'versions GET');
        is($last->{path}, "$BASE/call_flow/$ID/versions", 'versions singular path');
        is($last->{matched_route}, 'fabric.list_call_flow_versions', 'versions route');

        $r->deploy_version($ID, version => 'v2');
        $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'deploy POST');
        is($last->{path}, "$BASE/call_flow/$ID/versions", 'deploy singular path');
        is($last->{matched_route}, 'fabric.deploy_call_flow_version', 'deploy route');
    };

    subtest 'test_errors' => sub {
        my $rget = sub { MockTest::client()->fabric->call_flows };
        _err($rget, 'fabric.list_call_flows', 500, sub { $_[0]->list() });
        _err($rget, 'fabric.create_call_flow', 422, sub { $_[0]->create() });
        _err($rget, 'fabric.get_call_flow', 404, sub { $_[0]->get('missing') });
        _err($rget, 'fabric.update_call_flow', 404, sub { $_[0]->update('missing', name => 'x') });
        _err($rget, 'fabric.delete_call_flow', 404, sub { $_[0]->delete_resource('missing') });
        _err($rget, 'fabric.list_call_flow_addresses', 404, sub { $_[0]->list_addresses('missing') });
        _err($rget, 'fabric.list_call_flow_versions', 404, sub { $_[0]->list_versions('missing') });
        _err($rget, 'fabric.deploy_call_flow_version', 422, sub { $_[0]->deploy_version('missing', version => 'v2') });
    };
};

subtest 'TestFabricConferenceRooms' => sub {
    # PUT CRUD + custom conference_room/{id}/addresses (SINGULAR segment).
    subtest 'test_crud' => sub {
        my $client = MockTest::client();
        my $r = $client->fabric->conference_rooms;
        $r->list();
        is(MockTest::journal_last()->{matched_route}, 'fabric.list_conference_rooms', 'list route');
        $r->create(name => 'room');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'create POST');
        is($last->{matched_route}, 'fabric.create_conference_room', 'create route');
        $r->get($ID);
        is(MockTest::journal_last()->{matched_route}, 'fabric.get_conference_room', 'get route');
        $r->update($ID, name => 'x');
        $last = MockTest::journal_last();
        is($last->{method}, 'PUT', 'update PUT');
        is($last->{matched_route}, 'fabric.update_conference_room', 'update route');
        $r->delete_resource($ID);
        is(MockTest::journal_last()->{matched_route}, 'fabric.delete_conference_room', 'delete route');
    };

    subtest 'test_list_addresses' => sub {
        my $client = MockTest::client();
        $client->fabric->conference_rooms->list_addresses($ID);
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'addresses GET');
        is($last->{path}, "$BASE/conference_room/$ID/addresses", 'addresses singular path');
        is($last->{matched_route}, 'fabric.list_conference_room_addresses', 'addresses route');
    };

    subtest 'test_errors' => sub {
        my $rget = sub { MockTest::client()->fabric->conference_rooms };
        _err($rget, 'fabric.list_conference_rooms', 500, sub { $_[0]->list() });
        _err($rget, 'fabric.create_conference_room', 422, sub { $_[0]->create() });
        _err($rget, 'fabric.get_conference_room', 404, sub { $_[0]->get('missing') });
        _err($rget, 'fabric.update_conference_room', 404, sub { $_[0]->update('missing', name => 'x') });
        _err($rget, 'fabric.delete_conference_room', 404, sub { $_[0]->delete_resource('missing') });
        _err($rget, 'fabric.list_conference_room_addresses', 404, sub { $_[0]->list_addresses('missing') });
    };
};

done_testing();
