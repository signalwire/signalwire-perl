#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use MIME::Base64 ();

use SignalWire::Core::AuthHandler;

# ---- a minimal security-config stub ----
{
    package FakeSecConfig;
    sub new {
        my ( $class, %opts ) = @_;
        return bless { %opts }, $class;
    }
    sub get_basic_auth { return ( $_[0]->{user} // 'signalwire', $_[0]->{pass} // 'pw' ); }
    sub bearer_token   { return $_[0]->{bearer}; }
    sub api_key        { return $_[0]->{api_key}; }
    sub api_key_header { return $_[0]->{api_key_header}; }
}

sub basic_env {
    my ( $u, $p ) = @_;
    return { HTTP_AUTHORIZATION => 'Basic ' . MIME::Base64::encode_base64( "$u:$p", '' ) };
}

subtest 'construction + basic method always enabled' => sub {
    my $h = SignalWire::Core::AuthHandler->new(
        FakeSecConfig->new( user => 'bob', pass => 'sekret' ) );
    ok( $h, 'handler created' );
    ok( $h->auth_methods->{basic}{enabled}, 'basic auth enabled' );
    my $info = $h->get_auth_info;
    is( $info->{basic}{username}, 'bob', 'get_auth_info exposes username' );
    ok( !exists $info->{basic}{password}, 'get_auth_info never leaks password' );
    ok( !exists $info->{bearer},  'no bearer configured' );
    ok( !exists $info->{api_key}, 'no api key configured' );
};

subtest 'verify_basic_auth (timing-safe)' => sub {
    my $h = SignalWire::Core::AuthHandler->new(
        FakeSecConfig->new( user => 'bob', pass => 'sekret' ) );
    my $good = SignalWire::Core::AuthHandler::BasicCredentials->new( 'bob', 'sekret' );
    my $bad  = SignalWire::Core::AuthHandler::BasicCredentials->new( 'bob', 'wrong' );
    ok( $h->verify_basic_auth($good),  'correct creds accepted' );
    ok( !$h->verify_basic_auth($bad),  'wrong password rejected' );
};

subtest 'verify_bearer_token + verify_api_key' => sub {
    my $h = SignalWire::Core::AuthHandler->new(
        FakeSecConfig->new(
            bearer  => 'tok123',
            api_key => 'key456',
        )
    );
    ok( $h->auth_methods->{bearer}{enabled},  'bearer enabled when configured' );
    ok( $h->auth_methods->{api_key}{enabled}, 'api_key enabled when configured' );

    my $b_good = SignalWire::Core::AuthHandler::BearerCredentials->new( 'Bearer', 'tok123' );
    my $b_bad  = SignalWire::Core::AuthHandler::BearerCredentials->new( 'Bearer', 'nope' );
    ok( $h->verify_bearer_token($b_good), 'valid bearer accepted' );
    ok( !$h->verify_bearer_token($b_bad), 'invalid bearer rejected' );

    is( $b_good->scheme,      'Bearer', 'BearerCredentials carries the scheme' );
    is( $b_good->credentials, 'tok123', 'BearerCredentials carries the credentials' );

    ok( $h->verify_api_key('key456'), 'valid api key accepted' );
    ok( !$h->verify_api_key('bad'),   'invalid api key rejected' );

    my $info = $h->get_auth_info;
    is( $info->{api_key}{header}, 'X-API-Key', 'default api key header' );
    like( $info->{bearer}{hint}, qr/Bearer/, 'bearer hint present' );
};

subtest 'bearer env path carries the scheme, not just the token' => sub {
    my $h = SignalWire::Core::AuthHandler->new( FakeSecConfig->new( bearer => 'tok123' ) );

    # Capture the carrier the PSGI-env path actually constructs, so the split is
    # asserted where the header is parsed — not only on a hand-built carrier.
    my $seen;
    no warnings 'redefine';    ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    my $real = \&SignalWire::Core::AuthHandler::verify_bearer_token;
    local *SignalWire::Core::AuthHandler::verify_bearer_token = sub {
        $seen = $_[1];
        return $real->(@_);
    };

    ok( $h->_bearer_env_ok( { HTTP_AUTHORIZATION => 'Bearer tok123' } ),
        'bearer env authenticates' );
    is( $seen->scheme,      'Bearer', 'scheme parsed from the Authorization header' );
    is( $seen->credentials, 'tok123', 'credentials are the header tail' );
};

subtest 'verify_api_key disabled when not configured' => sub {
    my $h = SignalWire::Core::AuthHandler->new( FakeSecConfig->new );
    ok( !$h->verify_api_key('anything'), 'api key check false when disabled' );
    my $b = SignalWire::Core::AuthHandler::BearerCredentials->new( 'Bearer', 'x' );
    ok( !$h->verify_bearer_token($b), 'bearer check false when disabled' );
};

subtest 'plack_dependency (aka get_fastapi_dependency)' => sub {
    my $h = SignalWire::Core::AuthHandler->new(
        FakeSecConfig->new( user => 'bob', pass => 'sekret' ) );

    my $dep = $h->plack_dependency;
    is( ref $dep, 'CODE', 'plack_dependency returns a coderef' );

    my $ok = $dep->( basic_env( 'bob', 'sekret' ) );
    is( $ok->{authenticated}, 1,       'authenticated true' );
    is( $ok->{method},        'basic', 'method reported' );

    # required (non-optional) failure dies with AuthError carrying a 401
    eval { $dep->( { HTTP_AUTHORIZATION => '' } ) };
    my $err = $@;
    ok( $err, 'required dependency dies on failure' );
    isa_ok( $err, 'SignalWire::Core::AuthError', 'dies with AuthError' );
    is( $err->response->[0], 401, 'AuthError carries a 401 response' );

    # optional does not die
    my $opt = $h->get_fastapi_dependency( optional => 1 );
    my $res = $opt->( { HTTP_AUTHORIZATION => '' } );
    is( $res->{authenticated}, 0,     'optional -> authenticated false' );
    is( $res->{method},        undef, 'optional -> method undef' );
};

subtest 'plack_middleware (aka flask_decorator)' => sub {
    my $h = SignalWire::Core::AuthHandler->new(
        FakeSecConfig->new( user => 'bob', pass => 'sekret' ) );

    my $app = sub { return [ 200, [ 'Content-Type' => 'text/plain' ], ['ok'] ] };
    my $guarded = $h->flask_decorator($app);
    is( ref $guarded, 'CODE', 'flask_decorator returns a wrapping app' );

    my $pass = $guarded->( basic_env( 'bob', 'sekret' ) );
    is( $pass->[0], 200, 'authenticated request passes through' );

    my $deny = $guarded->( { HTTP_AUTHORIZATION => '' } );
    is( $deny->[0], 401, 'unauthenticated request gets 401' );
    my %hdr = @{ $deny->[1] };
    like( $hdr{'WWW-Authenticate'}, qr/Basic realm/, 'challenge header present' );
};

subtest 'bearer via env in middleware' => sub {
    my $h = SignalWire::Core::AuthHandler->new( FakeSecConfig->new( bearer => 'tok123' ) );
    my $app     = sub { return [ 200, [], ['ok'] ] };
    my $guarded = $h->plack_middleware($app);
    my $res     = $guarded->( { HTTP_AUTHORIZATION => 'Bearer tok123' } );
    is( $res->[0], 200, 'valid bearer token authenticates via middleware' );
};

subtest 'custom api key header' => sub {
    my $h = SignalWire::Core::AuthHandler->new(
        FakeSecConfig->new( api_key => 'k', api_key_header => 'X-Custom-Key' ) );
    my $app     = sub { return [ 200, [], ['ok'] ] };
    my $guarded = $h->plack_middleware($app);
    my $res     = $guarded->( { HTTP_X_CUSTOM_KEY => 'k' } );
    is( $res->[0], 200, 'custom api key header authenticates' );
};

done_testing;
