package SignalWire::Agents;
use strict;
use warnings;

our $VERSION = '1.1.0';

use SignalWire::Agents::Logging;
use SignalWire::Agents::SWML::Document;
use SignalWire::Agents::SWML::Schema;
use SignalWire::Agents::SWML::Service;
use SignalWire::Agents::SWAIG::FunctionResult;
use SignalWire::Agents::Security::SessionManager;
use SignalWire::Agents::DataMap;
use SignalWire::Agents::Contexts;

1;

__END__

=head1 NAME

SignalWire::Agents - SDK for building AI agents as microservices on SignalWire

=head1 SYNOPSIS

    use SignalWire::Agents::Agent::AgentBase;

    my $agent = SignalWire::Agents::Agent::AgentBase->new(
        name  => 'my_agent',
        route => '/agent',
        host  => '0.0.0.0',
        port  => 3000,
    );

    # Build structured prompts
    $agent->prompt_add_section('Role', 'You are a helpful assistant.');
    $agent->prompt_add_section('Rules',
        body   => ['Be concise', 'Be friendly'],
        bullet => '*',
    );

    # Define tools with local handlers
    $agent->define_tool(
        name        => 'get_time',
        description => 'Get the current time',
        parameters  => { type => 'object', properties => {} },
        handler     => sub {
            my ($args, $raw) = @_;
            require SignalWire::Agents::SWAIG::FunctionResult;
            return SignalWire::Agents::SWAIG::FunctionResult->new(
                "The time is " . localtime
            );
        },
    );

    # Add built-in skills
    $agent->add_skill('datetime');
    $agent->add_skill('math');

    # Start the HTTP server
    $agent->run();

=head1 DESCRIPTION

SignalWire::Agents is the Perl port of the SignalWire AI Agents SDK. It provides
a framework for building, deploying, and managing AI agents as self-contained
web applications that expose HTTP endpoints to interact with the SignalWire
platform.

=head2 Key Features

=over 4

=item * B<Prompt Object Model> - Structured, section-based prompt management

=item * B<Local Tools> - Define tool handlers that execute in your agent process

=item * B<DataMap Tools> - Server-side API integration without webhooks

=item * B<Skills System> - Modular, reusable capabilities (datetime, math, web search, etc.)

=item * B<Contexts> - Branching workflow management for multi-step conversations

=item * B<Prefabs> - Ready-made agent types (InfoGatherer, Survey, Receptionist, etc.)

=item * B<Multi-Agent Server> - Host multiple agents in a single process

=item * B<RELAY Client> - Real-time WebSocket call control

=item * B<REST Client> - Synchronous HTTP API for SignalWire resources

=back

=head1 CORE MODULES

=over 4

=item L<SignalWire::Agents::Agent::AgentBase> - Base class for all AI agents

=item L<SignalWire::Agents::SWML::Service> - SWML document management

=item L<SignalWire::Agents::SWAIG::FunctionResult> - Tool response builder with actions

=item L<SignalWire::Agents::DataMap> - Declarative server-side API tools

=item L<SignalWire::Agents::Contexts> - Workflow context management

=item L<SignalWire::Agents::Server::AgentServer> - Multi-agent HTTP server

=item L<SignalWire::Agents::Relay::Client> - WebSocket-based call control

=item L<SignalWire::Agents::REST::SignalWireClient> - REST API client

=back

=head1 TOOL TYPES

=head2 Local Tools

Handler subroutines that execute within your agent process:

    $agent->define_tool(
        name        => 'lookup_order',
        description => 'Look up an order by ID',
        parameters  => {
            type       => 'object',
            properties => {
                order_id => { type => 'string', description => 'Order ID' },
            },
            required => ['order_id'],
        },
        handler => sub {
            my ($args, $raw) = @_;
            my $order = get_order($args->{order_id});
            return SignalWire::Agents::SWAIG::FunctionResult->new(
                "Order status: $order->{status}"
            );
        },
    );

=head2 DataMap Tools

Declarative API calls evaluated server-side, no webhook required:

    use SignalWire::Agents::DataMap;

    my $tool = SignalWire::Agents::DataMap->new('get_weather')
        ->description('Get weather for a location')
        ->parameter('city', 'string', 'City name', required => 1)
        ->webhook('GET', 'https://api.weather.com/v1?q=${args.city}')
        ->output(SignalWire::Agents::SWAIG::FunctionResult->new(
            'Weather: ${response.temp}°F'
        ));

    $agent->register_swaig_function($tool->to_swaig_function);

=head2 Skills

Pre-built capabilities added with a single call:

    $agent->add_skill('datetime');
    $agent->add_skill('math');
    $agent->add_skill('web_search', {
        api_key          => $ENV{GOOGLE_SEARCH_API_KEY},
        search_engine_id => $ENV{GOOGLE_SEARCH_ENGINE_ID},
    });

=head1 ENVIRONMENT VARIABLES

=over 4

=item C<SWML_BASIC_AUTH_USER> / C<SWML_BASIC_AUTH_PASSWORD> - Override auto-generated basic auth credentials

=item C<SIGNALWIRE_PROJECT_ID> - Project ID for Relay and REST clients

=item C<SIGNALWIRE_API_TOKEN> - API token for Relay and REST clients

=item C<SIGNALWIRE_SPACE> - SignalWire space hostname

=back

=head1 SOURCE

L<https://github.com/signalwire/signalwire-agents-perl>

=head1 LICENSE

This is free software licensed under the MIT License.

=cut
