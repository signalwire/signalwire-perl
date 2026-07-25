package SignalWire::SWML::Schema;
use strict;
use warnings;
use Moo;
use JSON           ();
use File::Basename ();

# Singleton instance
my $instance;

has 'verbs' => (
    init_arg => undef,
    is       => 'ro',
    default  => sub { {} },
);

has 'schema_data' => (
    is      => 'ro',
    default => sub { {} },
);

sub BUILD {
    my ($self) = @_;
    $self->_load_schema();
    return;
}

sub _load_schema {
    my ($self)      = @_;
    my $dir         = File::Basename::dirname(__FILE__);
    my $schema_file = "$dir/schema.json";

    open my $fh, '<', $schema_file
        or die "Cannot open schema.json at $schema_file: $!";
    local $/;
    my $json_text = <$fh>;
    close $fh;

    my $data = JSON::decode_json($json_text);
    $self->{schema_data} = $data;

    my $defs        = $data->{'$defs'}      || {};
    my $swml_method = $defs->{SWMLMethod}   || {};
    my $any_of      = $swml_method->{anyOf} || [];

    my %verbs;
    for my $entry (@$any_of) {
        my $ref = $entry->{'$ref'} || next;
        ( my $def_name ) = $ref =~ m{/([^/]+)$};
        next unless $def_name;

        my $def   = $defs->{$def_name} || next;
        my $props = $def->{properties} || next;

        my @keys = keys %$props;
        next unless @keys;

        my $verb_name = $keys[0];
        $verbs{$verb_name} = {
            schema_name => $def_name,
            verb_name   => $verb_name,
            properties  => $props->{$verb_name},
        };
    }

    $self->{verbs} = \%verbs;
    return;
}

sub instance {
    my ($class) = @_;
    $instance //= $class->new();
    return $instance;
}

sub get_verb_names {
    my ($self) = @_;
    my @names = sort keys %{ $self->verbs };
    return @names;
}

sub has_verb {
    my ( $self, $name ) = @_;
    return exists $self->verbs->{$name};
}

sub get_verb {
    my ( $self, $name ) = @_;
    return $self->verbs->{$name};
}

sub verb_count {
    my ($self) = @_;
    return scalar keys %{ $self->verbs };
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::SWML::Schema - SWML verb schema registry (singleton)

=head1 SYNOPSIS

    use SignalWire::SWML::Schema;

    my $schema = SignalWire::SWML::Schema->instance;

    if ( $schema->has_verb('play') ) {
        my $info = $schema->get_verb('play');
    }

    my @names = $schema->get_verb_names;
    my $count = $schema->verb_count;

=head1 DESCRIPTION

L<SignalWire::SWML::Schema> is a Moo class that loads the SWML JSON schema
(C<schema.json>, shipped alongside the module) and indexes the verbs it
defines. It parses the schema's C<SWMLMethod> C<anyOf> union into a
per-verb map of name to C<< { schema_name, verb_name, properties } >>. It
is used for verb validation and auto-vivification by
L<SignalWire::SWML::Service>.

The class is normally used as a process-wide singleton via C<instance>
rather than being constructed directly.

=head1 ATTRIBUTES

=over 4

=item C<verbs>

Hashref of verb name to its schema entry (C<ro>; populated at C<BUILD>).

=item C<schema_data>

The raw decoded C<schema.json> data (C<ro>).

=back

=head1 METHODS

=over 4

=item C<instance>

Return the shared singleton instance, constructing it on first use.

=item C<get_verb_names>

Return the sorted list of known verb names.

=item C<has_verb($name)>

True if C<$name> is a known SWML verb.

=item C<get_verb($name)>

Return the schema entry hashref for a verb, or undef.

=item C<verb_count>

Return the number of known verbs.

=back

=head1 SEE ALSO

L<SignalWire::SWML::Service>, L<SignalWire::SWML::Document>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
