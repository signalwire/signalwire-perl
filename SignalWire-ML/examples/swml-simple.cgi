#!/usr/bin/env perl
use strict;
use warnings;
use CGI;
use SignalWire::ML;

my $q = CGI->new;

my $swml = SignalWire::ML->new({version => '1.0.0', voice => 'en-US-Neural2-J' });

$swml->add_application("main", "answer");

$swml->add_application("main", "play",
		       { urls => [ "https://github.com/freeswitch/freeswitch-sounds/raw/master/en/us/callie/ivr/48000/ivr-welcome_to_freeswitch.wav" ] });
$swml->add_application("main", "hangup");

print $q->header("application/json");
print $swml->render_json;
