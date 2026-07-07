package SignalWire::SWAIG::SWAIGFunction;
use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
no warnings 'experimental::signatures';

use Scalar::Util ();
use SignalWire::SWAIG::FunctionResult;
use SignalWire::Logging;

# SWAIGFunction — Perl port of the Python reference
# signalwire.core.swaig_function.SWAIGFunction (and the Ruby
# SignalWire::Swaig::SWAIGFunction). A SWAIGFunction is exactly the same
# concept as a "tool" in native OpenAI / Anthropic tool calling: it holds a
# name/description/parameters/handler and renders into the tool schema sent to
# the model.

# JSON-Schema type -> predicate, used by the built-in validator fallback.
my %JSON_TYPE_CHECKS = (
    'string'  => sub { defined $_[0] && !ref $_[0] },
    'integer' => sub { defined $_[0] && !ref $_[0] && $_[0] =~ /\A-?[0-9]+\z/ },
    'number'  =>
        sub { defined $_[0] && !ref $_[0] && $_[0] =~ /\A-?(?:[0-9]+\.?[0-9]*|\.[0-9]+)\z/ },
    'boolean' =>
        sub { my $v = $_[0]; !ref $v && ( !defined $v || $v eq '' || $v eq '0' || $v eq '1' ) },
    'array'  => sub { ref $_[0] eq 'ARRAY' },
    'object' => sub { ref $_[0] eq 'HASH' },
);

# Generic, non-leaking message returned when a handler dies.
my $EXECUTE_ERROR_RESPONSE =
"Sorry, I couldn't complete that action. Please try again or contact support if the issue persists.";

# Function name (the `name` field in the tool schema).
has 'name' => ( is => 'ro', required => 1 );

# Callable invoked when the model calls this tool (a coderef).
has 'handler' => ( is => 'ro', required => 1 );

# LLM-facing description.
has 'description' => ( is => 'ro', required => 1 );

# JSON Schema for the arguments (hashref).
has 'parameters' => ( is => 'ro', default => sub { {} } );

# Whether this function requires SWAIG token validation.
has 'secure' => ( is => 'ro', default => sub { 0 } );

# Filler phrases by language code (deprecated).
has 'fillers' => ( is => 'ro', default => sub { undef } );

# Audio file URL to play while executing.
has 'wait_file' => ( is => 'ro', default => sub { undef } );

# Number of times to loop wait_file.
has 'wait_file_loops' => ( is => 'ro', default => sub { undef } );

# External webhook URL instead of local handling.
has 'webhook_url' => ( is => 'ro', default => sub { undef } );

# Required parameter names (arrayref).
has 'required' => ( is => 'ro', default => sub { [] } );

# Whether the handler uses type-hinted parameters.
has 'is_typed_handler' => ( is => 'ro', default => sub { 0 } );

# Additional SWAIG-only fields (meta_data_token, web_hook_auth_*, etc.).
has 'extra_swaig_fields' => ( is => 'ro', default => sub { {} } );

# Whether this function is external (a webhook_url was provided).
has 'is_external' => ( is => 'lazy' );

sub _build_is_external ($self) {
    return defined $self->webhook_url ? 1 : 0;
}

# Normalise constructor kwargs so `parameters`/`required` default to the SWML
# shape and any unrecognised keyword becomes an extra SWAIG field (Python
# **extra_swaig_fields / Ruby **extra_swaig_fields parity).
around BUILDARGS => sub ( $orig, $class, @args ) {
    my %opts = ( @args == 1 && ref $args[0] eq 'HASH' ) ? %{ $args[0] } : @args;

    my %known = map { $_ => 1 } qw(
        name handler description parameters secure fillers wait_file
        wait_file_loops webhook_url required is_typed_handler extra_swaig_fields
    );

    my %extra = %{ delete $opts{extra_swaig_fields} // {} };
    for my $k ( keys %opts ) {
        next if $known{$k};
        $extra{$k} = delete $opts{$k};
    }
    $opts{extra_swaig_fields} = \%extra;
    $opts{parameters} //= {};
    $opts{required}   //= [];

    return $class->$orig(%opts);
};

# Call the underlying handler function.
#
# Perl analog of the Python reference's __call__ (makes the object callable).
# Mirrors Ruby's `call` (aliased to __call__ in the surface). Invokes the
# handler with whatever positional args are passed through.
sub call ( $self, @args ) {
    return $self->handler->(@args);
}

# Execute the function with the given arguments.
#
# Everything ends up as a FunctionResult hashref. On any error a generic
# error message is returned (details are logged, not exposed to the AI).
sub execute ( $self, $args, $raw_data = undef ) {
    my $result = eval { $self->handler->( $args, $raw_data // {} ); };
    if ($@) {
        SignalWire::Logging->get_logger( "SWAIG::" . $self->name )
            ->error( "Error executing SWAIG function " . $self->name . ": $@" );
        return SignalWire::SWAIG::FunctionResult->new($EXECUTE_ERROR_RESPONSE)->to_hash;
    }
    return $self->_coerce_result($result);
}

# Validate the arguments against the parameter schema.
#
# Uses the built-in lightweight check of the `required` list and each declared
# property's `type` (Python parity: when no JSON-Schema validator is
# installed, validation is skipped/lightweight). Returns ($valid, $errors).
sub validate_args ( $self, $args ) {
    my $ok = eval {
        my $schema = $self->_ensure_parameter_structure;
        return [ 1, [] ]
            if !defined $schema
            || ref $schema->{properties} ne 'HASH'
            || !%{ $schema->{properties} };
        return $self->_validate_args_builtin( $schema, $args );
    };
    if ($@) {
        SignalWire::Logging->get_logger( "SWAIG::" . $self->name )
            ->debug( "schema validation error for " . $self->name . ": $@" );
        return ( 1, [] );
    }
    return @$ok;
}

# Convert this function to a SWAIG-compatible hashref for SWML.
#
# All functions use a single /swaig endpoint. include_auth is accepted for
# signature parity but does not change the emitted URL (mirrors the reference).
sub to_swaig ( $self, %opts ) {
    my $base_url = $opts{base_url} // die("to_swaig requires 'base_url'");
    my $token    = $opts{token};
    my $call_id  = $opts{call_id};

    my $url = "$base_url/swaig";
    $url = "$url?token=$token&call_id=$call_id" if defined $token && defined $call_id;

    my $function_def = {
        function    => $self->name,
        description => $self->description,
        parameters  => $self->_ensure_parameter_structure,
    };
    $function_def->{web_hook_url} = $url if defined $url && length $url;
    $function_def->{fillers}      = $self->fillers
        if ref $self->fillers eq 'HASH' && %{ $self->fillers };

    %$function_def = ( %$function_def, %{ $self->extra_swaig_fields } );
    return $function_def;
}

# ------------------------------------------------------------------
# Private helpers
# ------------------------------------------------------------------

# Coerce a handler return value into a FunctionResult hashref (Python parity).
sub _coerce_result ( $self, $result ) {
    if ( Scalar::Util::blessed($result) && $result->isa('SignalWire::SWAIG::FunctionResult') ) {
        return $result->to_hash;
    }
    if ( ref $result eq 'HASH' && exists $result->{response} ) {
        return $result;
    }
    if ( ref $result eq 'HASH' ) {
        return SignalWire::SWAIG::FunctionResult->new('Function completed successfully')->to_hash;
    }
    return SignalWire::SWAIG::FunctionResult->new( defined $result ? "$result" : '' )->to_hash;
}

# Minimal built-in argument validation: enforce the schema's `required` list
# and each declared property's JSON `type`. Returns [ $valid, \@errors ].
sub _validate_args_builtin ( $self, $schema, $args ) {
    $args = {} unless ref $args eq 'HASH';
    my @errors = @{ _missing_required_errors( $schema, $args ) };
    push @errors, @{ _type_mismatch_errors( $schema, $args ) };
    return [ ( @errors ? 0 : 1 ), \@errors ];
}

sub _missing_required_errors ( $schema, $args ) {
    my $required = ref $schema->{required} eq 'ARRAY' ? $schema->{required} : [];
    return [
        map  { "missing required property '$_'" }
        grep { !exists $args->{$_} } @$required
    ];
}

sub _type_mismatch_errors ( $schema, $args ) {
    my $props = ref $schema->{properties} eq 'HASH' ? $schema->{properties} : {};
    my @errors;
    for my $name ( keys %$props ) {
        my $prop = $props->{$name};
        next unless ref $prop eq 'HASH' && exists $args->{$name};
        my $checker = $JSON_TYPE_CHECKS{ $prop->{type} // '' };
        push @errors, "property '$name' must be of type " . $prop->{type}
            if $checker && !$checker->( $args->{$name} );
    }
    return \@errors;
}

# Ensure the parameters are correctly structured for SWML — wrap loose
# property maps in the {type, properties[, required]} envelope.
sub _ensure_parameter_structure ($self) {
    my $params = $self->parameters;
    return { type => 'object', properties => {} }
        if !defined $params || ref $params ne 'HASH' || !%$params;

    return $params if exists $params->{type} && exists $params->{properties};

    my $result = { type => 'object', properties => $params };
    $result->{required} = $self->required if @{ $self->required };
    return $result;
}

1;

__END__

=head1 NAME

SignalWire::SWAIG::SWAIGFunction - a SWAIG function (a tool the AI model can call)

=head1 SYNOPSIS

    use SignalWire::SWAIG::SWAIGFunction;

    my $fn = SignalWire::SWAIG::SWAIGFunction->new(
        name        => 'get_weather',
        description => 'Get current weather',
        handler     => sub { my ($args, $raw) = @_; ... },
        parameters  => { city => { type => 'string' } },
        required    => ['city'],
    );

    my ($valid, $errors) = $fn->validate_args({ city => 'Reno' });
    my $result = $fn->execute({ city => 'Reno' });
    my $swaig  = $fn->to_swaig( base_url => 'https://example.com' );

    # The object is also callable via ->call (Python __call__ / Ruby call).
    my $raw = $fn->call({ city => 'Reno' }, {});

=head1 DESCRIPTION

Perl port of the Python reference
C<signalwire.core.swaig_function.SWAIGFunction> (and the Ruby
C<SignalWire::Swaig::SWAIGFunction>). A SWAIGFunction wraps a handler as an
OpenAI-style tool: it holds the C<name>, C<description>, JSON-Schema
C<parameters>, and metadata, and renders into the SWAIG entry embedded in an
SWML C<ai> verb.

=head1 CONSTRUCTOR

=head2 new(%opts)

C<name>, C<handler>, and C<description> are required. C<parameters>,
C<secure>, C<fillers>, C<wait_file>, C<wait_file_loops>, C<webhook_url>,
C<required>, and C<is_typed_handler> are optional. Any additional keyword is
collected into C<extra_swaig_fields> and merged into the C<to_swaig> output.

=head1 METHODS

=over 4

=item * C<call(@args)> - invoke the underlying handler (Perl analog of Python's
C<__call__>).

=item * C<execute($args, $raw_data)> - run the handler and coerce the result to
a FunctionResult hashref; returns a generic error hashref on failure.

=item * C<validate_args($args)> - lightweight required/type validation; returns
C<($valid, $errors_arrayref)>.

=item * C<to_swaig(base_url =E<gt> ..., token =E<gt> ..., call_id =E<gt> ...)> -
build the SWAIG entry hashref for SWML.

=item * C<is_external> - true when a C<webhook_url> was provided.

=back

=head1 SEE ALSO

L<SignalWire::SWAIG::FunctionResult>

=cut
