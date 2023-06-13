#!/usr/bin/env perl
use strict;
use warnings;
use CGI;
use SignalWire::ML;
use Data::Dumper;

my $q = CGI->new;

my $swml = SignalWire::ML->new({version => '1.0.0', voice => 'en-GB-Neural2-F' });

$swml->set_aiprompt({
    temperature => "0.9",
    top_p => "1.0",
    text => "Your name is Olivia, You are able to lookup weather and time for various locations." });
$swml->set_aipost_prompt({ text => "Summarize the conversation" });

$swml->add_aihints("jokes", "weather", "time");

$swml->set_aipost_prompt_url({ post_prompt_url => $ENV{post_prompt_url} });

$swml->add_aiswaigdefaults({ web_hook_url => "$ENV{web_hook_url}" });

$swml->add_aiinclude({
    url => "https://swml.herokuapp.com/swaig.cgi",
    auth_user => "user",
    auth_password => "pass",
    functions => [ "get_joke", "get_weather", "get_time" ]  });

$swml->add_aiswaigfunction({
    function => 'get_weather',
    purpose => "To determine what the current weather is in a provided location.",
    argument => "The location or name of the city to get the weather from." });

$swml->add_aiswaigfunction({
    function => 'get_time',
    purpose => "To determine what the current time is in a provided location.",
    argument => "The location or name of the city to get the time from." });

$swml->add_aiapplication("main");

print $q->header("application/json");
print $swml->render_json;
