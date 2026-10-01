#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Behavior parity bundle — regression tests for the four AgentBase fixes
# tracked as issues #190, #191, #185, #182. Each fix aligns Perl with the
# clean TypeScript reference (signalwire-typescript/src). See the PR
# "fix(agent): behavior parity bundle (#190/#191/#185/#182)".

use_ok('SignalWire::Agent::AgentBase');

# ============================================================
# #190 — set_global_data MERGES (does NOT replace)
#
# TS reference: AgentBase.setGlobalData calls safeAssign(this.globalData,
# data) — identical to updateGlobalData. Existing keys are preserved;
# incoming keys overwrite only on collision. A replacing setGlobalData
# would silently clobber skill-contributed keys.
# ============================================================
subtest 'set_global_data merges instead of replacing' => sub {
    my $a = SignalWire::Agent::AgentBase->new( name => 'gd_merge' );
    $a->set_global_data( { existing => 'keep' } );
    $a->set_global_data( { added    => 'new' } );
    is( $a->global_data->{existing}, 'keep', 'prior key preserved (merge, not replace)' );
    is( $a->global_data->{added},    'new',  'new key added' );

    # Collision: incoming value wins on the colliding key only.
    $a->set_global_data( { existing => 'overwritten' } );
    is( $a->global_data->{existing}, 'overwritten', 'colliding key overwritten' );
    is( $a->global_data->{added},    'new',         'non-colliding key still preserved' );
};

# ============================================================
# #191 — set_function_includes drops invalid entries and warns per drop
#
# TS reference: AgentBase.setFunctionIncludes filters to entries that
# have a truthy `url` AND an array `functions`
# (includes.filter(inc => inc.url && Array.isArray(inc.functions))).
# Python parity (ai_config_mixin.set_function_includes) drops the same
# invalid entries. The Perl port additionally warns once per dropped
# entry (matching the established codebase idiom — cf.
# set_internal_fillers carping on unrecognized names).
# ============================================================
subtest 'set_function_includes keeps valid entries' => sub {
    my $a     = SignalWire::Agent::AgentBase->new( name => 'fi_valid' );
    my $valid = { url => 'https://example.com/swaig', functions => ['f1'] };
    $a->set_function_includes( [$valid] );
    is( scalar @{ $a->function_includes }, 1,                           'valid include kept' );
    is( $a->function_includes->[0]{url},   'https://example.com/swaig', 'url preserved' );
};

subtest 'set_function_includes drops invalid entries and warns per drop' => sub {
    my $a = SignalWire::Agent::AgentBase->new( name => 'fi_drop' );

    my $valid     = { url       => 'https://example.com/swaig', functions => ['f1'] };
    my $no_url    = { functions => ['f2'] };                                           # missing url
    my $no_funcs  = { url => 'https://x.example' };                              # missing functions
    my $bad_funcs = { url => 'https://y.example', functions => 'not-an-array' };

    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    $a->set_function_includes( [ $valid, $no_url, $no_funcs, $bad_funcs ] );

    is( scalar @{ $a->function_includes }, 1, 'only the one valid include kept' );
    is( $a->function_includes->[0]{url},
        'https://example.com/swaig', 'valid include is the survivor' );

    is( scalar @warnings, 3, 'one warning per dropped entry (3 drops)' );
    like( join( "\n", @warnings ), qr/function_include/i, 'warning mentions function include' );
};

# ============================================================
# #185 — empty prompt emits the default fallback text
#
# TS reference: renderSwml emits prompt.text = prompt || `You are
# ${this.name}, a helpful AI assistant.` Python parity
# (prompt_mixin.get_prompt) returns the identical default string
# "You are {name}, a helpful AI assistant." when no prompt/POM is set.
# The Perl bug omitted the prompt key entirely when empty.
# ============================================================
subtest 'empty prompt falls back to default text' => sub {
    my $a = SignalWire::Agent::AgentBase->new( name => 'fallback_bot', use_pom => 0 );

    # No prompt text and no POM sections.
    my $swml = $a->render_swml;
    my @ai   = grep { exists $_->{ai} } @{ $swml->{sections}{main} };
    ok( exists $ai[0]{ai}{prompt}, 'prompt key emitted even when empty' );
    is(
        $ai[0]{ai}{prompt}{text},
        'You are fallback_bot, a helpful AI assistant.',
        'default fallback prompt text emitted (matches TS/Python)'
    );
};

subtest 'non-empty prompt is unchanged by the fallback' => sub {
    my $a = SignalWire::Agent::AgentBase->new( name => 'real_bot', use_pom => 0 );
    $a->set_prompt_text('Custom prompt');
    my $swml = $a->render_swml;
    my @ai   = grep { exists $_->{ai} } @{ $swml->{sections}{main} };
    is( $ai[0]{ai}{prompt}{text}, 'Custom prompt', 'explicit prompt preserved (no fallback)' );
};

# ============================================================
# #182 — prompt_add_to_section / prompt_add_subsection auto-create
#
# TS reference: PomBuilder.addToSection and addSubsection both create
# the (parent) section when absent
# (if (!this.sectionMap.has(...)) this.addSection(...)).
# The Perl bug made both a silent no-op when the section was missing.
# ============================================================
subtest 'prompt_add_to_section auto-creates missing section' => sub {
    my $a = SignalWire::Agent::AgentBase->new( name => 'auto_to' );
    $a->prompt_add_to_section( 'Brand New', body => 'hello', bullets => ['b1'] );
    is( scalar @{ $a->pom_sections }, 1, 'section auto-created' );
    my $sec = $a->pom_sections->[0];
    is( $sec->{title}, 'Brand New', 'auto-created section has the requested title' );
    like( $sec->{body}, qr/hello/, 'body applied to auto-created section' );
    is_deeply( $sec->{bullets}, ['b1'], 'bullets applied to auto-created section' );
};

subtest 'prompt_add_subsection auto-creates missing parent' => sub {
    my $a = SignalWire::Agent::AgentBase->new( name => 'auto_sub' );
    $a->prompt_add_subsection( 'Missing Parent', 'Child', 'child body' );
    is( scalar @{ $a->pom_sections }, 1, 'parent section auto-created' );
    my $sec = $a->pom_sections->[0];
    is( $sec->{title}, 'Missing Parent', 'auto-created parent has the requested title' );
    ok( exists $sec->{subsections}, 'subsection list created under parent' );
    is( $sec->{subsections}[0]{title}, 'Child',      'subsection added under auto-created parent' );
    is( $sec->{subsections}[0]{body},  'child body', 'subsection body applied' );
};

subtest 'prompt_add_to_section still appends to an existing section' => sub {
    my $a = SignalWire::Agent::AgentBase->new( name => 'existing_to' );
    $a->prompt_add_section( 'Sec', 'Original' );
    $a->prompt_add_to_section( 'Sec', body => 'appended' );
    is( scalar @{ $a->pom_sections }, 1, 'no duplicate section created' );
    like( $a->pom_sections->[0]{body}, qr/Original/, 'original body retained' );
    like( $a->pom_sections->[0]{body}, qr/appended/, 'new body appended' );
};

done_testing;
