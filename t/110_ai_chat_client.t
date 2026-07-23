#!/usr/bin/env perl
# Unit tests for SignalWire::AIChat::Client — construction, URL resolution, wire
# behavior (Basic auth, identity-never-in-params, param mapping, decode), the
# summarize one_of {summary}|{error} branches (INCLUDING {error} -> typed
# SummaryError, never a silent empty string), and the JSON-RPC error-code
# mapping. The HTTP transport is stubbed via the injectable `ua` attribute; the
# stub mirrors porting-sdk's mock_ai_chat.
use strict;
use warnings;
use Test::More;
use JSON qw(encode_json decode_json);

# A minimal stub transport answering ->request like HTTP::Tiny. Declared up top
# (before any use) so its Moo accessor exists when the test body runs.
BEGIN {
    package StubUA;    ## no critic (ProhibitMultiplePackages)
    use Moo;
    has 'on_request' => ( is => 'ro', required => 1 );

    sub request {
        my ( $self, $method, $url, $opts ) = @_;
        return $self->on_request->( $method, $url, $opts );
    }
}

use_ok('SignalWire::AIChat::Client');
use_ok('SignalWire::AIChat::Error');

# Identity keys that must never ride in the JSON-RPC params.
my @FORBIDDEN_IN_PARAMS = qw(project_id project token api_token space_id space);

# The canned success results the mock emits per method (mirrors mock_ai_chat).
my %CANNED = (
    create_conversation => { status => 'created', id => 'conv-1', initial_message => 'hello' },
    chat                => { response => 'hi there', user_event => { event_type => 'demo', n => 1 } },
    end_conversation    => { status => 'ended', id => 'conv-1' },
    delete              => { status => 'deleted', id => 'conv-1' },
    chat_log            => { chat_log => [ { role => 'user', content => 'm' } ], call_timeline => [ { t => 1 } ] },
    summarize           => { summary => 'a concise summary' },
);

# Build a stub UA that behaves like mock_ai_chat: it records every request and
# returns a JSON-RPC response chosen by $responder (a coderef of
# ($method,$params) -> an envelope hashref: {result=>..} or {error=>..}). Returns
# ($ua, $requests_arrayref).
sub stub_ua {
    my ($responder) = @_;
    my @requests;
    my $ua = StubUA->new(
        on_request => sub {
            my ( $method, $url, $opts ) = @_;
            my $payload = decode_json( $opts->{content} );
            push @requests,
                {
                method        => $payload->{method},
                params        => $payload->{params},
                authorization => $opts->{headers}{Authorization},
                };
            my $envelope = $responder->( $payload->{method}, $payload->{params} );
            my $body = { jsonrpc => '2.0', %$envelope, id => $payload->{id} };
            return {
                success => 1,
                status  => 200,
                content => encode_json($body),
            };
        },
    );
    return ( $ua, \@requests );
}

# A responder mirroring the mock: canned success, sentinel-driven errors.
sub mock_responder {
    my ( $method, $params ) = @_;
    my $id = $params->{id};
    if ( defined $id && $id =~ /^__err_(-?\d+)$/ ) {
        return { error => { code => $1 + 0, message => 'forced error' } };
    }
    if ( $method eq 'summarize' && defined $id && $id eq '__summarize_error' ) {
        return { result => { error => 'Failed to generate summary' } };
    }
    return { result => $CANNED{$method} // {} };
}

sub new_client {
    my ($ua) = @_;
    return SignalWire::AIChat::Client->new(
        project => 'proj-1',
        token   => 'tok-1',
        url     => 'http://mock/api/ai/chat',
        ua      => $ua,
    );
}

# ── construction / URL resolution ────────────────────────────────────
{
    local $ENV{SIGNALWIRE_PROJECT_ID};
    delete local $ENV{SIGNALWIRE_PROJECT_ID};
    my $err = do { local $@; eval { SignalWire::AIChat::Client->new( url => 'http://x' ) }; $@ };
    like( $err, qr/project is required/, 'requires a project (arg or env)' );
}

{
    my $c = SignalWire::AIChat::Client->new( project => 'p', token => 't', space => 'myspace' );
    is( $c->url, 'https://myspace.signalwire.com/api/ai/chat',
        'builds the space URL when no explicit url is given' );
}

{
    my $c = SignalWire::AIChat::Client->new(
        project => 'p', token => 't', url => 'http://local/api/ai/chat' );
    is( $c->url, 'http://local/api/ai/chat', 'uses an explicit url verbatim' );
}

{
    my $err = do {
        local $@;
        eval { SignalWire::AIChat::Client->new( project => 'p', token => 't' ) };
        $@;
    };
    like( $err, qr/No service URL/, 'throws when neither url nor space resolves' );
}

# ── wire behavior ────────────────────────────────────────────────────
{
    my ( $ua, $requests ) = stub_ua( \&mock_responder );
    my $client = new_client($ua);
    $client->create_conversation( 'conv-1', config_url => 'http://cfg', timeout => 30, reinit => 1 );

    my $req = $requests->[0];
    like( $req->{authorization}, qr/^Basic /, 'sends HTTP Basic auth' );
    ( my $b64 = $req->{authorization} ) =~ s/^Basic //;
    require MIME::Base64;
    is( MIME::Base64::decode_base64($b64), 'proj-1:tok-1', 'project is the Basic-auth username' );
    for my $key (@FORBIDDEN_IN_PARAMS) {
        ok( !exists $req->{params}{$key}, "identity key '$key' never in params" );
    }
}

{
    my ( $ua, $requests ) = stub_ua( \&mock_responder );
    my $info = new_client($ua)
        ->create_conversation( 'conv-1', config_url => 'http://cfg', timeout => 30, reinit => 1 );
    is( $requests->[0]{method}, 'create_conversation', 'create hits create_conversation' );
    is( $requests->[0]{params}{id},                   'conv-1',    'id on the wire' );
    is( $requests->[0]{params}{config_url},           'http://cfg', 'config_url on the wire' );
    is( $requests->[0]{params}{conversation_timeout}, 30, 'timeout -> conversation_timeout' );
    ok( $requests->[0]{params}{reinit}, 'reinit on the wire' );
    is( $info->id,              'conv-1',  'decoded id' );
    is( $info->status,          'created', 'decoded status' );
    is( $info->initial_message, 'hello',   'decoded initial_message' );
}

{
    my ( $ua, $requests ) = stub_ua( \&mock_responder );
    my $reply = new_client($ua)->chat( 'conv-1', 'hello', timeout => 30, reinit => 1 );
    is( $requests->[0]{method},         'chat',    'chat hits chat' );
    is( $requests->[0]{params}{message}, 'hello',  'message on the wire' );
    is( $requests->[0]{params}{role},    'user',   'role defaults to user' );
    is( $requests->[0]{params}{conversation_timeout}, 30, 'timeout -> conversation_timeout' );
    is( $reply->text,            'hi there', 'decoded response text' );
    is( $reply->conversation_id, 'conv-1',   'conversation_id echoed' );
    is_deeply( $reply->user_event, { event_type => 'demo', n => 1 }, 'decoded user_event' );
}

{
    my ( $ua, $requests ) = stub_ua( \&mock_responder );
    ok( new_client($ua)->end('conv-1'), 'end returns true on {status: ended}' );
    is( $requests->[0]{method}, 'end_conversation', 'end hits end_conversation' );
}

{
    my ( $ua, $requests ) = stub_ua( \&mock_responder );
    ok( new_client($ua)->delete('conv-1'), 'delete returns true on {status: deleted}' );
    is( $requests->[0]{method}, 'delete', 'delete hits delete' );
}

{
    my ( $ua, $requests ) = stub_ua( \&mock_responder );
    my $log = new_client($ua)->log('conv-1');
    is( $requests->[0]{method}, 'chat_log', 'log hits chat_log' );
    is_deeply( $log->messages,      [ { role => 'user', content => 'm' } ], 'decoded messages' );
    is_deeply( $log->call_timeline, [ { t => 1 } ],                         'decoded call_timeline' );
}

{
    my ( $ua, $requests ) = stub_ua( \&mock_responder );
    is( new_client($ua)->summarize('conv-1'),
        'a concise summary', 'summarize returns the summary on the {summary} branch' );
}

{
    my ( $ua, $requests ) = stub_ua( \&mock_responder );
    new_client($ua)->summarize( 'conv-1',
        summary_prompt => 'be brief', temperature => 0.2, max_tokens => 64 );
    is( $requests->[0]{params}{summary_prompt}, 'be brief', 'summary_prompt on the wire' );
    is( $requests->[0]{params}{temperature},    0.2,        'temperature on the wire' );
    is( $requests->[0]{params}{max_tokens},     64,         'max_tokens on the wire' );
}

# ── summarize one_of {error} branch: RAISES SummaryError ─────────────
{
    my ( $ua, $requests ) = stub_ua( \&mock_responder );
    my $client  = new_client($ua);
    my $summary = eval { $client->summarize('__summarize_error') };
    my $err     = $@;
    ok( !defined $summary, 'summarize({error}) does NOT return a value' );
    ok( ref $err && $err->isa('SignalWire::AIChat::SummaryError'),
        'summarize({error}) raises SummaryError (never a silent empty string)' );
    ok( $err->isa('SignalWire::AIChat::Error'), 'SummaryError is-a base AIChat error' );
    ok( !defined $err->code, 'SummaryError carries a null/undef code (success-envelope failure)' );
    is( $err->message, 'Failed to generate summary', 'SummaryError carries the server message' );
}

# summary wins when both summary and error are present.
{
    my ( $ua, $requests ) = stub_ua( sub { return { result => { summary => 's', error => 'ignored' } } } );
    is( new_client($ua)->summarize('conv-1'), 's',
        'does NOT raise when both summary and error present (summary wins)' );
}

# ── JSON-RPC error mapping ───────────────────────────────────────────
my @CASES = (
    [ -32001, 'SignalWire::AIChat::ConversationNotFoundError' ],
    [ -32005, 'SignalWire::AIChat::RateLimitError' ],
    [ -32006, 'SignalWire::AIChat::RateLimitError' ],
    [ -32007, 'SignalWire::AIChat::ChatInProgressError' ],
    [ -32009, 'SignalWire::AIChat::AuthenticationError' ],
);
for my $case (@CASES) {
    my ( $code, $class ) = @$case;
    my ( $ua, $requests ) = stub_ua( \&mock_responder );
    my $ok  = eval { new_client($ua)->chat( "__err_$code", 'x' ); 1 };
    my $err = $@;
    ok( !$ok, "chat forcing $code raises" );
    ok( ref $err && $err->isa($class), "code $code maps to $class" );
    ok( $err->isa('SignalWire::AIChat::Error'), "code $code error is-a base" );
    is( $err->code, $code, "raised error carries code $code" );
}

# an unmapped code falls to the base AIChatError.
{
    my ( $ua, $requests ) = stub_ua( \&mock_responder );
    my $ok  = eval { new_client($ua)->chat( '__err_-32602', 'x' ); 1 };
    my $err = $@;
    ok( !$ok, 'unmapped code raises' );
    ok( ref $err && $err->isa('SignalWire::AIChat::Error'), 'unmapped code -> base AIChatError' );
    ok( !$err->isa('SignalWire::AIChat::ConversationNotFoundError'),
        'unmapped code is NOT a typed subclass' );
    is( $err->code, -32602, 'base error carries the unmapped code' );
}

# a non-JSON body raises the base AIChatError.
{
    my $ua = StubUA->new(
        on_request => sub { return { success => 0, status => 502, content => '<html>not json' } } );
    my $ok  = eval { new_client($ua)->chat( 'conv-1', 'x' ); 1 };
    my $err = $@;
    ok( !$ok, 'non-JSON body raises' );
    ok( ref $err && $err->isa('SignalWire::AIChat::Error'), 'non-JSON body -> AIChatError' );
}

done_testing();
