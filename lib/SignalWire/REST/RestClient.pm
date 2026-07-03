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
has '_project_id' => ( is => 'ro', required => 1, init_arg => 'project' );
has 'token'       => ( is => 'ro', required => 1 );
has 'host'        => ( is => 'ro', required => 1 );

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
