package SignalWire::SWML::Document;
use strict;
use warnings;
use Moo;
use JSON ();

has 'version' => (
    is      => 'ro',
    default => sub { '1.0.0' },
);

has 'sections' => (
    is => 'rw',

    # Python parity: SWMLService._create_empty_document seeds the document with
    # an (empty) "main" section — {"version":"1.0.0","sections":{"main":[]}} —
    # so a freshly rendered SWML doc always carries sections.main, even before
    # any verb is added.
    default => sub { { main => [] } },
);

sub add_section {
    my ( $self, $name ) = @_;
    $self->sections->{$name} //= [];
    return $self;
}

sub add_verb {
    my ( $self, $section_name, $verb_name, $verb_data ) = @_;
    $self->sections->{$section_name} //= [];
    push @{ $self->sections->{$section_name} }, { $verb_name => $verb_data };
    return $self;
}

sub add_raw_verb {
    my ( $self, $section_name, $verb_hash ) = @_;
    $self->sections->{$section_name} //= [];
    push @{ $self->sections->{$section_name} }, $verb_hash;
    return $self;
}

sub get_section {
    my ( $self, $name ) = @_;
    return $self->sections->{$name};
}

sub has_section {
    my ( $self, $name ) = @_;
    return exists $self->sections->{$name};
}

sub clear_section {
    my ( $self, $name ) = @_;
    $self->sections->{$name} = [];
    return $self;
}

sub to_hash {
    my ($self) = @_;
    return {
        version  => $self->version,
        sections => $self->sections,
    };
}

sub to_json {
    my ($self) = @_;
    return JSON::encode_json( $self->to_hash );
}

sub to_pretty_json {
    my ($self) = @_;
    my $json = JSON->new->utf8->canonical->pretty;
    return $json->encode( $self->to_hash );
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::SWML::Document - build and serialize a SWML document

=head1 SYNOPSIS

    use SignalWire::SWML::Document;

    my $doc = SignalWire::SWML::Document->new;
    $doc->add_verb('main', 'answer', {});
    $doc->add_verb('main', 'play', { url => 'https://example.com/hi.mp3' });

    my $hash = $doc->to_hash;   # { version => '1.0.0', sections => {...} }
    my $json = $doc->to_json;
    print $doc->to_pretty_json;

=head1 DESCRIPTION

L<SignalWire::SWML::Document> is a Moo class that models a SWML document —
a versioned collection of named sections, each an ordered list of verbs. A
freshly constructed document carries an empty C<main> section, so
C<sections.main> is always present even before any verb is added.

=head1 ATTRIBUTES

=over 4

=item C<version>

The SWML version string (C<ro>, default C<'1.0.0'>).

=item C<sections>

Hashref of section name to an arrayref of verb hashrefs (C<rw>, default
C<< { main => [] } >>).

=back

=head1 METHODS

=over 4

=item C<add_section($name)>

Ensure a named section exists (as an empty list if new). Returns C<$self>.

=item C<add_verb($section_name, $verb_name, $verb_data)>

Append the verb C<< { $verb_name => $verb_data } >> to the named section
(creating it if absent). Returns C<$self>.

=item C<add_raw_verb($section_name, $verb_hash)>

Append an already-formed verb hashref to the named section. Returns
C<$self>.

=item C<get_section($name)>

Return the arrayref of verbs for a section, or undef.

=item C<has_section($name)>

True if the named section exists.

=item C<clear_section($name)>

Reset the named section to an empty list. Returns C<$self>.

=item C<to_hash>

Return the document as a C<< { version, sections } >> hashref.

=item C<to_json>

Serialize C<to_hash> to a compact JSON string.

=item C<to_pretty_json>

Serialize C<to_hash> to a canonical, pretty-printed JSON string.

=back

=head1 SEE ALSO

L<SignalWire::SWML::Service>, L<SignalWire::SWML::Schema>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
