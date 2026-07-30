#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# SignalWire::Core::Random is the SDK's single entropy source. This suite is
# deliberately PLATFORM-NEUTRAL: it asserts properties of the helper (exact byte
# count, successive calls differ, no weak fallback) rather than the presence of
# any particular device file. A test that reads /dev/urandom to prove the CSPRNG
# works would pass on POSIX and prove nothing about the platform the bug was on
# — Windows has no such device, which is the whole reason this module exists.

use SignalWire::Core::Random ();

subtest 'Crypt::URandom is a hard runtime dependency (no optional fallback)' => sub {

    # If this fails, the cpanfile `requires` is not being honoured on this
    # platform. That MUST be a loud failure: the SDK has no weaker path to
    # silently fall back to, by design.
    ok( $INC{'Crypt/URandom.pm'}, 'Crypt::URandom loaded by SignalWire::Core::Random' );
};

subtest '_random_bytes returns EXACTLY the requested byte count' => sub {

    # 1 and 16 are real call sizes (UUIDs); 32 is the session-key/password size.
    for my $n ( 1, 8, 15, 16, 32, 64, 257 ) {
        my $bytes = SignalWire::Core::Random::_random_bytes($n);
        is( length($bytes), $n, "_random_bytes($n) returned exactly $n bytes" );
    }
};

subtest '_random_bytes: two successive calls differ' => sub {

    # A 32-byte collision has probability 2**-256; a repeat here means the
    # source is not random (e.g. a constant, or an unseeded/degraded PRNG).
    my $a = SignalWire::Core::Random::_random_bytes(32);
    my $b = SignalWire::Core::Random::_random_bytes(32);
    isnt( unpack( 'H*', $a ), unpack( 'H*', $b ), 'two 32-byte draws differ' );

    # And across many draws there are no duplicates at all.
    my %seen;
    $seen{ unpack 'H*', SignalWire::Core::Random::_random_bytes(16) }++ for 1 .. 200;
    is( scalar keys %seen, 200, '200 successive 16-byte draws are all distinct' );
};

subtest '_random_bytes rejects a bad count rather than guessing' => sub {
    for my $bad ( 0, -1, undef, '', 'abc', '4.5' ) {
        my $label = defined $bad ? "'$bad'" : 'undef';
        my $ok    = eval { SignalWire::Core::Random::_random_bytes($bad); 1 };
        ok( !$ok, "_random_bytes($label) dies" );
    }
};

subtest '_random_hex: 2*n lowercase hex chars, distinct across calls' => sub {
    for my $n ( 1, 16, 32 ) {
        my $hex = SignalWire::Core::Random::_random_hex($n);
        is( length($hex), $n * 2, "_random_hex($n) is " . ( $n * 2 ) . ' chars' );
        like( $hex, qr/\A[0-9a-f]+\z/, "_random_hex($n) is lowercase hex" );
    }
    isnt(
        SignalWire::Core::Random::_random_hex(32),
        SignalWire::Core::Random::_random_hex(32),
        'two _random_hex(32) draws differ'
    );
};

subtest '_random_urlsafe: URL-safe, unpadded, distinct across calls' => sub {
    for my $n ( 1, 16, 32 ) {
        my $tok = SignalWire::Core::Random::_random_urlsafe($n);
        like( $tok, qr{\A[A-Za-z0-9_-]+\z}, "_random_urlsafe($n) uses only the URL-safe alphabet" );
        unlike( $tok, qr/=/, "_random_urlsafe($n) is unpadded" );
    }
    isnt(
        SignalWire::Core::Random::_random_urlsafe(16),
        SignalWire::Core::Random::_random_urlsafe(16),
        'two _random_urlsafe(16) draws differ'
    );
};

subtest '_random_uuid4: RFC 4122 v4 shape, distinct across calls' => sub {
    my $uuid = SignalWire::Core::Random::_random_uuid4();
    like(
        $uuid,
        qr/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/,
        'version nibble is 4 and variant nibble is 8/9/a/b'
    );
    my %seen;
    $seen{ SignalWire::Core::Random::_random_uuid4() }++ for 1 .. 200;
    is( scalar keys %seen, 200, '200 successive UUIDs are all distinct' );
};

subtest 'every consumer draws through the shared helper' => sub {

    # The point of the refactor: entropy sourcing lives in ONE place. Each of
    # these was previously its own open('/dev/urandom') or rand() loop.
    require SignalWire::Security::SessionManager;
    require SignalWire::Core::SecurityConfig;
    require SignalWire::Agent::AgentBase;
    require SignalWire::SWML::Service;
    require SignalWire::Relay::Call;
    require SignalWire::Relay::Client;

    is( length( SignalWire::Security::SessionManager::_random_hex(32) ),
        64, 'SessionManager::_random_hex(32)' );
    like( SignalWire::Security::SessionManager::_random_urlsafe(16),
        qr{\A[A-Za-z0-9_-]+\z}, 'SessionManager::_random_urlsafe(16)' );
    like( SignalWire::Core::SecurityConfig::_token_urlsafe(32),
        qr{\A[A-Za-z0-9_-]+\z}, 'SecurityConfig::_token_urlsafe(32)' );
    is( length( SignalWire::SWML::Service::_random_hex(32) ), 64,
        'SWML::Service::_random_hex(32)' );
    is( length( SignalWire::Agent::AgentBase::_generate_random_password() ),
        64, 'AgentBase::_generate_random_password' );

    my $v4 = qr/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/;
    like( SignalWire::Agent::AgentBase::_generate_uuid4(), $v4, 'AgentBase::_generate_uuid4' );
    like( SignalWire::Relay::Call::_generate_uuid(),       $v4, 'Relay::Call::_generate_uuid' );
    like( SignalWire::Relay::Client::_generate_uuid(),     $v4, 'Relay::Client::_generate_uuid' );
};

subtest 'no consumer reads a POSIX device path or calls rand()' => sub {

    # The regression guard for the actual defect. Grepping the shipped source is
    # the only check that stays valid on a platform where the device is absent —
    # a behavioral test cannot distinguish "used the CSPRNG" from "used rand()".
    my @files = qw(
        lib/SignalWire/Core/Random.pm
        lib/SignalWire/Core/SecurityConfig.pm
        lib/SignalWire/Security/SessionManager.pm
        lib/SignalWire/SWML/Service.pm
        lib/SignalWire/Agent/AgentBase.pm
        lib/SignalWire/Relay/Call.pm
        lib/SignalWire/Relay/Client.pm
    );

    for my $f (@files) {
        open my $fh, '<', $f or do { fail("open $f: $!"); next };
        my @bad;
        my $lineno = 0;
        while ( my $line = <$fh> ) {
            $lineno++;

            # Skip comments and POD prose — Random.pm documents the old defect.
            next if $line =~ /^\s*#/;
            push @bad, "$lineno: $line" if $line =~ m{['"]/dev/urandom['"]};
            push @bad, "$lineno: $line" if $line =~ /\brand\s*\(?\s*256/;
        }
        close $fh;
        is( scalar @bad, 0, "$f: no /dev/urandom open, no rand(256)" )
            or diag( join '', @bad );
    }
};

done_testing();
