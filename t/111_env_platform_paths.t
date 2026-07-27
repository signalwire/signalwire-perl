#!/usr/bin/env perl
#
# t/111_env_platform_paths.t — regression guard for the Windows toolchain-
# resolution defect found in nightly Multi-OS run 30238072907.
#
# TWO defects, both invisible on POSIX, so this test SIMULATES the Windows shapes
# rather than relying on the platform:
#
#   1. scripts/_env.sh joined PERL5LIB with a hardcoded ':'. On Win32 PERL5LIB is
#      ';'-separated and entries carry drive letters, so ':' is a path CHARACTER,
#      not a separator. The corrupted value made perl split `D:\a\...` into `D`
#      + `\a\...`, and @INC came out with no usable directory:
#        @INC entries checked: D \a\signalwire-perl\...\local\lib\perl5;D \a\...
#      -> assert the join uses $Config{path_sep}, and that a Windows-shaped
#         incoming value round-trips through a Win32-style split intact.
#
#   2. scripts/run-tests.sh invoked a bare `prove` from PATH. On the Windows
#      runner that was Strawberry's prove, which then resolved App::Prove from an
#      MSYS core_perl lacking TAP::Harness::Env. The harness must instead be run
#      THROUGH the resolved interpreter ($SW_PERL) so interpreter and @INC are the
#      same install by construction.
#      -> assert no gate script calls a bare `prove`, and that the App::Prove
#         entry point we use is correct (process_args is void; run returns bool).

use strict;
use warnings;
use Test::More;
use Config;
use File::Basename qw(dirname);
use File::Spec;

my $repo = File::Spec->rel2abs( File::Spec->catdir( dirname(__FILE__), File::Spec->updir ) );

my $env_sh    = File::Spec->catfile( $repo, 'scripts', '_env.sh' );
my $run_tests = File::Spec->catfile( $repo, 'scripts', 'run-tests.sh' );

# ---------------------------------------------------------------------------
# Defect 1 — PERL5LIB must be joined with the PLATFORM separator.
# ---------------------------------------------------------------------------

sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "cannot read $path: $!";
    local $/;
    my $c = <$fh>;
    close $fh;
    return $c;
}

my $env_src = slurp($env_sh);

like(
    $env_src,
    qr/\$Config\{path_sep\}/,
    '_env.sh derives the path separator from $Config{path_sep}, not a literal',
);

# The specific regression: no PERL5LIB assignment may hardcode ':' as the join.
my @bad_joins = grep { /PERL5LIB=.*\$\{PERL5LIB:\+:/ } split /\n/, $env_src;
is_deeply( \@bad_joins, [],
    'no PERL5LIB assignment joins with a hardcoded ":" (Win32 uses ";")' );

# Every PERL5LIB prepend must interpolate the computed separator instead.
my @joins = grep { /export PERL5LIB=/ } split /\n/, $env_src;
ok( scalar(@joins) >= 2, 'found the PERL5LIB prepend sites' );
for my $line (@joins) {
    next unless $line =~ /\$\{PERL5LIB:\+/;
    like( $line, qr/\$\{PERL5LIB:\+\$SW_PATH_SEP\$PERL5LIB\}/,
        'PERL5LIB prepend uses $SW_PATH_SEP' );
}

# Behavioural check: a Windows-shaped value joined with ';' must split back into
# entries that are each a real drive-lettered path -- and joining with ':'
# (the old code) must NOT. This is what actually broke @INC.
{
    my $incoming = 'D:\\a\\p\\local\\lib\\perl5;D:\\a\\p\\local\\lib\\perl5\\MSWin32-x64-multi-thread';
    my $ll       = 'C:\\ll\\lib\\perl5';

    my $good = $ll . ';' . $incoming;
    my @got  = split /;/, $good;
    is( scalar(@got), 3, 'Win32 ";" join splits back into 3 entries' );
    ok( ( !grep { !/^[A-Za-z]:\\/ } @got ),
        'every entry keeps its drive letter when joined with ";"' );

    # The old ':' join produces an entry containing TWO paths welded together by
    # the stray colon -- `C:\ll\lib\perl5:D:\a\p\local\lib\perl5` -- so the
    # local::lib is silently lost. A valid Win32 entry has exactly ONE drive
    # colon; this one has two.
    my $bad = $ll . ':' . $incoming;
    my @bad = split /;/, $bad;
    my ($welded) = grep { ( () = /:/g ) > 1 } @bad;
    ok( defined $welded,
        'the old ":" join welds two paths into one entry (the original defect)' );
    like( ( $welded // '' ), qr/\Q$ll\E:D:/,
        'the welded entry is the local::lib fused to the next path, so both are lost' );
}

# ---------------------------------------------------------------------------
# Defect 2 — the harness runs through the resolved interpreter, not bare `prove`.
# ---------------------------------------------------------------------------

my $rt_src = slurp($run_tests);

unlike(
    $rt_src,
    qr/^\s*(?:exec\s+)?prove\b/m,
    'run-tests.sh never invokes a bare `prove` from PATH',
);

like( $rt_src, qr/_sw_perl_tool\s+App::Prove/,
    'run-tests.sh drives App::Prove through the resolved interpreter' );

like( $env_src, qr/SW_PERL=/, '_env.sh exports SW_PERL (the one chosen interpreter)' );

# SW_PERL must NOT be resolved by PATH position. Under `shell: bash` on Windows,
# Git-for-Windows injects the MSYS /usr/bin ahead of what actions-setup-perl
# prepended, so `command -v perl` returns MSYS's perl -- the very install whose
# @INC lacks TAP::Harness::Env (measured: run 30239532589 failed with
# "ERROR: /usr/bin/perl cannot load App::Prove"). Selection must be by EVIDENCE.
unlike(
    $env_src,
    qr/SW_PERL="\$\{SW_PERL:-\$\(command -v perl/,
    'SW_PERL is not resolved by naive PATH position (command -v perl)',
);
like( $env_src, qr/_pick_perl\.sh/,
    '_env.sh delegates interpreter choice to the evidence-based picker' );

# The picker itself: it must probe candidates for App::Prove rather than trusting
# order, and it must consider the hosted toolcache (where actions-setup-perl puts
# the interpreter the workflow provisioned and set PERL5LIB for).
{
    my $picker = File::Spec->catfile( $repo, 'scripts', '_pick_perl.sh' );
    ok( -e $picker, 'scripts/_pick_perl.sh exists' );

    my $psrc = slurp($picker);
    like( $psrc, qr/-MApp::Prove -e1/,
        'picker validates a candidate by loading App::Prove' );
    like( $psrc, qr/RUNNER_TOOL_CACHE/,
        'picker considers the actions-setup-perl toolcache install' );

    # Behavioural: a BROKEN candidate that sorts first must be SKIPPED, not
    # chosen. Fake a toolcache whose perl always fails, and assert the picker
    # falls through to a usable interpreter instead.
    require File::Path;
    my $fake = File::Spec->catdir( $repo, '.sw-tmp', "pickperl-$$", 'perl', '9.9.9', 'x64', 'bin' );
    File::Path::make_path($fake);
    my $fake_perl = File::Spec->catfile( $fake, 'perl' );
    open my $fh, '>', $fake_perl or die $!;
    print {$fh} "#!/bin/sh\nexit 1\n";
    close $fh;
    chmod 0755, $fake_perl;

    my $cache = File::Spec->catdir( $repo, '.sw-tmp', "pickperl-$$" );
    my $picked = `RUNNER_TOOL_CACHE='$cache' bash '$picker' 2>/dev/null`;
    chomp $picked;
    isnt( $picked, $fake_perl,
        'picker SKIPS a first-in-line candidate that cannot load App::Prove' );
    ok( length $picked, 'picker still returns an interpreter' );

    # ...and the POSITIVE case: a toolcache perl that DOES work must be PREFERRED
    # over PATH, since it is the install the workflow provisioned and set PERL5LIB
    # for. Without this assertion a wrong find(1) depth silently stops discovering
    # the toolcache entirely and every run quietly falls back to PATH perl.
    my $good_dir = File::Spec->catdir( $repo, '.sw-tmp', "pickgood-$$", 'perl', '9.9.9', 'x64', 'bin' );
    File::Path::make_path($good_dir);
    my $good_perl = File::Spec->catfile( $good_dir, 'perl' );
    open my $gfh, '>', $good_perl or die $!;
    print {$gfh} "#!/bin/sh\nexec '$^X' \"\$@\"\n";
    close $gfh;
    chmod 0755, $good_perl;

    my $good_cache = File::Spec->catdir( $repo, '.sw-tmp', "pickgood-$$" );
    my $picked_good = `RUNNER_TOOL_CACHE='$good_cache' bash '$picker' 2>/dev/null`;
    chomp $picked_good;
    is( $picked_good, $good_perl,
        'picker PREFERS a usable toolcache perl over whatever PATH offers' );

    File::Path::remove_tree( File::Spec->catdir( $repo, '.sw-tmp', "pickgood-$$" ) );

    File::Path::remove_tree( File::Spec->catdir( $repo, '.sw-tmp', "pickperl-$$" ) );
}

# The entry point must match the real prove script's contract: process_args in
# VOID context, run() mapped to an exit code. Chaining ->process_args(...)->run
# dies ("Can't call method run on an undefined value"), and ignoring run()'s
# boolean would exit 0 on a FAILING suite.
like( $rt_src, qr/\$a->process_args\(\@ARGV\);/,
    'process_args is called in void context (it is not chainable)' );
like( $rt_src, qr/exit\(\s*\$a->run\s*\?\s*0\s*:\s*1\s*\)/,
    'run() boolean is mapped to an exit code so a red suite fails the gate' );

# Prove the entry point really works with THIS perl, end to end, including that a
# failing test yields a non-zero exit (a gate must not pass on red).
SKIP: {
    eval { require App::Prove; 1 }
        or skip 'App::Prove not available', 2;

    my $tmp = File::Spec->catdir( $repo, '.sw-tmp', "envpaths-$$" );
    require File::Path;
    File::Path::make_path($tmp);

    my $entry = 'my $a = App::Prove->new; $a->process_args(@ARGV); exit($a->run ? 0 : 1);';

    my %case = ( pass => "ok 1\n", fail => "not ok 1\n" );
    my %exp  = ( pass => 0,        fail => 1 );

    for my $name ( sort keys %case ) {
        my $t = File::Spec->catfile( $tmp, "$name.t" );
        open my $fh, '>', $t or die $!;
        print {$fh} "print \"1..1\\n$case{$name}\";\n";
        close $fh;

        my @cmd = ( $^X, '-MApp::Prove', '-e', $entry, '--', $t );
        my $rc  = system("@{[ map { qq('$_') } @cmd ]} >/dev/null 2>&1");
        is( $rc >> 8, $exp{$name},
            "App::Prove entry point exits $exp{$name} for a $name-ing test" );
    }

    File::Path::remove_tree($tmp);
}

done_testing();
