#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_video_conferences_full_mock.py
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

# video.conferences is a CRUD resource at /api/video/conferences (PUT update)
# plus conference_tokens / streams sub-collections and create_stream.
# Conferences inherits CrudResource; delete is delete_resource.

subtest 'TestVideoConferencesSuccess' => sub {
    subtest 'test_list' => sub {
        my $client = MockTest::client();
        my $body = $client->video->conferences->list();
        is(ref $body, 'HASH', 'hashref');
        ok(exists $body->{data}, 'data present');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/video/conferences', 'path');
        is($last->{matched_route}, 'video.list_video_conferences', 'matched route');
    };

    subtest 'test_create' => sub {
        my $client = MockTest::client();
        my $body = $client->video->conferences->create(name => 'conf-alpha');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST');
        is($last->{path}, '/api/video/conferences', 'path');
        is($last->{matched_route}, 'video.create_video_conference', 'matched route');
        is($last->{body}{name}, 'conf-alpha', 'name forwarded');
    };

    subtest 'test_get' => sub {
        my $client = MockTest::client();
        my $body = $client->video->conferences->get('conf-1');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/video/conferences/conf-1', 'path');
        is($last->{matched_route}, 'video.get_video_conference', 'matched route');
    };

    subtest 'test_update' => sub {
        my $client = MockTest::client();
        my $body = $client->video->conferences->update('conf-1', name => 'renamed');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'PUT', 'PUT');
        is($last->{path}, '/api/video/conferences/conf-1', 'path');
        is($last->{matched_route}, 'video.update_video_conference', 'matched route');
        is($last->{body}{name}, 'renamed', 'name forwarded');
    };

    subtest 'test_delete' => sub {
        my $client = MockTest::client();
        $client->video->conferences->delete_resource('conf-1');
        my $last = MockTest::journal_last();
        is($last->{method}, 'DELETE', 'DELETE');
        is($last->{path}, '/api/video/conferences/conf-1', 'path');
        is($last->{matched_route}, 'video.delete_video_conference', 'matched route');
    };

    subtest 'test_list_conference_tokens' => sub {
        my $client = MockTest::client();
        my $body = $client->video->conferences->list_conference_tokens('conf-1');
        is(ref $body, 'HASH', 'hashref');
        ok(exists $body->{data}, 'data present');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/video/conferences/conf-1/conference_tokens', 'path');
        is($last->{matched_route}, 'video.list_conference_tokens', 'matched route');
    };

    subtest 'test_list_streams' => sub {
        my $client = MockTest::client();
        my $body = $client->video->conferences->list_streams('conf-1');
        is(ref $body, 'HASH', 'hashref');
        ok(exists $body->{data}, 'data present');
        my $last = MockTest::journal_last();
        is($last->{method}, 'GET', 'GET');
        is($last->{path}, '/api/video/conferences/conf-1/streams', 'path');
        is($last->{matched_route}, 'video.list_conference_streams', 'matched route');
    };

    subtest 'test_create_stream' => sub {
        my $client = MockTest::client();
        my $body = $client->video->conferences->create_stream('conf-1', url => 'rtmp://example.com/live');
        is(ref $body, 'HASH', 'hashref');
        my $last = MockTest::journal_last();
        is($last->{method}, 'POST', 'POST');
        is($last->{path}, '/api/video/conferences/conf-1/streams', 'path');
        is($last->{matched_route}, 'video.create_conference_stream', 'matched route');
        is($last->{body}{url}, 'rtmp://example.com/live', 'url forwarded');
    };
};

subtest 'TestVideoConferencesErrors' => sub {
    subtest 'test_list_server_error' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.list_video_conferences', 500, { error => 'internal' });
        my $ok = eval { $client->video->conferences->list(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 500, 'status 500');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.list_video_conferences', 'matched route');
        is($last->{response_status}, 500, 'journaled 500');
    };

    subtest 'test_create_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.create_video_conference', 422, { error => 'name required' });
        my $ok = eval { $client->video->conferences->create(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.create_video_conference', 'matched route');
        is($last->{response_status}, 422, 'journaled 422');
    };

    subtest 'test_get_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.get_video_conference', 404, { error => 'not found' });
        my $ok = eval { $client->video->conferences->get('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.get_video_conference', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_update_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.update_video_conference', 404, { error => 'not found' });
        my $ok = eval { $client->video->conferences->update('missing', name => 'x'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.update_video_conference', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_delete_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.delete_video_conference', 404, { error => 'not found' });
        my $ok = eval { $client->video->conferences->delete_resource('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.delete_video_conference', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_list_conference_tokens_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.list_conference_tokens', 404, { error => 'not found' });
        my $ok = eval { $client->video->conferences->list_conference_tokens('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.list_conference_tokens', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_list_streams_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.list_conference_streams', 404, { error => 'not found' });
        my $ok = eval { $client->video->conferences->list_streams('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.list_conference_streams', 'matched route');
        is($last->{response_status}, 404, 'journaled 404');
    };

    subtest 'test_create_stream_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('video.create_conference_stream', 422, { error => 'url required' });
        my $ok = eval { $client->video->conferences->create_stream('conf-1'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $last = MockTest::journal_last();
        is($last->{matched_route}, 'video.create_conference_stream', 'matched route');
        is($last->{response_status}, 422, 'journaled 422');
    };
};

done_testing();
