#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON ();

use SignalWire::SWAIG::FunctionResult;

# Helper to decode the result for comparison
sub result_hash {
    my ($fr) = @_;
    # Roundtrip through JSON to normalize booleans
    return JSON::decode_json(JSON::encode_json($fr->to_hash));
}

# =============================================
# Test: Basic construction
# =============================================
subtest 'Construction' => sub {
    # Default
    my $r = SignalWire::SWAIG::FunctionResult->new();
    is($r->response, '', 'default response is empty string');
    is($r->post_process, 0, 'default post_process is false');
    is(scalar @{ $r->action }, 0, 'default actions empty');

    # Positional string
    $r = SignalWire::SWAIG::FunctionResult->new('Hello');
    is($r->response, 'Hello', 'positional string constructor');

    # Named args
    $r = SignalWire::SWAIG::FunctionResult->new(
        response     => 'test',
        post_process => 1,
    );
    is($r->response, 'test', 'named response');
    is($r->post_process, 1, 'named post_process');
};

# =============================================
# Test: Core methods
# =============================================
subtest 'Core methods' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('initial');

    # set_response
    my $ret = $r->set_response('updated');
    is($r->response, 'updated', 'set_response works');
    is($ret, $r, 'set_response returns self');

    # set_post_process
    $ret = $r->set_post_process(1);
    is($r->post_process, 1, 'set_post_process works');
    is($ret, $r, 'set_post_process returns self');

    # add_action
    $ret = $r->add_action('say', 'hello');
    is(scalar @{ $r->action }, 1, 'add_action adds one action');
    is_deeply($r->action->[0], { say => 'hello' }, 'action content correct');
    is($ret, $r, 'add_action returns self');

    # add_actions
    $r->add_actions([{ stop => JSON::true }, { hangup => JSON::true }]);
    is(scalar @{ $r->action }, 3, 'add_actions adds multiple');
};

# =============================================
# Test: Serialization
# =============================================
subtest 'Serialization' => sub {
    # Response only
    my $r = SignalWire::SWAIG::FunctionResult->new('test');
    my $h = result_hash($r);
    is($h->{response}, 'test', 'response in hash');
    ok(!exists $h->{action}, 'no action when empty');
    ok(!exists $h->{post_process}, 'no post_process when false');

    # With action and post_process
    $r->add_action('say', 'hello');
    $r->set_post_process(1);
    $h = result_hash($r);
    is($h->{response}, 'test', 'response preserved');
    is(scalar @{ $h->{action} }, 1, 'action included');
    ok($h->{post_process}, 'post_process included when true');

    # Empty result
    $r = SignalWire::SWAIG::FunctionResult->new();
    $h = result_hash($r);
    is($h->{response}, 'Action completed.', 'empty result gets default response');
};

# =============================================
# Test: Call Control
# =============================================
subtest 'connect' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('transferring');
    $r->connect('+15551234567', final => 1, from => '+15559876543');
    my $h = result_hash($r);
    my $action = $h->{action}[0];
    ok(exists $action->{SWML}, 'connect creates SWML action');
    is($action->{SWML}{sections}{main}[0]{connect}{to}, '+15551234567', 'connect to correct');
    is($action->{SWML}{sections}{main}[0]{connect}{from}, '+15559876543', 'connect from correct');
    is($action->{transfer}, 'true', 'final=true sets transfer');

    # Without from
    $r = SignalWire::SWAIG::FunctionResult->new('test');
    $r->connect('sip:test@example.com', final => 0);
    $h = result_hash($r);
    $action = $h->{action}[0];
    ok(!exists $action->{SWML}{sections}{main}[0]{connect}{from}, 'no from when not specified');
    is($action->{transfer}, 'false', 'final=false sets transfer=false');
};

subtest 'swml_transfer' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('bye');
    $r->swml_transfer('https://example.com/swml', 'Transfer complete');
    my $h = result_hash($r);
    my $action = $h->{action}[0];
    my $main = $action->{SWML}{sections}{main};
    is_deeply($main->[0], { set => { ai_response => 'Transfer complete' } }, 'set ai_response');
    is_deeply($main->[1], { transfer => { dest => 'https://example.com/swml' } }, 'transfer dest');
    is($action->{transfer}, 'true', 'default final is true');
};

subtest 'hangup' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('goodbye');
    $r->hangup;
    my $h = result_hash($r);
    ok($h->{action}[0]{hangup}, 'hangup action is true');
};

subtest 'hold' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('hold');
    $r->hold(500);
    my $h = result_hash($r);
    is($h->{action}[0]{hold}, 500, 'hold with timeout');

    # Clamping
    $r = SignalWire::SWAIG::FunctionResult->new('hold');
    $r->hold(9999);
    $h = result_hash($r);
    is($h->{action}[0]{hold}, 900, 'hold clamped to 900');

    $r = SignalWire::SWAIG::FunctionResult->new('hold');
    $r->hold(-5);
    $h = result_hash($r);
    is($h->{action}[0]{hold}, 0, 'hold clamped to 0');
};

subtest 'wait_for_user' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('wait');
    $r->wait_for_user();
    my $h = result_hash($r);
    ok($h->{action}[0]{wait_for_user}, 'default wait_for_user is true');

    $r = SignalWire::SWAIG::FunctionResult->new('wait');
    $r->wait_for_user(answer_first => 1);
    $h = result_hash($r);
    is($h->{action}[0]{wait_for_user}, 'answer_first', 'answer_first mode');

    $r = SignalWire::SWAIG::FunctionResult->new('wait');
    $r->wait_for_user(timeout => 30);
    $h = result_hash($r);
    is($h->{action}[0]{wait_for_user}, 30, 'timeout mode');
};

subtest 'stop' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('stop');
    $r->stop;
    my $h = result_hash($r);
    ok($h->{action}[0]{stop}, 'stop is true');
};

# =============================================
# Test: State & Data
# =============================================
subtest 'State & Data' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('state');

    $r->update_global_data({ key1 => 'v1', key2 => 'v2' });
    my $h = result_hash($r);
    is_deeply($h->{action}[0]{set_global_data}, { key1 => 'v1', key2 => 'v2' }, 'update_global_data');

    $r = SignalWire::SWAIG::FunctionResult->new('state');
    $r->remove_global_data(['key1', 'key2']);
    $h = result_hash($r);
    is_deeply($h->{action}[0]{unset_global_data}, ['key1', 'key2'], 'remove_global_data');

    $r = SignalWire::SWAIG::FunctionResult->new('state');
    $r->set_metadata({ meta_key => 'meta_val' });
    $h = result_hash($r);
    is_deeply($h->{action}[0]{set_meta_data}, { meta_key => 'meta_val' }, 'set_metadata');

    $r = SignalWire::SWAIG::FunctionResult->new('state');
    $r->remove_metadata(['meta_key']);
    $h = result_hash($r);
    is_deeply($h->{action}[0]{unset_meta_data}, ['meta_key'], 'remove_metadata');
};

subtest 'Context switching' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('ctx');
    $r->swml_change_step('step2');
    my $h = result_hash($r);
    is($h->{action}[0]{change_step}, 'step2', 'swml_change_step');

    $r = SignalWire::SWAIG::FunctionResult->new('ctx');
    $r->swml_change_context('support');
    $h = result_hash($r);
    is($h->{action}[0]{change_context}, 'support', 'swml_change_context');

    # Simple context switch
    $r = SignalWire::SWAIG::FunctionResult->new('ctx');
    $r->switch_context(system_prompt => 'You are a helper');
    $h = result_hash($r);
    is($h->{action}[0]{context_switch}, 'You are a helper', 'simple context switch');

    # Advanced context switch
    $r = SignalWire::SWAIG::FunctionResult->new('ctx');
    $r->switch_context(
        system_prompt => 'new prompt',
        user_prompt   => 'hi there',
        consolidate   => 1,
        full_reset    => 1,
    );
    $h = result_hash($r);
    my $cs = $h->{action}[0]{context_switch};
    is($cs->{system_prompt}, 'new prompt', 'advanced: system_prompt');
    is($cs->{user_prompt}, 'hi there', 'advanced: user_prompt');
    ok($cs->{consolidate}, 'advanced: consolidate');
    ok($cs->{full_reset}, 'advanced: full_reset');
};

subtest 'replace_in_history' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('history');
    $r->replace_in_history('summary text');
    my $h = result_hash($r);
    is($h->{action}[0]{replace_in_history}, 'summary text', 'replace_in_history with text');
};

# =============================================
# Test: Media
# =============================================
subtest 'Media' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('media');
    $r->say('Hello world');
    my $h = result_hash($r);
    is($h->{action}[0]{say}, 'Hello world', 'say action');

    $r = SignalWire::SWAIG::FunctionResult->new('media');
    $r->play_background_file('music.mp3');
    $h = result_hash($r);
    is($h->{action}[0]{playback_bg}, 'music.mp3', 'play_background_file without wait');

    $r = SignalWire::SWAIG::FunctionResult->new('media');
    $r->play_background_file('music.mp3', wait => 1);
    $h = result_hash($r);
    is($h->{action}[0]{playback_bg}{file}, 'music.mp3', 'play_background_file with wait - file');
    ok($h->{action}[0]{playback_bg}{wait}, 'play_background_file with wait - wait true');

    $r = SignalWire::SWAIG::FunctionResult->new('media');
    $r->stop_background_file;
    $h = result_hash($r);
    ok($h->{action}[0]{stop_playback_bg}, 'stop_background_file');
};

# =============================================
# Test: Speech & AI
# =============================================
subtest 'Speech & AI' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('speech');
    $r->add_dynamic_hints(['hint1', 'hint2']);
    my $h = result_hash($r);
    is_deeply($h->{action}[0]{add_dynamic_hints}, ['hint1', 'hint2'], 'add_dynamic_hints');

    $r = SignalWire::SWAIG::FunctionResult->new('speech');
    $r->clear_dynamic_hints;
    $h = result_hash($r);
    is_deeply($h->{action}[0]{clear_dynamic_hints}, {}, 'clear_dynamic_hints');

    $r = SignalWire::SWAIG::FunctionResult->new('speech');
    $r->set_end_of_speech_timeout(500);
    $h = result_hash($r);
    is($h->{action}[0]{end_of_speech_timeout}, 500, 'set_end_of_speech_timeout');

    $r = SignalWire::SWAIG::FunctionResult->new('speech');
    $r->set_speech_event_timeout(3000);
    $h = result_hash($r);
    is($h->{action}[0]{speech_event_timeout}, 3000, 'set_speech_event_timeout');

    $r = SignalWire::SWAIG::FunctionResult->new('speech');
    $r->toggle_functions([
        { function => 'f1', active => JSON::true },
        { function => 'f2', active => JSON::false },
    ]);
    $h = result_hash($r);
    is($h->{action}[0]{toggle_functions}[0]{function}, 'f1', 'toggle_functions');

    $r = SignalWire::SWAIG::FunctionResult->new('speech');
    $r->enable_functions_on_timeout(1);
    $h = result_hash($r);
    ok($h->{action}[0]{functions_on_speaker_timeout}, 'enable_functions_on_timeout');

    $r = SignalWire::SWAIG::FunctionResult->new('speech');
    $r->enable_extensive_data(1);
    $h = result_hash($r);
    ok($h->{action}[0]{extensive_data}, 'enable_extensive_data');

    $r = SignalWire::SWAIG::FunctionResult->new('speech');
    $r->update_settings({ temperature => 0.5, top_p => 0.9 });
    $h = result_hash($r);
    is($h->{action}[0]{settings}{temperature}, 0.5, 'update_settings');
};

# =============================================
# Test: Advanced
# =============================================
subtest 'execute_swml' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('swml');
    $r->execute_swml({ version => '1.0.0', sections => { main => [{ hangup => {} }] } });
    my $h = result_hash($r);
    my $swml = $h->{action}[0]{SWML};
    is($swml->{version}, '1.0.0', 'execute_swml hashref');

    # With transfer
    $r = SignalWire::SWAIG::FunctionResult->new('swml');
    $r->execute_swml({ version => '1.0.0', sections => { main => [] } }, transfer => 1);
    $h = result_hash($r);
    is($h->{action}[0]{SWML}{transfer}, 'true', 'execute_swml with transfer');

    # String input
    $r = SignalWire::SWAIG::FunctionResult->new('swml');
    $r->execute_swml('{"version":"1.0.0","sections":{"main":[]}}');
    $h = result_hash($r);
    is($h->{action}[0]{SWML}{version}, '1.0.0', 'execute_swml from JSON string');
};

# =============================================
# Test: join_conference — full parity with the Python reference
# (core/function_result.py join_conference). 19 params (name + 18
# optional), 7 validations with EXACT Python ValueError messages, and
# simple-form (all defaults -> bare conference NAME string) vs full-object
# emission (every NON-DEFAULT param under its snake_case wire key).
# Drives the REAL join_conference -> execute_swml -> add_action path and
# asserts on the serialized SWML action. No mocks.
# =============================================

# Pull the join_conference payload back out of a serialized result.
# It lands at action[0]/SWML/sections/main/[0]/join_conference — either a
# bare string (simple form) or a hashref (full-object form).
sub jc_payload {
    my ($fr) = @_;
    my $h = result_hash($fr);
    return $h->{action}[0]{SWML}{sections}{main}[0]{join_conference};
}

subtest 'join_conference simple form (all defaults -> bare name)' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('conf');
    my $ret = $r->join_conference('support-lobby');
    is($ret, $r, 'join_conference returns self for chaining');

    my $payload = jc_payload($r);
    ok(!ref $payload, 'all-defaults emits a bare scalar, not a hashref');
    is($payload, 'support-lobby', 'bare conference name on the wire');

    # Defaults that equal the simple-form trigger must NOT force object form.
    $r = SignalWire::SWAIG::FunctionResult->new('conf');
    $r->join_conference(
        'lobby2',
        muted                            => 0,
        beep                             => 'true',
        start_on_enter                   => 1,
        end_on_exit                      => 0,
        max_participants                 => 250,
        record                           => 'do-not-record',
        trim                             => 'trim-silence',
        status_callback_method           => 'POST',
        recording_status_callback_method => 'POST',
        recording_status_callback_event  => 'completed',
    );
    is(jc_payload($r), 'lobby2',
        'explicitly passing every default still collapses to bare name');
};

subtest 'join_conference full-object form (non-default params, snake_case keys)' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('conf');
    $r->join_conference(
        'big-room',
        muted                            => 1,
        beep                             => 'onEnter',
        start_on_enter                   => 0,
        end_on_exit                      => 1,
        wait_url                         => 'https://example.com/hold.swml',
        max_participants                 => 100,
        record                           => 'record-from-start',
        region                           => 'us-east',
        trim                             => 'do-not-trim',
        coach                            => 'call-abc-123',
        status_callback_event            => 'start end join leave',
        status_callback                  => 'https://example.com/status',
        status_callback_method           => 'GET',
        recording_status_callback        => 'https://example.com/rec',
        recording_status_callback_method => 'GET',
        recording_status_callback_event  => 'in-progress',
        result                           => { foo => 'bar' },
    );

    my $p = jc_payload($r);
    is(ref $p, 'HASH', 'non-default params emit a hashref');
    is($p->{name}, 'big-room', 'name key present in object form');

    # Every non-default param under its EXACT snake_case wire key.
    is($p->{muted}, JSON::true, 'muted => true (boolean, not 1-ish)');
    is($p->{beep}, 'onEnter', 'beep wire key');
    is($p->{start_on_enter}, JSON::false, 'start_on_enter => false');
    is($p->{end_on_exit}, JSON::true, 'end_on_exit => true');
    is($p->{wait_url}, 'https://example.com/hold.swml', 'wait_url (NOT holdAudio)');
    is($p->{max_participants}, 100, 'max_participants');
    is($p->{record}, 'record-from-start', 'record');
    is($p->{region}, 'us-east', 'region');
    is($p->{trim}, 'do-not-trim', 'trim');
    is($p->{coach}, 'call-abc-123', 'coach');
    is($p->{status_callback_event}, 'start end join leave', 'status_callback_event');
    is($p->{status_callback}, 'https://example.com/status', 'status_callback');
    is($p->{status_callback_method}, 'GET', 'status_callback_method');
    is($p->{recording_status_callback}, 'https://example.com/rec', 'recording_status_callback');
    is($p->{recording_status_callback_method}, 'GET', 'recording_status_callback_method');
    is($p->{recording_status_callback_event}, 'in-progress', 'recording_status_callback_event');
    is_deeply($p->{result}, { foo => 'bar' }, 'result passthrough');

    # There must be no Twilio-style camelCase key leaking in.
    ok(!exists $p->{holdAudio}, 'no holdAudio key (Python uses wait_url)');
    ok(!exists $p->{startConferenceOnEnter}, 'no camelCase startConferenceOnEnter');
};

subtest 'join_conference omits keys left at their defaults' => sub {
    # Only ONE non-default param: object form with name + that one key only.
    my $r = SignalWire::SWAIG::FunctionResult->new('conf');
    $r->join_conference('room', max_participants => 50);
    my $p = jc_payload($r);
    is(ref $p, 'HASH', 'single non-default forces object form');
    is($p->{name}, 'room', 'name present');
    is($p->{max_participants}, 50, 'max_participants present');
    # None of the default-valued params should appear.
    for my $k (qw(muted beep start_on_enter end_on_exit wait_url record
                  region trim coach status_callback_event status_callback
                  status_callback_method recording_status_callback
                  recording_status_callback_method recording_status_callback_event
                  result)) {
        ok(!exists $p->{$k}, "default-valued '$k' is omitted");
    }
};

subtest 'join_conference validations (exact Python ValueError messages)' => sub {
    # Invalid beep.
    {
        my $r = SignalWire::SWAIG::FunctionResult->new('conf');
        my $ok = eval { $r->join_conference('c', beep => 'maybe'); 1 };
        ok(!$ok, 'invalid beep dies');
        like($@, qr/\Qbeep must be one of ['true', 'false', 'onEnter', 'onExit']\E/,
            'beep message matches Python list rendering');
    }
    # max_participants out of range: > 250, == 0, < 0.
    for my $bad (251, 1000, 0, -1, -50) {
        my $r = SignalWire::SWAIG::FunctionResult->new('conf');
        my $ok = eval { $r->join_conference('c', max_participants => $bad); 1 };
        ok(!$ok, "max_participants=$bad dies");
        like($@, qr/\Qmax_participants must be a positive integer <= 250\E/,
            "max_participants=$bad message");
    }
    # Boundary: exactly 250 and exactly 1 are accepted.
    for my $good (1, 250) {
        my $r = SignalWire::SWAIG::FunctionResult->new('conf');
        my $ok = eval { $r->join_conference('c', max_participants => $good); 1 };
        ok($ok, "max_participants=$good accepted") or diag($@);
    }
    # Invalid record.
    {
        my $r = SignalWire::SWAIG::FunctionResult->new('conf');
        my $ok = eval { $r->join_conference('c', record => 'sometimes'); 1 };
        ok(!$ok, 'invalid record dies');
        like($@, qr/\Qrecord must be one of ['do-not-record', 'record-from-start']\E/,
            'record message');
    }
    # Invalid trim.
    {
        my $r = SignalWire::SWAIG::FunctionResult->new('conf');
        my $ok = eval { $r->join_conference('c', trim => 'maybe-trim'); 1 };
        ok(!$ok, 'invalid trim dies');
        like($@, qr/\Qtrim must be one of ['trim-silence', 'do-not-trim']\E/,
            'trim message');
    }
    # Invalid status_callback_method.
    {
        my $r = SignalWire::SWAIG::FunctionResult->new('conf');
        my $ok = eval { $r->join_conference('c', status_callback_method => 'PUT'); 1 };
        ok(!$ok, 'invalid status_callback_method dies');
        like($@, qr/\Qstatus_callback_method must be one of ['GET', 'POST']\E/,
            'status_callback_method message');
    }
    # Invalid recording_status_callback_method.
    {
        my $r = SignalWire::SWAIG::FunctionResult->new('conf');
        my $ok = eval { $r->join_conference('c', recording_status_callback_method => 'DELETE'); 1 };
        ok(!$ok, 'invalid recording_status_callback_method dies');
        like($@, qr/\Qrecording_status_callback_method must be one of ['GET', 'POST']\E/,
            'recording_status_callback_method message');
    }
    # Empty name and whitespace-only name (after trim).
    {
        my $r = SignalWire::SWAIG::FunctionResult->new('conf');
        ok(!eval { $r->join_conference(''); 1 }, 'empty name dies');
        like($@, qr/\Qname cannot be empty\E/, 'empty-name message');
    }
    {
        my $r = SignalWire::SWAIG::FunctionResult->new('conf');
        ok(!eval { $r->join_conference('   '); 1 }, 'whitespace-only name dies');
        like($@, qr/\Qname cannot be empty\E/, 'whitespace-name message');
    }
};

subtest 'join_conference Optional[str] truthiness emission (Python parity)' => sub {
    # Python emits the six Optional[str] params with `if <str>:` (truthiness):
    # an empty string is OMITTED (but still forces object form via the
    # simple-form `is None` gate). `result` uses `is not None`, so a defined
    # falsy result (0) IS emitted.
    my $r = SignalWire::SWAIG::FunctionResult->new('conf');
    $r->join_conference('room', wait_url => '', region => '', coach => '');
    my $p = jc_payload($r);
    is(ref $p, 'HASH', 'empty-string optional forces object form (matches Python is-None gate)');
    is($p->{name}, 'room', 'name present');
    ok(!exists $p->{wait_url}, 'empty wait_url omitted (truthiness gate)');
    ok(!exists $p->{region},   'empty region omitted (truthiness gate)');
    ok(!exists $p->{coach},    'empty coach omitted (truthiness gate)');

    # result => 0 is defined-but-falsy; Python's `is not None` emits it.
    my $r2 = SignalWire::SWAIG::FunctionResult->new('conf');
    $r2->join_conference('room', result => 0);
    my $p2 = jc_payload($r2);
    ok(exists $p2->{result}, 'result => 0 is emitted (is-not-None gate, not truthiness)');
    is($p2->{result}, 0, 'result value 0 preserved');

    # result => arrayref (the "cond when array []" form) passes through.
    my $r3 = SignalWire::SWAIG::FunctionResult->new('conf');
    $r3->join_conference('room', result => ['a', 'b']);
    is_deeply(jc_payload($r3)->{result}, ['a', 'b'], 'arrayref result passthrough');
};

subtest 'join_conference chaining with other actions' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('multi')
        ->say('Joining the conference')
        ->join_conference('lobby', muted => 1)
        ->set_post_process(1);
    my $h = result_hash($r);
    is($h->{response}, 'multi', 'response preserved through chain');
    is(scalar @{ $h->{action} }, 2, 'say + join_conference => 2 actions');
    is($h->{action}[0]{say}, 'Joining the conference', 'first action is say');
    is($h->{action}[1]{SWML}{sections}{main}[0]{join_conference}{name}, 'lobby',
        'second action is the join_conference object');
    is($h->{action}[1]{SWML}{sections}{main}[0]{join_conference}{muted}, JSON::true,
        'muted carried into the chained join_conference');
    ok($h->{post_process}, 'post_process set after chain');
};

subtest 'join_room' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('room');
    $r->join_room('my-room');
    my $h = result_hash($r);
    my $main = $h->{action}[0]{SWML}{sections}{main};
    is($main->[0]{join_room}{name}, 'my-room', 'join_room');
};

subtest 'sip_refer' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('sip');
    $r->sip_refer('sip:user@example.com');
    my $h = result_hash($r);
    my $main = $h->{action}[0]{SWML}{sections}{main};
    is($main->[0]{sip_refer}{to_uri}, 'sip:user@example.com', 'sip_refer');
};

subtest 'simulate_user_input' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('sim');
    $r->simulate_user_input('hello bot');
    my $h = result_hash($r);
    is($h->{action}[0]{user_input}, 'hello bot', 'simulate_user_input');
};

# =============================================
# Test: RPC
# =============================================
subtest 'RPC methods' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('rpc');
    $r->execute_rpc(method => 'test_method', params => { key => 'value' });
    my $h = result_hash($r);
    my $main = $h->{action}[0]{SWML}{sections}{main};
    is($main->[0]{execute_rpc}{method}, 'test_method', 'execute_rpc method');
    is($main->[0]{execute_rpc}{params}{key}, 'value', 'execute_rpc params');

    $r = SignalWire::SWAIG::FunctionResult->new('rpc');
    $r->rpc_dial(
        to_number   => '+15551234567',
        from_number => '+15559876543',
        dest_swml   => 'https://example.com/agent',
    );
    $h = result_hash($r);
    $main = $h->{action}[0]{SWML}{sections}{main};
    is($main->[0]{execute_rpc}{method}, 'dial', 'rpc_dial method');

    $r = SignalWire::SWAIG::FunctionResult->new('rpc');
    $r->rpc_ai_message(
        call_id      => 'call-123',
        message_text => 'Hello agent',
    );
    $h = result_hash($r);
    $main = $h->{action}[0]{SWML}{sections}{main};
    is($main->[0]{execute_rpc}{method}, 'ai_message', 'rpc_ai_message');
    is($main->[0]{execute_rpc}{call_id}, 'call-123', 'rpc_ai_message call_id');

    $r = SignalWire::SWAIG::FunctionResult->new('rpc');
    $r->rpc_ai_unhold(call_id => 'call-456');
    $h = result_hash($r);
    $main = $h->{action}[0]{SWML}{sections}{main};
    is($main->[0]{execute_rpc}{method}, 'ai_unhold', 'rpc_ai_unhold');
};

# =============================================
# Test: Chaining
# =============================================
subtest 'Method chaining' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('chained')
        ->say('Please hold')
        ->hold(120)
        ->update_global_data({ status => 'on_hold' })
        ->set_post_process(1);
    my $h = result_hash($r);
    is($h->{response}, 'chained', 'chained response');
    is(scalar @{ $h->{action} }, 3, 'chained actions count');
    ok($h->{post_process}, 'chained post_process');
};

# =============================================
# Test: Payment helpers
# =============================================
subtest 'Payment class methods' => sub {
    my $action = SignalWire::SWAIG::FunctionResult->create_payment_action('Say', 'Enter your card');
    is($action->{type}, 'Say', 'payment action type');
    is($action->{phrase}, 'Enter your card', 'payment action phrase');

    my $param = SignalWire::SWAIG::FunctionResult->create_payment_parameter('amount', '10.00');
    is($param->{name}, 'amount', 'payment parameter name');
    is($param->{value}, '10.00', 'payment parameter value');

    my $prompt = SignalWire::SWAIG::FunctionResult->create_payment_prompt(
        for_situation => 'payment-card-number',
        actions       => [$action],
        card_type     => 'visa',
    );
    is($prompt->{for}, 'payment-card-number', 'payment prompt for');
    is($prompt->{card_type}, 'visa', 'payment prompt card_type');
};

# =============================================
# Test: pay (always-on keys, incl. min_postal_code_length)
# =============================================
# The pay verb rides at main[1] (main[0] is the {set:{ai_response}} preamble).
sub pay_params {
    my ($fr) = @_;
    return result_hash($fr)->{action}[0]{SWML}{sections}{main}[1]{pay};
}

subtest 'pay always-on keys (Python parity)' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new;
    $r->pay(payment_connector_url => 'https://pay.test/connect');
    my $p = pay_params($r);

    # Every always-on key Python emits unconditionally — the whole point of
    # this subtest is min_postal_code_length, which the slurpy-%opts body
    # used to drop entirely. All are strings on the wire.
    is($p->{payment_connector_url}, 'https://pay.test/connect', 'connector url');
    is($p->{input},                 'dtmf',                     'input default');
    is($p->{payment_method},        'credit-card',              'payment_method default');
    is($p->{timeout},               '5',                        'timeout stringified');
    is($p->{max_attempts},          '1',                        'max_attempts stringified');
    is($p->{security_code},         'true',                     'security_code default');
    is($p->{min_postal_code_length}, '0', 'min_postal_code_length default "0" (was dropped)');
    is($p->{token_type},            'reusable',                 'token_type default');
    is($p->{currency},              'usd',                      'currency default');
    is($p->{language},              'en-US',                    'language default');
    is($p->{voice},                 'woman',                    'voice default');
    is($p->{valid_card_types},      'visa mastercard amex',     'valid_card_types default');
    is($p->{postal_code},           'true',                     'postal_code bool default');

    # min_postal_code_length is read off %opts and stringified.
    my $r2 = SignalWire::SWAIG::FunctionResult->new;
    $r2->pay(payment_connector_url => 'https://pay.test/c', min_postal_code_length => 5);
    is(pay_params($r2)->{min_postal_code_length}, '5',
        'min_postal_code_length passthrough stringified');

    # The full always-on key set matches Python exactly (no extra, none missing).
    my $r3 = SignalWire::SWAIG::FunctionResult->new;
    $r3->pay(payment_connector_url => 'https://pay.test/c');
    is_deeply(
        [ sort keys %{ pay_params($r3) } ],
        [ sort qw(payment_connector_url input payment_method timeout max_attempts
            security_code min_postal_code_length token_type currency language voice
            valid_card_types postal_code) ],
        'pay always-on key set is byte-identical to Python',
    );
};

# =============================================
# Test: tap (rtp_ptime + status_url restored, rtp_ptime validation)
# =============================================
sub tap_params {
    my ($fr) = @_;
    return result_hash($fr)->{action}[0]{SWML}{sections}{main}[0]{tap};
}

subtest 'tap rtp_ptime + status_url + validation (Python parity)' => sub {
    # Defaults: only uri (rtp_ptime==20 and status_url undef are omitted,
    # matching Python's per-key gating).
    my $r = SignalWire::SWAIG::FunctionResult->new;
    $r->tap('wss://t.test/s');
    is_deeply(tap_params($r), { uri => 'wss://t.test/s' },
        'all-defaults tap emits only uri');

    # Non-default rtp_ptime + status_url both reach the wire (were dropped).
    my $r2 = SignalWire::SWAIG::FunctionResult->new;
    $r2->tap('wss://t.test/s', control_id => 't1', direction => 'speak',
        codec => 'PCMA', rtp_ptime => 40, status_url => 'https://s.test/cb');
    my $p = tap_params($r2);
    is($p->{rtp_ptime},  40,                  'rtp_ptime reaches the SWML (was dropped)');
    is($p->{status_url}, 'https://s.test/cb', 'status_url reaches the SWML (was dropped)');
    is($p->{control_id}, 't1',                'control_id present');
    is($p->{direction},  'speak',             'direction present');
    is($p->{codec},      'PCMA',              'codec present');

    # rtp_ptime at its default (20) is still omitted even alongside other params.
    my $r3 = SignalWire::SWAIG::FunctionResult->new;
    $r3->tap('wss://t.test/s', status_url => 'https://s.test/cb');
    ok(!exists tap_params($r3)->{rtp_ptime},
        'default rtp_ptime (20) omitted');

    # rtp_ptime <= 0 dies (Python: ValueError "rtp_ptime must be a positive integer").
    my $rd = SignalWire::SWAIG::FunctionResult->new;
    ok(!eval { $rd->tap('wss://t.test/s', rtp_ptime => 0); 1 },
        'rtp_ptime => 0 dies');
    like($@, qr/\Qrtp_ptime must be a positive integer\E/,
        'rtp_ptime validation message matches Python');
    my $rn = SignalWire::SWAIG::FunctionResult->new;
    ok(!eval { $rn->tap('wss://t.test/s', rtp_ptime => -5); 1 },
        'negative rtp_ptime dies');
};

# =============================================
# Test: swml_user_event
# =============================================
subtest 'swml_user_event' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('event');
    $r->swml_user_event({ type => 'cards_dealt', score => 21 });
    my $h = result_hash($r);
    my $swml = $h->{action}[0]{SWML};
    my $main = $swml->{sections}{main};
    is($main->[0]{user_event}{event}{type}, 'cards_dealt', 'user event type');
    is($main->[0]{user_event}{event}{score}, 21, 'user event data');
};

done_testing;
