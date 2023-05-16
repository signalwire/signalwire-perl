#!/usr/bin/env perl
use strict;
use warnings;
use CGI;
use SignalWire::ML;
use Data::Dumper;

my $q = CGI->new;

my $swml = SignalWire::ML->new({version => '1.0.1', voice => 'en-US-Neural2-J' });


$swml->add_application("main", "send_sms",{
    tags => ["ai", "demo"],
    to_number => "+19184249378",
    from_number => "$ENV{SIGNALWIRE_NUMBERX}",
    body => "Testing &r^5JD8NQ%M9A9$8%Abk962j2",
    region => "us" });

$swml->add_application("main", "play",
		      { urls => ['https://github.com/freeswitch/freeswitch-sounds/raw/master/fr/ca/june/voicemail/48000/vm-goodbye.wav']});
print $q->header("application/json");
print $swml->render_json;
