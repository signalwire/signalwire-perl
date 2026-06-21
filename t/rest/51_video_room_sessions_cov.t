#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_video_room_sessions_full_mock.py
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

# video.room_sessions is read-only: list / get plus events, members, recordings
# sub-collections at /api/video/room_sessions[/{id}[/{sub}]].

subtest 'TestVideoRoomSessionsSuccess' => sub {
    subtest 'test_list' => sub {
        my $client = MockTest::client();
        my $body = $client->video->room_sessions->list();
        is(ref $body, 'HASH', 'hashref');
        ok(exists $body->{data}, 'data present');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/video/room_sessions', 'path');
        is($last->{matched_route}, 'video.list_room_sessions', 'matched route');
    };

    subtest 'test_get' => sub {
        my $client = MockTest::client();
        my $body = $client->video->room_sessions->get('sess-1');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/video/room_sessions/sess-1', 'path');
        is($last->{matched_route}, 'video.get_room_session', 'matched route');
    };

    subtest 'test_list_events' => sub {
        my $client = MockTest::client();
        my $body = $client->video->room_sessions->list_events('sess-1');
        is(ref $body, 'HASH', 'hashref');
        ok(exists $body->{data}, 'data present');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/video/room_sessions/sess-1/events', 'path');
        is($last->{matched_route}, 'video.list_room_session_events', 'matched route');
    };

    subtest 'test_list_members' => sub {
        my $client = MockTest::client();
        my $body = $client->video->room_sessions->list_members('sess-1');
        is(ref $body, 'HASH', 'hashref');
        ok(exists $body->{data}, 'data present');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/video/room_sessions/sess-1/members', 'path');
        is($last->{matched_route}, 'video.list_room_session_members', 'matched route');
    };

    subtest 'test_list_recordings' => sub {
        my $client = MockTest::client();
        my $body = $client->video->room_sessions->list_recordings('sess-1');
        is(ref $body, 'HASH', 'hashref');
        ok(exists $body->{data}, 'data present');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/video/room_sessions/sess-1/recordings', 'path');
        is($last->{matched_route}, 'video.list_room_session_recordings', 'matched route');
    };
};

subtest 'TestVideoRoomSessionsErrors' => sub {
    subtest 'test_list_server_error' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.list_room_sessions', 500, { error => 'internal' });
        my $ok = eval { $client->video->room_sessions->list(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 500, 'status 500');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.list_room_sessions', 'matched route');
        is($last->{response_status}, 500, 'journaled 500');
    };

    subtest 'test_get_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.get_room_session', 404, { error => 'not found' });
        my $ok = eval { $client->video->room_sessions->get('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.get_room_session', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_list_events_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.list_room_session_events', 404, { error => 'not found' });
        my $ok = eval { $client->video->room_sessions->list_events('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.list_room_session_events', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_list_members_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.list_room_session_members', 404, { error => 'not found' });
        my $ok = eval { $client->video->room_sessions->list_members('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.list_room_session_members', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_list_recordings_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.list_room_session_recordings', 404, { error => 'not found' });
        my $ok = eval { $client->video->room_sessions->list_recordings('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.list_room_session_recordings', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };
};

done_testing();
