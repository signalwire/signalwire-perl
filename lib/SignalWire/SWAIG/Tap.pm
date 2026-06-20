package SignalWire::SWAIG::Tap;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# The two closed-set string parameters of
# SignalWire::SWAIG::FunctionResult->tap, as typed, named constants:
#
#   - DIRECTION: which audio channel(s) to tap — 'speak', 'hear', or 'both'
#   - CODEC:     the RTP codec for the tapped media — 'PCMU' or 'PCMA'
#
# Like SignalWire::SWAIG::RecordCall these are NOT merely advisory: tap
# already validates both inline and dies on anything outside the set
# ("direction must be 'speak', 'hear', or 'both'", "codec must be 'PCMU'
# or 'PCMA'"). This module hoists those two literal sets into a single
# source of truth so the accepted values are discoverable and
# autocompletable, instead of living only inside the `die` strings.
#
# ★ DISTINCT FROM RecordCall — three direction vocabularies never unify.
# tap's direction set is {speak, HEAR, both}: the inbound-listen channel
# is 'hear', NOT record_call's 'listen' ({speak, LISTEN, both}). They are
# different SWML verbs with different channel words; reusing RecordCall's
# LISTEN here would be a wire bug. Likewise this 2-value CODEC {PCMU,PCMA}
# is the SWAIG-tap codec set ONLY — it is a strict subset of, and must NOT
# be conflated with, the RELAY connect/stream codec superset
# ({PCMU,PCMA,OPUS,G722,G729,VP8,H264,...}). Keep this module tap-only.
#
# Perl has no real enums, so these constants buy no compile-time typo
# checking — tap's own `die` is still what rejects a bad value at runtime.
# The constants ARE the canonical wire strings, so tap's signature is
# unchanged: it still takes plain `direction => ...` / `codec => ...`
# strings, preserving Python parity and any caller already passing the
# literals.
#
#     use SignalWire::SWAIG::Tap qw(SPEAK HEAR BOTH PCMU PCMA);
#     $result->tap($uri, direction => HEAR, codec => PCMA);    # constants
#     $result->tap($uri, direction => 'hear', codec => 'PCMA'); # strings
#
# Mirrors SignalWire::SWAIG::RecordCall / SignalWire::Skills::SkillName /
# SignalWire::Logging::LogLevel and the cross-port Tier-1 idiom proof,
# adapted to Perl's constants idiom.

use strict;
use warnings;

use Exporter 'import';

# Tap channel directions. Values are the exact strings tap accepts
# (anything else dies). Keep in lockstep with tap's
# `die "direction must be 'speak', 'hear', or 'both'"` guard.
# NOTE 'hear' (NOT 'listen' — that's record_call's word).
use constant {
    SPEAK => 'speak',
    HEAR  => 'hear',
    BOTH  => 'both',
};

# Tap RTP codecs. Values are the exact strings tap accepts. Keep in
# lockstep with tap's `die "codec must be 'PCMU' or 'PCMA'"` guard.
use constant {
    PCMU => 'PCMU',
    PCMA => 'PCMA',
};

our @EXPORT_OK   = qw( SPEAK HEAR BOTH PCMU PCMA );
our %EXPORT_TAGS = (
    all        => [@EXPORT_OK],
    directions => [qw( SPEAK HEAR BOTH )],
    codecs     => [qw( PCMU PCMA )],
);

# Canonical accepted sets, in the order tap lists them in its validation
# messages.
my @DIRECTIONS = qw( speak hear both );
my @CODECS     = qw( PCMU PCMA );

my %IS_DIRECTION = map { $_ => 1 } @DIRECTIONS;
my %IS_CODEC     = map { $_ => 1 } @CODECS;

# Tap->directions — arrayref of the accepted tap direction strings.
sub directions {
    return [@DIRECTIONS];
}

# Tap->codecs — arrayref of the accepted tap codec strings.
sub codecs {
    return [@CODECS];
}

# Tap->is_direction($value) — true if $value is an accepted tap direction.
# Accepts the bareword constant too (it's just the string).
sub is_direction {
    my ( $class, $value ) = @_;
    return 0 unless defined $value;
    return exists $IS_DIRECTION{$value} ? 1 : 0;
}

# Tap->is_codec($value) — true if $value is an accepted tap codec.
# Accepts the bareword constant too.
sub is_codec {
    my ( $class, $value ) = @_;
    return 0 unless defined $value;
    return exists $IS_CODEC{$value} ? 1 : 0;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::SWAIG::Tap - typed closed sets for FunctionResult->tap

=head1 SYNOPSIS

    use SignalWire::SWAIG::Tap qw(SPEAK HEAR BOTH PCMU PCMA);
    use SignalWire::SWAIG::FunctionResult;

    my $result = SignalWire::SWAIG::FunctionResult->new;

    # Named constants and bare wire strings are interchangeable:
    $result->tap( 'rtp://1.2.3.4:5000', direction => HEAR,   codec => PCMA );
    $result->tap( 'rtp://1.2.3.4:5000', direction => 'hear', codec => 'PCMA' );

    # Membership / iteration helpers:
    SignalWire::SWAIG::Tap->is_direction('hear');  # 1
    SignalWire::SWAIG::Tap->is_codec('OPUS');      # 0 (RELAY-only codec)
    @{ SignalWire::SWAIG::Tap->codecs };           # ('PCMU','PCMA')

=head1 DESCRIPTION

The two closed-set string parameters of
L<SignalWire::SWAIG::FunctionResult>'s C<tap> verb, surfaced as typed,
named constants:

=over 4

=item * B<DIRECTION> — which audio channel(s) to tap: C<speak>, C<hear>,
or C<both>.

=item * B<CODEC> — the RTP codec for the tapped media: C<PCMU> or C<PCMA>.

=back

C<tap> validates both inline and dies on anything outside the set; this
module hoists those literal sets into a single source of truth so the
accepted values are discoverable and autocompletable instead of living
only inside the C<die> strings. The constants B<are> the canonical wire
strings, so C<tap>'s signature is unchanged.

B<Distinct from RecordCall.> The tap direction set is
C<{speak, hear, both}>: the inbound-listen channel is C<hear>, not
C<record_call>'s C<listen>. Likewise this two-value codec set
C<{PCMU, PCMA}> is the SWAIG-tap codec set only — a strict subset of the
RELAY connect/stream codec superset (C<PCMU>, C<PCMA>, C<OPUS>, C<G722>,
...). These vocabularies must never be conflated.

=head1 CONSTANTS

Exported on request via L<Exporter>. The C<:directions> tag pulls
C<SPEAK>/C<HEAR>/C<BOTH>; C<:codecs> pulls C<PCMU>/C<PCMA>; C<:all> pulls
every constant.

    SPEAK => 'speak'    PCMU => 'PCMU'
    HEAR  => 'hear'     PCMA => 'PCMA'
    BOTH  => 'both'

=head1 METHODS

=head2 directions

    my $aref = SignalWire::SWAIG::Tap->directions;

Arrayref of the accepted tap-direction strings.

=head2 codecs

    my $aref = SignalWire::SWAIG::Tap->codecs;

Arrayref of the accepted tap-codec strings.

=head2 is_direction

    my $bool = SignalWire::SWAIG::Tap->is_direction($value);

True if C<$value> is an accepted tap direction. Accepts the bareword
constant too (it is just the string).

=head2 is_codec

    my $bool = SignalWire::SWAIG::Tap->is_codec($value);

True if C<$value> is an accepted tap codec.

=head1 SEE ALSO

L<SignalWire::SWAIG::FunctionResult>,
L<SignalWire::SWAIG::RecordCall>,
L<SignalWire::SWAIG::JoinConference>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
