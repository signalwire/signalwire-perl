#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_compat_phone_numbers_full_mock.py
#
# Full success + error coverage for $client->compat->phone_numbers — the LaML
# (Twilio-compatible) IncomingPhoneNumbers / ImportedPhoneNumbers /
# AvailablePhoneNumbers resources. Each canonical route gets a SUCCESS test and
# an ERROR test (scenario_set arms a 4xx/5xx; the SDK raises
# SignalWire::REST::HttpClient::Error).
#
# GAP (accepted, allowlisted): compatibility.list_available_phone_number_resources_by_country
# (GET /AvailablePhoneNumbers/{IsoCountry}) has no Perl SDK method, mirroring the
# Python gap — no test is written for it.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

my $INC   = "/api/laml/2010-04-01/Accounts/$MockTest::PROJECT/IncomingPhoneNumbers";
my $IMP   = "/api/laml/2010-04-01/Accounts/$MockTest::PROJECT/ImportedPhoneNumbers";
my $AVAIL = "/api/laml/2010-04-01/Accounts/$MockTest::PROJECT/AvailablePhoneNumbers";

# ---- Success ----

subtest 'test_list_incoming_phone_numbers' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->phone_numbers->list();
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{incoming_phone_numbers}, 'has incoming_phone_numbers');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, $INC, 'path');
    is($last->{matched_route}, 'compatibility.list_incoming_phone_numbers', 'matched route');
};

subtest 'test_create_incoming_phone_number' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->phone_numbers->purchase(PhoneNumber => '+15551112222');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, $INC, 'path');
    is($last->{matched_route}, 'compatibility.create_incoming_phone_number', 'matched route');
    is($last->{body}{PhoneNumber}, '+15551112222', 'body PhoneNumber forwarded');
};

subtest 'test_retrieve_incoming_phone_number' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->phone_numbers->get('PN1');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$INC/PN1", 'path');
    is($last->{matched_route}, 'compatibility.retrieve_incoming_phone_number', 'matched route');
};

subtest 'test_update_incoming_phone_number' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->phone_numbers->update('PN1', FriendlyName => 'renamed');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, "$INC/PN1", 'path');
    is($last->{matched_route}, 'compatibility.update_incoming_phone_number', 'matched route');
    is($last->{body}{FriendlyName}, 'renamed', 'body FriendlyName forwarded');
};

subtest 'test_delete_incoming_phone_number' => sub {
    my $client = MockTest::client();
    $client->compat->phone_numbers->delete('PN1');
    my $last = MockTest::journal_last();
    is($last->{method}, 'DELETE', 'DELETE');
    is($last->{path}, "$INC/PN1", 'path');
    is($last->{matched_route}, 'compatibility.delete_incoming_phone_number', 'matched route');
};

subtest 'test_create_imported_phone_number' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->phone_numbers->import_number(PhoneNumber => '+15551112222');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{sid}, 'has sid');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, $IMP, 'path');
    is($last->{matched_route}, 'compatibility.create_imported_phone_number', 'matched route');
    is($last->{body}{PhoneNumber}, '+15551112222', 'body PhoneNumber forwarded');
};

subtest 'test_list_available_phone_number_resources' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->phone_numbers->list_available_countries();
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{countries}, 'has countries');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, $AVAIL, 'path');
    is($last->{matched_route}, 'compatibility.list_available_phone_number_resources', 'matched route');
};

subtest 'test_search_local_available_phone_numbers' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->phone_numbers->search_local('US');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{available_phone_numbers}, 'has available_phone_numbers');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$AVAIL/US/Local", 'path');
    is($last->{matched_route}, 'compatibility.search_local_available_phone_numbers', 'matched route');
};

subtest 'test_search_toll_free_available_phone_numbers' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->phone_numbers->search_toll_free('US');
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{available_phone_numbers}, 'has available_phone_numbers');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$AVAIL/US/TollFree", 'path');
    is($last->{matched_route}, 'compatibility.search_toll_free_available_phone_numbers', 'matched route');
};

# ---- Errors ----

subtest 'test_list_incoming_phone_numbers_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.list_incoming_phone_numbers', 500, { error => 'internal' });
    my $ok = eval { $client->compat->phone_numbers->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.list_incoming_phone_numbers', 'matched route');
    is($last->{response_status}, 500, 'journaled 500');
};

subtest 'test_create_incoming_phone_number_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.create_incoming_phone_number', 422, { error => 'bad' });
    my $ok = eval { $client->compat->phone_numbers->purchase(PhoneNumber => '+1'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.create_incoming_phone_number', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

subtest 'test_retrieve_incoming_phone_number_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.retrieve_incoming_phone_number', 404, { error => 'not found' });
    my $ok = eval { $client->compat->phone_numbers->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.retrieve_incoming_phone_number', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_incoming_phone_number_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.update_incoming_phone_number', 404, { error => 'not found' });
    my $ok = eval { $client->compat->phone_numbers->update('missing', FriendlyName => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.update_incoming_phone_number', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_incoming_phone_number_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.delete_incoming_phone_number', 404, { error => 'not found' });
    my $ok = eval { $client->compat->phone_numbers->delete('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.delete_incoming_phone_number', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'test_create_imported_phone_number_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.create_imported_phone_number', 422, { error => 'bad' });
    my $ok = eval { $client->compat->phone_numbers->import_number(PhoneNumber => '+1'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.create_imported_phone_number', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

subtest 'test_list_available_phone_number_resources_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.list_available_phone_number_resources', 500, { error => 'internal' });
    my $ok = eval { $client->compat->phone_numbers->list_available_countries(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.list_available_phone_number_resources', 'matched route');
    is($last->{response_status}, 500, 'journaled 500');
};

subtest 'test_search_local_available_phone_numbers_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.search_local_available_phone_numbers', 500, { error => 'internal' });
    my $ok = eval { $client->compat->phone_numbers->search_local('US'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.search_local_available_phone_numbers', 'matched route');
    is($last->{response_status}, 500, 'journaled 500');
};

subtest 'test_search_toll_free_available_phone_numbers_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.search_toll_free_available_phone_numbers', 500, { error => 'internal' });
    my $ok = eval { $client->compat->phone_numbers->search_toll_free('US'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'compatibility.search_toll_free_available_phone_numbers', 'matched route');
    is($last->{response_status}, 500, 'journaled 500');
};

done_testing();
