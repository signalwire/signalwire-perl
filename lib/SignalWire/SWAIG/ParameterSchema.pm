package SignalWire::SWAIG::ParameterSchema;
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# A fluent, typed builder for the JSON-Schema `parameters` blob that
# define_tool() expects for a SWAIG function. Today that blob is written by
# hand as nested hashrefs:
#
#     parameters => {
#         type       => 'object',
#         properties => {
#             service => { type => 'string', description => 'The service' },
#             fmt     => { type => 'string', description => 'format',
#                          enum => ['wav','mp3','mp4'] },
#         },
#         required => ['service'],
#     }
#
# That works, but it is easy to typo a key, forget `type => 'object'`, mis-spell
# `properties`, or drift the `enum` list out of sync with the closed set it is
# supposed to mirror. This builder constructs the SAME hashref through named,
# typed property kinds:
#
#     my $params = SignalWire::SWAIG::ParameterSchema->new
#         ->string('service', 'The service')
#         ->string('date',    'YYYY-MM-DD')
#         ->enum('fmt', SignalWire::SWAIG::RecordCall->formats, 'format')
#         ->required('service', 'date')
#         ->to_hash;
#
#     $agent->define_tool(name => 'book', parameters => $params, handler => ...);
#
# IT IS A CONVENIENCE OVER THE SAME WIRE OUTPUT, NOT A NEW FORMAT.
# ->to_hash returns the identical `{ type => 'object', properties => {...},
# required => [...] }` hashref the hand-written form produces, byte for byte
# (`required` is omitted when empty, exactly as hand-written schemas omit it).
# The untyped hashref path into define_tool() is untouched — both forms are
# accepted, so Python parity and every existing caller are unchanged. This is
# additive (PORT_ADDITIONS.md), the Perl Tier-2 flagship of the cross-port
# "typed SWAIG tool-parameter builder" idiom.
#
# CLOSED-SET INTEGRATION. ->enum takes an arrayref of accepted values, so the
# Tier-1 constant modules drop straight in as the single source of truth:
#
#     ->enum('format',    SignalWire::SWAIG::RecordCall->formats,    '...')
#     ->enum('direction', SignalWire::SWAIG::RecordCall->directions, '...')
#     ->enum('direction', SignalWire::SWAIG::Tap->directions,        '...')
#     ->enum('codec',     SignalWire::SWAIG::Tap->codecs,            '...')
#
# Perl has no real enums; like RecordCall/Tap this buys discoverability and a
# single source of truth, not compile-time typo checking. The values land in
# the schema verbatim as `enum => [...]`.
#
# Mirrors the Moo + `use feature 'signatures'` + POD style of the earlier
# Tier-2 idiom pass (SignalWire::POM::Section, the Relay::* isa/signature work).

use strict;
use warnings;
use Moo;
# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
use Carp qw(croak);
use Scalar::Util qw(blessed reftype);
use Tie::IxHash;

# Property definitions, stored in a tied IxHash so iteration is in builder-
# call order. That only governs the ORDER properties are walked when building
# output; ->to_hash copies them into PLAIN hashes (see _clone), so the
# returned schema is is_deeply- and JSON-identical to a hand-written literal
# and a deterministic `canonical` JSON encode is up to the encoder, not a
# tied hash (which would defeat canonical key sorting).
has _properties => (
    is      => 'ro',
    default => sub {
        tie my %h, 'Tie::IxHash';
        return \%h;
    },
);

# Names pushed by ->required, in call order, de-duplicated on emit.
has _required => (
    is      => 'ro',
    default => sub { [] },
);

# ---------- the kinds the wire schema understands ----------
#
# Each kind method has the shape:
#
#     ->KIND($name, $description, %opts)
#
# $description is the common second positional (it is the #1 thing every
# property carries and the LLM-facing prompt text). It may instead be passed
# as `description => ...` inside %opts; an explicit %opts value wins. %opts
# carries the optional JSON-Schema facets: required => 1 (shorthand for also
# calling ->required($name)), default => ..., enum => [...], format => ....
# Every method returns $self so calls chain.

# A free-form string property: { type => 'string', ... }.
sub string ($self, $name, $description = undef, %opts) {
    return $self->_add($name, 'string', $description, {}, %opts);
}

# A JSON number (float) property: { type => 'number', ... }.
sub number ($self, $name, $description = undef, %opts) {
    return $self->_add($name, 'number', $description, {}, %opts);
}

# An integer property: { type => 'integer', ... }.
sub integer ($self, $name, $description = undef, %opts) {
    return $self->_add($name, 'integer', $description, {}, %opts);
}

# A boolean property: { type => 'boolean', ... }.
sub boolean ($self, $name, $description = undef, %opts) {
    return $self->_add($name, 'boolean', $description, {}, %opts);
}

# A closed-set string property: { type => 'string', enum => [...], ... }.
#
# $values is the arrayref of accepted values — pass a Tier-1 constant set
# directly, e.g. SignalWire::SWAIG::RecordCall->formats. The values land in
# the schema verbatim as `enum`. Defaults the JSON type to 'string' (the
# usual case); override with type => 'integer' etc. via %opts for a
# numeric-enum.
sub enum ($self, $name, $values, $description = undef, %opts) {
    croak("enum('$name', ...) requires an arrayref of accepted values")
        unless ref $values eq 'ARRAY';
    croak("enum('$name', ...) requires a non-empty value set")
        unless @$values;
    my $type = delete $opts{type} // 'string';
    return $self->_add($name, $type, $description,
        { enum => [@$values] }, %opts);
}

# An array property: { type => 'array', items => {...}, ... }.
#
# The element shape is given by `of => ...` in %opts and may be:
#   * a kind name string — 'string' / 'number' / 'integer' / 'boolean' /
#     'object' / 'array' — projected to { type => <kind> };
#   * a nested SignalWire::SWAIG::ParameterSchema — projected via its
#     ->to_hash (an object items schema);
#   * a raw hashref items schema, used verbatim.
# `of` is optional: omit it for an untyped array (no `items`), which is how
# the hand-written `{ type => 'array' }` form is most often written.
sub array ($self, $name, $description = undef, %opts) {
    my $of    = delete $opts{of};
    my %facets;
    tie %facets, 'Tie::IxHash';
    if (defined $of) {
        $facets{items} = $self->_items_schema($name, $of);
    }
    return $self->_add($name, 'array', $description, \%facets, %opts);
}

# A nested object property: { type => 'object', properties => {...},
# required => [...], ... }.
#
# `properties => ...` in %opts gives the nested shape and may be:
#   * a nested SignalWire::SWAIG::ParameterSchema — its ->to_hash is spliced
#     in (so the nested `properties`/`required` come along);
#   * a coderef — called with a fresh child ParameterSchema; whatever it
#     returns is ignored and the child's ->to_hash is spliced in (a block
#     style: ->object('addr', properties => sub ($p) { $p->string(...) }));
#   * a raw hashref already shaped like { type=>'object', properties=>... }
#     or a bare properties map — spliced in as given.
# `properties` is optional: omit it for an open object ({ type => 'object' }).
#
# The nested object's own `properties` / `required` are STRUCTURAL facets of
# this property's body — they are emitted verbatim and must not be confused
# with the property-level `required => 1` shorthand (which marks THIS object
# property required on the PARENT). _add keeps the two apart.
sub object ($self, $name, $description = undef, %opts) {
    my $props = delete $opts{properties};
    my %facets;
    tie %facets, 'Tie::IxHash';
    if (defined $props) {
        my %body = $self->_object_body($name, $props);
        $facets{$_} = $body{$_} for keys %body;
    }
    return $self->_add($name, 'object', $description, \%facets, %opts);
}

# Mark one or more already-declared properties as required. Accumulates across
# calls and de-duplicates on emit, preserving first-seen order. Returns $self.
sub required ($self, @names) {
    for my $n (@names) {
        croak("required(...) takes property name strings")
            if ref $n;
        push @{ $self->_required }, $n;
    }
    return $self;
}

# ---------- emit ----------

# Render to the JSON-Schema `parameters` hashref define_tool() expects:
#
#     { type => 'object', properties => { ... }, required => [ ... ] }
#
# `required` is omitted entirely when no property was marked required, exactly
# as hand-written schemas omit it. The returned structure is built from PLAIN
# (untied) hashrefs — identical in kind to a hand-written literal — so it
# compares equal under is_deeply and serialises identically under any JSON
# encoder (including `canonical`, which a tied hash would defeat). It shares
# no references with the builder's internal state.
sub to_hash ($self) {
    my %properties;
    my $props = $self->_properties;
    for my $name (keys %$props) {
        $properties{$name} = $self->_clone($props->{$name});
    }

    my %schema = (
        type       => 'object',
        properties => \%properties,
    );

    my @req = $self->_unique_required;
    $schema{required} = \@req if @req;

    return \%schema;
}

# Convenience alias matching the rest of the SDK's serialiser naming
# (FunctionResult->to_hash, POM::Section->to_hash, ...). Identical output.
sub to_dict ($self) { return $self->to_hash }

# ---------- internals ----------

# Build and store one property hashref under $name.
#
# $facets is a hashref of STRUCTURAL body keys assembled by the kind method
# (enum / items / properties / a nested object's own `required` array). These
# are literal property-body keys and are NEVER touched by the required-
# shorthand logic. %opts is the caller-facing trailing options, where
# `required => 1` is the shorthand to mark THIS property required on the
# parent (stripped from the body), `description` is the alt description
# channel, and everything else (default / format / minimum / ...) is a scalar
# JSON-Schema facet emitted verbatim.
sub _add ($self, $name, $type, $description, $facets, %opts) {
    croak("property name is required") unless defined $name && length $name;
    croak("property '$name' is already defined")
        if exists $self->_properties->{$name};

    # description: positional wins unless undef, then fall back to %opts.
    my $desc = $description;
    $desc = delete $opts{description} if !defined $desc;

    # `required => 1` shorthand: also register it on the required list. Strip
    # it from %opts so it never leaks into the property body (JSON-Schema puts
    # `required` on the enclosing object, not on the property). This applies
    # ONLY to %opts — a nested object's structural `required` lives in $facets
    # and is emitted as-is.
    my $req_flag = delete $opts{required};

    my %prop;
    tie %prop, 'Tie::IxHash';
    $prop{type} = $type;
    $prop{description} = $desc if defined $desc;

    # Structural facets first (enum / items / properties / nested required),
    # in the order the kind method assembled them.
    for my $k (keys %$facets) {
        $prop{$k} = $facets->{$k};
    }

    # Then trailing scalar facets (default / format / minimum / ...) in
    # caller-given order. `default` may legitimately be false-y (0, '', []),
    # so they are copied unconditionally rather than truth-gated.
    for my $k (keys %opts) {
        $prop{$k} = $opts{$k};
    }

    $self->_properties->{$name} = \%prop;
    $self->required($name) if $req_flag;
    return $self;
}

# Resolve an array `of => ...` element spec to an items schema hashref.
sub _items_schema ($self, $name, $of) {
    if (blessed($of) && $of->isa(__PACKAGE__)) {
        return $of->to_hash;
    }
    if (ref $of eq 'HASH') {
        return $self->_clone($of);
    }
    if (!ref $of) {
        my %items;
        tie %items, 'Tie::IxHash';
        $items{type} = $of;
        return \%items;
    }
    croak("array('$name', of => ...): 'of' must be a kind name, a "
        . "ParameterSchema, or a hashref items schema");
}

# Resolve an object `properties => ...` spec to the (properties => ...,
# required => ...) pair to splice into the property body.
sub _object_body ($self, $name, $props) {
    if (blessed($props) && $props->isa(__PACKAGE__)) {
        return $self->_object_body_from_hash($props->to_hash);
    }
    if (ref $props eq 'CODE') {
        my $child = __PACKAGE__->new;
        $props->($child);
        return $self->_object_body_from_hash($child->to_hash);
    }
    if (ref $props eq 'HASH') {
        # Either a full { type=>object, properties=>..., required=>... } or a
        # bare properties map. Detect the former by its `properties` key.
        if (exists $props->{properties}) {
            return $self->_object_body_from_hash($props);
        }
        return (properties => $self->_clone($props));
    }
    croak("object('$name', properties => ...): 'properties' must be a "
        . "ParameterSchema, a coderef, or a hashref");
}

# Pull (properties => ..., required => ...) out of an already-built object
# schema hashref, dropping its redundant top-level `type => 'object'` (the
# caller's _add re-sets `type` for the nesting property).
sub _object_body_from_hash ($self, $hash) {
    my %out;
    $out{properties} = $self->_clone($hash->{properties})
        if exists $hash->{properties};
    $out{required} = [@{ $hash->{required} }]
        if exists $hash->{required};
    return %out;
}

# De-duplicated required list, first-seen order preserved.
sub _unique_required ($self) {
    my %seen;
    return grep { !$seen{$_}++ } @{ $self->_required };
}

# Deep-copy a value into PLAIN (untied) structures so the emitted schema
# shares no references with the builder's internal state and round-trips
# through is_deeply / JSON (incl. `canonical`) identically to a hand-written
# literal. Iterating the source — a tied IxHash for the builder's own
# property bodies — yields keys in insertion order, but the COPY is a plain
# hash (a tied copy would defeat JSON's canonical key sorting and surprise any
# serialiser that special-cases tied hashes).
sub _clone ($self, $value) {
    my $r = ref $value;
    if ($r eq 'HASH' || (blessed($value) && reftype($value) && reftype($value) eq 'HASH')) {
        my %copy;
        for my $k (keys %$value) {
            $copy{$k} = $self->_clone($value->{$k});
        }
        return \%copy;
    }
    if ($r eq 'ARRAY' || (blessed($value) && reftype($value) && reftype($value) eq 'ARRAY')) {
        return [ map { $self->_clone($_) } @$value ];
    }
    return $value;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::SWAIG::ParameterSchema - fluent, typed builder for a SWAIG tool's
JSON-Schema C<parameters>

=head1 SYNOPSIS

    use SignalWire::SWAIG::ParameterSchema;
    use SignalWire::SWAIG::RecordCall;

    my $params = SignalWire::SWAIG::ParameterSchema->new
        ->string('service', 'The service to book')
        ->string('date',    'Appointment date, YYYY-MM-DD')
        ->enum('format', SignalWire::SWAIG::RecordCall->formats,
               'Recording container format')
        ->integer('seats', 'How many seats', default => 1)
        ->required('service', 'date')
        ->to_hash;

    # $params is the SAME hashref you would have hand-written:
    #   {
    #     type       => 'object',
    #     properties => {
    #         service => { type => 'string',  description => 'The service to book' },
    #         date    => { type => 'string',  description => 'Appointment date, YYYY-MM-DD' },
    #         format  => { type => 'string',  description => 'Recording container format',
    #                      enum => ['wav','mp3','mp4'] },
    #         seats   => { type => 'integer', description => 'How many seats', default => 1 },
    #     },
    #     required => ['service','date'],
    #   }

    $agent->define_tool(
        name        => 'book_appointment',
        description => 'Book an appointment for a service on a date.',
        parameters  => $params,          # typed-built, same wire shape
        handler     => sub { ... },
    );

=head1 DESCRIPTION

A SWAIG tool's argument schema is the JSON-Schema C<parameters> object that
L<SignalWire::Agent::AgentBase>'s C<define_tool> renders into the SWAIG
function block. It is normally written by hand as nested hashrefs. This class
builds the B<exact same hashref> through a fluent, named, typed API:
C<< ->to_hash >> returns the identical
C<< { type => 'object', properties => {...}, required => [...] } >> structure a
hand-written literal produces, byte for byte (C<required> is omitted when no
property was marked required, just as hand-written schemas omit it).

It is a B<convenience over the same wire output, not a new format>. The
untyped-hashref path into C<define_tool> is unchanged and still accepted, so
Python parity and every existing caller keep working; the builder is purely
additive (see F<PORT_ADDITIONS.md>). This is the Perl realisation of the
cross-port Tier-2 flagship idiom: a typed SWAIG tool-parameter builder.

=head2 Property kinds

Each kind method has the form C<< ->KIND($name, $description, %opts) >> and
returns C<$self> so calls chain. The C<$description> second positional is the
LLM-facing prompt text (it may also be given as C<< description => ... >> in
C<%opts>). C<%opts> carries the optional facets: C<< required => 1 >>
(shorthand for also calling C<< ->required($name) >>), C<< default => ... >>,
C<< enum => [...] >>, C<< format => ... >>, and any other JSON-Schema keyword,
emitted verbatim in caller-given order.

=over 4

=item * C<< ->string($name, $desc, %opts) >> — C<< { type => 'string' } >>.

=item * C<< ->number($name, $desc, %opts) >> — C<< { type => 'number' } >>.

=item * C<< ->integer($name, $desc, %opts) >> — C<< { type => 'integer' } >>.

=item * C<< ->boolean($name, $desc, %opts) >> — C<< { type => 'boolean' } >>.

=item * C<< ->enum($name, $values, $desc, %opts) >> — a closed-set string,
C<< { type => 'string', enum => [ @$values ] } >>. C<$values> is an arrayref
of accepted values; pass a Tier-1 constant set directly
(C<< SignalWire::SWAIG::RecordCall->formats >>,
C<< SignalWire::SWAIG::Tap->codecs >>, ...) so the schema's C<enum> is
single-sourced from the same closed set the verb validates against. Pass
C<< type => 'integer' >> in C<%opts> for a numeric enum.

=item * C<< ->array($name, $desc, %opts) >> — C<< { type => 'array' } >>, with
an optional C<< of => ... >> element spec rendered as C<items>. C<of> may be a
kind-name string (C<'string'>, C<'object'>, ...), a nested
C<ParameterSchema>, or a raw hashref items schema. Omit C<of> for an untyped
array.

=item * C<< ->object($name, $desc, %opts) >> — C<< { type => 'object' } >>,
with an optional C<< properties => ... >> nested spec. C<properties> may be a
nested C<ParameterSchema>, a coderef called with a fresh child schema, or a
raw hashref. The nested C<properties>/C<required> are spliced in. Omit
C<properties> for an open object.

=back

=head2 Marking required fields

=over 4

=item * C<< ->required(@names) >> — mark already-declared properties required.
Accumulates across calls and de-duplicates on emit, preserving first-seen
order. Equivalent to passing C<< required => 1 >> on each kind call.

=back

=head1 METHODS

=head2 new

    my $schema = SignalWire::SWAIG::ParameterSchema->new;

Construct an empty builder.

=head2 string / number / integer / boolean / enum / array / object

Add a property of the named kind. See L</Property kinds>. Each returns
C<$self>. Dies on a duplicate property name.

=head2 required

    $schema->required('a', 'b');

Mark properties required. See L</Marking required fields>. Returns C<$self>.

=head2 to_hash

    my $params = $schema->to_hash;

Render the JSON-Schema C<parameters> hashref. C<required> is omitted when
empty. The result is is_deeply- and JSON-identical to the equivalent
hand-written literal and shares no references with the builder's internal
state.

=head2 to_dict

Alias for L</to_hash>, matching the SDK's serialiser naming. Identical output.

=head1 SEE ALSO

L<SignalWire::Agent::AgentBase> (C<define_tool>),
L<SignalWire::SWML::Service> (C<define_tool>),
L<SignalWire::SWAIG::RecordCall>, L<SignalWire::SWAIG::Tap>
(Tier-1 closed-set constant sets that drop into C<< ->enum >>),
L<SignalWire::POM::Section> (sibling Tier-2 typed-builder idiom).

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
