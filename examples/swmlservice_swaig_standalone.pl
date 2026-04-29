#!/usr/bin/env perl
# swmlservice_swaig_standalone.pl
#
# Proves that SignalWire::SWML::Service - by itself, with NO AgentBase -
# can host SWAIG functions and serve them on its own /swaig endpoint.
#
# This is the path you take when you want a SWAIG-callable HTTP service
# that isn't an <ai> agent: the SWAIG verb is a generic LLM-tool surface
# and SWML::Service is the host. AgentBase is just an SWML::Service
# subclass that *also* layers in prompts, AI config, dynamic config, and
# token validation.
#
# Run:
#     perl -Ilib examples/swmlservice_swaig_standalone.pl
#
# Then exercise the endpoints:
#     curl -u user:pass http://localhost:3000/standalone
#     curl -u user:pass http://localhost:3000/standalone/swaig \
#         -H 'Content-Type: application/json' \
#         -d '{"function":"lookup_competitor","argument":{"parsed":[{"competitor":"ACME"}]}}'
#
# Or drive it through the bundled CLI without standing up the server:
#     bin/swaig-test --url http://user:pass@localhost:3000/standalone --list-tools
#     bin/swaig-test --url http://user:pass@localhost:3000/standalone \
#         --exec lookup_competitor --param competitor=ACME

use strict;
use warnings;
use lib 'lib';
use SignalWire::SWML::Service;

sub build_service {
    my %opts = @_;
    my %args = (
        name                => 'standalone-swaig',
        route               => '/standalone',
        basic_auth_user     => $opts{user} // 'user',
        basic_auth_password => $opts{pass} // 'pass',
    );
    # Only override host/port when caller provides one - otherwise the
    # Service constructor honors SWML_HOST / SWML_PORT environment vars.
    $args{host} = $opts{host} if defined $opts{host};
    $args{port} = $opts{port} if defined $opts{port};
    my $svc = SignalWire::SWML::Service->new(%args);

    # 1. Build a minimal SWML document. Any verbs are fine - the SWAIG
    #    HTTP surface is independent of what the document contains.
    $svc->document->add_verb('main', 'answer', {});
    $svc->document->add_verb('main', 'hangup', {});

    # 2. Register a SWAIG function. define_tool() lives on SWML::Service,
    #    not just AgentBase. The handler receives parsed arguments plus
    #    the raw POST body.
    $svc->define_tool(
        name        => 'lookup_competitor',
        description => 'Look up competitor pricing by company name. Use this when '
                     . "the user asks how a competitor's price compares to ours.",
        parameters  => {
            type       => 'object',
            properties => {
                competitor => {
                    type        => 'string',
                    description => "The competitor's company name, e.g. 'ACME'.",
                },
            },
            required   => ['competitor'],
        },
        handler => sub {
            my ($args, $raw_data) = @_;
            my $competitor = $args->{competitor} // '<unknown>';
            return {
                response => "$competitor pricing is \$99/seat; we're \$79/seat.",
            };
        },
    );

    return $svc;
}

# Top-level: only run the server when executed directly. `caller` is
# false in script context, true when this file is loaded via `require`
# (e.g. by tests).
unless (caller) {
    my $svc = build_service();
    print "SWML::Service standalone SWAIG host\n";
    print "Route:      " . $svc->route . "\n";
    print "Basic auth: " . $svc->basic_auth_user . ":" . $svc->basic_auth_password . "\n";
    print "SWAIG URL:  http://"
        . $svc->basic_auth_user . ":" . $svc->basic_auth_password
        . "\@" . $svc->host . ":" . $svc->port . $svc->route . "\n\n";

    require Plack::Runner;
    my $runner = Plack::Runner->new;
    $runner->parse_options(
        '--host'   => $svc->host,
        '--port'   => $svc->port,
        '--server' => 'HTTP::Server::PSGI',
    );
    $runner->run($svc->to_psgi_app);
}

1;
