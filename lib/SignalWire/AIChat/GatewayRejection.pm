package SignalWire::AIChat::GatewayRejection;

# Copyright (c) 2026 SignalWire
# Licensed under the MIT License.
#
# A request the gateway refused, with the status the browser should see.
# Mirrors signalwire.ai_chat.gateway.GatewayRejection. Deliberately coarse: the
# browser is told THAT it was refused and, at most, which of a handful of
# buckets it fell into -- anything finer would let a caller map out the caps and
# the allowlist by probing.

use strict;
use warnings;
use Moo;

# HTTP status to send back (401 bad key, 403 origin/handle, 400 disallowed
# method, 413 over a size limit, 429 a cap was hit).
has 'status' => ( is => 'ro', required => 1 );

# Short, fixed explanation; it reaches the browser.
has 'reason' => ( is => 'ro', required => 1 );

# Positional shorthand, as the reference constructs it: ->new(403, 'invalid handle').
around BUILDARGS => sub {
    my ( $orig, $class, @args ) = @_;
    if ( @args == 2 && defined $args[0] && $args[0] =~ /\A\d+\z/ ) {
        return $class->$orig( status => $args[0], reason => $args[1] );
    }
    return $class->$orig(@args);
};

use overload
    '""'     => sub { my ($self) = @_; $self->status . ': ' . $self->reason },
    'bool'   => sub { 1 },
    fallback => 1;

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::AIChat::GatewayRejection - a browser request the chat gateway refused

=head1 SYNOPSIS

    my $id = eval { $gateway->read_handle($handle) };
    if ( my $rej = $@ ) {
        die $rej unless ref $rej && $rej->isa('SignalWire::AIChat::GatewayRejection');
        return [ $rej->status, [], [ $rej->reason ] ];
    }

=head1 DESCRIPTION

Raised (via C<die>) by L<SignalWire::AIChat::Gateway> for a request it refuses.
Stringifies as C<"status: reason">.

=head1 ATTRIBUTES

=over 4

=item C<status>

The HTTP status the route should return: 401 bad key, 403 origin or handle,
400 a disallowed method or malformed input, 413 a request, message or metadata
over its size limit, 429 a cap was hit.

=item C<reason>

A short, fixed explanation that reaches the browser -- for a handle,
C<malformed handle>, C<invalid handle> or C<expired handle>; never the caps'
values or the allowlist.

=back

=head1 CONSTRUCTION

C<< ->new(status => 403, reason => 'invalid handle') >> or the positional
C<< ->new(403, 'invalid handle') >>.

=head1 LICENSE

Copyright (c) 2026 SignalWire. Licensed under the MIT License.

=cut
