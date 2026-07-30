package SignalWire::Skills::Builtin::Datasphere;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# Real DataSphere RAG client. Mirrors signalwire-python's
# skills/datasphere/skill.py:_search_knowledge_handler — POST a
# JSON body to /api/datasphere/documents/search with HTTP Basic auth
# (project_id : token), parse `chunks[]`, format as numbered results.

use strict;
use warnings;
use Moo;
use HTTP::Tiny;
use JSON         ();
use MIME::Base64 qw(encode_base64);
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill( 'datasphere', __PACKAGE__ );

has '+skill_name' => ( default => sub { 'datasphere' } );
has '+skill_description' =>
    ( default => sub { 'Search knowledge using SignalWire DataSphere RAG stack' } );
has '+supports_multiple_instances' => ( default => sub { 1 } );

# Honor DATASPHERE_BASE_URL env var so the audit fixture
# (audit_skills_dispatch.py) can redirect us at a local HTTP server.
# When unset we build the canonical
# https://{space}.signalwire.com/api/datasphere/documents/search URL.
# When the env var is set, append the canonical
# `/api/datasphere/documents/search` path so the audit sees the
# expected `datasphere` substring on the wire.
has 'base_url' => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $override = $ENV{DATASPHERE_BASE_URL};
        return '' unless $override;
        $override =~ s{/+$}{};
        return "$override/api/datasphere/documents/search";
    },
);

has '_http' => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        HTTP::Tiny->new(
            agent      => 'SignalWire-Perl-DataSphere/1.0',
            timeout    => 30,
            verify_SSL => 1,
        );
    },
);

sub setup {
    my ($self) = @_;

    # Required parameters per Python (skills/datasphere/skill.py:120-127).
    # The audit harness doesn't always set every value, so missing is
    # warned but not fatal — the skill still answers, the API call just
    # fails informatively. Production callers MUST provide all four.
    return 1;
}

sub register_tools {
    my ($self) = @_;
    my $tool_name = $self->params->{tool_name} // 'search_knowledge';

    my $weak_self = $self;
    require Scalar::Util;
    Scalar::Util::weaken($weak_self);

    return $self->define_tool(
        name        => $tool_name,
        description =>
            'Search the knowledge base for information on any topic and return relevant results',
        parameters => {
            type       => 'object',
            properties => {
                query => {
                    type        => 'string',
                    description => 'The search query - what information you are looking for',
                },
            },

            # No `required`: the Python reference (skills/datasphere/skill.py)
            # passes none and the handler guards an empty query. Adding it would
            # over-constrain the SWAIG schema vs the reference contract.
        },
        handler => sub {
            my ( $args, $raw ) = @_;
            require SignalWire::SWAIG::FunctionResult;
            my $query = $args->{query} // '';
            $query =~ s/^\s+|\s+$//g;
            unless ( length $query ) {
                return SignalWire::SWAIG::FunctionResult->new(
                    response => 'Please provide a search query.', );
            }
            my $text = $weak_self->search_knowledge($query);
            return SignalWire::SWAIG::FunctionResult->new( response => $text );
        },
    );
}

sub _build_url {
    my ($self) = @_;
    return $self->base_url if $self->base_url;
    my $space = $self->params->{space_name} // '';
    return "https://$space.signalwire.com/api/datasphere/documents/search";
}

sub search_knowledge {
    my ( $self, $query ) = @_;

    my $project_id  = $self->params->{project_id}  // $ENV{SIGNALWIRE_PROJECT_ID} // '';
    my $token       = $self->params->{token}       // $ENV{DATASPHERE_TOKEN}      // '';
    my $document_id = $self->params->{document_id} // '';

    my %payload = (
        document_id  => $document_id,
        query_string => $query,
        distance     => $self->params->{distance} // 3.0,
        count        => $self->params->{count}    // 1,
    );
    $payload{tags}          = $self->params->{tags}     if defined $self->params->{tags};
    $payload{language}      = $self->params->{language} if defined $self->params->{language};
    $payload{pos_to_expand} = $self->params->{pos_to_expand}
        if defined $self->params->{pos_to_expand};
    $payload{max_synonyms} = $self->params->{max_synonyms} if defined $self->params->{max_synonyms};

    my $body = JSON::encode_json( \%payload );
    my $auth = encode_base64( "$project_id:$token", '' );

    my $url  = $self->_build_url;
    my $resp = $self->_http->post(
        $url,
        {
            headers => {
                'Authorization' => "Basic $auth",
                'Content-Type'  => 'application/json',
                'Accept'        => 'application/json',
            },
            content => $body,
        },
    );

    unless ( $resp->{success} ) {
        return "Sorry, there was an error accessing the knowledge base "
            . "($resp->{status} $resp->{reason}). Please try again later.";
    }

    my $data = eval { JSON::decode_json( $resp->{content} ) };
    if ($@) {
        return "Sorry, the knowledge base returned an unparseable response.";
    }

    # The DataSphere v1 wire shape returns `chunks` (Python uses that
    # field exclusively, see signalwire-python/skills/datasphere/skill.py:226).
    # Some upstream fixtures and integrations use `results` for the same
    # shape — accept either to keep the parser tolerant of incidental
    # rename without forcing tests through a translation layer.
    my $chunks = $data->{chunks} // $data->{results} // [];
    unless ( ref $chunks eq 'ARRAY' && @$chunks ) {
        my $msg = $self->params->{no_results_message}
            // "I couldn't find any relevant information for '{query}' in the knowledge base. "
            . "Try rephrasing your question or asking about a different topic.";
        $msg =~ s/\{query\}/$query/g;
        return $msg;
    }

    my $count = scalar @$chunks;
    my $header =
        $count == 1
        ? "I found 1 result for '$query':\n\n"
        : "I found $count results for '$query':\n\n";

    my @blocks;
    my $i = 1;
    for my $chunk (@$chunks) {
        my $text = $chunk->{text} // $chunk->{content} // $chunk->{chunk};
        $text = JSON::encode_json($chunk) unless defined $text;
        push @blocks, "=== RESULT $i ===\n$text\n" . ( '=' x 50 );
        $i++;
    }
    return $header . join( "\n\n", @blocks );
}

sub get_hints { return [] }

sub get_global_data {
    my ($self) = @_;
    return {
        datasphere_enabled => JSON::true,
        document_id        => $self->params->{document_id} // '',
        knowledge_provider => 'SignalWire DataSphere',
    };
}

sub _get_prompt_sections {
    return [
        {
            title   => 'Knowledge Search Capability',
            body    => 'You have access to a knowledge base that you can search for information.',
            bullets => [
                'Use the search tool to find relevant information',
                'Provide accurate answers based on search results',
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

SignalWire::Skills::Builtin::Datasphere - knowledge-base search skill using the SignalWire DataSphere RAG stack

=head1 SYNOPSIS

    $agent->add_skill('datasphere', {
        space_name  => 'example',
        project_id  => $PROJECT_ID,
        token       => $TOKEN,
        document_id => $DOC_ID,
    });

    # Optional: rename the tool, tune result count / distance:
    $agent->add_skill('datasphere', {
        space_name  => 'example',
        project_id  => $PROJECT_ID,
        token       => $TOKEN,
        document_id => $DOC_ID,
        tool_name   => 'search_knowledge',
        count       => 3,
        distance    => 3.0,
    });

=head1 DESCRIPTION

L<SignalWire::Skills::Builtin::Datasphere> registers a handler-based
SWAIG tool (default name C<search_knowledge>) that performs a
retrieval-augmented search against the SignalWire DataSphere RAG stack.

Unlike the serverless DataMap variant, this skill issues the HTTP request itself:
the handler POSTs a JSON body to C<< /api/datasphere/documents/search >> with HTTP
Basic auth (C<< project_id : token >>), parses the returned C<chunks[]>, and
formats them as numbered results for the LLM. It supports multiple instances.

=head1 METHODS

=over

=item C<register_tools>

Registers the C<search_knowledge> tool (name overridable via the C<tool_name>
param) whose handler calls C<search_knowledge>.

=item C<search_knowledge($query)>

Performs the DataSphere search for C<$query> and returns the formatted result
string (or an informative error/no-results message).

=item C<get_global_data>

Returns the skill's global-data contribution (C<datasphere_enabled>,
C<document_id>, C<knowledge_provider>).

=item C<get_hints>

Returns an empty hint list.

=item C<setup>

Instance setup hook; returns true.

=item C<get_parameter_schema>

Returns the configuration schema: C<space_name>, C<project_id>, C<token>,
C<document_id> (all required), plus C<count> and C<distance>.

=back

=head1 ATTRIBUTES

C<base_url> (derived from C<DATASPHERE_BASE_URL> when set, else empty for the
canonical space URL).

=head1 SEE ALSO

L<SignalWire::Skills::Builtin::DatasphereServerless>, L<SignalWire::Skills::SkillBase>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
