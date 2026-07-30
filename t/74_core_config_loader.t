#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp ();
use JSON::PP   ();

use SignalWire::Core::ConfigLoader;

# A scope guard that chdir's back on scope exit — including the die path, which
# a trailing `chdir $orig` in the body does NOT cover. See the comment on the
# find_config_file subtest below for the defect this replaced.
{

    package SignalWire::Test::CwdGuard;    ## no critic (Modules::ProhibitMultiplePackages)

    sub new {
        my ( $class, $dir ) = @_;
        return bless { dir => $dir }, $class;
    }

    sub DESTROY {
        my ($self) = @_;
        chdir $self->{dir} if defined $self->{dir};
        return;
    }
}

# Build a temp JSON config file for the load tests.
my $dir      = File::Temp->newdir;
my $cfg_path = "$dir/config.json";
{
    open my $fh, '>', $cfg_path or die $!;
    print {$fh} JSON::PP::encode_json(
        {
            security => {
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
    is( $loader->substitute_vars('${SET_VAR}'),       'value1', 'env var substituted' );
    is( $loader->substitute_vars('${UNSET_VAR|def}'), 'def',    'default used when unset' );
    is( $loader->substitute_vars('${UNSET_VAR2}'),    '',       'empty when unset & no default' );

    # type coercion (Python JSON typing parity)
    is( $loader->substitute_vars('42'),   42,   'integer coerced' );
    is( $loader->substitute_vars('3.14'), 3.14, 'float coerced' );
    ok( $loader->substitute_vars('true'),   'true -> truthy' );
    ok( !$loader->substitute_vars('false'), 'false -> falsy' );
    is( $loader->substitute_vars('plain'), 'plain', 'plain string unchanged' );

    # recursive on hash / array
    my $out = $loader->substitute_vars( { a => '${SET_VAR}', b => ['${UNSET_VAR|x}'] } );
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

    # chdir into temp dir so relative default paths resolve there.
    #
    # The restore is a SCOPE GUARD, not a trailing `chdir $orig if $orig`. Two
    # defects in that older shape:
    #   1. `my $orig = ... if COND` is undefined behaviour in perl (perlsyn:
    #      "the behaviour ... is undefined"); the declaration is compile-time but
    #      the assignment is not, so $orig's value is not reliably scoped.
    #   2. A trailing chdir is SKIPPED whenever the body dies — a real assertion
    #      failure, a missing file, anything. The process is then left inside
    #      $dir, which File::Temp deletes at exit, so every later relative-path
    #      test resolves against a removed directory and File::Temp itself dies
    #      with "cannot remove path when cwd is ...".
    # A guard object's DESTROY runs on BOTH the normal and the die path.
    require Cwd;
    my $orig    = Cwd::getcwd();
    my $restore = SignalWire::Test::CwdGuard->new($orig);
    chdir $dir or die "chdir $dir: $!";
    my $found = SignalWire::Core::ConfigLoader->find_config_file;
    is( $found, 'config.json', 'finds config.json in cwd' );
    is( SignalWire::Core::ConfigLoader->find_config_file('nosuch'),
        'config.json', 'falls through to default when service config absent' );
};

# REGRESSION for the cwd-leak above. The old shape restored the directory with a
# trailing `chdir $orig if $orig`, which never runs when the body dies — leaving
# the process inside a File::Temp dir that is then rmdir'd, so File::Temp aborts
# the run with "cannot remove path when cwd is ...". Prove the guard restores on
# the DIE path, which is exactly the path the old code missed.
subtest 'CwdGuard restores the directory even when the body dies' => sub {
    require Cwd;
    my $home = Cwd::getcwd();
    my $tmp  = File::Temp->newdir;
    my $died = 0;
    eval {
        my $restore = SignalWire::Test::CwdGuard->new( Cwd::getcwd() );
        chdir $tmp or die "chdir $tmp: $!";
        isnt( Cwd::getcwd(), $home, 'inside the temp dir before the die' );
        die "simulated failure inside the guarded scope\n";
    };
    $died = 1 if $@;
    ok( $died, 'the body really did die' );
    is( Cwd::getcwd(), $home, 'CWD restored by the guard despite the die' );
};

done_testing;
