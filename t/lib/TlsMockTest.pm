package TlsMockTest;

# Shared test-only TLS support for the three cross-port "every SDK does
# verified HTTPS + WSS" capability quadrants (mirrors signalwire-go's
# pkg/{relay,rest,swml} tls_support_test.go helpers).
#
# Responsibilities:
#   * Locate the porting-sdk throwaway test CA + leaf cert via the same
#     adjacency walk the plain-HTTP mock helpers use, running the idempotent
#     gen_certs.sh on demand.
#   * Wire CA trust the idiomatic, no-transport-mock way: set SSL_CERT_FILE to
#     certs/ca.crt. Net::SSLeay / IO::Socket::SSL honor it as the default CA
#     store, so the RELAY client (wss://, SSL_VERIFY_PEER) and the REST client
#     (HTTP::Tiny verify_SSL => 1) both trust the leaf with NO code change and
#     NO SSL_VERIFY_NONE. Real verification only.
#   * Spawn the shared mocks in --tls mode on DEDICATED ports so the plaintext
#     mocks the rest of the suite uses (8770 / 8780+9780) are untouched:
#       - mock_signalwire --tls  -> HTTPS (whole app, control plane included)
#       - mock_relay      --tls  -> WSS WS plane; HTTP control plane stays plain
#
# Tests that cannot find an adjacent porting-sdk skip cleanly (matching the
# plain-HTTP mock helpers' adjacency contract).

use strict;
use warnings;

use HTTP::Tiny;
use JSON qw(decode_json);
use POSIX ();
use Time::HiRes qw(sleep time);
use File::Spec ();
use Cwd ();
use Config ();

our $VERSION = '0.01';

# Dedicated TLS ports — distinct from the plaintext mock ports so a TLS test
# never collides with a concurrently-running plaintext mock.
our $HOST            = '127.0.0.1';
our $HTTPS_PORT      = $ENV{MOCK_SIGNALWIRE_TLS_PORT} || 18766;
our $WSS_PORT        = $ENV{MOCK_RELAY_TLS_WS_PORT}   || 18775;
our $WSS_HTTP_PORT   = $ENV{MOCK_RELAY_TLS_HTTP_PORT} || 19775;

our $PROJECT = 'test_proj';
our $TOKEN   = 'test_tok';

# ---------------------------------------------------------------------------
# CA trust + cert discovery
# ---------------------------------------------------------------------------

# certs_dir walks up to porting-sdk/test_harness/tls, runs the idempotent
# gen_certs.sh (no-op when the leaf cert is still fresh), and returns the
# absolute certs/ directory, or undef when porting-sdk is not adjacent.
sub certs_dir {
    my $here = Cwd::abs_path(__FILE__);
    return undef unless defined $here;
    my $dir = File::Spec->canonpath((File::Spec->splitpath($here))[1]);
    $dir =~ s{[/\\]$}{};
    while (1) {
        my $parent = File::Spec->canonpath(File::Spec->catdir($dir, File::Spec->updir));
        last if $parent eq $dir;
        my $tls = File::Spec->catdir($parent, 'porting-sdk', 'test_harness', 'tls');
        my $gen = File::Spec->catfile($tls, 'gen_certs.sh');
        if (-f $gen) {
            # Idempotent: regenerates only when the leaf cert is missing/stale.
            # Capture stdout/stderr so gen_certs.sh's chatter stays out of TAP.
            my $out = `bash \Q$gen\E 2>&1`;
            return undef if $? != 0;
            return File::Spec->catdir($tls, 'certs');
        }
        $dir = $parent;
    }
    return undef;
}

# trust_ca returns the path to the CA cert AND sets $ENV{SSL_CERT_FILE} so the
# default IO::Socket::SSL trust store accepts the harness leaf. The caller
# should localize SSL_CERT_FILE (or call this at the top of the test) so it is
# in force before any TLS handshake. Returns undef (skip) when not adjacent.
sub trust_ca {
    my $certs = certs_dir();
    return undef unless defined $certs;
    my $ca = File::Spec->catfile($certs, 'ca.crt');
    return undef unless -f $ca;
    $ENV{SSL_CERT_FILE} = $ca;
    return $ca;
}

# ---------------------------------------------------------------------------
# Adjacency walk to put porting-sdk/test_harness/<name> on PYTHONPATH.
# ---------------------------------------------------------------------------

sub _discover_pkg {
    my ($name) = @_;
    my $here = Cwd::abs_path(__FILE__);
    return undef unless defined $here;
    my $dir = File::Spec->canonpath((File::Spec->splitpath($here))[1]);
    $dir =~ s{[/\\]$}{};
    while (1) {
        my $parent = File::Spec->canonpath(File::Spec->catdir($dir, File::Spec->updir));
        last if $parent eq $dir;
        my $candidate = File::Spec->catdir($parent, 'porting-sdk', 'test_harness', $name);
        my $init = File::Spec->catfile($candidate, $name, '__init__.py');
        return $candidate if -f $init;
        $dir = $parent;
    }
    return undef;
}

# _spawn_tls_mock(name, \@extra_args, \%env) forks a `python -m <name> --tls`
# child with stdio redirected to /dev/null, prepending the discovered package
# dir to PYTHONPATH and applying %env (SIGNALWIRE_MOCK_TLS=1, ...). Returns the
# child pid, or undef when the package is not adjacent / fork fails.
sub _spawn_tls_mock {
    my ($name, $extra_args, $env) = @_;
    my $pkg_dir = _discover_pkg($name);
    return undef unless defined $pkg_dir;

    my $sep = $Config::Config{path_sep} // ':';
    my $existing = defined $ENV{PYTHONPATH} ? $ENV{PYTHONPATH} : '';
    my $pythonpath = $existing ne '' ? "$pkg_dir$sep$existing" : $pkg_dir;

    my @cmd = ('python3', '-m', $name, '--tls', '--log-level', 'error', @{ $extra_args || [] });

    my $pid = fork();
    return undef unless defined $pid;
    if ($pid == 0) {
        # Child: trust env + redirect stdio so the startup banner can't SIGPIPE.
        $ENV{PYTHONPATH} = $pythonpath;
        $ENV{SIGNALWIRE_MOCK_TLS} = '1';
        for my $k (keys %{ $env || {} }) { $ENV{$k} = $env->{$k} }
        open(STDIN,  '<', '/dev/null');
        open(STDOUT, '>', '/dev/null');
        open(STDERR, '>', '/dev/null');
        eval { POSIX::setsid() };
        exec(@cmd) or POSIX::_exit(127);
    }
    return $pid;
}

# _wait_health($ua, $url, $key) polls $url for up to 30s, returning true once
# it answers 200 with a JSON body containing $key (the readiness signal).
sub _wait_health {
    my ($ua, $url, $key) = @_;
    my $deadline = time + 30;
    while (time < $deadline) {
        my $resp = $ua->get($url);
        if ($resp->{success}) {
            my $payload = eval { decode_json($resp->{content} || '{}') };
            return 1 if !$@ && exists $payload->{$key};
        }
        sleep 0.2;
    }
    return 0;
}

# ---------------------------------------------------------------------------
# mock_signalwire --tls (HTTPS, whole app including the control plane)
# ---------------------------------------------------------------------------

our $_SW_PID;

# start_https_mock spawns mock_signalwire --tls on $HTTPS_PORT and waits for the
# HTTPS /__mock__/health (using a CA-trusting client). Returns the https://
# base URL, or undef (skip) when unavailable. Reaped on END.
sub start_https_mock {
    my $base = "https://$HOST:$HTTPS_PORT";

    # Build a CA-trusting client up front. mock_signalwire serves the whole
    # app (control plane included) over HTTPS in --tls mode, so the readiness
    # probe itself crosses a verified TLS session.
    my $ua = HTTP::Tiny->new(timeout => 5, verify_SSL => 1);

    # Reuse a mock already listening on the TLS port (idempotent across files).
    return $base if _probe_now($ua, $base, 'specs_loaded');

    $_SW_PID = _spawn_tls_mock(
        'mock_signalwire',
        ['--host', $HOST, '--port', $HTTPS_PORT],
        {},
    );
    return undef unless defined $_SW_PID;
    eval { $SIG{CHLD} = 'IGNORE' };

    if (_wait_health($ua, "$base/__mock__/health", 'specs_loaded')) {
        return $base;
    }
    _reap(\$_SW_PID);
    return undef;
}

# _probe_now is a single (non-polling) health probe used to decide reuse.
sub _probe_now {
    my ($ua, $base, $key) = @_;
    my $resp = $ua->get("$base/__mock__/health");
    return 0 unless $resp->{success};
    my $p = eval { decode_json($resp->{content} || '{}') };
    return !$@ && exists $p->{$key};
}

# https_journal_last returns the most recently recorded REST request on the
# mock's (HTTPS) control plane, or dies if the journal is empty.
sub https_journal_last {
    my $base = "https://$HOST:$HTTPS_PORT";
    my $ua = HTTP::Tiny->new(timeout => 5, verify_SSL => 1);
    my $resp = $ua->get("$base/__mock__/journal");
    die "https journal fetch failed: $resp->{status} $resp->{reason}" unless $resp->{success};
    my $entries = decode_json($resp->{content} || '[]');
    die "https journal is empty - HTTPS request did not reach the mock" unless @$entries;
    return $entries->[-1];
}

# ---------------------------------------------------------------------------
# mock_relay --tls (WSS WS plane; HTTP control plane stays plain HTTP)
# ---------------------------------------------------------------------------

our $_RELAY_PID;

# start_wss_mock spawns mock_relay --tls (WS plane wss:// on $WSS_PORT, HTTP
# control plane on $WSS_HTTP_PORT) and waits for the plain-HTTP control plane
# /__mock__/health. Returns the plain http:// control-plane base URL (for
# journal reads), or undef (skip). Reaped on END.
sub start_wss_mock {
    my $http_base = "http://$HOST:$WSS_HTTP_PORT";
    my $ua = HTTP::Tiny->new(timeout => 5);  # control plane is plain HTTP

    return $http_base if _probe_now($ua, $http_base, 'schemas_loaded');

    $_RELAY_PID = _spawn_tls_mock(
        'mock_relay',
        ['--host', $HOST, '--ws-port', $WSS_PORT, '--http-port', $WSS_HTTP_PORT],
        { MOCK_RELAY_PORT => $WSS_PORT },
    );
    return undef unless defined $_RELAY_PID;
    eval { $SIG{CHLD} = 'IGNORE' };

    if (_wait_health($ua, "$http_base/__mock__/health", 'schemas_loaded')) {
        return $http_base;
    }
    _reap(\$_RELAY_PID);
    return undef;
}

# wss_journal_reset clears the relay mock journal (plain-HTTP control plane).
sub wss_journal_reset {
    my $http_base = "http://$HOST:$WSS_HTTP_PORT";
    my $ua = HTTP::Tiny->new(timeout => 5);
    for my $i (1 .. 10) {
        my $resp = $ua->post("$http_base/__mock__/journal/reset");
        return if $resp->{success};
        sleep 0.1;
    }
    die "wss journal_reset failed";
}

# wss_saw_recv($method) reports whether the relay mock journaled an inbound
# (SDK->server) frame with the given JSON-RPC method — proof traffic crossed
# the wss:// link (the journal is read over the plain-HTTP control plane).
sub wss_saw_recv {
    my ($method) = @_;
    my $http_base = "http://$HOST:$WSS_HTTP_PORT";
    my $ua = HTTP::Tiny->new(timeout => 5);
    my $resp = $ua->get("$http_base/__mock__/journal");
    die "wss journal fetch failed: $resp->{status}" unless $resp->{success};
    my $entries = decode_json($resp->{content} || '[]');
    for my $e (@$entries) {
        return 1 if ($e->{direction} // '') eq 'recv' && ($e->{method} // '') eq $method;
    }
    return 0;
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

sub _reap {
    my ($pidref) = @_;
    my $pid = $$pidref;
    return unless $pid && $pid > 0;
    eval {
        kill 'TERM', $pid;
        for my $i (1 .. 20) {
            last unless kill 0, $pid;
            sleep 0.05;
        }
        kill 'KILL', $pid if kill 0, $pid;
        waitpid($pid, POSIX::WNOHANG());
    };
    $$pidref = undef;
}

END {
    local $?;
    _reap(\$_SW_PID);
    _reap(\$_RELAY_PID);
}

1;

__END__

=head1 NAME

TlsMockTest - shared TLS capability-test support for signalwire-perl.

=head1 DESCRIPTION

Spawns the porting-sdk shared mocks in C<--tls> mode on dedicated ports and
wires CA trust via C<SSL_CERT_FILE> pointing at the throwaway test CA, so the
real Perl SDK clients (RELAY over wss://, REST over https://) and the SDK's own
HTTPS server can be exercised over genuinely-verified TLS — no transport mocks,
no C<SSL_VERIFY_NONE>.

=cut
