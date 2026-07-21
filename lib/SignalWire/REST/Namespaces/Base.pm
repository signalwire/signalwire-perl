package SignalWire::REST::Namespaces::Base;
use strict;
use warnings;
use Moo;

# Base for all namespace/resource classes.
has '_http'      => ( is => 'ro', required => 1 );
has '_base_path' => ( is => 'ro', required => 1 );

sub _path {
    my ( $self, @parts ) = @_;
    return join( '/', $self->_base_path, @parts );
}

# --- CrudResource ---
package SignalWire::REST::Namespaces::CrudResource;
use Moo;
extends 'SignalWire::REST::Namespaces::Base';

# Subclasses can override: 'PATCH' (default) or 'PUT'
has '_update_method' => ( is => 'ro', default => sub { 'PATCH' } );

# Every CRUD verb accepts a keyword-only request_options (PY-7 parity): it is
# stripped from the slurpy args and threaded to the HttpClient verb, NEVER folded
# into the wire body/query. undef => inherit the client-level default.
sub list {
    my ( $self, %params ) = @_;
    my $request_options = delete $params{request_options};
    my $p               = %params ? \%params : undef;
    return $self->_http->get(
        $self->_base_path,
        params          => $p,
        request_options => $request_options
    );
}

sub create {
    my ( $self, %kwargs ) = @_;
    my $request_options = delete $kwargs{request_options};
    return $self->_http->post(
        $self->_base_path,
        body            => \%kwargs,
        request_options => $request_options
    );
}

sub get {
    my ( $self, $resource_id, %opts ) = @_;
    return $self->_http->get( $self->_path($resource_id),
        request_options => $opts{request_options} );
}

sub update {
    my ( $self, $resource_id, %kwargs ) = @_;
    my $request_options = delete $kwargs{request_options};
    my $method          = lc( $self->_update_method );
    return $self->_http->$method(
        $self->_path($resource_id),
        body            => \%kwargs,
        request_options => $request_options
    );
}

sub delete {
    my ( $self, $resource_id, %opts ) = @_;
    return $self->_http->delete_request( $self->_path($resource_id),
        request_options => $opts{request_options} );
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::REST::Namespaces::Base - base classes for REST resource and namespace objects

=head1 SYNOPSIS

    # A generated resource class extends CrudResource, e.g.:
    #   package SignalWire::REST::Namespaces::Generated::PhoneNumbers;
    #   use Moo;
    #   extends 'SignalWire::REST::Namespaces::CrudResource';

    # inherits list / create / get / update / delete over _base_path

=head1 DESCRIPTION

This file defines two base classes shared by the generated REST resource
tree. They are the Perl analogue of the reference's C<_base> resource
bases; the generated per-resource classes (emitted by
C<scripts/generate_rest.py>) extend them.

=head2 SignalWire::REST::Namespaces::Base

The root base for every namespace and resource object. It holds the shared
L<SignalWire::REST::HttpClient> (C<_http>) and the resource's C<_base_path>,
both required. Its one helper, C<_path(@parts)>, joins the base path with
additional segments (e.g. a resource id) using C</>.

=head2 SignalWire::REST::Namespaces::CrudResource

Extends C<Base> with the standard CRUD verbs over C<_base_path>. The update
HTTP method is C<PATCH> by default; a subclass may set C<_update_method> to
C<'PUT'>.

=over 4

=item list(%params)

GET the collection, passing any C<%params> as query parameters.

=item create(%kwargs)

POST C<%kwargs> as the JSON body to create a resource.

=item get($resource_id)

GET a single resource by id.

=item update($resource_id, %kwargs)

PATCH (or PUT) C<%kwargs> onto the resource identified by C<$resource_id>.

=item delete($resource_id)

DELETE the resource identified by C<$resource_id>.

=back

=head1 SEE ALSO

L<SignalWire::REST::RestClient>, L<SignalWire::REST::HttpClient>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
