package SignalWire::SWAIG::JoinConference;
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# The four closed-set string parameters of
# SignalWire::SWAIG::FunctionResult->join_conference, as typed, named
# constants:
#
#   - BEEP:   beep behaviour — 'true', 'false', 'onEnter', or 'onExit'
#   - RECORD: recording mode — 'do-not-record' or 'record-from-start'
#   - TRIM:   silence trimming — 'trim-silence' or 'do-not-trim'
#   - METHOD: HTTP method for the status / recording-status callbacks —
#             'GET' or 'POST' (shared by status_callback_method and
#             recording_status_callback_method)
#
# Like RecordCall's FORMAT/DIRECTION these are NOT merely advisory:
# join_conference validates each inline and dies on anything outside the
# set, mirroring the Python reference's exact ValueError messages
# (e.g. "beep must be one of ['true', 'false', 'onEnter', 'onExit']").
# This module hoists those literal sets into a single source of truth so
# the accepted values are discoverable and autocompletable instead of
# living only inside the `die` strings.
#
# Perl has no real enums, so these constants buy no compile-time typo
# checking — join_conference's own `die` is still what rejects a bad value
# at runtime. The constants ARE the canonical wire strings, so
# join_conference's signature is unchanged: it still takes plain
# `beep => ...` / `record => ...` / `trim => ...` /
# `status_callback_method => ...` strings, preserving Python parity and any
# caller already passing the literals.
#
#     use SignalWire::SWAIG::JoinConference qw(ON_ENTER RECORD_FROM_START);
#     $result->join_conference('lobby', beep => ON_ENTER,
#                              record => RECORD_FROM_START);     # constants
#     $result->join_conference('lobby', beep => 'onEnter',
#                              record => 'record-from-start');   # strings
#
# Mirrors SignalWire::SWAIG::RecordCall / SignalWire::Skills::SkillName /
# SignalWire::Logging::LogLevel and the cross-port Tier-1 idiom proof,
# adapted to Perl's constants idiom.

use strict;
use warnings;

use Exporter 'import';

# Beep behaviour. Values are the exact strings join_conference accepts
# (anything else dies). Keep in lockstep with join_conference's
# beep validation. (Constant names use snake-ish SHOUTING; the VALUES are
# the camelCase wire strings 'onEnter' / 'onExit' the SWML verb expects.)
use constant {
    BEEP_TRUE  => 'true',
    BEEP_FALSE => 'false',
    ON_ENTER   => 'onEnter',
    ON_EXIT    => 'onExit',
};

# Recording mode.
use constant {
    DO_NOT_RECORD     => 'do-not-record',
    RECORD_FROM_START => 'record-from-start',
};

# Silence trimming.
use constant {
    TRIM_SILENCE => 'trim-silence',
    DO_NOT_TRIM  => 'do-not-trim',
};

# Callback HTTP methods (status_callback_method /
# recording_status_callback_method).
use constant {
    GET  => 'GET',
    POST => 'POST',
};

our @EXPORT_OK = qw(
    BEEP_TRUE BEEP_FALSE ON_ENTER ON_EXIT
    DO_NOT_RECORD RECORD_FROM_START
    TRIM_SILENCE DO_NOT_TRIM
    GET POST
);
our %EXPORT_TAGS = (
    all     => [@EXPORT_OK],
    beep    => [qw( BEEP_TRUE BEEP_FALSE ON_ENTER ON_EXIT )],
    record  => [qw( DO_NOT_RECORD RECORD_FROM_START )],
    trim    => [qw( TRIM_SILENCE DO_NOT_TRIM )],
    methods => [qw( GET POST )],
);

# Canonical accepted sets, in the order join_conference lists them in its
# validation messages (matching Python's list rendering exactly).
my @BEEPS   = qw( true false onEnter onExit );
my @RECORDS = ( 'do-not-record', 'record-from-start' );
my @TRIMS   = ( 'trim-silence', 'do-not-trim' );
my @METHODS = qw( GET POST );

my %IS_BEEP   = map { $_ => 1 } @BEEPS;
my %IS_RECORD = map { $_ => 1 } @RECORDS;
my %IS_TRIM   = map { $_ => 1 } @TRIMS;
my %IS_METHOD = map { $_ => 1 } @METHODS;

# JoinConference->beeps — arrayref of the accepted beep strings.
sub beeps   { return [@BEEPS]; }

# JoinConference->records — arrayref of the accepted record-mode strings.
sub records { return [@RECORDS]; }

# JoinConference->trims — arrayref of the accepted trim strings.
sub trims   { return [@TRIMS]; }

# JoinConference->methods — arrayref of the accepted callback HTTP methods.
sub methods { return [@METHODS]; }

# JoinConference->is_beep($value) — true if $value is an accepted beep
# value. Accepts the bareword constant too (it's just the string).
sub is_beep {
    my ($class, $value) = @_;
    return 0 unless defined $value;
    return exists $IS_BEEP{$value} ? 1 : 0;
}

# JoinConference->is_record($value) — true if $value is an accepted record
# mode.
sub is_record {
    my ($class, $value) = @_;
    return 0 unless defined $value;
    return exists $IS_RECORD{$value} ? 1 : 0;
}

# JoinConference->is_trim($value) — true if $value is an accepted trim
# value.
sub is_trim {
    my ($class, $value) = @_;
    return 0 unless defined $value;
    return exists $IS_TRIM{$value} ? 1 : 0;
}

# JoinConference->is_method($value) — true if $value is an accepted
# callback HTTP method.
sub is_method {
    my ($class, $value) = @_;
    return 0 unless defined $value;
    return exists $IS_METHOD{$value} ? 1 : 0;
}

1;
