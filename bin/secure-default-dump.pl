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
# CALL_ID, and emits per fixture the RENDERED WIRE PAYLOAD for the differ to
# classify:
#
#   {"<fixture id>": {"secure_default_true": bool, "rendered": {<functions[] entry>}}}
#
#   secure_default_true   the SDK-RECORDED secure flag for the tool, read back off
#                         the registry (true for the default case, false for the
#                         explicit case). Read, not assumed — a port that failed to
#                         default secure reds here.
#   rendered              that tool's own ``SWAIG.functions[]`` entry, VERBATIM,
#                         with every token VALUE replaced by the corpus
#                         placeholder ``<TOKEN>`` (the values are HMACs bound to
#                         (call_id, tool, secret) and vary per run; the KEY PATH is
#                         the whole contract and is preserved exactly).
#
# This program deliberately makes NO judgement about whether the render is
# correct. The previous version emitted a self-computed ``wire_reflects_secure``
# boolean, which made the gate vacuous by construction: the differ never saw the
# wire, so it could not see WHICH key a port had classified on, nor that an
# INSECURE tool had been handed its own unauthenticated per-function callback URL.
# The differ now sees the keys and decides (diff_port_secure_default.py: topology
# -> {secure_default_true, has_own_webhook, token_carrier}).
#
# Protocol: stdout carries ONE JSON object mapping corpus fixture-id =>
# payload map, and NOTHING else. All diagnostics must go to stderr.
# Deterministic: no socket, no timing.
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
# Process-wide on purpose: this dump program keeps the SDK logger off stdout for
# its entire run (only JSON goes there), so the setting must outlive any scope.
## no critic (Variables::RequireLocalizedPunctuationVars)
$ENV{SIGNALWIRE_LOG_LEVEL} = 'critical';
$ENV{SIGNALWIRE_LOG_MODE}  = 'off';
## use critic

use SignalWire::Agent::AgentBase;

# Must match porting-sdk/scripts/secure_default_corpus.py CALL_ID + tool names.
my $CALL_ID = 'call-secure-default-fixture';

my @CORPUS = (
    {
        id            => 'define_tool_default_is_secure',
        kind          => 'secure_default',
        tool_name     => 'sd_default_secure',
        expect_secure => 1,
    },
    {
        id            => 'define_tool_explicit_insecure',
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

# Must match porting-sdk/scripts/secure_default_corpus.py TOKEN_PLACEHOLDER.
my $TOKEN_PLACEHOLDER = '<TOKEN>';

# Replace the VALUE of every token-suffixed query parameter in a URL with the
# placeholder, preserving the parameter KEYS and their order exactly.
sub redact_url_tokens {
    my ($url) = @_;
    my $q = index( $url, '?' );
    return $url if $q < 0;
    my $head = substr( $url, 0, $q + 1 );
    my @out;
    for my $pair ( split /&/, substr( $url, $q + 1 ), -1 ) {
        my ( $k, $v ) = split /=/, $pair, 2;
        if ( defined $v && lc($k) =~ /token\z/ ) {
            push @out, "$k=$TOKEN_PLACEHOLDER";
        } else {
            push @out, $pair;
        }
    }
    return $head . join( '&', @out );
}

# Normalize a rendered functions[] entry: replace every nondeterministic token
# VALUE (an HMAC) with the placeholder while preserving every KEY and key path
# exactly — both a token-suffixed field and a token-suffixed query parameter on a
# URL value. Mirrors diff_port_secure_default.redact_entry so the differ's
# re-application is a no-op (idempotent).
sub redact_entry {
    my ($entry) = @_;
    return {} unless ref $entry eq 'HASH';
    my %out;
    for my $k ( keys %$entry ) {
        my $v = $entry->{$k};
        if ( defined $v && !ref $v ) {
            if ( lc($k) =~ /token\z/ ) {
                $out{$k} = $TOKEN_PLACEHOLDER;
                next;
            }
            if ( index( $v, '://' ) >= 0 || substr( $v, 0, 1 ) eq '/' ) {
                $out{$k} = redact_url_tokens($v);
                next;
            }
        }
        $out{$k} = $v;
    }
    return \%out;
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
    my $name      = $case->{tool_name};
    my $is_secure = $recorded{$name} // 0;
    $out{ $case->{id} } = {
        secure_default_true => $is_secure ? JSON::true : JSON::false,
        rendered            => redact_entry( $by_name{$name} ),
    };
}

print JSON->new->canonical->encode( \%out ), "\n";
