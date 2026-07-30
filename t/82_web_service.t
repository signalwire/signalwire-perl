#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp   qw(tempdir);
use File::Spec   ();
use MIME::Base64 qw(encode_base64);

# Real-behavior tests for SignalWire::Web::WebService (parity with Python's
# signalwire.web.web_service.WebService, mirroring Ruby's
# tests/web_web_service_test.rb). The service actually binds an HTTP server
# on an ephemeral port and serves real files; each server is stopped so
# nothing hangs.

BEGIN {
    unless ( eval { require HTTP::Server::PSGI; 1 } ) {
        plan skip_all => 'HTTP::Server::PSGI (Plack) not available';
    }
    unless ( eval { require HTTP::Tiny; 1 } ) {
        plan skip_all => 'HTTP::Tiny not available';
    }
}

use_ok('SignalWire::Web::WebService');

my $USER = 'webuser';
my $PASS = 'webpass';

# ---- fixture directory ----
my $dir = tempdir( CLEANUP => 1 );
_write( 'hello.txt', 'hello world' );
_write( 'page.html', '<h1>hi</h1>' );
_write( '.env',      'SECRET=1' );

sub _write {
    my ( $name, $content ) = @_;
    open my $fh, '>', File::Spec->catfile( $dir, $name ) or die $!;
    print {$fh} $content;
    close $fh;
    return;
}

# ---- non-network unit-ish assertions (no server needed) ----

subtest 'add_directory validates and stores' => sub {
    my $svc = SignalWire::Web::WebService->new;
    my $ret = $svc->add_directory( 'static', $dir );
    is( $ret, $svc, 'add_directory returns self' );
    ok( exists $svc->directories->{'/static'}, 'route normalised with leading slash' );

    eval { $svc->add_directory( '/missing', '/no/such/dir/xyz' ); 1 };
    like( $@, qr/Directory does not exist/, 'missing dir dies' );
};

subtest 'remove_directory drops the route' => sub {
    my $svc = SignalWire::Web::WebService->new;
    $svc->add_directory( '/static', $dir );
    $svc->remove_directory('/static');
    ok( !exists $svc->directories->{'/static'}, 'route removed' );
};

subtest 'file_allowed predicate' => sub {
    my $svc = SignalWire::Web::WebService->new;
    ok( $svc->file_allowed( File::Spec->catfile( $dir,  'hello.txt' ) ), 'plain file allowed' );
    ok( !$svc->file_allowed( File::Spec->catfile( $dir, '.env' ) ), 'blocked .env not allowed' );
};

# ---- real HTTP server tests ----

my $svc = SignalWire::Web::WebService->new( basic_auth => [ $USER, $PASS ] );
$svc->add_directory( '/static', $dir );
my $port = $svc->start( host => '127.0.0.1', port => 0 );

subtest 'start returns bound ephemeral port' => sub {
    cmp_ok( $port, '>', 0, 'a real port was bound' );
};

my $http = HTTP::Tiny->new( timeout => 5 );

sub _get {
    my ( $path, %opts ) = @_;
    my %headers;
    unless ( $opts{no_auth} ) {
        my $creds = ( $opts{user} // $USER ) . ':' . ( $opts{pass} // $PASS );
        chomp( my $b64 = encode_base64($creds) );
        $headers{Authorization} = "Basic $b64";
    }
    return $http->get( "http://127.0.0.1:$port$path", { headers => \%headers } );
}

subtest 'serves real file contents' => sub {
    my $res = _get('/static/hello.txt');
    is( $res->{status},  200,           'HTTP 200' );
    is( $res->{content}, 'hello world', 'file body served' );
};

subtest 'serves html with security headers' => sub {
    my $res = _get('/static/page.html');
    is( $res->{status}, 200, 'HTTP 200' );
    like( $res->{content}, qr{<h1>hi</h1>}, 'html body served' );
    is( $res->{headers}{'x-content-type-options'}, 'nosniff',              'nosniff header' );
    is( $res->{headers}{'cache-control'},          'public, max-age=3600', 'cache-control header' );
};

subtest 'missing file is not found' => sub {
    my $res = _get('/static/does-not-exist.txt');
    is( $res->{status}, 404, 'HTTP 404' );
};

subtest 'blocked extension is forbidden' => sub {
    my $res = _get('/static/.env');
    is( $res->{status}, 403, 'HTTP 403 for .env' );
};

subtest 'requires auth' => sub {
    my $res = _get( '/static/hello.txt', no_auth => 1 );
    is( $res->{status}, 401, 'HTTP 401 without credentials' );
};

subtest 'wrong auth rejected' => sub {
    my $res = _get( '/static/hello.txt', pass => 'wrongpass' );
    is( $res->{status}, 401, 'HTTP 401 with wrong password' );
};

subtest 'auth-scheme token is matched case-insensitively (RFC 7235)' => sub {

    # The reference guards this route with FastAPI's HTTPBasic, which compares
    # ``scheme.lower() != "basic"``. A client sending the legal lowercase form
    # authenticates there and must authenticate here.
    chomp( my $b64 = encode_base64("$USER:$PASS") );
    for my $scheme ( 'Basic', 'basic', 'BASIC', 'BaSiC' ) {
        my $res = $http->get(
            "http://127.0.0.1:$port/static/hello.txt",
            { headers => { Authorization => "$scheme $b64" } }
        );
        is( $res->{status}, 200, "authenticated with scheme '$scheme'" );
    }

    # ...and the scheme check is still a real check.
    for my $bad ( 'Digest', 'Bearer', 'Basicx', 'Negotiate' ) {
        my $res = $http->get(
            "http://127.0.0.1:$port/static/hello.txt",
            { headers => { Authorization => "$bad $b64" } }
        );
        is( $res->{status}, 401, "scheme '$bad' rejected" );
    }
};

subtest 'path traversal denied' => sub {
    my $res = _get('/static/../../etc/passwd');
    ok( ( grep { $_ == $res->{status} } ( 403, 404, 400 ) ), 'traversal blocked (403/404/400)' );
    unlike( $res->{content} // '', qr/root:/, 'no /etc/passwd contents leaked' );
};

$svc->stop;
pass('server stopped cleanly');

done_testing;
