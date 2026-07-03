package SignalWire::Core::Agent::Tools::TypeInference;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# Reflection-based schema inference for SWAIG tool functions.
#
# Perl port of the module-level functions in
# signalwire.core.agent.tools.type_inference
# (signalwire-python/signalwire/signalwire/core/agent/tools/type_inference.py),
# structurally mirroring Ruby's
# SignalWire::Core::Agent::Tools::TypeInference module functions
# (signalwire-ruby/lib/signalwire/core/agent/tools/type_inference.rb).
#
# The reference exposes two module-level functions — infer_schema and
# create_typed_handler_wrapper. This Perl package is a plain function
# namespace (no constructor / no instances), so the two callables are
# ordinary package subs and everything else is a private helper.
#
# Perl coderefs carry no runtime parameter-NAME reflection (unlike Ruby's
# Method#parameters or Python's inspect.signature), so a caller describes
# the callable's parameters explicitly via a `params` arrayref of
# { name => ..., kind => ... } descriptors — the direct analog of Ruby's
# [kind, name] pairs. `kind` is one of:
#   'req'     positional, no default   -> required
#   'opt'     positional, has default  -> optional
#   'keyreq'  keyword,    no default   -> required
#   'key'     keyword,    has default  -> optional
#   'rest'    *args splat
#   'keyrest' **kwargs splat
# A callable with a splat can't be introspected into a fixed schema and
# falls back to old style. Each named parameter becomes a `string`
# property unless refined via `types`.

use strict;
use warnings;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';

# Map a Perl-ish type name to its JSON Schema type name. Perl has no
# distinct scalar classes, so callers pass canonical names ('Integer',
# 'Float', ...) mirroring Ruby's RUBY_TYPE_MAP, or the schema type string
# directly ('integer', 'number', ...).
my %TYPE_MAP = (
    'String'     => 'string',
    'Integer'    => 'integer',
    'Int'        => 'integer',
    'Float'      => 'number',
    'Num'        => 'number',
    'Numeric'    => 'number',
    'Bool'       => 'boolean',
    'Boolean'    => 'boolean',
    'TrueClass'  => 'boolean',
    'FalseClass' => 'boolean',
    'Array'      => 'array',
    'ArrayRef'   => 'array',
    'Hash'       => 'object',
    'HashRef'    => 'object',
);

my %SCHEMA_TYPES  = map { $_ => 1 } values %TYPE_MAP;
my %REQUIRED_KIND = ( req  => 1, keyreq  => 1 );
my %SPLAT_KIND    = ( rest => 1, keyrest => 1 );

# ---------- public (module-level) functions ----------

# Inspect a callable's described signature to infer a JSON Schema for
# SWAIG tool parameters.
#
# Mirrors Python's / Ruby's infer_schema return contract. The `raw_data`
# parameter is treated as the SWAIG raw-payload channel and excluded from
# the schema.
#
#   $func   coderef (retained for parity; not reflected)
#   %opts:
#     params       => arrayref of { name => Str, kind => Str } descriptors
#     types        => hashref  name => (type-name | schema-type string)
#     descriptions => hashref  name => description string
#
# Returns the 5-element list [parameters, required, description,
# is_typed, has_raw_data]:
#   parameters   hashref  name => property hashref (string keys)
#   required     arrayref required parameter names
#   description  always undef (Perl has no docstrings to parse)
#   is_typed     true if the callable takes named parameters (i.e. it is
#                NOT the old-style (args) / (args, raw_data) handler)
#   has_raw_data true if the callable accepts raw_data
sub infer_schema ( $func, %opts ) {
    my $params       = $opts{params}       || [];
    my $types        = $opts{types}        || {};
    my $descriptions = $opts{descriptions} || {};

    my @named = grep { defined $_->{name} && $_->{name} ne '' } @$params;
    my @names = map  { $_->{name} } @named;

    # Old-style handler: (args) or (args, raw_data) with no typing.
    return ( {}, [], undef, 0, 0 ) if _legacy_handler( \@names );

    my $has_raw_data  = ( grep { $_ eq 'raw_data' } @names ) ? 1 : 0;
    my @schema_params = grep { $_->{name} ne 'raw_data' } @named;

    return _build_schema( \@schema_params, $types, $descriptions, $has_raw_data );
}

# Wrap a typed handler so it can be invoked with the standard SWAIG
# calling convention (args, raw_data).
#
# Mirrors Python's / Ruby's create_typed_handler_wrapper. The wrapper
# explodes the args hashref into keyword arguments for the wrapped
# callable, passing raw_data as a keyword only when the handler declared
# it. Returns a coderef with the (args, raw_data) signature.
sub create_typed_handler_wrapper ( $func, $has_raw_data ) {
    return sub {
        my ( $args, $raw_data ) = @_;
        my %kwargs = _symbolize_args($args);
        if ($has_raw_data) {
            return $func->( %kwargs, raw_data => $raw_data );
        }
        return $func->(%kwargs);
    };
}

# ---------- private helpers ----------

# An old-style handler is the positional (args) or (args, raw_data) shape
# with no additional named params.
sub _legacy_handler ($names) {
    return 1 if @$names == 1 && $names->[0] eq 'args';
    return 1 if @$names == 2 && $names->[0] eq 'args' && $names->[1] eq 'raw_data';
    return 0;
}

# A callable with a splat (*args / **kwargs) can't be introspected into a
# fixed schema.
sub _splat_present ($params) {
    return ( grep { $SPLAT_KIND{ $_->{kind} // '' } } @$params ) ? 1 : 0;
}

# Build the (parameters, required, ...) tuple from named params.
sub _build_schema ( $schema_params, $types, $descriptions, $has_raw_data ) {
    return ( {}, [], undef, 0, 0 ) if _splat_present($schema_params);
    return ( {}, [], undef, 1, $has_raw_data ) unless @$schema_params;

    my %parameters;
    my @required;
    for my $p (@$schema_params) {
        my $name = $p->{name};
        $parameters{$name} = _property_for( $name, $types, $descriptions );
        push @required, $name if _required_kind( $p->{kind} );
    }
    return ( \%parameters, \@required, undef, 1, $has_raw_data );
}

# Build one JSON-Schema property hashref for a parameter.
sub _property_for ( $name, $types, $descriptions ) {
    my $prop = { type => _schema_type( $types->{$name} ) };
    my $desc = $descriptions->{$name};
    $prop->{description} = $desc if defined $desc && length $desc;
    return $prop;
}

# Resolve a type override (type name or schema-type string) to a JSON
# Schema type name; default to "string" when unknown/absent.
sub _schema_type ($override) {
    return 'string' unless defined $override;
    return $override if $SCHEMA_TYPES{$override};
    return $TYPE_MAP{$override} // 'string';
}

# Required kinds: req (positional, no default) and keyreq (keyword, no
# default). opt / key have defaults -> optional.
sub _required_kind ($kind) {
    return $REQUIRED_KIND{ $kind // '' } ? 1 : 0;
}

# Convert an args hashref into keyword arguments for the wrapped handler.
sub _symbolize_args ($args) {
    return () unless ref $args eq 'HASH';
    return %$args;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Core::Agent::Tools::TypeInference - schema inference for SWAIG tool functions

=head1 SYNOPSIS

    use SignalWire::Core::Agent::Tools::TypeInference;

    my ($params, $required, $desc, $is_typed, $has_raw) =
        SignalWire::Core::Agent::Tools::TypeInference::infer_schema(
            $handler,
            params => [
                { name => 'city',  kind => 'keyreq' },
                { name => 'units', kind => 'key' },
            ],
            types  => { units => 'string' },
        );
    # $params   = { city => { type => 'string' }, units => { type => 'string' } }
    # $required = ['city']; $is_typed = 1

    my $wrapped = SignalWire::Core::Agent::Tools::TypeInference::create_typed_handler_wrapper(
        $handler, $has_raw,
    );
    $wrapped->({ city => 'Reno' }, $raw_data);

=head1 DESCRIPTION

L<SignalWire::Core::Agent::Tools::TypeInference> ports the two
module-level functions of
C<signalwire.core.agent.tools.type_inference> — C<infer_schema> and
C<create_typed_handler_wrapper>. It is a plain function namespace with no
constructor and no instances.

Perl coderefs carry no runtime parameter-name reflection, so a caller
describes the callable's parameters explicitly through a C<params>
arrayref of C<{ name =E<gt> ..., kind =E<gt> ... }> descriptors — the
direct analog of Ruby's C<[kind, name]> pairs. C<kind> is one of C<req>,
C<opt>, C<keyreq>, C<key> (required iff C<req>/C<keyreq>), or C<rest> /
C<keyrest> (a splat, which forces the old-style fallback).

=head2 Functions

=over 4

=item * C<infer_schema($func, %opts)> — returns the 5-element list
C<(parameters, required, description, is_typed, has_raw_data)>. The
C<raw_data> parameter is excluded from the schema and flagged in
C<has_raw_data>. C<description> is always C<undef>.

=item * C<create_typed_handler_wrapper($func, $has_raw_data)> — returns a
coderef with the C<(args, raw_data)> convention that explodes the C<args>
hashref into keyword arguments for C<$func>, passing C<raw_data> as a
keyword only when C<$has_raw_data> is true.

=back

=head1 SEE ALSO

L<SignalWire::Core::Agent::Tools::Registry>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
