package SignalWire::SWML::Service;
use strict;
use warnings;
use Moo;
use JSON         ();
use Digest::SHA  qw(hmac_sha256_hex);
use MIME::Base64 ();
use Scalar::Util ();
use SignalWire::SWML::Document;
use SignalWire::SWML::Schema;
use SignalWire::Utils::SchemaUtils ();
use SignalWire::Logging;

has 'name' => (
    is      => 'rw',
    default => sub { 'service' },
);

has 'route' => (
    is      => 'rw',
    default => sub { '/' },
);

has 'host' => (
    is      => 'rw',
    default => sub { $ENV{SWML_HOST} // '0.0.0.0' },
);

has 'port' => (
    is      => 'rw',
    default => sub { $ENV{SWML_PORT} // 3000 },
);

has 'basic_auth_user' => (
    is      => 'rw',
    default => sub { $ENV{SWML_BASIC_AUTH_USER} // _random_hex(16) },
);

has 'basic_auth_password' => (
    is      => 'rw',
    default => sub { $ENV{SWML_BASIC_AUTH_PASSWORD} // _random_hex(32) },
);

# Python parity: SWMLService.__init__(basic_auth=(user, password)) takes the
# credential as ONE (user, password) tuple. Perl models the two halves as the
# separate ``basic_auth_user`` / ``basic_auth_password`` attributes, so accept
# the reference's pair form as an arrayref and FORWARD it to those two
# attributes in BUILDARGS (an explicitly-passed half still wins). Reads back as
# the pair so ``$svc->basic_auth`` mirrors the reference's ``_basic_auth``.
has 'basic_auth' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_basic_auth',
);

sub _build_basic_auth {
    my ($self) = @_;
    return [ $self->basic_auth_user, $self->basic_auth_password ];
}

# Unfold the reference's ``basic_auth => (user, password)`` pair onto the two
# Perl credential attributes. An explicitly-supplied basic_auth_user /
# basic_auth_password still wins, matching the reference's precedence (an
# explicit value beats the derived one).
sub BUILDARGS {
    my ( $class, @args ) = @_;
    my $args = ( @args == 1 && ref $args[0] eq 'HASH' ) ? { %{ $args[0] } } : {@args};

    if ( ref $args->{basic_auth} eq 'ARRAY' ) {
        my ( $user, $password ) = @{ $args->{basic_auth} };
        $args->{basic_auth_user}     //= $user     if defined $user;
        $args->{basic_auth_password} //= $password if defined $password;
    }

    return $args;
}

# Python parity: SWMLService.__init__(schema_path=None) — the path of the
# SWML JSON Schema to validate against. undef selects the bundled schema.
# FORWARDED to the SchemaUtils collaborator (``schema_validator``).
has 'schema_path' => (
    is      => 'rw',
    default => sub { undef },
);

# Python parity: SWMLService.__init__(schema_validation=True) — enable SWML
# schema validation. FORWARDED to the SchemaUtils collaborator, which also
# honours SWML_SKIP_SCHEMA_VALIDATION.
has 'schema_validation' => (
    is      => 'rw',
    default => sub { 1 },
);

# Python parity: SWMLService.__init__(config_file=None) — path to a JSON/YAML
# config file. FORWARDED to the SecurityConfig collaborator, which layers the
# file's ``security`` section over the environment defaults.
has 'config_file' => (
    is      => 'rw',
    default => sub { undef },
);

has 'document' => (
    init_arg => undef,
    is       => 'rw',
    default  => sub { SignalWire::SWML::Document->new() },
);

# Specialized SWML verb handlers keyed by verb name (register_verb_handler).
has 'verb_handlers' => (
    init_arg => undef,
    is       => 'rw',
    default  => sub { {} },
);

# Strict-schema-validation flag (full_validation_enabled).
has 'full_validation' => (
    init_arg => undef,
    is       => 'rw',
    default  => sub { 0 },
);

# SWML schema validator (verb existence + closed-key + type checks). Lazily
# built; used by add_verb / add_verb_to_section when full_validation is on to
# enforce the STRICT-RENDER contract (an unknown/misspelled/wrong-typed verb
# config must die, not be appended silently). Mirrors the python reference's
# SWMLService.schema_utils.validate_verb schema pass.
has '_schema_validator' => (
    init_arg => undef,
    is       => 'lazy',
    default  => sub {
        my ($self) = @_;

        # FORWARD the construction params to the collaborator, exactly as the
        # reference's SWMLService.__init__ does (swml_service.py:181-183):
        #   self.schema_utils = SchemaUtils(schema_path,
        #                                   schema_validation=self._schema_validation)
        return SignalWire::Utils::SchemaUtils->new(
            schema_path       => $self->schema_path,
            schema_validation => $self->schema_validation ? 1 : 0,
        );
    },
);

# External base URL override for webhook URLs behind a proxy
# (manual_set_proxy_url / SWML_PROXY_URL_BASE).
has 'proxy_url_base' => (
    init_arg => undef,
    is       => 'rw',
    default  => sub { $ENV{SWML_PROXY_URL_BASE} // '' },
);

# Set while serve() is running; cleared by stop().
has '_server_running' => (
    init_arg => undef,
    is       => 'rw',
    default  => sub { 0 },
);

# Toggled by enable_debug_routes(); when true the service exposes its
# debug endpoints (Python WebMixin debug-route parity).
has '_debug_routes_enabled' => (
    init_arg => undef,
    is       => 'rw',
    default  => sub { 0 },
);

# SWAIG tool registry — lifted from AgentBase so any Service (sidecar,
# non-agent verb host) can register and dispatch SWAIG functions.
has 'tools' => (
    init_arg => undef,
    is       => 'rw',
    default  => sub { {} },
);

has 'tool_order' => (
    init_arg => undef,
    is       => 'rw',
    default  => sub { [] },
);

has 'routing_callbacks' => (
    init_arg => undef,
    is       => 'rw',
    default  => sub { {} },
);

has '_logger' => (
    init_arg => undef,
    is       => 'ro',
    default  => sub { SignalWire::Logging->get_logger('signalwire.swml_service') },
);

# Python parity: schema_utils / verb_registry / security accessors.
# In Python these are instance attributes set in __init__; cross-language
# audit treats them as zero-arg getters.
#
# ``schema_utils`` is the reference's per-instance SchemaUtils built FROM the
# construction params (swml_service.py:181-183) — NOT a process-wide singleton.
# It is the same object as ``_schema_validator``; the two names are the
# reference's spelling and this port's internal spelling of one collaborator.
has 'schema_utils' => (
    is      => 'lazy',
    default => sub {
        my ($self) = @_;
        return $self->_schema_validator;
    },
);

has 'verb_registry' => (
    init_arg => undef,
    is       => 'lazy',
    default  => sub {

        # Tiny stand-in registry for verb-handler dispatch. The Perl SDK
        # uses AUTOLOAD against the schema for verb lookup; this hashref
        # mirrors Python's VerbHandlerRegistry surface (handlers indexed
        # by verb name) so callers can introspect / extend it.
        #
        # Python parity: VerbHandlerRegistry.__init__ pre-registers the
        # AIVerbHandler under verb name "ai" (swml_handler.py). Ship the same
        # default handler so a fresh registry already knows the "ai" verb.
        return { handlers => { ai => { verb => 'ai' } } };
    },
);

has 'security' => (
    init_arg => undef,
    is       => 'lazy',
    default  => sub {
        my ($self) = @_;

        # Python parity: SWMLService.__init__ builds
        #   self.security = SecurityConfig(config_file=config_file,
        #                                  service_name=name)
        # (swml_service.py:139) and then exposes ssl_enabled / domain /
        # ssl_cert_path / ssl_key_path off it. FORWARD the construction params
        # to that collaborator so a config_file passed to ->new actually
        # reaches the security configuration.
        require SignalWire::Core::SecurityConfig;
        return SignalWire::Core::SecurityConfig->new(
            config_file  => $self->config_file,
            service_name => $self->name,
        );
    },
);

# Python parity: swml_service.py:143-146 lifts four values off the
# SecurityConfig collaborator onto the service itself --
#   self.ssl_enabled   = self.security.ssl_enabled
#   self.domain        = self.security.domain
#   self.ssl_cert_path = self.security.ssl_cert_path
#   self.ssl_key_path  = self.security.ssl_key_path
# They are caller-observable VALUES, and the reference also REASSIGNS them
# later (serve() overrides ssl_enabled/domain at swml_service.py:1235-1248,
# and clears ssl_enabled at :1248 when the cert/key check fails), so these
# are read/write, not read-only. ``lazy`` defers to ->security so the
# config_file passed to ->new is honoured, matching the reference's
# construction order.
has 'ssl_enabled' => (
    init_arg => undef,
    is       => 'rw',
    lazy     => 1,
    default  => sub { $_[0]->security->ssl_enabled },
);

has 'ssl_cert_path' => (
    init_arg => undef,
    is       => 'rw',
    lazy     => 1,
    default  => sub { $_[0]->security->ssl_cert_path },
);

has 'ssl_key_path' => (
    init_arg => undef,
    is       => 'rw',
    lazy     => 1,
    default  => sub { $_[0]->security->ssl_key_path },
);

has 'domain' => (
    init_arg => undef,
    is       => 'rw',
    lazy     => 1,
    default  => sub { $_[0]->security->domain },
);

# Function-name validation pattern matches the other ports.
my $SWAIG_FN_NAME = qr/\A[a-zA-Z_][a-zA-Z0-9_]*\z/;

# Schema-driven verb auto-vivification via AUTOLOAD
our $AUTOLOAD;
my $_schema;

sub _get_schema {
    $_schema //= SignalWire::SWML::Schema->instance();
    return $_schema;
}

sub AUTOLOAD {
    my $self   = shift;
    my $method = $AUTOLOAD;
    $method =~ s/.*:://;    # strip package name

    return if $method eq 'DESTROY';

    my $schema = _get_schema();
    if ( $schema->has_verb($method) ) {

        # For 'sleep' verb: takes an integer (milliseconds), not a hashref
        my $section = shift // 'main';
        my $data;
        if ( $method eq 'sleep' ) {
            $data = shift // 0;

            # Ensure it is a numeric value
            $data = int($data);
        } else {
            $data = shift // {};
        }
        $self->document->add_verb( $section, $method, $data );
        return $self;
    }

    die "Can't locate method \"$method\" via package \"" . ref($self) . "\"";
}

# Provide can() that knows about schema verbs
sub can {
    my ( $self, $method ) = @_;

    # Check if it is a regular method first
    my $code = $self->SUPER::can($method);
    return $code if $code;

    # Check schema verbs
    my $schema = _get_schema();
    if ( $schema && $schema->has_verb($method) ) {
        return sub { $self->$method(@_) };
    }
    return;
}

sub _random_hex {
    my ($len) = @_;

    # Use /dev/urandom for cryptographically secure random bytes.
    # Die on failure rather than falling back to weak randomness.
    if ( open my $fh, '<:raw', '/dev/urandom' ) {
        my $bytes;
        my $read = read( $fh, $bytes, $len );
        close $fh;
        if ( defined $read && $read == $len ) {
            return unpack( 'H*', $bytes );
        }
    }
    die "FATAL: Cannot generate secure random bytes - /dev/urandom unavailable or read failed. "
        . "Set SWML_BASIC_AUTH_USER and SWML_BASIC_AUTH_PASSWORD environment variables instead.\n";
}

sub _timing_safe_compare {
    my ( $a, $b ) = @_;

    # Compare HMAC of both values with a fixed key for constant-time comparison
    my $key    = 'timing-safe-comparison-key';
    my $hmac_a = hmac_sha256_hex( $a, $key );
    my $hmac_b = hmac_sha256_hex( $b, $key );
    return $hmac_a eq $hmac_b;
}

# Validate provided basic-auth credentials. (Python parity:
# AuthMixin.validate_basic_auth(username, password).)
sub validate_basic_auth {
    my ( $self, $username, $password ) = @_;
    my $u = $self->basic_auth_user;
    my $p = $self->basic_auth_password;
    return 0 unless defined $u && defined $p;
    return _timing_safe_compare( $username, $u )
        && _timing_safe_compare( $password, $p );
}

# Returns ($user, $password) by default; if $include_source is truthy,
# returns ($user, $password, $source) where $source is "provided",
# "environment", or "generated". (Python parity:
# AuthMixin.get_basic_auth_credentials(include_source=False).)
sub get_basic_auth_credentials {
    my ( $self, $include_source ) = @_;
    my $user = $self->basic_auth_user     // '';
    my $pass = $self->basic_auth_password // '';
    return ( $user, $pass ) unless $include_source;
    my $env_user = $ENV{SWML_BASIC_AUTH_USER}     // '';
    my $env_pass = $ENV{SWML_BASIC_AUTH_PASSWORD} // '';
    my $source;
    if ( $env_user ne '' && $env_pass ne '' && $user eq $env_user && $pass eq $env_pass ) {
        $source = 'environment';
    } elsif ( $user =~ /^user_/ && length($pass) > 20 ) {
        $source = 'generated';
    } else {
        $source = 'provided';
    }
    return ( $user, $pass, $source );
}

# Backward-compat alias for Perl callers that used the named-helper form.
# Equivalent to ``$self->get_basic_auth_credentials(1)``.
sub get_basic_auth_credentials_with_source {
    my ($self) = @_;
    return $self->get_basic_auth_credentials(1);
}

# extract_sip_username($request_body)
#
# Python parity: SWMLService.extract_sip_username(request_body) is a
# @staticmethod that pulls the username out of a SignalWire/SWML
# request body's call.to field. Handles SIP URIs (``sip:user@host``),
# TEL URIs (``tel:+15551234567``), and plain destination strings.
# Returns undef when the body shape doesn't match.
#
# Callable as either a class method or instance method (Perl idiom for
# what Python expresses with @staticmethod). The class_or_self receiver
# is mirrored from FunctionResult and other static-method-shaped helpers.
sub extract_sip_username {
    my ( $class_or_self, $request_body ) = @_;

    # Allow being called as a free function (single-arg form): if the
    # first arg is itself the request_body hashref, shift it forward.
    if ( !defined $request_body && ref $class_or_self eq 'HASH' ) {
        $request_body = $class_or_self;
    }
    return unless ref $request_body eq 'HASH';
    my $call = $request_body->{call};
    return unless ref $call eq 'HASH';
    my $to = $call->{to};

    # Python's implementation calls ``to_field.startswith(...)`` which
    # raises AttributeError for non-string values (None / int / list)
    # and returns None via the except path. Mirror that policy: any
    # non-defined or ref value short-circuits to undef.
    return unless defined $to && !ref $to;

    if ( $to =~ m{^sip:([^@]+)\@}i ) {
        return $1;
    }
    if ( $to =~ m{^tel:(.+)$}i ) {
        return $1;
    }
    return $to;
}

sub _check_basic_auth {
    my ( $self, $env ) = @_;
    my $auth = $env->{HTTP_AUTHORIZATION} // '';
    return 0 unless $auth =~ /^Basic\s+(.+)$/i;
    my $decoded = MIME::Base64::decode_base64($1);
    my ( $user, $pass ) = split( /:/, $decoded, 2 );
    return 0 unless defined $user && defined $pass;
    return _timing_safe_compare( $user, $self->basic_auth_user )
        && _timing_safe_compare( $pass, $self->basic_auth_password );
}

sub _security_headers {
    return (
        'X-Content-Type-Options' => 'nosniff',
        'X-Frame-Options'        => 'DENY',
        'X-XSS-Protection'       => '1; mode=block',
        'Cache-Control'          => 'no-store, no-cache, must-revalidate',
        'Pragma'                 => 'no-cache',
        'Content-Type'           => 'application/json',
    );
}

sub _json_response {
    my ( $status, $data ) = @_;
    my @headers = _security_headers();
    my $body    = JSON::encode_json($data);
    return [ $status, \@headers, [$body] ];
}

# Append the standard security headers to an existing PSGI response's header
# list in place (skipping Content-Type, which the caller already set). Used by
# to_psgi_app to layer security headers onto the handle_request-marshalled
# response, since Service has no wrapping middleware the way AgentBase does.
sub _add_security_headers {
    my ($res) = @_;
    return unless ref $res eq 'ARRAY' && ref $res->[1] eq 'ARRAY';
    my @sec = _security_headers();
    while (@sec) {
        my ( $k, $v ) = splice @sec, 0, 2;
        next if $k eq 'Content-Type';
        push @{ $res->[1] }, $k => $v;
    }
    return;
}

sub _read_body {
    my ($env) = @_;
    my $input = $env->{'psgi.input'};
    return '' unless $input;
    local $/;
    my $body = <$input>;
    return $body // '';
}

sub to_psgi_app {
    my ($self) = @_;

    return sub {
        my ($env)  = @_;
        my $method = $env->{REQUEST_METHOD};
        my $path   = $env->{PATH_INFO} // '/';

        # Health/ready endpoints (no auth)
        if ( $path eq '/health' || $path eq '/ready' ) {
            return _json_response( 200, { status => 'ok' } );
        }

        # Normalize route for matching
        my $route = $self->route;
        $route =~ s{/$}{};    # strip trailing slash
        $path  =~ s{/$}{};    # strip trailing slash
        $route = '' if $route eq '/';
        $path  = '' if $path eq '/';

        # Check if this request matches our routes
        my $is_swml_route  = ( $path eq $route );
        my $is_swaig_route = ( $path eq "$route/swaig" );
        my $is_post_prompt = ( $path eq "$route/post_prompt" );

        # The MAIN SWML route delegates its auth/routing/render DECISION to the
        # decomposed handle_request core (401 auth, 307 routing-callback
        # redirect, 200 render) — so the served path can no longer skip the
        # routing-callback 307 the way the old inline _handle_swml_request did.
        if ($is_swml_route) {
            my $res = $self->_serve_main_via_handle_request($env);
            _add_security_headers($res);
            return $res;
        }

        if ( $is_swaig_route || $is_post_prompt ) {

            # Require basic auth for protected routes
            unless ( $self->_check_basic_auth($env) ) {
                return [
                    401,
                    [
                        'Content-Type'     => 'text/plain',
                        'WWW-Authenticate' => 'Basic realm="SignalWire"'
                    ],
                    ['Authentication required'],
                ];
            }

            if ($is_swaig_route) {
                return $self->_handle_swaig_request($env);
            } elsif ($is_post_prompt) {
                return $self->_handle_post_prompt($env);
            }
        }

        return _json_response( 404, { error => 'Not found' } );
    };
}

# ------------------------------------------------------------------
# handle_request — the framework-free request-dispatch core.
#
# Python parity: SWMLService.handle_request(method, url, headers, body)
# -> (status, response_headers, body_string). This is the primitive
# dispatch surface the SDK ports share (the same one dotnet ships as
# HandleRequest and Python's FastAPI _handle_request delegates to). It
# performs basic-auth, the routing-callback check, and on_request
# modification over plain primitives instead of a PSGI $env, returning a
# ($status, \%headers, $body_string) triple. The PSGI app (to_psgi_app)
# is a thin adapter that marshals $env into these primitives and the
# triple back into a PSGI response.
#
#   $method  HTTP method string ("GET"/"POST")
#   $url     full request URL (used for callback-path derivation + proxy)
#   $headers hashref of request headers (plain, lower/any-case)
#   $body    already-parsed JSON body hashref for POST, or undef
#
# Returns the list ($status, $headers_hashref, $body_string). For a 200
# it is the SWML JSON document; for a routing redirect it is 307 with a
# Location header and an empty body; for an auth failure it is 401 with a
# WWW-Authenticate: Basic header and a JSON error body.
sub handle_request {
    my ( $self, $method, $url, $headers, $body ) = @_;
    $headers //= {};
    $body    //= {};
    my $callback_path = $self->_callback_path_for_url($url);

    # Auth (over the plain headers hashref).
    unless ( $self->_check_basic_auth_headers($headers) ) {
        return (
            401,
            { 'WWW-Authenticate' => 'Basic' },
            JSON::encode_json( { error => 'Unauthorized' } ),
        );
    }

    # Routing callback: (body, headers) -> route | undef. Only for a POST
    # with a non-empty parsed body targeting a registered callback path.
    if (   $method eq 'POST'
        && ref $body eq 'HASH'
        && %$body
        && defined $callback_path
        && $self->routing_callbacks->{$callback_path} )
    {
        my $cb    = $self->routing_callbacks->{$callback_path};
        my $route = eval { $cb->( $body, $headers ) };
        if ($@) {
            $self->log->error( "error_in_routing_callback", error => "$@" );
        } elsif ( defined $route ) {

            # 307 preserves the POST method + body on the redirect.
            return ( 307, { 'Location' => $route }, '' );
        }
    }

    # Subclass modification hook.
    my $modifications = $self->on_request( $body, $callback_path );
    if ( $modifications && ref $modifications eq 'HASH' ) {
        my $document = $self->get_document;
        for my $key ( keys %$modifications ) {
            $document->{$key} = $modifications->{$key} if exists $document->{$key};
        }
        return ( 200, {}, JSON::encode_json($document) );
    }

    return ( 200, {}, $self->render_document );
}

# ------------------------------------------------------------------
# _serve_main_via_handle_request — the thin PSGI adapter for the MAIN SWML
# endpoint. Extracts (method, url, headers, body) from the PSGI $env, calls
# the decomposed handle_request core (which owns the auth-401 / routing-307 /
# render-200 DECISION), and marshals the returned (status, \%headers, body)
# triple back into a PSGI [status, \@headers, [body]] response — INCLUDING the
# 307 Location redirect and the 401 WWW-Authenticate.
#
# Both serve paths (Service->to_psgi_app and AgentBase->_build_psgi_app) route
# the main route through this so the served path can no longer diverge from
# handle_request (it previously rendered a 200 SWML even when a routing
# callback wanted a 307). php/rust/dotnet share this same "framework adapter
# delegates to handle_request" shape.
sub _serve_main_via_handle_request {
    my ( $self, $env ) = @_;

    my ( $method, $url, $headers, $body ) = $self->_psgi_primitives($env);
    my ( $status, $resp_headers, $resp_body ) =
        $self->handle_request( $method, $url, $headers, $body );

    return _marshal_handle_request_psgi( $status, $resp_headers, $resp_body );
}

# Extract the (method, url, headers, body) primitives handle_request wants
# from a PSGI $env. Headers are recovered from the CGI-style HTTP_* keys back
# to their header-name form (so _check_basic_auth_headers and the routing
# callback's second arg see Authorization / X-Trace / forwarding headers), and
# the POST body is buffered and JSON-parsed into the hashref handle_request
# expects.
sub _psgi_primitives {
    my ( $self, $env ) = @_;

    my $method = $env->{REQUEST_METHOD} // 'GET';
    my $path   = $env->{PATH_INFO}      // '/';
    my $query  = $env->{QUERY_STRING};
    my $url    = $path;
    $url .= "?$query" if defined $query && length $query;

    my %headers;
    for my $k ( keys %$env ) {
        if ( $k =~ /^HTTP_(.+)$/ ) {
            ( my $name = $1 ) =~ s/_/-/g;
            $name = join '-', map { ucfirst lc } split /-/, $name;
            $headers{$name} = $env->{$k};
        }
    }
    $headers{'Content-Type'}   = $env->{CONTENT_TYPE}   if defined $env->{CONTENT_TYPE};
    $headers{'Content-Length'} = $env->{CONTENT_LENGTH} if defined $env->{CONTENT_LENGTH};

    my $body;
    if ( $method eq 'POST' || $method eq 'PUT' ) {
        my $raw = _read_body($env);
        if ( defined $raw && length $raw ) {
            $body = eval { JSON::decode_json($raw) };
            $body = undef unless ref $body eq 'HASH';
        }
    }

    return ( $method, $url, \%headers, $body );
}

# Marshal a handle_request (status, \%headers, $body_string) triple into a PSGI
# [status, \@headers, [body]] response. Content-Type defaults to
# application/json; the handle_request headers (Location for the 307,
# WWW-Authenticate for the 401) are passed through. Security headers are added
# by each serve path's own layer (AgentBase's middleware / Service's wrap
# below), not baked in here, so they aren't emitted twice.
sub _marshal_handle_request_psgi {
    my ( $status, $headers, $body ) = @_;
    $headers //= {};
    $body    //= '';

    my @out = ( 'Content-Type' => 'application/json' );
    for my $k ( sort keys %$headers ) {
        push @out, $k => $headers->{$k};
    }
    return [ $status, \@out, [$body] ];
}

# Derive the registered routing-callback path (if any) that $url targets.
# The PSGI path already normalizes the route; here we recover the
# equivalent by matching the URL's path against the registered callbacks.
sub _callback_path_for_url {
    my ( $self, $url ) = @_;
    return unless %{ $self->routing_callbacks };
    my $path = defined $url ? $url : '';
    $path =~ s{^[a-z][a-z0-9+.\-]*://[^/]+}{}i;    # strip scheme+authority
    $path =~ s{\?.*$}{};                           # strip query
    my $trimmed = $path;
    $trimmed =~ s{^/+}{};
    $trimmed =~ s{/+$}{};
    my $normalized = length $trimmed ? "/$trimmed" : $path;
    $normalized =~ s{/+$}{} unless $normalized eq '/';

    for my $cb_path ( keys %{ $self->routing_callbacks } ) {
        return $cb_path
            if $normalized eq $cb_path
            || ( length $cb_path && $normalized =~ /\Q$cb_path\E$/ );
    }
    return;
}

# Basic-auth check over a plain headers hashref (the handle_request
# primitive analog of _check_basic_auth, which reads a PSGI $env). Accepts
# either an ``Authorization`` or CGI-style ``HTTP_AUTHORIZATION`` key.
sub _check_basic_auth_headers {
    my ( $self, $headers ) = @_;
    my $auth = $headers->{Authorization} // $headers->{authorization}
        // $headers->{HTTP_AUTHORIZATION} // '';
    return 0 unless $auth =~ /^Basic\s+(.+)$/i;
    my $decoded = MIME::Base64::decode_base64($1);
    my ( $user, $pass ) = split( /:/, $decoded, 2 );
    return 0 unless defined $user && defined $pass;
    return _timing_safe_compare( $user, $self->basic_auth_user )
        && _timing_safe_compare( $pass, $self->basic_auth_password );
}

sub _handle_swml_request {
    my ( $self, $env ) = @_;
    my $doc = $self->render_main_swml($env);
    return _json_response( 200, $doc );
}

# Extension point: render the SWML document for the main path or for
# GET /swaig. Default returns the currently-built Document. AgentBase
# overrides to emit prompt + AI verb at request time.
sub render_main_swml {
    my ( $self, $env ) = @_;
    return $self->document->to_hash;
}

# Backwards-compatible alias kept for subclasses that override render_swml.
sub render_swml {
    my ( $self, $env ) = @_;
    return $self->render_main_swml($env);
}

# ------------------------------------------------------------------
# Document manipulation (Python parity: SWMLService document methods).
# Perl composes a SWML::Document; these expose the reference's
# SWMLService-level document API directly on the service, delegating to
# the composed document. Verb/section adds target the ``main`` section
# unless a section is named (matching the Python reference, whose
# add_verb/add_section operate on ``sections.main``).
# ------------------------------------------------------------------

# reset_document — replace the working document with a fresh empty one.
sub reset_document {
    my ($self) = @_;
    $self->document( SignalWire::SWML::Document->new() );
    return;
}

# add_verb(verb_name, config) — append a verb to the main section. A
# specialized verb handler (register_verb_handler) validates when present;
# otherwise schema validation applies. Returns true on success, false when
# config is not a hashref (and not the sleep integer special-case).
sub add_verb {
    my ( $self, $verb_name, $config ) = @_;
    if ( $verb_name eq 'sleep' && defined $config && !ref $config ) {
        $self->document->add_verb( 'main', $verb_name, int($config) );
        return 1;
    }
    return 0 unless defined $config && ref $config eq 'HASH';
    if ( my $handler = $self->verb_handlers->{$verb_name} ) {
        my ( $ok, $errors ) = $handler->validate_config($config);
        die "SWML verb '$verb_name' validation failed: @{ $errors // [] }\n" unless $ok;
    }

    # STRICT-RENDER: when full validation is on, run the schema pass. It rejects
    # an unknown verb, a misspelled/unknown key on a closed verb, a wrong-typed
    # value, or a missing required property — the r5 silent-drop family. A
    # registered handler's validate_config carries verb-specific diagnostics but
    # does NOT perform the schema's closed-key check, so run the schema pass too
    # (mirrors the python reference's add_verb: handler THEN schema pass).
    $self->_validate_verb_strict( $verb_name, $config );

    $self->document->add_verb( 'main', $verb_name, $config );
    return 1;
}

# Run the SWML schema validation for a verb config and die on failure, but only
# when full_validation is enabled. Off by default, so the non-strict path is
# unchanged (parity with the python schema pass being a no-op when validation
# is disabled).
sub _validate_verb_strict {
    my ( $self, $verb_name, $config ) = @_;
    return unless $self->full_validation;
    my ( $ok, $errors ) = $self->_schema_validator->validate_verb( $verb_name, $config );
    return if $ok;
    die SignalWire::Utils::SchemaValidationError->new(
        verb_name => $verb_name,
        errors    => $errors // [],
    );
}

# add_section(section_name) — create a new named section. Returns false if
# it already exists, true if created.
sub add_section {
    my ( $self, $section_name ) = @_;
    return 0 if $self->document->has_section($section_name);
    $self->document->add_section($section_name);
    return 1;
}

# add_verb_to_section(section_name, verb_name, config) — append a verb to a
# named section (creating the section if absent).
sub add_verb_to_section {
    my ( $self, $section_name, $verb_name, $config ) = @_;
    if ( $verb_name eq 'sleep' && defined $config && !ref $config ) {
        $self->document->add_verb( $section_name, $verb_name, int($config) );
        return 1;
    }
    return 0 unless defined $config && ref $config eq 'HASH';
    if ( my $handler = $self->verb_handlers->{$verb_name} ) {
        my ( $ok, $errors ) = $handler->validate_config($config);
        die "SWML verb '$verb_name' validation failed: @{ $errors // [] }\n" unless $ok;
    }

    # STRICT-RENDER: same schema pass as add_verb (see there). No-op when
    # full_validation is off.
    $self->_validate_verb_strict( $verb_name, $config );

    $self->document->add_verb( $section_name, $verb_name, $config );
    return 1;
}

# get_document — the current document as a plain hashref (parity with
# SWMLService.get_document, which returns the document dict).
sub get_document {
    my ($self) = @_;
    return $self->document->to_hash;
}

# render_document — the current document serialized to a JSON string.
sub render_document {
    my ($self) = @_;
    return $self->document->to_json;
}

# register_verb_handler(handler) — install a specialized verb handler; its
# get_verb_name() names the verb it validates/builds (parity with
# SWMLService.register_verb_handler).
sub register_verb_handler {
    my ( $self, $handler ) = @_;
    my $name = $handler->get_verb_name;
    $self->verb_handlers->{$name} = $handler;

    # Python parity: VerbHandlerRegistry.register_handler indexes the handler
    # by verb name under _handlers. Mirror the registration into the
    # introspectable verb_registry (which ships pre-loaded with the "ai"
    # handler — see the verb_registry default) so the registry reflects both.
    $self->verb_registry->{handlers}{$name} = $handler;
    return;
}

# full_validation_enabled — whether strict schema validation is on. Perl
# validates opportunistically; the flag defaults off and is honored by
# add_verb when a schema is available.
sub full_validation_enabled {
    my ($self) = @_;
    return $self->full_validation ? 1 : 0;
}

# manual_set_proxy_url(url) — override the external base URL used when
# building webhook URLs behind a reverse proxy (parity with
# SWMLService.manual_set_proxy_url / SWML_PROXY_URL_BASE).
sub manual_set_proxy_url {
    my ( $self, $proxy_url ) = @_;
    $proxy_url =~ s{/+$}{} if defined $proxy_url;
    $self->proxy_url_base($proxy_url);
    return;
}

# as_router — the PSGI app coderef that mounts this service (parity with
# SWMLService.as_router, which returns a FastAPI APIRouter). Perl's routable
# unit is the PSGI app.
sub as_router {
    my ($self) = @_;
    return $self->to_psgi_app;
}

# get_app — return the PSGI application for this service (deployment
# adapters mount this). Mirrors Python WebMixin.get_app, which returns
# the FastAPI app; the Perl analogue is the PSGI coderef from
# to_psgi_app.
sub get_app {
    my ($self) = @_;
    return $self->to_psgi_app;
}

# enable_debug_routes — turn on the service's debug endpoints. Mirrors
# WebMixin.enable_debug_routes. Returns $self for chaining.
sub enable_debug_routes {
    my ($self) = @_;
    $self->_debug_routes_enabled(1);
    return $self;
}

# setup_graceful_shutdown — install SIGTERM/SIGINT handlers that stop the
# running server (Kubernetes-friendly). Mirrors
# WebMixin.setup_graceful_shutdown. Returns $self for chaining; a
# platform that cannot trap a given signal is ignored quietly.
sub setup_graceful_shutdown {
    my ($self) = @_;
    for my $sig (qw(TERM INT)) {
        eval {
            ## no critic (Variables::RequireLocalizedPunctuationVars)
            # Intentionally a PERSISTENT process-wide signal handler (not a
            # localized one) — graceful shutdown must survive past this scope.
            $SIG{$sig} = sub {
                $self->_logger->info("shutdown_signal_received signal=$sig")
                    if $self->_logger;
                $self->stop;
            };
            1;
        };
    }
    return $self;
}

# serve(host, port) — start a blocking Plack HTTP server for this service.
# Parity with SWMLService.serve(host, port).
sub serve {
    my ( $self, %opts ) = @_;

    # In-process test guard (swaig-test --file, SWAIG_TEST_INPROCESS): never
    # bind/serve when the harness is loading this file to introspect it —
    # return $self so a file ending in `$svc->serve` yields the service instead
    # of blocking on a listen socket.
    return $self if $ENV{SWAIG_TEST_INPROCESS};

    my $host = $opts{host} // $self->host;
    my $port = $opts{port} // $self->port;
    require Plack::Runner;
    my $runner = Plack::Runner->new;
    $runner->parse_options( '--host', $host, '--port', $port );
    $self->_server_running(1);
    $runner->run( $self->to_psgi_app );
    return;
}

# stop — signal the running server to stop (parity with SWMLService.stop).
sub stop {
    my ($self) = @_;
    $self->_server_running(0);
    return;
}

# Customization hook called when SWML is requested. Default delegates to
# on_swml_request and returns its result. Subclasses typically override
# on_swml_request rather than this method.
#
# Return undef to use the default SWML rendering, or a hashref of
# modifications to merge into the rendered document.
#
# Python parity: WebMixin.on_request(request_data, callback_path).
# The Python third `request` argument is FastAPI-specific and
# intentionally not mirrored.
sub on_request {
    my ( $self, $request_data, $callback_path ) = @_;
    return $self->on_swml_request( $request_data, $callback_path );
}

# Customization point for subclasses to modify SWML based on request
# data. The default implementation returns undef (no modification).
#
# Python parity: WebMixin.on_swml_request(request_data, callback_path, request).
# The third ``$request`` parameter mirrors Python's optional FastAPI
# Request object; in Perl this is the PSGI ``$env`` hashref (or a
# wrapper produced by the calling code). Subclasses that don't need
# direct request access can ignore it.
sub on_swml_request {
    my ( $self, $request_data, $callback_path, $request ) = @_;
    return;
}

# ------------------------------------------------------------------
# SWAIG tool registry (lifted from AgentBase)
# ------------------------------------------------------------------

# Define a SWAIG function the AI can call. Tool descriptions and
# parameter descriptions are LLM-facing prompt engineering — see
# PORTING_GUIDE for guidance.
# Wrap a bare property map into a JSON-Schema object (SWAIG parameters shape),
# mirroring python's SWAIGFunction._ensure_parameter_structure. A hashref that
# already carries BOTH `type` and `properties` is returned unchanged; a bare
# property map (or empty/undef) is wrapped as { type => 'object', properties =>
# <map> }, merging any `required` list.
sub _normalise_tool_parameters {
    my ( $parameters, $required ) = @_;

    # Empty / undef -> the canonical empty object schema.
    if ( !defined $parameters || ref $parameters ne 'HASH' || !%$parameters ) {
        my %schema = ( type => 'object', properties => {} );
        $schema{required} = [@$required] if ref $required eq 'ARRAY' && @$required;
        return \%schema;
    }

    # Already a full object schema (has BOTH type and properties): use verbatim,
    # only merging an explicit `required` list not already present.
    if ( exists $parameters->{type} && exists $parameters->{properties} ) {
        return $parameters unless ref $required eq 'ARRAY' && @$required;
        my $existing = $parameters->{required} || [];
        my %seen;
        my @merged = grep { !$seen{$_}++ } ( @$existing, @$required );
        return { %$parameters, required => \@merged };
    }

    # Bare property map -> wrap it.
    my %schema = ( type => 'object', properties => $parameters );
    $schema{required} = [@$required] if ref $required eq 'ARRAY' && @$required;
    return \%schema;
}

sub define_tool {
    my ( $self, %opts ) = @_;
    my $name        = $opts{name}        // die("define_tool requires 'name'");
    my $description = $opts{description} // '';
    my $parameters  = $opts{parameters}  // { type => 'object', properties => {} };
    my $handler     = $opts{handler};

    # Normalise `parameters` into a valid JSON-Schema object so a caller may pass
    # a bare property map (the natural idiom) and still emit a SWAIG-valid schema.
    # Mirrors the python reference's SWAIGFunction._ensure_parameter_structure:
    # a map with BOTH `type` and `properties` is used verbatim; anything else is
    # wrapped as { type => 'object', properties => <map> } (with `required`
    # merged when given). Without this, a bare { city => {...} } was stored
    # verbatim — an invalid SWAIG parameters schema (no type/properties wrapper).
    $parameters = _normalise_tool_parameters( $parameters, $opts{required} );

    my $tool_def = {
        function    => $name,
        description => $description,
        parameters  => $parameters,

        # `secure` defaults to TRUE — a tool defined without an explicit
        # `secure` REQUIRES SWAIG token validation. Python parity:
        # tool_mixin.define_tool(..., secure: bool = True). This is
        # security-critical: the SDK must never silently register a tool as
        # unauthenticated because the caller omitted the flag. The wire
        # manifestation is the per-tool `__token` AgentBase's render appends
        # to a secure tool's `web_hook_url` when a call_id is active.
        secure => ( exists $opts{secure} ? ( $opts{secure} ? 1 : 0 ) : 1 ),
        ( defined $handler ? ( _handler => $handler ) : () ),
    };
    for my $k ( keys %opts ) {
        next if $k =~ /^(name|description|parameters|handler|required|secure)$/;
        $tool_def->{$k} = $opts{$k};
    }
    $self->tools->{$name} = $tool_def;
    push @{ $self->tool_order }, $name
        unless grep { $_ eq $name } @{ $self->tool_order };
    return $self;
}

# Register a raw SWAIG function definition (e.g. from DataMap).
sub register_swaig_function {
    my ( $self, $func_def ) = @_;
    my $name = $func_def->{function} // die("register_swaig_function needs 'function' key");
    $self->tools->{$name} = $func_def;
    push @{ $self->tool_order }, $name
        unless grep { $_ eq $name } @{ $self->tool_order };
    return $self;
}

# Whether a SWAIG function with the given name is registered.
# (Python parity: ToolRegistry.has_function.)
sub has_function {
    my ( $self, $name ) = @_;
    return exists $self->tools->{$name} ? 1 : 0;
}

# Get a registered SWAIG function by name, or undef when absent.
# (Python parity: ToolRegistry.get_function.)
sub get_function {
    my ( $self, $name ) = @_;
    return $self->tools->{$name};
}

# Snapshot of all registered SWAIG functions keyed by name.
# (Python parity: ToolRegistry.get_all_functions.)
sub get_all_functions {
    my ($self) = @_;
    return { %{ $self->tools } };
}

# Remove a registered SWAIG function. Returns 1 on success, 0 if absent.
# (Python parity: ToolRegistry.remove_function.)
sub remove_function {
    my ( $self, $name ) = @_;
    return 0 unless exists $self->tools->{$name};
    delete $self->tools->{$name};
    @{ $self->tool_order } = grep { $_ ne $name } @{ $self->tool_order };
    return 1;
}

# Register multiple tool definitions at once.
sub define_tools {
    my ( $self, @tool_defs ) = @_;
    for my $t (@tool_defs) {
        if ( ref $t eq 'HASH' ) {
            if ( exists $t->{function} ) {
                $self->register_swaig_function($t);
            } else {
                $self->define_tool(%$t);
            }
        }
    }
    return $self;
}

# Dispatch a function call to the registered handler. Default plain
# implementation. AgentBase may override to add token validation.
sub on_function_call {
    my ( $self, $name, $args, $raw_data ) = @_;
    my $tool = $self->tools->{$name};
    return unless $tool && $tool->{_handler};
    return $tool->{_handler}->( $args, $raw_data );
}

# List registered SWAIG tool names in registration order.
sub list_tool_names {
    my ($self) = @_;
    return @{ $self->tool_order };
}

# Extension point: invoked between argument parsing and function dispatch
# on POST /swaig. Returns ($target, $short_circuit). If $short_circuit is
# defined, it's encoded as the SWAIG response without calling
# on_function_call. AgentBase may override to add session-token validation.
sub swaig_pre_dispatch {
    my ( $self, $request_data, $func_name, $env ) = @_;
    return ( $self, undef );
}

# Extension point: subclasses may override to add /post_prompt, /mcp etc.
# Receives the relative sub-path (after the route prefix) and parsed body.
# Returns a PSGI response triple, or undef if not handled.
sub handle_additional_route {
    my ( $self, $sub_path, $request_data, $env ) = @_;
    return;
}

# Register a routing callback at a given sub-path under the service route.
sub register_routing_callback {
    my ( $self, $path, $cb ) = @_;

    # Normalize the path for consistent lookup (Python parity:
    # SWMLService.register_routing_callback -> path.rstrip("/") then ensure a
    # leading "/"). Without this, "/sip/" and "voice" register under
    # non-canonical keys and never match an incoming request path.
    $path = '' unless defined $path;
    $path =~ s{/+$}{};
    $path = "/$path" unless $path =~ m{^/};

    $self->routing_callbacks->{$path} = $cb;
    return $self;
}

sub _handle_swaig_request {
    my ( $self, $env ) = @_;
    my $method = $env->{REQUEST_METHOD} // 'GET';

    if ( $method eq 'GET' ) {
        my $doc = $self->render_main_swml($env);
        return _json_response( 200, $doc );
    }

    my $body = _read_body($env);
    my $payload;
    eval { $payload = JSON::decode_json($body) if length($body) };
    if ( $@ || !$payload || ref $payload ne 'HASH' ) {
        return _json_response( 400, { error => 'Invalid JSON' } );
    }

    my $func_name = $payload->{function};
    if ( !defined $func_name || $func_name eq '' ) {
        return _json_response( 400, { error => 'Missing function name' } );
    }
    if ( $func_name !~ $SWAIG_FN_NAME ) {
        return _json_response( 400, { error => "Invalid function name format: '$func_name'" } );
    }

    # Argument extraction: nested {argument:{parsed:[...]}} OR flat {arguments}
    my $args = {};
    if ( ref $payload->{argument} eq 'HASH' ) {
        my $parsed = $payload->{argument}{parsed};
        $args = $parsed->[0] if ref $parsed eq 'ARRAY' && @$parsed;
    } elsif ( ref $payload->{arguments} eq 'HASH' ) {
        $args = $payload->{arguments};
    }
    $args //= {};

    my ( $target, $short_circuit ) = $self->swaig_pre_dispatch( $payload, $func_name, $env );
    return _json_response( 200, $short_circuit ) if defined $short_circuit;

    my $result = $target->on_function_call( $func_name, $args, $payload );
    return _json_response( 404, { error => "Unknown function: $func_name" } )
        unless defined $result;

    # FunctionResult-like objects respond to to_hash; handlers may also
    # return plain hashrefs.
    my $result_hash;
    if ( ref $result eq 'HASH' ) {
        $result_hash = $result;
    } elsif ( Scalar::Util::blessed($result) && $result->can('to_hash') ) {
        $result_hash = $result->to_hash;
    } else {
        $result_hash = { response => "$result" };
    }
    return _json_response( 200, $result_hash );
}

sub _handle_post_prompt {
    my ( $self, $env ) = @_;
    return _json_response( 200, { response => 'Post prompt endpoint' } );
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::SWML::Service - foundation for SWML document management and serving

=head1 SYNOPSIS

    use SignalWire::SWML::Service;

    my $svc = SignalWire::SWML::Service->new(
        name  => 'my_service',
        route => '/swml',
    );

    # Build a SWML document (schema verbs auto-vivify via AUTOLOAD):
    $svc->answer;
    $svc->play({ url => 'https://example.com/hi.mp3' });

    # Or use the explicit document API:
    $svc->add_verb('hangup', {});
    my $json = $svc->render_document;

    # Register SWAIG tools:
    $svc->define_tool(
        name        => 'get_time',
        description => 'Return the current time',
        handler     => sub { ... },
    );

    # Serve over HTTP (Plack/PSGI):
    my $app = $svc->to_psgi_app;   # or $svc->serve(host => '0.0.0.0', port => 3000)

=head1 DESCRIPTION

L<SignalWire::SWML::Service> is the Perl port of
C<signalwire.core.swml_service.SWMLService>. It is a Moo class that owns a
L<SignalWire::SWML::Document>, exposes the document-building API, dispatches
inbound HTTP requests (SWML render, SWAIG function calls, post-prompt) as a
PSGI app, and provides basic-auth, routing callbacks, and a SWAIG tool
registry. L<SignalWire::Agent::AgentBase> extends this class.

SWML verbs are auto-vivified: any schema-known verb name (see
L<SignalWire::SWML::Schema>) called as a method (e.g. C<< $svc->play(...) >>)
appends that verb to the document's main section. C<can> is overridden to
report these schema verbs as callable.

=head1 ATTRIBUTES

Constructor attributes (all C<rw> unless noted). Key ones:

=over 4

=item C<name>

Service name (default C<'service'>).

=item C<route>

The base HTTP route the service is mounted at (default C<'/'>).

=item C<host>, C<port>

Bind host/port for C<serve> (default from C<SWML_HOST> / C<SWML_PORT> or
C<0.0.0.0>:C<3000>).

=item C<basic_auth_user>, C<basic_auth_password>

Basic-auth credentials for the protected routes; default to the
C<SWML_BASIC_AUTH_*> env vars or freshly generated secure random values.

=item C<document>

The composed L<SignalWire::SWML::Document> (default a fresh empty one).

=item C<verb_handlers>

Specialized verb handlers keyed by verb name
(see C<register_verb_handler>).

=item C<full_validation>

Strict-schema-validation flag (default off).

=item C<proxy_url_base>

External base URL override for webhook URLs behind a proxy (default from
C<SWML_PROXY_URL_BASE>).

=item C<tools>, C<tool_order>, C<routing_callbacks>

The SWAIG tool registry, its registration order, and routing callbacks.

=item C<schema_utils>, C<verb_registry>, C<security>

Lazily built accessors mirroring the Python reference's schema/verb-registry
/security surface.

=back

=head1 METHODS

=head2 Request handling / serving

=over 4

=item C<to_psgi_app>

Return the PSGI app coderef that dispatches this service's routes (main
SWML, C</swaig>, C</post_prompt>, health/ready). C<as_router> and C<get_app>
are aliases.

=item C<handle_request($method, $url, $headers, $body)>

The framework-free dispatch core. Performs basic-auth, the routing-callback
check, and the C<on_request> modification hook over plain primitives, and
returns a C<($status, \%headers, $body_string)> triple.

=item C<serve(host =E<gt> ..., port =E<gt> ...)>

Start a blocking Plack HTTP server. C<stop> signals it to stop.

=item C<setup_graceful_shutdown>

Install SIGTERM/SIGINT handlers that stop the running server. Returns
C<$self>.

=item C<enable_debug_routes>

Turn on the service's debug endpoints. Returns C<$self>.

=item C<render_main_swml($env)> / C<render_swml($env)>

Extension point returning the SWML document for the main path (subclasses
override to render at request time).

=back

=head2 Authentication

=over 4

=item C<validate_basic_auth($username, $password)>

Constant-time-compare the given credentials against the service's.

=item C<get_basic_auth_credentials($include_source)>

Return C<($user, $password)>, or C<($user, $password, $source)> when
C<$include_source> is truthy (source is C<provided>/C<environment>/
C<generated>). C<get_basic_auth_credentials_with_source> is a convenience
alias.

=item C<extract_sip_username($request_body)>

Class or instance method. Pull the username out of a request body's
C<call.to> field (SIP/TEL URI or plain destination); undef when the shape
does not match.

=back

=head2 Document manipulation

=over 4

=item C<reset_document>

Replace the working document with a fresh empty one.

=item C<add_verb($verb_name, $config)>

Append a verb to the main section (validating via a registered handler when
present). Returns true on success.

=item C<add_section($section_name)>

Create a new named section. Returns false if it already exists.

=item C<add_verb_to_section($section_name, $verb_name, $config)>

Append a verb to a named section (creating it if absent).

=item C<get_document>

The current document as a plain hashref.

=item C<render_document>

The current document serialized to a JSON string.

=item C<register_verb_handler($handler)>

Install a specialized verb handler (keyed by its C<get_verb_name>).

=item C<full_validation_enabled>

Whether strict schema validation is on.

=item C<manual_set_proxy_url($url)>

Override the external base URL used for webhook URLs behind a proxy.

=back

=head2 SWAIG tool registry

=over 4

=item C<define_tool(%opts)>

Define a SWAIG function the AI can call (C<name>, C<description>,
C<parameters>, C<handler>). Returns C<$self>.

=item C<define_tools(@tool_defs)>

Register multiple tool definitions at once.

=item C<register_swaig_function($func_def)>

Register a raw SWAIG function definition (e.g. from DataMap).

=item C<has_function($name)>, C<get_function($name)>,
C<get_all_functions>, C<remove_function($name)>

Query and manage the tool registry.

=item C<list_tool_names>

Registered tool names in registration order.

=item C<on_function_call($name, $args, $raw_data)>

Dispatch a function call to its registered handler.

=back

=head2 Extension / routing hooks

=over 4

=item C<on_request($request_data, $callback_path)> /
C<on_swml_request($request_data, $callback_path, $request)>

Customization hooks for modifying the SWML based on request data. The
default returns undef (no modification).

=item C<register_routing_callback($path, $cb)>

Register a routing callback at a sub-path under the service route.

=item C<swaig_pre_dispatch($request_data, $func_name, $env)>

Extension point between argument parsing and dispatch on POST C</swaig>;
returns C<($target, $short_circuit)>.

=item C<handle_additional_route($sub_path, $request_data, $env)>

Extension point for subclasses to add routes (e.g. C</mcp>). Returns a PSGI
triple or undef.

=back

=head1 SEE ALSO

L<SignalWire::SWML::Document>, L<SignalWire::SWML::Schema>,
L<SignalWire::Agent::AgentBase>, L<SignalWire::SWAIG::FunctionResult>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
