#!/usr/bin/env perl
# Mock-backed REST coverage tests translated from
# signalwire-python/tests/unit/rest/test_relay_registry_full_mock.py
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MockTest;

my $BASE = '/api/relay/rest/registry/beta';

# -------------------- Brands: Success --------------------

subtest 'brands_test_list' => sub {
    my $client = MockTest::client();
    my $body = $client->registry->brands->list();
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/brands", 'path');
    is($last->{matched_route}, 'relay-rest.list_brands', 'matched route');
};

subtest 'brands_test_create' => sub {
    my $client = MockTest::client();
    my $body = $client->registry->brands->create({ entity_type => 'PRIVATE_PROFIT' });
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, "$BASE/brands", 'path');
    is($last->{matched_route}, 'relay-rest.create_brand', 'matched route');
    is(($last->{body} || {})->{entity_type}, 'PRIVATE_PROFIT', 'entity_type forwarded');
};

subtest 'brands_test_get' => sub {
    my $client = MockTest::client();
    my $body = $client->registry->brands->get('brand-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/brands/brand-1", 'path');
    is($last->{matched_route}, 'relay-rest.retrieve_brand', 'matched route');
};

subtest 'brands_test_list_campaigns' => sub {
    my $client = MockTest::client();
    my $body = $client->registry->brands->list_campaigns('brand-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/brands/brand-1/campaigns", 'path');
    is($last->{matched_route}, 'relay-rest.list_campaigns', 'matched route');
};

subtest 'brands_test_create_campaign' => sub {
    my $client = MockTest::client();
    my $body = $client->registry->brands->create_campaign('brand-1', { usecase => 'LOW_VOLUME' });
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, "$BASE/brands/brand-1/campaigns", 'path');
    is($last->{matched_route}, 'relay-rest.create_campaign', 'matched route');
    is(($last->{body} || {})->{usecase}, 'LOW_VOLUME', 'usecase forwarded');
};

# -------------------- Brands: Errors --------------------

subtest 'brands_test_list_server_error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.list_brands', 500, { error => 'boom' });
    my $ok = eval { $client->registry->brands->list(); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.list_brands', 'matched route');
    is($last->{response_status}, 500, 'journaled 500');
};

subtest 'brands_test_create_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.create_brand', 422, { error => 'bad' });
    my $ok = eval { $client->registry->brands->create({}); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.create_brand', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

subtest 'brands_test_get_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.retrieve_brand', 404, { error => 'nope' });
    my $ok = eval { $client->registry->brands->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.retrieve_brand', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'brands_test_list_campaigns_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.list_campaigns', 404, { error => 'nope' });
    my $ok = eval { $client->registry->brands->list_campaigns('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.list_campaigns', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'brands_test_create_campaign_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.create_campaign', 422, { error => 'bad' });
    my $ok = eval { $client->registry->brands->create_campaign('brand-1', {}); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.create_campaign', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

# -------------------- Campaigns: Success --------------------

subtest 'campaigns_test_get' => sub {
    my $client = MockTest::client();
    my $body = $client->registry->campaigns->get('camp-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/campaigns/camp-1", 'path');
    is($last->{matched_route}, 'relay-rest.retrieve_campaign', 'matched route');
};

subtest 'campaigns_test_update' => sub {
    my $client = MockTest::client();
    my $body = $client->registry->campaigns->update('camp-1', description => 'x');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'PUT', 'PUT');
    is($last->{path}, "$BASE/campaigns/camp-1", 'path');
    is($last->{matched_route}, 'relay-rest.update_campaign', 'matched route');
    is(($last->{body} || {})->{description}, 'x', 'description forwarded');
};

subtest 'campaigns_test_list_numbers' => sub {
    my $client = MockTest::client();
    my $body = $client->registry->campaigns->list_numbers('camp-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/campaigns/camp-1/numbers", 'path');
    is($last->{matched_route}, 'relay-rest.list_number_assignments', 'matched route');
};

subtest 'campaigns_test_list_orders' => sub {
    my $client = MockTest::client();
    my $body = $client->registry->campaigns->list_orders('camp-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/campaigns/camp-1/orders", 'path');
    is($last->{matched_route}, 'relay-rest.list_orders', 'matched route');
};

subtest 'campaigns_test_create_order' => sub {
    my $client = MockTest::client();
    my $body = $client->registry->campaigns->create_order('camp-1', numbers => ['pn-1']);
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'POST', 'POST');
    is($last->{path}, "$BASE/campaigns/camp-1/orders", 'path');
    is($last->{matched_route}, 'relay-rest.create_order', 'matched route');
    is_deeply(($last->{body} || {})->{numbers}, ['pn-1'], 'numbers forwarded');
};

# -------------------- Campaigns: Errors --------------------

subtest 'campaigns_test_get_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.retrieve_campaign', 404, { error => 'nope' });
    my $ok = eval { $client->registry->campaigns->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.retrieve_campaign', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'campaigns_test_update_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.update_campaign', 404, { error => 'nope' });
    my $ok = eval { $client->registry->campaigns->update('missing', description => 'x'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.update_campaign', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'campaigns_test_list_numbers_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.list_number_assignments', 404, { error => 'nope' });
    my $ok = eval { $client->registry->campaigns->list_numbers('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.list_number_assignments', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'campaigns_test_list_orders_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.list_orders', 404, { error => 'nope' });
    my $ok = eval { $client->registry->campaigns->list_orders('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.list_orders', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

subtest 'campaigns_test_create_order_unprocessable' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.create_order', 422, { error => 'bad' });
    my $ok = eval { $client->registry->campaigns->create_order('camp-1'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 422, 'status 422');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.create_order', 'matched route');
    is($last->{response_status}, 422, 'journaled 422');
};

# -------------------- Orders: Success + Error --------------------

subtest 'orders_test_get' => sub {
    my $client = MockTest::client();
    my $body = $client->registry->orders->get('order-1');
    is(ref $body, 'HASH', 'response is a hashref');
    my $last = MockTest::journal_last();
    is($last->{method}, 'GET', 'GET');
    is($last->{path}, "$BASE/orders/order-1", 'path');
    is($last->{matched_route}, 'relay-rest.retrieve_order', 'matched route');
};

subtest 'orders_test_get_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.retrieve_order', 404, { error => 'nope' });
    my $ok = eval { $client->registry->orders->get('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.retrieve_order', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

# -------------------- Numbers: Success + Error --------------------

subtest 'numbers_test_delete' => sub {
    my $client = MockTest::client();
    $client->registry->numbers->delete('num-1');
    my $last = MockTest::journal_last();
    is($last->{method}, 'DELETE', 'DELETE');
    is($last->{path}, "$BASE/numbers/num-1", 'path');
    is($last->{matched_route}, 'relay-rest.delete_number_assignment', 'matched route');
};

subtest 'numbers_test_delete_not_found' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set('relay-rest.delete_number_assignment', 404, { error => 'nope' });
    my $ok = eval { $client->registry->numbers->delete('missing'); 1 };
    my $e = $@;
    ok(!$ok, 'raised');
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 404, 'status 404');
    my $last = MockTest::journal_last();
    is($last->{matched_route}, 'relay-rest.delete_number_assignment', 'matched route');
    is($last->{response_status}, 404, 'journaled 404');
};

done_testing();
