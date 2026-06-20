package SignalWire::Skills::Builtin::Math;
use strict;
use warnings;
use Moo;
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill( 'math', __PACKAGE__ );

has '+skill_name'        => ( default => sub { 'math' } );
has '+skill_description' => ( default => sub { 'Perform basic mathematical calculations' } );
has '+supports_multiple_instances' => ( default => sub { 0 } );

sub setup { 1 }

sub register_tools {
    my ($self) = @_;

    $self->define_tool(
        name        => 'calculate',
        description =>
            'Perform a mathematical calculation with basic operations (+, -, *, /, %, **)',
        parameters => {
            type       => 'object',
            properties => {
                expression =>
                    { type => 'string', description => 'Mathematical expression to evaluate' },
            },

            # No `required`: the Python reference (skills/math/skill.py) passes
            # none, and the handler guards an empty/invalid expression. Adding it
            # would over-constrain the SWAIG schema vs the reference contract.
        },
        handler => sub {
            my ( $args, $raw ) = @_;
            require SignalWire::SWAIG::FunctionResult;
            my $expr = $args->{expression} // '';

            my $result = eval { _safe_eval($expr) };
            if ( defined $result && !$@ ) {
                return SignalWire::SWAIG::FunctionResult->new(
                    response => "The result of $args->{expression} is $result" );
            }
            return SignalWire::SWAIG::FunctionResult->new(
                response => "Could not evaluate expression: $args->{expression}" );
        },
    );
}

# Safe arithmetic evaluator — the Perl analog of the Python reference's
# ast-based _safe_eval (signalwire/skills/math/skill.py). It replaces the old
# stringy `eval $expr` (perlcritic ProhibitStringyEval / ProhibitNoStrict) with
# a small recursive-descent parser over a fixed grammar so NO user input ever
# reaches the Perl compiler. Supported: integer/decimal literals, unary +/-,
# the binary operators + - * / % and ** / ^ (exponentiation), and parentheses —
# exactly the operator set the tool description and prompt advertise. Any
# unexpected character or malformed expression dies, which the handler's eval
# turns into the "Could not evaluate" response (matching the old behavior).
sub _safe_eval {
    my ($expr) = @_;

    # Tokenize: numbers, the operators (treating ^ as **), and parens. Anything
    # else is rejected, preserving the old char-class whitelist.
    my @tokens;
    while ( length $expr ) {
        if ( $expr =~ s/^\s+// ) {
            next;
        }
        if ( $expr =~ s/^(\d+(?:\.\d+)?|\.\d+)// ) {
            push @tokens, [ num => $1 ];
        } elsif ( $expr =~ s/^(\*\*|\^)// ) {
            push @tokens, [ op => '**' ];
        } elsif ( $expr =~ s{^([-+*/%()])}{} ) {
            push @tokens, [ op => $1 ];
        } else {
            die "math: unexpected token near '$expr'\n";
        }
    }
    die "math: empty expression\n" unless @tokens;

    my $pos = 0;

    # expr := term (('+'|'-') term)*
    my ( $parse_expr, $parse_term, $parse_power, $parse_unary, $parse_atom );

    my $peek = sub { $pos < @tokens ? $tokens[$pos] : undef };
    my $eat  = sub {
        my ($op) = @_;
        my $t = $tokens[$pos];
        die "math: expected '$op'\n"
            unless $t && $t->[0] eq 'op' && $t->[1] eq $op;
        $pos++;
        return;
    };

    $parse_atom = sub {
        my $t = $peek->();
        die "math: unexpected end of expression\n" unless $t;
        if ( $t->[0] eq 'num' ) {
            $pos++;
            return 0 + $t->[1];
        }
        if ( $t->[0] eq 'op' && $t->[1] eq '(' ) {
            $eat->('(');
            my $v = $parse_expr->();
            $eat->(')');
            return $v;
        }
        die "math: unexpected token\n";
    };

    # unary := ('+'|'-') unary | atom
    $parse_unary = sub {
        my $t = $peek->();
        if ( $t && $t->[0] eq 'op' && ( $t->[1] eq '+' || $t->[1] eq '-' ) ) {
            my $op = $t->[1];
            $pos++;
            my $v = $parse_unary->();
            return $op eq '-' ? -$v : $v;
        }
        return $parse_atom->();
    };

    # power := unary ('**' power)?   (right-associative, like Perl/Python)
    $parse_power = sub {
        my $base = $parse_unary->();
        my $t    = $peek->();
        if ( $t && $t->[0] eq 'op' && $t->[1] eq '**' ) {
            $pos++;
            my $exp = $parse_power->();
            die "math: exponent too large\n" if $exp > 1000;
            return $base**$exp;
        }
        return $base;
    };

    # term := power (('*'|'/'|'%') power)*
    $parse_term = sub {
        my $v = $parse_power->();
        while ( my $t = $peek->() ) {
            last unless $t->[0] eq 'op' && $t->[1] =~ /^[*\/%]$/;
            my $op = $t->[1];
            $pos++;
            my $rhs = $parse_power->();
            if    ( $op eq '*' ) { $v *= $rhs }
            elsif ( $op eq '/' ) { $v /= $rhs }
            else                 { $v %= $rhs }
        }
        return $v;
    };

    $parse_expr = sub {
        my $v = $parse_term->();
        while ( my $t = $peek->() ) {
            last unless $t->[0] eq 'op' && ( $t->[1] eq '+' || $t->[1] eq '-' );
            my $op = $t->[1];
            $pos++;
            my $rhs = $parse_term->();
            if   ( $op eq '+' ) { $v += $rhs }
            else                { $v -= $rhs }
        }
        return $v;
    };

    my $result = $parse_expr->();
    die "math: trailing tokens\n" if $pos != @tokens;
    return $result;
}

sub _get_prompt_sections {
    return [
        {
            title   => 'Mathematical Calculations',
            body    => '',
            bullets => [
                'Use the calculate tool for math operations',
                'Supports +, -, *, /, %, and ** (exponentiation)',
            ],
        }
    ];
}

sub get_parameter_schema {
    return { %{ SignalWire::Skills::SkillBase->get_parameter_schema }, };
}

1;
