package SignalWire::Skills::Builtin::SwmlTransfer;
use strict;
use warnings;
use Moo;
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill( 'swml_transfer', __PACKAGE__ );

has '+skill_name' => ( default => sub { 'swml_transfer' } );
has '+skill_description' =>
    ( default => sub { 'Transfer calls between agents based on pattern matching' } );
has '+supports_multiple_instances' => ( default => sub { 1 } );

sub setup { return 1 }

sub register_tools {
    my ($self)      = @_;
    my $tool_name   = $self->params->{tool_name}      // 'transfer_call';
    my $description = $self->params->{description}    // 'Transfer call based on pattern matching';
    my $param_name  = $self->params->{parameter_name} // 'transfer_type';
    my $transfers   = $self->params->{transfers}      // {};

    my @patterns = keys %$transfers;

    # Build DataMap expressions from transfer patterns
    my @expressions;
    for my $pattern (@patterns) {
        my $cfg = $transfers->{$pattern};
        my $url = $cfg->{url} // $cfg->{address} // '';
        push @expressions,
            {
            string  => "\${args.$param_name}",
            pattern => $pattern,
            output  => {
                response => $cfg->{message} // "Transferring to $pattern",
                action   => [ { swml_transfer => $url } ],
            },
            };
    }

    return $self->agent->register_swaig_function(
        {
            function    => $tool_name,
            description => $description,
            parameters  => {
                type       => 'object',
                properties => {
                    $param_name => {
                        type        => 'string',
                        description => $self->params->{parameter_description}
                            // 'The transfer destination',
                    },
                },
                required => [$param_name],
            },
            data_map => { expressions => \@expressions },
        }
    );
}

sub get_hints {
    my ($self) = @_;
    my @hints = ( 'transfer', 'connect', 'speak to', 'talk to' );
    for my $pattern ( keys %{ $self->params->{transfers} // {} } ) {
        push @hints, split( /[\s_-]+/, $pattern );
    }
    return \@hints;
}

sub _get_prompt_sections {
    my ($self)       = @_;
    my $transfers    = $self->params->{transfers} // {};
    my @destinations = map { "- $_" } keys %$transfers;
    return [
        {
            title => 'Transferring',
            body  => "Available transfer destinations:\n" . join( "\n", @destinations ),
        },
        {
            title => 'Transfer Instructions',
            body  => 'When the user wants to be transferred, use the transfer tool.',
        },
    ];
}

sub get_parameter_schema {
    return {
        %{ SignalWire::Skills::SkillBase->get_parameter_schema },
        transfers             => { type => 'object', required => 1 },
        description           => { type => 'string' },
        parameter_name        => { type => 'string', default => 'transfer_type' },
        parameter_description => { type => 'string' },
        default_message       => { type => 'string' },
    };
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::Builtin::SwmlTransfer - transfer calls by pattern-matching against configured destinations

=head1 SYNOPSIS

    $agent->add_skill('swml_transfer', {
        transfers => {
            sales   => { url => 'https://.../sales',   message => 'Connecting you to sales.' },
            support => { url => 'https://.../support', message => 'Connecting you to support.' },
        },
    });

=head1 DESCRIPTION

L<SignalWire::Skills::Builtin::SwmlTransfer> registers a single
DataMap-based SWAIG tool (default name C<transfer_call>) that transfers the caller
to one of a set of configured destinations.

The C<transfers> param maps a pattern to a destination config (C<url>/C<address>
and optional C<message>); each entry becomes a C<data_map> expression that matches
the tool's parameter (default name C<transfer_type>) against the pattern and emits
a C<swml_transfer> action. The skill supports multiple instances.

=head1 METHODS

=over

=item C<register_tools>

Registers the transfer tool with the agent, building one DataMap expression per
configured transfer pattern.

=item C<get_hints>

Returns speech hints (C<transfer>, C<connect>, C<speak to>, C<talk to>, plus the
tokens of each configured pattern).

=item C<setup>

Instance setup hook; returns true.

=item C<get_parameter_schema>

Returns the configuration schema: C<transfers> (required object), C<description>,
C<parameter_name>, C<parameter_description>, and C<default_message>.

=back

=head1 SEE ALSO

L<SignalWire::Skills::SkillBase>, L<SignalWire::SWAIG::FunctionResult>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
