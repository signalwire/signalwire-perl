#!/usr/bin/env perl
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# secure-default-dump.pl — the Perl port's SECURE-DEFAULT (A1) behavioral dump
# program for the cross-port secure-default differ
# (porting-sdk/scripts/diff_port_secure_default.py, corpus
# secure_default_corpus.py).
#
# The A1 contract: ``define_tool`` defaults ``secure => 1`` fleet-wide — a tool
# defined WITHOUT an explicit ``secure`` REQUIRES SWAIG token validation. The WIRE
# manifestation of ``secure`` is not a ``"secure": true`` key (that is an SDK-side
# flag and never reaches the wire); it is the per-tool ``__token`` the rendered
# SWAIG webhook carries when the SWML is rendered with an active ``call_id``
# (python agent_base.py:1040 / 1096-1100). A ``secure => 0`` tool gets NO token.
#
# This program defines both corpus tools on ONE agent — a default (no explicit
# ``secure``) and a ``secure => 0`` — renders the SWML with the FIXED corpus
# CALL_ID, and reduces each to the deterministic pair the differ compares against
# the python golden:
#
#   secure_default_true   the SDK-RECORDED secure flag for the tool, read back off
#                         the registry (true for the default case, false for the
#                         explicit case). Read, not assumed — a port that failed to
#                         default secure reds here.
#   wire_reflects_secure  a ``__token`` is present on the rendered webhook IFF the
#                         tool is secure (secure -> token present; insecure ->
#                         token correctly absent).
#
# The token VALUE is an HMAC bound to (call_id, tool, secret) and is NOT compared
# — only its PRESENCE folds into the boolean, so the golden is deterministic while
# the behavior producing it is real and unfakeable.
#
# Protocol: stdout carries ONE JSON object mapping corpus fixture-id =>
# classification map, and NOTHING else. The differ invokes this with 2>/dev/null,
# so all diagnostics must go to stderr. Deterministic: no socket, no timing.
#
# Run from the signalwire-perl repo root:
#
#     perl -Ilib bin/secure-default-dump.pl

use strict;
use warnings;

use FindBin qw($RealBin);
use File::Spec;
use JSON ();

use lib File::Spec->catdir( $RealBin, File::Spec->updir, 'lib' );

# Keep the SDK logger off stdout (only JSON goes there).
$ENV{SIGNALWIRE_LOG_LEVEL} = 'critical';
$ENV{SIGNALWIRE_LOG_MODE}  = 'off';

use SignalWire::Agent::AgentBase;

# Must match porting-sdk/scripts/secure_default_corpus.py CALL_ID + tool names.
my $CALL_ID = 'call-secure-default-fixture';

my @CORPUS = (
    {   id            => 'define_tool_default_is_secure',
        kind          => 'secure_default',
        tool_name     => 'sd_default_secure',
        expect_secure => 1,
    },
    {   id            => 'define_tool_explicit_insecure',
        kind          => 'secure_explicit_false',
        tool_name     => 'sd_explicit_insecure',
        expect_secure => 0,
    },
);

# Locate the SWAIG functions array in a rendered SWML document (sections.main ->
# the ``ai`` verb -> SWAIG.functions). Mirrors the oracle's _find_swaig_functions.
sub swaig_functions {
    my ($doc) = @_;
    return [] unless ref $doc eq 'HASH';
    my $main = eval { $doc->{sections}{main} };
    return [] unless ref $main eq 'ARRAY';
    for my $entry (@$main) {
        next unless ref $entry eq 'HASH' && ref $entry->{ai} eq 'HASH';
        my $fns = eval { $entry->{ai}{SWAIG}{functions} };
        return $fns if ref $fns eq 'ARRAY';
    }
    return [];
}

# True iff a rendered SWAIG function entry's webhook carries the reserved
# ``__token`` query parameter — the wire reflection of ``secure``. Mirrors the
# oracle's _webhook_has_token.
sub webhook_has_token {
    my ($entry) = @_;
    return 0 unless ref $entry eq 'HASH';
    my $url = $entry->{web_hook_url} // '';
    return ( index( $url, '__token=' ) >= 0 ) ? 1 : 0;
}

my $agent = SignalWire::Agent::AgentBase->new(
    name                => 'secure-default-fixture',
    route               => '/sd',
    basic_auth_user     => 'u',
    basic_auth_password => 'p',
);

# Register both corpus tools: one with NO explicit secure (must default SECURE),
# one with secure => 0.
for my $case (@CORPUS) {
    my %opts = (
        name        => $case->{tool_name},
        description => 'secure-default fixture tool',
        parameters  => {},
        handler     => sub { return { response => 'ok' } },
    );
    $opts{secure} = 0 if $case->{kind} eq 'secure_explicit_false';
    $agent->define_tool(%opts);
}

# Read back the SDK-RECORDED secure flag per tool (do NOT assume the corpus's
# expectation — reading it is what makes secure_default_true a real observation).
my %recorded;
for my $name ( keys %{ $agent->tools } ) {
    $recorded{$name} = $agent->tools->{$name}{secure} ? 1 : 0;
}

# Render WITH the fixed call_id so each SECURE tool mints its per-tool __token.
my $doc     = $agent->_render_swml_for_call( {}, $CALL_ID );
my %by_name = map { ( $_->{function} // '' ) => $_ }
    grep { ref $_ eq 'HASH' } @{ swaig_functions($doc) };

my %out;
for my $case (@CORPUS) {
    my $name          = $case->{tool_name};
    my $expect_secure = $case->{expect_secure} ? 1 : 0;
    my $is_secure     = $recorded{$name} // 0;
    my $token_present = webhook_has_token( $by_name{$name} );
    $out{ $case->{id} } = {
        secure_default_true  => $is_secure ? JSON::true : JSON::false,
        wire_reflects_secure => ( $token_present == $expect_secure ) ? JSON::true : JSON::false,
    };
}

print JSON->new->canonical->encode( \%out ), "\n";
