#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Validate core Hexproof payload shapes and generate Qt field constants."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

FIELD_NAME_RE = re.compile(r"^[a-z][A-Za-z0-9]*$")
TYPE_NAME_RE = re.compile(r"^[A-Z][A-Za-z0-9]*$")
GO_STRUCT_RE = re.compile(
    r"^type\s+(?P<name>[A-Z][A-Za-z0-9]*)\s+struct\s*\{\n(?P<body>.*?)^\}",
    re.M | re.S,
)
GO_EMPTY_STRUCT_RE = re.compile(
    r"^type\s+(?P<name>[A-Z][A-Za-z0-9]*)\s+struct\s*\{\s*\}\s*$", re.M
)
GO_FIELD_RE = re.compile(
    r'^\s*(?P<go_name>[A-Z][A-Za-z0-9]*)\s+(?P<go_type>[^`]+?)\s+`json:"(?P<tag>[^\"]+)"`',
    re.M,
)
SUPPORTED_TYPES = {"string", "integer", "number", "boolean", "array", "object"}
SUPPORTED_DIRECTIONS = {"clientToServer", "serverToClient"}


@dataclass(frozen=True)
class FieldSpec:
    name: str
    type: str
    required: bool
    nullable: bool = False
    ref: str | None = None
    items_type: str | None = None
    items_ref: str | None = None
    go_type: str | None = None


@dataclass(frozen=True)
class ObjectSpec:
    name: str
    go_type: str
    fields: tuple[FieldSpec, ...]
    message_type: str | None = None
    direction: str | None = None
    qt_file: str | None = None
    qt_function: str | None = None


@dataclass(frozen=True)
class PayloadSchema:
    protocol: str
    definitions: dict[str, ObjectSpec]
    messages: dict[str, ObjectSpec]

    @property
    def objects(self) -> tuple[ObjectSpec, ...]:
        return tuple(self.definitions.values()) + tuple(self.messages.values())


def _field_from_json(raw: Any, owner: str, known_refs: set[str]) -> FieldSpec:
    if not isinstance(raw, dict):
        raise ValueError(f"{owner}: field must be an object")
    name = raw.get("name")
    kind = raw.get("type")
    required = raw.get("required")
    nullable = raw.get("nullable", False)
    if not isinstance(name, str) or not FIELD_NAME_RE.fullmatch(name):
        raise ValueError(f"{owner}: invalid field name {name!r}")
    if kind not in SUPPORTED_TYPES:
        raise ValueError(f"{owner}.{name}: unsupported type {kind!r}")
    if not isinstance(required, bool):
        raise ValueError(f"{owner}.{name}: required must be boolean")
    if not isinstance(nullable, bool):
        raise ValueError(f"{owner}.{name}: nullable must be boolean")

    ref = raw.get("ref")
    if ref is not None:
        if kind != "object" or not isinstance(ref, str) or ref not in known_refs:
            raise ValueError(f"{owner}.{name}: invalid object ref {ref!r}")

    items_type: str | None = None
    items_ref: str | None = None
    go_type: str | None = None
    items = raw.get("items")
    if kind == "array":
        if not isinstance(items, dict):
            raise ValueError(f"{owner}.{name}: array items must be an object")
        items_type = items.get("type")
        if items_type not in SUPPORTED_TYPES - {"array"}:
            raise ValueError(f"{owner}.{name}: invalid array item type {items_type!r}")
        items_ref = items.get("ref")
        if items_ref is not None:
            if items_type != "object" or not isinstance(items_ref, str) or items_ref not in known_refs:
                raise ValueError(f"{owner}.{name}: invalid array item ref {items_ref!r}")
    elif items is not None:
        raise ValueError(f"{owner}.{name}: non-array field cannot declare items")

    go_type = raw.get("goType")
    if go_type is not None and (not isinstance(go_type, str) or not go_type):
        raise ValueError(f"{owner}.{name}: goType must be a non-empty string")

    return FieldSpec(name, kind, required, nullable, ref, items_type, items_ref, go_type)


def _object_from_json(
    raw: Any,
    owner: str,
    known_refs: set[str],
    *,
    message: bool,
) -> ObjectSpec:
    if not isinstance(raw, dict):
        raise ValueError(f"{owner}: entry must be an object")
    name = raw.get("name") if not message else raw.get("type")
    go_type = raw.get("goType")
    if not isinstance(go_type, str) or not TYPE_NAME_RE.fullmatch(go_type):
        raise ValueError(f"{owner}: invalid goType {go_type!r}")
    direction = raw.get("direction") if message else None
    if message and direction not in SUPPORTED_DIRECTIONS:
        raise ValueError(f"{owner}: invalid direction {direction!r}")
    qt_file: str | None = None
    qt_function: str | None = None
    qt_builder = raw.get("qtBuilder") if message else None
    if qt_builder is not None:
        if not isinstance(qt_builder, dict):
            raise ValueError(f"{owner}: qtBuilder must be an object")
        qt_file = qt_builder.get("file")
        qt_function = qt_builder.get("function")
        if not isinstance(qt_file, str) or not qt_file.endswith(".cpp"):
            raise ValueError(f"{owner}: invalid qtBuilder file")
        if not isinstance(qt_function, str) or "::" not in qt_function:
            raise ValueError(f"{owner}: invalid qtBuilder function")
    fields_raw = raw.get("fields")
    if not isinstance(fields_raw, list):
        raise ValueError(f"{owner}: fields must be a list")
    fields = tuple(_field_from_json(field, owner, known_refs) for field in fields_raw)
    field_names = [field.name for field in fields]
    if len(field_names) != len(set(field_names)):
        raise ValueError(f"{owner}: duplicate field names")
    return ObjectSpec(
        name=go_type if message else str(name),
        go_type=go_type,
        fields=fields,
        message_type=str(name) if message else None,
        direction=direction,
        qt_file=qt_file,
        qt_function=qt_function,
    )


def load_payload_schema(root: Path, message_types: set[str]) -> PayloadSchema:
    schema_dir = root / "protocol/v1"
    paths = [schema_dir / "payload-schema.json"] + sorted(
        path
        for path in schema_dir.glob("payload-*.json")
        if path.name != "payload-schema.json"
    )
    documents: list[tuple[Path, dict[str, Any]]] = []
    protocol: str | None = None
    definitions_raw: list[tuple[Path, Any]] = []
    messages_raw: list[tuple[Path, Any]] = []
    for path in paths:
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("schemaVersion") != 1:
            raise ValueError(f"{path.name}: payload schema version must be 1")
        document_protocol = data.get("protocol")
        if not isinstance(document_protocol, str) or not document_protocol:
            raise ValueError(f"{path.name}: protocol must be a non-empty string")
        if protocol is None:
            protocol = document_protocol
        elif document_protocol != protocol:
            raise ValueError(f"{path.name}: protocol does not match payload-schema.json")
        raw_definitions = data.get("definitions")
        raw_messages = data.get("messages")
        if not isinstance(raw_definitions, list) or not isinstance(raw_messages, list):
            raise ValueError(f"{path.name}: definitions and messages must be lists")
        documents.append((path, data))
        definitions_raw.extend((path, raw) for raw in raw_definitions)
        messages_raw.extend((path, raw) for raw in raw_messages)

    definition_names: list[str] = []
    for index, (path, raw) in enumerate(definitions_raw):
        name = raw.get("name") if isinstance(raw, dict) else None
        if not isinstance(name, str) or not TYPE_NAME_RE.fullmatch(name):
            raise ValueError(f"{path.name} definition #{index}: invalid name {name!r}")
        definition_names.append(name)
    if len(definition_names) != len(set(definition_names)):
        raise ValueError("payload schema fragments have duplicate definition names")
    known_refs = set(definition_names)

    definitions = {
        name: _object_from_json(
            raw, f"{path.name} definition {name}", known_refs, message=False
        )
        for name, (path, raw) in zip(definition_names, definitions_raw, strict=True)
    }

    messages: dict[str, ObjectSpec] = {}
    for index, (path, raw) in enumerate(messages_raw):
        message_type = raw.get("type") if isinstance(raw, dict) else None
        if not isinstance(message_type, str) or message_type not in message_types:
            raise ValueError(
                f"{path.name} message #{index}: unknown message type {message_type!r}"
            )
        if message_type in messages:
            raise ValueError(f"duplicate payload schema for {message_type}")
        messages[message_type] = _object_from_json(
            raw, f"{path.name} message {message_type}", known_refs, message=True
        )

    if protocol is None:
        raise ValueError("payload schema is empty")
    return PayloadSchema(protocol, definitions, messages)


def _json_matches_type(value: Any, kind: str) -> bool:
    if kind == "string":
        return isinstance(value, str)
    if kind == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if kind == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if kind == "boolean":
        return isinstance(value, bool)
    if kind == "array":
        return isinstance(value, list)
    if kind == "object":
        return isinstance(value, dict)
    return False


def _validate_object(
    value: Any,
    spec: ObjectSpec,
    schema: PayloadSchema,
    location: str,
) -> list[str]:
    if not isinstance(value, dict):
        return [f"{location}: expected object"]
    fields = {field.name: field for field in spec.fields}
    problems: list[str] = []
    unknown = sorted(set(value) - set(fields))
    if unknown:
        problems.append(f"{location}: unknown fields {', '.join(unknown)}")
    for field in spec.fields:
        field_location = f"{location}.{field.name}"
        if field.name not in value:
            if field.required:
                problems.append(f"{field_location}: required field is missing")
            continue
        actual = value[field.name]
        if actual is None:
            if not field.nullable:
                problems.append(f"{field_location}: null is not allowed")
            continue
        if not _json_matches_type(actual, field.type):
            problems.append(f"{field_location}: expected {field.type}")
            continue
        if field.ref is not None:
            problems.extend(
                _validate_object(actual, schema.definitions[field.ref], schema, field_location)
            )
        if field.type == "array" and field.items_type is not None:
            for index, item in enumerate(actual):
                item_location = f"{field_location}[{index}]"
                if not _json_matches_type(item, field.items_type):
                    problems.append(f"{item_location}: expected {field.items_type}")
                elif field.items_ref is not None:
                    problems.extend(
                        _validate_object(
                            item,
                            schema.definitions[field.items_ref],
                            schema,
                            item_location,
                        )
                    )
    return problems


def verify_payload_fixtures(root: Path, schema: PayloadSchema) -> list[str]:
    problems: list[str] = []
    covered: set[str] = set()
    for path in sorted((root / "testdata/protocol/v1").glob("*.json")):
        try:
            envelope = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(envelope, dict):
            continue
        message_type = envelope.get("type")
        spec = schema.messages.get(message_type)
        if spec is None:
            continue
        covered.add(message_type)
        payload = envelope.get("payload", {})
        for problem in _validate_object(
            payload, spec, schema, str(path.relative_to(root)) + ".payload"
        ):
            problems.append(problem)
    missing = sorted(set(schema.messages) - covered)
    for message_type in missing:
        problems.append(f"payload schema {message_type}: no shared fixture")
    return problems


def _go_type_for_field(field: FieldSpec) -> tuple[str, bool]:
    if field.go_type is not None:
        base = field.go_type
    elif field.type == "string":
        base = "string"
    elif field.type == "integer":
        base = "int"
    elif field.type == "number":
        base = "float64"
    elif field.type == "boolean":
        base = "bool"
    elif field.type == "object":
        base = field.ref or "object"
    elif field.type == "array":
        if field.items_type == "string":
            base = "[]string"
        elif field.items_type == "object" and field.items_ref:
            base = f"[]{field.items_ref}"
        else:
            base = "[]object"
    else:
        base = field.type
    if field.nullable and field.type != "array":
        base = "*" + base
    return base, not field.required


def parse_go_structs(path: Path) -> dict[str, dict[str, tuple[str, bool]]]:
    text = path.read_text(encoding="utf-8")
    structs: dict[str, dict[str, tuple[str, bool]]] = {
        match.group("name"): {} for match in GO_EMPTY_STRUCT_RE.finditer(text)
    }
    for match in GO_STRUCT_RE.finditer(text):
        if match.group("name") in structs:
            continue
        fields: dict[str, tuple[str, bool]] = {}
        for field_match in GO_FIELD_RE.finditer(match.group("body")):
            tag_parts = field_match.group("tag").split(",")
            json_name = tag_parts[0]
            if json_name == "-":
                continue
            fields[json_name] = (
                " ".join(field_match.group("go_type").split()),
                "omitempty" in tag_parts[1:],
            )
        structs[match.group("name")] = fields
    return structs


def verify_go_payload_structs(root: Path, schema: PayloadSchema) -> list[str]:
    structs = parse_go_structs(root / "apps/server/internal/protocol/protocol.go")
    problems: list[str] = []
    for spec in schema.objects:
        actual = structs.get(spec.go_type)
        if actual is None:
            problems.append(f"Go payload struct {spec.go_type} is missing")
            continue
        expected_names = {field.name for field in spec.fields}
        actual_names = set(actual)
        if actual_names != expected_names:
            missing = sorted(expected_names - actual_names)
            extra = sorted(actual_names - expected_names)
            if missing:
                problems.append(f"Go struct {spec.go_type}: missing JSON fields {', '.join(missing)}")
            if extra:
                problems.append(f"Go struct {spec.go_type}: extra JSON fields {', '.join(extra)}")
        for field in spec.fields:
            if field.name not in actual:
                continue
            actual_type, omitempty = actual[field.name]
            expected_type, expected_omitempty = _go_type_for_field(field)
            if actual_type != expected_type:
                problems.append(
                    f"Go struct {spec.go_type}.{field.name}: type {actual_type}, want {expected_type}"
                )
            if omitempty != expected_omitempty:
                wording = "optional" if expected_omitempty else "required"
                problems.append(
                    f"Go struct {spec.go_type}.{field.name}: JSON tag must be {wording}"
                )
    return problems



QT_STRING_FIELD_RE = re.compile(
    r'(?:\{\s*|insert\()u"(?P<name>[a-z][A-Za-z0-9]*)"_s\s*,'
)


def _qt_function_body(text: str, function: str) -> str | None:
    marker = f"{function}("
    start = text.find(marker)
    if start < 0:
        return None
    opening = text.find("{", start)
    if opening < 0:
        return None
    depth = 0
    for index in range(opening, len(text)):
        character = text[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return text[opening + 1 : index]
    return None


def verify_qt_payload_builders(root: Path, schema: PayloadSchema) -> list[str]:
    problems: list[str] = []
    source_cache: dict[str, str] = {}
    for message_type, spec in schema.messages.items():
        if spec.qt_file is None or spec.qt_function is None:
            continue
        try:
            text = source_cache.setdefault(
                spec.qt_file, (root / spec.qt_file).read_text(encoding="utf-8")
            )
        except OSError as error:
            problems.append(f"Qt builder {message_type}: {error}")
            continue
        body = _qt_function_body(text, spec.qt_function)
        if body is None:
            problems.append(
                f"Qt builder {message_type}: function {spec.qt_function} is missing"
            )
            continue
        actual_fields = set(QT_STRING_FIELD_RE.findall(body))
        expected_fields = {field.name for field in spec.fields}
        if actual_fields != expected_fields:
            missing = sorted(expected_fields - actual_fields)
            extra = sorted(actual_fields - expected_fields)
            if missing:
                problems.append(
                    f"Qt builder {message_type}: missing fields {', '.join(missing)}"
                )
            if extra:
                problems.append(
                    f"Qt builder {message_type}: unknown fields {', '.join(extra)}"
                )
    return problems
