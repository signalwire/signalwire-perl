#!/usr/bin/env perl
use strict;
use warnings;
use SignalWire::SWAIG;
use URL::Encode qw (url_encode);                                                                                                          
use LWP::Simple;

my $SWAIG = new SignalWire::SWAIG;

my %dispatch = (
    get_weather => \&get_weather,
    get_time    => \&get_time
);

if (exists $dispatch{$SWAIG->function}) {
    $dispatch{$SWAIG->function}->($SWAIG->argument_parsed);
} else {
    $SWAIG->response("Unknown function $SWAIG->function");
}

sub get_weather {
    my $argument = shift;
    my $json     = $SWAIG->json;
    my $where    = url_encode($argument->{location});
    my $weather  = $json->decode(get "https://api.weatherapi.com/v1/current.json?key=$ENV{WEATHERAPI}&q=$where&aqi=no");
    $SWAIG->response("The weather in $argument->{location} is $weather->{current}->{condition}->{text} and $weather->{current}->{temp_f} degrees Fahrenheit");
}

sub get_time {
    my $argument = shift;
    my $json     = $SWAIG->json;
    my $where    = url_encode($argument->{location});
    my $time     =  $json->decode(get "http://api.weatherapi.com/v1/timezone.json?key=$ENV{WEATHERAPI}&q=$where");
    $SWAIG->response("The time in $argument->{location} is $time->{location}->{localtime}");
}

1;
