#!/usr/bin/env perl
# $client->space — the Space Administration API — against the live mock server.
#
# The server serves /api/space only to a user's Personal Access Token: HTTP Basic
# with an EMPTY username and the PAT as the password. The mock enforces the same
# credential on every `space` route, so each test here proves the SDK sent it.
#
# Also covers the wire shapes only this namespace has: a text/csv success
# (billing_statement.csv), a success that IS a redirect (billing_statement.pdf ->
# 302 to the statement's URL), and a required request header (the top-up
# Idempotency-Key). Mirrors the python reference tests/unit/rest/test_space_mock.py.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MIME::Base64 qw(decode_base64);
use MockTest;
use SignalWire::REST::RestClient;

sub decoded_auth {
    my ($entry) = @_;
    my $value = $entry->{headers}{authorization} // '';
    like( $value, qr/^Basic /, 'Basic auth' );
    ( my $b64 = $value ) =~ s/^Basic //;
    return decode_base64($b64);
}

subtest 'space request carries the PAT with an empty username' => sub {
    my $client = MockTest::client();
    $client->space->members->list;
    my $last = MockTest::journal_last();
    is( $last->{path},            '/api/space/members', 'path' );
    is( $last->{matched_route},   'space.list_members', 'matched_route' );
    is( $last->{response_status}, 200,                  'status 200' );
    my ( $user, $password ) = split /:/, decoded_auth($last), 2;
    is( $user, '', 'empty username' );
    like( $password, qr/^pat_/, 'password is the PAT' );
};

subtest 'project resources keep the project credential' => sub {
    my $client = MockTest::client();
    $client->fabric->addresses->list;
    my ($user) = split /:/, decoded_auth( MockTest::journal_last() ), 2;
    is( $user, $MockTest::PROJECT, 'project credential' );
};

subtest 'space error surfaces as a REST error' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set( 'space.get_space', 401, { message => 'Unauthorized' } );
    my $ok = eval { $client->space->settings->get; 1 };
    ok( !$ok, 'raised' );
    isa_ok( $@, 'SignalWireRestError' );
    is( $@->status_code,                           401,               'status 401' );
    is( MockTest::journal_last()->{matched_route}, 'space.get_space', 'matched_route' );
};

subtest 'member invite body' => sub {
    my $client = MockTest::client();
    $client->space->members->create(
        email => 'ada@example.com',
        role  => 'admin',
        name  => 'Ada Lovelace',
    );
    my $last = MockTest::journal_last();
    is( $last->{method}, 'POST',               'POST' );
    is( $last->{path},   '/api/space/members', 'path' );
    is_deeply( $last->{body},
        { email => 'ada@example.com', role => 'admin', name => 'Ada Lovelace' }, 'body' );
};

subtest 'billing statement csv returns the text' => sub {
    my $client = MockTest::client();
    my $body   = $client->space->billing_statements->get_csv( month => '2026-08' );
    ok( defined $body && !ref $body && length $body, 'non-empty text body' );
    my $last = MockTest::journal_last();
    is( $last->{path}, '/api/space/billing_statement.csv', 'path' );
    is_deeply( $last->{query_params}{month}, ['2026-08'], 'month query' );
    is( $last->{headers}{accept}, 'text/csv', 'Accept text/csv' );
};

subtest 'billing statement pdf returns the redirect location' => sub {
    my $client = MockTest::client();
    my $url    = $client->space->billing_statements->get_pdf( month => '2026-08' );
    like( $url, qr{^https://}, 'Location URL returned' );
    my $last = MockTest::journal_last();
    is( $last->{path},            '/api/space/billing_statement.pdf', 'path' );
    is( $last->{response_status}, 302,                                'status 302 (not followed)' );
};

subtest 'billing statement pdf success that is not a redirect raises' => sub {
    my $client = MockTest::client();
    MockTest::scenario_set( 'space.get_billing_statement_pdf', 200, { not => 'a redirect' } );
    my $ok = eval { $client->space->billing_statements->get_pdf( month => '2026-08' ); 1 };
    ok( !$ok, 'raised' );
    isa_ok( $@, 'SignalWireRestError' );
    is( $@->status_code, 200, 'status 200' );
};

subtest 'top-up sends the Idempotency-Key header' => sub {
    my $client = MockTest::client();
    $client->space->balance->create_top_up(
        idempotency_key        => 'key-123',
        amount_in_microdollars => 10_000_000,
        payment_method_id      => '00000000-0000-4000-8000-000000000000',
    );
    my $last = MockTest::journal_last();
    is( $last->{method},                     'POST',                       'POST' );
    is( $last->{path},                       '/api/space/balance/top_ups', 'path' );
    is( $last->{headers}{'idempotency-key'}, 'key-123', 'Idempotency-Key header' );
    is_deeply(
        $last->{body},
        {
            amount_in_microdollars => 10_000_000,
            payment_method_id      => '00000000-0000-4000-8000-000000000000',
        },
        'header arg is not sent in the body'
    );
};

subtest 'member project enable' => sub {
    my $client = MockTest::client();
    $client->space->members->enable_project( 'm-1', 'p-1' );
    my $last = MockTest::journal_last();
    is( $last->{method},        'PUT',                                 'PUT' );
    is( $last->{path},          '/api/space/members/m-1/projects/p-1', 'path' );
    is( $last->{matched_route}, 'space.enable_member_project',         'matched_route' );
};

subtest 'recording download returns the redirect location' => sub {
    my $client = MockTest::client();
    my $url    = $client->recordings->download('rec-1');
    ok( defined $url && length $url, 'Location URL returned' );
    my $last = MockTest::journal_last();
    is( $last->{path},            '/api/relay/rest/recordings/rec-1.mp3', 'format-suffixed path' );
    is( $last->{response_status}, 302, 'status 302 (not followed)' );
};

subtest 'client construction' => sub {
    local $ENV{SIGNALWIRE_PROJECT_ID};
    local $ENV{SIGNALWIRE_API_TOKEN};
    local $ENV{SIGNALWIRE_PERSONAL_ACCESS_TOKEN};
    local $ENV{SIGNALWIRE_SPACE};
    delete @ENV{
        qw(SIGNALWIRE_PROJECT_ID SIGNALWIRE_API_TOKEN
            SIGNALWIRE_PERSONAL_ACCESS_TOKEN SIGNALWIRE_SPACE)
    };

    my $pat_only = SignalWire::REST::RestClient->new(
        personal_access_token => 'pat_x',
        host                  => 'example.signalwire.com',
    );
    isa_ok( $pat_only->space->members, 'SignalWire::REST::Namespaces::Generated::SpaceMembers' );
    my $ok = eval { $pat_only->fabric->addresses->list; 1 };
    ok( !$ok, 'PAT-only client refuses a project resource' );
    like( $@, qr/project and token are required/, 'names the missing credential' );

    my $project_only = SignalWire::REST::RestClient->new(
        project => 'p',
        token   => 't',
        host    => 'example.signalwire.com',
    );
    $ok = eval { $project_only->space->members->list; 1 };
    ok( !$ok, 'project-only client refuses space' );
    like( $@, qr/personal_access_token is required/, 'names the missing credential' );

    local $ENV{SIGNALWIRE_PERSONAL_ACCESS_TOKEN} = 'pat_env';
    local $ENV{SIGNALWIRE_SPACE}                 = 'example.signalwire.com';
    my $from_env = SignalWire::REST::RestClient->new;
    is( $from_env->personal_access_token, 'pat_env', 'PAT from the environment' );
    is( $from_env->_pat_http->project,    '',        'PAT client has an empty username' );
    is( $from_env->_pat_http->token,      'pat_env', 'PAT client password is the PAT' );

    delete $ENV{SIGNALWIRE_PERSONAL_ACCESS_TOKEN};
    $ok = eval { SignalWire::REST::RestClient->new( host => 'example.signalwire.com' ); 1 };
    ok( !$ok, 'no credential at all still dies' );
    like( $@, qr/project, token, and host are required/, 'message' );
};

done_testing();
