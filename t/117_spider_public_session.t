#!/usr/bin/env perl
# SpiderSkill.session -- the public-only HTTP session (python reference:
# skills/spider/skill.py `self.session = _PublicSession()`,
# utils/url_validator._PublicSession). Every request and redirect hop is
# checked; direct connections are pinned to a checked address; environment
# proxies are ignored unless SWML_URL_FETCH_USE_PROXY is set.
use strict;
use warnings;
use Test::More;

use SignalWire::Agent::AgentBase;
use SignalWire::Skills::SkillRegistry;
use SignalWire::Utils::UrlValidator;
use SignalWire::Utils::UrlValidator::PublicSession;

delete local $ENV{SWML_ALLOW_PRIVATE_URLS};
delete local $ENV{SWML_URL_FETCH_USE_PROXY};
delete local $ENV{SPIDER_BASE_URL};

# Deterministic DNS: public.example / hop.example resolve public, inside.example
# resolves to the cloud-metadata address.
my %DNS = (
    'public.example' => ['93.184.216.34'],
    'hop.example'    => ['93.184.216.35'],
    'inside.example' => ['169.254.169.254'],
);
local $SignalWire::Utils::UrlValidator::_RESOLVER = sub {
    my ($host) = @_;
    return $DNS{$host} if $DNS{$host};
    return [$host]     if SignalWire::Utils::UrlValidator::_is_ip_literal($host);
    return;
};

sub new_session {
    my (%args) = @_;
    return SignalWire::Utils::UrlValidator::PublicSession->new(%args);
}

subtest 'SpiderSkill.session is the public session, configured from params' => sub {
    my $factory = SignalWire::Skills::SkillRegistry->get_factory('spider');
    my $agent   = SignalWire::Agent::AgentBase->new(
        name                => 'sp',
        basic_auth_user     => 'u',
        basic_auth_password => 'p'
    );
    my $skill   = $factory->new( agent => $agent, params => {} );
    my $session = $skill->session;
    isa_ok( $session, 'SignalWire::Utils::UrlValidator::PublicSession' );
    isa_ok( $session, 'HTTP::Tiny' );
    is( $session->agent,   'Spider/1.0 (SignalWire AI Agent)', 'reference default user agent' );
    is( $session->timeout, 5,                                  'reference default timeout' );
    ok( $session->verify_SSL,     'TLS verification on' );
    ok( !$session->allow_private, 'private addresses refused' );
    is( $skill->session, $session, 'one session per skill (connection reuse)' );

    my $custom = $factory->new(
        agent  => $agent,
        params => { user_agent => 'Bot/2', headers => { 'X-Key' => 'k' }, timeout => 9 },
    )->session;
    is( $custom->agent,   'Bot/2', 'user_agent param' );
    is( $custom->timeout, 9,       'timeout param' );
    is_deeply(
        $custom->default_headers,
        { 'X-Key' => 'k', 'User-Agent' => 'Bot/2' },
        'headers param plus User-Agent'
    );

    local $ENV{SPIDER_BASE_URL} = 'http://127.0.0.1:1';
    ok( $factory->new( agent => $agent, params => {} )->session->allow_private,
        'an operator SPIDER_BASE_URL allows the private base' );
};

subtest 'a private or internal URL is refused before any connection' => sub {
    my $sent = 0;
    local *HTTP::Tiny::request =
        sub { $sent++; return { status => 200, success => 1, content => 'x' } };
    my $session = new_session();
    for my $url (
        'http://127.0.0.1/',      'http://169.254.169.254/latest/meta-data',
        'http://inside.example/', 'http://10.1.2.3/x',
        'ftp://public.example/'
        )
    {
        my $res = $session->get($url);
        is( $res->{status}, 599, "$url -> 599" );
        like( $res->{content}, qr/is private, internal or invalid/, "$url -> reason" );
    }
    is( $sent, 0, 'nothing was sent' );

    my $pw = $session->get('http://user:secret@10.0.0.1/');
    unlike( $pw->{content}, qr/secret/, 'credentials redacted in the reason' );

    local $ENV{SWML_ALLOW_PRIVATE_URLS} = '1';
    is( new_session()->get('http://127.0.0.1/')->{status},
        200, 'SWML_ALLOW_PRIVATE_URLS allows it' );
    delete local $ENV{SWML_ALLOW_PRIVATE_URLS};
    is( new_session( allow_private => 1 )->get('http://127.0.0.1/')->{status},
        200, 'allow_private allows it' );
};

subtest 'redirects are followed hop by hop, each hop checked' => sub {
    my @calls;
    my %routes = (
        'https://public.example/start' =>
            { status => 302, success => '', headers => { location => 'https://hop.example/next' } },
        'https://hop.example/next' =>
            { status => 200, success => 1, headers => {}, content => 'landed' },
        'https://public.example/evil' => {
            status  => 301,
            success => '',
            headers => { location => 'http://inside.example/latest/meta-data' }
        },
        'https://public.example/rel' =>
            { status => 302, success => '', headers => { location => '/next2' } },
        'https://public.example/next2' =>
            { status => 200, success => 1, headers => {}, content => 'rel' },
    );
    local *HTTP::Tiny::request = sub {
        my ( $self, $method, $url, $args ) = @_;
        push @calls, [ $method, $url, $args->{peer} ];
        return { %{ $routes{$url} // { status => 404, success => '', headers => {} } },
            url => $url };
    };

    my $session = new_session();
    my $res     = $session->get('https://public.example/start');
    is( $res->{status},                200,      'redirect followed' );
    is( $res->{content},               'landed', 'to the target' );
    is( scalar @{ $res->{redirects} }, 1,        'hop recorded in redirects' );
    is_deeply(
        [ map { $_->[1] } @calls ],
        [ 'https://public.example/start', 'https://hop.example/next' ],
        'each hop requested once'
    );
    is( ref $calls[0][2], 'CODE', 'direct connection pinned through the peer hook' );

    @calls = ();
    $res   = $session->get('https://public.example/evil');
    is( $res->{status}, 599, 'redirect to an internal address refused' );
    like( $res->{content}, qr/inside\.example.*private, internal or invalid/, 'with the reason' );
    is( scalar @calls, 1, 'the internal hop was never requested' );

    is( $session->get('https://public.example/rel')->{content},
        'rel', 'relative Location resolved' );

    my $capped = new_session( max_redirect => 0 )->get('https://public.example/start');
    is( $capped->{status}, 302, 'max_redirect bounds the hops' );
};

subtest 'the peer hook refuses a rebinding answer' => sub {
    is( SignalWire::Utils::UrlValidator::PublicSession::_checked_peer('public.example'),
        '93.184.216.34', 'connects to the checked address' );
    my $err = do {
        local $@;
        eval { SignalWire::Utils::UrlValidator::PublicSession::_checked_peer('inside.example') };
        $@;
    };
    like(
        $err,
        qr/Refused to connect to inside\.example: 169\.254\.169\.254/,
        'private peer refused'
    );
};

subtest 'environment proxies are ignored unless allowed' => sub {
    local $ENV{http_proxy}  = 'http://proxy.example:3128';
    local $ENV{https_proxy} = 'http://proxy.example:3128';
    my $direct = new_session();
    ok( !defined $direct->{http_proxy} && !defined $direct->{https_proxy},
        'direct: proxies dropped' );

    local $ENV{SWML_URL_FETCH_USE_PROXY} = 'true';
    my $proxied = new_session();
    is( $proxied->{http_proxy}, 'http://proxy.example:3128',
        'SWML_URL_FETCH_USE_PROXY keeps them' );
};

subtest '_address_is_blocked' => sub {
    my $blocked = \&SignalWire::Utils::UrlValidator::_address_is_blocked;
    ok( $blocked->('10.0.0.1'),                            'private v4' );
    ok( $blocked->('0:0:0:0:0:0:0:0'),                     'unspecified v6' );
    ok( $blocked->('0:0:0:0:0:ffff:a9fe:a9fe'),            'v4-mapped metadata address' );
    ok( !$blocked->('93.184.216.34'),                      'public v4' );
    ok( !$blocked->('2606:2800:220:1:248:1893:25c8:1946'), 'public v6' );
};

done_testing;
