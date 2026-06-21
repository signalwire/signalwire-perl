#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_video_room_recordings_full_mock.py
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

# video.room_recordings is the top-level recordings collection: list / get /
# delete plus the events sub-collection. RoomRecordings has a 'delete' alias.

subtest 'TestVideoRoomRecordingsSuccess' => sub {
    subtest 'test_list' => sub {
        my $client = MockTest::client();
        my $body = $client->video->room_recordings->list();
        is(ref $body, 'HASH', 'hashref');
        ok(exists $body->{data}, 'data present');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/video/room_recordings', 'path');
        is($last->{matched_route}, 'video.list_room_recordings', 'matched route');
    };

    subtest 'test_get' => sub {
        my $client = MockTest::client();
        my $body = $client->video->room_recordings->get('rec-1');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/video/room_recordings/rec-1', 'path');
        is($last->{matched_route}, 'video.get_room_recording', 'matched route');
    };

    subtest 'test_delete' => sub {
        my $client = MockTest::client();
        my $body = $client->video->room_recordings->delete('rec-1');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'DELETE', 'DELETE');
        is($last->{path}, '/api/video/room_recordings/rec-1', 'path');
        is($last->{matched_route}, 'video.delete_room_recording', 'matched route');
    };

    subtest 'test_list_events' => sub {
        my $client = MockTest::client();
        my $body = $client->video->room_recordings->list_events('rec-1');
        is(ref $body, 'HASH', 'hashref');
        ok(exists $body->{data}, 'data present');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/video/room_recordings/rec-1/events', 'path');
        is($last->{matched_route}, 'video.list_room_recording_events', 'matched route');
    };
};

subtest 'TestVideoRoomRecordingsErrors' => sub {
    subtest 'test_list_server_error' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.list_room_recordings', 500, { error => 'internal' });
        my $ok = eval { $client->video->room_recordings->list(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 500, 'status 500');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.list_room_recordings', 'matched route');
        is($last->{response_status}, 500, 'journaled 500');
    };

    subtest 'test_get_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.get_room_recording', 404, { error => 'not found' });
        my $ok = eval { $client->video->room_recordings->get('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.get_room_recording', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_delete_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.delete_room_recording', 404, { error => 'not found' });
        my $ok = eval { $client->video->room_recordings->delete('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.delete_room_recording', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_list_events_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.list_room_recording_events', 404, { error => 'not found' });
        my $ok = eval { $client->video->room_recordings->list_events('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.list_room_recording_events', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };
};

done_testing();
