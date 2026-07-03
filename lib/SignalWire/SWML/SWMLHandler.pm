package SignalWire::SWML::SWMLHandler;
use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
no warnings 'experimental::signatures';

# SWMLHandler — Perl port of the Python reference
# signalwire.core.swml_handler.SWMLVerbHandler (and the Ruby
# SignalWire::SWML::SWMLVerbHandler). Base interface for SWML verb handlers.
#
# Verb handlers provide specialized logic for complex SWML verbs that cannot be
# handled generically. Python parity: the abstract SWMLVerbHandler ABC. Perl
# has no ABCs; the base methods die so a subclass that forgets to override them
# fails loudly (the analog of @abstractmethod).

# Get the name of the verb this handler handles.
sub get_verb_name ($self) {
    die ref($self) . "->get_verb_name must be implemented\n";
}

# Validate the configuration for this verb.
# Returns ($is_valid, $error_messages_arrayref).
sub validate_config ( $self, $config ) {
    die ref($self) . "->validate_config must be implemented\n";
}

# Build a configuration for this verb from the provided arguments (kwargs-hash).
# Returns a config hashref.
sub build_config ( $self, %kwargs ) {
    die ref($self) . "->build_config must be implemented\n";
}

package SignalWire::SWML::SWMLHandler::AIVerbHandler;
use strict;
use warnings;
use Moo;

use feature 'signatures';
no warnings 'experimental::signatures';

extends 'SignalWire::SWML::SWMLHandler';

# AIVerbHandler — Perl port of the Python reference
# signalwire.core.swml_handler.AIVerbHandler (and the Ruby AIVerbHandler).
# Handler for the SWML 'ai' verb, which is complex and requires specialized
# handling for prompts, SWAIG functions, and AI configurations.

# Top-level AI keys that live outside the params object (Python parity).
my %TOP_LEVEL_AI_KEYS = map { $_ => 1 } qw(languages hints pronounce global_data);

# @return "ai"
sub get_verb_name ($self) {
    return 'ai';
}

# Validate the configuration for the AI verb.
#
# Checks that `prompt` is present and an object, contains exactly one of
# `text` / `pom` (mutually exclusive), that `prompt.contexts` (if present) is
# an object, and that `SWAIG` (if present) is an object.
# Returns ($is_valid, $error_messages_arrayref).
sub validate_config ( $self, $config ) {
    return ( 0, ["Missing required field 'prompt'"] ) unless exists $config->{prompt};

    my $prompt = $config->{prompt};
    return ( 0, ["'prompt' must be an object"] ) unless ref $prompt eq 'HASH';

    my @errors = @{ _validate_base_prompt($prompt) };
    push @errors, "'prompt.contexts' must be an object"
        if exists $prompt->{contexts} && ref $prompt->{contexts} ne 'HASH';
    push @errors, "'SWAIG' must be an object"
        if exists $config->{SWAIG} && ref $config->{SWAIG} ne 'HASH';

    return ( ( @errors ? 0 : 1 ), \@errors );
}

# Build a configuration for the AI verb.
#
# Requires exactly one of `prompt_text` / `prompt_pom` (mutually exclusive).
# `languages`, `hints`, `pronounce` and `global_data` are placed at the top
# level; every other extra keyword is placed into config->{params} (Python
# parity). Returns a config hashref.
sub build_config ( $self, %kwargs ) {
    my $prompt_text = delete $kwargs{prompt_text};
    my $prompt_pom  = delete $kwargs{prompt_pom};
    my $contexts    = delete $kwargs{contexts};
    my $post_prompt = delete $kwargs{post_prompt};
    my $post_url    = delete $kwargs{post_prompt_url};
    my $swaig       = delete $kwargs{swaig};

    _require_single_base_prompt( $prompt_text, $prompt_pom );

    my $config = { prompt => _build_prompt_config( $prompt_text, $prompt_pom, $contexts ) };
    $config->{post_prompt}     = { text => $post_prompt } if defined $post_prompt;
    $config->{post_prompt_url} = $post_url                if defined $post_url;
    $config->{SWAIG}           = $swaig                   if defined $swaig;

    # Match Python behaviour: always initialise the params dict.
    $config->{params} = {};
    _route_extra_kwargs( $config, \%kwargs );
    return $config;
}

# ------------------------------------------------------------------
# Private helpers
# ------------------------------------------------------------------

# Base-prompt errors for validate_config (exactly one of text/pom required).
sub _validate_base_prompt ($prompt) {
    my $count = ( exists $prompt->{text} ? 1 : 0 ) + ( exists $prompt->{pom} ? 1 : 0 );
    return ["'prompt' must contain either 'text' or 'pom' as base prompt"] if $count == 0;
    return ["'prompt' can only contain one of: 'text' or 'pom' (mutually exclusive)"]
        if $count > 1;
    return [];
}

# Enforce the mutually-exclusive base-prompt contract for build_config.
sub _require_single_base_prompt ( $prompt_text, $prompt_pom ) {
    my $count = ( defined $prompt_text ? 1 : 0 ) + ( defined $prompt_pom ? 1 : 0 );
    die "Either prompt_text or prompt_pom must be provided as base prompt\n" if $count == 0;
    die "prompt_text and prompt_pom are mutually exclusive\n"                if $count > 1;
    return;
}

# Build the prompt object ({text|pom => ...} plus optional contexts).
sub _build_prompt_config ( $prompt_text, $prompt_pom, $contexts ) {
    my $prompt_config = {};
    if ( defined $prompt_text ) {
        $prompt_config->{text} = $prompt_text;
    } elsif ( defined $prompt_pom ) {
        $prompt_config->{pom} = $prompt_pom;
    }
    $prompt_config->{contexts} = $contexts if defined $contexts;
    return $prompt_config;
}

# Route extra kwargs: recognised top-level keys stay at the top level,
# everything else drops into config->{params} (Python parity).
sub _route_extra_kwargs ( $config, $kwargs ) {
    for my $key ( keys %$kwargs ) {
        if ( $TOP_LEVEL_AI_KEYS{$key} ) {
            $config->{$key} = $kwargs->{$key};
        } else {
            $config->{params}{$key} = $kwargs->{$key};
        }
    }
    return;
}

package SignalWire::SWML::SWMLHandler::VerbHandlerRegistry;
use strict;
use warnings;
use Moo;

use feature 'signatures';
no warnings 'experimental::signatures';

# VerbHandlerRegistry — Perl port of the Python reference
# signalwire.core.swml_handler.VerbHandlerRegistry (and the Ruby
# VerbHandlerRegistry). Maintains a registry of handlers for special SWML
# verbs. The "ai" verb handler is registered automatically on construction
# (Python parity).

has '_handlers' => ( is => 'ro', default => sub { {} } );

# Register the default handlers (the AI verb handler).
sub BUILD ( $self, $args ) {
    $self->register_handler( SignalWire::SWML::SWMLHandler::AIVerbHandler->new );
    return;
}

# Register a new verb handler, replacing any existing handler for the same
# verb name.
sub register_handler ( $self, $handler ) {
    $self->_handlers->{ $handler->get_verb_name } = $handler;
    return;
}

# Get the handler for a specific verb, or undef when none is registered.
sub get_handler ( $self, $verb_name ) {
    return $self->_handlers->{$verb_name};
}

# Whether a handler exists for a specific verb.
sub has_handler ( $self, $verb_name ) {
    return exists $self->_handlers->{$verb_name} ? 1 : 0;
}

1;

__END__

=head1 NAME

SignalWire::SWML::SWMLHandler - SWML verb handler interface and implementations

=head1 SYNOPSIS

    use SignalWire::SWML::SWMLHandler;

    my $registry = SignalWire::SWML::SWMLHandler::VerbHandlerRegistry->new;
    my $handler  = $registry->get_handler('ai');

    my ($ok, $errors) = $handler->validate_config({
        prompt => { text => 'You are helpful.' },
    });

    my $config = $handler->build_config( prompt_text => 'You are helpful.' );

=head1 DESCRIPTION

Perl port of the Python reference module C<signalwire.core.swml_handler>
(and the Ruby equivalents). Defines the base verb-handler interface plus the
C<ai>-verb handler and a registry.

=over 4

=item * L</SignalWire::SWML::SWMLHandler> - base interface (maps to the Python
C<SWMLVerbHandler> ABC). Its C<get_verb_name>, C<validate_config>, and
C<build_config> die unless a subclass overrides them.

=item * L</SignalWire::SWML::SWMLHandler::AIVerbHandler> - handler for the
C<ai> verb, with prompt/SWAIG validation and config building.

=item * L</SignalWire::SWML::SWMLHandler::VerbHandlerRegistry> - registry that
auto-registers the AI handler on construction.

=back

=head1 SEE ALSO

L<SignalWire::SWML::SWMLBuilder>, L<SignalWire::SWML::SWMLRenderer>

=cut
