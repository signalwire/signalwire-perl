#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use SignalWire::REST::RestClient;

# The Fabric namespace + its sub-resources come from the GENERATED resource tree
# (scripts/generate_rest.py). Each sub-resource is its own generated class named
# verbatim after the spec's x-sdk-resource.name.
my $client = SignalWire::REST::RestClient->new(
    project => 'p', token => 't', host => 'h',
);

subtest 'fabric namespace' => sub {
    my $f = $client->fabric;
    isa_ok($f, 'SignalWire::REST::Namespaces::Generated::FabricNamespace');
};

subtest 'swml_scripts' => sub {
    isa_ok($client->fabric->swml_scripts, 'SignalWire::REST::Namespaces::Generated::SwmlScripts');
};

subtest 'relay_applications' => sub {
    isa_ok($client->fabric->relay_applications, 'SignalWire::REST::Namespaces::Generated::RelayApplications');
};

subtest 'call_flows' => sub {
    my $cf = $client->fabric->call_flows;
    isa_ok($cf, 'SignalWire::REST::Namespaces::Generated::CallFlows');
    ok($cf->can('list_versions'),  'list_versions');
    ok($cf->can('deploy_version'), 'deploy_version');
};

subtest 'conference_rooms' => sub {
    isa_ok($client->fabric->conference_rooms, 'SignalWire::REST::Namespaces::Generated::ConferenceRooms');
};

subtest 'subscribers' => sub {
    my $s = $client->fabric->subscribers;
    isa_ok($s, 'SignalWire::REST::Namespaces::Generated::Subscribers');
    ok($s->can('list_sip_endpoints'),  'list_sip_endpoints');
    ok($s->can('create_sip_endpoint'), 'create_sip_endpoint');
};

subtest 'sip_endpoints' => sub {
    isa_ok($client->fabric->sip_endpoints, 'SignalWire::REST::Namespaces::Generated::SipEndpoints');
};

subtest 'cxml resources' => sub {
    isa_ok($client->fabric->cxml_scripts, 'SignalWire::REST::Namespaces::Generated::CxmlScripts');
    my $ca = $client->fabric->cxml_applications;
    isa_ok($ca, 'SignalWire::REST::Namespaces::Generated::CxmlApplications');
    # cXML applications cannot be created via the API — the generated class is a
    # BaseResource with list/get/update/delete/list_addresses but NO create.
    ok(!$ca->can('create'), 'cxml_applications has no create method');
    ok($ca->can('update'),  'cxml_applications has update');
    ok($ca->can('delete'),  'cxml_applications has delete');
};

subtest 'fabric resources' => sub {
    isa_ok($client->fabric->swml_webhooks, 'SignalWire::REST::Namespaces::Generated::SwmlWebhooks');
    isa_ok($client->fabric->ai_agents,     'SignalWire::REST::Namespaces::Generated::AiAgents');
    isa_ok($client->fabric->sip_gateways,  'SignalWire::REST::Namespaces::Generated::SipGateways');
    isa_ok($client->fabric->cxml_webhooks, 'SignalWire::REST::Namespaces::Generated::CxmlWebhooks');
    isa_ok($client->fabric->freeswitch_connectors,
        'SignalWire::REST::Namespaces::Generated::FreeswitchConnectors');
};

subtest 'addresses and tokens' => sub {
    isa_ok($client->fabric->addresses, 'SignalWire::REST::Namespaces::Generated::FabricAddresses');
    my $tokens = $client->fabric->tokens;
    isa_ok($tokens, 'SignalWire::REST::Namespaces::Generated::FabricTokens');
    ok($tokens->can('create_subscriber_token'), 'subscriber token');
    ok($tokens->can('create_guest_token'),      'guest token');
    ok($tokens->can('create_embed_token'),      'embed token');
};

subtest 'resources' => sub {
    my $r = $client->fabric->resources;
    isa_ok($r, 'SignalWire::REST::Namespaces::Generated::GenericResources');
    ok($r->can('assign_phone_route'),        'assign_phone_route');
    ok($r->can('assign_domain_application'), 'assign_domain_application');
};

done_testing;
