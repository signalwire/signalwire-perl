#!/usr/bin/env perl
# Tests proving SWML::Service can host SWAIG functions and serve a non-agent
# SWML doc (e.g. ai_sidecar) without subclassing AgentBase. This is the
# contract that lets sidecar / non-agent verbs reuse the SWAIG dispatch
# surface that previously lived only on AgentBase.

use strict;
use warnings;
use Test::More;
use JSON ();
use MIME::Base64 qw(encode_base64);

use SignalWire::SWML::Service;

sub make_svc {
    return SignalWire::SWML::Service->new(
        name                => 'svc',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );
}

sub auth_header { 'Basic ' . encode_base64('u:p', '') }

sub psgi_request {
    my ($svc, $method, $path, $body, %extra) = @_;
    my $env = {
        REQUEST_METHOD => $method,
        PATH_INFO      => $path,
        CONTENT_TYPE   => 'application/json',
        HTTP_AUTHORIZATION => auth_header(),
        %extra,
    };
    if (defined $body) {
        open my $input, '<', \$body or die $!;
        $env->{'psgi.input'}    = $input;
        $env->{CONTENT_LENGTH}  = length $body;
    } else {
        open my $input, '<', \'';
        $env->{'psgi.input'}    = $input;
    }
    return $svc->to_psgi_app->($env);
}

# -----------------------------------------------------------------------
# Service gains SWAIG-hosting capability
# -----------------------------------------------------------------------

subtest 'service has SWAIG methods' => sub {
    my $svc = make_svc();
    ok($svc->can('define_tool'), 'define_tool present');
    ok($svc->can('register_swaig_function'), 'register_swaig_function present');
    ok($svc->can('define_tools'), 'define_tools present');
    ok($svc->can('on_function_call'), 'on_function_call present');
};

subtest 'define_tool registers function and dispatches via on_function_call' => sub {
    my $svc = make_svc();
    my %captured;
    $svc->define_tool(
        name        => 'lookup',
        description => 'Look it up',
        parameters  => {},
        handler     => sub {
            my ($args) = @_;
            %captured = %$args;
            return { response => 'ok' };
        },
    );
    my $result = $svc->on_function_call('lookup', { x => 'y' }, {});
    is_deeply(\%captured, { x => 'y' }, 'handler received args');
    is($result->{response}, 'ok', 'result has response key');
};

subtest 'on_function_call returns undef for unknown' => sub {
    my $svc = make_svc();
    is($svc->on_function_call('no_such_fn', {}, {}), undef, 'unknown function => undef');
};

subtest 'list_tool_names returns registered order' => sub {
    my $svc = make_svc();
    $svc->define_tool(name => 'first', description => 'f', handler => sub { {} });
    $svc->define_tool(name => 'second', description => 's', handler => sub { {} });
    is_deeply([$svc->list_tool_names], ['first', 'second'], 'order preserved');
};

# -----------------------------------------------------------------------
# /swaig endpoint
# -----------------------------------------------------------------------

subtest 'GET /swaig returns SWML' => sub {
    my $svc = make_svc();
    $svc->hangup;
    my $res = psgi_request($svc, 'GET', '/swaig');
    is($res->[0], 200, 'status 200');
    my $body = JSON::decode_json($res->[2][0]);
    ok($body->{sections}, 'has sections');
};

subtest 'POST /swaig dispatches registered handler' => sub {
    my $svc = make_svc();
    $svc->define_tool(
        name        => 'lookup_competitor',
        description => 'Look up competitor pricing.',
        parameters  => { competitor => { type => 'string' } },
        handler     => sub {
            my ($args) = @_;
            return { response => "$args->{competitor} is \$99/seat; we're \$79." };
        },
    );
    my $payload = JSON::encode_json({
        function => 'lookup_competitor',
        argument => { parsed => [{ competitor => 'ACME' }] },
        call_id  => 'c-1',
    });
    my $res = psgi_request($svc, 'POST', '/swaig', $payload);
    is($res->[0], 200, 'status 200');
    like($res->[2][0], qr/ACME/, 'response mentions ACME');
    like($res->[2][0], qr/\$79/, 'response mentions $79');
};

subtest 'POST /swaig missing function returns 400' => sub {
    my $svc = make_svc();
    my $res = psgi_request($svc, 'POST', '/swaig', '{}');
    is($res->[0], 400, 'status 400');
};

subtest 'POST /swaig invalid function name returns 400' => sub {
    my $svc = make_svc();
    my $res = psgi_request($svc, 'POST', '/swaig',
        JSON::encode_json({ function => '../etc/passwd' }));
    is($res->[0], 400, 'status 400');
};

subtest 'POST /swaig unknown function returns 404' => sub {
    my $svc = make_svc();
    my $res = psgi_request($svc, 'POST', '/swaig',
        JSON::encode_json({ function => 'nope', argument => { parsed => [{}] } }));
    is($res->[0], 404, 'status 404');
};

subtest 'unauthorized returns 401' => sub {
    my $svc = make_svc();
    my $res = $svc->to_psgi_app->({
        REQUEST_METHOD => 'POST',
        PATH_INFO      => '/swaig',
        # No HTTP_AUTHORIZATION
    });
    is($res->[0], 401, 'status 401');
};

# -----------------------------------------------------------------------
# Sidecar pattern: non-agent SWML + tool registration + (sketch) event sink
# -----------------------------------------------------------------------

subtest 'sidecar pattern emits verb and registers tool' => sub {
    my $svc = make_svc();

    # 1. Build the SWML — answer + ai_sidecar verb config.
    $svc->answer('main', {});
    $svc->document->add_verb('main', 'ai_sidecar', {
        prompt    => 'real-time copilot',
        lang      => 'en-US',
        direction => ['remote-caller', 'local-caller'],
    });
    my $rendered = $svc->document->to_hash;
    my @verbs = map { (keys %$_)[0] } @{ $rendered->{sections}{main} };
    ok(scalar(grep { $_ eq 'answer' } @verbs), 'has answer verb');
    ok(scalar(grep { $_ eq 'ai_sidecar' } @verbs), 'has ai_sidecar verb');

    # 2. Register a SWAIG tool the sidecar's LLM can call.
    $svc->define_tool(
        name        => 'lookup_competitor',
        description => 'Look up competitor pricing.',
        parameters  => { competitor => { type => 'string' } },
        handler     => sub {
            my ($args) = @_;
            return { response => "Pricing for $args->{competitor}: \$99" };
        },
    );

    # 3. Dispatch end-to-end through the public on_function_call surface.
    my $result = $svc->on_function_call(
        'lookup_competitor',
        { competitor => 'ACME' },
        {},
    );
    like($result->{response}, qr/ACME/, 'dispatched and got ACME');
};

done_testing;
