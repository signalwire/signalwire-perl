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
