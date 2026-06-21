#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_compat_messages_full_mock.py
#
# Full success + error coverage for $client->compat->messages and
# $client->compat->faxes — the LaML (Twilio-compatible) Messages / Faxes
# resources and their Media sub-resources. Each canonical route gets a SUCCESS
# test and an ERROR test (scenario_set arms a 4xx/5xx; the SDK raises
# SignalWire::REST::HttpClient::Error).
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

my $MSG = "/api/laml/2010-04-01/Accounts/$MockTest::PROJECT/Messages";
my $FAX = "/api/laml/2010-04-01/Accounts/$MockTest::PROJECT/Faxes";

# ---- Messages success ----

subtest 'test_list_messages' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->messages->list();
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{messages}, 'has messages');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, $MSG, 'path');
    is($last->{matched_route}, 'compatibility.list_messages', 'matched route');
};

subtest 'test_create_message' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->messages->create(
        To => '+15551112222', From => '+15553334444', Body => 'hi',
    );
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, $MSG, 'path');
    is($last->{matched_route}, 'compatibility.create_message', 'matched route');
    is($last->{body}{Body}, 'hi', 'body Body forwarded');
};

subtest 'test_list_media' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->messages->list_media('MM1');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{media_list}, 'has media_list');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$MSG/MM1/Media", 'path');
    is($last->{matched_route}, 'compatibility.list_media', 'matched route');
};

subtest 'test_retrieve_media' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->messages->get_media('MM1', 'ME1');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$MSG/MM1/Media/ME1", 'path');
    is($last->{matched_route}, 'compatibility.retrieve_media', 'matched route');
};

subtest 'test_delete_message_media' => sub {
    my $client = MockTest::client();
    $client->compat->messages->delete_media('MM1', 'ME1');
    my $last = MockTest::journal_last();
    is($last->{method}, 'DELETE', 'DELETE');
    is($last->{path}, "$MSG/MM1/Media/ME1", 'path');
    is($last->{matched_route}, 'compatibility.delete_message_media', 'matched route');
};

subtest 'test_retrieve_message' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->messages->get('MM1');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$MSG/MM1", 'path');
    is($last->{matched_route}, 'compatibility.retrieve_message', 'matched route');
};

subtest 'test_update_message' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->messages->update('MM1', Body => 'redacted');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, "$MSG/MM1", 'path');
    is($last->{matched_route}, 'compatibility.update_message', 'matched route');
    is($last->{body}{Body}, 'redacted', 'body Body forwarded');
};

subtest 'test_delete_message' => sub {
    my $client = MockTest::client();
    $client->compat->messages->delete_resource('MM1');
    my $last = MockTest::journal_last();
    is($last->{method}, 'DELETE', 'DELETE');
    is($last->{path}, "$MSG/MM1", 'path');
    is($last->{matched_route}, 'compatibility.delete_message', 'matched route');
};

# ---- Messages errors ----

subtest 'test_list_messages_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.list_messages', 500, { error => 'internal' });
    my $ok = eval { $client->compat->messages->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.list_messages', 'matched route');
    is($last->{response_status}, 500, 'journaled 500');
};

subtest 'test_create_message_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.create_message', 422, { error => 'bad' });
    my $ok = eval { $client->compat->messages->create(To => '+1', From => '+1', Body => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.create_message', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

subtest 'test_list_media_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.list_media', 404, { error => 'not found' });
    my $ok = eval { $client->compat->messages->list_media('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.list_media', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_retrieve_media_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.retrieve_media', 404, { error => 'not found' });
    my $ok = eval { $client->compat->messages->get_media('MM1', 'missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.retrieve_media', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_message_media_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.delete_message_media', 404, { error => 'not found' });
    my $ok = eval { $client->compat->messages->delete_media('MM1', 'missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.delete_message_media', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_retrieve_message_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.retrieve_message', 404, { error => 'not found' });
    my $ok = eval { $client->compat->messages->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.retrieve_message', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_message_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.update_message', 404, { error => 'not found' });
    my $ok = eval { $client->compat->messages->update('missing', Body => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.update_message', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_message_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.delete_message', 404, { error => 'not found' });
    my $ok = eval { $client->compat->messages->delete_resource('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.delete_message', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

# ---- Faxes success ----

subtest 'test_list_all_faxes' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->faxes->list();
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{faxes}, 'has faxes');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, $FAX, 'path');
    is($last->{matched_route}, 'compatibility.list_all_faxes', 'matched route');
};

subtest 'test_send_fax' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->faxes->create(
        To => '+15551112222', From => '+15553334444', MediaUrl => 'https://x/y.pdf',
    );
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, $FAX, 'path');
    is($last->{matched_route}, 'compatibility.send_fax', 'matched route');
    is($last->{body}{MediaUrl}, 'https://x/y.pdf', 'body MediaUrl forwarded');
};

subtest 'test_list_all_fax_media' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->faxes->list_media('FX1');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{media}, 'has media');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$FAX/FX1/Media", 'path');
    is($last->{matched_route}, 'compatibility.list_all_fax_media', 'matched route');
};

subtest 'test_retrieve_medias' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->faxes->get_media('FX1', 'ME1');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$FAX/FX1/Media/ME1", 'path');
    is($last->{matched_route}, 'compatibility.retrieve_medias', 'matched route');
};

subtest 'test_delete_fax_media' => sub {
    my $client = MockTest::client();
    $client->compat->faxes->delete_media('FX1', 'ME1');
    my $last = MockTest::journal_last();
    is($last->{method}, 'DELETE', 'DELETE');
    is($last->{path}, "$FAX/FX1/Media/ME1", 'path');
    is($last->{matched_route}, 'compatibility.delete_fax_media', 'matched route');
};

subtest 'test_retrieve_fax' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->faxes->get('FX1');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$FAX/FX1", 'path');
    is($last->{matched_route}, 'compatibility.retrieve_fax', 'matched route');
};

subtest 'test_update_fax' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->faxes->update('FX1', Status => 'canceled');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, "$FAX/FX1", 'path');
    is($last->{matched_route}, 'compatibility.update_fax', 'matched route');
    is($last->{body}{Status}, 'canceled', 'body Status forwarded');
};

subtest 'test_delete_fax' => sub {
    my $client = MockTest::client();
    $client->compat->faxes->delete_resource('FX1');
    my $last = MockTest::journal_last();
    is($last->{method}, 'DELETE', 'DELETE');
    is($last->{path}, "$FAX/FX1", 'path');
    is($last->{matched_route}, 'compatibility.delete_fax', 'matched route');
};

# ---- Faxes errors ----

subtest 'test_list_all_faxes_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.list_all_faxes', 500, { error => 'internal' });
    my $ok = eval { $client->compat->faxes->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.list_all_faxes', 'matched route');
    is($last->{response_status}, 500, 'journaled 500');
};

subtest 'test_send_fax_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.send_fax', 422, { error => 'bad' });
    my $ok = eval { $client->compat->faxes->create(To => '+1', From => '+1', MediaUrl => 'u'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.send_fax', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

subtest 'test_list_all_fax_media_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.list_all_fax_media', 404, { error => 'not found' });
    my $ok = eval { $client->compat->faxes->list_media('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.list_all_fax_media', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_retrieve_medias_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.retrieve_medias', 404, { error => 'not found' });
    my $ok = eval { $client->compat->faxes->get_media('FX1', 'missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.retrieve_medias', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_fax_media_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.delete_fax_media', 404, { error => 'not found' });
    my $ok = eval { $client->compat->faxes->delete_media('FX1', 'missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.delete_fax_media', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_retrieve_fax_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.retrieve_fax', 404, { error => 'not found' });
    my $ok = eval { $client->compat->faxes->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.retrieve_fax', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_fax_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.update_fax', 404, { error => 'not found' });
    my $ok = eval { $client->compat->faxes->update('missing', Status => 'canceled'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.update_fax', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_fax_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.delete_fax', 404, { error => 'not found' });
    my $ok = eval { $client->compat->faxes->delete_resource('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.delete_fax', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

done_testing();
