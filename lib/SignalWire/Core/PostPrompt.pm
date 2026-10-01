package SignalWire::Core::PostPrompt;

# Copyright (c) 2026 SignalWire
# Licensed under the MIT License.
#
# Post-prompt normalization. Mirrors signalwire.core.post_prompt: one
# conversation can run over voice and over text chat, and both engines produce
# "the post-prompt" in different shapes. This module absorbs the divergence so
# an application sees one artifact regardless of which engine finished the
# conversation. Nothing here raises -- the conversation that produced the input
# is already over and there is nobody to show an error to.

use strict;
use warnings;

use B    ();
use JSON ();

use Exporter qw(import);
our @EXPORT_OK = qw(
    dialogue_turns normalize_post_prompt parse_post_prompt_data strip_json_fence
    DIALOGUE_ROLES
);

# Roles that are actual dialogue. Everything else in a call log is machinery:
# `system` is the prompt, `system-log` lifecycle tracing, `tool` function
# output, `assistant-manual` filler speech.
use constant DIALOGUE_ROLES => qw(user assistant);

my $JSON = JSON->new->allow_nonref;

# Unwrap ```json ... ``` fencing. The chat engine hands the model's answer back
# verbatim, fence and all, where the voice engine parses it first.
sub strip_json_fence {
    my ($text) = @_;
    my $stripped = _strip( defined $text ? $text : '' );
    if ( substr( $stripped, 0, 3 ) eq '```' ) {
        $stripped =~ s/\A```[a-zA-Z]*\s*//;
        $stripped =~ s/\s*```\z//;
    }
    return _strip($stripped);
}

# Return post_prompt_data as a plain hashref, whichever shape it arrived in:
# the {parsed => [ {...} ]} wrapper, a flat object, or {raw => "```json ...```"}.
# Prose instead of JSON yields { summary => "<the prose>" }. {} when nothing is
# usable.
sub parse_post_prompt_data {
    my ($data) = @_;
    return {} unless ref $data eq 'HASH';

    my $unwrapped = _unwrap_parsed($data);
    return $unwrapped if $unwrapped && %$unwrapped;

    # Flat shape: real keys already present (anything but raw/parsed).
    my %flat = map { $_ => $data->{$_} } grep { $_ ne 'raw' && $_ ne 'parsed' } keys %$data;
    return \%flat if %flat;

    my $raw = $data->{raw};
    return {} if !defined $raw || ref $raw || $raw !~ /\S/;
    my $unfenced = strip_json_fence($raw);
    my $loaded   = eval { $JSON->decode($unfenced) };
    if ($@) {

        # Prose instead of JSON. Still a summary.
        return { summary => $unfenced };
    }
    return ref $loaded eq 'HASH' ? $loaded : { summary => _py_str($loaded) };
}

# Extract the real dialogue from a call log: user/assistant turns only, with
# tool calls, empty content and (optionally) the chat engine's summary echo
# removed. Options: roles (arrayref, default DIALOGUE_ROLES), drop_echo (exact
# content to treat as the summary echo).
sub dialogue_turns {
    my ( $call_log, %opts ) = @_;
    return [] unless ref $call_log eq 'ARRAY';

    my @roles = ref $opts{roles} eq 'ARRAY' ? @{ $opts{roles} } : (DIALOGUE_ROLES);
    my %keep  = map { $_ => 1 } grep { defined } @roles;
    my $echo  = _strip( defined $opts{drop_echo} ? $opts{drop_echo} : '' );

    my @out;
    for my $entry (@$call_log) {
        next unless ref $entry eq 'HASH';
        my $role = $entry->{role};
        next if !defined $role || ref $role || !$keep{$role};
        next if _py_truthy( $entry->{tool_calls} );
        my $content = $entry->{content};
        next if !defined $content || ref $content || $content !~ /\S/;
        next if length $echo && _strip($content) eq $echo;
        push @out, { role => $role, content => $content };
    }
    return \@out;
}

# Normalize a post-prompt body from either engine into a
# SignalWire::Core::PostPrompt::NormalizedPostPrompt. A body this cannot make
# sense of yields one with empty fields.
sub normalize_post_prompt {
    my ($body) = @_;
    return SignalWire::Core::PostPrompt::NormalizedPostPrompt->new
        unless ref $body eq 'HASH';

    my $ppd     = $body->{post_prompt_data};
    my $summary = parse_post_prompt_data($ppd);

    # The echo is compared against the RAW string the engine returned, not the
    # parsed summary -- the assistant turn carries the fence too.
    my $raw_summary = '';
    $raw_summary = $ppd->{raw}
        if ref $ppd eq 'HASH' && defined $ppd->{raw} && !ref $ppd->{raw};

    my $log;
    for my $key (qw(call_log raw_call_log raw_messages)) {
        if ( _py_truthy( $body->{$key} ) ) { $log = $body->{$key}; last }
    }

    my $medium = $body->{conversation_type};
    return SignalWire::Core::PostPrompt::NormalizedPostPrompt->new(
        medium          => _py_truthy($medium) ? _py_str($medium) : '',
        conversation_id => _py_truthy( $body->{conversation_id} )
        ? $body->{conversation_id}
        : undef,
        summary  => $summary,
        dialogue =>
            dialogue_turns( $log // [], drop_echo => length $raw_summary ? $raw_summary : undef ),
        call_id => _py_truthy( $body->{call_id} ) ? $body->{call_id} : undef,
        raw     => $body,
    );
}

# --- helpers ---------------------------------------------------------------

sub _strip {
    my ($s) = @_;
    $s =~ s/\A\s+//;
    $s =~ s/\s+\z//;
    return $s;
}

# Pull the object out of a {parsed => [...]} wrapper, if present. Checked
# before the generic sweep, which would otherwise return {parsed => [...]} --
# structurally fine, semantically empty.
sub _unwrap_parsed {
    my ($data) = @_;
    my $parsed = $data->{parsed};
    return $parsed if ref $parsed eq 'HASH';
    if ( ref $parsed eq 'ARRAY' ) {
        for my $item (@$parsed) {
            return $item if ref $item eq 'HASH' && %$item;
        }
    }
    return;
}

# Python truthiness for JSON-shaped values: empty containers, '', 0, null and
# false are falsy; a non-empty STRING (even "0") is truthy.
sub _py_truthy {
    my ($v) = @_;
    return 0 unless defined $v;
    return $v          ? 1 : 0 if JSON::is_bool($v);
    return scalar(%$v) ? 1 : 0 if ref $v eq 'HASH';
    return scalar(@$v) ? 1 : 0 if ref $v eq 'ARRAY';
    return 1 if ref $v;
    return length($v) ? 1 : 0 if _is_string($v);
    return $v != 0 ? 1 : 0;
}

sub _is_string {
    my ($v) = @_;
    my $flags = B::svref_2object( \$v )->FLAGS;
    return ( $flags & B::SVp_POK() ) || !( $flags & ( B::SVp_IOK() | B::SVp_NOK() ) );
}

# str() of a decoded JSON value, as python renders it.
sub _py_str {
    my ($v) = @_;
    return 'None' unless defined $v;
    return $v ? 'True' : 'False' if JSON::is_bool($v);
    return _py_repr($v)          if ref $v;
    return "$v";
}

sub _py_repr {
    my ($v) = @_;
    return 'None' unless defined $v;
    return $v ? 'True' : 'False' if JSON::is_bool($v);
    if ( ref $v eq 'ARRAY' ) {
        return '[' . join( ', ', map { _py_repr($_) } @$v ) . ']';
    }
    if ( ref $v eq 'HASH' ) {
        return
            '{'
            . join( ', ', map { _py_repr($_) . ': ' . _py_repr( $v->{$_} ) } sort keys %$v ) . '}';
    }
    return "$v" unless _is_string($v);
    ( my $s = $v ) =~ s/(['\\])/\\$1/g;
    return "'$s'";
}

package SignalWire::Core::PostPrompt::NormalizedPostPrompt;    ## no critic (ProhibitMultiplePackages)

# One finished conversation leg, in a shape that does not vary by engine.
# Mirrors the frozen dataclass signalwire.core.post_prompt.NormalizedPostPrompt.
use Moo;

has 'medium'          => ( is => 'ro', default => sub { '' } );
has 'conversation_id' => ( is => 'ro', default => sub { undef } );
has 'summary'         => ( is => 'ro', default => sub { {} } );
has 'dialogue'        => ( is => 'ro', default => sub { [] } );
has 'call_id'         => ( is => 'ro', default => sub { undef } );
has 'raw'             => ( is => 'ro', default => sub { {} } );

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Core::PostPrompt - normalize post-prompt bodies from the voice and chat engines

=head1 SYNOPSIS

    use SignalWire::Core::PostPrompt qw(normalize_post_prompt);

    my $leg = normalize_post_prompt($raw_body);
    if ( @{ $leg->dialogue } ) {
        store( $leg->conversation_id, $leg->medium, $leg->summary, $leg->dialogue );
    }

=head1 DESCRIPTION

One conversation can run over voice and over text chat, and both engines
produce "the post-prompt" in different shapes: C<app_name> differs, only chat
carries a top-level C<conversation_id>, the full log is C<raw_call_log> on
voice and C<raw_messages> on chat, the chat engine echoes its summary as a bare
C<role: assistant> turn, and C<post_prompt_data> arrives parsed, fenced
(C<< {raw => "```json ...```"} >>) or wrapped (C<< {parsed => [ {...} ]} >>).
This module absorbs those differences. Parsing is schema-agnostic: the summary
is returned as found. Nothing here dies.

=head1 FUNCTIONS

All are exportable on request.

=over 4

=item C<strip_json_fence($text)>

Unwrap C<```json ... ```> fencing and trim. Returns the inner text.

=item C<parse_post_prompt_data($data)>

Return C<post_prompt_data> as a plain hashref whichever shape it arrived in:
the C<parsed> wrapper's first non-empty object, a flat object (every key but
C<raw>/C<parsed>), or C<raw> decoded as JSON after fence stripping. Prose
instead of JSON yields C<< { summary => $prose } >>. Returns C<{}> when there
is nothing usable.

=item C<dialogue_turns($call_log, roles =E<gt> \@roles, drop_echo =E<gt> $text)>

Extract the real dialogue from a call log: entries whose role is in C<roles>
(default C<user>/C<assistant>), that carry no C<tool_calls>, whose content is
a non-blank string, and whose trimmed content is not C<drop_echo> (the chat
engine's summary echo). Returns an arrayref of C<< { role, content } >>.

=item C<normalize_post_prompt($body)>

Normalize a complete post-prompt request body into a
L</SignalWire::Core::PostPrompt::NormalizedPostPrompt>.

=item C<DIALOGUE_ROLES>

The default dialogue roles: C<user>, C<assistant>.

=back

=head1 SignalWire::Core::PostPrompt::NormalizedPostPrompt

Read-only attributes:

=over 4

=item C<medium>

C<conversation_type> as reported (C<voice> / C<chat>); empty string when the
engine did not say.

=item C<conversation_id>

Present on chat, undef on voice.

=item C<summary>

The parsed C<post_prompt_data> hashref (C<{}> when none).

=item C<dialogue>

The C<user>/C<assistant> turns, tool calls and summary echo removed.

=item C<call_id>

The platform call id, when present.

=item C<raw>

The complete request body, untouched.

=back

=head1 LICENSE

Copyright (c) 2026 SignalWire. Licensed under the MIT License.

=cut
