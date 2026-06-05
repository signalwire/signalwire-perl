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

__END__

=encoding utf-8

=head1 NAME

SignalWire::SWAIG::JoinConference - typed closed sets for FunctionResult->join_conference

=head1 SYNOPSIS

    use SignalWire::SWAIG::JoinConference qw(ON_ENTER RECORD_FROM_START);
    use SignalWire::SWAIG::FunctionResult;

    my $result = SignalWire::SWAIG::FunctionResult->new;

    # Named constants and bare wire strings are interchangeable:
    $result->join_conference( 'lobby',
        beep   => ON_ENTER,
        record => RECORD_FROM_START );
    $result->join_conference( 'lobby',
        beep   => 'onEnter',
        record => 'record-from-start' );

    # Membership / iteration helpers:
    SignalWire::SWAIG::JoinConference->is_beep('onEnter');  # 1
    @{ SignalWire::SWAIG::JoinConference->records };        # do-not-record,...

=head1 DESCRIPTION

The four closed-set string parameters of
L<SignalWire::SWAIG::FunctionResult>'s C<join_conference> verb, surfaced
as typed, named constants:

=over 4

=item * B<BEEP> — beep behaviour: C<true>, C<false>, C<onEnter>, or
C<onExit>.

=item * B<RECORD> — recording mode: C<do-not-record> or
C<record-from-start>.

=item * B<TRIM> — silence trimming: C<trim-silence> or C<do-not-trim>.

=item * B<METHOD> — HTTP method for the status / recording-status
callbacks: C<GET> or C<POST> (shared by C<status_callback_method> and
C<recording_status_callback_method>).

=back

C<join_conference> validates each inline and dies on anything outside the
set, reproducing the Python reference's exact C<ValueError> messages
(e.g. C<beep must be one of ['true', 'false', 'onEnter', 'onExit']>). This
module hoists those literal sets into a single source of truth so the
accepted values are discoverable and autocompletable. The constants B<are>
the canonical wire strings, so C<join_conference>'s signature is
unchanged, preserving Python parity.

The constant B<names> use shouting identifiers (C<ON_ENTER>); the
B<values> are the camelCase wire strings the SWML verb expects
(C<onEnter>).

=head1 CONSTANTS

Exported on request via L<Exporter>. Tags: C<:beep>, C<:record>, C<:trim>,
C<:methods>, and C<:all>.

    BEEP_TRUE  => 'true'      DO_NOT_RECORD     => 'do-not-record'
    BEEP_FALSE => 'false'     RECORD_FROM_START => 'record-from-start'
    ON_ENTER   => 'onEnter'   TRIM_SILENCE      => 'trim-silence'
    ON_EXIT    => 'onExit'    DO_NOT_TRIM       => 'do-not-trim'
    GET        => 'GET'       POST              => 'POST'

=head1 METHODS

=head2 beeps / records / trims / methods

    my $aref = SignalWire::SWAIG::JoinConference->beeps;
    my $aref = SignalWire::SWAIG::JoinConference->records;
    my $aref = SignalWire::SWAIG::JoinConference->trims;
    my $aref = SignalWire::SWAIG::JoinConference->methods;

Arrayrefs of the accepted strings for each set, in the order
C<join_conference> lists them in its validation messages.

=head2 is_beep / is_record / is_trim / is_method

    my $bool = SignalWire::SWAIG::JoinConference->is_beep($value);
    my $bool = SignalWire::SWAIG::JoinConference->is_record($value);
    my $bool = SignalWire::SWAIG::JoinConference->is_trim($value);
    my $bool = SignalWire::SWAIG::JoinConference->is_method($value);

True if C<$value> is an accepted member of the corresponding set. Each
accepts the bareword constant too (it is just the string).

=head1 SEE ALSO

L<SignalWire::SWAIG::FunctionResult>,
L<SignalWire::SWAIG::RecordCall>,
L<SignalWire::SWAIG::Tap>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
