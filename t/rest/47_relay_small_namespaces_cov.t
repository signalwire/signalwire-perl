#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_relay_small_namespaces_full_mock.py
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

# -------------------- SipProfile: Success --------------------

my $SIP = '/api/relay/rest/sip_profile';

subtest 'sip_profile_test_get' => sub {
    my $client = MockTest::client();
    my $body = $client->sip_profile->get();
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, $SIP, 'path');
    is($last->{matched_route}, 'relay-rest.retrieve_sip_profile', 'matched route');
};

subtest 'sip_profile_test_update' => sub {
    my $client = MockTest::client();
    my $body = $client->sip_profile->update(domain => 'acme');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'PUT', 'PUT');
    is($last->{path}, $SIP, 'path');
    is($last->{matched_route}, 'relay-rest.update_sip_profile', 'matched route');
    is(($last->{body} || {})->{domain}, 'acme', 'domain forwarded');
};

# -------------------- SipProfile: Errors --------------------

subtest 'sip_profile_test_get_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.retrieve_sip_profile', 500, { error => 'boom' });
    my $ok = eval { $client->sip_profile->get(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.retrieve_sip_profile', 'matched route');
    is($last->{response_status}, 500, 'journaled 500');
};

subtest 'sip_profile_test_update_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.update_sip_profile', 422, { error => 'bad' });
    my $ok = eval { $client->sip_profile->update(domain => ''); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.update_sip_profile', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

# -------------------- Lookup: Success + Error --------------------

subtest 'lookup_test_phone_number' => sub {
    my $client = MockTest::client();
    my $body = $client->lookup->phone_number('+15551230000');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, '/api/relay/rest/lookup/phone_number/+15551230000', 'path');
    is($last->{matched_route}, 'relay-rest.lookup_phone_number', 'matched route');
};

subtest 'lookup_test_phone_number_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.lookup_phone_number', 404, { error => 'nope' });
    my $ok = eval { $client->lookup->phone_number('+19999999999'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.lookup_phone_number', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

# -------------------- ShortCodes: Success --------------------

my $SC = '/api/relay/rest/short_codes';

subtest 'short_codes_test_list' => sub {
    my $client = MockTest::client();
    my $body = $client->short_codes->list();
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, $SC, 'path');
    is($last->{matched_route}, 'relay-rest.list_short_codes', 'matched route');
};

subtest 'short_codes_test_get' => sub {
    my $client = MockTest::client();
    my $body = $client->short_codes->get('sc-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$SC/sc-1", 'path');
    is($last->{matched_route}, 'relay-rest.retrieve_short_code', 'matched route');
};

subtest 'short_codes_test_update' => sub {
    my $client = MockTest::client();
    my $body = $client->short_codes->update('sc-1', friendly_name => 'promo');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'PUT', 'PUT');
    is($last->{path}, "$SC/sc-1", 'path');
    is($last->{matched_route}, 'relay-rest.update_short_code', 'matched route');
    is(($last->{body} || {})->{friendly_name}, 'promo', 'friendly_name forwarded');
};

# -------------------- ShortCodes: Errors --------------------

subtest 'short_codes_test_list_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.list_short_codes', 500, { error => 'boom' });
    my $ok = eval { $client->short_codes->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.list_short_codes', 'matched route');
    is($last->{response_status}, 500, 'journaled 500');
};

subtest 'short_codes_test_get_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.retrieve_short_code', 404, { error => 'nope' });
    my $ok = eval { $client->short_codes->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.retrieve_short_code', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'short_codes_test_update_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.update_short_code', 404, { error => 'nope' });
    my $ok = eval { $client->short_codes->update('missing', friendly_name => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.update_short_code', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

# -------------------- ImportedNumbers: Success + Error --------------------

my $IMP = '/api/relay/rest/imported_phone_numbers';

subtest 'imported_numbers_test_create' => sub {
    my $client = MockTest::client();
    my $body = $client->imported_numbers->create(number => '+15551230000');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, $IMP, 'path');
    is($last->{matched_route}, 'relay-rest.create_imported_phone_number', 'matched route');
    is(($last->{body} || {})->{number}, '+15551230000', 'number forwarded');
};

subtest 'imported_numbers_test_create_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.create_imported_phone_number', 422, { error => 'bad' });
    my $ok = eval { $client->imported_numbers->create(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.create_imported_phone_number', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

# -------------------- MFA: Success --------------------

subtest 'mfa_test_call' => sub {
    my $client = MockTest::client();
    my $body = $client->mfa->call(to => '+15551230000');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, '/api/relay/rest/mfa/call', 'path');
    is($last->{matched_route}, 'relay-rest.request_mfa_call', 'matched route');
    is(($last->{body} || {})->{to}, '+15551230000', 'to forwarded');
};

subtest 'mfa_test_sms' => sub {
    my $client = MockTest::client();
    my $body = $client->mfa->sms(to => '+15551230000');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, '/api/relay/rest/mfa/sms', 'path');
    is($last->{matched_route}, 'relay-rest.request_mfa_sms', 'matched route');
    is(($last->{body} || {})->{to}, '+15551230000', 'to forwarded');
};

subtest 'mfa_test_verify' => sub {
    my $client = MockTest::client();
    my $body = $client->mfa->verify('mfa-1', token => '123456');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, '/api/relay/rest/mfa/mfa-1/verify', 'path');
    is($last->{matched_route}, 'relay-rest.verify_mfa_token', 'matched route');
    is(($last->{body} || {})->{token}, '123456', 'token forwarded');
};

# -------------------- MFA: Errors --------------------

subtest 'mfa_test_call_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.request_mfa_call', 422, { error => 'to required' });
    my $ok = eval { $client->mfa->call(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.request_mfa_call', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

subtest 'mfa_test_sms_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.request_mfa_sms', 422, { error => 'to required' });
    my $ok = eval { $client->mfa->sms(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.request_mfa_sms', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

subtest 'mfa_test_verify_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.verify_mfa_token', 422, { error => 'bad token' });
    my $ok = eval { $client->mfa->verify('mfa-1', token => '000000'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.verify_mfa_token', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

done_testing();
