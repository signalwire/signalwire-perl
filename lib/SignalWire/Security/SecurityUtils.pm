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
