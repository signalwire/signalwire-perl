#!/usr/bin/env perl
# Auto-Vivified SWML Service Example
#
# Demonstrates calling verb methods directly on a SWMLService instead
# of using add_verb(). Each auto-vivified verb method takes a section
# name (defaults to 'main') and a config hashref:
#     $svc->play('main', { url => 'say:...' });
# Builds voicemail, IVR, and call transfer services.

use strict;
use warnings;
use lib 'lib';
use JSON ();
use SignalWire;
use SignalWire::SWML::Service;

# --- Voicemail Service ---
my $voicemail = SignalWire::SWML::Service->new(
    name  => 'voicemail',
    route => '/voicemail',
);

$voicemail->answer;
$voicemail->play('main', { url => 'say:Hello, you have reached the voicemail service. Please leave a message after the beep.' });
$voicemail->sleep('main', 1000);
$voicemail->play('main', { url => 'https://example.com/beep.wav' });
# stereo/beep are anyOf<boolean, SWMLVar>: a bare Perl 0 JSON-encodes as the
# number 0, which the schema rejects. Use real JSON booleans.
$voicemail->record('main', {
    format     => 'mp3',
    stereo     => JSON::false,
    beep       => JSON::false,
    max_length => 120,
    terminators => '#',
    status_url => 'https://example.com/voicemail-status',
});
$voicemail->play('main', { url => 'say:Thank you for your message. Goodbye!' });
$voicemail->hangup;

# --- IVR Menu Service ---
my $ivr = SignalWire::SWML::Service->new(
    name  => 'ivr',
    route => '/ivr',
);

$ivr->answer;
$ivr->add_section('main_menu');
$ivr->add_verb_to_section('main_menu', 'prompt', {
    play         => 'say:Press 1 for sales, 2 for support, or 3 to leave a message.',
    max_digits   => 1,
    terminators  => '#',
    digit_timeout => 5.0,
});
$ivr->add_verb_to_section('main_menu', 'switch', {
    variable => 'prompt_digits',
    case     => {
        1 => [{ transfer => { dest => 'sales' } }],
        2 => [{ transfer => { dest => 'support' } }],
    },
});
$ivr->add_verb('transfer', { dest => 'main_menu' });

# --- Call Transfer Service ---
my $transfer = SignalWire::SWML::Service->new(
    name  => 'transfer',
    route => '/transfer',
);

$transfer->answer;
$transfer->add_verb('play', { url => 'say:Connecting you with the next available agent.' });
$transfer->add_verb('connect', {
    from    => '+15551234567',
    timeout => 30,
    parallel => [
        { to => '+15552223333' },
        { to => '+15554445555' },
    ],
});
# $defs/Record.beep is anyOf<boolean, SWMLVar> — a bare Perl 1 JSON-encodes as
# the number 1 and the schema rejects it. Use a real JSON boolean.
$transfer->add_verb( 'record', { format => 'mp3', beep => JSON::true, max_length => 120 } );
$transfer->hangup;

# Run the voicemail service
print "Starting voicemail service at http://localhost:3000/voicemail\n";
$voicemail->serve;
