#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Build the desktop helper with the checksum of its matching bundled adapter."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--overlay-dir", type=Path, default=ROOT / "build/forge-overlay")
    parser.add_argument("--go", default="go")
    parser.add_argument("--ldflags", default="")
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("forge_overlay", ROOT / "third_party/forge-runtime/build-overlay.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    identity, _ = module.identity()
    source = (ROOT / "apps/server/internal/forgehost/identity.go").read_text()
    declared = re.search(r'const RuntimeID = "([^"]+)"', source)
    if declared is None or declared[1] != identity:
        raise ValueError("Host runtime identity is stale; update identity.go from build-overlay.py --identity")
    metadata = json.loads((args.overlay_dir / "forge-overlay.json").read_text())
    jar = args.overlay_dir / "forge-overlay.jar"
    with jar.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if metadata["runtimeId"] != identity or metadata["sha256"] != digest:
        raise ValueError("Packaged overlay does not match the current native sources")
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    flags = (args.ldflags + " -X main.overlaySHA256=" + digest).strip()
    subprocess.run([args.go, "build", "-trimpath", "-ldflags=" + flags, "-o", str(output),
                    "./cmd/hexproof-forge-host"], cwd=ROOT / "apps/server",
                   env=dict(os.environ, CGO_ENABLED="0"), check=True)
    shutil.copyfile(jar, output.parent / "forge-overlay.jar")


if __name__ == "__main__":
    main()
