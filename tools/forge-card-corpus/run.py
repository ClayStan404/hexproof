#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Compile the isolated corpus driver against an existing pinned runtime."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-index", type=Path, default=ROOT / "build/forge-native/local-runtime.json")
    parser.add_argument("--manifest", type=Path, default=Path(__file__).with_name("decks-2026-09-22.json"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cards", default=".*", help="Java full-match regex over frozen card names")
    parser.add_argument("--current-host", action="store_true", help="Compile working host sources in the isolated test directory")
    parser.add_argument("--abilities", action="store_true", help="Also attempt every printed native activated ability")
    parser.add_argument("--patch-source", type=Path, help="Compile these reviewed working patch classes from the pinned source checkout")
    args = parser.parse_args()
    runtime = Path(json.loads(args.runtime_index.read_text())["runtimeRoot"])
    args.output.mkdir(parents=True, exist_ok=False)
    classes = args.output / "classes"
    classes.mkdir(exist_ok=True)
    classpath = os.pathsep.join(map(str, [runtime / "forge-harness.jar", *sorted((runtime / "lib").glob("*.jar"))]))
    sources = [Path(__file__).with_name("NativeCorpus.java")]
    if args.current_host:
        sources.extend(sorted((ROOT / "third_party/forge-runtime/native-host/src/main/java").rglob("*.java")))
    if args.patch_source:
        for path in ("forge-gui/src/main/java/forge/player/HumanCostDecision.java",
                     "forge-gui/src/main/java/forge/gamemodes/match/input/InputSelectCardsForConvokeOrImprovise.java"):
            sources.append(args.patch_source.resolve() / path)
    subprocess.run(["javac", "--release", "21", "-encoding", "UTF-8", "-cp", classpath,
                    "-d", str(classes), *map(str, sources)], check=True)
    command = ["java", "-Xmx2g", "-Djava.awt.headless=true", "-cp", str(classes) + os.pathsep + classpath,
               "org.hexproof.forge.NativeCorpus", str(runtime / "forge-gui"), str(args.manifest.resolve()),
               str((args.output / "native.jsonl").resolve()), args.cards, "abilities" if args.abilities else "entry"]
    (args.output / "run.json").write_text(json.dumps({"runtime": json.loads(args.runtime_index.read_text()),
        "manifestSha256": hashlib.sha256(args.manifest.read_bytes()).hexdigest(),
        "runtimeProvenanceSha256": hashlib.sha256((runtime / "provenance.json").read_bytes()).hexdigest(),
        "command": command, "sources": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources},
        "fixture": "Deterministic synthetic boards; 120 floating mana per seat; actual human native play and stack resolution"}, indent=2) + "\n")
    with (args.output / "native.log").open("w") as log:
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=14400)


if __name__ == "__main__":
    main()
