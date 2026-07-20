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
# same contract as the Python reference (rest/client.py raises ValueError with a
# message naming the three SIGNALWIRE_* env vars).
sub BUILD {
    my ($self) = @_;
    unless ( length( $self->_project_id // '' )
        && length( $self->token // '' )
        && length( $self->host  // '' ) )
    {
        die "project, token, and host are required. Provide them as arguments or "
            . "set SIGNALWIRE_PROJECT_ID, SIGNALWIRE_API_TOKEN, and SIGNALWIRE_SPACE "
            . "environment variables.\n";
    }
    return;
}

# The HTTP client the whole resource tree shares. Declared BEFORE composing the
# ResourceTree role below, because the role `requires '_http'` and Moo checks that
# requirement at `with`-time.
has '_http' => ( is => 'lazy' );

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
    return SignalWire::REST::HttpClient->new(
        project         => $self->_project_id,
        token           => $self->token,
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

L<SignalWire::REST::RestClient> is the Perl port of
C<signalwire.rest.client.RestClient>. It is the entry point for the
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
(C<SIGNALWIRE_PROJECT_ID>, C<SIGNALWIRE_API_TOKEN>, C<SIGNALWIRE_SPACE>)
when the corresponding constructor argument is omitted, matching the
Python reference. The constructor dies if any of the three is neither
passed nor present in the environment.

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
