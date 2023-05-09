#!/usr/bin/env perl
use CGI;
use JSON;
use URL::Encode qw (url_encode);
use LWP::Simple;

my $q    = new CGI;
my $json = JSON->new->allow_nonref;

print $q->header("application/json");

my $json_text = $q->param( 'POSTDATA' );

exit unless $json_text;

my $post_data =  $json->pretty->utf8->decode( $json_text );

if ($post_data->{function} eq "get_weather") {
    my $where = url_encode( $post_data->{argument} );

    my $weather = $json->decode(
	get "https://api.weatherapi.com/v1/current.json?key=$ENV{WEATHERAPI}&q=$where&aqi=no");

    print $json->pretty->utf8->encode( {
	response => "$weather->{current}->{condition}->{text} $weather->{current}->{temp_f}F degrees." });

} elsif ($post_data->{function} eq "get_world_time") {
    my $where = url_encode($post_data->{argument});

    my $jobj =  $json->decode(
	get "http://api.weatherapi.com/v1/timezone.json?key=$ENV{WEATHERAPI}&q=$where");

    print $json->pretty->utf8->encode({
	response => "<say-as interpret-as='time' format='hm12'>$jobj->{location}->{localtime}</say-as>" });
}

