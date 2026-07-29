package SignalWire::Logging;
use strict;
use warnings;
use Moo;

# Log levels in ascending severity
my %LEVELS = (
    debug => 0,
    info  => 1,
    warn  => 2,
    error => 3,
);

has 'name' => (
    is      => 'ro',
    default => sub { 'signalwire' },
);

has 'level' => (
    is      => 'rw',
    default => sub {
        my $env = $ENV{SIGNALWIRE_LOG_LEVEL} // 'info';
        return lc($env);
    },
);

has 'suppressed' => (
    is      => 'rw',
    default => sub {
        my $mode = $ENV{SIGNALWIRE_LOG_MODE} // '';
        return lc($mode) eq 'off' ? 1 : 0;
    },
);

sub _should_log {
    my ( $self, $msg_level ) = @_;
    return 0 if $self->suppressed;
    my $current = $LEVELS{ $self->level } // 1;
    my $target  = $LEVELS{$msg_level}     // 1;
    return $target >= $current;
}

sub _log {
    my ( $self, $level, @msgs ) = @_;
    return unless $self->_should_log($level);
    my $tag  = uc($level);
    my $name = $self->name;
    my $msg  = join( ' ', @msgs );
    my $ts   = _timestamp();

    # Scrub control characters BEFORE emitting — log-injection defence, and the
    # reason the reference registers strip_control_chars in both of its structlog
    # processor chains. A port that merely EXPOSES the scrub without putting it on
    # the emission path offers no protection at all: a caller-supplied NUL or an
    # ESC-[ escape reaches the terminal verbatim and can forge log lines.
    # CYCLE NOTE: SignalWire::Core::LoggingConfig already `use`s this module, so a
    # compile-time `use` here would close the loop. Require at call time instead —
    # by the time anything logs, the module is loadable.
    require SignalWire::Core::LoggingConfig;
    # Route through the reference's event-map contract rather than a second
    # sub: a port-only `strip_control_chars_value` is surface the reference does
    # not have, and the surface gate reports it as an invented addition.
    my $safe = SignalWire::Core::LoggingConfig::strip_control_chars( { event => $msg } )->{event};
    print STDERR "[$ts] [$tag] [$name] $safe\n";
    return;
}

sub debug { my ( $self, @args ) = @_; return $self->_log( 'debug', @args ); }
sub info  { my ( $self, @args ) = @_; return $self->_log( 'info',  @args ); }
sub warn  { my ( $self, @args ) = @_; return $self->_log( 'warn',  @args ); }
sub error { my ( $self, @args ) = @_; return $self->_log( 'error', @args ); }

sub _timestamp {
    my @t = localtime;
    return sprintf(
        '%04d-%02d-%02d %02d:%02d:%02d',
        $t[5] + 1900,
        $t[4] + 1,
        $t[3], $t[2], $t[1], $t[0]
    );
}

# Singleton-ish factory
my %loggers;

sub get_logger {
    my ( $class, $name ) = @_;
    $name //= 'signalwire';
    $loggers{$name} //= SignalWire::Logging->new( name => $name );
    return $loggers{$name};
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Logging - lightweight leveled logger for the SignalWire SDK

=head1 SYNOPSIS

    use SignalWire::Logging;

    my $log = SignalWire::Logging->get_logger('signalwire.mymodule');
    $log->info('starting up');
    $log->warn('something looks off', $detail);
    $log->error('failed', $err);

=head1 DESCRIPTION

L<SignalWire::Logging> is a small Moo-based leveled logger. Messages are
written to C<STDERR> with a timestamp, level tag, and logger name. The
active level and suppression are taken from the C<SIGNALWIRE_LOG_LEVEL>
and C<SIGNALWIRE_LOG_MODE> environment variables at construction time,
and only messages at or above the current level are emitted. Loggers are
cached per name, so C<get_logger> returns the same instance for a given
name.

The four severity levels, in ascending order, are C<debug>, C<info>,
C<warn>, C<error>. Setting C<SIGNALWIRE_LOG_MODE> to C<off> suppresses
all output.

=head1 ATTRIBUTES

=over 4

=item C<name>

The logger name (read-only, defaults to C<'signalwire'>).

=item C<level>

The active minimum level to emit (read/write; defaults from
C<SIGNALWIRE_LOG_LEVEL>, else C<'info'>).

=item C<suppressed>

Whether all output is suppressed (read/write; true when
C<SIGNALWIRE_LOG_MODE> is C<off>).

=back

=head1 METHODS

=over 4

=item C<< SignalWire::Logging->get_logger($name) >>

Class-method factory returning the cached logger for C<$name> (defaults
to C<'signalwire'>), constructing it on first use.

=item C<debug(@msgs)>, C<info(@msgs)>, C<warn(@msgs)>, C<error(@msgs)>

Emit a message at the named level. Arguments are joined with a single
space. Output is skipped when suppressed or below the current level.

=back

=head1 SEE ALSO

L<SignalWire::Core::LoggingConfig>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
