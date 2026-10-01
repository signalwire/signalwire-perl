#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON         qw(encode_json decode_json);
use MIME::Base64 qw(encode_base64);
use File::Spec;
use CompileCheck ();

# ============================================================
# 1. swaig-test script exists and is executable
# ============================================================
subtest 'swaig-test script exists' => sub {
    my $script = File::Spec->catfile( 'bin', 'swaig-test' );
    ok( -f $script, 'bin/swaig-test exists' );
    ok( -x $script, 'bin/swaig-test is executable' );
};

# ============================================================
# 2. swaig-test --help exits cleanly
# ============================================================
subtest 'swaig-test --help' => sub {
    my $output = `PERL5LIB="lib:\$PERL5LIB" $^X bin/swaig-test --help 2>&1`;
    like( $output, qr/Usage/,        'help output contains Usage' );
    like( $output, qr/--url/,        'help mentions --url' );
    like( $output, qr/--dump-swml/,  'help mentions --dump-swml' );
    like( $output, qr/--list-tools/, 'help mentions --list-tools' );
    like( $output, qr/--exec/,       'help mentions --exec' );
    like( $output, qr/--param/,      'help mentions --param' );
    like( $output, qr/--raw/,        'help mentions --raw' );
    like( $output, qr/--verbose/,    'help mentions --verbose' );
};

# ============================================================
# 3. swaig-test errors without --url
# ============================================================
subtest 'swaig-test requires --url' => sub {
    my $output = `PERL5LIB="lib:\$PERL5LIB" $^X bin/swaig-test --dump-swml 2>&1`;
    like(
        $output,
        qr/--url\s+or\s+--file\s+is\s+required/i,
        'errors when neither --url nor --file is provided'
    );
};

# ============================================================
# 4. swaig-test requires an action
# ============================================================
subtest 'swaig-test requires action' => sub {
    my $output =
        `PERL5LIB="lib:\$PERL5LIB" $^X bin/swaig-test --url http://user:pass\@localhost:9999/ 2>&1`;
    like( $output, qr/--dump-swml|--list-tools|--exec/, 'errors when no action provided' );
};

# ============================================================
# 5. Integration test: start a PSGI agent, test dump-swml via HTTP
# ============================================================
subtest 'swaig-test integration with live agent' => sub {

    # Use the agent PSGI app directly to simulate HTTP without needing a real server
    require SignalWire::Agent::AgentBase;
    my $agent = SignalWire::Agent::AgentBase->new(
        name                => 'cli_test_agent',
        route               => '/',
        basic_auth_user     => 'testuser',
        basic_auth_password => 'testpass',
    );

    $agent->prompt_add_section( 'Role', 'You are a test agent.' );
    $agent->define_tool(
        name        => 'greet',
        description => 'Greet the user',
        parameters  => {
            type       => 'object',
            properties => {
                name => { type => 'string', description => 'Name to greet' },
            },
            required => ['name'],
        },
        handler => sub {
            my ($args) = @_;
            return { response => "Hello, $args->{name}!" };
        },
    );

    my $app  = $agent->psgi_app;
    my $auth = encode_base64( 'testuser:testpass', '' );

    # Simulate GET for SWML
    my $swml_res = $app->(
        {
            REQUEST_METHOD     => 'GET',
            PATH_INFO          => '/',
            SCRIPT_NAME        => '',
            SERVER_NAME        => 'localhost',
            SERVER_PORT        => 3000,
            HTTP_AUTHORIZATION => "Basic $auth",
            'psgi.input'       => do { open my $fh, '<', \(''); $fh },
        }
    );

    is( $swml_res->[0], 200, 'SWML request returns 200' );
    my $swml_data = decode_json( $swml_res->[2][0] );
    ok( exists $swml_data->{sections}{main}, 'SWML has main section' );

    # Find SWAIG functions
    my @ai_verbs = grep { ref $_ eq 'HASH' && exists $_->{ai} } @{ $swml_data->{sections}{main} };
    ok( @ai_verbs, 'AI verb found' );
    my $funcs = $ai_verbs[0]{ai}{SWAIG}{functions} // [];
    ok( scalar @$funcs >= 1, 'at least one SWAIG function found' );
    is( $funcs->[0]{function}, 'greet', 'greet function found' );

    # Simulate POST to /swaig.
    #
    # `greet` is secure (define_tool's default), so this POST must carry a
    # valid per-call `__token` exactly as the engine's would: the credential on
    # the QUERY STRING, the call_id in the BODY — the split the rendered
    # web_hook_url emits. Minted from this agent's own SessionManager because
    # the token is HMAC-keyed by a per-process secret and expires, so it can
    # never be a literal. Without it the call is refused, which is the
    # contract, not a defect of this test.
    my $call_id = 'cli-test-call';
    my $token   = $agent->session_manager->create_tool_token( 'greet', $call_id );

    my $swaig_payload = encode_json(
        {
            function => 'greet',
            call_id  => $call_id,
            argument => {
                parsed => [ { name => 'World' } ],
            },
        }
    );

    open my $input_fh, '<', \$swaig_payload;
    my $swaig_res = $app->(
        {
            REQUEST_METHOD     => 'POST',
            PATH_INFO          => '/swaig',
            SCRIPT_NAME        => '',
            SERVER_NAME        => 'localhost',
            SERVER_PORT        => 3000,
            QUERY_STRING       => "__token=$token",
            HTTP_AUTHORIZATION => "Basic $auth",
            CONTENT_TYPE       => 'application/json',
            CONTENT_LENGTH     => length($swaig_payload),
            'psgi.input'       => $input_fh,
        }
    );

    is( $swaig_res->[0], 200, 'SWAIG exec returns 200' );
    my $swaig_body = decode_json( $swaig_res->[2][0] );
    like( $swaig_body->{response}, qr/Hello.*World/, 'SWAIG exec returns greeting' );
};

# ============================================================
# 5b. --parse-only validates args and exits without touching the network
# ============================================================
subtest 'swaig-test --parse-only' => sub {

    # Valid invocation against an UNREACHABLE url: must be instant + print
    # exactly "parse OK" + exit 0 (proves it never loads the agent / hits net).
    my $ok =
`PERL5LIB="lib:\$PERL5LIB" $^X bin/swaig-test --parse-only --url http://user:pass\@10.255.255.1:9/route --list-tools 2>&1`;
    is( $? >> 8, 0, 'valid --parse-only exits 0' );
    like( $ok, qr/^parse OK\s*$/, 'prints exactly "parse OK"' );

    # Position-independent: --parse-only trailing an --exec still recognized.
    my $trail =
`PERL5LIB="lib:\$PERL5LIB" $^X bin/swaig-test --url http://user:pass\@10.255.255.1:9/route --exec foo --param bar=1 --parse-only 2>&1`;
    is( $? >> 8, 0, 'trailing --parse-only exits 0' );
    like( $trail, qr/^parse OK\s*$/, 'position-independent parse OK' );

    # Invalid invocation exits 2 and does NOT print parse OK.
    my $bad =
`PERL5LIB="lib:\$PERL5LIB" $^X bin/swaig-test --parse-only --url http://user:pass\@localhost:9999/ 2>&1`;
    is( $? >> 8, 2, 'invalid --parse-only exits 2' );
    unlike( $bad, qr/^parse OK\s*$/m, 'no "parse OK" success line on error path' );
};

# ============================================================
# 6. Script compiles cleanly
# ============================================================
subtest 'swaig-test compiles' => sub {
    CompileCheck::compile_ok( qq{PERL5LIB="lib:\$PERL5LIB" $^X -c bin/swaig-test 2>&1},
        'bin/swaig-test compiles without errors' );
};

done_testing;
