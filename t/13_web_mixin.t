#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use SignalWire::SWML::Document;
use SignalWire::SWML::Schema;
use SignalWire::SWML::Service;

# =============================================================================
# WebMixin parity: on_request / on_swml_request
#
# Python parity:
#   tests/unit/core/mixins/test_web_mixin.py::
#     test_on_request_delegates_to_on_swml_request
#     test_on_swml_request_called
# =============================================================================

# Test subclass that captures input and returns a configured hashref.
{
    package CustomService;
    use parent -norequire, 'SignalWire::SWML::Service';

    sub new {
        my ($class, %args) = @_;
        my $self = $class->SUPER::new(%args);
        $self->{custom_return} = undef;
        $self->{last_request_data} = undef;
        $self->{last_callback_path} = undef;
        return $self;
    }

    sub on_swml_request {
        my ($self, $request_data, $callback_path) = @_;
        $self->{last_request_data} = $request_data;
        $self->{last_callback_path} = $callback_path;
        return $self->{custom_return};
    }
}

subtest 'on_request delegates to on_swml_request' => sub {
    my $svc = CustomService->new(name => 't');
    $svc->{custom_return} = { custom => 1 };
    my $rd = { data => 'val' };
    my $result = $svc->on_request($rd, '/cb');
    is_deeply($svc->{last_request_data}, $rd, 'hook received request_data');
    is($svc->{last_callback_path}, '/cb', 'hook received callback_path');
    is_deeply($result, { custom => 1 }, 'on_request returned hook result');
};

subtest 'on_swml_request default returns undef' => sub {
    my $svc = SignalWire::SWML::Service->new(name => 't');
    is($svc->on_swml_request(undef, undef), undef,
       'default on_swml_request returns undef');
};

subtest 'on_request default returns undef' => sub {
    my $svc = SignalWire::SWML::Service->new(name => 't');
    is($svc->on_request(undef, undef), undef,
       'default on_request returns undef');
};

subtest 'on_request passes nulls to hook' => sub {
    my $svc = CustomService->new(name => 't');
    $svc->{custom_return} = undef;
    my $result = $svc->on_request(undef, undef);
    is($result, undef, 'returns undef when hook returns undef');
    is($svc->{last_request_data}, undef, 'request_data passed as undef');
    is($svc->{last_callback_path}, undef, 'callback_path passed as undef');
};

done_testing();
