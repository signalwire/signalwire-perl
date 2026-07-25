package SignalWire::Core::SecurityConfig;

# Copyright (c) 2025 SignalWire
#
# This file is part of the SignalWire SDK.
#
# Licensed under the MIT License.
# See LICENSE file in the project root for full license information.
#
# Unified security configuration for SignalWire services. Perl port of
# signalwire.core.security_config.SecurityConfig. Provides centralized
# security settings (SSL, allowed hosts, CORS, security headers, basic auth)
# consumed by the web/agent services, ensuring consistent behavior.

use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
use JSON::PP     ();
use MIME::Base64 ();
use SignalWire::Core::ConfigLoader;
use SignalWire::Logging;

# ---------- security environment variable names ----------

use constant {
    SSL_ENABLED     => 'SWML_SSL_ENABLED',
    SSL_CERT_PATH   => 'SWML_SSL_CERT_PATH',
    SSL_KEY_PATH    => 'SWML_SSL_KEY_PATH',
    SSL_DOMAIN      => 'SWML_DOMAIN',
    SSL_VERIFY_MODE => 'SWML_SSL_VERIFY_MODE',

    ALLOWED_HOSTS    => 'SWML_ALLOWED_HOSTS',
    CORS_ORIGINS     => 'SWML_CORS_ORIGINS',
    MAX_REQUEST_SIZE => 'SWML_MAX_REQUEST_SIZE',
    RATE_LIMIT       => 'SWML_RATE_LIMIT',
    REQUEST_TIMEOUT  => 'SWML_REQUEST_TIMEOUT',
    USE_HSTS         => 'SWML_USE_HSTS',
    HSTS_MAX_AGE     => 'SWML_HSTS_MAX_AGE',

    BASIC_AUTH_USER     => 'SWML_BASIC_AUTH_USER',
    BASIC_AUTH_PASSWORD => 'SWML_BASIC_AUTH_PASSWORD',
};

# Defaults (secure by default), keyed by env-var name.
my %DEFAULTS = (
    SSL_ENABLED()      => 0,
    SSL_VERIFY_MODE()  => 'CERT_REQUIRED',
    ALLOWED_HOSTS()    => '*',
    CORS_ORIGINS()     => '*',
    MAX_REQUEST_SIZE() => 10 * 1024 * 1024,
    RATE_LIMIT()       => 60,
    REQUEST_TIMEOUT()  => 30,
    USE_HSTS()         => 1,
    HSTS_MAX_AGE()     => 31_536_000,
);

# ---------- attributes ----------

has ssl_enabled         => ( init_arg => undef, is => 'rw' );
has ssl_cert_path       => ( init_arg => undef, is => 'rw' );
has ssl_key_path        => ( init_arg => undef, is => 'rw' );
has domain              => ( init_arg => undef, is => 'rw' );
has ssl_verify_mode     => ( init_arg => undef, is => 'rw' );
has allowed_hosts       => ( init_arg => undef, is => 'rw' );
has cors_origins        => ( init_arg => undef, is => 'rw' );
has max_request_size    => ( init_arg => undef, is => 'rw' );
has rate_limit          => ( init_arg => undef, is => 'rw' );
has request_timeout     => ( init_arg => undef, is => 'rw' );
has use_hsts            => ( init_arg => undef, is => 'rw' );
has hsts_max_age        => ( init_arg => undef, is => 'rw' );
has basic_auth_user     => ( init_arg => undef, is => 'rw' );
has basic_auth_password => ( init_arg => undef, is => 'rw' );

has _basic_auth_autogen_warned => ( init_arg => undef, is => 'rw', default => sub { 0 } );

# Python parity: SecurityConfig.__init__(config_file=None, service_name=None).
# These are genuine construction parameters — BUILD reads them to locate and
# layer the config file over the environment defaults. Declared as real
# attributes (rather than only read out of ``$args``) so the constructor
# surface is introspectable and the values are readable after construction.
has config_file  => ( is => 'ro', default => sub { undef } );
has service_name => ( is => 'ro', default => sub { undef } );

# ---------- construction ----------

# Python signature: ``__init__(self, config_file=None, service_name=None)``.
# Defaults are applied first, then environment variables (backward compat),
# then a config file if available (highest priority).
sub BUILD ( $self, $args ) {
    $self->_set_defaults;
    $self->load_from_env;
    $self->_load_config_file( $self->config_file, $self->service_name );
    return;
}

# ---------- public methods ----------

# Load configuration from environment variables.
#
# Each read spells the SWML_* env var as a literal `$ENV{'SWML_...'}` (rather than
# `$ENV{ CONST() }`) so the read is statically visible — both to a human and to the
# cross-port DOC-ENV audit, which resolves `$ENV{LITERAL}` but cannot trace Perl's
# `use constant { NAME => 'SWML_...' }` fat-comma indirection. The constants above
# remain the single source of the names (still used as the %DEFAULTS keys).
sub load_from_env ($self) {
    my $ssl_enabled_env = lc( $ENV{'SWML_SSL_ENABLED'} // '' );
    $self->ssl_enabled( ( grep { $_ eq $ssl_enabled_env } qw(true 1 yes) ) ? 1 : 0 );
    $self->ssl_cert_path( $ENV{'SWML_SSL_CERT_PATH'} );
    $self->ssl_key_path( $ENV{'SWML_SSL_KEY_PATH'} );
    $self->domain( $ENV{'SWML_DOMAIN'} );
    $self->ssl_verify_mode( $ENV{'SWML_SSL_VERIFY_MODE'} // $DEFAULTS{ SSL_VERIFY_MODE() } );

    $self->allowed_hosts(
        $self->_parse_list( $ENV{'SWML_ALLOWED_HOSTS'} // $DEFAULTS{ ALLOWED_HOSTS() } ) );
    $self->cors_origins(
        $self->_parse_list( $ENV{'SWML_CORS_ORIGINS'} // $DEFAULTS{ CORS_ORIGINS() } ) );
    $self->max_request_size(
        int( $ENV{'SWML_MAX_REQUEST_SIZE'} // $DEFAULTS{ MAX_REQUEST_SIZE() } ) );
    $self->rate_limit( int( $ENV{'SWML_RATE_LIMIT'}           // $DEFAULTS{ RATE_LIMIT() } ) );
    $self->request_timeout( int( $ENV{'SWML_REQUEST_TIMEOUT'} // $DEFAULTS{ REQUEST_TIMEOUT() } ) );

    my $use_hsts_env = lc( $ENV{'SWML_USE_HSTS'} // '' );
    $self->use_hsts(
        length $use_hsts_env ? ( $use_hsts_env ne 'false' ? 1 : 0 ) : $DEFAULTS{ USE_HSTS() } );
    $self->hsts_max_age( int( $ENV{'SWML_HSTS_MAX_AGE'} // $DEFAULTS{ HSTS_MAX_AGE() } ) );

    $self->basic_auth_user( $ENV{'SWML_BASIC_AUTH_USER'} );
    $self->basic_auth_password( $ENV{'SWML_BASIC_AUTH_PASSWORD'} );
    return;
}

# Validate SSL configuration. Returns a two-element list
# ($is_valid, $error_message) ($error_message is undef when valid).
sub validate_ssl_config ($self) {
    return ( 1, undef )                                        unless $self->ssl_enabled;
    return ( 0, 'SSL enabled but SWML_SSL_CERT_PATH not set' ) unless $self->ssl_cert_path;
    return ( 0, 'SSL enabled but SWML_SSL_KEY_PATH not set' )  unless $self->ssl_key_path;
    return ( 0, 'SSL certificate file not found: ' . $self->ssl_cert_path )
        unless -e $self->ssl_cert_path;
    return ( 0, 'SSL key file not found: ' . $self->ssl_key_path )
        unless -e $self->ssl_key_path;
    return ( 1, undef );
}

# Get native TLS options for binding an SSL-enabled Plack/Starman server.
# Returns an empty hashref when SSL is disabled or the configuration fails
# validation.
#
# Perl idiom note: Python returns uvicorn ssl_certfile/ssl_keyfile kwargs;
# Perl returns IO::Socket::SSL option keys (SSL_cert_file / SSL_key_file)
# ready to hand to a Plack SSL server backend.
sub get_ssl_context_kwargs ($self) {
    return {} unless $self->ssl_enabled;

    my ($valid) = $self->validate_ssl_config;
    return {} unless $valid;

    return {
        SSL_cert_file => $self->ssl_cert_path,
        SSL_key_file  => $self->ssl_key_path,
    };
}

# Get basic auth credentials, generating a random password if not set.
# Returns a two-element list ($username, $password).
sub get_basic_auth ($self) {
    my $username = $self->basic_auth_user || 'signalwire';
    if ( !defined $self->basic_auth_password || !length $self->basic_auth_password ) {
        $self->basic_auth_password( _token_urlsafe(32) );
        $self->_warn_basic_auth_autogen($username);
    }
    return ( $username, $self->basic_auth_password );
}

# Get security headers to add to responses. When $is_https is true and HSTS
# is enabled, a Strict-Transport-Security header is included.
sub get_security_headers ( $self, %opts ) {
    my $is_https = $opts{is_https} ? 1 : 0;
    my %headers  = (
        'X-Content-Type-Options' => 'nosniff',
        'X-Frame-Options'        => 'DENY',
        'X-XSS-Protection'       => '1; mode=block',
        'Referrer-Policy'        => 'strict-origin-when-cross-origin',
    );
    if ( $is_https && $self->use_hsts ) {
        $headers{'Strict-Transport-Security'} =
            'max-age=' . $self->hsts_max_age . '; includeSubDomains';
    }
    return \%headers;
}

# Check if a host is allowed ('*' in the allowed list allows all).
sub should_allow_host ( $self, $host ) {
    return 1 if grep { $_ eq '*' } @{ $self->allowed_hosts };
    return ( grep { $_ eq $host } @{ $self->allowed_hosts } ) ? 1 : 0;
}

# Get CORS configuration.
sub get_cors_config ($self) {
    return {
        allow_origins     => $self->cors_origins,
        allow_credentials => JSON::PP::true(),
        allow_methods     => ['*'],
        allow_headers     => ['*'],
    };
}

# Get the URL scheme based on SSL configuration.
sub get_url_scheme ($self) {
    return $self->ssl_enabled ? 'https' : 'http';
}

# Log the current security configuration.
sub log_config ( $self, $service_name ) {
    $self->_logger->info(
        "security_config_loaded service=$service_name " . $self->_config_summary );
    return;
}

# ---------- private helpers ----------

sub _logger ($self) {
    return SignalWire::Logging->get_logger('security_config');
}

sub _config_summary ($self) {
    my $has_basic_auth =
        ( defined $self->basic_auth_user && defined $self->basic_auth_password ) ? 1 : 0;
    return
          'ssl_enabled='
        . $self->ssl_enabled
        . ' domain='
        . ( defined $self->domain ? $self->domain : 'undef' )
        . ' allowed_hosts='
        . join( ',', @{ $self->allowed_hosts } )
        . ' cors_origins='
        . join( ',', @{ $self->cors_origins } )
        . ' max_request_size='
        . $self->max_request_size
        . ' rate_limit='
        . $self->rate_limit
        . ' use_hsts='
        . $self->use_hsts
        . " has_basic_auth=$has_basic_auth";
}

sub _set_defaults ($self) {
    $self->ssl_enabled( $DEFAULTS{ SSL_ENABLED() } );
    $self->ssl_cert_path(undef);
    $self->ssl_key_path(undef);
    $self->domain(undef);
    $self->ssl_verify_mode( $DEFAULTS{ SSL_VERIFY_MODE() } );

    $self->allowed_hosts( $self->_parse_list( $DEFAULTS{ ALLOWED_HOSTS() } ) );
    $self->cors_origins( $self->_parse_list( $DEFAULTS{ CORS_ORIGINS() } ) );
    $self->max_request_size( $DEFAULTS{ MAX_REQUEST_SIZE() } );
    $self->rate_limit( $DEFAULTS{ RATE_LIMIT() } );
    $self->request_timeout( $DEFAULTS{ REQUEST_TIMEOUT() } );
    $self->use_hsts( $DEFAULTS{ USE_HSTS() } );
    $self->hsts_max_age( $DEFAULTS{ HSTS_MAX_AGE() } );

    $self->basic_auth_user(undef);
    $self->basic_auth_password(undef);
    return;
}

sub _load_config_file ( $self, $config_file, $service_name ) {
    $config_file //= SignalWire::Core::ConfigLoader->find_config_file($service_name);
    return unless $config_file;

    my $loader = SignalWire::Core::ConfigLoader->new( [$config_file] );
    return unless $loader->has_config;

    my $section = $loader->get_section('security');
    return unless $section && %$section;

    $self->_apply_security_section($section);
    return;
}

sub _apply_security_section ( $self, $section ) {
    $self->ssl_enabled( $section->{ssl_enabled} )         if exists $section->{ssl_enabled};
    $self->ssl_cert_path( $section->{ssl_cert_path} )     if exists $section->{ssl_cert_path};
    $self->ssl_key_path( $section->{ssl_key_path} )       if exists $section->{ssl_key_path};
    $self->domain( $section->{domain} )                   if exists $section->{domain};
    $self->ssl_verify_mode( $section->{ssl_verify_mode} ) if exists $section->{ssl_verify_mode};

    $self->allowed_hosts( $self->_parse_list( $section->{allowed_hosts} ) )
        if exists $section->{allowed_hosts};
    $self->cors_origins( $self->_parse_list( $section->{cors_origins} ) )
        if exists $section->{cors_origins};
    $self->max_request_size( int $section->{max_request_size} )
        if exists $section->{max_request_size};
    $self->rate_limit( int $section->{rate_limit} )           if exists $section->{rate_limit};
    $self->request_timeout( int $section->{request_timeout} ) if exists $section->{request_timeout};

    $self->use_hsts( $section->{use_hsts} )             if exists $section->{use_hsts};
    $self->hsts_max_age( int $section->{hsts_max_age} ) if exists $section->{hsts_max_age};

    my $auth_config = $section->{auth};
    return unless ref $auth_config eq 'HASH';
    my $basic = $auth_config->{basic};
    return unless ref $basic eq 'HASH';
    $self->basic_auth_user( $basic->{user} )         if exists $basic->{user};
    $self->basic_auth_password( $basic->{password} ) if exists $basic->{password};
    return;
}

# Parse a comma-separated string (or pass an arrayref through) into a list.
sub _parse_list ( $self, $value ) {
    return $value if ref $value eq 'ARRAY';
    return ['*']  if defined $value && $value eq '*';
    return [ grep { length } map { s/^\s+|\s+$//gr } split /,/, ( $value // '' ) ];
}

sub _warn_basic_auth_autogen ( $self, $username ) {
    return if $self->_basic_auth_autogen_warned;
    $self->_logger->warn( "basic_auth_password_autogenerated username=$username: no "
            . 'SWML_BASIC_AUTH_PASSWORD in environment and no password passed; generated a '
            . 'random password that exists only in this process. External callers will get '
            . "HTTP 401 unless they read it from this process's env. Set SWML_BASIC_AUTH_USER "
            . '/ SWML_BASIC_AUTH_PASSWORD to suppress.' );
    $self->_basic_auth_autogen_warned(1);
    return;
}

# URL-safe random token, base64-flavoured (mirrors secrets.token_urlsafe).
sub _token_urlsafe ($nbytes) {
    my $raw = '';
    $raw .= chr( int rand 256 ) for 1 .. $nbytes;
    my $b64 = MIME::Base64::encode_base64( $raw, '' );
    $b64 =~ tr{+/}{-_};
    $b64 =~ s/=+$//;
    return $b64;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Core::SecurityConfig - unified security configuration for services

=head1 SYNOPSIS

    use SignalWire::Core::SecurityConfig;

    my $cfg = SignalWire::Core::SecurityConfig->new;
    my ( $ok, $err ) = $cfg->validate_ssl_config;
    my ( $user, $pass ) = $cfg->get_basic_auth;
    my $headers = $cfg->get_security_headers( is_https => 1 );
    my $scheme  = $cfg->get_url_scheme;

=head1 DESCRIPTION

L<SignalWire::Core::SecurityConfig> is a Perl port of
C<signalwire.core.security_config.SecurityConfig>. It centralises security
settings — SSL, allowed hosts, CORS, security headers, and basic auth — so
the web/agent services behave consistently. Defaults are applied first, then
environment variables (backward compatibility), then a config file if
available (highest priority).

=head1 METHODS

=over 4

=item * C<new(config_file =E<gt> ..., service_name =E<gt> ...)> — construct
and load defaults, env, and (optionally) a config file.

=item * C<load_from_env> — (re)load from C<SWML_*> environment variables.

=item * C<validate_ssl_config> — returns C<($is_valid, $error_message)>.

=item * C<get_ssl_context_kwargs> — IO::Socket::SSL options
(C<SSL_cert_file> / C<SSL_key_file>) or an empty hashref.

=item * C<get_basic_auth> — C<($username, $password)>, auto-generating a
random password (with a one-time warning) when none is configured.

=item * C<get_security_headers(is_https =E<gt> ...)> — standard security
response headers (plus HSTS over HTTPS).

=item * C<should_allow_host($host)> — allow-list check (C<*> allows all).

=item * C<get_cors_config> / C<get_url_scheme> — CORS settings and the URL
scheme derived from SSL.

=item * C<log_config($service_name)> — log the current configuration summary.

=back

=head1 SEE ALSO

L<SignalWire::Core::ConfigLoader>, L<SignalWire::Core::AuthHandler>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
