package SignalWire::Logging::LogLevel;
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# Log levels as a typed, named closed set.
#
# Perl is dynamically typed and has no real enums, so a bare string like
# 'debg' still only surfaces at runtime (here it'd silently fall back to
# the 'info' threshold via the `// 1` default in SignalWire::Logging).
# What this module DOES buy:
#   - a single source of truth for the four log levels, co-located with
#     the logger (the canonical set otherwise lives only inside the
#     %LEVELS table in SignalWire::Logging);
#   - editor autocomplete + discoverability via named constants;
#   - LogLevel->all for iteration / validation, LogLevel->is_valid for
#     membership checks, and LogLevel->severity for the ascending-severity
#     ordering (the same numbers SignalWire::Logging uses to decide
#     whether a message clears the configured threshold).
#
# The constants ARE the canonical level strings, so nothing about
# SignalWire::Logging changes: the `level` attribute, the
# SIGNALWIRE_LOG_LEVEL env var, and the debug/info/warn/error methods all
# still take / emit plain strings. That keeps parity with the Python
# reference (stdlib logging level names) and leaves any custom threshold
# string working exactly as before.
#
#     use SignalWire::Logging::LogLevel qw(DEBUG);
#     my $log = SignalWire::Logging->new(level => DEBUG);   # imported constant
#     SignalWire::Logging->new(level => 'debug');           # string (parity)
#     $ENV{SIGNALWIRE_LOG_LEVEL} = SignalWire::Logging::LogLevel::WARN();  # FQ
#
# Mirrors SignalWire::Skills::SkillName (the built-in-skill closed set)
# and the cross-port Tier-1 idiom proof, adapted to Perl's constants
# idiom.

use strict;
use warnings;

use Exporter 'import';

# Each constant's value is the exact level string SignalWire::Logging
# recognises in its %LEVELS table and emits from debug/info/warn/error.
use constant {
    DEBUG => 'debug',
    INFO  => 'info',
    WARN  => 'warn',
    ERROR => 'error',
};

our @EXPORT_OK = qw( DEBUG INFO WARN ERROR );
our %EXPORT_TAGS = ( all => [@EXPORT_OK] );

# Ascending severity — the SAME ordering SignalWire::Logging's private
# %LEVELS table uses to decide whether a message at one level clears the
# configured threshold. Keep this in lockstep with that table.
my %SEVERITY = (
    debug => 0,
    info  => 1,
    warn  => 2,
    error => 3,
);

# Ordered low->high severity. Not sorted alphabetically: the natural
# order for log levels is severity, which is also how a human reads them.
my @ALL = qw( debug info warn error );

my %IS_VALID = map { $_ => 1 } @ALL;

# LogLevel->all — arrayref of the four level strings, ascending severity.
sub all {
    return [@ALL];
}

# LogLevel->is_valid($level) — true if $level is one of the four known
# levels, false otherwise. Accepts the bareword constant too (it's just
# the string).
sub is_valid {
    my ($class, $level) = @_;
    return 0 unless defined $level;
    return exists $IS_VALID{$level} ? 1 : 0;
}

# LogLevel->severity($level) — the ascending-severity integer for $level
# (debug=0 .. error=3), or undef for an unknown level. Mirrors the
# threshold numbers SignalWire::Logging uses internally.
sub severity {
    my ($class, $level) = @_;
    return undef unless defined $level;
    return $SEVERITY{$level};
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Logging::LogLevel - log levels as a typed closed set

=head1 SYNOPSIS

    use SignalWire::Logging::LogLevel qw(DEBUG);

    my $log = SignalWire::Logging->new( level => DEBUG );  # imported constant
    SignalWire::Logging->new( level => 'debug' );          # string (parity)
    $ENV{SIGNALWIRE_LOG_LEVEL} = SignalWire::Logging::LogLevel::WARN();

    # Membership / ordering helpers:
    SignalWire::Logging::LogLevel->is_valid('warn');  # 1
    SignalWire::Logging::LogLevel->severity('error'); # 3
    @{ SignalWire::Logging::LogLevel->all };           # debug,info,warn,error

=head1 DESCRIPTION

The four log levels, surfaced as typed, named constants whose values are
the exact level strings L<SignalWire::Logging> recognises in its private
C<%LEVELS> table and emits from C<debug>/C<info>/C<warn>/C<error>.

The constants B<are> the canonical level strings, so nothing about
L<SignalWire::Logging> changes: the C<level> attribute, the
C<SIGNALWIRE_LOG_LEVEL> env var, and the level methods all still take /
emit plain strings. That keeps parity with the Python reference (stdlib
C<logging> level names) and leaves any custom threshold string working
exactly as before.

This buys a single source of truth for the four levels (otherwise they
live only inside the C<%LEVELS> table), plus editor autocomplete and the
membership/severity helpers below.

=head1 CONSTANTS

Exported on request via L<Exporter>; C<:all> pulls every constant.

    DEBUG => 'debug'    WARN  => 'warn'
    INFO  => 'info'     ERROR => 'error'

=head1 METHODS

=head2 all

    my $aref = SignalWire::Logging::LogLevel->all;

Arrayref of the four level strings in ascending severity (not alphabetical
— severity is the natural reading order for log levels).

=head2 is_valid

    my $bool = SignalWire::Logging::LogLevel->is_valid($level);

True if C<$level> is one of the four known levels, false otherwise.
Accepts the bareword constant too.

=head2 severity

    my $n = SignalWire::Logging::LogLevel->severity($level);

The ascending-severity integer for C<$level> (C<debug>=0 .. C<error>=3),
or C<undef> for an unknown level. These are the same threshold numbers
L<SignalWire::Logging> uses internally to decide whether a message clears
the configured threshold.

=head1 SEE ALSO

L<SignalWire::Logging>, L<SignalWire::Skills::SkillName>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
