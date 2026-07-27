package SignalWire::Core::Random;

# Copyright (c) 2025 SignalWire
#
# This file is part of the SignalWire SDK.
#
# Licensed under the MIT License.
# See LICENSE file in the project root for full license information.
#
# The SDK's single cryptographically-secure entropy source.

use strict;
use warnings;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
use Crypt::URandom ();
use MIME::Base64   ();

# The SDK's single entropy source.
#
# Every cryptographically-relevant random value in this port — session HMAC
# keys, SWAIG `__token` material, auto-generated basic-auth credentials, RELAY
# control ids, UUIDs — comes from here and nowhere else. Two properties this
# module exists to guarantee:
#
#   1. PORTABILITY. The previous implementation read `/dev/urandom` directly at
#      eight call sites. Windows has no such device, so every one of those sites
#      failed (or silently degraded) on Windows — this is the SDK's CSPRNG, so
#      that broke every Windows user, not just CI. Crypt::URandom dispatches to
#      the platform primitive: getrandom(2)/`/dev/urandom` on Unix,
#      CryptGenRandom/RtlGenRandom via Win32::API on Win32.
#
#   2. NO SILENT DOWNGRADE. There is deliberately no fallback path — not to
#      `rand()`, not to time-seeded material, not to an environment variable.
#      A weak entropy source in a security primitive is worse than a loud
#      failure, because the failure is invisible in the output: `rand()`-derived
#      tokens look exactly like CSPRNG-derived ones. If the platform CSPRNG is
#      unavailable, we die.
#
# All subs are underscore-private: this module is SDK-internal plumbing with no
# counterpart in the Python reference (which calls `secrets`/`os.urandom`
# directly), so it deliberately emits zero public surface.

# Raw CSPRNG bytes. Dies unless it can return exactly $n bytes.
sub _random_bytes ($n) {
    die "SignalWire::Core::Random: byte count must be a positive integer (got "
        . ( defined $n ? "'$n'" : 'undef' ) . ")\n"
        unless defined $n && $n =~ /\A[0-9]+\z/ && $n > 0;

    my $bytes = eval { Crypt::URandom::urandom($n) };
    my $err   = $@;

    die "FATAL: SignalWire::Core::Random: the platform CSPRNG is unavailable "
        . "($err). This SDK will not fall back to a weaker source of randomness "
        . "for security material.\n"
        if !defined $bytes && $err;

    die "FATAL: SignalWire::Core::Random: the platform CSPRNG returned "
        . ( defined $bytes ? length($bytes) : 'no' )
        . " bytes, expected $n. Refusing to proceed with short entropy.\n"
        unless defined $bytes && length($bytes) == $n;

    return $bytes;
}

# Lowercase hex expansion of $n CSPRNG bytes (returns 2*$n characters).
sub _random_hex ($n) {
    return unpack 'H*', _random_bytes($n);
}

# URL-safe base64 of $n CSPRNG bytes, unpadded (mirrors Python's
# secrets.token_urlsafe).
sub _random_urlsafe ($n) {
    my $b64 = MIME::Base64::encode_base64( _random_bytes($n), '' );
    $b64 =~ tr{+/}{-_};
    $b64 =~ s/=+\z//;
    return $b64;
}

# RFC 4122 version-4 UUID string built entirely from CSPRNG bytes
# (Python parity: str(uuid.uuid4())).
sub _random_uuid4 () {
    my @octets = unpack 'C16', _random_bytes(16);
    $octets[6] = ( $octets[6] & 0x0f ) | 0x40;    # version 4
    $octets[8] = ( $octets[8] & 0x3f ) | 0x80;    # variant 10xx
    my $hex = join '', map { sprintf '%02x', $_ } @octets;
    return join '-', substr( $hex, 0, 8 ), substr( $hex, 8, 4 ), substr( $hex, 12, 4 ),
        substr( $hex, 16, 4 ), substr( $hex, 20, 12 );
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Core::Random - the SDK's single cryptographically-secure entropy source

=head1 DESCRIPTION

SDK-internal plumbing. Every security-relevant random value in this
distribution is drawn from this module, so that the choice of entropy source
lives in exactly one place.

Backed by L<Crypt::URandom>, which dispatches to the platform CSPRNG:
C<getrandom(2)> or C</dev/urandom> on Unix-likes, and C<RtlGenRandom> /
C<CryptGenRandom> on Win32. Reading C</dev/urandom> directly — as this SDK
previously did at eight call sites — is not portable: Windows has no such
device.

There is deliberately B<no fallback> to C<rand()>, to time-seeded material, or
to an environment-supplied value. A downgraded entropy path in a security
primitive is worse than a loud failure, because the degraded output is
indistinguishable from the good output. If the platform CSPRNG cannot be
reached, these subs C<die>.

All subs are underscore-private; there is no public API and no counterpart in
the Python reference, which calls C<secrets> / C<os.urandom> directly.

=head1 SEE ALSO

L<Crypt::URandom>

=cut
