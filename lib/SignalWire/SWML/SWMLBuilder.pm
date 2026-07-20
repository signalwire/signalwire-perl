package SignalWire::SWML::SWMLBuilder;
use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
no warnings 'experimental::signatures';

use SignalWire::SWML::Schema;

# SWMLBuilder — Perl port of the Python reference
# signalwire.core.swml_builder.SWMLBuilder (and the Ruby
# SignalWire::SWML::SWMLBuilder). A fluent builder for SWML documents that
# delegates to an underlying SignalWire::SWML::Service instance for the actual
# document creation.
#
# The explicit verb helpers (answer/hangup/play/ai/say) cover the common
# verbs; every other schema verb is auto-vivified through AUTOLOAD (the Perl
# analog of the Python reference's runtime __getattr__ verb dispatch, and of
# the Ruby method_missing). AUTOLOAD delegates to __getattr__, which does the
# actual dispatch and is the recorded surface symbol.

our $AUTOLOAD;

# Verbs that AUTOLOAD must not swallow (they have explicit methods, or are Moo
# / Perl plumbing). The schema check in __getattr__ is the primary guard; this
# keeps the intent explicit.
my %EXPLICIT_METHOD = map { $_ => 1 } qw(
    answer hangup ai play say add_section build render reset service
);

# The Service instance to delegate to.
has 'service' => ( is => 'ro', required => 1 );

# Add an 'answer' verb to the main section.
sub answer ( $self, %opts ) {
    my $config = {};
    $config->{max_duration} = $opts{max_duration} if defined $opts{max_duration};
    $config->{codecs}       = $opts{codecs}       if defined $opts{codecs};
    $self->_add_verb( 'answer', $config );
    return $self;
}

# Add a 'hangup' verb to the main section.
sub hangup ( $self, %opts ) {
    my $config = {};
    $config->{reason} = $opts{reason} if defined $opts{reason};
    $self->_add_verb( 'hangup', $config );
    return $self;
}

# Add an 'ai' verb to the main section.
#
# The SWML `ai` verb requires `prompt` to be an OBJECT — {text => ...} or
# {pom => [...]}; a bare string is a fatal error in the AI engine, so the
# text/pom form is wrapped accordingly. Any extra kwargs are merged into the
# config (parity with Python's config.update(kwargs)).
sub ai ( $self, %opts ) {
    my $prompt_text = delete $opts{prompt_text};
    my $prompt_pom  = delete $opts{prompt_pom};
    my $post_prompt = delete $opts{post_prompt};
    my $post_url    = delete $opts{post_prompt_url};
    my $swaig       = delete $opts{swaig};

    my $config = {};
    $config->{prompt} = _ai_prompt( $prompt_text, $prompt_pom )
        unless !defined $prompt_text && !defined $prompt_pom;
    $config->{post_prompt}     = { text => $post_prompt } if defined $post_prompt;
    $config->{post_prompt_url} = $post_url                if defined $post_url;
    $config->{SWAIG}           = $swaig                   if defined $swaig;

    # Merge any additional kwargs (parity with Python's config.update(kwargs)).
    $config->{$_} = $opts{$_} for keys %opts;

    $self->_add_verb( 'ai', $config );
    return $self;
}

# Add a 'play' verb to the main section.
sub play ( $self, %opts ) {
    my $config = _play_source_config( $opts{url}, $opts{urls} );
    $config->{volume}       = $opts{volume}       if defined $opts{volume};
    $config->{say_voice}    = $opts{say_voice}    if defined $opts{say_voice};
    $config->{say_language} = $opts{say_language} if defined $opts{say_language};
    $config->{say_gender}   = $opts{say_gender}   if defined $opts{say_gender};
    $config->{auto_answer}  = $opts{auto_answer}  if defined $opts{auto_answer};

    $self->_add_verb( 'play', $config );
    return $self;
}

# Add a 'play' verb with a `say:` prefix for text-to-speech.
sub say ( $self, $text, %opts ) {
    return $self->play(
        url          => "say:$text",
        say_voice    => $opts{voice},
        say_language => $opts{language},
        say_gender   => $opts{gender},
        volume       => $opts{volume},
    );
}

# Add a new section to the document.
sub add_section ( $self, $section_name ) {
    $self->service->document->add_section($section_name);
    return $self;
}

# Build and return the SWML document as a hashref.
sub build ($self) {
    return $self->service->document->to_hash;
}

# Build and render the SWML document as a JSON string.
sub render ($self) {
    return $self->service->document->to_json;
}

# Reset the document to an empty state.
sub reset ($self) {
    $self->service->document->sections( {} );
    return $self;
}

# Auto-vivify SWML verb methods from the schema.
#
# Perl analog of the Python reference's __getattr__ runtime verb dispatch (and
# of the Ruby method_missing): any schema verb name not covered by an explicit
# method is dispatched to the underlying document, returning self for
# chaining. `$name` is the verb; the remaining args mirror the Python
# **kwargs (a kwargs-hash), except `sleep` which takes a bare integer.
sub __getattr__ ( $self, $name, @args ) {
    my $schema = SignalWire::SWML::Schema->instance;
    die "'" . ref($self) . "' object has no attribute '$name'"
        unless $schema->has_verb($name);

    if ( $name eq 'sleep' ) {
        $self->_add_verb( 'sleep', _sleep_duration(@args) );
    } else {
        my %kwargs = @args;
        my $config = { map { ( $_ => $kwargs{$_} ) } grep { defined $kwargs{$_} } keys %kwargs };
        $self->_add_verb( $name, $config );
    }
    return $self;
}

# Perl dynamic-dispatch entry point for auto-vivified verbs. Delegates to
# __getattr__ (the recorded surface symbol) so `$builder->denoise(...)` and
# `$builder->sleep(2000)` work like Python attribute-access verb dispatch.
sub AUTOLOAD ( $self, @args ) {
    my $name = $AUTOLOAD;
    $name =~ s/.*:://;
    return if $name eq 'DESTROY';

    # Never intercept explicit methods (Moo accessors etc. resolve normally).
    die qq{Can't locate object method "$name" via package "} . ref($self) . qq{"}
        if $EXPLICIT_METHOD{$name};

    return $self->__getattr__( $name, @args );
}

# ------------------------------------------------------------------
# Private helpers
# ------------------------------------------------------------------

# Add a verb to the underlying document's main section.
#
# Bridges to the Perl Document::add_verb($section, $verb, $data) signature
# (the Python/Ruby references implicitly target the "main" section).
sub _add_verb ( $self, $name, $config ) {
    $self->service->document->add_verb( 'main', $name, $config );
    return;
}

# The prompt object for an ai verb — {text => ...} preferred, else {pom => ...}.
sub _ai_prompt ( $prompt_text, $prompt_pom ) {
    return { text => $prompt_text } if defined $prompt_text;
    return { pom  => $prompt_pom };
}

# The url/urls source config for a play verb (mutually exclusive).
sub _play_source_config ( $url, $urls ) {
    return { url  => $url }  if defined $url;
    return { urls => $urls } if defined $urls;
    die "Either url or urls must be provided\n";
}

# The `sleep` verb takes a bare integer (sleep(2000)) or a duration => N
# keyword; SWML emits the raw integer, not a config object.
sub _sleep_duration (@args) {
    if ( @args == 1 && !ref $args[0] && $args[0] =~ /\A-?[0-9]+\z/ ) {
        return int( $args[0] );
    }
    my %kwargs = @args;
    return int( $kwargs{duration} ) if defined $kwargs{duration};
    if (%kwargs) {
        my ($first) = sort keys %kwargs;
        return $kwargs{$first};
    }
    die "sleep requires an integer duration\n";
}

1;

__END__

=encoding utf8

=head1 NAME

SignalWire::SWML::SWMLBuilder - fluent builder for SWML documents

=head1 SYNOPSIS

    use SignalWire::SWML::Service;
    use SignalWire::SWML::SWMLBuilder;

    my $service = SignalWire::SWML::Service->new;
    my $builder = SignalWire::SWML::SWMLBuilder->new( service => $service );

    $builder->reset
            ->answer
            ->ai( prompt_text => 'You are a helpful assistant.' )
            ->hangup;

    my $doc  = $builder->build;    # hashref
    my $json = $builder->render;   # JSON string

    # Any schema verb not covered by an explicit method is auto-vivified:
    $builder->denoise->record;
    $builder->sleep(2000);

=head1 DESCRIPTION

Perl port of the Python reference C<signalwire.core.swml_builder.SWMLBuilder>
(and the Ruby C<SignalWire::SWML::SWMLBuilder>). Provides a fluent interface
for building SWML documents by chaining method calls, delegating to an
underlying L<SignalWire::SWML::Service> for the actual document.

The explicit helpers C<answer>, C<hangup>, C<play>, C<ai>, and C<say> cover the
common verbs. Every other schema verb is auto-vivified through C<AUTOLOAD>,
which delegates to C<__getattr__> — the Perl analog of the Python reference's
runtime C<__getattr__> verb dispatch. All mutators return C<$self> for chaining.

=head1 CONSTRUCTOR

=head2 new( service =E<gt> $service )

C<service> (a L<SignalWire::SWML::Service>) is required.

=head1 METHODS

=over 4

=item * C<answer(max_duration =E<gt> ..., codecs =E<gt> ...)>

=item * C<hangup(reason =E<gt> ...)>

=item * C<ai(prompt_text|prompt_pom =E<gt> ..., post_prompt =E<gt> ..., swaig =E<gt> ..., ...)>

=item * C<play(url|urls =E<gt> ..., volume =E<gt> ..., ...)>

=item * C<say($text, voice =E<gt> ..., language =E<gt> ..., ...)>

=item * C<add_section($name)>, C<build>, C<render>, C<reset>

=back

=head1 SEE ALSO

L<SignalWire::SWML::Service>, L<SignalWire::SWML::SWMLRenderer>

=cut
