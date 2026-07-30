#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON ();

use SignalWire::DataMap;
use SignalWire::SWAIG::FunctionResult;

# =============================================
# Test: Basic construction
# =============================================
subtest 'Construction' => sub {
    my $dm = SignalWire::DataMap->new('get_weather');
    ok( $dm, 'DataMap created' );
    is( $dm->function_name, 'get_weather', 'function_name set' );

    # Named args
    $dm = SignalWire::DataMap->new( function_name => 'search' );
    is( $dm->function_name, 'search', 'named construction' );
};

# =============================================
# Test: Fluent API
# =============================================
subtest 'Fluent API chaining' => sub {
    my $dm = SignalWire::DataMap->new('test');

    my $ret = $dm->purpose('Test purpose');
    is( $ret, $dm, 'purpose returns self' );

    $ret = $dm->description('Test desc');
    is( $ret, $dm, 'description returns self' );

    $ret = $dm->parameter( 'city', 'string', 'City name', required => 1 );
    is( $ret, $dm, 'parameter returns self' );

    $ret = $dm->webhook( 'GET', 'https://api.example.com' );
    is( $ret, $dm, 'webhook returns self' );

    $ret = $dm->output( SignalWire::SWAIG::FunctionResult->new('result') );
    is( $ret, $dm, 'output returns self' );
};

# =============================================
# Test: Simple API tool
# =============================================
subtest 'Simple API tool' => sub {
    my $dm =
        SignalWire::DataMap->new('get_weather')
        ->purpose('Get weather for a location')
        ->parameter( 'location', 'string', 'City name', required => 1 )
        ->webhook( 'GET', 'https://api.weather.com/v1?q=${location}' )
        ->output( SignalWire::SWAIG::FunctionResult->new('Weather: ${response.temp}') );

    my $func = $dm->to_swaig_function;
    is( $func->{function},    'get_weather',                'function name' );
    is( $func->{description}, 'Get weather for a location', 'description' );

    # Parameters
    my $params = $func->{parameters};
    is( $params->{type}, 'object', 'params type is object' );
    ok( exists $params->{properties}{location}, 'has location parameter' );
    is( $params->{properties}{location}{type}, 'string', 'location is string' );
    is_deeply( $params->{required}, ['location'], 'location is required' );

    # Data map
    my $data_map = $func->{data_map};
    ok( exists $data_map->{webhooks}, 'has webhooks' );
    is( scalar @{ $data_map->{webhooks} }, 1,     'one webhook' );
    is( $data_map->{webhooks}[0]{method},  'GET', 'webhook method' );
    is( $data_map->{webhooks}[0]{url}, 'https://api.weather.com/v1?q=${location}', 'webhook url' );
    is( $data_map->{webhooks}[0]{output}{response}, 'Weather: ${response.temp}', 'webhook output' );
};

# =============================================
# Test: Expression-based tool
# =============================================
subtest 'Expression-based tool' => sub {
    my $dm =
        SignalWire::DataMap->new('file_control')
        ->purpose('Control file playback')
        ->parameter( 'command', 'string', 'Playback command', required => 1 )
        ->expression( '${args.command}', 'start.*',
        SignalWire::SWAIG::FunctionResult->new('Starting playback'),
        )
        ->expression( '${args.command}', 'stop.*',
        SignalWire::SWAIG::FunctionResult->new('Stopping playback'),
        );

    my $func     = $dm->to_swaig_function;
    my $data_map = $func->{data_map};
    ok( exists $data_map->{expressions}, 'has expressions' );
    is( scalar @{ $data_map->{expressions} }, 2, 'two expressions' );

    my $expr1 = $data_map->{expressions}[0];
    is( $expr1->{string},           '${args.command}',   'expression test value' );
    is( $expr1->{pattern},          'start.*',           'expression pattern' );
    is( $expr1->{output}{response}, 'Starting playback', 'expression output' );
};

# =============================================
# Test: Multiple webhooks with fallback
# =============================================
subtest 'Multiple webhooks and fallback' => sub {
    my $dm =
        SignalWire::DataMap->new('search_multi')
        ->purpose('Search with fallback')
        ->parameter( 'query', 'string', 'Search query', required => 1 )
        ->webhook( 'GET', 'https://api.primary.com/search?q=${query}' )
        ->output( SignalWire::SWAIG::FunctionResult->new('Primary: ${response.title}') )
        ->webhook( 'GET', 'https://api.fallback.com/search?q=${query}' )
        ->output( SignalWire::SWAIG::FunctionResult->new('Fallback: ${response.title}') )
        ->fallback_output( SignalWire::SWAIG::FunctionResult->new('All APIs unavailable') );

    my $func     = $dm->to_swaig_function;
    my $data_map = $func->{data_map};
    is( scalar @{ $data_map->{webhooks} }, 2, 'two webhooks' );
    is(
        $data_map->{webhooks}[0]{output}{response},
        'Primary: ${response.title}',
        'first webhook output'
    );
    is(
        $data_map->{webhooks}[1]{output}{response},
        'Fallback: ${response.title}',
        'second webhook output'
    );
    is( $data_map->{output}{response}, 'All APIs unavailable', 'fallback output' );
};

# =============================================
# Test: Error keys
# =============================================
subtest 'Error keys' => sub {
    my $dm =
        SignalWire::DataMap->new('test')
        ->purpose('Test')
        ->webhook( 'GET', 'https://api.example.com' )
        ->output( SignalWire::SWAIG::FunctionResult->new('ok') )
        ->error_keys( [ 'error', 'err' ] );

    my $func = $dm->to_swaig_function;
    is_deeply(
        $func->{data_map}{webhooks}[0]{error_keys},
        [ 'error', 'err' ],
        'webhook error_keys'
    );

    # Global error keys
    $dm = SignalWire::DataMap->new('test2')->purpose('Test')->global_error_keys( ['global_err'] );

    $func = $dm->to_swaig_function;
    is_deeply( $func->{data_map}{error_keys}, ['global_err'], 'global error_keys' );
};

# =============================================
# Test: Foreach
# =============================================
subtest 'Foreach' => sub {
    my $dm =
        SignalWire::DataMap->new('search_docs')
        ->purpose('Search docs')
        ->parameter( 'query', 'string', 'Search query', required => 1 )
        ->webhook( 'POST', 'https://api.docs.com/search' )
        ->params( { query => '${query}' } )
        ->output( SignalWire::SWAIG::FunctionResult->new('Results: ${formatted}') )
        ->foreach(
        {
            input_key  => 'results',
            output_key => 'formatted',
            max        => 3,
            append     => '${this.title}: ${this.summary}\n',
        }
        );

    my $func = $dm->to_swaig_function;
    my $fe   = $func->{data_map}{webhooks}[0]{foreach};
    is( $fe->{input_key},  'results',   'foreach input_key' );
    is( $fe->{output_key}, 'formatted', 'foreach output_key' );
    is( $fe->{max},        3,           'foreach max' );
};

# =============================================
# Test: Parameter with enum
# =============================================
subtest 'Parameter with enum' => sub {
    my $dm = SignalWire::DataMap->new('test')->purpose('Test')->parameter(
        'unit', 'string', 'Temperature unit',
        required => 1,
        enum     => [ 'fahrenheit', 'celsius' ]
    );

    my $func  = $dm->to_swaig_function;
    my $param = $func->{parameters}{properties}{unit};
    is_deeply( $param->{enum}, [ 'fahrenheit', 'celsius' ], 'parameter enum' );
};

# =============================================
# Test: Error handling
# =============================================
subtest 'Error handling' => sub {
    my $dm = SignalWire::DataMap->new('test');

    # params without webhook
    eval { $dm->params( { key => 'value' } ) };
    ok( $@, 'params without webhook dies' );

    # output without webhook
    eval { $dm->output( SignalWire::SWAIG::FunctionResult->new('x') ) };
    ok( $@, 'output without webhook dies' );

    # foreach without webhook
    eval { $dm->foreach( { input_key => 'a', output_key => 'b', append => 'c' } ) };
    ok( $@, 'foreach without webhook dies' );

    # foreach missing keys
    $dm->webhook( 'GET', 'https://example.com' );
    eval { $dm->foreach( { input_key => 'a' } ) };
    ok( $@, 'foreach with missing keys dies' );
};

# =============================================
# Test: Default description
# =============================================
subtest 'Default description' => sub {
    my $dm   = SignalWire::DataMap->new('my_tool');
    my $func = $dm->to_swaig_function;
    is( $func->{description}, 'Execute my_tool', 'default description when none set' );
};

# =============================================
# Test: No parameters
# =============================================
subtest 'No parameters' => sub {
    my $dm   = SignalWire::DataMap->new('simple')->purpose('Simple tool');
    my $func = $dm->to_swaig_function;
    is( $func->{parameters}{type}, 'object', 'empty params has type object' );
    is_deeply( $func->{parameters}{properties}, {}, 'empty params has empty properties' );
};

# =============================================
# Test: the body() builder is GONE
#
# Owner-ruled 2026-07-29 (signalwire-python 71eed0c), extending the f171ce3
# ruling ("if the server doesn't read them, remove them") from the
# create_simple_api_tool PARAMETER to the public BUILDER METHOD. Three
# independent sources condemn it:
#
#   * porting-sdk/schema.json $defs/Webhook declares exactly ten properties
#     under unevaluatedProperties: {"not": {}} -- body is not among them, so
#     emitting it is a SCHEMA VIOLATION.
#   * mod_openai/actions.c:735-739 and bedrock.c:4920-4926 read url, method,
#     form_param, params and headers and nothing else; grep -n '"body"'
#     across both returns ZERO matches.
#   * So its only possible effect was producing an invalid document while
#     silently discarding the caller's payload.
#
# params() is the correct method: it writes the `params` key, which IS in the
# contract and IS read.
# =============================================
subtest 'body() builder is removed' => sub {
    ok( !SignalWire::DataMap->can('body'),
              'DataMap->can("body") is false -- the builder writes a schema-forbidden '
            . 'key that no engine reader consumes; use params() instead' );

    # create_simple_api_tool must no longer forward a body option to the wire.
    my $dm = SignalWire::DataMap::create_simple_api_tool(
        name              => 'search',
        url               => 'https://api.example.com/search',
        response_template => 'Found: ${response.title}',
        method            => 'POST',
        body              => { query => 'Q' },
    );
    my $wh = $dm->to_swaig_function->{data_map}{webhooks}[0];
    ok( !exists $wh->{body}, 'create_simple_api_tool emits no body key' );
    is_deeply( [ sort keys %$wh ],
        [qw(method output url)], 'webhook keys are exactly method/output/url' );
};

# =============================================
# Test: params() still writes the contract key (positive control)
# =============================================
subtest 'params writes the contract key' => sub {
    my $dm =
        SignalWire::DataMap->new('search')
        ->purpose('Search docs')
        ->parameter( 'query', 'string', 'Search query', required => 1 )
        ->webhook( 'POST', 'https://api.docs.com/search',
        headers => { 'Authorization' => 'Bearer TOKEN' } )
        ->params( { query => '${query}', limit => 3 } )
        ->output( SignalWire::SWAIG::FunctionResult->new('Found: ${response.title}') );

    my $wh = $dm->to_swaig_function->{data_map}{webhooks}[0];
    is( $wh->{method},                 'POST',         'POST method' );
    is( $wh->{headers}{Authorization}, 'Bearer TOKEN', 'has headers' );
    is_deeply(
        $wh->{params},
        { query => '${query}', limit => 3 },
        'params written verbatim to the contract key'
    );
    ok( !exists $wh->{body}, 'no body key emitted' );
};

done_testing;
