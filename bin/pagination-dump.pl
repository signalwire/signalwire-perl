#!/usr/bin/env perl
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# pagination-dump.pl — the Perl port's PAGINATION-CORPUS dump program for the
# cross-port behavioral differ (porting-sdk/scripts/diff_port_pagination.py).
#
# Drives the SDK's REST PaginatedIterator through the three shared corpus
# fixtures against a live mock_signalwire (each page body — including links.next —
# armed FIFO via the mock's scenario store on a list endpoint) and prints the
# per-fixture CLASSIFICATION map as JSON on stdout:
#
#   empty_page_with_next   {continued_past_empty: bool, items_seen: int}
#   repeating_cursor_guard {loop_guarded: bool, hung: bool}
#   exhaustion             {terminated: bool, total_items: int}
#
# The golden (what a correct port emits) is
# `python3 scripts/diff_port_pagination.py --show-oracle`. The classifications
# are booleans + fixed item counts, so the dump is deterministic. A paginator that
# stops on the empty page reds empty_page_with_next; one with no cycle guard HANGS
# and the bounded watchdog here (+ the differ's deadline) reds it LOUD.
#
# Protocol: stdout = ONE JSON object mapping fixture-id -> classification map.
# Only stdout carries JSON (setup noise is routed to stderr).
#
# Run from the signalwire-perl repo root (mock auto-spawned or via
# MOCK_SIGNALWIRE_PORT):
#
#   perl -Ilib bin/pagination-dump.pl

use strict;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use FindBin qw($RealBin);
use File::Spec;
use JSON ();
use Test::More ();    # MockTest uses plan(skip_all) on a missing mock

use lib File::Spec->catdir( $RealBin, File::Spec->updir, 'lib' );
use lib File::Spec->catdir( $RealBin, File::Spec->updir, 't', 'lib' );

use SignalWire::REST::Pagination ();

# Keep stdout PURE JSON (the differ does json.loads(proc.stdout)); redirect the
# STDOUT filehandle to STDERR during setup, restore it only to emit the final JSON.
open( my $REAL_STDOUT, '>&', \*STDOUT ) or die "dup stdout: $!";
open( STDOUT, '>&', \*STDERR ) or die "redirect stdout->stderr: $!";

require MockTest;

# The list endpoint the mock's scenario store overrides FIFO (a stable
# spec-derived endpoint id returning a {data, links} shape) — the same endpoint
# the perl pagination_mock test uses.
my $LIST_PATH        = '/api/fabric/addresses';
my $LIST_ENDPOINT_ID = 'fabric.list_fabric_addresses';

# Bounded watchdog for the cycle-guard fixture: a paginator with no guard loops
# forever, so a walk that does not terminate inside this window is HUNG.
my $CYCLE_WATCHDOG_S = 8;

sub next_link ($token) {
    return "http://example.com$LIST_PATH?page_token=$token";
}

# Arm one FIFO page (data + links) on the list endpoint via the auth-scoped
# scenario control frame (MockTest::scenario_set forwards {status,response}).
sub push_page ( $data, $links ) {
    MockTest::scenario_set( $LIST_ENDPOINT_ID, 200, { data => $data, links => $links } );
    return;
}

sub new_iterator ($client) {
    return SignalWire::REST::Pagination::PaginatedIterator->new(
        http     => $client->_http,
        path     => $LIST_PATH,
        data_key => 'data',
    );
}

# empty_page_with_next — page 1 empty but carries links.next; page 2 has the item.
# A naive `while data:` stops on page 1 and drops page 2.
sub run_empty_page_with_next ($client) {
    push_page( [], { next => next_link('EP_page2') } );
    push_page( [ { id => 'found-after-empty' } ], {} );
    my @ids = map { $_->{id} } new_iterator($client)->all;
    return {
        continued_past_empty =>
            ( @ids == 1 && $ids[0] eq 'found-after-empty' ) ? JSON::true : JSON::false,
        items_seen => scalar(@ids),
    };
}

# repeating_cursor_guard — both pages point at the SAME links.next cursor. A
# paginator with no cycle guard re-fetches forever; a bounded watchdog reds it.
sub run_repeating_cursor_guard ($client) {
    push_page( [ { id => 'loop-1' } ], { next => next_link('LOOP') } );
    push_page( [ { id => 'loop-2' } ], { next => next_link('LOOP') } );
    my @ids;
    my $hung = 0;
    my $ok   = eval {
        local $SIG{ALRM} = sub { die "watchdog\n" };
        alarm $CYCLE_WATCHDOG_S;
        @ids = map { $_->{id} } new_iterator($client)->all;
        alarm 0;
        1;
    };
    if ( !$ok ) {
        alarm 0;
        $hung = 1 if $@ =~ /watchdog/;
    }
    return { loop_guarded => JSON::false, hung => JSON::true } if $hung;
    my $guarded = ( @ids == 2 && $ids[0] eq 'loop-1' && $ids[1] eq 'loop-2' );
    return {
        loop_guarded => $guarded ? JSON::true : JSON::false,
        hung         => JSON::false,
    };
}

# exhaustion — three pages; the walk must terminate yielding exactly all 5 items.
sub run_exhaustion ($client) {
    push_page( [ { id => 'x-1' }, { id => 'x-2' } ], { next => next_link('EX_page2') } );
    push_page( [ { id => 'x-3' }, { id => 'x-4' } ], { next => next_link('EX_page3') } );
    push_page( [ { id => 'x-5' } ], {} );
    my @ids = map { $_->{id} } new_iterator($client)->all;
    my $exact = ( join( ',', @ids ) eq 'x-1,x-2,x-3,x-4,x-5' );
    return {
        terminated  => $exact ? JSON::true : JSON::false,
        total_items => scalar(@ids),
    };
}

my %out;
# A fresh client (fresh auth-scoped scenario view) per fixture so an armed FIFO
# sequence never crosses between fixtures.
$out{empty_page_with_next}   = run_empty_page_with_next( MockTest::client() );
$out{repeating_cursor_guard} = run_repeating_cursor_guard( MockTest::client() );
$out{exhaustion}             = run_exhaustion( MockTest::client() );

print {$REAL_STDOUT} JSON->new->canonical->encode( \%out ), "\n";
