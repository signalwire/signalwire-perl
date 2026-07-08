#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON ();

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

sub render_and_parse {
    return JSON::decode_json( $RENDERER->render_swml(@_) );
}

subtest 'render_swml basic text prompt' => sub {
    my $doc  = render_and_parse( prompt => 'you are helpful', service => new_service() );
    my $main = $doc->{sections}{main};
    is( scalar @$main, 1, 'one verb' );
    is_deeply( $main->[0]{ai}{prompt}, { text => 'you are helpful' }, 'ai text prompt' );
};

subtest 'add_answer precedes ai' => sub {
    my $doc  = render_and_parse( prompt => 'hi', service => new_service(), add_answer => 1 );
    my $main = $doc->{sections}{main};
    is( ( keys %{ $main->[0] } )[0], 'answer', 'answer first' );
    is( ( keys %{ $main->[1] } )[0], 'ai',     'ai second' );
};

subtest 'record_call wire keys' => sub {
    my $doc = render_and_parse(
        prompt        => 'hi',
        service       => new_service(),
        record_call   => 1,
        record_format => 'wav',
        record_stereo => JSON::false,
    );
    my ($rc) = grep { exists $_->{record_call} } @{ $doc->{sections}{main} };
    is( $rc->{record_call}{format}, 'wav', 'format key' );
    ok( !$rc->{record_call}{stereo}, 'stereo false' );
};

subtest 'default_webhook_url becomes SWAIG defaults' => sub {
    my $doc = render_and_parse(
        prompt              => 'hi',
        service             => new_service(),
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
        service          => new_service(),
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
        render_and_parse( prompt => $pom, service => new_service(), prompt_is_pom => 1 );
    is_deeply( $doc->{sections}{main}[0]{ai}{prompt}, { pom => $pom }, 'pom prompt' );
};

subtest 'params merged into ai' => sub {
    my $doc = render_and_parse(
        prompt  => 'hi',
        service => new_service(),
        params  => { temperature => 0.3 },
    );
    cmp_ok( abs( $doc->{sections}{main}[0]{ai}{temperature} - 0.3 ),
        '<', 1e-9, 'temperature merged' );
};

subtest 'yaml format' => sub {
    my $out = $RENDERER->render_swml( prompt => 'hi', service => new_service(), format => 'yaml' );
    require YAML;
    my $parsed = YAML::Load($out);
    is( ( keys %{ $parsed->{sections}{main}[0] } )[0], 'ai', 'yaml round-trips' );
};

# ---- render_function_response_swml ----

subtest 'function response plays text' => sub {
    my $out = $RENDERER->render_function_response_swml(
        response_text => 'All done',
        service       => new_service(),
    );
    my $main = JSON::decode_json($out)->{sections}{main};
    is_deeply( $main->[0], { play => { text => 'All done' } }, 'play text' );
};

subtest 'function response appends actions' => sub {
    my $out = $RENDERER->render_function_response_swml(
        response_text => 'bye',
        service       => new_service(),
        actions       => [
            { hangup   => { reason => 'done' } },
            { transfer => { dest   => 'sip:x@y' } },
        ],
    );
    my $main = JSON::decode_json($out)->{sections}{main};
    is_deeply( $main->[0], { play     => { text   => 'bye' } },      'play text' );
    is_deeply( $main->[1], { hangup   => { reason => 'done' } },     'hangup action' );
    is_deeply( $main->[2], { transfer => { dest   => 'sip:x@y' } },  'transfer action' );
};

subtest 'function response empty text skips play' => sub {
    my $out = $RENDERER->render_function_response_swml(
        response_text => '',
        service       => new_service(),
        actions       => [ { ai => { prompt => { text => 'x' } } } ],
    );
    my $main = JSON::decode_json($out)->{sections}{main};
    is( scalar @$main, 1, 'only the action verb' );
    is( ( keys %{ $main->[0] } )[0], 'ai', 'ai action present' );
};

done_testing;
