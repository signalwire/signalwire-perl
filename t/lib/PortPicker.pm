package PortPicker;

# Pick free loopback TCP ports by binding to :0 and reading the OS-assigned
# port. Used by the mock-test harnesses so concurrent runs / leftover mocks
# never collide on a fixed port (and then hang on a health poll). Mirrors the
# cross-port contract: never reuse a hardcoded default — pick free instead.

use strict;
use warnings;
use IO::Socket::INET ();

our $VERSION = '0.01';

sub pick_free_port {
    my ($host) = @_;
    $host = '127.0.0.1' unless defined $host;
    my $s = IO::Socket::INET->new(
        LocalAddr => $host,
        LocalPort => 0,
        Listen    => 1,
        ReuseAddr => 1,
    ) or die "PortPicker: failed to bind $host:0: $!";
    my $port = $s->sockport;
    $s->close;
    return $port;
}

1;
