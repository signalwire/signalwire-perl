#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON ();

# Tests for SignalWire::SWML::SWMLBuilder — the fluent SWML builder. Verb
# helpers emit exact wire keys, fluent chaining returns self, and AUTOLOAD
# (the Perl analog of Python __getattr__) auto-vivifies schema verbs. Mirrors
# the Ruby tests/swml_builder_test.rb.

use_ok('SignalWire::SWML::Service');
use_ok('SignalWire::SWML::SWMLBuilder');

sub new_builder {
    my $service = SignalWire::SWML::Service->new( name => 'builder-test' );
    return SignalWire::SWML::SWMLBuilder->new( service => $service );
}

sub main_of {
    my ($builder) = @_;
    return $builder->build->{sections}{main};
}

subtest 'answer empty config' => sub {
    my $b = new_builder();
    is( $b->answer, $b, 'answer returns self' );
    is_deeply( main_of($b)->[0], { answer => {} }, 'answer verb' );
};

subtest 'answer with options' => sub {
    my $b = new_builder();
    $b->answer( max_duration => 30, codecs => 'PCMU' );
    is_deeply(
        main_of($b)->[0],
        { answer => { max_duration => 30, codecs => 'PCMU' } },
        'answer with options',
    );
};

subtest 'hangup reason' => sub {
    my $b = new_builder();
    $b->hangup( reason => 'busy' );
    is_deeply( main_of($b)->[0], { hangup => { reason => 'busy' } }, 'hangup reason' );
};

subtest 'ai text prompt wire shape' => sub {
    my $b = new_builder();
    $b->ai( prompt_text => 'you are helpful' );

    # prompt must be an OBJECT {text => ...}, never a bare string.
    is_deeply(
        main_of($b)->[0],
        { ai => { prompt => { text => 'you are helpful' } } },
        'ai text prompt',
    );
};

subtest 'ai pom, post_prompt, swaig and kwargs' => sub {
    my $b   = new_builder();
    my $pom = [ { title => 'Role' } ];
    $b->ai(
        prompt_pom      => $pom,
        post_prompt     => 'summarize',
        post_prompt_url => 'https://ex.com/pp',
        swaig           => { functions => [] },
        temperature     => 0.4,
    );
    my $cfg = main_of($b)->[0]{ai};
    is_deeply( $cfg->{prompt},      { pom  => $pom },        'pom prompt' );
    is_deeply( $cfg->{post_prompt}, { text => 'summarize' }, 'post_prompt wrapped' );
    is( $cfg->{post_prompt_url}, 'https://ex.com/pp', 'post_prompt_url' );
    is_deeply( $cfg->{SWAIG}, { functions => [] }, 'SWAIG passed through' );
    cmp_ok( abs( $cfg->{temperature} - 0.4 ), '<', 1e-9, 'temperature kwarg merged' );
};

subtest 'play url' => sub {
    my $b = new_builder();
    $b->play( url => 'https://ex.com/a.mp3', volume => 5.0 );
    is_deeply(
        main_of($b)->[0],
        { play => { url => 'https://ex.com/a.mp3', volume => 5.0 } },
        'play url',
    );
};

subtest 'play urls list' => sub {
    my $b = new_builder();
    $b->play( urls => [qw(a.mp3 b.mp3)] );
    is_deeply( main_of($b)->[0], { play => { urls => [qw(a.mp3 b.mp3)] } }, 'play urls' );
};

subtest 'play requires url or urls' => sub {
    my $b = new_builder();
    eval { $b->play };
    like( $@, qr/Either url or urls/, 'dies without url/urls' );
};

subtest 'say prefixes url' => sub {
    my $b = new_builder();
    $b->say( 'hello there', voice => 'en-US-Neural', language => 'en-US' );
    my $cfg = main_of($b)->[0]{play};
    is( $cfg->{url},          'say:hello there', 'say: prefix' );
    is( $cfg->{say_voice},    'en-US-Neural',    'say_voice' );
    is( $cfg->{say_language}, 'en-US',           'say_language' );
};

subtest 'add_section' => sub {
    my $b = new_builder();
    $b->add_section('intro');
    ok( exists $b->build->{sections}{intro}, 'intro section added' );
};

subtest 'reset clears document' => sub {
    my $b = new_builder();
    $b->answer->hangup;
    ok( scalar @{ main_of($b) }, 'main not empty before reset' );
    is( $b->reset, $b, 'reset returns self' );
    is_deeply( $b->build->{sections}, {}, 'sections cleared' );
};

subtest 'render is JSON string' => sub {
    my $b = new_builder();
    $b->answer;
    my $parsed = JSON::decode_json( $b->render );
    my ($first_key) = keys %{ $parsed->{sections}{main}[0] };
    is( $first_key, 'answer', 'render round-trips through JSON' );
};

subtest 'fluent chaining returns self' => sub {
    my $b      = new_builder();
    my $result = $b->reset->answer->say('hi')->hangup( reason => 'done' );
    is( $result, $b, 'chain returns builder' );
    my @verbs = map { ( keys %$_ )[0] } @{ main_of($b) };
    is_deeply( \@verbs, [qw(answer play hangup)], 'verb order' );
};

# ---- AUTOLOAD / __getattr__ (Perl analog of Python __getattr__) ----

subtest 'autovivifies schema verb' => sub {
    my $b = new_builder();
    $b->denoise;
    is_deeply( main_of($b)->[0], { denoise => {} }, 'denoise auto-vivified' );
};

subtest 'sleep is bare integer' => sub {
    my $b = new_builder();
    $b->sleep(2000);

    # SWML `sleep` emits a raw integer, not a config object.
    is_deeply( main_of($b)->[0], { sleep => 2000 }, 'sleep raw integer' );
};

subtest 'passes kwargs as config' => sub {
    my $b = new_builder();
    $b->record_call( stereo => JSON::true, format => 'wav' );
    my $cfg = main_of($b)->[0]{record_call};
    is( $cfg->{format}, 'wav', 'format kwarg' );
    ok( $cfg->{stereo}, 'stereo kwarg' );
};

subtest 'unknown method dies' => sub {
    my $b = new_builder();
    eval { $b->definitely_not_a_verb };
    like( $@, qr/no attribute|locate object method/, 'unknown verb dies' );
};

# __getattr__ can also be called directly (it is the recorded surface symbol).
subtest 'direct __getattr__ dispatch' => sub {
    my $b = new_builder();
    $b->__getattr__('denoise');
    is_deeply( main_of($b)->[0], { denoise => {} }, '__getattr__ dispatches verb' );
};

done_testing;
