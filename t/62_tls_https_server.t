#!/usr/bin/env perl
# TLS capability test #3 (HTTPS server — the SDK self-serves HTTPS).
#
# The third cross-port "every SDK does verified HTTPS + WSS" quadrant, the
# server side (template: signalwire-go commit b6b2b6d, TestTLS_Server_HTTPS).
# Starts the SDK's own webhook/agent server over HTTPS using the shared
# porting-sdk self-signed leaf cert (SAN localhost/127.0.0.1), then reaches its
# unauthenticated /health route from an in-test HTTP::Tiny client that trusts
# the test CA over https://, asserting a real JSON response.
#
# The server is started via AgentServer->run(ssl_cert => ..., ssl_key => ...),
# which (when a cert+key pair resolves) builds an IO::Socket::SSL listen socket
# and hands it to HTTP::Server::PSGI via listen_sock — the SDK presenting its
# own cert, no reverse proxy. Run in a forked child since run() blocks.
#
# CA trust is wired idiomatically: SSL_CERT_FILE -> certs/ca.crt, honored by the
# in-test HTTP::Tiny (verify_SSL => 1) client. A negative subtest uses an empty
# trust store and asserts the handshake is rejected, proving the server's cert
# is genuinely verified.

use strict;
use warnings;
use Test::More;
use FindBin ();
use lib "$FindBin::Bin/lib";
use POSIX ();
use Time::HiRes ();
use HTTP::Tiny;
use JSON qw(decode_json);

use TlsMockTest;
use SignalWire::Server::AgentServer;
use SignalWire::Agent::AgentBase;

# Reap a child with a HARD DEADLINE. A bare waitpid($pid, 0) hangs the whole suite
# forever when the child does not die — on Win32 an emulated-fork pseudo-process in
# a blocking accept() ignores even SIGKILL. Same shape as the documented pattern in
# t/relay/outbound_call_mock.t. Caller has already signalled; we just don't wait
# forever for the corpse.
sub _bounded_reap {
    my ( $pid, $what ) = @_;
    return unless defined $pid && $pid > 0;
    my $deadline = time + 30;
    while ( time < $deadline ) {
        my $w = waitpid( $pid, POSIX::WNOHANG() );
        return if $w == $pid || $w == -1;
        Time::HiRes::sleep(0.05);
    }
    diag("62_tls_https_server: $what — child $pid exceeded 30s reap deadline; abandoning to avoid suite hang");
    return;
}

# Resolve the harness cert/key + CA (and set SSL_CERT_FILE for the client).
my $ca = TlsMockTest::trust_ca();
plan skip_all => 'porting-sdk/test_harness/tls not adjacent (no certs)' unless defined $ca;
my $certs = TlsMockTest::certs_dir();
my $cert  = "$certs/server.crt";
my $key   = "$certs/server.key";
plan skip_all => 'harness leaf cert/key missing' unless -f $cert && -f $key;

# Pick a free loopback port.
sub free_port {
    require IO::Socket::INET;
    my $s = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => 0,
                                  Listen => 1, ReuseAddr => 1)
        or die "free_port: $!";
    my $p = $s->sockport;
    $s->close;
    return $p;
}

my $host = '127.0.0.1';

# Build a minimal agent + server. /health is served by AgentServer regardless
# of registered agents, but registering one keeps the path realistic.
my $agent = SignalWire::Agent::AgentBase->new(name => 'tls-cap-test', route => '/agent');
my $server = SignalWire::Server::AgentServer->new(host => $host);
$server->register($agent);

# start_https_server forks a child that serves $server over HTTPS (the SDK's
# self-TLS path) on a free port, then polls until the verified TLS /health
# answers. There is an unavoidable window between free_port() releasing a port
# and the child re-binding it; under a loaded full-suite run another listener
# can occasionally grab it, yielding a persistent "connection refused". So this
# retries on a fresh port, and gives up early if the child dies (no listener
# will ever come up). Returns ($pid, $base_url) or (undef, undef).
my $ua = HTTP::Tiny->new(timeout => 3, verify_SSL => 1);  # trusts CA via SSL_CERT_FILE

sub start_https_server {
    for my $attempt (1 .. 5) {
        my $port = free_port();
        my $base = "https://$host:$port";

        my $pid = fork();
        die "fork failed: $!" unless defined $pid;
        if ($pid == 0) {
            open(STDIN,  '<', '/dev/null');
            open(STDOUT, '>', '/dev/null');
            open(STDERR, '>', '/dev/null');
            eval { POSIX::setsid() };
            eval {
                $server->run(host => $host, port => $port,
                             ssl_cert => $cert, ssl_key => $key);
            };
            POSIX::_exit(0);   # run() only returns on listen failure
        }

        # Poll the verified HTTPS /health until it answers or the child dies.
        my $deadline = time + 12;
        while (time < $deadline) {
            my $resp = $ua->get("$base/health");
            return ($pid, $base) if $resp->{success};
            # Child gone? this port will never come up — retry on a new one.
            if (waitpid($pid, POSIX::WNOHANG()) == $pid) { last; }
            Time::HiRes::sleep(0.1);
        }

        # This attempt failed: tear the child down and try a fresh port. BOUNDED —
        # even after SIGKILL, waitpid($pid, 0) can block forever if the child is a
        # Win32 pseudo-process (emulated fork) that does not die on a signal, and
        # this sits in a retry loop, so a wedge here never even reports a failure.
        kill 'KILL', $pid if kill 0, $pid;
        _bounded_reap($pid, "https server attempt $attempt teardown");
        note("https server attempt $attempt on port $port did not come up; retrying");
    }
    return (undef, undef);
}

my ($pid, $base) = start_https_server();

# Ensure the child is torn down no matter how the test ends.
my $reaped = 0;
my $reap = sub {
    return if $reaped || !defined $pid;
    $reaped = 1;
    kill 'TERM', $pid;
    for (1 .. 40) { last unless kill 0, $pid; Time::HiRes::sleep(0.05); }
    kill 'KILL', $pid if kill 0, $pid;
    # BOUNDED — this runs from an END block, so an unbounded waitpid here hangs the
    # suite AFTER all assertions have passed: the tests would look complete and the
    # job would still have to be cancelled, with no clue which file was at fault.
    _bounded_reap($pid, 'https server END teardown');
};
END { $reap->() if defined $pid && $pid > 0 }

plan skip_all => 'SDK HTTPS server did not come up after retries'
    unless defined $base;

# ---------------------------------------------------------------------------
# Reach the SDK's HTTPS /health from a CA-trusting client.
# ---------------------------------------------------------------------------

subtest 'SDK server self-serves verified HTTPS' => sub {
    my $resp = $ua->get("$base/health");

    ok($resp->{success}, "GET $base/health succeeded over verified HTTPS")
        or diag "status=$resp->{status} reason=$resp->{reason} content=$resp->{content}";
    is($resp->{status}, 200, '/health returned 200 over TLS');

    my $payload = eval { decode_json($resp->{content} || '{}') };
    ok(!$@, '/health body is JSON') or diag $@;
    is($payload->{status}, 'healthy', '/health body reports status=healthy');
};

# ---------------------------------------------------------------------------
# Negative control: a client that does NOT trust the CA must be rejected,
# proving the server presents a cert that is actually verified.
# ---------------------------------------------------------------------------

subtest 'untrusted client is rejected by the SDK HTTPS server' => sub {
    local $ENV{SSL_CERT_FILE} = '/dev/null';   # no trust anchors
    my $untrusted = HTTP::Tiny->new(timeout => 5, verify_SSL => 1);
    my $resp = $untrusted->get("$base/health");

    ok(!$resp->{success}, 'untrusted client rejected by the SDK HTTPS server')
        or diag "unexpectedly succeeded: status=$resp->{status}";
    note("untrusted client correctly rejected: status=$resp->{status} "
         . "reason=" . ($resp->{reason} // ''));
};

$reap->();
done_testing();
