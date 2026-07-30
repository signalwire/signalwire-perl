#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use SignalWire::REST::RestClient;

my $client = SignalWire::REST::RestClient->new(
    project => 'p',
    token   => 't',
    host    => 'h',
);

# ============================================================
# 1. All 21 namespaces accessible
# ============================================================
subtest 'all namespaces' => sub {
    my @ns = qw(fabric calling phone_numbers addresses queues recordings
        number_groups verified_callers sip_profile lookup short_codes
        imported_numbers mfa registry datasphere video logs
        project pubsub chat);
    for my $ns (@ns) {
        ok( $client->can($ns), "client has $ns accessor" );
        my $obj = $client->$ns;
        ok( defined $obj, "$ns returns object" );
    }
};

# ============================================================
# 2. Datasphere sub-resources
# ============================================================
subtest 'datasphere documents' => sub {
    my $ds   = $client->datasphere;
    my $docs = $ds->documents;
    isa_ok( $docs, 'SignalWire::REST::Namespaces::Generated::DatasphereDocuments' );
    for my $m (qw(search list_chunks get_chunk delete_chunk)) {
        ok( $docs->can($m), "documents has $m" );
    }
};

# ============================================================
# 3. Video sub-resources
# ============================================================
subtest 'video sub-resources' => sub {
    my $v = $client->video;
    isa_ok( $v->rooms,           'SignalWire::REST::Namespaces::Generated::VideoRooms' );
    isa_ok( $v->room_tokens,     'SignalWire::REST::Namespaces::Generated::VideoRoomTokens' );
    isa_ok( $v->room_sessions,   'SignalWire::REST::Namespaces::Generated::VideoRoomSessions' );
    isa_ok( $v->room_recordings, 'SignalWire::REST::Namespaces::Generated::VideoRoomRecordings' );
    isa_ok( $v->conferences,     'SignalWire::REST::Namespaces::Generated::VideoConferences' );
    isa_ok( $v->conference_tokens,
        'SignalWire::REST::Namespaces::Generated::VideoConferenceTokens' );
    isa_ok( $v->streams, 'SignalWire::REST::Namespaces::Generated::VideoStreams' );
    ok( $v->rooms->can('list_streams'),        'rooms has list_streams' );
    ok( $v->room_sessions->can('list_events'), 'sessions has list_events' );
};

# ============================================================
# 6. Registry namespace
# ============================================================
subtest 'registry namespace' => sub {
    my $r = $client->registry;
    for my $sub (qw(brands campaigns orders numbers)) {
        ok( $r->can($sub), "registry has $sub" );
    }
    ok( $r->brands->can('list_campaigns'), 'brands list_campaigns' );
    ok( $r->campaigns->can('list_orders'), 'campaigns list_orders' );
};

# ============================================================
# 7. Logs namespace
# ============================================================
subtest 'logs namespace' => sub {
    my $l = $client->logs;
    for my $sub (qw(messages voice fax conferences)) {
        ok( $l->can($sub), "logs has $sub" );
    }
    ok( $l->voice->can('list_events'), 'voice list_events' );
};

# ============================================================
# 8. Project namespace
# ============================================================
subtest 'project namespace' => sub {
    my $p      = $client->project;
    my $tokens = $p->tokens;
    for my $m (qw(create update delete)) {
        ok( $tokens->can($m), "project tokens has $m" );
    }
};

# ============================================================
# 9. PubSub and Chat
# ============================================================
subtest 'pubsub and chat' => sub {
    ok( $client->pubsub->can('create_token'), 'pubsub create_token' );
    ok( $client->chat->can('create_token'),   'chat create_token' );
};

# ============================================================
# 10. Base paths
# ============================================================
subtest 'base paths' => sub {
    is( $client->calling->_base_path,       '/api/calling/calls',            'calling path' );
    is( $client->phone_numbers->_base_path, '/api/relay/rest/phone_numbers', 'phone_numbers path' );
    is( $client->pubsub->_base_path,        '/api/pubsub/tokens',            'pubsub path' );
    is( $client->chat->_base_path,          '/api/chat/tokens',              'chat path' );
};

# ============================================================
# 11. Relay REST resources methods
# ============================================================
subtest 'relay REST resource methods' => sub {
    ok( $client->phone_numbers->can('search'),            'phone_numbers search' );
    ok( $client->queues->can('list_members'),             'queues list_members' );
    ok( $client->queues->can('get_next_member'),          'queues get_next_member' );
    ok( $client->number_groups->can('list_memberships'),  'number_groups list_memberships' );
    ok( $client->number_groups->can('add_membership'),    'number_groups add_membership' );
    ok( $client->number_groups->can('get_membership'),    'number_groups get_membership' );
    ok( $client->number_groups->can('delete_membership'), 'number_groups delete_membership' );
    ok( $client->verified_callers->can('redial_verification'),
        'verified_callers redial_verification' );
    ok( $client->sip_profile->can('get'),     'sip_profile get' );
    ok( $client->lookup->can('phone_number'), 'lookup phone_number' );
    ok( $client->mfa->can('sms'),             'mfa sms' );
    ok( $client->mfa->can('verify'),          'mfa verify' );
};

done_testing;
