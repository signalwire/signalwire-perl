#!/usr/bin/env perl
# SWAIG `__token` ENFORCEMENT — the security decision, on EVERY transport.
#
# A tool registered with `secure => 1` (define_tool's DEFAULT) REQUIRES a valid
# per-call `__token`. Absent, forged, or unvalidatable => REFUSE. This is the
# whole point of the flag: "if it's secure it needs to actually be secure".
#
# Python parity (swml_service.py `_swaig_validate_token`, the transport-agnostic
# core; agent_base.py's override is the real implementation):
#
#     valid token     -> handler RUNS,               200
#     forged token    -> handler does NOT run, REFUSED, 200 + FunctionResult
#     absent token    -> handler does NOT run, REFUSED   (fail-CLOSED)
#     call_id absent  -> REFUSED — a token is only checkable against a call_id,
#                        so a missing one is UNVALIDATED, never a bypass
#     insecure tool   -> RUNS ungated in ALL of the above
#
# THE REFUSAL IS A 200 + FunctionResult BODY, NOT AN HTTP ERROR STATUS. The
# engine (mod_openai) has no handling for a SWAIG refusal status, so the tool
# reports it cannot execute and the model relays that to the caller.
#
# TRANSPORTS COVERED — perl has THREE distinct paths that reach
# on_function_call, and they do NOT share a dispatcher. Fixing one would have
# compiled, read correctly, and enforced nothing:
#
#   1. AgentBase::_handle_swaig — the HTTP/PSGI endpoint agents actually serve
#      from. AgentBase's own PSGI router sends POST $route/swaig HERE, so
#      SWMLService::_handle_swaig_request was never on this path at all.
#   2. SWMLService::_handle_swaig_request -> swaig_pre_dispatch — reached by a
#      bare SWMLService host. The `cgi`, `google_cloud_function` and
#      `azure_function` serverless modes all funnel through psgi_app.
#   3. AgentBase::_lambda_swaig_response — lambda mode handles its event
#      DIRECTLY, never routing through the PSGI app, so it never consulted the
#      hook either. Reached from TWO call sites (the /swaig endpoint and
#      path-based function routing), both exercised below.
#
# Regression lock: before this, `swaig_pre_dispatch` was a live no-op with NO
# override anywhere in the tree, and neither the HTTP endpoint agents serve from
# nor the lambda path consulted it — so perl validated the `__token` on NO
# transport. It minted tokens onto the wire and then accepted any request
# regardless.

use strict;
use warnings;
use Test::More;
use JSON ();
use MIME::Base64 ();

use SignalWire::Agent::AgentBase;

my $USER     = 'u';
my $PASSWORD = 'p';
my $CALL_ID  = 'call-token-enforcement-t101';

my $REFUSAL = "I'm sorry, the security token for this function is invalid "
    . "or expired. I cannot execute this action.";

# An agent with one SECURE tool (the default) and one explicitly INSECURE tool.
# Both handlers return a distinctive response so "did the handler run?" is a
# direct observation, not an inference from a status code.
sub build_agent {
    my $a = SignalWire::Agent::AgentBase->new(
        name                => 'tok-agent',
        route               => '/tok',
        basic_auth_user     => $USER,
        basic_auth_password => $PASSWORD,
    );
    $a->define_tool(
        name        => 'secure_tool',
        description => 'secure by default',
        parameters  => {},
        handler     => sub { return { response => 'SECURE RAN' } },
    );
    $a->define_tool(
        name        => 'insecure_tool',
        description => 'explicitly insecure',
        parameters  => {},
        secure      => 0,
        handler     => sub { return { response => 'INSECURE RAN' } },
    );
    return $a;
}

sub basic_auth_header {
    return 'Basic ' . MIME::Base64::encode_base64( "$USER:$PASSWORD", '' );
}

# A structurally well-formed but WRONG token: mint a real one for a DIFFERENT
# call_id, so it survives base64/field-count parsing and fails only on the
# signature/call_id check. A garbage string would pass the test for the wrong
# reason (rejected as unparseable rather than as invalid).
sub forged_token {
    my ( $agent, $fn ) = @_;
    return $agent->session_manager->create_tool_token( $fn, 'some-other-call' );
}

sub valid_token {
    my ( $agent, $fn, $call_id ) = @_;
    return $agent->session_manager->create_tool_token( $fn, $call_id // $CALL_ID );
}

# ---------------------------------------------------------------------------
# Transport 1 — HTTP / PSGI (also the cgi / gcf / azure serverless modes)
# ---------------------------------------------------------------------------

# Drive a SWAIG POST through the real PSGI app: token on the QUERY STRING,
# call_id in the POST BODY. That split is the contract, not an artifact — it is
# exactly what _build_webhook_url emits and what the engine posts back.
sub http_swaig {
    my ( $agent, %args ) = @_;
    my $fn      = $args{function};
    my $token   = $args{token};
    my $call_id = $args{call_id};

    my %payload = ( function => $fn, argument => { parsed => [ {} ] } );
    $payload{call_id} = $call_id if defined $call_id;
    my $body = JSON::encode_json( \%payload );

    my $query = defined $token ? ( '__token=' . $token ) : '';

    open my $input, '<', \$body or die "cannot open body handle: $!";
    my $env = {
        PATH_INFO      => '/tok/swaig',
        REQUEST_METHOD => 'POST',
        QUERY_STRING   => $query,
        CONTENT_TYPE   => 'application/json',
        HTTP_AUTHORIZATION => basic_auth_header(),
        'psgi.input'   => $input,
        'psgi.errors'  => \*STDERR,
    };

    my ( $status, $headers, $res_body ) = @{ $agent->psgi_app->($env) };
    my $joined = ref $res_body eq 'ARRAY' ? join( '', @$res_body ) : "$res_body";
    my $decoded = eval { JSON::decode_json($joined) };
    return ( $status, $decoded, $joined );
}

subtest 'HTTP: secure tool REQUIRES a valid __token' => sub {
    subtest 'valid token -> handler RUNS, 200' => sub {
        my $agent = build_agent();
        my ( $status, $body ) = http_swaig(
            $agent,
            function => 'secure_tool',
            token    => valid_token( $agent, 'secure_tool' ),
            call_id  => $CALL_ID,
        );
        is( $status, 200, 'valid token -> 200' );
        is( $body->{response}, 'SECURE RAN',
            'the secure handler RAN — a fix that refuses everything is not a fix' );
    };

    subtest 'forged token -> REFUSED, handler does NOT run, 200' => sub {
        my $agent = build_agent();
        my ( $status, $body ) = http_swaig(
            $agent,
            function => 'secure_tool',
            token    => forged_token( $agent, 'secure_tool' ),
            call_id  => $CALL_ID,
        );
        is( $status, 200, 'refusal is a 200, NOT an HTTP error status' );
        is( $body->{response}, $REFUSAL, 'refusal FunctionResult body' );
        isnt( $body->{response}, 'SECURE RAN', 'the secure handler did NOT run' );
    };

    subtest 'absent token -> REFUSED (fail-CLOSED)' => sub {
        my $agent = build_agent();
        my ( $status, $body ) = http_swaig(
            $agent,
            function => 'secure_tool',
            token    => undef,
            call_id  => $CALL_ID,
        );
        is( $status, 200, 'refusal is a 200' );
        is( $body->{response}, $REFUSAL,
            'omitting the credential is refused exactly like presenting a wrong one' );
    };

    subtest 'call_id absent -> REFUSED (unvalidated, never a bypass)' => sub {
        my $agent = build_agent();
        # A REAL token for the real call, but the body carries no call_id — so
        # there is nothing to bind it to. Dropping the call_id must not be a
        # way to turn a secure tool into an open one.
        my ( $status, $body ) = http_swaig(
            $agent,
            function => 'secure_tool',
            token    => valid_token( $agent, 'secure_tool' ),
            call_id  => undef,
        );
        is( $status, 200, 'refusal is a 200' );
        is( $body->{response}, $REFUSAL,
            'a token with no call_id to check against is UNVALIDATED, so refused' );
    };
};

subtest 'HTTP: insecure tool runs UNGATED in every case' => sub {
    my @cases = (
        [ 'valid token',    sub { valid_token( $_[0], 'insecure_tool' ) },  $CALL_ID ],
        [ 'forged token',   sub { forged_token( $_[0], 'insecure_tool' ) }, $CALL_ID ],
        [ 'absent token',   sub { undef },                                  $CALL_ID ],
        [ 'no call_id',     sub { undef },                                  undef ],
    );
    for my $case (@cases) {
        my ( $label, $tokgen, $call_id ) = @$case;
        my $agent = build_agent();
        my ( $status, $body ) = http_swaig(
            $agent,
            function => 'insecure_tool',
            token    => $tokgen->($agent),
            call_id  => $call_id,
        );
        is( $status, 200, "insecure/$label -> 200" );
        is( $body->{response}, 'INSECURE RAN',
            "insecure/$label -> handler RAN ungated" );
    }
};

# ---------------------------------------------------------------------------
# Transport 2 — LAMBDA DIRECT (never touches swaig_pre_dispatch)
# ---------------------------------------------------------------------------

# The token rides `queryStringParameters` (the parsed mapping both the REST API
# v1 and HTTP API v2 lambda payload shapes provide); the call_id rides the POST
# body, read back as raw_data.call_id. Identical split to the HTTP transport.
sub lambda_swaig {
    my ( $agent, %args ) = @_;
    my $fn      = $args{function};
    my $token   = $args{token};
    my $call_id = $args{call_id};

    my %payload = ( function => $fn, argument => { parsed => [ {} ] } );
    $payload{call_id} = $call_id if defined $call_id;

    my %event = (
        rawPath => '/swaig',
        headers => { authorization => basic_auth_header() },
        body    => JSON::encode_json( \%payload ),
    );
    $event{queryStringParameters} = { __token => $token } if defined $token;

    my $res = $agent->handle_serverless_request( mode => 'lambda', event => \%event );
    my $decoded = eval { JSON::decode_json( $res->{body} ) };
    return ( $res->{statusCode}, $decoded, $res->{body} );
}

subtest 'LAMBDA: secure tool REQUIRES a valid __token' => sub {
    subtest 'valid token -> handler RUNS, 200' => sub {
        my $agent = build_agent();
        my ( $status, $body ) = lambda_swaig(
            $agent,
            function => 'secure_tool',
            token    => valid_token( $agent, 'secure_tool' ),
            call_id  => $CALL_ID,
        );
        is( $status, 200, 'valid token -> 200' );
        is( $body->{response}, 'SECURE RAN', 'the secure handler RAN on lambda' );
    };

    subtest 'forged token -> REFUSED, handler does NOT run, 200' => sub {
        my $agent = build_agent();
        my ( $status, $body ) = lambda_swaig(
            $agent,
            function => 'secure_tool',
            token    => forged_token( $agent, 'secure_tool' ),
            call_id  => $CALL_ID,
        );
        is( $status, 200, 'refusal is a 200, NOT an HTTP error status' );
        is( $body->{response}, $REFUSAL, 'refusal FunctionResult body' );
        isnt( $body->{response}, 'SECURE RAN', 'the secure handler did NOT run' );
    };

    subtest 'absent token -> REFUSED (fail-CLOSED)' => sub {
        my $agent = build_agent();
        my ( $status, $body ) = lambda_swaig(
            $agent,
            function => 'secure_tool',
            token    => undef,
            call_id  => $CALL_ID,
        );
        is( $status, 200, 'refusal is a 200' );
        is( $body->{response}, $REFUSAL,
            'the lambda path is NOT a weaker transport than HTTP' );
    };

    subtest 'call_id absent -> REFUSED (unvalidated, never a bypass)' => sub {
        my $agent = build_agent();
        my ( $status, $body ) = lambda_swaig(
            $agent,
            function => 'secure_tool',
            token    => valid_token( $agent, 'secure_tool' ),
            call_id  => undef,
        );
        is( $status, 200, 'refusal is a 200' );
        is( $body->{response}, $REFUSAL,
            'a token with no call_id to check against is UNVALIDATED, so refused' );
    };
};

subtest 'LAMBDA: insecure tool runs UNGATED in every case' => sub {
    my @cases = (
        [ 'valid token',  sub { valid_token( $_[0], 'insecure_tool' ) },  $CALL_ID ],
        [ 'forged token', sub { forged_token( $_[0], 'insecure_tool' ) }, $CALL_ID ],
        [ 'absent token', sub { undef },                                  $CALL_ID ],
        [ 'no call_id',   sub { undef },                                  undef ],
    );
    for my $case (@cases) {
        my ( $label, $tokgen, $call_id ) = @$case;
        my $agent = build_agent();
        my ( $status, $body ) = lambda_swaig(
            $agent,
            function => 'insecure_tool',
            token    => $tokgen->($agent),
            call_id  => $call_id,
        );
        is( $status, 200, "insecure/$label -> 200" );
        is( $body->{response}, 'INSECURE RAN',
            "insecure/$label -> handler RAN ungated" );
    }
};

# ---------------------------------------------------------------------------
# The path-routed lambda shape (/say_hello rather than /swaig) reaches the SAME
# executor. Covered explicitly because it is a SECOND call site of
# _lambda_swaig_response and a fix applied to only one of them would leave a
# live bypass.
# ---------------------------------------------------------------------------
subtest 'LAMBDA path-routed function is gated too' => sub {
    my $agent = build_agent();
    my $res   = $agent->handle_serverless_request(
        mode  => 'lambda',
        event => {
            rawPath => '/secure_tool',
            headers => { authorization => basic_auth_header() },
            body    => JSON::encode_json(
                { function => 'secure_tool', argument => { parsed => [ {} ] }, call_id => $CALL_ID }
            ),
        },
    );
    is( $res->{statusCode}, 200, 'refusal is a 200' );
    my $body = JSON::decode_json( $res->{body} );
    is( $body->{response}, $REFUSAL,
        'path-based routing is not a bypass of the token check' );
};

# ---------------------------------------------------------------------------
# The transport-agnostic core itself: three nullable strings in, nullable out.
# Mirrors the reference's `_swaig_validate_token(function_name, token, call_id)`
# so every transport reaches the IDENTICAL decision and none re-implements it.
# ---------------------------------------------------------------------------
subtest '_swaig_validate_token: the shared decision core' => sub {
    my $agent = build_agent();

    is( $agent->_swaig_validate_token( 'secure_tool', valid_token( $agent, 'secure_tool' ), $CALL_ID ),
        undef, 'valid -> undef (proceed)' );

    my $refusal = $agent->_swaig_validate_token( 'secure_tool',
        forged_token( $agent, 'secure_tool' ), $CALL_ID );
    is( ref $refusal, 'HASH', 'forged -> a refusal hashref' );
    is( $refusal->{response}, $REFUSAL, 'refusal carries the FunctionResult response' );

    isnt( $agent->_swaig_validate_token( 'secure_tool', undef, $CALL_ID ), undef,
        'absent token -> refusal' );
    isnt( $agent->_swaig_validate_token( 'secure_tool', valid_token( $agent, 'secure_tool' ), undef ),
        undef, 'absent call_id -> refusal' );

    is( $agent->_swaig_validate_token( 'insecure_tool', undef, undef ), undef,
        'insecure tool -> undef (proceed) even with nothing at all' );

    is( $agent->_swaig_validate_token( 'no_such_tool', undef, undef ), undef,
        'unregistered function -> undef; dispatch decides, not the token check' );
};

done_testing();
