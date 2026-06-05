#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON ();

# SignalWire::SWAIG::ParameterSchema — the Tier-2 flagship: a fluent, typed
# builder for a SWAIG tool's JSON-Schema `parameters` blob. The core
# guarantee (the cross-port Tier-2 contract): the builder produces the EXACT
# SAME `parameters` hashref — a `properties` map plus a top-level `required`
# arrayref — as the hand-written nested-hashref form. It is a typed
# convenience over the SAME wire output, NOT a new format.
#
# This test proves that two ways:
#   (a) byte-identical (is_deeply + canonical-JSON) builder output vs the
#       equivalent hand-written params hashref, across EVERY property kind
#       (string/number/integer/boolean/enum/array/object), including an enum
#       property single-sourced from a Tier-1 closed-set constant module; and
#   (b) a REAL define_tool() using builder-built params, then render the SWML
#       and invoke the function — asserting the parameters appear, unchanged,
#       in the generated SWAIG functions JSON, and the handler runs.
#
# No mocks: real ParameterSchema objects, a real AgentBase, real render +
# dispatch. Mirrors the t/65 (RecordCall) / t/67 (Tap) byte-identical style.

use_ok('SignalWire::SWAIG::ParameterSchema');
use_ok('SignalWire::SWAIG::RecordCall');
use_ok('SignalWire::SWAIG::Tap');
use_ok('SignalWire::Agent::AgentBase');

# Convenience constructor.
sub schema { SignalWire::SWAIG::ParameterSchema->new }

# Canonical (sorted-key) JSON of a structure — a second, stricter identity
# check on top of is_deeply: catches a stray/extra key that is_deeply on a
# tied vs plain hash could in principle mask, and proves the exact bytes that
# would land on the wire.
my $CANON = JSON->new->canonical(1)->utf8;
sub canon { $CANON->encode($_[0]) }

# ------------------------------------------------------------------
# 1. Empty schema is the minimal object schema; `required` is OMITTED when
#    nothing is required — exactly as hand-written schemas omit it (e.g. the
#    Datetime skill's `{ type => 'object', properties => {...} }`).
# ------------------------------------------------------------------
subtest 'empty / no-required shape matches hand-written' => sub {
    is_deeply(schema()->to_hash, { type => 'object', properties => {} },
        'empty builder => { type=>object, properties=>{} } with no required key');

    my $one = schema()->string('timezone', 'Timezone (e.g. UTC, US/Eastern)')->to_hash;
    is_deeply($one, {
        type       => 'object',
        properties => { timezone => { type => 'string',
                                      description => 'Timezone (e.g. UTC, US/Eastern)' } },
    }, 'single optional string omits the required arrayref');
    ok(!exists $one->{required}, 'required key absent when no field marked required');
};

# ------------------------------------------------------------------
# 2. THE CORE PROOF: builder output is byte-identical to the equivalent
#    hand-written params hashref across ALL property kinds, including an enum.
# ------------------------------------------------------------------
subtest 'builder == hand-written across all property kinds (incl. enum)' => sub {
    # The hand-written form a developer would write today, by hand.
    my $hand = {
        type       => 'object',
        properties => {
            service => { type => 'string',  description => 'The service to book' },
            date    => { type => 'string',  description => 'Appointment date, YYYY-MM-DD' },
            fmt     => { type => 'string',  description => 'Recording container format',
                         enum => ['wav', 'mp3', 'mp4'] },
            seats   => { type => 'integer', description => 'How many seats', default => 1 },
            price   => { type => 'number',  description => 'Quoted price' },
            confirm => { type => 'boolean', description => 'Whether to confirm' },
            tags    => { type => 'array',   description => 'Arbitrary tags',
                         items => { type => 'string' } },
            address => { type => 'object',  description => 'Service address',
                         properties => {
                             city => { type => 'string', description => 'City name' },
                             zip  => { type => 'string', description => 'Postal code' },
                         },
                         required => ['city'] },
        },
        required => ['service', 'date'],
    };

    # The SAME thing, built fluently. The enum is single-sourced from the
    # Tier-1 RecordCall constant set — the schema's `enum` is exactly the
    # closed set record_call validates against.
    my $built = schema()
        ->string('service', 'The service to book')
        ->string('date',    'Appointment date, YYYY-MM-DD')
        ->enum('fmt', SignalWire::SWAIG::RecordCall->formats, 'Recording container format')
        ->integer('seats', 'How many seats', default => 1)
        ->number('price', 'Quoted price')
        ->boolean('confirm', 'Whether to confirm')
        ->array('tags', 'Arbitrary tags', of => 'string')
        ->object('address', 'Service address', properties => sub {
            my ($p) = @_;
            $p->string('city', 'City name')
              ->string('zip',  'Postal code')
              ->required('city');
        })
        ->required('service', 'date')
        ->to_hash;

    is_deeply($built, $hand,
        'builder-built params are deeply identical to the hand-written hashref');
    is(canon($built), canon($hand),
        'and canonical (sorted-key) JSON is byte-for-byte identical');

    # Pin the enum specifically: it IS the RecordCall closed set, verbatim.
    is_deeply($built->{properties}{fmt}{enum},
        SignalWire::SWAIG::RecordCall->formats,
        'enum property carries the RecordCall closed set verbatim');
};

# ------------------------------------------------------------------
# 2b. The enum kind integrates ALL the Tier-1 closed-set constant modules,
#     producing schema `enum:[...]` from the same single source of truth the
#     verbs validate against (RecordCall formats/directions, Tap
#     directions/codecs). The vocabularies stay distinct.
# ------------------------------------------------------------------
subtest 'enum integrates the Tier-1 constant sets (distinct vocabularies)' => sub {
    my $h = schema()
        ->enum('rec_format',    SignalWire::SWAIG::RecordCall->formats,    'record format')
        ->enum('rec_direction', SignalWire::SWAIG::RecordCall->directions, 'record direction')
        ->enum('tap_direction', SignalWire::SWAIG::Tap->directions,        'tap direction')
        ->enum('tap_codec',     SignalWire::SWAIG::Tap->codecs,            'tap codec')
        ->to_hash;

    is_deeply($h->{properties}{rec_format}{enum},    ['wav', 'mp3', 'mp4'],
        'RecordCall->formats => enum [wav,mp3,mp4]');
    is_deeply($h->{properties}{rec_direction}{enum}, ['speak', 'listen', 'both'],
        'RecordCall->directions => enum [speak,listen,both]');
    is_deeply($h->{properties}{tap_direction}{enum}, ['speak', 'hear', 'both'],
        'Tap->directions => enum [speak,hear,both] (hear, NOT listen)');
    is_deeply($h->{properties}{tap_codec}{enum},     ['PCMU', 'PCMA'],
        'Tap->codecs => enum [PCMU,PCMA]');

    # Every enum property is, by construction, a string with the closed set.
    for my $name (qw(rec_format rec_direction tap_direction tap_codec)) {
        is($h->{properties}{$name}{type}, 'string', "$name enum is a string type");
    }

    # The record-direction and tap-direction vocabularies are NOT the same
    # set — the builder copies each verbatim and never unifies them.
    isnt(canon($h->{properties}{rec_direction}{enum}),
         canon($h->{properties}{tap_direction}{enum}),
        'record-direction and tap-direction enums are distinct sets');
};

# ------------------------------------------------------------------
# 2c. The `required => 1` per-property shorthand is exactly equivalent to a
#     trailing ->required($name) call, and a nested object's own structural
#     `required` array is NEVER confused with the shorthand (it stays inside
#     the nested object body; it does NOT mark the object property required
#     on the parent).
# ------------------------------------------------------------------
subtest 'required shorthand vs nested structural required' => sub {
    my $by_flag = schema()->string('a', 'A', required => 1)
                          ->string('b', 'B')->to_hash;
    my $by_call = schema()->string('a', 'A')->string('b', 'B')
                          ->required('a')->to_hash;
    is_deeply($by_flag, $by_call, 'required=>1 shorthand == ->required(...)');
    is_deeply($by_flag->{required}, ['a'], 'only the marked field is required');

    # A nested object whose inner field is required, but the object property
    # itself is NOT required on the parent: the inner `required` lives in the
    # nested body, the parent has no `required` key.
    my $nested = schema()->object('addr', 'addr', properties => sub {
        my ($p) = @_;
        $p->string('zip', 'zip')->required('zip');
    })->to_hash;
    ok(!exists $nested->{required},
        'parent has no required key (the object property is optional)');
    is_deeply($nested->{properties}{addr}{required}, ['zip'],
        'nested object keeps its own structural required => [zip]');
};

# ------------------------------------------------------------------
# 3. REAL define_tool() + render + invoke: builder-built params reach the
#    generated SWAIG functions JSON unchanged, and the handler runs.
# ------------------------------------------------------------------
subtest 'real define_tool with builder params: params reach SWAIG JSON + handler runs' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'param_schema_agent');

    # Build the params with the typed builder, including an enum from the
    # Tier-1 set, then register a REAL tool with them.
    my $params = schema()
        ->string('service', 'The service to book')
        ->enum('format', SignalWire::SWAIG::RecordCall->formats, 'Recording container format')
        ->integer('seats', 'How many seats', default => 1)
        ->required('service')
        ->to_hash;

    my $handler_args;
    $agent->define_tool(
        name        => 'book_appointment',
        description => 'Book an appointment for a service.',
        parameters  => $params,
        handler     => sub {
            my ($args, $raw) = @_;
            $handler_args = $args;
            return { response => "booked $args->{service} ($args->{format})" };
        },
    );

    # --- Render the whole agent to SWML, then JSON round-trip it so the
    #     assertion is literally against the generated SWAIG JSON bytes. ---
    my $doc  = $agent->render_swml;
    my $json = JSON->new->canonical(1)->encode($doc);
    my $back = JSON->new->decode($json);

    # Navigate: sections.main -> the `ai` verb -> SWAIG.functions[].
    my ($ai_verb) = grep { exists $_->{ai} } @{ $back->{sections}{main} };
    ok($ai_verb, 'rendered SWML has an ai verb');
    my $functions = $ai_verb->{ai}{SWAIG}{functions};
    ok($functions && @$functions, 'SWAIG block has a functions list');

    my ($fn) = grep { $_->{function} eq 'book_appointment' } @$functions;
    ok($fn, 'our tool is present in the SWAIG functions JSON');

    # The parameters in the generated JSON are byte-identical to what the
    # builder produced (modulo handler stripping, which is not in parameters).
    is_deeply($fn->{parameters}, $params,
        'generated SWAIG function parameters are exactly the builder output');

    # Spot the individual pieces in the rendered JSON, to be explicit.
    is($fn->{parameters}{type}, 'object', 'rendered parameters.type is object');
    is($fn->{parameters}{properties}{service}{type}, 'string',
        'service property rendered as string');
    is($fn->{parameters}{properties}{service}{description}, 'The service to book',
        'service description carried into the SWAIG JSON');
    is_deeply($fn->{parameters}{properties}{format}{enum}, ['wav', 'mp3', 'mp4'],
        'enum closed set rendered into the SWAIG JSON');
    is($fn->{parameters}{properties}{seats}{default}, 1,
        'integer default rendered into the SWAIG JSON');
    is_deeply($fn->{parameters}{required}, ['service'],
        'required arrayref rendered into the SWAIG JSON');

    # --- Now INVOKE the function through the real dispatch path and confirm
    #     the handler receives the args and returns the expected response. ---
    my $result = $agent->on_function_call('book_appointment',
        { service => 'haircut', format => 'mp3' }, { call_id => 'call-1' });
    is($result->{response}, 'booked haircut (mp3)',
        'invoking the tool runs the handler with the parsed args');
    is_deeply($handler_args, { service => 'haircut', format => 'mp3' },
        'handler received exactly the call arguments');
};

# ------------------------------------------------------------------
# 4. Equivalence at the define_tool boundary: a tool defined with
#    builder-built params and the SAME tool defined with the literal
#    hand-written hashref render to the IDENTICAL SWAIG function. This is the
#    "same wire output, not a new format" promise, end to end.
# ------------------------------------------------------------------
subtest 'builder-defined tool renders identically to hand-defined tool' => sub {
    my $built_params = schema()
        ->string('q', 'The search query')
        ->enum('fmt', SignalWire::SWAIG::RecordCall->formats, 'format')
        ->required('q')
        ->to_hash;

    my $hand_params = {
        type       => 'object',
        properties => {
            q   => { type => 'string', description => 'The search query' },
            fmt => { type => 'string', description => 'format', enum => ['wav', 'mp3', 'mp4'] },
        },
        required => ['q'],
    };

    my $a1 = SignalWire::Agent::AgentBase->new(name => 'built');
    $a1->define_tool(name => 'search', description => 'Search.',
        parameters => $built_params, handler => sub { { response => 'ok' } });

    my $a2 = SignalWire::Agent::AgentBase->new(name => 'hand');
    $a2->define_tool(name => 'search', description => 'Search.',
        parameters => $hand_params, handler => sub { { response => 'ok' } });

    my $extract = sub {
        my ($agent) = @_;
        my $doc = $agent->render_swml;
        my ($ai) = grep { exists $_->{ai} } @{ $doc->{sections}{main} };
        my ($fn) = grep { $_->{function} eq 'search' } @{ $ai->{ai}{SWAIG}{functions} };
        delete $fn->{web_hook_url};   # auth-derived; not part of the params contract
        return $fn;
    };

    is_deeply($extract->($a1), $extract->($a2),
        'builder-defined and hand-defined SWAIG functions are byte-identical');
};

done_testing;
