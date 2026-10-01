package SignalWire::REST::RestClient;
use strict;
use warnings;
use Moo;

use SignalWire::REST::HttpClient;
use SignalWire::REST::Namespaces::Base;

# Auth credentials. The project id is stored privately (`_project_id`) so it does
# not collide with the generated `project` accessor (the ProjectNamespace) that
# the ResourceTree role provides — mirroring the Python reference, which keeps the
# credential on `self._project` and lets the tree own `project`.
#
# Each credential falls back to its SIGNALWIRE_* environment variable when the
# constructor arg is omitted, matching the Python reference (rest/client.py:
# `token or os.environ.get("SIGNALWIRE_API_TOKEN", "")`, likewise SIGNALWIRE_
# PROJECT_ID / SIGNALWIRE_SPACE). This is why those vars are documented as SDK
# knobs — the SDK itself reads them.
has '_project_id' => (
    is       => 'ro',
    init_arg => 'project',
    default  => sub { $ENV{SIGNALWIRE_PROJECT_ID} },
);
has 'token' => (
    is      => 'ro',
    default => sub { $ENV{SIGNALWIRE_API_TOKEN} },
);
has 'host' => (
    is      => 'ro',
    default => sub { $ENV{SIGNALWIRE_SPACE} },
);

# A user's Personal Access Token (`pat_...`). It authenticates `$client->space`
# (the Space Administration API), which the server serves ONLY to a Personal
# Access Token — HTTP Basic with an EMPTY username (prime-rails
# API::Space::BaseController -> Authenticators::PersonalAccessToken). Falls back
# to SIGNALWIRE_PERSONAL_ACCESS_TOKEN. Mirrors the Python reference's
# RestClient(..., personal_access_token=...).
has 'personal_access_token' => (
    is      => 'ro',
    default => sub { $ENV{SIGNALWIRE_PERSONAL_ACCESS_TOKEN} },
);

# Client-default request options (plan 4.2): a SignalWire::REST::RequestOptions
# applied to every request the shared HttpClient issues, shallow-overridden
# per-call by a request_options passed to a verb. undef => the built-in defaults
# (30s timeout, no retries). Mirrors the Python reference's
# RestClient(..., request_options=...).
has 'request_options' => (
    is      => 'ro',
    default => sub { undef },
);

# Fail loud when a credential is neither passed nor present in the environment —
# same contract as the Python reference (rest/client.py raises ValueError). A
# client holds the project credential (project + token), a Personal Access Token,
# or both; host is always required.
sub BUILD {
    my ($self) = @_;
    unless ( length( $self->host // '' )
        && ( $self->_has_project_credential || length( $self->personal_access_token // '' ) ) )
    {
        die "project, token, and host are required. Provide them as arguments or "
            . "set SIGNALWIRE_PROJECT_ID, SIGNALWIRE_API_TOKEN, and SIGNALWIRE_SPACE "
            . "environment variables (or, for client.space only, host and "
            . "personal_access_token / SIGNALWIRE_PERSONAL_ACCESS_TOKEN).\n";
    }
    return;
}

sub _has_project_credential {
    my ($self) = @_;
    return length( $self->_project_id // '' ) && length( $self->token // '' ) ? 1 : 0;
}

# The HTTP clients the resource tree shares: `_http` carries the project token
# (every project-scoped resource), `_pat_http` the Personal Access Token
# (`$client->space`). Declared BEFORE composing the ResourceTree role below,
# because the role `requires` both and Moo checks that at `with`-time. A client
# built without one of the credentials gets a stand-in that dies, naming the
# missing credential, before any request is sent.
has '_http'     => ( init_arg => undef, is => 'lazy' );
has '_pat_http' => ( init_arg => undef, is => 'lazy' );

# The resource object tree (flat resources + namespace containers) is GENERATED
# from the specs: scripts/generate_rest.py emits the per-resource classes, the
# per-namespace containers, and this ResourceTree role. The role provides a lazy
# accessor for every flat resource (phone_numbers, addresses, calling, chat,
# pubsub, …) and every container (fabric, video, logs, registry, project,
# datasphere). This hand class owns ONLY auth + the HTTP client; it composes the
# generated tree via `with`.
use SignalWire::REST::Namespaces::Generated::ResourceTree;
with 'SignalWire::REST::Namespaces::Generated::ResourceTree';

sub _build__http {
    my ($self) = @_;
    return $self->_missing_credential_http( "project and token are required for this resource "
            . "(SIGNALWIRE_PROJECT_ID / SIGNALWIRE_API_TOKEN); this client has only "
            . "a personal access token, which authenticates client.space" )
        unless $self->_has_project_credential;
    return SignalWire::REST::HttpClient->new(
        project         => $self->_project_id,
        token           => $self->token,
        host            => $self->host,
        request_options => $self->request_options,
    );
}

# Stands in for the HTTP client of a credential this client was not given: every
# request dies naming the missing credential, before anything is sent — so a
# PAT-only client fails loudly on a project resource (and a project-only client on
# $client->space) instead of sending a request the server can only refuse.
sub _missing_credential_http {
    my ( $self, $message ) = @_;
    return SignalWire::REST::HttpClient->new(
        project             => '',
        token               => '',
        host                => $self->host,
        _missing_credential => $message,
    );
}

sub _build__pat_http {
    my ($self) = @_;
    my $pat = $self->personal_access_token // '';
    return $self->_missing_credential_http(
        "personal_access_token is required for client.space (SIGNALWIRE_PERSONAL_ACCESS_TOKEN)")
        unless length $pat;

    # A Personal Access Token is HTTP Basic with an EMPTY username.
    return SignalWire::REST::HttpClient->new(
        project         => '',
        token           => $pat,
        host            => $self->host,
        request_options => $self->request_options,
    );
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::REST::RestClient - synchronous SignalWire REST API client

=head1 SYNOPSIS

    use SignalWire::REST::RestClient;

    my $client = SignalWire::REST::RestClient->new(
        project => $ENV{SIGNALWIRE_PROJECT_ID},
        token   => $ENV{SIGNALWIRE_API_TOKEN},
        host    => $ENV{SIGNALWIRE_SPACE},
    );

    # Namespaced resource access (the tree is generated from the specs):
    my $numbers = $client->phone_numbers->list;
    my $agent   = $client->fabric->ai_agents->create(
        name => 'Bot', prompt => { text => '...' },
    );

=head1 DESCRIPTION

L<SignalWire::REST::RestClient> is the entry point for the
synchronous REST API: it holds the project/token/host credentials, owns
the shared L<SignalWire::REST::HttpClient>, and exposes the generated
resource tree (flat resources such as C<phone_numbers> and C<addresses>,
plus namespace containers such as C<fabric>, C<video>, C<logs>,
C<registry>, C<project>, and C<datasphere>).

The resource accessors are provided by the generated
C<SignalWire::REST::Namespaces::Generated::ResourceTree> role, which this
class composes; this hand class owns only authentication and the HTTP
client.

Each credential falls back to its C<SIGNALWIRE_*> environment variable
(C<SIGNALWIRE_PROJECT_ID>, C<SIGNALWIRE_API_TOKEN>, C<SIGNALWIRE_SPACE>,
C<SIGNALWIRE_PERSONAL_ACCESS_TOKEN>) when the corresponding constructor
argument is omitted. C<project> + C<token> authenticate every
project-scoped resource; C<personal_access_token> authenticates
C<< $client->space >> (the Space Administration API). Either credential, or
both, may be given. The constructor dies if C<host> is missing, or if
neither a complete C<project> + C<token> pair nor a
C<personal_access_token> is available; calling a resource whose credential
is missing dies naming that credential, before any request is sent.

    # The Space Administration API authenticates with a user's
    # Personal Access Token instead of a project token:
    my $admin = SignalWire::REST::RestClient->new(
        personal_access_token => 'pat_...',
        host                  => 'your-space.signalwire.com',
    );
    my $members = $admin->space->members->list;

=head1 ATTRIBUTES

=over 4

=item project

The SignalWire project id (stored privately as C<_project_id> so it does
not collide with the generated C<project> namespace accessor). Defaults to
C<$ENV{SIGNALWIRE_PROJECT_ID}>.

=item token

The API token. Defaults to C<$ENV{SIGNALWIRE_API_TOKEN}>.

=item host

The SignalWire space host. Defaults to C<$ENV{SIGNALWIRE_SPACE}>.

=item personal_access_token

A user's Personal Access Token (C<pat_...>), which authenticates
C<< $client->space >>. Defaults to
C<$ENV{SIGNALWIRE_PERSONAL_ACCESS_TOKEN}>.

=item request_options

An optional client-default L<SignalWire::REST::RequestOptions> applied to
every request the shared HTTP client issues, shallow-overridden per call by
a C<request_options> passed to a verb. C<undef> means the built-in defaults
(30s timeout, no retries).

=back

=head1 SEE ALSO

L<SignalWire::REST::HttpClient>, L<SignalWire::REST::RequestOptions>,
L<SignalWire::REST::Namespaces::Base>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
