package SignalWire::Skills::Builtin::CustomSkills;
use strict;
use warnings;
use Moo;
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill( 'custom_skills', __PACKAGE__ );

has '+skill_name'                  => ( default => sub { 'custom_skills' } );
has '+skill_description'           => ( default => sub { 'Register user-defined custom tools' } );
has '+supports_multiple_instances' => ( default => sub { 1 } );

sub setup { return 1 }

sub register_tools {
    my ($self) = @_;
    my $tools = $self->params->{tools} // [];

    for my $tool_def (@$tools) {
        next unless ref $tool_def eq 'HASH';
        if ( exists $tool_def->{function} ) {
            $self->agent->register_swaig_function($tool_def);
        } elsif ( exists $tool_def->{name} ) {
            $self->agent->define_tool(%$tool_def);
        }
    }
    return;
}

sub get_parameter_schema {
    return {
        %{ SignalWire::Skills::SkillBase->get_parameter_schema },
        tools => { type => 'array', description => 'Array of tool definition objects' },
    };
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::Builtin::CustomSkills - register user-supplied SWAIG tool definitions as a skill

=head1 SYNOPSIS

    # Register arbitrary tool definitions through the skill framework:
    $agent->add_skill('custom_skills', {
        tools => [
            # A raw SWAIG function definition (has a `function` key):
            { function => 'my_tool', description => '...', parameters => {...},
              data_map => {...} },
            # ...or a define_tool-style spec (has a `name` key):
            { name => 'other_tool', description => '...', parameters => {...},
              handler => sub { ... } },
        ],
    });

=head1 DESCRIPTION

L<SignalWire::Skills::Builtin::CustomSkills> is a thin skill wrapper that lets
callers register their own tool definitions through the standard skill
mechanism.

Each element of the C<tools> param is inspected: a hash with a C<function> key is
passed to the agent's C<register_swaig_function> (a raw SWAIG definition), while a
hash with a C<name> key is passed to the agent's C<define_tool> (a handler-based
tool). Non-hash entries are skipped. The skill supports multiple instances.

=head1 METHODS

=over

=item C<register_tools>

Iterates the C<tools> param and registers each definition with the agent by its
shape (C<function> vs C<name>).

=item C<setup>

Instance setup hook; returns true.

=item C<get_parameter_schema>

Returns the configuration schema, adding the C<tools> array over the base skill
schema.

=back

=head1 SEE ALSO

L<SignalWire::Skills::SkillBase>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
