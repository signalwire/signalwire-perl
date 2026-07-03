## no critic (Modules::RequireFilenameMatchesPackage)
# This file hosts two packages (SchemaValidationError + SchemaUtils); the
# file is named for the primary SchemaUtils class, matching the Python
# reference's schema_utils module which declares both.
package SignalWire::Utils::SchemaValidationError;
use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
no warnings 'experimental::signatures';

# SchemaValidationError — Perl port of
# signalwire.utils.schema_utils.SchemaValidationError (and the Ruby
# SignalWire::Utils::SchemaValidationError). Raised when SWML schema
# validation of a verb config fails. Stringifies to the same message the
# Python/Ruby exceptions build so callers that print $@ see identical text.

use overload
    '""'     => sub { $_[0]->message },
    'bool'   => sub { 1 },
    fallback => 1;

has 'verb_name' => ( is => 'ro' );
has 'errors'    => ( is => 'ro', default => sub { [] } );
has 'message'   => ( is => 'lazy' );

sub _build_message ($self) {
    my $errs = join( '; ', @{ $self->errors // [] } );
    return "Schema validation failed for '" . ( $self->verb_name // '' ) . "': $errs";
}

package SignalWire::Utils::SchemaUtils;
use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
no warnings 'experimental::signatures';

use JSON           ();
use File::Basename ();
use File::Spec     ();

# SchemaUtils — Perl port of signalwire.utils.schema_utils.SchemaUtils
# (mirrors the Ruby SignalWire::Utils::SchemaUtils). Loads the SWML JSON
# Schema, extracts verb metadata, validates either a single verb config or a
# complete SWML document, and generates Python-style method signatures/bodies
# for codegen tooling.
#
# Construction rules mirror Python/Ruby:
#   - schema_path => undef uses the bundled schema.json.
#   - schema_validation => 0 disables validation (validate_verb returns
#     (1, []) for every call).
#   - SWML_SKIP_SCHEMA_VALIDATION=1/true/yes also disables validation
#     regardless of the constructor argument.
#
# The Perl port ships the lightweight validator (verb existence +
# required-property check). Full JSON Schema validation can be wired in via a
# JSON-Schema validator by extending _init_full_validator; the lightweight
# contract matches Python's _validate_verb_lightweight() exactly.

# JSON-schema scalar type -> Python type-annotation string (codegen parity).
my %PYTHON_SCALAR_TYPES = (
    'string'  => 'str',
    'integer' => 'int',
    'number'  => 'float',
    'boolean' => 'bool',
    'object'  => 'Dict[str, Any]',
);

# Path to a schema.json file; undef selects the bundled copy at
# lib/SignalWire/SWML/schema.json (Python parity: schema_path).
has 'schema_path' => ( is => 'ro', default => sub { undef } );

# Enable/disable schema validation (Python parity: schema_validation).
has 'schema_validation' => ( is => 'ro', default => sub { 1 } );

# Parsed JSON Schema document (Python parity: schema).
has 'schema' => ( is => 'lazy' );

# Verb-name -> {name, schema_name, definition} map (Python parity: verbs).
has 'verbs' => ( is => 'lazy' );

has '_validation_enabled' => ( is => 'lazy' );
has '_full_validator'     => ( is => 'rw', default => sub { undef } );

sub BUILD ( $self, $args ) {

    # Force lazy attrs so behaviour (schema load, verb extract, validator
    # init) happens at construction time, matching Python/Ruby __init__.
    $self->schema;
    $self->verbs;
    if ( $self->_validation_enabled && %{ $self->schema } ) {
        $self->_init_full_validator;
    }
    return;
}

sub _build__validation_enabled ($self) {
    my $env_skip = _env_boolish( $ENV{SWML_SKIP_SCHEMA_VALIDATION} // '' );
    return ( $self->schema_validation && !$env_skip ) ? 1 : 0;
}

sub _build_schema ($self) {
    return $self->load_schema;
}

sub _build_verbs ($self) {
    return $self->_extract_verb_definitions;
}

# Whether full JSON Schema validation is wired up.
# Mirrors Python's full_validation_available property / Ruby's
# full_validation_available?. Recorded as method `full_validation_available`.
sub full_validation_available ($self) {
    return defined $self->_full_validator ? 1 : 0;
}

# Read and parse the JSON Schema. Mirrors Python/Ruby load_schema.
# Returns an empty hashref when the path is missing or unparseable.
sub load_schema ($self) {
    my $path = $self->schema_path // _default_schema_path();
    return {} if !defined $path || !-e $path;

    # Read raw UTF-8 bytes (no :encoding layer): JSON::decode_json expects a
    # byte string and decodes UTF-8 itself. Reading through an :encoding layer
    # would yield decoded characters and trigger a "Wide character" error.
    my $raw = eval {
        open my $fh, '<:raw', $path or die "open: $!";
        local $/;
        my $text = <$fh>;
        close $fh;
        $text;
    };
    return {} unless defined $raw;

    my $data = eval { JSON::decode_json($raw) };
    return {} unless defined $data && ref $data eq 'HASH';
    return $data;
}

# Sorted list of all known verb names. Mirrors Python get_all_verb_names
# (Python preserves insertion order; Ruby sorts — Perl mirrors Ruby's sort
# for deterministic output). Returns a list.
sub get_all_verb_names ($self) {
    my @names = sort keys %{ $self->verbs };
    return @names;
}

# The properties[verb_name] block for a verb, or {} when unknown.
# Mirrors Python/Ruby get_verb_properties.
sub get_verb_properties ( $self, $verb_name ) {
    my $v = $self->verbs->{$verb_name};
    return {} unless defined $v;

    my $outer = _verb_definition_properties($v);
    return {} unless ref $outer eq 'HASH';

    my $inner = $outer->{$verb_name};
    return ref $inner eq 'HASH' ? $inner : {};
}

# The required list for a verb, or [] when unknown / none.
# Mirrors Python/Ruby get_verb_required_properties. Returns an arrayref.
sub get_verb_required_properties ( $self, $verb_name ) {
    my $inner = $self->get_verb_properties($verb_name);
    my $req   = $inner->{required};
    return [] unless ref $req eq 'ARRAY';

    return [ grep { defined $_ && !ref $_ } @$req ];
}

# Parameter-definition block used by code-gen tooling.
# Mirrors Python/Ruby get_verb_parameters. Returns a hashref.
sub get_verb_parameters ( $self, $verb_name ) {
    my $inner = $self->get_verb_properties($verb_name);
    my $props = $inner->{properties};
    return ref $props eq 'HASH' ? $props : {};
}

# Validate a verb config against the schema.
# Mirrors Python/Ruby validate_verb. Returns ($valid, $errors_arrayref).
sub validate_verb ( $self, $verb_name, $verb_config ) {
    return ( 1, [] ) unless $self->_validation_enabled;

    return ( 0, ["Unknown verb: $verb_name"] ) unless exists $self->verbs->{$verb_name};

    if ( $self->_full_validator ) {
        return $self->_validate_verb_full( $verb_name, $verb_config );
    }
    return $self->_validate_verb_lightweight( $verb_name, $verb_config );
}

# Validate a complete SWML document.
# Mirrors Python/Ruby validate_document. Returns
# (0, ['Schema validator not initialized']) when no full validator is wired
# in. Returns ($valid, $errors_arrayref).
sub validate_document ( $self, $document ) {
    return ( 0, ['Schema validator not initialized'] ) unless defined $self->_full_validator;

    # Reserved for full-validator wiring.
    return ( 1, [] );
}

# Generate a Python-style method signature string for a verb.
# Mirrors Python/Ruby generate_method_signature.
sub generate_method_signature ( $self, $verb_name ) {
    my $params = $self->get_verb_parameters($verb_name);
    my @keys   = sort keys %$params;
    my @parts  = $self->_signature_param_parts( $verb_name, $params, \@keys );
    my $doc    = $self->_signature_docstring( $verb_name, $params, \@keys );
    return "def $verb_name(" . join( ', ', @parts ) . ") -> bool:\n$doc";
}

# Generate a Python-style method body string for a verb.
# Mirrors Python/Ruby generate_method_body.
sub generate_method_body ( $self, $verb_name ) {
    my @keys = sort keys %{ $self->get_verb_parameters($verb_name) };
    my @config_lines;
    for my $name (@keys) {
        push @config_lines, "        if $name is not None:", "            config['$name'] = $name";
    }
    return join( "\n",
        '        # Prepare the configuration',
        '        config = {}',
        @config_lines, $self->_method_body_kwargs_lines($verb_name),
    );
}

# ------------------------------------------------------------------
# Private helpers
# ------------------------------------------------------------------

sub _method_body_kwargs_lines ( $self, $verb_name ) {
    return (
        '        # Add any additional parameters from kwargs',
        '        for key, value in kwargs.items():',
        '            if value is not None:',
        '                config[key] = value',
        '',
        "        # Add the $verb_name verb",
        "        return self.add_verb('$verb_name', config)",
    );
}

sub _signature_param_parts ( $self, $verb_name, $params, $keys ) {
    my %required = map { $_ => 1 } @{ $self->get_verb_required_properties($verb_name) };
    my @param_parts =
        map { _format_signature_param( $_, $params->{$_}, \%required ) } @$keys;
    return ( 'self', @param_parts, '**kwargs' );
}

sub _format_signature_param ( $name, $defn, $required ) {
    my $t = _python_type_annotation($defn);
    return "$name: $t" if $required->{$name};
    return "$name: Optional[$t] = None";
}

sub _signature_docstring ( $self, $verb_name, $params, $keys ) {
    my $doc = "\"\"\"\n        Add the $verb_name verb to the current document\n        \n";
    for my $name (@$keys) {
        my $desc = '';
        my $d    = $params->{$name};
        if ( ref $d eq 'HASH' && defined $d->{description} ) {
            $desc = $d->{description};
            $desc =~ tr/\n/ /;
            $desc =~ s/^\s+|\s+$//g;
        }
        $doc .= "        Args:\n            $name: $desc\n";
    }
    $doc .= "        \n        Returns:\n            True if the verb was added successfully, "
        . "False otherwise\n        \"\"\"\n";
    return $doc;
}

sub _verb_definition_properties ($verb_entry) {
    my $props = eval { $verb_entry->{definition}{properties} };
    return $props;
}

sub _default_schema_path {

    # Bundled schema lives in lib/SignalWire/SWML/schema.json.
    my $dir = File::Basename::dirname(__FILE__);
    return File::Spec->catfile( $dir, File::Spec->updir, 'SWML', 'schema.json' );
}

sub _env_boolish ($value) {
    my $v = defined $value ? lc($value) : '';
    $v =~ s/^\s+|\s+$//g;
    return ( $v eq '1' || $v eq 'true' || $v eq 'yes' ) ? 1 : 0;
}

sub _extract_verb_definitions ($self) {
    my %verbs;
    my $defs = $self->schema->{'$defs'};
    return \%verbs unless ref $defs eq 'HASH';

    my $swml_method = $defs->{SWMLMethod};
    return \%verbs unless ref $swml_method eq 'HASH';

    my $any_of = $swml_method->{anyOf};
    return \%verbs unless ref $any_of eq 'ARRAY';

    for my $entry (@$any_of) {
        _register_verb_entry( \%verbs, $entry, $defs );
    }
    return \%verbs;
}

sub _register_verb_entry ( $verbs, $entry, $defs ) {
    my $schema_name = _entry_schema_name($entry);
    return unless defined $schema_name;

    my $defn = $defs->{$schema_name};
    return unless ref $defn eq 'HASH';

    my $props = $defn->{properties};
    return unless ref $props eq 'HASH' && %$props;

    my ($actual_verb) = sort keys %$props;

    # Python/Ruby take the FIRST declared property. Perl hash order is not
    # stable, so pick deterministically by sorted key (verb defs have a single
    # property in practice, so this is equivalent).
    $verbs->{$actual_verb} = {
        name        => $actual_verb,
        schema_name => $schema_name,
        definition  => $defn,
    };
    return;
}

# The "#/$defs/<name>" ref's <name>, or undef if the entry isn't a valid ref.
sub _entry_schema_name ($entry) {
    return unless ref $entry eq 'HASH';

    my $ref = $entry->{'$ref'};
    return unless defined $ref && !ref $ref;

    my $prefix = '#/$defs/';
    return unless index( $ref, $prefix ) == 0;

    return substr( $ref, length $prefix );
}

sub _init_full_validator ($self) {

    # Reserved for full-validator wiring (a JSON-Schema validator gem/module).
    $self->_full_validator(undef);
    return;
}

sub _validate_verb_full ( $self, $verb_name, $verb_config ) {

    # Reserved for full-validator wiring; falls back to lightweight check.
    return $self->_validate_verb_lightweight( $verb_name, $verb_config );
}

sub _validate_verb_lightweight ( $self, $verb_name, $verb_config ) {
    my @errors;
    for my $prop ( @{ $self->get_verb_required_properties($verb_name) } ) {
        push @errors, "Missing required property '$prop' for verb '$verb_name'"
            unless exists $verb_config->{$prop};
    }
    return ( ( @errors ? 0 : 1 ), \@errors );
}

sub _python_type_annotation ($defn) {
    return 'Any' unless ref $defn eq 'HASH';

    my $type = $defn->{type};
    return $PYTHON_SCALAR_TYPES{$type}     if defined $type && exists $PYTHON_SCALAR_TYPES{$type};
    return _python_array_annotation($defn) if defined $type && $type eq 'array';

    return 'Any';
}

sub _python_array_annotation ($defn) {
    my $item =
        ref $defn->{items} eq 'HASH' ? _python_type_annotation( $defn->{items} ) : 'Any';
    return "List[$item]";
}

1;

__END__

=head1 NAME

SignalWire::Utils::SchemaUtils - SWML schema loading, verb extraction, and validation

=head1 SYNOPSIS

    use SignalWire::Utils::SchemaUtils;

    my $utils = SignalWire::Utils::SchemaUtils->new;              # bundled schema
    my @verbs = $utils->get_all_verb_names;
    my ($ok, $errors) = $utils->validate_verb('answer', {});
    my $props = $utils->get_verb_properties('ai');

    # Validation can be disabled explicitly or via the environment.
    my $u2 = SignalWire::Utils::SchemaUtils->new( schema_validation => 0 );

=head1 DESCRIPTION

Perl port of the Python reference C<signalwire.utils.schema_utils.SchemaUtils>
(and the Ruby C<SignalWire::Utils::SchemaUtils>). Loads the SWML JSON Schema,
extracts verb metadata from the C<SWMLMethod> C<anyOf> union, validates a
single verb config or a complete document, and generates Python-style method
signatures and bodies for code-generation tooling.

The port ships the lightweight validator (verb existence plus required-property
checking). C<full_validation_available> returns false until a full JSON-Schema
validator is wired into C<_init_full_validator>.

=head1 CONSTRUCTOR

=head2 new(%opts)

=over 4

=item * C<schema_path> - path to a C<schema.json>; C<undef> (default) selects the
bundled copy at C<lib/SignalWire/SWML/schema.json>.

=item * C<schema_validation> - enable (default, truthy) or disable (falsey)
validation. The C<SWML_SKIP_SCHEMA_VALIDATION> environment variable
(C<1>/C<true>/C<yes>) also disables validation regardless of this argument.

=back

=head1 METHODS

=over 4

=item * C<load_schema> - read and parse the JSON Schema (hashref; C<{}> on failure).

=item * C<get_all_verb_names> - sorted list of known verb names.

=item * C<get_verb_properties($verb)> / C<get_verb_parameters($verb)> /
C<get_verb_required_properties($verb)> - verb metadata accessors.

=item * C<validate_verb($verb, $config)> - returns C<($valid, $errors_arrayref)>.

=item * C<validate_document($document)> - returns C<($valid, $errors_arrayref)>.

=item * C<generate_method_signature($verb)> / C<generate_method_body($verb)> -
Python-source code-gen helpers.

=item * C<full_validation_available> - whether a full validator is wired in.

=back

=head1 SEE ALSO

L<SignalWire::Utils::SchemaValidationError>, L<SignalWire::SWML::Schema>

=cut
