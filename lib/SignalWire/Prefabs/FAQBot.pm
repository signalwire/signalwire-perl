package SignalWire::Prefabs::FAQBot;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.

use strict;
use warnings;
use Moo;
use JSON qw(encode_json);
extends 'SignalWire::Agent::AgentBase';

has faqs            => ( is => 'ro', default => sub { [] } );
has suggest_related => ( is => 'ro', default => sub { 1 } );
has persona => (
    is      => 'ro',
    default =>
        sub { 'You are a helpful FAQ bot that provides accurate answers to common questions.' }
);

sub BUILD {
    my ( $self, $args ) = @_;

    $self->name('faq_bot') if $self->name eq 'agent';
    $self->route('/faq')   if $self->route eq '/';
    $self->use_pom(1);

    my $faqs = $self->faqs;

    $self->set_global_data(
        {
            faqs            => $faqs,
            suggest_related => $self->suggest_related ? JSON::true : JSON::false,
        }
    );

    $self->prompt_add_section( 'Personality', $self->persona, );

    # Build FAQ knowledge
    my @faq_bullets;
    for my $faq (@$faqs) {
        push @faq_bullets, "Q: $faq->{question} A: $faq->{answer}";
    }

    $self->prompt_add_section(
        'FAQ Knowledge Base',
        'You have knowledge of the following frequently asked questions.',
        bullets => \@faq_bullets,
    );

    if ( $self->suggest_related ) {
        $self->prompt_add_section(
            'Related Questions',
            'When appropriate, suggest related questions the user might also be interested in.',
        );
    }

    # Register lookup tool
    $self->define_tool(
        name        => 'lookup_faq',
        description => 'Look up an FAQ answer by keyword matching',
        parameters  => {
            type       => 'object',
            properties => {
                query => { type => 'string', description => 'The question or keywords to search' },
            },
            required => ['query'],
        },
        handler => sub {
            my ( $a, $raw ) = @_;
            return $self->search_faqs( $a, $raw );
        },
    );
    return;
}

# Tool: search_faqs — Python parity
# (signalwire.prefabs.faq_bot.FAQBotAgent.search_faqs).
#
# Keyword-matches the query against known FAQ questions (either
# direction) and returns the matching answer, or the list of topics the
# bot can help with when nothing matches.
sub search_faqs {
    my ( $self, $args, $raw_data ) = @_;
    require SignalWire::SWAIG::FunctionResult;

    my $query = lc( $args->{query} // '' );
    my @faqs  = @{ $self->faqs };

    for my $faq (@faqs) {
        my $question = lc( $faq->{question} // '' );
        if ( index( $question, $query ) >= 0
            || ( length $query && index( $query, $question ) >= 0 ) )
        {
            return SignalWire::SWAIG::FunctionResult->new( response => $faq->{answer} );
        }
    }

    my $topics = join( '; ', map { $_->{question} } @faqs );
    return SignalWire::SWAIG::FunctionResult->new(
        response => "I don't have a specific answer for that. "
            . "Here are the topics I can help with: $topics" );
}

# Lifecycle hook: on_summary — Python parity
# (signalwire.prefabs.faq_bot.FAQBotAgent.on_summary).
#
# Logs the post-prompt interaction summary; structured (hashref)
# summaries are emitted as pretty JSON.
sub on_summary {
    my ( $self, $summary, $raw_data ) = @_;
    return if !defined $summary;

    my $ok = eval {
        if ( ref $summary eq 'HASH' ) {
            print 'FAQ interaction summary: ' . JSON->new->canonical->pretty->encode($summary);
        } else {
            print "FAQ interaction summary: $summary\n";
        }
        1;
    };
    print "Error processing summary: $@" if !$ok;
    return;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Prefabs::FAQBot - ready-made FAQ-answering AI agent

=head1 SYNOPSIS

    use SignalWire::Prefabs::FAQBot;

    my $agent = SignalWire::Prefabs::FAQBot->new(
        faqs => [
            { question => 'What are your hours?', answer => 'We are open 9 to 5.' },
            { question => 'Where are you located?', answer => 'At 123 Main Street.' },
        ],
        suggest_related => 1,
    );

    $agent->run;

=head1 DESCRIPTION

L<SignalWire::Prefabs::FAQBot> is a ready-made subclass of
L<SignalWire::Agent::AgentBase> that answers callers' questions from a
supplied list of frequently asked questions.

C<BUILD> names the agent C<faq_bot> and mounts it at C</faq> (unless
overridden), enables POM sections, seeds global data with the FAQ list,
builds the personality and FAQ-knowledge prompt sections, and registers
the C<lookup_faq> SWAIG tool (which dispatches to C<search_faqs>).

=head1 ATTRIBUTES

Constructor attributes (all C<ro>):

=over 4

=item C<faqs>

Arrayref of C<< { question => ..., answer => ... } >> hashrefs
(default C<[]>).

=item C<suggest_related>

Boolean; when true the prompt asks the bot to suggest related questions
(default C<1>).

=item C<persona>

The personality prompt line (default a helpful-FAQ-bot persona).

=back

=head1 METHODS

=over 4

=item C<search_faqs($args, $raw_data)>

Tool handler. Keyword-matches the query against the known FAQ questions
(in either direction) and returns the matching answer, or the list of
topics the bot can help with when nothing matches.

=item C<on_summary($summary, $raw_data)>

Lifecycle hook. Logs the post-prompt interaction summary; hashref
summaries are emitted as pretty JSON.

=back

=head1 SEE ALSO

L<SignalWire::Agent::AgentBase>, L<SignalWire::SWAIG::FunctionResult>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
