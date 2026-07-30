package SignalWire::Skills::SkillRegistry;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.

use strict;
use warnings;
use File::Spec ();

# Global registry mapping skill name -> class name
my %REGISTRY;

# External skill directories registered via add_skill_directory.
# Mirrors Python's SkillRegistry._external_paths.
my @EXTERNAL_PATHS;

sub register_skill {
    my ( $class, $skill_name, $skill_class ) = @_;
    $REGISTRY{$skill_name} = $skill_class;
    return;
}

sub get_factory {
    my ( $class, $skill_name ) = @_;

    # Return if already registered
    return $REGISTRY{$skill_name} if exists $REGISTRY{$skill_name};

    # Attempt to auto-load from Builtin namespace. Translate the package name to
    # its .pm path and require THAT (a path string), so we avoid a stringy
    # `eval "require $module"` (perlcritic ProhibitStringyEval) entirely — no
    # registry input ever reaches the Perl compiler.
    my $module = 'SignalWire::Skills::Builtin::' . _camelize($skill_name);
    ( my $module_path = "$module.pm" ) =~ s{::}{/}g;
    eval { require $module_path; 1 };
    if ( !$@ ) {

        # If the module registered itself, return it
        return $REGISTRY{$skill_name} if exists $REGISTRY{$skill_name};

        # Otherwise register it
        $REGISTRY{$skill_name} = $module;
        return $module;
    }

    return;
}

sub list_skills {
    my ($class) = @_;

    # Make sure all builtins are loaded
    $class->_load_all_builtins;
    return [ sort keys %REGISTRY ];
}

# Get a skill CLASS (package name) by name, loading on demand. Mirrors
# Python's SkillRegistry.get_skill_class(name) — the class-returning
# companion to get_factory (which is the Perl-idiom factory accessor).
# Returns the package name or undef if unknown.
sub get_skill_class {
    my ( $class, $skill_name ) = @_;
    return $class->get_factory($skill_name);
}

# Ensure built-in skills are registered and return their names. Mirrors
# Python's SkillRegistry.discover_skills (a no-op there since skills load
# on-demand); Perl ships built-ins explicitly, so this guarantees they're
# registered (idempotent) and returns the registered skill names.
sub discover_skills {
    my ($class) = @_;
    $class->_load_all_builtins;
    return [ sort keys %REGISTRY ];
}

# List all skill sources and the skills available from each. Mirrors
# Python's SkillRegistry.list_all_skill_sources: a hashref keyed by source
# type. Perl has no Python-style entry_points, so that bucket is empty;
# ``registered`` holds any skill registered outside the shipped built-ins.
sub list_all_skill_sources {
    my ($class) = @_;
    $class->_load_all_builtins;
    my @builtins = qw(
        api_ninjas_trivia claude_skills custom_skills datasphere
        datasphere_serverless datetime google_maps info_gatherer joke math
        mcp_gateway native_vector_search play_background_file spider
        swml_transfer weather_api web_search wikipedia_search
    );
    my %is_builtin = map  { $_ => 1 } @builtins;
    my @registered = grep { !$is_builtin{$_} } sort keys %REGISTRY;
    return {
        'built-in'       => [ sort @builtins ],
        'external_paths' => [ map { _skill_dirs_under($_) } @EXTERNAL_PATHS ],
        'entry_points'   => [],
        'registered'     => \@registered,
    };
}

# Skill subdirectory names found directly under $path (each is a candidate
# external skill source). Non-existent / unreadable paths yield nothing.
sub _skill_dirs_under {
    my ($path) = @_;
    return () unless defined $path && -d $path;
    opendir( my $dh, $path ) or return ();
    my @dirs = grep { $_ !~ /^\./ && -d File::Spec->catdir( $path, $_ ) } readdir($dh);
    closedir $dh;
    my @sorted = sort @dirs;
    return @sorted;
}

# Get complete schema for all registered skills.
#
# Mirrors Python's ``SkillRegistry.get_all_skills_schema()`` — returns a
# hashref keyed by skill name where each value carries metadata + the
# parameter schema for that skill. Perl skills don't carry rich
# Python-style parameter introspection in v1, so the value defaults to
# the minimal shape with just the skill name; built-in skills that
# expose ``parameter_schema`` get richer detail.
sub get_all_skills_schema {
    my ($self) = @_;

    # Accept both class-method (SkillRegistry->get_all_skills_schema) and
    # instance-method ($registry->get_all_skills_schema) calls.
    my $class = ref($self) || $self || __PACKAGE__;
    $class->_load_all_builtins;
    my %schema;
    for my $name ( sort keys %REGISTRY ) {
        my $skill_class = $REGISTRY{$name};
        my %entry       = ( name => $name, parameters => {} );
        if ( ref($skill_class) eq 'CODE' ) {

            # Factory closure; can't introspect statically
            ;
        } elsif ( defined $skill_class ) {
            if ( $skill_class->can('parameter_schema') ) {
                eval {
                    my $params = $skill_class->parameter_schema;
                    $entry{parameters} = $params if ref($params) eq 'HASH';
                };
            }
            if ( $skill_class->can('skill_description') ) {
                eval { $entry{description} = $skill_class->skill_description };
            }
            if ( $skill_class->can('skill_version') ) {
                eval { $entry{version} = $skill_class->skill_version };
            }
        }
        $schema{$name} = \%entry;
    }
    return \%schema;
}

sub _load_all_builtins {
    my ($class) = @_;
    my @names = qw(
        api_ninjas_trivia claude_skills datasphere datasphere_serverless
        datetime google_maps info_gatherer joke math mcp_gateway
        native_vector_search play_background_file spider swml_transfer
        weather_api web_search wikipedia_search custom_skills
    );
    for my $name (@names) {
        $class->get_factory($name);    # triggers auto-load
    }
    return;
}

sub _camelize {
    my ($name) = @_;

    # Convert snake_case to CamelCase: api_ninjas_trivia -> ApiNinjasTrivia
    $name =~ s/_(.)/uc($1)/ge;
    return ucfirst($name);
}

sub clear_registry {
    %REGISTRY       = ();
    @EXTERNAL_PATHS = ();
    return;
}

# Add a directory to search for skills.
#
# Mirrors Python's
# `signalwire.skills.registry.SkillRegistry.add_skill_directory`:
# validate the path, die with an "X: <path>" message (Perl's analog of
# raising ValueError) when the path doesn't exist or isn't a directory,
# and de-duplicate entries in the external paths list.
# Add a load-path to search for skills AND return the file-based skills
# (SKILL.md dirs) discovered under it. Validates the load-path (dies loud on
# a missing / non-directory path — the Perl analog of Python raising
# ValueError), de-duplicates the external-paths list, then walks the path
# with the SHARED SignalWire::Skills::SkillDiscovery walker (the same one the
# claude_skills builtin uses — one implementation, two callers) and returns
# the parsed SKILL.md skills. In list context the discovered skills are
# returned; this is the framework-level load-path discovery (#75). Parity
# surface with Python's add_skill_directory (which validates + registers the
# path); the SKILL.md file discovery is the interpreted-port extension.
sub add_skill_directory {
    my ( $class, $path ) = @_;
    die "Skill directory does not exist: $path\n" unless -e $path;
    die "Path is not a directory: $path\n"        unless -d $path;
    unless ( grep { $_ eq $path } @EXTERNAL_PATHS ) {
        push @EXTERNAL_PATHS, $path;
    }

    require SignalWire::Skills::SkillDiscovery;
    return SignalWire::Skills::SkillDiscovery::discover_skills($path);
}

# Returns the registered external skill directories.
# Parity surface for Python's private `_external_paths` attribute —
# exposed under the underscored name so the signature enumerator skips
# it (matches Python convention).
sub _external_paths {
    my ($class) = @_;
    return [@EXTERNAL_PATHS];
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::SkillRegistry - global registry of available agent skills

=head1 SYNOPSIS

    use SignalWire::Skills::SkillRegistry;

    my $names = SignalWire::Skills::SkillRegistry->list_skills;
    my $class = SignalWire::Skills::SkillRegistry->get_factory('datetime');

    # Register an external skill directory (returns discovered SKILL.md skills):
    my $found = SignalWire::Skills::SkillRegistry->add_skill_directory('/path/to/skills');

=head1 DESCRIPTION

L<SignalWire::Skills::SkillRegistry> maps skill names to their classes (or factory
closures) in a process-global registry, auto-loading the shipped built-in
skills from the C<SignalWire::Skills::Builtin::> namespace on demand
(snake_case names are camelised to package names). All methods are class
methods.

=head1 METHODS

=over 4

=item C<< register_skill($skill_name, $skill_class) >>

Register C<$skill_class> under C<$skill_name>.

=item C<< get_factory($skill_name) >>

Return the class (or factory) for C<$skill_name>, auto-loading it from
the C<Builtin::> namespace if not already registered; C<undef> if
unknown.

=item C<< get_skill_class($skill_name) >>

The skill's package name, loading it on demand — an alias for
C<get_factory>. Returns C<undef> for an unknown skill. A skill's class B<is>
its factory, so the two spellings return the same thing; both exist because
either name is a natural thing to reach for.

=item C<< list_skills() >> / C<< discover_skills() >>

Ensure all built-ins are registered and return a sorted arrayref of the
registered skill names.

=item C<< list_all_skill_sources() >>

Return a hashref of skill sources keyed by type: C<built-in>,
C<external_paths>, C<entry_points> (always empty in Perl), and
C<registered> (skills registered outside the shipped built-ins).

=item C<< get_all_skills_schema() >>

Return a hashref keyed by skill name, each value carrying the skill's
metadata and parameter schema (enriched for built-ins that expose
C<parameter_schema> / C<skill_description> / C<skill_version>). Callable
as a class or instance method.

=item C<< add_skill_directory($path) >>

Register an external skill load-path (dies loud if the path is missing or
not a directory, de-duplicating the list), then walk it with the shared
skill-discovery walker and return the discovered C<SKILL.md> skills.

=item C<< clear_registry() >>

Empty the registry and external-path list (primarily for tests).

=back

=head1 SEE ALSO

L<SignalWire::Skills::SkillManager>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
