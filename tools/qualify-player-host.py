#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Qualify the pinned desktop runtime and relay on the current OS, locally."""
import argparse
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="New evidence directory")
    parser.add_argument("--runtime-dir", required=True, type=Path, help="Private optional-download cache")
    parser.add_argument("--overlay-dir", type=Path, default=ROOT / "build/forge-overlay")
    parser.add_argument("--checkpoint-import", type=Path,
                        help="Synthetic checkpoint exported by qualification on another OS")
    args = parser.parse_args()
    output, runtime = args.output.resolve(), args.runtime_dir.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {"platform": platform.platform(), "architecture": platform.machine(), "status": "failed"}
    binary = output / ("hexproof-forge-host.exe" if os.name == "nt" else "hexproof-forge-host")
    env = dict(os.environ, CGO_ENABLED="0")
    try:
        subprocess.run([sys.executable, str(ROOT / "third_party/forge-runtime/build-overlay.py"),
                        "--output", str(args.overlay_dir.resolve())], check=True, timeout=1800)
        subprocess.run([sys.executable, str(ROOT / "tools/build-forge-helper.py"),
                        "--output", str(binary), "--overlay-dir", str(args.overlay_dir.resolve())],
                       cwd=ROOT, env=env, check=True, timeout=180)
        started = time.monotonic()
        with (output / "prepare.log").open("w") as log:
            subprocess.run([str(binary), "--runtime-dir", str(runtime), "--prepare"],
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=1800)
        report["prepareSeconds"] = round(time.monotonic() - started, 3)
        # This is the helper's atomically published installation generation.
        pointers = sorted(runtime.glob("*.current"), key=lambda p: p.stat().st_mtime)
        if not pointers:
            raise RuntimeError("No verified runtime generation")
        installation = runtime / pointers[-1].read_text()
        java = installation / "jdk-21.0.12.1+1-jre"
        if sys.platform == "darwin":
            java /= "Contents/Home"
        java /= "bin/java.exe" if os.name == "nt" else "bin/java"
        env.update(HEXPROOF_REAL_FORGE_ROOT=str(installation / "hexproof-forge-runtime"),
                   HEXPROOF_FORGE_JAVA=str(java), HEXPROOF_TEST_FORGE_OVERLAY=str(binary.parent / "forge-overlay.jar"))
        with (output / "matches.log").open("w") as log:
            subprocess.run(["go", "test", "-count=1", "-tags", "engineintegration", "./internal/server",
                            "-run", "^TestLivePlayer(Host(edForgeMatches|Migration)|PeerDecisionsAndFallback)$", "-v", "-timeout", "8m"],
                           cwd=ROOT / "apps/server", env=env, stdout=log,
                           stderr=subprocess.STDOUT, check=True, timeout=540)
        with (output / "lifecycle.log").open("w") as log:
            subprocess.run(["go", "test", "-count=1", "-race", "-tags", "engineintegration", "./internal/forgehost",
                            "-run", "^TestLive(PlayerHostReconnectCrashAndRevoke|CheckpointReplay|CheckpointImport)$", "-v", "-timeout", "3m"],
                           cwd=ROOT / "apps/server", env=dict(env, CGO_ENABLED="1",
                               HEXPROOF_CHECKPOINT_EXPORT=str(output / "synthetic-checkpoint.json"),
                               HEXPROOF_CHECKPOINT_IMPORT=str(args.checkpoint_import.resolve()) if args.checkpoint_import else ""), stdout=log,
                           stderr=subprocess.STDOUT, check=True, timeout=240)
        with (output / "native-prompts.log").open("w") as log:
            subprocess.run(["go", "test", "-count=1", "-race", "-tags", "engineintegration", "./internal/rulesengine/forge",
                            "-run", "^TestLiveNative(ProtocolUTF8|GroupedCardTargets)$", "-v", "-timeout", "2m"],
                           cwd=ROOT / "apps/server", env=dict(env, CGO_ENABLED="1"), stdout=log,
                           stderr=subprocess.STDOUT, check=True, timeout=150)
        with (output / "peer-transport.log").open("w") as log:
            subprocess.run(["go", "test", "-count=1", "-race", "./internal/peerlink", "-timeout", "90s"],
                           cwd=ROOT / "apps/server", env=dict(env, CGO_ENABLED="1"), stdout=log,
                           stderr=subprocess.STDOUT, check=True, timeout=120)
        report["status"] = "passed"
    except (OSError, subprocess.SubprocessError, RuntimeError) as error:
        report["error"] = str(error)
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
