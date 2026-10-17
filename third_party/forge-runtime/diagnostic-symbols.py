#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Generate deterministic diagnostic code/catalog symbols from the actual pinned build."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile


class ClassReader:
    def __init__(self, data):
        self.data, self.offset = data, 0

    def take(self, count):
        result = self.data[self.offset:self.offset + count]
        if len(result) != count:
            raise ValueError("Truncated Java class")
        self.offset += count
        return result

    def number(self, count):
        return int.from_bytes(self.take(count), "big")

    def attributes(self):
        for _ in range(self.number(2)):
            self.take(2)
            self.take(self.number(4))

    def read(self):
        if self.take(4) != b"\xca\xfe\xba\xbe":
            raise ValueError("Invalid Java class")
        self.take(4)
        pool, index, count = {}, 1, self.number(2)
        while index < count:
            tag = self.number(1)
            if tag == 1:
                pool[index] = self.take(self.number(2)).decode("utf-8", errors="replace")
            elif tag in (7, 8, 16, 19, 20):
                pool[index] = self.number(2)
            elif tag in (3, 4, 9, 10, 11, 12, 17, 18):
                self.take(4)
            elif tag in (5, 6):
                self.take(8)
                index += 1
            elif tag == 15:
                self.take(3)
            else:
                raise ValueError(f"Unknown class constant tag {tag}")
            index += 1
        self.take(2)
        name = pool[pool[self.number(2)]].replace("/", ".")
        self.take(2)
        self.take(2 * self.number(2))
        enum_fields = []
        for _ in range(self.number(2)):
            flags, field = self.number(2), pool[self.number(2)]
            self.take(2)
            if flags & 0x4000:
                enum_fields.append(field)
            self.attributes()
        methods = set()
        for _ in range(self.number(2)):
            self.take(2)
            methods.add(pool[self.number(2)])
            self.take(2)
            self.attributes()
        return name, sorted(methods), enum_fields


def generate(classes, jars, cards, aliases, runtime_id):
    symbols, apis = {}, []

    def add(data):
        nonlocal apis
        name, methods, enum_fields = ClassReader(data).read()
        if name.startswith(("forge.", "org.hexproof.forge.")):
            symbols[name] = methods
        if name == "forge.game.ability.ApiType":
            apis = enum_fields

    for jar in sorted(jars):
        with zipfile.ZipFile(jar) as archive:
            for name in sorted(archive.namelist()):
                if name.startswith(("forge/", "org/hexproof/forge/")) and name.endswith(".class"):
                    add(archive.read(name))
    for path in sorted(classes.rglob("*.class")):
        add(path.read_bytes())
    names = set()
    for path in sorted(cards.rglob("*.txt")):
        for line in path.read_text(encoding="utf-8-sig").splitlines():
            if line.startswith("Name:"):
                names.add(line[5:].strip())
    for line in aliases.read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#"):
            names.update(line.split("\t", 1)[0].split(" // "))
    if not symbols or not apis or not names:
        raise ValueError("Diagnostic symbols require compiled Forge APIs and pinned card resources")
    result = {"schemaVersion": 1, "runtimeId": runtime_id, "classes": symbols,
              "apis": sorted(apis), "cardNames": sorted(names)}
    return (json.dumps(result, sort_keys=True, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--classes", type=Path, required=True)
    parser.add_argument("--jar", type=Path, action="append", default=[])
    parser.add_argument("--cards", type=Path, required=True)
    parser.add_argument("--aliases", type=Path, required=True)
    parser.add_argument("--runtime-id", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    data = generate(args.classes, args.jar, args.cards, args.aliases, args.runtime_id)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    print(hashlib.sha256(data).hexdigest())


if __name__ == "__main__":
    main()
