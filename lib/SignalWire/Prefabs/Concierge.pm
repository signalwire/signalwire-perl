package SignalWire::Prefabs::Concierge;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.

use strict;
use warnings;
use Moo;
use JSON qw(encode_json);
extends 'SignalWire::Agent::AgentBase';

has venue_name           => ( is => 'ro', required => 1 );
has services             => ( is => 'ro', default  => sub { [] } );
has amenities            => ( is => 'ro', default  => sub { {} } );
has hours_of_operation   => ( is => 'ro', default  => sub { {} } );
has special_instructions => ( is => 'ro', default  => sub { [] } );
has welcome_message      => ( is => 'ro', default  => sub { undef } );

sub BUILD {
    my ( $self, $args ) = @_;

    $self->name('concierge')   if $self->name eq 'agent';
    $self->route('/concierge') if $self->route eq '/';
    $self->use_pom(1);

    my $welcome = $self->welcome_message
        // "Welcome to ${\$self->venue_name}. How can I assist you today?";

    $self->set_global_data(
        {
            venue_name => $self->venue_name,
            services   => $self->services,
            amenities  => $self->amenities,
        }
    );

    $self->prompt_add_section(
        'Concierge Role',
        "You are the virtual concierge for ${\$self->venue_name}. $welcome",
        bullets => [
            'Welcome users and explain available services',
            'Answer questions about amenities, hours, and directions',
            'Help with bookings and reservations',
            'Provide personalized recommendations',
        ],
    );

    # Services
    if ( @{ $self->services } ) {
        $self->prompt_add_section( 'Available Services', '', bullets => $self->services, );
    }

    # Amenities
    if ( %{ $self->amenities } ) {
        my @amenity_bullets;
        for my $name ( sort keys %{ $self->amenities } ) {
            my $info = $self->amenities->{$name};
            my $desc = "$name";
            $desc .= " - Hours: $info->{hours}"       if $info->{hours};
            $desc .= " - Location: $info->{location}" if $info->{location};
            push @amenity_bullets, $desc;
        }
        $self->prompt_add_section( 'Amenities', '', bullets => \@amenity_bullets, );
    }

    # Hours
    if ( %{ $self->hours_of_operation } ) {
        my @hour_bullets;
        for my $day ( sort keys %{ $self->hours_of_operation } ) {
            push @hour_bullets, "$day: $self->{hours_of_operation}{$day}";
        }
        $self->prompt_add_section( 'Hours of Operation', '', bullets => \@hour_bullets, );
    }

    # Special instructions
    if ( @{ $self->special_instructions } ) {
        $self->prompt_add_section( 'Special Instructions',
            '', bullets => $self->special_instructions, );
    }

    # Register check availability tool
    $self->define_tool(
        name        => 'check_availability',
        description => 'Check availability for a service or amenity',
        parameters  => {
            type       => 'object',
            properties => {
                service => { type => 'string', description => 'Service or amenity to check' },
                date    => { type => 'string', description => 'Date to check (optional)' },
            },
            required => ['service'],
        },
        handler => sub {
            my ( $a, $raw ) = @_;
            return $self->check_availability( $a, $raw );
        },
    );

    # Register get_directions tool
    $self->define_tool(
        name        => 'get_directions',
        description => 'Get directions to an amenity or location within the venue',
        parameters  => {
            type       => 'object',
            properties => {
                location => { type => 'string', description => 'Amenity or location name' },
            },
            required => ['location'],
        },
        handler => sub {
            my ( $a, $raw ) = @_;
            return $self->get_directions( $a, $raw );
        },
    );
    return;
}

# Tool: check_availability — Python parity
# (signalwire.prefabs.concierge.ConciergeAgent.check_availability).
#
# Simulated booking lookup: confirms availability when the requested
# service is one of the venue's offered services, otherwise lists the
# available services.
sub check_availability {
    my ( $self, $args, $raw_data ) = @_;
    require SignalWire::SWAIG::FunctionResult;

    my $service  = lc( $args->{service} // '' );
    my @services = @{ $self->services };

    unless ( grep { lc($_) eq $service } @services ) {
        my $list = join( ', ', @services );
        return SignalWire::SWAIG::FunctionResult->new(
            response => "I'm sorry, we don't offer $service at ${\$self->venue_name}. "
                . "Our available services are: $list." );
    }

    my $date = $args->{date} // '';
    my $time = $args->{time} // '';
    return SignalWire::SWAIG::FunctionResult->new(
        response => "Yes, $service is available on $date at $time. "
            . 'Would you like to make a reservation?' );
}

# Tool: get_directions — Python parity
# (signalwire.prefabs.concierge.ConciergeAgent.get_directions).
#
# Returns directions to an amenity when that amenity declares a
# "location" detail, otherwise points the caller at the front desk.
sub get_directions {
    my ( $self, $args, $raw_data ) = @_;
    require SignalWire::SWAIG::FunctionResult;

    my $location  = lc( $args->{location} // '' );
    my $amenities = $self->amenities;

    my ($key) = grep { lc($_) eq $location } keys %$amenities;
    my $info = defined $key ? $amenities->{$key} : undef;

    unless ( ref $info eq 'HASH' && defined $info->{location} ) {
        return SignalWire::SWAIG::FunctionResult->new(
            response => "I don't have specific directions to $location. "
                . 'You can ask our staff at the front desk for assistance.' );
    }

    my $where = $info->{location};
    return SignalWire::SWAIG::FunctionResult->new(
        response => "The $location is located at $where. "
            . "From the main entrance, follow the signs to $where." );
}

# Lifecycle hook: on_summary — Python parity
# (signalwire.prefabs.concierge.ConciergeAgent.on_summary).
#
# Processes the post-prompt interaction summary. Structured (hashref)
# summaries are logged as pretty JSON; anything else is logged as-is.
# Subclasses may override to persist or forward the interaction.
sub on_summary {
    my ( $self, $summary, $raw_data ) = @_;
    return if !defined $summary;

    my $ok = eval {
        if ( ref $summary eq 'HASH' ) {
            print 'Concierge interaction summary: '
                . JSON->new->canonical->pretty->encode($summary);
        } else {
            print "Concierge interaction summary: $summary\n";
        }
        1;
    };
    print "Error processing summary: $@" if !$ok;
    return;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Prefabs::Concierge - ready-made venue concierge AI agent

=head1 SYNOPSIS

    use SignalWire::Prefabs::Concierge;

    my $agent = SignalWire::Prefabs::Concierge->new(
        venue_name         => 'The Grand Hotel',
        services           => [ 'Room service', 'Spa booking', 'Valet parking' ],
        amenities          => {
            Pool => { hours => '6am-10pm', location => '3rd floor' },
            Gym  => { hours => '24/7',     location => 'Basement' },
        },
        hours_of_operation => { 'Front Desk' => '24/7' },
        welcome_message    => 'Welcome to The Grand Hotel.',
    );

    $agent->run;

=head1 DESCRIPTION

L<SignalWire::Prefabs::Concierge> is the Perl port of
C<signalwire.prefabs.concierge.ConciergeAgent>. It is a ready-made
subclass of L<SignalWire::Agent::AgentBase> that acts as a virtual
concierge for a venue: it welcomes callers, explains available services,
answers questions about amenities and hours, and helps with bookings.

C<BUILD> configures the agent from its attributes — it names the agent
C<concierge> and mounts it at C</concierge> (unless overridden), enables
POM prompt sections, seeds global data with the venue details, builds the
prompt sections (role, services, amenities, hours, special instructions),
and registers the C<check_availability> and C<get_directions> SWAIG tools.

=head1 ATTRIBUTES

Constructor attributes (all C<ro>):

=over 4

=item C<venue_name> (required)

The name of the venue, used throughout the prompt and responses.

=item C<services>

Arrayref of service names offered by the venue (default C<[]>).

=item C<amenities>

Hashref of amenity name to a details hashref (C<hours>, C<location>)
(default C<{}>).

=item C<hours_of_operation>

Hashref of day/label to hours string (default C<{}>).

=item C<special_instructions>

Arrayref of extra prompt bullets (default C<[]>).

=item C<welcome_message>

Optional custom welcome line; defaults to a generated greeting.

=back

=head1 METHODS

=over 4

=item C<check_availability($args, $raw_data)>

Tool handler. Confirms availability when the requested service is one the
venue offers, otherwise lists the available services.

=item C<get_directions($args, $raw_data)>

Tool handler. Returns directions to an amenity that declares a C<location>
detail, otherwise points the caller at the front desk.

=item C<on_summary($summary, $raw_data)>

Lifecycle hook. Logs the post-prompt interaction summary; hashref
summaries are emitted as pretty JSON. Override to persist or forward the
interaction.

=back

=head1 SEE ALSO

L<SignalWire::Agent::AgentBase>, L<SignalWire::SWAIG::FunctionResult>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
