#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# PERL-8 / PSDK-6 TLS-VERIFY: every builtin skill that makes outbound HTTPS
# calls must build its HTTP::Tiny client with TLS verification EXPLICITLY
# enabled (verify_SSL => 1).
#
# Why source-level, not just $http->{verify_SSL}: HTTP::Tiny's *default* for
# verify_SSL is version-dependent (older releases default it OFF -- the
# footgun -- and newer ones ON). Relying on the runtime default is exactly the
# bug. The contract is that each skill PASSES verify_SSL => 1 explicitly so
# outbound calls verify certs on every HTTP::Tiny version. This guards the
# source construction against regressing to the implicit (unsafe-on-old-Perl)
# form. The PSDK-6 TLS-VERIFY static gate enforces the same invariant fleet-wide.

use File::Spec ();

# skill file (relative to lib/) => the agent string that anchors its
# HTTP::Tiny->new(...) constructor block.
my @skills = (
    [ 'SignalWire/Skills/Builtin/WebSearch.pm',          'SignalWire-Perl-WebSearch' ],
    [ 'SignalWire/Skills/Builtin/WikipediaSearch.pm',    'SignalWire-Perl-WikipediaSearch' ],
    [ 'SignalWire/Skills/Builtin/Datasphere.pm',         'SignalWire-Perl-DataSphere' ],
    [ 'SignalWire/Skills/Builtin/NativeVectorSearch.pm', 'SignalWire-Perl-NativeVectorSearch' ],
    [ 'SignalWire/Skills/Builtin/Spider.pm',             'SignalWire-Perl-Spider' ],
);

# Locate lib/ relative to this test file (t/59_...t -> ../lib).
my ( $vol, $dir ) = File::Spec->splitpath(__FILE__);
my $lib = File::Spec->catdir( $dir, File::Spec->updir, 'lib' );

for my $entry (@skills) {
    my ( $rel, $agent ) = @$entry;
    my $path = File::Spec->catfile( $lib, split m{/}, $rel );
    ok( -f $path, "$rel: source present" ) or next;

    open my $fh, '<', $path or die "open $path: $!";
    my $src = do { local $/; <$fh> };
    close $fh;

    # Isolate the HTTP::Tiny->new( ... ) block for this skill.
    my ($block) = $src =~ /HTTP::Tiny->new\(\s*(.*?)\)\s*;/s;
    ok( defined $block, "$rel: found an HTTP::Tiny->new block" ) or next;
    like( $block, qr/\Q$agent\E/, "$rel: it is this skill's client block" );
    like( $block, qr/verify_SSL\s*=>\s*1\b/,
        "$rel: HTTP::Tiny built with explicit verify_SSL => 1 (TLS verify ON)" );
}

done_testing;
