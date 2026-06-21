#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_compat_misc_full_mock.py
#
# Covers client.compat.laml_bins / .queues (+members) / .recordings /
# .transcriptions. Each canonical route gets BOTH a success (2xx) and an error
# (4xx/5xx) test, asserting the on-the-wire method/path and the journaled
# matched_route + response_status.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

my $BINS   = "/api/laml/2010-04-01/Accounts/$MockTest::PROJECT/LamlBins";
my $QUEUES = "/api/laml/2010-04-01/Accounts/$MockTest::PROJECT/Queues";
my $RECS   = "/api/laml/2010-04-01/Accounts/$MockTest::PROJECT/Recordings";
my $TRANS  = "/api/laml/2010-04-01/Accounts/$MockTest::PROJECT/Transcriptions";

# ------------------------------------------------------------ LamlBins ----

subtest 'test_list_cxml_scripts' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->laml_bins->list();
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{laml_bins}, 'laml_bins key');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, $BINS, 'path');
    is($j->{matched_route}, 'compatibility.list_cxml_scripts', 'matched route');
};

subtest 'test_create_cxml_script' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->laml_bins->create(Name => 'bin-a', Contents => '<Response/>');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'POST', 'POST');
    is($j->{path}, $BINS, 'path');
    is($j->{matched_route}, 'compatibility.create_cxml_script', 'matched route');
    is($j->{body}{Name}, 'bin-a', 'Name forwarded');
};

subtest 'test_retrieve_cxml_script' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->laml_bins->get('LB1');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, "$BINS/LB1", 'path');
    is($j->{matched_route}, 'compatibility.retrieve_cxml_script', 'matched route');
};

subtest 'test_update_cxml_script' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->laml_bins->update('LB1', Name => 'renamed');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'POST', 'POST');
    is($j->{path}, "$BINS/LB1", 'path');
    is($j->{matched_route}, 'compatibility.update_cxml_script', 'matched route');
    is($j->{body}{Name}, 'renamed', 'Name forwarded');
};

subtest 'test_delete_cxml_script' => sub {
    my $client = MockTest::client();
    $client->compat->laml_bins->delete_resource('LB1');
    my $j = MockTest::journal_last();
    is($j->{method}, 'DELETE', 'DELETE');
    is($j->{path}, "$BINS/LB1", 'path');
    is($j->{matched_route}, 'compatibility.delete_cxml_script', 'matched route');
};

subtest 'test_list_cxml_scripts_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.list_cxml_scripts', 500, { error => 'internal' });
    my $ok = eval { $client->compat->laml_bins->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.list_cxml_scripts', 'matched route');
    is($j->{response_status}, 500, 'journaled 500');
};

subtest 'test_create_cxml_script_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.create_cxml_script', 422, { error => 'bad' });
    my $ok = eval { $client->compat->laml_bins->create(Name => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.create_cxml_script', 'matched route');
    is($j->{response_status}, 422, 'journaled 422');
};

subtest 'test_retrieve_cxml_script_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.retrieve_cxml_script', 404, { error => 'not found' });
    my $ok = eval { $client->compat->laml_bins->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.retrieve_cxml_script', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_cxml_script_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.update_cxml_script', 404, { error => 'not found' });
    my $ok = eval { $client->compat->laml_bins->update('missing', Name => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.update_cxml_script', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_cxml_script_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.delete_cxml_script', 404, { error => 'not found' });
    my $ok = eval { $client->compat->laml_bins->delete_resource('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.delete_cxml_script', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

# -------------------------------------------------------------- Queues ----

subtest 'test_list_queues' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->queues->list();
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{queues}, 'queues key');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, $QUEUES, 'path');
    is($j->{matched_route}, 'compatibility.list_queues', 'matched route');
};

subtest 'test_create_queue' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->queues->create(FriendlyName => 'q-a');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'POST', 'POST');
    is($j->{path}, $QUEUES, 'path');
    is($j->{matched_route}, 'compatibility.create_queue', 'matched route');
    is($j->{body}{FriendlyName}, 'q-a', 'FriendlyName forwarded');
};

subtest 'test_list_all_queue_members' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->queues->list_members('QU1');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{queue_members}, 'queue_members key');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, "$QUEUES/QU1/Members", 'path');
    is($j->{matched_route}, 'compatibility.list_all_queue_members', 'matched route');
};

subtest 'test_retrieve_queue_member' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->queues->get_member('QU1', 'CA1');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, "$QUEUES/QU1/Members/CA1", 'path');
    is($j->{matched_route}, 'compatibility.retrieve_queue_member', 'matched route');
};

subtest 'test_update_queue_member' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->queues->dequeue_member('QU1', 'CA1', Url => 'https://x/y');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'POST', 'POST');
    is($j->{path}, "$QUEUES/QU1/Members/CA1", 'path');
    is($j->{matched_route}, 'compatibility.update_queue_member', 'matched route');
    is($j->{body}{Url}, 'https://x/y', 'Url forwarded');
};

subtest 'test_retrieve_queue' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->queues->get('QU1');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, "$QUEUES/QU1", 'path');
    is($j->{matched_route}, 'compatibility.retrieve_queue', 'matched route');
};

subtest 'test_update_queue' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->queues->update('QU1', FriendlyName => 'renamed');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'POST', 'POST');
    is($j->{path}, "$QUEUES/QU1", 'path');
    is($j->{matched_route}, 'compatibility.update_queue', 'matched route');
    is($j->{body}{FriendlyName}, 'renamed', 'FriendlyName forwarded');
};

subtest 'test_delete_queue' => sub {
    my $client = MockTest::client();
    $client->compat->queues->delete_resource('QU1');
    my $j = MockTest::journal_last();
    is($j->{method}, 'DELETE', 'DELETE');
    is($j->{path}, "$QUEUES/QU1", 'path');
    is($j->{matched_route}, 'compatibility.delete_queue', 'matched route');
};

subtest 'test_list_queues_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.list_queues', 500, { error => 'internal' });
    my $ok = eval { $client->compat->queues->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.list_queues', 'matched route');
    is($j->{response_status}, 500, 'journaled 500');
};

subtest 'test_create_queue_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.create_queue', 422, { error => 'bad' });
    my $ok = eval { $client->compat->queues->create(FriendlyName => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.create_queue', 'matched route');
    is($j->{response_status}, 422, 'journaled 422');
};

subtest 'test_list_all_queue_members_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.list_all_queue_members', 404, { error => 'not found' });
    my $ok = eval { $client->compat->queues->list_members('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.list_all_queue_members', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_retrieve_queue_member_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.retrieve_queue_member', 404, { error => 'not found' });
    my $ok = eval { $client->compat->queues->get_member('QU1', 'missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.retrieve_queue_member', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_queue_member_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.update_queue_member', 404, { error => 'not found' });
    my $ok = eval { $client->compat->queues->dequeue_member('QU1', 'missing', Url => 'https://x/y'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.update_queue_member', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_retrieve_queue_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.retrieve_queue', 404, { error => 'not found' });
    my $ok = eval { $client->compat->queues->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.retrieve_queue', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_queue_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.update_queue', 404, { error => 'not found' });
    my $ok = eval { $client->compat->queues->update('missing', FriendlyName => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.update_queue', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_queue_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.delete_queue', 404, { error => 'not found' });
    my $ok = eval { $client->compat->queues->delete_resource('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.delete_queue', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

# ---------------------------------------------------------- Recordings ----

subtest 'test_list_recordings' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->recordings->list();
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{recordings}, 'recordings key');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, $RECS, 'path');
    is($j->{matched_route}, 'compatibility.list_recordings', 'matched route');
};

subtest 'test_retrieve_recording' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->recordings->get('RE1');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, "$RECS/RE1", 'path');
    is($j->{matched_route}, 'compatibility.retrieve_recording', 'matched route');
};

subtest 'test_delete_recording' => sub {
    my $client = MockTest::client();
    $client->compat->recordings->delete('RE1');
    my $j = MockTest::journal_last();
    is($j->{method}, 'DELETE', 'DELETE');
    is($j->{path}, "$RECS/RE1", 'path');
    is($j->{matched_route}, 'compatibility.delete_recording', 'matched route');
};

subtest 'test_list_recordings_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.list_recordings', 500, { error => 'internal' });
    my $ok = eval { $client->compat->recordings->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.list_recordings', 'matched route');
    is($j->{response_status}, 500, 'journaled 500');
};

subtest 'test_retrieve_recording_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.retrieve_recording', 404, { error => 'not found' });
    my $ok = eval { $client->compat->recordings->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.retrieve_recording', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_recording_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.delete_recording', 404, { error => 'not found' });
    my $ok = eval { $client->compat->recordings->delete('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.delete_recording', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

# ----------------------------------------------------- Transcriptions ----

subtest 'test_list_transcriptions' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->transcriptions->list();
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{transcriptions}, 'transcriptions key');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, $TRANS, 'path');
    is($j->{matched_route}, 'compatibility.list_transcriptions', 'matched route');
};

subtest 'test_retrieve_transcription' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->transcriptions->get('TR1');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, "$TRANS/TR1", 'path');
    is($j->{matched_route}, 'compatibility.retrieve_transcription', 'matched route');
};

subtest 'test_delete_transcription' => sub {
    my $client = MockTest::client();
    $client->compat->transcriptions->delete('TR1');
    my $j = MockTest::journal_last();
    is($j->{method}, 'DELETE', 'DELETE');
    is($j->{path}, "$TRANS/TR1", 'path');
    is($j->{matched_route}, 'compatibility.delete_transcription', 'matched route');
};

subtest 'test_list_transcriptions_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.list_transcriptions', 500, { error => 'internal' });
    my $ok = eval { $client->compat->transcriptions->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.list_transcriptions', 'matched route');
    is($j->{response_status}, 500, 'journaled 500');
};

subtest 'test_retrieve_transcription_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.retrieve_transcription', 404, { error => 'not found' });
    my $ok = eval { $client->compat->transcriptions->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.retrieve_transcription', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_transcription_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.delete_transcription', 404, { error => 'not found' });
    my $ok = eval { $client->compat->transcriptions->delete('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.delete_transcription', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

done_testing();
