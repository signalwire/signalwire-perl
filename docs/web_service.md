# WebService Documentation

The `WebService` class provides static file serving capabilities for the SignalWire AI Agents SDK. It follows the same architectural pattern as `SearchService`, allowing it to run as a standalone service or alongside your AI agents.

## Table of Contents
- [Overview](#overview)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Security Features](#security-features)
- [HTTPS/SSL Support](#httpsssl-support)
- [API Endpoints](#api-endpoints)
- [Usage Examples](#usage-examples)
- [Deployment Patterns](#deployment-patterns)

## Overview

WebService is designed to serve static files with configurable security features. It's perfect for:
- Serving agent documentation and API specs
- Hosting static assets (images, CSS, JavaScript)
- Serving generated reports and exports
- Providing configuration files and templates
- Hosting agent UI components

### Key Features
- **Multiple directory mounting** - Serve different directories at different URL paths
- **Security-first design** - Authentication, CORS, security headers, file filtering
- **HTTPS support** - Full SSL/TLS support with PEM files
- **Directory browsing** - Optional HTML directory listings
- **MIME type handling** - Automatic content-type detection
- **Path traversal protection** - Prevents access outside designated directories
- **File filtering** - Allow/block specific file extensions

## Installation

WebService is included in the core SignalWire AI Agents SDK. Install the SDK's
dependencies from the repo root:

```bash
cpanm --installdeps .
```

## Quick Start

```perl
use SignalWire::Web::WebService;

# Create a service to serve files
my $service = SignalWire::Web::WebService->new(
    port        => 8002,
    directories => {
        '/docs'   => './documentation',
        '/assets' => './static/assets',
    },
);

# Start the service (non-blocking; returns the bound port)
$service->start;
# Service available at http://localhost:8002
# Basic Auth from SWML_BASIC_AUTH_USER / SWML_BASIC_AUTH_PASSWORD, if set
```

## Configuration

WebService can be configured through multiple methods (in order of priority):

### 1. Constructor Parameters

```perl
use SignalWire::Web::WebService;
my $service = SignalWire::Web::WebService->new(
    port        => 8002,                    # Port to bind to
    directories => {                        # URL path to directory mappings
        '/docs'   => './documentation',
        '/assets' => './static',
    },
    basic_auth                => [ 'admin', 'secret' ],  # Custom authentication ([user, pass])
    enable_directory_browsing => 1,                      # Allow directory listings
    allowed_extensions        => [ '.html', '.css', '.js' ],  # Whitelist extensions
    blocked_extensions        => [ '.env', '.key' ],         # Blacklist extensions
    max_file_size             => 100 * 1024 * 1024,          # Max file size (100MB)
    enable_cors               => 1,                          # Enable CORS headers
);
```

### 2. Environment Variables

```bash
# Basic authentication
export SWML_BASIC_AUTH_USER="admin"
export SWML_BASIC_AUTH_PASSWORD="secretpassword"

# SSL/HTTPS configuration
export SWML_SSL_ENABLED=true
export SWML_SSL_CERT="/path/to/cert.pem"
export SWML_SSL_KEY="/path/to/key.pem"

# Security settings
export SWML_ALLOWED_HOSTS="example.com,*.example.com"
export SWML_CORS_ORIGINS="https://app.example.com"
```

### 3. Configuration File

You can keep service settings in a `web.json` (or `swml_web.json`) file and load
it yourself — read the JSON and pass the values to the constructor. The shape:

```json
{
    "service": {
        "port": 8002,
        "directories": {
            "/docs": "./documentation",
            "/api": "./api-specs",
            "/reports": "./generated/reports"
        },
        "enable_directory_browsing": true,
        "max_file_size": 52428800,
        "allowed_extensions": [".html", ".css", ".js", ".json", ".pdf"],
        "blocked_extensions": [".env", ".key", ".pem"]
    },
    "security": {
        "basic_auth": {
            "username": "admin",
            "password": "secure123"
        },
        "ssl_enabled": true,
        "ssl_cert": "/etc/ssl/certs/server.crt",
        "ssl_key": "/etc/ssl/private/server.key",
        "allowed_hosts": ["*"],
        "cors_origins": ["*"]
    }
}
```

## Security Features

### Basic Authentication

WebService implements HTTP Basic Authentication. Credentials can be set via:

1. **Constructor**: `basic_auth => [ 'username', 'password' ]`
2. **Environment**: `SWML_BASIC_AUTH_USER` and `SWML_BASIC_AUTH_PASSWORD`
3. **None**: If neither the constructor arg nor the environment variables are set, no authentication is required

### File Security

#### Default Blocked Extensions/Files
- `.env`, `.git`, `.gitignore`
- `.key`, `.pem`, `.crt`
- `.pyc`, `__pycache__`
- `.DS_Store`, `.swp`

#### Path Traversal Protection
WebService prevents access outside designated directories:
```text
# These attempts will be blocked:
# GET /docs/../../../etc/passwd
# GET /docs/./././../config.json
```

#### File Size Limits
Default maximum file size is 100MB. Configure with:
```perl
use SignalWire::Web::WebService;
my $service = SignalWire::Web::WebService->new(max_file_size => 50 * 1024 * 1024);  # 50MB
```

### Security Headers

Automatically adds security headers to all file responses:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: SAMEORIGIN`

## HTTPS/SSL Support

WebService provides multiple ways to enable HTTPS:

### Method 1: Environment Variables

```bash
# Using file paths
export SWML_SSL_CERT="/path/to/cert.pem"
export SWML_SSL_KEY="/path/to/key.pem"

# Or using inline PEM content
export SWML_SSL_CERT_INLINE="-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIJAKLdQVPy...
-----END CERTIFICATE-----"
export SWML_SSL_KEY_INLINE="-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQE...
-----END PRIVATE KEY-----"
```

### Method 2: Direct Parameters

`start` accepts `ssl_cert` and `ssl_key` for API parity with the reference:

<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
my $service = SignalWire::Web::WebService->new(directories => { '/docs' => './docs' });
$service->start(
    ssl_cert => '/path/to/cert.pem',
    ssl_key  => '/path/to/key.pem',
);
```

### Method 3: Configuration File

```json
{
    "security": {
        "ssl_enabled": true,
        "ssl_cert": "/etc/ssl/certs/server.crt",
        "ssl_key": "/etc/ssl/private/server.key"
    }
}
```

### Generating Self-Signed Certificates

For development/testing:

```bash
# Generate a self-signed certificate
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem \
    -days 365 -nodes -subj "/CN=localhost"

# Use with WebService
export SWML_SSL_CERT="cert.pem"
export SWML_SSL_KEY="key.pem"
```

## API Endpoints

### GET /{route}/{file_path}
Serve files from mounted directories. Any request that does not match a
configured route prefix returns `404 File not found`.

**Parameters:**
- `route`: The mounted directory route (e.g., `/docs`)
- `file_path`: Path to file within the directory

**Response:**
- File content with appropriate MIME type
- 404 if file not found
- 403 if file type blocked or directory browsing disabled

## Usage Examples

### Basic File Serving

```perl
use SignalWire::Web::WebService;

# Serve documentation
my $service = SignalWire::Web::WebService->new(
    directories => {
        '/docs' => './documentation',
        '/api'  => './api-specs',
    },
);
$service->start;

# Files accessible at:
# http://localhost:8002/docs/index.html
# http://localhost:8002/api/swagger.json
```

### With Directory Browsing

<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
my $service = SignalWire::Web::WebService->new(
    directories               => { '/files' => './public' },
    enable_directory_browsing => 1,   # Allow browsing directories
);
$service->start;

# Browse files at: http://localhost:8002/files/
```

### Restricted File Types

```perl
use SignalWire::Web::WebService;
# Only serve web assets
my $service = SignalWire::Web::WebService->new(
    directories               => { '/web' => './www' },
    allowed_extensions        => [ '.html', '.css', '.js', '.png', '.jpg', '.woff2' ],
    enable_directory_browsing => 0,
);
```

### Dynamic Directory Management

<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
my $service = SignalWire::Web::WebService->new;

# Add directories after initialization
$service->add_directory('/docs', './documentation');
$service->add_directory('/reports', './generated/reports');

# Remove a directory
$service->remove_directory('/reports');

$service->start;
```

### With Custom Authentication

<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
my $service = SignalWire::Web::WebService->new(
    directories => { '/private' => './sensitive-docs' },
    basic_auth  => [ 'admin', 'super-secret-password' ],
);
$service->start;
```

### HTTPS with Let's Encrypt

<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
# Assuming you have Let's Encrypt certificates
my $service = SignalWire::Web::WebService->new(
    directories => { '/secure' => './secure-files' },
);
$service->start(
    ssl_cert => '/etc/letsencrypt/live/example.com/fullchain.pem',
    ssl_key  => '/etc/letsencrypt/live/example.com/privkey.pem',
);
```

### Multi-Environment Configuration

<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
# Development vs Production
my $service;
if ( ( $ENV{ENVIRONMENT} // '' ) eq 'production' ) {
    $service = SignalWire::Web::WebService->new(
        port                      => 443,
        directories               => { '/' => './dist' },
        enable_directory_browsing => 0,
    );
    $service->start(
        host     => '0.0.0.0',
        ssl_cert => '/etc/ssl/certs/production.crt',
        ssl_key  => '/etc/ssl/private/production.key',
    );
}
else {
    $service = SignalWire::Web::WebService->new(
        port                      => 8002,
        directories               => { '/' => './src' },
        enable_directory_browsing => 1,
    );
    $service->start;
}
```

## Deployment Patterns

### Standalone Service

Run WebService as a dedicated static file server:

<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
# web_server.pl
use SignalWire::Web::WebService;

my $service = SignalWire::Web::WebService->new(
    port        => 8002,
    directories => {
        '/docs'      => '/var/www/docs',
        '/assets'    => '/var/www/assets',
        '/downloads' => '/var/www/downloads',
    },
);
$service->start( block => 1 );   # block => 1 runs in the foreground
```

### Alongside AI Agents

Run WebService alongside your AI agents on different ports:

`start` is non-blocking by default (it forks a background child and returns
the bound port), so no explicit thread is required — start the web service,
then run the agent in the foreground:

<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
# main.pl
use SignalWire::Agent::AgentBase;
use SignalWire::Web::WebService;

# Start WebService in the background (non-blocking fork)
my $web = SignalWire::Web::WebService->new(
    port        => 8002,
    directories => { '/docs' => './agent-docs' },
);
$web->start;

# Run your agent in the foreground
my $agent = SignalWire::Agent::AgentBase->new( name => 'My Agent' );
$agent->serve( port => 3000 );   # Agent on port 3000, WebService on 8002
```

### Docker Deployment

```dockerfile
FROM perl:5.38-slim

WORKDIR /app

# Install SDK dependencies
COPY cpanfile /app/cpanfile
RUN cpanm --installdeps .

# Copy the SDK and static files
COPY ./lib /app/lib
COPY ./static /app/static
COPY ./web_server.pl /app/web_server.pl

# Expose port
EXPOSE 8002

# Run WebService in the foreground
CMD ["perl", "-Ilib", "web_server.pl"]
```

Where `web_server.pl` is the standalone script shown above (with
`$service->start( block => 1 )`).

### Systemd Service

Create `/etc/systemd/system/signalwire-web.service`:

```ini
[Unit]
Description=SignalWire Web Service
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/signalwire
Environment="SWML_SSL_CERT=/etc/ssl/certs/server.crt"
Environment="SWML_SSL_KEY=/etc/ssl/private/server.key"
ExecStart=/usr/bin/perl -Ilib /opt/signalwire/web_server.pl
Restart=always

[Install]
WantedBy=multi-user.target
```

### Nginx Reverse Proxy

For production, use Nginx as a reverse proxy:

```nginx
server {
    listen 80;
    server_name static.example.com;
    
    # Redirect to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name static.example.com;
    
    ssl_certificate /etc/ssl/certs/example.com.crt;
    ssl_certificate_key /etc/ssl/private/example.com.key;
    
    location / {
        proxy_pass http://localhost:8002;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Cache static assets
        location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
            proxy_pass http://localhost:8002;
            expires 1h;
            add_header Cache-Control "public, immutable";
        }
    }
}
```

## Best Practices

### Security
1. **Always use HTTPS in production** - Protect data in transit
2. **Change default credentials** - Never use auto-generated auth in production
3. **Restrict file types** - Use `allowed_extensions` to whitelist safe files
4. **Disable directory browsing** - Turn off in production environments
5. **Use reverse proxy** - Put Nginx/Apache in front for additional security

### Performance
1. **Set appropriate cache headers** - WebService adds 1-hour cache by default
2. **Limit file sizes** - Adjust `max_file_size` based on your needs
3. **Use CDN for static assets** - Offload traffic for better performance
4. **Compress large files** - Use gzip/brotli at reverse proxy level

### Organization
1. **Separate content types** - Use different routes for different file types
2. **Version your assets** - Include version in path (e.g., `/assets/v1/`)
3. **Use index.html** - Provide default files for directories
4. **Document your structure** - Maintain clear directory organization

## Troubleshooting

### Common Issues

**Issue: "Can't locate HTTP/Server/PSGI.pm"**
```bash
# Install the PSGI server dependency
cpanm Plack HTTP::Server::PSGI
```

**Issue: SSL certificate errors**
```perl
# Check certificate paths
print( ( -e '/path/to/cert.pem' ) ? "cert present\n" : "cert MISSING\n" );
print( ( -e '/path/to/key.pem' )  ? "key present\n"  : "key MISSING\n" );
```

**Issue: Permission denied**
```bash
# Ensure read permissions on directories
chmod -R 755 /path/to/static/files
```

**Issue: Directory not found**
```perl
use SignalWire::Web::WebService;
# Use absolute paths
use Cwd qw(abs_path);
my $service = SignalWire::Web::WebService->new(
    directories => {
        '/docs' => abs_path('./documentation'),
    },
);
```

Note: `add_directory` dies if the target path is not an existing directory,
so prefer it (over the `directories` constructor arg, which is not validated)
when you want an early, explicit failure for a missing path.

## API Reference

### WebService Class

<!-- snippet: no-compile illustrative constructor args with a list-literal yada-yada elision -->
```perl
my $service = SignalWire::Web::WebService->new(
    port                      => 8002,           # default 8002
    directories               => {},             # URL path => local directory
    basic_auth                => [ $user, $pass ],   # or omit for no auth
    enable_directory_browsing => 0,              # default 0 (false)
    allowed_extensions        => undef,          # arrayref, or undef for all
    blocked_extensions        => [ '.env', ... ],
    max_file_size             => 100 * 1024 * 1024,  # default 100MB
    enable_cors               => 1,              # default 1 (true)
);
```

#### Parameters
- `port`: Port to bind to (default: 8002)
- `directories`: Hashref mapping URL paths to local directories
- `basic_auth`: `[ username, password ]` arrayref for authentication
- `enable_directory_browsing`: Allow directory listing (default: false)
- `allowed_extensions`: Arrayref of allowed file extensions (undef = all)
- `blocked_extensions`: Arrayref of blocked file extensions
- `max_file_size`: Maximum file size in bytes (default: 100MB)
- `enable_cors`: Enable CORS headers (default: true)

#### Methods

##### start(%opts)
```perl
$service->start(
    host     => '127.0.0.1',   # default 127.0.0.1
    port     => undef,         # defaults to the constructed port; 0 = ephemeral
    ssl_cert => undef,         # accepted for parity
    ssl_key  => undef,
    block    => 0,             # 1 = run in the foreground
);
```
Start the web service. Non-blocking by default (forks a background child and
returns the bound port); pass `block => 1` to run in the foreground.

##### stop
```perl
$service->stop;
```
Stop the service and reap the background child. Safe to call when not running.

##### add_directory($route, $directory)
```perl
$service->add_directory($route, $directory);
```
Add a new directory to serve (dies if `$directory` is not an existing directory).

##### remove_directory($route)
```perl
$service->remove_directory($route);
```
Remove a directory from being served (no-op when absent).

##### psgi_app
```perl
my $app = $service->psgi_app;
```
Return the PSGI coderef, for mounting the service in your own Plack stack.

## Integration with SignalWire Agents

WebService complements AI agents by providing static file serving:

<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
package DocumentationAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';
use SignalWire::SWAIG::FunctionResult;

sub BUILD {
    my ($self) = @_;

    # Reference documentation served by WebService
    $self->prompt_add_section(
        'Documentation',
        'User documentation is available at https://example.com:8002/docs/',
    );

    $self->define_tool(
        name        => 'get_doc_link',
        description => 'Get link to a documentation page',
        parameters  => {
            type       => 'object',
            properties => {
                doc_name => { type => 'string', description => 'Name of the documentation page' },
            },
        },
        handler => sub {
            my ($args, $raw_data) = @_;
            my $doc_name = $args->{doc_name};
            return SignalWire::SWAIG::FunctionResult->new(
                "Documentation available at: https://example.com:8002/docs/$doc_name.html"
            );
        },
    );
}

package main;
use SignalWire::Web::WebService;

# Start WebService for documentation (non-blocking background child)
my $web = SignalWire::Web::WebService->new(
    port        => 8002,
    directories => { '/docs' => './documentation' },
);
$web->start;

# Run the agent in the foreground
my $agent = DocumentationAgent->new( name => 'Documentation Assistant' );
$agent->serve( port => 3000 );
```

## Summary

WebService provides a secure, configurable static file server that integrates with the SignalWire AI Agents SDK. It follows the same architectural patterns as other SDK services, making it familiar and easy to use while providing configurable security features and flexible deployment options.