#!/usr/bin/env perl
# Post-prompt normalization across the voice and chat engines, and reading the
# capabilities a client declared. Cases mirror the python reference tests
# (tests/unit/core/test_post_prompt_normalize.py, test_capabilities.py).
use strict;
use warnings;
use Test::More;
use JSON ();

use SignalWire::Core::PostPrompt
    qw(dialogue_turns normalize_post_prompt parse_post_prompt_data strip_json_fence);
use SignalWire::Core::Capabilities qw(declared_capabilities has_capability user_variables);

my $FENCED = qq{```json\n{"summary": "s", "already_answered": ["pricing"]}\n```};

subtest 'parse_post_prompt_data shapes' => sub {
    is_deeply(
        parse_post_prompt_data( { summary => 's', user_goal => 'g' } ),
        { summary => 's', user_goal => 'g' },
        'flat keys (voice)'
    );
    is_deeply(
        parse_post_prompt_data( { raw => $FENCED } ),
        { summary => 's', already_answered => ['pricing'] },
        'fenced raw (chat)'
    );
    is_deeply(
        parse_post_prompt_data( { parsed => [ { summary => 's3' } ], raw => '...' } ),
        { summary => 's3' },
        'object wrapped in a list under parsed'
    );
    ok( !exists parse_post_prompt_data( { parsed => [ { summary => 's' } ] } )->{parsed},
        'parsed wrapper wins over the generic sweep' );
    is_deeply(
        parse_post_prompt_data( { parsed => { summary => 's' } } ),
        { summary => 's' },
        'parsed as a bare object'
    );
    is_deeply(
        parse_post_prompt_data( { raw => 'They asked about pricing.' } ),
        { summary => 'They asked about pricing.' },
        'prose kept as the summary'
    );
    is_deeply(
        parse_post_prompt_data( { raw => '"just a string"' } ),
        { summary => 'just a string' },
        'JSON that is not an object'
    );
    is_deeply(
        parse_post_prompt_data( { raw => '[1, 2]' } ),
        { summary => '[1, 2]' },
        'JSON list rendered as python str()'
    );

    for my $junk ( undef, {}, 'text', 42, [], { raw => '' }, { raw => '   ' }, { raw => undef } ) {
        is_deeply( parse_post_prompt_data($junk), {}, 'junk degrades to {}' );
    }
};

subtest 'strip_json_fence' => sub {
    is( strip_json_fence(qq{```json\n{"a":1}\n```}), '{"a":1}',         'json fence' );
    is( strip_json_fence("```\nplain\n```"),         'plain',           'bare fence' );
    is( strip_json_fence('no fence at all'),         'no fence at all', 'no fence' );
    is( strip_json_fence(''),                        '',                'empty' );
    is( strip_json_fence(undef),                     '',                'undef' );
};

my @LOG = (
    { role => 'user',             content => 'hi' },
    { role => 'assistant',        content => 'hello' },
    { role => 'system',           content => 'the prompt' },
    { role => 'system-log',       content => 'step trace' },
    { role => 'tool',             content => 'tool output' },
    { role => 'assistant',        content => '', tool_calls => [ { id => 1 } ] },
    { role => 'assistant-manual', content => 'let me look that up' },
    { role => 'assistant',        content => '   ' },
    'not even a dict',
);

subtest 'dialogue_turns' => sub {
    is_deeply(
        dialogue_turns( \@LOG ),
        [ { role => 'user', content => 'hi' }, { role => 'assistant', content => 'hello' } ],
        'only real dialogue'
    );
    my @with_echo = ( @LOG, { role => 'assistant', content => $FENCED } );
    my $dropped   = dialogue_turns( \@with_echo, drop_echo => $FENCED );
    ok( !( grep { $_->{content} eq $FENCED } @$dropped ), 'summary echo dropped' );
    is( scalar @{ dialogue_turns( \@with_echo ) }, 3, 'echo kept when not asked to drop' );
    is_deeply(
        dialogue_turns( \@LOG, roles => ['system'] ),
        [ { role => 'system', content => 'the prompt' } ],
        'roles option'
    );
    is_deeply(
        dialogue_turns( [ { role => 'assistant', content => 'x', tool_calls => [] } ] ),
        [ { role => 'assistant', content => 'x' } ],
        'an EMPTY tool_calls list does not drop the turn'
    );
    is_deeply( dialogue_turns($_), [], 'junk log' ) for ( undef, [], 'nonsense', 42 );
};

subtest 'normalize_post_prompt' => sub {
    my $voice = normalize_post_prompt(
        {
            conversation_type => 'voice',
            call_id           => 'c-1',
            post_prompt_data  => { parsed => [ { summary => 'v' } ] },
            raw_call_log      => [ { role => 'user', content => 'hi' } ],
        }
    );
    isa_ok( $voice, 'SignalWire::Core::PostPrompt::NormalizedPostPrompt' );
    is( $voice->medium,          'voice', 'medium' );
    is( $voice->conversation_id, undef,   'voice has no conversation_id' );
    is_deeply( $voice->summary, { summary => 'v' }, 'summary' );
    is( $voice->call_id,              'c-1', 'call_id' );
    is( scalar @{ $voice->dialogue }, 1,     'dialogue' );

    my $chat = normalize_post_prompt(
        {
            conversation_type => 'chat',
            conversation_id   => 'conv-9',
            post_prompt_data  => { raw => $FENCED },
            raw_messages      => [
                { role => 'user', content => 'hi' }, { role => 'assistant', content => $FENCED }
            ],
        }
    );
    is( $chat->medium,          'chat',   'chat medium' );
    is( $chat->conversation_id, 'conv-9', 'chat conversation_id' );
    is_deeply( $chat->summary->{already_answered}, ['pricing'],          'fenced summary parsed' );
    is_deeply( $chat->dialogue, [ { role => 'user', content => 'hi' } ], 'echo removed' );

    is(
        scalar @{
            normalize_post_prompt( { call_log => [ { role => 'user', content => 'hi' } ] } )
                ->dialogue
        },
        1,
        'call_log key accepted'
    );
    is(
        scalar @{
            normalize_post_prompt(
                { call_log => [], raw_call_log => [ { role => 'user', content => 'a' } ] }
            )->dialogue
        },
        1,
        'an empty call_log falls through to raw_call_log'
    );

    for my $junk ( undef, 'text', 42, [] ) {
        my $r = normalize_post_prompt($junk);
        is( $r->medium, '', 'junk: empty medium' );
        is_deeply( $r->summary,  {}, 'junk: empty summary' );
        is_deeply( $r->dialogue, [], 'junk: empty dialogue' );
    }

    my $body = { conversation_type => 'voice', extra => 'kept' };
    is( normalize_post_prompt($body)->raw, $body, 'raw is the same body' );
};

my $BODY = {
    vars => {
        userVariables => {
            capabilities => {
                display_content => JSON::true,
                transcript      => JSON::true,
                chat_handoff    => JSON::false
            },
            metadata => { widget => { opened_at => '2026-01-01T00:00:00Z' } },
        }
    }
};

subtest 'user_variables' => sub {
    ok( exists user_variables($BODY)->{capabilities}, 'nested shape' );
    for my $junk (
        undef, {}, 'nonsense', 42,
        { vars => undef },
        { vars => {} },
        { vars => { userVariables => undef } },
        { vars => { userVariables => 'not a dict' } },
        )
    {
        is_deeply( user_variables($junk), {}, 'missing levels -> {}' );
    }
};

subtest 'declared_capabilities / has_capability' => sub {
    is_deeply( declared_capabilities($BODY), [qw(display_content transcript)],
        'truthy names only' );
    ok( !has_capability( $BODY, 'chat_handoff' ), 'false is not a declaration' );
    is_deeply( declared_capabilities( { capabilities => { a => JSON::true } } ),
        ['a'], 'already-extracted user variables' );
    ok( has_capability( { capabilities => { future_thing => JSON::true } }, 'future_thing' ),
        'unknown names pass through' );
    ok( has_capability( $BODY,  'display_content' ), 'declared' );
    ok( !has_capability( $BODY, 'telepathy' ),       'never mentioned' );
    for my $junk (
        undef,
        {},
        'nonsense',
        42,
        { vars => { userVariables => { capabilities => 'not a dict' } } },
        { vars => { userVariables => { capabilities => undef } } },
        { vars => { userVariables => {} } },
        )
    {
        is_deeply( declared_capabilities($junk), [], 'absence/malformation -> none' );
        ok( !has_capability( $junk, 'display_content' ), 'and has_capability is false' );
    }
};

done_testing;
