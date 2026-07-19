package SignalWire::REST::RequestOptions;
use strict;
use warnings;
use Moo;

# RequestOptions -- the REST request-options envelope (plan 4.2), the Perl mirror
# of signalwire.rest._request_options. A single value object controlling
# per-request transport behavior: timeout, retries (with an idempotency-aware
# retry policy + exponential backoff), and cooperative cancellation. Supplied at
# two levels:
#
#   * Client default: RestClient->new(..., request_options => ...) stored on the
#     HttpClient and applied to every request.
#   * Per-request override: each verb accepts an optional request_options that
#     SHALLOW-overrides the client default for that one call -- an unset (undef)
#     field falls back to the client default, then the built-in default.
#
# The timeout + retry semantics are the reference-pinned, wire-observable
# contract (the mock sees N attempts and honors the backoff ordering).
# abort_signal fidelity is per-port idiom: every port exposes the field; how
# deeply the cancellation cuts is the language's business. Perl's REST client is
# SYNCHRONOUS (HTTP::Tiny), so -- like the Python sync client -- it cannot
# interrupt an in-flight blocking socket read; cancellation is checked
# cooperatively BETWEEN attempts (the honest, portable minimum). The abort_signal
# is any object/coderef answering ->is_set (a coderef is called; an object's
# is_set method is invoked); truthy => the request raises before the send.
#
# All fields are optional; undef means "inherit" -- resolved per-request over
# client-default over the built-in default (see resolve()).

has 'timeout'         => ( is => 'ro', default => sub { undef } );
has 'retries'         => ( is => 'ro', default => sub { undef } );
has 'retry_on_status' => ( is => 'ro', default => sub { undef } );
has 'retry_backoff'   => ( is => 'ro', default => sub { undef } );
has 'abort_signal'    => ( is => 'ro', default => sub { undef } );

# The field set (used by merge()/resolve() so a new field is added in one place).
my @FIELDS = qw(timeout retries retry_on_status retry_backoff abort_signal);

# merge -- return a NEW RequestOptions with any set (defined) field of $override
# applied over $self. This is the per-request-over-client-default shallow merge:
# an unset (undef) field on $override leaves $self's value intact. Returns $self
# unchanged when $override is undef. (Mirrors Python RequestOptions.merge, which
# dataclasses.replace()s the set fields.)
sub merge {
    my ( $self, $override ) = @_;
    return $self unless defined $override;
    my %changes;
    for my $name (@FIELDS) {
        my $value = $override->$name;
        $changes{$name} = $value if defined $value;
    }
    return ref($self)->new( ( map { $_ => $self->$_ } @FIELDS ), %changes );
}

# --- Module free functions (Python parity: the module-level resolve() +
# status_is_retryable() in signalwire.rest._request_options). They live in a
# distinct package with no class so they project onto the reference module's
# free-function surface, not onto the RequestOptions class. ---
package SignalWire::REST::RequestOptions::Resolver;    ## no critic (ProhibitMultiplePackages)
use strict;
use warnings;

# The built-in defaults (the contract floor). undef on a RequestOptions field
# means "inherit"; these are what an unset field resolves to at apply-time.
our $DEFAULT_TIMEOUT         = 30.0;
our $DEFAULT_RETRIES         = 0;
our @DEFAULT_RETRY_ON_STATUS = ( 429, 500, 502, 503, 504 );
our $DEFAULT_RETRY_BACKOFF   = 0.5;

# Methods with no server-side side effect -- safe to retry on any retryable
# status. POST/PATCH are excluded: they may create/mutate, so they retry ONLY on
# a transport error or 429/503 (throttles), never blindly on 500/502/504, to
# avoid duplicate side effects. This asymmetry is part of the pinned contract.
my %IDEMPOTENT_METHODS = map { $_ => 1 } qw(GET PUT DELETE HEAD OPTIONS);

# resolve -- the effective options: per-request over client-default over
# built-in. undef on any field inherits the next level down; the built-in
# defaults are the floor. Returns a plain hashref with every field concrete:
#   { timeout, retries, retry_on_status (hashref set), retry_backoff, abort_signal }.
# (The Python analogue returns an _EffectiveOptions dataclass; Perl's honest
# idiom for that private, no-undef value is a hashref -- an internal detail the
# retry loop reads, not part of the public surface.)
sub resolve {
    my ( $client_default, $per_request ) = @_;
    my $base   = $client_default // SignalWire::REST::RequestOptions->new;
    my $merged = $base->merge($per_request);

    my $ros = $merged->retry_on_status;
    my %status_set =
        defined $ros
        ? ( map { $_ => 1 } @$ros )
        : ( map { $_ => 1 } @DEFAULT_RETRY_ON_STATUS );

    return {
        timeout         => defined $merged->timeout ? $merged->timeout : $DEFAULT_TIMEOUT,
        retries         => defined $merged->retries ? $merged->retries : $DEFAULT_RETRIES,
        retry_on_status => \%status_set,
        retry_backoff   => defined $merged->retry_backoff
        ? $merged->retry_backoff
        : $DEFAULT_RETRY_BACKOFF,
        abort_signal => $merged->abort_signal,
    };
}

# status_is_retryable -- whether an HTTP $status for $method should trigger a
# retry given the resolved $opts (the resolve() hashref). Idempotent methods
# (GET/PUT/DELETE) retry on the full retry_on_status set. Non-idempotent methods
# (POST/PATCH) retry only on 429/503 (the Retry-After-bearing throttles, which
# mean "the request was NOT processed"), never on 500/502/504, to avoid
# replaying a side effect that may have partially applied.
sub status_is_retryable {
    my ( $method, $status, $opts ) = @_;
    return 0 unless $opts->{retry_on_status}{$status};
    return 1 if $IDEMPOTENT_METHODS{ uc $method };
    return ( $status == 429 || $status == 503 ) ? 1 : 0;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::REST::RequestOptions - per-request transport options for the REST client

=head1 SYNOPSIS

    use SignalWire::REST::RequestOptions;

    my $opts = SignalWire::REST::RequestOptions->new(
        timeout       => 10,
        retries       => 3,
        retry_backoff => 0.5,
        abort_signal  => sub { $cancelled },
    );

    # As a client default:
    my $client = SignalWire::REST::RestClient->new(
        ..., request_options => $opts,
    );

    # Or per call, shallow-overriding the client default:
    $client->phone_numbers->list( request_options => $opts );

=head1 DESCRIPTION

L<SignalWire::REST::RequestOptions> is the Perl mirror of
C<signalwire.rest._request_options>. It is a value object controlling
per-request transport behavior: request C<timeout>, C<retries> with an
idempotency-aware retry policy and exponential backoff, and cooperative
cancellation via an C<abort_signal>.

Options apply at two levels: a B<client default> passed to
C<< RestClient->new(request_options => ...) >>, and a B<per-request
override> passed to a verb that shallow-overrides the client default for
that one call. All fields are optional; an unset (C<undef>) field means
"inherit" -- it falls back to the client default, then to the built-in
default.

The timeout and retry semantics are the reference-pinned, wire-observable
contract. C<abort_signal> fidelity is per-port idiom: Perl's REST client is
synchronous (L<HTTP::Tiny>), so -- like the Python sync client -- it cannot
interrupt an in-flight blocking read; cancellation is checked cooperatively
between attempts. The C<abort_signal> is any object answering C<< ->is_set >>
or a plain coderef; a truthy result raises before the send.

=head1 ATTRIBUTES

=over 4

=item timeout

Per-request wall-clock timeout in seconds. Built-in default: 30.

=item retries

Number of retry attempts after the first (total attempts = retries + 1).
Built-in default: 0.

=item retry_on_status

An arrayref of HTTP statuses eligible for retry. Built-in default:
C<[429, 500, 502, 503, 504]>.

=item retry_backoff

The base backoff in seconds; the delay grows exponentially per attempt.
Built-in default: 0.5.

=item abort_signal

A cooperative cancellation signal (an object with C<is_set>, or a coderef).
Checked before every attempt; truthy raises a transport error.

=back

=head1 METHODS

=over 4

=item merge($override)

Return a NEW C<RequestOptions> with each defined field of C<$override>
applied over C<$self> (an unset field on C<$override> leaves C<$self>'s
value intact). Returns C<$self> unchanged when C<$override> is C<undef>.

=back

=head1 THE RESOLVER

Module-level free functions live in
C<SignalWire::REST::RequestOptions::Resolver> (Python parity: the
module-level C<resolve> / C<status_is_retryable> in
C<signalwire.rest._request_options>), kept in a distinct package so they
project onto the reference's module-free-function surface rather than the
C<RequestOptions> class.

=over 4

=item SignalWire::REST::RequestOptions::Resolver::resolve($client_default, $per_request)

Return a plain hashref of the effective options -- per-request over
client-default over the built-in defaults -- with every field concrete
(C<timeout>, C<retries>, C<retry_on_status> as a set hashref,
C<retry_backoff>, C<abort_signal>). The retry loop in
L<SignalWire::REST::HttpClient> reads this hashref.

=item SignalWire::REST::RequestOptions::Resolver::status_is_retryable($method, $status, $opts)

Return whether an HTTP C<$status> for C<$method> should trigger a retry
given the resolved C<$opts>. Idempotent methods (GET/PUT/DELETE/HEAD/
OPTIONS) retry on the full C<retry_on_status> set; non-idempotent methods
(POST/PATCH) retry only on 429/503 (the Retry-After-bearing throttles),
never on 500/502/504, to avoid replaying a side effect.

=back

=head1 SEE ALSO

L<SignalWire::REST::HttpClient>, L<SignalWire::REST::RestClient>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
