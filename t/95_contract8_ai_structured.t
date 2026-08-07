#!/usr/bin/env perl
# Behavioral Contract 8 — AI/LLM structured add_pattern_hint / add_language.
#
# Python (ai_config mixin): add_pattern_hint attaches a STRUCTURED hint
# ({pattern, replace, hint, ignore_case}), not a bare string; add_language
# carries engine + model + fillers (list) into the rendered SWML
# ai.languages entry. A degraded impl drops the structure / the
# engine/model/fillers.
#
# Required test: set a pattern hint WITH replace + a language WITH
# engine+model+fillers; render the SWML; assert every field survives into
# the document. Perl is already structured (lock-in), plus this locks in the
# add_pattern_hint structured fix.
use strict;
use warnings;
use Test::More;

use_ok('SignalWire::Agent::AgentBase');

my $a = SignalWire::Agent::AgentBase->new( name => 'c8' );

# Structured pattern hint (Python: {hint, pattern, replace, ignore_case}).
$a->add_pattern_hint(
    {
        hint        => 'AI',
        pattern     => 'A\\.I\\.',
        replace     => 'AI',
        ignore_case => 1,
    }
);

# Language carrying engine + model + fillers (speech + function).
$a->add_language(
    name             => 'English',
    code             => 'en-US',
    voice            => 'josh',
    engine           => 'elevenlabs',
    model            => 'eleven_turbo_v2_5',
    speech_fillers   => [ 'um',         'let me see' ],
    function_fillers => [ 'one moment', 'checking' ],
);

# Guard parity (Python "if hint and pattern and replace"): an incomplete
# pattern hint is DROPPED, not appended as a half-built / bare entry. A
# degraded impl that just pushes whatever it's given would keep this.
$a->add_pattern_hint( { hint => 'oops', pattern => 'p' } );    # no replace => dropped

# ignore_case defaults to a JSON boolean false when omitted (a degraded
# impl that pushes the raw hashref through would have NO ignore_case key).
my $b = SignalWire::Agent::AgentBase->new( name => 'c8b' );
$b->add_pattern_hint( { hint => 'H', pattern => 'P', replace => 'R' } );
my ($bh) = grep { ref($_) eq 'HASH' } @{ $b->pattern_hints };
ok( exists $bh->{ignore_case}, 'ignore_case defaulted onto a hint that omitted it' );

my $swml = $a->render_swml;
my @ai   = grep { exists $_->{ai} } @{ $swml->{sections}{main} };
ok( @ai, 'ai verb rendered' );
my $ai = $ai[0]{ai};

# ---- Pattern hint survives as a STRUCTURED dict, not a bare string ----
my @struct = grep { ref($_) eq 'HASH' } @{ $ai->{hints} };
is( scalar @struct, 1, 'exactly one structured hint (incomplete hint was dropped by the guard)' );
my $ph = $struct[0];
ok( $ph, 'pattern hint rendered as a structured dict (not bare string)' );
is( $ph->{hint},    'AI',       'hint field survives' );
is( $ph->{pattern}, 'A\\.I\\.', 'pattern field survives' );
is( $ph->{replace}, 'AI',       'replace field survives' );
ok( exists $ph->{ignore_case}, 'ignore_case field present' );

# A bare-string / degraded impl would have NO hashref hint at all.
my @string_hints = grep { !ref($_) } @{ $ai->{hints} };
is_deeply( \@string_hints, [], 'no bare-string pattern hint leaked (structured, not degraded)' );

# ---- Language carries engine + model + fillers into ai.languages ----
my $lang = $ai->{languages}[0];
ok( $lang, 'language rendered into ai.languages' );
is( $lang->{code},   'en-US',             'language code survives' );
is( $lang->{engine}, 'elevenlabs',        'engine survives into SWML' );
is( $lang->{model},  'eleven_turbo_v2_5', 'model survives into SWML' );
is_deeply( $lang->{speech_fillers}, [ 'um', 'let me see' ], 'speech_fillers list survives' );
is_deeply(
    $lang->{function_fillers},
    [ 'one moment', 'checking' ],
    'function_fillers list survives'
);

done_testing;
