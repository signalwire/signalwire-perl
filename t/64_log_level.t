#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# SignalWire::Logging::LogLevel — the typed closed set of log-level names.
# The core guarantee (mirroring SkillName / the cross-port Tier-1 idiom
# proof): a named constant and the bare level string configure the
# IDENTICAL logger threshold, so parity with the Python reference (stdlib
# level-name strings) holds. Drives REAL SignalWire::Logging threshold
# behavior via its public level attribute + debug/info/warn/error — no
# mocks, no patching.

use_ok('SignalWire::Logging::LogLevel');
use_ok('SignalWire::Logging');

use SignalWire::Logging::LogLevel qw(DEBUG INFO WARN ERROR);

# ------------------------------------------------------------------
# 1. Constants ARE the canonical level strings.
# ------------------------------------------------------------------
subtest 'constants equal level strings' => sub {
    is(DEBUG, 'debug', 'DEBUG constant');
    is(INFO,  'info',  'INFO constant');
    is(WARN,  'warn',  'WARN constant');
    is(ERROR, 'error', 'ERROR constant');
    # Fully-qualified call form also works (constants are subs).
    is(SignalWire::Logging::LogLevel::ERROR(), 'error', 'FQ ERROR() constant');
};

# ------------------------------------------------------------------
# 2. ->all is the full closed set (ascending severity) and ->severity
#    matches that ordering.
# ------------------------------------------------------------------
subtest 'all + severity ordering' => sub {
    my $all = SignalWire::Logging::LogLevel->all;
    is(ref $all, 'ARRAY', 'all returns an arrayref');
    is_deeply($all, [qw(debug info warn error)],
        'all lists the four levels in ascending severity');

    # Severity is strictly increasing in the listed order.
    my @sev = map { SignalWire::Logging::LogLevel->severity($_) } @$all;
    is_deeply(\@sev, [0, 1, 2, 3], 'severity ascends 0..3 across all()');
    for my $i (1 .. $#sev) {
        ok($sev[$i] > $sev[$i - 1],
            "severity($all->[$i]) > severity($all->[$i-1])");
    }
    is(SignalWire::Logging::LogLevel->severity('nope'), undef,
        'severity of unknown level is undef');
};

# ------------------------------------------------------------------
# 3. ->is_valid membership: known true, unknown/undef false.
# ------------------------------------------------------------------
subtest 'is_valid membership' => sub {
    ok(SignalWire::Logging::LogLevel->is_valid('debug'), 'debug is valid');
    ok(SignalWire::Logging::LogLevel->is_valid(ERROR), 'ERROR constant is valid');
    ok(!SignalWire::Logging::LogLevel->is_valid('trace'), 'trace is not valid');
    ok(!SignalWire::Logging::LogLevel->is_valid('debg'), 'typo is not valid');
    ok(!SignalWire::Logging::LogLevel->is_valid(undef), 'undef is not valid');
};

# ------------------------------------------------------------------
# 4. The core proof: a logger configured via the named constant and one
#    configured via the bare string make IDENTICAL threshold decisions
#    across every level. This exercises the real SignalWire::Logging
#    _should_log path (which reads the same private %LEVELS the constants
#    mirror) — no mocks.
# ------------------------------------------------------------------
subtest 'constant- and string-configured loggers behave identically' => sub {
    my @levels = qw(debug info warn error);

    for my $threshold (@levels) {
        my $const_val = { debug => DEBUG, info => INFO, warn => WARN, error => ERROR }->{$threshold};

        my $by_const = SignalWire::Logging->new(name => "c_$threshold", level => $const_val);
        my $by_str   = SignalWire::Logging->new(name => "s_$threshold", level => $threshold);

        is($by_const->level, $by_str->level,
            "level attr identical for threshold '$threshold'");

        # For each message level, the suppress/emit decision must match
        # between the two loggers, AND match the severity contract
        # (emit iff message severity >= threshold severity).
        for my $msg (@levels) {
            my $c = $by_const->_should_log($msg) ? 1 : 0;
            my $s = $by_str->_should_log($msg)   ? 1 : 0;
            is($c, $s,
                "_should_log('$msg') identical (constant vs string, threshold '$threshold')");

            my $expected =
                SignalWire::Logging::LogLevel->severity($msg)
                    >= SignalWire::Logging::LogLevel->severity($threshold)
                ? 1 : 0;
            is($c, $expected,
                "_should_log('$msg') matches severity contract at threshold '$threshold'");
        }
    }
};

done_testing;
