#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Run the study's focused Qt Quick checks, failing on QML warnings."""

import os
from pathlib import Path
import shutil
import subprocess


def main() -> int:
    source = Path(__file__).resolve().parent
    runner = shutil.which("qmltestrunner") or shutil.which("qmltestrunner6")
    if runner is None:
        qml = shutil.which("qml6") or shutil.which("qml")
        if qml:
            candidate = Path(qml).resolve().parent / "qmltestrunner"
            if candidate.is_file():
                runner = str(candidate)
    if runner is None:
        raise SystemExit("Qt's qmltestrunner is required.")
    environment = os.environ.copy()
    environment["QT_QPA_PLATFORM"] = "offscreen"
    environment["QT_FORCE_STDERR_LOGGING"] = "1"
    result = subprocess.run([runner, "-input", str(source / "tests"), "-o", "-,txt"],
                            env=environment, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=90)
    print(result.stdout, end="")
    if result.returncode:
        return result.returncode
    markers = ("QWARN", "ReferenceError:", "TypeError:", "Binding loop", "failed to load component")
    if any(marker in result.stdout for marker in markers):
        print("Verification failed: QML diagnostics were emitted.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
