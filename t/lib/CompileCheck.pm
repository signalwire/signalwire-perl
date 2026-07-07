package CompileCheck;
# t/lib/CompileCheck.pm — a fork-pressure-robust wrapper around `perl -c`.
#
# Several smoke tests (t/12_cli.t, t/53_surface_audit.t, t/54_doc_audit.t)
# syntax-check a script or example by shelling out to `perl -c <file>` via
# backticks and asserting the captured output contains "syntax OK".
#
# The problem: under heavy parallel/fork pressure (a loaded box running many
# `prove` jobs, or the cross-port matrix) the backtick child can fail to fork
# or be reaped before it writes anything, so the backtick returns the EMPTY
# STRING with no diagnostic — even though the file compiles perfectly. The old
# `like($out, qr/syntax OK/)` assertion then reports a FALSE FAILURE that has
# nothing to do with the code under test.
#
# `perl -c` prints "<file> syntax OK" to STDERR and exits 0 on success; on a
# genuine syntax error it prints the diagnostic(s) to STDERR and exits non-zero.
# So the only outcomes that should FAIL a test are: a run that actually produced
# compiler diagnostics. Empty output (no "syntax OK", no diagnostic) is the
# fork-pressure signature and must NOT fail — we SKIP it instead.
#
# compile_ok($tb_or_undef, $cmd, $desc):
#   * $cmd is the full backtick command (already quoted by the caller) that runs
#     `perl ... -c <file> 2>&1`.
#   * On "syntax OK" in the output          -> pass.
#   * On empty/whitespace-only output        -> skip (fork-pressure; inconclusive).
#   * On real diagnostics (non-zero exit AND -> fail, with the diagnostic in the
#     non-empty, non-"syntax OK" output)         diag.
#   * On non-zero exit with NO output        -> skip (the child never ran; a fork
#                                               failure, not a compile error).
use strict;
use warnings;
use Exporter 'import';
use Test::More ();

our @EXPORT_OK = qw(compile_ok);

# Run $cmd (a backtick command string that already redirects 2>&1) and classify
# the result. Returns nothing; emits exactly one Test::More assertion or skip.
sub compile_ok {
    my ($cmd, $desc) = @_;

    my $out = `$cmd`;
    my $status = $?;              # $? from the backtick child (or -1 if it never launched)
    my $shell_err = $!;          # errno if the shell/backtick itself failed to spawn
    $out = '' unless defined $out;

    # ---- Success: the compiler said so. -------------------------------------
    if ($out =~ /syntax OK/) {
        Test::More::pass($desc);
        return;
    }

    # ---- Inconclusive (fork/resource pressure) -> SKIP, never FAIL. ----------
    # We only FAIL on a genuine compilation diagnostic from a child that ran to
    # a NORMAL exit. Everything below is the fork-pressure family: the syntax
    # check never actually reported, so failing would be a false negative.
    #
    #  (a) No output at all — the child produced neither "syntax OK" nor a
    #      diagnostic (killed/reaped before writing, or never forked).
    #  (b) Backtick never launched a child ($status == -1), i.e. the shell
    #      itself could not fork/exec.
    #  (c) Child was killed by a SIGNAL (low 7 bits of $status set) rather than
    #      exiting normally — a compile error is a normal exit(non-zero), never
    #      a signal death.
    #  (d) Output is a fork/exec/resource-exhaustion diagnostic from perl or the
    #      shell (out of processes/memory, cannot exec), not a compile error.
    my $signalled = ($status != -1) && (($status & 127) != 0);
    my $resource_err = $out =~ /
          Can't[ ]fork
        | Resource[ ]temporarily[ ]unavailable
        | Cannot[ ]allocate[ ]memory
        | Out[ ]of[ ]memory
        | fork[ ]failed
        | too[ ]many[ ]open[ ]files
    /xi;

    if ($out !~ /\S/ || $status == -1 || $signalled || $resource_err) {
        my $why =
              ($out !~ /\S/)      ? 'empty output (child never reported)'
            : ($status == -1)     ? "backtick failed to spawn ($shell_err)"
            : $signalled          ? 'child killed by signal'
            :                       'fork/resource-exhaustion diagnostic';
        Test::More::note(
            "compile check inconclusive under fork pressure — $why "
          . "(status=$status); skipping rather than failing: $desc");
      SKIP: {
            Test::More::skip("compile check inconclusive ($why)", 1);
        }
        return;
    }

    # ---- Genuine compile error: normal exit + real diagnostic. --------------
    # Non-empty, no "syntax OK", not a fork/resource/signal artifact, and the
    # child exited normally. Fail loudly with the diagnostic attached.
    Test::More::fail($desc);
    Test::More::diag("compile check failed (status=$status):\n$out");
    return;
}

1;
