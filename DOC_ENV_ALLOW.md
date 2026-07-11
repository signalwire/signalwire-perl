# DOC_ENV_ALLOW — justified DOC-ENV exceptions (perl)

Each `- VAR — reason` line excuses one `doc_env.py` finding. Every entry below is a
proven NON-finding: the variable IS both documented AND read by the SDK — but
`doc_env.py`'s `ENV_READ_RE` / `CONST_VALUE_RE` cannot parse Perl's env-read idioms,
so the reads are invisible to the gate:

  * `ENV_READ_RE` allows only `[\s\[(\"']*` between the read marker and the var name,
    but Perl reads env as `$ENV{NAME}` — the `{` is not in that character class, so
    EVERY `$ENV{...}` read is missed.
  * `CONST_VALUE_RE` matches `= "NAME"` but not Perl's fat-comma constants-class idiom
    `CONST => 'SWML_<name>'` (lib/SignalWire/Core/SecurityConfig.pm), then read via
    `$ENV{ CONST() }`.

The clean permanent fix is a two-character porting-sdk change (add `{` to
`ENV_READ_RE`'s class; let `CONST_VALUE_RE` accept `=>`); flagged to the orchestrator.
Until that lands, these entries keep the gate honest without deleting correct docs.
Each var's read site is cited so the claim is verifiable.

- SIGNALWIRE_LOG_LEVEL — read via `$ENV{SIGNALWIRE_LOG_LEVEL}` (lib/SignalWire/Core/LoggingConfig.pm); gate can't see `$ENV{}` (perl, 2026-07-11)
- SIGNALWIRE_LOG_MODE — read via `$ENV{SIGNALWIRE_LOG_MODE}` (lib/SignalWire/Core/LoggingConfig.pm); gate can't see `$ENV{}` (perl, 2026-07-11)
- SIGNALWIRE_PROJECT_ID — read via `$ENV{SIGNALWIRE_PROJECT_ID}` (RestClient default + LoggingConfig); gate can't see `$ENV{}` (perl, 2026-07-11)
- SIGNALWIRE_API_TOKEN — read via `$ENV{SIGNALWIRE_API_TOKEN}` (RestClient token default, reference parity); gate can't see `$ENV{}` (perl, 2026-07-11)
- SIGNALWIRE_SPACE — read via `$ENV{SIGNALWIRE_SPACE}` (RestClient host default, reference parity); gate can't see `$ENV{}` (perl, 2026-07-11)
- SIGNALWIRE_SIGNING_KEY — read via `$ENV{SIGNALWIRE_SIGNING_KEY}` (webhook signature validation); gate can't see `$ENV{}` (perl, 2026-07-11)
- SIGNALWIRE_RELAY_HOST — documented only in EXAMPLES_RUN_ALLOW.md as an env a RELAY audit example needs (loopback WS fixture), not an SDK-surface promise; not an SDK knob the code must read (perl, 2026-07-11)
- SWML_HOST — read via `$ENV{SWML_HOST}` (server bind host); gate can't see `$ENV{}` (perl, 2026-07-11)
- SWML_PORT — read via `$ENV{SWML_PORT}` (server bind port); gate can't see `$ENV{}` (perl, 2026-07-11)
- SWML_PROXY_URL_BASE — read via `$ENV{SWML_PROXY_URL_BASE}` (proxy URL base); gate can't see `$ENV{}` (perl, 2026-07-11)
- SWML_BASIC_AUTH_USER — read via `$ENV{SWML_BASIC_AUTH_USER}` (basic-auth user); gate can't see `$ENV{}` (perl, 2026-07-11)
- SWML_BASIC_AUTH_PASSWORD — read via `$ENV{SWML_BASIC_AUTH_PASSWORD}` (basic-auth password); gate can't see `$ENV{}` (perl, 2026-07-11)
- SWML_ALLOW_PRIVATE_URLS — read via `$ENV{SWML_ALLOW_PRIVATE_URLS}` (SSRF guard); gate can't see `$ENV{}` (perl, 2026-07-11)
- SWML_SSL_ENABLED — read via `SSL_ENABLED => 'SWML_SSL_ENABLED'` const then `$ENV{}` (SecurityConfig.pm); gate can't see `$ENV{}`/`=>` (perl, 2026-07-11)
- SWML_SSL_CERT_PATH — read via `SSL_CERT_PATH => 'SWML_SSL_CERT_PATH'` const then `$ENV{}` (SecurityConfig.pm); gate can't see `$ENV{}`/`=>` (perl, 2026-07-11)
- SWML_SSL_KEY_PATH — read via `SSL_KEY_PATH => 'SWML_SSL_KEY_PATH'` const then `$ENV{}` (SecurityConfig.pm); gate can't see `$ENV{}`/`=>` (perl, 2026-07-11)
- SWML_DOMAIN — read via `SSL_DOMAIN => 'SWML_DOMAIN'` const then `$ENV{}` (SecurityConfig.pm); gate can't see `$ENV{}`/`=>` (perl, 2026-07-11)
- SWML_ALLOWED_HOSTS — read via `ALLOWED_HOSTS => 'SWML_ALLOWED_HOSTS'` const then `$ENV{}` (SecurityConfig.pm); gate can't see `$ENV{}`/`=>` (perl, 2026-07-11)
- SWML_CORS_ORIGINS — read via `CORS_ORIGINS => 'SWML_CORS_ORIGINS'` const then `$ENV{}` (SecurityConfig.pm); gate can't see `$ENV{}`/`=>` (perl, 2026-07-11)
