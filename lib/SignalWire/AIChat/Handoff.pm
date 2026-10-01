package SignalWire::AIChat::Handoff;

# Copyright (c) 2026 SignalWire
# Licensed under the MIT License.
#
# Moving one conversation between voice and text. Mirrors
# signalwire.ai_chat.handoff.HandoffRouter: the three routes a browser client
# calls beside a ChatGateway -- /handoff (voice -> text), /escalate (text ->
# voice) and /say (type into a live call). The SignalWire address widget derives
# all three from the same URL as the gateway's JSON-RPC endpoint.
#
# MECHANISM VS POLICY: this owns the wire contract only (routes, nonce, ordering
# guarantee, spend guards). What a conversation IS -- where a leg's record is
# written, what a resumed greeting says -- is the application's, injected as
# callbacks.
#
# THE NONCE: a browser cannot be trusted to name a call, so the application
# puts a random handoff_nonce in the user variables of one dial, registers it
# here against that call's ids, and the browser presents it later. The first
# registration stands; redemption is single use; typing is repeatable up to
# max_messages_per_call until the nonce is redeemed or nonce_ttl passes. An
# unknown nonce is answered exactly like an expired or redeemed one.
#
# THE ORDERING GUARANTEE: a medium never starts until the one it replaces has
# finished and its record is durable -- /handoff ends the call and waits for
# capture_leg before minting a handle; /escalate waits before returning. The
# wait is bounded by capture_timeout.
#
# DEPLOYMENT: the nonce table lives in this process. A redemption must reach the
# process that served the dial: run one, use sticky routing, or supply a shared
# `registry` (a hashref; a redemption is stored by assigning the entry back).
# A Perl PSGI worker handles one request at a time, so within one router the
# read-modify-write steps cannot interleave; across processes sharing a
# registry they can.

use strict;
use warnings;
use Moo;

use Encode       ();
use JSON         ();
use Scalar::Util qw(blessed);
use Time::HiRes  ();

use SignalWire::AIChat::Gateway;
use SignalWire::AIChat::GatewayRejection;
use SignalWire::AIChat::NonceEntry;
use SignalWire::Logging;

use constant DEFAULT_NONCE_TTL             => 3600;
use constant DEFAULT_MAX_MESSAGES_PER_CALL => 200;
use constant DEFAULT_CAPTURE_TIMEOUT       => 8.0;

my $TIMEOUT_SENTINEL = "__signalwire_handoff_capture_timeout__\n";

# The gateway that owns the conversations: mints handles and checks origins.
has 'gateway' => ( is => 'ro', required => 1 );

# capture_leg->($conversation_id, $medium): end a leg and write its record;
# return true only once that record is durable. Omitted: no wait happens and
# the ordering guarantee is not provided.
has 'capture_leg' => ( is => 'ro', default => sub { undef } );

# end_call->($call_id): hang the call up server-side.
has 'end_call' => ( is => 'ro', default => sub { undef } );

# send_message->($call_id, $text): inject typed text into the live call.
# Omitted: typing is disabled (/say answers 404).
has 'send_message' => ( is => 'ro', default => sub { undef } );

# next_conversation_id->($conversation_id): the id for the NEW leg (an ended
# conversation cannot be reopened). Defaults to appending/incrementing ".N".
has 'next_conversation_id' => ( is => 'ro', default => sub { \&_default_next_id } );

has 'nonce_ttl'             => ( is => 'ro', default => sub { DEFAULT_NONCE_TTL } );
has 'max_messages_per_call' => ( is => 'ro', default => sub { DEFAULT_MAX_MESSAGES_PER_CALL } );
has 'capture_timeout'       => ( is => 'ro', default => sub { DEFAULT_CAPTURE_TIMEOUT } );

# The nonce table: a shared hashref of nonce => SignalWire::AIChat::NonceEntry,
# or a private one.
has '_nonces' => ( is => 'ro', init_arg => 'registry', default => sub { {} } );

has '_log' => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { SignalWire::Logging->get_logger('signalwire.ai_chat.handoff') },
);

# ── Nonce lifecycle ──────────────────────────────────────────────────

# root -> root.1; root.2 -> root.3. "." specifically: the chat service strips
# "~", "_" and "-" occur inside generated ids, and ":" is the handle delimiter.
sub _default_next_id {
    my ($conversation_id) = @_;
    my ( $root, $tail ) = $conversation_id =~ /\A(.*)\.([^.]*)\z/s;
    return "$root." . ( $tail + 1 ) if defined $root && length $root && $tail =~ /\A[0-9]+\z/;
    return "$conversation_id.1";
}

# Record what a nonce is a capability for. Call it from the per-call config
# callback of the dial that carried the nonce, reading call_id from the request
# the PLATFORM sent -- never from anything the browser supplied. The first
# registration stands: re-registering changes nothing (a conflicting one, or one
# for a redeemed nonce, is logged as a warning). Once nonce_ttl has passed the
# nonce can be registered again.
sub register {
    my ( $self, $nonce, %opts ) = @_;
    return if !defined $nonce || ref $nonce || !length $nonce;
    my $conversation_id = $opts{conversation_id};
    my $call_id         = $opts{call_id};

    $self->_prune;
    my $existing = $self->_nonces->{$nonce};
    if ( !$existing ) {
        $self->_nonces->{$nonce} = SignalWire::AIChat::NonceEntry->new(
            conversation_id => $conversation_id,
            call_id         => $call_id,
        );
        $self->_log->info( 'handoff_nonce_registered conversation_id='
                . ( $conversation_id // '' )
                . ' call_id='
                . ( $call_id // '' ) );
        return;
    }
    if (   $existing->redeemed
        || !_same( $existing->conversation_id, $conversation_id )
        || !_same( $existing->call_id,         $call_id ) )
    {
        $self->_log->warn( 'handoff_nonce_already_registered conversation_id='
                . ( $existing->conversation_id // '' )
                . ' call_id='
                . ( $existing->call_id // '' )
                . ' redeemed='
                . ( $existing->redeemed ? 'true' : 'false' ) );
    }
    return;
}

# Exchange a nonce for a chat handle. Single use: ends the call, waits for its
# record, and only then mints a handle for a new leg of the same conversation.
# Returns the signed handle, or undef for an unknown, expired or already
# redeemed nonce -- deliberately indistinguishable.
sub redeem {
    my ( $self, $nonce ) = @_;
    my $entry = $self->_lookup($nonce) or return;

    # Consumed even if what follows fails: a nonce is one attempt. Written back
    # so a shared registry stores the change.
    $entry->redeemed(1);
    $self->_nonces->{$nonce} = $entry;

    if ( defined $entry->call_id && length $entry->call_id && $self->end_call ) {
        eval { $self->end_call->( $entry->call_id ); 1 } or do {
            my $err = _one_line($@);
            $self->_log->warn("handoff_end_call_failed error=$err");
        };
    }

    $self->_capture( $entry->conversation_id, 'voice' );

    my $handle = eval {
        $self->gateway->mint_handle( $self->next_conversation_id->( $entry->conversation_id ) );
    };
    if ( !defined $handle ) {
        my $err = _one_line($@);
        $self->_log->error("handoff_mint_failed error=$err");
        return;
    }
    $self->_log->info( 'handoff_redeemed conversation_id=' . $entry->conversation_id );
    return $handle;
}

# End a chat leg and wait for its record, before a call is placed: a voice leg
# started afterwards is guaranteed to find the text leg recorded. Returns 1, or
# 0 for a handle the gateway does not accept.
sub escalate {
    my ( $self, $handle ) = @_;
    my $conversation_id = eval { $self->gateway->read_handle($handle) };
    return 0 unless defined $conversation_id;
    $self->_capture( $conversation_id, 'chat' );
    $self->_log->info("handoff_escalated conversation_id=$conversation_id");
    return 1;
}

# Deliver typed text into the live call the nonce names. Does NOT consume the
# nonce; bounded by max_messages_per_call. Text is trimmed; blank text, or text
# over the gateway's MAX_MESSAGE_BYTES (UTF-8), is refused. Returns 1 when
# delivered, 0 otherwise.
sub say {
    my ( $self, $nonce, $text ) = @_;
    return 0 unless $self->send_message;
    my $cleaned = defined $text && !ref $text ? $text : '';
    $cleaned =~ s/\A\s+//;
    $cleaned =~ s/\s+\z//;
    return 0
        if !length $cleaned
        || length( Encode::encode( 'UTF-8', $cleaned ) ) >
        SignalWire::AIChat::Gateway::MAX_MESSAGE_BYTES;

    my $entry = $self->_lookup($nonce);
    return 0 if !$entry || !defined $entry->call_id || !length $entry->call_id;
    if ( $entry->messages >= $self->max_messages_per_call ) {
        $self->_log->warn( 'handoff_say_cap_reached call_id=' . $entry->call_id );
        return 0;
    }

    # Take the message's slot before delivering. Written back so a shared
    # registry stores the change.
    $entry->messages( $entry->messages + 1 );
    $self->_nonces->{$nonce} = $entry;

    my $ok = eval { $self->send_message->( $entry->call_id, $cleaned ); 1 };
    return 1 if $ok;

    my $err = _one_line($@);
    $self->_log->error("handoff_say_failed error=$err");

    # Not delivered: give the slot back, if the table still holds this
    # registration (matched by value: a shared registry may hand back a copy).
    my $current = $self->_nonces->{$nonce};
    if (   $current
        && $current->messages > 0
        && _same( $current->conversation_id, $entry->conversation_id )
        && _same( $current->call_id,         $entry->call_id )
        && $current->issued_at == $entry->issued_at )
    {
        $current->messages( $current->messages - 1 );
        $self->_nonces->{$nonce} = $current;
    }
    return 0;
}

# ── PSGI surface ─────────────────────────────────────────────────────

# A PSGI app with the three POST routes. Mount it at the SAME prefix as the
# gateway's router, since the browser derives all three paths from one URL:
#
#   $agent->mount( $gateway->router, prefix => '/chat' );
#   $agent->mount( $handoff->router, prefix => '/chat' );
#
# Every route answers 403 for a disallowed Origin and 413 for a body over the
# gateway's MAX_REQUEST_BODY_BYTES; /say also 413 for text over
# MAX_MESSAGE_BYTES -- both checked before the nonce is looked up.
sub router {
    my ($self) = @_;
    my $router = $self;

    my %routes = (
        '/handoff' => sub {
            my ($data) = @_;
            my $nonce = $data->{nonce};
            return _json( 404, { error => 'not found' } ) if !defined $nonce || ref $nonce;
            my $handle = $router->redeem($nonce);

            # Same answer for unknown, expired and already-redeemed.
            return _json( 404, { error  => 'not found' } ) unless $handle;
            return _json( 200, { handle => $handle } );
        },
        '/escalate' => sub {
            my ($data) = @_;
            my $handle = $data->{handle};
            return _json( 400, { error => 'bad request' } )
                if !defined $handle || ref $handle || !length $handle;
            return _json( 404, { error => 'not found' } ) unless $router->escalate($handle);
            return _json( 200, { ok    => JSON::true() } );
        },
        '/say' => sub {
            my ($data) = @_;
            my $nonce  = $data->{nonce};
            my $text   = exists $data->{text} ? $data->{text} : '';
            return _json( 404, { error => 'not found' } )
                if !defined $nonce || ref $nonce || !defined $text || ref $text;
            return _json( 413, { error => 'message too large' } )
                if length( Encode::encode( 'UTF-8', $text ) ) >
                SignalWire::AIChat::Gateway::MAX_MESSAGE_BYTES;
            return _json( 404, { error => 'not found' } ) unless $router->say( $nonce, $text );
            return _json( 200, { ok    => JSON::true() } );
        },
    );

    return sub {
        my ($env) = @_;
        my $path  = defined $env->{PATH_INFO} ? $env->{PATH_INFO} : '';
        my $route = $routes{$path};
        return _json( 404, { detail => 'Not Found' } ) unless $route;
        return _json( 405, { detail => 'Method Not Allowed' } )
            unless ( $env->{REQUEST_METHOD} // '' ) eq 'POST';

        return _json( 403, { error => 'origin not allowed' } )
            unless eval { $router->gateway->check_origin( $env->{HTTP_ORIGIN} ); 1 };

        my $data = eval { SignalWire::AIChat::Gateway::_read_json_body($env) };
        if ( my $err = $@ ) {
            return _json( $err->status, { error => $err->reason } )
                if blessed($err) && $err->isa('SignalWire::AIChat::GatewayRejection');
            $data = {};
        }
        $data = {} unless ref $data eq 'HASH';
        return $route->($data);
    };
}

# ── Internals ────────────────────────────────────────────────────────

# Drop entries, redeemed ones included, whose TTL has passed.
sub _prune {
    my ($self) = @_;
    my $cutoff = SignalWire::AIChat::NonceEntry::_monotonic() - $self->nonce_ttl;
    my $table  = $self->_nonces;
    for my $nonce ( keys %$table ) {
        delete $table->{$nonce} if $table->{$nonce}->issued_at < $cutoff;
    }
    return;
}

# The live entry for $nonce: undef if unknown, expired or redeemed.
sub _lookup {
    my ( $self, $nonce ) = @_;
    return if !defined $nonce || ref $nonce || !length $nonce;
    $self->_prune;
    my $entry = $self->_nonces->{$nonce};
    return if !$entry || $entry->redeemed;
    return $entry;
}

# Run the application's capture, bounded by capture_timeout. Never dies;
# returns true only when capture_leg reported the record durable.
sub _capture {
    my ( $self, $conversation_id, $medium ) = @_;
    return 0 unless $self->capture_leg;
    my $result;
    my $ok = eval {
        $result = _with_timeout( $self->capture_timeout,
            sub { $self->capture_leg->( $conversation_id, $medium ) } );
        1;
    };
    return $result ? 1 : 0 if $ok;

    my $err = $@;
    if ( defined $err && $err eq $TIMEOUT_SENTINEL ) {
        $self->_log->warn(
                  "handoff_capture_timeout conversation_id=$conversation_id medium=$medium "
                . 'note="starting the next medium without this leg\'s record"' );
    } else {
        $self->_log->error(
            "handoff_capture_failed conversation_id=$conversation_id error=" . _one_line($err) );
    }
    return 0;
}

# Call $code, dying with $TIMEOUT_SENTINEL if it runs past $seconds (a SIGALRM
# ceiling; Time::HiRes allows fractional seconds). An outer alarm is restored.
sub _with_timeout {
    my ( $seconds, $code ) = @_;
    return $code->() unless $seconds && $seconds > 0;

    my $started = Time::HiRes::time();
    my ( $result, $ok, $err );
    {
        local $SIG{ALRM} = sub { die $TIMEOUT_SENTINEL };
        my $outer = Time::HiRes::alarm($seconds);
        $ok  = eval { $result = $code->(); 1 };
        $err = $@;
        Time::HiRes::alarm(0);
        if ( $outer && $outer > 0 ) {
            my $left = $outer - ( Time::HiRes::time() - $started );
            Time::HiRes::alarm( $left > 0 ? $left : 0.001 );
        }
    }
    die $err unless $ok;
    return $result;
}

sub _same {
    my ( $lhs, $rhs ) = @_;
    return 1 if !defined $lhs && !defined $rhs;
    return 0 if !defined $lhs || !defined $rhs;
    return $lhs eq $rhs ? 1 : 0;
}

sub _one_line {
    my ($err) = @_;
    $err = 'unknown error' unless defined $err && length $err;
    $err = "$err";
    $err =~ s/\s+\z//;
    $err =~ s/\n/ /g;
    return $err;
}

sub _json {
    my ( $status, $data ) = @_;
    return [ $status, [ 'Content-Type' => 'application/json' ], [ JSON::encode_json($data) ] ];
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::AIChat::Handoff - move one AI conversation between voice and text (HandoffRouter)

=head1 SYNOPSIS

    use SignalWire::AIChat::Gateway;
    use SignalWire::AIChat::Handoff;

    my $gateway = SignalWire::AIChat::Gateway->new( config_url => $SWML_URL );
    my $handoff = SignalWire::AIChat::Handoff->new(
        gateway      => $gateway,
        capture_leg  => sub { my ( $conversation_id, $medium ) = @_; store_leg(...); 1 },
        end_call     => sub { my ($call_id) = @_; hang_up($call_id) },
        send_message => sub { my ( $call_id, $text ) = @_; inject($call_id, $text) },
    );

    # Register the nonce the browser put in the dial's user variables, from
    # the per-call config callback (call_id from the PLATFORM's request):
    $agent->add_per_call_config( sub {
        my ( $query, $body, $headers, $ephemeral ) = @_;
        my $vars = SignalWire::Core::Capabilities::user_variables($body);
        $handoff->register( $vars->{handoff_nonce},
            conversation_id => $vars->{conversation_id}, call_id => $body->{call_id} )
            if $vars->{handoff_nonce};
    } );

    $agent->mount( $gateway->router, prefix => '/chat' );
    $agent->mount( $handoff->router, prefix => '/chat' );

=head1 DESCRIPTION

The other half of what a browser client needs beside a
L<SignalWire::AIChat::Gateway>: C</handoff> (redeem a nonce for a chat handle,
voice to text), C</escalate> (end a chat leg before a call is placed) and
C</say> (type into a live call). It owns the wire contract -- routes, the
nonce, the ordering guarantee, the spend guards -- and nothing about what a
conversation is: that policy is injected as callbacks.

A browser proves which call it is on with a C<handoff_nonce> the application
put in that dial's user variables and registered here; the first registration
stands, redemption is single use, and typing is repeatable up to
C<max_messages_per_call> until the nonce is redeemed or C<nonce_ttl> passes. A
medium never starts until the one it replaces is recorded: C</handoff> ends the
call and waits (bounded by C<capture_timeout>) for C<capture_leg> before
minting a handle.

The nonce table lives in this process (or a shared C<registry> hashref).

=head1 CONSTRUCTION

C<< ->new(gateway => $gateway, %opts) >> with the optional C<capture_leg>,
C<end_call>, C<send_message>, C<next_conversation_id> (coderefs), C<nonce_ttl>
(3600), C<max_messages_per_call> (200), C<capture_timeout> (8.0 seconds) and
C<registry> (a shared hashref of nonce =E<gt> L<SignalWire::AIChat::NonceEntry>).

=head1 ATTRIBUTES

C<gateway>, C<capture_leg>, C<end_call>, C<send_message>,
C<next_conversation_id>, C<nonce_ttl>, C<max_messages_per_call>,
C<capture_timeout> -- read-only.

=head1 METHODS

=over 4

=item C<register($nonce, conversation_id =E<gt> $id, call_id =E<gt> $call_id)>

Record what a nonce is a capability for. The first registration stands.

=item C<redeem($nonce)>

Exchange a nonce for a chat handle (single use). Ends the call, waits for its
record, mints a handle for the next leg. Undef for an unknown, expired or
redeemed nonce.

=item C<escalate($handle)>

End a chat leg and wait for its record. 1, or 0 for a handle the gateway does
not accept.

=item C<say($nonce, $text)>

Deliver typed text into the call the nonce names. 1 when delivered, 0
otherwise.

=item C<router>

A PSGI app with the C<POST /handoff>, C</escalate> and C</say> routes. Mount it
at the same prefix as the gateway's router.

=back

=head1 SEE ALSO

L<SignalWire::AIChat::Gateway>, L<SignalWire::AIChat::NonceEntry>.

=head1 LICENSE

Copyright (c) 2026 SignalWire. Licensed under the MIT License.

=cut
