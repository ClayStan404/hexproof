#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Validate payload contracts against all Go structs in the protocol package."""

from __future__ import annotations

from pathlib import Path

from payload_schema import PayloadSchema, _go_type_for_field, parse_go_structs


def parse_go_package_structs(
    directory: Path,
) -> dict[str, dict[str, tuple[str, bool]]]:
    structs: dict[str, dict[str, tuple[str, bool]]] = {}
    owners: dict[str, Path] = {}
    for path in sorted(directory.glob("*.go")):
        if path.name.endswith("_test.go"):
            continue
        for name, fields in parse_go_structs(path).items():
            previous = owners.get(name)
            if previous is not None:
                raise ValueError(
                    f"duplicate Go struct {name} in {previous.name} and {path.name}"
                )
            structs[name] = fields
            owners[name] = path
    return structs


def verify_go_payload_structs(root: Path, schema: PayloadSchema) -> list[str]:
    structs = parse_go_package_structs(root / "apps/server/internal/protocol")
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
                problems.append(
                    f"Go struct {spec.go_type}: missing JSON fields {', '.join(missing)}"
                )
            if extra:
                problems.append(
                    f"Go struct {spec.go_type}: extra JSON fields {', '.join(extra)}"
                )
        for field in spec.fields:
            if field.name not in actual:
                continue
            actual_type, omitempty = actual[field.name]
            expected_type, expected_omitempty = _go_type_for_field(field)
            if actual_type != expected_type:
                problems.append(
                    f"Go struct {spec.go_type}.{field.name}: type {actual_type}, "
                    f"want {expected_type}"
                )
            if omitempty != expected_omitempty:
                wording = "optional" if expected_omitempty else "required"
                problems.append(
                    f"Go struct {spec.go_type}.{field.name}: JSON tag must be {wording}"
                )
    return problems
