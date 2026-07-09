# SignalWire SWML Service Guide

## Table of Contents
- [Introduction](#introduction)
- [Installation](#installation)
- [Basic Usage](#basic-usage)
- [Logging](#logging)
- [SWML Document Creation](#swml-document-creation)
- [Verb Handling](#verb-handling)
- [Web Service Features](#web-service-features)
- [Custom Routing Callbacks](#custom-routing-callbacks)
- [Advanced Usage](#advanced-usage)
- [API Reference](#api-reference)
- [Examples](#examples)

## Introduction

The `SignalWire::SWML::Service` class provides a foundation for creating and serving SignalWire Markup Language (SWML) documents. It serves as the base class for all SignalWire services, including AI Agents (`SignalWire::Agent::AgentBase` extends it), and handles common tasks such as:

- SWML document creation and manipulation
- Schema-driven verb construction
- Web service functionality (PSGI/Plack)
- Authentication
- SWAIG function hosting

The class is designed to be extended for specific use cases, while providing a full set of capabilities out of the box. It is built with Moo, so subclasses use `extends` and configure themselves in a `BUILD` method.

## Installation

The `SignalWire::SWML::Service` class is part of the SignalWire AI Agent SDK. Install the SDK's dependencies with cpanm:

```bash
cpanm --installdeps .
```

The SDK requires Perl 5.36 or newer.

## Basic Usage

Here's a simple example of creating an SWML service. Verbs are added to the
document through schema-driven accessor methods (`answer`, `play`, `hangup`,
etc.) provided via `AUTOLOAD` — each takes a section name (default `'main'`)
and a configuration hashref, and returns the service so calls chain:

```perl
use strict;
use warnings;
use lib 'lib';
use SignalWire::SWML::Service;

package SimpleVoiceService;
use Moo;
extends 'SignalWire::SWML::Service';

sub BUILD {
    my ($self) = @_;
    $self->build_document;
}

sub build_document {
    my ($self) = @_;

    # Add the answer verb to the main section
    $self->answer('main', {});

    # Add a play verb for the greeting
    $self->play('main', { url => 'say:Hello, thank you for calling our service.' });

    # Add a hangup verb
    $self->hangup('main', {});
}

package main;
my $service = SimpleVoiceService->new(
    name  => 'voice-service',
    route => '/voice',
    host  => '0.0.0.0',
    port  => 3000,
);

# Mount the PSGI app under any Plack server, e.g. plackup:
my $app = $service->to_psgi_app;
```

## Logging

`SignalWire::SWML::Service` uses `SignalWire::Logging`. Each service instance
holds a logger bound to a service-scoped channel. The logger is available
internally to the SDK; services and subclasses can obtain one via
`SignalWire::Logging->get_logger($name)`:

```perl
use SignalWire::Logging;
my $log = SignalWire::Logging->get_logger('signalwire.my_service');
$log->info('service_started');
$log->debug('document_created');
```

## SWML Document Creation

The `SignalWire::SWML::Service` class manipulates an underlying
`SignalWire::SWML::Document` (the `document` attribute).

### Document Structure

SWML documents have the following basic structure:

```json
{
  "version": "1.0.0",
  "sections": {
    "main": [
      { "verb1": { } },
      { "verb2": { } }
    ],
    "section1": [
      { "verb3": { } }
    ]
  }
}
```

### Document Methods

The `document` object provides:

- `add_section($name)`: Add (or ensure) a section
- `add_verb($section_name, $verb_name, $config)`: Add a verb to a section
- `add_raw_verb($section_name, $verb_hash)`: Push a pre-built verb hashref
- `get_section($name)`: Return a section's verb list
- `has_section($name)`: Whether a section exists
- `clear_section($name)`: Empty a section
- `to_hash()`: The document as a hashref
- `to_json()` / `to_pretty_json()`: The document as a JSON string

```perl
$self->document->add_section('greeting');
$self->document->add_verb('greeting', 'play', { url => 'say:Hi!' });
my $doc = $self->document->to_hash;
```

### Verb Accessors (schema-driven)

The service object also exposes every SWML verb as a method via `AUTOLOAD`.
`$self->VERB($section, $config)` validates the verb name against the SWML
schema and appends it to the named section (default `'main'`):

```perl
$self->answer('main', {});
$self->play('main', { url => 'say:Hello, world!', volume => 5 });
$self->hangup('main', {});
```

`$self->can('play')` returns true for any verb the schema recognizes.

## Verb Handling

### Verb Validation

When you call a verb accessor, the service checks the verb name against the
SignalWire SWML schema (`SignalWire::SWML::Schema`). An unrecognized verb name
raises an error rather than producing an invalid document:

```perl
# Valid verb — appended to the document
$self->play('main', { url => 'say:Hello, world!', volume => 5 });

# Unknown verb name — dies "Can't locate method ..."
$self->not_a_real_verb('main', {});
```

The schema instance is available via `$self->schema_utils` (and the verb
registry view via `$self->verb_registry`).

## Web Service Features

The `SignalWire::SWML::Service` class includes built-in web service
capabilities for serving SWML documents over PSGI/Plack.

### Endpoints

By default, a service provides the following endpoints under its `route`:

- `GET /route`: Return the SWML document
- `POST /route`: Process request data and return the SWML document
- `POST /route/swaig`: SWAIG function dispatch
- `POST /route/post_prompt`: Post-prompt handling
- `GET /health` and `GET /ready`: Unauthenticated health probes

Where `route` is the route path specified when creating the service. Build the
PSGI application with `$service->to_psgi_app`.

### Authentication

Basic authentication is automatically enforced on the protected routes.
Credentials are generated if not provided, or can be specified at construction:

```perl
use SignalWire::SWML::Service;
my $service = SignalWire::SWML::Service->new(
    name                => 'my-service',
    basic_auth_user     => 'username',
    basic_auth_password => 'password',
);
```

You can also set credentials using environment variables:
- `SWML_BASIC_AUTH_USER`
- `SWML_BASIC_AUTH_PASSWORD`

Validate or read credentials at runtime:

```perl
my $ok = $service->validate_basic_auth($user, $pass);
my ($user, $pass)         = $service->get_basic_auth_credentials;
my ($u, $p, $source)      = $service->get_basic_auth_credentials(1);  # source: provided/environment/generated
```

### Dynamic SWML Generation

Override `on_swml_request` to customize SWML documents based on request data.
Return `undef` to serve the document as built, or a hashref of modifications to
merge into the rendered document:

```perl
package DynamicService;
use Moo;
extends 'SignalWire::SWML::Service';

sub on_swml_request {
    my ($self, $request_data, $callback_path, $request) = @_;
    return unless $request_data;

    # Customize the document based on request_data
    $self->document->clear_section('main');
    $self->answer('main', {});

    if (($request_data->{caller_type} // '') eq 'vip') {
        $self->play('main', { url => 'say:Welcome VIP caller!' });
    } else {
        $self->play('main', { url => 'say:Welcome caller!' });
    }

    # Return undef to use the document we've built without modifications
    return;
}
```

## Custom Routing Callbacks

The `SignalWire::SWML::Service` class lets you register custom routing
callbacks keyed by sub-path.

### Registering a Routing Callback

Use `register_routing_callback($path, $callback)`. Note the Perl signature is
positional: the path comes first, then the callback coderef:

```perl
my $customer_cb = sub {
    my ($request, $body) = @_;

    # Example: route based on a field in the request body
    if (exists $body->{customer_id}) {
        return "/customer/$body->{customer_id}";
    }

    # Process the request normally
    return;   # undef
};

# Register the callback for a specific sub-path
$service->register_routing_callback('/customer', $customer_cb);
```

The callback receives the request and the parsed JSON body. Returning a string
redirects; returning `undef` continues normal processing.

### Serving Different Content for Different Paths

Use the `callback_path` argument passed to `on_request`/`on_swml_request` to
serve different content for different paths:

```perl
sub on_request {
    my ($self, $request_data, $callback_path) = @_;

    if (($callback_path // '') eq '/customer') {
        return {
            sections => {
                main => [
                    { answer => {} },
                    { play => { url => 'say:Welcome to customer service!' } },
                ],
            },
        };
    }
    elsif (($callback_path // '') eq '/product') {
        return {
            sections => {
                main => [
                    { answer => {} },
                    { play => { url => 'say:Welcome to product support!' } },
                ],
            },
        };
    }

    # Default content
    return;
}
```

### Example: Multi-Section Service

```perl
package MultiSectionService;
use Moo;
extends 'SignalWire::SWML::Service';

sub BUILD {
    my ($self) = @_;

    # Create the main document
    $self->answer('main', {});
    $self->play('main', { url => 'say:Hello from the main service!' });
    $self->hangup('main', {});

    # Register customer and product routes
    $self->register_customer_route;
    $self->register_product_route;
}

sub register_customer_route {
    my ($self) = @_;

    my $customer_callback = sub {
        my ($request, $body) = @_;
        if (exists $body->{customer_id}) {
            # In a real implementation, you might redirect to another service.
            # Here we process normally.
        }
        return;
    };
    $self->register_routing_callback('/customer', $customer_callback);

    # Create the customer SWML section
    $self->document->add_section('customer_section');
    $self->document->add_verb('customer_section', 'answer', {});
    $self->document->add_verb('customer_section', 'play', { url => 'say:Welcome to customer service!' });
    $self->document->add_verb('customer_section', 'hangup', {});
}

sub register_product_route {
    my ($self) = @_;

    my $product_callback = sub {
        my ($request, $body) = @_;
        return;
    };
    $self->register_routing_callback('/product', $product_callback);

    # Create the product SWML section
    $self->document->add_section('product_section');
    $self->document->add_verb('product_section', 'answer', {});
    $self->document->add_verb('product_section', 'play', { url => 'say:Welcome to product support!' });
    $self->document->add_verb('product_section', 'hangup', {});
}

sub on_request {
    my ($self, $request_data, $callback_path) = @_;
    if (($callback_path // '') eq '/customer') {
        return { sections => { main => $self->document->get_section('customer_section') } };
    }
    elsif (($callback_path // '') eq '/product') {
        return { sections => { main => $self->document->get_section('product_section') } };
    }
    return;
}
```

In this example:
1. The service registers two custom route paths: `/customer` and `/product`
2. Each path has its own callback function to handle routing decisions
3. The `on_request` method uses the `callback_path` to determine which content to serve
4. Different SWML sections are served for different paths

## Advanced Usage

### Mounting the PSGI App

`to_psgi_app` returns a PSGI coderef you can mount under any Plack handler,
including alongside other apps with `Plack::Builder`:

```perl
use SignalWire::SWML::Service;
use Plack::Builder;

my $service = SignalWire::SWML::Service->new(name => 'my-service', route => '/voice');

my $app = builder {
    mount '/voice' => $service->to_psgi_app;
};
```

### Static SIP Username Extraction

`extract_sip_username($request_body)` is a helper (callable as a class or
instance method) that pulls the caller's SIP username out of a request body's
`call.to`/`call.from` field:

```perl
use SignalWire::SWML::Service;
my $user = SignalWire::SWML::Service->extract_sip_username($request_body);
```

## API Reference

### Constructor Parameters

- `name`: Service name/identifier (default: `'service'`)
- `route`: HTTP route path (default: `'/'`)
- `host`: Host to bind to (default: `'0.0.0.0'`, or `$SWML_HOST`)
- `port`: Port to bind to (default: `3000`, or `$SWML_PORT`)
- `basic_auth_user`: Basic-auth username (default: `$SWML_BASIC_AUTH_USER` or random)
- `basic_auth_password`: Basic-auth password (default: `$SWML_BASIC_AUTH_PASSWORD` or random)

### Document Methods (on `$service->document`)

- `add_section($name)`
- `add_verb($section_name, $verb_name, $config)`
- `add_raw_verb($section_name, $verb_hash)`
- `get_section($name)` / `has_section($name)` / `clear_section($name)`
- `to_hash()` / `to_json()` / `to_pretty_json()`

### Service Methods

- `to_psgi_app()`: Return the PSGI application coderef
- `render_main_swml($env)` / `render_swml($env)`: Render the document hashref
- `on_request($request_data, $callback_path)`: Override point for SWML generation
- `on_swml_request($request_data, $callback_path, $request)`: Lower-level override point
- `register_routing_callback($path, $callback)`: Register a callback for request routing
- `validate_basic_auth($user, $pass)`: Constant-time credential check
- `get_basic_auth_credentials($include_source)`: Read the basic-auth credentials
- `extract_sip_username($request_body)`: Pull the SIP username from a request body
- `schema_utils()` / `verb_registry()` / `security()`: Introspection accessors

### SWAIG Tool Methods (a service can host SWAIG functions too)

- `define_tool(name =>, description =>, parameters =>, handler =>)`
- `register_swaig_function($func_def)`
- `define_tools(@tool_defs)`
- `has_function($name)` / `get_function($name)` / `get_all_functions()` / `remove_function($name)`
- `on_function_call($name, $args, $raw_data)`
- `list_tool_names()`

### Verb Accessors

- `$service->VERB($section, $config)`: Any schema-recognized SWML verb

## Examples

### Basic Voicemail Service

```perl
package VoicemailService;
use Moo;
use JSON ();
extends 'SignalWire::SWML::Service';

sub BUILD {
    my ($self) = @_;
    $self->build_voicemail_document;
}

sub build_voicemail_document {
    my ($self) = @_;

    # Answer the call
    $self->answer('main', {});

    # Greeting
    $self->play('main', {
        url => 'say:Hello, you\'ve reached the voicemail service. Please leave a message after the beep.',
    });

    # Play a beep
    $self->play('main', { url => 'https://example.com/beep.wav' });

    # Record the message
    $self->record('main', {
        format      => 'mp3',
        stereo      => JSON::false,
        max_length  => 120,        # 2 minutes max
        terminators => '#',
    });

    # Thank the caller
    $self->play('main', { url => 'say:Thank you for your message. Goodbye!' });

    # Hang up
    $self->hangup('main', {});
}

package main;
my $service = VoicemailService->new(
    name  => 'voicemail',
    route => '/voicemail',
    host  => '0.0.0.0',
    port  => 3000,
);
my $app = $service->to_psgi_app;
```

### Dynamic Call Routing Service

```perl
package CallRouterService;
use Moo;
use JSON ();
extends 'SignalWire::SWML::Service';

sub on_swml_request {
    my ($self, $request_data, $callback_path, $request) = @_;

    # If there's no request data, use the default document
    return unless $request_data;

    # Rebuild the main section
    $self->document->clear_section('main');
    $self->answer('main', {});

    # Get routing parameters
    my $department = lc($request_data->{department} // '');

    # Greeting
    $self->play('main', {
        url => "say:Thank you for calling our $department department. Please hold.",
    });

    # Route based on department
    my %phone_numbers = (
        sales   => '+15551112222',
        support => '+15553334444',
        billing => '+15555556666',
    );
    my $to_number = $phone_numbers{$department} // '+15559990000';

    # Connect to the department
    $self->connect('main', {
        to               => $to_number,
        timeout          => 30,
        answer_on_bridge => JSON::true,
    });

    # Fallback message and hangup
    $self->play('main', {
        url => 'say:We\'re sorry, but all of our agents are currently busy. Please try again later.',
    });
    $self->hangup('main', {});

    return;   # use the document we've built
}
```

For more examples, see the `examples/` directory in the SignalWire AI Agent SDK repository.
