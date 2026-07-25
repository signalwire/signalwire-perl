package SignalWire::Core::Agent::Prompt::Manager;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# Prompt management functionality for AgentBase.
#
# Perl port of signalwire.core.agent.prompt.manager.PromptManager
# (signalwire-python/signalwire/signalwire/core/agent/prompt/manager.py),
# structurally mirroring Ruby's
# SignalWire::Core::Agent::Prompt::Manager
# (signalwire-ruby/lib/signalwire/core/agent/prompt/manager.rb).
#
# Manages a POM-backed prompt (via SignalWire::POM::PromptObjectModel),
# an optional raw prompt text, a post-prompt, and a contexts
# configuration (via SignalWire::Contexts::ContextBuilder).
#
# The prompt has two mutually exclusive modes: raw text
# (set_prompt_text) OR POM sections (the prompt_add_* methods). Mixing the
# two dies. Contexts, when defined, take precedence over both in
# get_prompt.

use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
use Scalar::Util qw(blessed);
use Carp         qw(croak);
use SignalWire::POM::PromptObjectModel;

# ---------- attributes ----------

# Optional parent AgentBase back-reference, kept for parity with the
# Python/Ruby managers; may be undef for standalone use.
has agent => (
    is      => 'ro',
    default => sub { undef },
);

# The backing POM. A fresh, empty PromptObjectModel by default.
has pom => (
    init_arg => undef,
    is       => 'rw',
    default  => sub { SignalWire::POM::PromptObjectModel->new },
);

has _prompt_text => (
    init_arg => undef,
    is       => 'rw',
    default  => sub { undef },
);

has _post_prompt_text => (
    init_arg => undef,
    is       => 'rw',
    default  => sub { undef },
);

has _contexts => (
    init_arg => undef,
    is       => 'rw',
    default  => sub { undef },
);

# ---------- public methods ----------

# Set the agent's prompt as raw text. Dies if POM sections are already in
# use (the two prompt modes are mutually exclusive). Returns $self.
sub set_prompt_text ( $self, $text ) {
    $self->_validate_prompt_mode_exclusivity;
    $self->_prompt_text($text);
    return $self;
}

# Set the post-prompt text. Returns $self.
sub set_post_prompt ( $self, $text ) {
    $self->_post_prompt_text($text);
    return $self;
}

# Set the prompt from a POM arrayref (list of section hashrefs). Clears
# any raw prompt text and rebuilds the POM. Mirrors Python's
# set_prompt_pom(pom). Returns $self.
sub set_prompt_pom ( $self, $pom ) {
    $self->_prompt_text(undef);
    $self->pom( SignalWire::POM::PromptObjectModel->from_json($pom) );
    return $self;
}

# Add a section to the prompt. Mirrors Python's
# prompt_add_section(title, body="", bullets=None, numbered=False,
# numbered_bullets=False, subsections=None). Returns $self.
sub prompt_add_section ( $self, $title, %opts ) {
    $self->_validate_prompt_mode_exclusivity;
    my $section = $self->pom->add_section(
        title           => $title,
        body            => defined $opts{body} ? $opts{body} : '',
        bullets         => $opts{bullets} || [],
        numbered        => $opts{numbered}         ? 1 : 0,
        numberedBullets => $opts{numbered_bullets} ? 1 : 0,
    );
    $self->_add_subsections( $section, $opts{subsections} );
    return $self;
}

# Add content to an existing section (creating it if needed). Mirrors
# Python's prompt_add_to_section(title, body=None, bullet=None,
# bullets=None). Returns $self.
sub prompt_add_to_section ( $self, $title, %opts ) {
    my $section = $self->pom->find_section($title)
        || $self->pom->add_section( title => $title, body => '' );
    $self->_append_body( $section, $opts{body} );
    $self->_append_bullets( $section, $opts{bullet}, $opts{bullets} );
    return $self;
}

# Add a subsection to an existing section (creating the parent if
# needed). Mirrors Python's prompt_add_subsection(parent_title, title,
# body="", bullets=None). Returns $self.
sub prompt_add_subsection ( $self, $parent_title, $title, %opts ) {
    my $parent = $self->pom->find_section($parent_title)
        || $self->pom->add_section( title => $parent_title, body => '' );
    $parent->add_subsection(
        title   => $title,
        body    => defined $opts{body} ? $opts{body} : '',
        bullets => $opts{bullets} || [],
    );
    return $self;
}

# Check whether a section exists in the prompt. Returns 1/0.
sub prompt_has_section ( $self, $title ) {
    return defined $self->pom->find_section($title) ? 1 : 0;
}

# Define contexts for the agent. Accepts a ContextBuilder (materialised
# via to_hash / to_dict) or a raw hashref. Mirrors Python's
# define_contexts(contexts). Dies otherwise. Returns $self.
sub define_contexts ( $self, $contexts ) {
    if ( blessed($contexts) && $contexts->can('to_hash') ) {
        $self->_contexts( $contexts->to_hash );
    } elsif ( blessed($contexts) && $contexts->can('to_dict') ) {
        $self->_contexts( $contexts->to_dict );
    } elsif ( ref $contexts eq 'HASH' ) {
        $self->_contexts($contexts);
    } else {
        croak 'contexts must be a hashref or a ContextBuilder object';
    }
    return $self;
}

# Get the prompt configuration. Contexts take precedence (return —
# they render their own sections); otherwise the raw text if set, else
# the POM section arrayref, else undef.
sub get_prompt ($self) {
    return                     if $self->_contexts;
    return $self->_prompt_text if defined $self->_prompt_text && length $self->_prompt_text;

    my $sections = $self->pom->to_hash;
    return ( ref $sections eq 'ARRAY' && @$sections ) ? $sections : undef;
}

# Get the raw prompt text if set (or undef).
sub get_raw_prompt ($self) {
    return $self->_prompt_text;
}

# Get the post-prompt text (or undef).
sub get_post_prompt ($self) {
    return $self->_post_prompt_text;
}

# Get the contexts configuration (hashref or undef).
sub get_contexts ($self) {
    return $self->_contexts;
}

# ---------- private helpers ----------

# Die if both prompt modes (raw text + POM sections) are active.
sub _validate_prompt_mode_exclusivity ($self) {
    return unless defined $self->_prompt_text && length $self->_prompt_text;
    my $sections = $self->pom->to_hash;
    return unless ref $sections eq 'ARRAY' && @$sections;

    croak 'Cannot use both prompt_text and POM sections. '
        . 'Please use either set_prompt_text() OR the prompt_add_* methods, not both.';
}

sub _add_subsections ( $self, $section, $subsections ) {
    return unless ref $subsections eq 'ARRAY';

    for my $sub (@$subsections) {
        next unless ref $sub eq 'HASH';
        next unless defined $sub->{title};
        $section->add_subsection(
            title   => $sub->{title},
            body    => defined $sub->{body} ? $sub->{body} : '',
            bullets => $sub->{bullets} || [],
        );
    }
    return;
}

sub _append_body ( $self, $section, $body ) {
    return unless defined $body && length $body;
    my $cur = $section->body;
    if ( defined $cur && length $cur ) {
        $section->body("$cur\n\n$body");
    } else {
        $section->body($body);
    }
    return;
}

sub _append_bullets ( $self, $section, $bullet, $bullets ) {
    my @to_add;
    push @to_add, $bullet   if defined $bullet;
    push @to_add, @$bullets if ref $bullets eq 'ARRAY';
    $section->add_bullets( \@to_add ) if @to_add;
    return;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Core::Agent::Prompt::Manager - prompt building and configuration for an agent

=head1 SYNOPSIS

    use SignalWire::Core::Agent::Prompt::Manager;

    my $pm = SignalWire::Core::Agent::Prompt::Manager->new;

    # POM mode
    $pm->prompt_add_section('Role', body => 'You are a helpful assistant.')
       ->prompt_add_subsection('Role', 'Tone', body => 'Be warm.');
    my $sections = $pm->get_prompt;   # arrayref of section hashes

    # OR raw-text mode (mutually exclusive with POM sections)
    my $pm2 = SignalWire::Core::Agent::Prompt::Manager->new;
    $pm2->set_prompt_text('You are a helpful assistant.');
    my $text = $pm2->get_prompt;      # the string

=head1 DESCRIPTION

L<SignalWire::Core::Agent::Prompt::Manager> is the Perl port of
C<signalwire.core.agent.prompt.manager.PromptManager>. It manages a
POM-backed prompt (via L<SignalWire::POM::PromptObjectModel>), an optional
raw prompt text, a post-prompt, and a contexts configuration.

The prompt has two mutually exclusive modes: raw text
(C<set_prompt_text>) OR POM sections (the C<prompt_add_*> methods). Mixing
the two dies. Contexts, when defined, take precedence over both in
C<get_prompt> (which then returns C<undef> because contexts render their
own sections).

=head2 Methods

=over 4

=item * C<set_prompt_text($text)> — set the raw prompt (dies if POM sections exist).

=item * C<set_post_prompt($text)> — set the post-prompt text.

=item * C<set_prompt_pom($arrayref)> — rebuild the POM from a section arrayref.

=item * C<prompt_add_section($title, %opts)> — add a POM section (C<body>,
C<bullets>, C<numbered>, C<numbered_bullets>, C<subsections>).

=item * C<prompt_add_to_section($title, %opts)> — append C<body> / C<bullet>
/ C<bullets> to a section, creating it if needed.

=item * C<prompt_add_subsection($parent_title, $title, %opts)> — add a
subsection, creating the parent if needed.

=item * C<prompt_has_section($title)> — true if the section exists.

=item * C<define_contexts($contexts)> — set contexts from a ContextBuilder or hashref.

=item * C<get_prompt> / C<get_raw_prompt> / C<get_post_prompt> / C<get_contexts>
— accessors for the configured prompt state.

=back

All mutators return C<$self> for chaining.

=head1 SEE ALSO

L<SignalWire::POM::PromptObjectModel>, L<SignalWire::Agent::AgentBase>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
