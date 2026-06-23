# Skills Parameter Schema System

This guide explains the parameter schema system for SignalWire AI Agents SDK skills, which enables configuration tooling and programmatic skill discovery.

## Overview

The parameter schema system allows skills to declare their configurable parameters with metadata including types, descriptions, default values, and security hints. This enables:

- **Configuration tools** - Automatically generate configuration forms
- **API documentation** - Document all available parameters
- **Validation** - Type checking and constraint validation
- **Security** - Mark sensitive parameters as hidden

## Using the Schema System

### Getting All Skills Schema

Use `SignalWire::list_skills_with_params()` to get a complete schema of all available skills:

```perl
use SignalWire;

# Get complete schema for all skills (returns a hashref keyed by skill name)
my $schema = SignalWire::list_skills_with_params();

# Example structure for one entry:
# {
#     web_search => {
#         name        => 'web_search',
#         description => 'Search the web for information using Google Custom Search API',
#         version     => '2.0.0',
#         supports_multiple_instances => 1,
#         parameters  => {
#             api_key          => { type => 'string',  required => 1, hidden => 1 },
#             search_engine_id => { type => 'string',  required => 1, hidden => 1 },
#             num_results      => { type => 'integer', default  => 3, min => 1, max => 10 },
#             ...
#         },
#     },
#     ...
# }
```

### Using Schema for Configuration

Here's an example of how to use the schema to drive a configuration form:

```perl
use SignalWire;

my $schema = SignalWire::list_skills_with_params();

# Example: inspect the web_search skill's parameters
my $web_search_params = $schema->{web_search}{parameters};

for my $param_name (sort keys %$web_search_params) {
    my $info = $web_search_params->{$param_name};

    my $label    = $info->{description} // $param_name;
    my $required = $info->{required}    ? 'required' : '';
    # Render sensitive fields as password inputs
    my $type     = $info->{hidden}      ? 'password' : 'text';

    print "Field: $param_name ($type) $required - $label\n";
}
```

### Programmatic Skill Configuration

Use the schema to validate required parameters before adding a skill:

```perl
use SignalWire;
use SignalWire::Agent::AgentBase;

my $agent  = SignalWire::Agent::AgentBase->new(name => 'my-agent');
my $schema = SignalWire::list_skills_with_params();

my %web_search_params = (
    api_key          => 'your-api-key',
    search_engine_id => 'your-engine-id',
    num_results      => 3,
);

# Validate required parameters
my $param_schema = $schema->{web_search}{parameters};
for my $param (keys %$param_schema) {
    next unless $param_schema->{$param}{required};
    die "Missing required parameter: $param\n"
        unless exists $web_search_params{$param};
}

$agent->add_skill('web_search', \%web_search_params);
```

## Parameter Schema Reference

Each parameter in the schema can have the following properties:

| Property | Type | Description |
|----------|------|-------------|
| `type` | string | Parameter type: "string", "integer", "number", "boolean", "object", "array" |
| `description` | string | Human-readable description of the parameter |
| `default` | any | Default value if not provided |
| `required` | boolean | Whether the parameter is required (default: false) |
| `hidden` | boolean | Whether to hide this field in UIs (for secrets/API keys) |
| `enum` | array | List of allowed values (for string types) |
| `min` | number | Minimum value (for numeric types) |
| `max` | number | Maximum value (for numeric types) |

## Implementing Parameter Schema in Skills

To add parameter schema support to a skill, override the `get_parameter_schema()` method. Merge the base schema (which provides common parameters) with your own:

```perl
package SignalWire::Skills::Builtin::MyCustomSkill;
use strict;
use warnings;
use Moo;
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill('my_custom_skill', __PACKAGE__);

has '+skill_name'        => ( default => sub { 'my_custom_skill' } );
has '+skill_description' => ( default => sub { 'My custom skill' } );
has '+skill_version'     => ( default => sub { '1.0.0' } );

sub get_parameter_schema {
    return {
        # Inherit the base parameters (swaig_fields, skip_prompt, tool_name)
        %{ SignalWire::Skills::SkillBase->get_parameter_schema },

        api_endpoint => {
            type        => 'string',
            description => 'API endpoint URL',
            required    => 1,
            default     => 'https://api.example.com',
        },
        api_key => {
            type        => 'string',
            description => 'API authentication key',
            required    => 1,
            hidden      => 1,   # Mark as sensitive
        },
        timeout => {
            type        => 'integer',
            description => 'Request timeout in seconds',
            default     => 30,
            min         => 1,
            max         => 300,
        },
        output_format => {
            type        => 'string',
            description => 'Output format for results',
            default     => 'json',
            enum        => ['json', 'xml', 'text'],
        },
        enable_cache => {
            type        => 'boolean',
            description => 'Enable response caching',
            default     => 1,
        },
    };
}

sub setup {
    my ($self) = @_;
    # Access parameters via $self->params
    my $api_endpoint = $self->params->{api_endpoint};
    my $api_key      = $self->params->{api_key};
    my $timeout      = $self->params->{timeout} // 30;
    return 1;
}

1;
```

## Common Parameter Patterns

### API Keys and Secrets

Always mark sensitive parameters as `hidden`:

```perl
api_key => {
    type        => 'string',
    description => 'API key for authentication',
    required    => 1,
    hidden      => 1,
}
```

### Numeric Parameters with Constraints

Use `min` and `max` to enforce valid ranges:

```perl
port => {
    type        => 'integer',
    description => 'Server port number',
    default     => 8080,
    min         => 1,
    max         => 65535,
}
```

### Enumerated Values

Use `enum` to restrict to specific values:

```perl
log_level => {
    type        => 'string',
    description => 'Logging level',
    default     => 'info',
    enum        => ['debug', 'info', 'warning', 'error'],
}
```

### Optional Features

Use boolean parameters for optional features:

```perl
enable_analytics => {
    type        => 'boolean',
    description => 'Enable analytics tracking',
    default     => 0,
}
```

## Base Parameters

All skills automatically inherit these base parameters from `SignalWire::Skills::SkillBase`:

- **`swaig_fields`** (object) - Additional SWAIG function metadata to merge into tool definitions
- **`skip_prompt`** (boolean) - Skip injecting prompt sections (default: false)
- **`tool_name`** (string) - Override the default tool name (useful for skills with `supports_multiple_instances`)

## Examples

### Simple Skill (No Parameters)

Skills like `datetime` and `math` that don't need configuration just return the base schema:

```perl
sub get_parameter_schema {
    return { %{ SignalWire::Skills::SkillBase->get_parameter_schema } };
}
```

### Complex Skill (Many Parameters)

Skills like `web_search` merge the base schema with several configuration options:

```perl
sub get_parameter_schema {
    return {
        %{ SignalWire::Skills::SkillBase->get_parameter_schema },

        # API credentials (hidden)
        api_key          => { type => 'string', required => 1, hidden => 1 },
        search_engine_id => { type => 'string', required => 1, hidden => 1 },

        # Configuration options
        num_results      => { type => 'integer', default => 3, min => 1, max => 10 },
        response_prefix  => { type => 'string',  default => '' },
        response_postfix => { type => 'string',  default => '' },
    };
}
```

## Best Practices

1. **Always provide descriptions** - Make parameters self-documenting
2. **Set sensible defaults** - Allow skills to work with minimal configuration
3. **Mark secrets as hidden** - Protect sensitive information in UIs
4. **Use appropriate types** - Enable proper validation and UI controls
5. **Validate in `setup()`** - Ensure all required parameters are present
6. **Merge the base schema** - Always include `SignalWire::Skills::SkillBase->get_parameter_schema`
