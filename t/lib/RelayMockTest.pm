package RelayMockTest;

# Test helper for the porting-sdk mock_relay WebSocket server.
#
# Mirrors MockTest.pm but for RELAY:
# - Probes the mock-relay HTTP control plane's /__mock__/health on the resolved
#   HTTP port to find/spawn mock-relay (two independent planes: a WS plane and an
#   HTTP control plane).
# - Reuses MockTest's adjacency walk to find porting-sdk/test_harness/mock_relay
#   and prepends to PYTHONPATH for `python -m mock_relay`.
# - Test pattern:
#       my $client = RelayMockTest::client(contexts => ["default"]);
#       $client->connect;  # combined connect_ws + authenticate
#       ... drive SDK ...
#       my $entry = RelayMockTest::journal_last();
#       is($entry->{method}, "signalwire.connect", "...");
#
# PORT: the CI gate's MOCK_RELAY_PORT / MOCK_RELAY_HTTP_PORT (a pre-spawned mock)
# are used when set; otherwise two FREE ephemeral ports are picked per run (WS and
# HTTP control plane independently) — never fixed ports, which would collide with a
# stale/concurrent mock and hang a health poll.

use strict;
use warnings;

use HTTP::Tiny;
use JSON qw(encode_json decode_json);
use POSIX ();
use Time::HiRes qw(sleep time);
use IPC::Open3 ();
use Symbol ();
use IO::Handle ();
use File::Spec ();
use Cwd ();
use Config ();

use SignalWire::Relay::Client;

our $VERSION = '0.01';

use PortPicker ();

# Ports: env overrides win; otherwise pick FREE ports (WS and HTTP control
# plane independently) rather than hardcoded defaults that collide with a
# stale/concurrent mock and hang the suite.
our $HOST      = '127.0.0.1';
our $WS_PORT   = ( $ENV{MOCK_RELAY_PORT} && $ENV{MOCK_RELAY_PORT} =~ /^[0-9]+$/ )
    ? $ENV{MOCK_RELAY_PORT}
    : PortPicker::pick_free_port($HOST);
our $HTTP_PORT = ( $ENV{MOCK_RELAY_HTTP_PORT} && $ENV{MOCK_RELAY_HTTP_PORT} =~ /^[0-9]+$/ )
    ? $ENV{MOCK_RELAY_HTTP_PORT}
    : PortPicker::pick_free_port($HOST);
our $WS_URL    = "ws://$HOST:$WS_PORT";
our $HTTP_URL  = "http://$HOST:$HTTP_PORT";
our $RELAY_HOST = "$HOST:$WS_PORT";

our $PROJECT = 'test_proj';
our $TOKEN   = 'test_tok';

# Singleton state: spawn once per process.
our $_UA;
our $_MOCK_PID;
our $_ENSURED = 0;
our $_SKIP_REASON;

# Public API ---------------------------------------------------------------

# The client most recently handed out by client(). Journal/scenario calls that
# aren't given an explicit session_id default to THIS client's handshake
# session (once it connects), so a test transparently sees only its own frames
# even when the shared mock is driven by other tests in parallel processes.
# Within one test file prove runs tests serially, so "the active client" is
# unambiguous; cross-file isolation is exactly what the session scoping buys.
our $_ACTIVE_CLIENT;

# client(%opts) returns a SignalWire::Relay::Client pointed at the mock and
# registers it as the active client for default journal/scenario scoping.
#
# NO global journal/scenario reset is performed: each connect yields a brand-new
# server session whose scoped journal starts empty, so a reset is unnecessary
# AND a global wipe would race a concurrent test's in-flight frames on the
# shared mock. (Mirrors the TS frozen design: fresh client + per-session view,
# no global reset.) Does NOT connect — caller must $client->connect.
sub client {
    my %opts = @_;
    _ensure_server();
    if ($_SKIP_REASON) {
        if (eval { require Test::More; 1 }) {
            Test::More::plan(skip_all => "RelayMockTest: $_SKIP_REASON");
        }
        die "RelayMockTest: $_SKIP_REASON";
    }

    my $client = SignalWire::Relay::Client->new(
        project  => $opts{project}  // $PROJECT,
        token    => $opts{token}    // $TOKEN,
        host     => $opts{host}     // $RELAY_HOST,
        scheme   => $opts{scheme}   // 'ws',
        path     => exists $opts{path} ? $opts{path} : '',
        contexts => $opts{contexts} // [],
        (exists $opts{agent} ? (agent => $opts{agent}) : ()),
    );
    $_ACTIVE_CLIENT = $client;
    return $client;
}

# scope($client) makes $client the active client for default scoping and
# returns it (so a test can write `my $c = RelayMockTest::scope($mine);`).
# Use this for clients built by hand (not via client()), or to re-point the
# default scope at a specific client in a multi-client test.
sub scope {
    my ($client) = @_;
    $_ACTIVE_CLIENT = $client;
    return $client;
}

# The session id to scope a control-plane call to: an explicit session_id arg
# wins; otherwise the active client's handshake session (empty until connect).
# An empty string means "global view" (unscoped), preserving back-compat for
# callers that pass session_id => '' or run before any client connected.
sub _scope_session {
    my (%opts) = @_;
    return $opts{session_id} if exists $opts{session_id};
    return undef unless $_ACTIVE_CLIENT;
    my $sid = eval { $_ACTIVE_CLIENT->session_id };
    return (defined $sid && $sid ne '') ? $sid : undef;
}

# Connect a fresh client (helper that does both connect_ws + authenticate).
sub connect_client {
    my ($client) = @_;
    my $ok = $client->connect_ws;
    die "RelayMockTest: connect_ws failed" unless $ok;
    my $r = $client->authenticate;
    die "RelayMockTest: authenticate failed" unless $r;
    return $r;
}

# Build a `?session_id=<urlencoded id>` query suffix when a session id is
# supplied, else the empty string. The session id is the server-assigned
# `sessionid` from the RELAY connect handshake (== $client->session_id).
# Threading it onto a control-plane call scopes that call to one connection's
# frames, so concurrent tests against the shared mock never see each other's
# (parallel-safe). Absent => global view (back-compat, correct under serial).
sub _session_query {
    my ($sid) = @_;
    return '' unless defined $sid && $sid ne '';
    # Percent-encode anything outside the unreserved set; session ids are hex
    # in practice, but encode defensively so an arbitrary id is URL-safe.
    (my $enc = $sid) =~ s/([^A-Za-z0-9_.~-])/sprintf('%%%02X', ord($1))/ge;
    return "?session_id=$enc";
}

# Inject $sid into a scenario_play timeline op's push/expect_recv spec when the
# op doesn't already specify a session_id. Leaves sleep ops untouched. Returns
# a shallow copy so the caller's ops array is not mutated.
sub _scope_op {
    my ($op, $sid) = @_;
    return $op unless ref $op eq 'HASH';
    my %out = %$op;
    for my $key (qw(push expect_recv)) {
        my $spec = $out{$key};
        if (ref $spec eq 'HASH' && !exists $spec->{session_id}) {
            $out{$key} = { %$spec, session_id => $sid };
        }
    }
    return \%out;
}

# journal_reset clears journal entries on the mock. With session_id => <id>,
# clears only that session's entries (parallel-safe); absent => clears all.
sub journal_reset {
    my (%opts) = @_;
    _ensure_server();
    return if $_SKIP_REASON;
    my $q = _session_query(_scope_session(%opts));
    # Retry: the mock may be transiently unreachable during cross-test
    # spawn races (HTTP::Tiny 599 = internal connect/timeout).
    my $resp;
    for my $i (1..10) {
        $resp = _ua()->post("$HTTP_URL/__mock__/journal/reset$q");
        last if $resp->{success};
        Time::HiRes::sleep(0.1);
    }
    die "journal_reset failed: $resp->{status}" unless $resp->{success};
}

# scenario_reset clears queued scenarios on the mock. With session_id => <id>,
# clears only that session's armed scenarios (parallel-safe); absent => all.
sub scenario_reset {
    my (%opts) = @_;
    _ensure_server();
    return if $_SKIP_REASON;
    my $q = _session_query(_scope_session(%opts));
    my $resp;
    for my $i (1..10) {
        $resp = _ua()->post("$HTTP_URL/__mock__/scenarios/reset$q");
        last if $resp->{success};
        Time::HiRes::sleep(0.1);
    }
    die "scenario_reset failed: $resp->{status}" unless $resp->{success};
}

# journal_all returns recorded frames since reset. With session_id => <id>,
# returns only that session's frames (parallel-safe); absent => every frame.
sub journal_all {
    my (%opts) = @_;
    _ensure_server();
    die "RelayMockTest: $_SKIP_REASON" if $_SKIP_REASON;
    my $q = _session_query(_scope_session(%opts));
    my $resp = _ua()->get("$HTTP_URL/__mock__/journal$q");
    die "journal fetch failed: $resp->{status}" unless $resp->{success};
    return decode_json($resp->{content} || '[]');
}

# journal_last returns the most recently recorded frame (optionally scoped to
# session_id => <id>).
sub journal_last {
    my (%opts) = @_;
    my @entries = @{ journal_all(%opts) };
    die "RelayMockTest: journal is empty - no SDK frames reached the mock"
        unless @entries;
    return $entries[-1];
}

# journal_recv returns inbound (SDK→server) frames, optionally filtered by
# method and/or scoped to session_id => <id>.
sub journal_recv {
    my (%opts) = @_;
    # Forward an explicit session_id to journal_all; if absent, journal_all
    # applies the active-client default via _scope_session.
    my %scope = exists $opts{session_id} ? (session_id => $opts{session_id}) : ();
    my @entries = grep { ($_->{direction} // '') eq 'recv' } @{ journal_all(%scope) };
    if (defined $opts{method}) {
        @entries = grep { ($_->{method} // '') eq $opts{method} } @entries;
    }
    return \@entries;
}

# journal_send returns outbound (server→SDK) frames, optionally filtered by
# event_type and/or scoped to session_id => <id>.
sub journal_send {
    my (%opts) = @_;
    my %scope = exists $opts{session_id} ? (session_id => $opts{session_id}) : ();
    my @entries = grep { ($_->{direction} // '') eq 'send' } @{ journal_all(%scope) };
    if (defined $opts{event_type}) {
        my $et = $opts{event_type};
        @entries = grep {
            my $f = $_->{frame} // {};
            my $p = $f->{params} // {};
            ($f->{method} // '') eq 'signalwire.event'
              && ref $p eq 'HASH'
              && ($p->{event_type} // '') eq $et;
        } @entries;
    }
    return \@entries;
}

# arm_method queues scripted post-RPC events for `method` (FIFO, consume-once).
# With session_id => <id>, the scenario is scoped to that session so a parallel
# test can't consume it; absent => shared bucket.
sub arm_method {
    my ($method, $events, %opts) = @_;
    _ensure_server();
    return if $_SKIP_REASON;
    my $q = _session_query(_scope_session(%opts));
    my $body = encode_json($events);
    my $resp = _ua()->post(
        "$HTTP_URL/__mock__/scenarios/$method$q",
        { content => $body, headers => { 'Content-Type' => 'application/json' } },
    );
    die "arm_method failed: $resp->{status} - $resp->{content}" unless $resp->{success};
}

# arm_dial queues a dial-dance scenario (winner state events + final dial
# event). With session_id => <id>, the scenario is scoped to that session;
# the mock also accepts the id in the body, but we put it on the query string
# to match the other control-plane endpoints.
sub arm_dial {
    my (%kwargs) = @_;
    _ensure_server();
    return if $_SKIP_REASON;
    my %sopt = exists $kwargs{session_id} ? (session_id => delete $kwargs{session_id}) : ();
    my $q = _session_query(_scope_session(%sopt));
    my $body = encode_json(\%kwargs);
    my $resp = _ua()->post(
        "$HTTP_URL/__mock__/scenarios/dial$q",
        { content => $body, headers => { 'Content-Type' => 'application/json' } },
    );
    die "arm_dial failed: $resp->{status} - $resp->{content}" unless $resp->{success};
}

# push a single signalwire.event (or other) frame to the SDK over WS.
sub push_frame {
    my ($frame, %opts) = @_;
    _ensure_server();
    return if $_SKIP_REASON;
    my $url = "$HTTP_URL/__mock__/push" . _session_query(_scope_session(%opts));
    my $body = encode_json({ frame => $frame });
    my $resp = _ua()->post(
        $url,
        { content => $body, headers => { 'Content-Type' => 'application/json' } },
    );
    die "push_frame failed: $resp->{status} - $resp->{content}" unless $resp->{success};
    return decode_json($resp->{content} // '{}');
}

# inbound_call pushes a calling.call.receive frame (and optional state events).
sub inbound_call {
    my (%opts) = @_;
    _ensure_server();
    return if $_SKIP_REASON;
    my %body = (
        from_number => $opts{from_number} // '+15551234567',
        to_number   => $opts{to_number}   // '+15559876543',
        context     => $opts{context}     // 'default',
        auto_states => $opts{auto_states} // ['created'],
        delay_ms    => $opts{delay_ms}    // 50,
    );
    $body{call_id} = $opts{call_id} if exists $opts{call_id};
    # Default to the active client's session so the inbound-call sequence is
    # delivered only to this test's client (parallel-safe); an explicit
    # session_id wins, and an empty string broadcasts (legacy behavior).
    my $sid = _scope_session(%opts);
    $body{session_id} = $sid if defined $sid && $sid ne '';
    my $payload = encode_json(\%body);
    my $resp = _ua()->post(
        "$HTTP_URL/__mock__/inbound_call",
        { content => $payload, headers => { 'Content-Type' => 'application/json' } },
    );
    die "inbound_call failed: $resp->{status} - $resp->{content}" unless $resp->{success};
    return decode_json($resp->{content} // '{}');
}

# scenario_play runs a scripted timeline (push/sleep/expect_recv ops). With
# session_id => <id>, every push/expect_recv op that doesn't already carry a
# session_id is stamped with it (mirrors the TS harness's scopeOp), so the
# timeline targets only that session's client and expect_recv matches only
# that session's frames — making it parallel-safe. sleep ops are left as-is.
sub scenario_play {
    my ($ops, %opts) = @_;
    _ensure_server();
    return if $_SKIP_REASON;
    my $sid = _scope_session(%opts);
    if (defined $sid && $sid ne '') {
        $ops = [ map { _scope_op($_, $sid) } @$ops ];
    }
    my $body = encode_json($ops);
    my $ua = _ua();
    # scenario_play can take longer due to expect_recv waits; bump timeout.
    my $resp = $ua->post(
        "$HTTP_URL/__mock__/scenario_play",
        { content => $body, headers => { 'Content-Type' => 'application/json' } },
    );
    die "scenario_play failed: $resp->{status} - $resp->{content}" unless $resp->{success};
    return decode_json($resp->{content} // '{}');
}

# pump_for($client, $seconds) drives the client's recv loop for up to N seconds.
# Useful when a test pushes a server-initiated event and needs the SDK to
# process it before assertions.
sub pump_for {
    my ($client, $seconds, $until_cb) = @_;
    my $deadline = time() + $seconds;
    while (time() < $deadline) {
        eval { $client->_read_once };
        last if $until_cb && eval { $until_cb->($client) };
    }
}

# pump_until($client, $seconds, sub { ... predicate ... })
# Drive the recv loop until the predicate returns truthy or timeout expires.
sub pump_until {
    my ($client, $seconds, $cb) = @_;
    my $deadline = time() + $seconds;
    while (time() < $deadline) {
        return 1 if eval { $cb->() };
        eval { $client->_read_once };
    }
    return eval { $cb->() } ? 1 : 0;
}

# Internals ----------------------------------------------------------------

sub _ua {
    return $_UA ||= HTTP::Tiny->new( timeout => 30 );
}

# Walk this file's directory upward looking for an adjacent
# ../porting-sdk/test_harness/mock_relay/mock_relay/__init__.py.
# Returns the absolute path to the directory containing the Python package,
# or undef when no adjacent porting-sdk is reachable.
# Resolve the test_harness/<name> dir holding the Python mock package. Resolution
# order mirrors run-ci / the python gates: $PORTING_SDK env first (CI checks
# porting-sdk out NESTED at <repo>/porting-sdk, which the sibling adjacency walk
# misses), then a SIBLING ../porting-sdk, then a NESTED <dir>/porting-sdk.
sub discover_porting_sdk_package {
    my ($name) = @_;

    my $ok = sub {
        my ($psdk_root) = @_;
        return undef unless defined $psdk_root && length $psdk_root;
        my $candidate = File::Spec->catdir($psdk_root, 'test_harness', $name);
        my $init = File::Spec->catfile($candidate, $name, '__init__.py');
        return -f $init ? $candidate : undef;
    };

    if ( defined $ENV{PORTING_SDK} && length $ENV{PORTING_SDK} ) {
        my $hit = $ok->($ENV{PORTING_SDK});
        return $hit if $hit;
    }

    my $here = Cwd::abs_path(__FILE__);
    return undef unless defined $here;
    my $dir = File::Spec->canonpath((File::Spec->splitpath($here))[1]);
    $dir =~ s{[/\\]$}{};
    while (1) {
        my $parent = File::Spec->canonpath(File::Spec->catdir($dir, File::Spec->updir));
        my $sib = $ok->(File::Spec->catdir($parent, 'porting-sdk'));
        return $sib if $sib;
        my $nested = $ok->(File::Spec->catdir($dir, 'porting-sdk'));
        return $nested if $nested;
        last if $parent eq $dir;
        $dir = $parent;
    }
    return undef;
}

sub _ensure_server {
    return if $_ENSURED;
    $_ENSURED = 1;

    # Probe first.
    if (_probe_health()) {
        # Reuse whatever's already listening.
        return;
    }

    # Find porting-sdk/test_harness/mock_relay/ and put it on PYTHONPATH so
    # `python -m mock_relay` resolves without a prior `pip install -e ...`.
    my $pkg_dir = discover_porting_sdk_package('mock_relay');
    my $sep = $Config::Config{path_sep} // ':';
    my $existing = defined $ENV{PYTHONPATH} ? $ENV{PYTHONPATH} : '';
    local $ENV{PYTHONPATH} = defined $pkg_dir
        ? ($existing ne '' ? "$pkg_dir$sep$existing" : $pkg_dir)
        : $existing;

    my @cmd = (
        'python3', '-m', 'mock_relay',
        '--host', $HOST,
        '--ws-port',   $WS_PORT,
        '--http-port', $HTTP_PORT,
        '--log-level', 'error',
    );

    # fork() + redirect stderr/stdout to /dev/null in the child so the
    # mock's startup banner doesn't fill a closed-pipe and SIGPIPE the
    # process. IPC::Open3 leaves the child wired to perl's stderr/stdout
    # pipes; once we close them on the parent side the child dies on the
    # next write.
    my $pid = fork();
    if (!defined $pid) {
        $_SKIP_REASON = "fork failed: $!";
        return;
    }
    if ($pid == 0) {
        # Child.
        open(STDIN,  '<', '/dev/null');
        open(STDOUT, '>', '/dev/null');
        open(STDERR, '>', '/dev/null');
        # POSIX::setsid lets the parent's process group not propagate
        # SIGINT to the mock when a test runner Ctrl-C's.
        eval { POSIX::setsid() };
        exec(@cmd) or do {
            warn "exec failed: $!";
            POSIX::_exit(127);
        };
    }
    $_MOCK_PID = $pid;

    eval { $SIG{CHLD} = 'IGNORE' };

    # Wait up to 30s for /__mock__/health.
    my $deadline = time + 30;
    while (time < $deadline) {
        return if _probe_health();
        sleep 0.2;
    }

    $_SKIP_REASON = "mock_relay did not become ready on $HTTP_URL within 30s "
                  . "(clone porting-sdk next to signalwire-perl, or pip install mock_relay)";
    eval { kill 'TERM', $_MOCK_PID } if $_MOCK_PID;
}

sub _probe_health {
    my $resp = _ua()->get("$HTTP_URL/__mock__/health");
    return 0 unless $resp->{success};
    my $payload = eval { decode_json($resp->{content} || '{}') };
    return 0 if $@;
    return exists $payload->{schemas_loaded};
}

END {
    # Preserve the test's exit status; waitpid otherwise stomps $?.
    local $?;
    # We deliberately do NOT kill the spawned mock here.
    #
    # Under `prove -jN` the mock is a per-PORT singleton shared across test-file
    # PROCESSES: the first file to run spawns it, every other file probes and
    # REUSES it (only the spawner sets $_MOCK_PID). If the spawner tore the mock
    # down at its END, any sibling file still mid-WS-session would have its
    # socket yanked — surfacing as a process that "passed all subtests" yet
    # exits 255 (WS drop on teardown) or hangs forever on an expect_recv that
    # can never arrive. That race is exactly what breaks the suite under -j.
    #
    # So we leave the detached (setsid'd, stdio-to-/dev/null) mock running for
    # the lifetime of the prove run. The next invocation's _ensure_server probe
    # reuses it (idempotent), and per-session journal/scenario scoping keeps
    # cross-run state clean. Strays are reaped by the suite's stale-mock cleanup
    # (`lsof -ti :$MOCK_RELAY_HTTP_PORT :$MOCK_RELAY_PORT | xargs kill`, or the
    # picked free ports). This mirrors the TS harness's
    # `child.unref()` lifecycle (tests/relay/mocktest.ts) — detach, never kill.
    #
    # $_MOCK_PID is retained only so a *failed* startup (below) can TERM the
    # half-spawned child; a healthy mock is intentionally left alone.
}

1;

__END__

=head1 NAME

RelayMockTest - test helper for the shared mock_relay WebSocket server.

=head1 SYNOPSIS

    use lib 't/lib';
    use RelayMockTest;
    use Test::More;

    my $client = RelayMockTest::client(contexts => ["default"]);
    $client->connect_ws;
    $client->authenticate;

    is($client->protocol =~ /^signalwire_/, 1, 'protocol assigned');

    my $j = RelayMockTest::journal_last();
    is($j->{method}, 'signalwire.connect', 'connect frame recorded');

=head1 DESCRIPTION

The mock server's lifetime is per-process: the first RelayMockTest::client()
call probes the mock-relay HTTP control plane's C</__mock__/health> on the
resolved HTTP port and either confirms a running server or starts one via
`python -m mock_relay`. Each test that calls C<client()> gets a freshly-reset
journal and scenarios.

The mock is a real WebSocket server (no monkey-patching). It speaks
ws://, so callers pass C<scheme =E<gt> 'ws'> to the SDK.

=head1 PORTS

No fixed ports are used. When the CI gate exports MOCK_RELAY_PORT /
MOCK_RELAY_HTTP_PORT (a pre-spawned mock), those are reused; otherwise two FREE
ephemeral ports are picked per run (the WS plane and the HTTP control plane
independently) so concurrent/stale mocks never collide on hardcoded ports and
hang a health poll.

=cut
