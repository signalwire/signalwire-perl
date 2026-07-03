#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# ===== HttpClient =====
use_ok('SignalWire::REST::HttpClient');

# HttpClient construction
{
    my $http = SignalWire::REST::HttpClient->new(
        project => 'proj-123',
        token   => 'tok-abc',
        host    => 'example.signalwire.com',
    );
    is($http->project, 'proj-123', 'http project');
    is($http->token, 'tok-abc', 'http token');
    is($http->host, 'example.signalwire.com', 'http host');
    is($http->base_url, 'https://example.signalwire.com', 'base_url built');
}

# Auth header
{
    my $http = SignalWire::REST::HttpClient->new(
        project => 'user',
        token   => 'pass',
        host    => 'test.host',
    );
    use MIME::Base64 qw(encode_base64);
    my $expected = 'Basic ' . encode_base64('user:pass', '');
    is($http->_auth_header, $expected, 'auth header correct');
}

# HttpClient Error class
{
    my $err = SignalWire::REST::HttpClient::Error->new(
        status_code => 404,
        body        => 'Not Found',
        url         => '/api/test',
        method      => 'GET',
    );
    is($err->status_code, 404, 'error status_code');
    is($err->url, '/api/test', 'error url');
    is($err->method, 'GET', 'error method');
    like("$err", qr/GET.*404.*Not Found/, 'error stringification');
}

# HttpClient Error with hash body
{
    my $err = SignalWire::REST::HttpClient::Error->new(
        status_code => 422,
        body        => { errors => ['invalid'] },
        url         => '/api/resource',
        method      => 'POST',
    );
    like("$err", qr/POST.*422/, 'error with hash body stringifies');
}

# HttpClient has all HTTP methods
{
    my $http = SignalWire::REST::HttpClient->new(
        project => 'p', token => 't', host => 'h',
    );
    ok($http->can('get'), 'has get');
    ok($http->can('post'), 'has post');
    ok($http->can('put'), 'has put');
    ok($http->can('patch'), 'has patch');
    ok($http->can('delete_request'), 'has delete_request');
}

# ===== Base namespace =====
use_ok('SignalWire::REST::Namespaces::Base');

# Base construction
{
    my $http_mock = bless {}, 'MockHttp';
    my $base = SignalWire::REST::Namespaces::Base->new(
        _http      => $http_mock,
        _base_path => '/api/test',
    );
    is($base->_base_path, '/api/test', 'base_path set');
    is($base->_path('foo', 'bar'), '/api/test/foo/bar', '_path joins correctly');
}

# CrudResource construction
{
    my $http_mock = bless {}, 'MockHttp';
    my $crud = SignalWire::REST::Namespaces::CrudResource->new(
        _http      => $http_mock,
        _base_path => '/api/crud',
    );
    is($crud->_update_method, 'PATCH', 'default update method is PATCH');
    ok($crud->can('list'), 'has list');
    ok($crud->can('create'), 'has create');
    ok($crud->can('get'), 'has get');
    ok($crud->can('update'), 'has update');
    ok($crud->can('delete_resource'), 'has delete_resource');
}

# ===== RestClient =====
use_ok('SignalWire::REST::RestClient');

# Client construction
{
    my $client = SignalWire::REST::RestClient->new(
        project => 'proj-test',
        token   => 'tok-test',
        host    => 'test.signalwire.com',
    );
    is($client->_project_id, 'proj-test', 'client project credential');
    is($client->token, 'tok-test', 'client token');
    is($client->host, 'test.signalwire.com', 'client host');
}

# Client _http is lazily built
{
    my $client = SignalWire::REST::RestClient->new(
        project => 'p', token => 't', host => 'h',
    );
    my $http = $client->_http;
    isa_ok($http, 'SignalWire::REST::HttpClient');
    is($http->project, 'p', '_http has correct project');
}

# All 21 namespaces are accessible
{
    my $client = SignalWire::REST::RestClient->new(
        project => 'p', token => 't', host => 'h',
    );

    # The flat resources + namespace containers come from the GENERATED
    # ResourceTree role the client composes.
    isa_ok($client->fabric, 'SignalWire::REST::Namespaces::Generated::FabricNamespace');
    isa_ok($client->calling, 'SignalWire::REST::Namespaces::Generated::Calling');
    isa_ok($client->phone_numbers, 'SignalWire::REST::Namespaces::Generated::PhoneNumbers');
    isa_ok($client->addresses, 'SignalWire::REST::Namespaces::Generated::Addresses');
    isa_ok($client->queues, 'SignalWire::REST::Namespaces::Generated::Queues');
    isa_ok($client->recordings, 'SignalWire::REST::Namespaces::Generated::Recordings');
    isa_ok($client->number_groups, 'SignalWire::REST::Namespaces::Generated::NumberGroups');
    isa_ok($client->verified_callers, 'SignalWire::REST::Namespaces::Generated::VerifiedCallers');
    isa_ok($client->sip_profile, 'SignalWire::REST::Namespaces::Generated::SipProfile');
    isa_ok($client->lookup, 'SignalWire::REST::Namespaces::Generated::Lookup');
    isa_ok($client->short_codes, 'SignalWire::REST::Namespaces::Generated::ShortCodes');
    isa_ok($client->imported_numbers, 'SignalWire::REST::Namespaces::Generated::ImportedNumbers');
    isa_ok($client->mfa, 'SignalWire::REST::Namespaces::Generated::Mfa');
    isa_ok($client->registry, 'SignalWire::REST::Namespaces::Generated::RegistryNamespace');
    isa_ok($client->datasphere, 'SignalWire::REST::Namespaces::Generated::DatasphereNamespace');
    isa_ok($client->video, 'SignalWire::REST::Namespaces::Generated::VideoNamespace');
    isa_ok($client->logs, 'SignalWire::REST::Namespaces::Generated::LogsNamespace');
    isa_ok($client->project, 'SignalWire::REST::Namespaces::Generated::ProjectNamespace');
    isa_ok($client->pubsub, 'SignalWire::REST::Namespaces::Generated::PubSub');
    isa_ok($client->chat, 'SignalWire::REST::Namespaces::Generated::Chat');
}

# ===== Fabric Namespace sub-objects =====
{
    my $client = SignalWire::REST::RestClient->new(
        project => 'p', token => 't', host => 'h',
    );
    my $f = $client->fabric;

    # All fabric sub-resources (generated classes, verbatim spec names)
    isa_ok($f->swml_scripts, 'SignalWire::REST::Namespaces::Generated::SwmlScripts');
    isa_ok($f->relay_applications, 'SignalWire::REST::Namespaces::Generated::RelayApplications');
    isa_ok($f->call_flows, 'SignalWire::REST::Namespaces::Generated::CallFlows');
    isa_ok($f->conference_rooms, 'SignalWire::REST::Namespaces::Generated::ConferenceRooms');
    isa_ok($f->freeswitch_connectors, 'SignalWire::REST::Namespaces::Generated::FreeswitchConnectors');
    isa_ok($f->subscribers, 'SignalWire::REST::Namespaces::Generated::Subscribers');
    isa_ok($f->sip_endpoints, 'SignalWire::REST::Namespaces::Generated::SipEndpoints');
    isa_ok($f->cxml_scripts, 'SignalWire::REST::Namespaces::Generated::CxmlScripts');
    isa_ok($f->cxml_applications, 'SignalWire::REST::Namespaces::Generated::CxmlApplications');
    isa_ok($f->swml_webhooks, 'SignalWire::REST::Namespaces::Generated::SwmlWebhooks');
    isa_ok($f->ai_agents, 'SignalWire::REST::Namespaces::Generated::AiAgents');
    isa_ok($f->sip_gateways, 'SignalWire::REST::Namespaces::Generated::SipGateways');
    isa_ok($f->cxml_webhooks, 'SignalWire::REST::Namespaces::Generated::CxmlWebhooks');
    isa_ok($f->resources, 'SignalWire::REST::Namespaces::Generated::GenericResources');
    isa_ok($f->addresses, 'SignalWire::REST::Namespaces::Generated::FabricAddresses');
    isa_ok($f->tokens, 'SignalWire::REST::Namespaces::Generated::FabricTokens');

    # CallFlows has version methods
    ok($f->call_flows->can('list_versions'), 'call_flows has list_versions');
    ok($f->call_flows->can('deploy_version'), 'call_flows has deploy_version');

    # Subscribers has SIP endpoint methods
    ok($f->subscribers->can('list_sip_endpoints'), 'subscribers has list_sip_endpoints');
    ok($f->subscribers->can('create_sip_endpoint'), 'subscribers has create_sip_endpoint');

    # CxmlApplications is a BaseResource with NO create (cXML apps can't be created
    # via the API) — the generated class simply doesn't provide the method.
    ok(!$f->cxml_applications->can('create'), 'cxml_applications has no create');
    ok($f->cxml_applications->can('update'), 'cxml_applications has update');

    # Tokens has methods
    ok($f->tokens->can('create_subscriber_token'), 'tokens has create_subscriber_token');
    ok($f->tokens->can('create_guest_token'), 'tokens has create_guest_token');
    ok($f->tokens->can('create_embed_token'), 'tokens has create_embed_token');
}

# ===== Calling Namespace =====
{
    my $client = SignalWire::REST::RestClient->new(
        project => 'p', token => 't', host => 'h',
    );
    my $c = $client->calling;

    # Has all command methods
    my @methods = qw(
        dial update end transfer disconnect
        play play_pause play_resume play_stop play_volume
        record record_pause record_resume record_stop
        collect collect_stop collect_start_input_timers
        detect detect_stop
        tap tap_stop
        stream stream_stop
        denoise denoise_stop
        transcribe transcribe_stop
        ai_message ai_hold ai_unhold ai_stop
        live_transcribe live_translate
        send_fax_stop receive_fax_stop
        refer user_event
    );
    for my $method (@methods) {
        ok($c->can($method), "calling has method: $method");
    }
}

# ===== Datasphere Namespace =====
{
    my $client = SignalWire::REST::RestClient->new(
        project => 'p', token => 't', host => 'h',
    );
    my $ds = $client->datasphere;
    isa_ok($ds->documents, 'SignalWire::REST::Namespaces::Generated::DatasphereDocuments');
    ok($ds->documents->can('search'), 'documents has search');
    ok($ds->documents->can('list_chunks'), 'documents has list_chunks');
    ok($ds->documents->can('get_chunk'), 'documents has get_chunk');
    ok($ds->documents->can('delete_chunk'), 'documents has delete_chunk');
}

# ===== Video Namespace =====
{
    my $client = SignalWire::REST::RestClient->new(
        project => 'p', token => 't', host => 'h',
    );
    my $v = $client->video;

    isa_ok($v->rooms, 'SignalWire::REST::Namespaces::Generated::VideoRooms');
    isa_ok($v->room_tokens, 'SignalWire::REST::Namespaces::Generated::VideoRoomTokens');
    isa_ok($v->room_sessions, 'SignalWire::REST::Namespaces::Generated::VideoRoomSessions');
    isa_ok($v->room_recordings, 'SignalWire::REST::Namespaces::Generated::VideoRoomRecordings');
    isa_ok($v->conferences, 'SignalWire::REST::Namespaces::Generated::VideoConferences');
    isa_ok($v->conference_tokens, 'SignalWire::REST::Namespaces::Generated::VideoConferenceTokens');
    isa_ok($v->streams, 'SignalWire::REST::Namespaces::Generated::VideoStreams');

    ok($v->rooms->can('list_streams'), 'rooms has list_streams');
    ok($v->rooms->can('create_stream'), 'rooms has create_stream');
    ok($v->room_sessions->can('list_events'), 'room_sessions has list_events');
    ok($v->room_sessions->can('list_members'), 'room_sessions has list_members');
}

# ===== Registry Namespace =====
{
    my $client = SignalWire::REST::RestClient->new(
        project => 'p', token => 't', host => 'h',
    );
    my $r = $client->registry;

    isa_ok($r->brands, 'SignalWire::REST::Namespaces::Generated::RegistryBrands');
    isa_ok($r->campaigns, 'SignalWire::REST::Namespaces::Generated::RegistryCampaigns');
    isa_ok($r->orders, 'SignalWire::REST::Namespaces::Generated::RegistryOrders');
    isa_ok($r->numbers, 'SignalWire::REST::Namespaces::Generated::RegistryNumbers');

    ok($r->brands->can('list_campaigns'), 'brands has list_campaigns');
    ok($r->brands->can('create_campaign'), 'brands has create_campaign');
    ok($r->campaigns->can('list_orders'), 'campaigns has list_orders');
    ok($r->campaigns->can('create_order'), 'campaigns has create_order');
}

# ===== Logs Namespace =====
{
    my $client = SignalWire::REST::RestClient->new(
        project => 'p', token => 't', host => 'h',
    );
    my $l = $client->logs;

    isa_ok($l->messages, 'SignalWire::REST::Namespaces::Generated::MessageLogs');
    isa_ok($l->voice, 'SignalWire::REST::Namespaces::Generated::VoiceLogs');
    isa_ok($l->fax, 'SignalWire::REST::Namespaces::Generated::FaxLogs');
    isa_ok($l->conferences, 'SignalWire::REST::Namespaces::Generated::ConferenceLogs');

    ok($l->voice->can('list_events'), 'voice logs has list_events');
}

# ===== Project Namespace =====
{
    my $client = SignalWire::REST::RestClient->new(
        project => 'p', token => 't', host => 'h',
    );
    my $p = $client->project;
    isa_ok($p->tokens, 'SignalWire::REST::Namespaces::Generated::ProjectTokens');
    ok($p->tokens->can('create'), 'project tokens has create');
    ok($p->tokens->can('update'), 'project tokens has update');
    ok($p->tokens->can('delete'), 'project tokens has delete');
}

# ===== PubSub and Chat =====
{
    my $client = SignalWire::REST::RestClient->new(
        project => 'p', token => 't', host => 'h',
    );
    ok($client->pubsub->can('create_token'), 'pubsub has create_token');
    ok($client->chat->can('create_token'), 'chat has create_token');
}

# ===== Relay REST Resources =====
{
    my $client = SignalWire::REST::RestClient->new(
        project => 'p', token => 't', host => 'h',
    );

    # PhoneNumbers has search
    ok($client->phone_numbers->can('search'), 'phone_numbers has search');

    # Queues has member methods
    ok($client->queues->can('list_members'), 'queues has list_members');
    ok($client->queues->can('get_next_member'), 'queues has get_next_member');

    # NumberGroups has membership
    ok($client->number_groups->can('list_memberships'), 'number_groups has list_memberships');

    # VerifiedCallers has verification flow
    ok($client->verified_callers->can('redial_verification'), 'verified_callers has redial_verification');
    ok($client->verified_callers->can('submit_verification'), 'verified_callers has submit_verification');

    # SipProfile singleton
    ok($client->sip_profile->can('get'), 'sip_profile has get');
    ok($client->sip_profile->can('update'), 'sip_profile has update');

    # Lookup
    ok($client->lookup->can('phone_number'), 'lookup has phone_number');

    # MFA
    ok($client->mfa->can('sms'), 'mfa has sms');
    ok($client->mfa->can('call'), 'mfa has call');
    ok($client->mfa->can('verify'), 'mfa has verify');

    # ImportedNumbers
    ok($client->imported_numbers->can('create'), 'imported_numbers has create');
}

# ===== Base path verification =====
{
    my $client = SignalWire::REST::RestClient->new(
        project => 'p', token => 't', host => 'h',
    );

    # Spot-check key base paths
    is($client->calling->_base_path, '/api/calling/calls', 'calling base path');
    is($client->phone_numbers->_base_path, '/api/relay/rest/phone_numbers', 'phone_numbers base path');
    is($client->pubsub->_base_path, '/api/pubsub/tokens', 'pubsub base path');
    is($client->chat->_base_path, '/api/chat/tokens', 'chat base path');
}

done_testing();

# Minimal mock for tests that don't call HTTP
package MockHttp;
sub new { bless {}, shift }

1;
