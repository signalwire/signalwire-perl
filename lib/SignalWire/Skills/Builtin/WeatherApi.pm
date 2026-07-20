package SignalWire::Skills::Builtin::WeatherApi;
use strict;
use warnings;
use Moo;
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill( 'weather_api', __PACKAGE__ );

has '+skill_name' => ( default => sub { 'weather_api' } );
has '+skill_description' =>
    ( default => sub { 'Get current weather information from WeatherAPI.com' } );
has '+supports_multiple_instances' => ( default => sub { 0 } );

sub setup { return 1 }

# Python parity: get_tools returns the raw SWAIG tool DEFINITION hash(es)
# (the DataMap tool the skill provides). register_tools builds on top of
# this by registering each returned tool with the agent.
sub get_tools {
    my ($self)    = @_;
    my $tool_name = $self->params->{tool_name}        // 'get_weather';
    my $api_key   = $self->params->{api_key}          // '';
    my $unit      = $self->params->{temperature_unit} // 'fahrenheit';

    my $temp_field  = $unit eq 'celsius' ? 'temp_c'      : 'temp_f';
    my $feels_field = $unit eq 'celsius' ? 'feelslike_c' : 'feelslike_f';
    my $unit_label  = $unit eq 'celsius' ? 'C'           : 'F';

    # Honor WEATHER_API_BASE_URL env var so the audit fixture
    # (audit_skills_dispatch.py) can redirect us at a local HTTP server.
    # When unset we use the canonical
    # https://api.weatherapi.com/v1/current.json URL. Either way the
    # `current.json` path component is preserved (the audit's
    # expected_path_substring is `current.json`).
    my $base = $ENV{WEATHER_API_BASE_URL};
    my $url;
    if ($base) {
        $base =~ s{/+$}{};
        $url = "$base/v1/current.json?key=${api_key}&q=\${lc:enc:args.location}&aqi=no";
    } else {
        $url =
"https://api.weatherapi.com/v1/current.json?key=${api_key}&q=\${lc:enc:args.location}&aqi=no";
    }

    return [
        {
            function    => $tool_name,
            description => 'Get current weather information for any location',
            parameters  => {
                type       => 'object',
                properties => {
                    location => { type => 'string', description => 'Location to get weather for' },
                },
                required => ['location'],
            },
            data_map => {
                webhooks => [
                    {
                        method => 'GET',
                        url    => $url,
                        output => {
                            response => "Temperature: \${current.${temp_field}}${unit_label}, "
                                . "Feels like: \${current.${feels_field}}${unit_label}, "
                                . "Condition: \${current.condition.text}, "
                                . "Humidity: \${current.humidity}%, "
                                . "Wind: \${current.wind_mph} mph",
                        },
                    }
                ],
            },
        }
    ];
}

sub register_tools {
    my ($self) = @_;
    my $result;
    for my $tool ( @{ $self->get_tools } ) {
        $result = $self->agent->register_swaig_function($tool);
    }
    return $result;
}

sub get_parameter_schema {
    return {
        %{ SignalWire::Skills::SkillBase->get_parameter_schema },
        api_key          => { type => 'string', required => 1, hidden => 1 },
        tool_name        => { type => 'string', default  => 'get_weather' },
        temperature_unit =>
            { type => 'string', enum => [ 'fahrenheit', 'celsius' ], default => 'fahrenheit' },
    };
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::Builtin::WeatherApi - current-weather skill backed by WeatherAPI.com

=head1 SYNOPSIS

    $agent->add_skill('weather_api', { api_key => $WEATHERAPI_KEY });

    # Optionally rename the tool or switch units:
    $agent->add_skill('weather_api', {
        api_key          => $WEATHERAPI_KEY,
        tool_name        => 'get_weather',
        temperature_unit => 'celsius',
    });

=head1 DESCRIPTION

L<SignalWire::Skills::Builtin::WeatherApi> is the Perl port of the Python
reference C<signalwire.skills.weather_api.skill>. It registers a single
DataMap-based SWAIG tool (default name C<get_weather>) that returns current
weather for a C<location> from WeatherAPI.com.

Being DataMap-based, the SignalWire SWML platform fetches the webhook
(C<https://api.weatherapi.com/v1/current.json>) and renders the response
template. The C<temperature_unit> param (C<fahrenheit> or C<celsius>) selects the
temperature fields and unit label. The skill does not support multiple instances.

=head1 METHODS

=over

=item C<get_tools>

Returns an arrayref of the raw SWAIG tool-definition hash(es) this skill provides
(the weather DataMap tool), honoring C<tool_name>, C<api_key>, and
C<temperature_unit>.

=item C<register_tools>

Registers each tool from C<get_tools> with the agent.

=item C<setup>

Instance setup hook; returns true.

=item C<get_parameter_schema>

Returns the configuration schema: C<api_key> (required), C<tool_name>, and
C<temperature_unit>.

=back

=head1 SEE ALSO

L<SignalWire::Skills::SkillBase>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
