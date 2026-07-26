#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON qw(encode_json decode_json);

use_ok('SignalWire::Prefabs::Survey');

# The construction param is `questions`, matching the reference
# (prefabs/survey.py:56 — a REQUIRED positional). It was previously spelled
# `survey_questions`, so a reference-shaped `questions => [...]` was SILENTLY
# DISCARDED by Moo: the agent built with zero questions, rendered an empty
# "Survey Questions" section, and never errored. Assert the value REACHES both
# the accessor and the rendered prompt, not just that construction succeeded.
subtest 'questions reaches the accessor AND the rendered prompt' => sub {
    my $a = SignalWire::Prefabs::Survey->new(
        survey_name => 'CSAT',
        questions   => [
            { id => 'q1', text => 'How satisfied were you?', type => 'rating', scale => 5 },
            { id => 'q2', text => 'Any comments?',           type => 'open_ended' },
        ],
    );
    is(scalar @{ $a->questions }, 2, 'questions readable back off the accessor');
    is($a->questions->[0]{id}, 'q1', 'first question preserved');

    # RENDERED prompt text, not storage: a stored-but-unrendered value is the
    # prefab defect this campaign found in five other ports.
    my $rendered = $a->pom->render_markdown;
    like($rendered, qr/How satisfied were you\?/, 'question 1 text rendered into the prompt');
    like($rendered, qr/Any comments\?/,           'question 2 text rendered into the prompt');

    # global_data carries the questions under the reference's `questions` key.
    is(scalar @{ $a->global_data->{questions} }, 2, 'global_data.questions populated');
};

subtest 'construction defaults' => sub {
    my $a = SignalWire::Prefabs::Survey->new(
        survey_name      => 'Test Survey',
        questions => [
            { id => 'q1', text => 'Rate us', type => 'rating', scale => 5, required => 1 },
        ],
    );
    is($a->name, 'survey', 'default name');
    is($a->route, '/survey', 'default route');
    ok($a->isa('SignalWire::Agent::AgentBase'), 'isa AgentBase');
};

subtest 'tools registered' => sub {
    my $a = SignalWire::Prefabs::Survey->new(
        survey_name      => 'S',
        questions => [{ id => 'q1', text => 'Q?', type => 'rating', scale => 5, required => 1 }],
    );
    ok(exists $a->tools->{submit_survey_answer}, 'submit_survey_answer');
};

subtest 'prompt sections' => sub {
    my $a = SignalWire::Prefabs::Survey->new(
        survey_name      => 'Test',
        questions => [{ id => 'q1', text => 'Q?', type => 'open_ended', required => 0 }],
    );
    ok($a->prompt_has_section('Survey Introduction'), 'intro section');
    ok($a->prompt_has_section('Survey Questions'), 'questions section');
};

subtest 'global data' => sub {
    my $a = SignalWire::Prefabs::Survey->new(
        survey_name      => 'Satisfaction',
        questions => [
            { id => 'q1', text => 'Q1?', type => 'rating', scale => 5, required => 1 },
            { id => 'q2', text => 'Q2?', type => 'open_ended', required => 0 },
        ],
    );
    my $gdata = $a->global_data;
    is($gdata->{survey_name}, 'Satisfaction', 'survey name in data');
    is(scalar @{$gdata->{questions}}, 2, 'two questions');
};

subtest 'tool execution' => sub {
    my $a = SignalWire::Prefabs::Survey->new(
        survey_name      => 'S',
        questions => [{ id => 'q1', text => 'Q?', type => 'rating', scale => 5, required => 1 }],
    );
    my $result = $a->on_function_call('submit_survey_answer', { question_id => 'q1', answer => '5' }, {});
    ok(defined $result, 'returns result');
    like($result->response, qr/q1/, 'response mentions question id');
};

subtest 'render_swml' => sub {
    my $a = SignalWire::Prefabs::Survey->new(
        survey_name      => 'S',
        questions => [{ id => 'q1', text => 'Q?', type => 'rating', scale => 5, required => 1 }],
    );
    my $swml = $a->render_swml;
    is($swml->{version}, '1.0.0', 'version');
};

subtest 'custom introduction' => sub {
    my $a = SignalWire::Prefabs::Survey->new(
        survey_name      => 'S',
        questions => [{ id => 'q1', text => 'Q?', type => 'rating', scale => 5, required => 1 }],
        introduction     => 'Welcome to our custom survey!',
    );
    # The prompt section body should contain the custom intro
    my $pom = $a->pom_sections;
    my ($intro_sec) = grep { $_->{title} eq 'Survey Introduction' } @$pom;
    like($intro_sec->{body}, qr/custom survey/, 'custom introduction in prompt');
};

done_testing;
