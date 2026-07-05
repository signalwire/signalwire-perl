package SignalWire::Security::WebhookMiddleware;

# Plack middleware that gates inbound webhook requests on a valid
# X-SignalWire-Signature (or legacy X-Twilio-Signature) header.
#
# Copyright (c) 2025 SignalWire. Licensed under the MIT License.
#
# Behavior:
#   1. If $signing_key is empty / undef, the middleware is a passthrough.
#      (AgentBase warns at startup when this happens.)
#   2. Reads the entire body from psgi.input, caches it on the env under
#      ``signalwire.raw_body``, and rewinds psgi.input so downstream
#      handlers can re-read.
#   3. Reconstructs the public URL using:
#        - X-Forwarded-Proto / X-Forwarded-Host (when trust_proxy is on)
#        - SWML_PROXY_URL_BASE env var (if set)
#        - falls back to ``psgi.url_scheme://HTTP_HOST + REQUEST_URI``
#   4. Calls validate_webhook_signature; on failure returns
#      ``[403, [], []]`` and never invokes the wrapped app.
#
# Usage (PSGI):
#
#   use Plack::Builder;
#   use SignalWire::Security::WebhookMiddleware;
#
#   builder {
#       enable sub {
#           SignalWire::Security::WebhookMiddleware->wrap(
#               app         => $_[0],
#               signing_key => $ENV{SIGNALWIRE_SIGNING_KEY},
#               trust_proxy => 1,
#           );
#       };
#       $app;
#   };
#
# Or directly:
#
#   my $wrapped = SignalWire::Security::WebhookMiddleware->wrap(
#       app         => $app,
#       signing_key => $key,
#       paths       => [ '/swaig', '/post_prompt', '/' ],   # optional whitelist
#       methods     => [ 'POST' ],                           # default POST only
#   );

use strict;
use warnings;

use Carp                                   qw(croak);
use SignalWire::Security::WebhookValidator qw(validate_webhook_signature);

# Header names the decomposed ``validate`` core consults, lower-cased for a
# case-insensitive lookup. ``X-SignalWire-Signature`` is present on every
# signed request; ``X-Twilio-Signature`` is honored as a legacy cXML alias.
my $SIGNALWIRE_SIGNATURE_HEADER    = 'x-signalwire-signature';
my $TWILIO_COMPAT_SIGNATURE_HEADER = 'x-twilio-signature';

# ``validate`` — the framework-free webhook-validation decision core.
#
#   validate($method, $url, \%headers, $body, signing_key => $key)
#       -> undef             (signature valid; let the handler run)
#       -> [403, {}, '']     (missing/bad signature; short-circuit)
#
# This is the SAME decomposed shape every port ships (dotnet
# ``WebhookValidationMiddleware.Validate``, python
# ``webhook_middleware.validate``, a Rack/PSGI middleware response): a request
# reduced to language-neutral primitives, returning either a 403-shaped
# reject triple or ``undef`` to pass. In PSGI a ``[status, headers, body]``
# arrayref literally IS a response, so the reject triple is returned as-is
# and can be handed straight back from a Plack handler; the ``wrap`` Plack
# middleware below is the only framework idiom layered on top of this core.
#
# ``$headers`` is a hashref looked up case-insensitively for the signature
# header (``X-SignalWire-Signature`` or the ``X-Twilio-Signature`` alias).
# ``$method`` is accepted for cross-port signature parity but is not part of
# the HMAC. The signing key is passed as a trailing named argument
# (``signing_key => $key``) mirroring the reference's keyword-only parameter.
#
# On any failure (missing or bad signature, validator error) it returns
# ``[403, {}, '']`` with no body detail, so which branch tripped is not
# leaked. An empty ``signing_key`` is a programming error and croaks.
sub validate {
    my ( $method, $url, $headers, $body, %opts ) = @_;
    my $signing_key = $opts{signing_key};
    croak "signing_key is required"
        unless defined $signing_key && length $signing_key;

    $headers = {} unless ref($headers) eq 'HASH';
    $body    = '' unless defined $body;

    # Case-insensitive header lookup: prefer X-SignalWire-Signature, fall
    # back to the legacy X-Twilio-Signature alias for cXML compat.
    my %lc_headers;
    for my $k ( keys %$headers ) {
        $lc_headers{ lc $k } = $headers->{$k};
    }
    my $signature = $lc_headers{$SIGNALWIRE_SIGNATURE_HEADER};
    $signature = $lc_headers{$TWILIO_COMPAT_SIGNATURE_HEADER}
        unless defined $signature;

    return [ 403, {}, '' ] unless defined $signature && length $signature;

    my $ok = eval { validate_webhook_signature( $signing_key, $signature, $url, $body ); };
    return [ 403, {}, '' ] if $@ || !$ok;

    return undef;    ## no critic (Subroutines::ProhibitExplicitReturnUndef)
}

# ``wrap`` returns a PSGI app that performs validation and forwards
# successful requests to the wrapped ``app``. Options:
#
#   app         => $psgi_app           (required)
#   signing_key => $string              (optional; if empty -> passthrough)
#   paths       => arrayref of paths    (optional; if set, only those paths
#                                        are gated -- others passthrough)
#   methods     => arrayref of methods  (default ['POST'])
#   trust_proxy => 0|1                  (default 1)
#   public_url_base => string           (overrides everything; usually for
#                                        tests)
sub wrap {
    my ( $class, %opts ) = @_;
    my $app = $opts{app} or croak "wrap: 'app' is required";
    croak "wrap: 'app' must be a CODE ref" unless ref($app) eq 'CODE';

    my $signing_key     = $opts{signing_key};
    my $paths           = $opts{paths};                                         # arrayref or undef
    my $methods         = $opts{methods} || ['POST'];
    my $trust_proxy     = exists $opts{trust_proxy} ? $opts{trust_proxy} : 1;
    my $public_url_base = $opts{public_url_base};

    my %method_set = map { uc($_) => 1 } @$methods;
    my %path_set;
    %path_set = map { $_ => 1 } @$paths if $paths;

    # If no signing key, this middleware is a no-op. (AgentBase emits the
    # warning at startup; we don't double-log here.)
    if ( !defined $signing_key || $signing_key eq '' ) {
        return $app;
    }

    return sub {
        my $env = shift;

        # Method gating: only validate POST (or whichever methods caller asked).
        my $method = uc( $env->{REQUEST_METHOD} || 'GET' );
        if ( !$method_set{$method} ) {
            return $app->($env);
        }

        # Path gating: if a whitelist was configured, only those paths
        # require a signature; everything else passes through.
        my $path = $env->{PATH_INFO} || '/';
        if ( %path_set && !$path_set{$path} ) {
            return $app->($env);
        }

        # Slurp the body and stash it on the env so downstream handlers
        # don't have to read it again.
        my $raw_body = _slurp_body($env);
        $env->{'signalwire.raw_body'} = $raw_body;

        my $url = _reconstruct_url( $env, $trust_proxy, $public_url_base );

        # Delegate the signature decision to the decomposed ``validate``
        # core: header lookup (X-SignalWire-Signature / X-Twilio-Signature
        # alias) + validate_webhook_signature, returning a reject triple or
        # undef. The wrapper is just the Plack idiom on top of that core.
        my %headers = (
            (
                defined $env->{HTTP_X_SIGNALWIRE_SIGNATURE}
                ? ( 'X-SignalWire-Signature' => $env->{HTTP_X_SIGNALWIRE_SIGNATURE} )
                : ()
            ),
            (
                defined $env->{HTTP_X_TWILIO_SIGNATURE}
                ? ( 'X-Twilio-Signature' => $env->{HTTP_X_TWILIO_SIGNATURE} )
                : ()
            ),
        );

        my $reject = validate( $method, $url, \%headers, $raw_body, signing_key => $signing_key );
        if ($reject) {
            return [ 403, [ 'Content-Type' => 'text/plain' ], ['Forbidden'] ];
        }

        return $app->($env);
    };
}

# Read all of psgi.input, then rewind so downstream handlers can re-read.
# Returns '' when there's no input or it's already empty.
sub _slurp_body {
    my ($env) = @_;
    my $input = $env->{'psgi.input'};
    return '' unless $input;

    my $body = '';
    my $buf;

    # Limit to CONTENT_LENGTH if present so we don't hang on a streaming
    # source, but still allow chunked / unknown-length when not.
    my $cl = $env->{CONTENT_LENGTH};
    if ( defined $cl && $cl =~ /\A\d+\z/ ) {
        my $remaining = $cl;
        while ( $remaining > 0 ) {
            my $chunk = $remaining > 8192 ? 8192 : $remaining;
            my $n     = $input->read( $buf, $chunk );
            last unless defined $n && $n > 0;
            $body .= $buf;
            $remaining -= $n;
        }
    } else {
        while ( my $n = $input->read( $buf, 8192 ) ) {
            $body .= $buf;
        }
    }

    # Rewind so downstream code can re-read. If seek isn't supported,
    # swap in a string-handle pointing at the buffered body.
    if ( $input->can('seek') ) {
        eval { $input->seek( 0, 0 ) };
    }
    if ( $@ || !$input->can('seek') ) {

        # In-memory handle is deliberately handed off as psgi.input for
        # downstream re-reads; it must NOT be closed here (see RequireBriefOpen
        # exemption rationale in .perlcriticrc).
        open my $fh, '<', \$body;
        $env->{'psgi.input'}   = $fh;
        $env->{CONTENT_LENGTH} = length($body);
    } elsif ( !defined $cl ) {
        $env->{CONTENT_LENGTH} = length($body);
    }

    return $body;
}

# Reconstruct the full public URL SignalWire actually POSTed to.
sub _reconstruct_url {
    my ( $env, $trust_proxy, $public_url_base ) = @_;

    # 1) Explicit override (caller / config / tests).
    if ( defined $public_url_base && $public_url_base ne '' ) {
        return _join_base_path( $public_url_base, $env );
    }

    # 2) SWML_PROXY_URL_BASE env var (per spec).
    if ( defined $ENV{SWML_PROXY_URL_BASE} && $ENV{SWML_PROXY_URL_BASE} ne '' ) {
        return _join_base_path( $ENV{SWML_PROXY_URL_BASE}, $env );
    }

    # 3) X-Forwarded-* headers when trust_proxy is on.
    my ( $scheme, $host );
    if ($trust_proxy) {
        my $xfp = $env->{HTTP_X_FORWARDED_PROTO};
        my $xfh = $env->{HTTP_X_FORWARDED_HOST};
        if ( $xfp && $xfh ) {
            ( $scheme, $host ) = ( $xfp, $xfh );
        }
    }

    # 4) Fallback to raw request fields.
    $scheme //= $env->{'psgi.url_scheme'} // 'http';
    $host   //= $env->{HTTP_HOST}
        // ( ( $env->{SERVER_NAME} // 'localhost' ) . ':' . ( $env->{SERVER_PORT} // '80' ) );

    my $req_uri =
        defined $env->{REQUEST_URI} && $env->{REQUEST_URI} ne '' ? $env->{REQUEST_URI}
        : (
        ( $env->{PATH_INFO} // '/' )
        . (
            defined $env->{QUERY_STRING} && $env->{QUERY_STRING} ne '' ? '?' . $env->{QUERY_STRING}
            : ''
        )
        );

    return "$scheme://$host$req_uri";
}

# Join an external base ("https://foo.ngrok.io") with the path+query
# from the request env.
sub _join_base_path {
    my ( $base, $env ) = @_;
    $base =~ s{/+\z}{};
    my $req_uri =
        defined $env->{REQUEST_URI} && $env->{REQUEST_URI} ne '' ? $env->{REQUEST_URI}
        : (
        ( $env->{PATH_INFO} // '/' )
        . (
            defined $env->{QUERY_STRING} && $env->{QUERY_STRING} ne '' ? '?' . $env->{QUERY_STRING}
            : ''
        )
        );
    return $base . $req_uri;
}

1;

__END__

=head1 NAME

SignalWire::Security::WebhookMiddleware - Plack middleware enforcing
SignalWire webhook signatures

=head1 SYNOPSIS

    use SignalWire::Security::WebhookMiddleware;

    my $wrapped = SignalWire::Security::WebhookMiddleware->wrap(
        app         => $psgi_app,
        signing_key => $ENV{SIGNALWIRE_SIGNING_KEY},
        paths       => [ '/', '/swaig', '/post_prompt' ],
        trust_proxy => 1,
    );

=head1 DESCRIPTION

Wraps a PSGI app so that incoming POST requests must carry a valid
C<X-SignalWire-Signature> header (or the legacy C<X-Twilio-Signature>)
matching the configured signing key. Invalid or missing signatures
produce a 403 without ever invoking the wrapped app.

The raw body is captured before validation and stashed on the env as
C<signalwire.raw_body>; C<psgi.input> is rewound (or replaced with a
buffer) so downstream handlers can re-read.

=head1 OPTIONS

=over

=item app

PSGI coderef. Required.

=item signing_key

The customer's Signing Key from the SignalWire Dashboard. If empty,
the middleware is a passthrough (AgentBase logs a startup warning in
that case).

=item paths

Optional arrayref of paths to gate. When set, only those paths require
a signature; other paths pass through unchecked.

=item methods

Arrayref of HTTP methods to gate. Defaults to C<['POST']>.

=item trust_proxy

Honor C<X-Forwarded-Proto> / C<X-Forwarded-Host> when reconstructing
the public URL. Default true.

=item public_url_base

Hard-override the URL base (e.g. for tests). Takes precedence over
everything else.

=back

=cut
