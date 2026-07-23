package SignalWire::AIChat::Client;
use strict;
use warnings;
use Moo;

use HTTP::Tiny;
use JSON         qw(encode_json decode_json);
use MIME::Base64 qw(encode_base64);

use SignalWire::AIChat::Error;

# Default endpoint path appended to a space-derived base URL.
my $DEFAULT_PATH = '/api/ai/chat';

# The service streams keepalive whitespace ahead of a slow response body (every
# ~10s), so liveness is byte-driven, not wall-clock: a per-read idle timeout
# bounds true byte-silence (a dead connection), NOT total turn length — mirroring
# the python reference's aiohttp.ClientTimeout(total=None, connect=10,
# sock_read=60). HTTP::Tiny exposes only a single wall-clock timeout, so the
# honest portable analog is a generous idle bound (60s) with NO total cap that a
# live-but-slow turn could trip. Leading whitespace is valid JSON, so decode is
# unaffected.
my $DEFAULT_READ_IDLE_TIMEOUT_SECONDS = 60;

# JSON-RPC error code -> the typed error class it maps to. Unmapped codes fall to
# the base AIChatError.
my %ERROR_BY_CODE = (
    -32001 => 'SignalWire::AIChat::ConversationNotFoundError',
    -32005 => 'SignalWire::AIChat::RateLimitError',
    -32006 => 'SignalWire::AIChat::RateLimitError',
    -32007 => 'SignalWire::AIChat::ChatInProgressError',
    -32009 => 'SignalWire::AIChat::AuthenticationError',
);

# ── Attributes ───────────────────────────────────────────────────────

# Project id (Basic-auth username). Falls back to SIGNALWIRE_PROJECT_ID.
has 'project' => ( is => 'ro', default => sub { $ENV{SIGNALWIRE_PROJECT_ID} // '' } );

# API token (Basic-auth password). Falls back to SIGNALWIRE_API_TOKEN.
has 'token' => ( is => 'ro', default => sub { $ENV{SIGNALWIRE_API_TOKEN} // '' } );

# Space name; builds https://{space}.signalwire.com/api/ai/chat. Falls back to
# SIGNALWIRE_SPACE.
has 'space' => ( is => 'ro', default => sub { $ENV{SIGNALWIRE_SPACE} // '' } );

# Fully-qualified endpoint URL, used verbatim (highest precedence).
has 'url' => ( is => 'lazy' );

# Idle read timeout in seconds (byte-silence, NOT total turn length). 0 disables.
has 'read_idle_timeout_seconds' =>
    ( is => 'ro', default => sub { $DEFAULT_READ_IDLE_TIMEOUT_SECONDS } );

# The HTTP transport. Injectable for tests (a stub answering ->request); defaults
# to a configured HTTP::Tiny. Any object answering
# ->request($method,$url,\%opts) and returning HTTP::Tiny's response hashref works.
has 'ua' => ( is => 'lazy' );

has '_auth_header'     => ( is => 'lazy' );
has '_request_counter' => ( is => 'rw', default => sub { 0 } );

sub BUILD {
    my ($self) = @_;
    if ( !length $self->project ) {
        die "project is required. Provide it as an argument or set the "
            . "SIGNALWIRE_PROJECT_ID environment variable.\n";
    }

    # Resolve the URL eagerly so a missing target fails at construction, mirroring
    # the python/TS reference (which resolve in __init__/constructor).
    $self->url;
    return;
}

sub _build_url {
    my ($self) = @_;
    my $space = $self->space;
    if ( length $space ) {
        return "https://$space.signalwire.com$DEFAULT_PATH";
    }
    die "No service URL: provide url= or space= / SIGNALWIRE_SPACE.\n";
}

sub _build__auth_header {
    my ($self) = @_;
    my $credentials = $self->project . ':' . $self->token;
    return 'Basic ' . encode_base64( $credentials, '' );
}

sub _build_ua {
    my ($self) = @_;
    my $timeout = $self->read_idle_timeout_seconds;

    my %ssl_options;

    # A5 fleet CA-var contract: when SIGNALWIRE_REST_CA_FILE names a custom CA
    # bundle, use it as the TLS trust root (the analog of the python reference's
    # session.verify). Unset -> the OS trust store, unchanged.
    my $ca_file = $ENV{SIGNALWIRE_REST_CA_FILE};
    if ( defined $ca_file && length $ca_file ) {
        $ssl_options{SSL_ca_file} = $ca_file;
    }

    return HTTP::Tiny->new(
        agent           => 'signalwire-perl/' . ( $SignalWire::VERSION // '0' ),
        default_headers => {
            'Content-Type'  => 'application/json',
            'Accept'        => 'application/json',
            'Authorization' => $self->_auth_header,
        },

        # A total request timeout a heartbeat can't reset would sever a
        # live-but-slow turn; HTTP::Tiny has only a single wall-clock timeout, so
        # use the generous idle bound as the dead-connection detector. 0 disables.
        ( $timeout > 0 ? ( timeout => $timeout ) : () ),

        # Verify TLS by default (parity with the python reference); a stub UA in
        # tests never reaches TLS.
        verify_SSL => 1,
        ( %ssl_options ? ( SSL_options => \%ssl_options ) : () ),
    );
}

# ── Wire ─────────────────────────────────────────────────────────────

# POST one JSON-RPC call and return its decoded `result` hashref.
#
# Success/failure is decided by the JSON-RPC BODY, not the HTTP status: the
# service's keepalive heartbeat commits 200 before the turn's outcome is known,
# so a slow error can arrive as 200 + {"error": …}. Never gate on the HTTP status
# here (mirrors the python reference). Raises a typed AIChatError (or subclass)
# when the body carries `error`.
sub _request {
    my ( $self, $method, $params ) = @_;

    $self->_request_counter( $self->_request_counter + 1 );
    my $payload = {
        jsonrpc => '2.0',
        method  => $method,
        params  => $params,
        id      => 'req-' . $self->_request_counter,
    };

    my $response = $self->ua->request(
        'POST',
        $self->url,
        {
            content => encode_json($payload),

            # A stub UA (tests) may ignore per-request headers; the default
            # HTTP::Tiny carries auth/content-type in default_headers. Pass them
            # here too so an injected UA without defaults still authenticates.
            headers => {
                'Content-Type'  => 'application/json',
                'Accept'        => 'application/json',
                'Authorization' => $self->_auth_header,
            },
        },
    );

    # Buffer the whole body then parse. Leading keepalive whitespace is valid
    # JSON, so a plain decode handles it — no need to strip.
    my $status = defined $response->{status} ? $response->{status} : 0;
    my $body   = eval { decode_json( $response->{content} // '' ) };
    if ($@) {
        die SignalWire::AIChat::Error->new(
            code    => $status,
            message => "non-JSON response (HTTP $status)",
        );
    }

    if ( ref $body eq 'HASH' && defined $body->{error} ) {
        my $error = ref $body->{error} eq 'HASH' ? $body->{error} : {};
        my $code  = $error->{code};
        my $class =
            ( defined $code && exists $ERROR_BY_CODE{$code} )
            ? $ERROR_BY_CODE{$code}
            : 'SignalWire::AIChat::Error';
        die $class->new( code => $code, message => $error->{message} // '' );
    }

    my $result = ( ref $body eq 'HASH' ) ? $body->{result} : undef;
    return ( ref $result eq 'HASH' ) ? $result : {};
}

# ── API methods ──────────────────────────────────────────────────────

# Create a conversation (or, with reinit, reinitialize an existing one) and
# optionally send its opening user message. Returns a
# SignalWire::AIChat::ConversationInfo.
sub create_conversation {
    my ( $self, $conversation_id, %opts ) = @_;
    my $params = { id => $conversation_id, config_url => $opts{config_url} };
    $params->{user_message} = $opts{user_message}
        if defined $opts{user_message} && length $opts{user_message};
    $params->{conversation_timeout} = $opts{timeout}       if $opts{timeout};
    $params->{user_meta_data}       = $opts{user_metadata} if $opts{user_metadata};
    $params->{reinit}               = JSON::true()         if $opts{reinit};

    my $result = $self->_request( 'create_conversation', $params );
    return SignalWire::AIChat::ConversationInfo->new(
        id     => $conversation_id,
        status => ( defined $result->{status} && !ref $result->{status} )
        ? $result->{status}
        : 'created',
        initial_message => $result->{initial_message},
    );
}

# Send a message and await a full LLM round trip. Passing config_url auto-creates
# the conversation if it doesn't exist yet. Returns a
# SignalWire::AIChat::ChatResponse.
sub chat {
    my ( $self, $conversation_id, $message, %opts ) = @_;
    my $params = {
        id      => $conversation_id,
        message => $message,
        role    => defined $opts{role} ? $opts{role} : 'user',
    };
    $params->{config_url}           = $opts{config_url}    if $opts{config_url};
    $params->{user_meta_data}       = $opts{user_metadata} if $opts{user_metadata};
    $params->{conversation_timeout} = $opts{timeout}       if $opts{timeout};
    $params->{reinit}               = JSON::true()         if $opts{reinit};

    my $result = $self->_request( 'chat', $params );
    return SignalWire::AIChat::ChatResponse->new(
        text => ( defined $result->{response} && !ref $result->{response} )
        ? $result->{response}
        : '',
        conversation_id => $conversation_id,
        user_event      => ( ref $result->{user_event} eq 'HASH' ) ? $result->{user_event} : undef,
    );
}

# End a conversation (triggers server-side post-processing). Returns true when the
# service reported the conversation ended.
sub end {
    my ( $self, $conversation_id ) = @_;
    my $result = $self->_request( 'end_conversation', { id => $conversation_id } );
    return ( defined $result->{status} && $result->{status} eq 'ended' ) ? 1 : 0;
}

# Permanently delete a conversation and its data. Returns true when the service
# reported the conversation deleted.
sub delete {
    my ( $self, $conversation_id ) = @_;
    my $result = $self->_request( 'delete', { id => $conversation_id } );
    return ( defined $result->{status} && $result->{status} eq 'deleted' ) ? 1 : 0;
}

# Full message history plus the call timeline. Returns a SignalWire::AIChat::ChatLog.
sub log {
    my ( $self, $conversation_id ) = @_;
    my $result = $self->_request( 'chat_log', { id => $conversation_id } );
    return SignalWire::AIChat::ChatLog->new(
        messages      => ( ref $result->{chat_log} eq 'ARRAY' ) ? $result->{chat_log} : [],
        call_timeline => ( ref $result->{call_timeline} eq 'ARRAY' )
        ? $result->{call_timeline}
        : [],
    );
}

# AI summary of the conversation (rate limited server-side).
#
# The service returns EXACTLY ONE of {summary} or {error} — BOTH on the success
# envelope — so a failed generation must surface as a thrown SummaryError, never
# as an empty string. Accepts an optional summary_prompt plus sampling params
# (temperature/top_p/frequency_penalty/presence_penalty/max_tokens), which ride
# the wire as-is.
sub summarize {
    my ( $self, $conversation_id, %opts ) = @_;
    my $params = { id => $conversation_id };
    $params->{summary_prompt} = $opts{summary_prompt}
        if defined $opts{summary_prompt} && length $opts{summary_prompt};

    for my $k (qw(temperature top_p frequency_penalty presence_penalty max_tokens)) {
        $params->{$k} = $opts{$k} if defined $opts{$k};
    }

    my $result = $self->_request( 'summarize', $params );
    if ( exists $result->{error} && !exists $result->{summary} ) {
        die SignalWire::AIChat::SummaryError->new(
            code    => undef,
            message => "$result->{error}",
        );
    }
    my $summary = $result->{summary};
    return defined $summary ? ( ref $summary ? "$summary" : $summary ) : '';
}

# ── Response models ──────────────────────────────────────────────────

package SignalWire::AIChat::ConversationInfo;    ## no critic (ProhibitMultiplePackages)
use Moo;

has 'id'              => ( is => 'ro', required => 1 );
has 'status'          => ( is => 'ro', required => 1 );
has 'initial_message' => ( is => 'ro', default  => sub { undef } );

package SignalWire::AIChat::ChatResponse;        ## no critic (ProhibitMultiplePackages)
use Moo;

has 'text'            => ( is => 'ro', required => 1 );
has 'conversation_id' => ( is => 'ro', required => 1 );
has 'user_event'      => ( is => 'ro', default  => sub { undef } );

package SignalWire::AIChat::ChatLog;             ## no critic (ProhibitMultiplePackages)
use Moo;

has 'messages'      => ( is => 'ro', default => sub { [] } );
has 'call_timeline' => ( is => 'ro', default => sub { [] } );

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::AIChat::Client - client for the SignalWire AI Chat service

=head1 SYNOPSIS

    use SignalWire::AIChat::Client;

    my $client = SignalWire::AIChat::Client->new( space => 'myspace' );  # env supplies creds

    my $info  = $client->create_conversation( 'conv-1', config_url => $CONFIG_URL );
    my $reply = $client->chat( 'conv-1', 'hello' );
    print $reply->text, "\n";

    my $summary = eval { $client->summarize('conv-1') };
    if ( my $err = $@ ) {
        # SignalWire::AIChat::SummaryError when generation failed
        warn "summary failed: ", $err->message;
    }

=head1 DESCRIPTION

L<SignalWire::AIChat::Client> speaks the standard SignalWire front-door
protocol: HTTP Basic C<project:api_token> with the space in the hostname --
C<POST https://{space}.signalwire.com/api/ai/chat> -- carrying a JSON-RPC 2.0
body whose params are pure payload (identity NEVER appears in the body; it
rides the Basic-auth header only). It mirrors the python reference
C<signalwire.ai_chat.AIChatClient>.

A C<chat()> call awaits a full LLM round trip (seconds, not milliseconds). The
service streams keepalive whitespace ahead of a slow response body, so liveness
is byte-driven rather than wall-clock: there is no total-request timeout an idle
turn could trip -- only a per-read idle bound (default 60s), mirroring the
python reference's C<sock_read=60>. Leading whitespace is valid JSON, so the
buffered parse is unaffected.

=head2 URL resolution

In order: C<url> (verbatim), else C<< https://{space}.signalwire.com/api/ai/chat >>
built from C<space> (argument or C<SIGNALWIRE_SPACE>). Credentials come from the
constructor or C<SIGNALWIRE_PROJECT_ID> / C<SIGNALWIRE_API_TOKEN>.

=head1 ATTRIBUTES

=over 4

=item project / token / space / url

Connection + credentials. C<project> is required (argument or
C<SIGNALWIRE_PROJECT_ID>). Either C<url> or C<space> (or C<SIGNALWIRE_SPACE>)
must resolve a target.

=item read_idle_timeout_seconds

Idle read timeout in seconds (byte-silence, NOT total turn length). Default 60;
C<0> disables it.

=item ua

The HTTP transport. Defaults to a configured L<HTTP::Tiny>; injectable for tests
(any object answering C<< ->request($method, $url, \%opts) >> and returning
HTTP::Tiny's response hashref).

=back

=head1 METHODS

=over 4

=item create_conversation($conversation_id, config_url => $url, %opts)

Create (or, with C<< reinit => 1 >>, reinitialize) a conversation. Optional
C<user_message>, C<timeout> (wire C<conversation_timeout>), C<user_metadata>
(wire C<user_meta_data>). Returns a C<SignalWire::AIChat::ConversationInfo>
(C<id>, C<status>, C<initial_message>).

=item chat($conversation_id, $message, %opts)

Send a message and await the AI reply. Optional C<role> (default C<user>),
C<config_url> (auto-creates the conversation), C<timeout>, C<reinit>,
C<user_metadata>. Returns a C<SignalWire::AIChat::ChatResponse> (C<text>,
C<conversation_id>, C<user_event>).

=item end($conversation_id)

End a conversation. Returns true when the service reported it ended.

=item delete($conversation_id)

Permanently delete a conversation. Returns true when the service reported it
deleted.

=item log($conversation_id)

Return the full message history plus call timeline as a
C<SignalWire::AIChat::ChatLog> (C<messages>, C<call_timeline>).

=item summarize($conversation_id, %opts)

Return an AI summary string. Optional C<summary_prompt> plus sampling params
(C<temperature>, C<top_p>, C<frequency_penalty>, C<presence_penalty>,
C<max_tokens>). The service returns EXACTLY ONE of C<{summary}> or C<{error}>
(both on the success envelope), so a failed generation is raised as a
C<SignalWire::AIChat::SummaryError> -- never a silent empty string.

=back

=head1 ERRORS

See L<SignalWire::AIChat::Error> for the typed error family
(C<SignalWire::AIChat::Error> base + C<AuthenticationError> /
C<ConversationNotFoundError> / C<RateLimitError> / C<ChatInProgressError> /
C<SummaryError>).

=head1 SEE ALSO

L<SignalWire::AIChat::Error>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
