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
    requires 'Test::More', '1.302220';
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
    requires 'Perl::Tidy';
    requires 'Perl::Critic';
};
