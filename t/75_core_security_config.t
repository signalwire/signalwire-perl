#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use SignalWire::Core::SecurityConfig;

# Ensure a clean environment for the default-value tests.
delete local @ENV{
    grep { /^SWML_/ } keys %ENV
};

subtest 'defaults' => sub {
    my $c = SignalWire::Core::SecurityConfig->new;
    ok( !$c->ssl_enabled, 'ssl disabled by default' );
    is( $c->ssl_verify_mode, 'CERT_REQUIRED', 'default verify mode' );
    is_deeply( $c->allowed_hosts, ['*'], 'allowed hosts default *' );
    is_deeply( $c->cors_origins,  ['*'], 'cors origins default *' );
    is( $c->max_request_size, 10 * 1024 * 1024, 'default max request size' );
    is( $c->rate_limit,       60,              'default rate limit' );
    is( $c->request_timeout,  30,              'default request timeout' );
    ok( $c->use_hsts, 'hsts on by default' );
    is( $c->hsts_max_age, 31_536_000, 'default hsts max age' );
};

subtest 'load_from_env' => sub {
    local $ENV{SWML_SSL_ENABLED}    = 'true';
    local $ENV{SWML_ALLOWED_HOSTS}  = 'a.com, b.com';
    local $ENV{SWML_CORS_ORIGINS}   = 'https://x.com, https://y.com';
    local $ENV{SWML_DOMAIN}         = 'agent.example.test';
    local $ENV{SWML_RATE_LIMIT}     = '120';
    local $ENV{SWML_REQUEST_TIMEOUT} = '45';
    local $ENV{SWML_MAX_REQUEST_SIZE} = '2048';
    local $ENV{SWML_SSL_VERIFY_MODE}  = 'CERT_OPTIONAL';
    local $ENV{SWML_HSTS_MAX_AGE}     = '600';
    local $ENV{SWML_USE_HSTS}       = 'false';
    my $c = SignalWire::Core::SecurityConfig->new;
    ok( $c->ssl_enabled, 'ssl enabled from env' );
    is_deeply( $c->allowed_hosts, [ 'a.com', 'b.com' ], 'hosts parsed + trimmed' );
    is_deeply( $c->cors_origins, [ 'https://x.com', 'https://y.com' ], 'cors origins from env' );
    is( $c->domain,           'agent.example.test', 'domain from env' );
    is( $c->rate_limit,       120,                  'rate limit from env' );
    is( $c->request_timeout,  45,                   'request timeout from env' );
    is( $c->max_request_size, 2048,                 'max request size from env' );
    is( $c->ssl_verify_mode,  'CERT_OPTIONAL',      'ssl verify mode from env' );
    is( $c->hsts_max_age,     600,                  'hsts max-age from env' );
    ok( !$c->use_hsts, 'hsts disabled from env' );
};

subtest 'validate_ssl_config' => sub {
    my $c = SignalWire::Core::SecurityConfig->new;
    my ( $ok, $err ) = $c->validate_ssl_config;
    ok( $ok, 'valid when ssl disabled' );
    is( $err, undef, 'no error when disabled' );

    $c->ssl_enabled(1);
    $c->ssl_cert_path(undef);
    ( $ok, $err ) = $c->validate_ssl_config;
    ok( !$ok, 'invalid when enabled without cert' );
    like( $err, qr/SWML_SSL_CERT_PATH/, 'error mentions missing cert path' );
};

subtest 'get_ssl_context_kwargs' => sub {
    my $c = SignalWire::Core::SecurityConfig->new;
    is_deeply( $c->get_ssl_context_kwargs, {}, 'empty when ssl disabled' );
    $c->ssl_enabled(1);
    $c->ssl_cert_path('/no/such/cert');    # fails validation -> empty
    is_deeply( $c->get_ssl_context_kwargs, {}, 'empty when validation fails' );
};

subtest 'get_basic_auth generates a password' => sub {
    my $c = SignalWire::Core::SecurityConfig->new;
    $c->basic_auth_user(undef);
    $c->basic_auth_password(undef);
    my ( $user, $pass ) = $c->get_basic_auth;
    is( $user, 'signalwire', 'default username' );
    ok( length $pass > 0, 'password auto-generated' );

    # explicit credentials preserved
    my $c2 = SignalWire::Core::SecurityConfig->new;
    $c2->basic_auth_user('bob');
    $c2->basic_auth_password('secret');
    is_deeply( [ $c2->get_basic_auth ], [ 'bob', 'secret' ], 'explicit creds preserved' );
};

subtest 'get_security_headers' => sub {
    my $c = SignalWire::Core::SecurityConfig->new;
    my $h = $c->get_security_headers;
    is( $h->{'X-Content-Type-Options'}, 'nosniff', 'nosniff header' );
    is( $h->{'X-Frame-Options'},        'DENY',    'frame options' );
    ok( !exists $h->{'Strict-Transport-Security'}, 'no HSTS header over http' );

    my $h2 = $c->get_security_headers( is_https => 1 );
    like( $h2->{'Strict-Transport-Security'}, qr/max-age=/, 'HSTS header over https' );
};

subtest 'should_allow_host / get_cors_config / get_url_scheme' => sub {
    my $c = SignalWire::Core::SecurityConfig->new;
    ok( $c->should_allow_host('anything.com'), 'wildcard allows any host' );

    $c->allowed_hosts( [ 'only.com' ] );
    ok( $c->should_allow_host('only.com'),   'listed host allowed' );
    ok( !$c->should_allow_host('other.com'), 'unlisted host denied' );

    my $cors = $c->get_cors_config;
    is_deeply( $cors->{allow_methods}, ['*'], 'cors allow_methods' );

    is( $c->get_url_scheme, 'http', 'http when ssl off' );
    $c->ssl_enabled(1);
    is( $c->get_url_scheme, 'https', 'https when ssl on' );
};

subtest 'log_config does not die' => sub {
    my $c = SignalWire::Core::SecurityConfig->new;
    eval { $c->log_config('unit-test') };
    is( $@, '', 'log_config runs without error' );
};

done_testing;
