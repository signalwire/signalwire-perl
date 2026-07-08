#!/usr/bin/env perl
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# swml-dump.pl — the Perl port's SWML dump program for the cross-port SWML
# differ (porting-sdk/scripts/diff_port_swml.py).
#
# For each swml_corpus case it builds an AgentBase, applies the setter chain,
# renders the SWML document, and extracts the observed dotted path (e.g.
# "ai.prompt.pom") — emitting ONE JSON object mapping
#
#     case-id -> extracted-fragment
#
# to stdout. The differ canonicalizes both sides and byte-compares against the
# python oracle. Only stdout carries JSON. Mirrors signalwire-go/cmd/swml-dump.
#
# Run from the signalwire-perl repo root:
#
#     perl -Ilib bin/swml-dump.pl

use strict;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use FindBin qw($RealBin);
use File::Spec;
use JSON ();

use lib File::Spec->catdir( $RealBin, File::Spec->updir, 'lib' );

use SignalWire::Agent::AgentBase;

# new_agent constructs a demo AgentBase (name "demo", route "/demo"); POM is on
# by default so prompt_add_section renders into ai.prompt.pom, matching the oracle.
sub new_agent {
    return SignalWire::Agent::AgentBase->new( name => 'demo', route => '/demo' );
}

# extract walks a dotted path into a rendered SWML doc. "ai.prompt" means: find
# the ai verb in sections.main, then index into it — the Perl mirror of
# diff_port_swml._extract.
sub extract ( $doc, $path ) {
    my $ai;
    if ( ref $doc eq 'HASH' && ref $doc->{sections} eq 'HASH' ) {
        my $main = $doc->{sections}{main};
        if ( ref $main eq 'ARRAY' ) {
            for my $sec (@$main) {
                if ( ref $sec eq 'HASH' && exists $sec->{ai} ) {
                    $ai = $sec->{ai};
                    last;
                }
            }
        }
    }
    my $node = defined $ai ? { ai => $ai } : $doc;
    for my $part ( split /\./, $path ) {
        return undef unless ref $node eq 'HASH';
        $node = $node->{$part};
    }
    return $node;
}

# pick reduces a map fragment to the listed keys (mirrors the oracle's `pick`).
sub pick ( $frag, @keys ) {
    return $frag unless ref $frag eq 'HASH';
    return { map { $_ => $frag->{$_} } @keys };
}

# swaig_field mirrors the oracle's SWAIG-function filter (diff_port_swml
# build_oracle): given the ai.SWAIG.functions LIST, find the entry whose
# `function` matches $fn, then return that entry's $field.
sub swaig_field ( $frag, $fn, $field ) {
    return undef unless ref $frag eq 'ARRAY';
    for my $f (@$frag) {
        next unless ref $f eq 'HASH';
        return $f->{$field} if defined $f->{function} && $f->{function} eq $fn;
    }
    return undef;
}

sub render ($a) {
    return $a->render_swml();
}

sub main {
    my %out;

    # swml_set_prompt_llm_params: two set_prompt_llm_params calls MERGE.
    {
        my $a = new_agent();
        $a->set_prompt_llm_params( temperature => 0.5 );
        $a->set_prompt_llm_params( top_p       => 0.9 );
        $out{swml_set_prompt_llm_params} = pick( extract( render($a), 'ai.prompt' ), 'temperature', 'top_p' );
    }

    # swml_set_post_prompt_llm_params: establish a post-prompt, then merge params.
    {
        my $a = new_agent();
        $a->set_post_prompt('Summarize the call.');
        $a->set_post_prompt_llm_params( temperature => 0.3 );
        $a->set_post_prompt_llm_params( top_p       => 0.8 );
        $out{swml_set_post_prompt_llm_params} =
            pick( extract( render($a), 'ai.post_prompt' ), 'temperature', 'top_p' );
    }

    # swml_add_language: engine/model/voice carried into ai.languages.
    {
        my $a = new_agent();
        $a->add_language(
            name  => 'English', code   => 'en-US', voice => 'rime.spore',
            engine => 'rime',   model => 'mistv2',
        );
        $out{swml_add_language} = extract( render($a), 'ai.languages' );
    }

    # swml_add_pattern_hint: structured hint into ai.hints.
    {
        my $a = new_agent();
        $a->add_pattern_hint(
            { hint => 'SignalWire', pattern => 'signal wire', replace => 'SignalWire', ignore_case => 1 } );
        $out{swml_add_pattern_hint} = extract( render($a), 'ai.hints' );
    }

    # swml_add_hint: a plain string hint.
    {
        my $a = new_agent();
        $a->add_hint('SignalWire');
        $out{swml_add_hint} = extract( render($a), 'ai.hints' );
    }

    # swml_prompt_add_section: POM sections render into ai.prompt.pom.
    {
        my $a = new_agent();
        $a->prompt_add_section( 'Role', 'You are a helpful assistant.' );
        $a->prompt_add_section( 'Rules', undef, bullets => [ 'Be concise', 'Be accurate' ] );
        $out{swml_prompt_add_section} = extract( render($a), 'ai.prompt.pom' );
    }

    # swml_add_pronunciation: renders into ai.pronounce. Python's kwarg
    # `with_text` maps to the Perl native `with` (the rendered SWML key).
    {
        my $a = new_agent();
        $a->add_pronunciation( replace => 'SW', with => 'SignalWire', ignore_case => JSON::true );
        $out{swml_add_pronunciation} = extract( render($a), 'ai.pronounce' );
    }

    # swml_define_tool_complete_schema: define_tool given a COMPLETE
    # {type,properties,required} schema must render ai.SWAIG.functions[?
    # function=lookup].parameters as that schema FLAT (pass-through), NOT
    # double-wrapped in another {type:object, properties:{...}} layer. Mirrors
    # python swaig_function._ensure_parameter_structure (returns the schema as-is
    # when type+properties are already present).
    {
        my $a      = new_agent();
        my $schema = {
            type       => 'object',
            properties => { q => { type => 'string' } },
            required   => ['q'],
        };
        $a->define_tool(
            name        => 'lookup',
            description => 'Look up a thing',
            parameters  => $schema,
            handler     => sub { return; },
        );
        $out{swml_define_tool_complete_schema} =
            swaig_field( extract( render($a), 'ai.SWAIG.functions' ), 'lookup', 'parameters' );
    }

    print JSON->new->canonical->encode( \%out ), "\n";
    return 0;
}

exit main();
