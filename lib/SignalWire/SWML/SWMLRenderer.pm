package SignalWire::SWML::SWMLRenderer;
use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
no warnings 'experimental::signatures';

use SignalWire::SWML::SWMLBuilder;

# SWMLRenderer — Perl port of the Python reference
# signalwire.core.swml_renderer.SwmlRenderer (and the Ruby
# SignalWire::SWML::SwmlRenderer). Renders SWML documents for SignalWire AI
# Agents with AI and SWAIG components, built on top of the SWML::Service
# document model.
#
# Both public helpers are class methods (Python parity: the reference methods
# are @staticmethod; Ruby uses def self.). Call them on the class, e.g.
# SignalWire::SWML::SWMLRenderer->render_swml( prompt => ..., service => ... ).

# Special hook function names that are deduped from the caller's list.
my @HOOK_FUNCTIONS = qw(startup_hook hangup_hook);

# Action verbs (in precedence order) recognised in a function response.
my @RESPONSE_ACTION_VERBS = qw(play hangup transfer ai);

# Generate a complete SWML document with an AI configuration.
#
# Required kwargs: prompt, service. Optional kwargs mirror the reference:
# post_prompt, post_prompt_url, swaig_functions, startup_hook_url,
# hangup_hook_url, prompt_is_pom, params, add_answer, record_call,
# record_format, record_stereo, format, default_webhook_url.
# Returns the SWML document as a string.
sub render_swml ( $class, %opts ) {
    my $prompt  = $opts{prompt};
    my $service = $opts{service} // die("render_swml requires 'service'");

    my $format        = $opts{format}        // 'json';
    my $prompt_is_pom = $opts{prompt_is_pom} // 0;
    my $add_answer    = $opts{add_answer}    // 0;
    my $record_call   = $opts{record_call}   // 0;
    my $record_format = $opts{record_format} // 'mp4';
    my $record_stereo = defined $opts{record_stereo} ? $opts{record_stereo} : 1;

    my $builder = SignalWire::SWML::SWMLBuilder->new( service => $service );
    $builder->reset;
    $builder->answer                                             if $add_answer;
    _add_record_call( $service, $record_format, $record_stereo ) if $record_call;

    my $functions =
        _build_functions( $opts{swaig_functions}, $opts{startup_hook_url}, $opts{hangup_hook_url} );
    my $swaig_config = _build_swaig_config( $functions, $opts{default_webhook_url} );
    _emit_ai( $builder, $prompt, $prompt_is_pom, $swaig_config,
        $opts{post_prompt}, $opts{post_prompt_url}, $opts{params}, );
    return _render_in( $builder, $format );
}

# Generate a SWML document for a function response — a `play` of the response
# text followed by any provided actions.
#
# Required kwargs: response_text, service. Optional: actions, format.
# Returns the SWML document as a string.
sub render_function_response_swml ( $class, %opts ) {
    my $response_text = $opts{response_text};
    my $service       = $opts{service} // die("render_function_response_swml requires 'service'");
    my $actions       = $opts{actions} // [];
    my $format        = $opts{format}  // 'json';

    $service->document->sections( {} );
    $service->document->add_verb( 'main', 'play', { text => $response_text } )
        if defined $response_text && length $response_text;
    _add_response_action( $service, $_ ) for @$actions;

    return lc("$format") eq 'yaml'
        ? _render_yaml( $service->document->to_hash )
        : $service->document->to_json;
}

# ------------------------------------------------------------------
# Private helpers
# ------------------------------------------------------------------

# Add the record_call verb with its exact wire keys (format + stereo).
sub _add_record_call ( $service, $record_format, $record_stereo ) {
    $service->document->add_verb( 'main', 'record_call',
        { format => $record_format, stereo => $record_stereo } );
    return;
}

# Emit the ai verb on the builder from the renderer's inputs.
sub _emit_ai ( $builder, $prompt, $prompt_is_pom, $swaig_config, $post_prompt, $post_url, $params )
{
    $builder->ai(
        prompt_text     => $prompt_is_pom ? undef   : $prompt,
        prompt_pom      => $prompt_is_pom ? $prompt : undef,
        post_prompt     => $post_prompt,
        post_prompt_url => $post_url,
        swaig           => ( %$swaig_config ? $swaig_config : undef ),
        %{ $params // {} },
    );
    return;
}

# Render the builder's document in the requested format ("json" | "yaml").
sub _render_in ( $builder, $format ) {
    return lc("$format") eq 'yaml' ? _render_yaml( $builder->build ) : $builder->render;
}

# Add the first recognised action verb from an action hashref to the document.
sub _add_response_action ( $service, $action ) {
    my ($verb) = grep { exists $action->{$_} } @RESPONSE_ACTION_VERBS;
    $service->document->add_verb( 'main', $verb, $action->{$verb} ) if defined $verb;
    return;
}

# Build the SWAIG function list, prepending startup/hangup hooks and skipping
# any duplicate hooks in the caller-supplied list.
sub _build_functions ( $swaig_functions, $startup_hook_url, $hangup_hook_url ) {
    my @functions = @{ _hook_functions( $startup_hook_url, $hangup_hook_url ) };
    my %is_hook   = map { $_ => 1 } @HOOK_FUNCTIONS;
    for my $func ( @{ $swaig_functions // [] } ) {
        my $fn = $func->{function};
        push @functions, $func unless defined $fn && $is_hook{$fn};
    }
    return \@functions;
}

# The startup/hangup hook function definitions (only for non-empty URLs).
sub _hook_functions ( $startup_hook_url, $hangup_hook_url ) {
    my @list;
    push @list, _hook_function( 'startup_hook', 'Called when the call starts', $startup_hook_url )
        if defined $startup_hook_url && length $startup_hook_url;
    push @list, _hook_function( 'hangup_hook', 'Called when the call ends', $hangup_hook_url )
        if defined $hangup_hook_url && length $hangup_hook_url;
    return \@list;
}

# Build a single startup/hangup hook function definition.
sub _hook_function ( $name, $description, $url ) {
    return {
        function     => $name,
        description  => $description,
        parameters   => { type => 'object', properties => {} },
        web_hook_url => $url,
    };
}

# Build the SWAIG config object from the function list + default URL.
sub _build_swaig_config ( $functions, $default_webhook_url ) {
    my $swaig_config = {};
    my $has_default  = defined $default_webhook_url && length $default_webhook_url;
    return $swaig_config unless @$functions || $has_default;

    $swaig_config->{defaults}  = { web_hook_url => $default_webhook_url } if $has_default;
    $swaig_config->{functions} = $functions                               if @$functions;
    return $swaig_config;
}

# Render a document hashref as YAML (parity with the reference's optional yaml
# branch). Perl's YAML module is available in the SDK toolchain.
sub _render_yaml ($doc) {
    require YAML;
    return YAML::Dump($doc);
}

1;

__END__

=head1 NAME

SignalWire::SWML::SWMLRenderer - render SWML documents with AI and SWAIG components

=head1 SYNOPSIS

    use SignalWire::SWML::Service;
    use SignalWire::SWML::SWMLRenderer;

    my $service = SignalWire::SWML::Service->new;

    my $swml = SignalWire::SWML::SWMLRenderer->render_swml(
        prompt          => 'You are a helpful assistant.',
        service         => $service,
        add_answer      => 1,
        swaig_functions => [ { function => 'get_time', description => '...' } ],
    );

    my $resp = SignalWire::SWML::SWMLRenderer->render_function_response_swml(
        response_text => 'Done!',
        service       => $service,
        actions       => [ { hangup => {} } ],
    );

=head1 DESCRIPTION

Perl port of the Python reference C<signalwire.core.swml_renderer.SwmlRenderer>
(and the Ruby C<SignalWire::SWML::SwmlRenderer>). Two class-method helpers
render SWML documents on top of the L<SignalWire::SWML::Service> document model:

=over 4

=item * C<render_swml(%opts)> - a full document with an C<ai> verb, optional
C<answer> / C<record_call>, and a SWAIG block (with startup/hangup hooks).

=item * C<render_function_response_swml(%opts)> - a C<play> of the response
text followed by any provided action verbs.

=back

Both accept a C<format> of C<"json"> (default) or C<"yaml">.

=head1 SEE ALSO

L<SignalWire::SWML::SWMLBuilder>, L<SignalWire::SWML::Service>

=cut
