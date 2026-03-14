package SignalWire::Agents::Server::AgentServer;
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.

use strict;
use warnings;
use Moo;
use JSON qw(encode_json decode_json);
use Carp qw(croak);

has host      => (is => 'rw', default => sub { '0.0.0.0' });
has port      => (is => 'rw', default => sub { $ENV{PORT} || 3000 });
has log_level => (is => 'rw', default => sub { 'info' });
has agents    => (is => 'rw', default => sub { {} });

# SIP routing
has _sip_routing_enabled  => (is => 'rw', default => sub { 0 });
has _sip_username_mapping => (is => 'rw', default => sub { {} });

sub register {
    my ($self, $agent, $route) = @_;

    $route //= $agent->route;
    $route = "/$route" unless $route =~ m{^/};
    $route =~ s{/+$}{} unless $route eq '/';

    if (exists $self->agents->{$route}) {
        croak("Route '$route' is already registered");
    }

    $agent->route($route);
    $self->agents->{$route} = $agent;
    return $self;
}

sub unregister {
    my ($self, $route) = @_;
    $route = "/$route" unless $route =~ m{^/};
    $route =~ s{/+$}{} unless $route eq '/';
    delete $self->agents->{$route};
    return $self;
}

sub list_agents {
    my ($self) = @_;
    return [ sort keys %{ $self->agents } ];
}

sub get_agent {
    my ($self, $route) = @_;
    return $self->agents->{$route};
}

sub psgi_app {
    my ($self) = @_;
    return $self->_build_psgi_app;
}

sub _build_psgi_app {
    my ($self) = @_;
    require Plack::Request;

    my $server = $self;

    # Build a plain PSGI app with route dispatch
    my $core_app = sub {
        my $env = shift;
        my $path = $env->{PATH_INFO} // '/';
        $path =~ s{/+$}{} unless $path eq '/';

        # Health/ready (no auth)
        if ($path eq '/health') {
            my @agent_names = map { $server->agents->{$_}->name }
                              sort keys %{ $server->agents };
            return [200, ['Content-Type' => 'application/json'],
                [encode_json({ status => 'healthy', agents => \@agent_names })]];
        }
        if ($path eq '/ready') {
            return [200, ['Content-Type' => 'application/json'],
                [encode_json({ status => 'ready' })]];
        }

        # Find matching agent by longest prefix
        my $matched_route;
        for my $route (sort { length($b) <=> length($a) } keys %{ $server->agents }) {
            if ($route eq '/') {
                $matched_route = $route;
                last;
            }
            if ($path eq $route || index($path, "$route/") == 0) {
                $matched_route = $route;
                last;
            }
        }

        if (defined $matched_route) {
            my $agent     = $server->agents->{$matched_route};
            my $agent_app = $agent->psgi_app;
            return $agent_app->($env);
        }

        return [404, ['Content-Type' => 'application/json'],
            [encode_json({ error => 'Not Found' })]];
    };

    # Wrap with security headers
    return sub {
        my $env = shift;
        my $res = $core_app->($env);
        if (ref $res eq 'ARRAY') {
            push @{ $res->[1] },
                'X-Content-Type-Options' => 'nosniff',
                'X-Frame-Options'        => 'DENY',
                'Cache-Control'          => 'no-store';
        }
        return $res;
    };
}

sub run {
    my ($self, %opts) = @_;
    my $app  = $self->psgi_app;
    my $host = $opts{host} // $self->host;
    my $port = $opts{port} // $self->port;

    require Plack::Runner;
    my $runner = Plack::Runner->new;
    $runner->parse_options(
        '--host'   => $host,
        '--port'   => $port,
        '--server' => 'HTTP::Server::PSGI',
    );
    $runner->run($app);
}

1;
