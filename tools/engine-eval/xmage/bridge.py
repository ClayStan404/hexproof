#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Launch the compiled test-only human bridge, preserving pure JSONL stdout."""

import argparse
import json
import hashlib
import os
from pathlib import Path
import stat
import tempfile
import time


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def assert_catalog_closed(path):
    """Reject H2 locks/observed writers; disclose inaccessible descriptors."""
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Catalog template must be a regular non-symlink file: {path}")
    lock = path.with_name(path.name.removesuffix(".mv.db") + ".lock.db")
    if lock.exists() or lock.is_symlink():
        raise ValueError(f"Catalog template has an H2 lock; close its owner first: {lock}")
    if not Path("/proc/self/fdinfo").is_dir():
        raise OSError("Catalog quiescence verification currently requires Linux /proc")
    identity = path.stat()
    writers = []
    uninspectable = set()
    for process in Path("/proc").iterdir():
        if not process.name.isdecimal():
            continue
        try:
            if process.stat().st_uid != os.getuid():
                continue
            for descriptor in (process / "fd").iterdir():
                try:
                    opened = descriptor.stat()
                    if (opened.st_dev, opened.st_ino) != (identity.st_dev, identity.st_ino):
                        continue
                    info = (process / "fdinfo" / descriptor.name).read_text()
                    flags = next(int(line.split()[1], 8) for line in info.splitlines()
                                 if line.startswith("flags:"))
                    if flags & os.O_ACCMODE != os.O_RDONLY:
                        writers.append(int(process.name))
                except (FileNotFoundError, ProcessLookupError):
                    continue
                except PermissionError:
                    uninspectable.add(int(process.name))
        except (FileNotFoundError, ProcessLookupError):
            continue
        except PermissionError:
            uninspectable.add(int(process.name))
    if writers:
        raise ValueError(f"Catalog template still has writable descriptors in PIDs {sorted(set(writers))}")
    return {"identity": {"device": identity.st_dev, "inode": identity.st_ino,
                         "size": identity.st_size, "mtimeNs": identity.st_mtime_ns,
                         "ctimeNs": identity.st_ctime_ns},
            "descriptorCheck": {"userId": os.getuid(), "uninspectablePids": sorted(uninspectable),
                                "observedWritableTemplatePids": [],
                                "scope": "Inspectable same-UID descriptors only; not a claim of exhaustive process visibility"}}


def prepare_runtime(profile, source_cwd, template=None):
    """Copy only a closed prebuilt catalog into a fresh private working directory."""
    source = template if template is not None else source_cwd / "db/cards.h2.mv.db"
    source = Path(source).absolute()
    started = time.monotonic()
    initial = assert_catalog_closed(source)
    if not stat.S_ISREG(source.stat().st_mode) or source.stat().st_size == 0:
        raise ValueError(f"Catalog template is empty or not regular: {source}")
    # Exclusive creation intentionally rejects reused profiles and symlink paths.
    runtime = profile / "runtime"
    runtime.mkdir()
    database = runtime / "db"
    database.mkdir()
    target = database / "cards.h2.mv.db"
    digest = hashlib.sha256()
    with source.open("rb") as incoming, target.open("xb") as outgoing:
        for chunk in iter(lambda: incoming.read(4 * 1024 * 1024), b""):
            outgoing.write(chunk)
            digest.update(chunk)
    copied_hash = digest.hexdigest()
    target_hash = sha256_file(target)
    source_hash = sha256_file(source)
    final = assert_catalog_closed(source)
    if initial["identity"] != final["identity"] or source_hash != copied_hash or target_hash != copied_hash:
        raise ValueError("Catalog changed while being copied or the private copy differs; use a fresh profile after closing its owner")
    if (source.stat().st_dev, source.stat().st_ino) == (target.stat().st_dev, target.stat().st_ino):
        raise ValueError("Private catalog must not be a hardlink to the source")
    return runtime, {
        "mode": "private copy of closed prebuilt catalog", "source": str(source.resolve()),
        "destination": str(target.resolve()), "sourceSha256": source_hash,
        "destinationSha256": target_hash, "bytes": target.stat().st_size,
        "sourceIdentityBeforeAndAfter": initial["identity"], "elapsedSeconds": time.monotonic() - started,
        "descriptorCheckBefore": initial["descriptorCheck"], "descriptorCheckAfter": final["descriptorCheck"],
        "quiescenceChecks": "H2 lock absent before/after; source stat and SHA256 stable; no observed writable descriptors among inspectable same-UID processes. Uninspectable PIDs are disclosed, not assumed checked.",
        "startupBoundary": "Fresh JVM/private writable database, not an empty-catalog build. Template copy and SHA256 validation are included in launcher startup time.",
    }


def absolute_classpath(command, original_cwd):
    command = list(command)
    index = command.index("-cp") + 1
    entries = []
    for raw in command[index].split(os.pathsep):
        # Surefire often emits a trailing separator. An empty entry meant the
        # original cwd; preserve that read-only classpath location explicitly.
        path = Path(raw) if raw else original_cwd
        path = path if path.is_absolute() else original_cwd / path
        path = path.resolve()
        # Java ignores absent optional directories in Surefire's classpath.
        # Preserve them as absolute paths; required modules were checked by run.py.
        entries.append(str(path))
    command[index] = os.pathsep.join(entries)
    return command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--profile", type=Path,
                        help="Fresh isolated JVM home, runtime cwd and private database; reused runtime directories are rejected")
    parser.add_argument("--database-template", type=Path,
                        help="Closed prebuilt cards.h2.mv.db to copy; default is the compiled checkout's catalog")
    parser.add_argument("--workload", type=Path)
    parser.add_argument("--workload-id")
    args = parser.parse_args()
    commands = json.loads((args.run_dir / "commands.json").read_text())
    run = commands["run"]
    main_index = run.index("org.hexproof.eval.Qualification")
    original_cwd = Path(commands["cwd"]).resolve()
    if args.profile is not None and args.profile.is_symlink():
        parser.error("Profile must not be a symlink")
    profile = (args.profile.resolve() if args.profile else
               Path(tempfile.mkdtemp(prefix="human-profile-", dir=args.run_dir.resolve())))
    profile.mkdir(parents=True, exist_ok=True)
    command = absolute_classpath([arg for arg in run[:main_index] if not arg.startswith("-Duser.home=")], original_cwd)
    command += [f"-Duser.home={profile}", "org.hexproof.eval.HumanBridge"]
    if bool(args.workload) != bool(args.workload_id):
        parser.error("--workload and --workload-id must be supplied together")
    manifest_path = profile / "bridge-command.json"
    if manifest_path.exists() or manifest_path.is_symlink():
        parser.error("Profile already contains bridge evidence; use a fresh profile")
    runtime, database = prepare_runtime(profile, original_cwd, args.database_template)
    manifest = {"runDirectory": str(args.run_dir.resolve()), "command": command,
                "cwd": str(runtime), "originalBuildCwd": str(original_cwd), "database": database,
                "bridgeSha256": sha256_file(Path(__file__)),
                "absentOptionalClasspathEntries": [entry for entry in command[command.index("-cp") + 1].split(os.pathsep)
                                                   if not Path(entry).exists()]}
    if args.workload:
        workload = args.workload.read_bytes()
        snapshot = profile / "workloads.json"
        with snapshot.open("xb") as output:
            output.write(workload)
        command += [str(snapshot), args.workload_id]
        manifest["workloadSha256"] = hashlib.sha256(workload).hexdigest()
    with (profile / "bridge-source.py").open("xb") as output:
        output.write(Path(__file__).read_bytes())
    with manifest_path.open("x") as output:
        output.write(json.dumps(manifest, indent=2) + "\n")
    os.chdir(runtime)
    os.execvp(command[0], command)


if __name__ == "__main__":
    main()
