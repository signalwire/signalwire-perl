package SignalWire::AIChat::Error;
use strict;
use warnings;
use Moo;

# ── Base error ───────────────────────────────────────────────────────
#
# SignalWire::AIChat::Error is the base of the AI Chat typed error family (the
# Perl analog of signalwire.ai_chat.AIChatError). Every failure of the AI Chat
# service is raised via die() as a member of this family, so a caller catching the
# base class handles every AI-Chat failure with one eval and can branch on ->code
# or the subclass type.
#
# `code` is the JSON-RPC error code (undef when the failure rode the success
# envelope, as with SummaryError). `message` is the server-provided message.

has 'code'    => ( is => 'ro', default => sub { undef } );
has 'message' => ( is => 'ro', default => sub { '' } );

use overload
    '""' => sub {
    my ($self) = @_;
    '[' . ( defined $self->code ? $self->code : '' ) . '] ' . ( $self->message // '' );
    },
    'bool'   => sub { 1 },
    fallback => 1;

# ── Typed subclasses ─────────────────────────────────────────────────

package SignalWire::AIChat::AuthenticationError;    ## no critic (ProhibitMultiplePackages)
use Moo;
extends 'SignalWire::AIChat::Error';

package SignalWire::AIChat::ConversationNotFoundError;    ## no critic (ProhibitMultiplePackages)
use Moo;
extends 'SignalWire::AIChat::Error';

package SignalWire::AIChat::RateLimitError;               ## no critic (ProhibitMultiplePackages)
use Moo;
extends 'SignalWire::AIChat::Error';

package SignalWire::AIChat::ChatInProgressError;          ## no critic (ProhibitMultiplePackages)
use Moo;
extends 'SignalWire::AIChat::Error';

package SignalWire::AIChat::SummaryError;                 ## no critic (ProhibitMultiplePackages)
use Moo;
extends 'SignalWire::AIChat::Error';

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::AIChat::Error - typed error family for the AI Chat client

=head1 SYNOPSIS

    use SignalWire::AIChat::Client;

    my $reply = eval { $client->chat( 'conv-1', 'hi' ) };
    if ( my $err = $@ ) {
        if ( ref $err && $err->isa('SignalWire::AIChat::Error') ) {
            warn "AI Chat failed [", ( $err->code // 'no-code' ), "]: ", $err->message;
        }
    }

=head1 DESCRIPTION

The AI Chat client raises a typed error family (the Perl analog of
C<signalwire.ai_chat>). A caller catching the base class
L<SignalWire::AIChat::Error> handles every AI-Chat failure with one C<eval>.

=head2 SignalWire::AIChat::Error

The base class. Read-only accessors:

=over 4

=item C<code>

The JSON-RPC error code (e.g. C<-32001>), or C<undef> when the failure rode the
JSON-RPC B<success> envelope (as with L</SignalWire::AIChat::SummaryError>).

=item C<message>

The server-provided error message.

=back

Instances stringify (C<use overload '""'>) to C<< [code] message >>.

=head2 Subclasses

=over 4

=item SignalWire::AIChat::AuthenticationError

Missing/rejected identity (HTTP 401 / JSON-RPC C<-32009>).

=item SignalWire::AIChat::ConversationNotFoundError

The conversation does not exist in this project (C<-32001>).

=item SignalWire::AIChat::RateLimitError

Project or conversation rate limit hit (C<-32005> / C<-32006>).

=item SignalWire::AIChat::ChatInProgressError

Another message is being processed for this conversation (C<-32007>).

=item SignalWire::AIChat::SummaryError

Summary generation failed. C<summarize> returns EXACTLY ONE of C<{summary}>
(success) or C<{error}> (generation failed), and the failure rides the JSON-RPC
B<success> envelope -- not an C<error> object -- so it never reaches the
error-code mapping. Surfaced here so a failed summary can't masquerade as an
empty string. C<code> is C<undef> (no JSON-RPC code).

=back

An unmapped JSON-RPC code falls back to the base
C<SignalWire::AIChat::Error> carrying that code.

=head1 SEE ALSO

L<SignalWire::AIChat::Client>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
