package SignalWire::AIChat::NonceEntry;

# Copyright (c) 2026 SignalWire
# Licensed under the MIT License.
#
# What a handoff nonce is a capability for. Mirrors the dataclass
# signalwire.ai_chat.handoff.NonceEntry. `redeemed` marks a nonce /handoff has
# exchanged for a handle; the entry is kept until its TTL passes, so the nonce
# can be neither redeemed nor registered again.

use strict;
use warnings;
use Moo;

use Time::HiRes ();

has 'conversation_id' => ( is => 'rw', required => 1 );
has 'call_id'         => ( is => 'rw', default  => sub { undef } );
has 'issued_at'       => ( is => 'rw', default  => sub { _monotonic() } );
has 'messages'        => ( is => 'rw', default  => sub { 0 } );
has 'redeemed'        => ( is => 'rw', default  => sub { 0 } );

sub _monotonic {
    my $t = eval { Time::HiRes::clock_gettime( Time::HiRes::CLOCK_MONOTONIC() ) };
    return defined $t ? $t : Time::HiRes::time();
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::AIChat::NonceEntry - what a voice/text handoff nonce is a capability for

=head1 DESCRIPTION

One entry of a L<SignalWire::AIChat::Handoff> nonce table.

=head1 ATTRIBUTES

=over 4

=item C<conversation_id>

The conversation the nonce's call belongs to (required).

=item C<call_id>

The call the nonce was registered for, when known.

=item C<issued_at>

Monotonic time of the first registration (defaults to now).

=item C<messages>

Typed messages delivered into the call so far (default 0).

=item C<redeemed>

True once C</handoff> exchanged the nonce for a handle (default false).

=back

All are read-write (the table updates entries in place and writes them back).

=head1 LICENSE

Copyright (c) 2026 SignalWire. Licensed under the MIT License.

=cut
