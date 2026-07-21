# TLS-verify-off allowlist (perl)

This file records the ONE legitimate allowlist reason the PSDK-6 TLS-VERIFY gate
(`porting-sdk/scripts/tls_verify.py`) accepts: a **secure-default-gated
`verify_ssl` config opt-in**. Per the gate's own fix message and docstring, a
config option with a SECURE default (verification ON) that an operator may
explicitly disable for a self-signed-cert environment is the endorsed idiom
(python's `verify=self.verify_ssl`) — and its `HTTP::Tiny->new(...)` site is
allowlisted rather than forced to a hardcoded literal.

Format (parsed by `_load_allow`): `- <check-id> — reason`.

- tls-verify-off:lib/SignalWire/Skills/Builtin/McpGateway.pm:79 — mcp_gateway CLIENT skill: `HTTP::Tiny->new(verify_SSL => $self->verify_ssl)` threads the `verify_ssl` config param, whose default is SECURE (verify ON — see `verify_ssl` attribute default `1` and the `get_parameter_schema` default `JSON::true`, both confirmed by `verify_ssl_parity.py` → secure_default:true). Setting `verify_ssl => 0` is the explicit self-signed-cert opt-out, mirroring python's `verify=self.verify_ssl`. This is the exact secure-default-gated site the gate's fix message names as the allowlisted idiom (perl port skill work, 2026-07-20).
