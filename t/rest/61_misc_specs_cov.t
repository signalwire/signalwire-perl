#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_misc_specs_full_mock.py
#
# Full success + error coverage for the small REST specs:
#   project (create/update/delete token), voice logs (list/get/list_events),
#   fax logs (list/get), message logs (list/get), calling command dispatch,
#   chat token, conference logs (list), pubsub token.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

# -------------------- project tokens --------------------

subtest 'TestProjectTokensSuccess' => sub {
    subtest 'create' => sub {
        my $client = MockTest::client();
        my $body = $client->project_ns->tokens->create(name => 'ci-token');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'POST', 'POST');
        is($j->{path}, '/api/project/tokens', 'path');
        is($j->{matched_route}, 'project.create_token', 'matched route');
        is(($j->{body} || {})->{name}, 'ci-token', 'name forwarded');
    };

    subtest 'update' => sub {
        my $client = MockTest::client();
        my $body = $client->project_ns->tokens->update('tok-1', name => 'renamed');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'PATCH', 'PATCH');
        is($j->{path}, '/api/project/tokens/tok-1', 'path');
        is($j->{matched_route}, 'project.update_token', 'matched route');
        is(($j->{body} || {})->{name}, 'renamed', 'name forwarded');
    };

    subtest 'delete' => sub {
        my $client = MockTest::client();
        $client->project_ns->tokens->delete('tok-1');
        my $j = MockTest::journal_last();
        is($j->{method}, 'DELETE', 'DELETE');
        is($j->{path}, '/api/project/tokens/tok-1', 'path');
        is($j->{matched_route}, 'project.delete_token', 'matched route');
    };
};

subtest 'TestProjectTokensErrors' => sub {
    subtest 'create_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('project.create_token', 422, { error => 'name required' });
        my $ok = eval { $client->project_ns->tokens->create(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'project.create_token', 'matched route');
        is($j->{response_status}, 422, 'journaled 422');
    };

    subtest 'update_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('project.update_token', 404, { error => 'not found' });
        my $ok = eval { $client->project_ns->tokens->update('missing', name => 'x'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'project.update_token', 'matched route');
        is($j->{response_status}, 404, 'journaled 404');
    };

    subtest 'delete_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('project.delete_token', 404, { error => 'not found' });
        my $ok = eval { $client->project_ns->tokens->delete('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'project.delete_token', 'matched route');
        is($j->{response_status}, 404, 'journaled 404');
    };
};

# -------------------- voice logs --------------------

subtest 'TestVoiceLogsSuccess' => sub {
    subtest 'list' => sub {
        my $client = MockTest::client();
        my $body = $client->logs->voice->list();
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/voice/logs', 'path');
        is($j->{matched_route}, 'voice.list_voice_logs', 'matched route');
    };

    subtest 'get' => sub {
        my $client = MockTest::client();
        my $body = $client->logs->voice->get('vl-1');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/voice/logs/vl-1', 'path');
        is($j->{matched_route}, 'voice.get_voice_log', 'matched route');
    };

    subtest 'list_events' => sub {
        my $client = MockTest::client();
        my $body = $client->logs->voice->list_events('vl-1');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/voice/logs/vl-1/events', 'path');
        is($j->{matched_route}, 'voice.list_voice_log_events', 'matched route');
    };
};

subtest 'TestVoiceLogsErrors' => sub {
    subtest 'list_server_error' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('voice.list_voice_logs', 500, { error => 'internal' });
        my $ok = eval { $client->logs->voice->list(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 500, 'status 500');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'voice.list_voice_logs', 'matched route');
        is($j->{response_status}, 500, 'journaled 500');
    };

    subtest 'get_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('voice.get_voice_log', 404, { error => 'not found' });
        my $ok = eval { $client->logs->voice->get('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'voice.get_voice_log', 'matched route');
        is($j->{response_status}, 404, 'journaled 404');
    };

    subtest 'list_events_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('voice.list_voice_log_events', 404, { error => 'not found' });
        my $ok = eval { $client->logs->voice->list_events('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'voice.list_voice_log_events', 'matched route');
        is($j->{response_status}, 404, 'journaled 404');
    };
};

# -------------------- fax logs --------------------

subtest 'TestFaxLogsSuccess' => sub {
    subtest 'list' => sub {
        my $client = MockTest::client();
        my $body = $client->logs->fax->list();
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/fax/logs', 'path');
        is($j->{matched_route}, 'fax.list_fax_logs', 'matched route');
    };

    subtest 'get' => sub {
        my $client = MockTest::client();
        my $body = $client->logs->fax->get('fl-1');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/fax/logs/fl-1', 'path');
        is($j->{matched_route}, 'fax.get_fax_log', 'matched route');
    };
};

subtest 'TestFaxLogsErrors' => sub {
    subtest 'list_server_error' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fax.list_fax_logs', 500, { error => 'internal' });
        my $ok = eval { $client->logs->fax->list(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 500, 'status 500');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'fax.list_fax_logs', 'matched route');
        is($j->{response_status}, 500, 'journaled 500');
    };

    subtest 'get_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('fax.get_fax_log', 404, { error => 'not found' });
        my $ok = eval { $client->logs->fax->get('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'fax.get_fax_log', 'matched route');
        is($j->{response_status}, 404, 'journaled 404');
    };
};

# -------------------- message logs --------------------

subtest 'TestMessageLogsSuccess' => sub {
    subtest 'list' => sub {
        my $client = MockTest::client();
        my $body = $client->logs->messages->list();
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/messaging/logs', 'path');
        is($j->{matched_route}, 'message.list_message_logs', 'matched route');
    };

    subtest 'get' => sub {
        my $client = MockTest::client();
        my $body = $client->logs->messages->get('ml-1');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/messaging/logs/ml-1', 'path');
        is($j->{matched_route}, 'message.get_message_log', 'matched route');
    };
};

subtest 'TestMessageLogsErrors' => sub {
    subtest 'list_server_error' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('message.list_message_logs', 500, { error => 'internal' });
        my $ok = eval { $client->logs->messages->list(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 500, 'status 500');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'message.list_message_logs', 'matched route');
        is($j->{response_status}, 500, 'journaled 500');
    };

    subtest 'get_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('message.get_message_log', 404, { error => 'not found' });
        my $ok = eval { $client->logs->messages->get('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'message.get_message_log', 'matched route');
        is($j->{response_status}, 404, 'journaled 404');
    };
};

# -------------------- calling command dispatch --------------------

subtest 'TestCallingCommandSuccess' => sub {
    subtest 'dial' => sub {
        my $client = MockTest::client();
        my $body = $client->calling->dial(
            url => 'https://example.com/swml', to => '+15551234567',
        );
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'POST', 'POST');
        is($j->{path}, '/api/calling/calls', 'path');
        is($j->{matched_route}, 'calling.call-commands', 'matched route');
        is(($j->{body} || {})->{command}, 'dial', 'command is dial');
    };
};

subtest 'TestCallingCommandErrors' => sub {
    subtest 'dial_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('calling.call-commands', 422, { error => 'bad command' });
        my $ok = eval { $client->calling->dial(url => 'https://example.com/swml'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'calling.call-commands', 'matched route');
        is($j->{response_status}, 422, 'journaled 422');
    };
};

# -------------------- chat token --------------------

subtest 'TestChatTokenSuccess' => sub {
    subtest 'create_token' => sub {
        my $client = MockTest::client();
        my $body = $client->chat->create_token(channels => { room => {} });
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'POST', 'POST');
        is($j->{path}, '/api/chat/tokens', 'path');
        is($j->{matched_route}, 'chat.create_chat_token', 'matched route');
        is_deeply(($j->{body} || {})->{channels}, { room => {} }, 'channels forwarded');
    };
};

subtest 'TestChatTokenErrors' => sub {
    subtest 'create_token_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('chat.create_chat_token', 422, { error => 'channels required' });
        my $ok = eval { $client->chat->create_token(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'chat.create_chat_token', 'matched route');
        is($j->{response_status}, 422, 'journaled 422');
    };
};

# -------------------- conference logs --------------------

subtest 'TestConferenceLogsSuccess' => sub {
    subtest 'list' => sub {
        my $client = MockTest::client();
        my $body = $client->logs->conferences->list();
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/logs/conferences', 'path');
        is($j->{matched_route}, 'logs.list_conferences', 'matched route');
    };
};

subtest 'TestConferenceLogsErrors' => sub {
    subtest 'list_server_error' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('logs.list_conferences', 500, { error => 'internal' });
        my $ok = eval { $client->logs->conferences->list(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 500, 'status 500');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'logs.list_conferences', 'matched route');
        is($j->{response_status}, 500, 'journaled 500');
    };
};

# -------------------- pubsub token --------------------

subtest 'TestPubSubTokenSuccess' => sub {
    subtest 'create_token' => sub {
        my $client = MockTest::client();
        my $body = $client->pubsub->create_token(channels => { news => {} });
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'POST', 'POST');
        is($j->{path}, '/api/pubsub/tokens', 'path');
        is($j->{matched_route}, 'pubsub.create_token', 'matched route');
        is_deeply(($j->{body} || {})->{channels}, { news => {} }, 'channels forwarded');
    };
};

subtest 'TestPubSubTokenErrors' => sub {
    subtest 'create_token_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('pubsub.create_token', 422, { error => 'channels required' });
        my $ok = eval { $client->pubsub->create_token(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'pubsub.create_token', 'matched route');
        is($j->{response_status}, 422, 'journaled 422');
    };
};

done_testing();
