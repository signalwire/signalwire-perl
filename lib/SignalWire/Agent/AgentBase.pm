package SignalWire::Agent::AgentBase;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.

use strict;
use warnings;
use Moo;
use SignalWire::SWML::Service;
extends 'SignalWire::SWML::Service';
use JSON         qw(encode_json decode_json);
use MIME::Base64 qw(encode_base64 decode_base64);
use Digest::SHA  qw(hmac_sha256_hex);
use POSIX        qw(strftime);
use Scalar::Util qw(blessed reftype);
use Storable     qw(dclone);
use Carp         qw(croak carp);

# ---------- attributes ----------

# name, route, host, port, basic_auth_user, basic_auth_password, document,
# tools, tool_order, routing_callbacks are inherited from Service.
# Override AgentBase's defaults where they diverge from Service's:
has '+name' => ( default => sub { 'agent' } );
has '+port' => ( default => sub { $ENV{PORT} || 3000 } );
has '+basic_auth_user' => (
    lazy    => 1,
    builder => '_build_basic_auth_user',
);
has '+basic_auth_password' => (
    lazy    => 1,
    builder => '_build_basic_auth_password',
);

# Call settings
has auto_answer   => ( is => 'rw', default => sub { 1 } );
has record_call   => ( is => 'rw', default => sub { 0 } );
has record_format => ( is => 'rw', default => sub { 'mp4' } );
has record_stereo => ( is => 'rw', default => sub { 1 } );

# Prompt system
has prompt_text  => ( init_arg => undef, is      => 'rw', default => sub { '' } );
has post_prompt  => ( init_arg => undef, is      => 'rw', default => sub { '' } );
has use_pom      => ( is       => 'rw',  default => sub { 1 } );
has pom_sections => ( init_arg => undef, is      => 'rw', default => sub { [] } );

# Tool registry — `tools` and `tool_order` are now declared on Service
# (lifted so non-agent SWML services can host SWAIG functions). Inherited.

# AI config
has hints            => ( init_arg => undef, is      => 'rw', default => sub { [] } );
has pattern_hints    => ( init_arg => undef, is      => 'rw', default => sub { [] } );
has languages        => ( init_arg => undef, is      => 'rw', default => sub { [] } );
has multilingual     => ( init_arg => undef, is      => 'rw', default => sub { undef } );
has pronunciations   => ( init_arg => undef, is      => 'rw', default => sub { [] } );
has params           => ( init_arg => undef, is      => 'rw', default => sub { {} } );
has global_data      => ( init_arg => undef, is      => 'rw', default => sub { {} } );
has native_functions => ( is       => 'rw',  default => sub { [] } );

# Internal settings
has internal_fillers   => ( init_arg => undef, is => 'rw', default => sub { undef } );
has debug_events_level => ( init_arg => undef, is => 'rw', default => sub { 0 } );

# Includes and LLM params
has function_includes      => ( init_arg => undef, is => 'rw', default => sub { [] } );
has prompt_llm_params      => ( init_arg => undef, is => 'rw', default => sub { {} } );
has post_prompt_llm_params => ( init_arg => undef, is => 'rw', default => sub { {} } );

# Verb insertion points
has pre_answer_verbs  => ( init_arg => undef, is => 'rw', default => sub { [] } );
has post_answer_verbs => ( init_arg => undef, is => 'rw', default => sub { [] } );
has post_ai_verbs     => ( init_arg => undef, is => 'rw', default => sub { [] } );
has answer_config     => ( init_arg => undef, is => 'rw', default => sub { {} } );

# SIP routing (Python parity: AgentBase SIP username mapping).
has sip_routing_enabled => ( init_arg => undef, is => 'rw', default => sub { 0 } );
has sip_auto_map        => ( init_arg => undef, is => 'rw', default => sub { 1 } );
has sip_path            => ( init_arg => undef, is => 'rw', default => sub { '/sip' } );
has sip_usernames       => ( init_arg => undef, is => 'rw', default => sub { [] } );

# Context system (lazy)
has context_builder => (
    init_arg => undef,
    is       => 'rw',
    lazy     => 1,
    builder  => '_build_context_builder',
);

# Callbacks
has dynamic_config_callback => ( init_arg => undef, is => 'rw', default => sub { undef } );
has summary_callback        => ( init_arg => undef, is => 'rw', default => sub { undef } );
has debug_event_handler     => ( init_arg => undef, is => 'rw', default => sub { undef } );

# URLs
has webhook_url     => ( init_arg => undef, is => 'rw', default => sub { undef } );
has post_prompt_url => ( init_arg => undef, is => 'rw', default => sub { undef } );
has proxy_url_base =>
    ( init_arg => undef, is => 'rw', lazy => 1, builder => '_build_proxy_url_base' );
has swaig_query_params => ( init_arg => undef, is => 'rw', default => sub { {} } );

# Python parity: AgentBase.__init__(token_expiry_secs=3600). The reference does
# NOT store this on self — it FORWARDS it to the SessionManager collaborator
# (agent_base.py:247: SessionManager(token_expiry_secs=token_expiry_secs)).
has token_expiry_secs => ( is => 'rw', default => sub { 3600 } );

# Session manager — built lazily so it picks up token_expiry_secs.
has session_manager => (
    init_arg => undef,
    is       => 'rw',
    lazy     => 1,
    builder  => '_build_session_manager',
);

sub _build_session_manager {
    my ($self) = @_;
    require SignalWire::Security::SessionManager;
    return SignalWire::Security::SessionManager->new(
        token_expiry_secs => $self->token_expiry_secs );
}

# Python parity: AgentBase.__init__(agent_id=None) — "Optional unique ID for
# this agent, generated if not provided" (agent_base.py:229:
# self.agent_id = agent_id or str(uuid.uuid4())).
has agent_id => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_agent_id',
);

sub _build_agent_id {
    return _generate_uuid4();
}

# Python parity: AgentBase.__init__(default_webhook_url=None) — "Optional
# default webhook URL for all SWAIG functions". Stored on the agent
# (agent_base.py:225: self._default_webhook_url = default_webhook_url).
has default_webhook_url => ( is => 'rw', default => sub { undef } );

# Python parity: AgentBase.__init__(suppress_logs=False) — "Whether to suppress
# structured logs" (agent_base.py:226). Consulted on the request-handling path.
has suppress_logs => ( is => 'rw', default => sub { 0 } );

# The active call's id for the DURATION of one SWML render. Python threads it as
# the ``_render_swml(call_id)`` parameter (agent_base.py:867); Perl's public
# render_swml($request_env) keeps its signature and carries the call_id here so a
# SECURE tool's rendered webhook gets its per-tool ``__token``
# (agent_base.py:1040). Set + cleared by _render_swml_for_call; never a
# constructor arg (it is per-render state, not configuration).
#
# PRIVATE (leading underscore): the reference carries this as a PARAMETER, not an
# attribute, so a public accessor here would be public surface the reference
# lacks. Underscore-named, it is internal render state and adds no surface.
has _render_call_id => ( init_arg => undef, is => 'rw', default => sub { undef } );

# Python parity: AgentBase.__init__(enable_post_prompt_override=False) /
# (check_for_input_override=False). The reference accepts and documents both;
# neither is consulted elsewhere in the reference, so they are stored verbatim.
has enable_post_prompt_override => ( is => 'rw', default => sub { 0 } );
has check_for_input_override    => ( is => 'rw', default => sub { 0 } );

# Python parity: AgentBase.__init__(trust_proxy_for_signature=False) — "If True,
# honor X-Forwarded-Proto / X-Forwarded-Host when reconstructing the URL during
# signature validation. Default False — proxy headers are spoofable, so opt in
# only when you control the proxy chain." FORWARDED to WebhookMiddleware.
has trust_proxy_for_signature => ( is => 'rw', default => sub { 0 } );

# Webhook signature validation. When set (or SIGNALWIRE_SIGNING_KEY env
# is non-empty), the PSGI app auto-mounts SignalWire::Security::WebhookMiddleware
# on POST /, POST /swaig, POST /post_prompt and rejects unsigned/invalid
# requests with 403. When unset, AgentBase logs a prominent startup
# warning the first time psgi_app is built.
has signing_key => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_signing_key',
);

sub _build_signing_key {
    my ($self) = @_;
    return $ENV{SIGNALWIRE_SIGNING_KEY};
}

# Skill manager
has skill_manager => ( is => 'rw', lazy => 1, builder => '_build_skill_manager' );

# MCP integration
has mcp_servers        => ( init_arg => undef, is => 'rw', default => sub { [] } );
has mcp_server_enabled => ( init_arg => undef, is => 'rw', default => sub { 0 } );

# ---------- builders ----------

sub _build_basic_auth_user {
    my ($self) = @_;
    return $ENV{SWML_BASIC_AUTH_USER} || $self->name;
}

sub _build_basic_auth_password {
    my ($self) = @_;
    return $ENV{SWML_BASIC_AUTH_PASSWORD} if $ENV{SWML_BASIC_AUTH_PASSWORD};

    my $password = _generate_random_password();

    # Warn loudly so external callers (tests, RPC clients, MCP) know why
    # they are getting HTTP 401. This is the silent cause of every
    # external caller failing when .env wasn't loaded — the password
    # lives only in this process and changes on every restart.
    carp "basic_auth_password_autogenerated: username=\""
        . ( $self->basic_auth_user || $self->name ) . "\". "
        . "No SWML_BASIC_AUTH_PASSWORD found in environment and no "
        . "basic_auth_password passed to the agent constructor. The SDK "
        . "generated a random password that exists only in this process; "
        . "external callers will get HTTP 401 unless they read the value "
        . "from this process's env. To fix, set SWML_BASIC_AUTH_USER and "
        . "SWML_BASIC_AUTH_PASSWORD in your environment, or pass "
        . "basic_auth_user => ... , basic_auth_password => ... to "
        . "AgentBase->new(...).";
    return $password;
}

sub _build_proxy_url_base {
    return $ENV{SWML_PROXY_URL_BASE} || undef;
}

sub _build_context_builder {
    require SignalWire::Contexts::ContextBuilder;
    return SignalWire::Contexts::ContextBuilder->new;
}

sub _build_skill_manager {
    my ($self) = @_;
    require SignalWire::Skills::SkillManager;
    return SignalWire::Skills::SkillManager->new( agent => $self );
}

sub BUILD {
    my ($self) = @_;

    # Strip trailing slash from route
    my $r = $self->route;
    $r =~ s{/+$}{} if $r ne '/';
    $self->route($r);

    return;
}

# Python parity: AgentBase.__init__ loads the config file's ``service`` section
# BEFORE initializing the base service, and applies route/host/port/name from it
# with CONSTRUCTOR PARAMETERS TAKING PRECEDENCE (agent_base.py:189-196):
#
#   final_route = route if route != "/" else service_config.get("route", route)
#   final_host  = host  if host  != "0.0.0.0" else service_config.get("host", host)
#   final_port  = port if port is not None else service_config.get("port", None)
#   final_name  = service_config.get("name", name)
#
# Perl's construction is Moo's generated ``new``, so the equivalent hook is
# BUILDARGS: fold the config values into the argument hash before the
# attributes are built. Service::BUILDARGS (which unfolds the ``basic_auth``
# pair) runs as part of the same chain via SUPER.
sub BUILDARGS {
    my ( $class, @args ) = @_;
    my $args = $class->SUPER::BUILDARGS(@args);

    my $service_config = _load_service_config( $args->{config_file}, $args->{name} );
    return $args unless %$service_config;

    # Constructor parameters take precedence over the config file; the config
    # file supplies the value only where the caller did not (matching the
    # reference's default-sentinel comparisons).
    $args->{route} = $service_config->{route}
        if !defined $args->{route} && defined $service_config->{route};
    $args->{host} = $service_config->{host}
        if !defined $args->{host} && defined $service_config->{host};
    $args->{port} = $service_config->{port}
        if !defined $args->{port} && defined $service_config->{port};
    $args->{name} = $service_config->{name} if defined $service_config->{name};

    return $args;
}

# Python parity: AgentBase._load_service_config(config_file, service_name) —
# a @staticmethod that finds the config file (falling back to
# ConfigLoader.find_config_file when none was passed), loads it, and returns
# its ``service`` section, or {} (agent_base.py:358-382).
sub _load_service_config {
    my ( $config_file, $service_name ) = @_;

    require SignalWire::Core::ConfigLoader;

    $config_file //= SignalWire::Core::ConfigLoader->find_config_file($service_name);
    return {} unless $config_file;

    my $loader = SignalWire::Core::ConfigLoader->new( [$config_file] );
    return {} unless $loader->has_config;

    my $section = $loader->get_section('service');
    return ref $section eq 'HASH' ? $section : {};
}

# RFC 4122 version-4 UUID (Python parity: str(uuid.uuid4())). Uses the same
# CSPRNG source as the credential generator.
sub _generate_uuid4 {
    my @octets = map { int( rand 256 ) } 1 .. 16;
    if ( open my $fh, '<:raw', '/dev/urandom' ) {
        my $bytes = '';
        if ( read( $fh, $bytes, 16 ) == 16 ) {
            @octets = unpack 'C16', $bytes;
        }
        close $fh;
    }
    $octets[6] = ( $octets[6] & 0x0f ) | 0x40;    # version 4
    $octets[8] = ( $octets[8] & 0x3f ) | 0x80;    # variant 10xx
    my $hex = join '', map { sprintf '%02x', $_ } @octets;
    return join '-', substr( $hex, 0, 8 ), substr( $hex, 8, 4 ), substr( $hex, 12, 4 ),
        substr( $hex, 16, 4 ), substr( $hex, 20, 12 );
}

# ---------- Prompt methods ----------

sub set_prompt_text {
    my ( $self, $text ) = @_;
    $self->prompt_text($text);
    return $self;
}

sub set_post_prompt {
    my ( $self, $text ) = @_;
    $self->post_prompt($text);
    return $self;
}

sub prompt_add_section {
    my ( $self, $title, $body, %opts ) = @_;
    my $section = { title => $title };

    # Python parity: signalwire.pom Section.to_dict emits ``body`` only when
    # it is non-empty (``if self.body``). Mirror that here so a bullets-only
    # section renders without a spurious ``body => ""`` key.
    $section->{body}    = $body          if defined $body && length $body;
    $section->{bullets} = $opts{bullets} if $opts{bullets};
    push @{ $self->pom_sections }, $section;
    return $self;
}

sub prompt_add_subsection {
    my ( $self, $parent_title, $title, $body, %opts ) = @_;

    # Auto-create the parent section when absent. TS parity:
    # PomBuilder.addSubsection does `if (!sectionMap.has(parentTitle))
    # this.addSection(parentTitle)` before attaching the subsection.
    $self->prompt_add_section($parent_title)
        unless $self->prompt_has_section($parent_title);

    for my $sec ( @{ $self->pom_sections } ) {
        if ( $sec->{title} eq $parent_title ) {
            $sec->{subsections} //= [];
            my $sub = { title => $title, body => $body // '' };
            $sub->{bullets} = $opts{bullets} if $opts{bullets};
            push @{ $sec->{subsections} }, $sub;
            last;
        }
    }
    return $self;
}

sub prompt_add_to_section {
    my ( $self, $title, %opts ) = @_;

    # Auto-create the section when absent. TS parity:
    # PomBuilder.addToSection does `if (!sectionMap.has(title))
    # this.addSection(title)` before appending body/bullets.
    $self->prompt_add_section($title)
        unless $self->prompt_has_section($title);

    for my $sec ( @{ $self->pom_sections } ) {
        if ( $sec->{title} eq $title ) {
            if ( $opts{body} ) {
                $sec->{body} .= "\n" . $opts{body};
            }
            if ( $opts{bullets} ) {
                $sec->{bullets} //= [];
                push @{ $sec->{bullets} }, @{ $opts{bullets} };
            }
            last;
        }
    }
    return $self;
}

sub prompt_has_section {
    my ( $self, $title ) = @_;
    for my $sec ( @{ $self->pom_sections } ) {
        return 1 if $sec->{title} eq $title;
    }
    return 0;
}

sub get_prompt {
    my ($self) = @_;
    if ( $self->use_pom && @{ $self->pom_sections } ) {
        return $self->pom_sections;
    }
    return $self->prompt_text;
}

# Read-only snapshot of the agent's POM as a typed
# SignalWire::POM::PromptObjectModel object.
#
# Python parity: ``agent.pom`` instance attribute (agent_base.py
# line 209) — Python returns a PromptObjectModel instance built from
# ``pom_sections`` (or None when ``use_pom`` is false). This Perl port
# mirrors that contract: undef when use_pom is off, otherwise a fresh
# PromptObjectModel constructed from a deep-cloned copy of the
# internal section list so caller mutations cannot leak back.
sub pom {
    my ($self) = @_;
    return unless $self->use_pom;
    require Storable;
    require SignalWire::POM::PromptObjectModel;
    my $cloned = Storable::dclone( $self->pom_sections );

    # Empty pom_sections still returns a PromptObjectModel (Python
    # parity: ``self.pom = PromptObjectModel()`` even when no sections
    # have been added).
    return SignalWire::POM::PromptObjectModel->new if !@$cloned;
    return SignalWire::POM::PromptObjectModel->_from_data($cloned);
}

# Returns the post-prompt text whatever set_post_prompt stored, or
# the empty string when none has been set.
#
# Mirrors Python's PromptManager.get_post_prompt /
# PromptMixin.get_post_prompt — used by SWML rendering when a
# post-prompt is configured.
sub get_post_prompt {
    my ($self) = @_;
    return $self->post_prompt;
}

# Returns the raw prompt text whatever set_prompt_text stored, or the
# empty string when no raw prompt has been set. Distinct from
# get_prompt which may return the POM array when use_pom is true.
#
# Mirrors Python's PromptManager.get_raw_prompt.
sub get_raw_prompt {
    my ($self) = @_;
    return $self->prompt_text;
}

# Sets the prompt as a list of POM section hashes. Each section hash
# supports keys "title", "body", "bullets", "numbered",
# "numbered_bullets", and "subsections". Switches the agent to POM
# mode.
#
# Mirrors Python's PromptManager.set_prompt_pom — accepts a list of
# section dicts and stores them in pom_sections.
sub set_prompt_pom {
    my ( $self, $pom ) = @_;
    $self->use_pom(1);
    $pom //= [];
    $self->pom_sections( [@$pom] );
    return $self;
}

# Returns the contexts dictionary as a hashref of serialised SWML, or
# undef when no contexts have been defined yet.
#
# Mirrors Python's PromptManager.get_contexts which returns the
# contexts dict or None.
sub get_contexts {
    my ($self) = @_;
    my $cb = $self->context_builder;
    return unless defined $cb;
    return $cb->to_hash;
}

# ---------- Tool methods ----------

#
# define_tool — register a SWAIG tool (function) that the AI can invoke
# during a call.
#
# HOW THIS BECOMES A TOOL THE MODEL SEES
#
# A SWAIG function is EXACTLY THE SAME CONCEPT as a "tool" in native
# OpenAI / Anthropic tool calling. On every LLM turn, the SDK renders
# each registered SWAIG function into the OpenAI tool schema:
#
#   {
#     "type": "function",
#     "function": {
#       "name":        "your_name_here",
#       "description": "your description text",
#       "parameters":  { ... your JSON schema ... }
#     }
#   }
#
# That schema is sent to the model as part of the same API call that
# produces the next assistant message. The model reads:
#
#   - the function `description` to decide WHEN to call this tool
#   - each parameter `description` (inside parameters) to decide HOW
#     to fill in that argument from the user's utterance
#
# This means DESCRIPTIONS ARE PROMPT ENGINEERING, not developer
# comments. A vague description is the #1 cause of "the model has the
# right tool but doesn't call it" failures.
#
# BAD vs GOOD descriptions:
#
#   BAD : description => 'Lookup function'
#   GOOD: description => 'Look up a customer\'s account details by '
#                      . 'account number. Use this BEFORE quoting any '
#                      . 'account-specific info (balance, plan, '
#                      . 'status). Do not use for general product '
#                      . 'questions.'
#
#   BAD : parameters => { id => { type=>'string', description=>'the id' } }
#   GOOD: parameters => { account_number => { type=>'string',
#             description => 'The customer\'s 8-digit account number, '
#                          . 'no dashes or spaces. Ask the user if they '
#                          . 'don\'t provide it.' } }
#
# TOOL COUNT MATTERS: LLM tool selection accuracy degrades past ~7-8
# simultaneously-active tools per call. Use Step->set_functions() to
# partition tools across steps so only the relevant subset is active at
# any moment. See SignalWire::Contexts.
#
# define_tool, register_swaig_function, define_tools, on_function_call are
# provided by SignalWire::SWML::Service (parent). Inherited via `extends`.

# Mint a per-call SWAIG-function token via the agent's SessionManager.
#
# Python parity: state_mixin.StateMixin._create_tool_token —
# delegates to SessionManager->create_tool_token and returns "" on any
# raised error (Python catches all exceptions and returns "").
sub create_tool_token {
    my ( $self, $tool_name, $call_id ) = @_;
    my $token = '';
    eval {
        $token = $self->session_manager->create_tool_token( $tool_name, $call_id );
        1;
    } or do {
        return '';
    };
    return $token;
}

# Validate a per-call SWAIG-function token. Returns false (0) when the
# function is not registered, when the SessionManager rejects the token,
# or on any underlying exception.
#
# Python parity: state_mixin.StateMixin.validate_tool_token —
# rejects unknown function names up-front and swallows errors.
sub validate_tool_token {
    my ( $self, $function_name, $token, $call_id ) = @_;
    return 0 unless $self->has_function($function_name);
    my $result = 0;
    eval {
        # Note: Perl SessionManager's validate_token signature is
        # (call_id, function_name, token), not the Python order. The
        # AgentBase facade keeps the Python order so callers can write
        # the same code across languages.
        $result = $self->session_manager->validate_token( $call_id, $function_name, $token );
        1;
    } or do {
        return 0;
    };
    return $result ? 1 : 0;
}

# ---------- AI Config methods ----------

sub add_hint {
    my ( $self, $hint ) = @_;
    push @{ $self->hints }, $hint;
    return $self;
}

sub add_hints {
    my ( $self, $hints ) = @_;

    # Python parity: add_hints(hints: List[str]). Accept an arrayref
    # as the canonical form. Backward-compat: also accept slurpy
    # (``add_hints('a', 'b', 'c')``) when the first arg is a string.
    if ( ref $hints eq 'ARRAY' ) {
        for my $h (@$hints) {
            push @{ $self->hints }, $h if defined $h && !ref($h) && length $h;
        }
    } else {

        # Slurpy form — re-grab @_ skipping $self.
        my @rest = @_;
        shift @rest;
        for my $h (@rest) {
            push @{ $self->hints }, $h if defined $h && !ref($h) && length $h;
        }
    }
    return $self;
}

# Add a complex pattern-matching hint. Perl hashref-kwargs idiom of
# Python's add_pattern_hint(hint, pattern, replace, ignore_case=False):
# the caller passes a hashref carrying { hint, pattern, replace,
# ignore_case }. A STRUCTURED hint dict (not a bare string) is appended
# to pattern_hints and flows into the rendered SWML ``ai.hints`` list,
# byte-parity with Python's ``self._hints.append({...})``. Matches
# Python's guard: only appended when hint, pattern, AND replace are all
# truthy; ignore_case defaults to false.
sub add_pattern_hint {
    my ( $self, $args ) = @_;
    $args = {} unless defined $args && ref($args) eq 'HASH';

    my $hint    = $args->{hint};
    my $pattern = $args->{pattern};
    my $replace = $args->{replace};
    my $ignore_case =
        exists $args->{ignore_case}
        ? ( $args->{ignore_case} ? JSON::true : JSON::false )
        : JSON::false;

    if (   defined $hint
        && length $hint
        && defined $pattern
        && length $pattern
        && defined $replace
        && length $replace )
    {
        push @{ $self->pattern_hints },
            {
            hint        => $hint,
            pattern     => $pattern,
            replace     => $replace,
            ignore_case => $ignore_case,
            };
    }
    return $self;
}

sub add_language {
    my ( $self, %lang ) = @_;

    # Per-language params (engine-specific tuning, voice settings, etc.).
    # Python parity (commit 029ca6f): only emit the ``params`` key when
    # the supplied hashref is non-empty so SWML stays byte-identical for
    # existing callers who don't pass params. Treat an explicit empty
    # hashref the same as "not passed".
    if ( exists $lang{params} ) {
        my $p = $lang{params};
        if ( !defined $p || ref($p) ne 'HASH' || !%$p ) {
            delete $lang{params};
        }
    }
    push @{ $self->languages }, \%lang;
    return $self;
}

sub set_languages {
    my ( $self, $langs ) = @_;
    $self->languages($langs);
    return $self;
}

# Configure ASR-driven multilingual mode (Mode B). Emits a top-level
# ``multilingual`` object on the AI verb: the recognizer runs in
# code-switching mode and the agent answers in whatever language the caller
# actually spoke. Mutually exclusive with set_languages() — when both are
# set the server prefers ``multilingual`` and ignores ``languages``. Mirrors
# AIConfigMixin.set_multilingual: an empty/non-hash config is a no-op so the
# rendered SWML is unchanged. Returns $self for chaining.
sub set_multilingual {
    my ( $self, $config ) = @_;
    if ( defined $config && ref($config) eq 'HASH' && %$config ) {
        $self->multilingual($config);
    }
    return $self;
}

# Set (or replace) the per-language ``params`` hashref on an
# already-added language. Python parity (commit 029ca6f): empty hashref
# removes the key; unknown ``code`` is a no-op; always returns $self
# for chaining.
sub set_language_params {
    my ( $self, $code, $params ) = @_;
    for my $language ( @{ $self->languages } ) {
        next unless defined $language->{code} && $language->{code} eq $code;
        if ( defined $params && ref($params) eq 'HASH' && %$params ) {
            $language->{params} = $params;
        } else {
            delete $language->{params};
        }
        last;
    }
    return $self;
}

# Read the per-language ``params`` hashref for a previously-added
# language. Returns undef when the code is unknown or when params were
# never set — no exception path (matches Python's ``return None``).
sub get_language_params {
    my ( $self, $code ) = @_;
    for my $language ( @{ $self->languages } ) {
        next unless defined $language->{code} && $language->{code} eq $code;
        return $language->{params};
    }
    return;
}

sub add_pronunciation {
    my ( $self, %pron ) = @_;
    push @{ $self->pronunciations }, \%pron;
    return $self;
}

sub set_pronunciations {
    my ( $self, $prons ) = @_;
    $self->pronunciations($prons);
    return $self;
}

sub set_param {
    my ( $self, $key, $value ) = @_;
    $self->params->{$key} = $value;
    return $self;
}

sub set_params {
    my ( $self, $p ) = @_;
    $self->params( { %{ $self->params }, %$p } );
    return $self;
}

sub set_global_data {
    my ( $self, $data ) = @_;

    # MERGES $data into the existing global_data — despite the name, this
    # does NOT replace. Existing keys are preserved; incoming keys overwrite
    # only on collision. Identical to update_global_data. TS parity:
    # AgentBase.setGlobalData calls safeAssign(this.globalData, data) (the
    # same merge as updateGlobalData); Python's set_global_data is a dict
    # .update(). A replacing set_global_data would silently clobber
    # skill-contributed keys.
    $self->global_data( { %{ $self->global_data }, %$data } );
    return $self;
}

sub update_global_data {
    my ( $self, $data ) = @_;
    $self->global_data( { %{ $self->global_data }, %$data } );
    return $self;
}

sub set_native_functions {
    my ( $self, $funcs ) = @_;
    $self->native_functions($funcs);
    return $self;
}

#
# The complete set of internal SWAIG function names that accept fillers,
# matching the SWAIGInternalFiller schema definition. Any name outside
# this set is silently ignored by the runtime — set_internal_fillers and
# add_internal_filler warn if you pass an unknown name.
#
# Notable absences: change_step, gather_submit, and arbitrary user-defined
# SWAIG function names are NOT supported.
#
our %SUPPORTED_INTERNAL_FILLER_NAMES = (
    hangup                  => 1,    # AI is hanging up the call
    check_time              => 1,    # AI is checking the time
    wait_for_user           => 1,    # AI is waiting for user input
    wait_seconds            => 1,    # deliberate pause / wait period
    adjust_response_latency => 1,    # AI is adjusting response timing
    next_step               => 1,    # transitioning between steps in prompt.contexts
    change_context          => 1,    # switching between contexts in prompt.contexts
    get_visual_input        => 1,    # processing visual input (enable_vision)
    get_ideal_strategy      => 1,    # thinking (enable_thinking)
);

#
# set_internal_fillers — set internal fillers for native SWAIG functions.
#
# Internal fillers are short phrases the AI agent speaks (via TTS) while
# an internal/native function is running, so the caller doesn't hear
# dead air during transitions or background work.
#
# Supported function names (match the SWAIGInternalFiller schema):
#   hangup, check_time, wait_for_user, wait_seconds,
#   adjust_response_latency, next_step, change_context,
#   get_visual_input, get_ideal_strategy
#
# Notably NOT supported: change_step, gather_submit, or arbitrary
# user-defined SWAIG function names. The runtime only honors fillers for
# the names listed above; everything else is silently ignored at the
# SWML level. This method warns at registration time if you pass an
# unknown name so you catch the typo early.
#
# Expected format:
#   { function_name => { language_code => [ phrase1, phrase2, ... ] } }
#
sub set_internal_fillers {
    my ( $self, $fillers ) = @_;
    if ( ref $fillers eq 'HASH' ) {
        my @unknown = sort grep { !exists $SUPPORTED_INTERNAL_FILLER_NAMES{$_} }
            keys %$fillers;
        if (@unknown) {
            my @supported = sort keys %SUPPORTED_INTERNAL_FILLER_NAMES;
            carp "unknown_internal_filler_names: ["
                . join( ', ', map { "'$_'" } @unknown )
                . "]. set_internal_fillers received names that the SWML "
                . "schema does not recognize. Those entries will be "
                . "ignored by the runtime. Supported names: ["
                . join( ', ', map { "'$_'" } @supported ) . "].";
        }
    }
    $self->internal_fillers($fillers);
    return $self;
}

#
# add_internal_filler — add a single internal filler entry.
#
# See set_internal_fillers for the complete list of supported internal
# function names and what fillers do. Calling with a function name
# outside the supported set logs a warning but the entry is still stored.
#
# Three calling conventions are supported:
#
#   $agent->add_internal_filler('plain text')       # legacy: raw scalar
#   $agent->add_internal_filler({ ... })             # legacy: raw hashref
#   $agent->add_internal_filler($function_name, $lang_code, \@phrases)
#
sub add_internal_filler {
    my ( $self, @args ) = @_;

    # Legacy forms: single scalar or single hashref — preserve existing
    # behavior (push onto the flat arrayref).
    if ( @args == 1 ) {
        my $filler = $args[0];
        if ( !defined $self->internal_fillers ) {
            $self->internal_fillers( [] );
        }
        my $store = $self->internal_fillers;
        push @$store, $filler if ref $store eq 'ARRAY';
        return $self;
    }

    # New form: (function_name, language_code, fillers_arrayref)
    my ( $function_name, $language_code, $fillers ) = @args;
    if ( !exists $SUPPORTED_INTERNAL_FILLER_NAMES{$function_name} ) {
        my @supported = sort keys %SUPPORTED_INTERNAL_FILLER_NAMES;
        carp "unknown_internal_filler_name: '$function_name'. "
            . "add_internal_filler received a function name the SWML "
            . "schema does not recognize. The entry will be stored but "
            . "the runtime will not play these fillers. Supported "
            . "names: ["
            . join( ', ', map { "'$_'" } @supported ) . "].";
    }

    # Initialise as a hashref if empty or legacy list.
    my $store = $self->internal_fillers;
    if ( !defined $store || ref $store ne 'HASH' ) {
        $store = {};
        $self->internal_fillers($store);
    }
    $store->{$function_name} //= {};
    $store->{$function_name}{$language_code} = $fillers;
    return $self;
}

sub enable_debug_events {
    my ( $self, $level ) = @_;
    $level //= 1;
    $self->debug_events_level($level);
    return $self;
}

sub add_function_include {
    my ( $self, $include ) = @_;
    push @{ $self->function_includes }, $include;
    return $self;
}

sub set_function_includes {
    my ( $self, $includes ) = @_;

    # Drop-filter invalid entries, keeping only those that have a truthy
    # `url` AND an arrayref `functions`. TS parity:
    # AgentBase.setFunctionIncludes filters on `inc.url &&
    # Array.isArray(inc.functions)`; Python's set_function_includes drops
    # the same shape. The Perl port additionally warns once per dropped
    # entry (codebase idiom — cf. set_internal_fillers carping on
    # unrecognized names) so the typo surfaces at registration time.
    if ( ref $includes eq 'ARRAY' ) {
        my @valid;
        my $index = 0;
        for my $inc (@$includes) {
            my $ok =
                   ref $inc eq 'HASH'
                && defined $inc->{url}
                && $inc->{url} ne ''
                && ref $inc->{functions} eq 'ARRAY';
            if ($ok) {
                push @valid, $inc;
            } else {
                carp "dropped_invalid_function_include: index=$index. "
                    . "set_function_includes received an entry that is not a "
                    . "valid include — each entry must be a hashref with a "
                    . "non-empty 'url' and an arrayref 'functions'. This entry "
                    . "is dropped and will not appear in the SWAIG includes.";
            }
            $index++;
        }
        $self->function_includes( \@valid );
    }
    return $self;
}

sub set_prompt_llm_params {
    my ( $self, %p ) = @_;
    $self->prompt_llm_params( { %{ $self->prompt_llm_params }, %p } );
    return $self;
}

sub set_post_prompt_llm_params {
    my ( $self, %p ) = @_;
    $self->post_prompt_llm_params( { %{ $self->post_prompt_llm_params }, %p } );
    return $self;
}

# ---------- Verb management ----------

sub add_pre_answer_verb {
    my ( $self, $verb_name, $verb_config ) = @_;
    push @{ $self->pre_answer_verbs }, { $verb_name => $verb_config };
    return $self;
}

sub add_post_answer_verb {
    my ( $self, $verb_name, $verb_config ) = @_;
    push @{ $self->post_answer_verbs }, { $verb_name => $verb_config };
    return $self;
}

sub add_post_ai_verb {
    my ( $self, $verb_name, $verb_config ) = @_;
    push @{ $self->post_ai_verbs }, { $verb_name => $verb_config };
    return $self;
}

# get_name — this agent's name (Python parity: AgentBase.get_name).
sub get_name {
    my ($self) = @_;
    return $self->name;
}

# add_answer_verb(config) — set the auto-answer verb configuration used when
# the agent picks up (Python parity: AgentBase.add_answer_verb).
sub add_answer_verb {
    my ( $self, $config ) = @_;
    $self->answer_config( $config // {} );
    return $self;
}

# enable_sip_routing(auto_map => 1, path => '/sip') — turn on SIP username
# routing for this agent (Python parity: AgentBase.enable_sip_routing).
sub enable_sip_routing {
    my ( $self, %opts ) = @_;
    $self->sip_routing_enabled(1);
    $self->sip_auto_map( exists $opts{auto_map} ? $opts{auto_map} : 1 );
    my $path = $opts{path} // '/sip';
    $self->sip_path($path);

    # Register a routing callback at the SIP path so the served /sip endpoint
    # actually consults the SIP username mapping (Python parity:
    # enable_sip_routing calls register_routing_callback(sip_routing_callback,
    # path=path)). The callback extracts the SIP username from the request body;
    # if it is registered with this agent it is handled here (return undef → the
    # agent renders its own SWML), otherwise it delegates to the SIP-routing hook
    # (on_sip_request) which may return a redirect URL for a username routed to a
    # different agent.
    $self->register_routing_callback(
        $path,
        sub {
            my ( $body, $headers ) = @_;
            return $self->_sip_routing_callback( $body, $headers );
        },
    );

    $self->auto_map_sip_usernames if $self->sip_auto_map;
    return $self;
}

# _sip_routing_callback(body, headers) — the framework-free routing callback
# registered at the SIP path. Extracts the SIP username from the body; if it is
# registered with THIS agent, returns undef (this agent handles the request and
# renders its SWML). If it is not registered here, delegates to the
# _on_sip_request hook, which a subclass may override to return a redirect URL
# for the agent that owns that username. Python parity: the inner
# sip_routing_callback closure created by AgentBase.enable_sip_routing (a
# closure there, an underscore-private method here — off the public surface).
sub _sip_routing_callback {
    my ( $self, $body, $headers ) = @_;
    my $sip_username = $self->extract_sip_username($body);
    return unless defined $sip_username && length $sip_username;

    $self->_logger->info("sip_username_extracted username=$sip_username");

    if ( grep { lc($_) eq lc($sip_username) } @{ $self->sip_usernames } ) {
        $self->_logger->info("sip_username_matched username=$sip_username");

        # Registered with this agent — handled here, no redirect.
        return;
    }

    $self->_logger->info("sip_username_not_matched username=$sip_username");
    return $self->_on_sip_request( $sip_username, $body, $headers );
}

# _on_sip_request(username, body, headers) — extension hook invoked when a SIP
# username is NOT registered with this agent. The base returns undef (no
# redirect; routing continues / this agent renders). A multi-agent router
# (AgentServer) or a subclass overrides this to return the URL of the agent that
# owns the username. Internal hook (underscore-private) — not part of the
# Python public surface.
sub _on_sip_request {
    my ( $self, $username, $body, $headers ) = @_;
    return;
}

# register_sip_username(username) — register a SIP username that routes to
# this agent (Python parity: AgentBase.register_sip_username). Deduplicated.
sub register_sip_username {
    my ( $self, $username ) = @_;
    return $self unless defined $username && length $username;

    # Python parity: AgentBase.register_sip_username does
    # ``self._sip_usernames.add(sip_username.lower())`` — the store is a
    # LOWER-CASED set, so "Bob"/"BOB"/"bob" collapse to one entry. Without
    # the case-fold the same username registered in different casings would
    # accumulate duplicate routes.
    $username = lc $username;
    push @{ $self->sip_usernames }, $username
        unless grep { $_ eq $username } @{ $self->sip_usernames };
    return $self;
}

# auto_map_sip_usernames — derive SIP usernames from the agent name and
# route (lower-cased, stripped to [a-z0-9_]) plus a no-vowels variant of the
# name, registering each. Deduplicated (Python parity).
sub auto_map_sip_usernames {
    my ($self) = @_;
    my $sanitize = sub {
        my $v = lc( $_[0] // '' );
        $v =~ s/[^a-z0-9_]//g;
        return $v;
    };
    my $clean_name = $sanitize->( $self->name );
    $self->register_sip_username($clean_name) if length $clean_name;

    my $clean_route = $sanitize->( $self->route );
    $self->register_sip_username($clean_route)
        if length $clean_route && $clean_route ne $clean_name;

    if ( length $clean_name > 3 ) {
        ( my $no_vowels = $clean_name ) =~ s/[aeiou]//g;
        $self->register_sip_username($no_vowels)
            if length $no_vowels && $no_vowels ne $clean_name;
    }
    return $self;
}

sub clear_pre_answer_verbs {
    my ($self) = @_;
    $self->pre_answer_verbs( [] );
    return $self;
}

sub clear_post_answer_verbs {
    my ($self) = @_;
    $self->post_answer_verbs( [] );
    return $self;
}

sub clear_post_ai_verbs {
    my ($self) = @_;
    $self->post_ai_verbs( [] );
    return $self;
}

sub set_answer_config {
    my ( $self, $config ) = @_;
    $self->answer_config($config);
    return $self;
}

# ---------- Contexts ----------

#
# define_contexts — return this agent's ContextBuilder, attaching the
# agent so that ContextBuilder->validate can check user-defined tool
# names against reserved native tool names (next_step, change_context,
# gather_submit). See SignalWire::Contexts::ContextBuilder.
#
sub define_contexts {
    my ( $self, $contexts ) = @_;

    # Python parity: PromptMixin.define_contexts(contexts=None).
    #   - When called with no arg (legacy / Perl idiom), returns the
    #     ContextBuilder for fluent chaining (``$agent->define_contexts->add_context(...)``).
    #   - When called with a hashref or ContextBuilder, applies that
    #     configuration via context_builder and returns $self for chaining.
    if ( defined $contexts ) {
        if ( ref $contexts eq 'HASH' ) {

            # Apply each top-level context name -> config pair.
            my $cb = $self->context_builder;
            $cb->attach_agent($self) if $cb->can('attach_agent');
            for my $name ( keys %$contexts ) {
                my $cfg = $contexts->{$name};
                my $ctx = $cb->add_context($name);

                # Best-effort: if config is a hashref, apply known keys.
                if ( ref $cfg eq 'HASH' ) {
                    if ( defined $cfg->{steps} && ref $cfg->{steps} eq 'HASH' ) {
                        for my $sname ( keys %{ $cfg->{steps} } ) {
                            $ctx->add_step( $sname, %{ $cfg->{steps}{$sname} } );
                        }
                    }
                }
            }
            return $self;
        }

        # ContextBuilder-like object: assume $contexts->to_hash is the
        # canonical projection; replace this agent's builder with it.
        if ( ref $contexts && $contexts->can('to_hash') ) {
            $self->{_external_context_builder} = $contexts;
            $contexts->attach_agent($self) if $contexts->can('attach_agent');
            return $self;
        }
        die "define_contexts: contexts must be a hashref or a ContextBuilder";
    }

    # No-arg form: return the (memoized) ContextBuilder.
    my $cb = $self->context_builder;
    $cb->attach_agent($self) if $cb->can('attach_agent');
    return $cb;
}

#
# reset_contexts — remove all contexts, returning the agent to a
# no-contexts state. Convenience wrapper around
# define_contexts()->reset(). Use in a dynamic config callback when
# you need to rebuild contexts from scratch for a specific request.
#
sub reset_contexts {
    my ($self) = @_;
    if ( $self->context_builder->can('reset') ) {
        $self->context_builder->reset;
    }
    return $self;
}

#
# list_tool_names — return the names of every registered SWAIG tool in
# insertion order. Used by SignalWire::Contexts::ContextBuilder->validate
# to detect collisions with reserved native tool names.
#
sub list_tool_names {
    my ($self) = @_;
    return @{ $self->tool_order };
}

sub contexts {
    my ($self) = @_;
    return $self->context_builder;
}

# ---------- Skills ----------

sub add_skill {
    my ( $self, $skill_name, $params ) = @_;
    $params //= {};
    return $self->skill_manager->load_skill( $skill_name, undef, $params );
}

sub remove_skill {
    my ( $self, $skill_name ) = @_;
    return $self->skill_manager->unload_skill($skill_name);
}

sub list_skills {
    my ($self) = @_;
    return $self->skill_manager->list_skills;
}

sub has_skill {
    my ( $self, $skill_name ) = @_;
    return $self->skill_manager->has_skill($skill_name);
}

# ---------- Web / callback setters ----------

sub set_dynamic_config_callback {
    my ( $self, $cb ) = @_;
    $self->dynamic_config_callback($cb);
    return $self;
}

sub set_web_hook_url {
    my ( $self, $url ) = @_;
    $self->webhook_url($url);
    return $self;
}

sub set_post_prompt_url {
    my ( $self, $url ) = @_;
    $self->post_prompt_url($url);
    return $self;
}

sub manual_set_proxy_url {
    my ( $self, $url ) = @_;
    $self->proxy_url_base($url);
    return $self;
}

sub add_swaig_query_params {
    my ( $self, %params ) = @_;
    $self->swaig_query_params( { %{ $self->swaig_query_params }, %params } );
    return $self;
}

sub clear_swaig_query_params {
    my ($self) = @_;
    $self->swaig_query_params( {} );
    return $self;
}

sub on_summary {
    my ( $self, $summary, $raw_data ) = @_;

    # Python parity: AgentBase.on_summary(summary, raw_data=None).
    #
    # Two invocation forms:
    #   1. Registration form (Perl idiom):
    #        $agent->on_summary(sub { my ($summary, $raw) = @_; ... });
    #      A coderef as the first arg installs that handler as the
    #      summary callback and returns $self for chaining.
    #   2. Dispatch form (Python parity):
    #        $agent->on_summary($summary, $raw_data);
    #      Anything else is treated as the summary payload itself
    #      and dispatches to the registered callback. Default
    #      implementation is a no-op (matches Python's pass).
    if ( ref $summary eq 'CODE' ) {
        $self->summary_callback($summary);
        return $self;
    }
    my $cb = $self->summary_callback;
    if ($cb) {
        return $cb->( $summary, $raw_data );
    }
    return;
}

sub on_debug_event {
    my ( $self, $cb ) = @_;
    $self->debug_event_handler($cb);
    return $self;
}

# ---------- MCP integration ----------

sub add_mcp_server {
    my ( $self, $url, %opts ) = @_;
    my $server = { url => $url };
    $server->{headers}       = $opts{headers}       if $opts{headers};
    $server->{resources}     = JSON::true           if $opts{resources};
    $server->{resource_vars} = $opts{resource_vars} if $opts{resource_vars};
    push @{ $self->mcp_servers }, $server;
    return $self;
}

sub enable_mcp_server {
    my ($self) = @_;
    $self->mcp_server_enabled(1);
    return $self;
}

sub _build_mcp_tool_list {
    my ($self) = @_;
    my @tools;
    for my $fname ( @{ $self->tool_order } ) {
        my $tool = $self->tools->{$fname};
        next unless $tool;
        my $t = {
            name        => $fname,
            description => $tool->{description} || $fname,
        };
        if ( $tool->{parameters} && %{ $tool->{parameters} } ) {
            my $params = $tool->{parameters};
            if ( $params->{type} && $params->{type} eq 'object' ) {
                $t->{inputSchema} = $params;
            } else {
                $t->{inputSchema} = { type => 'object', properties => $params };
            }
        } else {
            $t->{inputSchema} = { type => 'object', properties => {} };
        }
        push @tools, $t;
    }
    return \@tools;
}

sub _handle_mcp_request {
    my ( $self, $body ) = @_;
    my $jsonrpc = $body->{jsonrpc} // '';
    my $method  = $body->{method}  // '';
    my $req_id  = $body->{id};
    my $params  = $body->{params} // {};

    if ( $jsonrpc ne '2.0' ) {
        return _mcp_error( $req_id, -32600, 'Invalid JSON-RPC version' );
    }

    # Initialize
    if ( $method eq 'initialize' ) {
        return {
            jsonrpc => '2.0',
            id      => $req_id,
            result  => {
                protocolVersion => '2025-06-18',
                capabilities    => { tools => {} },
                serverInfo      => { name  => $self->name, version => '1.0.0' },
            },
        };
    }

    # Initialized notification
    if ( $method eq 'notifications/initialized' ) {
        return { jsonrpc => '2.0', id => $req_id, result => {} };
    }

    # List tools
    if ( $method eq 'tools/list' ) {
        return {
            jsonrpc => '2.0',
            id      => $req_id,
            result  => { tools => $self->_build_mcp_tool_list },
        };
    }

    # Call tool
    if ( $method eq 'tools/call' ) {
        my $tool_name = $params->{name}      // '';
        my $arguments = $params->{arguments} // {};

        my $tool = $self->tools->{$tool_name};
        unless ( $tool && $tool->{_handler} ) {
            return _mcp_error( $req_id, -32602, "Unknown tool: $tool_name" );
        }

        my $result = eval {
            my $raw_data = {
                function => $tool_name,
                argument => { parsed => [$arguments] },
            };
            $tool->{_handler}->( $arguments, $raw_data );
        };

        if ($@) {
            return {
                jsonrpc => '2.0',
                id      => $req_id,
                result  => {
                    content => [ { type => 'text', text => "Error: $@" } ],
                    isError => JSON::true,
                },
            };
        }

        my $response_text = '';
        if ( blessed($result) && $result->can('to_hash') ) {
            my $h = $result->to_hash;
            $response_text = $h->{response} // '';
        } elsif ( ref $result eq 'HASH' ) {
            $response_text = $result->{response} // '';
        } elsif ( defined $result ) {
            $response_text = "$result";
        }

        return {
            jsonrpc => '2.0',
            id      => $req_id,
            result  => {
                content => [ { type => 'text', text => $response_text } ],
                isError => JSON::false,
            },
        };
    }

    # Ping
    if ( $method eq 'ping' ) {
        return { jsonrpc => '2.0', id => $req_id, result => {} };
    }

    return _mcp_error( $req_id, -32601, "Method not found: $method" );
}

sub _mcp_error {
    my ( $req_id, $code, $message ) = @_;
    return {
        jsonrpc => '2.0',
        id      => $req_id,
        error   => { code => $code, message => $message },
    };
}

# ---------- URL construction ----------

sub _build_webhook_url {
    my ( $self, $request_env ) = @_;

    # If explicit override set, use it
    return $self->webhook_url if defined $self->webhook_url;

    my $base  = $self->_detect_proxy_url($request_env);
    my $route = $self->route eq '/' ? '' : $self->route;
    my $url   = $base . $route . '/swaig';

    # Append query params
    if ( %{ $self->swaig_query_params } ) {
        my @parts;
        for my $k ( sort keys %{ $self->swaig_query_params } ) {
            push @parts, "$k=" . ( $self->swaig_query_params->{$k} // '' );
        }
        $url .= '?' . join( '&', @parts );
    }

    return $url;
}

sub _build_post_prompt_url {
    my ( $self, $request_env ) = @_;
    return $self->post_prompt_url if defined $self->post_prompt_url;
    my $base  = $self->_detect_proxy_url($request_env);
    my $route = $self->route eq '/' ? '' : $self->route;
    return $base . $route . '/post_prompt';
}

sub _detect_proxy_url {
    my ( $self, $env ) = @_;

    return $self->proxy_url_base if defined $self->proxy_url_base;

    $env //= {};

    # Check X-Forwarded headers
    my $proto = $env->{HTTP_X_FORWARDED_PROTO};
    my $fhost = $env->{HTTP_X_FORWARDED_HOST};
    if ( $proto && $fhost ) {
        return "${proto}://${fhost}";
    }

    # Check X-Original-URL
    my $orig = $env->{HTTP_X_ORIGINAL_URL};
    return $orig if $orig;

    # Fallback to server config
    my $scheme = ( $env->{HTTPS} || $env->{'psgi.url_scheme'} || 'http' );
    $scheme = 'https' if $scheme eq 'on';
    my $host = $env->{HTTP_HOST} || $self->host . ':' . $self->port;
    return "${scheme}://${host}";
}

sub get_full_url {
    my ( $self, %opts ) = @_;
    my $base  = $self->proxy_url_base // ( 'http://' . $self->host . ':' . $self->port );
    my $route = $self->route eq '/' ? '' : $self->route;
    my $url   = $base . $route;
    if ( $opts{include_auth} ) {
        my $user = $self->basic_auth_user;
        my $pass = $self->basic_auth_password;
        $url =~ s{^(https?://)}{$1${user}:${pass}\@};
    }
    return $url;
}

# ---------- render_swml (5-phase pipeline) ----------

# _render_swml_for_call — render the SWML for an ACTIVE call, so every SECURE
# tool's SWAIG webhook carries its per-call ``__token``.
#
# Python parity: ``_render_swml(call_id)`` (agent_base.py:867) — the call_id is
# what makes the per-tool token mintable (it is bound to the call), so a render
# WITHOUT one emits no tokens. Perl keeps the public ``render_swml($request_env)``
# signature and carries the call_id in ``_render_call_id`` for the render's
# duration; the serving paths (handle_request / the PSGI app / lambda mode) call
# THIS, having parsed call_id off the request body.
#
# PRIVATE (leading underscore), matching the reference: python's call_id-aware
# render is the private ``_render_swml``, and only the SDK's own serving paths
# drive it. Keeping it private means it adds no public surface the reference
# lacks — there is nothing here to excuse as a PORT_ADDITION.
#
# Always clears _render_call_id, so a die inside the render cannot leave a stale
# call_id bound to the agent (which would mint tokens for the WRONG call on the
# next render).
sub _render_swml_for_call {
    my ( $self, $request_env, $call_id ) = @_;
    $self->_render_call_id($call_id);
    my @r   = eval { $self->render_swml($request_env) };
    my $err = $@;
    $self->_render_call_id(undef);
    die $err if $err;
    return $r[0];
}

sub render_swml {
    my ( $self, $request_env ) = @_;
    $request_env //= {};

    my $webhook_url     = $self->_build_webhook_url($request_env);
    my $post_prompt_url = $self->_build_post_prompt_url($request_env);

    # Embed auth credentials in webhook URL
    my $auth_user = $self->basic_auth_user;
    my $auth_pass = $self->basic_auth_password;
    $webhook_url =~ s{^(https?://)}{$1${auth_user}:${auth_pass}\@}
        unless $webhook_url =~ /\@/;
    $post_prompt_url =~ s{^(https?://)}{$1${auth_user}:${auth_pass}\@}
        unless $post_prompt_url =~ /\@/;

    my @main_section;

    # Phase 1: Pre-answer verbs
    push @main_section, @{ $self->pre_answer_verbs };

    # Phase 2: Answer verb
    if ( $self->auto_answer ) {
        my %answer_params = ( max_duration => 14400 );
        %answer_params = ( %answer_params, %{ $self->answer_config } ) if %{ $self->answer_config };
        push @main_section, { answer => \%answer_params };
    }

    # Record call if enabled
    if ( $self->record_call ) {
        push @main_section,
            {
            record_call => {
                format => $self->record_format,
                stereo => $self->record_stereo ? JSON::true : JSON::false,
            }
            };
    }

    # Phase 3: Post-answer verbs
    push @main_section, @{ $self->post_answer_verbs };

    # Phase 4: AI verb
    my $ai = $self->_build_ai_verb( $webhook_url, $post_prompt_url );
    push @main_section, { ai => $ai };

    # Phase 5: Post-AI verbs
    push @main_section, @{ $self->post_ai_verbs };

    my $doc = {
        version  => '1.0.0',
        sections => { main => \@main_section },
    };

    return $doc;
}

sub _build_ai_verb {
    my ( $self, $webhook_url, $post_prompt_url ) = @_;

    my %ai;

    # Prompt
    my $prompt = $self->get_prompt;
    if ( ref $prompt eq 'ARRAY' ) {

        # POM mode
        $ai{prompt} = { pom => $prompt };
    } else {

        # Text mode. When no prompt text has been set, emit the default
        # fallback rather than omitting the prompt key. TS parity:
        # renderSwml uses `prompt || ` . "You are ${this.name}, a helpful "
        # . "AI assistant." Python parity: prompt_mixin.get_prompt returns
        # the identical "You are {name}, a helpful AI assistant." default.
        my $text =
            ( defined $prompt && $prompt ne '' )
            ? $prompt
            : 'You are ' . $self->name . ', a helpful AI assistant.';
        $ai{prompt} = { text => $text };
    }

    # Merge prompt LLM params
    if ( %{ $self->prompt_llm_params } ) {
        $ai{prompt} //= {};
        for my $k ( keys %{ $self->prompt_llm_params } ) {
            $ai{prompt}{$k} = $self->prompt_llm_params->{$k};
        }
    }

    # Post prompt
    if ( $self->post_prompt && $self->post_prompt ne '' ) {
        $ai{post_prompt} = { text => $self->post_prompt };
        if ( %{ $self->post_prompt_llm_params } ) {
            for my $k ( keys %{ $self->post_prompt_llm_params } ) {
                $ai{post_prompt}{$k} = $self->post_prompt_llm_params->{$k};
            }
        }
    }

    $ai{post_prompt_url} = $post_prompt_url if $post_prompt_url;

    # Params
    $ai{params} = { %{ $self->params } } if %{ $self->params };

    # Hints
    my @all_hints = @{ $self->hints };
    push @all_hints, @{ $self->pattern_hints };
    $ai{hints} = \@all_hints if @all_hints;

    # Languages
    $ai{languages} = $self->languages if @{ $self->languages };

    # ASR-driven multilingual mode (set_multilingual): emit the top-level
    # ``multilingual`` object on the AI verb. Mutually exclusive with
    # ``languages`` — the server prefers ``multilingual`` when both present.
    {
        my $ml = $self->multilingual;
        $ai{multilingual} = $ml if defined $ml && ref($ml) eq 'HASH' && %$ml;
    }

    # Pronunciations
    $ai{pronounce} = $self->pronunciations if @{ $self->pronunciations };

    # SWAIG
    my $swaig = {};

    # Build function list
    my @functions;
    my $call_id = $self->_render_call_id;
    for my $fname ( @{ $self->tool_order } ) {
        my $tool = $self->tools->{$fname};
        next unless $tool;
        my %func = %$tool;
        delete $func{_handler};    # Don't include handler in SWML

        # `secure` is an SDK-SIDE flag, never a SWAIG wire key. Python builds the
        # rendered function entry from an explicit field list, so `secure` never
        # reaches the wire (agent_base.py:1051-1054); a blanket copy of the tool
        # definition would emit an invented `"secure"` key. Capture it, then drop
        # it — its wire manifestation is the `__token` below, nothing else.
        my $is_secure = delete $func{secure};

        $func{web_hook_url} //= $webhook_url;

        # A SECURE tool rendered with an active call_id carries a per-tool
        # `__token` on its webhook so the platform can validate the callback —
        # the WIRE manifestation of `secure` (python agent_base.py:1040 /
        # 1096-1100). An insecure tool gets NO token. Without a call_id no token
        # can be minted (it is bound to the call), matching the reference.
        if ( $is_secure && defined $call_id && length $call_id ) {
            my $token = $self->create_tool_token( $fname, $call_id );
            if ( defined $token && length $token ) {
                my $sep = ( $func{web_hook_url} =~ /\?/ ) ? '&' : '?';
                $func{web_hook_url} .= $sep . '__token=' . $token;
            }
        }
        push @functions, \%func;
    }
    $swaig->{functions} = \@functions if @functions;

    # Native functions
    $swaig->{native_functions} = $self->native_functions
        if @{ $self->native_functions };

    # Includes
    $swaig->{includes} = $self->function_includes
        if @{ $self->function_includes };

    $ai{SWAIG} = $swaig if %$swaig;

    # Global data
    $ai{global_data} = { %{ $self->global_data } }
        if %{ $self->global_data };

    # Internal fillers
    if ( defined $self->internal_fillers ) {
        $ai{params} //= {};
        $ai{params}{internal_fillers} = $self->internal_fillers;
    }

    # Debug events
    if ( $self->debug_events_level > 0 ) {
        $ai{params} //= {};
        $ai{params}{debug_events} = $self->debug_events_level;
    }

    # Contexts — go under ai.prompt.contexts per Python's
    # PromptManager.to_dict() behavior (signalwire-python /core/swml_handler.py
    # build_config:172, /core/agent/prompt/manager.py:_contexts).
    if ( $self->context_builder && $self->context_builder->has_contexts ) {
        $ai{prompt} //= {};
        $ai{prompt}{contexts} = $self->context_builder->to_hash;
    }

    # MCP servers
    if ( @{ $self->mcp_servers } ) {
        $ai{mcp_servers} = [ @{ $self->mcp_servers } ];
    }

    return \%ai;
}

# ---------- PSGI / Plack ----------

sub psgi_app {
    my ($self) = @_;
    return $self->_build_psgi_app;
}

# handle_request — the framework-free request-dispatch core for AgentBase.
#
# Python parity: AgentBase.handle_request overrides SWMLService.handle_request
# so the primitive dispatch surface renders SWML via AgentBase's render_swml
# (mirroring the FastAPI _handle_root_request path) instead of the base
# render_document. Performs proxy detection, basic-auth, the routing-callback
# check, and on_swml_request modification over plain primitives, returning a
# ($status, \%headers, $body_string) triple with the 401-auth and 307-redirect
# behavior preserved.
#
#   $method  HTTP method string ("GET"/"POST")
#   $url     full request URL (callback-path derivation + proxy detection)
#   $headers hashref of request headers
#   $body    already-parsed JSON body hashref for POST, or undef
sub handle_request {
    my ( $self, $method, $url, $headers, $body ) = @_;
    $headers //= {};
    $body    //= {};
    my $callback_path = $self->_callback_path_for_url($url);

    # Auth (over the plain headers hashref; inherited from SWMLService).
    unless ( $self->_check_basic_auth_headers($headers) ) {
        return (
            401,
            { 'WWW-Authenticate' => 'Basic' },
            encode_json( { error => 'Unauthorized' } ),
        );
    }

    # A synthetic PSGI-style env so render_swml's proxy detection sees the
    # request's forwarding headers (the primitive analog of the $env the
    # PSGI path passes).
    my $request_env = $self->_env_from_primitives( $url, $headers );

    # call_id from the parsed body (POST); routing callback: (body, headers).
    # The call_id is what makes a SECURE tool's per-tool ``__token`` mintable on
    # the render (python agent_base.py:1770-1774 parses it off the body and passes
    # it to _render_swml). It was parsed nowhere before, so every served document
    # rendered its secure tools WITHOUT a token.
    my $call_id;
    if ( $method eq 'POST' && ref $body eq 'HASH' && %$body ) {
        $call_id = $body->{call_id};
        if ( ( !defined $call_id || !length $call_id ) && ref $body->{call} eq 'HASH' ) {
            $call_id = $body->{call}{call_id};
        }
        if ( defined $callback_path
            && $self->routing_callbacks->{$callback_path} )
        {
            my $cb    = $self->routing_callbacks->{$callback_path};
            my $route = eval { $cb->( $body, $headers ) };
            if ($@) {
                $self->log->error( "error_in_routing_callback", error => "$@" );
            } elsif ( defined $route ) {
                return ( 307, { 'Location' => $route }, '' );
            }
        }
    }

    # Per-request dynamic configuration (multi-tenancy): clone this agent and
    # let the callback mutate the clone, then render off the clone — so the
    # served path (which routes through handle_request) keeps the same dynamic
    # config behavior the old inline _handle_swml had.
    my $agent = $self;
    if ( $self->dynamic_config_callback ) {
        $agent = $self->_clone_for_request;
        my $query_params = _query_params_from_url($url);
        my $body_params  = ( ref $body eq 'HASH' ) ? $body : {};
        my $lc_headers   = {};
        for my $k ( keys %$headers ) {
            $lc_headers->{ lc $k } = $headers->{$k};
        }
        eval {
            $self->dynamic_config_callback->( $query_params, $body_params, $lc_headers, $agent );
            1;
        } or do {
            $self->log->error( "error_in_dynamic_config", error => "$@" );
        };
    }

    # Subclass request-modification hook (on_swml_request); the primitive
    # path passes undef for the FastAPI-Request third arg.
    my $modifications = eval { $agent->on_swml_request( $body, $callback_path, undef ) };
    if ($@) {
        $self->log->error( "error_in_request_modifier", error => "$@" );
        $modifications = undef;
    }

    my $swml = $agent->_render_swml_for_call( $request_env, $call_id );
    if ( $modifications && ref $modifications eq 'HASH' ) {
        $swml = { %$swml, %$modifications };
    }
    return ( 200, {}, encode_json($swml) );
}

# Parse the query string of a request URL into a plain hashref (last value
# wins for repeated keys). Used to feed dynamic_config_callback the same
# query-parameter view the PSGI path derived from $req->query_parameters.
sub _query_params_from_url {
    my ($url) = @_;
    my %params;
    return \%params unless defined $url && $url =~ /\?(.*)$/;
    my $qs = $1;
    for my $pair ( split /[&;]/, $qs ) {
        next unless length $pair;
        my ( $k, $v ) = split /=/, $pair, 2;
        next unless defined $k && length $k;
        $v //= '';
        for ( $k, $v ) {
            tr/+/ /;
            s/%([0-9A-Fa-f]{2})/chr hex $1/ge;
        }
        $params{$k} = $v;
    }
    return \%params;
}

# Build a synthetic PSGI env from handle_request's (url, headers) so the
# proxy-URL detection in render_swml/_detect_proxy_url works off the same
# forwarding headers the PSGI path would carry.
sub _env_from_primitives {
    my ( $self, $url, $headers ) = @_;
    my %env;
    for my $k ( keys %$headers ) {
        my $cgi = uc $k;
        $cgi =~ s/-/_/g;
        $env{"HTTP_$cgi"} = $headers->{$k}
            unless $cgi =~ /^HTTP_/;    # already CGI-cased
        $env{$k} = $headers->{$k} if $k =~ /^HTTP_/;
    }
    if ( defined $url && $url =~ m{^([a-z][a-z0-9+.\-]*)://}i ) {
        $env{'psgi.url_scheme'} = lc $1;
    }
    return \%env;
}

sub _build_psgi_app {
    my ($self) = @_;
    require Plack::Request;

    my $route = $self->route;
    $route = '' if $route eq '/';

    my $agent = $self;

    # Build the core app as a plain PSGI sub
    my $core_app = sub {
        my $env  = shift;
        my $req  = Plack::Request->new($env);
        my $path = $req->path_info;

        # Normalize path
        $path =~ s{/+$}{} unless $path eq '/';

        # Health/ready endpoints (no auth)
        if ( $path eq '/health' ) {
            return [
                200,
                [ 'Content-Type' => 'application/json' ],
                [ encode_json( { status => 'healthy', agent => $agent->name } ) ]
            ];
        }
        if ( $path eq '/ready' ) {
            return [
                200,
                [ 'Content-Type' => 'application/json' ],
                [ encode_json( { status => 'ready' } ) ]
            ];
        }

        # Auth check for protected routes
        my $expected_route = $route eq '' ? '/' : $route;
        my $is_swaig       = ( $path eq "$route/swaig" );
        my $is_post_prompt = ( $path eq "$route/post_prompt" );
        my $is_mcp         = ( $path eq "$route/mcp" );
        my $is_main        = ( $path eq $expected_route || ( $route ne '' && $path eq "$route/" ) );

        # Root agent: treat '/' as main
        if ( $route eq '' && $path eq '/' ) {
            $is_main = 1;
        }

        # The MAIN SWML route delegates its auth/routing/render DECISION to the
        # decomposed handle_request core (401 auth, 307 routing-callback
        # redirect, 200 render) so the served path can no longer skip the
        # routing-callback 307 the old inline _handle_swml did. swaig /
        # post_prompt keep the inline auth + handler below.
        if ( $is_main && ( $req->method eq 'GET' || $req->method eq 'POST' ) ) {
            return $agent->_serve_main_via_handle_request($env);
        }

        # A request to a registered routing-callback path (e.g. the SIP path
        # from enable_sip_routing) also flows through handle_request, so the
        # stored callback is actually consulted at its served endpoint — a 307
        # redirect (routed elsewhere) or the agent's own SWML (handled here).
        # Without this, a /sip mapping would be stored-but-unconsulted (the
        # dispatch would fall through to the 404 below). Matches on the path via
        # the same _callback_path_for_url the routing dispatch uses.
        if (   !$is_swaig
            && !$is_post_prompt
            && !$is_mcp
            && ( $req->method eq 'GET' || $req->method eq 'POST' )
            && defined $agent->_callback_path_for_url($path) )
        {
            return $agent->_serve_main_via_handle_request($env);
        }

        if ( $is_swaig || $is_post_prompt ) {
            my $auth_ok = $agent->_check_auth($env);
            unless ($auth_ok) {
                return [
                    401,
                    [
                        'Content-Type'     => 'text/plain',
                        'WWW-Authenticate' => 'Basic realm="SignalWire Agent"'
                    ],
                    ['Unauthorized']
                ];
            }
        }

        # Route dispatch
        if ( $is_swaig && $req->method eq 'POST' ) {
            return $agent->_handle_swaig( $env, $req );
        } elsif ( $is_post_prompt && $req->method eq 'POST' ) {
            return $agent->_handle_post_prompt( $env, $req );
        } elsif ( $is_mcp && $req->method eq 'POST' ) {
            return $agent->_handle_mcp_endpoint( $env, $req );
        }

        return [ 404, [ 'Content-Type' => 'text/plain' ], ['Not Found'] ];
    };

    # Maximum request body size: 1MB
    my $max_body_size = 1_048_576;

    # Wrap with body size limit and security headers middleware
    my $app_with_middleware = sub {
        my $env = shift;

        # Enforce body size limit by actually reading the body
        if ( $env->{REQUEST_METHOD} eq 'POST' || $env->{REQUEST_METHOD} eq 'PUT' ) {
            my $input = $env->{'psgi.input'};
            if ($input) {
                my $body  = '';
                my $total = 0;
                my $buf;
                while ( my $read = $input->read( $buf, 8192 ) ) {
                    $total += $read;
                    if ( $total > $max_body_size ) {
                        return [
                            413,
                            [
                                'Content-Type'           => 'application/json',
                                'X-Content-Type-Options' => 'nosniff',
                                'X-Frame-Options'        => 'DENY',
                                'Cache-Control'          => 'no-store'
                            ],
                            [ encode_json( { error => 'Request body too large' } ) ]
                        ];
                    }
                    $body .= $buf;
                }

                # Replace psgi.input with the buffered content so handlers can
                # re-read. In-memory handle is deliberately handed off as
                # psgi.input for downstream re-reads; it must NOT be closed here
                # (see RequireBriefOpen exemption rationale in .perlcriticrc).
                open my $new_input, '<', \$body;
                $env->{'psgi.input'}   = $new_input;
                $env->{CONTENT_LENGTH} = length($body);
            }
        }

        my $res = $core_app->($env);
        if ( ref $res eq 'ARRAY' ) {
            push @{ $res->[1] },
                'X-Content-Type-Options' => 'nosniff',
                'X-Frame-Options'        => 'DENY',
                'Cache-Control'          => 'no-store';
        }
        return $res;
    };

    # Signed-webhook gate — wraps the entire app so unsigned / invalid
    # requests on POST /, POST $route/swaig, POST $route/post_prompt
    # are rejected with 403 before any other handling. Passthrough when
    # signing_key is empty (the startup-warning code below logs once
    # so callers know validation is disabled).
    my $signing_key = $self->signing_key;
    if ( defined $signing_key && $signing_key ne '' ) {
        require SignalWire::Security::WebhookMiddleware;
        my $main_path   = ( $route eq '' || $route eq '/' ) ? '/' : $route;
        my @gated_paths = ($main_path);
        push @gated_paths, "$route/swaig", "$route/post_prompt"
            if $route ne '';
        push @gated_paths, '/swaig', '/post_prompt'
            if $route eq '' || $route eq '/';

        # De-dup
        my %seen;
        @gated_paths = grep { !$seen{$_}++ } @gated_paths;

        my $signed_app = SignalWire::Security::WebhookMiddleware->wrap(
            app         => $app_with_middleware,
            signing_key => $signing_key,
            paths       => \@gated_paths,
            methods     => ['POST'],

            # Python parity: web_mixin.py:450 passes
            # trust_proxy=getattr(self, "_trust_proxy_for_signature", False).
            # Proxy headers are spoofable, so this is OPT-IN, not always-on.
            trust_proxy => $self->trust_proxy_for_signature ? 1 : 0,
        );
        return $signed_app;
    } else {
        $self->_warn_signing_key_disabled_once;
    }

    return $app_with_middleware;
}

# Emit a one-time startup warning when signing_key is unset. Mirrors
# the Python and Node SDKs: webhook signature validation is OFF unless
# you pass signing_key or set SIGNALWIRE_SIGNING_KEY.
sub _warn_signing_key_disabled_once {
    my ($self) = @_;
    return if $self->{_signing_warning_emitted};
    $self->{_signing_warning_emitted} = 1;
    carp "[signalwire] webhook signature validation is disabled — "
        . "set signing_key or SIGNALWIRE_SIGNING_KEY to enable";
    return;
}

sub _check_auth {
    my ( $self, $env ) = @_;
    my $auth_header = $env->{HTTP_AUTHORIZATION} // '';
    return 0 unless $auth_header =~ /^Basic\s+(.+)$/i;
    my $decoded = eval { decode_base64($1) } // '';
    my ( $user, $pass ) = split( /:/, $decoded, 2 );
    return 0 unless defined $user && defined $pass;

    # Timing-safe comparison using HMAC (constant-time, no length leak)
    my $expected_user = $self->basic_auth_user;
    my $expected_pass = $self->basic_auth_password;

    my $user_ok = _timing_safe_eq( $user, $expected_user );
    my $pass_ok = _timing_safe_eq( $pass, $expected_pass );

    return ( $user_ok && $pass_ok ) ? 1 : 0;
}

sub _timing_safe_eq {
    my ( $a, $b ) = @_;

    # HMAC-based constant-time comparison: no length leak
    my $key    = 'signalwire-timing-safe-comparison';
    my $hmac_a = hmac_sha256_hex( $a, $key );
    my $hmac_b = hmac_sha256_hex( $b, $key );
    return $hmac_a eq $hmac_b;
}

sub _handle_swml {
    my ( $self, $env, $req ) = @_;

    my $agent = $self;

    # Parse the POST body up-front: the call_id it carries is what makes a SECURE
    # tool's per-tool ``__token`` mintable on the render (python
    # agent_base.py:1795-1812 — body call_id, falling back to the ?call_id= query
    # param). Parsed for EVERY request, not just the dynamic-config one, since the
    # token is needed regardless.
    my $body_params = {};
    if ( $req->method eq 'POST' && $req->content_length ) {
        eval { $body_params = decode_json( $req->content ) };
        $body_params = {} unless ref $body_params eq 'HASH';
    }
    my $call_id = $body_params->{call_id};
    if ( ( !defined $call_id || !length $call_id ) && ref $body_params->{call} eq 'HASH' ) {
        $call_id = $body_params->{call}{call_id};
    }
    $call_id = $req->query_parameters->get('call_id')
        unless defined $call_id && length $call_id;

    # If dynamic config callback is set, clone and apply
    if ( $self->dynamic_config_callback ) {
        $agent = $self->_clone_for_request;
        my $query_params = $req->query_parameters->as_hashref_mixed;
        my $headers      = {};
        for my $k ( keys %$env ) {
            if ( $k =~ /^HTTP_(.+)/ ) {
                $headers->{ lc($1) } = $env->{$k};
            }
        }
        $self->dynamic_config_callback->( $query_params, $body_params, $headers, $agent );
    }

    my $swml = $agent->_render_swml_for_call( $env, $call_id );
    my $json = encode_json($swml);

    return [ 200, [ 'Content-Type' => 'application/json' ], [$json] ];
}

sub _handle_swaig {
    my ( $self, $env, $req ) = @_;

    my $body = eval { decode_json( $req->content ) };
    unless ( $body && ref $body eq 'HASH' ) {
        return [
            400,
            [ 'Content-Type' => 'application/json' ],
            [ encode_json( { error => 'Invalid JSON' } ) ]
        ];
    }

    my $func_name = $body->{function};
    unless ( $func_name && exists $self->tools->{$func_name} ) {
        return [
            404,
            [ 'Content-Type' => 'application/json' ],
            [ encode_json( { error => 'Function not found' } ) ]
        ];
    }

    # Extract args
    my $args = {};
    if (   $body->{argument}
        && ref $body->{argument}{parsed} eq 'ARRAY'
        && @{ $body->{argument}{parsed} } )
    {
        $args = $body->{argument}{parsed}[0] // {};
    }

    my $result = $self->on_function_call( $func_name, $args, $body );
    unless ( defined $result ) {
        return [
            500,
            [ 'Content-Type' => 'application/json' ],
            [ encode_json( { error => 'Handler returned no result' } ) ]
        ];
    }

    # Serialize result
    my $response;
    if ( blessed($result) && $result->can('to_hash') ) {
        $response = $result->to_hash;
    } elsif ( ref $result eq 'HASH' ) {
        $response = $result;
    } else {

        # Neither a FunctionResult-like object nor a hashref. Warn and
        # fall back to wrapping the stringified value, matching Python's
        # web_mixin / serverless_mixin / tool_mixin behavior.
        my $type = ref($result) || 'SCALAR';
        carp "unexpected_function_result_type: function=\"$func_name\" "
            . "result_type=\"$type\". SWAIG function returned a value "
            . "that is neither a FunctionResult (blessed with to_hash) "
            . "nor a hashref; falling back to wrapping the stringified "
            . "value. The AI will see the stringified value as its "
            . "tool response. Return a "
            . "SignalWire::SWAIG::FunctionResult object or a hashref "
            . "with at least a 'response' key.";
        $response = { response => "$result" };
    }

    return [ 200, [ 'Content-Type' => 'application/json' ], [ encode_json($response) ] ];
}

sub _handle_post_prompt {
    my ( $self, $env, $req ) = @_;

    my $body = eval { decode_json( $req->content ) };
    $body //= {};

    if ( $self->summary_callback ) {
        my $summary = undef;
        if ( $body->{post_prompt_data} ) {
            $summary = $body->{post_prompt_data}{parsed} // $body->{post_prompt_data}{raw};
        }
        $self->summary_callback->( $summary, $body );
    }

    return [ 200, [ 'Content-Type' => 'application/json' ], [ encode_json( { status => 'ok' } ) ] ];
}

sub _handle_mcp_endpoint {
    my ( $self, $env, $req ) = @_;

    unless ( $self->mcp_server_enabled ) {
        return [
            404,
            [ 'Content-Type' => 'application/json' ],
            [ encode_json( { error => 'MCP server not enabled' } ) ]
        ];
    }

    my $body = eval { decode_json( $req->content ) };
    unless ( $body && ref $body eq 'HASH' ) {
        return [
            400,
            [ 'Content-Type' => 'application/json' ],
            [ encode_json( _mcp_error( undef, -32700, 'Parse error' ) ) ]
        ];
    }

    my $resp = $self->_handle_mcp_request($body);
    return [ 200, [ 'Content-Type' => 'application/json' ], [ encode_json($resp) ] ];
}

# ---------- Clone for dynamic config ----------

sub _clone_for_request {
    my ($self) = @_;

    # CONSTRUCTION vs STATE TRANSFER. Only the agent's genuine construction
    # contract (the params the python reference's AgentBase.__init__ accepts)
    # goes through ``new``. Everything else is INTERNAL agent state that the
    # reference configures through methods (add_hints/set_global_data/…) and
    # its ephemeral clone copies attribute-by-attribute onto the built object —
    # so this does the same, writing each attribute on the clone after
    # construction rather than smuggling it in as a constructor argument.
    my %init;
    for my $attr (
        qw(name route host port auto_answer record_call record_format
        record_stereo use_pom basic_auth_user basic_auth_password)
        )
    {
        $init{$attr} = $self->$attr;
    }

    my $clone = ( ref $self )->new(%init);

    # Scalar state — copied straight across.
    for my $attr (
        qw(prompt_text post_prompt debug_events_level webhook_url
        post_prompt_url proxy_url_base mcp_server_enabled session_manager)
        )
    {
        $clone->$attr( $self->$attr );
    }

    # Deep-copied container state. dclone for nested structures, a shallow
    # copy for the flat ones, so per-request mutation on the clone can never
    # write through to the shared original.
    for my $attr (
        qw(pom_sections tools languages pronunciations global_data
        function_includes pre_answer_verbs post_answer_verbs post_ai_verbs
        mcp_servers)
        )
    {
        $clone->$attr( dclone( $self->$attr ) );
    }
    for my $attr (qw(tool_order hints pattern_hints native_functions)) {
        $clone->$attr( [ @{ $self->$attr } ] );
    }
    for my $attr (
        qw(params prompt_llm_params post_prompt_llm_params answer_config
        swaig_query_params)
        )
    {
        $clone->$attr( { %{ $self->$attr } } );
    }

    $clone->internal_fillers(
        defined $self->internal_fillers ? dclone( $self->internal_fillers ) : undef );

    # ASR-driven multilingual (Mode B) config — a render-relevant attribute
    # (emitted as the top-level ``multilingual`` object on the AI verb). It was
    # previously NOT copied, so a dynamic-config-callback request rendered off
    # the clone silently lost the agent's multilingual config. Mirror python's
    # ephemeral clone, which deep-copies _multilingual.
    $clone->multilingual( defined $self->multilingual ? dclone( $self->multilingual ) : undef );

    # context_builder — the contexts tree is render-relevant (emitted under
    # ai.prompt.contexts) and was ALSO not carried by the clone, so a
    # dynamic-config request rendered off the clone lost the ENTIRE contexts
    # tree. Deep-copy the builder so per-request modifications (reset/rebuild in
    # a dynamic callback) don't leak into the shared original, mirroring
    # python's memo'd deepcopy of _contexts_builder. The builder holds a WEAK
    # backref to its owning agent; detach it across the copy (dclone would
    # otherwise drag the whole agent graph in) and re-attach the fresh copy to
    # the clone. Both the fluent builder (context_builder slot) and the
    # object-form external builder (_external_context_builder slot) are carried.
    # Read the RAW slots so we don't trigger the lazy builder on an agent that
    # never defined contexts.
    for my $slot (qw(context_builder _external_context_builder)) {
        my $src = $self->{$slot};
        next unless defined $src && ref $src && $src->can('has_contexts');

        my $has_agent = $src->can('_agent');
        my $saved_agent;
        if ($has_agent) {
            $saved_agent = $src->_agent;
            $src->_agent(undef);
        }
        my $copy = dclone($src);
        $src->_agent($saved_agent) if $has_agent;

        $clone->{$slot} = $copy;
        $copy->attach_agent($clone) if $copy->can('attach_agent');
    }

    return $clone;
}

# ---------- run / serve ----------

sub run {
    my ( $self, %opts ) = @_;

    # In-process test guard (swaig-test --file): when SWAIG_TEST_INPROCESS is
    # set, `run()` must NOT start the blocking HTTP server — swaig-test loads
    # the agent file with `do` to introspect its tools/SWML, and a quickstart
    # that ends in `$agent->run` would otherwise bind a socket and serve
    # forever (README file-mode workflow hung on all unguarded examples). Under
    # the flag, return $self so the loaded file yields the built agent to the
    # harness. This makes the "guard + return-the-agent" contract automatic for
    # EVERY agent file (user agents included), not just the few examples that
    # hand-wrote an `unless caller` guard.
    return $self if $ENV{SWAIG_TEST_INPROCESS};

    return $self->serve(%opts);
}

# handle_serverless_request — dispatch a request in a serverless
# environment (CGI / Lambda / Cloud Functions).
#
# Python parity: ServerlessMixin.handle_serverless_request(event, context,
# mode). Ruby parity: routes through the same PSGI/rack app the HTTP
# server uses. When mode is not given it is auto-detected via
# get_execution_mode(). In 'lambda' mode a Lambda-proxy response hashref
# ({ statusCode, headers, body }) is returned; in 'cgi' mode the rendered
# body string is returned; any other mode falls through to run().
sub handle_serverless_request {
    my ( $self, %opts ) = @_;
    my $event   = $opts{event};
    my $context = $opts{context};

    require SignalWire::Core::LoggingConfig;
    my $mode = $opts{mode} // SignalWire::Core::LoggingConfig::get_execution_mode();

    if ( $mode eq 'lambda' ) {
        return $self->_run_serverless_lambda($event);
    } elsif ( $mode eq 'cgi' ) {
        return $self->_run_serverless_cgi;
    } elsif ( $mode eq 'google_cloud_function' || $mode eq 'gcf' ) {
        return $self->_run_serverless_gcf($event);
    } elsif ( $mode eq 'azure_function' || $mode eq 'azure' ) {
        return $self->_run_serverless_azure($event);
    }

    return $self->run( host => $opts{host}, port => $opts{port} );
}

# Build a minimal PSGI env for a serverless/CGI invocation.
sub _serverless_psgi_env {
    my ( $self, %args ) = @_;
    my $body = $args{body} // '';
    my $input;
    open $input, '<', \$body or ( $input = undef );
    return {
        PATH_INFO      => $args{path}   // '/',
        REQUEST_METHOD => $args{method} // 'GET',
        QUERY_STRING   => $args{query}  // '',
        'psgi.input'   => $input,
        'psgi.errors'  => \*STDERR,
    };
}

# Lambda: dispatch the event DIRECTLY (Python parity:
# ServerlessMixin.handle_serverless_request, mode "lambda") — this does NOT
# route through the PSGI/framework app. It (1) enforces Basic auth and returns a
# 401 challenge when it fails, (2) strips rawPath and dispatches "/swaig"
# (function named in the body) or a path-named function to the SWAIG executor,
# and (3) falls back to rendering the SWML document at the root. Each success is
# a {statusCode:200, headers:{Content-Type:application/json}, body:<json>}
# Lambda-proxy response.
sub _run_serverless_lambda {
    my ( $self, $event ) = @_;

    # Auth challenge (Python: _check_lambda_auth -> _send_lambda_auth_challenge).
    unless ( $self->_check_lambda_auth($event) ) {
        return {
            statusCode => 401,
            headers    => { 'WWW-Authenticate' => 'Basic', 'Content-Type' => 'application/json' },
            body       => JSON::encode_json( { error => 'Unauthorized' } ),
        };
    }

    # No event at all -> root SWML.
    return $self->_lambda_swml_response unless $event && ref $event eq 'HASH';

    # HTTP API v2 uses rawPath; REST API v1 uses pathParameters.proxy.
    my $path = $event->{rawPath} // '';
    $path =~ s{^/+}{};
    $path =~ s{/+$}{};
    if ( $path eq '' && ref $event->{pathParameters} eq 'HASH' ) {
        $path = $event->{pathParameters}{proxy} // '';
    }

    # Parse the request body for the function name + arguments.
    my ( $function_name, $args, $call_id, $raw_data ) = ( undef, {}, undef, undef );
    my $body_content = $event->{body};
    if ( defined $body_content && length $body_content ) {
        eval {
            $raw_data = ref $body_content ? $body_content : JSON::decode_json($body_content);
            if ( ref $raw_data eq 'HASH' ) {
                $call_id       = $raw_data->{call_id};
                $function_name = $raw_data->{function};
                if ( ref $raw_data->{argument} eq 'HASH' ) {
                    my $parsed = $raw_data->{argument}{parsed};
                    if ( ref $parsed eq 'ARRAY' && @$parsed ) {
                        $args = $parsed->[0];
                    } elsif ( defined $raw_data->{argument}{raw} ) {
                        my $decoded = eval { JSON::decode_json( $raw_data->{argument}{raw} ) };
                        $args = $decoded if ref $decoded eq 'HASH';
                    }
                }
            }
            1;
        };    # best-effort parse; empty args on failure (Python parity)
    }

    # /swaig endpoint with the function named in the body.
    if (   ( $path eq 'swaig' || $path eq 'swaig/' )
        && defined $function_name
        && length $function_name )
    {
        return $self->_lambda_swaig_response( $function_name, $args, $call_id, $raw_data );
    }

    # Path-based function routing (e.g. /say_hello).
    if ( length $path && $path ne 'swaig' && $path ne 'swaig/' ) {
        return $self->_lambda_swaig_response( $path, $args, $call_id, $raw_data );
    }

    # Root path (or /swaig without a function) -> SWML. The body's call_id (parsed
    # above) is threaded so a SECURE tool's rendered webhook carries its per-tool
    # ``__token`` (python threads call_id into every _render_swml call).
    return $self->_lambda_swml_response($call_id);
}

# _check_lambda_auth — Basic-auth gate for lambda mode (Python parity:
# ServerlessMixin._check_lambda_auth). Reads the event's headers hashref
# (case-insensitively) and compares against the agent's configured credentials.
sub _check_lambda_auth {
    my ( $self, $event ) = @_;
    my $headers = ( $event && ref $event->{headers} eq 'HASH' ) ? $event->{headers} : {};
    return $self->_check_basic_auth_headers($headers) ? 1 : 0;
}

# _lambda_swaig_response — execute a SWAIG function and shape the 200 response.
sub _lambda_swaig_response {
    my ( $self, $function_name, $args, $call_id, $raw_data ) = @_;
    $args //= {};
    my $result = $self->on_function_call( $function_name, $args, $raw_data );

    my $result_hash;
    if ( ref $result eq 'HASH' ) {
        $result_hash = $result;
    } elsif ( Scalar::Util::blessed($result) && $result->can('to_hash') ) {
        $result_hash = $result->to_hash;
    } else {
        $result_hash = { response => defined $result ? "$result" : '' };
    }
    return {
        statusCode => 200,
        headers    => { 'Content-Type' => 'application/json' },
        body       => JSON::encode_json($result_hash),
    };
}

# _lambda_swml_response — render the SWML document as the 200 root response.
# $call_id (when the event body carried one) makes each SECURE tool's per-tool
# ``__token`` mintable on the render.
sub _lambda_swml_response {
    my ( $self, $call_id ) = @_;
    my $doc = $self->_render_swml_for_call( undef, $call_id );
    return {
        statusCode => 200,
        headers    => { 'Content-Type' => 'application/json' },
        body       => ref $doc ? JSON::encode_json($doc) : $doc,
    };
}

# CGI: run PATH_INFO through the PSGI app and return the body string.
sub _run_serverless_cgi {
    my ($self) = @_;
    my $body   = '';
    my $len    = $ENV{CONTENT_LENGTH};
    if ( defined $len && $len =~ /^\d+$/ && $len > 0 ) {
        local $/;
        read( STDIN, $body, $len );
    }

    my $env = $self->_serverless_psgi_env(
        path   => $ENV{PATH_INFO}      // '/',
        method => $ENV{REQUEST_METHOD} // 'GET',
        query  => $ENV{QUERY_STRING}   // '',
        body   => $body,
    );

    my ( undef, undef, $response_body ) = @{ $self->psgi_app->($env) };
    return _join_psgi_body($response_body);
}

# Google Cloud Function: an event carries method/path/body (a Flask-request
# analog); run it through the PSGI app and shape a { status, headers, body }
# response hashref. Python parity: ServerlessMixin.
# _handle_google_cloud_function_request. php parity: Adapter::handleGcf.
sub _run_serverless_gcf {
    my ( $self, $event ) = @_;
    $event //= {};

    my $path = $event->{path} // $event->{rawPath} // '/';
    $path =~ s{\?.*$}{};    # strip any query string from the path
    my $method = uc( $event->{method} // $event->{httpMethod} // 'GET' );

    my $env = $self->_serverless_psgi_env(
        path   => $path,
        method => $method,
        query  => $event->{query} // '',
        body   => $event->{body}  // '',
    );

    my ( $status, $headers, $response_body ) = @{ $self->psgi_app->($env) };
    return {
        status  => int($status),
        headers => { @{ $headers // [] } },
        body    => _join_psgi_body($response_body),
    };
}

# Azure Function: an event carries a request URL + method/body; parse the path
# out of the URL, run it through the PSGI app, and shape a { status, headers,
# body } response hashref. Python parity:
# ServerlessMixin._handle_azure_function_request. php parity:
# Adapter::handleAzure.
sub _run_serverless_azure {
    my ( $self, $event ) = @_;
    $event //= {};

    my $url = $event->{url} // $event->{Url} // $event->{path} // '/';
    ( my $path = $url ) =~ s{^[a-z][a-z0-9+.\-]*://[^/]+}{}i;    # strip scheme+authority
    $path =~ s{\?.*$}{};                                         # strip query
    $path = '/' unless length $path;
    my $method = uc( $event->{method} // $event->{Method} // $event->{httpMethod} // 'GET' );
    my $body   = $event->{body} // $event->{Body} // '';

    my $env = $self->_serverless_psgi_env(
        path   => $path,
        method => $method,
        query  => '',
        body   => $body,
    );

    my ( $status, $headers, $response_body ) = @{ $self->psgi_app->($env) };
    return {
        status  => int($status),
        headers => { @{ $headers // [] } },
        body    => _join_psgi_body($response_body),
    };
}

sub _join_psgi_body {
    my ($body) = @_;
    return '' unless defined $body;
    return join( '', @$body ) if ref $body eq 'ARRAY';
    return "$body";
}

sub serve {
    my ( $self, %opts ) = @_;

    # In-process test guard (swaig-test --file, SWAIG_TEST_INPROCESS): a file
    # loaded for introspection must not bind a listen socket. Return $self so
    # `$agent->serve` (or run→serve) yields the agent instead of blocking.
    return $self if $ENV{SWAIG_TEST_INPROCESS};

    my $app  = $self->psgi_app;
    my $host = $opts{host} // $self->host;
    my $port = $opts{port} // $self->port;

    # HTTPS self-serve: when an SSL cert+key pair is configured the agent
    # presents it directly (no reverse proxy required), matching the Python
    # reference's uvicorn ssl_certfile/ssl_keyfile path. Two config sources,
    # mirroring Python:
    #   * Explicit serve()/run() options (ssl_cert + ssl_key) always enable
    #     TLS — the analogue of Python web_service.start(ssl_cert=, ssl_key=),
    #     which serves HTTPS whenever both are passed regardless of the flag.
    #   * Otherwise the SWML_SSL_* environment variables (same names the Python
    #     SecurityConfig reads): TLS only when SWML_SSL_ENABLED is truthy AND
    #     both SWML_SSL_CERT_PATH and SWML_SSL_KEY_PATH resolve.
    my ( $cert, $key ) = _resolve_tls( \%opts );
    if ( defined $cert && defined $key ) {
        return $self->_serve_tls( $app, $host, $port, $cert, $key );
    }

    require Plack::Runner;
    my $runner = Plack::Runner->new;
    $runner->parse_options(
        '--host'   => $host,
        '--port'   => $port,
        '--server' => 'HTTP::Server::PSGI',
    );
    return $runner->run($app);
}

# _resolve_tls(\%opts) -> ($cert, $key) when TLS should be served, else
# (undef, undef). Explicit ssl_cert + ssl_key options force HTTPS; otherwise the
# SWML_SSL_* environment is consulted (TLS only when SWML_SSL_ENABLED is truthy
# AND both cert + key paths are set), exactly matching the Python reference.
sub _resolve_tls {
    my ($opts) = @_;
    my $cert   = $opts->{ssl_cert} // $opts->{ssl_cert_path};
    my $key    = $opts->{ssl_key}  // $opts->{ssl_key_path};
    if ( defined $cert && length $cert && defined $key && length $key ) {
        return ( $cert, $key );
    }
    my $enabled = lc( $ENV{SWML_SSL_ENABLED} // '' );
    if ( $enabled eq 'true' || $enabled eq '1' || $enabled eq 'yes' ) {
        my $ecert = $ENV{SWML_SSL_CERT_PATH};
        my $ekey  = $ENV{SWML_SSL_KEY_PATH};
        if ( defined $ecert && length $ecert && defined $ekey && length $ekey ) {
            return ( $ecert, $ekey );
        }
    }
    return ( undef, undef );
}

# Serve $app over HTTPS by building an IO::Socket::SSL listen socket from the
# configured cert/key and handing it to HTTP::Server::PSGI via listen_sock
# (HTTP::Server::PSGI accepts an already-bound socket and derives host/port
# from it). IO::Socket::SSL is already a hard dependency (used by the RELAY
# client), so this adds no new dependency. Blocks like the plaintext path.
sub _serve_tls {
    my ( $self, $app, $host, $port, $cert, $key ) = @_;
    require IO::Socket::SSL;
    require HTTP::Server::PSGI;
    no warnings 'once';    # $IO::Socket::SSL::SSL_ERROR is populated at runtime

    my $ssl = IO::Socket::SSL->new(
        LocalAddr     => $host,
        LocalPort     => $port,
        Listen        => 5,
        ReuseAddr     => 1,
        SSL_cert_file => $cert,
        SSL_key_file  => $key,
        )
        or croak(
        "AgentBase: TLS listen on $host:$port failed: " . ( $IO::Socket::SSL::SSL_ERROR // $! ) );

    my $srv = HTTP::Server::PSGI->new(
        host        => $host,
        port        => $port,
        listen_sock => $ssl,
    );
    return $srv->run($app);
}

# ---------- helpers ----------

sub _generate_random_password {

    # Use /dev/urandom for cryptographically secure random bytes.
    # Die on failure rather than falling back to a weak password.
    my $bytes = '';
    if ( open my $fh, '<:raw', '/dev/urandom' ) {
        my $read = read( $fh, $bytes, 32 );
        close $fh;
        if ( defined $read && $read == 32 ) {

            # Convert to hex string (64 chars)
            return unpack( 'H*', $bytes );
        }
    }
    die "FATAL: Cannot generate secure random password - /dev/urandom unavailable or read failed. "
        . "Set SWML_BASIC_AUTH_PASSWORD environment variable instead.\n";
}

sub extract_sip_username {
    my ( $class_or_self, $body ) = @_;

    # Extract SIP username from a request body (hashref).
    # Looks in standard SignalWire fields for the SIP caller identity.
    return unless ref $body eq 'HASH';

    # Check call.from field (e.g., "sip:user@domain")
    my $from = $body->{call}{from} // $body->{sip_from} // $body->{from} // '';

    if ( $from =~ m{^sip:([^@]+)\@}i ) {
        return $1;
    }

    # Check for a direct caller_id_number
    if ( my $cid = $body->{call}{caller_id_number} // $body->{caller_id_number} ) {
        return $cid;
    }

    return;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Agent::AgentBase - base class for SignalWire AI agents

=head1 SYNOPSIS

    package MyAgent;
    use Moo;
    extends 'SignalWire::Agent::AgentBase';

    sub BUILD {
        my ($self) = @_;
        $self->prompt_add_section('Role', 'You are a helpful assistant.');
        $self->define_tool(          # inherited from SWML::Service
            name        => 'get_time',
            description => 'Get the current time',
            parameters  => { type => 'object', properties => {} },
            handler     => sub {
                require SignalWire::SWAIG::FunctionResult;
                return SignalWire::SWAIG::FunctionResult->new(
                    'The time is ' . localtime );
            },
        );
    }

    package main;
    MyAgent->new->run;   # start a Plack HTTP server

=head1 DESCRIPTION

L<SignalWire::Agent::AgentBase> is the Moo base class for all SignalWire AI
agents -- the Perl port of C<signalwire.agents.agent_base.AgentBase>. A
subclass configures its prompt, tools, skills, contexts, languages, hints,
and answer/verb behavior (typically in C<BUILD>), and the base class renders
the SWML document, exposes the HTTP endpoints (SWML, SWAIG, post-prompt,
optional MCP and SIP routing), validates inbound webhook auth, and serves
the agent -- as a Plack app, a standalone server, or a serverless handler.

It C<extends> L<SignalWire::SWML::Service>, from which it inherits the tool
registry and its C<define_tool> / C<register_swaig_function> / C<define_tools>
methods, plus the C<name>, C<route>, C<host>, C<port>, and basic-auth
attributes. This is a large "fat" base class; the sections below group its
own public surface. Consult the Python reference for the authoritative
per-argument contract. Setters generally return C<$self> for chaining.

=head1 ATTRIBUTES

Public read/write attributes configure the agent, including: C<auto_answer>,
C<record_call>, C<record_format>, C<record_stereo>; C<prompt_text>,
C<post_prompt>, C<use_pom>, C<pom_sections>; C<hints>, C<pattern_hints>,
C<languages>, C<multilingual>, C<pronunciations>, C<params>, C<global_data>,
C<native_functions>; C<internal_fillers>, C<debug_events_level>,
C<function_includes>, C<prompt_llm_params>, C<post_prompt_llm_params>;
C<pre_answer_verbs>, C<post_answer_verbs>, C<post_ai_verbs>,
C<answer_config>; C<sip_routing_enabled>, C<sip_auto_map>, C<sip_path>,
C<sip_usernames>; C<context_builder>, C<dynamic_config_callback>,
C<summary_callback>, C<debug_event_handler>; C<webhook_url>,
C<post_prompt_url>, C<proxy_url_base>, C<swaig_query_params>;
C<session_manager>, C<signing_key>, C<skill_manager>, C<mcp_servers>, and
C<mcp_server_enabled>. Most have accessors as named above; prefer the
grouped setter methods below where they exist.

=head1 METHODS

=head2 Prompt

C<set_prompt_text>, C<set_post_prompt>, C<prompt_add_section>,
C<prompt_add_subsection>, C<prompt_add_to_section>, C<prompt_has_section>,
C<get_prompt>, C<pom>, C<get_post_prompt>, C<get_raw_prompt>,
C<set_prompt_pom>, C<set_prompt_llm_params>, C<set_post_prompt_llm_params>.

=head2 Contexts

C<define_contexts>, C<get_contexts>, C<contexts>, C<reset_contexts>.

=head2 Tool tokens

C<create_tool_token>, C<validate_tool_token>, C<list_tool_names>.

=head2 Hints and pronunciations

C<add_hint>, C<add_hints>, C<add_pattern_hint>, C<add_pronunciation>,
C<set_pronunciations>.

=head2 Languages

C<add_language>, C<set_languages>, C<set_multilingual>,
C<set_language_params>, C<get_language_params>.

=head2 Params and data

C<set_param>, C<set_params>, C<set_global_data>, C<update_global_data>.

=head2 Functions and fillers

C<set_native_functions>, C<set_internal_fillers>, C<add_internal_filler>,
C<add_function_include>, C<set_function_includes>, C<enable_debug_events>.

=head2 Answer and verbs

C<add_pre_answer_verb>, C<add_post_answer_verb>, C<add_post_ai_verb>,
C<add_answer_verb>, C<clear_pre_answer_verbs>, C<clear_post_answer_verbs>,
C<clear_post_ai_verbs>, C<set_answer_config>.

=head2 SIP routing

C<enable_sip_routing>, C<register_sip_username>, C<auto_map_sip_usernames>,
C<extract_sip_username>.

=head2 Skills

C<add_skill>, C<remove_skill>, C<list_skills>, C<has_skill>.

=head2 Callbacks and URLs

C<set_dynamic_config_callback>, C<on_summary>, C<on_debug_event>,
C<set_web_hook_url>, C<set_post_prompt_url>, C<manual_set_proxy_url>,
C<add_swaig_query_params>, C<clear_swaig_query_params>, C<get_full_url>,
C<get_name>.

=head2 MCP

C<add_mcp_server>, C<enable_mcp_server>.

=head2 Serving

C<render_swml>, C<psgi_app>, C<handle_request>, C<run>, C<serve>,
C<handle_serverless_request>.

=head1 SEE ALSO

L<SignalWire::SWML::Service>, L<SignalWire::SWAIG::FunctionResult>,
L<SignalWire::DataMap>, L<SignalWire::Contexts::ContextBuilder>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
