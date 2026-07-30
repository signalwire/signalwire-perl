#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use SignalWire::Relay::Call;
use SignalWire::Relay::Event;
use SignalWire::Relay::Action;

# ============================================================
# 1. Construction
# ============================================================
subtest 'construction' => sub {
    my $call = SignalWire::Relay::Call->new(
        call_id => 'c1',
        node_id => 'n1',
        tag     => 't1',
    );
    is( $call->call_id, 'c1',      'call_id' );
    is( $call->node_id, 'n1',      'node_id' );
    is( $call->tag,     't1',      'tag' );
    is( $call->state,   'created', 'initial state' );
};

# project_id / direction / segment_id are construction params the reference
# records on Call (relay/call.py:341-353): settable AND readable back.
subtest 'project_id / direction / segment_id round-trip through construction' => sub {
    my $call = SignalWire::Relay::Call->new(
        call_id    => 'c-rt',
        project_id => 'proj-abc',
        direction  => 'outbound',
        segment_id => 'seg-7',
    );
    is( $call->project_id, 'proj-abc', 'project_id readable back' );
    is( $call->direction,  'outbound', 'direction readable back' );
    is( $call->segment_id, 'seg-7',    'segment_id readable back' );

    my $bare = SignalWire::Relay::Call->new( call_id => 'c-bare' );
    is( $bare->project_id, '', 'project_id defaults empty' );
    is( $bare->direction,  '', 'direction defaults empty' );
    is( $bare->segment_id, '', 'segment_id defaults empty' );
};

# ============================================================
# 2. State transitions via events
# ============================================================
subtest 'state transitions' => sub {
    my $call = SignalWire::Relay::Call->new( call_id => 'c2', node_id => 'n2' );

    for my $state (qw(ringing answered ending ended)) {
        my $event = SignalWire::Relay::Event->parse_event(
            'calling.call.state',
            {
                call_id    => 'c2',
                call_state => $state,
            }
        );
        $call->dispatch_event($event);
        is( $call->state, $state, "state changed to $state" );
    }
};

# ============================================================
# 3. End reason
# ============================================================
subtest 'end reason' => sub {
    my $call  = SignalWire::Relay::Call->new( call_id => 'c3', node_id => 'n3' );
    my $event = SignalWire::Relay::Event->parse_event(
        'calling.call.state',
        {
            call_id    => 'c3',
            call_state => 'ended',
            end_reason => 'hangup',
        }
    );
    $call->dispatch_event($event);
    is( $call->end_reason, 'hangup', 'end_reason set' );
};

# ============================================================
# 4. Event listener
# ============================================================
subtest 'event listener' => sub {
    my $call = SignalWire::Relay::Call->new( call_id => 'c4', node_id => 'n4' );
    my @received;
    $call->on( sub { push @received, $_[1] } );

    my $event = SignalWire::Relay::Event->parse_event(
        'calling.call.state',
        {
            call_id    => 'c4',
            call_state => 'ringing',
        }
    );
    $call->dispatch_event($event);
    is( scalar @received,         1,         'listener called once' );
    is( $received[0]->call_state, 'ringing', 'correct event' );
};

# ============================================================
# 5. Actions resolved on call end
# ============================================================
subtest 'actions resolved on end' => sub {
    my $call   = SignalWire::Relay::Call->new( call_id => 'c5', node_id => 'n5' );
    my $action = SignalWire::Relay::Action::Play->new(
        control_id => 'ctl-5',
        call_id    => 'c5',
        node_id    => 'n5',
    );
    $call->_actions->{'ctl-5'} = $action;

    my $event = SignalWire::Relay::Event->parse_event(
        'calling.call.state',
        {
            call_id    => 'c5',
            call_state => 'ended',
        }
    );
    $call->dispatch_event($event);
    ok( $action->is_done, 'action resolved on end' );
};

# ============================================================
# 6. All simple methods exist
# ============================================================
subtest 'simple methods' => sub {
    my $call = SignalWire::Relay::Call->new( call_id => 'x', node_id => 'n' );
    for my $m (
        qw(answer hangup pass connect disconnect hold unhold
        denoise denoise_stop transfer join_conference leave_conference
        echo join_room leave_room send_digits)
        )
    {
        ok( $call->can($m), "has method: $m" );
    }
};

# ============================================================
# 7. All action methods exist
# ============================================================
subtest 'action methods' => sub {
    my $call = SignalWire::Relay::Call->new( call_id => 'x', node_id => 'n' );
    for my $m (
        qw(play record detect collect play_and_collect
        send_fax receive_fax tap stream pay transcribe ai)
        )
    {
        ok( $call->can($m), "has action method: $m" );
    }
};

# ============================================================
# 7b. Concrete action control surface (parity with the Python oracle:
#     the control methods are projected onto each concrete action, NOT
#     onto abstract Stoppable/Pausable/Volume bases).
# ============================================================
subtest 'concrete action control methods' => sub {

    # Every concrete action is stoppable.
    my %stop_only = (
        'SignalWire::Relay::Action::AI'         => 'AIAction',
        'SignalWire::Relay::Action::Detect'     => 'DetectAction',
        'SignalWire::Relay::Action::Fax'        => 'FaxAction',
        'SignalWire::Relay::Action::Pay'        => 'PayAction',
        'SignalWire::Relay::Action::Stream'     => 'StreamAction',
        'SignalWire::Relay::Action::Tap'        => 'TapAction',
        'SignalWire::Relay::Action::Transcribe' => 'TranscribeAction',
    );
    for my $pkg ( sort keys %stop_only ) {
        ok( $pkg->can('stop'), "$stop_only{$pkg} has stop" );
    }

    # Play: stop + pause + resume + volume.
    my $play = 'SignalWire::Relay::Action::Play';
    ok( $play->can($_), "PlayAction has $_" ) for qw(stop pause resume volume);

    # Record: stop + pause + resume, but NO volume (matches the oracle).
    my $record = 'SignalWire::Relay::Action::Record';
    ok( $record->can($_),        "RecordAction has $_" ) for qw(stop pause resume);
    ok( !$record->can('volume'), 'RecordAction has NO volume' );

    # Collect: stop + pause + resume + volume + start_input_timers.
    my $collect = 'SignalWire::Relay::Action::Collect';
    ok( $collect->can($_), "CollectAction has $_" )
        for qw(stop pause resume volume start_input_timers);

    # StandaloneCollect: stop + start_input_timers (inherits from Collect).
    my $sc = 'SignalWire::Relay::Action::StandaloneCollect';
    ok( $sc->can($_), "StandaloneCollectAction has $_" )
        for qw(stop start_input_timers);

    # pause accepts an optional behavior string (no-arg and 1-arg both live).
    my $client_calls = [];
    my $fake_client  = bless {}, 'FakeRelayClient';
    {
        # A test double installed by poking the symbol table: FakeRelayClient
        # has no compile-time definition, so a symbolic glob assignment is the
        # only way to give it an execute() the code under test can call.
        no strict 'refs';    ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{'FakeRelayClient::execute'} = sub {
            my ( $self, $method, $params ) = @_;
            push @$client_calls, [ $method, $params ];
            return { ok => 1 };
        };
    }

    # The action derives call_id / node_id / client from the call it belongs
    # to (the reference's Action.__init__(call, control_id, ...) shape), so
    # build the owning call and hand it over rather than setting the three
    # identity fields on the action directly.
    my $owning_call = SignalWire::Relay::Call->new(
        call_id => 'c',
        node_id => 'n',
        _client => $fake_client,
    );
    my $pa = $play->new( call => $owning_call, control_id => 'ctl-p' );
    $pa->pause;               # no behavior
    $pa->pause('collect');    # with behavior
    is( $client_calls->[0][0], 'calling.play.pause', 'play.pause verb' );
    ok( !exists $client_calls->[0][1]{behavior}, 'no-arg pause omits behavior' );
    is( $client_calls->[1][1]{behavior}, 'collect', 'pause(behavior) sends behavior' );
};

# ============================================================
# 8. Multiple listeners
# ============================================================
subtest 'multiple listeners' => sub {
    my $call = SignalWire::Relay::Call->new( call_id => 'c8', node_id => 'n8' );
    my ( $a, $b ) = ( 0, 0 );
    $call->on( sub { $a++ } );
    $call->on( sub { $b++ } );

    my $event = SignalWire::Relay::Event->parse_event(
        'calling.call.state',
        {
            call_id    => 'c8',
            call_state => 'ringing',
        }
    );
    $call->dispatch_event($event);
    is( $a, 1, 'first listener called' );
    is( $b, 1, 'second listener called' );
};

# ============================================================
# Action identity survives its Call being collected
#
# `Action.call` is weak (Call._actions holds Actions strongly, so a strong
# back-reference would leak the cycle; the reference keeps a strong one and lets
# Python's cycle collector deal with it). Identity + transport are therefore
# snapshotted in BUILD. Derived LAZILY through the weak handle instead, they all
# resolved to undef/'' as soon as the Call was collected, and every control-op
# silently emitted nothing on its `return unless $client` guard -- the defect
# that made play/pause/stop/volume transmit no frame at all.
# ============================================================
subtest 'action keeps call_id / node_id / client after the Call is collected' => sub {
    my @sent;
    my $client = bless {}, 'CollectedCallProbeClient';
    {
        no strict 'refs';    ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{'CollectedCallProbeClient::execute'} = sub {
            my ( $self, $method, $params ) = @_;
            push @sent, [ $method, $params ];
            return {};
        };
    }

    # The Call is confined to this block and registered nowhere else, so it is
    # genuinely refcount-collected on scope exit.
    my $action = do {
        my $call = SignalWire::Relay::Call->new(
            call_id => 'c-collected',
            node_id => 'n-collected',
            state   => 'answered',
            _client => $client,
        );
        $call->play( play => [ { type => 'silence', params => { duration => 1 } } ] );
    };

    ok( !defined $action->call, 'the weak Call back-reference really was collected' );
    is( $action->call_id, 'c-collected', 'call_id snapshotted before collection' );
    is( $action->node_id, 'n-collected', 'node_id snapshotted before collection' );
    ok( defined $action->_client, 'client snapshotted before collection' );

    @sent = ();
    $action->stop;
    is( scalar @sent,            1,                   'stop emitted exactly one frame' );
    is( $sent[0][0],             'calling.play.stop', 'stop used the right RELAY verb' );
    is( $sent[0][1]{call_id},    'c-collected',       'frame carried the snapshotted call_id' );
    is( $sent[0][1]{node_id},    'n-collected',       'frame carried the snapshotted node_id' );
    is( $sent[0][1]{control_id}, $action->control_id, 'frame carried the control_id' );
};

done_testing;
