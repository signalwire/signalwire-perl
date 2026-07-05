package SignalWire::Skills::SkillName;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# Built-in skill names as a typed, named closed set.
#
# Perl is dynamically typed and has no real enums, so this buys NO
# compile-time typo checking — a bare string like 'datetiem' still only
# fails at load time, when the registry can't find the skill. What it
# DOES buy:
#   - a single source of truth for the 17 built-in skill names, co-located
#     with the skill system (the list otherwise lives only inside
#     SkillRegistry::_load_all_builtins and the test suite);
#   - editor autocomplete + discoverability via named constants;
#   - SkillName->all for iteration / validation and SkillName->is_builtin
#     for membership checks.
#
# The constants ARE the canonical wire strings, so nothing about
# AgentBase->add_skill / remove_skill / has_skill changes: they still take
# a string. That keeps parity with the Python reference (bare str) and
# leaves custom / third-party skill names working automatically — an
# unknown string is simply not in this set.
#
#     use SignalWire::Skills::SkillName qw(DATETIME);
#     $agent->add_skill( DATETIME );                  # imported constant
#     $agent->add_skill( SignalWire::Skills::SkillName::DATETIME() );  # FQ
#     $agent->add_skill( 'datetime' );                # string (Python parity)
#     $agent->add_skill( 'my_custom_skill' );         # open set: custom skill
#
# The names are exported on request (Exporter), so callers can pull just the
# ones they use, or `:all` for every built-in name.
#
# Mirrors the cross-port Tier-1 idiom proof (PHP's backed enum SkillName,
# TypeScript's union type, etc.) adapted to Perl's constants idiom.

use strict;
use warnings;

use Exporter 'import';

# Each constant's value is the skill's registered wire name — the exact
# string passed to SkillRegistry->register_skill in the matching
# SignalWire::Skills::Builtin::* module. Keep this list in lockstep with
# SkillRegistry::_load_all_builtins.
use constant {
    API_NINJAS_TRIVIA     => 'api_ninjas_trivia',
    CLAUDE_SKILLS         => 'claude_skills',
    CUSTOM_SKILLS         => 'custom_skills',
    DATASPHERE            => 'datasphere',
    DATASPHERE_SERVERLESS => 'datasphere_serverless',
    DATETIME              => 'datetime',
    GOOGLE_MAPS           => 'google_maps',
    INFO_GATHERER         => 'info_gatherer',
    JOKE                  => 'joke',
    MATH                  => 'math',
    NATIVE_VECTOR_SEARCH  => 'native_vector_search',
    PLAY_BACKGROUND_FILE  => 'play_background_file',
    SPIDER                => 'spider',
    SWML_TRANSFER         => 'swml_transfer',
    WEATHER_API           => 'weather_api',
    WEB_SEARCH            => 'web_search',
    WIKIPEDIA_SEARCH      => 'wikipedia_search',
};

# Constants are exported on request; `:all` pulls every built-in name.
our @EXPORT_OK = qw(
    API_NINJAS_TRIVIA CLAUDE_SKILLS CUSTOM_SKILLS DATASPHERE
    DATASPHERE_SERVERLESS DATETIME GOOGLE_MAPS INFO_GATHERER JOKE MATH
    NATIVE_VECTOR_SEARCH PLAY_BACKGROUND_FILE SPIDER
    SWML_TRANSFER WEATHER_API WEB_SEARCH WIKIPEDIA_SEARCH
);
our %EXPORT_TAGS = ( all => [@EXPORT_OK] );

# Sorted list of every built-in wire name. Sorted so the order matches
# SkillRegistry->list_skills (which sorts its keys).
my @ALL = sort qw(
    api_ninjas_trivia
    claude_skills
    custom_skills
    datasphere
    datasphere_serverless
    datetime
    google_maps
    info_gatherer
    joke
    math
    native_vector_search
    play_background_file
    spider
    swml_transfer
    weather_api
    web_search
    wikipedia_search
);

my %IS_BUILTIN = map { $_ => 1 } @ALL;

# SkillName->all — arrayref of the 17 built-in skill wire names (sorted).
sub all {
    return [@ALL];
}

# SkillName->is_builtin($name) — true if $name is one of the built-in
# skills, false for custom / unknown names. Accepts the bareword constant
# too (it's just the string).
sub is_builtin {
    my ( $class, $name ) = @_;
    return 0 unless defined $name;
    return exists $IS_BUILTIN{$name} ? 1 : 0;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::SkillName - built-in skill names as a typed closed set

=head1 SYNOPSIS

    use SignalWire::Skills::SkillName qw(DATETIME);

    $agent->add_skill( DATETIME );          # imported constant
    $agent->add_skill( 'datetime' );        # string (Python parity)
    $agent->add_skill( 'my_custom_skill' ); # open set: custom skill

    # Membership / iteration helpers:
    SignalWire::Skills::SkillName->is_builtin('datetime');     # 1
    SignalWire::Skills::SkillName->is_builtin('my_custom');    # 0
    @{ SignalWire::Skills::SkillName->all };                   # 17 names

=head1 DESCRIPTION

The 17 built-in skill names, surfaced as typed, named constants. Each
constant's value is the skill's registered wire name — the exact string
passed to C<< SkillRegistry->register_skill >> in the matching
C<SignalWire::Skills::Builtin::*> module.

The constants B<are> the canonical wire strings, so nothing about
C<< AgentBase->add_skill >> / C<remove_skill> / C<has_skill> changes: they
still take a string. That keeps parity with the Python reference (a bare
C<str>) and leaves custom / third-party skill names working automatically
— an unknown string is simply not in this set.

This buys a single source of truth for the built-in names (otherwise they
live only inside C<SkillRegistry::_load_all_builtins> and the test suite),
plus editor autocomplete and the membership/iteration helpers below.

=head1 CONSTANTS

Exported on request via L<Exporter>; C<:all> pulls every name. The full
set: C<API_NINJAS_TRIVIA>, C<CLAUDE_SKILLS>, C<CUSTOM_SKILLS>,
C<DATASPHERE>, C<DATASPHERE_SERVERLESS>, C<DATETIME>, C<GOOGLE_MAPS>,
C<INFO_GATHERER>, C<JOKE>, C<MATH>, C<NATIVE_VECTOR_SEARCH>,
C<PLAY_BACKGROUND_FILE>, C<SPIDER>,
C<SWML_TRANSFER>, C<WEATHER_API>, C<WEB_SEARCH>, C<WIKIPEDIA_SEARCH>.

=head1 METHODS

=head2 all

    my $aref = SignalWire::Skills::SkillName->all;

Arrayref of the 17 built-in skill wire names, sorted so the order matches
C<< SkillRegistry->list_skills >>.

=head2 is_builtin

    my $bool = SignalWire::Skills::SkillName->is_builtin($name);

True if C<$name> is one of the built-in skills, false for custom /
unknown names. Accepts the bareword constant too.

=head1 SEE ALSO

L<SignalWire::Skills::SkillRegistry>,
L<SignalWire::Skills::SkillManager>,
L<SignalWire::Skills::SkillBase>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
