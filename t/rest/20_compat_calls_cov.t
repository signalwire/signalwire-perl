#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_compat_calls_full_mock.py
#
# Full success + error coverage for $client->compat->calls — the LaML
# (Twilio-compatible) Calls resource and its Recordings / Streams sub-resources.
# Each canonical route gets a SUCCESS test (real SDK call, body shape + journal
# method/path/matched_route) and an ERROR test (scenario_set arms a 4xx/5xx; the
# SDK raises SignalWire::REST::HttpClient::Error with the matching status_code and
# the journal records the route hit with that status).
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

my $BASE = "/api/laml/2010-04-01/Accounts/$MockTest::PROJECT/Calls";

# ---- Success ----

subtest 'test_list_all_calls' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->calls->list();
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{calls}, 'has calls');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, $BASE, 'path');
    is($last->{matched_route}, 'compatibility.list_all_calls', 'matched route');
};

subtest 'test_create_a_call' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->calls->create(To => '+15551112222', From => '+15553334444');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, $BASE, 'path');
    is($last->{matched_route}, 'compatibility.create_a_call', 'matched route');
    is($last->{body}{To}, '+15551112222', 'body To forwarded');
};

subtest 'test_retrieve_a_call' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->calls->get('CA1');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/CA1", 'path');
    is($last->{matched_route}, 'compatibility.retrieve_a_call', 'matched route');
};

subtest 'test_update_a_call' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->calls->update('CA1', Status => 'completed');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, "$BASE/CA1", 'path');
    is($last->{matched_route}, 'compatibility.update_a_call', 'matched route');
    is($last->{body}{Status}, 'completed', 'body Status forwarded');
};

subtest 'test_delete_a_call' => sub {
    my $client = MockTest::client();
    $client->compat->calls->delete_resource('CA1');
    my $last = MockTest::journal_last();
    is($last->{method}, 'DELETE', 'DELETE');
    is($last->{path}, "$BASE/CA1", 'path');
    is($last->{matched_route}, 'compatibility.delete_a_call', 'matched route');
};

subtest 'test_create_recording' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->calls->start_recording('CA1');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, "$BASE/CA1/Recordings", 'path');
    is($last->{matched_route}, 'compatibility.create_recording', 'matched route');
};

subtest 'test_update_recording' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->calls->update_recording('CA1', 'RE1', Status => 'paused');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, "$BASE/CA1/Recordings/RE1", 'path');
    is($last->{matched_route}, 'compatibility.update_recording', 'matched route');
    is($last->{body}{Status}, 'paused', 'body Status forwarded');
};

subtest 'test_create_stream' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->calls->start_stream('CA1', Url => 'wss://a.b/s');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, "$BASE/CA1/Streams", 'path');
    is($last->{matched_route}, 'compatibility.create_stream', 'matched route');
    is($last->{body}{Url}, 'wss://a.b/s', 'body Url forwarded');
};

subtest 'test_update_stream' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->calls->stop_stream('CA1', 'ST1', Status => 'stopped');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, "$BASE/CA1/Streams/ST1", 'path');
    is($last->{matched_route}, 'compatibility.update_stream', 'matched route');
    is($last->{body}{Status}, 'stopped', 'body Status forwarded');
};

# ---- Errors ----

subtest 'test_list_all_calls_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.list_all_calls', 500, { error => 'internal' });
    my $ok = eval { $client->compat->calls->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.list_all_calls', 'matched route');
    is($last->{response_status}, 500, 'journaled 500');
};

subtest 'test_create_a_call_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.create_a_call', 422, { error => 'bad' });
    my $ok = eval { $client->compat->calls->create(To => '+1', From => '+1'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.create_a_call', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

subtest 'test_retrieve_a_call_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.retrieve_a_call', 404, { error => 'not found' });
    my $ok = eval { $client->compat->calls->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.retrieve_a_call', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_a_call_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.update_a_call', 404, { error => 'not found' });
    my $ok = eval { $client->compat->calls->update('missing', Status => 'completed'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.update_a_call', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_a_call_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.delete_a_call', 404, { error => 'not found' });
    my $ok = eval { $client->compat->calls->delete_resource('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.delete_a_call', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_create_recording_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.create_recording', 404, { error => 'not found' });
    my $ok = eval { $client->compat->calls->start_recording('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.create_recording', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_recording_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.update_recording', 404, { error => 'not found' });
    my $ok = eval { $client->compat->calls->update_recording('missing', 'RE1', Status => 'paused'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.update_recording', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_create_stream_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.create_stream', 404, { error => 'not found' });
    my $ok = eval { $client->compat->calls->start_stream('missing', Url => 'wss://a.b/s'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.create_stream', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_stream_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.update_stream', 404, { error => 'not found' });
    my $ok = eval { $client->compat->calls->stop_stream('missing', 'ST1', Status => 'stopped'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.update_stream', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

done_testing();
