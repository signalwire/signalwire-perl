#!/usr/bin/env perl
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# wire-relay-dump.pl — the Perl port's WIRE-RELAY dump program for the
# cross-port relay differ (porting-sdk/scripts/diff_port_wire_relay.py).
#
# It captures, for each wire_relay_corpus case, the observable RELAY artifact:
#   - verb   : the {method, params} JSON-RPC frame a Call verb (or an Action
#              control-op) hands to the wire.
#   - client : the {method, params} frame a RelayClient call (execute / dial /
#              send_message) sends.
#   - event  : the decoded fields a typed event decoder extracts from a payload.
#
# It prints ONE JSON object mapping case-id -> artifact to stdout; the differ
# canonicalizes both sides (normalizing the random control_id to a sentinel) and
# byte-compares against the python oracle. Only stdout carries JSON.
# Mirrors signalwire-go/cmd/wire-relay-dump.
#
# Frame capture (interpreted-port idiom): a recording RelayClient subclass
# overrides ``execute`` to record each {method, params} frame and return a canned
# success — no real socket / WS is involved. Call verbs and Action control-ops
# all funnel through $client->execute, so this captures every frame. Event
# decoding is pure (from_payload / parse_event).
#
# Run from the signalwire-perl repo root:
#
#     perl -Ilib bin/wire-relay-dump.pl

use strict;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use FindBin qw($RealBin);
use File::Spec;
use JSON ();

use lib File::Spec->catdir( $RealBin, File::Spec->updir, 'lib' );

use SignalWire::Relay::Call;
use SignalWire::Relay::Client;
use SignalWire::Relay::Event;

my $NODE = 'node-abc';
my $CALL = 'call-xyz';
my $CID  = 'ctl-123';

# ----------------------------------------------------------------------------
# RecordingClient — a RelayClient whose execute() records the wire frame and
# returns a canned success. For calling.dial it also resolves the pending dial
# (dial() blocks on a calling.call.dial event) with a stub Call so dial()
# returns at once.
# ----------------------------------------------------------------------------
{

    package RecordingClient;
    use Moo;
    extends 'SignalWire::Relay::Client';

    has frames => ( is => 'rw', default => sub { [] } );

    sub execute ( $self, $method, $params = undef ) {
        $params //= {};
        push @{ $self->frames }, { method => $method, params => $params };

        # Resolve a pending dial so RelayClient::dial does not block.
        if ( $method eq 'calling.dial' ) {
            my $tag     = $params->{tag};
            my $pending = $tag ? $self->_pending_dials->{$tag} : undef;
            if ($pending) {
                my $call = SignalWire::Relay::Call->new(
                    call_id => 'call-xyz',
                    node_id => 'node-abc',
                    _client => $self,
                );
                $pending->{resolve}->($call);
            }
            return { code => '200', message => 'Dialing' };
        }
        return { code => '200', message_id => 'msg-1' } if $method eq 'messaging.send';
        return { code => '200' };
    }

    # last_frame observes the CLIENT-SEND boundary: it returns the most recent
    # frame that actually reached execute(). If a verb built a frame but never
    # transmitted (never called $client->execute), frames is empty and we return
    # the oracle's sentinel so the case FAILS — mirroring diff_port_wire_relay's
    # {"_no_frame_transmitted": True}. (Perl Call verbs all funnel through
    # $client->execute, so this sentinel never fires here — it enforces the
    # invariant, not the current behavior.)
    sub last_frame ($self) {
        my $f = $self->frames->[-1];
        return defined $f ? $f : { _no_frame_transmitted => JSON::true };
    }
    sub clear_frames ($self) { $self->frames( [] ); return; }
}

sub new_client {
    return RecordingClient->new( project => 'proj-1', token => 'tok-1', host => 'mock' );
}

# new_call builds a Call bound to a fresh recording client (answered, so
# _start_action proceeds).
sub new_call ($client) {
    return SignalWire::Relay::Call->new(
        call_id => $CALL,
        node_id => $NODE,
        state   => 'answered',
        _client => $client,
    );
}

sub jbool ($v) { return $v ? JSON::true : JSON::false; }

# ---- verb frames (over the recording client) ----
sub capture_verbs ($out) {
    my $c;

    # relay_play
    $c = new_client();
    new_call($c)
        ->play( play => [ { type => 'audio', params => { url => 'https://x/a.mp3' } } ],
        volume => 5.0, control_id => $CID );
    $out->{relay_play} = $c->last_frame;

    # relay_play_tts
    $c = new_client();
    new_call($c)->play_tts( 'Hello world', voice => 'en-US-Neural' );
    $out->{relay_play_tts} = $c->last_frame;

    # relay_record
    $c = new_client();
    new_call($c)->record( record => { audio => { format => 'mp3', beep => JSON::true } }, control_id => $CID );
    $out->{relay_record} = $c->last_frame;

    # relay_connect
    $c = new_client();
    new_call($c)->connect(
        devices  => [ [ { type => 'phone', params => { to_number => '+15551112222' } } ] ],
        ringback => [ { type => 'ringtone', params => { name => 'us' } } ],
        tag      => 'leg-1',
        max_duration => 3600,
    );
    $out->{relay_connect} = $c->last_frame;

    # relay_collect
    $c = new_client();
    new_call($c)->collect(
        digits          => { max => 4, terminators => '#' },
        speech          => { language => 'en-US' },
        initial_timeout => 5.0,
        partial_results => JSON::true,
        control_id      => $CID,
    );
    $out->{relay_collect} = $c->last_frame;

    # relay_prompt (play_and_collect via prompt_tts)
    $c = new_client();
    new_call($c)->prompt_tts( 'Enter your PIN', { digits => { max => 4 } }, voice => 'en-US-Neural' );
    $out->{relay_prompt} = $c->last_frame;

    # relay_detect
    $c = new_client();
    new_call($c)
        ->detect( detect => { type => 'machine', params => { initial_timeout => 4.0 } },
        timeout => 30.0, control_id => $CID );
    $out->{relay_detect} = $c->last_frame;

    # relay_detect_amd
    $c = new_client();
    new_call($c)->detect_answering_machine(
        initial_timeout         => 4.0,
        machine_words_threshold => 6,
        timeout                 => 30.0,
    );
    $out->{relay_detect_amd} = $c->last_frame;

    # relay_tap
    $c = new_client();
    new_call($c)->tap(
        tap    => { type => 'audio', params => { direction => 'both' } },
        device => { type => 'ws',    params => { uri       => 'wss://x/tap' } },
        control_id => $CID,
    );
    $out->{relay_tap} = $c->last_frame;

    # relay_send_fax
    $c = new_client();
    new_call($c)->send_fax(
        document    => 'https://x/doc.pdf',
        identity    => '+15550001111',
        header_info => 'Hdr',
        control_id  => $CID,
    );
    $out->{relay_send_fax} = $c->last_frame;

    # relay_live_transcribe: caller's action MUST land as params.action (the
    # authoritative wire schema requires it -- relay-protocol/calling.live_transcribe.params.json).
    $c = new_client();
    new_call($c)->live_transcribe( { start => { lang => 'en' } } );
    $out->{relay_live_transcribe} = $c->last_frame;

    # relay_live_translate: same contract, plus optional sibling status_url.
    $c = new_client();
    new_call($c)->live_translate(
        { start => { from_lang => 'en', to_lang => 'es' } },
        status_url => 'https://x/cb',
    );
    $out->{relay_live_translate} = $c->last_frame;

    # ---- control-ops (Action methods) ----
    # relay_play_stop
    $c = new_client();
    my $pa = new_call($c)
        ->play( play => [ { type => 'audio', params => { url => 'https://x/a.mp3' } } ], control_id => $CID );
    $c->clear_frames;
    $pa->stop;
    $out->{relay_play_stop} = $c->last_frame;

    # relay_play_pause
    $c = new_client();
    my $pa2 = new_call($c)
        ->play( play => [ { type => 'audio', params => { url => 'https://x/a.mp3' } } ], control_id => $CID );
    $c->clear_frames;
    $pa2->pause('silence');
    $out->{relay_play_pause} = $c->last_frame;

    # relay_record_resume
    $c = new_client();
    my $ra = new_call($c)->record( record => { audio => { format => 'mp3' } }, control_id => $CID );
    $c->clear_frames;
    $ra->resume;
    $out->{relay_record_resume} = $c->last_frame;

    # relay_play_volume
    $c = new_client();
    my $pa3 = new_call($c)
        ->play( play => [ { type => 'audio', params => { url => 'https://x/a.mp3' } } ], control_id => $CID );
    $c->clear_frames;
    $pa3->volume(3.5);
    $out->{relay_play_volume} = $c->last_frame;
    return;
}

# ---- client-level frames ----
sub capture_client ($out) {
    my $c;

    # relay_client_execute
    $c = new_client();
    $c->execute( 'calling.answer', { node_id => $NODE, call_id => $CALL } );
    $out->{relay_client_execute} = $c->last_frame;

    # relay_send_message
    $c = new_client();
    $c->send_message(
        to_number   => '+15551112222',
        from_number => '+15553334444',
        body        => 'hi',
        tags        => ['t1'],
    );
    $out->{relay_send_message} = $c->last_frame;

    # relay_dial (the calling.dial frame; execute() resolves the pending dial)
    $c = new_client();
    $c->dial(
        devices => [ [ { type => 'phone', params => { to_number => '+15551112222' } } ] ],
        tag     => 'dial-1',
        max_duration => 600,
    );
    for my $fr ( @{ $c->frames } ) {
        if ( $fr->{method} eq 'calling.dial' ) { $out->{relay_dial} = $fr; last; }
    }
    return;
}

# ---- event decoders (pure) ----
sub decode_events ($out) {

    # relay_evt_queue
    my $q = SignalWire::Relay::Event::CallQueue->from_payload(
        {   event_type => 'calling.call.queue',
            params     => {
                call_id => $CALL, control_id => $CID, status => 'waiting',
                id      => 'q-42', name => 'support', position => 3, size => 10,
            },
        }
    );
    $out->{relay_evt_queue} = {
        control_id => $q->control_id,
        status     => $q->status,
        queue_id   => $q->queue_id,
        queue_name => $q->queue_name,
        position   => $q->position,
        size       => $q->size,
    };

    # relay_evt_record (url/duration/size fall back from nested record{})
    my $rec = SignalWire::Relay::Event::CallRecord->from_payload(
        {   event_type => 'calling.call.record',
            params     => {
                call_id => $CALL, control_id => $CID, state => 'finished',
                record  => { url => 'https://x/rec.mp3', duration => 12.5, size => 4096 },
            },
        }
    );
    $out->{relay_evt_record} = {
        control_id => $rec->control_id,
        state      => $rec->state,
        url        => $rec->url,
        duration   => $rec->duration,
        size       => $rec->size,
    };

    # relay_evt_state_dispatch (parse_event -> CallStateEvent). The observable
    # _class is the canonical Python class name.
    my $obj = SignalWire::Relay::Event->parse_event( 'calling.call.state',
        { call_id => $CALL, call_state => 'answered', direction => 'inbound', end_reason => '' } );
    $out->{relay_evt_state_dispatch} = {
        _class     => 'CallStateEvent',
        call_id    => $obj->call_id,
        call_state => $obj->call_state,
        direction  => $obj->direction,
    };

    # relay_evt_collect
    my $col = SignalWire::Relay::Event::CallCollect->from_payload(
        {   event_type => 'calling.call.collect',
            params     => {
                call_id => $CALL, control_id => $CID, state => 'finished',
                result  => { type => 'digit', params => { digits => '1234' } },
                final   => JSON::true,
            },
        }
    );
    $out->{relay_evt_collect} = {
        control_id => $col->control_id,
        state      => $col->state,
        result     => $col->result,
        final      => $col->final,
    };
    return;
}

sub main {
    my %out;
    decode_events( \%out );
    capture_verbs( \%out );
    capture_client( \%out );

    print JSON->new->canonical->encode( \%out ), "\n";
    return 0;
}

exit main();
