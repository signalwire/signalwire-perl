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
        project => $self->_project_id,
        token   => $self->token,
        host    => $self->host,
    );
}

1;
