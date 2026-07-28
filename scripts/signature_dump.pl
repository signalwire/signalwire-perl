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
    my @consumes;

    my $i = 0;
    while ( $i < @$lines ) {
        my $line = $lines->[$i];

        if ( $line =~ /^\s*package\s+([\w:]+)\s*;/ ) {

            # Flush previous package
            if ( defined $cur_pkg && ( @methods || @attrs || @extends || @consumes ) ) {
                push @entries,
                    {
                    full_name  => $cur_pkg,
                    methods    => [@methods],
                    attributes => [@attrs],
                    extends    => [@extends],
                    consumes   => [@consumes],
                    };
            }
            $cur_pkg  = $1;
            @methods  = ();
            @attrs    = ();
            @extends  = ();
            @consumes = ();
            $i++;
            next;
        }

        # ``extends 'Parent';`` — single arg
        if ( $line =~ /^\s*extends\s+(?:'([^']+)'|"([^"]+)")/ ) {
            push @extends, ( $1 // $2 );
            $i++;
            next;
        }

        # ``with 'Some::Role';`` — Moo/Moose ROLE COMPOSITION.
        #
        # A composed role is NOT a parent class: Moo FLATTENS the role's
        # attributes and methods directly into the consuming package at
        # `with`-time, so they are the consumer's OWN members (there is no
        # @ISA link and `extends` does not cover them). Without recording
        # this, every member a class gets from a role is invisible to the
        # audit — which is exactly how the 22 generated resource-tree
        # accessors RestClient composes from
        # SignalWire::REST::Namespaces::Generated::ResourceTree went
        # unrecorded while being fully reachable at runtime.
        #
        # Recorded separately from `extends` because the two have different
        # semantics downstream: an `extends` parent contributes constructor
        # args through inheritance, whereas a role's members are flattened
        # in as though written in the consumer's own body.
        #
        # Handles the single-arg form plus the multi-role list
        # (``with 'A', 'B';``), including the parenthesized spelling.
        if ( $line =~ /^\s*with\s*\(?\s*['"]/ ) {
            my $decl = with_decl_text( $lines, $i );
            while ( $decl =~ /(?:'([^']+)'|"([^"]+)")/g ) {
                my $role = $1 // $2;
                push @consumes, $role unless grep { $_ eq $role } @consumes;
            }
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

                # A signature default of ``undef`` is frequently a PLACEHOLDER
                # that the prologue immediately resolves:
                #     sub hold ( $self, $timeout = undef ) { $timeout //= 300; }
                # The real contract is "omitting the argument yields 300"; the
                # ``= undef`` only reserves the slot. Scanning the prologue
                # recovers the value the caller actually gets, so this spelling
                # and the classic-unpack spelling report the SAME default.
                apply_body_defaults( \@params, \@body );
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
            my ( $default,  $has_default )  = attr_default( $lines, $i );
            push @attrs,
                {
                name     => $attr,
                required => attr_required( $lines, $i ),
                ( $has_init_arg ? ( init_arg => $init_arg ) : () ),
                ( $has_default  ? ( default  => $default )  : () ),
                };
            $i++;
            next;
        }

        $i++;
    }

    if ( defined $cur_pkg && ( @methods || @attrs || @extends || @consumes ) ) {
        push @entries,
            {
            full_name  => $cur_pkg,
            methods    => [@methods],
            attributes => [@attrs],
            extends    => [@extends],
            consumes   => [@consumes],
            };
    }
    return @entries;
}

# The source text of the ``with '...';`` role composition starting at
# $lines->[$start]. A ``with`` may list several roles and may wrap across
# lines, so scan forward to the terminating ``;`` (bounded, like the ``has``
# scanner) rather than reading a single line.
sub with_decl_text {
    my ( $lines, $start ) = @_;
    my $text = '';
    for my $j ( $start .. $#$lines ) {
        my $l = $lines->[$j];
        $text .= $l;
        last if $l =~ /;/;
        last if $j - $start > 10;
    }
    return $text;
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

# The ``default`` VALUE of the ``has`` declaration at $lines->[$start], as
# ``($value, $present)``.
#
# Moo's ``default`` is what the constructor stores when the caller passes
# nothing — i.e. the Perl spelling of the reference's per-parameter default
# VALUE, which the cross-port defaults comparison needs as a real typed value
# (``900``, not ``"900"``; ``sub { 900 }`` yields ``900``).
#
# Moo requires a non-scalar default to be a CODEREF (``default => sub { [] }``)
# because a bare reference would be shared across instances, so essentially
# every default in this SDK is written ``default => sub { EXPR }``. We unwrap
# that one level and read EXPR. The bare-scalar spelling (``default => 900``)
# is accepted too, since Moo permits it for simple scalars.
#
# ONLY a literal EXPR is recoverable. ``sub { _random_hex(32) }`` computes its
# value at construction time and has no static value — a function call, a method
# call, a variable, or an expression yields ``($present = 0)`` so the caller
# emits NO default rather than a fabricated one. This is a deliberate,
# documented blind spot: a wrong default is worse than a missing one.
#
# Returns the value already typed for JSON: a number stays numeric (so
# ``JSON::PP`` encodes ``900`` not ``"900"``), a quoted string stays a string,
# and ``undef`` is returned as present-with-undef-value (a real "defaults to
# undef" declaration, distinct from "no default declared").
sub attr_default {
    my ( $lines, $start ) = @_;
    my $decl = attr_decl_text( $lines, $start );

    # Isolate the text following ``default =>`` up to the option that follows.
    return ( undef, 0 ) unless $decl =~ /\bdefault\s*=>\s*(.*)$/s;
    my $rest = $1;

    my $expr;
    if ( $rest =~ /^\s*sub\s*\{/ ) {

        # Unwrap ONE coderef level by matching balanced braces from the ``{``.
        my $open  = index( $rest, '{' );
        my $depth = 0;
        my $close;
        for my $k ( $open .. length($rest) - 1 ) {
            my $ch = substr( $rest, $k, 1 );
            $depth++ if $ch eq '{';
            if ( $ch eq '}' ) {
                $depth--;
                if ( $depth == 0 ) { $close = $k; last; }
            }
        }
        return ( undef, 0 ) unless defined $close;
        $expr = substr( $rest, $open + 1, $close - $open - 1 );
    } else {

        # Bare-scalar default: read up to the option separator / end of list.
        ($expr) = $rest =~ /^([^,\)]*)/;
    }

    # Anything that is not a literal — a function call (``_random_hex(32)``), a
    # constructor (``SignalWire::POM::PromptObjectModel->new``), a variable, a
    # computed expression — has NO static value, and ``literal_value`` reports
    # it as unrecovered so we emit no default rather than a fabricated one.
    return literal_value($expr);
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
# translator can map them to var_positional / var_keyword.
#
# Defaults (``= EXPR``) are RECOVERED, not stripped: ``$beta = 5`` records the
# value 5. The reference oracle records real default VALUES per parameter, and
# a port that emits none makes a defaults comparison vacuous. Only a LITERAL
# EXPR is recoverable (same rule as ``attr_default``) — a call or an expression
# has no static value and records no default rather than a fabricated one.
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

        # Split off the default: ``$beta = 5`` / ``$x //= 'foo'``.
        my $default_expr;
        if ( $part =~ s/(?:\/\/=|=)(.*)$//s ) {
            $default_expr = $1;
        }
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

        my %p = ( name => $part, sigil => $sigil );
        if ( defined $default_expr ) {
            my ( $v, $present ) = literal_value($default_expr);
            if ($present) {
                $p{default}     = $v;
                $p{has_default} = 1;
            } else {

                # A default EXISTS but its value is not statically recoverable.
                # Record that fact (it makes the param optional) without
                # claiming a value.
                $p{has_default} = 1;
            }
        }
        push @params, \%p;
    }
    return @params;
}

# ``($value, $recovered)`` for a Perl literal expression. Shared by
# ``parse_signature`` and ``attr_default`` so the two spellings of a default
# are read by the SAME rule. Returns $recovered = 0 for anything that is not a
# literal (a call, a variable, an interpolating string) — those have no static
# value and must emit no default.
sub literal_value {
    my ($expr) = @_;
    return ( undef, 0 ) unless defined $expr;
    $expr =~ s/#.*$//mg;
    $expr =~ s/^\s+//;
    $expr =~ s/\s+$//;
    $expr =~ s/;\s*$//;
    $expr =~ s/^\s+//;
    $expr =~ s/\s+$//;
    return ( undef, 0 ) if $expr eq '';

    return ( undef,       1 ) if $expr eq 'undef';
    return ( [],          1 ) if $expr =~ /^\[\s*\]$/;
    return ( {},          1 ) if $expr =~ /^\{\s*\}$/;
    return ( 0 + $expr,   1 ) if $expr =~ /^-?\d+$/;
    return ( 0.0 + $expr, 1 )
        if $expr =~ /^-?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?$/;
    if ( $expr =~ m{^[\d\s\.\*\+\-/\(\)]+$} && $expr =~ /\d/ ) {
        my $v = eval $expr;    ## no critic
        return ( $v + 0, 1 ) if !$@ && defined $v && $v =~ /^-?[\d.]+$/;
        return ( undef,  0 );
    }
    return ( "$1",  1 ) if $expr =~ /^'([^'\\]*)'$/;
    return ( "$1",  1 ) if $expr =~ /^"([^"\\\$\@]*)"$/;
    return ( undef, 0 );
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
            apply_body_defaults( \@params, $body );
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
    apply_body_defaults( \@params, $body );
    return @params;
}

# Recover per-parameter DEFAULTS from the body of a sub that unpacks with
# ``my (...) = @_;`` (or ``my $x = shift;``).
#
# The Perl 5.20+ signature form spells a default IN the signature
# (``sub f ($self, $timeout = 300)``) and ``parse_signature`` reads it there.
# The classic unpack form CANNOT — ``@_`` assignment has no default slot — so
# the SDK spells the very same contract on the next line:
#
#     sub validate_url {
#         my ( $url, $allow_private ) = @_;
#         $allow_private //= 0;
#
# That ``//=`` is not an implementation detail; it IS how this idiom declares
# "omitting the argument yields 0". A caller may omit ``$allow_private`` and
# gets exactly the reference's ``allow_private: bool = False`` behaviour. The
# parser previously saw only the unpack line, so every such parameter was
# emitted with no default and therefore ``required: True`` — reporting the
# whole ``my (...) = @_`` half of the SDK as demanding arguments it does not
# demand. That produced 25 spurious ``required-flip`` findings against a
# reference the source already matches.
#
# Only a defaulting assignment to a parameter NAME is recognised, in the two
# spellings the SDK uses:
#
#     $x //= EXPR;                     # defined-or assign
#     $x = EXPR unless defined $x;     # the long-hand equivalent
#
# A plain ``$x = EXPR;`` is deliberately NOT treated as a default: that is an
# unconditional overwrite of whatever the caller passed, which is a
# transformation of the argument, not a default for its absence (e.g.
# ``$route = "/$route" unless $route =~ m{^/}`` normalises a value the caller
# DID supply). Reading those as defaults would mark genuinely required
# parameters optional — the opposite error, and the more dangerous one.
#
# ONLY THE PROLOGUE COUNTS. The scan stops at the first statement that is not
# itself a defaulting assignment. That restriction is load-bearing, because the
# SAME ``//=`` syntax spells two different contracts depending on where it sits:
#
#   sub handle_request {                  |  sub validate_webhook_signature {
#       my ( $self, $m, $u, $h ) = @_;    |      my ( $key, $sig, $url ) = @_;
#       $h //= {};      # <- DEFAULT      |      croak "signing_key is required"
#       ...                               |          unless defined $key;
#                                         |      return 0 unless defined $sig;
#                                         |      $url = '' unless defined $url;
#                                         |          # <- NIL-COERCION, not a default
#
# On the right the sub has already REJECTED an under-specified call; the later
# ``$url = ''`` only keeps the hashing arithmetic from warning on undef. The
# parameter is still required — the reference records it required — and reading
# that line as a default would silently report a required param as optional.
# Restricting recovery to the prologue separates the two without a per-symbol
# table: a default is what the sub does BEFORE it does anything else.
#
# The recovered VALUE follows the same literal-only rule as ``attr_default``
# and ``parse_signature``: a computed default (``//= _random_urlsafe(16)``,
# ``//= $agent->route``) marks the parameter optional (``has_default``) but
# records no value, because a fabricated default is worse than a missing one.
sub apply_body_defaults {
    my ( $params, $body ) = @_;
    return unless @$params;

    my %by_name = map { $_->{name} => $_ } grep { !$_->{sigil} } @$params;
    return unless %by_name;

    for my $line (@$body) {

        # A TRAILING comment is not part of the statement. Strip it before
        # matching so ``$body //= '';    # Python parity: ...`` is recognised —
        # the SDK annotates these lines precisely because they encode contract,
        # and an end-anchored pattern that only matched bare statements would
        # miss the very lines most likely to carry a default.
        # Only a comment that follows a STATEMENT TERMINATOR is stripped
        # (``...;   # note``). Anchoring on the ``;`` keeps a ``#`` living
        # inside a string or regex literal — ``'#channel'``, ``m{/#/}`` —
        # safely out of reach, which a bare ``s/#.*$//`` would mangle.
        my $bline = $line;
        $bline =~ s/;\s+#.*$/;/;

        # Blank lines, comments, and the ``sub NAME {`` / unpack lines are not
        # statements — they do not end the prologue.
        next if $bline =~ /^\s*$/;
        next if $bline =~ /^\s*#/;
        next if $bline =~ /^\s*sub\s+\w+/;
        next if $bline =~ /\bmy\s*\(.*\)\s*=\s*\@_\s*;/;
        next if $bline =~ /\bmy\s+\$\w+\s*=\s*shift\s*;/;

        # A bare ``shift`` that drops a class-method RECEIVER is argument
        # plumbing, not a statement about the parameters — a dual free-function
        # / class-method sub normalises ``@_`` before it can unpack. Treating it
        # as the end of the prologue would hide the very next line's default.
        next if $bline =~ /^\s*shift\b[^;]*;\s*$/;

        # ``$x //= EXPR;``
        if ( $bline =~ /^\s*\$(\w+)\s*\/\/=\s*(.+?)\s*;\s*$/ ) {
            last unless record_body_default( \%by_name, $1, $2 );
            next;
        }

        # ``$x = EXPR unless defined $x;`` — the long-hand of the above. The
        # guard must name the SAME variable, otherwise it is a conditional
        # assignment driven by something else and not a default at all.
        if (   $bline =~ /^\s*\$(\w+)\s*=\s*(.+?)\s+unless\s+defined\s+\$(\w+)\s*;\s*$/
            && $1 eq $3 )
        {
            last unless record_body_default( \%by_name, $1, $2 );
            next;
        }

        # Any other statement ends the prologue.
        last;
    }
    return;
}

# Attach a recovered body default to the named parameter.
#
# ``has_default`` is set unconditionally (the parameter IS optional — that is
# syntax, not value analysis); ``default`` only when the expression is a
# recoverable literal.
#
# Returns TRUE when the assignment targeted a PARAMETER, i.e. when the prologue
# continues. A defaulting assignment to a local (``$expected //= ...``) is a
# real statement about something other than the signature, so it ENDS the
# prologue — returning false is what stops the scan there.
sub record_body_default {
    my ( $by_name, $name, $expr ) = @_;
    my $p = $by_name->{$name} or return 0;

    # First default wins, with ONE exception: a signature ``= undef``
    # placeholder that the prologue immediately resolves (``$t = undef`` then
    # ``$t //= 300``). ``undef`` there is a slot reservation, not the value the
    # caller gets, so the prologue's value supersedes it. Any other recorded
    # default is kept — a later re-assignment transforms the already-defaulted
    # value rather than re-declaring it. Either way the prologue continues:
    # this line WAS about a parameter.
    if ( $p->{has_default} ) {
        my $placeholder = exists $p->{default} && !defined $p->{default};
        return 1 unless $placeholder;
    }

    $p->{has_default} = 1;
    delete $p->{default};
    my ( $v, $present ) = literal_value($expr);
    $p->{default} = $v if $present;
    return 1;
}
