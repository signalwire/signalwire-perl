package SignalWire::AIChat::Gateway;

# Copyright (c) 2026 SignalWire
# Licensed under the MIT License.
#
# A browser-facing gateway for the SignalWire AI Chat service. Mirrors
# signalwire.ai_chat.gateway.ChatGateway.
#
# A chat widget running in a page cannot hold a SignalWire API token -- the
# token carries the whole project, and every turn bills. So the widget talks to
# a gateway mounted in your own app, which holds the credential server-side and
# forwards on the widget's behalf:
#
#   browser --(publishable key)--> your app --(project:token)--> chat service
#
# The browser learns two things: the gateway's URL and a publishable key. The
# gateway injects config_url itself, so a key only ever reaches the one agent it
# was issued for. Conversation handles are HMAC-signed, so ids cannot be guessed
# or enumerated; the caps (max_new_conversations, max_turns) bound what a
# leaked key can cost; the origin allowlist is leak containment, not access
# control. Every browser-sized field is bounded and answered 413 past its limit.

use strict;
use warnings;
use Moo;
use feature 'signatures';

use B            ();
use Digest::SHA  qw(hmac_sha256);
use Encode       ();
use JSON         ();
use MIME::Base64 ();
use Scalar::Util qw(blessed);
use Time::HiRes  ();
use URI          ();

use SignalWire::AIChat::Client;
use SignalWire::AIChat::GatewayRejection;
use SignalWire::Core::Random ();

# A handle outlives a page refresh but not a session left open overnight.
use constant DEFAULT_HANDLE_TTL => 24 * 60 * 60;

# The chat service's own default conversation timeout -- what the gateway
# reports when it has not been given one.
use constant SERVICE_DEFAULT_CONVERSATION_TIMEOUT => 3600;

# Caps chosen to be invisible to a real conversation and ruinous to a script.
use constant DEFAULT_MAX_NEW_CONVERSATIONS => 60;     # per window, per gateway
use constant DEFAULT_MAX_TURNS             => 200;    # per conversation, ever
use constant DEFAULT_WINDOW_SECONDS        => 60;

# Bounds on what whoever holds the key can size: the volunteered metadata bag
# (serialized), one typed message (UTF-8), and a whole request body.
use constant MAX_USER_METADATA_BYTES => 8 * 1024;
use constant MAX_MESSAGE_BYTES       => 8 * 1024;
use constant MAX_REQUEST_BODY_BYTES  => 64 * 1024;

my %LOCAL_HOSTS     = map { $_ => 1 } ( 'localhost', '127.0.0.1', '::1', '[::1]' );
my %ALLOWED_METHODS = map { $_ => 1 } qw(start chat log end);

# Roles a browser may see: the service's chat_log also holds the substituted
# system prompt and tool traffic, which are nobody's business.
my %VISIBLE_ROLES = map { $_ => 1 } qw(user assistant);

my $JSON = JSON->new->utf8->canonical;

# ── Attributes ───────────────────────────────────────────────────────

# The agent this key may talk to. Injected on every call, never taken from the
# request.
has 'config_url' => ( is => 'ro', required => 1 );

# The publishable key the widget carries.
has 'key' => (
    is      => 'ro',
    default => sub {
        my $env = $ENV{SIGNALWIRE_CHAT_GATEWAY_KEY};
        return ( defined $env && length $env )
            ? $env
            : 'pk_' . SignalWire::Core::Random::_random_urlsafe(24);
    },
);

# Origins permitted to use this key (trailing slash stripped). Localhost is
# always allowed; anything else must be listed.
has 'allowed_origins' => (
    is     => 'ro',
    coerce => sub {
        my ($origins) = @_;
        my %seen;
        my @out = grep { !$seen{$_}++ }
            map { ( my $o = $_ ) =~ s{/+\z}{}; $o } grep { defined } @{ $origins // [] };
        return [ sort @out ];
    },
    default => sub { [] },
);

has 'handle_ttl'            => ( is => 'ro', default => sub { DEFAULT_HANDLE_TTL } );
has 'conversation_timeout'  => ( is => 'ro', default => sub { undef } );
has 'max_new_conversations' => ( is => 'ro', default => sub { DEFAULT_MAX_NEW_CONVERSATIONS } );
has 'max_turns'             => ( is => 'ro', default => sub { DEFAULT_MAX_TURNS } );
has 'window_seconds'        => ( is => 'ro', default => sub { DEFAULT_WINDOW_SECONDS } );

# An AIChat client to reuse; omitted, the gateway builds (and owns) its own from
# the ambient credentials.
has '_client'      => ( is => 'rw', init_arg => 'client', default => sub { undef } );
has '_owns_client' => ( is => 'rw', init_arg => undef,    default => sub { 0 } );

# HMAC key for signing conversation handles. Random per process when omitted,
# so handles stop verifying across a restart or a second worker -- set it (or
# SIGNALWIRE_CHAT_GATEWAY_SECRET) in production.
has '_secret' => ( is => 'rw', init_arg => 'secret', default => sub { undef } );

has '_mints' => ( is => 'rw', init_arg => undef, default => sub { [] } );
has '_turns' => ( is => 'rw', init_arg => undef, default => sub { {} } );

sub BUILD {
    my ($self) = @_;
    die "config_url is required \x{2014} it is what a key is scoped to.\n"
        unless defined $self->config_url && length $self->config_url;

    if ( !defined $self->_client ) {
        $self->_client( SignalWire::AIChat::Client->new );
        $self->_owns_client(1);
    }

    my $secret = $self->_secret;
    if ( !defined $secret ) {
        my $env = $ENV{SIGNALWIRE_CHAT_GATEWAY_SECRET};
        $secret =
            ( defined $env && length $env ) ? $env : SignalWire::Core::Random::_random_bytes(32);
    }
    $secret = Encode::encode( 'UTF-8', $secret ) if utf8::is_utf8($secret);
    $self->_secret($secret);
    return;
}

# ── Static helpers ───────────────────────────────────────────────────

# Epoch SECONDS of the newest message, or undef if nothing is dated. The service
# stamps messages in MICROseconds; every role counts (the service's idle clock
# runs off any write).
sub last_activity {
    my ( $class_or_self, $messages ) = @_;
    my $newest;
    for my $msg ( @{ ref $messages eq 'ARRAY' ? $messages : [] } ) {
        next unless ref $msg eq 'HASH';
        my $ts = $msg->{timestamp};
        $newest = $ts if _is_int($ts) && $ts > 0 && ( !defined $newest || $ts > $newest );
    }
    return defined $newest ? $newest / 1_000_000 : undef;
}

# The transcript a browser may redraw: user and assistant turns with text,
# reduced to role, content and (epoch-seconds) timestamp.
sub visible_messages {
    my ( $class_or_self, $messages ) = @_;
    my @out;
    for my $msg ( @{ ref $messages eq 'ARRAY' ? $messages : [] } ) {
        next unless ref $msg eq 'HASH';
        my ( $role, $content ) = @{$msg}{qw(role content)};
        next unless defined $role    && !ref $role    && $VISIBLE_ROLES{$role};
        next unless defined $content && !ref $content && $content =~ /\S/;
        my %entry = ( role => $role, content => $content );
        my $ts    = $msg->{timestamp};
        $entry{timestamp} = $ts / 1_000_000 if _is_int($ts) && $ts > 0;
        push @out, \%entry;
    }
    return \@out;
}

# Idle seconds a conversation actually gets: conversation_timeout, else the
# service's documented default -- never undef, so a widget can always warn.
sub effective_timeout {
    my ($self) = @_;
    return $self->conversation_timeout || SERVICE_DEFAULT_CONVERSATION_TIMEOUT;
}

# Release the upstream client, if this gateway built it. A client passed in via
# `client` belongs to the caller and is left open.
sub close {    ## no critic (ProhibitBuiltinHomonyms)
    my ($self) = @_;
    $self->_client->close if $self->_owns_client;
    return;
}

# ── Handles ──────────────────────────────────────────────────────────

# Issue a signed handle for a (new) conversation. The browser never names a
# conversation; it can only present handles this gateway issued.
sub mint_handle ( $self, $conversation_id = undef ) {
    $conversation_id = 'chat-' . SignalWire::Core::Random::_random_urlsafe(18)
        unless defined $conversation_id && length $conversation_id;
    my $expires = int( Time::HiRes::time() ) + $self->handle_ttl;
    my $payload = Encode::encode( 'UTF-8', "$conversation_id:$expires" );
    my $sig     = hmac_sha256( $payload, $self->_secret );
    return _b64($payload) . '.' . _b64($sig);
}

# The conversation id inside a handle, or die with a GatewayRejection: 400
# "malformed handle", 403 "invalid handle" (signature) or 403 "expired handle".
# Signature first, expiry second, both before the id is trusted.
sub read_handle {
    my ( $self, $handle ) = @_;
    _reject( 400, 'malformed handle' )
        if !defined $handle || ref $handle || index( $handle, '.' ) < 0;
    my ( $raw, $sig ) = split /\./, $handle, 2;
    my $payload = _unb64($raw) // _reject( 400, 'malformed handle' );
    my $given   = _unb64($sig) // _reject( 400, 'malformed handle' );

    my $expected = hmac_sha256( $payload, $self->_secret );
    _reject( 403, 'invalid handle' ) unless _constant_time_eq( $given, $expected );

    my $text = eval { Encode::decode( 'UTF-8', $payload, Encode::FB_CROAK() ) };
    _reject( 400, 'malformed handle' ) unless defined $text;
    my ( $conversation_id, $expires ) = $text =~ /\A(.*):([^:]*)\z/s;
    _reject( 400, 'malformed handle' )
        unless defined $expires && $expires =~ /\A\s*[+-]?\d+\s*\z/;
    _reject( 403, 'expired handle' ) if Time::HiRes::time() > $expires;
    return $conversation_id;
}

# ── Guards ───────────────────────────────────────────────────────────

# Localhost always; anything else must be listed. A missing Origin is allowed:
# browsers always send one for these cross-origin POSTs, so absence means a
# non-browser caller -- and refusing those would stop nothing.
sub check_origin {
    my ( $self, $origin ) = @_;
    return unless defined $origin;
    my $host =
        eval { my $u = URI->new($origin); $u->can('host') ? lc( $u->host // '' ) : '' } // '';
    return if $LOCAL_HOSTS{$host} || $host =~ /\.localhost\z/;
    ( my $clean = $origin ) =~ s{/+\z}{};
    return if grep { $_ eq $clean } @{ $self->allowed_origins };
    _reject( 403, 'origin not allowed' );
    return;
}

# Verify the publishable key the browser sent (constant-time). 401 when missing
# or wrong.
sub check_key {
    my ( $self, $presented ) = @_;
    _reject( 401, 'bad key' )
        if !defined $presented
        || ref $presented
        || !length $presented
        || !_constant_time_eq( $presented, $self->key );
    return;
}

# ── The proxied call ─────────────────────────────────────────────────

# Validate the page context a browser volunteered (user_meta_data): undef for
# absent/null/empty, 400 when not an object or not serializable, 413 over
# MAX_USER_METADATA_BYTES serialized.
sub read_user_metadata {
    my ( $self, $body ) = @_;
    my $raw = ref $body eq 'HASH' ? $body->{user_meta_data} : undef;
    return                                             unless defined $raw;
    _reject( 400, 'user_meta_data must be an object' ) unless ref $raw eq 'HASH';
    return                                             unless %$raw;
    my $encoded = eval { JSON->new->ascii->encode($raw) };
    _reject( 400, 'user_meta_data must be JSON-serializable' ) unless defined $encoded;
    _reject( 413, 'user_meta_data too large' ) if length($encoded) > MAX_USER_METADATA_BYTES;
    return $raw;
}

# Validate a browser request and build the upstream JSON-RPC call. Returns
# ($method, \%params, $minted_handle); $minted_handle is set only on the call
# that created the conversation. Dies with a GatewayRejection.
sub prepare {
    my ( $self, $body, %opts ) = @_;
    $self->check_key( $opts{key} );
    $self->check_origin( $opts{origin} );

    my $method = exists $body->{method} ? $body->{method} : 'chat';
    _reject( 400, 'method not allowed' )
        unless defined $method && !ref $method && $ALLOWED_METHODS{$method};

    # Read before minting so a malformed bag costs the caller nothing.
    my $user_metadata = $self->read_user_metadata($body);

    # The message size is checked before minting for the same reason.
    my $message = $body->{message};
    _reject( 413, 'message too large' )
        if $method eq 'chat' && _is_string($message) && _utf8_len($message) > MAX_MESSAGE_BYTES;

    my $handle = $body->{handle};
    my ( $conversation_id, $minted );
    if ( _py_truthy($handle) ) {
        $conversation_id = $self->read_handle($handle);
    } elsif ( $method eq 'end' || $method eq 'log' ) {
        _reject( 400, "$method requires a handle" );
    } else {
        $self->_charge_mint;
        $minted          = $self->mint_handle;
        $conversation_id = $self->read_handle($minted);
    }

    return ( 'end_conversation', { id => $conversation_id }, undef ) if $method eq 'end';

    # Scoped to the conversation named INSIDE the signed handle.
    return ( 'chat_log', { id => $conversation_id }, undef ) if $method eq 'log';

    if ( $method eq 'start' ) {

        # Opens the conversation with no user message, so the agent speaks first.
        my %params = ( id => $conversation_id, config_url => $self->config_url );
        $params{conversation_timeout} = $self->conversation_timeout if $self->conversation_timeout;
        $params{user_meta_data}       = $user_metadata              if $user_metadata;
        return ( 'create_conversation', \%params, $minted );
    }

    _reject( 400, 'message is required' ) unless _is_string($message) && $message =~ /\S/;

    $self->_charge_turn($conversation_id);

    # config_url on every chat, so the service auto-creates on the first and
    # ignores it after; the timeout and the metadata bag likewise ride every
    # chat, because any chat may be the one that creates.
    my %chat = ( id => $conversation_id, message => $message, config_url => $self->config_url );
    $chat{conversation_timeout} = $self->conversation_timeout if $self->conversation_timeout;
    $chat{user_meta_data}       = $user_metadata              if $user_metadata;
    return ( 'chat', \%chat, $minted );
}

# ── PSGI surface ─────────────────────────────────────────────────────

# A PSGI app exposing this gateway (mount it with AgentBase->mount, or any
# Plack builder). `POST /` takes {"method": "start"|"chat"|"log"|"end",
# "handle"?, "message"?, "user_meta_data"?} with the key in
# `Authorization: Bearer`. A chat streams the service's JSON-RPC response body
# through UNBUFFERED (psgi.streaming), so the service's keepalive padding keeps
# reaching the browser; a newly minted handle rides back in X-Chat-Handle.
# `OPTIONS /` answers the CORS preflight. A body over MAX_REQUEST_BODY_BYTES is
# a 413 before it is parsed.
sub router {
    my ($self) = @_;
    my $gateway = $self;

    return sub {
        my ($env) = @_;
        my $path = defined $env->{PATH_INFO} ? $env->{PATH_INFO} : '';
        return _json( 404, { detail => 'Not Found' } ) unless $path eq '' || $path eq '/';

        my $origin = $env->{HTTP_ORIGIN};
        my %cors   = $gateway->_cors_headers($origin);
        my $verb   = $env->{REQUEST_METHOD} // '';

        if ( $verb eq 'OPTIONS' ) {
            if (%cors) {
                $cors{'Access-Control-Allow-Headers'} = 'Authorization, Content-Type';
                $cors{'Access-Control-Allow-Methods'} = 'POST, OPTIONS';
                $cors{'Access-Control-Max-Age'}       = '600';
            }
            return [ 204, [%cors], [] ];
        }
        return _json( 405, { detail => 'Method Not Allowed' } ) unless $verb eq 'POST';

        my $auth = $env->{HTTP_AUTHORIZATION} // '';
        my $key  = lc( substr( $auth, 0, 7 ) ) eq 'bearer ' ? substr( $auth, 7 ) : undef;

        my ( $method, $params, $minted );
        my $ok = eval {
            my $body = _read_json_body($env);
            _reject( 400, 'body must be an object' ) unless ref $body eq 'HASH';
            ( $method, $params, $minted ) =
                $gateway->prepare( $body, origin => $origin, key => $key );
            1;
        };
        if ( !$ok ) {
            my $err = $@;
            return _json( $err->status, { error => $err->reason },  %cors ) if _is_rejection($err);
            return _json( 400,          { error => 'bad request' }, %cors );
        }

        if ( $method eq 'end_conversation' ) {
            $gateway->_client->end( $params->{id} );
            return _json( 200, { status => 'ended' }, %cors );
        }

        if ( $method eq 'create_conversation' ) {
            my $info = $gateway->_client->create_conversation(
                $params->{id},
                config_url    => $params->{config_url},
                timeout       => $params->{conversation_timeout},
                user_metadata => $params->{user_meta_data},
            );
            $cors{'X-Chat-Handle'} = $minted if $minted;
            return _json(
                200,
                {
                    greeting => $info->initial_message,
                    status   => $info->status,
                    timeout  => $gateway->effective_timeout,
                },
                %cors
            );
        }

        if ( $method eq 'chat_log' ) {
            my $log = $gateway->_client->log( $params->{id} );
            return _json(
                200,
                {
                    messages => $gateway->visible_messages( $log->messages ),
                    timeout  => $gateway->effective_timeout,

                    # Computed from the raw log: the only place timestamps exist.
                    last_activity => $gateway->last_activity( $log->messages ),
                },
                %cors
            );
        }

        my %headers = %cors;
        $headers{'X-Chat-Handle'} = $minted if $minted;
        my @headers = ( 'Content-Type' => 'application/json', %headers );

        if ( !$env->{'psgi.streaming'} ) {

            # A server without streaming support: the body has to be buffered.
            my $res = $gateway->_client->raw_post( $method, $params );
            return [ 200, \@headers, [ $res->{content} // '' ] ];
        }

        return sub {
            my ($responder) = @_;
            my $writer = $responder->( [ 200, \@headers ] );
            $gateway->_client->raw_post(
                $method, $params,
                data_callback => sub {
                    my ($chunk) = @_;
                    $writer->write($chunk);
                    return;
                },
            );
            $writer->close;
            return;
        };
    };
}

# ── Internals ────────────────────────────────────────────────────────

# CORS headers for an allowed origin; none otherwise.
sub _cors_headers {
    my ( $self, $origin ) = @_;
    return () unless defined $origin;
    return () unless eval { $self->check_origin($origin); 1 };
    return (
        'Access-Control-Allow-Origin'   => $origin,
        'Access-Control-Expose-Headers' => 'X-Chat-Handle',
        'Vary'                          => 'Origin',
    );
}

# Count a new conversation against the window limit, or reject with 429.
sub _charge_mint {
    my ($self) = @_;
    my $now    = _monotonic();
    my $cutoff = $now - $self->window_seconds;
    my @mints  = grep { $_ > $cutoff } @{ $self->_mints };
    _reject( 429, 'too many new conversations' ) if @mints >= $self->max_new_conversations;
    push @mints, $now;
    $self->_mints( \@mints );
    return;
}

# Count a turn against the conversation's limit, or reject with 429. Swept here
# rather than on a timer: a handle cannot outlive its TTL.
sub _charge_turn {
    my ( $self, $conversation_id ) = @_;
    my $now    = _monotonic();
    my $cutoff = $now - $self->handle_ttl;
    my %turns  = map { $_ => $self->_turns->{$_} } grep { $self->_turns->{$_}[1] > $cutoff }
        keys %{ $self->_turns };
    my $count = $turns{$conversation_id} ? $turns{$conversation_id}[0] : 0;
    if ( $count >= $self->max_turns ) {
        $self->_turns( \%turns );
        _reject( 429, 'conversation turn limit reached' );
    }
    $turns{$conversation_id} = [ $count + 1, $now ];
    $self->_turns( \%turns );
    return;
}

# Parse a PSGI request's JSON body, refusing one over $limit bytes: a declared
# Content-Length over the limit is refused before anything is read, and the
# body is read in chunks and abandoned as soon as it passes the limit. Dies
# with a 413 GatewayRejection, or a plain error for invalid JSON. Shared with
# SignalWire::AIChat::Handoff.
sub _read_json_body {
    my ( $env, $limit ) = @_;
    $limit //= MAX_REQUEST_BODY_BYTES;
    my $declared = $env->{CONTENT_LENGTH} // '';
    _reject( 413, 'request too large' ) if $declared =~ /\A[0-9]+\z/ && $declared > $limit;

    my $received = '';
    my $input    = $env->{'psgi.input'};
    if ($input) {
        while (1) {
            my $read = $input->read( my $buf, 8192 );
            last unless $read;
            $received .= $buf;
            _reject( 413, 'request too large' ) if length($received) > $limit;
        }
    }
    return JSON->new->utf8->allow_nonref->decode($received);
}

sub _json {
    my ( $status, $data, %headers ) = @_;
    return [ $status, [ 'Content-Type' => 'application/json', %headers ],
        [ $JSON->encode($data) ] ];
}

sub _reject {
    my ( $status, $reason ) = @_;
    die SignalWire::AIChat::GatewayRejection->new( status => $status, reason => $reason );
}

sub _is_rejection {
    my ($err) = @_;
    return blessed($err) && $err->isa('SignalWire::AIChat::GatewayRejection') ? 1 : 0;
}

sub _b64 {
    my ($raw) = @_;
    my $text = MIME::Base64::encode_base64( $raw, '' );
    $text =~ tr{+/}{-_};
    $text =~ s/=+\z//;
    return $text;
}

# Decode unpadded URL-safe base64, or undef when it cannot be decoded (a length
# that is 1 more than a multiple of 4 can never be valid).
sub _unb64 {
    my ($text) = @_;
    return unless defined $text;
    ( my $clean = $text ) =~ tr{-_}{+/};
    $clean =~ s{[^A-Za-z0-9+/]}{}g;
    return if length($clean) % 4 == 1;
    return MIME::Base64::decode_base64( $clean . ( '=' x ( -length($clean) % 4 ) ) );
}

sub _constant_time_eq {
    my ( $lhs, $rhs ) = @_;
    $lhs = Encode::encode( 'UTF-8', $lhs ) if utf8::is_utf8($lhs);
    $rhs = Encode::encode( 'UTF-8', $rhs ) if utf8::is_utf8($rhs);
    return 0 unless length $lhs == length $rhs;
    my $diff = 0;
    $diff |= ord( substr( $lhs, $_, 1 ) ) ^ ord( substr( $rhs, $_, 1 ) ) for 0 .. length($lhs) - 1;
    return $diff == 0 ? 1 : 0;
}

# Length of $text in UTF-8 bytes.
sub _utf8_len {
    my ($text) = @_;
    return length( Encode::encode( 'UTF-8', $text ) );
}

sub _monotonic {
    my $t = eval { Time::HiRes::clock_gettime( Time::HiRes::CLOCK_MONOTONIC() ) };
    return defined $t ? $t : Time::HiRes::time();
}

# A plain (non-reference) string value, as python's isinstance(x, str).
sub _is_string {
    my ($v) = @_;
    return 0 if !defined $v || ref $v;
    my $flags = B::svref_2object( \$v )->FLAGS;
    return ( $flags & B::SVp_POK() ) || !( $flags & ( B::SVp_IOK() | B::SVp_NOK() ) ) ? 1 : 0;
}

# An integer NUMBER (not a string, not a boolean), as python's isinstance(x, int).
sub _is_int {
    my ($v) = @_;
    return 0 if !defined $v || ref $v;
    my $flags = B::svref_2object( \$v )->FLAGS;
    return 0 unless $flags & ( B::SVp_IOK() | B::SVp_NOK() );
    return 0 if ( $flags & B::SVp_POK() ) && !( $flags & B::SVp_IOK() );
    return $v == int($v) ? 1 : 0;
}

sub _py_truthy {
    my ($v) = @_;
    return 0 unless defined $v;
    return length($v) ? 1 : 0 if _is_string($v);
    return 1 if ref $v && !JSON::is_bool($v) && ref $v ne 'HASH' && ref $v ne 'ARRAY';
    return scalar(%$v) ? 1 : 0 if ref $v eq 'HASH';
    return scalar(@$v) ? 1 : 0 if ref $v eq 'ARRAY';
    return $v          ? 1 : 0;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::AIChat::Gateway - browser-facing gateway for the SignalWire AI Chat service (ChatGateway)

=head1 SYNOPSIS

    use SignalWire::AIChat::Gateway;

    my $gateway = SignalWire::AIChat::Gateway->new(
        config_url      => 'https://my-agent.example.com/swml',
        key             => 'pk_live_...',                 # what the widget carries
        allowed_origins => ['https://shop.example.com'],
    );
    $agent->mount( $gateway->router, prefix => '/chat' );

=head1 DESCRIPTION

A chat widget cannot hold a SignalWire API token, so it talks to this gateway,
mounted in your own app, which holds the credential server-side and forwards on
the widget's behalf. The browser learns only the gateway URL and a publishable
key; the gateway injects C<config_url> itself, so a key reaches exactly one
agent. Conversation handles are HMAC-signed (ids cannot be guessed); the caps
C<max_new_conversations> and C<max_turns> bound what a leaked key can cost; the
origin allowlist is leak containment, not access control.

The only browser field forwarded rather than overwritten is C<user_meta_data>
(the page context a widget collects about itself), bounded at
C<MAX_USER_METADATA_BYTES> and nested under its own key. It is a visitor's
I<claim>, never authority. Request bodies (C<MAX_REQUEST_BODY_BYTES>, 64 KiB),
chat messages (C<MAX_MESSAGE_BYTES>, 8 KiB of UTF-8) and the metadata bag are
answered with 413 past their limits.

Counters live in this process; behind several replicas each holds its own.

=head1 CONSTRUCTION

C<< ->new(%args) >> with C<config_url> (required -- dies when empty) and the
optional C<key> (else C<SIGNALWIRE_CHAT_GATEWAY_KEY>, else generated),
C<allowed_origins> (arrayref), C<client> (a L<SignalWire::AIChat::Client>;
built from the environment and owned when omitted), C<secret> (HMAC key; else
C<SIGNALWIRE_CHAT_GATEWAY_SECRET>, else random per process), C<handle_ttl>
(86400), C<conversation_timeout>, C<max_new_conversations> (60), C<max_turns>
(200), C<window_seconds> (60).

=head1 ATTRIBUTES

C<config_url>, C<key>, C<allowed_origins> (normalized, trailing slash
stripped), C<handle_ttl>, C<conversation_timeout>, C<max_new_conversations>,
C<max_turns>, C<window_seconds> -- read-only.

=head1 METHODS

=over 4

=item C<effective_timeout>

Idle seconds a conversation actually gets: C<conversation_timeout>, else the
service default (3600).

=item C<last_activity(\@messages)>

Epoch seconds of the newest dated message (the service stamps microseconds), or
undef. Callable as a class or instance method.

=item C<visible_messages(\@messages)>

The transcript a browser may redraw: user/assistant turns with text, reduced to
C<role>, C<content> and an epoch-seconds C<timestamp>. Callable as a class or
instance method.

=item C<mint_handle($conversation_id)>

Issue a signed, expiring handle (a fresh C<chat-...> id when omitted).

=item C<read_handle($handle)>

The conversation id inside a handle, or dies with a
L<SignalWire::AIChat::GatewayRejection>: 400 C<malformed handle>, 403
C<invalid handle>, 403 C<expired handle>.

=item C<check_origin($origin)>

Localhost always; otherwise the origin must be listed (403). A missing origin
passes.

=item C<check_key($presented)>

Constant-time key check; 401 C<bad key> when missing or wrong.

=item C<read_user_metadata(\%body)>

Validate C<user_meta_data>: undef for absent/null/empty, 400 when not an object
or not serializable, 413 when too large.

=item C<prepare(\%body, origin =E<gt> $origin, key =E<gt> $key)>

Validate a browser request and build the upstream JSON-RPC call; returns
C<($method, \%params, $minted_handle)>. C<start> opens a conversation
(C<create_conversation>), C<chat> sends a turn (charging the turn cap; a call
without a handle mints one, charging the new-conversation cap), C<log> reads
the C<chat_log> and C<end> ends it (both need a handle). Dies with a
L<SignalWire::AIChat::GatewayRejection>.

=item C<router>

A PSGI app: C<POST /> (the key in C<Authorization: Bearer>) and the C<OPTIONS
/> CORS preflight. Rejections come back as C<{"error": ...}> with their status;
C<start>, C<log> and C<end> return JSON summaries; a C<chat> streams the
service's response body through unbuffered (C<psgi.streaming>), with a newly
minted handle in the C<X-Chat-Handle> header.

=item C<close>

Release the upstream client if the gateway built it.

=back

=head1 CONSTANTS

C<DEFAULT_HANDLE_TTL>, C<SERVICE_DEFAULT_CONVERSATION_TIMEOUT>,
C<DEFAULT_MAX_NEW_CONVERSATIONS>, C<DEFAULT_MAX_TURNS>,
C<DEFAULT_WINDOW_SECONDS>, C<MAX_USER_METADATA_BYTES>, C<MAX_MESSAGE_BYTES>,
C<MAX_REQUEST_BODY_BYTES>.

=head1 SEE ALSO

L<SignalWire::AIChat::Handoff>, L<SignalWire::AIChat::Client>,
L<SignalWire::Agent::AgentBase/mount>.

=head1 LICENSE

Copyright (c) 2026 SignalWire. Licensed under the MIT License.

=cut
