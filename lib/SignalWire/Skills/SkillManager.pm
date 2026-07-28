package SignalWire::Skills::SkillManager;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.

use strict;
use warnings;
use Moo;
use Carp qw(croak);

# Subroutine signatures (stable since Perl 5.36, this SDK's declared floor —
# see cpanfile / Makefile.PL MIN_PERL_VERSION).
use feature 'signatures';
no warnings 'experimental::signatures';

has agent         => ( is       => 'ro',  required => 1,    weak_ref => 1 );
has loaded_skills => ( init_arg => undef, is       => 'rw', default  => sub { {} } );

# Python parity: SkillManager.load_skill(skill_name, skill_class=None,
# params=None). ``skill_class`` omitted means "look the class up in the
# registry"; ``params`` omitted means "no configuration".
sub load_skill ( $self, $skill_name, $skill_class = undef, $params = undef ) {
    $params //= {};

    # Get class from registry if not provided
    if ( !$skill_class ) {
        require SignalWire::Skills::SkillRegistry;
        my $factory = SignalWire::Skills::SkillRegistry->get_factory($skill_name);
        unless ($factory) {
            return ( 0, "Skill '$skill_name' not found in registry" );
        }
        $skill_class = $factory;
    }

    # Create instance
    my $instance = eval { $skill_class->new( agent => $self->agent, params => {%$params}, ); };
    if ($@) {
        return ( 0, "Failed to create skill '$skill_name': $@" );
    }

    my $instance_key = $instance->get_instance_key;

    # Check for duplicates
    if ( exists $self->loaded_skills->{$instance_key} ) {
        if ( !$instance->supports_multiple_instances ) {
            return ( 0,
                "Skill '$skill_name' already loaded and does not support multiple instances" );
        }
    }

    # Validate env vars
    unless ( $instance->validate_env_vars ) {
        return ( 0, "Skill '$skill_name' missing required environment variables" );
    }

    # Setup
    my $ok = eval { $instance->setup };
    if ( $@ || !$ok ) {
        my $err = $@ || 'setup() returned false';
        return ( 0, "Skill '$skill_name' setup failed: $err" );
    }

    # Register tools
    eval { $instance->register_tools };
    if ($@) {
        return ( 0, "Skill '$skill_name' register_tools failed: $@" );
    }

    # Merge hints
    my $hints = $instance->get_hints;
    if ( $hints && @$hints ) {
        $self->agent->add_hints(@$hints);
    }

    # Merge global data
    my $gdata = $instance->get_global_data;
    if ( $gdata && %$gdata ) {
        $self->agent->update_global_data($gdata);
    }

    # Add prompt sections
    my $sections = $instance->get_prompt_sections;
    if ( $sections && @$sections ) {
        for my $sec (@$sections) {
            $self->agent->prompt_add_section( $sec->{title}, $sec->{body},
                ( $sec->{bullets} ? ( bullets => $sec->{bullets} ) : () ),
            );
        }
    }

    $self->loaded_skills->{$instance_key} = $instance;
    return ( 1, '' );
}

sub unload_skill {
    my ( $self, $key ) = @_;
    my $instance = delete $self->loaded_skills->{$key};
    if ($instance) {
        eval { $instance->cleanup };
        return 1;
    }
    return 0;
}

sub list_skills {
    my ($self) = @_;
    return [ keys %{ $self->loaded_skills } ];
}

sub has_skill {
    my ( $self, $key ) = @_;
    return exists $self->loaded_skills->{$key} ? 1 : 0;
}

# Get a loaded skill instance by identifier (instance key), or undef.
#
# Python parity: ``SkillManager.get_skill(skill_identifier)`` — returns
# the loaded SkillBase instance when present, otherwise undef.
sub get_skill {
    my ( $self, $skill_identifier ) = @_;
    return $self->loaded_skills->{$skill_identifier};
}

# List instance keys of currently-loaded skills.
#
# Python parity: ``SkillManager.list_loaded_skills()`` — the keys of the
# loaded_skills map (distinct from the registry's list of available
# skills).
sub list_loaded_skills {
    my ($self) = @_;
    return [ keys %{ $self->loaded_skills } ];
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::SkillManager - load and manage skills for a single agent

=head1 SYNOPSIS

    use SignalWire::Skills::SkillManager;

    my $mgr = SignalWire::Skills::SkillManager->new( agent => $agent );

    my ($ok, $err) = $mgr->load_skill('datetime');
    die $err unless $ok;

    $mgr->has_skill('datetime');       # 1
    $mgr->list_loaded_skills;          # [ 'datetime' ]
    $mgr->unload_skill('datetime');

=head1 DESCRIPTION

L<SignalWire::Skills::SkillManager> is the Perl port of the Python SDK's
per-agent skill manager. It resolves skill classes (via
L<SignalWire::Skills::SkillRegistry> when a class isn't passed
directly), instantiates them against its owning agent, and wires each
loaded skill's tools, hints, global data, and prompt sections into that
agent. It tracks loaded skills by instance key and enforces the
single-instance / multi-instance rules each skill declares.

=head1 ATTRIBUTES

=over 4

=item C<agent>

The owning agent (required, read-only, held as a weak reference).

=item C<loaded_skills>

Hashref mapping instance key to loaded skill instance (read/write).

=back

=head1 METHODS

=over 4

=item C<load_skill($skill_name, $skill_class, $params)>

Load, set up, and register a skill on the agent. C<$skill_class> and
C<$params> are optional (the class is looked up in the registry when
omitted). Returns a two-element list C<($ok, $message)> — C<$ok> is C<1>
on success or C<0> with an explanatory C<$message> on failure (unknown
skill, duplicate, missing env vars, setup / registration error).

=item C<unload_skill($key)>

Remove the loaded skill identified by C<$key>, calling its C<cleanup>.
Returns C<1> if a skill was removed, C<0> otherwise.

=item C<list_skills()> / C<list_loaded_skills()>

Return an arrayref of the instance keys of currently-loaded skills.

=item C<has_skill($key)>

Return C<1> if a skill with instance key C<$key> is loaded, else C<0>.

=item C<get_skill($skill_identifier)>

Return the loaded skill instance for C<$skill_identifier>, or C<undef>.

=back

=head1 SEE ALSO

L<SignalWire::Skills::SkillRegistry>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
