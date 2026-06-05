#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Exception;
use JSON ();

# t/71_relay_device.t — the Tier-3 typed RELAY Device object.
#
# SignalWire::Relay::Device types the SHAPE of the { type, params } device
# object that the relay calling layer otherwise passes as a raw hashref
# across dial / connect / refer / tap. The core guarantee (the Tier-2/3
# byte-identical contract, mirroring t/69 ParameterSchema): Device->to_hash
# yields the EXACT hashref a developer would hand-write today, so a Device
# is a drop-in for the raw form and the wire shape is unchanged.
#
# Grounded in relay-protocol/calling.connect.params.json /
# calling.dial.params.json: each device is { "type": <string>,
# "params": <object> }, type required. The discriminant `type` stays a
# string (the type set is an open `{ "type": "string" }`, not enumerated).
#
# No mocks: real Device objects + a real Relay::Call verb dispatched
# through a tiny recording client (a real object that records the params a
# verb forwards — NOT a mock of transport), asserting the device a Device
# builds reaches the verb byte-identical to the hand-written hashref.

use_ok('SignalWire::Relay::Device');
use_ok('SignalWire::Relay::Call');

my $CANON = JSON->new->canonical(1)->utf8;
sub canon { $CANON->encode($_[0]) }

# ------------------------------------------------------------------
# 1. Construction + accessors; `type` is a plain string (NOT enum-typed).
# ------------------------------------------------------------------
subtest 'construction and accessors' => sub {
    my $d = SignalWire::Relay::Device->new(
        type   => 'phone',
        params => { to_number => '+15551234567', from_number => '+15557654321' },
    );
    isa_ok($d, 'SignalWire::Relay::Device');
    is($d->type, 'phone', 'type accessor');
    ok(!ref $d->type, 'type is a plain string (shape is typed, discriminant is not)');
    is_deeply($d->params, { to_number => '+15551234567', from_number => '+15557654321' },
        'params accessor');

    # params defaults to an empty hashref.
    my $bare = SignalWire::Relay::Device->new(type => 'sip');
    is_deeply($bare->params, {}, 'params defaults to {}');

    # A non-enumerated / forward-compat type is ACCEPTED (open set).
    my $future = SignalWire::Relay::Device->new(type => 'some_new_device_kind');
    is($future->type, 'some_new_device_kind',
        'an unknown/forward-compat type is accepted (type is an open string)');
};

# ------------------------------------------------------------------
# 2. isa guards fail fast on a bad shape.
# ------------------------------------------------------------------
subtest 'isa: bad shape dies' => sub {
    throws_ok { SignalWire::Relay::Device->new() }
        qr/type/, 'missing type dies (required)';
    throws_ok { SignalWire::Relay::Device->new(type => '') }
        qr/non-empty string/, 'empty type dies';
    throws_ok { SignalWire::Relay::Device->new(type => {}) }
        qr/non-empty string/, 'hashref type dies';
    throws_ok { SignalWire::Relay::Device->new(type => 'phone', params => 'oops') }
        qr/params must be a hashref/, 'string params dies';
    throws_ok { SignalWire::Relay::Device->new(type => 'phone', params => []) }
        qr/params must be a hashref/, 'arrayref params dies';
};

# ------------------------------------------------------------------
# 3. THE CORE PROOF: to_hash is byte-identical to the hand-written hashref,
#    across several realistic device shapes.
# ------------------------------------------------------------------
subtest 'to_hash == hand-written hashref (byte-identical)' => sub {
    my @cases = (
        {
            name => 'phone device',
            dev  => SignalWire::Relay::Device->new(
                type   => 'phone',
                params => {
                    to_number   => '+15551234567',
                    from_number => '+15557654321',
                    timeout     => 30,
                },
            ),
            hand => {
                type   => 'phone',
                params => {
                    to_number   => '+15551234567',
                    from_number => '+15557654321',
                    timeout     => 30,
                },
            },
        },
        {
            name => 'sip device',
            dev  => SignalWire::Relay::Device->new(
                type   => 'sip',
                params => {
                    to   => 'sip:alice@example.com',
                    from => 'sip:bob@example.com',
                },
            ),
            hand => {
                type   => 'sip',
                params => {
                    to   => 'sip:alice@example.com',
                    from => 'sip:bob@example.com',
                },
            },
        },
        {
            name => 'params-less device',
            dev  => SignalWire::Relay::Device->new( type => 'phone' ),
            hand => { type => 'phone', params => {} },
        },
    );

    for my $c (@cases) {
        is_deeply($c->{dev}->to_hash, $c->{hand},
            "$c->{name}: to_hash is_deeply the hand-written hashref");
        is(canon($c->{dev}->to_hash), canon($c->{hand}),
            "$c->{name}: canonical JSON is byte-for-byte identical");
    }
};

# ------------------------------------------------------------------
# 4. Device is an immutable snapshot: it copies params at CONSTRUCTION, so a
#    later edit to the caller's source hashref can't leak in; and each
#    to_hash is its own copy, so mutating one emitted hash doesn't affect the
#    Device or a subsequent emission. A built device can't be corrupted.
# ------------------------------------------------------------------
subtest 'Device is an immutable snapshot of params' => sub {
    my $src = { to_number => '+15551112222' };
    my $d = SignalWire::Relay::Device->new(type => 'phone', params => $src);

    my $emitted = $d->to_hash;
    # Mutate the ORIGINAL source hashref the device was built from.
    $src->{to_number} = '+19998887777';
    $src->{injected}  = 'late';

    # Construction-time snapshot: the Device's own params is unaffected.
    is($d->params->{to_number}, '+15551112222',
        'Device->params is a construction-time snapshot (source mutation does not leak)');
    ok(!exists $d->params->{injected},
        'a key added to the source after construction does not leak into the Device');
    # ...and so the already-emitted to_hash is likewise unaffected.
    is($emitted->{params}{to_number}, '+15551112222',
        'already-emitted to_hash is unaffected by later source mutation');

    # Per-emission copy: mutating one emitted hash doesn't change the next.
    $emitted->{params}{to_number} = 'mutated';
    is($d->to_hash->{params}{to_number}, '+15551112222',
        'a fresh to_hash is unaffected by mutating a prior to_hash');
};

# ------------------------------------------------------------------
# 5. REAL relay verb: a Device drops into a Call->connect devices matrix and
#    reaches the dispatched RPC params byte-identical to the hand-written
#    hashref. The "client" is a real object recording (method, params) — NOT
#    a transport mock (same pattern as t/68).
# ------------------------------------------------------------------
subtest 'Device drives a real Call->connect identically to a raw hashref' => sub {
    {
        package T::RecordingClient;
        use Moo;
        has calls => (is => 'rw', default => sub { [] });
        sub execute {
            my ($self, $method, $params) = @_;
            push @{ $self->calls }, [ $method, $params ];
            return { code => '200' };
        }
    }

    my $device = SignalWire::Relay::Device->new(
        type   => 'phone',
        params => { to_number => '+15551234567', from_number => '+15557654321' },
    );

    # Built via the Device.
    my $c1 = T::RecordingClient->new;
    my $call1 = SignalWire::Relay::Call->new(
        call_id => 'dev-call-1', node_id => 'n1', _client => $c1,
    );
    $call1->connect( devices => [ [ $device->to_hash ] ] );

    # Built by hand — the form a developer writes without the Device class.
    my $c2 = T::RecordingClient->new;
    my $call2 = SignalWire::Relay::Call->new(
        call_id => 'dev-call-1', node_id => 'n1', _client => $c2,
    );
    $call2->connect( devices => [ [ {
        type   => 'phone',
        params => { to_number => '+15551234567', from_number => '+15557654321' },
    } ] ] );

    my ($m1, $p1) = @{ $c1->calls->[0] };
    my ($m2, $p2) = @{ $c2->calls->[0] };

    is($m1, 'calling.connect', 'connect dispatched calling.connect');
    is($m1, $m2, 'same RPC method either way');

    # The device that landed in the dispatched params is byte-identical.
    is_deeply($p1->{devices}, $p2->{devices},
        'Device-built and hand-built devices matrices are deeply identical');
    is(canon($p1->{devices}), canon($p2->{devices}),
        'and canonical JSON of the dispatched devices is byte-for-byte identical');

    # Spot the concrete shape that reached the wire.
    is($p1->{devices}[0][0]{type}, 'phone', 'dispatched device type');
    is($p1->{devices}[0][0]{params}{to_number}, '+15551234567',
        'dispatched device param reached the RPC');
};

done_testing;
