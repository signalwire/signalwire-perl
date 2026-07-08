package SignalWire::Core::Agent::Tools::Registry;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# Tool registration and management.
#
# Perl port of signalwire.core.agent.tools.registry.ToolRegistry
# (signalwire-python/signalwire/signalwire/core/agent/tools/registry.py),
# structurally mirroring Ruby's
# SignalWire::Core::Agent::Tools::Registry
# (signalwire-ruby/lib/signalwire/core/agent/tools/registry.rb).
#
# A registry holds SWAIG function definitions keyed by name. Two kinds of
# entries are supported:
#
#   * definitions created via define_tool (carry a `handler`), and
#   * raw SWAIG function dictionaries via register_swaig_function (e.g.
#     from a DataMap's to_swaig_function) which execute on SignalWire's
#     server and carry no handler.
#
# Perl (like Ruby) has no dedicated SWAIGFunction value object — AgentBase
# stores plain hashrefs on the wire — so the registry stores the built
# definition hashref with string keys, matching the wire shape.

use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
use Carp qw(croak);

# ---------- attributes ----------

# Optional parent AgentBase back-reference, kept for parity with the
# Python/Ruby registries; may be undef for standalone use.
has agent => (
    is      => 'ro',
    default => sub { undef },
);

# name => definition hashref (string keys).
has _swaig_functions => (
    is      => 'rw',
    default => sub { {} },
);

# ---------- public methods ----------

# Define a SWAIG function that the AI can call.
#
# Python parity: define_tool(name, description, parameters, handler,
# secure=True, fillers=None, wait_file=None, wait_file_loops=None,
# webhook_url=None, required=None, is_typed_handler=False,
# **swaig_fields). Dies if the tool name already exists. Returns the
# stored definition hashref.
sub define_tool ( $self, %opts ) {
    my $name = $opts{name};
    croak "Tool with name '$name' already exists"
        if exists $self->_swaig_functions->{$name};

    my $definition = $self->_build_definition(
        $name,
        $opts{description},
        $opts{parameters} || {},
        $opts{required},
        handler          => $opts{handler},
        secure           => exists $opts{secure} ? $opts{secure} : 1,
        fillers          => $opts{fillers},
        wait_file        => $opts{wait_file},
        wait_file_loops  => $opts{wait_file_loops},
        webhook_url      => $opts{webhook_url},
        is_typed_handler => $opts{is_typed_handler} ? 1 : 0,
        swaig_fields     => $opts{swaig_fields},
    );
    $self->_swaig_functions->{$name} = $definition;
    return $definition;
}

# Register a raw SWAIG function dictionary (e.g. from a DataMap's
# to_swaig_function).
#
# Python parity: register_swaig_function(function_dict) — requires a
# `function` field and rejects duplicates. Returns the stored definition.
sub register_swaig_function ( $self, $function_dict ) {
    croak 'Function dictionary must contain \'function\' field with the function name'
        unless ref $function_dict eq 'HASH';
    my $fname = $function_dict->{function};
    croak 'Function dictionary must contain \'function\' field with the function name'
        unless defined $fname && length $fname;
    croak "Tool with name '$fname' already exists"
        if exists $self->_swaig_functions->{$fname};

    $self->_swaig_functions->{$fname} = {%$function_dict};
    return $self->_swaig_functions->{$fname};
}

# Get a registered function by name. Returns the definition hashref, or
# undef if not found.
sub get_function ( $self, $name ) {
    return $self->_swaig_functions->{$name};
}

# Get a copy of all registered functions (name => definition hashref).
sub get_all_functions ($self) {
    return { %{ $self->_swaig_functions } };
}

# Check whether a function is registered. Returns 1/0.
sub has_function ( $self, $name ) {
    return exists $self->_swaig_functions->{$name} ? 1 : 0;
}

# Remove a registered function. Returns 1 if removed, 0 if not found.
sub remove_function ( $self, $name ) {
    return 0 unless exists $self->_swaig_functions->{$name};
    delete $self->_swaig_functions->{$name};
    return 1;
}

# ---------- private helpers ----------

# Build the wire-shape definition hashref for a defined tool. Optional
# fields are only emitted when present so the wire matches AgentBase's own
# tool serialisation.
sub _build_definition ( $self, $name, $description, $parameters, $required, %opts ) {
    my $definition = {
        'function'    => $name,
        'description' => $description,
        'parameters'  => $self->_normalise_parameters( $parameters, $required ),
    };
    $self->_apply_optional_fields( $definition, \%opts );
    $self->_merge_swaig_fields( $definition, $opts{swaig_fields} );
    $definition->{handler} = $opts{handler} if defined $opts{handler};
    $definition->{secure}  = $opts{secure};
    return $definition;
}

sub _apply_optional_fields ( $self, $definition, $opts ) {
    if ( ref $opts->{fillers} eq 'HASH' && %{ $opts->{fillers} } ) {
        $definition->{fillers} = $opts->{fillers};
    }
    for my $key (qw(wait_file wait_file_loops webhook_url)) {
        $definition->{$key} = $opts->{$key} if $opts->{$key};
    }
    $definition->{is_typed_handler} = JSON::PP::true() if $opts->{is_typed_handler};
    return;
}

sub _merge_swaig_fields ( $self, $definition, $swaig_fields ) {
    return unless ref $swaig_fields eq 'HASH';
    for my $k ( keys %$swaig_fields ) {
        $definition->{$k} = $swaig_fields->{$k};
    }
    return;
}

# Wrap bare properties in an object schema and inject `required`.
sub _normalise_parameters ( $self, $parameters, $required ) {
    my $schema = $self->_object_schema($parameters);
    return $schema unless ref $required eq 'ARRAY' && @$required;

    my $existing = $schema->{required} || [];
    my %seen;
    my @merged = grep { !$seen{$_}++ } ( @$existing, @$required );
    return { %$schema, required => \@merged };
}

sub _object_schema ( $self, $parameters ) {
    return $parameters
        if ref $parameters eq 'HASH'
        && defined $parameters->{type}
        && $parameters->{type} eq 'object';

    return { type => 'object', properties => $parameters || {} };
}

# JSON::PP is loaded lazily so is_typed_handler emits a proper JSON bool.
require JSON::PP;

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Core::Agent::Tools::Registry - SWAIG function registration and management

=head1 SYNOPSIS

    use SignalWire::Core::Agent::Tools::Registry;

    my $reg = SignalWire::Core::Agent::Tools::Registry->new;

    $reg->define_tool(
        name        => 'get_weather',
        description => 'Get current weather',
        parameters  => { city => { type => 'string' } },
        required    => ['city'],
        handler     => sub { my ($args, $raw) = @_; ... },
    );

    $reg->has_function('get_weather');   # 1
    my $def = $reg->get_function('get_weather');
    $reg->remove_function('get_weather');

=head1 DESCRIPTION

L<SignalWire::Core::Agent::Tools::Registry> is the Perl port of
C<signalwire.core.agent.tools.registry.ToolRegistry>. It holds SWAIG
function definitions keyed by name, supporting both handler-carrying
definitions built by C<define_tool> and raw SWAIG dictionaries registered
via C<register_swaig_function> (e.g. from a DataMap).

Definitions are stored as plain hashrefs with string keys, matching the
wire shape AgentBase serialises. Optional fields (C<fillers>,
C<wait_file>, C<wait_file_loops>, C<webhook_url>, C<is_typed_handler>) are
only emitted when present.

=head2 Methods

=over 4

=item * C<define_tool(%opts)> — build and store a definition (dies on a
duplicate name); returns the definition hashref.

=item * C<register_swaig_function($hashref)> — store a raw SWAIG dictionary
(requires a C<function> field; dies on a duplicate).

=item * C<get_function($name)> — the definition hashref, or C<undef>.

=item * C<get_all_functions> — a shallow copy of the name → definition map.

=item * C<has_function($name)> — 1/0.

=item * C<remove_function($name)> — 1 if removed, 0 if absent.

=back

=head1 SEE ALSO

L<SignalWire::Agent::AgentBase>, L<SignalWire::DataMap>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
