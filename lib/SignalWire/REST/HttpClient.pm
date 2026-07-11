package SignalWire::REST::HttpClient;
use strict;
use warnings;
use Moo;

use HTTP::Tiny;
use JSON         qw(encode_json decode_json);
use MIME::Base64 qw(encode_base64);

# Derive the outbound User-Agent from the distribution $VERSION -- the single
# source of truth in lib/SignalWire.pm (also what Makefile.PL's VERSION_FROM
# reads) -- so it can never go stale against the released version. We resolve
# the version WITHOUT loading the full SignalWire framework tree: if the top
# module is already loaded we read its $VERSION, otherwise we parse it from the
# on-disk module file (the same way ExtUtils::MakeMaker's VERSION_FROM does),
# and fall back to '0' if neither is available.
sub _sdk_version {
    return $SignalWire::VERSION if defined $SignalWire::VERSION;
    ( my $rel = 'SignalWire.pm' ) =~ s{::}{/}g;
    for my $dir (@INC) {
        next if ref $dir;
        my $file = "$dir/$rel";
        next unless -f $file;
        require ExtUtils::MakeMaker;
        my $v = eval { MM->parse_version($file) };
        return $v if defined $v && $v ne 'undef';
    }
    return '0';
}

my $USER_AGENT = 'signalwire-perl/' . _sdk_version();

has 'project'      => ( is => 'ro', required => 1 );
has 'token'        => ( is => 'ro', required => 1 );
has 'host'         => ( is => 'ro', required => 1 );
has 'base_url'     => ( is => 'lazy' );
has '_ua'          => ( is => 'lazy' );
has '_auth_header' => ( is => 'lazy' );

sub _build_base_url {
    my ($self) = @_;
    my $host = $self->host;

    # Allow callers to pass a fully-qualified URL (used by the audit
    # fixture, which serves http://127.0.0.1:NNN). When the value
    # already carries a scheme we use it verbatim; otherwise we
    # prepend the production https://. Strip trailing slashes either
    # way so request paths concatenate cleanly.
    my $base;
    if ( $host =~ m{^https?://} ) {
        $base = $host;
    } else {
        $base = 'https://' . $host;
    }
    $base =~ s{/+$}{};
    return $base;
}

sub _build__ua {
    my ($self) = @_;
    return HTTP::Tiny->new(
        agent           => $USER_AGENT,
        default_headers => {
            'Content-Type'  => 'application/json',
            'Accept'        => 'application/json',
            'Authorization' => $self->_auth_header,
        },
        timeout => 30,

        # Verify TLS certificates by default, matching the Python reference
        # (requests/httpx verify by default). HTTP::Tiny otherwise defaults
        # verify_SSL => 0, which would silently accept any cert — a security
        # divergence from Python. Verification honors SSL_CERT_FILE / the OS
        # trust store; plaintext http:// requests are unaffected.
        verify_SSL => 1,
    );
}

sub _build__auth_header {
    my ($self) = @_;
    my $credentials = $self->project . ':' . $self->token;
    return 'Basic ' . encode_base64( $credentials, '' );
}

sub _request {
    my ( $self, $method, $path, %opts ) = @_;
    my $url = $self->base_url . $path;

    # Add query params to URL
    if ( $opts{params} && ref $opts{params} eq 'HASH' && %{ $opts{params} } ) {
        my @pairs;
        for my $key ( sort keys %{ $opts{params} } ) {
            my $val = $opts{params}{$key} // '';
            push @pairs, _uri_encode($key) . '=' . _uri_encode($val);
        }
        $url .= '?' . join( '&', @pairs );
    }

    my %request_opts;
    if ( $opts{body} ) {
        $request_opts{content} = encode_json( $opts{body} );
    }

    my $response = $self->_ua->request( $method, $url, \%request_opts );

    unless ( $response->{success} ) {
        my $body = $response->{content} // '';
        my $parsed;
        eval { $parsed = decode_json($body) };
        $parsed = $body if $@;
        die SignalWireRestError->new(
            status_code => $response->{status},
            body        => $parsed,
            url         => $path,
            method      => $method,
        );
    }

    # 204 No Content or empty body
    if ( $response->{status} == 204 || !$response->{content} ) {
        return {};
    }

    my $result;
    eval { $result = decode_json( $response->{content} ) };
    if ($@) {
        return { raw => $response->{content} };
    }
    return $result;
}

sub get {
    my ( $self, $path, %opts ) = @_;
    return $self->_request( 'GET', $path, params => $opts{params} );
}

sub post {
    my ( $self, $path, %opts ) = @_;
    return $self->_request( 'POST', $path, body => $opts{body}, params => $opts{params} );
}

sub put {
    my ( $self, $path, %opts ) = @_;
    return $self->_request( 'PUT', $path, body => $opts{body} );
}

sub patch {
    my ( $self, $path, %opts ) = @_;
    return $self->_request( 'PATCH', $path, body => $opts{body} );
}

sub delete_request {
    my ( $self, $path ) = @_;
    return $self->_request( 'DELETE', $path );
}

# Simple URI encoding
sub _uri_encode {
    my ($str) = @_;
    $str =~ s/([^A-Za-z0-9\-_.~])/sprintf("%%%02X", ord($1))/ge;
    return $str;
}

# --- Error class ---
#
# SignalWireRestError is the SDK's canonical typed REST error (Python parity:
# signalwire.rest._base.SignalWireRestError). It carries the full failure
# envelope — status_code, body, url, method — and is raised via `die` on any
# HTTP >= 400 response, so a caller can branch on the status/body instead of
# parsing a stringified message. SignalWire::REST::HttpClient::Error is retained
# as a subclass alias for back-compat (existing isa_ok checks against the old
# name keep passing through inheritance).
package SignalWireRestError;
use Moo;
use JSON qw(encode_json);

has 'status_code' => ( is => 'ro', required => 1 );
has 'body'        => ( is => 'ro', default  => sub { '' } );
has 'url'         => ( is => 'ro', default  => sub { '' } );
has 'method'      => ( is => 'ro', default  => sub { 'GET' } );

use overload '""' => sub {
    my ($self) = @_;
    my $body = ref $self->body ? encode_json( $self->body ) : ( $self->body // '' );
    return sprintf( '%s %s returned %s: %s', $self->method, $self->url, $self->status_code, $body );
};

# Back-compat alias: the error was historically named
# SignalWire::REST::HttpClient::Error. Alias that package's symbol table to
# SignalWireRestError's so the two names are the SAME class — an instance
# ->isa() both, and existing `isa_ok($e, 'SignalWire::REST::HttpClient::Error')`
# checks keep passing without re-blessing.
package SignalWire::REST::HttpClient::Error;    ## no critic (ProhibitMultiplePackages)
BEGIN { *SignalWire::REST::HttpClient::Error:: = *SignalWireRestError:: }

1;
