package SignalWire::Skills::SkillDiscovery;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.

# Shared SKILL.md discovery walker. ONE implementation serves both the
# claude_skills builtin (SignalWire::Skills::Builtin::ClaudeSkills, #72)
# and the framework-level load-path discovery on the SkillRegistry (#75).
#
# Parity target: Python's claude_skills skill (_discover_skills /
# _parse_skill_md / _discover_sections). Perl is interpreted so it does the
# full file-discovery + YAML-frontmatter parse the AOT ports can't.

use strict;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use File::Spec ();
use Exporter 'import';

our @EXPORT_OK = qw(discover_skills parse_skill_md discover_sections);

# Walk $skills_path; for every immediate SUBDIRECTORY that contains a
# SKILL.md, parse it (YAML frontmatter + markdown body) and its supporting
# .md section files. Returns an arrayref of parsed skill hashrefs (sorted by
# directory name for deterministic output). A non-existent / non-directory
# path yields an empty list. Optional %opts: include => [globs] (default
# ['*']), exclude => [globs] (default []).
sub discover_skills ( $skills_path, %opts ) {
    my @skills;
    return \@skills unless defined $skills_path && -d $skills_path;

    my $include = $opts{include} || ['*'];
    my $exclude = $opts{exclude} || [];

    opendir( my $dh, $skills_path ) or return \@skills;
    my @entries = sort grep { $_ ne '.' && $_ ne '..' } readdir($dh);
    closedir $dh;

    for my $name (@entries) {
        my $dir = File::Spec->catdir( $skills_path, $name );
        next unless -d $dir;

        my $skill_file = File::Spec->catfile( $dir, 'SKILL.md' );
        next unless -f $skill_file;

        next unless _matches_patterns( $name, $include, $exclude );

        my $parsed = parse_skill_md($skill_file);
        next unless $parsed;

        # Directory name is the fallback skill name.
        $parsed->{name}      = $name unless defined $parsed->{name} && length $parsed->{name};
        $parsed->{path}      = $skill_file;
        $parsed->{skill_dir} = $dir;
        $parsed->{sections}  = discover_sections($dir);

        push @skills, $parsed;
    }

    return \@skills;
}

# glob include/exclude filter (excludes win). Mirrors Python fnmatch use.
sub _matches_patterns ( $name, $include, $exclude ) {
    for my $pat (@$exclude) {
        return 0 if _fnmatch( $name, $pat );
    }
    for my $pat (@$include) {
        return 1 if _fnmatch( $name, $pat );
    }
    return 0;
}

# Minimal shell-glob match ('*' and '?'), anchored. No dependency on
# File::Glob's fnmatch (not universally available).
sub _fnmatch ( $name, $pattern ) {
    my $re = quotemeta($pattern);
    $re          =~ s/\\\*/.*/g;
    $re          =~ s/\\\?/./g;
    return $name =~ /\A$re\z/ ? 1 : 0;
}

# Parse a SKILL.md file: YAML frontmatter (delimited by leading/trailing
# '---') + markdown body. Returns a hashref
#   { name, description, argument_hint, body, _frontmatter }
# or undef when the file can't be read. A file with no frontmatter treats
# the whole content as body (name/description undef).
sub parse_skill_md ($path) {
    my $content = _slurp($path);
    return unless defined $content;

    # No frontmatter: whole content is the body.
    if ( $content !~ /\A---\s*\n/ ) {
        return {
            name          => undef,
            description   => undef,
            argument_hint => undef,
            body          => _trim($content),
            _frontmatter  => {},
        };
    }

    # Split: everything between the first '---' line and the next '---' line
    # is frontmatter; the remainder is the body.
    my @parts = split /^---\s*$/m, $content, 3;

    # parts[0] is empty (before first ---), parts[1] = frontmatter,
    # parts[2] = body.
    if ( @parts < 3 ) {
        return {
            name          => undef,
            description   => undef,
            argument_hint => undef,
            body          => _trim($content),
            _frontmatter  => {},
        };
    }

    my $frontmatter_str = $parts[1];
    my $body            = _trim( $parts[2] );

    my $fm = _parse_frontmatter($frontmatter_str);

    return {
        name          => $fm->{name},
        description   => $fm->{description},
        argument_hint => $fm->{'argument-hint'} // $fm->{argument_hint},
        body          => $body,
        _frontmatter  => $fm,
    };
}

# Parse YAML frontmatter. Prefer YAML::PP (a declared dependency) when
# loadable; otherwise fall back to a minimal ``key: value`` parser so
# discovery still works on minimal installs (matches the brief). The
# minimal parser handles the flat scalar frontmatter SKILL.md files use
# (name / description / argument-hint), strips optional surrounding
# quotes, and ignores comment / blank lines.
sub _parse_frontmatter ($text) {
    my $yaml = eval {
        require YAML::PP;
        my $pp     = YAML::PP->new;
        my $parsed = $pp->load_string($text);
        ( ref($parsed) eq 'HASH' ) ? $parsed : undef;
    };
    return $yaml if defined $yaml;

    # Minimal fallback: flat key: value lines.
    my %fm;
    for my $line ( split /\n/, $text ) {
        next if $line =~ /\A\s*#/;       # comment
        next if $line =~ /\A\s*\z/;      # blank
        next unless $line =~ /\A\s*([A-Za-z0-9_.\-]+)\s*:\s*(.*?)\s*\z/;
        my ( $k, $v ) = ( $1, $2 );
        $v =~ s/\A(['"])(.*)\1\z/$2/;    # strip matching surrounding quotes
        $fm{$k} = $v;
    }
    return \%fm;
}

# Find all .md files under $skill_dir (recursive) EXCEPT SKILL.md; returns
# a hashref { section_key => absolute_path }. section_key = the file's stem
# for top-level files, ``<relative-parent>/<stem>`` for nested files (fwd
# slashes). Mirrors Python _discover_sections.
sub discover_sections ($skill_dir) {
    my %sections;
    _walk_md(
        $skill_dir,
        $skill_dir,
        sub ( $abs, $rel ) {
            my ( undef, $rel_dir, $file ) = File::Spec->splitpath($rel);
            return if uc($file) eq 'SKILL.MD';

            ( my $stem = $file ) =~ s/\.md\z//i;
            $rel_dir =~ s{[/\\]+\z}{};                # trim trailing separators

            my $key;
            if ( length $rel_dir ) {
                ( my $norm = $rel_dir ) =~ s{\\}{/}g;
                $key = "$norm/$stem";
            } else {
                $key = $stem;
            }
            $sections{$key} = $abs;
        }
    );
    return \%sections;
}

# Recursive walk invoking $cb->($abs_path, $rel_path) for each *.md file.
sub _walk_md ( $root, $dir, $cb ) {
    opendir( my $dh, $dir ) or return;
    my @entries = sort grep { $_ ne '.' && $_ ne '..' } readdir($dh);
    closedir $dh;

    for my $e (@entries) {
        my $abs = File::Spec->catfile( $dir, $e );
        if ( -d $abs ) {
            _walk_md( $root, $abs, $cb );
        } elsif ( -f $abs && $e =~ /\.md\z/i ) {
            my $rel = File::Spec->abs2rel( $abs, $root );
            $cb->( $abs, $rel );
        }
    }
    return;
}

sub _slurp ($path) {
    open my $fh, '<:encoding(UTF-8)', $path or return;
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}

sub _trim ($s) {
    return '' unless defined $s;
    $s =~ s/\A\s+//;
    $s =~ s/\s+\z//;
    return $s;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::SkillDiscovery - shared SKILL.md discovery walker

=head1 DESCRIPTION

One discovery implementation shared by the C<claude_skills> builtin and the
framework-level load-path discovery on L<SignalWire::Skills::SkillRegistry>.
Walks a skills directory, finds each subdirectory's C<SKILL.md>, parses its
YAML frontmatter (via L<YAML::PP> when available, else a minimal flat-scalar
parser) and markdown body, and discovers supporting C<.md> section files.

=head1 FUNCTIONS

=over 4

=item * C<discover_skills($path, %opts)> — arrayref of parsed skill
hashrefs (C<name>, C<description>, C<argument_hint>, C<body>, C<sections>,
C<skill_dir>, C<path>). C<%opts>: C<include> / C<exclude> glob lists.

=item * C<parse_skill_md($file)> — parse one SKILL.md into a hashref.

=item * C<discover_sections($dir)> — map of section-key to C<.md> file path.

=back

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
