package SignalWire::Relay::Device;
use strict;
use warnings;
use Moo;
# Subroutine signatures (Perl 5.20+; floor 5.026). Must follow `use Moo;`
# (Moo's import re-enables the default warning set, which would otherwise
# un-silence experimental::signatures).
use feature 'signatures';
no warnings 'experimental::signatures';
use Carp ();

# A RELAY "device" object — the { type, params } pair that names one leg of
# a dial / connect / refer / tap target. It recurs as a RAW hashref across
# the relay calling layer (Client->dial(devices => [...]),
# Call->connect/refer, the device field on Call / CallStateEvent /
# CallReceiveEvent). This class types the SHAPE of that hashref so callers
# can build one with a constructor + named accessors instead of hand-
# assembling a nested map, while to_hash yields the byte-identical wire
# hashref the raw form produced.
#
# Grounded in relay-protocol/calling.connect.params.json and
# calling.dial.params.json: each device is
#     { "type": <string>, "params": <object> }
# with `type` required and `params` an arbitrary (per-type) object. We type
# the shape, NOT the discriminant: `type` stays a plain string because the
# device-type set ('phone', 'sip', 'agora', ...) is NOT enumerated in the
# wire schema (it's an open `{ "type": "string" }`), so typing it would
# reject valid/forward-compat values. This matches the open-set rule in the
# idiom journal (§3): type the knowable shape, leave the unbounded
# discriminant a string.
#
# Additive + parity-preserving: the relay verbs still accept a raw hashref
# (a device built here is just a hashref once you call ->to_hash), so
# nothing about the existing API changes. Mirrors the Tier-2 Moo +
# signatures + POD idiom of the rest of the relay layer.
#
#     use SignalWire::Relay::Device;
#     my $d = SignalWire::Relay::Device->new(
#         type   => 'phone',
#         params => { to_number => '+15551234567', from_number => '+15557654321' },
#     );
#     $call->connect( devices => [[ $d->to_hash ]] );   # identical wire shape
#     $d->type;                                          # 'phone'

# isa: type is the required discriminant. A bad construction must die
# immediately rather than yield a device the server can't route. params
# defaults to an empty hashref and must be a hashref when supplied.
my $NonEmptyStr = sub {
    Carp::croak("type must be a non-empty string")
        unless defined $_[0] && !ref $_[0] && length $_[0];
};
my $HashRef = sub {
    Carp::croak("params must be a hashref") unless ref $_[0] eq 'HASH';
};

# Snapshot the caller's params hashref at construction so the Device owns an
# independent copy: a later mutation of the hashref the caller passed in
# can't retroactively change this (immutable) device. A non-hashref is
# passed through untouched so the `isa` constraint below rejects it cleanly.
my $CopyHash = sub {
    my ($v) = @_;
    return ref $v eq 'HASH' ? { %$v } : $v;
};

has 'type'   => ( is => 'ro', required => 1, isa => $NonEmptyStr );
has 'params' => (
    is      => 'ro',
    default => sub { {} },
    coerce  => $CopyHash,
    isa     => $HashRef,
);

# to_hash — the canonical RELAY device wire hashref: { type, params }. This
# is exactly the raw shape the relay verbs already accept, so a Device is a
# drop-in for the hand-written hashref. params is snapshotted at
# construction and copied again here, so each emitted hash is independent:
# mutating one to_hash never affects the Device or a later emission.
sub to_hash ($self) {
    return {
        type   => $self->type,
        params => { %{ $self->params } },
    };
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Relay::Device - a typed RELAY device object ({ type, params })

=head1 SYNOPSIS

    use SignalWire::Relay::Device;

    my $device = SignalWire::Relay::Device->new(
        type   => 'phone',
        params => {
            to_number   => '+15551234567',
            from_number => '+15557654321',
            timeout     => 30,
        },
    );

    $device->type;     # 'phone'
    $device->params;   # { to_number => ..., from_number => ..., timeout => 30 }

    # to_hash yields the exact wire hashref the relay verbs accept:
    my $wire = $device->to_hash;
    # { type => 'phone', params => { to_number => ..., ... } }

    # Drop-in for the hand-written hashref in a devices matrix:
    $call->connect( devices => [[ $device->to_hash ]] );

=head1 DESCRIPTION

A RELAY B<device> object — the C<{ type, params }> pair that names one leg
of a dial / connect / refer / tap target. It recurs as a raw hashref across
the relay calling layer (C<< $client->dial(devices => [...]) >>,
C<< $call->connect >> / C<< $call->refer >>, and the C<device> field on
L<SignalWire::Relay::Call> / the C<CallState> / C<CallReceive> events).

This class types the B<shape> of that hashref so callers can build one with
a constructor and named accessors instead of hand-assembling a nested map.
L</to_hash> yields the byte-identical wire hashref the raw form produced, so
a C<Device> is a drop-in replacement wherever a device hashref is accepted —
the existing relay verbs are unchanged (additive, parity-preserving).

Grounded in C<relay-protocol/calling.connect.params.json> and
C<calling.dial.params.json>, where each device is
C<< { "type": <string>, "params": <object> } >> with C<type> required.

=head2 The shape is typed; the discriminant is not

C<type> is kept a plain B<string>: the device-type set
(C<phone>, C<sip>, ...) is B<not> enumerated in the wire schema (it is an
open C<< { "type": "string" } >>), so turning it into a closed enum would
reject valid and forward-compatible values. Per the idiom rule, this class
types the B<knowable shape> and leaves the B<unbounded discriminant> a
string. C<params> is a per-type arbitrary object, also left untyped.

Construction fails fast (Moo C<isa>): C<type> is required and must be a
non-empty string; C<params> must be a hashref when supplied.

=head1 ATTRIBUTES

=head2 type

The device type discriminant (e.g. C<phone>, C<sip>). Required, read-only,
a non-empty string.

=head2 params

The per-type parameters hashref (e.g. C<to_number> / C<from_number> for a
C<phone> device). Read-only; defaults to an empty hashref.

=head1 METHODS

=head2 to_hash

    my $wire = $device->to_hash;

Return the canonical RELAY device wire hashref C<< { type, params } >> —
exactly the raw shape the relay verbs already accept. C<params> is
snapshotted at construction and copied again here, so each emitted hash is
independent: mutating one C<to_hash> never affects the Device or a later
emission, and a mutation of the caller's original hashref after construction
does not leak in.

=head1 SEE ALSO

L<SignalWire::Relay::Call>, L<SignalWire::Relay::Client>,
L<SignalWire::Relay::Event>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
