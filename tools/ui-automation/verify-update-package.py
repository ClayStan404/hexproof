#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Verify a UI-downloaded Linux release without installing or modifying its source profile.

The default prepares an extracted release and checks its version; it never claims
GUI success. --launch additionally starts the production binary in a network
namespace and an independent profile, captures its PID-owned X11 window, requests
WM_DELETE_WINDOW, and checks persistent card data after exit.
"""

import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import signal
import sqlite3
import struct
import subprocess
import sys
import tarfile
import time
import zlib

ROOT = Path(__file__).resolve().parents[2]
APP_DATA = Path("data/Hexproof/Hexproof")
PROFILE_FILES = ("cards.sqlite", "decks.json", "card-cache.json", "catalog.json",
                 "custom-art.json", "settings.json")
PROFILE_DIRS = ("images", "custom-art")
MAX_MEMBERS = 5000
MAX_BYTES = 1024 * 1024 * 1024


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_json(path):
    return json.loads(path.read_text())


def regular(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Expected a regular file: {path}")
    return path


def load_download(source_run, seat):
    source_run = source_run.resolve(strict=True)
    metadata = read_json(regular(source_run / "environment.json"))
    report_path = regular(source_run / "report.json")
    report = read_json(report_path)
    if report.get("status") != "passed" or metadata.get("evidence") != "native-qt-input":
        raise ValueError("The source updater run did not pass native verification")
    seats = [entry for entry in report.get("seats", []) if entry.get("seat") == seat
             and entry.get("scenarioResult", {}).get("scenario") == "application-update"]
    if len(seats) != 1 or seats[0].get("status") != "passed":
        raise ValueError("Missing unique bound updater download evidence for the requested seat")
    entry = seats[0]
    result = entry.get("scenarioResult", {})
    if (result.get("status") != "passed" or result.get("downloadReady") is not True
            or result.get("sawDownload") is not True or result.get("updaterError")):
        raise ValueError("The source scenario did not download and verify a release package")
    version = result.get("targetVersion", "")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?", version):
        raise ValueError("Invalid release version")
    archive = Path(result.get("downloadPath", ""))
    regular(archive)
    archive = archive.resolve(strict=True)
    if not archive.is_relative_to(source_run / f"seat-{seat}/downloads"):
        raise ValueError("Downloaded archive is outside the selected native run's downloads")
    machine = {"amd64": "x86_64", "arm64": "aarch64"}.get(platform.machine(), platform.machine())
    package_root = f"Hexproof-{version}-linux-{machine}"
    if archive.name != package_root + ".tar.gz":
        raise ValueError("The archive does not match this host's Linux architecture and target version")
    stage = entry.get("stage")
    if type(stage) is not int or stage < 1:
        raise ValueError("Missing download stage binding")
    artifacts = source_run / f"seat-{seat}" / ("artifacts" if stage == 1 else f"stage-{stage}-artifacts")
    evidence_path = regular(artifacts / "download-evidence.json")
    evidence = read_json(evidence_path)
    binding = entry.get("verifiedDownload", {})
    archive_hash = digest(archive)
    if (binding.get("artifact") != evidence_path.name or binding.get("sha256") != digest(evidence_path)
            or evidence.get("schema") != "hexproof.verified-download.v1"
            or evidence.get("producer") != "native-runner" or not report.get("runId")
            or evidence.get("runId") != report.get("runId") or metadata.get("runId") != report.get("runId")
            or evidence.get("seat") != seat or evidence.get("stage") != stage
            or evidence.get("scenario") != "application-update"
            or evidence.get("sourceVersion") != result.get("sourceVersion")
            or evidence.get("targetVersion") != version
            or evidence.get("path") != str(archive)
            or type(evidence.get("bytes")) is not int or evidence["bytes"] != archive.stat().st_size
            or evidence.get("sha256") != archive_hash
            or evidence.get("resultSha256") != digest(regular(artifacts / "result.json"))
            or read_json(artifacts / "result.json") != result):
        raise ValueError("Verified download binding does not match the source result or current archive")
    return archive, package_root, version, {
        "run": str(source_run), "reportSha256": digest(report_path),
        "environmentSha256": digest(source_run / "environment.json"),
        "sourceVersion": result.get("sourceVersion"), "targetVersion": version,
        "archive": str(archive), "archiveSha256": archive_hash,
        "downloadEvidenceSha256": digest(evidence_path), "downloadStage": stage,
    }


def safe_extract(archive, destination, package_root):
    """Validate the complete archive before creating any package member."""
    if destination.exists():
        raise ValueError("Extraction requires a new destination")
    with tarfile.open(archive, "r:gz") as bundle:
        members = {}
        total = 0
        for member in bundle:
            name = member.name.rstrip("/")
            parts = name.split("/")
            if (not name or name.startswith("/") or "\\" in name or "\0" in name
                    or any(part in ("", ".", "..") for part in parts)
                    or parts[0] != package_root or name in members):
                raise ValueError(f"Unsafe or duplicate archive path: {member.name}")
            if not (member.isdir() or member.isfile() or member.issym()):
                raise ValueError(f"Unsupported archive member: {name}")
            total += member.size
            if total > MAX_BYTES or len(members) >= MAX_MEMBERS or member.size < 0:
                raise ValueError("Release archive exceeds extraction limits")
            members[name] = member
        for name, member in members.items():
            for parent in PurePosixPath(name).parents:
                ancestor = members.get(str(parent))
                if ancestor is not None and not ancestor.isdir():
                    raise ValueError(f"Archive member traverses a non-directory: {name}")
            if member.issym():
                target = member.linkname
                if (not target or target.startswith("/") or "\\" in target
                        or any(part in ("", ".", "..") for part in target.split("/"))):
                    raise ValueError(f"Unsafe archive symlink: {name}")
                resolved = str(PurePosixPath(name).parent / target)
                if resolved not in members or not members[resolved].isfile():
                    raise ValueError(f"Archive symlink must target an included regular file: {name}")
        binary_name = package_root + "/bin/hexproof"
        if binary_name not in members or not members[binary_name].isfile():
            raise ValueError("Release has no expected production executable")
        destination.mkdir(parents=True, exist_ok=False)
        for name, member in members.items():
            target = destination / name
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                with bundle.extractfile(member) as source, target.open("xb") as output:
                    shutil.copyfileobj(source, output)
                target.chmod(0o755 if member.mode & 0o111 else 0o644)
        for name, member in members.items():
            if member.issym():
                (destination / name).symlink_to(member.linkname)
    return destination / binary_name, {"members": len(members), "unpackedBytes": total}


def select_profile(args):
    if args.profile_run:
        run = args.profile_run.resolve(strict=True)
        if (read_json(regular(run / "environment.json")).get("evidence") != "native-qt-input"
                or read_json(regular(run / "report.json")).get("status") != "passed"):
            raise ValueError("The source profile must belong to a completed passing native run")
        profile = run / f"seat-{args.profile_seat}"
    else:
        profile = args.profile
    if profile is None:
        raise ValueError("--profile-run or explicit --profile is required for profile preservation")
    if profile.is_symlink() or not (profile / APP_DATA).is_dir():
        raise ValueError("The source profile must be a native runner seat root containing data/Hexproof/Hexproof")
    return profile.resolve(strict=True)


def profile_snapshot(profile):
    base = profile / APP_DATA
    files = {}
    for name in (*PROFILE_FILES, *PROFILE_DIRS):
        origin = base / name
        if not origin.exists() and not origin.is_symlink():
            continue
        entries = [origin, *origin.rglob("*")] if origin.is_dir() else [origin]
        for entry in entries:
            if entry.is_symlink() or not (entry.is_file() or entry.is_dir()):
                raise ValueError(f"Source profile contains a link or special file: {entry}")
            if entry.is_file():
                files[str(entry.relative_to(base))] = {"sha256": digest(entry), "bytes": entry.stat().st_size}
    return files


def clone_profile(source, destination):
    base = source / APP_DATA
    snapshot = profile_snapshot(source)
    decks = read_json(regular(base / "decks.json"))
    deck_rows = decks.get("decks", []) if isinstance(decks, dict) else decks
    if (not isinstance(deck_rows, list) or not deck_rows or "cards.sqlite" not in snapshot
            or not any(name.startswith("images/") for name in snapshot)):
        raise ValueError("Preservation requires a populated catalog, saved decks, and cached images")
    output = destination / APP_DATA
    output.mkdir(parents=True, exist_ok=False)
    for name in PROFILE_FILES:
        origin = base / name
        if not origin.exists():
            continue
        if name == "cards.sqlite":
            with closing(sqlite3.connect(origin.as_uri() + "?mode=ro", uri=True)) as database:
                if database.execute("SELECT COUNT(*) FROM cards").fetchone()[0] <= 0:
                    raise ValueError("Preservation requires a populated card database")
                with closing(sqlite3.connect(output / name)) as copy:
                    database.backup(copy)
        else:
            data = origin.read_text()
            json.loads(data)
            # Only explicit test profile paths are rebased; resume/session files
            # are never copied, and source files are never opened for writing.
            (output / name).write_text(data.replace(str(base), str(output)))
    for name in PROFILE_DIRS:
        if (base / name).exists():
            shutil.copytree(base / name, output / name)
    for name in ("config", "cache", "downloads"):
        (destination / name).mkdir()
    download = str(destination / "downloads").replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")
    (destination / "config/user-dirs.dirs").write_text(f'XDG_DOWNLOAD_DIR="{download}"\n')
    return {"decks": len(deck_rows), "imageFiles": sum(name.startswith("images/") for name in snapshot)}


def changed_files(before, after, ignore_settings=False):
    return sorted(name for name in before.keys() | after.keys()
                  if not (ignore_settings and name == "settings.json") and before.get(name) != after.get(name))


def isolated_environment(profile, native):
    env = os.environ.copy()
    for key in list(env):
        if (key.startswith("HEXPROOF_") or key in ("LD_LIBRARY_PATH", "QT_PLUGIN_PATH", "QT_QPA_PLATFORM_PLUGIN_PATH",
                                                  "QML_IMPORT_PATH", "QML2_IMPORT_PATH")
                or key.lower().endswith("_proxy")):
            env.pop(key)
    env.update(XDG_DATA_HOME=str(profile / "data"), XDG_CONFIG_HOME=str(profile / "config"),
               XDG_CACHE_HOME=str(profile / "cache"), QT_QPA_PLATFORM="xcb" if native else "offscreen")
    return env


def check_version(binary, version, profile, output):
    # The production archive ships xcb, not offscreen. --version is handled
    # before constructing the QML engine or any window, but QGuiApplication
    # still needs the packaged platform plugin to initialize first.
    result = subprocess.run([str(binary), "--version"], env=isolated_environment(profile, True),
                            capture_output=True, text=True, timeout=20, check=False)
    (output / "version.stdout.log").write_text(result.stdout)
    (output / "version.stderr.log").write_text(result.stderr)
    if result.returncode:
        raise ValueError(f"Extracted binary --version exited {result.returncode}: {result.stderr.strip()}")
    if not re.search(r"^Hexproof " + re.escape(version) + r"\s*$", result.stdout, re.MULTILINE):
        raise ValueError(f"Extracted binary version does not match {version}: {result.stdout.strip()}")
    return {"expected": version, "stdout": result.stdout.strip(), "exitCode": result.returncode}


def ppm_to_png(source, destination):
    with source.open("rb") as image:
        if image.readline() != b"P6\n":
            raise ValueError("Invalid native screenshot header")
        width, height = map(int, image.readline().split())
        if image.readline() != b"255\n" or width < 640 or height < 400 or width * height > 32_000_000:
            raise ValueError("Invalid native screenshot dimensions")
        pixels = image.read()
    if len(pixels) != width * height * 3 or len(set(pixels)) < 8:
        raise ValueError("Native screenshot is incomplete or blank")
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(b"\0" + pixels[y * width * 3:(y + 1) * width * 3] for y in range(height))
    with destination.open("xb") as image:
        image.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                    + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
    return {"width": width, "height": height, "sha256": digest(destination)}


def launch_release(binary, profile, output, helper, settle_seconds):
    regular(helper)
    if not os.environ.get("DISPLAY") or not shutil.which("unshare"):
        raise ValueError("Native launch requires X11 DISPLAY and unshare network isolation")
    namespace = ["unshare", "--user", "--map-root-user", "--net"]
    subprocess.run(namespace + ["true"], capture_output=True, check=True, timeout=5)
    process = None
    evidence = {"status": "failed", "network": "isolated Linux network namespace", "events": []}
    write_json(output / "gui.json", evidence)
    def request(action, extra=()):
        result = subprocess.run([str(helper), action, str(process.pid), *extra],
                                capture_output=True, text=True, timeout=5, check=False)
        if result.returncode:
            return None
        reply = json.loads(result.stdout)
        if reply.get("status") != "passed" or reply.get("pid") != process.pid or reply.get("visible") is not True:
            raise ValueError("X11 helper did not establish a visible window belonging to the launched process")
        return reply
    try:
        with (output / "application.log").open("w") as log:
            process = subprocess.Popen(namespace + [str(binary), "--instance-label", "Update Package Test"],
                                       env=isolated_environment(profile, True), stdout=log, stderr=subprocess.STDOUT,
                                       start_new_session=True, cwd=binary.parent.parent)
            evidence["pid"] = process.pid
            # A mapped window is necessary but not enough: retain it through a
            # settle interval before capture, and require the same process to exit.
            deadline = time.monotonic() + 30
            window = None
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise ValueError(f"Released application exited before its native window: {process.returncode}")
                window = request("--inspect")
                if window:
                    break
                time.sleep(0.2)
            if not window:
                raise ValueError("No unique visible PID-owned release window appeared")
            evidence["events"].append(window)
            try:
                process.wait(timeout=settle_seconds)
                raise ValueError("Released application exited during startup settling")
            except subprocess.TimeoutExpired:
                pass
            screenshot = request("--capture", [str(output / "release-window.ppm")])
            if not screenshot or screenshot["window"] != window["window"]:
                raise ValueError("The owned release window could not be captured after startup")
            evidence["events"].append(screenshot)
            evidence["screenshot"] = ppm_to_png(output / "release-window.ppm", output / "release-window.png")
            closed = request("--close")
            if not closed or closed["window"] != window["window"]:
                raise ValueError("WM_DELETE_WINDOW could not be sent to the same owned release window")
            evidence["events"].append(closed)
            evidence["exitCode"] = process.wait(timeout=15)
            if evidence["exitCode"] != 0:
                raise ValueError(f"Released application did not exit cleanly: {evidence['exitCode']}")
            evidence["status"] = "passed"
    finally:
        if process is not None and process.poll() is None:
            evidence["cleanupRequired"] = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=3)
        write_json(output / "gui.json", evidence)
    return evidence


def run(args):
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {"status": "failed", "gui": {"status": "not_run"},
              "coverage": "Safe release extraction and version only; GUI launch is a separate opt-in stage",
              "startedAt": time.time(), "toolSha256": digest(Path(__file__))}
    try:
        archive, package_root, version, source = load_download(args.source_run, args.seat)
        report["source"] = source
        source_profile = select_profile(args)
        source_before = profile_snapshot(source_profile)
        write_json(output / "source-profile-before.json", source_before)
        report["sourceProfile"] = str(source_profile)
        profile = output / "profile"
        report["profile"] = clone_profile(source_profile, profile)
        binary, report["extraction"] = safe_extract(archive, output / "package", package_root)
        report["binary"] = {"path": str(binary), "sha256": digest(binary)}
        report["version"] = check_version(binary, version, profile, output)
        before = profile_snapshot(profile)
        write_json(output / "profile-before.json", before)
        if args.launch:
            report["windowHelperSha256"] = digest(regular(args.window_helper.resolve()))
            report["gui"] = launch_release(binary, profile, output, args.window_helper.resolve(), args.settle_seconds)
        after = profile_snapshot(profile)
        source_after = profile_snapshot(source_profile)
        write_json(output / "profile-after.json", after)
        write_json(output / "source-profile-after.json", source_after)
        report["preservation"] = {"sourceChanged": changed_files(source_before, source_after),
                                  "cloneDataChanged": changed_files(before, after, ignore_settings=True),
                                  "settingsChanged": before.get("settings.json") != after.get("settings.json")}
        if report["preservation"]["sourceChanged"] or report["preservation"]["cloneDataChanged"]:
            raise ValueError("The source profile changed or the launched release changed preserved card data")
        report["status"] = "passed" if args.launch else "prepared"
        if args.launch:
            report["coverage"] = ("Production release version, visible PID-owned X11 startup and screenshot, "
                                  "WM_DELETE_WINDOW exit, and catalog/deck/image byte preservation; "
                                  "no install scripts, in-application actions, or online checks")
        return 0
    except (OSError, ValueError, sqlite3.Error, tarfile.TarError, subprocess.SubprocessError) as error:
        report["reason"] = str(error)
        return 1
    finally:
        report["finishedAt"] = time.time()
        write_json(output / "report.json", report)
        print(f"Update package verification: {output / 'report.json'}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-run", type=Path, required=True)
    parser.add_argument("--seat", type=int, default=1, help="Updater run seat")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--profile-run", type=Path, help="Passing native run whose data is copied read-only")
    source.add_argument("--profile", type=Path, help="Explicit native runner seat root to copy read-only")
    parser.add_argument("--profile-seat", type=int, default=1)
    parser.add_argument("--output", type=Path, required=True, help="A new directory; never reused")
    parser.add_argument("--launch", action="store_true", help="Also run the released production GUI on the native display")
    parser.add_argument("--window-helper", type=Path, default=ROOT / "build/ui-automation/xwindow-owned")
    parser.add_argument("--settle-seconds", type=float, default=8)
    args = parser.parse_args()
    if sys.platform != "linux" or args.seat < 1 or args.profile_seat < 1 or not 1 <= args.settle_seconds <= 30:
        parser.error("Linux, positive seats, and a 1–30 second settle interval are required")
    def interrupted(_signal, _frame):
        raise InterruptedError("Package verification interrupted; owned process cleanup requested")
    signal.signal(signal.SIGTERM, interrupted)
    try:
        if args.launch:
            import fcntl
            lock_path = ROOT / "build/native-verification/.display.lock"
            lock_path.parent.mkdir(parents=True, exist_ok=True)
            with lock_path.open("w") as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    parser.error("Another native scenario owns the display")
                return run(args)
        return run(args)
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    sys.exit(main())
