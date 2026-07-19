package SignalWire::Skills::Builtin::ApiNinjasTrivia;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# DataMap-based API Ninjas trivia skill. Mirrors signalwire-python's
# skills/api_ninjas_trivia/skill.py:get_tools — the SDK does NOT issue
# the HTTP request itself; the SignalWire SWML platform fetches the
# webhook URL described in the data_map, runs the response template,
# and returns the formatted result to the LLM. The SDK's job here is
# to register the right DataMap shape with the right URL/headers.

use strict;
use warnings;
use Moo;
use JSON ();
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill( 'api_ninjas_trivia', __PACKAGE__ );

has '+skill_name'                  => ( default => sub { 'api_ninjas_trivia' } );
has '+skill_description'           => ( default => sub { 'Get trivia questions from API Ninjas' } );
has '+supports_multiple_instances' => ( default => sub { 1 } );

my @ALL_CATEGORIES = qw(
    artliterature language sciencenature general fooddrink
    peopleplaces geography historyholidays entertainment
    toysgames music mathematics religionmythology
    sportsleisure
);

# Honor API_NINJAS_BASE_URL env var so the audit fixture
# (audit_skills_dispatch.py) can redirect us at a local HTTP server.
# When unset we use the canonical https://api.api-ninjas.com/v1/trivia
# URL Python writes verbatim. The audit's expected_path_substring is
# `trivia`, which is preserved either way.
sub _trivia_url {
    my $override = $ENV{API_NINJAS_BASE_URL};
    if ($override) {
        $override =~ s{/+$}{};
        return "$override/v1/trivia";
    }
    return 'https://api.api-ninjas.com/v1/trivia';
}

sub setup { return 1 }

# Python parity: get_tools returns the raw SWAIG tool DEFINITION hash(es)
# (the DataMap tool the skill provides). register_tools builds on top of
# this by registering each returned tool with the agent.
sub get_tools {
    my ($self)     = @_;
    my $tool_name  = $self->params->{tool_name}  // 'get_trivia';
    my $api_key    = $self->params->{api_key}    // '';
    my $categories = $self->params->{categories} // [@ALL_CATEGORIES];

    require SignalWire::SWAIG::FunctionResult;

    my $no_results = SignalWire::SWAIG::FunctionResult->new(
        response => 'Sorry, I cannot get trivia questions right now. Please try again later.', )
        ->to_hash;
    my $on_success = SignalWire::SWAIG::FunctionResult->new(
              response => 'Category %{array[0].category} question: %{array[0].question} '
            . 'Answer: %{array[0].answer}, be sure to give the user time to answer '
            . 'before saying the answer.', )->to_hash;

    my $url = _trivia_url();

    return [
        {
            function    => $tool_name,
            description => "Get trivia questions for " . ( $tool_name =~ s/_/ /gr ),
            parameters  => {
                type       => 'object',
                properties => {
                    category => {
                        type        => 'string',
                        description => 'Category for trivia question. Options: '
                            . join( '; ', @$categories ),
                        enum => $categories,
                    },
                },
                required => ['category'],
            },
            data_map => {
                webhooks => [
                    {
                        url     => "$url?category=%{args.category}",
                        method  => 'GET',
                        headers => { 'X-Api-Key' => $api_key },
                        output  => $on_success,
                    }
                ],
                error_keys => ['error'],
                output     => $no_results,
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
        api_key    => { type => 'string', required => 1, hidden => 1 },
        categories => { type => 'array',  default  => [@ALL_CATEGORIES] },
        tool_name  => { type => 'string', default  => 'get_trivia' },
    };
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::Builtin::ApiNinjasTrivia - trivia-question skill backed by the API Ninjas trivia API

=head1 SYNOPSIS

    # Skills are added to an agent by their registered name, not used directly:
    $agent->add_skill('api_ninjas_trivia', { api_key => $API_NINJAS_KEY });

    # Optionally rename the tool or restrict categories:
    $agent->add_skill('api_ninjas_trivia', {
        api_key    => $API_NINJAS_KEY,
        tool_name  => 'get_trivia',
        categories => [ 'sciencenature', 'geography' ],
    });

=head1 DESCRIPTION

L<SignalWire::Skills::Builtin::ApiNinjasTrivia> is the Perl port of the Python
reference C<signalwire.skills.api_ninjas_trivia.skill>. It registers a single
DataMap-based SWAIG tool (default name C<get_trivia>) that fetches a trivia
question from the API Ninjas trivia API.

Being DataMap-based, the SDK does not issue the HTTP request itself: it registers
a tool whose C<data_map> tells the SignalWire SWML platform which webhook URL to
fetch (C<https://api.api-ninjas.com/v1/trivia>, with the caller's C<X-Api-Key>)
and which response template to render. The skill supports multiple instances.

=head1 METHODS

=over

=item C<get_tools>

Returns an arrayref of the raw SWAIG tool-definition hash(es) this skill provides
(the trivia DataMap tool). Honors the C<tool_name>, C<api_key>, and C<categories>
params.

=item C<register_tools>

Registers each tool from C<get_tools> with the agent.

=item C<setup>

Instance setup hook; returns true.

=item C<get_parameter_schema>

Returns the configuration schema: C<api_key> (required), C<categories> (array),
and C<tool_name>, merged over the base skill schema.

=back

=head1 SEE ALSO

L<SignalWire::Skills::SkillBase>, L<SignalWire::Skills::Builtin::Joke>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
