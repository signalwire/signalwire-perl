package SignalWire::Server::AgentServer;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.

use strict;
use warnings;
use Moo;
use JSON qw(encode_json decode_json);
use Carp qw(croak);
use File::Spec;

has host      => ( is => 'rw', default => sub { '0.0.0.0' } );
has port      => ( is => 'rw', default => sub { $ENV{PORT} || 3000 } );
has log_level => ( is => 'rw', default => sub { 'info' } );
has agents    => ( is => 'rw', default => sub { {} } );

# SIP routing
has _sip_routing_enabled  => ( is => 'rw', default => sub { 0 } );
has _sip_username_mapping => ( is => 'rw', default => sub { {} } );
has _sip_route            => ( is => 'rw', default => sub { '/sip' } );

# Static file routes: { route => directory }
has _static_routes => ( is => 'rw', default => sub { {} } );

sub register {
    my ( $self, $agent, $route ) = @_;

    $route //= $agent->route;
    $route = "/$route" unless $route =~ m{^/};
    $route =~ s{/+$}{} unless $route eq '/';

    if ( exists $self->agents->{$route} ) {
        croak("Route '$route' is already registered");
    }

    $agent->route($route);
    $self->agents->{$route} = $agent;
    return $self;
}

sub unregister {
    my ( $self, $route ) = @_;
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
    my ( $self, $route ) = @_;
    return $self->agents->{$route};
}

# get_agents — the full route => agent map (Python parity:
# AgentServer.get_agents). A shallow copy so callers can't mutate the
# server's registry.
sub get_agents {
    my ($self) = @_;
    return { %{ $self->agents } };
}

# setup_sip_routing(route => '/sip', auto_map => 1) — enable SIP-based
# routing across the server; when auto_map is on, derive a SIP username for
# every registered agent from its route (Python parity:
# AgentServer.setup_sip_routing).
sub setup_sip_routing {
    my ( $self, %opts ) = @_;
    my $route    = $opts{route} // '/sip';
    my $auto_map = exists $opts{auto_map} ? $opts{auto_map} : 1;
    $self->_sip_routing_enabled(1);
    $self->_sip_route($route);
    if ($auto_map) {
        for my $r ( keys %{ $self->agents } ) {
            ( my $username = $r ) =~ s{^/}{};
            $username =~ s{/}{_}g;
            $self->_sip_username_mapping->{$username} = $r if length $username;
        }
    }
    return $self;
}

# register_sip_username(username, route) — map a SIP username to a route
# (Python parity: AgentServer.register_sip_username).
sub register_sip_username {
    my ( $self, $username, $route ) = @_;
    $route = "/$route" unless $route =~ m{^/};
    $self->_sip_username_mapping->{$username} = $route;
    return $self;
}

# register_global_routing_callback(callback => sub, path => '/x') — register
# a routing callback at the same path on every agent that supports it
# (Python parity: AgentServer.register_global_routing_callback).
sub register_global_routing_callback {
    my ( $self, %opts ) = @_;
    my $callback = $opts{callback};
    croak("register_global_routing_callback requires a callback coderef")
        unless ref $callback eq 'CODE';
    my $path = $opts{path} // croak("register_global_routing_callback requires a path");
    $path = "/$path" unless $path =~ m{^/};
    $path =~ s{/+$}{} unless $path eq '/';
    for my $agent ( values %{ $self->agents } ) {
        $agent->register_routing_callback( $path, $callback )
            if $agent->can('register_routing_callback');
    }
    return $self;
}

sub serve_static_files {
    my ( $self, $directory, $route ) = @_;

    croak("serve_static_files requires a directory")      unless defined $directory;
    croak("serve_static_files requires a route")          unless defined $route;
    croak("Static directory '$directory' does not exist") unless -d $directory;

    $route = "/$route" unless $route =~ m{^/};
    $route =~ s{/+$}{} unless $route eq '/';

    # Resolve the directory to an absolute path for security
    $self->_static_routes->{$route} = File::Spec->rel2abs($directory);
    return $self;
}

sub psgi_app {
    my ($self) = @_;
    return $self->_build_psgi_app;
}

sub _build_psgi_app {
    my ($self) = @_;
    require Plack::Request;

    my $server = $self;

    # MIME type mapping for static files
    my %mime_types = (
        html  => 'text/html',
        htm   => 'text/html',
        css   => 'text/css',
        js    => 'application/javascript',
        json  => 'application/json',
        png   => 'image/png',
        jpg   => 'image/jpeg',
        jpeg  => 'image/jpeg',
        gif   => 'image/gif',
        svg   => 'image/svg+xml',
        ico   => 'image/x-icon',
        txt   => 'text/plain',
        pdf   => 'application/pdf',
        xml   => 'application/xml',
        woff  => 'font/woff',
        woff2 => 'font/woff2',
        ttf   => 'font/ttf',
        eot   => 'application/vnd.ms-fontobject',
    );

    # Build a plain PSGI app with route dispatch
    my $core_app = sub {
        my $env  = shift;
        my $path = $env->{PATH_INFO} // '/';
        $path =~ s{/+$}{} unless $path eq '/';

        # Health/ready (no auth)
        if ( $path eq '/health' ) {
            my @agent_names = map { $server->agents->{$_}->name }
                sort keys %{ $server->agents };
            return [
                200,
                [ 'Content-Type' => 'application/json' ],
                [ encode_json( { status => 'healthy', agents => \@agent_names } ) ]
            ];
        }
        if ( $path eq '/ready' ) {
            return [
                200,
                [ 'Content-Type' => 'application/json' ],
                [ encode_json( { status => 'ready' } ) ]
            ];
        }

        # Check static file routes (longest prefix match)
        for my $static_route (
            sort { length($b) <=> length($a) }
            keys %{ $server->_static_routes }
            )
        {
            my $prefix = $static_route eq '/' ? '' : $static_route;
            if (   $path eq $static_route
                || index( $path, "$prefix/" ) == 0
                || ( $static_route eq '/' && $path =~ m{^/} ) )
            {
                next if $static_route eq '/' && $path eq '/';
                my $rel_path = substr( $path, length($prefix) );
                $rel_path =~ s{^/}{};

                # Path traversal protection: reject ".." components
                if ( $rel_path =~ m{(?:^|/)\.\.(?:/|$)} ) {
                    return [
                        403,
                        [
                            'Content-Type'           => 'text/plain',
                            'X-Content-Type-Options' => 'nosniff',
                            'X-Frame-Options'        => 'DENY',
                            'Cache-Control'          => 'no-store',
                        ],
                        ['Forbidden']
                    ];
                }

                my $base_dir  = $server->_static_routes->{$static_route};
                my $file_path = File::Spec->catfile( $base_dir, split( m{/}, $rel_path ) );

                # Resolve to absolute and verify it's within the base directory
                my $abs_path = File::Spec->rel2abs($file_path);
                unless ( index( $abs_path, $base_dir ) == 0 ) {
                    return [
                        403,
                        [
                            'Content-Type'           => 'text/plain',
                            'X-Content-Type-Options' => 'nosniff',
                            'X-Frame-Options'        => 'DENY',
                            'Cache-Control'          => 'no-store',
                        ],
                        ['Forbidden']
                    ];
                }

                if ( -f $abs_path && -r $abs_path ) {

                    # Determine MIME type from extension
                    my ($ext) = ( $abs_path =~ /\.(\w+)$/ );
                    $ext = lc( $ext // '' );
                    my $content_type = $mime_types{$ext} // 'application/octet-stream';

                    open my $fh, '<:raw',
                        $abs_path
                        or return [ 500, [ 'Content-Type' => 'text/plain' ],
                        ['Internal Server Error'] ];
                    local $/;
                    my $content = <$fh>;
                    close $fh;

                    return [
                        200,
                        [
                            'Content-Type'           => $content_type,
                            'Content-Length'         => length($content),
                            'X-Content-Type-Options' => 'nosniff',
                            'X-Frame-Options'        => 'DENY',
                            'Cache-Control'          => 'no-store',
                        ],
                        [$content]
                    ];
                }

                # Static route matched but file not found - fall through
            }
        }

        # Find matching agent by longest prefix
        my $matched_route;
        for my $route ( sort { length($b) <=> length($a) } keys %{ $server->agents } ) {
            if ( $route eq '/' ) {
                $matched_route = $route;
                last;
            }
            if ( $path eq $route || index( $path, "$route/" ) == 0 ) {
                $matched_route = $route;
                last;
            }
        }

        if ( defined $matched_route ) {
            my $agent     = $server->agents->{$matched_route};
            my $agent_app = $agent->psgi_app;
            return $agent_app->($env);
        }

        return [
            404,
            [ 'Content-Type' => 'application/json' ],
            [ encode_json( { error => 'Not Found' } ) ]
        ];
    };

    # Wrap with security headers
    return sub {
        my $env = shift;
        my $res = $core_app->($env);
        if ( ref $res eq 'ARRAY' ) {
            push @{ $res->[1] },
                'X-Content-Type-Options' => 'nosniff',
                'X-Frame-Options'        => 'DENY',
                'Cache-Control'          => 'no-store';
        }
        return $res;
    };
}

sub run {
    my ( $self, %opts ) = @_;
    my $app  = $self->psgi_app;
    my $host = $opts{host} // $self->host;
    my $port = $opts{port} // $self->port;

    # HTTPS self-serve: when an SSL cert+key pair is configured the server
    # presents it directly (no reverse proxy required), matching the Python
    # reference's uvicorn ssl_certfile/ssl_keyfile path. Two config sources,
    # mirroring Python:
    #   * Explicit run() options (ssl_cert + ssl_key) always enable TLS — the
    #     analogue of Python web_service.start(ssl_cert=, ssl_key=).
    #   * Otherwise the SWML_SSL_* environment variables: TLS only when
    #     SWML_SSL_ENABLED is truthy AND both cert + key paths resolve.
    my ( $cert, $key ) = _resolve_tls( \%opts );
    if ( defined $cert && defined $key ) {
        return _run_tls( $app, $host, $port, $cert, $key );
    }

    require Plack::Runner;
    my $runner = Plack::Runner->new;
    $runner->parse_options(
        '--host'   => $host,
        '--port'   => $port,
        '--server' => 'HTTP::Server::PSGI',
    );
    return $runner->run($app);
}

# _resolve_tls(\%opts) -> ($cert, $key) when TLS should be served, else
# (undef, undef). Explicit ssl_cert + ssl_key options force HTTPS; otherwise the
# SWML_SSL_* environment is consulted (TLS only when SWML_SSL_ENABLED is truthy
# AND both cert + key paths are set), exactly matching the Python reference.
sub _resolve_tls {
    my ($opts) = @_;
    my $cert   = $opts->{ssl_cert} // $opts->{ssl_cert_path};
    my $key    = $opts->{ssl_key}  // $opts->{ssl_key_path};
    if ( defined $cert && length $cert && defined $key && length $key ) {
        return ( $cert, $key );
    }
    my $enabled = lc( $ENV{SWML_SSL_ENABLED} // '' );
    if ( $enabled eq 'true' || $enabled eq '1' || $enabled eq 'yes' ) {
        my $ecert = $ENV{SWML_SSL_CERT_PATH};
        my $ekey  = $ENV{SWML_SSL_KEY_PATH};
        if ( defined $ecert && length $ecert && defined $ekey && length $ekey ) {
            return ( $ecert, $ekey );
        }
    }
    return ( undef, undef );
}

# Serve $app over HTTPS by building an IO::Socket::SSL listen socket from the
# configured cert/key and handing it to HTTP::Server::PSGI via listen_sock
# (HTTP::Server::PSGI accepts an already-bound socket and derives host/port
# from it). IO::Socket::SSL is already a hard dependency (used by the RELAY
# client), so this adds no new dependency. Blocks like the plaintext path.
sub _run_tls {
    my ( $app, $host, $port, $cert, $key ) = @_;
    require IO::Socket::SSL;
    require HTTP::Server::PSGI;
    no warnings 'once';    # $IO::Socket::SSL::SSL_ERROR is populated at runtime

    my $ssl = IO::Socket::SSL->new(
        LocalAddr     => $host,
        LocalPort     => $port,
        Listen        => 5,
        ReuseAddr     => 1,
        SSL_cert_file => $cert,
        SSL_key_file  => $key,
        )
        or croak(
        "AgentServer: TLS listen on $host:$port failed: " . ( $IO::Socket::SSL::SSL_ERROR // $! ) );

    my $srv = HTTP::Server::PSGI->new(
        host        => $host,
        port        => $port,
        listen_sock => $ssl,
    );
    return $srv->run($app);
}

1;
