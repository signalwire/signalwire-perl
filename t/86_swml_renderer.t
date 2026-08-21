#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON     ();
use JSON::PP ();

# Tests for SignalWire::SWML::SWMLRenderer->render_swml /
# render_function_response_swml — render a full SWML doc and assert its exact
# structure and wire keys. Mirrors the Ruby tests/swml_renderer_test.rb.

use_ok('SignalWire::SWML::Service');
use_ok('SignalWire::SWML::SWMLRenderer');

my $RENDERER = 'SignalWire::SWML::SWMLRenderer';

sub new_service {
    my ($name) = @_;
    return SignalWire::SWML::Service->new( name => $name // 'renderer-test' );
}

# A service with STRICT schema validation on. The renderer must emit only
# shapes the SWML schema accepts, so every renderer test runs against this:
# a schema-invalid verb config dies inside Service::add_verb instead of being
# appended silently. Asserting the rendered JSON against a hand-written blob
# alone re-encodes the very blind spot that let `play {text=>...}` ship — the
# raw Document::add_verb path never consulted the schema.
sub new_strict_service {
    my ($name) = @_;
    my $svc = new_service($name);
    $svc->full_validation(1);
    return $svc;
}

sub render_and_parse {
    my (@args) = @_;
    return JSON::decode_json( $RENDERER->render_swml(@args) );
}

subtest 'render_swml basic text prompt' => sub {
    my $doc  = render_and_parse( prompt => 'you are helpful', service => new_strict_service() );
    my $main = $doc->{sections}{main};
    is( scalar @$main, 1, 'one verb' );
    is_deeply( $main->[0]{ai}{prompt}, { text => 'you are helpful' }, 'ai text prompt' );
};

subtest 'add_answer precedes ai' => sub {
    my $doc  = render_and_parse( prompt => 'hi', service => new_strict_service(), add_answer => 1 );
    my $main = $doc->{sections}{main};
    is( ( keys %{ $main->[0] } )[0], 'answer', 'answer first' );
    is( ( keys %{ $main->[1] } )[0], 'ai',     'ai second' );
};

subtest 'record_call wire keys' => sub {
    my $doc = render_and_parse(
        prompt        => 'hi',
        service       => new_strict_service(),
        record_call   => 1,
        record_format => 'wav',
        record_stereo => JSON::false,
    );
    my ($rc) = grep { exists $_->{record_call} } @{ $doc->{sections}{main} };
    is( $rc->{record_call}{format}, 'wav', 'format key' );
    ok( !$rc->{record_call}{stereo}, 'stereo false' );
};

subtest 'record_call stereo is a JSON boolean, not a number' => sub {

    # $defs/RecordCall.stereo is anyOf<boolean, SWMLVar>. The default came
    # through as a bare Perl 1, which JSON-encodes as the NUMBER 1 and the
    # schema rejects. The renderer must normalise truthiness to JSON::true.
    my $doc = render_and_parse(
        prompt      => 'hi',
        service     => new_strict_service(),
        record_call => 1,
    );
    my ($rc) = grep { exists $_->{record_call} } @{ $doc->{sections}{main} };
    ok( JSON::PP::is_bool( $rc->{record_call}{stereo} ), 'stereo is a JSON boolean' );
    ok( $rc->{record_call}{stereo},                      'default stereo is true' );
};

subtest 'default_webhook_url becomes SWAIG defaults' => sub {
    my $doc = render_and_parse(
        prompt              => 'hi',
        service             => new_strict_service(),
        default_webhook_url => 'https://ex.com/swaig',
    );
    my $ai = $doc->{sections}{main}[0]{ai};
    is_deeply(
        $ai->{SWAIG}{defaults},
        { web_hook_url => 'https://ex.com/swaig' },
        'default webhook becomes defaults',
    );
};

sub hooks_functions {
    my $doc = render_and_parse(
        prompt           => 'hi',
        service          => new_strict_service(),
        startup_hook_url => 'https://ex.com/start',
        hangup_hook_url  => 'https://ex.com/end',
        swaig_functions  => [
            { function => 'get_weather', description => 'w', parameters => {} },

            # A caller-supplied startup_hook must be skipped (deduped).
            { function => 'startup_hook', description => 'dup' },
        ],
    );
    return $doc->{sections}{main}[0]{ai}{SWAIG}{functions};
}

subtest 'dedupes and orders hooks' => sub {
    my @names = map { $_->{function} } @{ hooks_functions() };
    is_deeply( \@names, [qw(startup_hook hangup_hook get_weather)], 'hook order + dedup' );
};

subtest 'hook wire shape' => sub {
    my $startup = hooks_functions()->[0];
    is( $startup->{web_hook_url}, 'https://ex.com/start', 'web_hook_url' );
    is_deeply( $startup->{parameters}, { type => 'object', properties => {} }, 'empty params' );
};

subtest 'pom prompt' => sub {
    my $pom = [ { title => 'Role', body => 'assistant' } ];
    my $doc =
        render_and_parse( prompt => $pom, service => new_strict_service(), prompt_is_pom => 1 );
    is_deeply( $doc->{sections}{main}[0]{ai}{prompt}, { pom => $pom }, 'pom prompt' );
};

subtest 'params merged into ai' => sub {

    # `params` merges FLAT into the ai config (reference: config.update(kwargs)),
    # so its keys must be real top-level AIObject properties. The old fixture
    # passed `temperature`, which is NOT one — it lives inside the prompt object
    # ($defs/AIPromptText.temperature) — and only survived because this path
    # bypassed the schema. `hints` is a genuine top-level ai key.
    my $doc = render_and_parse(
        prompt  => 'hi',
        service => new_strict_service(),
        params  => { hints => ['SignalWire'] },
    );
    is_deeply( $doc->{sections}{main}[0]{ai}{hints}, ['SignalWire'], 'params merged' );
};

subtest 'a params key that is not a top-level ai property is refused' => sub {
    my $ok = eval {
        render_and_parse(
            prompt  => 'hi',
            service => new_strict_service(),
            params  => { temperature => 0.3 },
        );
        1;
    };
    my $err = $@;
    ok( !$ok, 'temperature at the ai top level is rejected' );
    like( "$err", qr/temperature/, 'the error names the offending key' );
};

subtest 'yaml format' => sub {
    my $out =
        $RENDERER->render_swml( prompt => 'hi', service => new_strict_service(), format => 'yaml' );
    require YAML;
    my $parsed = YAML::Load($out);
    is( ( keys %{ $parsed->{sections}{main}[0] } )[0], 'ai', 'yaml round-trips' );
};

# ---- render_function_response_swml ----

subtest 'function response plays text via the say: URL scheme' => sub {

    # The SWML `play` verb has NO `text` key: its config is
    # PlayWithURL/PlayWithURLS and spoken text goes through the `say:` URL
    # scheme. Emitting {text=>...} produced a document the schema rejects.
    my $out = $RENDERER->render_function_response_swml(
        response_text => 'All done',
        service       => new_strict_service(),
    );
    my $main = JSON::decode_json($out)->{sections}{main};
    is_deeply( $main->[0], { play => { url => 'say:All done' } }, 'play url say:' );
    ok( !exists $main->[0]{play}{text}, 'no schema-forbidden text key' );
};

subtest 'function response appends actions' => sub {
    my $out = $RENDERER->render_function_response_swml(
        response_text => 'bye',
        service       => new_strict_service(),
        actions       => [

            # `hangup` is a CLOSED enum (hangup|busy|decline); the old fixture
            # rode the unvalidated raw path with reason => 'done'.
            { hangup   => { reason => 'hangup' } },
            { transfer => { dest   => 'sip:x@y' } },
        ],
    );
    my $main = JSON::decode_json($out)->{sections}{main};
    is_deeply( $main->[0], { play     => { url    => 'say:bye' } }, 'play url' );
    is_deeply( $main->[1], { hangup   => { reason => 'hangup' } },  'hangup action' );
    is_deeply( $main->[2], { transfer => { dest   => 'sip:x@y' } }, 'transfer action' );
};

subtest 'function response rejects a schema-invalid action' => sub {

    # The whole point of routing through Service::add_verb: an invalid config
    # must DIE, not ship.
    #
    # An unknown KEY on a closed verb is the misshapen-config case this
    # subtest exists to catch. The out-of-union `reason` case is covered by
    # t/102_schema_hangup_reason.t, which pins the engine's six-value set.
    my $err = '';
    my $ok  = eval {
        $RENDERER->render_function_response_swml(
            response_text => 'bye',
            service       => new_strict_service(),
            actions       => [ { hangup => { reasonn => 'busy' } } ],
        );
        1;
    };
    $err = $@;
    ok( !$ok, 'a misspelled key on a closed verb is refused' );
    like( "$err", qr/hangup/, 'the error names the offending verb' );

    # ...while an engine-valid reason SHIPS. 'noAnswer' is one of the six
    # values relay_apis.c:1105 accepts, and was absent from the schema's old
    # three-const union.
    my $engine_ok = eval {
        $RENDERER->render_function_response_swml(
            response_text => 'bye',
            service       => new_strict_service(),
            actions       => [ { hangup => { reason => 'noAnswer' } } ],
        );
        1;
    };
    ok( $engine_ok, 'an engine-valid hangup reason is NOT refused' ) or diag($@);
};

subtest 'function response empty text skips play' => sub {
    my $out = $RENDERER->render_function_response_swml(
        response_text => '',
        service       => new_strict_service(),
        actions       => [ { ai => { prompt => { text => 'x' } } } ],
    );
    my $main = JSON::decode_json($out)->{sections}{main};
    is( scalar @$main,               1,    'only the action verb' );
    is( ( keys %{ $main->[0] } )[0], 'ai', 'ai action present' );
};

done_testing;
