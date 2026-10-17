#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Select an installed JDK/JRE 21 without changing the system Java default."""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def find_tool(name, pattern, requested=None):
    executable = name + (".exe" if os.name == "nt" else "")
    if requested:
        candidates = [requested]
    else:
        homes = [value for key, value in sorted(os.environ.items())
                 if key.upper().startswith("JAVA_HOME_21_")]
        if home := os.environ.get("JAVA_HOME"):
            homes.append(home)
        candidates = [str(Path(home) / "bin" / executable) for home in homes]
        if current := shutil.which(executable):
            candidates.append(current)
        if sys.platform.startswith("linux"):
            candidates += [str(path) for path in sorted(Path("/usr/lib/jvm").glob(f"*/bin/{name}"))]
    versions = []
    for candidate in dict.fromkeys(candidates):
        try:
            result = subprocess.run([candidate, "-version"], capture_output=True, text=True, check=True)
        except (OSError, subprocess.SubprocessError):
            continue
        version = (result.stdout + result.stderr).strip()
        # JVM option environment variables can add notices before the version line.
        if re.search(pattern, version, re.MULTILINE):
            return str(Path(shutil.which(candidate) or candidate).resolve())
        versions.append(f"{candidate}: {version}")
    found = "; ".join(versions) or f"no usable {name} found"
    if name == "java":
        raise ValueError(f"Forge requires a Java 21 runtime ({found}). "
                         "Install Java 21 and select it with JAVA_HOME or HEXPROOF_FORGE_JAVA.")
    raise ValueError(f"Forge requires JDK 21 to match the reviewed diagnostic symbols ({found}). "
                     "Install JDK 21 and select it with JAVA_HOME or --javac.")


def find_javac(requested=None):
    # --release controls the class version, not compiler-generated method names.
    return find_tool("javac", r"\bjavac 21(?:[.\s]|$)", requested)


def find_java(requested=None):
    return find_tool("java", r'^(?:openjdk|java)(?: version)?\s+"?21(?:[.\s"]|$)', requested)


def build_environment():
    compiler = Path(find_javac())
    environment = dict(os.environ)
    environment["JAVA_HOME"] = str(compiler.parent.parent)
    environment["PATH"] = str(compiler.parent) + os.pathsep + environment.get("PATH", "")
    return environment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--java", action="store_true", help="Select the Java runtime instead of the compiler")
    args = parser.parse_args()
    try:
        print(find_java() if args.java else find_javac())
    except ValueError as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
