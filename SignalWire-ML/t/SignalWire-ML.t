#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 16;  # Updated test count
use JSON;

# Load the module
use_ok('SignalWire::ML');

# Create a new SignalWire::ML object
my $ml = SignalWire::ML->new({version => '1.0.0'});
isa_ok($ml, 'SignalWire::ML');

# Test set_aiprompt
$ml->set_aiprompt({
    text => "What's the weather like today?",
    temperature => 0.7,
    top_p => 0.9
});
is($ml->{_prompt}{text}, "What's the weather like today?", "set_aiprompt sets text correctly");
is($ml->{_prompt}{temperature}, 0.7, "set_aiprompt sets temperature correctly");

# Test set_aiparams
$ml->set_aiparams({max_tokens => 150});
is($ml->{_params}{max_tokens}, 150, "set_aiparams sets max_tokens correctly");

# Test add_aiapplication
$ml->add_aiapplication('main');
ok(exists $ml->{_content}{sections}{main}, "add_aiapplication adds section correctly");
is(ref $ml->{_content}{sections}{main}[0]{ai}, 'HASH', "add_aiapplication adds ai application correctly");

# Test add_application
$ml->add_application("main", "answer");
is_deeply($ml->{_content}{sections}{main}[-1], {answer => {}}, "add_application adds answer application correctly");

# Test set_aihints
$ml->set_aihints("hint1", "hint2");
is_deeply($ml->{_hints}, ["hint1", "hint2"], "set_aihints sets hints correctly");

# Test add_aihints
$ml->add_aihints("hint3");
is_deeply($ml->{_hints}, ["hint1", "hint2", "hint3"], "add_aihints adds hint correctly");

# Test set_ailanguage
$ml->set_ailanguage("en-US");
is($ml->{_languages}, "en-US", "set_ailanguage sets language correctly");

# Test add_aiswaigfunction
$ml->add_aiswaigfunction({name => "test_function", description => "A test function"});
is_deeply($ml->{_SWAIG}{functions}[0], {name => "test_function", description => "A test function"}, "add_aiswaigfunction adds function correctly");

# Test render_json
my $json_output = $ml->render_json();
my $decoded_json = JSON->new->decode($json_output);
ok(exists $decoded_json->{version}, "render_json includes version");
ok(exists $decoded_json->{sections}, "render_json includes sections");

# Test render_yaml
my $yaml_output = $ml->render_yaml();
like($yaml_output, qr/version: 1.0.0/, "render_yaml includes version");
like($yaml_output, qr/sections:/, "render_yaml includes sections");
