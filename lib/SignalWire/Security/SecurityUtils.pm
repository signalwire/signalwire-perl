package SignalWire::Security::SecurityUtils;

# Standalone security hygiene utilities.
#
# Copyright (c) 2025 SignalWire. Licensed under the MIT License.
# See LICENSE file in the project root for full license information.
#
# Mirror of the Python reference
# signalwire.core.security.security_utils (itself a mirror of the
# TypeScript SDK's SecurityUtils): keep credentials out of user callbacks
# and logs, and provide a reusable hostname character-level check.
#
# Public API (module-level free functions; the enumerate_surface.pl
# adapter maps this package with class=undef so each sub projects onto a
# Python module-level function under signalwire.core.security.security_utils):
#
#     filter_sensitive_headers($headers) -> hashref
#     redact_url($url)                    -> string (or input unchanged)
#     is_valid_hostname($host)            -> 0|1

use strict;
use warnings;

use Scalar::Util qw(reftype);

use Exporter qw(import);
our @EXPORT_OK = qw(filter_sensitive_headers redact_url is_valid_hostname);

# Header names whose values are credentials/secrets and must never be handed
# to user callbacks or written to logs. Compared case-insensitively.
my %SENSITIVE_HEADERS = map { $_ => 1 } qw(
    authorization
    cookie
    x-api-key
    proxy-authorization
    set-cookie
);

# Return a copy of $headers (a hashref) with sensitive (credential-bearing)
# headers removed, so request headers can be safely passed to user callbacks.
# Keys are preserved as given; the sensitivity check is case-insensitive.
# Empty / undef input yields an empty hashref.
sub filter_sensitive_headers {
    my ($headers) = @_;
    return {} unless $headers && ( reftype($headers) // '' ) eq 'HASH';
    my %filtered;
    foreach my $key ( keys %{$headers} ) {
        next if $SENSITIVE_HEADERS{ lc $key };
        $filtered{$key} = $headers->{$key};
    }
    return \%filtered;
}

# Mask the password in a URL's userinfo before logging:
#   https://user:secret@host/path -> https://user:****@host/path
# A URL with no embedded credentials is returned unchanged. Non-string
# (reference) input is returned as-is.
sub redact_url {
    my ($url) = @_;
    return $url if !defined $url || ref $url;
    $url =~ s{://([^:@/]+):([^@/]+)@}{://$1:****@}g;
    return $url;
}

# Standalone hostname sanity check: reject empty hosts and any host
# containing whitespace, slashes, backslashes, or control characters. This is
# the reusable character-level check, independent of the fuller
# SignalWire::Utils::UrlValidator::validate_url (scheme checks, DNS
# resolution, private-IP blocking).
sub is_valid_hostname {
    my ($host) = @_;
    return 0 if !defined $host || $host eq '';
    return 0 if $host =~ m{[\s/\\\x00-\x1f\x7f]};
    return 1;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Security::SecurityUtils - credential-hygiene and hostname-check utilities

=head1 SYNOPSIS

    use SignalWire::Security::SecurityUtils qw(
        filter_sensitive_headers redact_url is_valid_hostname
    );

    my $safe_headers = filter_sensitive_headers($request_headers);
    my $safe_url     = redact_url('https://user:secret@host/path');
    #   -> 'https://user:****@host/path'
    my $ok           = is_valid_hostname('example.com');   # 1

=head1 DESCRIPTION

L<SignalWire::Security::SecurityUtils> is the Perl port of
C<signalwire.core.security.security_utils> (itself a mirror of the
TypeScript SDK's SecurityUtils). It keeps credentials out of user
callbacks and logs and provides a reusable character-level hostname
check. All three subs are exportable via C<@EXPORT_OK>.

=head1 FUNCTIONS

=over 4

=item C<filter_sensitive_headers($headers)>

Return a copy of the C<$headers> hashref with credential-bearing headers
(C<authorization>, C<cookie>, C<x-api-key>, C<proxy-authorization>,
C<set-cookie>) removed. The sensitivity check is case-insensitive; keys
are otherwise preserved as given. Empty or non-hashref input yields an
empty hashref.

=item C<redact_url($url)>

Mask the password in a URL's userinfo before logging, e.g.
C<< https://user:secret@host >> becomes C<< https://user:****@host >>. A
URL with no embedded credentials, or non-string input, is returned
unchanged.

=item C<is_valid_hostname($host)>

Standalone hostname sanity check: return C<0> for an empty host or one
containing whitespace, slashes, backslashes, or control characters;
C<1> otherwise. This is the character-level check only, independent of
the fuller C<validate_url> (scheme / DNS / private-IP checks).

=back

=head1 SEE ALSO

L<SignalWire::Utils::UrlValidator> for full URL / SSRF validation.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
