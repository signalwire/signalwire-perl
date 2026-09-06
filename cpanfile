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

# WebSocket for RELAY
requires 'Protocol::WebSocket', '0.26';

# Testing
on 'test' => sub {
    requires 'Test::More', '1.302225';
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
