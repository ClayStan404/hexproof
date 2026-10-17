#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Retain a bounded command's evidence; an exit code is not a rules qualification."""

import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import time

from process_control import (ProcessCancelled, cancellation_signals,
                             start_owned_process, stop_owned_process, wait_owned_process)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--name", required=True)
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--cwd", type=Path, default=Path.cwd())
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or not 1 <= args.timeout <= 7200:
        parser.error("a command and timeout between 1 and 7200 seconds are required")
    args.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="command-", dir=args.output.resolve()))
    record = {"name": args.name, "command": command, "cwd": str(args.cwd.resolve()),
              "timeoutSeconds": args.timeout, "pid": None,
              "qualification": "Not inferred; inspect actual assertions and test framework outcomes"}
    (output / "command.json").write_text(json.dumps(record, indent=2) + "\n")
    print(output, flush=True)
    started = time.monotonic()
    code = 1
    process = None
    for filename in ("capture.py", "process_control.py"):
        (output / filename).write_bytes(Path(__file__).with_name(filename).read_bytes())
    with cancellation_signals() as cancellation, (output / "execution.log").open("wb") as log:
        try:
            cancellation.check()
            process = start_owned_process(command, cwd=args.cwd, stdout=log, stderr=subprocess.STDOUT)
            record["pid"] = process.pid
            (output / "command.json").write_text(json.dumps(record, indent=2) + "\n")
            code = wait_owned_process(process, args.timeout, cancellation)
        except subprocess.TimeoutExpired:
            record["timedOut"] = True
            code = 124
        except ProcessCancelled as error:
            record.update(cancelled=True, signal=error.signum)
            code = 128 + error.signum
        except OSError as error:
            record["launchError"] = f"{type(error).__name__}: {error}"
            log.write((record["launchError"] + "\n").encode())
            code = 127
        finally:
            if process is not None:
                record["cleanup"] = stop_owned_process(process)
    record.update(exitCode=code, elapsedSeconds=time.monotonic() - started)
    (output / "result.json").write_text(json.dumps(record, indent=2) + "\n")
    print(f"exit={code} elapsed={record['elapsedSeconds']:.3f}s", flush=True)
    return code if code >= 0 else 128 - code


if __name__ == "__main__":
    raise SystemExit(main())
