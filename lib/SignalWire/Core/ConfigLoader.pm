package SignalWire::Core::ConfigLoader;

# Copyright (c) 2025 SignalWire
#
# This file is part of the SignalWire SDK.
#
# Licensed under the MIT License.
# See LICENSE file in the project root for full license information.
#
# Configuration loader with environment variable substitution. Perl port of
# signalwire.core.config_loader.ConfigLoader. Supports ${VAR|default} syntax
# for referencing environment variables within JSON (or YAML) configuration
# files.

use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
use JSON::PP ();
use File::Spec;

# Pattern matching ${VAR} or ${VAR|default}.
my $VAR_PATTERN = qr/\$\{([^}|]+)(?:\|([^}]*))?\}/;

# ---------- attributes ----------

# List of config file paths to check; the first existing, parseable file
# wins. Defaults to the standard search paths when not provided.
has config_paths => (
    is      => 'rw',
    default => sub { [ _default_paths() ] },
);

has _config => (
    is      => 'rw',
    default => sub { undef },
);

has _config_file => (
    is      => 'rw',
    default => sub { undef },
);

# ---------- construction ----------

# Python signature: ``__init__(self, config_paths=None)``. Accept the
# positional config_paths arrayref as the first constructor argument so
# ``->new($paths)`` mirrors the reference; Moo's hash form still works.
sub BUILDARGS ( $class, @args ) {
    if ( @args == 1 && ( ref $args[0] eq 'ARRAY' || !defined $args[0] ) ) {
        return { config_paths => $args[0] // [ _default_paths() ] };
    }
    return {@args};
}

sub BUILD ( $self, $args ) {
    $self->_load_config;
    return;
}

# ---------- public methods ----------

# Check if a configuration was loaded.
sub has_config ($self) {
    return defined $self->_config ? 1 : 0;
}

# Get the path of the loaded config file, or undef.
sub get_config_file ($self) {
    return $self->_config_file;
}

# Get the raw configuration (before substitution) as a hashref.
sub get_config ($self) {
    return $self->_config || {};
}

# Recursively substitute environment variables in configuration values.
# Supports ${VAR|default} syntax. After substitution, string values that
# look like booleans/integers/floats are coerced to those native types
# (Python parity). Dies when max_depth is exhausted.
sub substitute_vars ( $self, $value, $max_depth = 10 ) {
    die "Maximum variable substitution depth exceeded\n" if $max_depth <= 0;

    if ( !ref $value ) {
        return $value unless defined $value;
        return $self->_substitute_string($value);
    }
    if ( ref $value eq 'HASH' ) {
        return {
            map { $_ => $self->substitute_vars( $value->{$_}, $max_depth - 1 ) }
                keys %$value
        };
    }
    if ( ref $value eq 'ARRAY' ) {
        return [ map { $self->substitute_vars( $_, $max_depth - 1 ) } @$value ];
    }
    return $value;
}

# Get a configuration value by dot-notation path (e.g.
# "security.ssl_enabled"), with variables substituted. Returns $default when
# the path is not found.
sub get ( $self, $key_path, $default = undef ) {
    return $default unless $self->_config;

    my $value = $self->_config;
    for my $key ( split /\./, $key_path ) {
        return $default unless ref $value eq 'HASH' && exists $value->{$key};
        $value = $value->{$key};
    }
    return $self->substitute_vars($value);
}

# Get an entire configuration section (a hashref) with all variables
# substituted. Returns an empty hashref when the section is absent.
sub get_section ( $self, $section ) {
    return {} unless $self->_config && exists $self->_config->{$section};
    return $self->substitute_vars( $self->_config->{$section} );
}

# Merge configuration with environment variables. The config file takes
# precedence (but config can reference env vars via substitution). Env vars
# beginning with $env_prefix (default "SWML_") are lowercased, the prefix
# stripped, and folded into the result on underscore boundaries -- only when
# not already present in the config.
sub merge_with_env ( $self, $env_prefix = 'SWML_' ) {
    my $result = $self->_config ? $self->substitute_vars( $self->_config ) : {};

    for my $key ( sort keys %ENV ) {
        next unless index( $key, $env_prefix ) == 0;
        my $ckey = lc( substr( $key, length $env_prefix ) );
        $self->_set_nested_key( $result, $ckey, $ENV{$key} )
            unless $self->_has_nested_key( $result, $ckey );
    }

    return $result;
}

# Find a config file for a service. $service_name optionally seeds
# service-specific config file names, $additional_paths are checked next,
# then the default paths. Returns the first file found, or undef. Mirrors
# Python's ``@staticmethod find_config_file`` — both
# Class->find_config_file(...) and $instance->find_config_file(...) work.
sub find_config_file ( $class_or_self, $service_name = undef, $additional_paths = undef ) {
    my @paths;
    if ($service_name) {
        push @paths, "${service_name}_config.json", ".swml/${service_name}_config.json";
    }
    push @paths, @$additional_paths if $additional_paths;
    push @paths, 'config.json', 'agent_config.json', '.swml/config.json',
        _expanduser('~/.swml/config.json'), '/etc/swml/config.json';

    for my $path (@paths) {
        return $path if -e $path;
    }
    return;
}

# ---------- private helpers ----------

sub _default_paths {
    return ( 'config.json', 'agent_config.json', 'swml_config.json', '.swml/config.json',
        _expanduser('~/.swml/config.json'),
        '/etc/swml/config.json', );
}

sub _expanduser ($path) {
    my $home = $ENV{HOME};
    return $path unless defined $home && $path =~ m{^~(/|$)};
    $path =~ s{^~}{$home};
    return $path;
}

sub _load_config ($self) {
    for my $path ( @{ $self->config_paths } ) {
        next unless -e $path;
        my $parsed = eval { $self->_parse_file($path) };
        next if $@;
        $self->_config($parsed);
        $self->_config_file($path);
        last;
    }
    return;
}

sub _parse_file ( $self, $path ) {
    open my $fh, '<', $path or die "open $path: $!\n";
    local $/;
    my $contents = <$fh>;
    close $fh;
    if ( $path =~ /\.(?:yaml|yml)$/ ) {
        require YAML::PP;
        return YAML::PP->new->load_string($contents);
    }
    return JSON::PP::decode_json($contents);
}

sub _substitute_string ( $self, $value ) {
    ( my $result = $value ) =~ s/$VAR_PATTERN/$ENV{$1} \/\/ (defined $2 ? $2 : '')/ge;
    return _coerce_scalar($result);
}

sub _coerce_scalar ($result) {
    my $lowered = lc $result;
    return JSON::PP::true()  if $lowered eq 'true';
    return JSON::PP::false() if $lowered eq 'false';
    return $result + 0       if $result =~ /\A\d+\z/;
    return $result + 0       if $result =~ /\A\d+\.\d+\z/;
    return $result;
}

sub _has_nested_key ( $self, $data, $key_path ) {
    my $current = $data;
    for my $key ( split /_/, $key_path ) {
        return 0 unless ref $current eq 'HASH' && exists $current->{$key};
        $current = $current->{$key};
    }
    return 1;
}

sub _set_nested_key ( $self, $data, $key_path, $value ) {
    my @keys    = split /_/, $key_path;
    my $current = $data;
    for my $key ( @keys[ 0 .. $#keys - 1 ] ) {
        $current->{$key} = {} unless ref $current->{$key} eq 'HASH';
        $current = $current->{$key};
    }
    $current->{ $keys[-1] } = $value;
    return;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Core::ConfigLoader - JSON/YAML config loader with env-var substitution

=head1 SYNOPSIS

    use SignalWire::Core::ConfigLoader;

    my $loader = SignalWire::Core::ConfigLoader->new(['config.json']);
    if ( $loader->has_config ) {
        my $ssl = $loader->get('security.ssl_enabled', 0);
        my $sec = $loader->get_section('security');
        my $all = $loader->merge_with_env('SWML_');
    }

    my $path = SignalWire::Core::ConfigLoader->find_config_file('agent');

=head1 DESCRIPTION

L<SignalWire::Core::ConfigLoader> is a Perl port of
C<signalwire.core.config_loader.ConfigLoader>. It loads the first available
JSON (or YAML) config file from a search path and supports C<${VAR|default}>
syntax for referencing environment variables within configuration values.
After substitution, string values that look like booleans, integers, or
floats are coerced to native Perl types (matching Python's JSON typing).

=head1 METHODS

=over 4

=item * C<new($config_paths)> — construct with an optional arrayref of paths
to try (first existing, parseable file wins); defaults to the standard search
paths.

=item * C<has_config> / C<get_config_file> / C<get_config> — load status,
loaded file path, and raw (unsubstituted) config.

=item * C<substitute_vars($value, $max_depth)> — recursively substitute env
vars (with type coercion) in a scalar / hashref / arrayref.

=item * C<get($key_path, $default)> — dot-notation lookup with substitution.

=item * C<get_section($section)> — an entire section, substituted.

=item * C<merge_with_env($env_prefix)> — merge config with C<SWML_>-prefixed
env vars (config wins).

=item * C<find_config_file($service_name, $additional_paths)> — static helper
returning the first existing config file for a service, or undef.

=back

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
