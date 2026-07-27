#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use POSIX ();
use Time::HiRes ();
use File::Basename qw(dirname);
use File::Path ();
use File::Spec;

use SignalWire::Agent::AgentBase;
use SignalWire::Skills::SkillRegistry;

# Repo root, for the .sw-tmp fallback scratch dir (never /tmp).
my $repo_root = File::Spec->rel2abs(
    File::Spec->catdir( dirname(__FILE__), File::Spec->updir ) );

my $factory = SignalWire::Skills::SkillRegistry->get_factory('spider');
ok(defined $factory, 'factory found');

subtest 'construction' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'sp');
    my $skill = $factory->new(agent => $agent, params => {});
    is($skill->skill_name, 'spider', 'skill_name');
    ok($skill->supports_multiple_instances, 'multi-instance');
};

subtest 'registers 3 tools' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'sp_reg');
    my $skill = $factory->new(agent => $agent, params => {});
    $skill->setup;
    $skill->register_tools;
    ok(exists $agent->tools->{scrape_url}, 'scrape_url');
    ok(exists $agent->tools->{crawl_site}, 'crawl_site');
    ok(exists $agent->tools->{extract_structured_data}, 'extract_structured_data');
};

subtest 'hints' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'sp_hints');
    my $skill = $factory->new(agent => $agent, params => {});
    my $hints = $skill->get_hints;
    ok(scalar @$hints > 0, 'has hints');
    ok(grep({ $_ eq 'spider' } @$hints), 'includes spider');
    ok(grep({ $_ eq 'scrape' } @$hints), 'includes scrape');
};

subtest 'tool execution against fixture' => sub {
    # Spider issues real outbound HTTP. To verify the dispatch path
    # deterministically — without depending on example.com being up
    # and serving stable text — point the skill at a local HTTP::Tiny
    # fixture by setting SPIDER_BASE_URL.
    # The PSGI app itself now lives in the exec'd child script below, so nothing
    # here needs Plack loaded in the parent.
    require IO::Socket::INET;
    my $listen = IO::Socket::INET->new(
        Listen    => 5,
        LocalAddr => '127.0.0.1',
        LocalPort => 0,
        Proto     => 'tcp',
        ReuseAddr => 1,
    );
    my $port = $listen->sockport;
    close $listen;

    # Spawn the fixture server via fork+EXEC, not a bare fork. On Win32 `fork` is
    # emulated with interpreter threads, so a bare-fork child that sits in
    # HTTP::Server::PSGI->run's blocking accept() is a PSEUDO-process: `kill 'TERM'`
    # does not reliably terminate it (the accept loop never checks for a signal),
    # and the parent's reap below then blocks forever. exec() makes the child a
    # REAL OS process on every platform, so signals and waitpid behave.
    # (This wedged the Windows nightly for 44 min — run 30261956136.)
    my $server_script = <<"PSGI_SERVER";
use strict;
use warnings;
use HTTP::Server::PSGI;
my \$app = sub {
    return [
        200,
        ['Content-Type', 'text/html'],
        ["<html><body>Test page sentinel zazzle</body></html>"],
    ];
};
HTTP::Server::PSGI->new(host => '127.0.0.1', port => $port)->run(\$app);
PSGI_SERVER

    my $tmpdir = $ENV{TMPDIR} || File::Spec->catdir( $repo_root, '.sw-tmp' );
    File::Path::make_path($tmpdir) unless -d $tmpdir;
    my $server_pl = File::Spec->catfile( $tmpdir, "spider_fixture_$$.pl" );
    open my $sfh, '>', $server_pl or die "open $server_pl: $!";
    print {$sfh} $server_script;
    close $sfh;

    my $pid = fork;
    die "fork: $!" unless defined $pid;
    if ($pid == 0) {
        # Fully detached real process — no shared sockets / interpreter state.
        exec( $^X, $server_pl ) or POSIX::_exit(127);
    }

    # Wait for the server to come up.
    my $up = 0;
    for (1..30) {
        my $sock = IO::Socket::INET->new(
            PeerAddr => '127.0.0.1',
            PeerPort => $port,
            Timeout  => 1,
        );
        if ($sock) { $up = 1; close $sock; last }
        Time::HiRes::sleep(0.1);
    }

    # $up was computed and never checked: if the fixture never came up, the test
    # went on to fail on a confusing HTTP error instead of saying so. Assert it, so
    # a fixture-startup problem is reported as a fixture-startup problem.
    ok($up, 'fixture HTTP server came up') or diag("fixture server on port $port never accepted a connection");

    eval {
        local $ENV{SPIDER_BASE_URL} = "http://127.0.0.1:$port";
        my $agent = SignalWire::Agent::AgentBase->new(name => 'sp_exec');
        my $skill = $factory->new(agent => $agent, params => {});
        $skill->setup;
        $skill->register_tools;
        my $result = $agent->on_function_call(
            'scrape_url',
            { url => 'https://upstream.invalid/somepage' },
            {},
        );
        ok(defined $result, 'scrape returns result');
        like($result->response, qr/zazzle/, 'mentions fixture sentinel from real HTTP');
    };
    my $err = $@;

    # BOUNDED reap. An unbounded waitpid($pid, 0) hangs the whole suite forever if
    # the child does not die on SIGTERM — exactly what happened on Windows, where a
    # bare-fork pseudo-process in a blocking accept() ignored the TERM (run
    # 30261956136: this file wedged for 44 min and the job had to be cancelled).
    # Same pattern as t/relay/outbound_call_mock.t: TERM, poll with WNOHANG to a
    # hard deadline, then SIGKILL a stuck child and reap the corpse.
    kill 'TERM', $pid;
    my $deadline = time + 30;
    my $reaped   = 0;
    while ( time < $deadline ) {
        my $w = waitpid( $pid, POSIX::WNOHANG() );
        if ( $w == $pid || $w == -1 ) { $reaped = 1; last }
        Time::HiRes::sleep(0.05);
    }
    unless ($reaped) {
        kill 'KILL', $pid;
        waitpid( $pid, 0 );
        diag("26_skill_spider: fixture server $pid exceeded 30s reap deadline — killed to avoid suite hang");
    }
    unlink $server_pl;
    die $err if $err;
};

subtest 'parameter schema' => sub {
    my $schema = $factory->get_parameter_schema;
    ok(exists $schema->{max_pages}, 'has max_pages');
    ok(exists $schema->{timeout}, 'has timeout');
};

done_testing;
