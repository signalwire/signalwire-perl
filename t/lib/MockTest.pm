package MockTest;

# Test helper for the porting-sdk mock_signalwire HTTP server.
#
# Mirrors the Python conftest fixtures and the Go pilot's mocktest package:
# - On first call to MockTest::client(), probe the mock's /__mock__/health on the
#   resolved port and either reuse a running mock server or spawn one as a
#   subprocess.
# - This process mints a UNIQUE random project (test_proj_<hex>) =>
#   unique Authorization header. journal_all()/journal_last() filter the shared
#   global journal client-side by that header, so a test sees ONLY its own
#   request — making the shared mock safe under file parallelism (`prove -j`)
#   with no SDK or mock-server change. Inspect the wire request via
#   MockTest::journal_last(). No reset is needed (the auth-filtered view starts
#   empty), and a global wipe would race a concurrent test.
# - Tests assert LAML AccountSid paths against $MockTest::PROJECT.
# - PORT: the CI gate's MOCK_SIGNALWIRE_PORT (a pre-spawned mock) is used when set;
#   otherwise a FREE ephemeral port is picked per run (PortPicker) — never a fixed
#   port, which would collide with a stale/concurrent mock and hang a health poll.

use strict;
use warnings;

use HTTP::Tiny;
use JSON qw(encode_json decode_json);
use MIME::Base64 qw(encode_base64);
use POSIX ();
use Time::HiRes qw(sleep);
use IPC::Open3 ();
use Symbol ();
use IO::Handle ();
use File::Spec ();
use Cwd ();
use Config ();

use SignalWire::REST::RestClient;

our $VERSION = '0.01';

use PortPicker ();

# Port: MOCK_SIGNALWIRE_PORT (set by the CI gate, which pre-spawns the mock)
# wins; otherwise pick a FREE port rather than a hardcoded default that would
# collide with a stale/concurrent mock and hang the suite.
our $HOST = '127.0.0.1';
our $PORT = ( $ENV{MOCK_SIGNALWIRE_PORT} && $ENV{MOCK_SIGNALWIRE_PORT} =~ /^[0-9]+$/ )
    ? $ENV{MOCK_SIGNALWIRE_PORT}
    : PortPicker::pick_free_port($HOST);
our $BASE_URL = "http://$HOST:$PORT";

our $TOKEN   = 'test_tok';

# The per-PROCESS project + its Authorization header. REST is pure
# request/response with no session handshake, so the isolation key is the
# Authorization header: each test process mints a UNIQUE random project
# (test_proj_<12 hex>) => Basic base64(project:token) => a unique header. The
# harness filters the shared global journal by that header (client-side) and
# scopes scenario overrides by it (server-side), so a test only ever
# sees/consumes its own requests and scenarios — parallel-safe under `prove -j`
# with NO SDK or mock-server change. Random (not a counter) so concurrent
# processes/machines hitting one shared mock can't collide.
#
# Minted at module-load time so $MockTest::PROJECT is final before a test file's
# top-level `my $BASE = ".../$MockTest::PROJECT/..."` runs. Tests assert LAML
# AccountSid paths against $MockTest::PROJECT, never a hard-coded test_proj.
our $ACTIVE_PROJECT;
our $ACTIVE_AUTH;
our $PROJECT;

_mint_project();

sub _mint_project {
    return if defined $ACTIVE_PROJECT;
    my $rand = '';
    $rand .= sprintf('%x', int(rand(16))) for 1 .. 12;
    $ACTIVE_PROJECT = "test_proj_$rand";
    $PROJECT = $ACTIVE_PROJECT;
    # Match SignalWire::REST::HttpClient->_build__auth_header exactly:
    # 'Basic ' . encode_base64("$project:$token", '').
    $ACTIVE_AUTH = 'Basic ' . encode_base64("$ACTIVE_PROJECT:$TOKEN", '');
    return;
}

# Singleton state. The mock server's lifetime is per-process: the first
# client() call probes for a running instance, then either reuses it or
# spawns one as a subprocess.
our $_UA;
our $_MOCK_PID;
our $_ENSURED = 0;
our $_SKIP_REASON;

# Public API ---------------------------------------------------------------

# client() returns a SignalWire::REST::RestClient pointed at the mock.
#
# Each call mints a UNIQUE per-process random project (test_proj_<12 hex>) on
# first use and reuses it for the lifetime of the process. REST is pure
# request/response with no session handshake, so the isolation key is the
# Authorization header: a unique project => Basic base64(project:token) => a
# unique header. journal()/journal_last() filter the shared global journal by
# that header (client-side), so a test only ever sees its own requests even
# when the shared mock is driven concurrently by other test files under
# `prove -j` — parallel-safe with NO SDK and NO mock-server change.
#
# Mirrors the TS frozen design (tests/rest/mocktest.ts newMockClient): random
# (not a counter) suffix so concurrent processes/machines can't collide. Tests
# that assert on the AccountSid in a LAML path read $MockTest::PROJECT instead
# of hard-coding test_proj.
#
# No journal reset is performed: this client starts with zero entries in its
# auth-filtered view, and a global wipe would race a concurrent test's frames.
sub client {
    _ensure_server();
    if ($_SKIP_REASON) {
        Test::More::plan(skip_all => "MockTest: $_SKIP_REASON");
        exit 0;
    }
    return SignalWire::REST::RestClient->new(
        project => $PROJECT,
        token   => $TOKEN,
        host    => $BASE_URL,
    );
}

# journal_reset clears request entries on the mock. With a per-test scoped
# project active, this is a NO-OP: the auth-filtered view starts empty for a
# fresh project and a global wipe would race a concurrent test's in-flight
# frames on the shared mock. Only an unscoped harness (no client() yet) does
# the legacy global reset. (Mirrors TS MockHarness.reset.)
sub journal_reset {
    _ensure_server();
    return if $_SKIP_REASON;
    return if defined $ACTIVE_AUTH;
    my $resp = _ua()->post("$BASE_URL/__mock__/journal/reset");
    die "journal_reset failed: $resp->{status}" unless $resp->{success};
}

# scenario_reset clears one-shot scenarios. Scoped to this client's auth header
# when a project is active (so a concurrent test's armed scenarios are left
# alone); unscoped harness clears the shared bucket.
sub scenario_reset {
    _ensure_server();
    return if $_SKIP_REASON;
    my $q = _scope_query();
    my $resp = _ua()->post("$BASE_URL/__mock__/scenarios/reset$q");
    die "scenario_reset failed: $resp->{status}" unless $resp->{success};
}

# scenario_set stages a one-shot response override for the named OperationId.
# scenario_set("calling.call-commands", 500, { error => "boom" })
# Scoped to this client's auth header (?session_id=<urlencoded auth>) when a
# project is active, so a concurrent test can't consume it; unscoped =>
# shared bucket. Matches the mock's REST session key == Authorization header.
sub scenario_set {
    my ($endpoint_id, $status, $response_body) = @_;
    _ensure_server();
    return if $_SKIP_REASON;
    my $payload = encode_json({ status => $status, response => $response_body });
    my $resp = _ua()->post(
        "$BASE_URL/__mock__/scenarios/$endpoint_id" . _scope_query(),
        { content => $payload, headers => { 'Content-Type' => 'application/json' } },
    );
    die "scenario_set failed: $resp->{status} - $resp->{content}" unless $resp->{success};
}

# Build a `?session_id=<urlencoded auth header>` suffix scoping a control-plane
# call to this client, or '' when no project is active (unscoped/shared).
sub _scope_query {
    return '' unless defined $ACTIVE_AUTH;
    (my $enc = $ACTIVE_AUTH) =~ s/([^A-Za-z0-9_.~-])/sprintf('%%%02X', ord($1))/ge;
    return "?session_id=$enc";
}

# journal_all returns the array-of-hashref of recorded requests in arrival
# order. Scoped to THIS client's Authorization header (client-side filter on
# the lowercase `authorization` key — Starlette lowercases header names) when a
# project is active, so a parallel test never sees another test's requests.
sub journal_all {
    _ensure_server();
    die "MockTest: $_SKIP_REASON" if $_SKIP_REASON;
    my $resp = _ua()->get("$BASE_URL/__mock__/journal");
    die "journal fetch failed: $resp->{status}" unless $resp->{success};
    my $entries = decode_json($resp->{content} || '[]');
    return $entries unless defined $ACTIVE_AUTH;
    return [ grep { ($_->{headers}{authorization} // '') eq $ACTIVE_AUTH } @$entries ];
}

# journal_last returns the most recently recorded request for THIS client.
# Dies if the journal is empty - every test that calls a mock-backed SDK
# method should produce at least one entry.
sub journal_last {
    my @entries = @{ journal_all() };
    die "MockTest: journal is empty - SDK call did not reach mock server"
        unless @entries;
    return $entries[-1];
}

# Internals ----------------------------------------------------------------

sub _ua {
    return $_UA ||= HTTP::Tiny->new( timeout => 5 );
}

# Resolve the directory containing the Python mock package (the value to put on
# PYTHONPATH so `python -m <name>` resolves), or undef if unreachable. Resolution
# order mirrors run-ci / the porting-sdk python gates:
#   1. $PORTING_SDK env var (run-ci exports it; CI checks porting-sdk out at a path
#      the adjacency walk MISSES — e.g. NESTED at <repo>/porting-sdk rather than a
#      sibling — so honor the explicit env first);
#   2. the upward adjacency walk for a SIBLING ../porting-sdk (the ~/src layout);
#   3. a NESTED <repo>/porting-sdk under each walked dir (the CI checkout layout).
# Returns the test_harness/<name> dir that holds the <name>/ package.
sub discover_porting_sdk_package {
    my ($name) = @_;

    my $ok = sub {
        my ($psdk_root) = @_;
        return undef unless defined $psdk_root && length $psdk_root;
        my $candidate = File::Spec->catdir($psdk_root, 'test_harness', $name);
        my $init = File::Spec->catfile($candidate, $name, '__init__.py');
        return -f $init ? $candidate : undef;
    };

    # 1. Explicit PORTING_SDK env (what run-ci + the python gates use).
    if ( defined $ENV{PORTING_SDK} && length $ENV{PORTING_SDK} ) {
        my $hit = $ok->($ENV{PORTING_SDK});
        return $hit if $hit;
    }

    my $here = Cwd::abs_path(__FILE__);
    return undef unless defined $here;
    my $dir = File::Spec->canonpath((File::Spec->splitpath($here))[1]);
    # File::Spec->splitpath returns trailing slash on the directory, strip.
    $dir =~ s{[/\\]$}{};
    while (1) {
        # 2. SIBLING ../porting-sdk (the ~/src adjacency layout).
        my $parent = File::Spec->canonpath(File::Spec->catdir($dir, File::Spec->updir));
        my $sib = $ok->(File::Spec->catdir($parent, 'porting-sdk'));
        return $sib if $sib;
        # 3. NESTED <dir>/porting-sdk (the CI checkout at path: porting-sdk).
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
        # Reuse whatever's already listening (we did not spawn it).
        return;
    }

    # Try to inject porting-sdk/test_harness/mock_signalwire/ into
    # PYTHONPATH so `python -m mock_signalwire` resolves without a prior
    # `pip install -e ...`. Adjacency contract: porting-sdk next to
    # signalwire-perl in ~/src/. When the walk fails we still spawn — the
    # child falls back to whatever is on the system Python's sys.path,
    # and the readiness probe surfaces a clear timeout error if neither
    # mode is available.
    my $pkg_dir = discover_porting_sdk_package('mock_signalwire');
    my $sep = $Config::Config{path_sep} // ':';
    my $existing = defined $ENV{PYTHONPATH} ? $ENV{PYTHONPATH} : '';
    local $ENV{PYTHONPATH} = defined $pkg_dir
        ? ($existing ne '' ? "$pkg_dir$sep$existing" : $pkg_dir)
        : $existing;

    # Try to spawn `python -m mock_signalwire`. On any failure, set the
    # skip reason and leave it to client() to plan(skip_all).
    #
    # Spawn via fork+exec with the child's STDIN/STDOUT/STDERR redirected to
    # /dev/null. Do NOT use IPC::Open3 with the pipes closed right after: the mock
    # prints a startup banner, and once the read end of a closed pipe is gone that
    # write raises SIGPIPE and KILLS the mock before it binds — so the health poll
    # then times out (30s) and the whole thing SKIPs. Redirecting to /dev/null lets
    # the banner go nowhere harmlessly and the mock comes up.
    my @cmd = (
        'python', '-m', 'mock_signalwire',
        '--host', $HOST,
        '--port', $PORT,
        '--log-level', 'error',
    );

    my $pid = fork();
    if ( !defined $pid ) {
        $_SKIP_REASON = "could not fork to spawn `@cmd`: $!";
        return;
    }
    if ( $pid == 0 ) {
        # CHILD: detach the std handles to /dev/null, then exec the mock.
        open( STDIN,  '<', File::Spec->devnull );
        open( STDOUT, '>', File::Spec->devnull );
        open( STDERR, '>', File::Spec->devnull );
        { exec { $cmd[0] } @cmd; }
        POSIX::_exit(127);    # exec failed
    }
    $_MOCK_PID = $pid;

    # Reap on END to avoid zombies.
    eval {
        $SIG{CHLD} = 'IGNORE';
    };

    # Wait up to 30s for /__mock__/health.
    my $deadline = time + 30;
    while (time < $deadline) {
        if (_probe_health()) {
            return;
        }
        sleep 0.2;
    }

    $_SKIP_REASON = "mock_signalwire did not become ready on $BASE_URL within 30s "
                  . "(clone porting-sdk next to signalwire-perl so tests can find "
                  . "porting-sdk/test_harness/mock_signalwire/, or pip install the mock_signalwire package)";
    eval { kill 'TERM', $_MOCK_PID } if $_MOCK_PID;
}

sub _probe_health {
    my $resp = _ua()->get("$BASE_URL/__mock__/health");
    return 0 unless $resp->{success};
    my $payload = eval { decode_json($resp->{content} || '{}') };
    return 0 if $@;
    return exists $payload->{specs_loaded};
}

END {
    # We deliberately do NOT kill the spawned mock here. Under `prove -jN` the
    # mock is a per-PORT singleton shared across test-file PROCESSES: the first
    # file spawns it, the rest probe and REUSE it (only the spawner sets
    # $_MOCK_PID). If the spawner tore it down at its END, a sibling file still
    # issuing requests would lose the server mid-suite. So we leave the detached
    # mock running for the lifetime of the prove run; the next invocation's
    # probe reuses it (idempotent), and per-client auth-header journal scoping
    # keeps cross-run state clean. Strays are reaped by the suite's stale-mock
    # cleanup (`lsof -ti :$MOCK_SIGNALWIRE_PORT | xargs kill`, or the picked free
    # port). Mirrors the relay harness and the
    # TS `child.unref()` lifecycle. (REST is quick request/response so the race
    # is far less likely than the relay WS case, but the fix is identical and
    # makes both harnesses uniformly parallel-safe.)
}

1;

__END__

=head1 NAME

MockTest - test helper for the shared mock_signalwire HTTP server.

=head1 SYNOPSIS

    use lib 't/lib';
    use MockTest;
    use Test::More;

    my $client = MockTest::client();
    my $body = $client->compat->calls->start_stream(
        'CA_TEST', Url => 'wss://example.com/stream', Name => 'my-stream',
    );
    is(ref $body, 'HASH', 'response is a hashref');

    my $j = MockTest::journal_last();
    is($j->{method}, 'POST', 'POST recorded');
    is($j->{path},
       "/api/laml/2010-04-01/Accounts/$MockTest::PROJECT/Calls/CA_TEST/Streams",
       'path matches');
    is($j->{body}{Url}, 'wss://example.com/stream', 'body Url forwarded');

=head1 DESCRIPTION

The mock server's lifetime is per-process: the first MockTest::client()
call probes the mock's C</__mock__/health> on the resolved port and either
confirms a running server or starts one via `python -m mock_signalwire`. The
process mints a unique random project (C<test_proj_E<lt>hexE<gt>>), so its
Basic-Auth header is unique; journal_all()/journal_last() filter the shared
journal by that header and return only this process's requests, making the
shared mock safe under file parallelism (C<prove -j>) with no reset. Tests
assert LAML AccountSid paths against C<$MockTest::PROJECT>.

=head1 PORT

No fixed port is used. When the CI gate exports C<MOCK_SIGNALWIRE_PORT> (a
pre-spawned mock), that port is reused; otherwise a FREE ephemeral port is
picked per run (via C<PortPicker>) so concurrent/stale mocks never collide on a
hardcoded port and hang a health poll.

=cut
