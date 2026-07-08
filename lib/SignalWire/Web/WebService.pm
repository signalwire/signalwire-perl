package SignalWire::Web::WebService;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# Static file serving service with an HTTP API.
#
# Perl port of signalwire.web.web_service.WebService
# (signalwire-python/signalwire/signalwire/web/web_service.py),
# structurally mirroring Ruby's SignalWire::Web::WebService
# (signalwire-ruby/lib/signalwire/web/web_service.rb).
#
# Maps URL route prefixes to local directories and serves their files over
# HTTP with security headers, extension filtering, and optional basic
# auth.
#
# Perl idiom note: Python builds a FastAPI/uvicorn app; Perl builds a PSGI
# app served by HTTP::Server::PSGI. start launches the server in a
# background child process (non-blocking) so it is safe to start and stop in
# tests without hanging; pass block => 1 to start to run in the
# foreground. The PSGI app itself is exposed via psgi_app for callers who
# want to mount it in their own Plack stack.

use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
use Carp         qw(croak);
use MIME::Base64 qw(decode_base64);
use File::Spec   ();
use Cwd          ();
use POSIX        ();

# Files/extensions never served regardless of the allow list.
my @DEFAULT_BLOCKED_EXTENSIONS =
    qw(.env .git .gitignore .key .pem .crt .pyc __pycache__ .DS_Store .swp);

# ---------- attributes ----------

has port                      => ( is => 'rw', default => sub { 8002 } );
has directories               => ( is => 'rw', default => sub { {} } );
has enable_directory_browsing => ( is => 'rw', default => sub { 0 } );
has max_file_size             => ( is => 'rw', default => sub { 100 * 1024 * 1024 } );
has enable_cors               => ( is => 'rw', default => sub { 1 } );
has allowed_extensions        => ( is => 'rw', default => sub { undef } );
has blocked_extensions        => ( is => 'rw', default => sub { [@DEFAULT_BLOCKED_EXTENSIONS] } );

# (username, password) arrayref, or undef for no auth.
has _basic_auth => ( is => 'rw', default => sub { undef } );

# Runtime handles (background server child PID + bound port).
has _pid        => ( is => 'rw', default => sub { undef } );
has _bound_port => ( is => 'rw', default => sub { undef } );

# Construction params captured for BUILDARGS handling.
has _basic_auth_arg => ( is => 'ro', default => sub { undef } );

# ---------- construction ----------

# Accept the Python/Ruby keyword surface: port, directories, basic_auth,
# config_file, enable_directory_browsing, allowed_extensions,
# blocked_extensions, max_file_size, enable_cors.
around BUILDARGS => sub ( $orig, $class, @args ) {
    my %opts = ( @args == 1 && ref $args[0] eq 'HASH' ) ? %{ $args[0] } : @args;

    my %build;
    $build{port}                      = $opts{port}        if defined $opts{port};
    $build{directories}               = $opts{directories} if defined $opts{directories};
    $build{enable_directory_browsing} = $opts{enable_directory_browsing} ? 1 : 0
        if exists $opts{enable_directory_browsing};
    $build{max_file_size}      = $opts{max_file_size}       if defined $opts{max_file_size};
    $build{enable_cors}        = $opts{enable_cors} ? 1 : 0 if exists $opts{enable_cors};
    $build{allowed_extensions} = $opts{allowed_extensions}  if defined $opts{allowed_extensions};
    $build{blocked_extensions} = $opts{blocked_extensions}  if defined $opts{blocked_extensions};
    $build{_basic_auth_arg}    = $opts{basic_auth}          if defined $opts{basic_auth};

    return $class->$orig(%build);
};

sub BUILD ( $self, $args ) {

    # basic_auth: explicit arg wins, else env-derived, else none.
    my $auth = $self->_basic_auth_arg;
    if ( !defined $auth ) {
        my $user = $ENV{SWML_BASIC_AUTH_USER};
        my $pass = $ENV{SWML_BASIC_AUTH_PASSWORD};
        $auth = [ $user, $pass ] if defined $user && defined $pass;
    }
    $self->_basic_auth($auth);
    return;
}

# ---------- directory management ----------

# Add a directory to serve at $route. Dies when the directory does not
# exist or is not a directory. Mirrors Python's add_directory. Returns
# $self.
sub add_directory ( $self, $route, $directory ) {
    $route = _normalize_route($route);
    croak "Directory does not exist: $directory" unless -e $directory;
    croak "Path is not a directory: $directory"  unless -d $directory;

    $self->directories->{$route} = $directory;
    return $self;
}

# Remove the directory served at $route (no-op when absent). Returns
# $self.
sub remove_directory ( $self, $route ) {
    $route = _normalize_route($route);
    delete $self->directories->{$route};
    return $self;
}

# ---------- lifecycle ----------

# Start the service. Non-blocking by default (forks a child running
# HTTP::Server::PSGI and returns the bound port). Pass block => 1 to run in
# the foreground. port => 0 binds an ephemeral port. A forked child is used
# (rather than a thread) because HTTP::Server::PSGI's run() blocks in
# accept(); a child dies cleanly on a signal from stop() whereas a blocked
# thread cannot be interrupted — this matches the port's TLS-server tests.
#
# Python parity: start(host="0.0.0.0", port=None, ssl_cert=None,
# ssl_key=None). The ssl_cert/ssl_key kwargs are accepted for parity.
sub start ( $self, %opts ) {
    my $host      = defined $opts{host} ? $opts{host} : '127.0.0.1';
    my $bind_port = defined $opts{port} ? $opts{port} : $self->port;

    require HTTP::Server::PSGI;
    my $app = $self->psgi_app;

    # Resolve an ephemeral port up front so a non-blocking caller learns the
    # bound port before the child binds it.
    if ( !$bind_port ) {
        $bind_port = _pick_free_port($host);
    }
    $self->_bound_port($bind_port);

    my $run = sub {
        my $server = HTTP::Server::PSGI->new(
            host            => $host,
            port            => $bind_port,
            server_software => 'SignalWire Web Service',
        );
        return $server->run($app);
    };

    return $run->() if $opts{block};

    my $pid = fork();
    die "fork failed: $!" unless defined $pid;
    if ( $pid == 0 ) {

        # Child: serve until killed.
        $run->();
        POSIX::_exit(0) if defined &POSIX::_exit;
        exit 0;
    }
    $self->_pid($pid);

    # Wait until the port accepts connections so stop() is race-free.
    _wait_listening( $host, $bind_port );
    return $bind_port;
}

# Stop the service and reap the background child. Safe to call when not
# running.
sub stop ($self) {
    my $pid = $self->_pid;
    if ( $pid && kill( 0, $pid ) ) {
        require Time::HiRes;
        kill 'TERM', $pid;
        for ( 1 .. 40 ) { last unless kill( 0, $pid ); Time::HiRes::sleep(0.05); }
        kill 'KILL', $pid if kill( 0, $pid );
        waitpid( $pid, 0 );
    }
    $self->_pid(undef);
    $self->_bound_port(undef);
    return;
}

# ---------- PSGI app ----------

# Build the PSGI coderef implementing the static-file API. Exposed so the
# app can be mounted in a caller's own Plack stack.
sub psgi_app ($self) {
    return sub ($env) {
        return $self->_handle_psgi($env);
    };
}

sub _handle_psgi ( $self, $env ) {
    my $path = $env->{PATH_INFO} // '/';

    # Match the longest configured route prefix.
    my ( $route, $directory ) = $self->_match_route($path);
    return _text_response( 404, 'File not found' ) unless defined $route;

    my $auth = $self->_authorize($env);
    return $auth if $auth;    # 401 response, or undef when authorized

    ( my $rel = $path ) =~ s{\A\Q$route\E/?}{};
    my $base = Cwd::abs_path($directory) // $directory;
    my $full = Cwd::abs_path( File::Spec->catfile( $directory, $rel ) );

    # Path-traversal guard.
    return _text_response( 403, 'Access denied' )
        unless defined $full
        && ( $full eq $base
        || index( $full, $base . '/' ) == 0 );
    return _text_response( 404, 'File not found' ) unless -e $full;

    return $self->_serve_path($full);
}

sub _serve_path ( $self, $full ) {
    if ( -d $full ) {
        return _text_response( 403, 'Directory browsing disabled' )
            unless $self->enable_directory_browsing;
        $full = File::Spec->catfile( $full, 'index.html' );
    }
    return _text_response( 403, 'Directory browsing disabled' ) unless -f $full;
    return _text_response( 403, 'File type not allowed' )       unless $self->file_allowed($full);

    return $self->_write_file($full);
}

sub _write_file ( $self, $full ) {
    open my $fh, '<:raw', $full or return _text_response( 404, 'File not found' );
    local $/;
    my $body = <$fh>;
    close $fh;

    my @headers = (
        'Content-Type'  => _mime_type($full),
        'Cache-Control' => 'public, max-age=3600',
        %{ _security_headers() },
    );
    return [ 200, \@headers, [$body] ];
}

# ---------- file / auth helpers ----------

# Whether a file may be served (size + extension/name filters). Mirrors
# Python's _is_file_allowed / Ruby's file_allowed?.
sub file_allowed ( $self, $path ) {
    return 0 unless -f $path;
    return 0 if -s $path > $self->max_file_size;
    return 0 if $self->_blocked($path);

    if ( $self->allowed_extensions ) {
        my $ext = _extname($path);
        return ( grep { lc($_) eq lc($ext) } @{ $self->allowed_extensions } ) ? 1 : 0;
    }
    return 1;
}

sub _blocked ( $self, $path ) {
    my ( undef, undef, $name ) = File::Spec->splitpath($path);
    my $ext = lc _extname($path);
    for my $blocked ( @{ $self->blocked_extensions } ) {
        if ( $blocked =~ /\A\./ ) {
            return 1 if $ext eq lc($blocked) || $name eq $blocked;
        } else {
            return 1 if $name eq $blocked || index( $path, $blocked ) >= 0;
        }
    }
    return 0;
}

# Return a 401 PSGI response if auth is required and missing/wrong;
# undef when authorized (or when no auth is configured).
sub _authorize ( $self, $env ) {
    my $auth = $self->_basic_auth;
    return unless ref $auth eq 'ARRAY';
    my ( $user, $pass ) = @$auth;
    return unless defined $user && defined $pass;

    my $header = $env->{HTTP_AUTHORIZATION} // '';
    if ( $header =~ /\ABasic\s+(.+)\z/ ) {
        my $decoded = decode_base64($1);
        my ( $in_user, $in_pass ) = split /:/, $decoded, 2;
        $in_pass //= '';
        return
            if _secure_eq( $user, $in_user ) && _secure_eq( $pass, $in_pass );
    }

    return [
        401,
        [
            'Content-Type'     => 'text/plain',
            'WWW-Authenticate' => 'Basic realm="SignalWire Web Service"',
        ],
        ['Authentication required'],
    ];
}

# Match the longest configured route that prefixes $path.
sub _match_route ( $self, $path ) {
    my $best;
    for my $route ( sort { length($b) <=> length($a) } keys %{ $self->directories } ) {
        if ( $path eq $route || index( $path, "$route/" ) == 0 ) {
            $best = $route;
            last;
        }
    }
    return defined $best ? ( $best, $self->directories->{$best} ) : ( undef, undef );
}

# ---------- static helpers ----------

sub _normalize_route ($route) {
    return $route =~ m{\A/} ? $route : "/$route";
}

sub _extname ($path) {
    return $path =~ /(\.[^.\/\\]+)\z/ ? $1 : '';
}

sub _mime_type ($full) {
    my %map = (
        '.html' => 'text/html',
        '.htm'  => 'text/html',
        '.css'  => 'text/css',
        '.js'   => 'application/javascript',
        '.json' => 'application/json',
        '.txt'  => 'text/plain',
        '.png'  => 'image/png',
        '.jpg'  => 'image/jpeg',
        '.jpeg' => 'image/jpeg',
        '.gif'  => 'image/gif',
        '.svg'  => 'image/svg+xml',
    );
    return $map{ lc _extname($full) } // 'application/octet-stream';
}

sub _security_headers {
    return {
        'X-Content-Type-Options' => 'nosniff',
        'X-Frame-Options'        => 'SAMEORIGIN',
    };
}

sub _text_response ( $status, $message ) {
    return [ $status, [ 'Content-Type' => 'text/plain' ], [$message] ];
}

# Constant-time-ish string comparison for basic-auth credentials.
sub _secure_eq ( $a, $b ) {
    $a //= '';
    $b //= '';
    return 0 if length($a) != length($b);
    my $diff = 0;
    $diff |= ord( substr $a, $_, 1 ) ^ ord( substr $b, $_, 1 ) for 0 .. length($a) - 1;
    return $diff == 0 ? 1 : 0;
}

# Bind an ephemeral loopback port, read the OS-assigned port, release it.
sub _pick_free_port ($host) {
    require IO::Socket::INET;
    my $sock = IO::Socket::INET->new(
        LocalAddr => $host,
        LocalPort => 0,
        Proto     => 'tcp',
        Listen    => 1,
    ) or croak "cannot bind ephemeral port: $!";
    my $port = $sock->sockport;
    $sock->close;
    return $port;
}

# Poll until the server accepts a connection (bounded), so a non-blocking
# start() returns only once stop() would be race-free.
sub _wait_listening ( $host, $port ) {
    require IO::Socket::INET;
    require Time::HiRes;
    for ( 1 .. 100 ) {
        my $sock = IO::Socket::INET->new(
            PeerAddr => $host,
            PeerPort => $port,
            Proto    => 'tcp',
            Timeout  => 1,
        );
        if ($sock) { $sock->close; return 1; }
        Time::HiRes::sleep(0.02);
    }
    return 0;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Web::WebService - static file serving service with an HTTP API

=head1 SYNOPSIS

    use SignalWire::Web::WebService;

    my $svc = SignalWire::Web::WebService->new(
        port        => 8002,
        directories => { '/docs' => '/srv/docs' },
    );
    $svc->add_directory('/assets', '/srv/assets');

    my $bound = $svc->start;   # background child, returns bound port
    # ... serve requests ...
    $svc->stop;

    # Or mount the PSGI app in your own Plack stack:
    my $app = $svc->psgi_app;

=head1 DESCRIPTION

L<SignalWire::Web::WebService> is the Perl port of
C<signalwire.web.web_service.WebService>. It maps URL route prefixes to
local directories and serves their files over HTTP with security headers,
extension filtering, path-traversal protection, and optional basic auth.

Python builds a FastAPI/uvicorn app; this port builds a PSGI app served by
L<HTTP::Server::PSGI>. C<start> is non-blocking by default (runs the
server in a forked child and returns the bound port); pass
C<block =E<gt> 1> to run in the foreground. C<port =E<gt> 0> binds an
ephemeral port.

=head2 Methods

=over 4

=item * C<new(%opts)> — C<port> (default 8002), C<directories>,
C<basic_auth> (a C<[user, pass]> arrayref; falls back to
C<SWML_BASIC_AUTH_USER> / C<SWML_BASIC_AUTH_PASSWORD>),
C<enable_directory_browsing>, C<allowed_extensions>,
C<blocked_extensions>, C<max_file_size>, C<enable_cors>.

=item * C<add_directory($route, $directory)> — serve C<$directory> at
C<$route> (dies if it is not an existing directory).

=item * C<remove_directory($route)> — stop serving C<$route> (no-op when absent).

=item * C<start(%opts)> — start the server; returns the bound port
(non-blocking). Accepts C<host>, C<port>, C<ssl_cert> / C<ssl_key>, and
C<block>.

=item * C<stop> — stop the server and reap the background child.

=item * C<file_allowed($path)> — whether a file passes the size + extension filters.

=item * C<psgi_app> — the PSGI coderef, for mounting in a custom Plack stack.

=back

=head1 SEE ALSO

L<HTTP::Server::PSGI>, L<Plack>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
