#!/usr/bin/env perl
# Quickstart: the minimal RELAY client shown in the top-level README.
#
# Connects to SignalWire over WebSocket (Blade protocol) and answers inbound
# calls in real time: answer, play a TTS greeting, then hang up.
#
# Set these env vars before running:
#   SIGNALWIRE_PROJECT_ID   - your SignalWire project ID
#   SIGNALWIRE_API_TOKEN    - your SignalWire API token
#   SIGNALWIRE_SPACE        - your SignalWire space (e.g. example.signalwire.com)

use lib 'lib';

# region: construct
use strict;
use warnings;
use SignalWire::Relay::Client;

my $client = SignalWire::Relay::Client->new(
    project  => $ENV{SIGNALWIRE_PROJECT_ID},
    token    => $ENV{SIGNALWIRE_API_TOKEN},
    host     => $ENV{SIGNALWIRE_SPACE} // 'relay.signalwire.com',
    contexts => ['default'],
);

$client->on_call(
    sub {
        my ($call) = @_;
        $call->answer;
        my $action =
            $call->play( play => [ { type => 'tts', params => { text => 'Welcome!' } } ] );
        $action->wait;
        $call->hangup;
    }
);

$client->connect_ws or die "Connection failed\n";
$client->authenticate;
$client->run;

# endregion: construct
