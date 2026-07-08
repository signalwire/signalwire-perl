#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use SignalWire::Core::LoggingConfig;

subtest 'strip_control_chars removes C0/C1 controls' => sub {
    my $event = {
        msg   => "hello\x00world\x1f!",
        keep  => "tab\ttab newline\nok",       # tab/newline preserved
        num   => 42,                           # non-string left alone
        ref   => [ 'x' ],                      # ref left alone
    };
    my $out = SignalWire::Core::LoggingConfig::strip_control_chars($event);
    is( $out, $event, 'returns the same hashref' );
    is( $out->{msg},  'helloworld!',            'null + control byte stripped' );
    is( $out->{keep}, "tab\ttab newline\nok",   'tab and newline preserved' );
    is( $out->{num},  42,                        'numeric value unchanged' );
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

done_testing;
