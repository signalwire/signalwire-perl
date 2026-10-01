#!/usr/bin/env perl
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# relay-liveness-dump.pl — the Perl port's RELAY-LIVENESS dump program for the
# cross-port behavioral differ (porting-sdk/scripts/diff_port_relay_liveness.py).
#
# The BROADER RELAY connection+error liveness suite (plan PSDK-2 / enterprise
# report F2/F3). The differ builds the golden by driving signalwire-python, then
# runs THIS program and structurally compares our per-fixture CLASSIFICATION.
# Every artifact is a deterministic boolean map (raised / bounded / detected /
# enforced / reconnected), never raw ms.
#
# Fixtures + classification (mirror relay_liveness_corpus.py):
#   cred_missing_project/token  {failed_preconnect_on_missing}
#   cred_auth_reject            {raised_after_bounded_retry, infinite_reconnect,
#                                server_message_surfaced}
#   relay_contract_500/404/410  {raised, swallowed}
#   dead_peer_half_open         {detected_bounded, hung}
#   black_hole_silent_peer      {bounded_error, unbounded_hang}
#   reconnect_after_drop        {reconnected, pending_faulted_not_hung, zombie}
#   max_active_calls_cap        {cap_enforced}
#
# The connect-level fault cases (auth-reject / dead-peer / black-hole /
# reconnect) are driven against a small embedded controllable WS server this
# program stands up (the Perl analog of the python differ's in-process _FakeWS):
# it speaks perl's signalwire.connect handshake and injects the specific fault.
# relay_contract is driven against the real mock_relay (rpc_code capability);
# cred_missing + max_active_calls need no socket.
#
# Protocol: stdout = ONE JSON object mapping fixture-id -> classification map.
# Only stdout carries JSON (setup noise is routed to stderr).
#
#   perl -Ilib bin/relay-liveness-dump.pl

use strict;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use FindBin qw($RealBin);
use File::Spec;
use IO::Socket::INET ();
use JSON             ();
use Time::HiRes      ();
use Test::More       ();    # RelayMockTest uses plan(skip_all) on a missing mock

use lib File::Spec->catdir( $RealBin, File::Spec->updir, 'lib' );
use lib File::Spec->catdir( $RealBin, File::Spec->updir, 't', 'lib' );

# Fast liveness timings so each fixture lands inside the gate's bounded window
# (diff_port_relay_liveness.BOUNDED_WINDOW_S = 5s, and the whole-dump budget is
# 5s * (fixtures + 2) + 20s). At the production 30s request timeout the
# dead-peer / black-hole fixtures alone consume ~60s and the dump blows that
# budget, which the gate correctly reports as an unbounded connection path.
# The client reads these lazily on first use, so setting them here (before any
# client is constructed) takes effect; production defaults apply when unset.
# Mirrors ts's scripts/relay-liveness-dump.ts preamble.
# Process-wide on purpose: this single-purpose dump program configures its own
# process before the client module loads (the client reads these lazily on first
# use). A `local` here would be restored before the client ever read them.
## no critic (Variables::RequireLocalizedPunctuationVars)
$ENV{SIGNALWIRE_RELAY_REQUEST_TIMEOUT_MS}    = '400';
$ENV{SIGNALWIRE_RELAY_RECONNECT_MIN_DELAY_S} = '0.02';
$ENV{SIGNALWIRE_RELAY_RECONNECT_MAX_DELAY_S} = '0.05';
## use critic

use Protocol::WebSocket::Handshake::Server ();
use Protocol::WebSocket::Frame             ();

use SignalWire::Relay::Client ();

# Keep stdout PURE JSON (the differ does json.loads(proc.stdout)); redirect the
# STDOUT filehandle to STDERR during setup, restore it only for the final JSON.
open( my $REAL_STDOUT, '>&', \*STDOUT ) or die "dup stdout: $!";
open( STDOUT,          '>&', \*STDERR ) or die "redirect stdout->stderr: $!";

# ======================================================================
# ControllableWsServer — a minimal single-thread WebSocket server that speaks
# perl's signalwire.connect handshake, then injects one fault. Built on a forked
# child holding a raw TCP accept loop + Protocol::WebSocket handshake/frames so it
# needs no async runtime. The parent talks to it only via the connection count
# file (a tiny shared side-channel) and the child's lifetime.
#
# fault: 'auth_reject' | 'dead_peer' | 'black_hole' | 'reconnect'
# ======================================================================
{

    package ControllableWsServer;
    use strict;
    use warnings;
    use feature 'signatures';
    no warnings 'experimental::signatures';
    use IO::Socket::INET                       ();
    use POSIX                                  ();
    use JSON                                   ();
    use Protocol::WebSocket::Handshake::Server ();
    use Protocol::WebSocket::Frame             ();

    my $AUTH_REQUIRED_CODE = -32002;

    sub new ( $class, %args ) {
        my $listen = IO::Socket::INET->new(
            LocalHost => '127.0.0.1',
            LocalPort => 0,
            Proto     => 'tcp',
            Listen    => 8,
            ReuseAddr => 1,
        ) or die "ControllableWsServer listen: $!";
        my $port = $listen->sockport;

        # A temp file the child bumps on each accepted+authed connection; the
        # parent polls it to observe reconnects. Repo-local scratch, never /tmp.
        my $countfile = File::Spec->catfile( File::Spec->tmpdir, "rl-conn-$$-$port" );

        # Prefer a worktree-local scratch dir over the system tmpdir.
        my $localtmp = File::Spec->catdir( $FindBin::RealBin, File::Spec->updir, '.sw-tmp' );
        if ( -d $localtmp || mkdir $localtmp ) {
            $countfile = File::Spec->catfile( $localtmp, "rl-conn-$$-$port" );
        }
        open( my $cf, '>', $countfile ) or die "countfile: $!";
        print {$cf} "0\n";
        close $cf;

        my $pid = fork();
        die "fork: $!" unless defined $pid;
        if ( $pid == 0 ) {

            # CHILD: serve until killed.
            _child_loop( $listen, $args{fault}, $args{auth_message}, $countfile );
            POSIX::_exit(0);
        }
        $listen->close;    # parent doesn't accept
        return bless {
            port       => $port,
            pid        => $pid,
            countfile  => $countfile,
            relay_host => "127.0.0.1:$port",
        }, $class;
    }

    sub port       ($self) { return $self->{port} }
    sub relay_host ($self) { return $self->{relay_host} }

    sub connect_count ($self) {
        open( my $fh, '<', $self->{countfile} ) or return 0;
        my $n = <$fh>;
        close $fh;
        chomp $n if defined $n;
        return ( defined $n && $n =~ /^\d+$/ ) ? 0 + $n : 0;
    }

    sub stop ($self) {
        if ( $self->{pid} ) {
            kill 'TERM', $self->{pid};

            # Reap NON-BLOCKINGLY, and tolerate the child already being gone.
            # A blocking waitpid() here HANGS FOREVER whenever anything earlier
            # in the process has set $SIG{CHLD} = 'IGNORE' — which RelayMockTest
            # does process-globally when it spawns the shared mock (t/lib/
            # RelayMockTest.pm), and the relay_contract_* fixtures run before
            # this one. Under CHLD=IGNORE the kernel auto-reaps the child the
            # instant it exits, so there is nothing left for waitpid to collect
            # and it blocks indefinitely instead of returning -1. That wedged the
            # whole dump past the gate's budget and surfaced as "relay-liveness
            # dump HUNG — an unbounded connection path", pointing at the SDK's
            # connection path when the real fault was this teardown.
            my $deadline = Time::HiRes::time() + 5;
            while ( Time::HiRes::time() < $deadline ) {
                my $reaped = waitpid( $self->{pid}, POSIX::WNOHANG() );
                last if $reaped != 0;                # reaped, or already auto-reaped (-1)
                last if !kill( 0, $self->{pid} );    # gone
                Time::HiRes::sleep(0.02);
            }
            kill 'KILL', $self->{pid};               # belt-and-braces; no-op if gone
            waitpid( $self->{pid}, POSIX::WNOHANG() );
            $self->{pid} = undef;
        }
        unlink $self->{countfile} if $self->{countfile};
        return;
    }

    # --- child side ---
    sub _bump_count ($countfile) {
        open( my $fh, '<', $countfile ) or return;
        my $n = <$fh>;
        close $fh;
        chomp $n if defined $n;
        $n = ( defined $n && $n =~ /^\d+$/ ) ? $n : 0;
        open( my $out, '>', $countfile ) or return;
        print {$out} ( $n + 1 ), "\n";
        close $out;
        return;
    }

    sub _child_loop ( $listen, $fault, $auth_message, $countfile ) {
        local $SIG{TERM} = sub { POSIX::_exit(0) };
        my $conn_seen = 0;
        while ( my $sock = $listen->accept ) {
            $conn_seen++;
            _serve( $sock, $fault, $auth_message, $countfile, $conn_seen );
            $sock->close;
        }
        return;
    }

    # Perform the WS upgrade, then inject the fault on the first signalwire.connect.
    sub _serve ( $sock, $fault, $auth_message, $countfile, $conn_seen ) {
        my $hs = Protocol::WebSocket::Handshake::Server->new;

        # Read handshake request bytes until parsed.
        while ( !$hs->is_done ) {
            my $buf;
            my $n = sysread( $sock, $buf, 4096 );
            return unless $n;
            $hs->parse($buf);
        }
        syswrite( $sock, $hs->to_string );

        my $frame = Protocol::WebSocket::Frame->new;

        # Read frames until a signalwire.connect arrives.
        while (1) {
            my $buf;
            my $n = sysread( $sock, $buf, 4096 );
            return unless $n;    # peer closed
            $frame->append($buf);
            while ( defined( my $msg = $frame->next ) ) {
                next unless length $msg;
                my $req = eval { JSON::decode_json($msg) };
                next unless $req && ( $req->{method} // '' ) eq 'signalwire.connect';
                _bump_count($countfile);
                my $id = $req->{id};
                if ( $fault eq 'auth_reject' ) {
                    _send(
                        $sock,
                        {
                            jsonrpc => '2.0',
                            id      => $id,
                            error   => { code => $AUTH_REQUIRED_CODE, message => $auth_message }
                        }
                    );
                    return;
                } elsif ( $fault eq 'black_hole' ) {

                    # Never answer the connect — the client's request must time out.
                    # Hold the socket open so the client blocks on recv.
                    Time::HiRes::sleep(30);
                    return;
                } elsif ( $fault eq 'dead_peer' ) {
                    _send_connect_ok( $sock, $id );

                    # After a successful connect, ignore everything forever.
                    Time::HiRes::sleep(30);
                    return;
                } elsif ( $fault eq 'reconnect' ) {
                    _send_connect_ok( $sock, $id );
                    if ( $conn_seen == 1 ) {

                        # First connection drops shortly after a SUCCESSFUL auth so
                        # the client must reconnect. Later connections stay up.
                        Time::HiRes::sleep(0.3);
                        _send_close($sock);
                        return;
                    }
                    Time::HiRes::sleep(30);
                    return;
                }
            }
        }
        return;
    }

    sub _send ( $sock, $obj ) {
        my $text = JSON::encode_json($obj);
        my $f    = Protocol::WebSocket::Frame->new( buffer => $text, type => 'text' );
        syswrite( $sock, $f->to_bytes );
        return;
    }

    sub _send_connect_ok ( $sock, $id ) {
        _send(
            $sock,
            {
                jsonrpc => '2.0',
                id      => $id,
                result  => {
                    protocol      => 'relay_proto_test',
                    sessionid     => 'sess-test',
                    nodeid        => 'n',
                    master_nodeid => 'n',
                    identity      => '',
                    protocols     => []
                }
            }
        );
        return;
    }

    sub _send_close ($sock) {
        my $f = Protocol::WebSocket::Frame->new( type => 'close' );
        syswrite( $sock, $f->to_bytes );
        return;
    }
}

# ======================================================================
# Helpers
# ======================================================================
sub clear_relay_env {
    delete @ENV{
        qw(SIGNALWIRE_PROJECT_ID SIGNALWIRE_API_TOKEN SIGNALWIRE_JWT_TOKEN SIGNALWIRE_SPACE)};
    return;
}

sub new_fault_client ($host) {
    return SignalWire::Relay::Client->new(
        project => 'p',
        token   => 't',
        host    => $host,
        scheme  => 'ws',
    );
}

# Run $code under a wall-clock alarm; returns (timed_out_bool).
sub with_deadline ( $seconds, $code ) {
    my $timed_out = 0;
    my $ok        = eval {
        local $SIG{ALRM} = sub { die "deadline\n" };
        alarm $seconds;
        $code->();
        alarm 0;
        1;
    };
    if ( !$ok ) {
        alarm 0;
        $timed_out = 1 if $@ =~ /deadline/;
        die $@ if $@ && $@ !~ /deadline/;    # re-raise a real error
    }
    return $timed_out;
}

# ======================================================================
# Fixture drivers — each returns its classification map.
# ======================================================================

# cred_missing: constructing+connecting a client with an empty credential must
# fail PRE-CONNECT (no socket) with a per-variable actionable message naming the
# env var. The perl A6 contract raises in connect() before any socket work.
sub drive_cred_missing ( $omit, @expect ) {
    clear_relay_env();
    my %kwargs = ( project => 'p', token => 't', host => 'relay.example.test' );
    $kwargs{$omit} = '';
    my $failed = 0;
    my $msg    = '';
    my $client = SignalWire::Relay::Client->new(%kwargs);
    my $ok     = eval { $client->connect; 1 };
    if ( !$ok ) {
        $failed = 1;
        $msg    = "$@";
    }
    my $actionable = 1;
    $actionable = 0 for grep { index( $msg, $_ ) < 0 } @expect;
    return {
        failed_preconnect_on_missing => ( $failed && $actionable ) ? JSON::true : JSON::false };
}

# cred_auth_reject: a 401-class connect rejection must RAISE the server message,
# never infinite-reconnect. connect() calls authenticate() -> execute(), which
# dies a RelayError carrying the server message.
sub drive_cred_auth_reject ($server_message) {
    my $srv = ControllableWsServer->new( fault => 'auth_reject', auth_message => $server_message );
    my $out = {
        raised_after_bounded_retry => JSON::false,
        infinite_reconnect         => JSON::false,
        server_message_surfaced    => JSON::false,
    };
    my $client    = new_fault_client( $srv->relay_host );
    my $raised    = 0;
    my $surfaced  = 0;
    my $timed_out = with_deadline(
        12,
        sub {
            my $ok = eval { $client->connect; 1 };
            if ( !$ok ) {
                $raised   = 1;
                $surfaced = 1 if index( "$@", $server_message ) >= 0;
            }
        }
    );
    if ($timed_out) {
        $out->{infinite_reconnect} = JSON::true;
    } else {
        $out->{raised_after_bounded_retry} = $raised   ? JSON::true : JSON::false;
        $out->{server_message_surfaced}    = $surfaced ? JSON::true : JSON::false;
    }
    $srv->stop;
    return $out;
}

# dead_peer: connect succeeds, then the peer ignores every request. A subsequent
# execute() must bounded-error (RelayError), never hang forever.
sub drive_dead_peer {
    my $srv      = ControllableWsServer->new( fault => 'dead_peer' );
    my $client   = new_fault_client( $srv->relay_host );
    my $detected = 0;

    # The client's request timeout is bounded (~30s); the outer deadline must be
    # LARGER so a genuine bounded-error at the request timeout counts as bounded,
    # and only a truly unbounded hang blows this deadline.
    my $timed_out = with_deadline(
        45,
        sub {
            eval { $client->connect };    # brings the socket up + authenticates
            my $ok = eval { $client->execute( 'calling.play', { control_id => 'x' } ); 1 };
            $detected = 1 if !$ok;        # bounded RelayError surfaced
        }
    );
    $detected = 0 if $timed_out;          # exceeded our generous outer bound => hung
    $srv->stop;
    return {
        detected_bounded => $detected ? JSON::true  : JSON::false,
        hung             => $detected ? JSON::false : JSON::true
    };
}

# black_hole: the connect frame is never answered. The client's connect must
# bounded-error within its request deadline, never hang forever.
sub drive_black_hole {
    my $srv     = ControllableWsServer->new( fault => 'black_hole' );
    my $client  = new_fault_client( $srv->relay_host );
    my $bounded = 0;

    # Outer deadline > the client's bounded request timeout (~30s) so a genuine
    # bounded connect-timeout counts as bounded, not a false hang.
    my $timed_out = with_deadline(
        45,
        sub {
            my $ok = eval { $client->connect; 1 };
            $bounded = 1 if !$ok;    # the connect request timed out (bounded) => error
        }
    );
    $bounded = 0 if $timed_out;      # never returned => unbounded hang
    $srv->stop;
    return {
        bounded_error  => $bounded ? JSON::true  : JSON::false,
        unbounded_hang => $bounded ? JSON::false : JSON::true
    };
}

# reconnect: the first socket drops right after auth. A REAL second connect+auth
# must happen; a pending caller across the drop is faulted (not hung); no zombie.
sub drive_reconnect {
    my $srv    = ControllableWsServer->new( fault => 'reconnect' );
    my $client = new_fault_client( $srv->relay_host );

    # connect once (first socket), then run() the auto-reconnect loop briefly so
    # the post-auth drop triggers a real second connect+auth.
    eval { $client->connect };
    my $reconnected = 0;
    my $timed_out   = with_deadline(
        20,
        sub {
            # Pump run() in a bounded window: run() reconnects on the drop.
            my $rpid = fork();
            if ( defined $rpid && $rpid == 0 ) {
                eval { $client->run };
                POSIX::_exit(0);
            }

            # Poll the server's connection count for a second connect.
            while ( $srv->connect_count < 2 ) {
                Time::HiRes::sleep(0.1);
            }
            $reconnected = 1;
            if ($rpid) {
                kill 'TERM', $rpid;

                # Non-blocking reap, for the same reason as
                # ControllableWsServer::stop: $SIG{CHLD} is 'IGNORE' by the time
                # this fixture runs (RelayMockTest sets it process-globally when
                # the earlier relay_contract_* fixtures spawn the shared mock),
                # so the kernel auto-reaps and a blocking waitpid() never
                # returns. It burned the outer 20s deadline, and the
                # `$reconnected = 0 if $timed_out` line below then THREW AWAY a
                # reconnect that had already succeeded — the fixture reported
                # reconnected=false while the SDK was working correctly.
                my $deadline_r = Time::HiRes::time() + 2;
                while ( Time::HiRes::time() < $deadline_r ) {
                    last if waitpid( $rpid, POSIX::WNOHANG() ) != 0;
                    last if !kill( 0, $rpid );
                    Time::HiRes::sleep(0.02);
                }
                kill 'KILL', $rpid;
                waitpid( $rpid, POSIX::WNOHANG() );
            }
        }
    );
    $reconnected = 0 if $timed_out;

    # A pending caller across a drop is faulted (RelayError), never hung: seed a
    # pending entry and reject all pending, then assert it flipped to an error.
    my $faulted = 0;
    my $err;
    $client->_pending->{'probe-id'} = { reject => sub { $err = $_[0] }, resolve => sub { } };
    $client->_reject_all_pending('probe drop');
    $faulted = 1 if defined $err;

    # No zombie: connected is false after the client is stopped.
    $client->disconnect_ws;
    my $zombie = $client->connected ? 1 : 0;

    $srv->stop;
    return {
        reconnected              => $reconnected ? JSON::true : JSON::false,
        pending_faulted_not_hung => $faulted     ? JSON::true : JSON::false,
        zombie                   => $zombie      ? JSON::true : JSON::false,
    };
}

# relay_contract: drive the REAL mock_relay (rpc_code capability) + Call._execute.
# 500 must RAISE; 404/410 swallowed. Mirrors the ruby driver + the perl
# actions_mock test harness (connect, pump _read_once, arm rpc_code, _execute).
sub drive_relay_contract ( $verb, $code ) {
    require RelayMockTest;
    my $out    = { raised => JSON::false, swallowed => JSON::false };
    my $client = RelayMockTest::client( contexts => ['default'] );
    $client->connect;
    my $call = _build_answered_call( $client, "call-relay-live-$code" );
    unless ($call) {
        $client->disconnect;
        return $out;    # could not stand up a call — leave both false (RED, loud)
    }
    RelayMockTest::arm_method( "calling.$verb", [ { rpc_code => $code } ] );

    # Call::_execute takes the FULL RELAY method name (the high-level verbs call
    # _start_action('calling.play', ...)); pass calling.<verb>, not the bare verb.
    my $ok = eval {
        $call->_execute(
            "calling.$verb",
            control_id => 'ctl-relay-live-1',
            play       => [ { type => 'tts', params => { text => 'hi' } } ],
        );
        1;
    };
    if   ($ok) { $out->{swallowed} = JSON::true }
    else       { $out->{raised}    = JSON::true if ref $@ }
    $client->disconnect;
    return $out;
}

# Pump the client's read loop until $cb is true or the deadline elapses.
sub _pump_until ( $client, $secs, $cb ) {
    my $deadline = Time::HiRes::time() + $secs;
    while ( Time::HiRes::time() < $deadline ) {
        return 1 if $cb->();
        eval { $client->_read_once };
    }
    return $cb->() ? 1 : 0;
}

# Establish an answered inbound call against the real mock (for relay_contract).
# Mirrors the actions_mock harness: register on_call, push an inbound_call, pump
# the read loop until the call is captured + answered.
sub _build_answered_call ( $client, $call_id ) {
    my $captured;
    $client->on_call(
        sub ($call) {
            $captured = $call;
            $call->answer;
        }
    );
    RelayMockTest::inbound_call( call_id => $call_id, auto_states => ['created'] );
    _pump_until( $client, 10, sub { defined $captured } );
    _pump_until( $client, 1,  sub { 0 } );                   # let the answer round-trip
    $captured->state('answered') if $captured;
    return $captured;
}

# max_active_calls: with cap=N, the N+1th inbound call is dropped (not accepted).
sub drive_max_active_calls ($cap) {
    clear_relay_env();
    my $client = SignalWire::Relay::Client->new(
        project          => 'p',
        token            => 't',
        host             => 'x',
        max_active_calls => $cap
    );
    $client->on_call( sub { } );    # accept each call (keeps it "active" in _calls)
    for my $i ( 0 .. $cap ) {
        $client->_handle_inbound_call( {},
            { call_id => "c$i", node_id => 'node-relay-live', call_state => 'created' },
        );
    }
    my $active = keys %{ $client->_calls };
    return { cap_enforced => ( $active == $cap ) ? JSON::true : JSON::false };
}

# ======================================================================
# main
# ======================================================================
my %out;
$out{cred_missing_project}   = drive_cred_missing( 'project', 'project', 'SIGNALWIRE_PROJECT_ID' );
$out{cred_missing_token}     = drive_cred_missing( 'token',   'token',   'SIGNALWIRE_API_TOKEN' );
$out{cred_auth_reject}       = drive_cred_auth_reject('auth rejected: bad token');
$out{relay_contract_500}     = drive_relay_contract( 'play', '500' );
$out{relay_contract_404}     = drive_relay_contract( 'play', '404' );
$out{relay_contract_410}     = drive_relay_contract( 'play', '410' );
$out{dead_peer_half_open}    = drive_dead_peer();
$out{black_hole_silent_peer} = drive_black_hole();
$out{reconnect_after_drop}   = drive_reconnect();
$out{max_active_calls_cap}   = drive_max_active_calls(2);

print {$REAL_STDOUT} JSON->new->canonical->encode( \%out ), "\n";
