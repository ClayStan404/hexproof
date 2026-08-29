#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Validate the generated Go/Qt wire constants against the v1 schema."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from payload_enums import load_payload_enum_schema, verify_payload_enum_fixtures
from payload_go_structs import verify_go_payload_structs
from payload_schema import (
    load_payload_schema,
    verify_payload_fixtures,
    verify_qt_payload_builders,
)
from protocol_codegen import generated_outputs, load_schema, verify_fixtures
from protocol_fixture_index import verify_fixture_index

GO_CONSTANT = re.compile(r'^\s*(?P<name>[A-Z][A-Za-z0-9]*)\s*=\s*"(?P<value>[^"]+)"', re.M)
CPP_CONSTANT = re.compile(
    r'^inline\s+const\s+QString\s+k(?P<name>[A-Z][A-Za-z0-9]*)'
    r'\s*=\s*QStringLiteral\("(?P<value>[^"]+)"\);',
    re.M,
)


def parse_constants(path: Path, pattern: re.Pattern[str]) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    constants: dict[str, str] = {}
    for match in pattern.finditer(text):
        name = match.group("name")
        value = match.group("value")
        if name in constants:
            raise ValueError(f"duplicate generated constant {name} in {path}")
        constants[name] = value
    return constants


def manual_declarations(root: Path, names: set[str]) -> list[str]:
    problems: list[str] = []
    sources = (
        root / "apps/server/internal/protocol/protocol.go",
        root / "apps/client-qt/src/protocol/Message.h",
    )
    for path in sources:
        text = path.read_text(encoding="utf-8")
        for name in sorted(names):
            if path.suffix == ".go":
                pattern = re.compile(rf'^\s*(?:const\s+)?{re.escape(name)}\s*=', re.M)
            else:
                pattern = re.compile(rf'^.*\bk{re.escape(name)}\s*=', re.M)
            if pattern.search(text):
                problems.append(
                    f"{path.relative_to(root)} manually redeclares generated constant {name}"
                )
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    root = args.root.resolve()

    try:
        constants = load_schema(root)
        expected = {item.name: item.value for item in constants}
        message_types = {item.value for item in constants if item.name.startswith("Type")}
        payload_schema = load_payload_schema(root, message_types)
        enum_schema = load_payload_enum_schema(root)
        if payload_schema.protocol != expected["ProtocolVersion"]:
            problems = ["payload schema protocol does not match wire schema"]
        else:
            problems = []
        outputs = generated_outputs(root, constants)
        problems.extend(verify_fixtures(root, constants))
        problems.extend(verify_fixture_index(root))
        problems.extend(verify_payload_fixtures(root, payload_schema))
        problems.extend(verify_payload_enum_fixtures(root, enum_schema))
        problems.extend(verify_go_payload_structs(root, payload_schema))
        problems.extend(verify_qt_payload_builders(root, payload_schema))
        for path, rendered in outputs.items():
            actual = path.read_text(encoding="utf-8")
            if actual != rendered:
                problems.append(
                    f"{path.relative_to(root)} is stale; run python3 tools/protocol_codegen.py"
                )
        go_path = root / "apps/server/internal/protocol/wire_constants_generated.go"
        cpp_path = root / "apps/client-qt/src/protocol/WireConstantsGenerated.h"
        go_constants = parse_constants(go_path, GO_CONSTANT)
        cpp_constants = parse_constants(cpp_path, CPP_CONSTANT)
        if go_constants != expected:
            problems.append("generated Go constants do not match the wire schema")
        if cpp_constants != expected:
            problems.append("generated Qt constants do not match the wire schema")
        problems.extend(manual_declarations(root, set(expected)))
        codegen_source = (root / "tools/protocol_codegen.py").read_text(encoding="utf-8")
        if "from payload_go_structs import verify_go_payload_structs" not in codegen_source:
            problems.append(
                "protocol_codegen.py does not use package-wide Go payload validation"
            )
        message_header = (root / "apps/client-qt/src/protocol/Message.h").read_text(
            encoding="utf-8"
        )
        if '#include "WireConstantsGenerated.h"' not in message_header:
            problems.append("Message.h does not include WireConstantsGenerated.h")
    except (OSError, ValueError) as error:
        print(f"protocol schema check failed: {error}", file=sys.stderr)
        return 2

    if problems:
        print("protocol schema check failed:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    print(
        f"protocol schema ok: {len(expected)} constants, "
        f"{len(payload_schema.messages)} payloads, and "
        f"{enum_schema.constrained_fields} enum fields match fixtures"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
