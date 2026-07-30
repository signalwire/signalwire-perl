#!/usr/bin/env perl
# Copyright (c) 2025 SignalWire
#
# Licensed under the MIT License.
# See LICENSE file in the project root for full license information.

# token-interop-mint.pl — the Perl port's TOKEN-INTEROP mint fixture for the
# cross-port checker (porting-sdk/scripts/diff_port_token_interop.py).
#
# The contract being proven is property 3 of the SWAIG tool-token contract: a
# token this port MINTS must validate under the REFERENCE's own decoder. The
# other two properties (that a token is minted at all; that the HMAC is keyed
# with the secret_key STRING's bytes) already had coverage — this one did not,
# and a port can pass both and still emit a token no other implementation
# accepts, in which case every secure tool call fails authentication in
# production. This port is where the defect class was caught in the wild:
# MIME::Base64's encode_base64url STRIPS the '=' padding the reference's
# urlsafe_b64decode requires, so SessionManager re-pads to the 4-char boundary.
#
# Protocol: read the FIXED mint inputs from the environment (the checker owns
# them, so this fixture cannot drift from the values it is verified against),
# construct a SessionManager with that secret key, mint ONE token, and print
# JUST the token on stdout. Anything else belongs on stderr.
#
# Run from the signalwire-perl repo root:
#
#   perl -Ilib bin/token-interop-mint.pl

use strict;
use warnings;

use SignalWire::Security::SessionManager;

# Read a required fixed mint input from the environment, or fail loud.
sub required {
    my ($name) = @_;
    my $value = $ENV{$name};
    unless ( defined $value && length $value ) {
        print STDERR "$name is not set — the TOKEN-INTEROP checker supplies the "
            . "fixed mint inputs in the environment; run this via "
            . "diff_port_token_interop.py --mint-cmd.\n";
        exit 1;
    }
    return $value;
}

my $secret_key    = required('SW_TOKEN_INTEROP_SECRET_KEY');
my $call_id       = required('SW_TOKEN_INTEROP_CALL_ID');
my $function_name = required('SW_TOKEN_INTEROP_FUNCTION_NAME');

# Default expiry — the token must carry a FUTURE expiry, which the checker verifies.
my $manager = SignalWire::Security::SessionManager->new(
    secret_key        => $secret_key,
    token_expiry_secs => 900,
);
print $manager->generate_token( $function_name, $call_id ), "\n";
