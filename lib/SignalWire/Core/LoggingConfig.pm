package SignalWire::Core::LoggingConfig;
use strict;
use warnings;
use Exporter qw(import);
use SignalWire::Logging;

our @EXPORT_OK = qw(
    get_execution_mode get_logger
    configure_logging reset_logging_configuration strip_control_chars
);

# Control characters that could be used for log injection. Mirrors the
# Python reference's _CONTROL_CHAR_RE (C0/C1 controls minus \t \n \r).
my $CONTROL_CHAR_RE = qr/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]/;

# Global flag ensuring configuration only happens once (mirrors Python's
# module-level _logging_configured).
my $logging_configured = 0;

# Python parity: signalwire.core.logging_config.get_logger(name) is a
# module-level factory that returns a structured logger bound to the
# given name. Perl's SignalWire::Logging->get_logger($name) is the
# class-method form; this free-function form mirrors Python's import
# shape so cross-port code reads the same.
sub get_logger {
    my ($name) = @_;
    return SignalWire::Logging->get_logger($name);
}

# Cross-language SDK contract for serverless / deployment-mode detection.
#
# Mirrors signalwire.core.logging_config.get_execution_mode in the Python
# reference. Order of precedence (FIRST match wins):
#
#   1. GATEWAY_INTERFACE                                       -> 'cgi'
#   2. AWS_LAMBDA_FUNCTION_NAME or LAMBDA_TASK_ROOT            -> 'lambda'
#   3. FUNCTION_TARGET, K_SERVICE, or GOOGLE_CLOUD_PROJECT     -> 'google_cloud_function'
#   4. AZURE_FUNCTIONS_ENVIRONMENT, FUNCTIONS_WORKER_RUNTIME,
#      or AzureWebJobsStorage                                  -> 'azure_function'
#   5. otherwise                                               -> 'server'
#
# Returns one of: 'cgi', 'lambda', 'google_cloud_function',
# 'azure_function', or 'server'.
sub get_execution_mode {
    return 'cgi' if _is_set('GATEWAY_INTERFACE');
    return 'lambda'
        if _is_set('AWS_LAMBDA_FUNCTION_NAME')
        || _is_set('LAMBDA_TASK_ROOT');
    return 'google_cloud_function'
        if _is_set('FUNCTION_TARGET')
        || _is_set('K_SERVICE')
        || _is_set('GOOGLE_CLOUD_PROJECT');
    return 'azure_function'
        if _is_set('AZURE_FUNCTIONS_ENVIRONMENT')
        || _is_set('FUNCTIONS_WORKER_RUNTIME')
        || _is_set('AzureWebJobsStorage');
    return 'server';
}

sub _is_set {
    my ($name) = @_;
    return defined $ENV{$name} && length $ENV{$name};
}

# Strip control characters from every string value of a log event hashref,
# preventing log-injection. Mirrors
# signalwire.core.logging_config.strip_control_chars — a structlog processor
# in Python; here it is a plain hash transformer. Returns the same hashref
# with string values sanitised.
sub strip_control_chars {
    my ($event_dict) = @_;
    for my $key ( keys %$event_dict ) {
        my $value = $event_dict->{$key};
        if ( defined $value && !ref $value ) {
            ( my $clean = $value ) =~ s/$CONTROL_CHAR_RE//g;
            $event_dict->{$key} = $clean;
        }
    }
    return $event_dict;
}

# Configure the SDK logging system once, globally, based on the
# SIGNALWIRE_LOG_MODE / SIGNALWIRE_LOG_LEVEL environment variables. Mirrors
# signalwire.core.logging_config.configure_logging: idempotent — a second
# call is a no-op unless reset_logging_configuration ran first.
sub configure_logging {
    return                         if $logging_configured;
    SignalWire::Logging->configure if SignalWire::Logging->can('configure');
    $logging_configured = 1;
    return;
}

# Reset the one-time configuration guard so configure_logging can run again
# (used when environment variables change after initial setup). Mirrors
# signalwire.core.logging_config.reset_logging_configuration.
sub reset_logging_configuration {
    $logging_configured = 0;
    SignalWire::Logging->reset if SignalWire::Logging->can('reset');
    return;
}

1;
