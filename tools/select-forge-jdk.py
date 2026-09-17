#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Select and verify the hosted runner's preinstalled JDK 21 for adapter builds."""

import os
from pathlib import Path
import re
import subprocess


def main():
    candidates = [value for key, value in sorted(os.environ.items())
                  if key.upper().startswith("JAVA_HOME_21_")]
    if current := os.environ.get("JAVA_HOME"):
        candidates.append(current)
    for candidate in dict.fromkeys(candidates):
        root = Path(candidate)
        suffix = ".exe" if os.name == "nt" else ""
        compiler = root / ("bin/javac" + suffix)
        runtime = root / ("bin/java" + suffix)
        if not compiler.is_file() or not runtime.is_file():
            continue
        version = subprocess.run([str(compiler), "-version"], capture_output=True, text=True, check=True)
        if not re.search(r"javac 21[.\s]", version.stdout + version.stderr):
            continue
        with Path(os.environ["GITHUB_ENV"]).open("a") as stream:
            stream.write("JAVA_HOME=" + str(root) + "\n")
        with Path(os.environ["GITHUB_PATH"]).open("a") as stream:
            stream.write(str(root / "bin") + "\n")
        subprocess.run([str(runtime), "-version"], check=True)
        return
    raise RuntimeError("This runner must provide JDK 21 before building the bundled Forge adapter")


if __name__ == "__main__":
    main()
