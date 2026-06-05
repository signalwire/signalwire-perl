package SignalWire::SWAIG::RecordCall;
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# The two closed-set string parameters of
# SignalWire::SWAIG::FunctionResult->record_call, as typed, named
# constants:
#
#   - FORMAT:    the recording container — 'wav' or 'mp3'
#   - DIRECTION: which audio channel(s) to capture — 'speak', 'listen',
#                or 'both'
#
# Unlike most "value" sets in this SDK these are NOT merely advisory:
# record_call already validates both inline and dies on anything outside
# the set ("format must be 'wav' or 'mp3'", "direction must be 'speak',
# 'listen', or 'both'"). This module hoists those two literal sets into a
# single source of truth so the accepted values are discoverable and
# autocompletable, instead of living only inside the `die` strings.
#
# NOTE: this `direction` is the WRITE-side record-channel selector the
# caller passes to record_call. It is unrelated to the read-only
# inbound/outbound `direction` field on inbound/outbound Relay message
# events (SignalWire::Relay::Event), which is not a user-set value.
#
# Perl has no real enums, so these constants buy no compile-time typo
# checking — record_call's own `die` is still what rejects a bad value at
# runtime. The constants ARE the canonical wire strings, so record_call's
# signature is unchanged: it still takes plain `format => ...` /
# `direction => ...` strings, preserving Python parity and any caller
# already passing the literals.
#
#     use SignalWire::SWAIG::RecordCall qw(MP3 BOTH);
#     $result->record_call(format => MP3, direction => BOTH);   # constants
#     $result->record_call(format => 'mp3', direction => 'both'); # strings
#
# Mirrors SignalWire::Skills::SkillName / SignalWire::Logging::LogLevel
# and the cross-port Tier-1 idiom proof, adapted to Perl's constants idiom.

use strict;
use warnings;

use Exporter 'import';

# Recording container formats. Values are the exact strings record_call
# accepts (anything else dies). Keep in lockstep with record_call's
# `die "format must be 'wav', 'mp3', or 'mp4'"` guard.
use constant {
    WAV => 'wav',
    MP3 => 'mp3',
    MP4 => 'mp4',
};

# Record channel directions. Values are the exact strings record_call
# accepts. Keep in lockstep with record_call's
# `die "direction must be 'speak', 'listen', or 'both'"` guard.
use constant {
    SPEAK  => 'speak',
    LISTEN => 'listen',
    BOTH   => 'both',
};

our @EXPORT_OK = qw( WAV MP3 MP4 SPEAK LISTEN BOTH );
our %EXPORT_TAGS = (
    all        => [@EXPORT_OK],
    formats    => [qw( WAV MP3 MP4 )],
    directions => [qw( SPEAK LISTEN BOTH )],
);

# Canonical accepted sets, in the order record_call lists them in its
# validation messages.
my @FORMATS    = qw( wav mp3 mp4 );
my @DIRECTIONS = qw( speak listen both );

my %IS_FORMAT    = map { $_ => 1 } @FORMATS;
my %IS_DIRECTION = map { $_ => 1 } @DIRECTIONS;

# RecordCall->formats — arrayref of the accepted format strings.
sub formats {
    return [@FORMATS];
}

# RecordCall->directions — arrayref of the accepted direction strings.
sub directions {
    return [@DIRECTIONS];
}

# RecordCall->is_format($value) — true if $value is an accepted recording
# format. Accepts the bareword constant too (it's just the string).
sub is_format {
    my ($class, $value) = @_;
    return 0 unless defined $value;
    return exists $IS_FORMAT{$value} ? 1 : 0;
}

# RecordCall->is_direction($value) — true if $value is an accepted record
# direction. Accepts the bareword constant too.
sub is_direction {
    my ($class, $value) = @_;
    return 0 unless defined $value;
    return exists $IS_DIRECTION{$value} ? 1 : 0;
}

1;
