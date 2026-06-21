#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_compat_accounts_full_mock.py
#
# Covers client.compat.accounts / .applications / .tokens. Each canonical route
# gets BOTH a success (2xx) and an error (4xx/5xx) test, asserting the
# on-the-wire method/path and the journaled matched_route + response_status.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

my $ACCOUNTS = "/api/laml/2010-04-01/Accounts";
my $BASE     = "/api/laml/2010-04-01/Accounts/$MockTest::PROJECT";

# ----------------------------------------------------------- Accounts ----

subtest 'test_list_accounts' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->accounts->list();
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{accounts}, 'accounts key');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, $ACCOUNTS, 'path');
    is($j->{matched_route}, 'compatibility.list_accounts', 'matched route');
};

subtest 'test_create_subprojects' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->accounts->create(FriendlyName => 'Sub-A');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'POST', 'POST');
    is($j->{path}, $ACCOUNTS, 'path');
    is($j->{matched_route}, 'compatibility.create_subprojects', 'matched route');
    is($j->{body}{FriendlyName}, 'Sub-A', 'FriendlyName forwarded');
};

subtest 'test_get_account' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->accounts->get('AC123');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, "$ACCOUNTS/AC123", 'path');
    is($j->{matched_route}, 'compatibility.get_account', 'matched route');
};

subtest 'test_update_account' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->accounts->update('AC123', FriendlyName => 'Renamed');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'POST', 'POST');
    is($j->{path}, "$ACCOUNTS/AC123", 'path');
    is($j->{matched_route}, 'compatibility.update_account', 'matched route');
    is($j->{body}{FriendlyName}, 'Renamed', 'FriendlyName forwarded');
};

subtest 'test_list_accounts_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.list_accounts', 500, { error => 'internal' });
    my $ok = eval { $client->compat->accounts->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.list_accounts', 'matched route');
    is($j->{response_status}, 500, 'journaled 500');
};

subtest 'test_create_subprojects_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.create_subprojects', 422, { error => 'bad' });
    my $ok = eval { $client->compat->accounts->create(FriendlyName => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.create_subprojects', 'matched route');
    is($j->{response_status}, 422, 'journaled 422');
};

subtest 'test_get_account_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.get_account', 404, { error => 'not found' });
    my $ok = eval { $client->compat->accounts->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.get_account', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_account_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.update_account', 404, { error => 'not found' });
    my $ok = eval { $client->compat->accounts->update('missing', FriendlyName => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.update_account', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

# --------------------------------------------------------- Applications ----

subtest 'test_list_applications' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->applications->list();
    is(ref $body, 'HASH', 'hashref');
    ok(exists $body->{applications}, 'applications key');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, "$BASE/Applications", 'path');
    is($j->{matched_route}, 'compatibility.list_applications', 'matched route');
};

subtest 'test_create_application' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->applications->create(FriendlyName => 'App-A');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'POST', 'POST');
    is($j->{path}, "$BASE/Applications", 'path');
    is($j->{matched_route}, 'compatibility.create_application', 'matched route');
    is($j->{body}{FriendlyName}, 'App-A', 'FriendlyName forwarded');
};

subtest 'test_get_application' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->applications->get('AP1');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'GET', 'GET');
    is($j->{path}, "$BASE/Applications/AP1", 'path');
    is($j->{matched_route}, 'compatibility.get_application', 'matched route');
};

subtest 'test_update_application' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->applications->update('AP1', FriendlyName => 'renamed');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'POST', 'POST');
    is($j->{path}, "$BASE/Applications/AP1", 'path');
    is($j->{matched_route}, 'compatibility.update_application', 'matched route');
    is($j->{body}{FriendlyName}, 'renamed', 'FriendlyName forwarded');
};

subtest 'test_delete_application' => sub {
    my $client = MockTest::client();
    $client->compat->applications->delete_resource('AP1');
    my $j = MockTest::journal_last();
    is($j->{method}, 'DELETE', 'DELETE');
    is($j->{path}, "$BASE/Applications/AP1", 'path');
    is($j->{matched_route}, 'compatibility.delete_application', 'matched route');
};

subtest 'test_list_applications_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.list_applications', 500, { error => 'internal' });
    my $ok = eval { $client->compat->applications->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.list_applications', 'matched route');
    is($j->{response_status}, 500, 'journaled 500');
};

subtest 'test_create_application_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.create_application', 422, { error => 'bad' });
    my $ok = eval { $client->compat->applications->create(FriendlyName => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.create_application', 'matched route');
    is($j->{response_status}, 422, 'journaled 422');
};

subtest 'test_get_application_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.get_application', 404, { error => 'not found' });
    my $ok = eval { $client->compat->applications->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.get_application', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_update_application_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.update_application', 404, { error => 'not found' });
    my $ok = eval { $client->compat->applications->update('missing', FriendlyName => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.update_application', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_application_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.delete_application', 404, { error => 'not found' });
    my $ok = eval { $client->compat->applications->delete_resource('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.delete_application', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

# -------------------------------------------------------------- Tokens ----

subtest 'test_create_token' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->tokens->create(name => 'tok-a');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'POST', 'POST');
    is($j->{path}, "$BASE/tokens", 'path');
    is($j->{matched_route}, 'compatibility.create_token', 'matched route');
    is($j->{body}{name}, 'tok-a', 'name forwarded');
};

subtest 'test_update_token' => sub {
    my $client = MockTest::client();
    my $body = $client->compat->tokens->update('tok1', name => 'renamed');
    is(ref $body, 'HASH', 'hashref');
    my $j = MockTest::journal_last();
    is($j->{method}, 'PATCH', 'PATCH');
    is($j->{path}, "$BASE/tokens/tok1", 'path');
    is($j->{matched_route}, 'compatibility.update_token', 'matched route');
    is($j->{body}{name}, 'renamed', 'name forwarded');
};

subtest 'test_delete_token' => sub {
    my $client = MockTest::client();
    $client->compat->tokens->delete('tok1');
    my $j = MockTest::journal_last();
    is($j->{method}, 'DELETE', 'DELETE');
    is($j->{path}, "$BASE/tokens/tok1", 'path');
    is($j->{matched_route}, 'compatibility.delete_token', 'matched route');
};

subtest 'test_create_token_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.create_token', 422, { error => 'bad' });
    my $ok = eval { $client->compat->tokens->create(name => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.create_token', 'matched route');
    is($j->{response_status}, 422, 'journaled 422');
};

subtest 'test_update_token_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.update_token', 404, { error => 'not found' });
    my $ok = eval { $client->compat->tokens->update('missing', name => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.update_token', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

subtest 'test_delete_token_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('compatibility.delete_token', 404, { error => 'not found' });
    my $ok = eval { $client->compat->tokens->delete('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $j = MockTest::journal_last();
    is($j->{matched_route}, 'compatibility.delete_token', 'matched route');
    is($j->{response_status}, 404, 'journaled 404');
};

done_testing();
