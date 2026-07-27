#!/usr/bin/env perl
# scripts/lint_bounded_reap.pl — fail if any test reaps a child with an UNBOUNDED
# waitpid($pid, 0).
#
# WHY THIS GATE EXISTS
# --------------------
# An unbounded waitpid($pid, 0) hangs the ENTIRE suite forever whenever the child
# does not die. That is not hypothetical:
#   * t/relay/outbound_call_mock.t documents it as "root cause of the historic
#     outbound_call_mock hang — the parent sat in wait4 on a stuck watcher";
#   * t/26_skill_spider.t wedged the Windows nightly for 44 MINUTES (run
#     30261956136) — a bare-fork PSEUDO-process on Win32 sat in a blocking
#     accept() and ignored SIGTERM, so the parent waited forever.
# On Win32 this is the NORMAL case, not the edge case: `fork` is emulated with
# interpreter threads and a pseudo-process may ignore even SIGKILL.
#
# A hang is strictly worse than a failure: no assertion output, no log (GitHub's
# API 404s BlobNotFound while a job is in_progress), and it burns runner hours
# until someone cancels it by hand. So the rule is: ALWAYS bound the wait.
#
# THE APPROVED PATTERN (see t/relay/outbound_call_mock.t):
#     kill 'TERM', $pid;
#     my $deadline = time + 30;
#     my $reaped = 0;
#     while (time < $deadline) {
#         my $w = waitpid($pid, POSIX::WNOHANG());
#         if ($w == $pid || $w == -1) { $reaped = 1; last }
#         Time::HiRes::sleep(0.05);
#     }
#     unless ($reaped) { kill 'KILL', $pid; waitpid($pid, 0); diag(...) }
#
# WHAT IS ALLOWED: a `waitpid($pid, 0)` that reaps the CORPSE right after a
# SIGKILL is fine — the process is already dead, so the wait cannot block. This
# linter therefore only flags a blocking waitpid that is NOT preceded by a nearby
# `kill 'KILL'`. Comments and POD are ignored, so prose *about* the hazard is fine.

use strict;
use warnings;
use File::Find ();
use File::Spec;
use File::Basename qw(dirname);

my $repo = File::Spec->rel2abs( File::Spec->catdir( dirname(__FILE__), File::Spec->updir ) );
my $tdir = File::Spec->catdir( $repo, 't' );

# How far back to look for the SIGKILL that makes a blocking reap safe.
my $KILL_WINDOW = 6;

my @offenders;

my @files;
File::Find::find(
    {   no_chdir => 1,
        wanted   => sub { push @files, $File::Find::name if /\.(?:t|pm)\z/ },
    },
    $tdir,
);

for my $file ( sort @files ) {
    open my $fh, '<', $file or die "open $file: $!";
    my @lines = <$fh>;
    close $fh;

    my $in_pod = 0;
    for my $i ( 0 .. $#lines ) {
        my $line = $lines[$i];

        # Skip POD blocks entirely.
        if ( $line =~ /^=cut\b/ )      { $in_pod = 0; next }
        if ( $line =~ /^=[a-zA-Z]\w*/ ) { $in_pod = 1; next }
        next if $in_pod;

        # Strip a trailing comment, then skip whole-line comments. This is what
        # lets the explanatory prose above (and in the tests) mention the bad
        # pattern without tripping the gate.
        my $code = $line;
        $code =~ s/#.*\z//s;
        next unless $code =~ /\S/;

        # An unbounded blocking reap: waitpid($x, 0)
        next unless $code =~ /waitpid \s* \( \s* \$\w+ \s* , \s* 0 \s* \)/x;

        # Allowed if a SIGKILL was sent just above (reaping a known-dead corpse).
        my $lo = $i - $KILL_WINDOW;
        $lo = 0 if $lo < 0;
        my $preceded_by_kill = 0;
        for my $j ( $lo .. $i - 1 ) {
            my $prev = $lines[$j];
            $prev =~ s/#.*\z//s;
            if ( $prev =~ /kill \s* \(? \s* ['"]KILL['"]/x ) { $preceded_by_kill = 1; last }
        }
        next if $preceded_by_kill;

        ( my $shown = $line ) =~ s/^\s+|\s+\z//g;
        my $rel = File::Spec->abs2rel( $file, $repo );
        push @offenders, "$rel:" . ( $i + 1 ) . ": $shown";
    }
}

if (@offenders) {
    print STDERR "BOUNDED-REAP: unbounded waitpid(\$pid, 0) found — a stuck child hangs the WHOLE suite.\n\n";
    print STDERR "  $_\n" for @offenders;
    print STDERR <<'HINT';

Bound the wait instead (pattern: t/relay/outbound_call_mock.t):
    kill 'TERM', $pid;
    my $deadline = time + 30;
    my $reaped = 0;
    while (time < $deadline) {
        my $w = waitpid($pid, POSIX::WNOHANG());
        if ($w == $pid || $w == -1) { $reaped = 1; last }
        Time::HiRes::sleep(0.05);
    }
    unless ($reaped) { kill 'KILL', $pid; waitpid($pid, 0); diag(...) }

A waitpid($pid, 0) immediately after `kill 'KILL', $pid` is allowed (the child is
already dead, so it cannot block).
HINT
    exit 1;
}

print "BOUNDED-REAP: no unbounded waitpid(\$pid, 0) in t/ (" . scalar(@files) . " files scanned)\n";
exit 0;
