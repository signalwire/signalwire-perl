#!/usr/bin/env perl
# Skills-framework load-path validation + SKILL.md discovery (#75).
#
# SkillRegistry->add_skill_directory validates a load-path (dies loud on a
# missing / non-directory path), registers it (idempotent, surfaces in
# _external_paths), and returns the file-based skills (SKILL.md dirs)
# discovered under it via the SHARED SignalWire::Skills::SkillDiscovery
# walker — the same walker the claude_skills builtin uses.
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Spec ();

use SignalWire::Skills::SkillRegistry;

# --- Build a temp load-path with one valid and one invalid skill dir ---
my $root = tempdir( CLEANUP => 1 );

# Valid skill: has SKILL.md with frontmatter.
my $good = File::Spec->catdir( $root, 'greeter' );
make_path($good);
open my $gfh, '>', File::Spec->catfile( $good, 'SKILL.md' ) or die $!;
print {$gfh} <<'MD';
---
name: greeter
description: Greet the caller warmly
---

Say hello to $ARGUMENTS.
MD
close $gfh;

# A "skill" directory with NO SKILL.md must be skipped by discovery.
my $bare = File::Spec->catdir( $root, 'not-a-skill' );
make_path($bare);
open my $bfh, '>', File::Spec->catfile( $bare, 'README.md' ) or die $!;
print {$bfh} "just docs\n";
close $bfh;

# A skill dir with a SKILL.md that has no frontmatter (whole file = body).
my $nofm = File::Spec->catdir( $root, 'plain' );
make_path($nofm);
open my $nfh, '>', File::Spec->catfile( $nofm, 'SKILL.md' ) or die $!;
print {$nfh} "Just a plain body, no frontmatter.\n";
close $nfh;

subtest 'load-path validation: bad paths die loud' => sub {
    eval {
        SignalWire::Skills::SkillRegistry->add_skill_directory(
            File::Spec->catdir( $root, 'nope' ) );
        1;
    };
    like( $@, qr/does not exist/, 'non-existent load-path dies' );

    my $file = File::Spec->catfile( $root, 'afile' );
    open my $fh, '>', $file or die $!;
    print {$fh} "x";
    close $fh;
    eval { SignalWire::Skills::SkillRegistry->add_skill_directory($file); 1; };
    like( $@, qr/not a directory/, 'a plain file as load-path dies' );
};

subtest 'discovers SKILL.md skills under a valid load-path' => sub {
    my $skills = SignalWire::Skills::SkillRegistry->add_skill_directory($root);
    is( ref($skills), 'ARRAY', 'returns an arrayref' );

    my %by_name = map { ( $_->{name} // '' ) => $_ } @$skills;

    # 'greeter' (with frontmatter) and 'plain' (no frontmatter, dir-name
    # fallback) are discovered; 'not-a-skill' (no SKILL.md) is NOT.
    ok( $by_name{greeter}, 'greeter skill discovered' );
    is( $by_name{greeter}{description}, 'Greet the caller warmly', 'frontmatter description parsed' );
    like( $by_name{greeter}{body}, qr/Say hello to \$ARGUMENTS/, 'body parsed' );

    ok( $by_name{plain}, 'no-frontmatter skill discovered via dir-name fallback' );

    ok( !exists $by_name{'not-a-skill'}, 'a dir without SKILL.md is not discovered' );
    is( scalar @$skills, 2, 'exactly the two SKILL.md dirs discovered' );
};

subtest 'load-path is registered (idempotent) in _external_paths' => sub {
    SignalWire::Skills::SkillRegistry->add_skill_directory($root);
    SignalWire::Skills::SkillRegistry->add_skill_directory($root);    # again
    my $paths = SignalWire::Skills::SkillRegistry->_external_paths;
    my @hits  = grep { $_ eq $root } @$paths;
    is( scalar @hits, 1, 'load-path registered exactly once (deduped)' );
};

done_testing;
