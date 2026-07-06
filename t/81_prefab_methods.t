#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use_ok('SignalWire::Prefabs::Concierge');
use_ok('SignalWire::Prefabs::FAQBot');
use_ok('SignalWire::Prefabs::InfoGatherer');
use_ok('SignalWire::Prefabs::Receptionist');
use_ok('SignalWire::Prefabs::Survey');

# ---------------------------------------------------------------------------
# Concierge: check_availability / get_directions / on_summary
# ---------------------------------------------------------------------------
subtest 'Concierge check_availability' => sub {
    my $a = SignalWire::Prefabs::Concierge->new(
        venue_name => 'Grand Hotel',
        services   => [ 'spa', 'room service' ],
        amenities  => { pool => { location => '2nd Floor' } },
    );

    my $ok = $a->check_availability( { service => 'spa', date => 'Mon', time => '3pm' } );
    like( $ok->response, qr/Yes, spa is available on Mon at 3pm/, 'available service confirmed' );
    like( $ok->response, qr/reservation/, 'offers reservation' );

    my $no = $a->check_availability( { service => 'helicopter' } );
    like( $no->response, qr/we don't offer helicopter/, 'unavailable service rejected' );
    like( $no->response, qr/spa, room service/,         'lists available services' );
};

subtest 'Concierge get_directions' => sub {
    my $a = SignalWire::Prefabs::Concierge->new(
        venue_name => 'Hotel',
        services   => [],
        amenities  => { Pool => { location => '2nd Floor' }, gym => {} },
    );

    my $r = $a->get_directions( { location => 'pool' } );    # case-insensitive
    like( $r->response, qr/pool is located at 2nd Floor/, 'known amenity directions' );
    like( $r->response, qr/follow the signs to 2nd Floor/, 'entrance guidance' );

    my $g = $a->get_directions( { location => 'gym' } );     # no location detail
    like( $g->response, qr/don't have specific directions to gym/, 'no-location amenity' );

    my $u = $a->get_directions( { location => 'roof' } );    # unknown
    like( $u->response, qr/front desk/, 'unknown location -> front desk' );
};

subtest 'Concierge on_summary' => sub {
    my $a = SignalWire::Prefabs::Concierge->new(
        venue_name => 'Hotel', services => [], amenities => {} );
    is( $a->on_summary(undef), undef, 'nil summary is a no-op' );

    my $out = '';
    {
        local *STDOUT;
        open STDOUT, '>', \$out or die;
        $a->on_summary( { foo => 'bar' } );
    }
    like( $out, qr/Concierge interaction summary/, 'hash summary logged' );
    like( $out, qr/"foo"/,                         'summary JSON contents' );
};

# ---------------------------------------------------------------------------
# FAQBot: search_faqs / on_summary
# ---------------------------------------------------------------------------
subtest 'FAQBot search_faqs' => sub {
    my $a = SignalWire::Prefabs::FAQBot->new(
        faqs => [
            { question => 'What is SignalWire?', answer => 'A comms platform.' },
            { question => 'How do I sign up?',   answer => 'Visit the site.' },
        ],
    );

    my $hit = $a->search_faqs( { query => 'signalwire' } );
    is( $hit->response, 'A comms platform.', 'keyword match returns answer' );

    my $miss = $a->search_faqs( { query => 'unrelated topic xyz' } );
    like( $miss->response, qr/don't have a specific answer/,  'no match message' );
    like( $miss->response, qr/What is SignalWire\?/,          'lists known topics' );
};

subtest 'FAQBot on_summary' => sub {
    my $a = SignalWire::Prefabs::FAQBot->new( faqs => [ { question => 'q', answer => 'a' } ] );
    is( $a->on_summary(undef), undef, 'nil summary no-op' );
    my $out = '';
    {
        local *STDOUT;
        open STDOUT, '>', \$out or die;
        $a->on_summary('plain text');
    }
    like( $out, qr/FAQ interaction summary: plain text/, 'string summary logged' );
};

# ---------------------------------------------------------------------------
# InfoGatherer: start_questions / submit_answer / set_question_callback /
# on_swml_request
# ---------------------------------------------------------------------------
subtest 'InfoGatherer static mode' => sub {
    my $a = SignalWire::Prefabs::InfoGatherer->new(
        questions => [
            { key_name => 'full_name', question_text => 'What is your full name?' },
            { key_name => 'email',     question_text => 'Email?' },
        ],
    );

    my $sq = $a->start_questions( {} );
    like( $sq->response, qr/\[Question 1 of 2\]/,          'question index shown' );
    like( $sq->response, qr/What is your full name\?/,     'first question text' );

    # submit_answer is a state machine: at index 0 of 2 questions it records the
    # answer, advances the index, and presents the 2nd question (with the answer
    # recorded via a set_global_data action, not echoed back in the text).
    my $sa = $a->submit_answer( { answer => 'Jane Doe' } );
    like( $sa->response, qr/\[Question 2 of 2\]/, 'advances to the 2nd question' );
    like( $sa->response, qr/Email\?/,             '2nd question text presented' );
    my ($upd) = grep { exists $_->{set_global_data} } @{ $sa->action };
    ok( defined $upd, 'answer recorded via a set_global_data action' );
    is( $upd->{set_global_data}{question_index}, 1, 'question_index advanced' );
    is_deeply(
        $upd->{set_global_data}{answers},
        [ { key_name => 'full_name', answer => 'Jane Doe' } ],
        'answer stored under its key_name',
    );

    # static mode -> on_swml_request is a no-op
    is( $a->on_swml_request( {}, undef ), undef, 'static mode on_swml_request no-op' );
};

subtest 'InfoGatherer start_questions with no questions' => sub {
    my $a = SignalWire::Prefabs::InfoGatherer->new( questions => [] );
    my $r = $a->start_questions( {} );
    like( $r->response, qr/don't have any questions/, 'empty question set message' );
};

subtest 'InfoGatherer dynamic mode + callback' => sub {
    my $a = SignalWire::Prefabs::InfoGatherer->new( questions => [] );
    is( $a->static_questions, undef, 'no static questions -> dynamic mode' );

    # No callback -> fallback questions
    my $fb = $a->on_swml_request( {}, undef );
    is( ref $fb, 'HASH', 'returns global_data hashref' );
    is( $fb->{global_data}{questions}[0]{key_name}, 'name', 'fallback question 1' );
    is( $fb->{global_data}{question_index},         0,      'index reset' );

    # Register a callback
    my $ret = $a->set_question_callback(
        sub {
            my ( $query, $body, $headers ) = @_;
            return [ { key_name => 'color', question_text => 'Favorite color?' } ];
        }
    );
    is( $ret, $a, 'set_question_callback returns self (chainable)' );

    my $dyn = $a->on_swml_request( { some => 'body' }, undef );
    is( $dyn->{global_data}{questions}[0]{key_name}, 'color', 'dynamic question used' );

    # Callback that returns junk -> fallback
    $a->set_question_callback( sub { return undef } );
    my $bad = $a->on_swml_request( {}, undef );
    is( $bad->{global_data}{questions}[0]{key_name}, 'name', 'bad callback falls back' );
};

# ---------------------------------------------------------------------------
# Receptionist: on_summary (no-op)
# ---------------------------------------------------------------------------
subtest 'Receptionist on_summary no-op' => sub {
    my $a = SignalWire::Prefabs::Receptionist->new(
        departments => [ { name => 'sales', number => '+15551235555' } ] );
    is( $a->on_summary( { anything => 1 } ), undef, 'no-op returns undef' );
};

# ---------------------------------------------------------------------------
# Survey: validate_response / log_response / on_summary
# ---------------------------------------------------------------------------
subtest 'Survey validate_response' => sub {
    my $a = SignalWire::Prefabs::Survey->new(
        survey_name      => 'CSAT',
        survey_questions => [
            { id => 'rate',   text => 'Rate us',    type => 'rating',          scale => 5 },
            { id => 'pick',   text => 'Pick one',   type => 'multiple_choice', options => [ 'a', 'b' ] },
            { id => 'yn',     text => 'Agree?',     type => 'yes_no' },
            { id => 'open',   text => 'Comments',   type => 'open_ended' },
        ],
    );

    like( $a->validate_response( { question_id => 'nope', response => 'x' } )->response,
        qr/not found/, 'unknown question id' );

    is( $a->validate_response( { question_id => 'rate', response => '3' } )->response,
        "Response to 'rate' is valid.", 'valid rating' );
    like( $a->validate_response( { question_id => 'rate', response => '9' } )->response,
        qr/between 1 and 5/, 'out-of-range rating' );
    like( $a->validate_response( { question_id => 'rate', response => 'abc' } )->response,
        qr/between 1 and 5/, 'non-numeric rating' );

    is( $a->validate_response( { question_id => 'pick', response => 'A' } )->response,
        "Response to 'pick' is valid.", 'valid multiple choice (case-insensitive)' );
    like( $a->validate_response( { question_id => 'pick', response => 'z' } )->response,
        qr/select one of: a, b/, 'invalid multiple choice' );

    is( $a->validate_response( { question_id => 'yn', response => 'YES' } )->response,
        "Response to 'yn' is valid.", 'valid yes/no' );
    like( $a->validate_response( { question_id => 'yn', response => 'maybe' } )->response,
        qr/'yes' or 'no'/, 'invalid yes/no' );

    like( $a->validate_response( { question_id => 'open', response => '  ' } )->response,
        qr/response is required/, 'empty required open-ended' );
};

subtest 'Survey log_response' => sub {
    my $a = SignalWire::Prefabs::Survey->new(
        survey_name      => 'CSAT',
        survey_questions => [ { id => 'q1', text => 'How was it?', type => 'open_ended' } ],
    );
    my $r = $a->log_response( { question_id => 'q1', response => 'great' } );
    is( $r->response, "Response to 'How was it?' has been recorded.", 'logs by question text' );
};

subtest 'Survey on_summary' => sub {
    my $a = SignalWire::Prefabs::Survey->new(
        survey_name => 'CSAT', survey_questions => [ { id => 'q', text => 't', type => 'open_ended' } ] );
    is( $a->on_summary(undef), undef, 'nil summary no-op' );
    my $out = '';
    {
        local *STDOUT;
        open STDOUT, '>', \$out or die;
        $a->on_summary( { score => 5 } );
    }
    like( $out, qr/Survey completed/, 'hash summary logged' );
    like( $out, qr/"score"/,          'summary contents' );
};

done_testing;
