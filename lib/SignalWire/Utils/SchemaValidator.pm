package SignalWire::Utils::SchemaValidator;
use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
no warnings 'experimental::signatures';

use Scalar::Util ();

# SchemaValidator — a focused JSON Schema (Draft 2020-12 subset) evaluator for
# the bundled SWML schema. It is the Perl analogue of the python reference's
# jsonschema-rs full validator: it exists so a MISSHAPEN SWML verb config (an
# unknown/misspelled/wrong-typed key on a closed verb) is REJECTED, not
# silently accepted — the STRICT-RENDER contract (Wave-2 P#5).
#
# Scope: it supports exactly the keywords the SWML schema.json uses —
#   $ref, allOf, anyOf, oneOf, not, if/then/else, type, const, enum,
#   properties, required, items, minItems, minProperties, minimum, maximum,
#   pattern, format, additionalProperties, and unevaluatedProperties.
# The closed-object machinery (properties evaluated across the applicators, then
# unevaluatedProperties/additionalProperties rejecting the rest) is what makes a
# stray top-level key on a closed verb — and thus a misspelling — an error.
# ``unevaluatedProperties`` / ``additionalProperties`` set to a schema of ``{}``
# (matches anything) leaves the object OPEN (that is the deliberate ai.params
# open door). ``{ not => {} }`` closes it (nothing matches ``not: {}``).
#
# Construction: new(schema => <root schema hashref>). The root is used to
# resolve local ``#/$defs/...`` $refs.

has 'schema' => ( is => 'ro', required => 1 );

# validate($instance, $subschema) — validate $instance against $subschema
# (default: the root schema). Returns a list of human-readable error strings;
# an empty list means the instance is valid.
sub validate ( $self, $instance, $subschema = undef ) {
    $subschema //= $self->schema;
    my @errors;
    $self->_eval( $instance, $subschema, '', \@errors );
    return @errors;
}

# is_valid($instance, $subschema) — boolean convenience wrapper.
sub is_valid ( $self, $instance, $subschema = undef ) {
    my @e = $self->validate( $instance, $subschema );
    return @e ? 0 : 1;
}

# Resolve a local "#/$defs/Name" (or "#/..." pointer) $ref against the root.
sub _resolve_ref ( $self, $ref ) {
    return unless defined $ref && !ref $ref;
    return unless $ref =~ m{^#/};
    my $node = $self->schema;
    for my $seg ( split m{/}, substr( $ref, 2 ) ) {
        $seg =~ s/~1/\//g;
        $seg =~ s/~0/~/g;
        return unless ref $node eq 'HASH' && exists $node->{$seg};
        $node = $node->{$seg};
    }
    return $node;
}

# _matches — a boolean "does $instance satisfy $schema" (no error collection),
# used by anyOf/oneOf/not/if and by unevaluatedProperties bookkeeping.
sub _matches ( $self, $instance, $schema ) {
    my @errors;
    $self->_eval( $instance, $schema, '', \@errors );
    return @errors ? 0 : 1;
}

# The core recursive evaluator. Appends error strings (prefixed by JSON-pointer
# $path) to $errors. $evaluated (optional) is a hashref used at object scope to
# record which property names were evaluated by properties (so
# unevaluatedProperties can reject the rest).
sub _eval ( $self, $instance, $schema, $path, $errors, $evaluated = undef ) {

    # A boolean schema: true = always valid, false = always invalid.
    if ( !ref $schema ) {
        push @$errors, "$path: schema is false (nothing valid here)"
            if defined $schema && "$schema" eq '0';
        return;
    }
    return unless ref $schema eq 'HASH';

    # $ref: resolve and evaluate the target in place (Draft 2020-12 lets $ref
    # sit beside other keywords; we evaluate both).
    if ( defined $schema->{'$ref'} ) {
        my $target = $self->_resolve_ref( $schema->{'$ref'} );
        if ( defined $target ) {
            $self->_eval( $instance, $target, $path, $errors, $evaluated );
        }
    }

    # type
    if ( defined $schema->{type} ) {
        my @types = ref $schema->{type} eq 'ARRAY' ? @{ $schema->{type} } : ( $schema->{type} );
        my $ok    = 0;
        for my $t (@types) { $ok = 1 if _type_ok( $instance, $t ); }
        push @$errors, "$path: expected type " . join( '|', @types )
            unless $ok;
    }

    # const
    if ( exists $schema->{const} ) {
        push @$errors, "$path: value does not equal const"
            unless _deep_eq( $instance, $schema->{const} );
    }

    # enum
    if ( ref $schema->{enum} eq 'ARRAY' ) {
        my $ok = 0;
        for my $e ( @{ $schema->{enum} } ) { $ok = 1 if _deep_eq( $instance, $e ); }
        push @$errors, "$path: value not in enum" unless $ok;
    }

    # numeric bounds
    if ( _is_number($instance) ) {
        push @$errors, "$path: below minimum"
            if defined $schema->{minimum} && $instance < $schema->{minimum};
        push @$errors, "$path: above maximum"
            if defined $schema->{maximum} && $instance > $schema->{maximum};
    }

    # string pattern — enforced for string instances. This is load-bearing:
    # numeric-typed fields commonly union `anyOf:[{type:integer},{$ref:SWMLVar}]`
    # where SWMLVar is a `${..}`/`%{..}` variable string; without the pattern a
    # plain non-variable string would spuriously satisfy the SWMLVar branch and
    # a wrong-typed value would slip through. format is advisory (not enforced).
    if ( defined $schema->{pattern} && defined $instance && !ref $instance ) {
        my $re = $schema->{pattern};
        push @$errors, "$path: string does not match pattern"
            unless $instance =~ /$re/;
    }

    # allOf
    if ( ref $schema->{allOf} eq 'ARRAY' ) {
        for my $sub ( @{ $schema->{allOf} } ) {
            $self->_eval( $instance, $sub, $path, $errors, $evaluated );
        }
    }

    # anyOf — at least one branch must match. On success, mark the matching
    # branch's evaluated properties (best-effort: mark ALL of the instance's
    # keys that the matching branch evaluates).
    if ( ref $schema->{anyOf} eq 'ARRAY' ) {
        my $matched;
        for my $sub ( @{ $schema->{anyOf} } ) {
            if ( $self->_matches( $instance, $sub ) ) { $matched = $sub; last; }
        }
        if ( !defined $matched ) {
            push @$errors, "$path: does not match any anyOf branch";
        } elsif ($evaluated) {
            $self->_mark_evaluated( $instance, $matched, $evaluated );
        }
    }

    # oneOf — exactly one branch must match.
    if ( ref $schema->{oneOf} eq 'ARRAY' ) {
        my @matched = grep { $self->_matches( $instance, $_ ) } @{ $schema->{oneOf} };
        if ( @matched != 1 ) {
            push @$errors, "$path: matched " . scalar(@matched) . " oneOf branches (want 1)";
        } elsif ($evaluated) {
            $self->_mark_evaluated( $instance, $matched[0], $evaluated );
        }
    }

    # not
    if ( exists $schema->{not} ) {
        push @$errors, "$path: matches 'not' schema (must not)"
            if $self->_matches( $instance, $schema->{not} );
    }

    # if / then / else
    if ( exists $schema->{if} ) {
        if ( $self->_matches( $instance, $schema->{if} ) ) {
            $self->_eval( $instance, $schema->{then}, $path, $errors, $evaluated )
                if exists $schema->{then};
        } else {
            $self->_eval( $instance, $schema->{else}, $path, $errors, $evaluated )
                if exists $schema->{else};
        }
    }

    # Array keywords
    if ( ref $instance eq 'ARRAY' ) {
        push @$errors, "$path: fewer than minItems"
            if defined $schema->{minItems} && @$instance < $schema->{minItems};
        if ( ref $schema->{items} eq 'HASH' ) {
            for my $i ( 0 .. $#$instance ) {
                $self->_eval( $instance->[$i], $schema->{items}, "$path/$i", $errors );
            }
        }
    }

    # Object keywords
    if ( ref $instance eq 'HASH' ) {
        $self->_eval_object( $instance, $schema, $path, $errors, $evaluated );
    }

    return;
}

# Object-scope evaluation: required, properties (recording evaluated keys), and
# the additionalProperties / unevaluatedProperties closedness gate.
sub _eval_object ( $self, $instance, $schema, $path, $errors, $parent_evaluated ) {

    # required
    if ( ref $schema->{required} eq 'ARRAY' ) {
        for my $r ( @{ $schema->{required} } ) {
            push @$errors, "$path: missing required property '$r'"
                unless exists $instance->{$r};
        }
    }

    # A local record of which keys THIS schema evaluates (properties +
    # applicators that ran here). Seeded from any parent-provided record so
    # unevaluatedProperties sees keys evaluated by sibling applicators.
    my %evaluated = $parent_evaluated ? %$parent_evaluated : ();

    my $props = $schema->{properties};
    if ( ref $props eq 'HASH' ) {
        for my $k ( keys %$instance ) {
            next unless exists $props->{$k};
            $evaluated{$k} = 1;
            $self->_eval( $instance->{$k}, $props->{$k}, "$path/$k", $errors );
        }
    }

    # Fold in keys evaluated by in-place applicators (allOf/anyOf/oneOf/$ref/
    # if-then-else) that ran against this object. _eval marked them into
    # $parent_evaluated via _mark_evaluated when it passed the same hashref
    # down; here we re-run that marking for the applicators so
    # unevaluatedProperties is accurate.
    $self->_mark_evaluated( $instance, $schema, \%evaluated );

    # additionalProperties — schema for keys NOT in properties.
    if ( exists $schema->{additionalProperties} ) {
        my $ap = $schema->{additionalProperties};
        for my $k ( keys %$instance ) {
            next if $evaluated{$k};
            if ( !ref $ap && defined $ap && "$ap" eq '0' ) {
                push @$errors, "$path: additional property '$k' is not allowed";
            } elsif ( ref $ap eq 'HASH' ) {
                $self->_eval( $instance->{$k}, $ap, "$path/$k", $errors );
                $evaluated{$k} = 1;
            } else {
                $evaluated{$k} = 1;    # true / {} — open
            }
        }
    }

    # unevaluatedProperties — schema for keys not evaluated by properties or any
    # applicator. This is what closes a verb: { not => {} } matches nothing so
    # every unevaluated key errors; {} (or true) matches everything so the
    # object stays OPEN (the ai.params door).
    if ( exists $schema->{unevaluatedProperties} ) {
        my $up = $schema->{unevaluatedProperties};
        for my $k ( keys %$instance ) {
            next if $evaluated{$k};
            if ( $self->_matches( $instance->{$k}, $up ) ) {
                $evaluated{$k} = 1;    # allowed by the unevaluated schema
            } else {
                push @$errors, "$path: unevaluated property '$k' is not allowed";
            }
        }
    }

    # Propagate what we evaluated back up to a parent record, so an enclosing
    # unevaluatedProperties (rare here) sees it too.
    if ($parent_evaluated) {
        $parent_evaluated->{$_} = 1 for keys %evaluated;
    }

    return;
}

# Best-effort: given a schema that MATCHED $instance, record into %$evaluated
# every instance key the schema (and its resolved $ref / applicator branches)
# names via `properties`. Used so unevaluatedProperties across anyOf/oneOf/$ref
# is accurate for the SWML schema's shapes.
sub _mark_evaluated ( $self, $instance, $schema, $evaluated ) {
    return unless ref $instance eq 'HASH' && ref $schema eq 'HASH';

    if ( defined $schema->{'$ref'} ) {
        my $t = $self->_resolve_ref( $schema->{'$ref'} );
        $self->_mark_evaluated( $instance, $t, $evaluated ) if ref $t eq 'HASH';
    }
    if ( ref $schema->{properties} eq 'HASH' ) {
        for my $k ( keys %{ $schema->{properties} } ) {
            $evaluated->{$k} = 1 if exists $instance->{$k};
        }
    }
    for my $kw (qw(allOf anyOf oneOf)) {
        next unless ref $schema->{$kw} eq 'ARRAY';
        for my $sub ( @{ $schema->{$kw} } ) {
            next unless ref $sub eq 'HASH';

            # Only credit branches that actually match, so a non-selected oneOf
            # branch's property names don't spuriously mark keys as evaluated.
            $self->_mark_evaluated( $instance, $sub, $evaluated )
                if $self->_matches( $instance, $sub );
        }
    }
    for my $kw (qw(then else)) {
        next unless ref $schema->{$kw} eq 'HASH';
    }
    if ( exists $schema->{if} ) {
        my $branch =
              $self->_matches( $instance, $schema->{if} )
            ? $schema->{then}
            : $schema->{else};
        $self->_mark_evaluated( $instance, $branch, $evaluated ) if ref $branch eq 'HASH';
    }
    return;
}

# ---- type + equality helpers -------------------------------------------------

sub _type_ok ( $instance, $type ) {
    if ( $type eq 'object' )  { return ref $instance eq 'HASH'  ? 1 : 0; }
    if ( $type eq 'array' )   { return ref $instance eq 'ARRAY' ? 1 : 0; }
    if ( $type eq 'null' )    { return !defined $instance       ? 1 : 0; }
    if ( $type eq 'boolean' ) { return _is_boolean($instance)   ? 1 : 0; }
    if ( $type eq 'string' ) {
        return 0 if ref $instance || !defined $instance;
        return 0 if _is_boolean($instance);

        # A value that is purely numeric is an integer/number, not a string,
        # for the purposes of the SWML schema's string-typed fields.
        return _looks_numeric($instance) ? 0 : 1;
    }
    if ( $type eq 'integer' ) {
        return 0 unless _is_number($instance);
        return ( $instance == int($instance) ) ? 1 : 0;
    }
    if ( $type eq 'number' ) {
        return _is_number($instance) ? 1 : 0;
    }
    return 1;    # unknown type keyword: do not reject
}

# Numeric-ness for JSON: a defined, non-ref scalar that looks like a number and
# is NOT a JSON boolean object.
sub _is_number ($v) {
    return 0 if !defined $v || ref $v;
    return 0 if _is_boolean($v);
    return _looks_numeric($v);
}

sub _looks_numeric ($v) {
    return 0 unless defined $v && !ref $v;
    return $v =~ /\A\s*-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?\s*\z/ ? 1 : 0;
}

# JSON::PP::Boolean / JSON::XS boolean detection.
sub _is_boolean ($v) {
    return 0 unless ref $v;
    my $b = Scalar::Util::blessed($v) // '';
    return (   $b eq 'JSON::PP::Boolean'
            || $b eq 'JSON::XS::Boolean'
            || $b eq 'Types::Serialiser::Boolean' )
        ? 1
        : 0;
}

sub _deep_eq ( $a, $b ) {
    return 1 if !defined $a && !defined $b;
    return 0 if !defined $a || !defined $b;
    if ( !ref $a && !ref $b ) {

        # Numeric compare when both look numeric, else string compare.
        if ( _looks_numeric($a) && _looks_numeric($b) ) { return $a == $b ? 1 : 0; }
        return "$a" eq "$b" ? 1 : 0;
    }
    if ( ref $a eq 'ARRAY' && ref $b eq 'ARRAY' ) {
        return 0 unless @$a == @$b;
        for my $i ( 0 .. $#$a ) { return 0 unless _deep_eq( $a->[$i], $b->[$i] ); }
        return 1;
    }
    if ( ref $a eq 'HASH' && ref $b eq 'HASH' ) {
        return 0 unless keys %$a == keys %$b;
        for my $k ( keys %$a ) {
            return 0
                unless exists $b->{$k} && _deep_eq( $a->{$k}, $b->{$k} );
        }
        return 1;
    }
    return 0;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Utils::SchemaValidator - focused JSON Schema evaluator for SWML verbs

=head1 DESCRIPTION

A small JSON Schema (Draft 2020-12 subset) evaluator over the bundled SWML
schema, the Perl analogue of the python reference's jsonschema-rs full
validator. It enforces the closed-object / typed-key semantics that make a
misspelled, unknown, or wrong-typed SWML verb config an ERROR rather than a
silent accept (the Wave-2 P#5 STRICT-RENDER contract). It supports exactly the
keywords the SWML C<schema.json> uses (C<$ref>, C<allOf>/C<anyOf>/C<oneOf>,
C<not>, C<if>/C<then>/C<else>, C<type>, C<const>, C<enum>, C<properties>,
C<required>, C<items>, numeric bounds, and
C<additionalProperties>/C<unevaluatedProperties> closedness).

=head1 METHODS

=over 4

=item C<new(schema =E<gt> $root)>

Construct against a root schema hashref (used to resolve local C<#/$defs/...>
C<$ref>s).

=item C<validate($instance, $subschema)>

Validate C<$instance> against C<$subschema> (default: the root). Returns a list
of error strings; empty means valid.

=item C<is_valid($instance, $subschema)>

Boolean convenience wrapper around C<validate>.

=back

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
