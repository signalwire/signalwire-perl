#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_small_namespaces_mock.py
#
# Success + error coverage for the small namespaces:
#   addresses (list/create/get/delete), recordings (list/get/delete),
#   short_codes (list/get/update), imported_numbers (create), mfa (call),
#   sip_profile (update), number_groups (list_memberships/delete_membership),
#   project.tokens (update/delete), datasphere.documents (get_chunk),
#   queues (get_member).
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

# Helper for an error subtest: arm a one-shot scenario, call CODEREF once,
# assert it raises with the right status and the journal records the route.
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

# -------------------- Addresses --------------------

subtest 'TestAddresses' => sub {
    subtest 'list' => sub {
        my $client = MockTest::client();
        my $body = $client->addresses->list(page_size => 10);
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/relay/rest/addresses', 'path');
        is($j->{matched_route}, 'relay-rest.list_addresses', 'matched route');
    };
    subtest 'list_error' => sub {
        my $client = MockTest::client();
        _err('relay-rest.list_addresses', 500, sub { $client->addresses->list() });
    };

    subtest 'create' => sub {
        my $client = MockTest::client();
        my $body = $client->addresses->create(
            address_type => 'commercial',
            first_name   => 'Ada',
            last_name    => 'Lovelace',
            country      => 'US',
        );
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'POST', 'POST');
        is($j->{path}, '/api/relay/rest/addresses', 'path');
        is($j->{matched_route}, 'relay-rest.create_address', 'matched route');
        is(($j->{body} || {})->{address_type}, 'commercial', 'address_type forwarded');
    };
    subtest 'create_error' => sub {
        my $client = MockTest::client();
        _err('relay-rest.create_address', 422, sub { $client->addresses->create() });
    };

    subtest 'get' => sub {
        my $client = MockTest::client();
        my $body = $client->addresses->get('addr-123');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/relay/rest/addresses/addr-123', 'path');
        is($j->{matched_route}, 'relay-rest.get_address', 'matched route');
    };
    subtest 'get_error' => sub {
        my $client = MockTest::client();
        _err('relay-rest.get_address', 404, sub { $client->addresses->get('missing') });
    };

    subtest 'delete' => sub {
        my $client = MockTest::client();
        $client->addresses->delete('addr-123');
        my $j = MockTest::journal_last();
        is($j->{method}, 'DELETE', 'DELETE');
        is($j->{path}, '/api/relay/rest/addresses/addr-123', 'path');
        is($j->{matched_route}, 'relay-rest.delete_address', 'matched route');
    };
    subtest 'delete_error' => sub {
        my $client = MockTest::client();
        _err('relay-rest.delete_address', 404, sub { $client->addresses->delete('missing') });
    };
};

# -------------------- Recordings --------------------

subtest 'TestRecordings' => sub {
    subtest 'list' => sub {
        my $client = MockTest::client();
        my $body = $client->recordings->list(page_size => 5);
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/relay/rest/recordings', 'path');
        is($j->{matched_route}, 'relay-rest.list_recordings', 'matched route');
    };
    subtest 'list_error' => sub {
        my $client = MockTest::client();
        _err('relay-rest.list_recordings', 500, sub { $client->recordings->list() });
    };

    subtest 'get' => sub {
        my $client = MockTest::client();
        my $body = $client->recordings->get('rec-123');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/relay/rest/recordings/rec-123', 'path');
        is($j->{matched_route}, 'relay-rest.get_recording', 'matched route');
    };
    subtest 'get_error' => sub {
        my $client = MockTest::client();
        _err('relay-rest.get_recording', 404, sub { $client->recordings->get('missing') });
    };

    subtest 'delete' => sub {
        my $client = MockTest::client();
        $client->recordings->delete('rec-123');
        my $j = MockTest::journal_last();
        is($j->{method}, 'DELETE', 'DELETE');
        is($j->{path}, '/api/relay/rest/recordings/rec-123', 'path');
        is($j->{matched_route}, 'relay-rest.delete_recording', 'matched route');
    };
    subtest 'delete_error' => sub {
        my $client = MockTest::client();
        _err('relay-rest.delete_recording', 404, sub { $client->recordings->delete('missing') });
    };
};

# -------------------- Short Codes --------------------

subtest 'TestShortCodes' => sub {
    subtest 'list' => sub {
        my $client = MockTest::client();
        my $body = $client->short_codes->list(page_size => 20);
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/relay/rest/short_codes', 'path');
        is($j->{matched_route}, 'relay-rest.list_short_codes', 'matched route');
    };
    subtest 'list_error' => sub {
        my $client = MockTest::client();
        _err('relay-rest.list_short_codes', 500, sub { $client->short_codes->list() });
    };

    subtest 'get' => sub {
        my $client = MockTest::client();
        my $body = $client->short_codes->get('sc-1');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/relay/rest/short_codes/sc-1', 'path');
        is($j->{matched_route}, 'relay-rest.retrieve_short_code', 'matched route');
    };
    subtest 'get_error' => sub {
        my $client = MockTest::client();
        _err('relay-rest.retrieve_short_code', 404, sub { $client->short_codes->get('missing') });
    };

    subtest 'update' => sub {
        my $client = MockTest::client();
        my $body = $client->short_codes->update('sc-1', name => 'Marketing SMS');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'PUT', 'PUT');
        is($j->{path}, '/api/relay/rest/short_codes/sc-1', 'path');
        is($j->{matched_route}, 'relay-rest.update_short_code', 'matched route');
        is(($j->{body} || {})->{name}, 'Marketing SMS', 'name forwarded');
    };
    subtest 'update_error' => sub {
        my $client = MockTest::client();
        _err('relay-rest.update_short_code', 404,
            sub { $client->short_codes->update('missing', name => 'x') });
    };
};

# -------------------- Imported Numbers --------------------

subtest 'TestImportedNumbers' => sub {
    subtest 'create' => sub {
        my $client = MockTest::client();
        my $body = $client->imported_numbers->create(
            number       => '+15551234567',
            sip_username => 'alice',
            sip_password => 'secret',
            sip_proxy    => 'sip.example.com',
        );
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'POST', 'POST');
        is($j->{path}, '/api/relay/rest/imported_phone_numbers', 'path');
        is($j->{matched_route}, 'relay-rest.create_imported_phone_number', 'matched route');
        is(($j->{body} || {})->{number}, '+15551234567', 'number forwarded');
    };
    subtest 'create_error' => sub {
        my $client = MockTest::client();
        _err('relay-rest.create_imported_phone_number', 422,
            sub { $client->imported_numbers->create() });
    };
};

# -------------------- MFA --------------------

subtest 'TestMfa' => sub {
    subtest 'call' => sub {
        my $client = MockTest::client();
        my $body = $client->mfa->call(
            to      => '+15551234567',
            from_   => '+15559876543',
            message => 'Your code is {code}',
        );
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'POST', 'POST');
        is($j->{path}, '/api/relay/rest/mfa/call', 'path');
        is($j->{matched_route}, 'relay-rest.request_mfa_call', 'matched route');
        is(($j->{body} || {})->{to}, '+15551234567', 'to forwarded');
    };
    subtest 'call_error' => sub {
        my $client = MockTest::client();
        _err('relay-rest.request_mfa_call', 422,
            sub { $client->mfa->call(to => '+15551234567') });
    };
};

# -------------------- SIP Profile --------------------

subtest 'TestSipProfile' => sub {
    subtest 'update' => sub {
        my $client = MockTest::client();
        my $body = $client->sip_profile->update(
            domain         => 'myco.sip.signalwire.com',
            default_codecs => ['PCMU', 'PCMA'],
        );
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'PUT', 'PUT');
        is($j->{path}, '/api/relay/rest/sip_profile', 'path');
        is($j->{matched_route}, 'relay-rest.update_sip_profile', 'matched route');
        is(($j->{body} || {})->{domain}, 'myco.sip.signalwire.com', 'domain forwarded');
    };
    subtest 'update_error' => sub {
        my $client = MockTest::client();
        _err('relay-rest.update_sip_profile', 422,
            sub { $client->sip_profile->update(domain => 'x') });
    };
};

# -------------------- Number Groups --------------------

subtest 'TestNumberGroups' => sub {
    subtest 'list_memberships' => sub {
        my $client = MockTest::client();
        my $body = $client->number_groups->list_memberships('ng-1', page_size => 10);
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path},
           '/api/relay/rest/number_groups/ng-1/number_group_memberships', 'path');
        is($j->{matched_route}, 'relay-rest.list_number_group_memberships', 'matched route');
    };
    subtest 'list_memberships_error' => sub {
        my $client = MockTest::client();
        _err('relay-rest.list_number_group_memberships', 404,
            sub { $client->number_groups->list_memberships('missing') });
    };

    subtest 'delete_membership' => sub {
        my $client = MockTest::client();
        $client->number_groups->delete_membership('mem-1');
        my $j = MockTest::journal_last();
        is($j->{method}, 'DELETE', 'DELETE');
        is($j->{path}, '/api/relay/rest/number_group_memberships/mem-1', 'path');
        is($j->{matched_route}, 'relay-rest.delete_number_group_membership', 'matched route');
    };
    subtest 'delete_membership_error' => sub {
        my $client = MockTest::client();
        _err('relay-rest.delete_number_group_membership', 404,
            sub { $client->number_groups->delete_membership('missing') });
    };
};

# -------------------- Project tokens --------------------

subtest 'TestProjectTokens' => sub {
    subtest 'update' => sub {
        my $client = MockTest::client();
        my $body = $client->project->tokens->update('tok-1', name => 'renamed-token');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'PATCH', 'PATCH');
        is($j->{path}, '/api/project/tokens/tok-1', 'path');
        is($j->{matched_route}, 'project.update_token', 'matched route');
        is(($j->{body} || {})->{name}, 'renamed-token', 'name forwarded');
    };
    subtest 'update_error' => sub {
        my $client = MockTest::client();
        _err('project.update_token', 404,
            sub { $client->project->tokens->update('missing', name => 'x') });
    };

    subtest 'delete' => sub {
        my $client = MockTest::client();
        $client->project->tokens->delete('tok-1');
        my $j = MockTest::journal_last();
        is($j->{method}, 'DELETE', 'DELETE');
        is($j->{path}, '/api/project/tokens/tok-1', 'path');
        is($j->{matched_route}, 'project.delete_token', 'matched route');
    };
    subtest 'delete_error' => sub {
        my $client = MockTest::client();
        _err('project.delete_token', 404,
            sub { $client->project->tokens->delete('missing') });
    };
};

# -------------------- Datasphere get_chunk --------------------

subtest 'TestDatasphere' => sub {
    subtest 'get_chunk' => sub {
        my $client = MockTest::client();
        my $body = $client->datasphere->documents->get_chunk('doc-1', 'chunk-99');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/datasphere/documents/doc-1/chunks/chunk-99', 'path');
        is($j->{matched_route}, 'datasphere.get_document_chunk', 'matched route');
    };
    subtest 'get_chunk_error' => sub {
        my $client = MockTest::client();
        _err('datasphere.get_document_chunk', 404,
            sub { $client->datasphere->documents->get_chunk('doc-1', 'missing') });
    };
};

# -------------------- Queues get_member --------------------

subtest 'TestQueues' => sub {
    subtest 'get_member' => sub {
        my $client = MockTest::client();
        my $body = $client->queues->get_member('q-1', 'mem-7');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/relay/rest/queues/q-1/members/mem-7', 'path');
        is($j->{matched_route}, 'relay-rest.retrieve_queue_member', 'matched route');
    };
    subtest 'get_member_error' => sub {
        my $client = MockTest::client();
        _err('relay-rest.retrieve_queue_member', 404,
            sub { $client->queues->get_member('q-1', 'missing') });
    };
};

done_testing();
