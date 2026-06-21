#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_video_tokens_streams_full_mock.py
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

# video.conference_tokens: get / reset.
# video.streams (top-level): get / update (PUT) / delete. Streams has a
# 'delete' alias.

subtest 'TestVideoConferenceTokensSuccess' => sub {
    subtest 'test_get' => sub {
        my $client = MockTest::client();
        my $body = $client->video->conference_tokens->get('tok-1');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/video/conference_tokens/tok-1', 'path');
        is($last->{matched_route}, 'video.get_conference_token', 'matched route');
    };

    subtest 'test_reset' => sub {
        my $client = MockTest::client();
        my $body = $client->video->conference_tokens->reset('tok-1');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST');
        is($last->{path}, '/api/video/conference_tokens/tok-1/reset', 'path');
        is($last->{matched_route}, 'video.reset_conference_token', 'matched route');
    };
};

subtest 'TestVideoConferenceTokensErrors' => sub {
    subtest 'test_get_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.get_conference_token', 404, { error => 'not found' });
        my $ok = eval { $client->video->conference_tokens->get('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.get_conference_token', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_reset_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.reset_conference_token', 404, { error => 'not found' });
        my $ok = eval { $client->video->conference_tokens->reset('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.reset_conference_token', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };
};

subtest 'TestVideoStreamsSuccess' => sub {
    subtest 'test_get' => sub {
        my $client = MockTest::client();
        my $body = $client->video->streams->get('stream-1');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/video/streams/stream-1', 'path');
        is($last->{matched_route}, 'video.get_stream', 'matched route');
    };

    subtest 'test_update' => sub {
        my $client = MockTest::client();
        my $body = $client->video->streams->update('stream-1', url => 'rtmp://example.com/new');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'PUT', 'PUT');
        is($last->{path}, '/api/video/streams/stream-1', 'path');
        is($last->{matched_route}, 'video.update_stream', 'matched route');
        is($last->{body}{url}, 'rtmp://example.com/new', 'url forwarded');
    };

    subtest 'test_delete' => sub {
        my $client = MockTest::client();
        my $body = $client->video->streams->delete('stream-1');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'DELETE', 'DELETE');
        is($last->{path}, '/api/video/streams/stream-1', 'path');
        is($last->{matched_route}, 'video.delete_stream', 'matched route');
    };
};

subtest 'TestVideoStreamsErrors' => sub {
    subtest 'test_get_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.get_stream', 404, { error => 'not found' });
        my $ok = eval { $client->video->streams->get('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.get_stream', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_update_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.update_stream', 404, { error => 'not found' });
        my $ok = eval { $client->video->streams->update('missing', url => 'x'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.update_stream', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_delete_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.delete_stream', 404, { error => 'not found' });
        my $ok = eval { $client->video->streams->delete('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.delete_stream', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };
};

done_testing();
