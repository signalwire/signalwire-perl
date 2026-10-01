package SignalWire::Skills::Builtin::PlayBackgroundFile;
use strict;
use warnings;
use Moo;
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill( 'play_background_file', __PACKAGE__ );

has '+skill_name'                  => ( default => sub { 'play_background_file' } );
has '+skill_description'           => ( default => sub { 'Control background file playback' } );
has '+supports_multiple_instances' => ( default => sub { 1 } );

sub setup { return 1 }

# Python parity: get_tools returns the raw SWAIG tool DEFINITION hash(es)
# (the DataMap tool the skill provides). register_tools builds on top of
# this by registering each returned tool with the agent.
sub get_tools {
    my ($self)    = @_;
    my $tool_name = $self->params->{tool_name} // 'play_background_file';
    my $files     = $self->params->{files}     // [];

    # Build action enum from file keys
    my @actions = ('stop');
    for my $f (@$files) {
        push @actions, "start_$f->{key}" if $f->{key};
    }

    # DataMap-style tool definition with expressions
    return [
        {
            function    => $tool_name,
            description => "Control background file playback for $tool_name",
            parameters  => {
                type       => 'object',
                properties => {
                    action => {
                        type        => 'string',
                        description => 'Playback action',
                        enum        => \@actions,
                    },
                },
                required => ['action'],
            },
            data_map => {
                expressions => [
                    {
                        string  => '${args.action}',
                        pattern => 'stop',
                        output  => {
                            response => 'Stopping background playback.',
                            action   => [ { stop_background_file => {} } ],
                        },
                    },
                ],
            },
        }
    ];
}

sub register_tools {
    my ($self) = @_;
    my $result;
    for my $tool ( @{ $self->get_tools } ) {
        $result = $self->agent->register_swaig_function($tool);
    }
    return $result;
}

sub get_parameter_schema {
    return {
        %{ SignalWire::Skills::SkillBase->get_parameter_schema },
        files => {
            type        => 'array',
            required    => 1,
            description => 'Array of file objects with key, description, url'
        },
        tool_name => { type => 'string', default => 'play_background_file' },
    };
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::Builtin::PlayBackgroundFile - control background-file playback via a DataMap tool

=head1 SYNOPSIS

    $agent->add_skill('play_background_file', {
        files => [
            { key => 'hold', description => 'Hold music', url => 'https://.../hold.mp3' },
        ],
    });

=head1 DESCRIPTION

L<SignalWire::Skills::Builtin::PlayBackgroundFile> registers a single
DataMap-based SWAIG tool (default name C<play_background_file>) that lets the
agent start or stop background audio playback.

The tool's C<action> parameter is an enum built from the configured C<files>: a
C<start_$key> value per file plus C<stop>. The C<data_map> expressions map the
C<stop> action to a C<stop_background_file> action. The skill supports multiple
instances.

=head1 METHODS

=over

=item C<get_tools>

Returns an arrayref of the raw SWAIG tool-definition hash(es) this skill provides
(the background-playback DataMap tool), with the C<action> enum derived from the
C<files> param.

=item C<register_tools>

Registers each tool from C<get_tools> with the agent.

=item C<setup>

Instance setup hook; returns true.

=item C<get_parameter_schema>

Returns the configuration schema: C<files> (required array of file objects with
C<key>/C<description>/C<url>) and C<tool_name>.

=back

=head1 SEE ALSO

L<SignalWire::Skills::SkillBase>, L<SignalWire::SWAIG::FunctionResult>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
