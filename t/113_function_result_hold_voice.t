#!/usr/bin/env perl
# FunctionResult: change_voice, hold(prompt, timeout, step, timeout_step),
# set_tool_response, rpc_ai_global_data (+ rpc_ai_message global_data).
# Wire shapes mirror signalwire.core.function_result in the python reference.
use strict;
use warnings;
use Test::More;
use JSON ();

use SignalWire::SWAIG::FunctionResult;

sub fr { my (@args) = @_; return SignalWire::SWAIG::FunctionResult->new(@args) }

subtest 'change_voice emits the change_voice action' => sub {
    my $r   = fr();
    my $ret = $r->change_voice('elevenlabs.rachel');
    is( $ret, $r, 'chains' );
    is_deeply( $r->to_hash->{action}, [ { change_voice => 'elevenlabs.rachel' } ], 'action shape' );
};

subtest 'set_tool_response builds the structured response' => sub {
    my $r = fr();
    is( $r->set_tool_response( tool_result => 'status: on hold', tool_prompt => 'Say hi' ),
        $r, 'chains' );
    is_deeply( $r->to_hash,
        { response => { tool_result => 'status: on hold', tool_prompt => 'Say hi' } },
        'both fields' );

    is_deeply(
        fr()->set_tool_response( tool_result => 'done' )->to_hash,
        { response => { tool_result => 'done' } },
        'tool_result only'
    );

    # An empty structured response is falsy (python `if self.response`), so the
    # default response is emitted instead of an empty object.
    is_deeply(
        fr()->set_tool_response->to_hash,
        { response => 'Action completed.' },
        'no fields -> empty object is not emitted'
    );
};

subtest 'hold: bare integer form is unchanged' => sub {
    is_deeply( fr()->hold->to_hash->{action},       [ { hold => 300 } ], 'default 300' );
    is_deeply( fr()->hold(120)->to_hash->{action},  [ { hold => 120 } ], 'number = timeout' );
    is_deeply( fr()->hold(5000)->to_hash->{action}, [ { hold => 900 } ], 'clamped high' );
    is_deeply( fr()->hold(-4)->to_hash->{action},   [ { hold => 0 } ],   'clamped low' );
    my $h = fr()->hold(120)->to_hash;
    ok( !exists $h->{post_process}, 'no prompt -> no post_process' );
    is( $h->{response}, undef, 'no prompt -> no response' );
};

subtest 'hold: prompt sets the structured response and post_process' => sub {
    my $h = fr()->hold( 'Tell the caller you are placing them on hold.', 120 )->to_hash;
    is_deeply( $h->{action}, [ { hold => 120 } ], 'bare timeout' );
    is_deeply(
        $h->{response},
        {
            tool_result => 'status: on hold',
            tool_prompt => 'Tell the caller you are placing them on hold.',
        },
        'structured response'
    );
    ok( JSON::is_bool( $h->{post_process} ) && $h->{post_process}, 'post_process true' );

    # A string that looks like a number is still a prompt (python str vs int).
    my $s = fr()->hold('120')->to_hash;
    is_deeply( $s->{action}, [ { hold => 300 } ], 'string "120" is a prompt, timeout default' );
    is( $s->{response}{tool_prompt}, '120', 'string kept as the prompt' );
};

subtest 'hold: a boolean first argument is ignored' => sub {
    my $h = fr()->hold(JSON::true)->to_hash;
    is_deeply( $h->{action}, [ { hold => 300 } ], 'bool is neither prompt nor timeout' );
    ok( !exists $h->{post_process}, 'no post_process' );
};

subtest 'hold: step / timeout_step routing' => sub {
    my $h = fr()->hold(
        'Tell the caller you are checking.', 300,
        step         => 'back_with_agent',
        timeout_step => 'take_a_message',
    )->to_hash;
    is_deeply(
        $h->{action},
        [
            {
                hold =>
                    { timeout => 300, step => 'back_with_agent', timeout_step => 'take_a_message' }
            }
        ],
        'object form with both steps'
    );

    is_deeply(
        fr()->hold( undef, 60, step => 'resume' )->to_hash->{action},
        [ { hold => { timeout => 60, step => 'resume' } } ],
        'step only, no prompt'
    );
    is_deeply(
        fr()->hold( undef, 2000, timeout_step => 'msg' )->to_hash->{action},
        [ { hold => { timeout => 900, timeout_step => 'msg' } } ],
        'timeout_step only, timeout clamped in object form'
    );
};

subtest 'rpc_ai_global_data / rpc_ai_message global_data' => sub {
    my $r = fr();
    is( $r->rpc_ai_global_data( 'call-9', { decline_message => 'busy' } ), $r, 'chains' );
    my $swml = $r->to_hash->{action}[0]{SWML};
    is_deeply(
        $swml->{sections}{main}[0]{execute_rpc},
        {
            method  => 'ai_message',
            call_id => 'call-9',
            params  => { global_data => { decline_message => 'busy' } },
        },
        'global_data only: no role/message_text'
    );

    my $both = fr()->rpc_ai_message(
        call_id      => 'c1',
        message_text => 'hi',
        global_data  => { k => 1 },
    )->to_hash->{action}[0]{SWML}{sections}{main}[0]{execute_rpc};
    is_deeply(
        $both->{params},
        { role => 'system', message_text => 'hi', global_data => { k => 1 } },
        'both payloads'
    );

    my $err = do {
        local $@;
        eval { fr()->rpc_ai_message( call_id => 'c1' ) };
        $@;
    };
    like( $err, qr/needs message_text, global_data, or both/, 'neither payload dies' );
};

subtest 'constructor tool_result / tool_prompt' => sub {
    is_deeply(
        SignalWire::SWAIG::FunctionResult->new(
            tool_result => 'Order 1042 placed.',
            tool_prompt => 'Tell them.'
        )->to_hash,
        { response => { tool_result => 'Order 1042 placed.', tool_prompt => 'Tell them.' } },
        'structured response built at construction'
    );
    is_deeply(
        SignalWire::SWAIG::FunctionResult->new( tool_result => 'Saved.' )->to_hash,
        { response => { tool_result => 'Saved.' } },
        'tool_result only'
    );
    is( SignalWire::SWAIG::FunctionResult->new('plain')->response,
        'plain', 'plain response unchanged' );
};

subtest 'execute_swml transfer rides beside the document' => sub {
    my $doc = { version => '1.0.0', sections => { main => [ { answer => {} } ] } };
    is_deeply(
        fr()->execute_swml( $doc, transfer => 1 )->to_hash->{action},
        [ { SWML => $doc, transfer => 'true' } ],
        'action-level transfer'
    );
    is_deeply(
        fr()->execute_swml($doc)->to_hash->{action},
        [ { SWML => $doc } ],
        'no transfer key by default'
    );
};

done_testing;
