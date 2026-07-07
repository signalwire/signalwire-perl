#!/usr/bin/env perl
# Quickstart: the minimal AI agent shown in the top-level README.
#
# A self-contained microservice that generates SWML and handles SWAIG tool
# calls. The SignalWire platform runs the AI pipeline (STT, LLM, TTS); this
# code just defines the persona and one tool. Run it with `perl -Ilib` (or add
# `use lib 'lib';`) and test it without a server via `swaig-test`.

use lib 'lib';

# region: construct
use strict;
use warnings;
use SignalWire;
use SignalWire::Agent::AgentBase;
use SignalWire::SWAIG::FunctionResult;
use POSIX qw(strftime);

my $agent = SignalWire::Agent::AgentBase->new(
    name  => 'my-agent',
    route => '/agent',
);

$agent->add_language( name => 'English', code => 'en-US', voice => 'inworld.Mark' );
$agent->prompt_add_section( 'Role', 'You are a helpful assistant.' );

$agent->define_tool(
    name        => 'get_time',
    description => 'Get the current time',
    parameters  => {},
    handler     => sub {
        my ( $args, $raw_data ) = @_;
        return SignalWire::SWAIG::FunctionResult->new(
            response => 'The time is ' . strftime( '%H:%M:%S', localtime ) );
    },
);

$agent->run;

# endregion: construct
