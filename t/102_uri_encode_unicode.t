#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Test::More;

# PERL-2: _uri_encode must percent-encode non-ASCII as UTF-8 bytes (RFC 3986).
# Previously it did sprintf("%%%02X", ord($1)) directly on the character, so:
#   * a latin-1 char (é, U+00E9) emitted the single byte %E9 instead of the
#     UTF-8 pair %C3%A9 (wrong request), and
#   * a char > U+00FF (☺, U+263A) emitted ord()=9786 as ">2 hex digits"
#     (%263A), which a server parses as %26 ('&') + literal '3A' — query-string
#     corruption / injection-shaped.

# Test::More writes descriptions (which mention unicode) to the TAP stream;
# make that stream UTF-8 so a unicode test name does not warn.
binmode Test::More->builder->output,         ':encoding(UTF-8)';
binmode Test::More->builder->failure_output, ':encoding(UTF-8)';
binmode Test::More->builder->todo_output,    ':encoding(UTF-8)';

use SignalWire::REST::HttpClient;

# é (U+00E9) -> UTF-8 %C3%A9, NOT the latin-1 byte %E9.
is( SignalWire::REST::HttpClient::_uri_encode('é'),
    '%C3%A9', 'é encodes as UTF-8 bytes %C3%A9 (not latin-1 %E9)' );

# ☺ (U+263A) -> UTF-8 %E2%98%BA, NOT a mangled multi-digit escape.
is( SignalWire::REST::HttpClient::_uri_encode('☺'),
    '%E2%98%BA', '☺ encodes as UTF-8 bytes %E2%98%BA (not %263A)' );

# Mixed ASCII + unicode + space.
is(
    SignalWire::REST::HttpClient::_uri_encode('café ☺'),
    'caf%C3%A9%20%E2%98%BA',
    'mixed ASCII/unicode/space round-trips as UTF-8 percent-encoding'
);

# Unreserved set (RFC 3986) passes through unencoded.
is( SignalWire::REST::HttpClient::_uri_encode('aZ0-_.~'),
    'aZ0-_.~', 'unreserved characters are not encoded' );

# Reserved ASCII is still encoded.
is( SignalWire::REST::HttpClient::_uri_encode('a b&c=d'),
    'a%20b%26c%3Dd', 'reserved ASCII (space, &, =) encoded' );

# No corruption: the encoded output never contains a stray high hex-triplet.
my $enc = SignalWire::REST::HttpClient::_uri_encode('naïve ☺ 日本');
unlike( $enc, qr/%[0-9A-F]{3,}/, 'no >2-hex-digit escape (no wide-char corruption)' );
# Every %XX is a valid single byte escape.
ok( $enc =~ /^(?:[A-Za-z0-9\-_.~]|%[0-9A-F]{2})+$/,
    'output is well-formed percent-encoding (byte escapes only)' );

done_testing;
