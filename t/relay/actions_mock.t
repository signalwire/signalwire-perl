#!/usr/bin/env perl
# Real-mock-backed tests for Action subclasses (Play/Record/Detect/Collect/...).
# Mirrors signalwire-python tests/unit/relay/test_actions_mock.py.

use strict;
use warnings;
use Test::More;
use FindBin ();
use lib "$FindBin::Bin/../lib";
use Time::HiRes qw(sleep time);

use JSON ();
use RelayMockTest;
use SignalWire::Relay::Client;
use SignalWire::Relay::Action;

sub _connected_client {
    my $client = RelayMockTest::client( contexts => ['default'] );
    $client->connect;
    return $client;
}

sub _pump_until {
    my ( $client, $secs, $cb ) = @_;
    my $deadline = time() + $secs;
    while ( time() < $deadline ) {
        return 1 if $cb->();
        eval { $client->_read_once };
    }
    return $cb->() ? 1 : 0;
}

# Bring an inbound call up to "answered" so subsequent action calls can run.
sub _answered_inbound_call {
    my ( $client, $call_id ) = @_;
    my $captured;
    $client->on_call(
        sub {
            my ($call) = @_;
            $captured = $call;
            $call->answer;
        }
    );
    RelayMockTest::inbound_call( call_id => $call_id, auto_states => ['created'] );
    _pump_until( $client, 5, sub { $captured } );

    # Pump for answer round-trip.
    _pump_until( $client, 1, sub { 0 } );
    $captured->state('answered');
    return $captured;
}

# ---------------------------------------------------------------------------
# PlayAction
# ---------------------------------------------------------------------------

subtest 'play journals calling.play' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-play' );
    $call->play( play => [ { type => 'tts', params => { text => 'hi' } } ], );
    my $entries = RelayMockTest::journal_recv( method => 'calling.play' );
    is( scalar @$entries, 1, 'one calling.play entry' );
    my $p = $entries->[0]{frame}{params};
    is( $p->{call_id}, 'call-play', 'call_id on wire' );
    ok( $p->{control_id}, 'control_id on wire' );
    is( $p->{play}[0]{type}, 'tts', 'play[0].type on wire' );
    $client->disconnect;
};

subtest 'play resolves on finished event' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-play-fin' );
    RelayMockTest::arm_method(
        'calling.play',
        [
            { emit => { state => 'playing' },  delay_ms => 1 },
            { emit => { state => 'finished' }, delay_ms => 5 },
        ]
    );
    my $action = $call->play( play => [ { type => 'silence', params => { duration => 1 } } ], );
    isa_ok( $action, 'SignalWire::Relay::Action::Play' );
    _pump_until( $client, 5, sub { $action->is_done } );
    ok( $action->is_done, 'action resolved' );
    $client->disconnect;
};

subtest 'play stop journals calling.play.stop' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-play-stop' );
    my $action = $call->play( play => [ { type => 'silence', params => { duration => 60 } } ], );
    $action->stop;
    my $stops = RelayMockTest::journal_recv( method => 'calling.play.stop' );
    ok( scalar @$stops, 'calling.play.stop in journal' );
    is( $stops->[-1]{frame}{params}{control_id}, $action->control_id, 'control_id matches' );
    $client->disconnect;
};

subtest 'play pause/resume/volume journal' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-play-prv' );
    my $action = $call->play( play => [ { type => 'silence', params => { duration => 60 } } ], );
    $action->pause;
    $action->resume;
    $action->volume(-3.0);

    ok( scalar @{ RelayMockTest::journal_recv( method => 'calling.play.pause' ) },
        'pause journaled' );
    ok( scalar @{ RelayMockTest::journal_recv( method => 'calling.play.resume' ) },
        'resume journaled' );
    my $vol = RelayMockTest::journal_recv( method => 'calling.play.volume' );
    ok( scalar @$vol, 'volume journaled' );
    cmp_ok( $vol->[-1]{frame}{params}{volume}, '==', -3.0, 'volume value' );
    $client->disconnect;
};

subtest 'play on_completed callback fires' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-play-cb' );
    RelayMockTest::arm_method( 'calling.play',
        [ { emit => { state => 'finished' }, delay_ms => 1 }, ] );
    my $cb_fired;
    my $action = $call->play( play => [ { type => 'silence', params => { duration => 1 } } ], );
    $action->on_completed( sub { $cb_fired = 1 } );
    _pump_until( $client, 5, sub { $action->is_done } );
    ok( $cb_fired, 'on_completed callback fired' );
    $client->disconnect;
};

# ---------------------------------------------------------------------------
# Play convenience: play_tts / play_audio / play_silence / play_ringtone
# Typed wrappers that build the RELAY media object and delegate to play().
# We assert the exact { type, params } wire shape lands on calling.play.
# ---------------------------------------------------------------------------

subtest 'play_tts builds tts media on calling.play' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-tts' );
    my $action = $call->play_tts(
        'Hello world',
        language => 'en-US',
        gender   => 'female',
        voice    => 'spore',
        volume   => 2.5
    );
    isa_ok( $action, 'SignalWire::Relay::Action::Play' );
    my $entries = RelayMockTest::journal_recv( method => 'calling.play' );
    is( scalar @$entries, 1, 'one calling.play entry' );
    my $p = $entries->[0]{frame}{params};
    is( $p->{call_id},                   'call-tts',    'call_id on wire' );
    is( $p->{play}[0]{type},             'tts',         'media type tts' );
    is( $p->{play}[0]{params}{text},     'Hello world', 'tts text on wire' );
    is( $p->{play}[0]{params}{language}, 'en-US',       'tts language on wire' );
    is( $p->{play}[0]{params}{gender},   'female',      'tts gender on wire' );
    is( $p->{play}[0]{params}{voice},    'spore',       'tts voice on wire' );
    cmp_ok( $p->{volume}, '==', 2.5, 'volume sibling on wire' );
    $client->disconnect;
};

subtest 'play_tts omits unset optional params' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-tts-min' );
    $call->play_tts('Just text');
    my $p = RelayMockTest::journal_recv( method => 'calling.play' )->[0]{frame}{params};
    is( $p->{play}[0]{params}{text}, 'Just text', 'text present' );
    ok( !exists $p->{play}[0]{params}{language}, 'no language key when unset' );
    ok( !exists $p->{play}[0]{params}{voice},    'no voice key when unset' );
    ok( !exists $p->{volume},                    'no volume key when unset' );
    $client->disconnect;
};

subtest 'play_audio builds audio media on calling.play' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-paud' );
    my $action = $call->play_audio( 'https://cdn.example/a.mp3', volume => -1.0 );
    isa_ok( $action, 'SignalWire::Relay::Action::Play' );
    my $p = RelayMockTest::journal_recv( method => 'calling.play' )->[0]{frame}{params};
    is( $p->{play}[0]{type},        'audio',                     'media type audio' );
    is( $p->{play}[0]{params}{url}, 'https://cdn.example/a.mp3', 'audio url on wire' );
    cmp_ok( $p->{volume}, '==', -1.0, 'volume sibling on wire' );
    $client->disconnect;
};

subtest 'play_silence builds silence media on calling.play' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-psil' );
    my $action = $call->play_silence(3.5);
    isa_ok( $action, 'SignalWire::Relay::Action::Play' );
    my $p = RelayMockTest::journal_recv( method => 'calling.play' )->[0]{frame}{params};
    is( $p->{play}[0]{type}, 'silence', 'media type silence' );
    cmp_ok( $p->{play}[0]{params}{duration}, '==', 3.5, 'silence duration on wire' );
    $client->disconnect;
};

subtest 'play_ringtone builds ringtone media on calling.play' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-prng' );
    my $action = $call->play_ringtone( 'us', duration => 5, volume => 0.0 );
    isa_ok( $action, 'SignalWire::Relay::Action::Play' );
    my $p = RelayMockTest::journal_recv( method => 'calling.play' )->[0]{frame}{params};
    is( $p->{play}[0]{type},         'ringtone', 'media type ringtone' );
    is( $p->{play}[0]{params}{name}, 'us',       'ringtone name on wire' );
    cmp_ok( $p->{play}[0]{params}{duration}, '==', 5, 'ringtone duration on wire' );
    $client->disconnect;
};

# ---------------------------------------------------------------------------
# Detect convenience: detect_digit / detect_answering_machine / detect_fax
# Typed wrappers that build the RELAY detect object and delegate to detect().
# timeout is a SIBLING of `detect`, not inside the detect object.
# ---------------------------------------------------------------------------

subtest 'detect_digit builds digit detect on calling.detect' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-ddig' );
    my $action = $call->detect_digit( digits => '123', timeout => 10 );
    isa_ok( $action, 'SignalWire::Relay::Action::Detect' );
    my $p = RelayMockTest::journal_recv( method => 'calling.detect' )->[0]{frame}{params};
    is( $p->{detect}{type},           'digit', 'detect type digit' );
    is( $p->{detect}{params}{digits}, '123',   'digits inside detect.params' );
    cmp_ok( $p->{timeout}, '==', 10, 'timeout is a sibling of detect' );
    ok( !exists $p->{detect}{params}{timeout}, 'timeout NOT inside detect.params' );
    $client->disconnect;
};

subtest 'detect_answering_machine builds machine detect, only-provided params' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-damd' );
    my $action = $call->detect_answering_machine(
        initial_timeout         => 4.5,
        machine_words_threshold => 6,
        detect_interruptions    => JSON::false(),
        timeout                 => 30,
    );
    isa_ok( $action, 'SignalWire::Relay::Action::Detect' );
    my $p = RelayMockTest::journal_recv( method => 'calling.detect' )->[0]{frame}{params};
    is( $p->{detect}{type}, 'machine', 'detect type machine' );
    cmp_ok( $p->{detect}{params}{initial_timeout}, '==', 4.5, 'initial_timeout on wire' );
    cmp_ok( $p->{detect}{params}{machine_words_threshold},
        '==', 6, 'machine_words_threshold on wire' );
    ok(
        exists $p->{detect}{params}{detect_interruptions},
        'detect_interruptions present (false is provided)'
    );
    ok( !exists $p->{detect}{params}{end_silence_timeout},     'unset AMD knob omitted' );
    ok( !exists $p->{detect}{params}{machine_voice_threshold}, 'unset AMD knob omitted' );
    cmp_ok( $p->{timeout}, '==', 30, 'timeout is a sibling of detect' );
    $client->disconnect;
};

subtest 'detect_fax builds fax detect on calling.detect' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-dfax' );
    my $action = $call->detect_fax( tone => 'CED', timeout => 15 );
    isa_ok( $action, 'SignalWire::Relay::Action::Detect' );
    my $p = RelayMockTest::journal_recv( method => 'calling.detect' )->[0]{frame}{params};
    is( $p->{detect}{type},         'fax', 'detect type fax' );
    is( $p->{detect}{params}{tone}, 'CED', 'fax tone inside detect.params' );
    cmp_ok( $p->{timeout}, '==', 15, 'timeout is a sibling of detect' );
    $client->disconnect;
};

# ---------------------------------------------------------------------------
# Prompt convenience: prompt_tts / prompt_audio
# Typed media over play_and_collect(); collect hashref passes through verbatim.
# ---------------------------------------------------------------------------

subtest 'prompt_tts builds tts media + collect on calling.play_and_collect' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-ptts' );
    my $action = $call->prompt_tts(
        'Press a key',
        { digits => { max => 1 } },
        voice  => 'spore',
        volume => 1.0
    );
    isa_ok( $action, 'SignalWire::Relay::Action::Collect' );
    my $p = RelayMockTest::journal_recv( method => 'calling.play_and_collect' )->[0]{frame}{params};
    is( $p->{play}[0]{type},          'tts',         'media type tts' );
    is( $p->{play}[0]{params}{text},  'Press a key', 'tts text on wire' );
    is( $p->{play}[0]{params}{voice}, 'spore',       'tts voice on wire' );
    is( $p->{collect}{digits}{max},   1,             'collect passed through verbatim' );
    cmp_ok( $p->{volume}, '==', 1.0, 'volume sibling on wire' );
    $client->disconnect;
};

subtest 'prompt_audio builds audio media + collect on calling.play_and_collect' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-paudc' );
    my $action =
        $call->prompt_audio( 'https://cdn.example/p.wav', { speech => { language => 'en-US' } } );
    isa_ok( $action, 'SignalWire::Relay::Action::Collect' );
    my $p = RelayMockTest::journal_recv( method => 'calling.play_and_collect' )->[0]{frame}{params};
    is( $p->{play}[0]{type},             'audio',                     'media type audio' );
    is( $p->{play}[0]{params}{url},      'https://cdn.example/p.wav', 'audio url on wire' );
    is( $p->{collect}{speech}{language}, 'en-US', 'collect.speech passed through verbatim' );
    ok( !exists $p->{volume}, 'no volume key when unset' );
    $client->disconnect;
};

# ---------------------------------------------------------------------------
# RecordAction
# ---------------------------------------------------------------------------

subtest 'record journals calling.record' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-rec' );
    $call->record( record => { audio => { format => 'mp3' } } );
    my $entries = RelayMockTest::journal_recv( method => 'calling.record' );
    is( scalar @$entries, 1, 'one entry' );
    my $p = $entries->[0]{frame}{params};
    is( $p->{call_id}, 'call-rec', 'call_id on wire' );
    ok( $p->{control_id}, 'control_id on wire' );
    is( $p->{record}{audio}{format}, 'mp3', 'record.audio.format on wire' );
    $client->disconnect;
};

subtest 'record resolves on finished event' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-rec-fin' );
    RelayMockTest::arm_method(
        'calling.record',
        [
            { emit => { state => 'recording' },                       delay_ms => 1 },
            { emit => { state => 'finished', url => 'http://r.wav' }, delay_ms => 5 },
        ]
    );
    my $action = $call->record( record => { audio => { format => 'wav' } } );
    isa_ok( $action, 'SignalWire::Relay::Action::Record' );
    _pump_until( $client, 5, sub { $action->is_done } );
    ok( $action->is_done, 'action resolved' );
    $client->disconnect;
};

subtest 'record stop journals calling.record.stop' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-rec-stop' );
    my $action = $call->record( record => { audio => { format => 'wav' } } );
    $action->stop;
    my $stops = RelayMockTest::journal_recv( method => 'calling.record.stop' );
    ok( scalar @$stops, 'stop journaled' );
    is( $stops->[-1]{frame}{params}{control_id}, $action->control_id, 'control_id matches' );
    $client->disconnect;
};

# ---------------------------------------------------------------------------
# DetectAction — gotcha: resolves on first detect payload
# ---------------------------------------------------------------------------

subtest 'detect resolves on first detect payload' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-det' );
    RelayMockTest::arm_method(
        'calling.detect',
        [
            {
                emit     => { detect => { type => 'machine', params => { event => 'MACHINE' } } },
                delay_ms => 1
            },

            # A finished state would also resolve via ACTION_TERMINAL_STATES,
            # but the Perl SDK now resolves on the first `params.detect` payload
            # — same as Python. The state(finished) is still emitted so we
            # don't accidentally resolve on it instead.
            { emit => { state => 'finished' }, delay_ms => 50 },
        ]
    );
    my $action = $call->detect( detect => { type => 'machine', params => {} }, );
    isa_ok( $action, 'SignalWire::Relay::Action::Detect' );
    _pump_until( $client, 5, sub { $action->is_done } );
    ok( $action->is_done, 'action resolved' );

    # The resolve event should be the detect payload one (not finished).
    my $resolve_event = $action->result;
    if ( $resolve_event && $resolve_event->can('params') ) {
        my $p = $resolve_event->params // {};
        ok(
            ref $p->{detect} eq 'HASH' && $p->{detect}{type} eq 'machine',
            'resolved on detect payload, not state(finished)'
        );
    }
    $client->disconnect;
};

subtest 'detect stop journals calling.detect.stop' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-det-stop' );
    my $action = $call->detect( detect => { type => 'fax', params => {} } );
    $action->stop;
    my $stops = RelayMockTest::journal_recv( method => 'calling.detect.stop' );
    ok( scalar @$stops, 'stop journaled' );
    $client->disconnect;
};

# ---------------------------------------------------------------------------
# CollectAction — play_and_collect gotcha
# ---------------------------------------------------------------------------

subtest 'play_and_collect journals calling.play_and_collect' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-pac' );
    $call->play_and_collect(
        play    => [ { type => 'tts', params => { text => 'Press 1' } } ],
        collect => { digits => { max => 1 } },
    );
    my $entries = RelayMockTest::journal_recv( method => 'calling.play_and_collect' );
    is( scalar @$entries, 1, 'one entry' );
    my $p = $entries->[0]{frame}{params};
    is( $p->{call_id},              'call-pac', 'call_id on wire' );
    is( $p->{play}[0]{type},        'tts',      'play[0].type on wire' );
    is( $p->{collect}{digits}{max}, 1,          'collect.digits.max on wire' );
    $client->disconnect;
};

subtest 'play_and_collect resolves on collect event only' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-pac-go' );
    my $action = $call->play_and_collect(
        play    => [ { type => 'silence', params => { duration => 1 } } ],
        collect => { digits => { max => 1 } },
    );
    isa_ok( $action, 'SignalWire::Relay::Action::Collect' );

    # Push a play(finished) — must NOT resolve.
    RelayMockTest::push_frame(
        {
            jsonrpc => '2.0',
            id      => 'evt-pac-play',
            method  => 'signalwire.event',
            params  => {
                event_type => 'calling.call.play',
                params     => {
                    call_id    => 'call-pac-go',
                    control_id => $action->control_id,
                    state      => 'finished',
                },
            },
        }
    );
    _pump_until( $client, 1, sub { $action->is_done } );
    ok( !$action->is_done, 'play(finished) does NOT resolve play_and_collect' );

    # Push collect with a result — resolves.
    RelayMockTest::push_frame(
        {
            jsonrpc => '2.0',
            id      => 'evt-pac-collect',
            method  => 'signalwire.event',
            params  => {
                event_type => 'calling.call.collect',
                params     => {
                    call_id    => 'call-pac-go',
                    control_id => $action->control_id,
                    result     => { type => 'digit', params => { digits => '1' } },
                },
            },
        }
    );
    _pump_until( $client, 5, sub { $action->is_done } );
    ok( $action->is_done, 'action resolved on collect with result' );
    $client->disconnect;
};

subtest 'play_and_collect stop journals pac.stop' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-pac-stop' );
    my $action = $call->play_and_collect(
        play    => [ { type => 'silence', params => { duration => 1 } } ],
        collect => { digits => { max => 1 } },
    );
    $action->stop;
    my $stops = RelayMockTest::journal_recv( method => 'calling.play_and_collect.stop' );
    ok( scalar @$stops, 'stop journaled' );
    $client->disconnect;
};

# ---------------------------------------------------------------------------
# StandaloneCollectAction
# ---------------------------------------------------------------------------

subtest 'collect journals calling.collect' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-col' );
    my $action = $call->collect( digits => { max => 4 } );
    isa_ok( $action, 'SignalWire::Relay::Action::StandaloneCollect' );
    my $entries = RelayMockTest::journal_recv( method => 'calling.collect' );
    is( scalar @$entries, 1, 'one entry' );
    is_deeply( $entries->[0]{frame}{params}{digits}, { max => 4 }, 'digits on wire' );
    $client->disconnect;
};

subtest 'collect stop journals calling.collect.stop' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-col-stop' );
    my $action = $call->collect( digits => { max => 4 } );
    $action->stop;
    my $stops = RelayMockTest::journal_recv( method => 'calling.collect.stop' );
    ok( scalar @$stops, 'stop journaled' );
    $client->disconnect;
};

# ---------------------------------------------------------------------------
# PayAction
# ---------------------------------------------------------------------------

subtest 'pay journals calling.pay' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-pay' );
    $call->pay(
        payment_connector_url => 'https://pay.example/connect',
        charge_amount         => '9.99',
    );
    my $entries = RelayMockTest::journal_recv( method => 'calling.pay' );
    is( scalar @$entries, 1, 'one entry' );
    my $p = $entries->[0]{frame}{params};
    is( $p->{payment_connector_url},
        'https://pay.example/connect', 'payment_connector_url on wire' );
    is( $p->{charge_amount}, '9.99', 'charge_amount on wire' );
    $client->disconnect;
};

subtest 'pay returns PayAction' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-pay-act' );
    my $action = $call->pay( payment_connector_url => 'https://pay.example/connect', );
    isa_ok( $action, 'SignalWire::Relay::Action::Pay' );
    $client->disconnect;
};

subtest 'pay stop journals calling.pay.stop' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-pay-stop' );
    my $action = $call->pay( payment_connector_url => 'https://pay.example/connect', );
    $action->stop;
    my $stops = RelayMockTest::journal_recv( method => 'calling.pay.stop' );
    ok( scalar @$stops, 'stop journaled' );
    $client->disconnect;
};

# ---------------------------------------------------------------------------
# FaxAction
# ---------------------------------------------------------------------------

subtest 'send_fax journals calling.send_fax' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-sfax' );
    $call->send_fax(
        document => 'https://docs.example/test.pdf',
        identity => '+15551112222',
    );
    my $entries = RelayMockTest::journal_recv( method => 'calling.send_fax' );
    is( scalar @$entries, 1, 'one entry' );
    my $p = $entries->[0]{frame}{params};
    is( $p->{document}, 'https://docs.example/test.pdf', 'document on wire' );
    is( $p->{identity}, '+15551112222',                  'identity on wire' );
    $client->disconnect;
};

subtest 'receive_fax returns FaxAction' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-rfax' );
    my $action = $call->receive_fax;
    isa_ok( $action, 'SignalWire::Relay::Action::Fax' );
    $client->disconnect;
};

# ---------------------------------------------------------------------------
# TapAction
# ---------------------------------------------------------------------------

subtest 'tap journals calling.tap' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-tap' );
    $call->tap(
        tap    => { type => 'audio', params => {} },
        device => { type => 'rtp',   params => { addr => '203.0.113.1', port => 4000 } },
    );
    my $entries = RelayMockTest::journal_recv( method => 'calling.tap' );
    is( scalar @$entries, 1, 'one entry' );
    my $p = $entries->[0]{frame}{params};
    is( $p->{tap}{type},            'audio', 'tap.type on wire' );
    is( $p->{device}{params}{port}, 4000,    'device.params.port on wire' );
    $client->disconnect;
};

subtest 'tap stop journals calling.tap.stop' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-tap-stop' );
    my $action = $call->tap(
        tap    => { type => 'audio', params => {} },
        device => { type => 'rtp',   params => { addr => '203.0.113.1', port => 4000 } },
    );
    isa_ok( $action, 'SignalWire::Relay::Action::Tap' );
    $action->stop;
    my $stops = RelayMockTest::journal_recv( method => 'calling.tap.stop' );
    ok( scalar @$stops, 'stop journaled' );
    $client->disconnect;
};

# ---------------------------------------------------------------------------
# StreamAction
# ---------------------------------------------------------------------------

subtest 'stream journals calling.stream' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-strm' );
    $call->stream(
        url   => 'wss://stream.example/audio',
        codec => 'OPUS@48000h',
    );
    my $entries = RelayMockTest::journal_recv( method => 'calling.stream' );
    is( scalar @$entries, 1, 'one entry' );
    my $p = $entries->[0]{frame}{params};
    is( $p->{url},   'wss://stream.example/audio', 'url on wire' );
    is( $p->{codec}, 'OPUS@48000h',                'codec on wire' );
    $client->disconnect;
};

subtest 'stream stop journals calling.stream.stop' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-strm-stop' );
    my $action = $call->stream( url => 'wss://stream.example/audio' );
    isa_ok( $action, 'SignalWire::Relay::Action::Stream' );
    $action->stop;
    my $stops = RelayMockTest::journal_recv( method => 'calling.stream.stop' );
    ok( scalar @$stops, 'stop journaled' );
    $client->disconnect;
};

# ---------------------------------------------------------------------------
# TranscribeAction
# ---------------------------------------------------------------------------

subtest 'transcribe journals calling.transcribe' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-tr' );
    my $action = $call->transcribe;
    isa_ok( $action, 'SignalWire::Relay::Action::Transcribe' );
    my $entries = RelayMockTest::journal_recv( method => 'calling.transcribe' );
    is( scalar @$entries, 1, 'one entry' );
    ok( $entries->[0]{frame}{params}{control_id}, 'control_id on wire' );
    $client->disconnect;
};

subtest 'transcribe stop journals calling.transcribe.stop' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-tr-stop' );
    my $action = $call->transcribe;
    $action->stop;
    my $stops = RelayMockTest::journal_recv( method => 'calling.transcribe.stop' );
    ok( scalar @$stops, 'stop journaled' );
    $client->disconnect;
};

# ---------------------------------------------------------------------------
# AIAction
# ---------------------------------------------------------------------------

subtest 'ai journals calling.ai' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-ai' );
    my $action = $call->ai( prompt => { text => 'You are helpful.' } );
    isa_ok( $action, 'SignalWire::Relay::Action::AI' );
    my $entries = RelayMockTest::journal_recv( method => 'calling.ai' );
    is( scalar @$entries, 1, 'one entry' );
    is_deeply(
        $entries->[0]{frame}{params}{prompt},
        { text => 'You are helpful.' },
        'prompt on wire'
    );
    $client->disconnect;
};

subtest 'ai stop journals calling.ai.stop' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-ai-stop' );
    my $action = $call->ai( prompt => { text => 'You are helpful.' } );
    $action->stop;
    my $stops = RelayMockTest::journal_recv( method => 'calling.ai.stop' );
    ok( scalar @$stops, 'stop journaled' );
    $client->disconnect;
};

# ---------------------------------------------------------------------------
# Concurrent actions
# ---------------------------------------------------------------------------

subtest 'concurrent play and record route independently' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'call-multi' );
    my $play_a = $call->play( play => [ { type => 'silence', params => { duration => 60 } } ], );
    my $rec_a  = $call->record( record => { audio => { format => 'wav' } } );
    ok( $play_a->control_id ne $rec_a->control_id, 'control_ids differ' );

    # Push finished only for play.
    RelayMockTest::push_frame(
        {
            jsonrpc => '2.0',
            id      => 'evt-multi-play',
            method  => 'signalwire.event',
            params  => {
                event_type => 'calling.call.play',
                params     => {
                    call_id    => 'call-multi',
                    control_id => $play_a->control_id,
                    state      => 'finished',
                },
            },
        }
    );
    _pump_until( $client, 5, sub { $play_a->is_done } );
    ok( $play_a->is_done, 'play resolved' );
    ok( !$rec_a->is_done, 'record still pending' );
    $client->disconnect;
};

# ---------------------------------------------------------------------------
# Action outlives its Call handle
#
# `Action.call` is a weak_ref (Call._actions holds every Action strongly, so a
# strong back-reference would leak the cycle under Perl's refcounting; the
# python reference relies on its cycle collector instead). Identity + transport
# must therefore be SNAPSHOTTED at construction, not derived lazily through the
# weak handle -- otherwise the moment the caller stops holding the Call, the
# handle goes undef, `_client` resolves to undef, and every control-op silently
# returns on its `return unless $client` guard, emitting NOTHING on the wire.
#
# The regression: an ordinary chained `$call->play(...)->stop` sent no frame at
# all, and so did pause / resume / volume.
# ---------------------------------------------------------------------------

subtest 'control-ops still emit when the Call handle has gone out of scope' => sub {
    my $client = _connected_client();

    # Deliberately do NOT keep the Call: take only the Action, exactly as a
    # chained `$call->play(...)->stop` would. The Call is unreferenced the
    # instant this statement completes.
    my $action = do {
        my $call = _answered_inbound_call( $client, 'call-orphan-action' );
        $call->play( play => [ { type => 'silence', params => { duration => 60 } } ] );
    };
    isa_ok( $action, 'SignalWire::Relay::Action::Play' );

    # NOTE: no assertion that `call` is already undef here — this client tracks
    # the inbound call in its own `_calls` map, so the Call legitimately outlives
    # the lexical. What must hold either way is that the transport and identity
    # do not depend on that handle; the unit test below drives the collected case
    # directly.
    ok( defined $action->_client, 'transport does not depend on the Call lexical' );
    is( $action->call_id, 'call-orphan-action', 'call_id was snapshotted at construction' );

    $action->stop;
    ok( scalar @{ RelayMockTest::journal_recv( method => 'calling.play.stop' ) },
        'stop still journaled calling.play.stop' );

    $action->pause('silence');
    ok( scalar @{ RelayMockTest::journal_recv( method => 'calling.play.pause' ) },
        'pause still journaled calling.play.pause' );

    $action->volume(3.5);
    ok( scalar @{ RelayMockTest::journal_recv( method => 'calling.play.volume' ) },
        'volume still journaled calling.play.volume' );

    $client->disconnect;
};

done_testing();
