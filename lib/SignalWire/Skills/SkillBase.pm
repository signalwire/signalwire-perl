package SignalWire::Skills::SkillBase;
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.

use strict;
use warnings;
use Moo;
# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
use Carp qw(croak);
use Scalar::Util ();

# --- isa constraint helpers (coderefs; no extra deps). Each dies on a bad
# value so a misdeclared subclass fails fast at construction time. ---
my $NonEmptyStr = sub {
    croak("must be a non-empty string")
        unless defined $_[0] && !ref $_[0] && length $_[0];
};
my $ArrayRef = sub { croak("must be an arrayref") unless ref $_[0] eq 'ARRAY' };
my $HashRef  = sub { croak("must be a hashref")  unless ref $_[0] eq 'HASH'  };
# agent must be a blessed object (the AgentBase the skill is attached to),
# not a plain string/hashref.
my $Object   = sub { croak("must be an object") unless Scalar::Util::blessed($_[0]) };

# Required class-level constants (subclasses override via 'has' or '+')
has skill_name        => (is => 'ro', required => 1, isa => $NonEmptyStr);
has skill_description => (is => 'ro', required => 1, isa => $NonEmptyStr);
has skill_version     => (is => 'ro', default => sub { '1.0.0' }, isa => $NonEmptyStr);

has supports_multiple_instances => (is => 'ro', default => sub { 0 });
has required_packages           => (is => 'ro', default => sub { [] }, isa => $ArrayRef);
has required_env_vars           => (is => 'ro', default => sub { [] }, isa => $ArrayRef);

# The agent this skill is attached to
has agent  => (is => 'ro', required => 1, weak_ref => 1, isa => $Object);
# Config params passed at registration
has params => (is => 'rw', default => sub { {} }, isa => $HashRef);

# Extra SWAIG fields to merge into tool definitions
has swaig_fields => (is => 'rw', default => sub { {} }, isa => $HashRef);

sub BUILD ($self, @) {
    # Extract swaig_fields from params if present
    if (exists $self->params->{swaig_fields}) {
        $self->swaig_fields(delete $self->params->{swaig_fields});
    }
}

# --- Abstract interface (subclasses must override) ---

sub setup ($self) {
    croak(ref($self) . " must implement setup()");
}

sub register_tools ($self) {
    croak(ref($self) . " must implement register_tools()");
}

# --- Default implementations ---

sub define_tool ($self, %opts) {
    # Merge swaig_fields into the tool definition
    my %merged = (%{ $self->swaig_fields }, %opts);
    return $self->agent->define_tool(%merged);
}

sub get_hints {
    return [];
}

sub get_global_data {
    return {};
}

sub get_prompt_sections ($self) {
    return [] if $self->params->{skip_prompt};
    return $self->_get_prompt_sections;
}

sub _get_prompt_sections {
    return [];
}

sub cleanup {
    # no-op by default
}

sub validate_env_vars ($self) {
    for my $var (@{ $self->required_env_vars }) {
        return 0 unless $ENV{$var};
    }
    return 1;
}

sub get_parameter_schema {
    return {
        swaig_fields => { type => 'object', description => 'Additional SWAIG fields' },
        skip_prompt  => { type => 'boolean', description => 'Skip injecting prompt sections', default => 0 },
        tool_name    => { type => 'string',  description => 'Override the default tool name' },
    };
}

sub get_instance_key ($self) {
    my $base = $self->skill_name;
    if ($self->params->{tool_name}) {
        return $base . ':' . $self->params->{tool_name};
    }
    return $base;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::SkillBase - abstract base class for agent skills

=head1 SYNOPSIS

    package SignalWire::Skills::Builtin::MySkill;
    use Moo;
    extends 'SignalWire::Skills::SkillBase';

    has '+skill_name'        => ( default => sub { 'my_skill' } );
    has '+skill_description' => ( default => sub { 'Does a thing' } );

    sub setup          ($self) { ...; return 1; }
    sub register_tools ($self) {
        $self->define_tool( name => 'do_thing', ... );
    }

=head1 DESCRIPTION

L<SignalWire::Skills::SkillBase> is the Perl port of the Python reference's
C<SkillBase>. Every built-in or custom skill extends it. A skill declares
metadata (C<skill_name>, C<skill_description>, C<skill_version>), optional
package / environment requirements, and overrides the abstract C<setup>
and C<register_tools> hooks to wire its SWAIG tools onto the owning agent.

Construction fails fast (Moo C<isa> constraints): C<skill_name> /
C<skill_description> must be non-empty strings, C<agent> must be a blessed
object, C<required_packages> / C<required_env_vars> must be arrayrefs, and
C<params> / C<swaig_fields> must be hashrefs.

=head1 ATTRIBUTES

C<skill_name>, C<skill_description>, C<skill_version>,
C<supports_multiple_instances>, C<required_packages>,
C<required_env_vars>, C<agent>, C<params>, C<swaig_fields>.

=head1 METHODS

=over 4

=item * C<setup> / C<register_tools> — abstract; a subclass B<must>
override both (the defaults C<croak>).

=item * C<define_tool(%opts)> — register a SWAIG tool on the agent,
merging the skill's C<swaig_fields> into the definition.

=item * C<get_hints> / C<get_global_data> / C<get_prompt_sections> —
default no-op contributions a subclass may override; C<get_prompt_sections>
honours the C<skip_prompt> param.

=item * C<cleanup> — teardown hook (no-op by default).

=item * C<validate_env_vars> — true iff every C<required_env_vars> entry is
set in C<%ENV>.

=item * C<get_parameter_schema> — the JSON-schema-ish description of the
config params the skill accepts.

=item * C<get_instance_key> — the registry key for this skill instance
(C<skill_name>, optionally suffixed by C<tool_name>).

=back

=head1 SEE ALSO

L<SignalWire::Skills::SkillRegistry>,
L<SignalWire::Skills::SkillManager>,
L<SignalWire::Skills::SkillName>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
