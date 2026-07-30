#!/usr/bin/env perl
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# emit-envelope.pl — the Perl port's REST error-ENVELOPE dump program for the
# cross-port envelope differ (porting-sdk/scripts/diff_port_envelope.py).
#
# It runs the shared error-envelope corpus
# (porting-sdk/scripts/envelope_corpus.py — the single source of truth) against
# the Perl SDK's REAL REST client driven at a live mock_signalwire server, and
# prints ONE JSON object mapping
#
#     case-id -> reduced-artifact
#
# to stdout. The differ builds the golden Python oracle the same way and
# byte-compares each artifact. Only stdout carries the JSON object; logs and
# diagnostics go to stderr.
#
# The reduced artifact is the shared cross-port denominator (see the
# envelope_corpus module docstring):
#
#     {
#       "raised":          <bool>,       # a typed error was raised (vs a success)
#       "error_kind":      "typed" | "bare:<Class>" | null,
#       "status_code":     <int|null>,   # the HTTP status the client decoded, or
#                                        # null for a TRANSPORT failure (no status)
#       "body_error_code": <str|null>,   # decoded errors[0].code, or null
#       "request_count":   <int>         # journal hits for this route (1 == no retry)
#     }
#
# CONTRACT (why this file looks the way it does):
#   - The corpus is read at runtime from the shared spec
#     (porting-sdk/scripts/envelope_corpus.py's CORPUS, data-only — it does NOT
#     import signalwire-python), so the id/case set is IDENTICAL to the oracle by
#     construction.
#   - Each non-transport case ARMS a one-shot scenario on the mock
#     (`POST /__mock__/scenarios/<endpoint>?session_id=<auth>`), scoped to THIS
#     process's Authorization header so a concurrent test can't consume it, then
#     runs the real client and reduces the raised SignalWireRestError.
#   - A `transport` case points the client at a DEAD port (a free port bound then
#     released, so nothing is listening) — the connection-refused path. A correct
#     client raises its TYPED transport error (SignalWireRestTransportError, a
#     SignalWireRestError-family member, status_code => undef) => error_kind
#     "typed", status_code null, request_count 0. A client leaking a bare
#     HTTP::Tiny synthetic-599 error would report bare:<Class> and FAIL.
#   - request_count is read from the mock JOURNAL (auth-scoped to this process),
#     counting entries whose path matches the call — 1 proves NO retry, 0 proves
#     nothing reached a server (transport).
#
# Run from the signalwire-perl repo root:
#
#     perl bin/emit-envelope.pl
#
# (the differ invokes exactly this; see PORT_DUMP_CMDS / --dump-cmd).

use strict;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use FindBin qw($RealBin);
use File::Spec;
use JSON             ();
use HTTP::Tiny       ();
use IO::Socket::INET ();
use Scalar::Util     ();
use POSIX            ();
use Time::HiRes      ();

# Make the SDK importable when run from the repo root (bin/.. = repo root; lib/
# and t/lib are siblings of bin/).
use lib File::Spec->catdir( $RealBin, File::Spec->updir, 'lib' );
use lib File::Spec->catdir( $RealBin, File::Spec->updir, 't', 'lib' );

use SignalWire::REST::HttpClient;
use SignalWire::REST::RestClient;
use SignalWire::REST::RequestOptions;
use MockTest ();

# The mock child pid we spawn (if any), torn down on exit.
my $OUR_MOCK_PID;

# --------------------------------------------------------------------------- #
# Locate + load the shared corpus spec.
# --------------------------------------------------------------------------- #
# The corpus is the SINGLE source of truth (porting-sdk/scripts/envelope_corpus.py's
# CORPUS list — data-only; it does NOT import signalwire-python). It has no CLI
# dumper, so we import the module and print CORPUS as JSON via a tiny python
# invocation. We locate the scripts/ dir by walking up from this file to an
# adjacent porting-sdk/ checkout (the same adjacency contract MockTest uses).
sub find_corpus_dir {
    if ( my $p = $ENV{ENVELOPE_CORPUS_DIR} ) {
        return $p if -d $p;
        die "emit-envelope: ENVELOPE_CORPUS_DIR=$p is not a directory\n";
    }
    my $dir = $RealBin;
    for ( 1 .. 8 ) {
        my $cand = File::Spec->catdir( $dir, File::Spec->updir, 'porting-sdk', 'scripts' );
        return File::Spec->rel2abs($cand)
            if -f File::Spec->catfile( $cand, 'envelope_corpus.py' );
        my $parent = File::Spec->catdir( $dir, File::Spec->updir );
        last if File::Spec->rel2abs($parent) eq File::Spec->rel2abs($dir);
        $dir = $parent;
    }
    my $home = $ENV{HOME} // '';
    if ($home) {
        my $cand = File::Spec->catdir( $home, 'src', 'porting-sdk', 'scripts' );
        return File::Spec->rel2abs($cand)
            if -f File::Spec->catfile( $cand, 'envelope_corpus.py' );
    }
    die "emit-envelope: cannot locate porting-sdk/scripts/envelope_corpus.py "
        . "(clone porting-sdk adjacent to this repo, or set ENVELOPE_CORPUS_DIR).\n";
}

sub load_corpus {
    my $dir = find_corpus_dir();
    local $ENV{ENVELOPE_CORPUS_SCRIPTS} = $dir;
    my $py =
          'import os,sys,json; sys.path.insert(0, os.environ["ENVELOPE_CORPUS_SCRIPTS"]); '
        . 'import envelope_corpus as ec; sys.stdout.write(json.dumps(ec.CORPUS))';
    my $json = qx{python3 -c '$py'};
    die "emit-envelope: failed to load envelope_corpus from $dir (exit $?)\n" if $? != 0;
    die "emit-envelope: empty corpus from $dir\n" unless length $json;
    return JSON->new->decode($json);
}

# --------------------------------------------------------------------------- #
# Mock control-plane helpers (arm scenario / reset / journal), auth-scoped to
# THIS process so a concurrent test on the shared mock can't cross-contaminate.
# --------------------------------------------------------------------------- #
my $UA = HTTP::Tiny->new( timeout => 10 );

sub scope_query {
    ( my $enc = $MockTest::ACTIVE_AUTH ) =~ s/([^A-Za-z0-9_.~-])/sprintf('%%%02X', ord($1))/ge;
    return "?session_id=$enc";
}

sub reset_journal {
    $UA->post("$MockTest::BASE_URL/__mock__/journal/reset");
    return;
}

sub reset_scenarios {
    $UA->post( "$MockTest::BASE_URL/__mock__/scenarios/reset" . scope_query() );
    return;
}

# Arm the FULL scenario JSON (status / response / headers? / delay_ms?) — unlike
# MockTest::scenario_set, which only forwards {status,response}, the corpus needs
# headers (Retry-After) + delay_ms passed through verbatim.
sub arm_scenario ( $endpoint, $scenario ) {
    my $payload = JSON->new->canonical->encode($scenario);
    my $resp    = $UA->post(
        "$MockTest::BASE_URL/__mock__/scenarios/$endpoint" . scope_query(),
        { content => $payload, headers => { 'Content-Type' => 'application/json' } },
    );
    die "emit-envelope: arm_scenario($endpoint) failed: $resp->{status} $resp->{content}\n"
        unless $resp->{success};
    return;
}

# Count journal entries (auth-scoped by MockTest::journal_all) whose path matches
# the call path — the retry check (1 == no retry, 0 == nothing reached a server).
sub request_count ($path) {
    my $entries = MockTest::journal_all();
    return scalar grep { ( $_->{path} // '' ) eq $path } @$entries;
}

# --------------------------------------------------------------------------- #
# Dead-port picker for the transport (connection-refused) case: bind an ephemeral
# port then release it, so nothing is listening on it.
# --------------------------------------------------------------------------- #
sub dead_port {
    my $s = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1',
        LocalPort => 0,
        Proto     => 'tcp',
        Listen    => 1,
    ) or die "emit-envelope: cannot bind a probe port: $!\n";
    my $port = $s->sockport;
    $s->close;
    return $port;
}

# --------------------------------------------------------------------------- #
# Decode errors[0].code out of a raised error's body (string or hashref), or
# undef — mirrors the oracle's _decode_body_error_code so the denominator is the
# same shape on both sides.
# --------------------------------------------------------------------------- #
sub decode_body_error_code ($body) {
    return unless defined $body;
    my $decoded = $body;
    if ( !ref $body ) {
        $decoded = eval { JSON::decode_json($body) };
        return if $@ || !defined $decoded;
    }
    return unless ref $decoded eq 'HASH';
    my $errs = $decoded->{errors};
    return unless ref $errs eq 'ARRAY' && @$errs && ref $errs->[0] eq 'HASH';
    my $code = $errs->[0]{code};
    return ( defined $code && !ref $code ) ? $code : undef;
}

# --------------------------------------------------------------------------- #
# Run one corpus case, return the reduced artifact hashref.
# --------------------------------------------------------------------------- #
sub run_case ($case) {
    my $call = $case->{call};
    my $path = $call->{path};

    my %artifact = (
        raised          => JSON::false,
        error_kind      => undef,
        status_code     => undef,
        body_error_code => undef,
        request_count   => 0,
    );

    # Fresh journal + scenarios per case so request_count is exact.
    reset_journal();
    reset_scenarios();

    # Arm the scenario. scenario_repeat arms the SAME override N times (FIFO) so a
    # retry-armed case sees the failure on every attempt (the mock consumes one
    # per request). Default 1 (a single arming) when the field is absent.
    my $scen = $case->{scenario};
    if ( defined $scen ) {
        my $repeat = $case->{scenario_repeat} // 1;
        arm_scenario( $case->{endpoint}, $scen ) for 1 .. $repeat;
    }

    # Per-request options (plan 4.2): the corpus supplies {retries?, retry_backoff?,
    # timeout?}; pass them as a RequestOptions so the retry-armed cases exercise the
    # real retry loop. retry_backoff is pinned to 0 in the corpus so no wall-clock
    # wait occurs. Absent => the port's default (retries 0, no retry).
    my $req_opts;
    if ( my $ro = $case->{request_options} ) {
        $req_opts = SignalWire::REST::RequestOptions->new(
            ( exists $ro->{retries}       ? ( retries       => $ro->{retries} )       : () ),
            ( exists $ro->{retry_backoff} ? ( retry_backoff => $ro->{retry_backoff} ) : () ),
            ( exists $ro->{timeout}       ? ( timeout       => $ro->{timeout} )       : () ),
        );
    }

    # Build the client. For a transport case, point it at a DEAD port so the
    # connection is refused; otherwise at the live mock.
    my $host = $MockTest::BASE_URL;
    if ( $case->{transport} ) {
        $host = 'http://127.0.0.1:' . dead_port();
    }
    my $client = SignalWire::REST::RestClient->new(
        project => $MockTest::PROJECT,
        token   => $MockTest::TOKEN,
        host    => $host,
    );
    my $http = $client->_http;

    eval {
        my $method = $call->{method};
        if ( $method eq 'GET' ) {
            $http->get( $path, request_options => $req_opts );
        } elsif ( $method eq 'POST' ) {

            # POST cases carry a body (relay-rest.create_address); drive a real
            # POST so the idempotency-asymmetry retry logic is exercised.
            $http->post( $path, body => $call->{body}, request_options => $req_opts );
        } else {
            $http->_request(
                $method, $path,
                body            => $call->{body},
                request_options => $req_opts
            );
        }
        1;
    } or do {
        my $err = $@;
        $artifact{raised} = JSON::true;
        if ( Scalar::Util::blessed($err) && $err->isa('SignalWireRestError') ) {
            $artifact{error_kind} = 'typed';

            # NUMIFY the status so JSON renders it as an integer (404), matching the
            # oracle — HTTP::Tiny's status is a string scalar, which JSON would emit
            # as "404". A transport error's status_code is undef and stays null.
            my $sc = $err->status_code;
            $artifact{status_code}     = defined $sc ? ( $sc + 0 ) : undef;
            $artifact{body_error_code} = decode_body_error_code( $err->body );
        } else {

            # A BARE error (string die or a non-family object) — the contract
            # violation the differ flags as bare:<Class>.
            my $cls = Scalar::Util::blessed($err) ? ref($err) : 'string';
            $artifact{error_kind} = "bare:$cls";
        }
    };

    # request_count: 0 for the transport case (nothing reached a server); else
    # the journal hits for this route.
    $artifact{request_count} = $case->{transport} ? 0 : request_count($path);

    return \%artifact;
}

# --------------------------------------------------------------------------- #
# Bring up the mock_signalwire server and point MockTest's journal/scope helpers
# at it. Three modes, in order:
#   1. MOCK_SIGNALWIRE_PORT set (the CI gate pre-spawned one) -> probe + reuse.
#   2. A server already answering on MockTest's chosen BASE_URL -> reuse.
#   3. Otherwise spawn `python -m mock_signalwire` OURSELVES, redirecting the
#      child's stdout/stderr to a log FILE (not closing them — closing the pipe
#      makes the mock take a SIGPIPE on its startup banner and die, which is the
#      failure MockTest's own open3 spawn hits when it has to spawn).
# We drive MockTest's journal/auth/scope helpers by setting its BASE_URL and
# marking it ensured, so its per-process auth scoping (request_count) still works.
# --------------------------------------------------------------------------- #
sub _probe_health ($base) {
    my $r = HTTP::Tiny->new( timeout => 3 )->get("$base/__mock__/health");
    return 0 unless $r->{success};
    my $p = eval { JSON::decode_json( $r->{content} || '{}' ) };
    return ( !$@ && ref $p eq 'HASH' && exists $p->{specs_loaded} ) ? 1 : 0;
}

sub ensure_mock {

    # Already answering (pre-spawned via MOCK_SIGNALWIRE_PORT, or a reused one)?
    return if _probe_health($MockTest::BASE_URL);

    # Spawn our own. Locate the mock package via the adjacency walk MockTest uses.
    my $pkg = MockTest::discover_porting_sdk_package('mock_signalwire');
    if ( defined $pkg ) {
        my $sep = ':';

        # Process-wide on purpose: PYTHONPATH must be inherited by the mock_signalwire
        # child this script exec's below, so the assignment has to outlive any local
        # scope.
        ## no critic (Variables::RequireLocalizedPunctuationVars)
        $ENV{PYTHONPATH} =
            ## use critic
            defined $ENV{PYTHONPATH} && length $ENV{PYTHONPATH}
            ? "$pkg$sep$ENV{PYTHONPATH}"
            : $pkg;
    }

    my $logdir = $ENV{TMPDIR} || File::Spec->catdir( $RealBin, File::Spec->updir, '.sw-tmp' );
    mkdir $logdir unless -d $logdir;
    my $log = File::Spec->catfile( $logdir, "emit-envelope-mock.$$.log" );

    my $pid = fork();
    die "emit-envelope: fork failed: $!\n" unless defined $pid;
    if ( $pid == 0 ) {

        # Child: redirect stdout+stderr to the log FILE (so the mock's startup
        # banner writes succeed — a closed pipe would SIGPIPE it dead), then exec.
        open( STDOUT, '>',  $log )     or POSIX::_exit(127);
        open( STDERR, '>&', \*STDOUT ) or POSIX::_exit(127);
        exec(
            'python', '-m',            'mock_signalwire', '--host', $MockTest::HOST,
            '--port', $MockTest::PORT, '--log-level',     'error'
        ) or POSIX::_exit(127);
    }
    $OUR_MOCK_PID = $pid;

    my $deadline = time + 30;
    while ( time < $deadline ) {
        return if _probe_health($MockTest::BASE_URL);

        # Fail loud if the child died (don't hang the full 30s on a dead mock).
        if ( waitpid( $pid, 1 ) == $pid ) {    # 1 == WNOHANG
            my $tail = -f $log ? do { local ( @ARGV, $/ ) = $log; <> } : '';
            die "emit-envelope: mock_signalwire died on startup (log $log):\n$tail\n";
        }
        Time::HiRes::sleep(0.2);
    }
    die "emit-envelope: mock_signalwire did not become ready on $MockTest::BASE_URL "
        . "within 30s (log $log)\n";
}

END {
    if ($OUR_MOCK_PID) {
        kill 'TERM', $OUR_MOCK_PID;
        waitpid( $OUR_MOCK_PID, 0 );
    }
}

# --------------------------------------------------------------------------- #
# main: emit one JSON object { id => artifact }.
# --------------------------------------------------------------------------- #
sub main {
    my $corpus = load_corpus();

    ensure_mock();

    my %out;
    my %seen;
    for my $case (@$corpus) {
        my $id = $case->{id};
        die "emit-envelope: duplicate corpus id '$id'\n" if $seen{$id}++;
        $out{$id} = run_case($case);
    }

    print JSON->new->canonical->encode( \%out ), "\n";
    return 0;
}

exit main();
