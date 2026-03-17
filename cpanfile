requires 'perl', '5.026';

# Core
requires 'Moo', '2.0';
requires 'JSON', '4.0';
requires 'Plack', '1.0';
requires 'Plack::Request';
requires 'HTTP::Tiny';
requires 'Digest::SHA';
requires 'MIME::Base64';
requires 'IO::Socket::SSL';

# WebSocket for RELAY
requires 'Protocol::WebSocket', '0.26';

# Testing
on 'test' => sub {
    requires 'Test::More', '0.98';
    requires 'Test::Exception';
    requires 'Plack::Test';
    requires 'HTTP::Request::Common';
};
