#!/usr/bin/env perl
use strict;
use warnings;
use CGI;
use SignalWire::ML;
use Data::Dumper;

my $q = CGI->new;

my $swml = SignalWire::ML->new({version => '1.0.1', voice => 'en-US-Neural2-J' });

$swml->addApplication("bye", "play",
		      { urls => ['https://github.com/freeswitch/freeswitch-sounds/raw/master/fr/ca/june/voicemail/48000/vm-goodbye.wav']});
$swml->addApplication("bye", "hangup", "NORMAL_CLEARING");

$swml->addApplication("main", "play",
		      { urls => ['https://github.com/freeswitch/freeswitch-sounds/raw/master/en/us/callie/ivr/48000/ivr-welcome_to_freeswitch.wav'] });
$swml->addApplication("main", "transfer", "bye");

print $q->header("application/json");
print $swml->renderJSON;
