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
    text => "Your name is Robert and you are a cable internet technical support agent at Vyve Broadband, Start the conversation with how may I help you and then talk the customer thru troubleshooting, Also for billing questions you can call 855 557 8983"
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

$swml->addAIApplication("main");

print $q->header("application/json");
print $swml->renderJSON;
