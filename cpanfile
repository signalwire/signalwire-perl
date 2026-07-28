requires 'perl', '5.036';

# Core
requires 'Moo', '2.005005';
requires 'JSON', '4.11';
requires 'JSON::PP';
requires 'YAML::PP';
requires 'Tie::IxHash';
requires 'Plack', '1.0054';
requires 'Plack::Request';
requires 'HTTP::Tiny';
requires 'Digest::SHA';
requires 'MIME::Base64';
requires 'IO::Socket::SSL';

# Portable CSPRNG. SignalWire::Core::Random is the SDK's single entropy source
# (session HMAC keys, SWAIG __token material, auto-generated basic-auth
# credentials, RELAY control ids, UUIDs). Crypt::URandom dispatches to the
# platform primitive — getrandom(2) / /dev/urandom on Unix-likes,
# RtlGenRandom / CryptGenRandom on Win32 — so it is a RUNTIME requirement on
# EVERY platform, not a Unix-only convenience. Reading /dev/urandom directly
# (what this SDK previously did) has no Windows equivalent.
requires 'Crypt::URandom', '0.52';

# Win32 ONLY, and load-bearing there. Crypt::URandom reaches the Windows CSPRNG
# through `require Win32::API` at RUNTIME (advapi32 RtlGenRandom /
# CryptGenRandom) but does NOT declare Win32::API as a prereq — verified against
# its CPAN metadata, whose runtime requires are only Carp/English/Exporter/
# FileHandle/constant. So `cpanm --installdeps .` would not pull it in, and the
# SDK's entropy source would die at first use on any Windows Perl that does not
# happen to bundle it. Declaring it here is what makes the dependency actually
# resolve on the Windows CI leg instead of trading /dev/urandom's failure for a
# missing-module failure. Guarded by $^O so the other nine legs never see it.
if ( $^O eq 'MSWin32' ) {
    requires 'Win32::API', '0.84';
}

# WebSocket for RELAY
requires 'Protocol::WebSocket', '0.26';

# Testing
on 'test' => sub {
    requires 'Test::More', '1.302222';
    requires 'Test::Exception';
    requires 'Plack::Test';
    requires 'HTTP::Request::Common';
};

# Developer tooling for the CI quality gates (scripts/run-ci.sh):
#   * Perl::Tidy  — the FMT gate's formatter (.perltidyrc).
# These are author/develop-phase deps, not needed to RUN the SDK. Install with
#   cpanm --installdeps --with-develop .
# (CI installs them so the FMT gate's `perltidy` resolves).
on 'develop' => sub {
    # Perl::Tidy is PINNED: its default vertical-alignment heuristics change
    # between releases (20260705 aligns interior `cmp`/`//` where 20260204 did
    # not), so an unpinned formatter makes the FMT gate non-deterministic —
    # local and CI on different releases disagree on --assert-tidy for the SAME
    # source. Pin so run-format.sh --check is reproducible everywhere. Bump
    # deliberately, then reformat the tree in the same commit.
    requires 'Perl::Tidy', '== 20260705';
    requires 'Perl::Critic';
};
