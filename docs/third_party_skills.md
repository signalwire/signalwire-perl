# Third-Party Skills Integration Guide

This guide explains how to create and integrate third-party skills with the SignalWire AI Agents SDK. The SDK supports multiple methods for loading external skills, making it easy to extend agent capabilities without modifying the core SDK.

## Overview

Third-party skills can be integrated using two methods:

1. **Direct Registration** - Register skill classes programmatically with `SignalWire::register_skill`
2. **Directory Registration** - Add directories containing skill collections with `SignalWire::add_skill_directory`

All third-party skills are discovered and indexed the same way as built-in skills, appearing in `SignalWire::list_skills_with_params()` output with their parameter schemas.

## Creating a Third-Party Skill

Third-party skills follow the same structure as built-in skills: extend
`SignalWire::Skills::SkillBase` and register with the skill registry.

```perl
package My::Skills::Weather;
use strict;
use warnings;
use Moo;
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill('weather', __PACKAGE__);

has '+skill_name'        => ( default => sub { 'weather' } );
has '+skill_description' => ( default => sub { 'Get weather information for any location' } );
has '+skill_version'     => ( default => sub { '1.0.0' } );
has '+required_env_vars' => ( default => sub { [] } );

sub get_parameter_schema {
    return {
        %{ SignalWire::Skills::SkillBase->get_parameter_schema },
        api_key => {
            type        => 'string',
            description => 'Weather API key',
            required    => 1,
            hidden      => 1,
        },
        units => {
            type        => 'string',
            description => 'Temperature units',
            default     => 'celsius',
            enum        => ['celsius', 'fahrenheit', 'kelvin'],
        },
        cache_timeout => {
            type        => 'integer',
            description => 'Cache timeout in seconds',
            default     => 300,
            min         => 0,
            max         => 3600,
        },
    };
}

sub setup {
    my ($self) = @_;
    return 0 unless $self->params->{api_key};
    return 1;
}

sub register_tools {
    my ($self) = @_;
    my $units = $self->params->{units} // 'celsius';

    $self->define_tool(
        name        => 'get_weather',
        description => 'Get current weather for a location',
        parameters  => {
            type       => 'object',
            properties => {
                location => { type => 'string', description => 'City name or coordinates' },
            },
            required => ['location'],
        },
        handler => sub {
            my ($args, $raw_data) = @_;
            require SignalWire::SWAIG::FunctionResult;
            my $location = $args->{location} // '';
            return SignalWire::SWAIG::FunctionResult->new('Please provide a location')
                unless length $location;

            # Implementation would call the weather API here.
            return SignalWire::SWAIG::FunctionResult->new(
                "The weather in $location is sunny ($units)");
        },
    );
}

1;
```

## Integration Methods

### Method 1: Direct Registration

Register individual skill classes programmatically:

<!-- snippet: no-compile references My::Skills::Weather, a reader-defined example package with no module file -->
```perl
use SignalWire;
use SignalWire::Agent::AgentBase;
use My::Skills::Weather;

# Register the skill (derives the name from skill_name)
SignalWire::register_skill('My::Skills::Weather');

# Now use it in any agent
my $agent = SignalWire::Agent::AgentBase->new(name => 'my-agent');
$agent->add_skill('weather', {
    api_key => 'your-api-key',
    units   => 'fahrenheit',
});
```

A skill module that already calls `SignalWire::Skills::SkillRegistry->register_skill`
at load time (as in the example above) is registered simply by `use`-ing it.

### Method 2: Directory Registration

Register directories containing multiple skill modules:

<!-- snippet: no-run references example skill directory /opt/custom_skills that does not exist -->
```perl
use SignalWire;

# Add a directory of custom skills
SignalWire::add_skill_directory('/opt/custom_skills');

# Now any skill registered from that directory can be added
$agent->add_skill('weather', { api_key => '...' });
```

`add_skill_directory` dies if the path does not exist or is not a directory, and
de-duplicates repeated entries.

## Skill Discovery and Schema

Third-party skills are integrated with the SDK's discovery system:

```perl
use SignalWire;

# Get all skills, including third-party ones
my $all_skills = SignalWire::list_skills_with_params();

# Inspect a third-party skill's metadata
my $weather = $all_skills->{weather};
# {
#     name        => 'weather',
#     description => 'Get weather information for any location',
#     version     => '1.0.0',
#     supports_multiple_instances => 0,
#     parameters  => {
#         api_key => { type => 'string', required => 1, hidden => 1 },
#         units   => { type => 'string', default => 'celsius',
#                      enum => ['celsius', 'fahrenheit', 'kelvin'] },
#     },
# }
```

## Best Practices

### 1. Skill Naming

- Use lowercase, underscore-separated names
- Choose unique names to avoid conflicts with built-in skills
- Match `skill_name` to the registration key

### 2. Parameter Design

- Always implement `get_parameter_schema()` for tooling compatibility
- Mark sensitive parameters as `hidden`
- Provide sensible defaults
- Always merge the base schema (`SignalWire::Skills::SkillBase->get_parameter_schema`)

### 3. Error Handling

```perl
sub setup {
    my ($self) = @_;

    # Validate required environment variables
    return 0 unless $self->validate_env_vars;

    # Validate required parameters
    unless ($self->params->{api_key}) {
        warn "API key is required\n";
        return 0;
    }

    # Test connectivity
    my $ok = eval { $self->_test_api_connection; 1 };
    unless ($ok) {
        warn "Failed to connect to API: $@\n";
        return 0;
    }

    return 1;
}
```

## Advanced Features

### Multiple Instances

Support multiple instances of your skill by enabling
`supports_multiple_instances` and giving each instance a distinct `tool_name`:

<!-- snippet: no-compile class-body fragment (Moo has-modifier and method, no package/use Moo scaffold) -->
```perl
has '+supports_multiple_instances' => ( default => sub { 1 } );

sub get_instance_key {
    my ($self) = @_;
    my $service = $self->params->{service} // 'default';
    return $self->skill_name . '_' . $service;
}
```

Usage:

```perl
# Add multiple weather services
$agent->add_skill('weather', {
    tool_name => 'openweather',
    service   => 'openweathermap',
    api_key   => 'key1',
});

$agent->add_skill('weather', {
    tool_name => 'weatherapi',
    service   => 'weatherapi',
    api_key   => 'key2',
});
```

### Dynamic Tool Names

Customize tool names for better agent prompts:

```perl
sub register_tools {
    my ($self) = @_;
    my $tool_name = $self->params->{tool_name} // 'get_weather';
    my $service   = $self->params->{service}   // 'default';

    $self->define_tool(
        name        => $tool_name,
        description => "Get weather using $service",
        parameters  => { type => 'object', properties => {} },
        handler     => sub { ... },
    );
}
```

### Skill Dependencies

Load skills that depend on other skills:

```perl
sub setup {
    my ($self) = @_;

    # Check if a required skill is available
    unless ($self->agent->has_skill('native_vector_search')) {
        warn "This skill requires the native_vector_search skill\n";
        return 0;
    }

    return 1;
}
```

## Testing Third-Party Skills

Test your skills before distribution:

<!-- snippet: no-compile references My::Skills::Weather, a reader-defined example package with no module file -->
```perl
use Test::More;
use SignalWire;
use SignalWire::Agent::AgentBase;
use My::Skills::Weather;

SignalWire::register_skill('My::Skills::Weather');

my $agent = SignalWire::Agent::AgentBase->new(name => 'test-agent');
$agent->add_skill('weather', { api_key => 'test-key' });
ok($agent->has_skill('weather'), 'weather skill loaded');

my $schema = My::Skills::Weather->get_parameter_schema;
ok(exists $schema->{api_key},      'api_key parameter present');
ok($schema->{api_key}{required},   'api_key is required');
ok($schema->{api_key}{hidden},     'api_key is hidden');

done_testing;
```

## Troubleshooting

### Skill Not Found

If your skill isn't being discovered:

1. Ensure the module calls `SignalWire::Skills::SkillRegistry->register_skill(...)` at load time
2. Verify the registration name matches the value passed to `add_skill`
3. Ensure the module is loadable (`perl -Ilib -c My/Skills/Weather.pm`)
4. Check for load errors via `warn`/`die` output

### Environment Variables

Skills can require environment variables via `required_env_vars`; `setup` should
call `$self->validate_env_vars` and return false when they are missing.
