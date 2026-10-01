#!/usr/bin/env perl
# HandoffRouter (SignalWire::AIChat::Handoff): moving one conversation between
# voice and text. Mirrors the python reference tests
# (tests/unit/ai_chat/test_handoff.py).
use strict;
use warnings;
use Test::More;
use JSON        qw(encode_json decode_json);
use Time::HiRes ();

use SignalWire::AIChat::Client;
use SignalWire::AIChat::Gateway;
use SignalWire::AIChat::Handoff;

{

    # A shared registry that hands back COPIES, like one backed by a cache.
    package CopyingRegistry;    ## no critic (ProhibitMultiplePackages)
    require Tie::Hash;
    our @ISA = ('Tie::StdHash');
    sub _copy { my ($v) = @_; return $v ? SignalWire::AIChat::NonceEntry->new( %{$v} ) : $v }
    sub FETCH { my ( $self, $key ) = @_; return _copy( $self->{$key} ) }
    sub STORE { my ( $self, $key, $value ) = @_; $self->{$key} = _copy($value); return }

    # A registry that records every assignment (key, redeemed).
    package RecordingRegistry;    ## no critic (ProhibitMultiplePackages)
    our @ISA = ('Tie::StdHash');
    our @ASSIGNED;

    sub STORE {
        my ( $self, $key, $value ) = @_;
        push @ASSIGNED, [ $key, $value->redeemed ? 1 : 0 ];
        $self->{$key} = $value;
        return;
    }
}

my $GATEWAY = SignalWire::AIChat::Gateway->new(
    config_url => 'https://agent.example.com/swml',
    key        => 'pk_test',
    secret     => 'handoff-secret',
    client     => SignalWire::AIChat::Client->new(
        project => 'p',
        token   => 't',
        url     => 'https://svc.invalid/'
    ),
);

sub make_router {
    my ( $events, %extra ) = @_;
    return SignalWire::AIChat::Handoff->new(
        gateway      => $GATEWAY,
        capture_leg  => sub { push @$events, [ 'capture',  @_ ]; return 1 },
        end_call     => sub { push @$events, [ 'end_call', @_ ]; return },
        send_message => sub { push @$events, [ 'say',      @_ ]; return 1 },
        %extra,
    );
}

sub post {
    my ( $app, $path, $body, %env ) = @_;
    my $content = ref $body ? encode_json($body) : $body // '';
    open my $in, '<', \$content;
    my $res = $app->(
        {
            REQUEST_METHOD => 'POST',
            PATH_INFO      => $path,
            CONTENT_LENGTH => length $content,
            'psgi.input'   => $in,
            %env,
        }
    );
    return { status => $res->[0], json => eval { decode_json( join '', @{ $res->[2] } ) } };
}

subtest 'redemption' => sub {
    my @events;
    my $router = make_router( \@events );
    my $app    = $router->router;
    $router->register( 'n1', conversation_id => 'conv-root', call_id => 'call-9' );
    my $res = post( $app, '/handoff', { nonce => 'n1' } );
    is( $res->{status},                                200,           'handoff answers 200' );
    is( $GATEWAY->read_handle( $res->{json}{handle} ), 'conv-root.1', 'a fresh dotted leg id' );
    is_deeply(
        \@events,
        [ [ 'end_call', 'call-9' ], [ 'capture', 'conv-root', 'voice' ] ],
        'the call ends before the leg is captured'
    );

    my $spent   = post( $app, '/handoff', { nonce => 'n1' } );
    my $unknown = post( $app, '/handoff', { nonce => 'never-existed' } );
    is( $spent->{status}, 404, 'single use' );
    is_deeply( $spent->{json}, $unknown->{json}, 'spent and unknown are indistinguishable' );
    is( post( $app, '/handoff', {} )->{status}, 404, 'missing nonce' );

    is( $router->next_conversation_id->('root.2'), 'root.3', 'leg ids increment' );
    is( $router->next_conversation_id->('root'),   'root.1', 'first leg' );

    my $expired = SignalWire::AIChat::Handoff->new( gateway => $GATEWAY, nonce_ttl => -1 );
    $expired->register( 'n1', conversation_id => 'c', call_id => 'x' );
    is( $expired->redeem('n1'), undef, 'expired nonces are not redeemable' );
};

subtest 'registration: the first one stands' => sub {
    my @events;
    my $router = make_router( \@events, max_messages_per_call => 1 );
    $router->register( 'n', conversation_id => 'c', call_id => 'call-1' );
    my $first = $router->_nonces->{n}->issued_at;
    ok( $router->say( 'n',  'one' ), 'first message' );
    ok( !$router->say( 'n', 'two' ), 'capped' );
    $router->register( 'n', conversation_id => 'c', call_id => 'call-1' );
    ok( !$router->say( 'n', 'three' ), 'a repeat registration keeps the typing count' );
    is( $router->_nonces->{n}->issued_at, $first, 'and the registration time' );

    @events = ();
    my $moved = make_router( \@events );
    $moved->register( 'n', conversation_id => 'conv-a', call_id => 'call-a' );
    $moved->register( 'n', conversation_id => 'conv-b', call_id => 'call-b' );
    is( post( $moved->router, '/say', { nonce => 'n', text => 'hi' } )->{status}, 200, 'say ok' );
    is_deeply( \@events, [ [ 'say', 'call-a', 'hi' ] ], 'a live nonce cannot be moved' );

    my $app = $moved->router;
    $moved->register( 'r', conversation_id => 'conv-root', call_id => 'call-9' );
    is( post( $app, '/handoff', { nonce => 'r' } )->{status}, 200, 'redeemed' );
    $moved->register( 'r', conversation_id => 'conv-root', call_id => 'call-10' );
    is( post( $app, '/handoff', { nonce => 'r' } )->{status},
        404, 'a redeemed nonce cannot be redeemed again' );
    @events = ();
    is( post( $app, '/say', { nonce => 'r', text => 'late' } )->{status},
        404, 'a redeemed nonce cannot type' );
    is_deeply( \@events, [], 'nothing delivered' );

    my $entry = $moved->_nonces->{r};
    ok( $entry->redeemed, 'kept, marked redeemed' );
    $entry->issued_at( $entry->issued_at - $moved->nonce_ttl - 1 );
    $moved->register( 'r', conversation_id => 'conv-new', call_id => 'call-11' );
    ok( !$moved->_nonces->{r}->redeemed, 'after the TTL it can be registered afresh' );
    is( $moved->_nonces->{r}->conversation_id, 'conv-new', 'with the new conversation' );
};

subtest 'shared registries' => sub {
    tie my %recording, 'RecordingRegistry';
    my $router = SignalWire::AIChat::Handoff->new( gateway => $GATEWAY, registry => \%recording );
    $router->register( 'n', conversation_id => 'c', call_id => 'call-1' );
    ok( defined $router->redeem('n'), 'redeemed' );
    is_deeply(
        \@RecordingRegistry::ASSIGNED,
        [ [ 'n', 0 ], [ 'n', 1 ] ],
        'the redemption is assigned back'
    );

    tie my %copying, 'CopyingRegistry';
    my @attempts;
    my $flaky = SignalWire::AIChat::Handoff->new(
        gateway               => $GATEWAY,
        max_messages_per_call => 1,
        registry              => \%copying,
        send_message          => sub {
            push @attempts, $_[1];
            die "platform unavailable\n" if @attempts == 1;
            return 1;
        },
    );
    $flaky->register( 'n', conversation_id => 'c', call_id => 'call-1' );
    ok( !$flaky->say( 'n', 'first' ),        'failed delivery' );
    ok( $flaky->say( 'n',  'again' ),        'its slot was given back' );
    ok( !$flaky->say( 'n', 'over the cap' ), 'cap still holds' );
    is_deeply( \@attempts, [ 'first', 'again' ], 'attempts' );

    tie my %copy2, 'CopyingRegistry';
    my $once = SignalWire::AIChat::Handoff->new( gateway => $GATEWAY, registry => \%copy2 );
    $once->register( 'n', conversation_id => 'c', call_id => 'call-1' );
    ok( defined $once->redeem('n'), 'redeemed through a copying registry' );
    $once->register( 'n', conversation_id => 'c', call_id => 'call-1' );
    is( $once->redeem('n'), undef, 'stays redeemed' );
};

subtest 'escalate' => sub {
    my @events;
    my $router = make_router( \@events );
    my $app    = $router->router;
    my $handle = $GATEWAY->mint_handle('conv-root.5');
    is( post( $app, '/escalate', { handle => $handle } )->{status}, 200, 'escalate answers 200' );
    is_deeply( \@events, [ [ 'capture', 'conv-root.5', 'chat' ] ], 'captured before returning' );
    is( post( $app, '/escalate', { handle => 'forged' } )->{status}, 404, 'forged handle' );
    is( post( $app, '/escalate', {} )->{status},                     400, 'missing handle' );
};

subtest 'say' => sub {
    my @events;
    my $router = make_router( \@events, max_messages_per_call => 3 );
    my $app    = $router->router;
    $router->register( 'n2', conversation_id => 'conv-root', call_id => 'call-9' );
    is( post( $app, '/say', { nonce => 'n2', text => '  hello  ' } )->{status}, 200, 'delivered' );
    is_deeply( \@events, [ [ 'say', 'call-9', 'hello' ] ], 'trimmed, to the nonce\'s call' );
    is( post( $app, '/say', { nonce => 'n2', text => 'x' } )->{status}, 200, 'repeatable' )
        for 1 .. 2;
    is( post( $app, '/say', { nonce => 'n2', text => 'x' } )->{status}, 404, 'capped per call' );
    $router->register( 'n3', conversation_id => 'c', call_id => 'call-1' );
    is( post( $app, '/say', { nonce => 'n3',      text => '   ' } )->{status}, 404, 'empty text' );
    is( post( $app, '/say', { nonce => 'guessed', text => 'hi' } )->{status}, 404,
        'unknown nonce' );

    my $mute = SignalWire::AIChat::Handoff->new( gateway => $GATEWAY );
    $mute->register( 'n', conversation_id => 'c', call_id => 'call-1' );
    ok( !$mute->say( 'n', 'hello' ), 'disabled without a sender' );
};

subtest 'size limits' => sub {
    my @events;
    my $router = make_router( \@events );
    my $app    = $router->router;
    my $max    = SignalWire::AIChat::Gateway::MAX_MESSAGE_BYTES;
    $router->register( 'n', conversation_id => 'conv-root', call_id => 'call-9' );
    my $big = post( $app, '/say', { nonce => 'n', text => 'x' x ( $max + 1 ) } );
    is( $big->{status}, 413, 'text over the limit' );
    is_deeply( $big->{json}, { error => 'message too large' }, 'body' );
    is( post( $app, '/say', { nonce => 'never-existed', text => 'x' x ( $max + 1 ) } )->{status},
        413, 'answered before the nonce lookup' );
    is_deeply( \@events, [], 'nothing delivered' );
    is( post( $app, '/say', { nonce => 'n', text => 'x' x $max } )->{status}, 200, 'at the limit' );
    ok( !$router->say( 'n', 'x' x ( $max + 1 ) ), 'say() itself refuses oversized text' );

    my $pad = ' ' x ( SignalWire::AIChat::Gateway::MAX_REQUEST_BODY_BYTES + 1 );
    for my $path (qw(/handoff /escalate /say)) {
        my $r = post( $app, $path, $pad );
        is( $r->{status}, 413, "$path oversized body" );
        is_deeply( $r->{json}, { error => 'request too large' }, "$path body" );
    }
    $router->register( 'h', conversation_id => 'conv-root', call_id => 'call-9' );
    post( $app, '/handoff',
              '{"nonce":"h","pad":"'
            . ( 'x' x SignalWire::AIChat::Gateway::MAX_REQUEST_BODY_BYTES )
            . '"}' );
    is( post( $app, '/handoff', { nonce => 'h' } )->{status},
        200, 'an oversized handoff leaves the nonce redeemable' );
};

subtest 'origins, methods, paths' => sub {
    my $app = make_router( [] )->router;
    is( post( $app, '/say', { nonce => 'n' }, HTTP_ORIGIN => 'https://evil.example' )->{status},
        403, 'disallowed origin' );
    is( post( $app, '/nope', {} )->{status},                             404, 'unknown path' );
    is( $app->( { REQUEST_METHOD => 'GET', PATH_INFO => '/say' } )->[0], 405, 'wrong method' );
};

subtest 'capture failures do not block the switch' => sub {
    my $slow = SignalWire::AIChat::Handoff->new(
        gateway         => $GATEWAY,
        capture_timeout => 0.05,
        capture_leg     => sub { Time::HiRes::sleep(10); return 1 },
    );
    $slow->register( 'n', conversation_id => 'c', call_id => 'call-1' );
    my $t0     = Time::HiRes::time();
    my $handle = $slow->redeem('n');
    ok( Time::HiRes::time() - $t0 < 5, 'the wait is bounded by capture_timeout' );
    is( $GATEWAY->read_handle($handle), 'c.1', 'a timed-out capture still switches' );

    my $boom = SignalWire::AIChat::Handoff->new(
        gateway     => $GATEWAY,
        capture_leg => sub { die "storage down\n" }
    );
    $boom->register( 'n', conversation_id => 'c', call_id => 'call-1' );
    is( $GATEWAY->read_handle( $boom->redeem('n') ), 'c.1', 'a dying capture still switches' );
};

done_testing;
