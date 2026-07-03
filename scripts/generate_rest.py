#!/usr/bin/env python3
"""Generate the SignalWire REST namespace resource layer for signalwire-perl.

This is the PERL realization of porting-sdk/REST_GENERATOR_RULES.md — the
language-neutral contract of the REST resource generator (bases,
x-sdk-resource markup, path composition, command-dispatch, set_methods,
cross-spec client-tree placement, fail-loud invariants).

Perl's enumerators are Python (scripts/enumerate_signatures.py /
enumerate_surface.pl), so — mirroring php's scripts/generate_rest.py — this is a
Python script that emits Perl .pm modules. It reads the shared specs and x-sdk-*
markup and writes Perl resource classes.

Inputs (resolved from $PORTING_SDK or the adjacent ../porting-sdk):
    rest-apis/<ns>/openapi.yaml       (+ x-sdk-* markup)
    rest-apis/x-sdk-bases.yaml        (shared base method-sets)
    rest-apis/fabric/x-sdk-bases.yaml (FabricResource)

Outputs: Perl files under lib/SignalWire/REST/Namespaces/Generated/ — one .pm
per generated resource class, one container .pm per namespace group, and
ResourceTree.pm (a role the hand RestClient composes). The hand BASES stay
hand-written (lib/SignalWire/REST/Namespaces/Base.pm — Base/CrudResource) and
the hand HttpClient/RestClient; the generator emits ONLY the per-resource
classes that EXTEND those bases, their declared/command/set methods, and the
container tree.

Perl idiom (PORT_PHILOSOPHY_PERL.md §B): a kwargs-language, so each generated
operation/command/set method takes a **hash of named args** (`%args`, keyed by
the wire field name), an explicit **`extras`** door (a hash key merged into the
body), and — because Perl has no real keyword args — the slurpy `%args` hash
IS the trailing `**kwargs`/var_keyword tail. Constants/Type::Tiny typing is a
follow-up (the oracle keys operation/command params by name+kind, so the current
loose hash surface is drift-neutral against it). Reserved/uppercase wire fields
(`from`, `SWAIG`, `SWML`) are **valid Perl hash keys**, so NO rename is needed in
the emitted surface (unlike a language whose params are identifiers).

Classes are named by x-sdk-resource.name VERBATIM (the Python oracle canonical
names — DatasphereDocuments, AiAgents, ShortCodes, VideoRooms, …), each emitted
as its own package `SignalWire::REST::Namespaces::Generated::<Name>`, so the Perl
adapter projects each generated class onto the same
signalwire.rest.namespaces.<ns>_resources_generated.<Name> oracle module.

Usage:
    python3 scripts/generate_rest.py                 # write into the repo tree
    python3 scripts/generate_rest.py --check         # GEN-FRESH: fail if stale
    python3 scripts/generate_rest.py --out DIR       # scratch: emit flat into DIR
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.stderr.write("generate_rest.py requires PyYAML (pip install pyyaml)\n")
    raise


# The 12 real REST spec directories (registry has no own dir — its resources
# live inside relay-rest via namespace: registry; swml-webhooks is types-only).
SPEC_DIRS = [
    "relay-rest", "fabric", "calling", "video", "datasphere",
    "logs", "message", "voice", "fax", "project", "chat", "pubsub",
]


# ---------------------------------------------------------------------------
# Resolution.
# ---------------------------------------------------------------------------

def resolve_porting_sdk() -> Path:
    env = os.environ.get("PORTING_SDK")
    if env and (Path(env) / "rest-apis").is_dir():
        return Path(env).resolve()
    here = Path(__file__).resolve()
    for parent in here.parents:
        cand = parent.parent / "porting-sdk"
        if (cand / "rest-apis").is_dir():
            return cand.resolve()
    raise SystemExit("generate_rest.py: porting-sdk not found (set $PORTING_SDK or clone adjacent)")


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


# ---------------------------------------------------------------------------
# Base loading (x-sdk-bases; §2).
# ---------------------------------------------------------------------------

def load_bases(psdk: Path) -> dict[str, list[str]]:
    raw = yaml.safe_load((psdk / "rest-apis" / "x-sdk-bases.yaml").read_text())
    bases = dict(raw.get("x-sdk-bases") or {})
    fab = psdk / "rest-apis" / "fabric" / "x-sdk-bases.yaml"
    if fab.is_file():
        bases.update((yaml.safe_load(fab.read_text()).get("x-sdk-bases") or {}))

    def resolve(name: str, seen: set[str]) -> list[str]:
        if name in seen:
            raise SystemExit(f"x-sdk-bases: cyclic extends at {name}")
        if name not in bases:
            raise SystemExit(f"x-sdk-bases: undefined base {name!r}")
        seen = seen | {name}
        methods: list[str] = []
        ext = bases[name].get("extends")
        if ext:
            methods.extend(resolve(ext, seen))
        methods.extend(list((bases[name].get("methods") or {}).keys()))
        return methods

    return {name: resolve(name, set()) for name in bases}


# ---------------------------------------------------------------------------
# Spec model.
# ---------------------------------------------------------------------------

class Spec:
    def __init__(self, name: str, doc: dict):
        self.name = name
        self.doc = doc
        self.server_path = _url_path(doc["servers"][0]["url"])
        if self.server_path != "/" and self.server_path.endswith("/"):
            raise SystemExit(f"{name}: servers[0].url path {self.server_path!r} has a trailing slash")
        self.namespace_attr = (doc.get("x-sdk-namespace") or {}).get("attr") or ""
        self.ops: dict[str, tuple[str, str, bool]] = {}
        self.op_body: dict[str, dict] = {}  # operationId -> requestBody JSON schema (or {})
        for path, item in (doc.get("paths") or {}).items():
            for verb in ("get", "post", "put", "patch", "delete"):
                o = item.get(verb)
                if o and o.get("operationId"):
                    self.ops[o["operationId"]] = (verb, path, bool(o.get("requestBody")))
                    body = o.get("requestBody") or {}
                    content = body.get("content") or {}
                    media = content.get("application/json") or (next(iter(content.values())) if content else {})
                    self.op_body[o["operationId"]] = (media or {}).get("schema") or {}
        self.schemas = ((doc.get("components") or {}).get("schemas")) or {}

    def resources(self) -> list[tuple[str, dict]]:
        out = []
        for path, item in (self.doc.get("paths") or {}).items():
            r = item.get("x-sdk-resource")
            if r and not r.get("exclude") and r.get("name"):
                out.append((path, r))
        return out


def _url_path(url: str) -> str:
    if "://" in url:
        url = url.split("://", 1)[1]
    i = url.find("/")
    return url[i:] if i >= 0 else "/"


def load_spec(psdk: Path, ns: str) -> Spec:
    return Spec(ns, yaml.safe_load((psdk / "rest-apis" / ns / "openapi.yaml").read_text()))


# ---------------------------------------------------------------------------
# Path composition (§4).
# ---------------------------------------------------------------------------

def join_path(a: str, b: str) -> str:
    if not b:
        return a
    return a.rstrip("/") + "/" + b.lstrip("/")


def collection_segment(anchor: str, markup: dict) -> str:
    if "collection" in markup:
        return markup["collection"]
    p = anchor
    i = p.find("/{")
    if i >= 0:
        p = p[:i]
    return p


def base_path(spec: Spec, anchor: str, markup: dict) -> str:
    return join_path(spec.server_path, collection_segment(anchor, markup))


def relative_tail(spec: Spec, anchor: str, markup: dict, op_path: str):
    coll = collection_segment(anchor, markup)
    full = join_path(spec.server_path, coll)
    absp = join_path(spec.server_path, op_path)
    if coll and absp.startswith(full + "/"):
        return ([s for s in absp[len(full) + 1:].split("/") if s], False)
    if coll and absp == full:
        return ([], False)
    return ([s for s in absp.lstrip("/").split("/") if s], True)


# ---------------------------------------------------------------------------
# Naming.
# ---------------------------------------------------------------------------

def snake(s: str) -> str:
    """Fold a wire/command token to a snake_case Perl method name."""
    s = s.replace("-", "_").replace(".", "_")
    return s


def arg_for(brace: str) -> str:
    """Path-param brace name → snake_case Perl arg name (§4)."""
    return snake(brace) or "id"


def perl_str(s: str) -> str:
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"


# ---------------------------------------------------------------------------
# Base mapping (§2).
# ---------------------------------------------------------------------------

BASE_PROVIDES = {
    "CrudResource": {"list", "create", "get", "update", "delete"},
    "FabricResource": {"list", "create", "get", "update", "delete", "list_addresses"},
    "ReadResource": {"list", "get"},
    "BaseResource": set(),
}

# The Perl parent PACKAGE each markup base maps to. The hand bases
# (Namespaces::Base = BaseResource, Namespaces::CrudResource) are reused; the
# generated layer adds its own ReadResource + Fabric bases into the Generated::
# package space so the whole generated tree is self-contained and re-run-safe.
EXTENDS = {
    "CrudResource": "SignalWire::REST::Namespaces::CrudResource",
    "ReadResource": "SignalWire::REST::Namespaces::Generated::ReadResource",
    "FabricResource": "SignalWire::REST::Namespaces::Generated::FabricResource",
    "BaseResource": "SignalWire::REST::Namespaces::Base",
}


# ---------------------------------------------------------------------------
# Command-dispatch (§6).
# ---------------------------------------------------------------------------

def command_method_name(cmd: str) -> str:
    # strip a leading `calling.` domain prefix, dots -> underscores.
    s = cmd[len("calling."):] if cmd.startswith("calling.") else cmd
    return s.replace(".", "_")


def discriminator_mapping(spec: Spec, schema_name: str) -> list[str]:
    sch = spec.schemas.get(schema_name)
    if sch is None:
        raise SystemExit(f"command-dispatch request {schema_name!r} not in components.schemas")
    mapping = (sch.get("discriminator") or {}).get("mapping")
    if not mapping:
        raise SystemExit(f"command-dispatch request {schema_name!r} has no discriminator.mapping")
    return list(mapping.keys())


# ---------------------------------------------------------------------------
# Typed inputs (§5) — schema → canonical audit type (the sidecar carries these;
# the Perl surface is a loose named-hash, drift-neutral against the oracle since
# the oracle keys operation/command params by name+kind, not by static type).
# ---------------------------------------------------------------------------

def resolve_schema(spec: Spec, schema: dict | None, seen=None) -> dict:
    if not schema:
        return {}
    if seen is None:
        seen = set()
    ref = schema.get("$ref")
    if ref:
        leaf = ref.rsplit("/", 1)[-1]
        if leaf in seen:
            return {}
        seen.add(leaf)
        return resolve_schema(spec, spec.schemas.get(leaf), seen)
    allof = schema.get("allOf")
    if allof and len(allof) == 1 and not schema.get("properties") and not schema.get("type"):
        return resolve_schema(spec, allof[0], seen)
    return schema


def _is_named_ref(schema: dict) -> bool:
    if not schema:
        return False
    if schema.get("$ref"):
        return True
    allof = schema.get("allOf")
    if allof and len(allof) == 1 and not schema.get("properties") and not schema.get("type"):
        return _is_named_ref(allof[0])
    return False


def _json_type(schema: dict) -> str | None:
    t = schema.get("type")
    if isinstance(t, list):
        non_null = [x for x in t if x != "null"]
        return non_null[0] if non_null else None
    return t


_SCALAR_CANON = {"string": "string", "integer": "int", "number": "float", "boolean": "bool"}


def canonical_type(spec: Spec, schema: dict, required: bool) -> str:
    """Canonical audit type for the sidecar (drift-neutral):
      * optional (any JSON type)         → optional<any>
      * required NAMED-$ref              → dict<string,any> (folds onto gen:<Name>)
      * required scalar                  → string/int/float/bool
      * required array                   → list<any>
      * required inline object/union     → dict<string,any>
    """
    if not required:
        return "optional<any>"
    if _is_named_ref(schema):
        return "dict<string,any>"
    resolved = resolve_schema(spec, schema)
    jt = _json_type(resolved)
    if jt in _SCALAR_CANON:
        return _SCALAR_CANON[jt]
    if jt == "array":
        return "list<any>"
    return "dict<string,any>"


def object_body_fields(spec: Spec, body_schema: dict) -> list[tuple[str, dict, bool]]:
    resolved = resolve_schema(spec, body_schema)
    props: dict[str, dict] = {}
    required: set[str] = set(resolved.get("required") or [])
    for name, psc in (resolved.get("properties") or {}).items():
        props.setdefault(name, psc)
    for br in resolved.get("allOf") or []:
        rb = resolve_schema(spec, br)
        required |= set(rb.get("required") or [])
        for name, psc in (rb.get("properties") or {}).items():
            props.setdefault(name, psc)
    return [(name, psc, name in required) for name, psc in props.items()]


def command_param_fields(spec: Spec, command_schema: dict) -> tuple[list[tuple[str, dict, bool]], bool]:
    """§6 union-flatten: expose the UNION of all variants' params fields; a field
    required only if EVERY variant requires it. has_id = the command has `id`."""
    cs = resolve_schema(spec, command_schema)
    has_id = "id" in (cs.get("properties") or {})
    params_schema = (cs.get("properties") or {}).get("params")
    if params_schema is None:
        return [], has_id
    ps = resolve_schema(spec, params_schema)
    variants: list[dict] = []
    for comb in ("anyOf", "oneOf"):
        if comb in ps:
            variants = [resolve_schema(spec, v) for v in ps[comb]]
            break
    if not variants:
        variants = [ps]
    all_props: dict[str, dict] = {}
    req_sets: list[set[str]] = []
    for v in variants:
        req_sets.append(set(v.get("required") or []))
        for name, psc in (v.get("properties") or {}).items():
            all_props.setdefault(name, psc)
    req_all = set.intersection(*req_sets) if req_sets else set()
    return [(name, psc, name in req_all) for name, psc in all_props.items()], has_id


def is_object_body(spec: Spec, body_schema: dict) -> bool:
    if not body_schema:
        return False
    if "anyOf" in body_schema or "oneOf" in body_schema:
        return False
    resolved = resolve_schema(spec, body_schema)
    if "anyOf" in resolved or "oneOf" in resolved:
        return False
    if resolved.get("properties") or resolved.get("allOf"):
        return True
    return _json_type(resolved) == "object"


def ordered_fields(fields: list[tuple[str, dict, bool]]) -> list[tuple[str, dict, bool]]:
    """Required-first, then optional; stable (spec order) within each group."""
    req = [f for f in fields if f[2]]
    opt = [f for f in fields if not f[2]]
    return req + opt


# Sidecar accumulator: (ClassName, perlMethodName) -> [param records without self].
_SIDECAR: dict[tuple[str, str], list[dict]] = {}


def _register_sidecar(cls: str, method: str, records: list[dict]) -> None:
    _SIDECAR[(cls, method)] = records


def body_field_records(spec: Spec, fields: list[tuple[str, dict, bool]],
                       leading: list[dict]) -> list[dict]:
    """Canonical sidecar records for an object body: leading positional id args,
    then each field as a keyword arg (required-first), then the extras keyword
    door + a trailing var_keyword (`kwargs`) — the Perl slurpy realizes both."""
    records: list[dict] = list(leading)
    for wire_name, schema, required in ordered_fields(fields):
        ct = canonical_type(spec, schema, required)
        rec: dict = {"name": wire_name, "kind": "keyword", "type": ct, "required": required}
        if not required:
            rec["default"] = None
        records.append(rec)
    records.append({"name": "extras", "kind": "keyword",
                    "type": "optional<dict<string,any>>", "required": False, "default": None})
    records.append({"name": "kwargs", "kind": "var_keyword", "type": "any",
                    "required": False, "default": {}})
    return records


# ---------------------------------------------------------------------------
# Emitters.
# ---------------------------------------------------------------------------

GEN_BANNER = (
    "# Code generated by scripts/generate_rest.py; DO NOT EDIT.\n"
    "#\n"
    "# AUTO-GENERATED from porting-sdk/rest-apis/ (x-sdk-* markup) — regenerate with:\n"
    "#   python3 scripts/generate_rest.py\n"
    "#\n"
    "# {desc}\n"
)


def method_call_path(spec: Spec, anchor: str, markup: dict, op_path: str):
    """Return (id_args, perl_path_expr)."""
    segs, sibling = relative_tail(spec, anchor, markup, op_path)
    id_args: list[str] = []
    pieces: list[str] = []
    for s in segs:
        if s.startswith("{") and s.endswith("}"):
            arg = arg_for(s[1:-1])
            while arg in id_args:
                arg += "2"
            id_args.append(arg)
            pieces.append("$" + arg)
        else:
            pieces.append(perl_str(s))
    if sibling:
        full = join_path(spec.server_path, op_path.lstrip("/"))
        expr = abs_perl_path(full, id_args)
    elif not pieces:
        expr = "$self->_base_path"
    else:
        expr = "$self->_path(" + ", ".join(pieces) + ")"
    return id_args, expr


def abs_perl_path(full: str, id_args: list[str]) -> str:
    """Perl string-concat expression for a sibling absolute path, substituting
    {brace} with the positional $id_args in order."""
    out = []
    literal = []
    ai = 0
    i = 0
    while i < len(full):
        if full[i] == "{":
            j = full.find("}", i)
            if literal:
                out.append(perl_str("".join(literal)))
                literal = []
            if ai < len(id_args):
                out.append("$" + id_args[ai])
                ai += 1
            i = j + 1
            continue
        literal.append(full[i])
        i += 1
    if literal:
        out.append(perl_str("".join(literal)))
    return " . ".join(out) if out else "''"


def emit_method(spec: Spec, anchor: str, markup: dict, base: str,
                method_snake: str, op_id: str) -> str:
    if op_id not in spec.ops:
        raise SystemExit(f"{markup['name']}.{method_snake}: op {op_id!r} not in spec")
    verb, op_path, has_body = spec.ops[op_id]
    id_args, path_expr = method_call_path(spec, anchor, markup, op_path)
    name = method_snake
    cls = markup["name"]

    id_records = [{"name": a, "kind": "positional", "type": "string", "required": True}
                  for a in id_args]
    id_unpack = "".join(", $" + a for a in id_args)
    write_verb = verb in ("post", "put", "patch")
    lines: list[str] = []

    if write_verb and has_body:
        body_schema = spec.op_body.get(op_id) or {}
        if is_object_body(spec, body_schema):
            # §5.1 object body → named-hash args + extras (the slurpy is the tail).
            fields = object_body_fields(spec, body_schema)
            _register_sidecar(cls, name, body_field_records(spec, fields, id_records))
            lines.append(f"sub {name} {{")
            lines.append(f"    my ( $self{id_unpack}, %args ) = @_;")
            lines.append("    my $body = { %args };")
            verb_fn = {"post": "post", "put": "put", "patch": "patch"}[verb]
            lines.append(f"    return $self->_http->{verb_fn}( {path_expr}, body => $body );")
            lines.append("}")
        else:
            # §5.2 union body → a single positional `body` param.
            _register_sidecar(cls, name, id_records + [
                {"name": "body", "kind": "positional", "type": "dict<string,any>", "required": True},
            ])
            verb_fn = {"post": "post", "put": "put", "patch": "patch"}[verb]
            lines.append(f"sub {name} {{")
            lines.append(f"    my ( $self{id_unpack}, $body ) = @_;")
            lines.append(f"    return $self->_http->{verb_fn}( {path_expr}, body => $body );")
            lines.append("}")
    elif write_verb:
        # write verb, no body → empty body.
        _register_sidecar(cls, name, list(id_records))
        verb_fn = {"post": "post", "put": "put", "patch": "patch"}[verb]
        lines.append(f"sub {name} {{")
        lines.append(f"    my ( $self{id_unpack} ) = @_;")
        lines.append(f"    return $self->_http->{verb_fn}( {path_expr}, body => {{}} );")
        lines.append("}")
    elif verb == "get":
        # §5.3 GET query door — a trailing var_keyword `params` map.
        _register_sidecar(cls, name, id_records + [
            {"name": "params", "kind": "var_keyword", "type": "any", "required": False, "default": {}},
        ])
        lines.append(f"sub {name} {{")
        lines.append(f"    my ( $self{id_unpack}, %params ) = @_;")
        lines.append("    my $p = %params ? \\%params : undef;")
        lines.append(f"    return $self->_http->get( {path_expr}, params => $p );")
        lines.append("}")
    else:  # delete
        _register_sidecar(cls, name, list(id_records))
        lines.append(f"sub {name} {{")
        lines.append(f"    my ( $self{id_unpack} ) = @_;")
        lines.append(f"    return $self->_http->delete_request( {path_expr} );")
        lines.append("}")
    return "\n".join(lines) + "\n"


def schema_fields(spec: Spec, schema: dict, seen=None) -> set[str]:
    if schema is None:
        return set()
    if seen is None:
        seen = set()
    ref = schema.get("$ref")
    if ref:
        leaf = ref.rsplit("/", 1)[-1]
        if leaf in seen:
            return set()
        seen.add(leaf)
        return schema_fields(spec, spec.schemas.get(leaf), seen)
    out = set(((schema.get("properties")) or {}).keys())
    for comb in ("allOf", "anyOf", "oneOf"):
        for br in schema.get(comb) or []:
            out |= schema_fields(spec, br, seen)
    return out


def _item_update_verb(spec: Spec, anchor: str, markup: dict) -> str | None:
    """The actual update verb (PUT/PATCH) the spec declares at the item-level
    ``<collection>/{id}`` path (NOT the anchor collection path, which only carries
    list/create). Returns None when the resource has no item-level write op.
    Used for the §9 update_method fail-loud check (the anchor path never has the
    update op, so checking the anchor silently skipped the validation)."""
    coll = collection_segment(anchor, markup)
    for path, item in (spec.doc.get("paths") or {}).items():
        if not path.startswith(coll + "/{"):
            continue
        if path.count("/{") != 1 or not path.endswith("}"):
            continue
        if item.get("put"):
            return "PUT"
        if item.get("patch"):
            return "PATCH"
    return None


def update_request_fields(spec: Spec, anchor: str, markup: dict) -> set[str]:
    coll = collection_segment(anchor, markup)
    want_verb = "put" if markup.get("update_method") == "PUT" else "patch"
    for path, item in (spec.doc.get("paths") or {}).items():
        if not path.startswith(coll + "/{"):
            continue
        if path.count("/{") != 1 or not path.endswith("}"):
            continue
        op = item.get(want_verb) or item.get("put") or item.get("patch")
        if not op:
            continue
        content = (op.get("requestBody") or {}).get("content") or {}
        for media in content.values():
            sch = media.get("schema")
            if sch:
                return schema_fields(spec, sch)
    return set()


def update_field_schemas(spec: Spec, anchor: str, markup: dict) -> dict[str, dict]:
    coll = collection_segment(anchor, markup)
    want_verb = "put" if markup.get("update_method") == "PUT" else "patch"
    for path, item in (spec.doc.get("paths") or {}).items():
        if not path.startswith(coll + "/{"):
            continue
        if path.count("/{") != 1 or not path.endswith("}"):
            continue
        op = item.get(want_verb) or item.get("put") or item.get("patch")
        if not op:
            continue
        content = (op.get("requestBody") or {}).get("content") or {}
        for media in content.values():
            sch = media.get("schema")
            if sch:
                out: dict[str, dict] = {}
                for name, psc, _ in object_body_fields(spec, sch):
                    out[name] = psc
                return out
    return {}


def emit_set_method(spec: Spec, markup: dict, sm_name: str, sm: dict,
                    update_schema_fields: set[str], field_schemas: dict[str, dict]) -> str:
    handler = sm.get("handler")
    if not handler:
        raise SystemExit(f"{markup['name']}.{sm_name}: set_method missing handler")
    cls = markup["name"]
    args = sm.get("args") or {}
    # resource_id is a leading positional (matches the oracle); args are POSITIONAL
    # in the oracle (they wrap update()); a trailing var_keyword `extra` door.
    records: list[dict] = [
        {"name": "resource_id", "kind": "positional", "type": "string", "required": True},
    ]
    required_names: list[tuple[str, str]] = []   # (arg_name, wire field)
    optional_names: list[tuple[str, str]] = []
    for arg_name, arg in args.items():
        field = arg.get("field")
        if not field:
            raise SystemExit(f"{markup['name']}.{sm_name}: arg {arg_name!r} missing field")
        if field not in update_schema_fields:
            raise SystemExit(
                f"{markup['name']}.{sm_name}: arg field {field!r} not in update request schema"
            )
        required = bool(arg.get("required"))
        ct = canonical_type(spec, field_schemas.get(field, {}), required)
        rec: dict = {"name": arg_name, "kind": "positional", "type": ct, "required": required}
        if required:
            required_names.append((arg_name, field))
        else:
            rec["default"] = None
            optional_names.append((arg_name, field))
        records.append(rec)
    records.append({"name": "extra", "kind": "var_keyword", "type": "any",
                    "required": False, "default": {}})
    _register_sidecar(cls, sm_name, records)

    # Positional signature: ($self, $resource_id, <required...>, <optional...>, %extra)
    pos = ["$" + a for a, _ in required_names] + ["$" + a for a, _ in optional_names]
    sig = ", ".join(["$self", "$resource_id"] + pos + ["%extra"])
    lines: list[str] = []
    lines.append(f"sub {sm_name} {{")
    lines.append(f"    my ( {sig} ) = @_;")
    lines.append("    my %body = (")
    lines.append(f"        call_handler => {perl_str(handler)},")
    for a, field in required_names:
        lines.append(f"        {perl_str(field)} => ${a},")
    lines.append("    );")
    for a, field in optional_names:
        lines.append(f"    $body{{{perl_str(field)}}} = ${a} if defined ${a};")
    lines.append("    return $self->update( $resource_id, %body, %extra );")
    lines.append("}")
    return "\n".join(lines) + "\n"


# The module that must be `require`d to load a given `extends` parent package
# (Moo's `extends` does NOT auto-load the parent). The hand Namespaces::Base file
# defines both Base and CrudResource; the generated bases each have their own file.
_PARENT_MODULE = {
    "SignalWire::REST::Namespaces::Base": "SignalWire::REST::Namespaces::Base",
    "SignalWire::REST::Namespaces::CrudResource": "SignalWire::REST::Namespaces::Base",
    "SignalWire::REST::Namespaces::Generated::ReadResource":
        "SignalWire::REST::Namespaces::Generated::ReadResource",
    "SignalWire::REST::Namespaces::Generated::FabricResource":
        "SignalWire::REST::Namespaces::Generated::FabricResource",
}


def package_header(pkg: str, extends: str | None, desc: str) -> str:
    out = GEN_BANNER.format(desc=desc)
    out += f"package {pkg};\n"
    out += "use strict;\n"
    out += "use warnings;\n"
    out += "use Moo;\n"
    if extends:
        parent_mod = _PARENT_MODULE.get(extends, extends)
        out += f"use {parent_mod} ();\n"
        out += f"extends '{extends}';\n"
    return out


def emit_command_dispatch(spec: Spec, anchor: str, markup: dict) -> str:
    name = markup["name"]
    request = markup.get("request")
    if not request:
        raise SystemExit(f"{name}: command-dispatch requires request")
    commands = discriminator_mapping(spec, request)
    op = spec.ops.get("call-commands")
    if op:
        base = join_path(spec.server_path, op[1].lstrip("/"))
    else:
        base = join_path(spec.server_path, anchor.lstrip("/"))

    pkg = f"SignalWire::REST::Namespaces::Generated::{name}"
    out = package_header(
        pkg, "SignalWire::REST::Namespaces::Base",
        f"Generated command-dispatch resource for the {spec.name!r} namespace. "
        f"Each method POSTs {{command, params, id?}} to the base path.",
    )
    out += "\n"
    # Bake the base path into the constructor (§4) so construction is
    # `<Class>->new( _http => $http )` — matching the other resources.
    out += "around BUILDARGS => sub {\n"
    out += "    my ( $orig, $class, %args ) = @_;\n"
    out += f"    $args{{_base_path}} //= {perl_str(base)};\n"
    out += "    return $class->$orig(%args);\n"
    out += "};\n"
    out += "\n"
    out += "# Each method POSTs { command, params, id? } to the resource base path.\n"
    out += "sub _execute {\n"
    out += "    my ( $self, $command, $call_id, %params ) = @_;\n"
    out += "    my %body = ( command => $command, params => \\%params );\n"
    out += "    $body{id} = $call_id if defined $call_id;\n"
    out += "    return $self->_http->post( $self->_base_path, body => \\%body );\n"
    out += "}\n"

    mapping = (spec.schemas.get(request).get("discriminator") or {}).get("mapping") or {}
    for cmd in commands:
        mname = command_method_name(cmd)
        cmd_schema_ref = mapping.get(cmd) or ""
        cmd_leaf = cmd_schema_ref.rsplit("/", 1)[-1] if cmd_schema_ref else ""
        cmd_schema = spec.schemas.get(cmd_leaf, {})
        fields, with_id = command_param_fields(spec, cmd_schema)

        records: list[dict] = []
        if with_id:
            records.append({"name": "call_id", "kind": "positional",
                            "type": "string", "required": True})
        for wire_name, schema, required in ordered_fields(fields):
            ct = canonical_type(spec, schema, required)
            rec: dict = {"name": wire_name, "kind": "keyword", "type": ct, "required": required}
            if not required:
                rec["default"] = None
            records.append(rec)
        records.append({"name": "extras", "kind": "keyword",
                        "type": "optional<dict<string,any>>", "required": False, "default": None})
        _register_sidecar(name, mname, records)

        out += "\n"
        if with_id:
            out += f"sub {mname} {{\n"
            out += "    my ( $self, $call_id, %args ) = @_;\n"
            out += f"    return $self->_execute( {perl_str(cmd)}, $call_id, %args );\n"
            out += "}\n"
        else:
            out += f"sub {mname} {{\n"
            out += "    my ( $self, %args ) = @_;\n"
            out += f"    return $self->_execute( {perl_str(cmd)}, undef, %args );\n"
            out += "}\n"
    out += "\n1;\n"
    return out


def emit_resource(spec: Spec, anchor: str, markup: dict) -> str:
    name = markup["name"]
    base = markup["base"]
    if markup.get("kind") == "command-dispatch":
        return emit_command_dispatch(spec, anchor, markup)
    if base not in EXTENDS:
        raise SystemExit(f"{name}: unknown base {base!r}")

    # §9: write-capable bases require update_method matching the spec verb.
    if base in ("CrudResource", "FabricResource"):
        upd = markup.get("update_method")
        if not upd:
            raise SystemExit(f"{name}: {base} requires update_method")
        spec_verb = _item_update_verb(spec, anchor, markup)
        if spec_verb and upd != spec_verb:
            raise SystemExit(f"{name}: update_method {upd} != spec update verb {spec_verb}")

    extends = EXTENDS[base]
    bp = base_path(spec, anchor, markup)

    pkg = f"SignalWire::REST::Namespaces::Generated::{name}"
    out = package_header(
        pkg, extends,
        f"Generated REST resource {name!r} ({spec.name} spec, base {base}).",
    )
    out += "\n"

    # Bake the base path + update verb into the constructor (§4) via a BUILDARGS
    # default so construction is `<Class>->new( _http => $http )`.
    if base in ("CrudResource", "FabricResource"):
        upd = markup.get("update_method", "PATCH")
        out += "around BUILDARGS => sub {\n"
        out += "    my ( $orig, $class, %args ) = @_;\n"
        out += f"    $args{{_base_path}}    //= {perl_str(bp)};\n"
        out += f"    $args{{_update_method}} //= {perl_str(upd)};\n"
        out += "    return $class->$orig(%args);\n"
        out += "};\n"
    else:
        out += "around BUILDARGS => sub {\n"
        out += "    my ( $orig, $class, %args ) = @_;\n"
        out += f"    $args{{_base_path}} //= {perl_str(bp)};\n"
        out += "    return $class->$orig(%args);\n"
        out += "};\n"

    provided = BASE_PROVIDES[base]
    declared = markup.get("methods") or {}

    for method_snake, spec_ref in declared.items():
        op_id = spec_ref.get("op")
        if not op_id:
            raise SystemExit(f"{name}.{method_snake}: method markup missing op")
        if method_snake in provided:
            if method_snake == "list_addresses":
                verb, op_path, _ = spec.ops[op_id]
                _, sibling = relative_tail(spec, anchor, markup, op_path)
                if not sibling:
                    continue
            else:
                continue
        out += "\n"
        out += emit_method(spec, anchor, markup, base, method_snake, op_id)

    # set_methods (§7): require a CRUD base.
    set_methods = markup.get("set_methods") or {}
    if set_methods:
        if base not in ("CrudResource", "FabricResource"):
            raise SystemExit(f"{name}: set_methods require a CRUD base, got {base}")
        upd_fields = update_request_fields(spec, anchor, markup)
        upd_field_schemas = update_field_schemas(spec, anchor, markup)
        for sm_name, sm in set_methods.items():
            out += "\n"
            out += emit_set_method(spec, markup, sm_name, sm, upd_fields, upd_field_schemas)

    out += "\n1;\n"
    return out


# ---------------------------------------------------------------------------
# Generated bases (ReadResource / FabricResource) — the Perl realizations of the
# x-sdk-bases method-sets that the hand tree doesn't already provide. CrudResource
# and BaseResource are reused from the hand Namespaces::Base.
# ---------------------------------------------------------------------------

def emit_read_resource_base() -> str:
    """ReadResource: list + get (no write) — extends the hand Base."""
    out = GEN_BANNER.format(desc="Generated ReadResource base (list/get) realizing the "
                                 "x-sdk-bases ReadResource method-set (§2).")
    out += "\npackage SignalWire::REST::Namespaces::Generated::ReadResource;\n"
    out += "use strict;\nuse warnings;\nuse Moo;\n"
    out += "use SignalWire::REST::Namespaces::Base ();\n"
    out += "extends 'SignalWire::REST::Namespaces::Base';\n\n"
    out += "sub list {\n"
    out += "    my ( $self, %params ) = @_;\n"
    out += "    my $p = %params ? \\%params : undef;\n"
    out += "    return $self->_http->get( $self->_base_path, params => $p );\n"
    out += "}\n\n"
    out += "sub get {\n"
    out += "    my ( $self, $resource_id ) = @_;\n"
    out += "    return $self->_http->get( $self->_path($resource_id) );\n"
    out += "}\n\n"
    out += "1;\n"
    return out


def emit_fabric_resource_base() -> str:
    """FabricResource: CrudResource + list_addresses — extends the hand CrudResource."""
    out = GEN_BANNER.format(desc="Generated FabricResource base (CrudResource + list_addresses) "
                                 "realizing the x-sdk-bases FabricResource method-set (§2).")
    out += "\npackage SignalWire::REST::Namespaces::Generated::FabricResource;\n"
    out += "use strict;\nuse warnings;\nuse Moo;\n"
    out += "use SignalWire::REST::Namespaces::Base ();\n"
    out += "extends 'SignalWire::REST::Namespaces::CrudResource';\n\n"
    out += "sub list_addresses {\n"
    out += "    my ( $self, $resource_id, %params ) = @_;\n"
    out += "    my $p = %params ? \\%params : undef;\n"
    out += "    return $self->_http->get( $self->_path( $resource_id, 'addresses' ), params => $p );\n"
    out += "}\n\n"
    out += "1;\n"
    return out


# ---------------------------------------------------------------------------
# Client tree (§8).
# ---------------------------------------------------------------------------

# Container attr -> (Perl container package leaf, RestClient accessor).
CONTAINERS = {
    "fabric": ("FabricNamespace", "fabric"),
    "video": ("VideoNamespace", "video"),
    "logs": ("LogsNamespace", "logs"),
    "registry": ("RegistryNamespace", "registry"),
    "project": ("ProjectNamespace", "project"),
    "datasphere": ("DatasphereNamespace", "datasphere"),
}

# Accessor-name overrides — mirrors the reference generator's _ATTR_OVERRIDE.
ATTR_OVERRIDE = {
    "GenericResources": "resources", "FabricAddresses": "addresses",
    "FabricTokens": "tokens", "DatasphereDocuments": "documents",
    "ProjectTokens": "tokens", "PubSub": "pubsub",
    "MessageLogs": "messages", "VoiceLogs": "voice", "FaxLogs": "fax",
    "ConferenceLogs": "conferences",
}


def _snake_accessor(name: str) -> str:
    """PascalCase class name → snake_case accessor."""
    s = re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()
    return s


def container_accessor(markup: dict, name: str, container: str) -> str:
    if markup.get("attr"):
        return markup["attr"]
    if name in ATTR_OVERRIDE:
        return ATTR_OVERRIDE[name]
    lead = container[:1].upper() + container[1:]
    stem = name[len(lead):] if name.startswith(lead) else name
    return _snake_accessor(stem) if stem else _snake_accessor(name)


def flat_accessor(name: str) -> str:
    if name in ATTR_OVERRIDE:
        return ATTR_OVERRIDE[name]
    return _snake_accessor(name)


def resolve_placement(specs: list[Spec]):
    placed = []
    for spec in specs:
        for anchor, markup in spec.resources():
            container = markup.get("namespace") or spec.namespace_attr or ""
            placed.append((spec, anchor, markup, container))
    return placed


def emit_container(container: str, members: list[tuple[str, str]]) -> str:
    """members: list of (accessor, class_name)."""
    cls, _ = CONTAINERS[container]
    pkg = f"SignalWire::REST::Namespaces::Generated::{cls}"
    out = GEN_BANNER.format(desc=f"Generated REST client container for the {container} namespace (§8).")
    out += f"\npackage {pkg};\n"
    out += "use strict;\nuse warnings;\nuse Moo;\n"
    for _accessor, class_name in members:
        out += f"use SignalWire::REST::Namespaces::Generated::{class_name} ();\n"
    out += "\n"
    out += "has '_http' => ( is => 'ro', required => 1 );\n"
    for accessor, _class_name in members:
        # init_arg => undef: these are lazily-built sub-resource accessors, never
        # constructor arguments (guards against a caller/credential arg of the same
        # name — e.g. `project` — colliding with the accessor).
        out += f"has '{accessor}' => ( is => 'lazy', init_arg => undef );\n"
    out += "\n"
    for accessor, class_name in members:
        out += f"sub _build_{accessor} {{\n"
        out += "    my ($self) = @_;\n"
        out += f"    return SignalWire::REST::Namespaces::Generated::{class_name}->new( _http => $self->_http );\n"
        out += "}\n\n"
    out += "1;\n"
    return out


def emit_resource_tree(placed) -> str:
    """Emit ResourceTree: a Moo::Role the hand RestClient composes, providing a
    lazy accessor per FLAT resource + per CONTAINER (§8)."""
    flats = []            # (accessor, class)
    containers_seen = []  # ordered container attrs
    seen_c = set()
    for spec, anchor, markup, container in placed:
        name = markup["name"]
        if not container:
            flats.append((flat_accessor(name), name))
        else:
            if container not in seen_c:
                seen_c.add(container)
                containers_seen.append(container)

    out = GEN_BANNER.format(desc="Generated REST resource tree role the hand RestClient composes (§8). "
                                 "Placement resolved from x-sdk-namespace.attr + per-resource "
                                 "x-sdk-resource.namespace/attr; base paths per §4.")
    out += "\npackage SignalWire::REST::Namespaces::Generated::ResourceTree;\n"
    out += "use strict;\nuse warnings;\nuse Moo::Role;\n"
    for _accessor, cls in flats:
        out += f"use SignalWire::REST::Namespaces::Generated::{cls} ();\n"
    for c in containers_seen:
        clsname, _acc = CONTAINERS[c]
        out += f"use SignalWire::REST::Namespaces::Generated::{clsname} ();\n"
    out += "\n"
    out += "# The consumer (the hand RestClient) must provide `_http`.\n"
    out += "requires '_http';\n\n"
    # init_arg => undef: these lazily-built resource/container accessors are never
    # constructor arguments. Critically, the consumer (the hand RestClient) takes a
    # `project` CREDENTIAL constructor arg; without init_arg => undef Moo would let
    # that value flow into the role's `project` (ProjectNamespace) accessor slot.
    for accessor, _cls in flats:
        out += f"has '{accessor}' => ( is => 'lazy', init_arg => undef );\n"
    for c in containers_seen:
        _clsname, acc = CONTAINERS[c]
        out += f"has '{acc}' => ( is => 'lazy', init_arg => undef );\n"
    out += "\n"
    for accessor, cls in flats:
        out += f"sub _build_{accessor} {{\n"
        out += "    my ($self) = @_;\n"
        out += f"    return SignalWire::REST::Namespaces::Generated::{cls}->new( _http => $self->_http );\n"
        out += "}\n\n"
    for c in containers_seen:
        clsname, acc = CONTAINERS[c]
        out += f"sub _build_{acc} {{\n"
        out += "    my ($self) = @_;\n"
        out += f"    return SignalWire::REST::Namespaces::Generated::{clsname}->new( _http => $self->_http );\n"
        out += "}\n\n"
    out += "1;\n"
    return out


# ---------------------------------------------------------------------------
# Wire-type emitter (item A/H — REAL read-side types, not a loose hash).
#
# For each REST namespace, emit one Perl data package per components/schemas
# entry whose schema is an OBJECT: a method-less Moo class with a read-only
# `has` attribute per property carrying the snake wire key. The Python reference
# records these as method-less type definitions, so the surface enumerator
# surfaces the bare package leaf with `[]` methods (Moo `has` accessors are NOT
# `sub` declarations, so enumerate_surface.pl's `^sub` scan never picks them up
# — the class stays method-less, matching the oracle).
#
# A named public enum (x-sdk-enum — only PhoneCallHandler in relay-rest) becomes
# a method-less Moo class exposing its wire values as `use constant` (surfaced as
# a bare class, matching the oracle which records the enum as a class name). Every
# OTHER schema kind — a scalar / array / union alias, a plain inline enum — is
# NOT surfaced by the Python reference (its enumerator drops module-level scalar
# TypeAlias / inline Literal), so this emitter emits nothing for it (verified per
# namespace: emit-set == oracle-set, 0 miss / 0 extra across all 13).
#
# Files land one-class-per-file under
#   lib/SignalWire/REST/Namespaces/Generated/Types/<Ns>/<TypeName>.pm
# in package SignalWire::REST::Namespaces::Generated::Types::<Ns>::<TypeName>.
# The <Ns> subdir maps 1:1 to the oracle <ns>_types_generated module
# (enumerate_surface.pl / enumerate_signatures.py route each Types/<Ns>/ file by
# PATH — the leaf recurs across namespaces, so path routing wins over any
# name-keyed map). The reference emits the SAME schema name into multiple
# <ns>_types_generated modules (shared SWML-schema types + shared Types_StatusCodes_*
# error types); Perl mirrors that per-namespace duplication faithfully, and the
# SURFACE-DIFF gen-type leaf-name fold collapses the duplicates on both sides.
#
# Unlike PHP, Perl package names are unrestricted — Goto/Return/Switch/Unset are
# valid package leaves (perl -c confirmed), so NO reserved-word suffix is needed;
# the emit-set matches the oracle bare (php had to suffix `_` and un-rename in its
# enumerator).
# ---------------------------------------------------------------------------

# Spec-dir -> the Perl Types subdir leaf + the oracle <ns>_types_generated leaf.
# The swml-webhooks spec is types-only (no resources, no servers block) and is
# loaded via _load_types_schemas. relay-rest folds registry.
TYPE_NS = [
    ("relay-rest", "RelayRest", "relay_rest"),
    ("fabric", "Fabric", "fabric"),
    ("calling", "Calling", "calling"),
    ("video", "Video", "video"),
    ("datasphere", "Datasphere", "datasphere"),
    ("logs", "Logs", "logs"),
    ("message", "Message", "message"),
    ("voice", "Voice", "voice"),
    ("fax", "Fax", "fax"),
    ("project", "Project", "project"),
    ("chat", "Chat", "chat"),
    ("pubsub", "PubSub", "pubsub"),
    ("swml-webhooks", "SwmlWebhooks", "swml_webhooks"),
]


def type_name(raw: str) -> str:
    """Sanitise a components/schemas key to a valid Perl package leaf, folding
    every non-identifier rune to ``_`` — matching the Go/TS/python ref_name so the
    LEAF the surface diff compares is the identical token across ports
    (``Types.StatusCodes.StatusCode400`` -> ``Types_StatusCodes_StatusCode400``).
    Perl imposes no reserved-word restriction on package names, so no suffix."""
    s = re.sub(r"[^A-Za-z0-9_]", "_", raw).lstrip("_")
    if not s:
        return "Schema"
    if s[0].isdigit():
        return "Schema_" + s
    return s


def _type_schema_type(node: dict):
    t = node.get("type")
    if isinstance(t, list):
        return next((x for x in t if x != "null"), None)
    return t


def is_object_schema(node: dict) -> bool:
    """Mirror the reference is_object test: type:object (or no type but non-empty
    properties) AND not a oneOf/anyOf/allOf combinator AND properties non-empty."""
    if any(k in node for k in ("oneOf", "anyOf", "allOf")):
        return False
    props = node.get("properties")
    t = _type_schema_type(node)
    return (t == "object" or (t is None and props)) and isinstance(props, dict) and len(props) > 0


def perl_attr_name(wire_key: str) -> str:
    """Perl `has` attribute name for a wire key. Fold non-identifier runes to
    ``_`` (rare — wire keys are snake_case); a leading digit gets a ``_`` prefix."""
    s = re.sub(r"[^A-Za-z0-9_]", "_", wire_key)
    if not s:
        s = "field"
    if s[0].isdigit():
        s = "_" + s
    return s


# Moo imports these keyword subs into every `use Moo;` package; a `has '<name>'`
# whose accessor would be named identically OVERWRITES the imported keyword and
# Moo dies ("cannot overwrite a locally defined method with a reader"). For such a
# property we still declare `has '<name>'` (so the wire key + the signature member
# name are preserved — signature_dump reads the has-name), but install the accessor
# under a safe ``get_<name>`` reader so nothing clobbers the Moo keyword. Verified
# collision set (empirically): with/extends/around/before/after/has (meta/blessed
# do NOT collide).
MOO_RESERVED_ATTRS = {"with", "extends", "around", "before", "after", "has"}


def perl_has_decl(attr: str) -> str:
    """The `has '<attr>' => ( ... );` line for a method-less data DTO property,
    read-only, with a safe reader when the name collides with a Moo keyword."""
    if attr in MOO_RESERVED_ATTRS:
        return f"has '{attr}' => ( is => 'ro', reader => 'get_{attr}' );"
    return f"has '{attr}' => ( is => 'ro' );"


TYPES_HEADER = (
    "# Code generated by scripts/generate_rest.py; DO NOT EDIT.\n"
    "#\n"
    "# AUTO-GENERATED from porting-sdk/rest-apis/ (components/schemas) — regenerate with:\n"
    "#   python3 scripts/generate_rest.py\n"
    "#\n"
    "# {desc}\n"
)


def emit_type_class(sub: str, raw_name: str, node: dict, ns_key: str) -> str:
    """Emit one method-less Moo data package for an object schema."""
    pl_name = type_name(raw_name)
    pkg = f"SignalWire::REST::Namespaces::Generated::Types::{sub}::{pl_name}"
    desc = (f"Generated REST wire type {pl_name!r} from the {ns_key!r} spec "
            f"(components/schemas {raw_name!r}).")
    out = TYPES_HEADER.format(desc=desc)
    out += f"package {pkg};\n"
    out += "use strict;\n"
    out += "use warnings;\n"
    out += "use Moo;\n\n"
    out += "# Pure data DTO: one read-only accessor per property carrying the snake\n"
    out += "# wire key; no methods (the reference records this as a method-less type).\n"
    props = node.get("properties") or {}
    used: set[str] = set()
    for wire_key in props:
        attr = perl_attr_name(wire_key)
        while attr in used:
            attr += "_"
        used.add(attr)
        if attr != wire_key:
            out += f"# wire key: {wire_key}\n"
        out += perl_has_decl(attr) + "\n"
    out += "\n1;\n"
    return out


def emit_type_enum(sub: str, enum_name: str, values: list, ns_key: str, raw_name: str) -> str:
    """Emit a method-less Moo package exposing an x-sdk-enum public enum's wire
    values as `use constant` (surfaced as a bare class by the reference)."""
    pkg = f"SignalWire::REST::Namespaces::Generated::Types::{sub}::{enum_name}"
    desc = (f"Generated REST public enum {enum_name!r} (x-sdk-enum on "
            f"components/schemas {raw_name!r}, {ns_key!r} spec).")
    out = TYPES_HEADER.format(desc=desc)
    out += f"package {pkg};\n"
    out += "use strict;\n"
    out += "use warnings;\n"
    out += "use Moo;\n\n"
    out += "# Backed enum: each constant's value is the exact wire string.\n"
    used: set[str] = set()
    for v in values:
        if v == "":
            continue
        cname = re.sub(r"[^A-Za-z0-9]+", "_", str(v)).strip("_").upper()
        if not cname:
            cname = "VALUE"
        if cname[0].isdigit():
            cname = "V_" + cname
        while cname in used:
            cname += "_"
        used.add(cname)
        out += f"use constant {cname} => {perl_str(str(v))};\n"
    out += "\n1;\n"
    return out


def _load_types_schemas(psdk: Path, spec_dir: str) -> dict:
    """Load a spec's components/schemas WITHOUT the full Spec model (swml-webhooks
    has no servers block, so Spec() would fail). Ordered by yaml declaration."""
    doc = yaml.safe_load((psdk / "rest-apis" / spec_dir / "openapi.yaml").read_text())
    return ((doc.get("components") or {}).get("schemas")) or {}


def emit_types(psdk: Path, outs: dict) -> None:
    """Emit every <ns>_types_generated Perl data package / enum into
    ``Types/<Sub>/<TypeName>.pm`` keys of ``outs`` (relative to the Generated dir)."""
    for spec_dir, sub, ns_key in TYPE_NS:
        schemas = _load_types_schemas(psdk, spec_dir)
        for raw_name, node in schemas.items():
            if not isinstance(node, dict):
                continue
            # x-sdk-enum public enum → emit a constants class (surfaced as a class).
            xe = node.get("x-sdk-enum")
            if xe:
                enum_name = type_name(xe)
                fn = f"Types/{sub}/{enum_name}.pm"
                if fn not in outs:
                    outs[fn] = emit_type_enum(
                        sub, enum_name, list(node.get("enum") or []), ns_key, raw_name)
            # Object schema → a data class. (Non-object, non-x-sdk-enum schemas —
            # scalar/array/union aliases and plain inline enums — are NOT surfaced
            # by the reference, so emit nothing for them.)
            if is_object_schema(node):
                pl_name = type_name(raw_name)
                fn = f"Types/{sub}/{pl_name}.pm"
                if fn not in outs:
                    outs[fn] = emit_type_class(sub, raw_name, node, ns_key)


# ---------------------------------------------------------------------------
# Driver.
# ---------------------------------------------------------------------------

def build_outputs(psdk: Path) -> dict[str, str]:
    load_bases(psdk)  # validate x-sdk-bases (fail loud)
    _SIDECAR.clear()
    specs = [load_spec(psdk, ns) for ns in SPEC_DIRS]
    outs: dict[str, str] = {}

    outs["ReadResource.pm"] = emit_read_resource_base()
    outs["FabricResource.pm"] = emit_fabric_resource_base()

    for spec in specs:
        for anchor, markup in spec.resources():
            src = emit_resource(spec, anchor, markup)
            outs[markup["name"] + ".pm"] = src

    placed = resolve_placement(specs)
    by_container: dict[str, list[tuple[str, str]]] = {}
    order: list[str] = []
    for spec, anchor, markup, container in placed:
        if not container:
            continue
        if container not in by_container:
            by_container[container] = []
            order.append(container)
        acc = container_accessor(markup, markup["name"], container)
        by_container[container].append((acc, markup["name"]))
    for container in order:
        if container not in CONTAINERS:
            raise SystemExit(f"container attr {container!r} has no Perl container class (add to CONTAINERS)")
        cls, _ = CONTAINERS[container]
        outs[cls + ".pm"] = emit_container(container, by_container[container])

    outs["ResourceTree.pm"] = emit_resource_tree(placed)

    # Wire types (item A/H): one method-less Moo data package per components/schemas
    # object across all 13 namespaces, under Types/<Sub>/.
    emit_types(psdk, outs)

    # Sidecar (§5): canonical typed-param records the signature enumerator unfolds
    # onto the regex-parsed Perl params (Perl signatures aren't introspectable —
    # PORT_SIGNATURE_OMISSIONS). Keyed "<ClassName>::<method>". Deterministic.
    sidecar: dict[str, list[dict]] = {}
    for (cls, method) in sorted(_SIDECAR.keys()):
        sidecar[f"{cls}::{method}"] = _SIDECAR[(cls, method)]
    outs["rest_signatures.json"] = json.dumps(
        {
            "_comment": "Code generated by scripts/generate_rest.py; DO NOT EDIT. "
                        "Canonical typed-param records for generated REST operation/"
                        "command/set methods; consumed by scripts/enumerate_signatures.py "
                        "to unfold the regex-parsed Perl params onto the Python oracle shape.",
            "methods": sidecar,
        },
        indent=2, sort_keys=False,
    ) + "\n"
    return outs


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="GEN-FRESH: exit non-zero if stale")
    ap.add_argument("--out", default="", help="scratch: emit flat into this dir")
    args = ap.parse_args(argv)

    psdk = resolve_porting_sdk()
    outs = build_outputs(psdk)

    if args.out:
        out_dir = Path(args.out)
    else:
        out_dir = repo_root() / "lib" / "SignalWire" / "REST" / "Namespaces" / "Generated"

    if args.check:
        stale = []
        for fn, src in outs.items():
            p = out_dir / fn
            if not p.is_file() or p.read_text() != src:
                stale.append(str(p))
        expected = set(outs.keys())
        for p in sorted(out_dir.rglob("*.pm")):
            rel = p.relative_to(out_dir).as_posix()
            if rel not in expected:
                stale.append(f"{p} (leftover — not in generator output)")
        for p in sorted(out_dir.rglob("*.json")):
            rel = p.relative_to(out_dir).as_posix()
            if rel not in expected:
                stale.append(f"{p} (leftover — not in generator output)")
        if stale:
            sys.stderr.write("GEN-FRESH FAIL: %d generated REST file(s) stale:\n" % len(stale))
            for s in stale:
                sys.stderr.write("  - %s\n" % s)
            return 1
        print("GEN-FRESH: generated REST files match the canonical specs.")
        return 0

    out_dir.mkdir(parents=True, exist_ok=True)
    for fn, src in outs.items():
        p = out_dir / fn
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(src)
    print(f"generated {len(outs)} REST file(s) into {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
