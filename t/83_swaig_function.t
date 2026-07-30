#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Tests for SignalWire::SWAIG::SWAIGFunction — the standalone SWAIG "tool"
# wrapper. Mirrors the Ruby tests/swaig_function_test.rb (construction, call,
# execute, to_swaig, validate_args).

use_ok('SignalWire::SWAIG::SWAIGFunction');
use_ok('SignalWire::SWAIG::FunctionResult');

sub build_function {
    my (%overrides) = @_;
    my %defaults = (
        name        => 'get_weather',
        description => 'Get the current weather for a city',
        handler     => sub {
            my ( $args, $raw ) = @_;
            return SignalWire::SWAIG::FunctionResult->new("Weather in $args->{city}");
        },
        parameters => { city => { type => 'string' } },
        required   => ['city'],
    );
    return SignalWire::SWAIG::SWAIGFunction->new( %defaults, %overrides );
}

# ------------------------------------------------------------------
# Construction
# ------------------------------------------------------------------
subtest 'initialize attributes' => sub {
    my $fn = build_function( webhook_url => 'https://ex.com/hook', secure => 1 );
    is( $fn->name,        'get_weather',                        'name' );
    is( $fn->description, 'Get the current weather for a city', 'description' );
    ok( $fn->secure,      'secure' );
    ok( $fn->is_external, 'is_external when webhook_url given' );
    is( $fn->webhook_url, 'https://ex.com/hook', 'webhook_url' );
};

subtest 'not external without webhook' => sub {
    ok( !build_function()->is_external, 'no webhook => not external' );
};

subtest 'extra swaig fields collected' => sub {
    my $fn = build_function( meta_data_token => 'tok', web_hook_auth_user => 'u' );
    is( $fn->extra_swaig_fields->{meta_data_token},    'tok', 'meta_data_token collected' );
    is( $fn->extra_swaig_fields->{web_hook_auth_user}, 'u',   'web_hook_auth_user collected' );
};

# ------------------------------------------------------------------
# call (Perl analog of Python __call__)
# ------------------------------------------------------------------
subtest 'call invokes handler' => sub {
    my $fn     = build_function();
    my $result = $fn->call( { city => 'NYC' }, {} );
    isa_ok( $result, 'SignalWire::SWAIG::FunctionResult' );
    is( $result->response, 'Weather in NYC', 'handler result' );
};

# ------------------------------------------------------------------
# execute
# ------------------------------------------------------------------
subtest 'execute coerces FunctionResult to hash' => sub {
    my $out = build_function()->execute( { city => 'LA' } );
    is( $out->{response}, 'Weather in LA', 'response key' );
};

subtest 'execute passthrough response hash' => sub {
    my $fn = build_function( handler => sub { return { response => 'raw' } } );
    is_deeply( $fn->execute( {} ), { response => 'raw' }, 'passthrough' );
};

subtest 'execute dict without response' => sub {
    my $fn = build_function( handler => sub { return { other => 1 } } );
    is( $fn->execute( {} )->{response}, 'Function completed successfully', 'generic success' );
};

subtest 'execute string result' => sub {
    my $fn = build_function( handler => sub { return 'plain string' } );
    is( $fn->execute( {} )->{response}, 'plain string', 'string wrapped' );
};

subtest 'execute swallows handler errors' => sub {
    my $fn  = build_function( handler => sub { die "boom\n" } );
    my $out = $fn->execute( { city => 'X' } );
    like( $out->{response}, qr/couldn't complete that action/, 'generic non-leaking error' );
};

# ------------------------------------------------------------------
# to_swaig
# ------------------------------------------------------------------
subtest 'to_swaig wire shape' => sub {
    my $swaig = build_function()->to_swaig( base_url => 'https://ex.com' );
    is( $swaig->{function},     'get_weather',                        'function name' );
    is( $swaig->{description},  'Get the current weather for a city', 'description' );
    is( $swaig->{web_hook_url}, 'https://ex.com/swaig',               'web_hook_url' );
    is_deeply(
        $swaig->{parameters},
        { type => 'object', properties => { city => { type => 'string' } }, required => ['city'] },
        'parameters wrapped into envelope',
    );
};

subtest 'to_swaig with token and call_id' => sub {
    my $swaig =
        build_function()->to_swaig( base_url => 'https://ex.com', token => 'T', call_id => 'C' );
    is( $swaig->{web_hook_url}, 'https://ex.com/swaig?token=T&call_id=C', 'auth query string' );
};

subtest 'to_swaig includes fillers and extras' => sub {
    my $fn = build_function( fillers => { 'en-US' => ['one moment'] }, meta_data_token => 'tok' );
    my $swaig = $fn->to_swaig( base_url => 'https://ex.com' );
    is_deeply( $swaig->{fillers}, { 'en-US' => ['one moment'] }, 'fillers' );
    is( $swaig->{meta_data_token}, 'tok', 'extra field merged' );
};

subtest 'to_swaig preexisting structured parameters untouched' => sub {
    my $schema =
        { type => 'object', properties => { q => { type => 'string' } }, required => ['q'] };
    my $fn = build_function( parameters => $schema, required => [] );
    is_deeply( $fn->to_swaig( base_url => 'https://ex.com' )->{parameters},
        $schema, 'structured parameters passed through' );
};

# ------------------------------------------------------------------
# validate_args
# ------------------------------------------------------------------
subtest 'validate_args accepts valid' => sub {
    my ( $valid, $errors ) = build_function()->validate_args( { city => 'NYC' } );
    ok( $valid, 'valid' );
    is_deeply( $errors, [], 'no errors' );
};

subtest 'validate_args rejects missing required' => sub {
    my ( $valid, $errors ) = build_function()->validate_args( {} );
    ok( !$valid,                      'invalid' );
    ok( ( grep { /city/ } @$errors ), 'error mentions city' );
};

subtest 'validate_args rejects wrong type' => sub {

    # In Perl a bare number is indistinguishable from a string, so use a
    # ref value (arrayref) which is unambiguously not a JSON string.
    my ( $valid, $errors ) = build_function()->validate_args( { city => [] } );
    ok( !$valid,                        'invalid' );
    ok( ( grep { /string/ } @$errors ), 'error mentions string type' );
};

subtest 'validate_args no params is valid' => sub {
    my $fn = build_function( parameters => {}, required => [] );
    my ( $valid, $errors ) = $fn->validate_args( {} );
    ok( $valid, 'valid' );
    is_deeply( $errors, [], 'no errors' );
};

done_testing;
