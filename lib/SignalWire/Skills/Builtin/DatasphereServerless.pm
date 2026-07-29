package SignalWire::Skills::Builtin::DatasphereServerless;
use strict;
use warnings;
use Moo;
use JSON         ();
use MIME::Base64 qw(encode_base64);
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill( 'datasphere_serverless', __PACKAGE__ );

has '+skill_name' => ( default => sub { 'datasphere_serverless' } );
has '+skill_description' => ( default =>
        sub { 'Search knowledge using SignalWire DataSphere with serverless DataMap execution' } );
has '+supports_multiple_instances' => ( default => sub { 1 } );

sub setup { return 1 }

sub register_tools {
    my ($self) = @_;
    my $tool_name = $self->params->{tool_name} // 'search_knowledge';

    my $space = $self->params->{space_name} // '';
    my $auth  = encode_base64(
        ( $self->params->{project_id} // '' ) . ':' . ( $self->params->{token} // '' ), '' );
    my $count    = $self->params->{count}    // 1;
    my $distance = $self->params->{distance} // 3.0;

    # DataMap-based tool: register as a SWAIG function definition.
    # The engine reads ONLY "params" and "headers" off a webhook (mod_openai/actions.c:735-739),
    # and expands ${formatted_results} from the "foreach" block -- see the commit message.
    return $self->agent->register_swaig_function(
        {
            function    => $tool_name,
            description =>
'Search the knowledge base for information on any topic and return relevant results',
            parameters => {
                type       => 'object',
                properties => {
                    query => { type => 'string', description => 'The search query' },
                },
                required => ['query'],
            },
            data_map => {
                webhooks => [
                    {
                        method  => 'POST',
                        url     => 'https://' . $space . '/api/datasphere/documents/search',
                        headers => {
                            'Content-Type'  => 'application/json',
                            'Authorization' => "Basic $auth",
                        },
                        params => {
                            document_id  => $self->params->{document_id} // '',
                            query_string => '${args.query}',
                            count        => $count,
                            distance     => $distance,
                        },
                        foreach => {
                            input_key  => 'chunks',
                            output_key => 'formatted_results',
                            max        => $count,
                            append     => "=== RESULT ===\n"
                                . '${this.text}' . "\n"
                                . ( '=' x 50 ) . "\n\n",
                        },
                        output => {
                            response =>
                                'I found results for "${args.query}":\n\n${formatted_results}',
                            action => [ { say => 'Here are the search results.' } ],
                        },
                    }
                ],
            },
        }
    );
}

sub get_hints { return [] }

sub get_global_data {
    my ($self) = @_;
    return {
        datasphere_serverless_enabled => JSON::true,
        document_id                   => $self->params->{document_id} // '',
        knowledge_provider            => 'SignalWire DataSphere (Serverless)',
    };
}

sub _get_prompt_sections {
    return [
        {
            title   => 'Knowledge Search Capability (Serverless)',
            body    => 'You have access to a serverless knowledge base search.',
            bullets => [
                'Use the search tool to find relevant information',
                'Results are processed server-side for efficiency',
            ],
        }
    ];
}

sub get_parameter_schema {
    return {
        %{ SignalWire::Skills::SkillBase->get_parameter_schema },
        space_name  => { type => 'string',  required => 1 },
        project_id  => { type => 'string',  required => 1 },
        token       => { type => 'string',  required => 1 },
        document_id => { type => 'string',  required => 1 },
        count       => { type => 'integer', default  => 1, min => 1, max => 10 },
        distance    => { type => 'number',  default  => 3.0 },
    };
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::Builtin::DatasphereServerless - DataSphere knowledge search via serverless DataMap execution

=head1 SYNOPSIS

    $agent->add_skill('datasphere_serverless', {
        space_name  => 'example.signalwire.com',
        project_id  => $PROJECT_ID,
        token       => $TOKEN,
        document_id => $DOC_ID,
    });

=head1 DESCRIPTION

L<SignalWire::Skills::Builtin::DatasphereServerless> is the Perl port of the
Python reference C<signalwire.skills.datasphere_serverless.skill>. It registers a
DataMap-based SWAIG tool (default name C<search_knowledge>) that searches the
SignalWire DataSphere knowledge base.

This is the serverless counterpart to L<SignalWire::Skills::Builtin::Datasphere>:
rather than issuing the HTTP call from the SDK, it registers a C<data_map> whose
webhook POSTs to C<< /api/datasphere/documents/search >> and whose output
template is rendered by the SignalWire SWML platform. The skill supports multiple
instances.

=head1 METHODS

=over

=item C<register_tools>

Registers the DataMap C<search_knowledge> tool (name overridable via C<tool_name>)
with the agent via C<register_swaig_function>.

=item C<get_global_data>

Returns the skill's global-data contribution (C<datasphere_serverless_enabled>,
C<document_id>, C<knowledge_provider>).

=item C<get_hints>

Returns an empty hint list.

=item C<setup>

Instance setup hook; returns true.

=item C<get_parameter_schema>

Returns the configuration schema: C<space_name>, C<project_id>, C<token>,
C<document_id> (all required), plus C<count> and C<distance>.

=back

=head1 SEE ALSO

L<SignalWire::Skills::Builtin::Datasphere>, L<SignalWire::Skills::SkillBase>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
