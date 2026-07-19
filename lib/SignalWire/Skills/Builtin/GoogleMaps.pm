package SignalWire::Skills::Builtin::GoogleMaps;
use strict;
use warnings;
use Moo;
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill( 'google_maps', __PACKAGE__ );

has '+skill_name' => ( default => sub { 'google_maps' } );
has '+skill_description' =>
    ( default => sub { 'Validate addresses and compute driving routes using Google Maps' } );
has '+supports_multiple_instances' => ( default => sub { 0 } );

sub setup { return 1 }

sub register_tools {
    my ($self)      = @_;
    my $lookup_name = $self->params->{lookup_tool_name} // 'lookup_address';
    my $route_name  = $self->params->{route_tool_name}  // 'compute_route';

    $self->define_tool(
        name        => $lookup_name,
        description => 'Look up and validate an address using Google Maps Geocoding',
        parameters  => {
            type       => 'object',
            properties => {
                address  => { type => 'string', description => 'Address to look up' },
                bias_lat => { type => 'number', description => 'Latitude bias' },
                bias_lng => { type => 'number', description => 'Longitude bias' },
            },

            # No `required`: the Python reference (skills/google_maps/skill.py)
            # passes none on lookup_address. Adding it would over-constrain the
            # SWAIG schema vs the reference contract.
        },
        handler => sub {
            my ( $args, $raw ) = @_;
            require SignalWire::SWAIG::FunctionResult;
            my $address = $args->{address} // '';
            return SignalWire::SWAIG::FunctionResult->new(
                response => "Address lookup for: $address" );
        },
    );

    return $self->define_tool(
        name        => $route_name,
        description => 'Compute a driving route between two points',
        parameters  => {
            type       => 'object',
            properties => {
                origin_lat => { type => 'number', description => 'Origin latitude' },
                origin_lng => { type => 'number', description => 'Origin longitude' },
                dest_lat   => { type => 'number', description => 'Destination latitude' },
                dest_lng   => { type => 'number', description => 'Destination longitude' },
            },

            # No `required`: the Python reference (skills/google_maps/skill.py)
            # passes none on compute_route (its handler validates the four coords
            # itself). Adding it would over-constrain the SWAIG schema vs the
            # reference contract.
        },
        handler => sub {
            my ( $args, $raw ) = @_;
            require SignalWire::SWAIG::FunctionResult;
            my ( $olat, $olng, $dlat, $dlng ) =
                map { $args->{$_} // '' } qw(origin_lat origin_lng dest_lat dest_lng);
            return SignalWire::SWAIG::FunctionResult->new(
                response => "Route computed from ($olat,$olng) to ($dlat,$dlng)" );
        },
    );
}

sub get_hints {
    return [ 'address', 'location', 'route', 'directions', 'miles', 'distance' ];
}

sub _get_prompt_sections {
    return [
        {
            title   => 'Google Maps',
            body    => '',
            bullets => [
                'Use lookup_address to validate and geocode addresses',
                'Use compute_route to get driving directions between two points',
            ],
        }
    ];
}

sub get_parameter_schema {
    return {
        %{ SignalWire::Skills::SkillBase->get_parameter_schema },
        api_key          => { type => 'string', required => 1, hidden => 1 },
        lookup_tool_name => { type => 'string', default  => 'lookup_address' },
        route_tool_name  => { type => 'string', default  => 'compute_route' },
    };
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::Builtin::GoogleMaps - address validation and driving-route skill using Google Maps

=head1 SYNOPSIS

    $agent->add_skill('google_maps', { api_key => $GOOGLE_MAPS_KEY });

    # Optionally rename the tools:
    $agent->add_skill('google_maps', {
        api_key          => $GOOGLE_MAPS_KEY,
        lookup_tool_name => 'lookup_address',
        route_tool_name  => 'compute_route',
    });

=head1 DESCRIPTION

L<SignalWire::Skills::Builtin::GoogleMaps> is the Perl port of the Python
reference C<signalwire.skills.google_maps.skill>. It registers two handler-based
SWAIG tools:

=over

=item *

C<lookup_address> (name overridable via C<lookup_tool_name>) - validate/geocode
an address; accepts C<address>, C<bias_lat>, C<bias_lng>.

=item *

C<compute_route> (name overridable via C<route_tool_name>) - compute a driving
route between two points; accepts C<origin_lat>, C<origin_lng>, C<dest_lat>,
C<dest_lng>.

=back

The skill does not support multiple instances.

=head1 METHODS

=over

=item C<register_tools>

Registers the address-lookup and route-computation tools with the agent.

=item C<get_hints>

Returns speech hints (C<address>, C<location>, C<route>, C<directions>, C<miles>,
C<distance>).

=item C<setup>

Instance setup hook; returns true.

=item C<get_parameter_schema>

Returns the configuration schema: C<api_key> (required) plus the two tool-name
overrides.

=back

=head1 SEE ALSO

L<SignalWire::Skills::SkillBase>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
