package SignalWire::Skills::Builtin::Joke;
use strict;
use warnings;
use Moo;
use JSON ();
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill( 'joke', __PACKAGE__ );

has '+skill_name'        => ( default => sub { 'joke' } );
has '+skill_description' => ( default => sub { 'Tell jokes using the API Ninjas joke API' } );
has '+supports_multiple_instances' => ( default => sub { 0 } );

sub setup { return 1 }

sub register_tools {
    my ($self) = @_;
    my $tool_name = $self->params->{tool_name} // 'get_joke';

    # DataMap-style registration
    return $self->agent->register_swaig_function(
        {
            function    => $tool_name,
            description => 'Get a random joke from API Ninjas',
            parameters  => {
                type       => 'object',
                properties => {
                    type => {
                        type        => 'string',
                        description => 'Type of joke',
                        enum        => [ 'jokes', 'dadjokes' ],
                    },
                },
                required => ['type'],
            },
            data_map => {
                webhooks => [
                    {
                        method  => 'GET',
                        url     => 'https://api.api-ninjas.com/v1/${args.type}',
                        headers => { 'X-Api-Key' => $self->params->{api_key} // '' },
                        output  => {
                            response => 'Here\'s a joke: ${array[0].joke}',
                        },
                    }
                ],
            },
        }
    );
}

sub get_global_data {
    return { joke_skill_enabled => JSON::true };
}

sub _get_prompt_sections {
    return [
        {
            title   => 'Joke Telling',
            body    => 'You can tell jokes to lighten the mood.',
            bullets => [
                'Use the joke tool when the user asks for a joke',
                'Choose between regular jokes and dad jokes',
            ],
        }
    ];
}

sub get_parameter_schema {
    return {
        %{ SignalWire::Skills::SkillBase->get_parameter_schema },
        api_key   => { type => 'string', required => 1, hidden => 1 },
        tool_name => { type => 'string', default  => 'get_joke' },
    };
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::Builtin::Joke - joke-telling skill backed by the API Ninjas joke API

=head1 SYNOPSIS

    $agent->add_skill('joke', { api_key => $API_NINJAS_KEY });

    # Optionally rename the tool:
    $agent->add_skill('joke', { api_key => $API_NINJAS_KEY, tool_name => 'get_joke' });

=head1 DESCRIPTION

L<SignalWire::Skills::Builtin::Joke> is the Perl port of the Python reference
C<signalwire.skills.joke.skill>. It registers a single DataMap-based SWAIG tool
(default name C<get_joke>) that fetches a random joke from the API Ninjas joke
API. The tool's C<type> parameter selects between C<jokes> and C<dadjokes>.

Being DataMap-based, the SignalWire SWML platform fetches the webhook
(C<https://api.api-ninjas.com/v1/${args.type}>, with the caller's C<X-Api-Key>)
and renders the response template. The skill does not support multiple instances.

=head1 METHODS

=over

=item C<register_tools>

Registers the DataMap joke tool (name overridable via C<tool_name>) with the
agent via C<register_swaig_function>.

=item C<get_global_data>

Returns the skill's global-data contribution (C<joke_skill_enabled>).

=item C<setup>

Instance setup hook; returns true.

=item C<get_parameter_schema>

Returns the configuration schema: C<api_key> (required) and C<tool_name>.

=back

=head1 SEE ALSO

L<SignalWire::Skills::Builtin::ApiNinjasTrivia>, L<SignalWire::Skills::SkillBase>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
