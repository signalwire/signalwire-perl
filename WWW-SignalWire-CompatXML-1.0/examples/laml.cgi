#!/usr/bin/env perl
use Data::Dumper;
use SignalWire::CompatXML;
use CGI;

my $q = new CGI;
my $sw = new SignalWire::CompatXML;

print $q->header("text/xml");

$sw->Response
    ->Connect
    ->AI({postPromptURL => "https://briankwest.ngrok.io/public/post.cgi"})
    ->Prompt("Your name is Olivia, You are a cable internet technical support agent, Start the conversation with how may I help you and then talk the customer thru troubleshooting")->parent
    ->postPrompt("Summarize the conversation")->parent
    ->Languages
    ->Language({name => "English", code => "en-US", voice => "en-GB-Neural2-F"})->parent->parent
    ->SWAIG->Defaults({webHookURL => "https://briankwest.ngrok.io/public/swaig.cgi"})->parent
    ->Function({name => "get_weather", purpose => "To determine what the current weather is in a provided location.",
		argument=>"The location or name of the city to get the weather from."})
    ->metavar1("Value1")->parent->parent
    ->Function({name => "get_world_time", purpose => "Get the time in a specific location", argument => "The name of the city to check the time"});

print $sw->to_string;
