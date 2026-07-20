#!/usr/bin/env perl
# PERL-9: per-call request_options on the GENERATED REST resource verbs (the
# PUBLIC door), mirroring signalwire-python PY-7
# (tests/unit/rest/test_resource_request_options.py).
#
# The envelope itself (retry / timeout / abort semantics) is proven at the
# HttpClient transport level in t/rest/20_request_options.t. THIS file proves the
# reference addition PY-7 wired into the GENERATOR: every generated resource verb
# accepts a keyword-only `request_options` and threads it down to
# $self->_http->$verb(..., request_options => $ro) -- WITHOUT ever folding it into
# the wire body/query the server sees. Driven through the real HTTP::Tiny
# transport into the shared mock_signalwire; asserted on the recorded journal (the
# same journal the REST-COVERAGE gate reads) -- NOT a transport mock.
#
# Contract pinned here:
#   1. A GET resource verb (paginate/list-family) forwards request_options so a
#      retryable 503 is retried into the 200 (transport saw N attempts).
#   2. A POST/object-body resource verb (create) forwards request_options AND the
#      request_options object NEVER appears as a wire body field.
#   3. request_options is keyword-only: it is stripped from the slurpy args and
#      does not leak into the query string or the JSON body.

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use Scalar::Util qw(blessed);

use MockTest;
use SignalWire::REST::RequestOptions;

my $ADDRESSES_ENDPOINT = 'fabric.list_fabric_addresses';
my $ADDRESSES_PATH     = '/api/fabric/addresses';
my $CREATE_ENDPOINT    = 'relay-rest.create_address';
my $CREATE_PATH        = '/api/relay/rest/addresses';

# Count this client's journal entries matching (method, path) -- a DELTA measure
# (the per-process journal accumulates across subtests; see 20_request_options.t).
sub count_hits {
    my ( $method, $path ) = @_;
    my $entries = MockTest::journal_all();
    return scalar grep {
        ( $_->{method} // '' ) eq $method && ( $_->{path} // '' ) eq $path
    } @$entries;
}

# Return the most recent journal entry for (method, path) for THIS client.
sub last_hit {
    my ( $method, $path ) = @_;
    my $entries = MockTest::journal_all();
    my @m = grep {
        ( $_->{method} // '' ) eq $method && ( $_->{path} // '' ) eq $path
    } @$entries;
    return $m[-1];
}

# ---- 1. A GET resource verb forwards request_options (retry observable) -----
subtest 'get_verb_forwards_request_options' => sub {
    my $client = MockTest::client();
    my $ro = SignalWire::REST::RequestOptions->new( retries => 1, retry_backoff => 0 );

    # fabric.addresses->paginate is a generated ReadResource verb. A single armed
    # 503 + retries=1 must retry into the default 200 => 2 transport attempts.
    my $before = count_hits( 'GET', $ADDRESSES_PATH );
    # Arm a TERMINATING two-page sequence, with a 503 in front of page 1. retries=1
    # retries the 503 into page 1; page 1 carries links.next -> page 2 (terminal,
    # empty links). This proves request_options is forwarded through the paginator
    # to the page fetch (the retry is only observable if it threads down). A
    # single-503-then-default page would loop forever on the synthesized default's
    # links.next, so the terminating sequence is deliberate.
    MockTest::scenario_set( $ADDRESSES_ENDPOINT, 503, { errors => [ { code => 'X' } ] } );
    MockTest::scenario_set(
        $ADDRESSES_ENDPOINT, 200,
        {   data  => [ { id => 'ro-pg-1' } ],
            links => { next => 'http://example.com/api/fabric/addresses?page_token=ro2' },
        },
    );
    MockTest::scenario_set(
        $ADDRESSES_ENDPOINT, 200,
        { data => [ { id => 'ro-pg-2' } ], links => {} },
    );
    my $iter = $client->fabric->addresses->paginate( request_options => $ro );
    my @items = $iter->all;
    is_deeply( [ map { $_->{id} } @items ], [ 'ro-pg-1', 'ro-pg-2' ],
        'paginate walked both pages to termination' );
    is( count_hits( 'GET', $ADDRESSES_PATH ) - $before, 3,
        'paginate(request_options=>retries): 503-retry + page1 + page2 = 3 GETs '
            . '(retry threaded through the paginator)' );
};

# ---- 2. list() (CrudResource) forwards request_options ----------------------
subtest 'list_verb_forwards_request_options' => sub {
    my $client = MockTest::client();
    my $ro = SignalWire::REST::RequestOptions->new( retries => 1, retry_backoff => 0 );
    my $before = count_hits( 'GET', $CREATE_PATH );
    MockTest::scenario_set( 'relay-rest.list_addresses', 503, { errors => [ { code => 'X' } ] } );
    my $res = $client->addresses->list( request_options => $ro );
    is( count_hits( 'GET', $CREATE_PATH ) - $before, 2,
        'list(request_options=>retries) retried the 503 into the 200 (2 attempts)' );
};

# ---- 3. create() forwards request_options and NEVER leaks it into the body --
subtest 'create_verb_forwards_and_does_not_leak_request_options' => sub {
    my $client = MockTest::client();
    my $ro = SignalWire::REST::RequestOptions->new( retries => 0 );
    my $before = count_hits( 'POST', $CREATE_PATH );
    my $res = $client->addresses->create(
        address_type    => 'commercial',
        first_name      => 'Ada',
        request_options => $ro,
    );
    is( count_hits( 'POST', $CREATE_PATH ) - $before, 1, 'create issued exactly one POST' );

    my $entry = last_hit( 'POST', $CREATE_PATH );
    ok( $entry, 'captured the create POST in the journal' );
    my $body = $entry->{body} || {};
    ok( ref $body eq 'HASH', 'wire body is a JSON object' );
    ok( !exists $body->{request_options},
        'request_options is NOT folded into the wire body' );
    is( $body->{address_type}, 'commercial', 'the real field IS in the wire body' );
};

done_testing;
