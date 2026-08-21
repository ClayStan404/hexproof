#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Validate payload enum declarations and fixture values against wire constants."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class EnumField:
    values: tuple[str, ...]
    ref: str | None = None
    items_ref: str | None = None


@dataclass(frozen=True)
class EnumSchema:
    definitions: dict[str, dict[str, EnumField]]
    messages: dict[str, dict[str, EnumField]]
    constrained_fields: int


def _wire_constants(root: Path) -> dict[str, str]:
    path = root / "protocol/v1/wire-schema.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    raw_constants = data.get("constants")
    if not isinstance(raw_constants, list):
        raise ValueError("wire-schema.json: constants must be a list")
    constants: dict[str, str] = {}
    for index, raw in enumerate(raw_constants):
        if not isinstance(raw, dict):
            raise ValueError(f"wire-schema.json constant #{index}: must be an object")
        name = raw.get("name")
        value = raw.get("value")
        if not isinstance(name, str) or not name:
            raise ValueError(f"wire-schema.json constant #{index}: invalid name {name!r}")
        if not isinstance(value, str):
            raise ValueError(f"wire-schema.json constant {name}: value must be a string")
        if name in constants:
            raise ValueError(f"wire-schema.json: duplicate constant {name}")
        constants[name] = value
    return constants


def _field_specs(
    fields: Any,
    owner: str,
    constants: dict[str, str],
) -> dict[str, EnumField]:
    if not isinstance(fields, list):
        raise ValueError(f"{owner}: fields must be a list")
    result: dict[str, EnumField] = {}
    for index, raw in enumerate(fields):
        if not isinstance(raw, dict):
            raise ValueError(f"{owner} field #{index}: must be an object")
        name = raw.get("name")
        kind = raw.get("type")
        if not isinstance(name, str) or not name:
            raise ValueError(f"{owner} field #{index}: invalid name {name!r}")
        enum_names = raw.get("enum")
        enum_values: tuple[str, ...] = ()
        if enum_names is not None:
            if kind != "string":
                raise ValueError(f"{owner}.{name}: enum is supported only for string fields")
            if not isinstance(enum_names, list) or not enum_names:
                raise ValueError(f"{owner}.{name}: enum must be a non-empty list")
            if any(not isinstance(item, str) for item in enum_names):
                raise ValueError(f"{owner}.{name}: enum entries must be constant names")
            if len(enum_names) != len(set(enum_names)):
                raise ValueError(f"{owner}.{name}: duplicate enum constant names")
            unknown = [item for item in enum_names if item not in constants]
            if unknown:
                raise ValueError(
                    f"{owner}.{name}: unknown wire constants {', '.join(unknown)}"
                )
            enum_values = tuple(constants[item] for item in enum_names)
            if len(enum_values) != len(set(enum_values)):
                raise ValueError(
                    f"{owner}.{name}: enum constants resolve to duplicate values"
                )
        ref = raw.get("ref") if kind == "object" else None
        items = raw.get("items")
        items_ref = items.get("ref") if isinstance(items, dict) else None
        result[name] = EnumField(enum_values, ref, items_ref)
    return result


def load_payload_enum_schema(root: Path) -> EnumSchema:
    constants = _wire_constants(root)
    schema_dir = root / "protocol/v1"
    paths = [schema_dir / "payload-schema.json"] + sorted(
        path
        for path in schema_dir.glob("payload-*.json")
        if path.name != "payload-schema.json"
    )
    definitions: dict[str, dict[str, EnumField]] = {}
    messages: dict[str, dict[str, EnumField]] = {}
    constrained_fields = 0
    for path in paths:
        data = json.loads(path.read_text(encoding="utf-8"))
        raw_definitions = data.get("definitions")
        raw_messages = data.get("messages")
        if not isinstance(raw_definitions, list) or not isinstance(raw_messages, list):
            raise ValueError(f"{path.name}: definitions and messages must be lists")
        for raw in raw_definitions:
            if not isinstance(raw, dict) or not isinstance(raw.get("name"), str):
                raise ValueError(f"{path.name}: invalid definition")
            name = raw["name"]
            if name in definitions:
                raise ValueError(f"payload schema fragments have duplicate definition {name}")
            specs = _field_specs(raw.get("fields"), f"definition {name}", constants)
            definitions[name] = specs
            constrained_fields += sum(bool(field.values) for field in specs.values())
        for raw in raw_messages:
            if not isinstance(raw, dict) or not isinstance(raw.get("type"), str):
                raise ValueError(f"{path.name}: invalid message")
            message_type = raw["type"]
            if message_type in messages:
                raise ValueError(f"duplicate payload schema for {message_type}")
            specs = _field_specs(
                raw.get("fields"), f"message {message_type}", constants
            )
            messages[message_type] = specs
            constrained_fields += sum(bool(field.values) for field in specs.values())
    return EnumSchema(definitions, messages, constrained_fields)


def _validate_object(
    value: Any,
    fields: dict[str, EnumField],
    schema: EnumSchema,
    location: str,
) -> list[str]:
    if not isinstance(value, dict):
        return []
    problems: list[str] = []
    for name, field in fields.items():
        if name not in value or value[name] is None:
            continue
        actual = value[name]
        field_location = f"{location}.{name}"
        if field.values and actual not in field.values:
            allowed = ", ".join(repr(item) for item in field.values)
            problems.append(
                f"{field_location}: value {actual!r} is not one of {allowed}"
            )
            continue
        if field.ref and isinstance(actual, dict):
            nested = schema.definitions.get(field.ref)
            if nested is not None:
                problems.extend(_validate_object(actual, nested, schema, field_location))
        if field.items_ref and isinstance(actual, list):
            nested = schema.definitions.get(field.items_ref)
            if nested is not None:
                for index, item in enumerate(actual):
                    problems.extend(
                        _validate_object(
                            item, nested, schema, f"{field_location}[{index}]"
                        )
                    )
    return problems


def verify_payload_enum_fixtures(root: Path, schema: EnumSchema) -> list[str]:
    problems: list[str] = []
    for path in sorted((root / "testdata/protocol/v1").glob("*.json")):
        try:
            envelope = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(envelope, dict):
            continue
        message_type = envelope.get("type")
        fields = schema.messages.get(message_type)
        if fields is None:
            continue
        problems.extend(
            _validate_object(
                envelope.get("payload", {}),
                fields,
                schema,
                str(path.relative_to(root)) + ".payload",
            )
        )
    return problems
