#!/usr/bin/env perl
# ChatGateway (SignalWire::AIChat::Gateway) and AIChatClient.raw_post: what a
# browser holding a publishable key can and cannot do, against an in-process
# stub chat service. Mirrors the python reference tests
# (tests/unit/ai_chat/test_gateway.py).
use strict;
use warnings;
use Test::More;
use JSON qw(encode_json decode_json);

use SignalWire::AIChat::Client;
use SignalWire::AIChat::Gateway;
use SignalWire::AIChat::GatewayRejection;

{

    package StubUA;    ## no critic (ProhibitMultiplePackages)
    use Moo;
    has 'seen'   => ( is => 'ro', default => sub { [] } );
    has 'chunks' => ( is => 'ro', default => sub { undef } );

    sub request {
        my ( $self, $method, $url, $opts ) = @_;
        my $body = JSON::decode_json( $opts->{content} );
        push @{ $self->seen }, $body;
        my %results = (
            chat                => { response => 'hi there' },
            create_conversation => { status => 'created', initial_message => 'Hi, I am Sigmond.' },
            chat_log            => {
                chat_log => [
                    { role => 'system',    content => 'secret prompt', timestamp => 1_000_000 },
                    { role => 'user',      content => 'hi',            timestamp => 2_000_000 },
                    { role => 'assistant', content => 'hi there',      timestamp => 3_000_000 },
                ]
            },
        );
        my $result = $results{ $body->{method} } // { status => 'ended' };
        my $json = JSON::encode_json( { jsonrpc => '2.0', result => $result, id => $body->{id} } );
        my $res  = { status => 200, success => 1, reason => 'OK', headers => {} };
        if ( my $cb = $opts->{data_callback} ) {
            my @parts = $self->chunks ? ( @{ $self->chunks }, $json ) : ($json);
            $cb->( $_, $res ) for @parts;
            return $res;
        }
        return { %$res, content => $json };
    }
}

my $CONFIG_URL = 'https://agent.example.com/swml';
my $KEY        = 'pk_test_key';

sub make_gateway {
    my (%kw)   = @_;
    my $ua     = StubUA->new( $kw{chunks} ? ( chunks => delete $kw{chunks} ) : () );
    my $client = SignalWire::AIChat::Client->new(
        project => 'p',
        token   => 't',
        url     => 'http://svc/',
        ua      => $ua
    );
    my $gw = SignalWire::AIChat::Gateway->new(
        config_url      => $CONFIG_URL,
        key             => $KEY,
        allowed_origins => ['https://shop.example.com'],
        client          => $client,
        secret          => 'test-secret',
        %kw,
    );
    return ( $gw, $ua );
}

sub rejection {
    my ($code) = @_;
    local $@;
    eval { $code->(); 1 } and return;
    return $@;
}

sub prep {
    my ( $gw, $body ) = @_;
    return $gw->prepare( $body, origin => undef, key => $KEY );
}

subtest 'raw_post returns the undecoded response and can stream it' => sub {
    my $ua     = StubUA->new( chunks => [ ' ', "\n" ] );
    my $client = SignalWire::AIChat::Client->new(
        project => 'p',
        token   => 't',
        url     => 'http://svc/',
        ua      => $ua
    );
    my $res = $client->raw_post( 'chat', { id => 'c1', message => 'hi' } );
    is( $res->{status}, 200, 'status' );
    is( decode_json( $res->{content} )->{result}{response},
        'hi there', 'body buffered when no callback' );
    is_deeply(
        $ua->seen->[0],
        {
            jsonrpc => '2.0',
            method  => 'chat',
            params  => { id => 'c1', message => 'hi' },
            id      => 'req-1'
        },
        'JSON-RPC envelope'
    );

    my @chunks;
    $client->raw_post( 'chat', { id => 'c1' }, data_callback => sub { push @chunks, $_[0] } );
    is_deeply( [ @chunks[ 0, 1 ] ], [ ' ', "\n" ], 'keepalive padding delivered as it arrives' );
    is( $ua->seen->[1]{id}, 'req-2', 'request counter shared with the typed methods' );
};

subtest 'construction' => sub {
    my $err = rejection( sub { make_gateway( config_url => '' ) } );
    like( $err, qr/config_url is required/, 'config_url is required' );
    my ($gw) = make_gateway( allowed_origins => [ 'https://a.example/', 'https://a.example' ] );
    is_deeply( $gw->allowed_origins, ['https://a.example'], 'origins normalized' );
    is( $gw->effective_timeout, 3600, 'effective_timeout defaults to the service default' );
    my ($gw2) = make_gateway( conversation_timeout => 900 );
    is( $gw2->effective_timeout, 900, 'effective_timeout follows conversation_timeout' );

    local $ENV{SIGNALWIRE_CHAT_GATEWAY_KEY};
    my $client =
        SignalWire::AIChat::Client->new( project => 'p', url => 'http://svc/', ua => StubUA->new );
    my $auto = SignalWire::AIChat::Gateway->new( config_url => $CONFIG_URL, client => $client );
    like( $auto->key, qr/\Apk_[A-Za-z0-9_-]{32}\z/, 'a key is generated when omitted' );
};

subtest 'handles' => sub {
    my ($gw) = make_gateway();
    my $handle = $gw->mint_handle;
    like( $gw->read_handle($handle), qr/\Achat-/, 'round trips' );
    is( $gw->read_handle( $gw->mint_handle('conv-9') ), 'conv-9', 'named conversation' );

    my ( $prefix, undef ) = split /\./, $handle;
    my $err = rejection( sub { $gw->read_handle("$prefix.AAAA") } );
    isa_ok( $err, 'SignalWire::AIChat::GatewayRejection' );
    is( $err->status, 403,              'forged signature -> 403' );
    is( $err->reason, 'invalid handle', 'invalid handle' );

    my ($other) = make_gateway( secret => 'different' );
    is( rejection( sub { $gw->read_handle( $other->mint_handle ) } )->status,
        403, 'another gateway\'s handle is refused' );

    my ($expired) = make_gateway( handle_ttl => -1 );
    my $old = rejection( sub { $expired->read_handle( $expired->mint_handle ) } );
    is( $old->reason, 'expired handle', 'expired handle' );

    for my $junk ( 'nodot', 'a.b.c.d', '!!!.???', '' ) {
        my $e = rejection( sub { $gw->read_handle($junk) } );
        ok( $e->status == 400 || $e->status == 403, "garbage '$junk' refused" );
    }
    is(
        rejection( sub { $gw->read_handle('nodot') } )->reason,
        'malformed handle',
        'malformed handle'
    );
};

subtest 'origins and key' => sub {
    my ($gw) = make_gateway();
    for my $origin (
        'http://localhost:3000', 'http://127.0.0.1:8080',
        'http://[::1]:5000',     'http://app.localhost'
        )
    {
        ok( !rejection( sub { $gw->check_origin($origin) } ), "$origin needs no listing" );
    }
    ok( !rejection( sub { $gw->check_origin('https://shop.example.com/') } ), 'listed origin' );
    is( rejection( sub { $gw->check_origin('https://evil.example') } )->status,
        403, 'unlisted origin' );
    ok( !rejection( sub { $gw->check_origin(undef) } ), 'missing origin allowed' );

    is( rejection( sub { $gw->check_key(undef) } )->status,      401,       'missing key' );
    is( rejection( sub { $gw->check_key('pk_wrong') } )->reason, 'bad key', 'wrong key' );
    ok( !rejection( sub { $gw->check_key($KEY) } ), 'right key' );
};

subtest 'prepare: what the browser may and may not name' => sub {
    my ($gw) = make_gateway();
    my ( $method, $params, $minted ) =
        prep( $gw, { message => 'hi', config_url => 'https://evil/swml', id => 'someone-else' } );
    is( $method,               'chat',      'chat is the default method' );
    is( $params->{config_url}, $CONFIG_URL, 'config_url is ours, not theirs' );
    ok( $minted, 'the first chat mints a handle' );
    is( $params->{id}, $gw->read_handle($minted), 'the id comes from the signed handle' );

    my ( undef, $again, $none ) = prep( $gw, { message => 'more', handle => $minted } );
    is( $none,        undef,         'later chats reuse the handle' );
    is( $again->{id}, $params->{id}, 'same conversation' );

    is(
        rejection( sub { prep( $gw, { method => 'delete', message => 'x' } ) } )->reason,
        'method not allowed',
        'only start/chat/log/end pass'
    );
    is(
        rejection( sub { prep( $gw, { method => 'end' } ) } )->reason,
        'end requires a handle',
        'end needs a handle'
    );
    is(
        rejection( sub { prep( $gw, { method => 'log' } ) } )->reason,
        'log requires a handle',
        'log needs a handle'
    );
    my ( $end, $end_params ) = prep( $gw, { method => 'end', handle => $minted } );
    is( $end, 'end_conversation', 'end maps to end_conversation' );
    is_deeply( $end_params, { id => $params->{id} }, 'end params' );
    my ( $log, $log_params ) = prep( $gw, { method => 'log', handle => $minted, id => 'other' } );
    is( $log,              'chat_log',    'log maps to chat_log' );
    is( $log_params->{id}, $params->{id}, 'log is scoped to the handle, not the body' );

    is(
        rejection( sub { prep( $gw, { message => '   ', handle => $minted } ) } )->reason,
        'message is required',
        'an empty message is refused'
    );

    my ( $start, $start_params, $start_minted ) = prep( $gw, { method => 'start' } );
    is( $start, 'create_conversation', 'start opens a conversation' );
    ok( $start_minted,                         'start mints' );
    ok( !exists $start_params->{user_message}, 'with no message' );

    is(
        rejection(
            sub {
                $gw->prepare( { message => 'x' }, origin => 'https://evil.example', key => $KEY );
            }
        )->status,
        403,
        'origin enforced in prepare'
    );
    is(
        rejection( sub { $gw->prepare( { message => 'x' }, origin => undef, key => 'nope' ) } )
            ->status,
        401,
        'key enforced in prepare'
    );
};

subtest 'caps' => sub {
    my ($gw) = make_gateway( max_new_conversations => 2 );
    prep( $gw, { message => 'a' } ) for 1 .. 2;
    is( rejection( sub { prep( $gw, { message => 'a' } ) } )->status, 429, 'minting is capped' );

    my ($turns) = make_gateway( max_turns => 2 );
    my ( undef, undef, $h1 ) = prep( $turns, { message => 'a' } );
    prep( $turns, { message => 'b', handle => $h1 } );
    is(
        rejection( sub { prep( $turns, { message => 'c', handle => $h1 } ) } )->reason,
        'conversation turn limit reached',
        'turns are capped per conversation'
    );
    my ( undef, undef, $h2 ) = prep( $turns, { message => 'a' } );
    ok( $h2, 'one conversation at its cap does not stop another' );
};

subtest 'page context (user_meta_data)' => sub {
    my ($gw) = make_gateway();
    my $page = { metadata => { page => { title => 'Pricing' } } };
    my ( undef, $start ) = prep( $gw, { method => 'start', user_meta_data => $page } );
    is_deeply( $start->{user_meta_data}, $page, 'reaches the create params' );
    my ( undef, $chat ) = prep( $gw, { message => 'hi', user_meta_data => $page } );
    is_deeply( $chat->{user_meta_data}, $page, 'rides the chat path too' );
    for my $body (
        { method => 'start' },
        { method => 'start', user_meta_data => undef },
        { method => 'start', user_meta_data => {} }
        )
    {
        my ( undef, $p ) = prep( $gw, $body );
        ok( !exists $p->{user_meta_data}, 'absent/null/empty -> not forwarded' );
    }
    for my $bad ( 'a string', 42, [ 'a', 'list' ], JSON::true ) {
        is(
            rejection( sub { prep( $gw, { method => 'start', user_meta_data => $bad } ) } )->status,
            400,
            'must be an object'
        );
    }
    my $fat = { junk => 'x' x ( SignalWire::AIChat::Gateway::MAX_USER_METADATA_BYTES + 1 ) };
    is( rejection( sub { prep( $gw, { method => 'start', user_meta_data => $fat } ) } )->status,
        413, 'bounded' );

    my ($one) = make_gateway( max_new_conversations => 1 );
    ok( rejection( sub { prep( $one, { method => 'start', user_meta_data => 'nope' } ) } ),
        'malformed bag refused' );
    my ( undef, undef, $minted ) = prep( $one, { method => 'start' } );
    ok( $minted, '... before a conversation was charged' );
};

subtest 'message size' => sub {
    my ($gw) = make_gateway( max_new_conversations => 1, max_turns => 1 );
    my $max = SignalWire::AIChat::Gateway::MAX_MESSAGE_BYTES;
    is( rejection( sub { prep( $gw, { message => 'x' x ( $max + 1 ) } ) } )->status,
        413, 'over the limit' );
    my $snowmen = "\x{2603}" x ( int( $max / 3 ) + 1 );    # 3 UTF-8 bytes each
    is( rejection( sub { prep( $gw, { message => $snowmen } ) } )->status,
        413, 'counts UTF-8 bytes, not characters' );
    my ( undef, undef, $minted ) = prep( $gw, { message => 'x' x $max } );
    ok( $minted, 'at the limit passes, and the rejected ones minted nothing' );
    is(
        rejection( sub { prep( $gw, { message => 'x' x ( $max + 1 ), handle => $minted } ) } )
            ->status,
        413,
        'oversized with a handle'
    );
};

subtest 'visible_messages / last_activity' => sub {
    my $raw = [
        { role => 'system',    content => 'Secret instructions', timestamp => 1 },
        { role => 'user',      content => 'hi',     timestamp => 123, id         => 'x' },
        { role => 'assistant', content => 'Hello!', timestamp => 124, tool_calls => [] },
        { role => 'tool',      content => 'internal' },
        { role => 'assistant', content => '   ' },
        'not a dict',
    ];
    is_deeply(
        SignalWire::AIChat::Gateway->visible_messages($raw),
        [
            { role => 'user',      content => 'hi',     timestamp => 123 / 1_000_000 },
            { role => 'assistant', content => 'Hello!', timestamp => 124 / 1_000_000 },
        ],
        'only the dialogue, reduced, in seconds'
    );
    is(
        SignalWire::AIChat::Gateway->last_activity(
            [
                { timestamp => 1_000_000 },
                { timestamp => 3_000_000 },
                { role      => 'tool', timestamp => 5_000_000 }
            ]
        ),
        5,
        'newest message of any role, in seconds'
    );
    is( SignalWire::AIChat::Gateway->last_activity( [ { role => 'user' } ] ), undef, 'undated' );
    is( SignalWire::AIChat::Gateway->last_activity(undef),                    undef, 'none' );
    is( SignalWire::AIChat::Gateway->last_activity( [ { timestamp => 'not a number' } ] ),
        undef, 'a string is not a timestamp' );
    is_deeply( SignalWire::AIChat::Gateway->visible_messages(undef), [], 'junk survives' );
};

# --- PSGI router -------------------------------------------------------------

sub call_app {
    my ( $app, %req ) = @_;
    my $content =
        defined $req{body} ? ( ref $req{body} ? encode_json( $req{body} ) : $req{body} ) : '';
    open my $in, '<', \$content;
    my %env = (
        REQUEST_METHOD     => $req{method} // 'POST',
        PATH_INFO          => $req{path}   // '/',
        CONTENT_LENGTH     => length $content,
        'psgi.input'       => $in,
        'psgi.streaming'   => $req{streaming} // 1,
        HTTP_AUTHORIZATION => 'Bearer ' . ( $req{key} // $KEY ),
        ( $req{origin} ? ( HTTP_ORIGIN => $req{origin} ) : () ),
        %{ $req{env} // {} },
    );
    my $res = $app->( \%env );
    if ( ref $res eq 'CODE' ) {
        my ( @head, $body );
        $body = '';
        $res->(
            sub {
                @head = @{ $_[0] };
                return StreamWriter->new( sink => \$body );
            }
        );
        return { status => $head[0], headers => { @{ $head[1] } }, body => $body, streamed => 1 };
    }
    return {
        status  => $res->[0],
        headers => { @{ $res->[1] } },
        body    => join( '', @{ $res->[2] } )
    };
}

{

    package StreamWriter;    ## no critic (ProhibitMultiplePackages)
    use Moo;
    has 'sink'   => ( is => 'ro' );
    has 'writes' => ( is => 'ro', default => sub { [] } );
    has 'closed' => ( is => 'rw', default => sub { 0 } );

    sub write {
        my ( $self, $chunk ) = @_;
        ${ $self->sink } .= $chunk;
        push @{ $self->writes }, $chunk;
        return;
    }
    sub close { my ($self) = @_; $self->closed(1); return }    ## no critic (ProhibitBuiltinHomonyms)
}

subtest 'router: start, log, end, chat' => sub {
    my ( $gw, $ua ) = make_gateway( conversation_timeout => 900, chunks => [ ' ', ' ' ] );
    my $app = $gw->router;

    my $origin  = 'https://shop.example.com';
    my $started = call_app( $app, body => { method => 'start' }, origin => $origin );
    is( $started->{status}, 200, 'start 200' );
    my $handle = $started->{headers}{'X-Chat-Handle'};
    ok( $handle, 'minted handle in X-Chat-Handle' );
    is( $started->{headers}{'Access-Control-Allow-Origin'}, $origin, 'CORS for an allowed origin' );
    is_deeply(
        decode_json( $started->{body} ),
        { greeting => 'Hi, I am Sigmond.', status => 'created', timeout => 900 },
        'start summary'
    );
    is( $ua->seen->[-1]{params}{conversation_timeout}, 900, 'timeout forwarded upstream' );

    my $log    = call_app( $app, body => { method => 'log', handle => $handle } );
    my $logged = decode_json( $log->{body} );
    is_deeply(
        [ map { $_->{content} } @{ $logged->{messages} } ],
        [ 'hi', 'hi there' ],
        'log hides the system prompt'
    );
    is( $logged->{last_activity}, 3, 'last_activity from the raw log' );
    is(
        $ua->seen->[-1]{params}{id},
        $gw->read_handle($handle),
        'log asked for the handle\'s conversation'
    );

    my $chat = call_app( $app, body => { message => 'hi', handle => $handle } );
    ok( $chat->{streamed}, 'chat streams' );
    is( $chat->{status}, 200, 'chat 200' );
    like( $chat->{body}, qr/\A  \{/, 'keepalive padding passed through unbuffered' );
    is( decode_json( $chat->{body} )->{result}{response}, 'hi there',  'service body relayed' );
    is( $ua->seen->[-1]{params}{config_url},              $CONFIG_URL, 'config_url injected' );

    my $buffered =
        call_app( $app, body => { message => 'again', handle => $handle }, streaming => 0 );
    ok( !$buffered->{streamed}, 'no psgi.streaming -> buffered' );
    is( decode_json( $buffered->{body} )->{result}{response}, 'hi there', 'buffered body' );

    my $end = call_app( $app, body => { method => 'end', handle => $handle } );
    is_deeply( decode_json( $end->{body} ), { status => 'ended' }, 'end' );
};

subtest 'router: rejections and preflight' => sub {
    my ($gw) = make_gateway();
    my $app = $gw->router;

    my $bad_key = call_app( $app, body => { message => 'x' }, key => 'nope' );
    is( $bad_key->{status}, 401, 'bad key' );
    is_deeply( decode_json( $bad_key->{body} ), { error => 'bad key' }, 'error body' );

    is( call_app( $app, body => '[1,2]' )->{status}, 400, 'body must be an object' );
    is( decode_json( call_app( $app, body => 'not json' )->{body} )->{error},
        'bad request', 'invalid JSON' );
    is(
        decode_json(
            call_app( $app, body => { method => 'start', user_meta_data => [1] } )->{body}
        )->{error},
        'user_meta_data must be an object',
        'a malformed bag is a clean 400'
    );

    my $big = 'x' x ( SignalWire::AIChat::Gateway::MAX_REQUEST_BODY_BYTES + 1 );
    is( call_app( $app, body => $big )->{status}, 413, 'oversized body refused unparsed' );
    is( call_app( $app, body => '{}', env => { CONTENT_LENGTH => 10_000_000 } )->{status},
        413, 'declared Content-Length over the limit' );

    my $pre = call_app( $app, method => 'OPTIONS', origin => 'https://shop.example.com' );
    is( $pre->{status},                                  204,             'preflight 204' );
    is( $pre->{headers}{'Access-Control-Allow-Methods'}, 'POST, OPTIONS', 'allow headers' );
    my $evil = call_app( $app, method => 'OPTIONS', origin => 'https://evil.example' );
    ok( !exists $evil->{headers}{'Access-Control-Allow-Origin'}, 'no CORS for a refused origin' );

    is( call_app( $app, method => 'GET' )->{status},    405, 'wrong method' );
    is( call_app( $app, path   => '/other' )->{status}, 404, 'unknown path' );
};

done_testing;
