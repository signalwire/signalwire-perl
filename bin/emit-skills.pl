#!/usr/bin/env perl
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# emit-skills.pl — the Perl port's SKILL-DUMP program for the cross-port
# SKILL-CONTRACT differ (porting-sdk/scripts/diff_skill_contracts.py).
#
# The sibling of bin/emit-corpus.pl, for built-in SKILLS rather than
# FunctionResult. The drift/surface gates see signatures + symbol names and
# EMISSION sees FunctionResult->to_hash; NONE sees a skill's SWAIG tool contract
# — the {name, parameters, required, enum} each skill registers. This program
# builds that contract for every covered skill so the differ can compare it
# against the Python reference.
#
# HOW IT WORKS
#   1. Read the shared corpus (porting-sdk/scripts/skill_contract_corpus.py —
#      the single source of truth) as JSON: { corpus: [ {id, skill, config} ] }.
#   2. For each entry: look up the skill class via SkillRegistry->get_factory,
#      construct it with a tiny CAPTURING fake agent + the corpus config as
#      params, run setup(), then register_tools(). SkillBase REQUIRES a blessed
#      `agent` (a weak_ref isa-checked to be an object), so the fake agent is a
#      real blessed object. It records BOTH registration paths a skill can use:
#        * handler tools  — $self->define_tool(...)  -> agent->define_tool(%opts)
#        * DataMap tools  — $self->agent->register_swaig_function({...})
#   3. Print ONE JSON object { id -> [ {name, parameters, required?} ] } to
#      stdout. Logs/diagnostics go to stderr. The id set equals corpus_ids() by
#      construction (the differ rejects a mismatch as a setup error).
#
# THE CONTRACT (what the differ compares — DESCRIPTIONS are NOT compared)
#   Each tool reduces to {name, parameters:{p:{type,enum?}}, required:[...]}.
#   Both registration shapes carry the WRAPPED parameter schema
#   ({type:'object', properties:{...}, required:[...]}); the differ reads the
#   `required` from inside that wrapper, so we forward each tool's parameters
#   verbatim and let the differ normalise.
#
# Run from the signalwire-perl repo root:
#
#     perl bin/emit-skills.pl
#
# (the differ invokes exactly this; see --dump-cmd in run-ci.sh.)

use strict;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use FindBin qw($RealBin);
use File::Spec;
use JSON ();

# Make the SDK importable when run from the repo root (bin/.. = repo root;
# lib/ is a sibling of bin/). Mirrors bin/emit-corpus.pl.
use lib File::Spec->catdir( $RealBin, File::Spec->updir, 'lib' );

use SignalWire::Skills::SkillRegistry;

# --------------------------------------------------------------------------- #
# Capturing fake agent.
# --------------------------------------------------------------------------- #
# SkillBase isa-checks `agent` to be a blessed object (a weak_ref to the owning
# AgentBase). We don't need a real agent to enumerate tool SCHEMAS — only an
# object that records what the skill registers. A skill reaches the agent two
# ways:
#   * via SkillBase->define_tool, which calls $self->agent->define_tool(%opts)
#   * directly via $self->agent->register_swaig_function($swaig_hashref)
# Both land here and are captured as {name, parameters, required?}.
{

    package SignalWire::Skills::_CapturingAgent;
    use strict;
    use warnings;

    sub new ($class) { return bless { captured => [] }, $class }

    sub captured ($self) { return $self->{captured} }

    # Handler tool: define_tool(name => ..., parameters => {wrapped}, required => [...]?, ...)
    sub define_tool ( $self, %opts ) {
        my $tool = { name => $opts{name}, parameters => $opts{parameters} // {} };

        # A handler tool may carry `required` either inside the wrapped
        # parameters schema OR as a sibling key; forward the sibling form so
        # the differ can fold it in.
        $tool->{required} = $opts{required} if defined $opts{required};
        push @{ $self->{captured} }, $tool;
        return $self;
    }

    # DataMap / raw SWAIG tool: register_swaig_function({ function => ...,
    # parameters => {wrapped, required:[...]}, data_map => {...}, ... }).
    sub register_swaig_function ( $self, $fn ) {
        return $self unless ref $fn eq 'HASH';
        push @{ $self->{captured} },
            {
            name       => $fn->{function},
            parameters => $fn->{parameters} // {},
            };
        return $self;
    }

    # Tolerate any other agent method a skill may poke during setup/register
    # (add_hint, set_global_data, prompt_add_section, ...): swallow silently.
    our $AUTOLOAD;

    sub AUTOLOAD ( $self, @ ) {
        my $name = $AUTOLOAD;
        $name =~ s/.*:://;
        return if $name eq 'DESTROY';
        return $self;
    }
}

# --------------------------------------------------------------------------- #
# Locate + load the shared skill corpus.
# --------------------------------------------------------------------------- #
# Walk upward from this file to find porting-sdk/scripts/skill_contract_corpus.py
# (the adjacency convention), honoring $PORTING_SDK / $PORTING_SDK_PATH first.
sub find_corpus_script {
    for my $base ( grep {defined} $ENV{PORTING_SDK}, $ENV{PORTING_SDK_PATH} ) {
        my $cand = File::Spec->catfile( $base, 'scripts', 'skill_contract_corpus.py' );
        return $cand if -f $cand;
    }
    my $dir = $RealBin;
    for ( 1 .. 8 ) {
        my $cand = File::Spec->catfile( $dir, File::Spec->updir, 'porting-sdk',
            'scripts', 'skill_contract_corpus.py' );
        return $cand if -f $cand;
        my $parent = File::Spec->catdir( $dir, File::Spec->updir );
        last if File::Spec->rel2abs($parent) eq File::Spec->rel2abs($dir);
        $dir = $parent;
    }
    my $home = $ENV{HOME} // '';
    if ($home) {
        my $cand = File::Spec->catfile( $home, 'src', 'porting-sdk', 'scripts',
            'skill_contract_corpus.py' );
        return $cand if -f $cand;
    }
    die "emit-skills: cannot locate porting-sdk/scripts/skill_contract_corpus.py "
        . "(clone porting-sdk adjacent to this repo, or set PORTING_SDK).\n";
}

sub load_corpus {
    my $script = find_corpus_script();
    my $json   = qx{python3 "$script"};
    die "emit-skills: failed to run python3 on $script (exit $?)\n" if $? != 0;
    die "emit-skills: empty corpus from $script\n" unless length $json;
    my $data = JSON->new->decode($json);
    return $data->{corpus} // die "emit-skills: corpus key missing in $script output\n";
}

# --------------------------------------------------------------------------- #
# Build the contract list for one corpus entry.
# --------------------------------------------------------------------------- #
sub contracts_for ($entry) {
    my $skill_name = $entry->{skill};
    my $config     = $entry->{config} // {};

    my $class = SignalWire::Skills::SkillRegistry->get_factory($skill_name);
    die "emit-skills: no registered factory for covered skill '$skill_name'\n"
        unless defined $class;

    my $agent = SignalWire::Skills::_CapturingAgent->new;

    # Construct with the fake agent + the corpus config as params. Pass a copy
    # of the config so a skill that mutates params (SkillBase BUILD deletes
    # swaig_fields) can't corrupt the shared corpus structure.
    my $skill = $class->new( agent => $agent, params => { %{$config} } );

    unless ( $skill->setup ) {
        die "emit-skills: skill '$skill_name' setup() returned false with the "
            . "corpus config — config drift between the corpus and the port.\n";
    }
    $skill->register_tools;

    return [ @{ $agent->captured } ];
}

# --------------------------------------------------------------------------- #
# main: emit one JSON object { id => [ contract, ... ] }.
# --------------------------------------------------------------------------- #
sub main {
    my $corpus = load_corpus();

    my %out;
    for my $entry (@$corpus) {
        my $id = $entry->{id};
        $out{$id} = contracts_for($entry);
    }

    print JSON->new->canonical->encode( \%out ), "\n";
    return 0;
}

exit main();
