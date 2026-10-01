#!/usr/bin/env perl
# AgentBase.on_call_end, WebMixin.add_per_call_config and WebMixin.mount --
# real behavior through the rendered SWML, the per-request clone and the PSGI
# app (python reference: core/agent_base.py on_call_end, core/mixins/web_mixin.py
# add_per_call_config / mount).
use strict;
use warnings;
use Test::More;
use JSON         qw(encode_json decode_json);
use MIME::Base64 qw(encode_base64);

use SignalWire::Agent::AgentBase;

sub new_agent {
    my (%extra) = @_;
    return SignalWire::Agent::AgentBase->new(
        name                => 'a',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
        %extra,
    );
}

my $AUTH = 'Basic ' . encode_base64( 'u:p', '' );

sub render {
    my ( $agent, $body ) = @_;
    my ( $status, undef, $json ) = $agent->handle_request( $body ? 'POST' : 'GET',
        'http://h/', { Authorization => $AUTH }, $body );
    is( $status, 200, 'render status 200' );
    my $doc = decode_json($json);
    my ($ai) = map { $_->{ai} } grep { ref $_ eq 'HASH' && $_->{ai} } @{ $doc->{sections}{main} };
    return $ai;
}

subtest 'on_call_end registers the reserved hangup_hook once' => sub {
    my $agent = new_agent();
    my @seen;
    my $h1  = sub { push @seen, [ 'h1', @_ ] };
    my $h2  = sub { push @seen, [ 'h2', @_ ] };
    my $ret = $agent->on_call_end($h1);
    is( $ret, $h1, 'returns the handler (decorator parity)' );
    $agent->on_call_end($h2);

    my $ai    = render($agent);
    my @hooks = grep { $_->{function} eq 'hangup_hook' } @{ $ai->{SWAIG}{functions} };
    is( scalar @hooks,          1, 'hangup_hook rendered exactly once' );
    is( $hooks[0]{description}, 'Internal: fires when the call ends.', 'reserved description' );
    ok( $ai->{params}{swaig_post_conversation}, 'swaig_post_conversation turned on' );
    ok( JSON::is_bool( $ai->{params}{swaig_post_conversation} ), 'as a JSON boolean' );

    my $handler = $agent->tools->{hangup_hook}{_handler};
    my $raw     = { call_id => 'c-1', call_log => [ { role => 'user', content => 'hi' } ] };
    my $result  = $handler->( {}, $raw );
    isa_ok( $result, 'SignalWire::SWAIG::FunctionResult' );
    is_deeply( [ map { $_->[0] } @seen ], [qw(h1 h2)],      'handlers run in registration order' );
    is_deeply( $seen[0][1],               $raw->{call_log}, 'call_log passed' );
    is( $seen[0][2], $raw, 'raw request passed' );
};

subtest 'on_call_end resolves raw_call_log and isolates failures' => sub {
    my $agent = new_agent();
    my @seen;
    $agent->on_call_end( sub { die "boom\n" } );
    $agent->on_call_end( sub { push @seen, $_[0] } );
    my $handler = $agent->tools->{hangup_hook}{_handler};

    $handler->(
        {}, { call_log => [], raw_call_log => [ { role => 'assistant', content => 'x' } ] }
    );
    is_deeply(
        $seen[0],
        [ { role => 'assistant', content => 'x' } ],
        'empty call_log falls through to raw_call_log; a dying handler does not stop the next'
    );

    $handler->( {}, undef );
    is_deeply( $seen[1], [], 'no log at all -> empty list' );
};

subtest 'on_call_end leaves an explicit swaig_post_conversation false alone' => sub {
    my $agent = new_agent();
    $agent->set_param( 'swaig_post_conversation', JSON::false );
    $agent->on_call_end( sub { } );
    my $ai = render($agent);
    ok( !$ai->{params}{swaig_post_conversation}, 'explicit false kept' );
};

subtest 'add_per_call_config accumulates, set_dynamic_config_callback replaces' => sub {
    my $agent = new_agent();
    my @order;
    my $first = sub {
        my ( $q, $b, $h, $ephemeral ) = @_;
        push @order, 'first';
        $ephemeral->set_global_data( { tier => 'gold' } );
    };
    my $second = sub {
        my ( $q, $b, $h, $ephemeral ) = @_;
        push @order, 'second';

        # A later callback sees what an earlier one configured.
        $ephemeral->set_global_data(
            { %{ $ephemeral->global_data }, seen => $ephemeral->global_data->{tier} } );
    };
    is( $agent->add_per_call_config($first), $agent, 'chains' );
    is( $agent->dynamic_config_callback,     $first, 'one callback is returned as-is' );
    $agent->add_per_call_config($second);

    my $ai = render($agent);
    is_deeply( \@order,             [qw(first second)], 'both run, in registration order' );
    is_deeply( $ai->{global_data},  { tier => 'gold', seen => 'gold' }, 'second saw the first' );
    is_deeply( $agent->global_data, {}, 'configured the clone, not the shared agent' );

    @order = ();
    $agent->set_dynamic_config_callback( sub { push @order, 'only' } );
    render($agent);
    is_deeply( \@order, ['only'], 'set_dynamic_config_callback replaced the chain' );

    $agent->dynamic_config_callback(undef);
    is( $agent->dynamic_config_callback, undef, 'assigning undef clears it' );
};

subtest 'a per-call config + a handler-backed tool renders (clone keeps handlers)' => sub {
    my $agent = new_agent();
    my $tool  = sub { return 'ok' };
    $agent->define_tool( name => 't', description => 'd', parameters => {}, handler => $tool );
    $agent->on_call_end( sub { } );
    $agent->add_per_call_config( sub { $_[3]->set_global_data( { x => 1 } ) } );
    my $ai = render($agent);
    is_deeply( $ai->{global_data}, { x => 1 }, 'rendered off the clone' );
    my $clone = $agent->_clone_for_request;
    is( $clone->tools->{t}{_handler}, $tool, 'handler shared by reference' );
    isnt( $clone->tools, $agent->tools, 'tool table itself copied' );
};

sub psgi_get {
    my ( $app, $path, %env ) = @_;
    open my $in, '<', \'';
    my $res = $app->(
        {
            REQUEST_METHOD    => 'GET',
            PATH_INFO         => $path,
            SCRIPT_NAME       => '',
            QUERY_STRING      => '',
            SERVER_NAME       => 'h',
            SERVER_PORT       => 80,
            'psgi.url_scheme' => 'http',
            'psgi.input'      => $in,
            %env,
        }
    );
    return $res;
}

subtest 'mount dispatches extra apps after the agent routes' => sub {
    my $agent = new_agent();
    my @seen;
    my $chat = sub {
        my ($env) = @_;
        push @seen, [ $env->{SCRIPT_NAME}, $env->{PATH_INFO} ];
        return $env->{PATH_INFO} eq '/hello'
            ? [ 200, [ 'Content-Type' => 'text/plain' ], ['chat'] ]
            : [ 404, [], ['nope'] ];
    };
    my $other = sub {
        my ($env) = @_;
        return $env->{PATH_INFO} eq '/say'
            ? [ 200, [], ['other'] ]
            : [ 404, [], ['nope'] ];
    };

    my $app = $agent->psgi_app;    # built BEFORE mounting
    is( $agent->mount( $chat, prefix => '/chat/' ), $agent, 'chains' );
    $agent->mount( $other, prefix => '/chat' );

    my $res = psgi_get( $app, '/chat/hello' );
    is( $res->[0], 200, 'mounted route served' );
    is_deeply( $res->[2], ['chat'],              'by the mounted app' );
    is_deeply( $seen[0],  [ '/chat', '/hello' ], 'SCRIPT_NAME/PATH_INFO adjusted' );

    $res = psgi_get( $app, '/chat/say' );
    is_deeply( $res->[2], ['other'], 'a 404 falls through to the next app at the same prefix' );

    is( psgi_get( $app, '/health' )->[0],       200, 'agent routes keep precedence' );
    is( psgi_get( $app, '/chat/missing' )->[0], 404, 'unclaimed mounted path is a 404' );
    is( psgi_get( $app, '/elsewhere' )->[0],    404, 'paths outside every prefix are a 404' );

    my $err = do {
        local $@;
        eval { $agent->mount('not an app') };
        $@;
    };
    like( $err, qr/PSGI app/, 'a non-app is refused' );
};

done_testing;
