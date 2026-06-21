#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_logs_mock.py
#
# Success + error coverage for the Logs namespace, which fans out across four
# spec docs (message/voice/fax/logs):
#   messages (list/get), voice (list/get), fax (list/get), conferences (list).
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

sub _err {
    my ($endpoint_id, $status, $code_ref) = @_;
    MockTest::scenario_set($endpoint_id, $status, { error => 'boom' });
    my $ok = eval { $code_ref->(); 1 };
    my $e = $@;
    ok(!$ok, "raised for $endpoint_id");
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, $status, "status $status for $endpoint_id");
    my $j = MockTest::journal_last();
    is($j->{matched_route}, $endpoint_id, "matched route $endpoint_id");
    is($j->{response_status}, $status, "journaled $status for $endpoint_id");
}

# -------------------- Message Logs --------------------

subtest 'TestMessageLogs' => sub {
    subtest 'list' => sub {
        my $client = MockTest::client();
        my $body = $client->logs->messages->list();
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/messaging/logs', 'path');
        is($j->{matched_route}, 'message.list_message_logs', 'matched route');
    };
    subtest 'list_error' => sub {
        my $client = MockTest::client();
        _err('message.list_message_logs', 500, sub { $client->logs->messages->list() });
    };

    subtest 'get' => sub {
        my $client = MockTest::client();
        my $body = $client->logs->messages->get('ml-42');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/messaging/logs/ml-42', 'path');
        is($j->{matched_route}, 'message.get_message_log', 'matched route');
    };
    subtest 'get_error' => sub {
        my $client = MockTest::client();
        _err('message.get_message_log', 404, sub { $client->logs->messages->get('missing') });
    };
};

# -------------------- Voice Logs --------------------

subtest 'TestVoiceLogs' => sub {
    subtest 'list' => sub {
        my $client = MockTest::client();
        my $body = $client->logs->voice->list();
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/voice/logs', 'path');
        is($j->{matched_route}, 'voice.list_voice_logs', 'matched route');
    };
    subtest 'list_error' => sub {
        my $client = MockTest::client();
        _err('voice.list_voice_logs', 500, sub { $client->logs->voice->list() });
    };

    subtest 'get' => sub {
        my $client = MockTest::client();
        my $body = $client->logs->voice->get('vl-99');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/voice/logs/vl-99', 'path');
        is($j->{matched_route}, 'voice.get_voice_log', 'matched route');
    };
    subtest 'get_error' => sub {
        my $client = MockTest::client();
        _err('voice.get_voice_log', 404, sub { $client->logs->voice->get('missing') });
    };
};

# -------------------- Fax Logs --------------------

subtest 'TestFaxLogs' => sub {
    subtest 'list' => sub {
        my $client = MockTest::client();
        my $body = $client->logs->fax->list();
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/fax/logs', 'path');
        is($j->{matched_route}, 'fax.list_fax_logs', 'matched route');
    };
    subtest 'list_error' => sub {
        my $client = MockTest::client();
        _err('fax.list_fax_logs', 500, sub { $client->logs->fax->list() });
    };

    subtest 'get' => sub {
        my $client = MockTest::client();
        my $body = $client->logs->fax->get('fl-7');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/fax/logs/fl-7', 'path');
        is($j->{matched_route}, 'fax.get_fax_log', 'matched route');
    };
    subtest 'get_error' => sub {
        my $client = MockTest::client();
        _err('fax.get_fax_log', 404, sub { $client->logs->fax->get('missing') });
    };
};

# -------------------- Conference Logs --------------------

subtest 'TestConferenceLogs' => sub {
    subtest 'list' => sub {
        my $client = MockTest::client();
        my $body = $client->logs->conferences->list();
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/logs/conferences', 'path');
        is($j->{matched_route}, 'logs.list_conferences', 'matched route');
    };
    subtest 'list_error' => sub {
        my $client = MockTest::client();
        _err('logs.list_conferences', 500, sub { $client->logs->conferences->list() });
    };
};

done_testing();
