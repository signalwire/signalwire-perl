#!/usr/bin/env perl
# Quickstart: the minimal REST client shown in the top-level README.
#
# A synchronous HTTP client for managing SignalWire resources and controlling
# calls -- no WebSocket required. Demonstrates namespaced access across Fabric,
# Calling, Phone Numbers, and Datasphere.
#
# Set these env vars before running:
#   SIGNALWIRE_PROJECT_ID   - your SignalWire project ID
#   SIGNALWIRE_API_TOKEN    - your SignalWire API token
#   SIGNALWIRE_SPACE        - your SignalWire space (e.g. example.signalwire.com)

use lib 'lib';

# region: construct
use strict;
use warnings;
use SignalWire::REST::RestClient;

my $client = SignalWire::REST::RestClient->new(
    project => $ENV{SIGNALWIRE_PROJECT_ID},
    token   => $ENV{SIGNALWIRE_API_TOKEN},
    host    => $ENV{SIGNALWIRE_SPACE},
);

$client->fabric->ai_agents->create(
    name   => 'Support Bot',
    prompt => { text => 'You are helpful.' }
);

my $call_id = 'call-id-from-a-prior-request';
$client->calling->play( $call_id, play => [ { type => 'tts', text => 'Hello!' } ] );
$client->phone_numbers->search( area_code => '512' );
$client->datasphere->documents->search( query_string => 'billing policy' );

# endregion: construct
