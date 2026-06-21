#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_video_rooms_full_mock.py
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

# video.rooms is a CRUD resource at /api/video/rooms (PUT update), plus the
# streams sub-collection (list_streams / create_stream). room_tokens.create
# posts to /api/video/room_tokens.
#
# Perl CRUD delete is delete_resource (Rooms inherits CrudResource which has no
# 'delete' alias). rooms.get hits GET /api/video/rooms/{id} which the router
# resolves to video.get_room_by_name (longer {name} template wins). video.get_room
# is an accepted gap (not independently reachable).

subtest 'TestVideoRoomsSuccess' => sub {
    subtest 'test_list_rooms' => sub {
        my $client = MockTest::client();
        my $body = $client->video->rooms->list();
        is(ref $body, 'HASH', 'hashref');
        ok(exists $body->{data}, 'data present');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/video/rooms', 'path');
        is($last->{matched_route}, 'video.list_rooms', 'matched route');
    };

    subtest 'test_create_room' => sub {
        my $client = MockTest::client();
        my $body = $client->video->rooms->create(name => 'room-alpha');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST');
        is($last->{path}, '/api/video/rooms', 'path');
        is($last->{matched_route}, 'video.create_room', 'matched route');
        is($last->{body}{name}, 'room-alpha', 'name forwarded');
    };

    subtest 'test_get_room_by_name' => sub {
        my $client = MockTest::client();
        my $body = $client->video->rooms->get('room-1001');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/video/rooms/room-1001', 'path');
        is($last->{matched_route}, 'video.get_room_by_name', 'matched route');
    };

    subtest 'test_update_room' => sub {
        my $client = MockTest::client();
        my $body = $client->video->rooms->update('room-1001', display_name => 'renamed');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'PUT', 'PUT');
        is($last->{path}, '/api/video/rooms/room-1001', 'path');
        is($last->{matched_route}, 'video.update_room', 'matched route');
        is($last->{body}{display_name}, 'renamed', 'display_name forwarded');
    };

    subtest 'test_delete_room' => sub {
        my $client = MockTest::client();
        $client->video->rooms->delete_resource('room-1001');
        my $last = MockTest::journal_last();
        is($last->{method}, 'DELETE', 'DELETE');
        is($last->{path}, '/api/video/rooms/room-1001', 'path');
        is($last->{matched_route}, 'video.delete_room', 'matched route');
    };

    subtest 'test_list_room_streams' => sub {
        my $client = MockTest::client();
        my $body = $client->video->rooms->list_streams('room-1001');
        is(ref $body, 'HASH', 'hashref');
        ok(exists $body->{data}, 'data present');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/video/rooms/room-1001/streams', 'path');
        is($last->{matched_route}, 'video.list_room_streams', 'matched route');
    };

    subtest 'test_create_room_stream' => sub {
        my $client = MockTest::client();
        my $body = $client->video->rooms->create_stream('room-1001', url => 'rtmp://example.com/live');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST');
        is($last->{path}, '/api/video/rooms/room-1001/streams', 'path');
        is($last->{matched_route}, 'video.create_room_stream', 'matched route');
        is($last->{body}{url}, 'rtmp://example.com/live', 'url forwarded');
    };

    subtest 'test_create_room_token' => sub {
        my $client = MockTest::client();
        my $body = $client->video->room_tokens->create(room_name => 'room-alpha');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST');
        is($last->{path}, '/api/video/room_tokens', 'path');
        is($last->{matched_route}, 'video.create_room_token', 'matched route');
        is($last->{body}{room_name}, 'room-alpha', 'room_name forwarded');
    };
};

subtest 'TestVideoRoomsErrors' => sub {
    subtest 'test_list_rooms_server_error' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.list_rooms', 500, { error => 'internal' });
        my $ok = eval { $client->video->rooms->list(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 500, 'status 500');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.list_rooms', 'matched route');
        is($last->{response_status}, 500, 'journaled 500');
    };

    subtest 'test_create_room_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.create_room', 422, { error => 'name required' });
        my $ok = eval { $client->video->rooms->create(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.create_room', 'matched route');
        is($last->{response_status}, 422, 'journaled 422');
    };

    subtest 'test_get_room_by_name_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.get_room_by_name', 404, { error => 'not found' });
        my $ok = eval { $client->video->rooms->get('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.get_room_by_name', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_update_room_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.update_room', 404, { error => 'not found' });
        my $ok = eval { $client->video->rooms->update('missing', display_name => 'x'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.update_room', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_delete_room_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.delete_room', 404, { error => 'not found' });
        my $ok = eval { $client->video->rooms->delete_resource('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.delete_room', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_list_room_streams_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.list_room_streams', 404, { error => 'not found' });
        my $ok = eval { $client->video->rooms->list_streams('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.list_room_streams', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_create_room_stream_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.create_room_stream', 422, { error => 'url required' });
        my $ok = eval { $client->video->rooms->create_stream('room-1001'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.create_room_stream', 'matched route');
        is($last->{response_status}, 422, 'journaled 422');
    };

    subtest 'test_create_room_token_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.create_room_token', 422, { error => 'room_name required' });
        my $ok = eval { $client->video->room_tokens->create(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.create_room_token', 'matched route');
        is($last->{response_status}, 422, 'journaled 422');
    };
};

done_testing();
