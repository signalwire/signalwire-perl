#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_datasphere_full_mock.py
#
# Full success + error coverage for $client->datasphere->documents:
#   list / create / get / update (PATCH) / delete, search (POST /search),
#   list_chunks / get_chunk / delete_chunk under {id}/chunks.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

# -------------------- Success --------------------

subtest 'TestDatasphereSuccess' => sub {
    subtest 'list' => sub {
        my $client = MockTest::client();
        my $body = $client->datasphere->documents->list();
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/datasphere/documents', 'path');
        is($j->{matched_route}, 'datasphere.list_documents', 'matched route');
    };

    subtest 'create' => sub {
        my $client = MockTest::client();
        my $body = $client->datasphere->documents->create(
            url => 'https://example.com/doc.pdf',
        );
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'POST', 'POST');
        is($j->{path}, '/api/datasphere/documents', 'path');
        is($j->{matched_route}, 'datasphere.create_document', 'matched route');
        is(($j->{body} || {})->{url}, 'https://example.com/doc.pdf', 'url forwarded');
    };

    subtest 'search' => sub {
        my $client = MockTest::client();
        my $body = $client->datasphere->documents->search(query_string => 'hello');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'POST', 'POST');
        is($j->{path}, '/api/datasphere/documents/search', 'path');
        is($j->{matched_route}, 'datasphere.search_documents', 'matched route');
        is(($j->{body} || {})->{query_string}, 'hello', 'query_string forwarded');
    };

    subtest 'list_chunks' => sub {
        my $client = MockTest::client();
        my $body = $client->datasphere->documents->list_chunks('doc-1001');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/datasphere/documents/doc-1001/chunks', 'path');
        is($j->{matched_route}, 'datasphere.list_document_chunks', 'matched route');
    };

    subtest 'get_chunk' => sub {
        my $client = MockTest::client();
        my $body = $client->datasphere->documents->get_chunk('doc-1001', 'ch-1');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/datasphere/documents/doc-1001/chunks/ch-1', 'path');
        is($j->{matched_route}, 'datasphere.get_document_chunk', 'matched route');
    };

    subtest 'delete_chunk' => sub {
        my $client = MockTest::client();
        $client->datasphere->documents->delete_chunk('doc-1001', 'ch-1');
        my $j = MockTest::journal_last();
        is($j->{method}, 'DELETE', 'DELETE');
        is($j->{path}, '/api/datasphere/documents/doc-1001/chunks/ch-1', 'path');
        is($j->{matched_route}, 'datasphere.delete_document_chunk', 'matched route');
    };

    subtest 'get' => sub {
        my $client = MockTest::client();
        my $body = $client->datasphere->documents->get('doc-1001');
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'GET', 'GET');
        is($j->{path}, '/api/datasphere/documents/doc-1001', 'path');
        is($j->{matched_route}, 'datasphere.get_document', 'matched route');
    };

    subtest 'update' => sub {
        my $client = MockTest::client();
        my $body = $client->datasphere->documents->update('doc-1001', tags => ['x']);
        is(ref $body, 'HASH', 'hashref');
        my $j = MockTest::journal_last();
        is($j->{method}, 'PATCH', 'PATCH');
        is($j->{path}, '/api/datasphere/documents/doc-1001', 'path');
        is($j->{matched_route}, 'datasphere.update_document', 'matched route');
        is_deeply(($j->{body} || {})->{tags}, ['x'], 'tags forwarded');
    };

    subtest 'delete' => sub {
        my $client = MockTest::client();
        $client->datasphere->documents->delete_resource('doc-1001');
        my $j = MockTest::journal_last();
        is($j->{method}, 'DELETE', 'DELETE');
        is($j->{path}, '/api/datasphere/documents/doc-1001', 'path');
        is($j->{matched_route}, 'datasphere.delete_document', 'matched route');
    };
};

# -------------------- Errors --------------------

subtest 'TestDatasphereErrors' => sub {
    subtest 'list_server_error' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('datasphere.list_documents', 500, { error => 'internal' });
        my $ok = eval { $client->datasphere->documents->list(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 500, 'status 500');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'datasphere.list_documents', 'matched route');
        is($j->{response_status}, 500, 'journaled 500');
    };

    subtest 'create_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('datasphere.create_document', 422, { error => 'url required' });
        my $ok = eval { $client->datasphere->documents->create(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'datasphere.create_document', 'matched route');
        is($j->{response_status}, 422, 'journaled 422');
    };

    subtest 'search_unprocessable' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('datasphere.search_documents', 422, { error => 'bad query' });
        my $ok = eval { $client->datasphere->documents->search(); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 422, 'status 422');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'datasphere.search_documents', 'matched route');
        is($j->{response_status}, 422, 'journaled 422');
    };

    subtest 'list_chunks_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('datasphere.list_document_chunks', 404, { error => 'not found' });
        my $ok = eval { $client->datasphere->documents->list_chunks('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'datasphere.list_document_chunks', 'matched route');
        is($j->{response_status}, 404, 'journaled 404');
    };

    subtest 'get_chunk_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('datasphere.get_document_chunk', 404, { error => 'not found' });
        my $ok = eval { $client->datasphere->documents->get_chunk('doc-1001', 'missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'datasphere.get_document_chunk', 'matched route');
        is($j->{response_status}, 404, 'journaled 404');
    };

    subtest 'delete_chunk_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('datasphere.delete_document_chunk', 404, { error => 'not found' });
        my $ok = eval { $client->datasphere->documents->delete_chunk('doc-1001', 'missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'datasphere.delete_document_chunk', 'matched route');
        is($j->{response_status}, 404, 'journaled 404');
    };

    subtest 'get_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('datasphere.get_document', 404, { error => 'not found' });
        my $ok = eval { $client->datasphere->documents->get('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'datasphere.get_document', 'matched route');
        is($j->{response_status}, 404, 'journaled 404');
    };

    subtest 'update_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('datasphere.update_document', 404, { error => 'not found' });
        my $ok = eval { $client->datasphere->documents->update('missing', tags => ['x']); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'datasphere.update_document', 'matched route');
        is($j->{response_status}, 404, 'journaled 404');
    };

    subtest 'delete_not_found' => sub {
        my $client = MockTest::client();
        MockTest::scenario_set('datasphere.delete_document', 404, { error => 'not found' });
        my $ok = eval { $client->datasphere->documents->delete_resource('missing'); 1 };
        my $e = $@;
        ok(!$ok, 'raised');
        isa_ok($e, 'SignalWire::REST::HttpClient::Error');
        is($e->status_code, 404, 'status 404');
        my $j = MockTest::journal_last();
        is($j->{matched_route}, 'datasphere.delete_document', 'matched route');
        is($j->{response_status}, 404, 'journaled 404');
    };
};

done_testing();
