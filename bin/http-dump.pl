#!/usr/bin/env perl
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# http-dump.pl — the Perl port's HTTP dump program for the cross-port HTTP
# differ (porting-sdk/scripts/diff_port_http.py).
#
# For each http_corpus case it feeds a synthetic request into the Perl SDK's
# framework-free dispatch core (SWMLService->handle_request, extract_sip_username,
# the webhook validate middleware, and the lambda serverless adapter) and prints
# ONE JSON object mapping
#
#     case-id -> reduced-artifact
#
# to stdout, reduced to the same shape the python oracle emits. The differ
# canonicalizes both sides and byte-compares. Only stdout carries JSON.
# Mirrors signalwire-go/cmd/http-dump.
#
# The corpus sentinels (__AUTH__/__AUTH_BAD__ Basic headers, __SIG__ webhook
# signature, __REDIRECT_CB__ routing callback, __HELLO_HANDLER__ SWAIG handler,
# __JSON__: lambda body prefix) are materialized here as the oracle materializes
# them, so the interop cases are reproducible.
#
# Run from the signalwire-perl repo root:
#
#     perl -Ilib bin/http-dump.pl

use strict;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use FindBin qw($RealBin);
use File::Spec;
use JSON ();
use MIME::Base64 ();
use Digest::SHA ();

use lib File::Spec->catdir( $RealBin, File::Spec->updir, 'lib' );

use SignalWire::Agent::AgentBase;
use SignalWire::SWML::Service;
use SignalWire::Security::WebhookMiddleware ();

my $USER        = 'user';
my $PASSWORD    = 'pass';
my $SIGNING_KEY = 'PSK-fixed-signing-key';
my $WH_URL      = 'https://agent.example.com/webhook';
my $WH_BODY     = '{"event":"call.created","id":"abc"}';

sub basic_auth ( $u, $p ) {
    return 'Basic ' . MIME::Base64::encode_base64( "$u:$p", '' );
}

sub webhook_sig ( $url, $body, $key ) {
    return Digest::SHA::hmac_sha1_hex( $url . $body, $key );
}

# observe_response reduces a (status, headers, body) triple to a comparable
# artifact — the Perl mirror of diff_port_http._observe_response.
sub observe_response ( $status, $headers, $body_str, $kind ) {
    my %out = ( status => $status, header_keys => [ sort keys %$headers ] );
    $out{location}         = $headers->{Location}           if exists $headers->{Location};
    $out{www_authenticate} = $headers->{'WWW-Authenticate'} if exists $headers->{'WWW-Authenticate'};
    if ( $kind eq 'response_full' ) {
        if ( defined $body_str && length $body_str ) {
            my $parsed = eval { JSON::decode_json($body_str) };
            $out{body} = $@ ? $body_str : $parsed;
        } else {
            $out{body} = '';
        }
    }
    return \%out;
}

sub new_service {
    return SignalWire::SWML::Service->new(
        name                => 'demo',
        route               => '/swml',
        basic_auth_user     => $USER,
        basic_auth_password => $PASSWORD,
    );
}

# redirect_cb redirects one specific 'to', else passes through (undef).
sub redirect_cb ( $body, $headers ) {
    my $to = eval { $body->{call}{to} } // '';
    return '/other-route' if $to eq 'sip:redirect-me@space';
    return undef;    ## no critic (ProhibitExplicitReturnUndef)
}

sub extract_username ($body) {
    my $u = SignalWire::SWML::Service->extract_sip_username($body);
    return { username => ( defined $u && $u ne '' ) ? $u : undef };
}

sub webhook_decision ( $method, $url, $body, $headers, $key ) {
    my $rej = SignalWire::Security::WebhookMiddleware::validate(
        $method, $url, $headers, $body, signing_key => $key );
    return { decision => 'pass' } unless defined $rej;
    return { decision => 'reject', status => $rej->[0] };
}

# reduce_lambda reduces a lambda response hashref to {status, body} with the
# body parsed as JSON — mirroring the oracle's serverless_result observer.
sub reduce_lambda ($res) {
    my $body = $res->{body};
    if ( defined $body && length $body ) {
        my $parsed = eval { JSON::decode_json($body) };
        $body = $parsed unless $@;
    }
    return { status => $res->{statusCode}, body => $body };
}

sub serverless_swaig {
    my $a = SignalWire::Agent::AgentBase->new(
        name                => 'demo',
        route               => '/demo',
        basic_auth_user     => $USER,
        basic_auth_password => $PASSWORD,
    );
    $a->define_tool(
        name        => 'say_hello',
        description => 'greet',
        parameters  => {},
        handler     => sub {
            require SignalWire::SWAIG::FunctionResult;
            return SignalWire::SWAIG::FunctionResult->new('hello there');
        },
    );
    my $res = $a->handle_serverless_request(
        mode  => 'lambda',
        event => {
            rawPath => '/swaig',
            headers => {
                authorization  => basic_auth( $USER, $PASSWORD ),
                'content-type' => 'application/json',
            },
            body           => '{"function":"say_hello","argument":{"parsed":[{}]},"call_id":"c1"}',
            requestContext => { http => { method => 'POST' } },
        },
    );
    return reduce_lambda($res);
}

sub serverless_noauth {
    my $a = SignalWire::Agent::AgentBase->new(
        name                => 'demo',
        route               => '/demo',
        basic_auth_user     => $USER,
        basic_auth_password => $PASSWORD,
    );
    my $res = $a->handle_serverless_request(
        mode  => 'lambda',
        event => { rawPath => '/', headers => {}, body => undef },
    );
    return reduce_lambda($res);
}

sub main {
    my %out;

    # ---- handle_request: 200 SWML happy path ----
    {
        my $svc = new_service();
        my ( $status, $headers, $body ) = $svc->handle_request( 'GET',
            'http://localhost:3000/swml', { Authorization => basic_auth( $USER, $PASSWORD ) }, undef );
        $out{http_handle_request_200_swml} = observe_response( $status, $headers, $body, 'response_full' );
    }
    # ---- handle_request: 401 no auth ----
    {
        my $svc = new_service();
        my ( $status, $headers, $body ) =
            $svc->handle_request( 'GET', 'http://localhost:3000/swml', {}, undef );
        $out{http_handle_request_401_no_auth} = observe_response( $status, $headers, $body, 'response_full' );
    }
    # ---- handle_request: 401 bad password (status+headers only) ----
    {
        my $svc = new_service();
        my ( $status, $headers, $body ) = $svc->handle_request( 'GET',
            'http://localhost:3000/swml', { Authorization => basic_auth( $USER, 'wrong' ) }, undef );
        $out{http_handle_request_401_bad_password} =
            observe_response( $status, $headers, $body, 'response_status_headers' );
    }
    # ---- handle_request: 307 redirect via routing callback ----
    {
        my $svc = new_service();
        $svc->register_routing_callback( '/sip', \&redirect_cb );
        my ( $status, $headers, $body ) = $svc->handle_request(
            'POST', 'http://localhost:3000/swml/sip',
            { Authorization => basic_auth( $USER, $PASSWORD ) },
            { call          => { to => 'sip:redirect-me@space' } },
        );
        $out{http_handle_request_307_redirect} =
            observe_response( $status, $headers, $body, 'response_full' );
    }
    # ---- handle_request: callback returns undef -> normal 200 SWML ----
    {
        my $svc = new_service();
        $svc->register_routing_callback( '/sip', \&redirect_cb );
        my ( $status, $headers, $body ) = $svc->handle_request(
            'POST', 'http://localhost:3000/swml/sip',
            { Authorization => basic_auth( $USER, $PASSWORD ) },
            { call          => { to => 'sip:keep@space' } },
        );
        $out{http_handle_request_callback_passthrough_200} =
            observe_response( $status, $headers, $body, 'response_full' );
    }

    # ---- extract_sip_username: pure extractor ----
    $out{http_extract_sip_username_sip} =
        extract_username( { call => { to => 'sip:alice@agents.signalwire.com' } } );
    $out{http_extract_sip_username_tel}  = extract_username( { call => { to => 'tel:+15551234567' } } );
    $out{http_extract_sip_username_plain} = extract_username( { call => { to => 'support' } } );
    $out{http_extract_sip_username_missing} = extract_username( { vars => {} } );

    # ---- webhook validate ----
    $out{http_webhook_validate_ok} = webhook_decision( 'POST', $WH_URL, $WH_BODY,
        { 'x-signalwire-signature' => webhook_sig( $WH_URL, $WH_BODY, $SIGNING_KEY ) }, $SIGNING_KEY );
    $out{http_webhook_validate_bad_sig} =
        webhook_decision( 'POST', $WH_URL, $WH_BODY, { 'x-signalwire-signature' => 'deadbeef' x 5 },
        $SIGNING_KEY );
    $out{http_webhook_validate_missing_sig} =
        webhook_decision( 'POST', $WH_URL, $WH_BODY, {}, $SIGNING_KEY );
    $out{http_webhook_validate_twilio_alias} = webhook_decision( 'POST', $WH_URL, $WH_BODY,
        { 'x-twilio-signature' => webhook_sig( $WH_URL, $WH_BODY, $SIGNING_KEY ) }, $SIGNING_KEY );

    # ---- serverless (lambda) ----
    $out{http_serverless_lambda_swaig}       = serverless_swaig();
    $out{http_serverless_lambda_noauth_401} = serverless_noauth();

    print JSON->new->canonical->encode( \%out ), "\n";
    return 0;
}

exit main();
