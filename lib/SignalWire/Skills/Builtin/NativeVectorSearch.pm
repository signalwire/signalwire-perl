package SignalWire::Skills::Builtin::NativeVectorSearch;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# Network/remote-mode native vector search skill. Mirrors the reference
# ruby skill (signalwire-ruby/lib/signalwire/skills/builtin/
# native_vector_search.rb) and the Python
# signalwire.skills.native_vector_search.skill.NativeVectorSearchSkill:
# a thin SkillBase skill that POSTs a {query,count} JSON body to a remote
# search service and formats the {content,score,metadata} results. This is
# the NETWORK-ONLY wrapper — the local RAG/vector backend (signalwire.search.*)
# is Python-only and NOT ported.

use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
no warnings 'experimental::signatures';

use HTTP::Tiny;
use JSON ();
use URI;
use MIME::Base64 qw(encode_base64);
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
use SignalWire::Utils::UrlValidator ();
SignalWire::Skills::SkillRegistry->register_skill( 'native_vector_search', __PACKAGE__ );

has '+skill_name' => ( default => sub { 'native_vector_search' } );
has '+skill_description' => (
    default => sub {
        'Search document indexes using vector similarity and keyword search (local or remote)';
    }
);
has '+supports_multiple_instances' => ( default => sub { 1 } );

has '_http' => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        HTTP::Tiny->new(
            agent      => 'SignalWire-Perl-NativeVectorSearch/1.0',
            timeout    => 30,
            verify_SSL => 1,
        );
    },
);

# Resolved-at-setup config (from params).
has '_remote_url'  => ( is => 'rw' );
has '_remote_base' => ( is => 'rw', default => sub { '' } );
has '_remote_auth' => ( is => 'rw', default => sub { '' } );
has '_index_name'  => ( is => 'rw' );
has '_tool_name'   => ( is => 'rw', default => sub { 'search_knowledge' } );
has '_tool_desc'   => ( is => 'rw' );
has '_count'       => ( is => 'rw', default => sub { 3 } );
has '_no_results'  => ( is => 'rw' );

sub setup ($self) {
    my $p = $self->params;

    $self->_remote_url( $p->{remote_url} );
    $self->_index_name( $p->{index_name} );
    $self->_tool_name( $p->{tool_name}   // 'search_knowledge' );
    $self->_tool_desc( $p->{description} // 'Search the local knowledge base for information' );
    $self->_count( defined $p->{count} ? int( $p->{count} ) : 3 );
    $self->_no_results( $p->{no_results_message} // "No results found for '{query}'." );

    # Network mode REQUIRES remote_url.
    my $url = $self->_remote_url;
    return 0 unless defined $url && length $url;

    # SSRF guard: reject non-http(s) schemes and hosts resolving to
    # private/loopback/link-local/metadata ranges (test hosts use the
    # SWML_ALLOW_PRIVATE_URLS escape hatch). Mirrors go/dotnet.
    return 0 unless SignalWire::Utils::UrlValidator::validate_url($url);

    # Split embedded userinfo (user:pass@host) into an Authorization header
    # and a clean base URL, mirroring the reference's URL handling.
    my $uri  = URI->new($url);
    my $info = $uri->can('userinfo') ? $uri->userinfo : undef;
    if ( defined $info && length $info ) {
        $self->_remote_auth( encode_base64( $info, '' ) );
        $uri->userinfo(undef);
    }
    ( my $base = $uri->as_string ) =~ s{/+$}{};
    $self->_remote_base($base);

    return 1;
}

sub get_instance_key ($self) {
    my $tool = $self->params->{tool_name} // $self->_tool_name // 'search_knowledge';
    return "native_vector_search_$tool";
}

sub register_tools ($self) {
    my $tool_name = $self->params->{tool_name} // 'search_knowledge';

    my $weak_self = $self;
    require Scalar::Util;
    Scalar::Util::weaken($weak_self);

    return $self->define_tool(
        name        => $tool_name,
        description => $self->_tool_desc // 'Search the local knowledge base for information',
        parameters  => {
            type       => 'object',
            properties => {
                query => { type => 'string',  description => 'Search query' },
                count => { type => 'integer', description => 'Number of results to return' },
            },
            required => ['query'],
        },
        handler => sub {
            my ( $args, $raw ) = @_;
            return $weak_self->_handle_search( $args, $raw );
        },
    );
}

sub get_hints ($self) {
    my @base   = ( 'search', 'find', 'look up', 'documentation', 'knowledge base' );
    my $custom = $self->params->{hints};
    push @base, @$custom if ref $custom eq 'ARRAY';
    return \@base;
}

sub get_global_data ($self) {

    # Remote mode has no local search-engine stats; report the mode sentinel.
    return { search_mode => 'remote' };
}

sub _get_prompt_sections ($self) {
    my $tool = $self->_tool_name // 'search_knowledge';
    return [
        {
            title   => 'Knowledge Search',
            body    => "You can search knowledge sources using $tool.",
            bullets => [
                "Use $tool to search document indexes",
                'Search for relevant information using clear, specific queries',
                'If no results are found, suggest the user try rephrasing their question',
            ],
        }
    ];
}

sub get_parameter_schema {
    return {
        %{ SignalWire::Skills::SkillBase->get_parameter_schema },
        remote_url =>
            { type => 'string', required => 1, description => 'URL of the remote search server' },
        index_name           => { type => 'string' },
        count                => { type => 'integer', default => 3, min => 1, max => 20 },
        similarity_threshold => { type => 'number',  default => 0.5 },
        description          => { type => 'string' },
        no_results_message   => { type => 'string' },
        hints                => { type => 'array' },
    };
}

# --- private helpers (underscore-prefixed: kept off the public surface) ---

sub _handle_search ( $self, $args, $raw ) {
    require SignalWire::SWAIG::FunctionResult;

    my $query = $args->{query} // '';
    $query =~ s/^\s+|\s+$//g;
    unless ( length $query ) {
        return SignalWire::SWAIG::FunctionResult->new('Please provide a search query.');
    }

    my $count = defined $args->{count} ? int( $args->{count} ) : $self->_count;

    my $resp = eval { $self->_post_search( $query, $count ) };
    if ($@) {
        return SignalWire::SWAIG::FunctionResult->new("Error searching: $@");
    }
    unless ( $resp && $resp->{success} ) {
        return SignalWire::SWAIG::FunctionResult->new(
            'Sorry, the search service is unavailable right now.');
    }

    my $data = eval { JSON::decode_json( $resp->{content} // '{}' ) };
    if ($@) {
        return SignalWire::SWAIG::FunctionResult->new(
            'Sorry, the search service returned an unparseable response.');
    }

    return $self->_format_results( $data, $query, $count );
}

sub _post_search ( $self, $query, $count ) {
    my %payload = ( query => $query, count => $count );
    $payload{index_name} = $self->_index_name if defined $self->_index_name;

    my $url     = ( $self->_remote_base // '' ) . '/search';
    my %headers = ( 'Content-Type' => 'application/json' );
    $headers{Authorization} = 'Basic ' . $self->_remote_auth if length $self->_remote_auth;

    return $self->_http->post(
        $url,
        {
            headers => \%headers,
            content => JSON::encode_json( \%payload ),
        },
    );
}

sub _format_results ( $self, $data, $query, $count ) {
    require SignalWire::SWAIG::FunctionResult;

    my $results = $data->{results} // $data->{chunks} // [];
    unless ( ref $results eq 'ARRAY' && @$results ) {
        ( my $msg = $self->_no_results // "No results found for '{query}'." ) =~
            s/\{query\}/$query/g;
        return SignalWire::SWAIG::FunctionResult->new($msg);
    }

    my @wanted = @$results;
    @wanted = @wanted[ 0 .. $count - 1 ] if @wanted > $count;

    my @blocks;
    my $i = 1;
    for my $r (@wanted) {
        next unless defined $r;
        my $text;
        if ( ref $r eq 'HASH' ) {
            $text = $r->{content} // $r->{text};
            if ( !defined $text ) {
                $text = JSON::encode_json($r);
            } elsif ( defined $r->{score} ) {
                my $meta = ref $r->{metadata} eq 'HASH' ? $r->{metadata} : {};
                my $from = $meta->{filename} // $meta->{source} // '';
                $text = sprintf( '(from %s, relevance: %.2f)', $from, $r->{score} ) . "\n$text";
            }
        } else {
            $text = "$r";
        }
        push @blocks, "=== RESULT $i ===\n$text\n" . ( '=' x 50 );
        $i++;
    }

    return SignalWire::SWAIG::FunctionResult->new(
        "Search results for '$query':\n\n" . join( "\n\n", @blocks ) );
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::Builtin::NativeVectorSearch - remote vector-search skill

=head1 DESCRIPTION

Network/remote-mode port of the reference C<native_vector_search> skill.
It POSTs C<{query,count}> to a configured C<remote_url> search service and
formats the returned C<{content,score,metadata}> results. The local RAG /
vector backend (C<signalwire.search.*>) is Python-only and not ported; this
wrapper is a normal L<SignalWire::Skills::SkillBase> skill.

C<setup> requires the C<remote_url> param (returns false when absent) and
SSRF-validates it via L<SignalWire::Utils::UrlValidator>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
