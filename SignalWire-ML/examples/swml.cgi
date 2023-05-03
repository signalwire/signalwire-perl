#!/usr/bin/env perl
use strict;
use warnings;
use CGI;
use SignalWire::ML;
use Data::Dumper;

my $q = CGI->new;

my $swml = SignalWire::ML->new({version => '1.0.1', voice => 'en-US-Neural2-J' });

$swml->addAIparams({languagesEnabled => 'false'});
$swml->addAIparams({languageMode => 'normal'});

$swml->setAIprompt({
    text => "You are a cable internet technical support agent at Vyve Broadband, Start the conversation with how may I help you and then talk the customer thru troubleshooting, Also for billing questions you can call 855 557 8983"
		   } );
$swml->setAIpostPrompt({
    text => "Summarize the conversation"
		       });
$swml->addAIhints("internet", "cable", "speed");

$swml->setAIpostPromptURL({
    postPromptURL => $ENV{postPromptURL},
    postPromptUser => $ENV{postPromptUser},
    postPromptPassword => $ENV{postPromptPassword}
			  });
$swml->addAISWAIG({function => 'get_weather', purpose => "To determine what the current weather is in a provided location.",
		   arugment => "The location or name of the city to get the weather from.", webHookURL => "$ENV{webHookURL}"
		  });

$swml->addAISWAIG({function => 'get_world_time', purpose => "To determine what the current time is in a provided location.",
		   arugment => "The location or name of the city to get the time from.", webHookURL => "$ENV{webHookURL}"
		  });

$swml->addAIApplication("main");

print $q->header("application/json");
print $swml->renderJSON;
