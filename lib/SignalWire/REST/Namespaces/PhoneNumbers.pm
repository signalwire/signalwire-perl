package SignalWire::REST::Namespaces::PhoneNumbers;
use strict;
use warnings;
use Moo;
extends 'SignalWire::REST::Namespaces::CrudResource';

has '+_update_method' => ( default => sub { 'PUT' } );

sub search {
    my ($self, %params) = @_;
    my $p = %params ? \%params : undef;
    return $self->_http->get($self->_path('search'), params => $p);
}

1;
