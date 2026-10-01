#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON         qw(encode_json decode_json);
use MIME::Base64 qw(encode_base64);

# =============================================================================
# Behavioral contract #6 — SIP routing DISPATCH over the served path.
#
# Python: enable_sip_routing registers a routing callback at /sip; the served
# /sip endpoint invokes it (reachable via #61's handle_request wiring). The
# callback extract_sip_username(body)s the caller, consults the registered
# usernames, and routes.
#
# Before this fix the SIP username mapping was stored (register_sip_username /
# sip_usernames) but NOT consulted: enable_sip_routing registered no callback,
# and the served PSGI app only routed the MAIN path through handle_request, so a
# POST to /sip fell through to a 404.
#
# These tests POST a SIP-shaped body to the ACTUAL served /sip endpoint (the
# coderef serve() hands Plack) and assert the callback fires + the username is
# extracted + the request is routed.
# =============================================================================

use SignalWire::Agent::AgentBase;

sub make_env {
    my (%o) = @_;
    my $body = $o{body} // '';
    open my $fh, '<', \$body or die "cannot open in-memory body: $!";
    return {
        REQUEST_METHOD => $o{method} // 'POST',
        PATH_INFO      => $o{path}   // '/sip',
        SCRIPT_NAME    => '',
        SERVER_NAME    => 'localhost',
        SERVER_PORT    => 3000,
        QUERY_STRING   => '',
        CONTENT_LENGTH => length($body),
        CONTENT_TYPE   => 'application/json',
        ( $o{auth} ? ( HTTP_AUTHORIZATION => "Basic $o{auth}" ) : () ),
        'psgi.input'      => $fh,
        'psgi.errors'     => \*STDERR,
        'psgi.url_scheme' => 'http',
    };
}

sub psgi_parts {
    my ($res) = @_;
    my %h     = @{ $res->[1] };
    my $body  = join '', @{ $res->[2] };
    return ( $res->[0], \%h, $body );
}

my $AUTH = encode_base64( 'u:p', '' );

subtest 'served /sip: callback fires, username extracted, registered -> handled here (200)' => sub {
    my $fired;
    my $seen_username;

    # A subclass-style agent that records that the SIP callback ran and what
    # username it extracted (proving the mapping was actually consulted).
    my $agent = SignalWire::Agent::AgentBase->new(
        name                => 'sipdesk',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );
    $agent->enable_sip_routing( auto_map => 0 );    # register the /sip callback
    $agent->register_sip_username('support');

    # Wrap _sip_routing_callback to observe it firing without changing behavior.
    my $orig = $agent->can('_sip_routing_callback');

    # Wrap a real SDK method to observe it firing without changing behaviour;
    # 'redefine' is exactly the warning this deliberate override raises.
    no warnings 'redefine';    ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    local *SignalWire::Agent::AgentBase::_sip_routing_callback = sub {
        my ( $self, $body, $headers ) = @_;
        $fired         = 1;
        $seen_username = $self->extract_sip_username($body);
        return $orig->( $self, $body, $headers );
    };

    my $app = $agent->psgi_app;
    my ( $status, undef, $body ) = psgi_parts(
        $app->(
            make_env(
                path => '/sip',
                auth => $AUTH,
                body => encode_json( { call => { from => 'sip:support@example.com' } } ),
            )
        )
    );

    ok( $fired, 'the SIP routing callback fired on the served /sip POST' );
    is( $seen_username, 'support', 'username extracted from the SIP body' );

    # Registered with this agent -> callback returns undef -> agent renders its
    # own SWML (200), not a 404 and not a redirect.
    is( $status, 200, 'registered username handled here: 200 SWML (not a 404)' );
    my $doc = eval { decode_json($body) };
    ok( ref $doc eq 'HASH', 'served /sip renders a SWML document' );
};

subtest 'served /sip: unregistered username routes elsewhere (307 via _on_sip_request)' => sub {
    my $routed_username;

    my $agent = SignalWire::Agent::AgentBase->new(
        name                => 'sipdesk2',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );
    $agent->enable_sip_routing( auto_map => 0 );
    $agent->register_sip_username('sales');

    # A router-style override: an unregistered username is redirected to the
    # agent that owns it.
    # Override a real SDK method to exercise router-style redirection;
    # 'redefine' is exactly the warning this deliberate override raises.
    no warnings 'redefine';    ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    local *SignalWire::Agent::AgentBase::_on_sip_request = sub {
        my ( $self, $username, $body, $headers ) = @_;
        $routed_username = $username;
        return "https://other.example/agents/$username";
    };

    my $app = $agent->psgi_app;
    my ( $status, $headers ) = psgi_parts(
        $app->(
            make_env(
                path => '/sip',
                auth => $AUTH,
                body => encode_json( { call => { from => 'sip:billing@example.com' } } ),
            )
        )
    );

    is( $routed_username, 'billing', 'the unregistered username was extracted and dispatched' );
    is( $status,          307,       'served /sip redirects an unregistered username (307)' );
    is(
        $headers->{Location},
        'https://other.example/agents/billing',
        'Location carries the routed URL'
    );
};

subtest 'served /sip: 401 on bad auth through the served endpoint' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(
        name                => 'sipdesk3',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );
    $agent->enable_sip_routing( auto_map => 0 );

    my $app = $agent->psgi_app;
    my ($status) = psgi_parts(
        $app->(
            make_env(
                path => '/sip',
                auth => encode_base64( 'u:wrong', '' ),
                body => encode_json( { call => { from => 'sip:x@example.com' } } ),
            )
        )
    );
    is( $status, 401, 'bad auth -> 401 through the served /sip path' );
};

done_testing;
