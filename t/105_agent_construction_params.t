#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use JSON::PP ();

# Construction-parameter parity for AgentBase / SWML::Service.
#
# The Python reference's ``AgentBase.__init__`` does NOT store these params on
# self — it FORWARDS them to collaborators:
#
#   schema_path / config_file / schema_validation -> super().__init__ (SWMLService)
#                                                    [agent_base.py:205-207]
#   token_expiry_secs                             -> SessionManager(...)
#                                                    [agent_base.py:247]
#
# Perl's AgentBase/Service had the collaborators (SchemaUtils honours
# schema_path + schema_validation, SecurityConfig/ConfigLoader honour
# config_file, SessionManager honours token_expiry_secs) but the constructor
# chain was never wired, so none of it was reachable from ``->new``.
#
# These tests exercise REAL behavior (no transport mocking): a real temp
# schema file, a real temp config file, a real SessionManager token TTL.

use_ok('SignalWire::Agent::AgentBase');
use_ok('SignalWire::SWML::Service');

# ------------------------------------------------------------------
# token_expiry_secs -> SessionManager
# ------------------------------------------------------------------
subtest 'token_expiry_secs forwards to SessionManager' => sub {
    my $default = SignalWire::Agent::AgentBase->new( name => 'tok_default' );
    is( $default->session_manager->token_expiry_secs,
        3600, 'default token_expiry_secs is 3600' );

    my $agent = SignalWire::Agent::AgentBase->new(
        name              => 'tok_agent',
        token_expiry_secs => 90,
    );
    is( $agent->token_expiry_secs, 90, 'token_expiry_secs readable on the agent' );
    is( $agent->session_manager->token_expiry_secs,
        90, 'token_expiry_secs was FORWARDED to the SessionManager collaborator' );
};

# ------------------------------------------------------------------
# schema_validation -> SchemaUtils (via Service)
# ------------------------------------------------------------------
subtest 'schema_validation forwards to the schema validator' => sub {
    my $on = SignalWire::SWML::Service->new( name => 'sv_on' );
    ok( $on->schema_validation, 'schema_validation defaults to true' );
    ok( $on->schema_utils->schema_validation,
        'validator collaborator has validation enabled by default' );

    my $off = SignalWire::SWML::Service->new(
        name              => 'sv_off',
        schema_validation => 0,
    );
    ok( !$off->schema_validation, 'schema_validation=0 readable' );
    ok( !$off->schema_utils->schema_validation,
        'schema_validation=0 was FORWARDED to the validator collaborator' );

    # Behavioral: with validation disabled, an unknown verb validates clean.
    my ( $ok_off, $errs_off ) = $off->schema_utils->validate_verb( 'no_such_verb', {} );
    ok( $ok_off, 'validation disabled -> unknown verb accepted (real behavior)' );

    my ( $ok_on, $errs_on ) = $on->schema_utils->validate_verb( 'no_such_verb', {} );
    ok( !$ok_on, 'validation enabled -> unknown verb rejected (real behavior)' );

    # Same wiring must reach through AgentBase.
    my $agent = SignalWire::Agent::AgentBase->new(
        name              => 'sv_agent',
        schema_validation => 0,
    );
    ok( !$agent->schema_utils->schema_validation,
        'AgentBase forwards schema_validation down to the validator' );
};

# ------------------------------------------------------------------
# schema_path -> SchemaUtils (via Service)
# ------------------------------------------------------------------
subtest 'schema_path forwards to the schema validator' => sub {
    my $dir  = tempdir( CLEANUP => 1 );
    my $path = File::Spec->catfile( $dir, 'schema.json' );

    # A minimal SWML schema carrying one distinctive verb name so we can prove
    # the custom file — not the bundled one — was actually loaded.
    my $schema = {
        '$defs' => {
            SWMLMethod => {
                anyOf => [ { '$ref' => '#/$defs/SWMLMethodCustomOnlyVerb' } ],
            },
            SWMLMethodCustomOnlyVerb => {
                type       => 'object',
                properties => { custom_only_verb => { type => 'object' } },
            },
        },
    };
    open my $fh, '>', $path or die "open $path: $!";
    print {$fh} JSON::PP->new->encode($schema);
    close $fh;

    my $svc = SignalWire::SWML::Service->new(
        name        => 'sp_svc',
        schema_path => $path,
    );
    is( $svc->schema_path, $path, 'schema_path readable on the service' );
    is( $svc->schema_utils->schema_path,
        $path, 'schema_path was FORWARDED to the validator collaborator' );

    # Behavioral: the validator really parsed OUR file.
    my @verb_names = $svc->schema_utils->get_all_verb_names;
    is_deeply( [ sort @verb_names ], ['custom_only_verb'],
        'custom schema file was actually loaded (only our verb is known)' );

    my $agent = SignalWire::Agent::AgentBase->new(
        name        => 'sp_agent',
        schema_path => $path,
    );
    is( $agent->schema_utils->schema_path,
        $path, 'AgentBase forwards schema_path down to the validator' );
};

# ------------------------------------------------------------------
# config_file -> SecurityConfig / service config
# ------------------------------------------------------------------
subtest 'config_file forwards to SecurityConfig and seeds service config' => sub {
    my $dir  = tempdir( CLEANUP => 1 );
    my $path = File::Spec->catfile( $dir, 'agent_config.json' );

    my $config = {
        service  => { route => '/from-config', host => '127.0.0.1', port => 8123 },
        security => { ssl_enabled => JSON::PP::true, domain => 'cfg.example.com' },
    };
    open my $fh, '>', $path or die "open $path: $!";
    print {$fh} JSON::PP->new->encode($config);
    close $fh;

    my $svc = SignalWire::SWML::Service->new(
        name        => 'cfg_svc',
        config_file => $path,
    );
    is( $svc->config_file, $path, 'config_file readable on the service' );
    is( $svc->security->domain, 'cfg.example.com',
        'config_file was FORWARDED to SecurityConfig (domain from file)' );
    ok( $svc->security->ssl_enabled, 'ssl_enabled came from the config file' );

    # AgentBase applies the service section, with ctor params taking precedence
    # (reference agent_base.py:191-196).
    my $agent = SignalWire::Agent::AgentBase->new(
        name        => 'cfg_agent',
        config_file => $path,
    );
    is( $agent->route, '/from-config', 'route defaulted from the config service section' );
    is( $agent->host,  '127.0.0.1',    'host defaulted from the config service section' );
    is( $agent->port,  8123,           'port defaulted from the config service section' );
    is( $agent->security->domain, 'cfg.example.com',
        'AgentBase forwards config_file down to SecurityConfig' );

    my $override = SignalWire::Agent::AgentBase->new(
        name        => 'cfg_override',
        config_file => $path,
        route       => '/explicit',
        host        => '10.0.0.1',
        port        => 9999,
    );
    is( $override->route, '/explicit', 'explicit route beats the config file' );
    is( $override->host,  '10.0.0.1',  'explicit host beats the config file' );
    is( $override->port,  9999,        'explicit port beats the config file' );
};

# ------------------------------------------------------------------
# basic_auth pair -> basic_auth_user / basic_auth_password
# ------------------------------------------------------------------
subtest 'basic_auth pair forwards to the credential attributes' => sub {
    my $svc = SignalWire::SWML::Service->new(
        name       => 'ba_svc',
        basic_auth => [ 'user', 'pass' ],
    );
    is( $svc->basic_auth_user,     'user', 'basic_auth[0] -> basic_auth_user' );
    is( $svc->basic_auth_password, 'pass', 'basic_auth[1] -> basic_auth_password' );
    is_deeply( $svc->basic_auth, [ 'user', 'pass' ], 'basic_auth reads back as the pair' );

    my $agent = SignalWire::Agent::AgentBase->new(
        name       => 'ba_agent',
        basic_auth => [ 'au', 'ap' ],
    );
    is( $agent->basic_auth_user,     'au', 'AgentBase basic_auth[0] -> basic_auth_user' );
    is( $agent->basic_auth_password, 'ap', 'AgentBase basic_auth[1] -> basic_auth_password' );

    # Behavioral: the credential actually authenticates.
    ok( $agent->validate_basic_auth( 'au', 'ap' ), 'basic_auth pair really authenticates' );
    ok( !$agent->validate_basic_auth( 'au', 'wrong' ), 'wrong password rejected' );

    # Explicit split attributes still win when both are given.
    my $split = SignalWire::Agent::AgentBase->new(
        name                => 'ba_split',
        basic_auth          => [ 'pair_u', 'pair_p' ],
        basic_auth_user     => 'explicit_u',
        basic_auth_password => 'explicit_p',
    );
    is( $split->basic_auth_user, 'explicit_u',
        'explicit basic_auth_user beats the pair' );
    is( $split->basic_auth_password, 'explicit_p',
        'explicit basic_auth_password beats the pair' );
};

# ------------------------------------------------------------------
# agent_id
# ------------------------------------------------------------------
subtest 'agent_id defaults to a generated UUID and is overridable' => sub {
    my $a = SignalWire::Agent::AgentBase->new( name => 'id_test' );
    ok( defined $a->agent_id, 'agent_id auto-generated' );
    like(
        $a->agent_id,
        qr/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i,
        'auto agent_id is a UUID'
    );

    my $b = SignalWire::Agent::AgentBase->new( name => 'id_test' );
    isnt( $a->agent_id, $b->agent_id, 'each agent gets a distinct id' );

    my $c = SignalWire::Agent::AgentBase->new(
        name     => 'id_test',
        agent_id => 'custom-123',
    );
    is( $c->agent_id, 'custom-123', 'explicit agent_id honoured' );
};

# ------------------------------------------------------------------
# default_webhook_url / suppress_logs / override flags
# ------------------------------------------------------------------
subtest 'stored agent params are constructor-settable' => sub {
    my $d = SignalWire::Agent::AgentBase->new( name => 'stored_defaults' );
    is( $d->default_webhook_url, undef, 'default_webhook_url defaults to undef' );
    ok( !$d->suppress_logs,               'suppress_logs defaults false' );
    ok( !$d->enable_post_prompt_override, 'enable_post_prompt_override defaults false' );
    ok( !$d->check_for_input_override,    'check_for_input_override defaults false' );

    my $a = SignalWire::Agent::AgentBase->new(
        name                        => 'stored_set',
        default_webhook_url         => 'https://example.com/hook',
        suppress_logs               => 1,
        enable_post_prompt_override => 1,
        check_for_input_override    => 1,
    );
    is( $a->default_webhook_url, 'https://example.com/hook', 'default_webhook_url set' );
    ok( $a->suppress_logs,               'suppress_logs set' );
    ok( $a->enable_post_prompt_override, 'enable_post_prompt_override set' );
    ok( $a->check_for_input_override,    'check_for_input_override set' );
};

# ------------------------------------------------------------------
# trust_proxy_for_signature
# ------------------------------------------------------------------
subtest 'trust_proxy_for_signature defaults OFF and reaches the middleware' => sub {
    my $d = SignalWire::Agent::AgentBase->new( name => 'tp_default' );
    ok( !$d->trust_proxy_for_signature,
        'trust_proxy_for_signature defaults FALSE (proxy headers are spoofable)' );

    my $a = SignalWire::Agent::AgentBase->new(
        name                      => 'tp_on',
        trust_proxy_for_signature => 1,
    );
    ok( $a->trust_proxy_for_signature, 'trust_proxy_for_signature=1 honoured' );

    # Behavioral: with a signing key set, the signature validator reconstructs
    # the URL from X-Forwarded-* ONLY when trust_proxy_for_signature is on.
    require SignalWire::Security::WebhookMiddleware;

    my $key = 'test-signing-key';
    my %env = (
        REQUEST_METHOD  => 'POST',
        PATH_INFO       => '/swaig',
        'psgi.url_scheme' => 'http',
        HTTP_HOST       => 'internal.local',
        SERVER_NAME     => 'internal.local',
        SERVER_PORT     => 80,
        HTTP_X_FORWARDED_PROTO => 'https',
        HTTP_X_FORWARDED_HOST  => 'public.example.com',
    );

    my $trusting = SignalWire::Security::WebhookMiddleware::_reconstruct_url(
        \%env, 1, undef );
    my $untrusting = SignalWire::Security::WebhookMiddleware::_reconstruct_url(
        \%env, 0, undef );

    like( $trusting, qr{public\.example\.com},
        'trust_proxy=1 honours X-Forwarded-Host' );
    unlike( $untrusting, qr{public\.example\.com},
        'trust_proxy=0 ignores X-Forwarded-Host (spoofable)' );
};

done_testing();
