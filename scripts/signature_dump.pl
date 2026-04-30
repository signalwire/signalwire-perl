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
find(sub { push @files, $File::Find::name if /\.pm$/ }, $lib_root);
@files = sort @files;

my @types;
for my $file (@files) {
    open my $fh, '<', $file or next;
    my @lines = <$fh>;
    close $fh;
    push @types, parse_file($file, \@lines);
}

print JSON::PP->new->pretty->canonical->encode({ types => \@types });

sub parse_file {
    my ($file, $lines) = @_;
    my @entries;
    my $cur_pkg;
    my @methods;
    my @attrs;

    my $i = 0;
    while ($i < @$lines) {
        my $line = $lines->[$i];

        if ($line =~ /^\s*package\s+([\w:]+)\s*;/) {
            # Flush previous package
            if (defined $cur_pkg && (@methods || @attrs)) {
                push @entries, {
                    full_name => $cur_pkg,
                    methods => [@methods],
                    attributes => [@attrs],
                };
            }
            $cur_pkg = $1;
            @methods = ();
            @attrs = ();
            $i++;
            next;
        }

        if ($line =~ /^\s*sub\s+([A-Za-z_][\w]*)\s*(?:\([^)]*\))?\s*\{/ ||
            $line =~ /^\s*sub\s+([A-Za-z_][\w]*)\s*$/) {
            my $name = $1;
            # Collect body lines (next ~10 lines or until balanced brace)
            my @body;
            my $depth = ($line =~ tr/\{// ) - ($line =~ tr/\}//);
            my $j = $i + 1;
            while ($j < @$lines && $depth > 0 && $j - $i < 30) {
                push @body, $lines->[$j];
                $depth += ($lines->[$j] =~ tr/\{//) - ($lines->[$j] =~ tr/\}//);
                $j++;
            }
            my @params = parse_params(\@body);
            push @methods, {
                name => $name,
                parameters => \@params,
            };
            $i++;
            next;
        }

        # Moo/Moose attribute: has 'name' => ( ... );
        if ($line =~ /^\s*has\s+(?:'([^']+)'|"([^"]+)")\s*=>/) {
            my $attr = $1 // $2;
            push @attrs, { name => $attr };
            $i++;
            next;
        }

        $i++;
    }

    if (defined $cur_pkg && (@methods || @attrs)) {
        push @entries, {
            full_name => $cur_pkg,
            methods => [@methods],
            attributes => [@attrs],
        };
    }
    return @entries;
}

sub parse_params {
    my ($body) = @_;
    my @params;

    for my $bline (@$body) {
        # ``my ($self, $a, $b, $c) = @_;`` — also handles ``my (@args) = @_;``
        # and ``my (%kwargs) = @_;`` (slurpy array / hash) which we tag with
        # a sigil prefix so the canonical translator can distinguish between
        # var_positional (@) and var_keyword (%).
        if ($bline =~ /^\s*my\s*\(\s*([^)]*)\s*\)\s*=\s*\@_\s*;/) {
            my $vars = $1;
            for my $v (split /\s*,\s*/, $vars) {
                next if $v eq '';
                my $sigil = '';
                if ($v =~ /^([\@\%])/) {
                    $sigil = $1;
                }
                $v =~ s/^[\$\@\%]//;
                next if $v eq '';
                push @params, { name => $v, sigil => $sigil };
            }
            return @params;
        }
        # ``my $x = shift;`` style — accumulate
        if ($bline =~ /^\s*my\s+\$(\w+)\s*=\s*shift\s*;/) {
            push @params, { name => $1, sigil => '' };
            next;
        }
        # First non-blank non-comment line that doesn't match either pattern:
        # stop accumulating shift-style and return what we have.
        if ($bline =~ /^\s*[^#\s]/ && !@params) {
            last;
        }
    }
    return @params;
}
