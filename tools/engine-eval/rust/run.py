#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Run bounded, pinned native engine qualification probes in an isolated clone."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile


PINS = {
    "rust": "143a6b556ac365cea97929ffcebb48eed03ecde8",
    "phase": "87b8355cc1b0771f5152bd33cee8f81a5f0550cb",
}


def bounded(command, cwd, env, log, seconds):
    with log.open("w") as output:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            return process.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            return 124


def main(candidate="rust"):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkout", type=Path, required=True)
    parser.add_argument("--target-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--filter", default="")
    parser.add_argument("--privacy", action="store_true", help="Run the Manabrew external DTO seam probe")
    parser.add_argument("--games", action="store_true", help="Run complete synthetic-deck games through external controller channels")
    parser.add_argument("--online", action="store_true", help="Allow downloads of lockfile-declared dependencies")
    parser.add_argument("--state-dir", type=Path, help="Inspect real saved Morph states through the native Rust DTO seam")
    args = parser.parse_args()
    checkout = args.checkout.resolve()
    pin = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
    if pin != PINS[candidate]:
        parser.error(f"Expected {PINS[candidate]}, got {pin}")
    args.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix=candidate + "-", dir=args.output.resolve()))
    package = "manabrew-engine" if candidate == "rust" else "phase-engine"
    crate = checkout / ("manabrew-rs/crates/manabrew-engine" if candidate == "rust" else "crates/engine")
    if args.privacy:
        if candidate != "rust":
            parser.error("Phase privacy is included in its main qualification")
        package = "manabrew-agent-interface"
        crate = checkout / "manabrew-rs/crates/manabrew-agent-interface"
    source_dir = Path(__file__).resolve().parents[1] / candidate
    if args.privacy and args.games:
        parser.error("Privacy and complete-game probes are separate runs")
    source = source_dir / ("privacy.rs" if args.privacy else "games.rs" if args.games else "qualification.rs")
    fixture_bytes = source.read_bytes()
    test_name = "hexproof_common_qualification_" + hashlib.sha256(fixture_bytes).hexdigest()[:12]
    destination = crate / "tests" / (test_name + ".rs")
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and destination.read_bytes() != fixture_bytes:
        parser.error(f"Refusing to overwrite a different existing fixture: {destination}")
    shutil.copyfile(source, destination)
    shutil.copyfile(source, output / "fixture.rs")
    env = dict(os.environ, CARGO_TARGET_DIR=str(args.target_dir.resolve()), CARGO_BUILD_JOBS="2",
               RUST_MIN_STACK="67108864", HEXPROOF_EVAL_OUTPUT=str(output),
               HEXPROOF_CARD_SCRIPTS=str(checkout / "forge/forge-gui/res/cardsfolder"))
    if args.state_dir:
        env["HEXPROOF_STATE_DIR"] = str(args.state_dir.resolve())
    command = ["cargo", "test", *([] if args.online else ["--offline"]), "--locked", "--manifest-path", str(checkout / "Cargo.toml"),
               "-p", package, "--test", test_name, args.filter, "--", "--nocapture", "--test-threads=1"]
    provenance = {"candidate": candidate, "pin": pin, "command": command,
                  "source_fixture": str(source),
                  "state_directory": str(args.state_dir.resolve()) if args.state_dir else None,
                  "note": "Semantic qualification; elapsed times are not comparative measurements."}
    (output / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    patch = subprocess.check_output(["git", "-C", str(checkout), "diff", "--", "Cargo.toml"], text=True)
    (output / "compatibility.patch").write_text(patch)
    print(output, flush=True)
    code = bounded(command, checkout, env, output / "run.log", 1200)
    log_text = (output / "run.log").read_text()
    for line in log_text.splitlines():
        if line.startswith(("error", "test result:", "thread '", "assertion ", "  left:", " right:")):
            print(line[:500])
    records = []
    for line in log_text.splitlines():
        if "HEXPROOF_OBSERVATION " in line:
            records.append(json.loads(line.split("HEXPROOF_OBSERVATION ", 1)[1]))
    (output / "raw-results.json").write_text(json.dumps(records, indent=2) + "\n")
    print(f"exit={code}; records={len(records)}; output={output}")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
