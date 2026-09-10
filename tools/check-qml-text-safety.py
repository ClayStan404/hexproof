#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Check direct QML text/menu properties without imposing property order.

This structural check complements Qt's parser and runtime tests; it is not a
general QML linter. Comments, strings and JavaScript regex literals are skipped.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEXEME = re.compile(
    r"(?P<space>\s+)|(?P<comment>//[^\n]*|/\*[\s\S]*?\*/)|"
    r'''(?P<string>"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*'|`(?:\\[\s\S]|[^`\\])*`)|'''
    r"(?P<word>[A-Za-z_$][\w$]*)|(?P<symbol>.)",
    re.DOTALL,
)
REGEX = re.compile(r"/(?:\\[^\n]|\[(?:\\[^\n]|[^\]\\\n])*\]|[^/\\\[\n])+/[a-z]*")


def tokenize(source: str) -> list[tuple[str, int]]:
    result: list[tuple[str, int]] = []
    position, line = 0, 1
    while position < len(source):
        match = LEXEME.match(source, position)
        assert match is not None
        value = match.group()
        kind = match.lastgroup
        if value == "/" and (not result or result[-1][0] in (
            "=", ":", "(", "[", ",", "!", "?", "return", "&", "|",
        )):
            regex = REGEX.match(source, position)
            if regex:
                match, value, kind = regex, regex.group(), "string"
        if kind == "symbol" and (value in "\"'`" or source.startswith("/*", position)):
            raise ValueError(f"line {line}: unterminated string or comment")
        if kind not in ("space", "comment"):
            result.append(("<literal>" if kind == "string" else value, line))
        line += value.count("\n")
        position = match.end()
    return result


def check_source(source: str) -> list[str]:
    tokens = tokenize(source)
    values = [value for value, _ in tokens]
    # Every brace gets a frame, so a child's binding cannot satisfy its parent.
    stack: list[dict] = []
    problems: list[str] = []
    for index, (value, line) in enumerate(tokens):
        if value == "{":
            stack.append({"type": values[index - 1] if index else "",
                          "line": line, "formats": []})
        elif value == "}":
            if not stack:
                raise ValueError(f"line {line}: unmatched closing brace")
            frame = stack.pop()
            if frame["type"] == "Text" and frame["formats"] != [True]:
                problems.append(f"{frame['line']}: Text must declare textFormat: Text.PlainText")
        elif stack and values[index:index + 2] == [value, ":"]:
            frame = stack[-1]
            if value == "textFormat" and frame["type"] == "Text":
                end = index + 5
                constant = values[index + 2:end] == ["Text", ".", "PlainText"]
                # Reject dynamic expressions beginning with Text.PlainText.
                boundary = end < len(tokens) and (
                    values[end] in (";", "}") or (
                        tokens[end][1] > tokens[end - 1][1]
                        and re.fullmatch(r"[A-Za-z_$][\w$]*", values[end]) is not None
                        and values[end] not in ("in", "instanceof")
                    )
                )
                frame["formats"].append(constant and boundary)
            if value == "visible" and frame["type"] in ("MenuItem", "MenuSeparator"):
                problems.append(f"{line}: conditional menu rows must use Conditional{frame['type']}")
    if stack:
        raise ValueError(f"line {stack[-1]['line']}: unclosed brace")
    return problems


def main() -> int:
    qml_root = ROOT / "apps/client-qt/qml"
    paths = sorted(qml_root.rglob("*.qml"))
    if not paths:
        print(f"No QML sources found in {qml_root}", file=sys.stderr)
        return 1
    problems = []
    for path in paths:
        try:
            errors = check_source(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, ValueError) as error:
            errors = [str(error)]
        problems.extend(f"{path.relative_to(ROOT)}:{error}" for error in errors)
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print("QML text safety ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
