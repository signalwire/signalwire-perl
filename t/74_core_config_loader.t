#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp ();
use JSON::PP   ();

use SignalWire::Core::ConfigLoader;

# Build a temp JSON config file for the load tests.
my $dir = File::Temp->newdir;
my $cfg_path = "$dir/config.json";
{
    open my $fh, '>', $cfg_path or die $!;
    print {$fh} JSON::PP::encode_json(
        {   security => {
                ssl_enabled  => JSON::PP::true(),
                allowed_host => '${MY_HOST|localhost}',
            },
            server => { port => 8080 },
        }
    );
    close $fh;
}

subtest 'no config found' => sub {
    my $loader = SignalWire::Core::ConfigLoader->new( ["$dir/does_not_exist.json"] );
    ok( !$loader->has_config, 'has_config false when nothing loaded' );
    is( $loader->get_config_file, undef, 'no config file path' );
    is_deeply( $loader->get_config, {}, 'get_config empty hash' );
    is( $loader->get( 'a.b', 'fallback' ), 'fallback', 'get returns default' );
    is_deeply( $loader->get_section('nope'), {}, 'get_section empty' );
};

subtest 'load from file' => sub {
    my $loader = SignalWire::Core::ConfigLoader->new( [$cfg_path] );
    ok( $loader->has_config, 'has_config true' );
    is( $loader->get_config_file, $cfg_path, 'config file path recorded' );
    my $raw = $loader->get_config;
    is( $raw->{server}{port}, 8080, 'raw config value' );
};

subtest 'get dot-notation + get_section' => sub {
    my $loader = SignalWire::Core::ConfigLoader->new( [$cfg_path] );
    ok( $loader->get('security.ssl_enabled'), 'nested value via dot path' );
    is( $loader->get( 'security.nope', 'd' ), 'd', 'missing nested returns default' );
    my $sec = $loader->get_section('security');
    is( ref $sec, 'HASH', 'section is a hash' );
    ok( exists $sec->{ssl_enabled}, 'section has ssl_enabled' );
};

subtest 'substitute_vars ${VAR|default} + type coercion' => sub {
    my $loader = SignalWire::Core::ConfigLoader->new( ["$dir/none.json"] );

    local $ENV{SET_VAR} = 'value1';
    is( $loader->substitute_vars('${SET_VAR}'),       'value1',  'env var substituted' );
    is( $loader->substitute_vars('${UNSET_VAR|def}'), 'def',     'default used when unset' );
    is( $loader->substitute_vars('${UNSET_VAR2}'),    '',        'empty when unset & no default' );

    # type coercion (Python JSON typing parity)
    is( $loader->substitute_vars('42'),   42,    'integer coerced' );
    is( $loader->substitute_vars('3.14'), 3.14,  'float coerced' );
    ok( $loader->substitute_vars('true'),  'true -> truthy' );
    ok( !$loader->substitute_vars('false'), 'false -> falsy' );
    is( $loader->substitute_vars('plain'), 'plain', 'plain string unchanged' );

    # recursive on hash / array
    my $out = $loader->substitute_vars( { a => '${SET_VAR}', b => [ '${UNSET_VAR|x}' ] } );
    is( $out->{a},    'value1', 'hash value substituted' );
    is( $out->{b}[0], 'x',      'array value substituted' );

    # depth guard
    eval { $loader->substitute_vars( 'x', 0 ) };
    like( $@, qr/depth exceeded/, 'depth guard dies' );
};

subtest 'merge_with_env folds prefixed env vars' => sub {
    my $loader = SignalWire::Core::ConfigLoader->new( ["$dir/none.json"] );
    local $ENV{SWML_SSL_ENABLED} = 'true';
    my $merged = $loader->merge_with_env('SWML_');
    is( $merged->{ssl}{enabled}, 'true', 'SWML_SSL_ENABLED -> ssl.enabled nested' );
};

subtest 'find_config_file static helper' => sub {
    # chdir into temp dir so relative default paths resolve there
    my $orig = Cwd::getcwd() if eval { require Cwd; 1 };
    chdir $dir or die;
    my $found = SignalWire::Core::ConfigLoader->find_config_file;
    is( $found, 'config.json', 'finds config.json in cwd' );
    is( SignalWire::Core::ConfigLoader->find_config_file('nosuch'),
        'config.json', 'falls through to default when service config absent' );
    chdir $orig if $orig;
};

done_testing;
