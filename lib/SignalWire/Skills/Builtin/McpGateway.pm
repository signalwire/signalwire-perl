package SignalWire::Skills::Builtin::McpGateway;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# MCP Gateway CLIENT skill. Mirrors signalwire-python's
# skills/mcp_gateway/skill.py (MCPGatewaySkill) — the CLIENT half of the
# MCP bridge: it connects to a RUNNING MCP gateway service over HTTP,
# authenticates (bearer token OR HTTP Basic), discovers the gateway's
# services + tools, and registers each MCP tool as a handler-based SWAIG
# function whose handler calls the gateway back at runtime.
#
# SERVER HALF IS PYTHON-ONLY (documented in PORT_PHILOSOPHY_PERL.md § MCP
# Gateway): the `mcp-gateway` service process (the thing this client talks
# to — spawning MCP servers, HTTP session routing, SSE bridging) is NOT
# ported to Perl. This skill is the CLIENT that any running gateway (the
# Python service, or a compatible third-party one) serves.

use strict;
use warnings;
use Moo;
use HTTP::Tiny;
use JSON         ();
use MIME::Base64 qw(encode_base64);
use Scalar::Util ();
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill( 'mcp_gateway', __PACKAGE__ );

has '+skill_name'        => ( default => sub { 'mcp_gateway' } );
has '+skill_description' => ( default => sub { 'Bridge MCP servers with SWAIG functions' } );
has '+skill_version'     => ( default => sub { '1.0.0' } );
has '+supports_multiple_instances' => ( default => sub { 1 } );
has '+required_packages'           => ( default => sub { ['HTTP::Tiny'] } );

# verify_ssl — secure-default (TRUE) TLS-verification opt-in, threaded to the
# outbound HTTP::Tiny client's verify_SSL. Python parity:
# skills/mcp_gateway/skill.py reads `self.verify_ssl = params.get("verify_ssl",
# True)` and passes `verify=self.verify_ssl` to every request. This is the
# load-bearing secure default for Perl: HTTP::Tiny's OWN default is
# verify_SSL => 0 (TLS verify OFF, the footgun), so a config that defaulted
# anything but TRUE would silently ship cert-blind. The default here is 1
# (verify ON); an operator sets verify_ssl => 0 only for a self-signed-cert
# gateway.
has 'verify_ssl' => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        my $v = $self->params->{verify_ssl};
        return 1 unless defined $v;    # secure default: verify ON
        return $v ? 1 : 0;
    },
);

# Normalised gateway base URL (trailing slash stripped).
has 'gateway_url' => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        my $url = $self->params->{gateway_url} // '';
        $url =~ s{/+$}{};
        return $url;
    },
);

# The outbound HTTP client. verify_SSL is threaded from the secure-default
# verify_ssl config param (TLS verify ON unless the operator opts out for a
# self-signed gateway — the same secure-default-gated idiom python endorses
# via `verify=self.verify_ssl`). NOTE: HTTP::Tiny's own default is
# verify_SSL => 0; we NEVER rely on that — verify_ssl defaults to 1.
has '_http' => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        HTTP::Tiny->new(
            agent      => 'SignalWire-Perl-McpGateway/1.0',
            timeout    => $self->params->{request_timeout} // 30,
            verify_SSL => $self->verify_ssl,
        );
    },
);

sub setup {
    my ($self) = @_;

    # Require a gateway URL always; then either a bearer token OR a
    # user/password basic-auth pair. Mirrors python setup() which fails
    # (returns false) when neither auth method is fully provided.
    unless ( length $self->gateway_url ) {
        return 0;
    }

    my $token = $self->params->{auth_token};
    if ( !( defined $token && length $token ) ) {
        my $user = $self->params->{auth_user};
        my $pass = $self->params->{auth_password};
        unless ( defined $user && length $user && defined $pass && length $pass ) {

            # No bearer token AND no complete basic-auth pair.
            return 0;
        }
    }

    return 1;
}

# Build the Authorization header value for the configured auth method:
# a Bearer token when present, else HTTP Basic from user:password. Returns
# undef when neither is configured (setup() already guards this).
sub _auth_header {
    my ($self) = @_;
    my $token = $self->params->{auth_token};
    if ( defined $token && length $token ) {
        return "Bearer $token";
    }
    my $user = $self->params->{auth_user};
    my $pass = $self->params->{auth_password};
    if ( defined $user && length $user ) {
        my $basic = encode_base64( "$user:$pass", '' );
        return "Basic $basic";
    }
    return;
}

# Issue an authenticated HTTP request to the gateway. Returns the HTTP::Tiny
# response hashref. `verify_SSL` is already baked into $self->_http from the
# secure-default verify_ssl config param.
sub _request {
    my ( $self, $method, $url, $content ) = @_;
    my %headers = ( 'Accept' => 'application/json' );
    my $auth    = $self->_auth_header;
    $headers{Authorization} = $auth if defined $auth;

    my %options = ( headers => \%headers );
    if ( defined $content ) {
        $headers{'Content-Type'} = 'application/json';
        $options{content}        = $content;
    }
    return $self->_http->request( $method, $url, \%options );
}

sub register_tools {
    my ($self) = @_;

    my $weak_self = $self;
    Scalar::Util::weaken($weak_self);

    my $tool_prefix = $self->params->{tool_prefix} // 'mcp_';

    for my $service ( @{ $self->_resolve_services } ) {
        my $service_name = $service->{name};
        next unless defined $service_name && length $service_name;

        my $tools = $self->_fetch_service_tools($service_name);

        # Filter tools when the service config names a specific list.
        my $filter = $service->{tools} // '*';
        if ( ref $filter eq 'ARRAY' ) {
            my %keep = map { $_ => 1 } @$filter;
            $tools = [ grep { $keep{ $_->{name} // '' } } @$tools ];
        }

        for my $tool (@$tools) {
            $self->_register_mcp_tool( $weak_self, $tool_prefix, $service_name, $tool );
        }
    }

    # Register the hangup hook that cleans up the MCP session on call end.
    return $self->define_tool(
        name           => '_mcp_gateway_hangup',
        description    => 'Internal cleanup function for MCP sessions',
        parameters     => { type => 'object', properties => {} },
        is_hangup_hook => 1,
        handler        => sub {
            my ( $args, $raw ) = @_;
            return $weak_self->_hangup_handler( $args, $raw );
        },
    );
}

# Resolve the list of services to register: the configured `services` list,
# or — when empty — every service the gateway advertises at /services.
sub _resolve_services {
    my ($self) = @_;
    my $configured = $self->params->{services};
    if ( ref $configured eq 'ARRAY' && @$configured ) {
        return $configured;
    }

    my $resp = $self->_request( 'GET', $self->gateway_url . '/services' );
    return [] unless $resp->{success};
    my $names = eval { JSON::decode_json( $resp->{content} // '[]' ) };
    return [] if $@ || ref $names ne 'ARRAY';
    return [ map { { name => $_ } } @$names ];
}

# Fetch the tool definitions the gateway exposes for one service.
sub _fetch_service_tools {
    my ( $self, $service_name ) = @_;
    my $url  = $self->gateway_url . "/services/$service_name/tools";
    my $resp = $self->_request( 'GET', $url );
    return [] unless $resp->{success};
    my $data = eval { JSON::decode_json( $resp->{content} // '{}' ) };
    return [] if $@ || ref $data ne 'HASH';
    my $tools = $data->{tools} // [];
    return ref $tools eq 'ARRAY' ? $tools : [];
}

# Register a single MCP tool definition as a handler-based SWAIG function.
sub _register_mcp_tool {
    my ( $self, $weak_self, $tool_prefix, $service_name, $tool_def ) = @_;
    my $tool_name = $tool_def->{name};
    return unless defined $tool_name && length $tool_name;

    my $swaig_name = "${tool_prefix}${service_name}_${tool_name}";

    # Convert the MCP inputSchema into SWAIG parameter properties.
    my $input_schema = $tool_def->{inputSchema}    // {};
    my $properties   = $input_schema->{properties} // {};
    my $required     = $input_schema->{required}   // [];

    my %swaig_props;
    for my $prop_name ( keys %$properties ) {
        my $prop_def = $properties->{$prop_name};
        my %param    = (
            type        => $prop_def->{type}        // 'string',
            description => $prop_def->{description} // '',
        );
        $param{enum} = $prop_def->{enum} if exists $prop_def->{enum};
        $swaig_props{$prop_name} = \%param;
    }

    $self->define_tool(
        name        => $swaig_name,
        description => "[$service_name] " . ( $tool_def->{description} // $tool_name ),
        parameters  => {
            type       => 'object',
            properties => \%swaig_props,
            ( ref $required eq 'ARRAY' && @$required ? ( required => [@$required] ) : () ),
        },
        handler => sub {
            my ( $args, $raw ) = @_;
            return $weak_self->_call_mcp_tool( $service_name, $tool_name, $args, $raw );
        },
    );
    return;
}

# Resolve the MCP session id for a call: prefer global_data.mcp_call_id,
# else the top-level call_id (python parity).
sub _session_id {
    my ( $self, $raw ) = @_;
    $raw //= {};
    my $global = $raw->{global_data} // {};
    if ( defined $global->{mcp_call_id} && length $global->{mcp_call_id} ) {
        return $global->{mcp_call_id};
    }
    return $raw->{call_id} // 'unknown';
}

# Call an MCP tool through the gateway and return its result as a
# FunctionResult. Retries on 5xx / transport errors up to retry_attempts.
sub _call_mcp_tool {
    my ( $self, $service_name, $tool_name, $args, $raw ) = @_;
    require SignalWire::SWAIG::FunctionResult;

    my $session_id = $self->_session_id($raw);
    my $agent_name = eval { $self->agent->name } // '';
    my $payload    = {
        tool       => $tool_name,
        arguments  => $args // {},
        session_id => $session_id,
        timeout    => $self->params->{session_timeout} // 300,
        metadata   => {
            agent_id  => $agent_name,
            timestamp => ( $raw ? $raw->{timestamp} : undef ),
            call_id   => ( $raw ? $raw->{call_id}   : undef ),
        },
    };
    my $body    = JSON::encode_json($payload);
    my $url     = $self->gateway_url . "/services/$service_name/call";
    my $retries = $self->params->{retry_attempts} // 3;

    my $last_error = 'unknown error';
    for my $attempt ( 1 .. $retries ) {
        my $resp = $self->_request( 'POST', $url, $body );

        if ( $resp->{success} ) {
            my $data = eval { JSON::decode_json( $resp->{content} // '{}' ) };
            my $text =
                  ( !$@ && ref $data eq 'HASH' )
                ? ( $data->{result} // 'No response' )
                : 'No response';
            return SignalWire::SWAIG::FunctionResult->new( response => $text );
        }

        my $status = $resp->{status} // 0;
        my $data   = eval { JSON::decode_json( $resp->{content} // '{}' ) };
        $last_error =
            ( !$@ && ref $data eq 'HASH' && defined $data->{error} )
            ? $data->{error}
            : "HTTP $status";

        # Retry only on server (5xx) / transport (599) errors; a 4xx is
        # a client error we don't retry.
        last if $status >= 400 && $status < 500;
    }

    return SignalWire::SWAIG::FunctionResult->new(
        response => "Failed to call $service_name.$tool_name: $last_error", );
}

# Clean up the MCP session for the ending call.
sub _hangup_handler {
    my ( $self, $args, $raw ) = @_;
    require SignalWire::SWAIG::FunctionResult;
    my $session_id = $self->_session_id($raw);
    my $url        = $self->gateway_url . "/sessions/$session_id";
    eval { $self->_request( 'DELETE', $url ); 1 };
    return SignalWire::SWAIG::FunctionResult->new( response => 'Session cleanup complete' );
}

sub get_hints {
    my ($self) = @_;
    my @hints = ( 'MCP', 'gateway' );
    for my $service ( @{ $self->_service_configs } ) {
        push @hints, $service->{name}
            if ref $service eq 'HASH' && defined $service->{name};
    }
    return \@hints;
}

sub get_global_data {
    my ($self) = @_;
    my @service_names =
        map { ref $_ eq 'HASH' ? ( $_->{name} // '' ) : "$_" } @{ $self->_service_configs };
    return {
        mcp_gateway_url => $self->gateway_url,
        mcp_services    => \@service_names,
    };
}

sub _get_prompt_sections {
    my ($self) = @_;
    my @descriptions;
    for my $service ( @{ $self->_service_configs } ) {
        next unless ref $service eq 'HASH';
        my $name  = $service->{name}  // 'Unknown';
        my $tools = $service->{tools} // '*';
        if ( ref $tools eq 'ARRAY' ) {
            push @descriptions, "$name (" . scalar(@$tools) . ' tools)';
        } else {
            push @descriptions, "$name (all tools)";
        }
    }
    return [] unless @descriptions;

    my $prefix = $self->params->{tool_prefix} // 'mcp_';
    return [
        {
            title => 'MCP Gateway Integration',
            body  =>
'You have access to external MCP (Model Context Protocol) services through a gateway.',
            bullets => [
                'Connected to gateway at ' . $self->gateway_url,
                'Available services: ' . join( ', ', @descriptions ),
                "Functions are prefixed with '$prefix' followed by service name",
                'Each service maintains its own session state throughout the call',
            ],
        }
    ];
}

# The configured `services` list as an arrayref (empty when unset). Used by
# the prompt/hint/global-data contributions, which describe the CONFIGURED
# services (register_tools separately discovers-all when the list is empty).
sub _service_configs {
    my ($self) = @_;
    my $services = $self->params->{services};
    return ref $services eq 'ARRAY' ? $services : [];
}

sub get_parameter_schema {
    return {
        %{ SignalWire::Skills::SkillBase->get_parameter_schema },
        gateway_url =>
            { type => 'string', description => 'URL of the MCP Gateway service', required => 1 },
        auth_token => {
            type        => 'string',
            description => 'Bearer token for authentication (alternative to basic auth)',
            hidden      => JSON::true,
        },
        auth_user     => { type => 'string', description => 'Username for basic authentication' },
        auth_password => {
            type        => 'string',
            description => 'Password for basic authentication',
            hidden      => JSON::true,
        },
        services => {
            type        => 'array',
            description => 'List of MCP services to connect to (empty for all available)',
            default     => [],
        },
        session_timeout =>
            { type => 'integer', description => 'Session timeout in seconds', default => 300 },
        tool_prefix => {
            type        => 'string',
            description => 'Prefix for registered SWAIG function names',
            default     => 'mcp_'
        },
        retry_attempts => {
            type        => 'integer',
            description => 'Number of retry attempts for failed requests',
            default     => 3
        },
        request_timeout =>
            { type => 'integer', description => 'Request timeout in seconds', default => 30 },

        # verify_ssl — secure default TRUE (verify ON). Threaded to
        # HTTP::Tiny verify_SSL. JSON::true keeps the schema default a real
        # boolean true on the wire (and, per the fleet verify_ssl_parity
        # oracle, records the secure-default explicitly).
        verify_ssl => {
            type        => 'boolean',
            description => 'Verify SSL certificates',
            default     => JSON::true,
        },
    };
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::Builtin::McpGateway - MCP Gateway CLIENT skill (bridge MCP servers to SWAIG functions)

=head1 SYNOPSIS

    # Bearer-token auth:
    $agent->add_skill('mcp_gateway', {
        gateway_url => 'https://mcp.example.com',
        auth_token  => $MCP_GATEWAY_AUTH_TOKEN,
    });

    # HTTP Basic auth, explicit service list:
    $agent->add_skill('mcp_gateway', {
        gateway_url   => 'https://mcp.example.com',
        auth_user     => $USER,
        auth_password => $PASS,
        services      => [ { name => 'files', tools => ['read','list'] } ],
        tool_prefix   => 'mcp_',
    });

=head1 DESCRIPTION

L<SignalWire::Skills::Builtin::McpGateway> is the Perl port of the Python
reference C<signalwire.skills.mcp_gateway.skill> (C<MCPGatewaySkill>). It is the
B<client> half of the MCP (Model Context Protocol) bridge: it connects to a
B<running> MCP gateway service over HTTP, authenticates (a Bearer C<auth_token>,
or HTTP Basic from C<auth_user> / C<auth_password>), discovers the gateway's
services and their tools, and registers each MCP tool as a handler-based SWAIG
function (C<< <tool_prefix><service>_<tool> >>). At call time each handler POSTs
to the gateway's C<< /services/<service>/call >> endpoint and returns the result
as a L<SignalWire::SWAIG::FunctionResult>. A hangup hook cleans up the MCP
session when the call ends.

B<The server half is Python-only.> The C<mcp-gateway> service process (which
spawns MCP servers, routes HTTP sessions, and bridges SSE) is not ported to Perl;
this skill is the client that talks to it (or to any compatible gateway). See
C<PORT_PHILOSOPHY_PERL.md> § MCP Gateway.

=head2 TLS verification (C<verify_ssl>)

The C<verify_ssl> config param defaults to B<true> (TLS verification ON) and is
threaded to the outbound L<HTTP::Tiny> client's C<verify_SSL>. This secure
default is load-bearing on Perl: HTTP::Tiny's own default leaves verification
OFF. An operator disables C<verify_ssl> only to talk to a self-signed-certificate
gateway. Mirrors python's C<verify=self.verify_ssl>.

=head1 METHODS

=over

=item C<setup>

Validates configuration: requires C<gateway_url> plus either an C<auth_token> or
a complete C<auth_user> / C<auth_password> pair. Returns true on success, false
otherwise.

=item C<register_tools>

Discovers the gateway's services (the configured C<services> list, or all
advertised services when empty), registers each MCP tool as a SWAIG function, and
registers the C<_mcp_gateway_hangup> cleanup hook.

=item C<get_hints>

Returns speech hints (C<MCP>, C<gateway>, plus configured service names).

=item C<get_global_data>

Returns the skill's global-data contribution (C<mcp_gateway_url>,
C<mcp_services>).

=item C<get_prompt_sections>

Returns a prompt section describing the connected gateway and services (empty
when no services are configured, or when C<skip_prompt> is set).

=item C<get_parameter_schema>

Returns the configuration schema: C<gateway_url> (required), C<auth_token>,
C<auth_user>, C<auth_password>, C<services>, C<session_timeout>, C<tool_prefix>,
C<retry_attempts>, C<request_timeout>, and C<verify_ssl> (secure default true).

=back

=head1 ATTRIBUTES

C<gateway_url> (normalised, trailing slash stripped), C<verify_ssl> (secure
default 1, threaded to HTTP::Tiny C<verify_SSL>).

=head1 SEE ALSO

L<SignalWire::Skills::SkillBase>, L<SignalWire::Skills::Builtin::Datasphere>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
