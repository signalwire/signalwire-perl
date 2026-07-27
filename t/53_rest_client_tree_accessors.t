#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";

use MockTest ();

# Behavioural regression guard for the RestClient resource tree.
#
# RestClient itself declares only auth + the shared HTTP client; all 22 resource
# accessors (addresses, calling, video, fabric, …) come from the GENERATED
# SignalWire::REST::Namespaces::Generated::ResourceTree Moo role it composes
# (`with`). Moo installs a role's accessors into the consuming class at
# composition time, so `$client->calling` is a real method on RestClient.
#
# This test proves that end-to-end at RUNTIME rather than by construction: it
# reaches each resource THROUGH the accessor on the client and asserts a real
# HTTP request lands on the shared porting-sdk mock with the expected path. A
# purely structural `->can` check would still pass if the tree were wired to a
# dead object, and a transport-level stub would not prove the accessor path is
# what produced the request.
#
# It also pins the accessor inventory to the reference oracle's
# signalwire.rest.client.RestClient member list, so a resource silently dropped
# from the generated role fails here and not only in the signature gate.

my $client = MockTest::client();

# Every accessor the reference's RestClient exposes (python_signatures.json,
# signalwire.rest.client.RestClient, minus __init__).
my @ACCESSORS = qw(
    addresses calling chat datasphere fabric imported_numbers logs lookup
    messages mfa number_groups phone_numbers project projects pubsub queues
    recordings registry short_codes sip_profile verified_callers video
);

subtest 'every reference accessor is reachable on the composed client' => sub {
    for my $name (@ACCESSORS) {
        ok( $client->can($name), "RestClient->can('$name')" );
        my $obj = $client->$name;
        ok( defined $obj && ref $obj, "\$client->$name returns an object" );
    }
};

# A flat resource (list) and a namespace container's sub-resource (list),
# chosen so each covers a different shape of the tree. The expected path is the
# resource's own base path; we assert the wire request the mock recorded.
my @WIRE_PROBES = (
    # [ label, coderef issuing the call, expected request path ]
    [   'calling (flat resource, direct verb)',
        sub { $client->calling->dial( to => '+15551230000', from => '+15559990000' ) },
        '/api/calling/calls',
        'POST',
    ],
    [   'phone_numbers (flat resource, list)',
        sub { $client->phone_numbers->list },
        '/api/relay/rest/phone_numbers',
        'GET',
    ],
    [   'fabric (namespace container -> sub-resource)',
        sub { $client->fabric->ai_agents->list },
        '/api/fabric/resources/ai_agents',
        'GET',
    ],
    [   'video (namespace container -> sub-resource)',
        sub { $client->video->rooms->list },
        '/api/video/rooms',
        'GET',
    ],
);

subtest 'accessor path produces a real request on the mock' => sub {
    for my $probe (@WIRE_PROBES) {
        my ( $label, $call, $expect_path, $expect_method ) = @$probe;
        eval { $call->(); 1 } or diag("call for $label returned an error: $@");
        my $entry = MockTest::journal_last();
        is( $entry->{path}, $expect_path, "$label -> path $expect_path" );
        is( uc( $entry->{method} // '' ), $expect_method, "$label -> $expect_method" );
    }
};

done_testing();
