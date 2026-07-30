#!/usr/bin/env perl
# Tests for `bin/swaig-test --file PATH --list-tools` against the
# non-AgentBase SWMLService examples. Proves the in-process file loader
# walks the runtime tool registry (NO HTTP) and surfaces the tools the
# example script registered.

use strict;
use warnings;
use Test::More;
use File::Spec;

my $perl       = $^X;
my $script     = File::Spec->catfile( 'bin',      'swaig-test' );
my $standalone = File::Spec->catfile( 'examples', 'swmlservice_swaig_standalone.pl' );
my $sidecar    = File::Spec->catfile( 'examples', 'swmlservice_ai_sidecar.pl' );

plan skip_all => "swaig-test not found at $script" unless -f $script;
plan skip_all => "$standalone not found"           unless -f $standalone;
plan skip_all => "$sidecar not found"              unless -f $sidecar;

sub run_cli {
    my (@args) = @_;
    my $cmd = qq{PERL5LIB="lib:\$PERL5LIB" $perl $script @args 2>&1};
    return scalar `$cmd`;
}

subtest '--help advertises --file' => sub {
    my $out = run_cli('--help');
    like( $out, qr/--file/, 'help mentions --file' );
};

subtest 'standalone example: --list-tools surfaces lookup_competitor' => sub {
    my $out = run_cli( '--file', $standalone, '--list-tools' );
    like( $out, qr/Found \d+ SWAIG function/, 'reports a tool count' );
    like( $out, qr/lookup_competitor/,        'lists lookup_competitor' );
    like( $out, qr/competitor/,               'lists the parameter' );
    unlike( $out, qr/No SWAIG functions found/, 'not the empty case' );
};

subtest 'sidecar example: --list-tools surfaces lookup_competitor' => sub {
    my $out = run_cli( '--file', $sidecar, '--list-tools' );
    like( $out, qr/Found \d+ SWAIG function/, 'reports a tool count' );
    like( $out, qr/lookup_competitor/,        'lists lookup_competitor' );
    unlike( $out, qr/No SWAIG functions found/, 'not the empty case' );
};

subtest 'standalone example: --exec runs the handler in-process' => sub {
    my $out = run_cli( '--file', $standalone, '--exec', 'lookup_competitor',
        '--param', 'competitor=ACME', );
    like( $out, qr/ACME/, 'response mentions ACME' );
    like( $out, qr/\$99/, 'response mentions $99' );
};

subtest '--file requires action and --url is mutually exclusive' => sub {
    my $out = run_cli( '--file', $standalone );
    like( $out, qr/--dump-swml|--list-tools|--exec/, 'errors when no action provided' );

    my $out2 = run_cli( '--file', $standalone, '--url', 'http://x/', '--list-tools' );
    like( $out2, qr/mutually exclusive/i, 'rejects --file + --url combo' );
};

subtest 'unknown --file path errors cleanly' => sub {
    my $out = run_cli( '--file', '/nonexistent/path.pl', '--list-tools' );
    like( $out, qr/does not exist|no such/i, 'errors on missing file' );
};

# --parse-only validates the invocation's arguments and exits WITHOUT loading
# the agent or hitting the network (prints exactly `parse OK`, exit 0). It is
# position-independent -- recognized whether it precedes or trails an --exec.
subtest '--parse-only validates without loading the agent' => sub {

    # Trailing --parse-only, real example file: parse OK / exit 0, no tool listing.
    my $out = run_cli( '--file', $standalone, '--list-tools', '--parse-only' );
    is( $? >> 8, 0, 'trailing --parse-only exits 0' );
    like( $out, qr/^parse OK\s*$/, 'prints exactly "parse OK"' );
    unlike(
        $out,
        qr/Found \d+ SWAIG function|lookup_competitor/,
        'did NOT load the agent (no tool listing)'
    );

    # Leading --parse-only, position-independent, trailing an --exec + --param.
    my $out2 = run_cli(
        '--parse-only',      '--file',  $standalone, '--exec',
        'lookup_competitor', '--param', 'competitor=ACME'
    );
    is( $? >> 8, 0, 'leading --parse-only trailing --exec exits 0' );
    like( $out2, qr/^parse OK\s*$/, 'position-independent: prints "parse OK"' );
    unlike( $out2, qr/ACME/, 'did NOT execute the handler' );

    # --dry-run alias, against an unreachable --url: instant, no network.
    my $out3 = run_cli( '--dry-run', '--url', 'http://user:pass@10.255.255.1:9/route',
        '--exec', 'foo', '--param', 'bar=1' );
    is( $? >> 8, 0, '--dry-run alias exits 0' );
    like( $out3, qr/^parse OK\s*$/, '--dry-run is an alias for --parse-only' );

    # Invalid invocation under --parse-only exits 2 and does NOT print parse OK.
    my $bad = run_cli( '--parse-only', '--url', 'http://user:pass@localhost:9999/' );
    is( $? >> 8, 2, 'invalid args under --parse-only exit 2' );
    unlike( $bad, qr/^parse OK\s*$/m, 'no "parse OK" success line on the error path' );
};

subtest 'README quickstart pattern ($agent->run) does NOT hang under --file' => sub {

    # r5 P#4: the README file-mode workflow hung because examples ending in
    # `$agent->run` (the quickstart) started a blocking HTTP server. The
    # SWAIG_TEST_INPROCESS guard now makes run()/serve() no-op + return the
    # agent under swaig-test --file. Prove an AgentBase example that ends in
    # `$agent->run` lists its tools within a hard deadline (a hang = the guard
    # regressed).
    my $quickstart = File::Spec->catfile( 'examples', 'quickstart_agent.pl' );
    plan skip_all => "$quickstart not found" unless -f $quickstart;

    # Confirm the fixture really ends in a bare $agent->run (the hang trigger).
    open my $fh, '<', $quickstart or die "open $quickstart: $!";
    my $src = do { local $/; <$fh> };
    close $fh;
    like( $src, qr/->run\s*;/, 'fixture ends in $agent->run (the P#4 hang pattern)' );

    my $cmd = qq{PERL5LIB="lib:\$PERL5LIB" $perl $script --file $quickstart --list-tools 2>&1};
    my $out = '';
    my $timed_out = 0;
    my $rc;
    eval {
        local $SIG{ALRM} = sub { die "TIMEOUT\n" };
        alarm 30;
        $out = scalar `$cmd`;
        $rc  = $? >> 8;
        alarm 0;
        1;
    } or do {
        $timed_out = 1 if ( $@ // '' ) eq "TIMEOUT\n";
    };

    ok( !$timed_out, 'swaig-test --file on the $agent->run quickstart did NOT hang' );
    is( $rc, 0, 'exited 0 (no server bound, no blocking serve)' ) unless $timed_out;
    like( $out, qr/Found \d+ SWAIG function/, 'listed the tool count in-process' )
        unless $timed_out;
};

done_testing;
