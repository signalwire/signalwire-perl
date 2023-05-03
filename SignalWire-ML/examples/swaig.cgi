#!/usr/bin/env perl
use CGI;
use Data::Dumper;
use JSON;
use URL::Encode qw (url_encode);
use LWP::Simple;

my $q    = new CGI;
my $json = JSON->new->allow_nonref;

print $q->header("application/json");

my %conditions = (
    0  => "Clear skies",
    1  => "Mainly Clear",
    2  => "Partly Cloudy",
    3  => "Overcast Skies",
    45 => "Fog",
    48 => "Depositing Rime Fog",
    51 => "Light Drizzle",
    53 => "Modeate Drizzle",
    55 => "Dense Drizzle",
    56 => "Light Freezing Drizzle",
    57 => "Dense Freezing Drizzle",
    61 => "Slight Rain",
    63 => "Moderate Rain",
    65 => "Dense Rain",
    66 => "Light Freezing Rain",
    67 => "Heavy Freezing Rain",
    71 => "Slight Snow",
    73 => "Moderate Snow",
    75 => "Heavy Snow",
    77 => "Snow Grains",
    80 => "Slight Rain Showers",
    81 => "Moderate Rain Showers",
    82 => "Violent Rain Showers",
    85 => "Slight Snow Showers",
    86 => "Heavy Snow Showers",
    95 => "Thunderstorm",
    96 => "Thunderstorm with Slight Hail",
    99 => "Thunderstorm with Heavy Hail"
);

sub code_to_text {
    my $code = shift;
    return $conditions{$code} ? $conditions{$code} : "Unknown Conditions";
}

my $json_text = $q->param( 'POSTDATA' );
exit unless $json_text;
my $post_data =  $json->decode( $json_text );

if ($post_data->{function} eq "get_weather") {
    my $where = url_encode( $post_data->{argument} );
    my $res = $json->decode( get "https://geocoding-api.open-meteo.com/v1/search?name=$where&count=1&language=en&format=json" );
    my $weather = $json->decode( get "https://api.open-meteo.com/v1/forecast?latitude=$res->{results}->[0]->{latitude}&longitude=$res->{results}->[0]->{longitude}&current_weather=true&temperature_unit=fahrenheit");
    my $des = code_to_text($weather->{current_weather}->{weathercode});

    print $json->pretty->utf8->encode( { response => "$des $weather->{current_weather}->{temperature} degrees." } );
    
} elsif ($post_data->{function} eq "get_world_time") {
    my $where = url_encode($post_data->{argument});
    
    my $jobj =  $json->decode( get "https://api.ipgeolocation.io/timezone?apiKey=$ENV{geoAPIKey}&location=${where}");
    
    print  $json->pretty->utf8->encode( { response => "in $post_data->{argument} the current time is: $jobj->{time_12}" } );
}
