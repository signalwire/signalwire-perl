#!/usr/bin/env perl
# Parity tests for SignalWire::Security::SecurityUtils. Mirrors the
# Python reference signalwire.core.security.security_utils (filter_
# sensitive_headers, redact_url, is_valid_hostname) and the TypeScript
# SecurityUtils these descend from.

use strict;
use warnings;

use Test::More;
use SignalWire::Security::SecurityUtils
    qw(filter_sensitive_headers redact_url is_valid_hostname);

# --- filter_sensitive_headers ----------------------------------------

subtest 'filter_sensitive_headers removes credential headers' => sub {
    my $in = {
        'Authorization'       => 'Bearer secret',
        'Cookie'              => 'session=abc',
        'X-API-Key'           => 'key123',
        'Proxy-Authorization' => 'Basic xyz',
        'Set-Cookie'          => 'a=b',
        'Content-Type'        => 'application/json',
        'X-Request-Id'        => 'req-1',
    };
    my $out = filter_sensitive_headers($in);
    is_deeply(
        $out,
        { 'Content-Type' => 'application/json', 'X-Request-Id' => 'req-1' },
        'sensitive headers stripped, non-sensitive preserved as given'
    );
    ok( !exists $out->{Authorization}, 'Authorization removed' );
    ok( !exists $out->{Cookie},        'Cookie removed' );
    ok( !exists $out->{'X-API-Key'},   'X-API-Key removed' );
};

subtest 'filter_sensitive_headers is case-insensitive on keys' => sub {
    my $out = filter_sensitive_headers(
        { 'AUTHORIZATION' => 'x', 'cookie' => 'y', 'SeT-CookIE' => 'z', 'Accept' => 'text/html' } );
    is_deeply( $out, { 'Accept' => 'text/html' },
        'mixed-case sensitive keys all removed regardless of casing' );
};

subtest 'filter_sensitive_headers preserves original key casing of kept headers' => sub {
    my $out = filter_sensitive_headers( { 'X-Custom-Header' => 'v' } );
    ok( exists $out->{'X-Custom-Header'}, 'kept key retains original casing' );
    is( $out->{'X-Custom-Header'}, 'v', 'kept value intact' );
};

subtest 'filter_sensitive_headers returns a NEW hashref (copy)' => sub {
    my $in  = { 'Accept' => 'text/html' };
    my $out = filter_sensitive_headers($in);
    isnt( $out, $in, 'returned hashref is a distinct copy' );
    $out->{Mutated} = 1;
    ok( !exists $in->{Mutated}, 'mutating the copy does not affect the input' );
};

subtest 'filter_sensitive_headers empty / undef input -> empty hashref' => sub {
    is_deeply( filter_sensitive_headers( {} ),    {}, 'empty hash -> empty hash' );
    is_deeply( filter_sensitive_headers(undef),   {}, 'undef -> empty hash' );
};

# --- redact_url -------------------------------------------------------

subtest 'redact_url masks password in userinfo' => sub {
    is(
        redact_url('https://user:secret@host/path'),
        'https://user:****@host/path',
        'password replaced with ****'
    );
};

subtest 'redact_url leaves credential-free URL unchanged' => sub {
    is( redact_url('https://host/path'), 'https://host/path', 'no credentials -> unchanged' );
    is( redact_url('https://user@host/path'),
        'https://user@host/path', 'userinfo without password -> unchanged' );
};

subtest 'redact_url handles multiple occurrences' => sub {
    is(
        redact_url('redis://u:p1@a/ x://v:p2@b'),
        'redis://u:****@a/ x://v:****@b',
        'all credential pairs masked'
    );
};

subtest 'redact_url non-string input returned as-is' => sub {
    my $ref = { not => 'a string' };
    is( redact_url($ref),  $ref,  'hashref returned unchanged' );
    is( redact_url(undef), undef, 'undef returned unchanged' );
};

# --- is_valid_hostname ------------------------------------------------

subtest 'is_valid_hostname accepts plain hostnames' => sub {
    ok( is_valid_hostname('example.com'),       'dotted hostname valid' );
    ok( is_valid_hostname('localhost'),         'bare hostname valid' );
    ok( is_valid_hostname('host-name_1'),       'hyphen/underscore/digit valid' );
    ok( is_valid_hostname('192.168.1.1'),       'IP literal valid (char-level)' );
};

subtest 'is_valid_hostname rejects empty / undef' => sub {
    ok( !is_valid_hostname(''),    'empty string rejected' );
    ok( !is_valid_hostname(undef), 'undef rejected' );
};

subtest 'is_valid_hostname rejects whitespace, slashes, control chars' => sub {
    ok( !is_valid_hostname('bad host'),       'space rejected' );
    ok( !is_valid_hostname("tab\thost"),      'tab rejected' );
    ok( !is_valid_hostname('host/path'),      'forward slash rejected' );
    ok( !is_valid_hostname('host\\path'),     'backslash rejected' );
    ok( !is_valid_hostname("host\x00null"),   'null byte rejected' );
    ok( !is_valid_hostname("host\x1fctl"),    'control char rejected' );
    ok( !is_valid_hostname("host\x7fdel"),    'DEL char rejected' );
    ok( !is_valid_hostname("host\nnewline"),  'newline rejected' );
};

done_testing();
