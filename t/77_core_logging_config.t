#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use SignalWire::Core::LoggingConfig;

subtest 'strip_control_chars removes C0/C1 controls' => sub {
    my $event = {
        msg  => "hello\x00world\x1f!",
        keep => "tab\ttab newline\nok",    # tab/newline preserved
        num  => 42,                        # non-string left alone
        ref  => ['x'],                     # ref left alone
    };
    my $out = SignalWire::Core::LoggingConfig::strip_control_chars($event);
    is( $out,         $event,                 'returns the same hashref' );
    is( $out->{msg},  'helloworld!',          'null + control byte stripped' );
    is( $out->{keep}, "tab\ttab newline\nok", 'tab and newline preserved' );
    is( $out->{num},  42,                     'numeric value unchanged' );
    is_deeply( $out->{ref}, ['x'], 'ref value unchanged' );

    # a DEL / C1 char is stripped too
    my $e2 = SignalWire::Core::LoggingConfig::strip_control_chars( { s => "a\x7fb\x9fc" } );
    is( $e2->{s}, 'abc', 'DEL and C1 stripped' );
};

subtest 'configure_logging is idempotent; reset re-arms it' => sub {

    # Should not die on repeated calls.
    eval {
        SignalWire::Core::LoggingConfig::configure_logging();
        SignalWire::Core::LoggingConfig::configure_logging();
    };
    is( $@, '', 'configure_logging idempotent, no error' );

    eval { SignalWire::Core::LoggingConfig::reset_logging_configuration(); };
    is( $@, '', 'reset_logging_configuration runs without error' );

    eval { SignalWire::Core::LoggingConfig::configure_logging(); };
    is( $@, '', 'configure_logging runs again after reset' );
};

# The scrub must be ON THE EMISSION PATH, not merely available.
#
# The map-contract subtest above passed for the life of this port while
# Logger::_log wrote the caller's message to STDERR verbatim — strip_control_chars
# was correct, exported, and called by NOTHING. Only an assertion that reads what
# the logger ACTUALLY emitted can tell those two states apart, which is why this
# captures STDERR and drives the real logger.
subtest 'log output has control chars stripped (the WIRING)' => sub {
    require SignalWire::Logging;

    my $captured = '';
    {
        # Redirect STDERR into a scalar for this block only; the local() restores
        # it on scope exit even if the logger dies.
        local *STDERR;
        open( STDERR, '>', \$captured ) or die "cannot redirect STDERR: $!";
        my $logger = SignalWire::Logging::get_logger('inject.test');
        $logger->info("user\x00said\x1b[31mRED\x07");
    }

    unlike( $captured, qr/\x00/, 'NUL does not reach the emitted line' );
    unlike( $captured, qr/\x1b/, 'ESC does not reach the emitted line' );
    unlike( $captured, qr/\x07/, 'BEL does not reach the emitted line' );
    like( $captured, qr/\Qusersaid[31mRED\E/, 'the printable text survives' );
};

# Tab/newline/CR are LEGAL in a log line and must survive — a scrub that ate them
# would satisfy the assertions above while mangling every multi-line message.
subtest 'log output keeps legal whitespace' => sub {
    require SignalWire::Logging;

    my $legal    = "line1\tcol\nline2\r end";
    my $captured = '';
    {
        local *STDERR;
        open( STDERR, '>', \$captured ) or die "cannot redirect STDERR: $!";
        my $logger = SignalWire::Logging::get_logger('inject.test');
        $logger->info($legal);
    }

    like( $captured, qr/\Q$legal\E/, 'tab/newline/CR survive the scrub' );
};

done_testing;
