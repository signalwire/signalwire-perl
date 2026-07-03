package SignalWire::Core::PomBuilder;

# Copyright (c) 2025 SignalWire
#
# This file is part of the SignalWire SDK.
#
# Licensed under the MIT License.
# See LICENSE file in the project root for full license information.
#
# PomBuilder for creating structured POM prompts for SignalWire AI Agents.
#
# Perl port of signalwire.core.pom_builder.PomBuilder. A flexible wrapper
# around SignalWire::POM::PromptObjectModel that allows for dynamic creation
# of sections on demand, adding content to existing sections, nesting
# subsections, and rendering to Markdown or XML. All mutator methods return
# $self for fluent chaining.

use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
use SignalWire::POM::PromptObjectModel;

# ---------- attributes ----------

# The underlying typed POM document. Populated with an empty model at
# construction; from_sections replaces it with a fully-built one.
has pom => (
    is      => 'rw',
    default => sub { SignalWire::POM::PromptObjectModel->new },
);

# Title -> Section index for auto-vivification and lookup. Not part of the
# Python public surface (leading-underscore private in the enumerator).
has _sections => (
    is      => 'rw',
    default => sub { {} },
);

# ---------- public methods ----------

# Add a new section to the POM.
#
# ``subsections`` is an optional arrayref of subsection descriptor hashrefs,
# each supporting the keys 'title', 'body', and 'bullets'. Returns $self for
# method chaining.
sub add_section ( $self, $title, %opts ) {
    my $section = $self->pom->add_section(
        title           => $title,
        body            => exists $opts{body} ? $opts{body} : '',
        bullets         => $opts{bullets} || [],
        numbered        => $opts{numbered},
        numberedBullets => $opts{numbered_bullets} ? 1 : 0,
    );
    $self->_sections->{$title} = $section;

    for my $subsection_data ( @{ $opts{subsections} || [] } ) {
        next unless ref $subsection_data eq 'HASH' && exists $subsection_data->{title};
        $section->add_subsection(
            title   => $subsection_data->{title},
            body    => exists $subsection_data->{body} ? $subsection_data->{body} : '',
            bullets => $subsection_data->{bullets} || [],
        );
    }

    return $self;
}

# Add content to an existing section, creating it if it doesn't exist
# (auto-vivification).
#
# ``body`` is appended to any existing body (separated by a blank line),
# ``bullet`` appends a single bullet, and ``bullets`` appends an arrayref of
# bullets. Returns $self for method chaining.
sub add_to_section ( $self, $title, %opts ) {
    $self->add_section($title) unless exists $self->_sections->{$title};

    my $section = $self->_sections->{$title};

    if ( defined $opts{body} && length $opts{body} ) {
        $self->_append_body( $section, $opts{body} );
    }
    push @{ $section->bullets }, $opts{bullet}       if defined $opts{bullet};
    push @{ $section->bullets }, @{ $opts{bullets} } if $opts{bullets};

    return $self;
}

# Add a subsection to an existing section, creating the parent if needed
# (auto-vivification). Returns $self for method chaining.
sub add_subsection ( $self, $parent_title, $title, %opts ) {
    $self->add_section($parent_title) unless exists $self->_sections->{$parent_title};

    my $parent = $self->_sections->{$parent_title};
    $parent->add_subsection(
        title   => $title,
        body    => exists $opts{body} ? $opts{body} : '',
        bullets => $opts{bullets} || [],
    );
    return $self;
}

# Check if a section with the given title exists.
sub has_section ( $self, $title ) {
    return exists $self->_sections->{$title} ? 1 : 0;
}

# Get a section by title, or undef if not found.
sub get_section ( $self, $title ) {
    return $self->_sections->{$title};
}

# Render the POM as Markdown.
sub render_markdown ($self) {
    return $self->pom->render_markdown;
}

# Render the POM as XML.
sub render_xml ($self) {
    return $self->pom->render_xml;
}

# Convert the POM to an arrayref of section hashes. Mirrors Python's
# ``PomBuilder.to_dict``.
sub to_dict ($self) {
    return $self->pom->to_hash;
}

# Convert the POM to a JSON string.
sub to_json ($self) {
    return $self->pom->to_json;
}

# Create a PomBuilder from an arrayref of section hashes. Mirrors Python's
# ``PomBuilder.from_sections`` classmethod (both Class->from_sections(...)
# and $instance->from_sections(...) work).
sub from_sections ( $class_or_self, $sections ) {
    my $class   = ref($class_or_self) || $class_or_self;
    my $builder = $class->new;
    $builder->pom( SignalWire::POM::PromptObjectModel->from_json($sections) );
    for my $section ( @{ $builder->pom->sections } ) {
        $builder->_sections->{ $section->title } = $section if defined $section->title;
    }
    return $builder;
}

# ---------- private helpers ----------

sub _append_body ( $self, $section, $body ) {
    my $existing = $section->body;
    if ( defined $existing && length $existing ) {
        $section->body("${existing}\n\n${body}");
    } else {
        $section->body($body);
    }
    return;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Core::PomBuilder - fluent builder for structured POM prompts

=head1 SYNOPSIS

    use SignalWire::Core::PomBuilder;

    my $builder = SignalWire::Core::PomBuilder->new;
    $builder->add_section( 'Role', body => 'You are a helpful assistant.' )
            ->add_to_section( 'Role', bullet => 'Be concise.' )
            ->add_subsection( 'Role', 'Tone', body => 'Speak warmly.' );

    print $builder->render_markdown;
    my $json = $builder->to_json;

    my $rebuilt = SignalWire::Core::PomBuilder->from_sections(
        [ { title => 'Greeting', body => 'Hi there.' } ] );

=head1 DESCRIPTION

L<SignalWire::Core::PomBuilder> is a Perl port of
C<signalwire.core.pom_builder.PomBuilder>. It is a flexible wrapper around
L<SignalWire::POM::PromptObjectModel> that supports dynamic creation of
sections, adding content to existing sections, nesting subsections, and
rendering to Markdown or XML. There are no predefined section types — any
structure that fits your needs can be created.

All mutator methods (C<add_section>, C<add_to_section>, C<add_subsection>)
return C<$self> for fluent chaining.

=head1 METHODS

=over 4

=item * C<add_section($title, %opts)> — add a new section; opts:
C<body>, C<bullets>, C<numbered>, C<numbered_bullets>, C<subsections>.

=item * C<add_to_section($title, %opts)> — append C<body> / C<bullet> /
C<bullets> to an existing section (auto-vivifying it).

=item * C<add_subsection($parent_title, $title, %opts)> — add a subsection
to a section (auto-vivifying the parent).

=item * C<has_section($title)> / C<get_section($title)> — presence check and
lookup.

=item * C<render_markdown> / C<render_xml> — render the POM.

=item * C<to_dict> — the POM as an arrayref of section hashes.

=item * C<to_json> — the POM as a JSON string.

=item * C<from_sections($sections)> — build a PomBuilder from an arrayref of
section hashes.

=back

=head1 SEE ALSO

L<SignalWire::POM::PromptObjectModel>, L<SignalWire::POM::Section>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
