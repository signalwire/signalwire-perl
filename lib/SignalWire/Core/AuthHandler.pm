package SignalWire::Core::AuthHandler;

# Copyright (c) 2025 SignalWire
#
# This file is part of the SignalWire SDK.
#
# Licensed under the MIT License.
# See LICENSE file in the project root for full license information.
#
# Unified authentication handler supporting multiple auth methods. Perl port
# of signalwire.core.auth_handler.AuthHandler. Provides a clean pattern for
# handling Basic Auth, Bearer tokens, and API keys across all SignalWire
# services. All credential comparisons are timing-safe.
#
# Perl idiom note: Python's flask_decorator / get_fastapi_dependency are
# framework-bound (Flask / FastAPI). Perl has neither; the native equivalents
# here are PSGI/Plack-based (Perl's standard web interface):
#   * plack_middleware -- a PSGI app wrapper so unauthenticated requests get a
#     401, exposed under the parity name flask_decorator.
#   * plack_dependency -- a callable taking a PSGI env and returning an
#     auth-result hashref, exposed under the parity name
#     get_fastapi_dependency.

use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
use MIME::Base64 ();
use SignalWire::Logging;

# ---------- attributes ----------

# The SecurityConfig (or any object exposing get_basic_auth and optional
# bearer_token / api_key / api_key_header readers).
has security_config => ( is => 'ro', required => 1 );

# Enabled auth methods, keyed by name ('basic'/'bearer'/'api_key').
has auth_methods => ( is => 'rw', default => sub { {} } );

# ---------- construction ----------

sub BUILD ( $self, $args ) {
    $self->_setup_auth_methods;
    return;
}

# Python signature: ``__init__(self, security_config)``. Accept the
# positional security_config as the first constructor argument.
sub BUILDARGS ( $class, @args ) {
    if (   @args == 1
        && ref $args[0]
        && !( ref $args[0] eq 'HASH' && exists $args[0]->{security_config} ) )
    {
        return { security_config => $args[0] };
    }
    return {@args};
}

# ---------- public methods ----------

# Verify basic auth credentials (any object responding to username/password).
# Timing-safe.
sub verify_basic_auth ( $self, $credentials ) {
    return 0 unless $self->auth_methods->{basic} && $self->auth_methods->{basic}{enabled};
    my $basic = $self->auth_methods->{basic};
    return (   _secure_compare( $credentials->username, $basic->{username} )
            && _secure_compare( $credentials->password, $basic->{password} ) ) ? 1 : 0;
}

# Verify a bearer token (any object responding to credentials). Timing-safe.
sub verify_bearer_token ( $self, $credentials ) {
    return 0 unless $self->auth_methods->{bearer} && $self->auth_methods->{bearer}{enabled};
    return _secure_compare( $credentials->credentials, $self->auth_methods->{bearer}{token} );
}

# Verify an API key string. Timing-safe.
sub verify_api_key ( $self, $api_key ) {
    return 0 unless $self->auth_methods->{api_key} && $self->auth_methods->{api_key}{enabled};
    return _secure_compare( $api_key, $self->auth_methods->{api_key}{key} );
}

# Native PSGI equivalent of Python's FastAPI dependency. Returns a coderef
# that takes a PSGI $env and returns an auth-result hashref
# { authenticated => 0|1, method => $name|undef }. When $optional is false
# and authentication fails, the coderef dies with a
# SignalWire::Core::AuthError (carrying a 401 PSGI response). When $optional
# is true it returns the result without dying. Exposed under the parity name
# get_fastapi_dependency.
sub plack_dependency ( $self, %opts ) {
    my $optional = $opts{optional} ? 1 : 0;
    return sub ($env) {
        my $method        = $self->_authenticate_env($env);
        my $authenticated = defined $method ? 1 : 0;
        if ( !$authenticated && !$optional ) {
            die SignalWire::Core::AuthError->new( _unauthorized_response() );
        }
        return { authenticated => $authenticated, method => $method };
    };
}

sub get_fastapi_dependency ( $self, %opts ) { return $self->plack_dependency(%opts); }

# Native PSGI equivalent of Python's Flask decorator. Given a PSGI app (a
# coderef taking $env), returns a wrapping app that enforces authentication:
# authenticated requests pass through, others get an HTTP 401 with a
# WWW-Authenticate challenge. Exposed under the parity name flask_decorator.
sub plack_middleware ( $self, $app ) {
    return sub ($env) {
        if ( $self->_authenticate_env($env) ) {
            return $app->($env);
        }
        $self->_log_auth_failure($env);
        return _unauthorized_response();
    };
}

sub flask_decorator ( $self, $app ) { return $self->plack_middleware($app); }

# Get information about configured auth methods (never includes secrets).
sub get_auth_info ($self) {
    my %info;
    $info{basic} = $self->_basic_auth_info
        if $self->auth_methods->{basic} && $self->auth_methods->{basic}{enabled};
    $info{bearer} = _bearer_auth_info()
        if $self->auth_methods->{bearer} && $self->auth_methods->{bearer}{enabled};
    $info{api_key} = $self->_api_key_info
        if $self->auth_methods->{api_key} && $self->auth_methods->{api_key}{enabled};
    return \%info;
}

# ---------- private helpers ----------

sub _setup_auth_methods ($self) {
    my %methods;
    my ( $username, $password ) = $self->security_config->get_basic_auth;
    $methods{basic} = { enabled => 1, username => $username, password => $password };

    my $bearer_token = $self->_config_attr('bearer_token');
    $methods{bearer} = { enabled => 1, token => $bearer_token } if $bearer_token;

    my $api_key = $self->_config_attr('api_key');
    if ($api_key) {
        my $header = $self->_config_attr('api_key_header') || 'X-API-Key';
        $methods{api_key} = { enabled => 1, key => $api_key, header => $header };
    }

    $self->auth_methods( \%methods );
    return;
}

sub _config_attr ( $self, $name ) {
    my $cfg = $self->security_config;
    return $cfg->can($name) ? $cfg->$name : undef;
}

# Try each configured auth method against a PSGI env. Returns the name of the
# method that authenticated ('bearer'/'api_key'/'basic'), or undef.
sub _authenticate_env ( $self, $env ) {
    return 'bearer'  if $self->_bearer_env_ok($env);
    return 'api_key' if $self->_api_key_env_ok($env);
    return 'basic'   if $self->_basic_env_ok($env);
    return;
}

sub _bearer_env_ok ( $self, $env ) {
    return 0 unless $self->auth_methods->{bearer} && $self->auth_methods->{bearer}{enabled};
    my $header = $env->{HTTP_AUTHORIZATION} // '';
    return 0 unless index( $header, 'Bearer ' ) == 0;
    return $self->verify_bearer_token(
        SignalWire::Core::AuthHandler::BearerCredentials->new( substr( $header, 7 ) ) );
}

sub _api_key_env_ok ( $self, $env ) {
    return 0 unless $self->auth_methods->{api_key} && $self->auth_methods->{api_key}{enabled};
    ( my $rack_header = uc $self->auth_methods->{api_key}{header} ) =~ tr/-/_/;
    my $key = $env->{"HTTP_$rack_header"};
    return ( defined $key && $self->verify_api_key($key) ) ? 1 : 0;
}

sub _basic_env_ok ( $self, $env ) {
    return 0 unless $self->auth_methods->{basic} && $self->auth_methods->{basic}{enabled};
    my $creds = _parse_basic_auth( $env->{HTTP_AUTHORIZATION} // '' );
    return 0 unless defined $creds;
    return $self->verify_basic_auth($creds);
}

sub _parse_basic_auth ($header) {
    return unless index( $header, 'Basic ' ) == 0;
    my $decoded = MIME::Base64::decode_base64( substr( $header, 6 ) );
    my ( $user, $pass ) = split /:/, $decoded, 2;
    return SignalWire::Core::AuthHandler::BasicCredentials->new( $user // '', $pass // '' );
}

# Constant-time comparison. Both args stringified; length mismatch returns 0
# immediately (as Python's secrets.compare_digest also requires equal length).
sub _secure_compare ( $lhs, $rhs ) {
    $lhs = defined $lhs ? "$lhs" : '';
    $rhs = defined $rhs ? "$rhs" : '';
    return 0 if length($lhs) != length($rhs);
    my $diff = 0;
    for my $i ( 0 .. length($lhs) - 1 ) {
        $diff |= ord( substr( $lhs, $i, 1 ) ) ^ ord( substr( $rhs, $i, 1 ) );
    }
    return $diff == 0 ? 1 : 0;
}

sub _unauthorized_response {
    return [
        401,
        [
            'Content-Type'     => 'text/plain',
            'WWW-Authenticate' => 'Basic realm="SignalWire Service"',
        ],
        ['Authentication required'],
    ];
}

sub _log_auth_failure ( $self, $env ) {
    SignalWire::Logging->get_logger('auth_handler')
        ->warn( 'auth_failed ip='
            . ( $env->{REMOTE_ADDR} // '' )
            . ' method='
            . ( $env->{REQUEST_METHOD} // '' )
            . ' path='
            . ( $env->{PATH_INFO} // '' ) );
    return;
}

sub _basic_auth_info ($self) {
    return { enabled => 1, username => $self->auth_methods->{basic}{username} };
}

sub _bearer_auth_info {
    return { enabled => 1, hint => 'Use Authorization: Bearer <token>' };
}

sub _api_key_info ($self) {
    my $header = $self->auth_methods->{api_key}{header};
    return { enabled => 1, header => $header, hint => "Use ${header}: <key>" };
}

# ---------- lightweight credential carriers ----------
# Parity with FastAPI's HTTPBasicCredentials / HTTPAuthorizationCredentials.

package SignalWire::Core::AuthHandler::BasicCredentials;
use strict;
use warnings;

sub new {
    my ( $class, $username, $password ) = @_;
    return bless { username => $username, password => $password }, $class;
}
sub username { return $_[0]->{username} }    ## no critic (Subroutines::RequireArgUnpacking)
sub password { return $_[0]->{password} }    ## no critic (Subroutines::RequireArgUnpacking)

package SignalWire::Core::AuthHandler::BearerCredentials;
use strict;
use warnings;

sub new {
    my ( $class, $credentials ) = @_;
    return bless { credentials => $credentials }, $class;
}
sub credentials { return $_[0]->{credentials} }    ## no critic (Subroutines::RequireArgUnpacking)

# ---------- AuthError ----------
# Raised by the plack_dependency callable when required authentication
# fails. Carries the PSGI 401 response arrayref.

package SignalWire::Core::AuthError;
use strict;
use warnings;
use overload '""' => sub { $_[0]->{message} }, fallback => 1;

sub new {
    my ( $class, $response ) = @_;
    return bless { response => $response, message => 'Invalid authentication credentials' }, $class;
}
sub response { return $_[0]->{response} }    ## no critic (Subroutines::RequireArgUnpacking)
sub message  { return $_[0]->{message} }     ## no critic (Subroutines::RequireArgUnpacking)

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Core::AuthHandler - unified multi-method authentication handler

=head1 SYNOPSIS

    use SignalWire::Core::SecurityConfig;
    use SignalWire::Core::AuthHandler;

    my $handler = SignalWire::Core::AuthHandler->new(
        SignalWire::Core::SecurityConfig->new );

    my $info = $handler->get_auth_info;

    # PSGI middleware (parity name: flask_decorator)
    my $guarded = $handler->plack_middleware($app);

    # PSGI dependency (parity name: get_fastapi_dependency)
    my $dep = $handler->plack_dependency( optional => 1 );
    my $result = $dep->($psgi_env);   # { authenticated => 0|1, method => ... }

=head1 DESCRIPTION

L<SignalWire::Core::AuthHandler> is a Perl port of
C<signalwire.core.auth_handler.AuthHandler>. It handles Basic Auth, Bearer
tokens, and API keys uniformly across SignalWire services. All credential
comparisons are timing-safe (a constant-time byte compare).

Python's C<flask_decorator> and C<get_fastapi_dependency> are framework-bound
(Flask / FastAPI). Perl uses PSGI/Plack as its standard web interface, so the
analogs are C<plack_middleware> (a PSGI app wrapper enforcing a 401) and
C<plack_dependency> (a PSGI-env callable returning an auth result); the
Python parity names C<flask_decorator> and C<get_fastapi_dependency> are
provided as thin wrappers.

=head1 METHODS

=over 4

=item * C<new($security_config)> — construct from a
L<SignalWire::Core::SecurityConfig> (or any object exposing C<get_basic_auth>
and optional C<bearer_token> / C<api_key> / C<api_key_header>).

=item * C<verify_basic_auth($creds)> / C<verify_bearer_token($creds)> /
C<verify_api_key($key)> — timing-safe credential checks.

=item * C<plack_dependency(optional =E<gt> ...)> (aka
C<get_fastapi_dependency>) — a PSGI-env callable returning
C<{ authenticated =E<gt> 0|1, method =E<gt> ... }>; dies with
L<SignalWire::Core::AuthError> when required auth fails.

=item * C<plack_middleware($app)> (aka C<flask_decorator>) — wrap a PSGI app
so unauthenticated requests get a 401.

=item * C<get_auth_info> — a secrets-free description of configured methods.

=back

=head1 SEE ALSO

L<SignalWire::Core::SecurityConfig>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
