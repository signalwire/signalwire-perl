#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_compat_conferences_full_mock.py
#
# Each canonical compatibility Conferences route gets BOTH a success (2xx) test
# and an error (4xx/5xx) test, asserting the on-the-wire method/path and the
# journaled matched_route + response_status.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

my $CONF = "/api/laml/2010-04-01/Accounts/$MockTest::PROJECT/Conferences";

# ---------------------------------------------------------------- success ----

subtest 'test_list_all_conferences' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->conferences->list();
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{conferences}, 'conferences key');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, $CONF, 'path');
    is($j->{matched_route}, 'compatibility.list_all_conferences', 'matched route');
};

subtest 'test_retrieve_conference' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->conferences->get('CF1');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, "$CONF/CF1", 'path');
    is($j->{matched_route}, 'compatibility.retrieve_conference', 'matched route');
};

subtest 'test_update_conference' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->conferences->update('CF1', Status => 'completed');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'POST', 'POST');
    is($j->{path}, "$CONF/CF1", 'path');
    is($j->{matched_route}, 'compatibility.update_conference', 'matched route');
    is($j->{body}{Status}, 'completed', 'Status forwarded');
};

subtest 'test_list_all_participants' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->conferences->list_participants('CF1');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{participants}, 'participants key');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, "$CONF/CF1/Participants", 'path');
    is($j->{matched_route}, 'compatibility.list_all_participants', 'matched route');
};

subtest 'test_retrieve_participant' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->conferences->get_participant('CF1', 'CA1');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, "$CONF/CF1/Participants/CA1", 'path');
    is($j->{matched_route}, 'compatibility.retrieve_participant', 'matched route');
};

subtest 'test_update_participant' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->conferences->update_participant('CF1', 'CA1', Muted => 'true');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'POST', 'POST');
    is($j->{path}, "$CONF/CF1/Participants/CA1", 'path');
    is($j->{matched_route}, 'compatibility.update_participant', 'matched route');
    is($j->{body}{Muted}, 'true', 'Muted forwarded');
};

subtest 'test_delete_participant' => sub {
    my $client = MockTest::client();
    $client->compat->conferences->remove_participant('CF1', 'CA1');
    my $j = MockTest::journal_last();
    is($j->{method}, 'DELETE', 'DELETE');
    is($j->{path}, "$CONF/CF1/Participants/CA1", 'path');
    is($j->{matched_route}, 'compatibility.delete_participant', 'matched route');
};

subtest 'test_list_conference_recordings' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->conferences->list_recordings('CF1');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{recordings}, 'recordings key');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, "$CONF/CF1/Recordings", 'path');
    is($j->{matched_route}, 'compatibility.list_conference_recordings', 'matched route');
};

subtest 'test_get_conference_recording' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->conferences->get_recording('CF1', 'RE1');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, "$CONF/CF1/Recordings/RE1", 'path');
    is($j->{matched_route}, 'compatibility.get_conference_recording', 'matched route');
};

subtest 'test_update_conference_recording' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->conferences->update_recording('CF1', 'RE1', Status => 'paused');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'POST', 'POST');
    is($j->{path}, "$CONF/CF1/Recordings/RE1", 'path');
    is($j->{matched_route}, 'compatibility.update_conference_recording', 'matched route');
    is($j->{body}{Status}, 'paused', 'Status forwarded');
};

subtest 'test_delete_conference_recording' => sub {
    my $client = MockTest::client();
    $client->compat->conferences->delete_recording('CF1', 'RE1');
    my $j = MockTest::journal_last();
    is($j->{method}, 'DELETE', 'DELETE');
    is($j->{path}, "$CONF/CF1/Recordings/RE1", 'path');
    is($j->{matched_route}, 'compatibility.delete_conference_recording', 'matched route');
};

subtest 'test_create_conference_stream' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->conferences->start_stream('CF1', Url => 'wss://a.b/s');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'POST', 'POST');
    is($j->{path}, "$CONF/CF1/Streams", 'path');
    is($j->{matched_route}, 'compatibility.create_conference_stream', 'matched route');
    is($j->{body}{Url}, 'wss://a.b/s', 'Url forwarded');
};

subtest 'test_update_conference_stream' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->conferences->stop_stream('CF1', 'ST1', Status => 'stopped');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'POST', 'POST');
    is($j->{path}, "$CONF/CF1/Streams/ST1", 'path');
    is($j->{matched_route}, 'compatibility.update_conference_stream', 'matched route');
    is($j->{body}{Status}, 'stopped', 'Status forwarded');
};

# ------------------------------------------------------------------ error ----

subtest 'test_list_all_conferences_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.list_all_conferences', 500, { error => 'internal' });
    my $ok = eval { $client->compat->conferences->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.list_all_conferences', 'matched route');
    is($j->{response_status}, 500, 'journaled 500');
};

subtest 'test_retrieve_conference_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.retrieve_conference', 404, { error => 'not found' });
    my $ok = eval { $client->compat->conferences->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.retrieve_conference', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_conference_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.update_conference', 404, { error => 'not found' });
    my $ok = eval { $client->compat->conferences->update('missing', Status => 'completed'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.update_conference', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_list_all_participants_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.list_all_participants', 404, { error => 'not found' });
    my $ok = eval { $client->compat->conferences->list_participants('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.list_all_participants', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_retrieve_participant_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.retrieve_participant', 404, { error => 'not found' });
    my $ok = eval { $client->compat->conferences->get_participant('CF1', 'missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.retrieve_participant', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_participant_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.update_participant', 404, { error => 'not found' });
    my $ok = eval { $client->compat->conferences->update_participant('CF1', 'missing', Muted => 'true'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.update_participant', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_participant_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.delete_participant', 404, { error => 'not found' });
    my $ok = eval { $client->compat->conferences->remove_participant('CF1', 'missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.delete_participant', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_list_conference_recordings_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.list_conference_recordings', 404, { error => 'not found' });
    my $ok = eval { $client->compat->conferences->list_recordings('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.list_conference_recordings', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_get_conference_recording_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.get_conference_recording', 404, { error => 'not found' });
    my $ok = eval { $client->compat->conferences->get_recording('CF1', 'missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.get_conference_recording', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_conference_recording_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.update_conference_recording', 404, { error => 'not found' });
    my $ok = eval { $client->compat->conferences->update_recording('CF1', 'missing', Status => 'paused'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.update_conference_recording', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_conference_recording_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.delete_conference_recording', 404, { error => 'not found' });
    my $ok = eval { $client->compat->conferences->delete_recording('CF1', 'missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.delete_conference_recording', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_create_conference_stream_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.create_conference_stream', 404, { error => 'not found' });
    my $ok = eval { $client->compat->conferences->start_stream('missing', Url => 'wss://a.b/s'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.create_conference_stream', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_conference_stream_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.update_conference_stream', 404, { error => 'not found' });
    my $ok = eval { $client->compat->conferences->stop_stream('missing', 'ST1', Status => 'stopped'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.update_conference_stream', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

done_testing();
