package SignalWire::REST::HttpClient;
use strict;
use warnings;
use Moo;

use HTTP::Tiny;
use JSON         qw(encode_json decode_json);
use MIME::Base64 qw(encode_base64);
use Scalar::Util qw(blessed);
use Time::HiRes  qw(sleep);

use SignalWire::REST::RequestOptions;

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

has 'project' => ( is => 'ro', required => 1 );
has 'token'   => ( is => 'ro', required => 1 );
has 'host'    => ( is => 'ro', required => 1 );

# The CLIENT-DEFAULT request options (plan 4.2) -- a
# SignalWire::REST::RequestOptions applied to every request, shallow-overridden
# per call by a request_options passed to a verb. undef => the built-in defaults
# (30s timeout, no retries) for every request. Stored here so the whole resource
# tree (which shares this one HttpClient) inherits it.
has 'request_options' => ( is => 'ro', default => sub { undef } );

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

    # Resolve the effective options: per-request over client-default over the
    # built-in defaults (plan 4.2). Every field is concrete after resolve().
    my $ro = SignalWire::REST::RequestOptions::Resolver::resolve( $self->request_options,
        $opts{request_options} );

    # total attempts = retries + 1; retry a retryable status (idempotency-aware)
    # or a transport failure, honoring Retry-After then exponential backoff.
    # abort_signal is checked cooperatively BEFORE every attempt.
    my $attempt = 0;
    while (1) {
        $attempt++;

        # Cooperative cancellation: a set abort_signal raises the typed transport
        # error (no response was produced) before the send. Checked between
        # attempts -- the honest portable minimum for a synchronous client.
        if ( _abort_is_set( $ro->{abort_signal} ) ) {
            die SignalWireRestTransportError->new(
                body   => 'request cancelled by abort_signal',
                url    => $url,
                method => $method,
            );
        }

        # Per-attempt wall-clock timeout: HTTP::Tiny carries the timeout on the
        # object, so scope the resolved timeout onto the shared UA for this send
        # and restore it afterwards (the resource tree shares one UA).
        my $ua       = $self->_ua;
        my $saved_to = $ua->{timeout};
        $ua->{timeout} = $ro->{timeout} if defined $ro->{timeout};
        my $response = $ua->request( $method, $url, \%request_opts );
        $ua->{timeout} = $saved_to;

        if ( $response->{success} ) {

            # 204 No Content or empty body
            if ( $response->{status} == 204 || !$response->{content} ) {
                return {};
            }
            my $result;
            eval { $result = decode_json( $response->{content} ) };
            return { raw => $response->{content} } if $@;
            return $result;
        }

        # --- failure paths (transport vs HTTP >= 400), retry-aware ---

        # Distinguish a TRANSPORT failure (the request never reached the server --
        # connection refused, DNS failure, connection reset, TLS error, read
        # timeout) from a real HTTP >= 400 response. HTTP::Tiny does NOT throw on a
        # transport failure; it SYNTHESISES a response with status 599 / reason
        # "Internal Exception" (599 is reserved by HTTP::Tiny for its own internal
        # exceptions -- no real server sends it). Map that synthetic 599 to the
        # TYPED transport error (SignalWireRestTransportError, status_code => undef),
        # a member of the SignalWireRestError family, so a caller catching
        # SignalWireRestError handles every REST failure (HTTP + transport) with one
        # eval. Python parity: signalwire.rest._base.SignalWireRestTransportError
        # (plan 1.3b).
        if ( _is_transport_failure($response) ) {
            if ( $attempt <= $ro->{retries} ) {
                _backoff_sleep( $ro->{retry_backoff} * ( 2**( $attempt - 1 ) ) );
                next;
            }
            die SignalWireRestTransportError->new(
                body   => $response->{content} // '',
                url    => $url,
                method => $method,
            );
        }

        # A real HTTP-error response. Retry if attempts remain AND the status is
        # retryable for this method (idempotency-aware), honoring Retry-After when
        # present then exponential backoff.
        if (
            $attempt <= $ro->{retries}
            && SignalWire::REST::RequestOptions::Resolver::status_is_retryable(
                $method, $response->{status}, $ro
            )
            )
        {
            my $delay = _retry_after_seconds($response);
            $delay = $ro->{retry_backoff} * ( 2**( $attempt - 1 ) )
                unless defined $delay;
            _backoff_sleep($delay);
            next;
        }

        my $body = $response->{content} // '';
        my $parsed;
        eval { $parsed = decode_json($body) };
        $parsed = $body if $@;
        die SignalWireRestError->new(
            status_code => $response->{status},
            body        => $parsed,
            url         => $url,
            method      => $method,
        );
    }

    # Unreachable: the while(1) loop only exits via a return (success) or a die
    # (transport/HTTP error). Present to satisfy Subroutines::RequireFinalReturn.
    return;
}

# Cooperative-cancellation probe: an abort_signal is any object/coderef answering
# ->is_set (an object's is_set method) or a plain coderef (called). Truthy =>
# cancel. undef => never cancelled.
sub _abort_is_set {
    my ($signal) = @_;
    return 0 unless defined $signal;
    if ( blessed($signal) && $signal->can('is_set') ) {
        return $signal->is_set ? 1 : 0;
    }
    if ( ref $signal eq 'CODE' ) {
        return $signal->() ? 1 : 0;
    }
    return 0;
}

# Backoff sleep between retries. A seam so a retry_backoff of 0 (the corpus /
# tests use it) never waits on wall-clock -- the mock proves attempt ORDERING,
# not real time. Time::HiRes::sleep handles the fractional exponential delays.
sub _backoff_sleep {
    my ($seconds) = @_;
    sleep($seconds) if defined $seconds && $seconds > 0;
    return;
}

# Parse a Retry-After header (delta-seconds form) off a response, or undef when
# absent / an HTTP-date form (fall back to computed backoff). HTTP::Tiny
# lower-cases header keys and gives an arrayref when a header repeats.
sub _retry_after_seconds {
    my ($response) = @_;
    my $headers    = $response->{headers} || {};
    my $value      = $headers->{'retry-after'};
    $value = $value->[0] if ref $value eq 'ARRAY';
    return unless defined $value;
    return ( $value =~ /^\s*\d+(?:\.\d+)?\s*$/ ) ? ( $value + 0 ) : undef;
}

sub get {
    my ( $self, $path, %opts ) = @_;
    return $self->_request(
        'GET', $path,
        params          => $opts{params},
        request_options => $opts{request_options}
    );
}

sub post {
    my ( $self, $path, %opts ) = @_;
    return $self->_request(
        'POST', $path,
        body            => $opts{body},
        params          => $opts{params},
        request_options => $opts{request_options}
    );
}

sub put {
    my ( $self, $path, %opts ) = @_;
    return $self->_request(
        'PUT', $path,
        body            => $opts{body},
        request_options => $opts{request_options}
    );
}

sub patch {
    my ( $self, $path, %opts ) = @_;
    return $self->_request(
        'PATCH', $path,
        body            => $opts{body},
        request_options => $opts{request_options}
    );
}

sub delete_request {
    my ( $self, $path, %opts ) = @_;
    return $self->_request( 'DELETE', $path, request_options => $opts{request_options} );
}

# Detect an HTTP::Tiny TRANSPORT failure vs a real HTTP error response.
#
# On a connection-level failure (connect refused, DNS failure, connection reset,
# TLS handshake error, read timeout) HTTP::Tiny does NOT die; it returns a
# SYNTHETIC response hashref with status => 599 and reason => "Internal Exception"
# (documented behaviour: 599 is reserved by HTTP::Tiny for its own internal
# exceptions, and no real HTTP server issues a 599). That synthetic 599 is the
# ONLY transport signal we treat specially -- a genuine >= 400 from the server
# (400/404/422/429/500/503/...) stays on the normal HTTP-error path and keeps its
# real status_code. Guard on both status 599 AND the "Internal Exception" reason so
# an (impossible-but-defensive) real 599 from a server would not be misclassified.
sub _is_transport_failure {
    my ($response) = @_;
    return 0 unless ref $response eq 'HASH';
    return 0 unless defined $response->{status} && $response->{status} == 599;
    my $reason = $response->{reason} // '';
    return $reason eq 'Internal Exception' ? 1 : 0;
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

    # A TRANSPORT failure carries no HTTP status (status_code is undef): render
    # "failed to reach the server" instead of "returned : ..." (Python parity).
    if ( !defined $self->status_code ) {
        return sprintf( '%s %s failed to reach the server: %s', $self->method, $self->url, $body );
    }
    return sprintf( '%s %s returned %s: %s', $self->method, $self->url, $self->status_code, $body );
};

# Back-compat alias: the error was historically named
# SignalWire::REST::HttpClient::Error. Alias that package's symbol table to
# SignalWireRestError's so the two names are the SAME class — an instance
# ->isa() both, and existing `isa_ok($e, 'SignalWire::REST::HttpClient::Error')`
# checks keep passing without re-blessing.
# --- Typed transport error ---
#
# SignalWireRestTransportError is raised when a REST request never reached a
# response -- a transport-level failure (connection refused, DNS failure,
# connection reset, TLS error). It is a SUBCLASS of SignalWireRestError (an
# instance ->isa('SignalWireRestError')), so a caller catching the base family
# handles both HTTP-error and transport-error failures with one eval, instead of a
# bare HTTP::Tiny synthetic 599 leaking through as if the server had answered. Its
# status_code is undef (there was no HTTP status) and body carries the underlying
# transport message. Python parity: signalwire.rest._base.SignalWireRestTransportError.
package SignalWireRestTransportError;    ## no critic (ProhibitMultiplePackages)
use Moo;
extends 'SignalWireRestError';

# status_code is required on the base but is undef for a transport failure (no HTTP
# status ever arrived). Override to default to undef so callers may omit it.
has '+status_code' => ( is => 'ro', required => 0, default => sub { undef } );

package SignalWire::REST::HttpClient::Error;    ## no critic (ProhibitMultiplePackages)
BEGIN { *SignalWire::REST::HttpClient::Error:: = *SignalWireRestError:: }

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::REST::HttpClient - HTTP transport for the SignalWire REST client

=head1 SYNOPSIS

    use SignalWire::REST::HttpClient;

    my $http = SignalWire::REST::HttpClient->new(
        project => $project_id,
        token   => $api_token,
        host    => $space_host,     # bare host or a full http(s):// URL
    );

    my $data = $http->get('/api/relay/rest/phone_numbers');
    my $new  = $http->post('/api/fabric/resources/ai_agents',
        body => { name => 'Bot' });

    # Errors are raised via die() as typed objects:
    my $result = eval { $http->get('/api/does-not-exist') };
    if ( my $err = $@ ) {
        warn $err->status_code, ': ', $err;   # SignalWireRestError
    }

=head1 DESCRIPTION

L<SignalWire::REST::HttpClient> is the shared HTTP transport underneath
L<SignalWire::REST::RestClient> and the whole generated resource tree. It
wraps L<HTTP::Tiny>, adds Basic authentication from the project/token,
sets the JSON content/accept headers and a version-derived User-Agent,
verifies TLS by default, and applies the L<SignalWire::REST::RequestOptions>
timeout/retry/cancellation policy to every request.

The verb methods build the URL from C<base_url> plus the request path,
encode a hashref C<body> as JSON, append a hashref C<params> as a
query string, decode a JSON response body, and return C<{}> for a 204 /
empty body. Any HTTP status E<gt>= 400 or a transport failure is raised
via C<die> as a member of the typed error family (see L</ERRORS>).

=head1 ATTRIBUTES

=over 4

=item project / token / host

Required. The credentials and space host; C<host> may be a bare hostname
(C<https://> is prepended) or a full C<http(s)://> URL (used verbatim, so
the audit fixture can point at a loopback server).

=item request_options

An optional client-default L<SignalWire::REST::RequestOptions> applied to
every request, shallow-overridden per call. C<undef> means the built-in
defaults (30s timeout, no retries).

=item base_url

Lazily built from C<host>: scheme-normalized and stripped of trailing
slashes so request paths concatenate cleanly.

=back

=head1 METHODS

=over 4

=item get($path, %opts)

Issue a GET. Accepts C<params> (query hashref) and C<request_options>.

=item post($path, %opts)

Issue a POST. Accepts C<body> (JSON-encoded), C<params>, and
C<request_options>.

=item put($path, %opts)

Issue a PUT. Accepts C<body> and C<request_options>.

=item patch($path, %opts)

Issue a PATCH. Accepts C<body> and C<request_options>.

=item delete_request($path, %opts)

Issue a DELETE (named C<delete_request> to avoid the reserved-word clash).
Accepts C<request_options>.

=back

Each verb resolves the effective request options (per-request over
client-default over built-in), retries a retryable status
(idempotency-aware) or a transport failure honoring C<Retry-After> then
exponential backoff, and checks the C<abort_signal> cooperatively before
every attempt.

=head1 ERRORS

The client raises a typed error family (Python parity:
C<signalwire.rest._base>). A caller catching the base class handles every
REST failure -- HTTP and transport -- with one C<eval>.

=over 4

=item SignalWireRestError

The base class and the SDK's canonical typed REST error. Raised via C<die>
on any HTTP response with status E<gt>= 400. Read-only accessors:

=over 4

=item C<status_code> - the HTTP status (e.g. 404, 422, 500).

=item C<body> - the response body, decoded from JSON when possible, else
the raw string.

=item C<url> - the full request URL (scheme, host, path, and query string).

=item C<method> - the HTTP method.

=back

The object stringifies (C<use overload '""'>) to a human-readable
C<< METHOD url returned STATUS: body >> message.

=item SignalWireRestTransportError

A subclass of C<SignalWireRestError> raised when a request never reached a
response -- a transport-level failure (connection refused, DNS failure,
connection reset, TLS error, read timeout, or a set C<abort_signal>).
HTTP::Tiny synthesizes a status-599 "Internal Exception" for these; the
client maps that to this typed error so it does not leak through as if the
server had answered. Its C<status_code> is C<undef> (no HTTP status
arrived) and C<body> carries the underlying transport message; it
stringifies to a C<< ... failed to reach the server: body >> message. An
instance C<< ->isa('SignalWireRestError') >> is true.

=item SignalWire::REST::HttpClient::Error

A back-compat alias: this package's symbol table is aliased to
C<SignalWireRestError>'s, so the two names are the SAME class. Existing
C<< isa_ok($e, 'SignalWire::REST::HttpClient::Error') >> checks keep
passing through the alias.

=back

=head1 SEE ALSO

L<SignalWire::REST::RestClient>, L<SignalWire::REST::RequestOptions>,
L<HTTP::Tiny>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
