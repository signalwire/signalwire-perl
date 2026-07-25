#!/usr/bin/env perl
# signature_dump.pl -- best-effort signature dump of the SignalWire Perl SDK.
#
# Walks every .pm file under lib/, parses out:
#   - the current `package` declaration
#   - each `sub NAME { ... }` block
#   - inside each block: the first ``my (...) = @_;`` line OR a sequence of
#     ``my $x = shift;`` lines. The parameter names from those forms are
#     emitted in order (skipping the first $self).
#   - Moo / Moose ``has 'attr' => ( ... )`` declarations, emitted as zero-arg
#     getters.
#
# Output: pretty-printed JSON to stdout, consumed by enumerate_signatures.py.
#
# Caveats: regex parsing of Perl is provably impossible in the general case
# (PPI's README says as much). The SDK's style is uniform enough that this
# best-effort parser covers most methods. Edge cases (conditional unpack,
# slurpy ``@rest``, signatures-feature opt-in via ``use feature 'signatures'``)
# will surface as drift in the diff and can either be fixed in source or
# documented in PORT_SIGNATURE_OMISSIONS.md.

use strict;
use warnings;
use File::Find;
use JSON::PP;

my $lib_root = $ARGV[0] // 'lib';
die "lib directory not found: $lib_root\n" unless -d $lib_root;

my @files;
find( sub { push @files, $File::Find::name if /\.pm$/ }, $lib_root );
@files = sort @files;

my @types;
for my $file (@files) {
    open my $fh, '<', $file or next;
    my @lines = <$fh>;
    close $fh;
    push @types, parse_file( $file, \@lines );
}

print JSON::PP->new->pretty->canonical->encode( { types => \@types } );

sub parse_file {
    my ( $file, $lines ) = @_;
    my @entries;
    my $cur_pkg;
    my @methods;
    my @attrs;
    my @extends;

    my $i = 0;
    while ( $i < @$lines ) {
        my $line = $lines->[$i];

        if ( $line =~ /^\s*package\s+([\w:]+)\s*;/ ) {

            # Flush previous package
            if ( defined $cur_pkg && ( @methods || @attrs || @extends ) ) {
                push @entries,
                    {
                    full_name  => $cur_pkg,
                    methods    => [@methods],
                    attributes => [@attrs],
                    extends    => [@extends],
                    };
            }
            $cur_pkg = $1;
            @methods = ();
            @attrs   = ();
            @extends = ();
            $i++;
            next;
        }

        # ``extends 'Parent';`` — single arg
        if ( $line =~ /^\s*extends\s+(?:'([^']+)'|"([^"]+)")/ ) {
            push @extends, ( $1 // $2 );
            $i++;
            next;
        }

        # ``sub NAME (SIGNATURE) {`` / ``sub NAME {`` / bare ``sub NAME``.
        # The optional ``(SIGNATURE)`` is the Perl 5.20+ subroutine-
        # signatures feature (``use feature 'signatures'``). We CAPTURE it
        # (rather than discard) so a method written in signature form
        #   sub foo ($self, $alpha, $beta = 5, %opts) { ... }
        # yields the same parameter inventory as the classic
        #   sub foo { my ($self, $alpha, $beta, %opts) = @_; ... }
        # form. Without this, a port-side switch to signatures would drop
        # every parameter and surface as spurious arity drift.
        my ( $name, $sig );
        if ( $line =~ /^\s*sub\s+([A-Za-z_][\w]*)\s*(\([^)]*\))?\s*\{/ ) {
            ( $name, $sig ) = ( $1, $2 );
        } elsif ( $line =~ /^\s*sub\s+([A-Za-z_][\w]*)\s*(\([^)]*\))?\s*$/ ) {

            # Declaration with no opening brace on this line (brace on the
            # next line). The signature, if any, is still on this line.
            ( $name, $sig ) = ( $1, $2 );
        }
        if ( defined $name ) {

            # Collect body lines. Always include the sub-declaration line
            # itself so single-line definitions like
            #   sub play_pause { my ($s, $id, %p) = @_; ... }
            # have their params parsed (depth becomes 0 immediately and
            # the j-loop below skips body collection).
            my @body  = ($line);
            my $depth = ( $line =~ tr/\{// ) - ( $line =~ tr/\}// );
            my $j     = $i + 1;
            while ( $j < @$lines && $depth > 0 && $j - $i < 30 ) {
                push @body, $lines->[$j];
                $depth += ( $lines->[$j] =~ tr/\{// ) - ( $lines->[$j] =~ tr/\}// );
                $j++;
            }

            # A non-empty signature parenthetical is authoritative: parse
            # the names straight from it. An empty signature ``()`` means a
            # genuinely zero-parameter sub (e.g. a classmethod-free helper).
            # When there's no signature at all, fall back to scanning the
            # body for ``my (...) = @_`` / ``my $x = shift``.
            my @params;
            if ( defined $sig ) {
                @params = parse_signature($sig);
            } else {
                @params = parse_params( \@body );
            }
            push @methods,
                {
                name       => $name,
                parameters => \@params,
                };
            $i++;
            next;
        }

        # Moo/Moose attribute: has 'name' => ( ... );
        if ( $line =~ /^\s*has\s+(?:'([^']+)'|"([^"]+)")\s*=>/ ) {
            my $attr = $1 // $2;

            # ``required => 1`` is part of the CONSTRUCTION CONTRACT
            # (porting-sdk ALLOWLIST_DISCIPLINE.md §10: ``required`` is
            # contract and must not vary between ports), so it has to be
            # recovered from the declaration, not defaulted. A ``has``
            # spans multiple lines whenever the option hash is wrapped, so
            # scan forward to the end of the declaration (balanced parens,
            # or the terminating ``;`` for the single-line form).
            # ``init_arg`` is Moo's CONSTRUCTOR-ARGUMENT name, and it is the
            # authority on what a caller may pass:
            #   * ``init_arg => 'project'`` renames the constructor arg (the
            #     attribute is stored as ``_project_id`` but built as
            #     ``->new( project => ... )``);
            #   * ``init_arg => undef`` removes the attribute from the
            #     constructor entirely (the lazy resource-tree accessors).
            # Both are construction contract, so record them alongside the name.
            my ( $init_arg, $has_init_arg ) = attr_init_arg( $lines, $i );
            push @attrs,
                {
                name     => $attr,
                required => attr_required( $lines, $i ),
                ( $has_init_arg ? ( init_arg => $init_arg ) : () ),
                };
            $i++;
            next;
        }

        $i++;
    }

    if ( defined $cur_pkg && ( @methods || @attrs || @extends ) ) {
        push @entries,
            {
            full_name  => $cur_pkg,
            methods    => [@methods],
            attributes => [@attrs],
            extends    => [@extends],
            };
    }
    return @entries;
}

# Does the Moo/Moose ``has`` declaration starting at $lines->[$start] carry
# ``required => 1``?
#
# Moo's auto-generated ``new`` accepts EVERY attribute as a named constructor
# argument, and ``required => 1`` is what makes one mandatory — i.e. it is the
# Perl spelling of a reference constructor param with no default. The
# construction contract compares ``required`` by name across ports
# (ALLOWLIST_DISCIPLINE.md §10), so it must be read from the source rather than
# assumed; without this, every required Perl attribute reports as optional.
#
# A ``has`` runs from its declaration line to the end of the option list. Track
# paren depth from the ``=>`` onward and stop at depth 0 — that handles both the
# single-line ``has 'x' => ( is => 'ro', required => 1 );`` and the wrapped
# multi-line form. The paren-less shorthand (``has 'x' => ( ... )`` is the only
# form this SDK uses) terminates at the first ``;`` seen at depth 0.
sub attr_required {
    my ( $lines, $start ) = @_;
    my $decl = attr_decl_text( $lines, $start );
    return $decl =~ /\brequired\s*=>\s*1\b/ ? 1 : 0;
}

# The ``init_arg`` of the ``has`` declaration at $lines->[$start], as
# ``($value, $present)``. ``$value`` is undef for ``init_arg => undef`` (the
# attribute is NOT a constructor argument) and the quoted string otherwise (the
# constructor argument is spelled differently from the attribute).
sub attr_init_arg {
    my ( $lines, $start ) = @_;
    my $decl = attr_decl_text( $lines, $start );
    if ( $decl =~ /\binit_arg\s*=>\s*(?:'([^']*)'|"([^"]*)")/ ) {
        return ( ( $1 // $2 ), 1 );
    }
    if ( $decl =~ /\binit_arg\s*=>\s*undef\b/ ) {
        return ( undef, 1 );
    }
    return ( undef, 0 );
}

# The source text of the Moo/Moose ``has`` declaration starting at
# $lines->[$start] — from its ``=>`` to the end of the option list.
#
# A ``has`` spans multiple lines whenever the option hash is wrapped, so track
# paren depth and stop at depth 0; the paren-less single-line form terminates at
# the first ``;``. Everything before the first ``=>`` is dropped so a word in a
# preceding comment, or in the attribute NAME itself, can't be misread as an
# option.
sub attr_decl_text {
    my ( $lines, $start ) = @_;

    my @collected;
    my $depth     = 0;
    my $seen_open = 0;
    for my $j ( $start .. $#$lines ) {
        my $text = $lines->[$j];
        $text =~ s/^.*?=>// if $j == $start;
        push @collected, $text;

        $depth += ( $text =~ tr/\(// ) - ( $text =~ tr/\)// );
        $seen_open = 1 if $text =~ /\(/;

        # End of the declaration: balanced parens after having opened one, or a
        # statement terminator before any paren opened.
        last if $seen_open  && $depth <= 0;
        last if !$seen_open && $text =~ /;/;

        # Defensive bound — a runaway scan would leak into the next declaration
        # and mis-attribute its options.
        last if $j - $start > 30;
    }
    return join( '', @collected );
}

# Parse a Perl 5.20+ subroutine signature parenthetical, e.g.
#   ($self, $alpha, $beta = 5, @rest)   or   ($self, %opts)
# into the same { name => ..., sigil => ... } shape parse_params emits
# from ``my (...) = @_``. The leading ``$`` sigil is dropped (positional
# scalars carry sigil => ''); ``@`` / ``%`` are preserved so the canonical
# translator can map them to var_positional / var_keyword. Defaults
# (``= EXPR``) are stripped — they don't affect the parameter NAME or its
# kind, and matching Python's per-parameter ``required`` flag is handled
# downstream from the Python reference, not from the Perl default here.
sub parse_signature {
    my ($sig) = @_;

    # Strip the surrounding parens.
    $sig =~ s/^\s*\(//;
    $sig =~ s/\)\s*$//;
    my @params;

    # Split on top-level commas. Signature defaults in this SDK are simple
    # scalars/strings without nested commas, so a plain comma split is
    # sufficient (and the parser is best-effort by design).
    for my $part ( split /,/, $sig ) {

        # Drop any default: ``$beta = 5`` / ``$x //= 'foo'`` -> ``$beta``.
        $part =~ s/(?:\/\/=|=).*$//s;
        $part =~ s/^\s+//;
        $part =~ s/\s+$//;
        next if $part eq '';

        # A bare sigil placeholder (``$``, ``@``, ``%`` with no name) is a
        # signature's way of accepting-and-ignoring an argument; skip it
        # since it has no name to record.
        my $sigil = '';
        if ( $part =~ /^([\@\%])/ ) {
            $sigil = $1;
        }
        $part =~ s/^[\$\@\%]//;
        next if $part eq '';
        next unless $part =~ /^[A-Za-z_]\w*$/;
        push @params, { name => $part, sigil => $sigil };
    }
    return @params;
}

sub parse_params {
    my ($body) = @_;
    my @params;

    for my $bline (@$body) {

        # ``my ($self, $a, $b, $c) = @_;`` — also handles ``my (@args) = @_;``
        # and ``my (%kwargs) = @_;`` (slurpy array / hash) which we tag with
        # a sigil prefix so the canonical translator can distinguish between
        # var_positional (@) and var_keyword (%).
        # The pattern may appear anywhere on the line (single-line subs put
        # it after `sub NAME {`).
        if ( $bline =~ /\bmy\s*\(\s*([^)]*)\s*\)\s*=\s*\@_\s*;/ ) {
            my $vars = $1;
            for my $v ( split /\s*,\s*/, $vars ) {

                # Trim surrounding whitespace so a perltidy-spaced unpack
                # ``my ( $self, $query ) = @_;`` yields the same parameter
                # NAMES as the tight ``my ($self, $query) = @_;`` form. The
                # split's ``\s*`` collapses inter-element spaces, but the
                # first/last element can still carry a leading/trailing space
                # (the capture's ``[^)]*`` swallows the inner padding); without
                # this trim the trailing var becomes ``query `` (with a space)
                # and shows up as spurious signature drift. FMT is source-style
                # only — the parser must be whitespace-agnostic.
                $v =~ s/^\s+//;
                $v =~ s/\s+$//;
                next if $v eq '';
                my $sigil = '';
                if ( $v =~ /^([\@\%])/ ) {
                    $sigil = $1;
                }
                $v =~ s/^[\$\@\%]//;
                next if $v eq '';
                push @params, { name => $v, sigil => $sigil };
            }
            return @params;
        }

        # ``my $x = shift;`` style — accumulate
        if ( $bline =~ /\bmy\s+\$(\w+)\s*=\s*shift\s*;/ ) {
            push @params, { name => $1, sigil => '' };
            next;
        }

        # Skip the sub-declaration line itself - it's only included so that
        # single-line definitions get parsed.
        next if $bline =~ /^\s*sub\s+\w+/;

        # First non-blank non-comment line that doesn't match either pattern:
        # stop accumulating shift-style and return what we have.
        if ( $bline =~ /^\s*[^#\s]/ && !@params ) {
            last;
        }
    }
    return @params;
}
