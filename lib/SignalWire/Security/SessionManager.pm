package SignalWire::Security::SessionManager;
use strict;
use warnings;
use Moo;
use JSON                     ();
use Digest::SHA              qw(hmac_sha256_hex);
use MIME::Base64             ();
use Time::HiRes              ();
use SignalWire::Core::Random ();

has 'token_expiry_secs' => (
    is      => 'ro',
    default => sub { 900 },    # 15 minutes
);

has 'secret_key' => (
    is      => 'ro',
    default => sub { _random_hex(32) },
);

has '_debug_mode' => (
    init_arg => undef,
    is       => 'rw',
    default  => sub { 0 },
);

sub _random_hex {
    my ($len) = @_;
    return SignalWire::Core::Random::_random_hex($len);
}

sub _random_urlsafe {
    my ($len) = @_;
    return SignalWire::Core::Random::_random_urlsafe($len);
}

sub create_session {
    my ( $self, $call_id ) = @_;
    $call_id //= _random_urlsafe(16);
    return $call_id;
}

sub generate_token {
    my ( $self, $function_name, $call_id ) = @_;
    my $expiry = int( time() ) + $self->token_expiry_secs;
    my $nonce  = _random_hex(8);

    my $message   = "$call_id:$function_name:$expiry:$nonce";
    my $signature = hmac_sha256_hex( $message, $self->secret_key );

    my $token = "$call_id.$function_name.$expiry.$nonce.$signature";

    # PADDED urlsafe base64, matching the reference's
    # `base64.urlsafe_b64encode(...)` (session_manager.py:86). MIME::Base64's
    # encode_base64url STRIPS the `=` padding, and the reference's validator
    # calls `base64.urlsafe_b64decode` with no padding tolerance — so it RAISES
    # on an unpadded token and returns False. A perl-minted `__token` on a SWAIG
    # webhook URL was therefore rejected by the reference (and by any port that
    # decodes strictly), while perl's own decoder tolerates padding, making the
    # break one-directional and easy to miss. Re-pad to the 4-char boundary.
    my $b64 = MIME::Base64::encode_base64url( $token, '' );
    if ( my $rem = length($b64) % 4 ) {
        $b64 .= '=' x ( 4 - $rem );
    }
    return $b64;
}

# Alias
sub create_tool_token {
    my ( $self, $function_name, $call_id ) = @_;
    return $self->generate_token( $function_name, $call_id );
}

sub _timing_safe_compare {
    my ( $a, $b ) = @_;

    # Compare HMAC of both values for constant-time comparison
    my $key    = 'timing-safe-token-comparison';
    my $hmac_a = hmac_sha256_hex( $a, $key );
    my $hmac_b = hmac_sha256_hex( $b, $key );
    return $hmac_a eq $hmac_b;
}

sub validate_token {
    my ( $self, $call_id, $function_name, $token ) = @_;

    return 0 unless $call_id && $function_name && $token;

    my $decoded;
    eval { $decoded = MIME::Base64::decode_base64url($token); };
    return 0 if $@ || !$decoded;

    my @parts = split( /\./, $decoded );
    return 0 unless @parts == 5;

    my ( $token_call_id, $token_function, $token_expiry, $token_nonce, $token_signature ) = @parts;

    # Verify function matches
    return 0 unless _timing_safe_compare( $token_function, $function_name );

    # Check expiry
    my $expiry = eval { int($token_expiry) };
    return 0 if $@ || !defined $expiry;
    return 0 if $expiry < time();

    # Recreate and verify signature
    my $message            = "$token_call_id:$token_function:$token_expiry:$token_nonce";
    my $expected_signature = hmac_sha256_hex( $message, $self->secret_key );
    return 0 unless _timing_safe_compare( $token_signature, $expected_signature );

    # Verify call_id
    return 0 unless _timing_safe_compare( $token_call_id, $call_id );

    return 1;
}

# Alias with different parameter order for backward compat
sub validate_tool_token {
    my ( $self, $function_name, $token, $call_id ) = @_;
    return $self->validate_token( $call_id, $function_name, $token );
}

# Legacy methods - no-ops for API compat (mirroring Python's
# stateless SessionManager.activate_session/end_session/etc. which
# accept the args, validate they're present, and return success).
sub activate_session {
    my ( $self, $call_id ) = @_;
    return 1;
}

sub end_session {
    my ( $self, $call_id ) = @_;
    return 1;
}

sub get_session_metadata {
    my ( $self, $call_id ) = @_;
    return {};
}

sub set_session_metadata {
    my ( $self, $call_id, $key, $value ) = @_;
    return 1;
}

sub debug_token {
    my ( $self, $token ) = @_;
    return { error => 'debug mode not enabled' } unless $self->_debug_mode;

    my $decoded;
    eval { $decoded = MIME::Base64::decode_base64url($token) };
    if ( $@ || !$decoded ) {
        return {
            valid_format => JSON::false,
            error        => $@ // 'decode failed',
            token_length => defined $token ? length($token) : 0,
        };
    }

    my @parts = split( /\./, $decoded );
    if ( @parts != 5 ) {
        return {
            valid_format => JSON::false,
            parts_count  => scalar @parts,
            token_length => length($token),
        };
    }

    my ( $tc, $tf, $te, $tn, $ts ) = @parts;
    my $current = int( time() );
    my $expiry  = eval { int($te) };
    my $expired = defined $expiry ? ( $expiry < $current ? 1 : 0 ) : undef;

    return {
        valid_format => JSON::true,
        components   => {
            call_id   => ( length($tc) > 8 ? substr( $tc, 0, 8 ) . '...' : $tc ),
            function  => $tf,
            expiry    => $te,
            nonce     => $tn,
            signature => ( length($ts) > 8 ? substr( $ts, 0, 8 ) . '...' : $ts ),
        },
        status => {
            current_time       => $current,
            is_expired         => $expired,
            expires_in_seconds => ( defined $expiry && !$expired ? $expiry - $current : 0 ),
        },
    };
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Security::SessionManager - stateless HMAC token issuer/validator for SWAIG sessions

=head1 SYNOPSIS

    use SignalWire::Security::SessionManager;

    my $mgr     = SignalWire::Security::SessionManager->new;
    my $call_id = $mgr->create_session;
    my $token   = $mgr->generate_token('get_weather', $call_id);

    if ( $mgr->validate_token($call_id, 'get_weather', $token) ) {
        # authorised
    }

=head1 DESCRIPTION

L<SignalWire::Security::SessionManager> issues and validates per-function,
per-call HMAC-SHA256 tokens used to authorise SWAIG tool invocations.
Tokens embed the call id, function name, an expiry timestamp, and a
nonce, all signed with a per-instance secret key; validation is
constant-time. The manager holds no session state — the "session"
methods exist for API compatibility and are effectively no-ops.

=head1 ATTRIBUTES

=over 4

=item C<token_expiry_secs>

Token lifetime in seconds (read-only; default 900 = 15 minutes).

=item C<secret_key>

The HMAC signing key (read-only; defaults to 32 bytes from the platform CSPRNG
via L<SignalWire::Core::Random>).

=back

=head1 METHODS

=over 4

=item C<create_session($call_id)>

Return C<$call_id>, generating a random URL-safe id when none is given.

=item C<generate_token($function_name, $call_id)>

Issue a signed, base64url-encoded token scoped to C<$function_name> and
C<$call_id>.

=item C<create_tool_token($function_name, $call_id)>

Alias for C<generate_token>, with the same argument order.

=item C<validate_token($call_id, $function_name, $token)>

Return C<1> when C<$token> is well-formed, unexpired, and its signature,
function, and call id all match; C<0> otherwise. Returns 0 rather than
dying on a malformed or undecodable token.

=item C<validate_tool_token($function_name, $token, $call_id)>

Alias for C<validate_token> — but note the B<argument order differs>:
C<$function_name, $token, $call_id> here versus
C<$call_id, $function_name, $token> there. The two are not interchangeable
positionally, so pick one spelling and keep to it.

=item C<activate_session>, C<end_session>, C<get_session_metadata>, C<set_session_metadata>

Stateless no-op session helpers kept for Python API compatibility. The
metadata getters/setters return an empty hashref / true respectively.

=item C<debug_token($token)>

Decode and describe a token's components and expiry status (call id and
signature are truncated). Returns an error hashref unless debug mode is
enabled on the instance.

=back

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
