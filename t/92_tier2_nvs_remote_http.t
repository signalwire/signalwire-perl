#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON ();
use IO::Socket::INET;
use POSIX ();
use Time::HiRes ();

# =============================================================================
# Behavioral contract #4 — native_vector_search REMOTE HTTP (real POST, not a
# stub string).
#
# Python: in network mode (remote_url set) the search tool POSTs {query,count}
# to <remote_url>/search and formats the returned [{content,score,metadata}].
#
# This test stands up a REAL HTTP server on a FREE port (a forked child that
# speaks minimal HTTP/1.1), configures the skill's remote_url at it, invokes the
# search tool, and asserts:
#   * a real POST reached the server at /search with the query in the JSON body,
#   * the mock's results were formatted into the FunctionResult.
# (A "[Would query…]" / "In production…" stub would never hit the socket.)
# =============================================================================

use SignalWire::Agent::AgentBase;
use SignalWire::Skills::SkillRegistry;

# WIN32: this test stands up its mock server in a BARE-FORK child and then signals
# it to shut down. On Win32 `fork` is emulated with interpreter threads, so the
# child is a PSEUDO-process in the SAME OS process and `kill 'TERM', $pid` lands on
# the PARENT — it kills the test instead of the server. (Measured in
# t/26_skill_spider.t on run 30266308509: SIGTERM 0.3ms after the reap, then a
# 24-minute hang.) The wire behaviour here is covered on POSIX, where fork and
# signals work; forcing it on Windows only produces a self-killed test.
plan skip_all => 'needs a real fork + signallable child; Win32 emulates fork with threads'
    if $^O =~ /^(MS)?Win32$/;

# Loopback URLs must pass the SSRF guard for this test.
local $ENV{SWML_ALLOW_PRIVATE_URLS} = '1';

# ---- Stand up a real HTTP server on a free ephemeral port -------------------
my $listener = IO::Socket::INET->new(
    LocalHost => '127.0.0.1',
    LocalPort => 0,             # OS-assigned free port
    Proto     => 'tcp',
    Listen    => 5,
    ReuseAddr => 1,
) or plan skip_all => "cannot bind loopback listener: $!";
my $port = $listener->sockport;

# A file the child writes the captured request to, so the parent can inspect
# what actually arrived over the wire. Kept in the repo-local scratch dir.
my $scratch = "$ENV{PWD}/.sw-tmp";
mkdir $scratch unless -d $scratch;
my $capture = "$scratch/nvs_capture_$$.json";
unlink $capture;

my $RESPONSE_BODY = JSON::encode_json(
    {
        results => [
            { content => 'The sky is blue.', score => 0.91, metadata => { filename => 'sky.md' } },
            { content => 'Grass is green.',  score => 0.72, metadata => { filename => 'grass.md' } },
        ],
    }
);

my $pid = fork();
defined $pid or plan skip_all => "cannot fork mock server: $!";

if ( $pid == 0 ) {
    # ---- child: accept ONE request, capture it, reply with the canned body ----
    my $client = $listener->accept;
    if ($client) {
        $client->autoflush(1);

        # Read the request incrementally until we have the full headers plus
        # the Content-Length worth of body (sysread, so we don't block on a
        # missing final newline the way <> would).
        my $data = '';
        my ( $headers_done, $need ) = ( 0, 0 );
        while (1) {
            my $chunk = '';
            my $n = sysread( $client, $chunk, 4096 );
            last unless $n;    # EOF or error
            $data .= $chunk;

            if ( !$headers_done && $data =~ /\r?\n\r?\n/ ) {
                $headers_done = 1;
                $need = ( $data =~ /^Content-Length:\s*(\d+)/mi ) ? $1 : 0;
            }
            if ($headers_done) {
                my ($hdr_len) = $data =~ /\A(.*?\r?\n\r?\n)/s;
                my $have = length($data) - length( $hdr_len // '' );
                last if $have >= $need;
            }
        }

        my ($request_line) = split /\r?\n/, $data;
        my $body = '';
        if ( $data =~ /\r?\n\r?\n(.*)\z/s ) {
            $body = $1;
        }

        open my $fh, '>', $capture or exit 1;
        print {$fh} JSON::encode_json( { request_line => $request_line, body => $body } );
        close $fh;

        my $resp =
              "HTTP/1.1 200 OK\r\n"
            . "Content-Type: application/json\r\n"
            . "Content-Length: " . length($RESPONSE_BODY) . "\r\n"
            . "Connection: close\r\n\r\n"
            . $RESPONSE_BODY;
        print {$client} $resp;
        close $client;
    }
    exit 0;
}

# ---- parent: drive the skill against the real server ------------------------
$listener->close;    # only the child accepts

my $result;
my $ok = eval {
    my $factory = SignalWire::Skills::SkillRegistry->get_factory('native_vector_search');
    my $agent   = SignalWire::Agent::AgentBase->new( name => 'nvs_wire' );
    my $skill   = $factory->new(
        agent  => $agent,
        params => {
            remote_url => "http://127.0.0.1:$port",
            index_name => 'docs',
        },
    );
    ok( $skill->setup, 'skill setup with a loopback remote_url' );

    $result = $skill->_handle_search( { query => 'colors', count => 2 }, {} );
    1;
};
my $err = $@;

# BOUNDED reap. This said "bounded" while using an UNBOUNDED waitpid($pid, 0):
# if the child is still blocked in accept() (the skill never connected, or it
# wedged mid-request), the parent sits in wait4 forever and takes the whole suite
# with it. On Win32 that is the normal case, since a bare-fork child is a
# pseudo-process that does not die on TERM. Same pattern as
# t/relay/outbound_call_mock.t: TERM, poll with WNOHANG to a hard deadline, then
# SIGKILL a stuck child and reap the corpse.
kill 'TERM', $pid;
my $nvs_deadline = time + 30;
my $nvs_reaped   = 0;
while ( time < $nvs_deadline ) {
    my $w = waitpid( $pid, POSIX::WNOHANG() );
    if ( $w == $pid || $w == -1 ) { $nvs_reaped = 1; last }
    Time::HiRes::sleep(0.05);
}
unless ($nvs_reaped) {
    kill 'KILL', $pid;
    waitpid( $pid, 0 );
    diag("92_tier2_nvs_remote_http: server child $pid exceeded 30s reap deadline — killed to avoid suite hang");
}

ok( $ok, 'search invocation completed against the real server' ) or diag($err);

# ---- assert a real POST hit /search with the query --------------------------
ok( -e $capture, 'the mock server captured a request (a real POST hit the socket)' );
my $captured = {};
if ( -e $capture ) {
    open my $fh, '<', $capture;
    local $/;
    $captured = JSON::decode_json(<$fh>);
    close $fh;
}

like( $captured->{request_line} // '', qr{^POST\s+/search\s}, 'POST to /search over the wire' );
my $sent = eval { JSON::decode_json( $captured->{body} // '{}' ) } // {};
is( $sent->{query},      'colors', 'query forwarded in the POST body' );
is( $sent->{count},      2,        'count forwarded in the POST body' );
is( $sent->{index_name}, 'docs',   'index_name forwarded in the POST body' );

# ---- assert the mock results were formatted into the FunctionResult ---------
my $text = $result ? $result->response : '';
like( $text, qr/Search results for 'colors'/, 'results header present' );
like( $text, qr/The sky is blue\./,           'first mock result formatted in' );
like( $text, qr/Grass is green\./,            'second mock result formatted in' );
like( $text, qr/relevance: 0\.91/,            'score from the mock rendered' );

unlink $capture;

done_testing;
