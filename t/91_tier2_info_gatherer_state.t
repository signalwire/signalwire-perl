#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# =============================================================================
# Behavioral contract #3 — InfoGatherer submit_answer STATE MACHINE.
#
# Python (prefabs/info_gatherer.py): submit_answer reads question_index/answers
# from global_data, STORES the answer, ADVANCES the index, and returns the next
# question (or a completion message). A stub ("Answer recorded" echo, no state)
# fails: the answer is not recorded and the index does not advance.
#
# This test starts with 2 questions at index 0, submits an answer, and asserts:
#   (a) the answer is recorded in global_data.answers (with its key_name),
#   (b) question_index advanced to 1,
#   (c) the result presents the 2nd question.
# =============================================================================

use SignalWire::Prefabs::InfoGatherer;

my $QUESTIONS = [
    { key_name => 'full_name', question_text => 'What is your full name?' },
    { key_name => 'email',     question_text => 'What is your email address?' },
];

# Pull the set_global_data payload out of a FunctionResult's actions.
sub global_update {
    my ($result) = @_;
    my ($action) = grep { exists $_->{set_global_data} } @{ $result->action };
    return $action ? $action->{set_global_data} : undef;
}

subtest 'start_questions presents the first question from state' => sub {
    my $agent = SignalWire::Prefabs::InfoGatherer->new( questions => $QUESTIONS );

    # Seed the live per-call state exactly as the platform would (from the
    # agent's set_global_data at construction).
    my $raw = { global_data => { questions => $QUESTIONS, question_index => 0, answers => [] } };

    my $start = $agent->on_function_call( 'start_questions', {}, $raw );
    like( $start->response, qr/full name/i, 'first question presented' );
    like( $start->response, qr/Question 1 of 2/, 'question 1 of 2 framing' );
};

subtest 'submit_answer records the answer, advances the index, presents Q2' => sub {
    my $agent = SignalWire::Prefabs::InfoGatherer->new( questions => $QUESTIONS );

    my $raw = { global_data => { questions => $QUESTIONS, question_index => 0, answers => [] } };

    my $result = $agent->on_function_call( 'submit_answer', { answer => 'Ada Lovelace' }, $raw );
    ok( defined $result, 'submit_answer returned a FunctionResult' );

    my $gd = global_update($result);
    ok( defined $gd, 'a set_global_data action was emitted (state update, not an echo)' );

    # (a) answer recorded in global_data.answers with its key_name
    is_deeply(
        $gd->{answers},
        [ { key_name => 'full_name', answer => 'Ada Lovelace' } ],
        'answer recorded in global_data.answers with key_name',
    );

    # (b) question_index advanced 0 -> 1
    is( $gd->{question_index}, 1, 'question_index advanced to 1' );

    # (c) the 2nd question is presented
    like( $result->response, qr/email address/i, '2nd question presented in the response' );
    like( $result->response, qr/Question 2 of 2/, 'question 2 of 2 framing' );
};

subtest 'submitting the final answer completes (index past the end)' => sub {
    my $agent = SignalWire::Prefabs::InfoGatherer->new( questions => $QUESTIONS );

    # State after the first answer: index 1, one answer recorded.
    my $raw = {
        global_data => {
            questions      => $QUESTIONS,
            question_index => 1,
            answers        => [ { key_name => 'full_name', answer => 'Ada Lovelace' } ],
        }
    };

    my $result = $agent->on_function_call( 'submit_answer', { answer => 'ada@example.com' }, $raw );
    my $gd = global_update($result);

    is( $gd->{question_index}, 2, 'question_index advanced past the last question' );
    is_deeply(
        $gd->{answers},
        [
            { key_name => 'full_name', answer => 'Ada Lovelace' },
            { key_name => 'email',     answer => 'ada@example.com' },
        ],
        'both answers accumulated in order',
    );
    like( $result->response, qr/all questions have been answered/i, 'completion message' );
};

done_testing;
