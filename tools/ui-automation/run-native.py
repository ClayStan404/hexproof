#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Run production Qt scenarios in isolated profiles with an external watchdog."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import socket
import sqlite3
import stat
import subprocess
import sys
import time
from urllib.parse import unquote, urlsplit
import uuid

ROOT = Path(__file__).resolve().parents[2]


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(path)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def scenario_provenance(path):
    return {"scenario": str(path), "sha256": digest(path),
            "localSources": {str(source): digest(source)
                             for source in sorted(path.parent.iterdir())
                             if source.is_file() and source.suffix in (".qml", ".js")}}


def git_output(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode().strip()


def copy_fixture(source, destination):
    """Copy only explicit test data; never import settings or resume credentials."""
    for name in ("decks.json", "card-cache.json", "images", "custom-art"):
        origin = source / name
        if not origin.exists() and not origin.is_symlink():
            continue
        entries = [origin, *origin.rglob("*")] if origin.is_dir() else [origin]
        if any(p.is_symlink() or not (p.is_file() or p.is_dir()) for p in entries):
            raise ValueError(f"Fixture contains a link or special file: {origin}")
        target = destination / name
        if origin.is_dir():
            shutil.copytree(origin, target)
        else:
            data = origin.read_text()
            # Fixtures use an explicit token, not paths into a live profile.
            data = data.replace("@PROFILE@", str(destination))
            json.loads(data)
            target.write_text(data)


def prepare_profile(profile, catalog=None, fixture=None, card_language="en", fresh_settings=False):
    app_data = profile / "data/Hexproof/Hexproof"
    app_data.mkdir(parents=True)
    (profile / "config").mkdir()
    (profile / "cache").mkdir()
    downloads = profile / "downloads"
    downloads.mkdir()
    # QStandardPaths reads XDG user directories separately from app data.
    # Package downloads must not escape into the owner's real Downloads folder.
    quoted_downloads = str(downloads).replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")
    (profile / "config/user-dirs.dirs").write_text(
        f'XDG_DOWNLOAD_DIR="{quoted_downloads}"\n')
    if catalog:
        with sqlite3.connect(catalog.resolve().as_uri() + "?mode=ro", uri=True) as source:
            with sqlite3.connect(app_data / "cards.sqlite") as target:
                source.backup(target)
    if fixture:
        copy_fixture(fixture, app_data)
    if not fresh_settings:
        write_json(app_data / "settings.json", {
            "uiLanguage": "en", "cardLanguage": card_language, "interfaceScale": 1.0,
            "sponsorAnnouncementVersion": 999,
        })
    return app_data


def profile_checkpoint(profile):
    app_data = profile / "data/Hexproof/Hexproof"
    return {
        "files": {name: {"bytes": (app_data / name).stat().st_size,
                         "sha256": digest(app_data / name)}
                  for name in ("settings.json", "cards.sqlite", "decks.json", "card-cache.json")
                  if (app_data / name).is_file()},
        "imageFiles": sum(1 for path in (app_data / "images").rglob("*") if path.is_file()),
    }


def record_verified_download(artifacts, result, run_id, seat, stage):
    """Seal a completed updater stage's file observation once, after native validation."""
    if result.get("scenario") != "application-update":
        return None
    if (result.get("status") != "passed" or result.get("downloadReady") is not True
            or result.get("sawDownload") is not True or result.get("updaterError")):
        raise ValueError("Updater did not complete a verified download")
    profile = artifacts.parent.resolve(strict=True)
    downloads = profile / "downloads"
    archive = Path(result.get("downloadPath", ""))
    if (not archive.is_absolute() or not archive.is_relative_to(downloads) or not archive.is_file()
            or archive.resolve(strict=True) != archive):
        raise ValueError("Verified download is outside the isolated downloads directory or traverses a link")
    with archive.open("rb") as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= 1024 * 1024 * 1024:
            raise ValueError("Verified download must be a nonempty regular file of at most 1 GiB")
        content_hash = hashlib.sha256()
        size = 0
        while chunk := stream.read(1024 * 1024):
            size += len(chunk)
            if size > before.st_size:
                raise ValueError("Verified download changed while its evidence was recorded")
            content_hash.update(chunk)
        after = os.fstat(stream.fileno())
    if (size != before.st_size or (before.st_size, before.st_mtime_ns, before.st_ctime_ns)
            != (after.st_size, after.st_mtime_ns, after.st_ctime_ns)
            or not os.path.samestat(after, archive.stat())):
        raise ValueError("Verified download changed while its evidence was recorded")
    evidence = {"schema": "hexproof.verified-download.v1", "producer": "native-runner",
                "runId": run_id, "seat": seat, "stage": stage, "scenario": "application-update",
                "sourceVersion": result.get("sourceVersion"), "targetVersion": result.get("targetVersion"),
                "resultSha256": digest(artifacts / "result.json"), "recordedAt": time.time(),
                "path": str(archive), "bytes": size, "sha256": content_hash.hexdigest()}
    destination = artifacts / "download-evidence.json"
    # A rerun must create a fresh stage. Never replace earlier observations.
    with destination.open("x") as output:
        output.write(json.dumps(evidence, indent=2, ensure_ascii=False) + "\n")
    return {"artifact": destination.name, "sha256": digest(destination)}


def stop_owned(process):
    """Only signal the process group created by this invocation."""
    if process.poll() is not None:
        return
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=3)


def pid_sample(pid):
    result = {"pid": pid}
    try:
        stat = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        result.update(cpuTicks=int(stat[11]) + int(stat[12]),
                      rssBytes=int(stat[21]) * os.sysconf("SC_PAGE_SIZE"),
                      name=Path(f"/proc/{pid}/comm").read_text().strip())
        for line in Path(f"/proc/{pid}/smaps_rollup").read_text().splitlines():
            if line.startswith("Pss:"):
                result["pssBytes"] = int(line.split()[1]) * 1024
    except (OSError, IndexError, ValueError):
        pass
    return result


def process_sample(process):
    result = pid_sample(process.pid)
    result["exitCode"] = process.poll()
    descendants, pending, seen = [], [process.pid], {process.pid}
    while pending and len(seen) < 128:
        parent = pending.pop()
        for children in Path(f"/proc/{parent}/task").glob("*/children"):
            try:
                for child in map(int, children.read_text().split()):
                    if child not in seen:
                        seen.add(child)
                        pending.append(child)
                        descendants.append(pid_sample(child))
            except (OSError, ValueError):
                pass
    result["children"] = descendants
    return result


def seat_result(process, artifacts, reason=None):
    """Require native input evidence as well as a scenario's own assertions."""
    try:
        result = json.loads((artifacts / "result.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        result = {}
    exit_code = process.poll()
    if reason is None and (exit_code != 0 or not isinstance(result, dict)
                           or result.get("status") != "passed"):
        reason = "Missing pass result or nonzero exit"
    if reason is None:
        try:
            startup = json.loads((artifacts / "startup.json").read_text(encoding="utf-8"))
            summary = json.loads((artifacts / "audit-summary.json").read_text(encoding="utf-8"))
            actions = [json.loads(line) for line in (artifacts / "actions.jsonl").read_text(encoding="utf-8").splitlines()
                       if line.strip()]
            window = startup.get("window") if isinstance(startup, dict) else None
            platform_name = window.get("platform") if isinstance(window, dict) else None
            if (not isinstance(platform_name, str) or not platform_name
                    or platform_name.split(":", 1)[0].lower() in ("offscreen", "minimal")
                    or window.get("visible") is not True or window.get("exposed") is not True
                    or startup.get("evidence") != "native-qt-input"):
                raise ValueError("Startup does not establish an exposed native window")
            if not isinstance(summary, dict) or summary.get("evidence") != "native-qt-input":
                raise ValueError("Missing native audit summary")
            inputs = summary.get("inputs")
            if type(inputs) is not int or inputs <= 0 or inputs != len(actions):
                raise ValueError("Input trace is empty or does not match the audit summary")
            for field in ("exitCode", "failedInputs", "artifactFailures"):
                if type(summary.get(field)) is not int or summary[field] != 0:
                    raise ValueError(f"Audit summary has missing or failed {field}")
            if summary.get("qmlWarnings") != []:
                raise ValueError("Audit summary has missing or nonempty QML warnings")
            client_log = artifacts.parent / (
                "client.log" if artifacts.name == "artifacts"
                else artifacts.name.removesuffix("-artifacts") + "-client.log")
            if client_log.is_file():
                with client_log.open(errors="replace") as stream:
                    for line in stream:
                        if any(marker in line for marker in (
                                "Gtk-CRITICAL", "GLib-GObject-CRITICAL", "GLib-CRITICAL",
                                "ERROR: AddressSanitizer", "WARNING: ThreadSanitizer")):
                            raise ValueError("Native runtime diagnostics: " + line.strip()[:500])
            for sequence, action in enumerate(actions, 1):
                if (not isinstance(action, dict) or action.get("accepted") is not True
                        or action.get("evidence") not in ("native-qt-input", "native-x11-input", "native-gtk-input")
                        or not isinstance(action.get("action"), str) or not action["action"]
                        or type(action.get("sequence")) is not int or action["sequence"] != sequence):
                    raise ValueError("Input trace contains failed or incomplete evidence")
                if action["action"] == "chooseFile":
                    if (action.get("dialogAccepted") is not True or action.get("dialogClosed") is not True
                            or not isinstance(action.get("selectedFile"), str)
                            or not isinstance(action.get("path"), str) or not action["path"].startswith("/")):
                        raise ValueError("File chooser did not establish actual acceptance and closure")
                    selected = urlsplit(action["selectedFile"])
                    if (selected.scheme != "file" or selected.netloc or selected.query or selected.fragment
                            or unquote(selected.path) != action["path"]):
                        raise ValueError("File chooser selected a different path from its requested input")
                if action.get("evidence") in ("native-x11-input", "native-gtk-input"):
                    dialog = action.get("nativeDialog", {})
                    if (action.get("action") != "chooseFile" or not isinstance(dialog, dict)
                            or dialog.get("status") != "passed" or dialog.get("matches") != 1
                            or type(startup.get("pid")) is not int or dialog.get("pid") != startup["pid"]
                            or type(dialog.get("keys")) is not int or dialog["keys"] <= 0
                            or not dialog.get("window") or not dialog.get("transientOwner")):
                        raise ValueError("Native file chooser evidence lacks scoped successful input")
                    if action["evidence"] == "native-gtk-input" and (
                            dialog.get("evidence") != "native-gtk-input"
                            or dialog.get("osInputRoutingVerified") is not False
                            or not isinstance(dialog.get("events"), list)
                            or len(dialog["events"]) != dialog["keys"]
                            or not isinstance(action.get("selectedFile"), str)
                            or not action["selectedFile"]):
                        raise ValueError("GTK widget evidence lacks truthful input routing and selection")
                    if action["evidence"] == "native-gtk-input":
                        selected = urlsplit(action["selectedFile"])
                        if (selected.scheme != "file" or selected.netloc or selected.query or selected.fragment
                                or unquote(selected.path) != action.get("path")
                                or dialog.get("path") != action.get("path")):
                            raise ValueError("GTK chooser selected a different path from its requested input")
                        pointers = dialog.get("pointerEvents")
                        if (not isinstance(pointers, list) or len(pointers) != 2
                                or any(not isinstance(event, dict) for event in pointers)
                                or [event.get("type") for event in pointers] != ["button-press", "button-release"]
                                or any(not event.get("target") or not event.get("window")
                                       or type(event.get("x")) not in (int, float)
                                       or type(event.get("y")) not in (int, float)
                                       for event in pointers)):
                            raise ValueError("GTK chooser acceptance lacks its real button input")
            screenshots = result.get("requiredScreenshots")
            if not isinstance(screenshots, list) or not screenshots:
                raise ValueError("Scenario did not declare required screenshots")
            for name in screenshots:
                if (not isinstance(name, str) or not name.endswith(".png") or len(name) > 164
                        or not name[0].isascii() or not name[0].isalnum()
                        or not all(c.isascii() and (c.isalnum() or c in "_.-") for c in name)):
                    raise ValueError("Invalid required screenshot name")
                with (artifacts / name).open("rb") as screenshot:
                    header = screenshot.read(24)
                    screenshot.seek(-12, os.SEEK_END)
                    trailer = screenshot.read(12)
                if (len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n"
                        or header[8:16] != b"\x00\x00\x00\rIHDR"
                        or int.from_bytes(header[16:20], "big") == 0
                        or int.from_bytes(header[20:24], "big") == 0
                        or trailer != b"\x00\x00\x00\x00IEND\xaeB`\x82"):
                    raise ValueError(f"Required screenshot is not a PNG image: {name}")
        except (OSError, ValueError) as error:
            reason = f"Incomplete native evidence: {error}"
    passed = reason is None
    return {"status": "passed" if passed else "failed", "exitCode": exit_code,
            "reason": reason,
            "scenarioResult": result, "artifacts": str(artifacts)}


def run(args):
    args.player_hosted = getattr(args, "player_hosted", False)
    args.reconnect_window = getattr(args, "reconnect_window", None)
    if platform.system() != "Linux":
        raise ValueError("This runner currently supports Linux isolated XDG profiles.")
    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        raise ValueError("A native display is required; offscreen is not native evidence.")
    if os.environ.get("QT_QPA_PLATFORM", "").split(":", 1)[0] in ("offscreen", "minimal"):
        raise ValueError("Offscreen/minimal platforms cannot produce native evidence.")
    scenarios = [args.scenario, *args.next_scenario]
    for path in (args.binary, *scenarios):
        if not path.is_file():
            raise ValueError(f"Required file not found: {path}")
    if args.players > 1 and not args.server_binary:
        raise ValueError("Multiple seats require --server-binary; public servers are unsupported.")
    if args.network_isolated and (args.players != 1 or args.server_binary):
        raise ValueError("Network-isolated verification requires one offline client and no hub.")
    namespace_launcher = shutil.which("unshare") if args.network_isolated else None
    if args.network_isolated and not namespace_launcher:
        raise ValueError("Network-isolated verification requires the installed unshare utility.")
    run_id = uuid.uuid4().hex
    output = (args.output or ROOT / "build/native-verification" /
              (time.strftime("%Y%m%d-%H%M%S-") + run_id[:8])).resolve()
    output.mkdir(parents=True, exist_ok=False)
    shared = output / "shared"
    shared.mkdir()
    metadata = {
        "runId": run_id, "commit": git_output("rev-parse", "HEAD"),
        "workingTree": git_output("status", "--short"),
        "diffSha256": hashlib.sha256(subprocess.check_output(
            ["git", "diff", "--binary", "HEAD"], cwd=ROOT)).hexdigest(),
        "binary": str(args.binary), "binarySha256": digest(args.binary),
        "scenario": str(args.scenario), "scenarioSha256": digest(args.scenario),
        "platform": platform.platform(), "players": args.players, "playerHosted": args.player_hosted,
        "scaleFactor": args.scale,
        "requestedWindowMode": "windowed" if args.windowed else "maximized",
        "requestedWindowSize": [args.width, args.height] if args.windowed else None,
        "graphicsEnvironment": {name: os.environ[name] for name in
            ("QT_QPA_PLATFORM", "QSG_NO_VSYNC", "QSG_RENDER_LOOP", "QSG_RHI_BACKEND",
             "QT_QUICK_BACKEND", "QT_LOGGING_RULES") if name in os.environ},
        "evidence": "native-qt-input", "startedAt": time.time(),
        "fixture": str(args.fixture_dir) if args.fixture_dir else None,
        "catalog": str(args.catalog) if args.catalog else None,
        "stages": [scenario_provenance(path) for path in scenarios],
        "catalogImport": str(args.catalog_import) if args.catalog_import else None,
        "deckManifest": str(args.deck_manifest) if args.deck_manifest else None,
        "startupServices": args.startup_services,
        "freshSettings": args.fresh_settings,
        "networkIsolated": args.network_isolated,
        "clientEnvironmentOverrides": {"GIO_USE_VFS": "local"} if args.network_isolated else {},
        "fileSystemScope": "local-files-only" if args.network_isolated else "not-restricted-by-runner",
        "clientLauncher": [namespace_launcher, "--user", "--map-root-user", "--net"]
            if namespace_launcher else [],
        "fileDialogHelper": {"path": str(args.file_dialog_helper),
                             "sha256": digest(args.file_dialog_helper)} if args.file_dialog_helper else None,
        "forge": ("configured by inherited server environment"
                  if os.environ.get("HEXPROOF_FORGE_HARNESS") else "not declared by runner"),
        "variant": args.variant,
    }
    write_json(output / "environment.json", metadata)
    print(f"Native verification artifacts: {output}", flush=True)
    processes, logs, seats, results = [], [], [], []
    download_bindings, completion_failures = {}, {}
    server = None
    reason = None
    started = time.monotonic()
    try:
        server_url = None
        if args.server_binary:
            with socket.socket() as probe:
                probe.bind(("127.0.0.1", 0))
                port = probe.getsockname()[1]
            server_url = f"ws://127.0.0.1:{port}/ws"
            log = (output / "server.log").open("w")
            logs.append(log)
            server = subprocess.Popen([
                str(args.server_binary), "-bind", "127.0.0.1", "-port", str(port),
                "-retention-dir", str(output / "retained"),
                "-forge-games-per-jvm", str(args.forge_games_per_jvm),
            ] + (["-allow-player-hosting"] if args.player_hosted else []) + (["-reconnect-window", str(args.reconnect_window)+"s"] if args.reconnect_window else []), cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            processes.append(server)
            deadline = time.monotonic() + 10
            while True:
                if server.poll() is not None:
                    raise RuntimeError("Local server exited before listening; see server.log")
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                        break
                except OSError:
                    if time.monotonic() > deadline:
                        raise RuntimeError("Local server did not listen within ten seconds")
                    time.sleep(0.1)
            metadata.update(serverUrl=server_url, serverSha256=digest(args.server_binary))
            write_json(output / "environment.json", metadata)

        # Finish potentially large catalog copies before starting any seat's
        # scenario deadline or waiting for another seat to join.
        for seat in range(1, args.players + 1):
            profile = output / f"seat-{seat}"
            prepare_profile(profile, args.catalog, args.fixture_dir, args.card_language, args.fresh_settings)

        started = time.monotonic()
        for stage, scenario in enumerate(scenarios, 1):
            stage_seats = []
            stage_shared = shared if stage == 1 else output / f"stage-{stage}-shared"
            stage_shared.mkdir(exist_ok=True)
            if args.deck_manifest:
                write_json(stage_shared / "fixture.json", json.loads(args.deck_manifest.read_text()))
            for seat in range(1, args.players + 1):
                profile = output / f"seat-{seat}"
                artifacts = profile / ("artifacts" if stage == 1 else f"stage-{stage}-artifacts")
                artifacts.mkdir()
                write_json(artifacts / "profile-before.json", profile_checkpoint(profile))
                env = dict(os.environ, XDG_CONFIG_HOME=str(profile / "config"),
                           XDG_DATA_HOME=str(profile / "data"), XDG_CACHE_HOME=str(profile / "cache"),
                           HEXPROOF_TEST_PROFILE_ROOT=str(profile),
                           HEXPROOF_AUDIT_DRIVER=str(scenario),
                           HEXPROOF_AUDIT_OUTPUT=str(artifacts), HEXPROOF_AUDIT_SHARED=str(stage_shared),
                           HEXPROOF_AUDIT_STAGE=str(stage),
                           HEXPROOF_AUDIT_STARTUP_SERVICES="1" if args.startup_services else "0",
                           HEXPROOF_AUDIT_NETWORK_ISOLATED="1" if args.network_isolated else "0",
                           HEXPROOF_AUDIT_CATALOG_IMPORT=str(args.catalog_import or ""),
                           HEXPROOF_AUDIT_DECK_MANIFEST=str(args.deck_manifest or ""),
                           HEXPROOF_AUDIT_FILE_DIALOG_HELPER=str(args.file_dialog_helper or ""),
                           HEXPROOF_AUDIT_SEAT=str(seat), HEXPROOF_AUDIT_PLAYERS=str(args.players),
                           HEXPROOF_AUDIT_RUN_ID=run_id,
                           HEXPROOF_AUDIT_WIDTH=str(args.width) if args.windowed else "",
                           HEXPROOF_AUDIT_VARIANT=args.variant,
                           HEXPROOF_AUDIT_PLAYER_HOSTED="1" if args.player_hosted else "0",
                           HEXPROOF_AUDIT_CARD_LANGUAGE=args.card_language,
                           HEXPROOF_AUDIT_HEIGHT=str(args.height) if args.windowed else "",
                           QT_SCALE_FACTOR=str(args.scale))
                # Do not let legacy inherited dimensions override this run's mode.
                env.pop("AUDIT_WIDTH", None)
                env.pop("AUDIT_HEIGHT", None)
                if args.network_isolated:
                    # The isolated client handles local files only. Host GVFS
                    # D-Bus authentication crosses a different user namespace
                    # and can leave GTK path-bar icon callbacks targeting removed
                    # widgets. GIO's local backend avoids that host service.
                    # This does not alter production GTK or validate GVFS mounts.
                    env["GIO_USE_VFS"] = "local"
                log = (profile / ("client.log" if stage == 1 else f"stage-{stage}-client.log")).open("w")
                logs.append(log)
                command = [str(args.binary), "--instance-label",
                           f"Native Test {run_id[:6]} seat {seat}"]
                if args.windowed:
                    command.append("--windowed")
                if server_url:
                    command += ["--server-url", server_url, "--display-name", f"Audit Player {seat}"]
                if namespace_launcher:
                    command = [namespace_launcher, "--user", "--map-root-user", "--net", *command]
                process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log,
                                           stderr=subprocess.STDOUT, start_new_session=True)
                processes.append(process)
                stage_seats.append((process, artifacts, time.monotonic()))
                seats.append(stage_seats[-1])

            with (output / "process-samples.jsonl").open("a") as samples:
                while any(process.poll() is None for process, _, _ in stage_seats):
                    now = time.monotonic()
                    if now - started > args.timeout:
                        reason = f"Run exceeded {args.timeout:g}s watchdog deadline"
                    if server and server.poll() is not None:
                        reason = "Local server exited during the scenario"
                    if server:
                        samples.write(json.dumps(dict(process_sample(server), role="server", stage=stage,
                            elapsedMs=round((now - started)*1000)))+"\n")
                    for process, artifacts, launched in stage_seats:
                        sample = process_sample(process)
                        sample["stage"] = stage
                        sample["elapsedMs"] = round((now - started) * 1000)
                        samples.write(json.dumps(sample) + "\n")
                        if process.poll() is not None:
                            if seat_result(process, artifacts)["status"] != "passed":
                                reason = f"Seat process {process.pid} exited without a passing result"
                            continue
                        heartbeat = artifacts / "heartbeat.json"
                        age = time.time() - heartbeat.stat().st_mtime if heartbeat.exists() else now - launched
                        limit = args.hang_timeout if heartbeat.exists() else max(30, args.hang_timeout)
                        if age > limit:
                            reason = f"Seat process {process.pid} heartbeat absent for {age:.1f}s"
                    samples.flush()
                    if reason:
                        break
                    time.sleep(0.25)
            for seat, (process, artifacts, _) in enumerate(stage_seats, 1):
                if process.poll() is not None:
                    write_json(artifacts / "profile-after.json", profile_checkpoint(artifacts.parent))
                    completed = seat_result(process, artifacts)
                    if completed["status"] == "passed":
                        try:
                            binding = record_verified_download(artifacts, completed["scenarioResult"], run_id, seat, stage)
                            if binding:
                                download_bindings[artifacts] = binding
                        except (OSError, ValueError) as error:
                            completion_failures[artifacts] = "Download evidence failed: " + str(error)
                            reason = completion_failures[artifacts]
                    elif reason is None:
                        reason = f"Stage {stage} did not pass; subsequent stages were not run"
            if reason:
                break
    except (OSError, RuntimeError, ValueError, KeyboardInterrupt) as error:
        reason = str(error) or "Interrupted"
    finally:
        for process in reversed(processes):
            stop_owned(process)
        for log in logs:
            log.close()
        # A later-stage failure must not relabel an already verified earlier
        # stage. The run fails as a whole, while each seat retains its evidence.
        results = []
        for index, (process, artifacts, _) in enumerate(seats):
            completed = dict(seat_result(process, artifacts, completion_failures.get(artifacts)),
                             stage=index // args.players + 1, seat=index % args.players + 1)
            if artifacts in download_bindings:
                completed["verifiedDownload"] = download_bindings[artifacts]
            results.append(completed)
        passed = reason is None and len(results) == args.players * len(scenarios) and all(
            result["status"] == "passed" for result in results)
        if not passed and reason is None:
            failure = next((result for result in results if result["status"] != "passed"), {})
            scenario_result = failure.get("scenarioResult", {})
            reason = ((scenario_result.get("message") if isinstance(scenario_result, dict) else None)
                      or failure.get("reason") or "Not all requested seats ran")
        report = {"status": "passed" if passed else "failed", "runId": run_id,
                  "durationSeconds": round(time.monotonic() - started, 3),
                  "reason": reason, "seats": results}
        write_json(output / "report.json", report)
        print(json.dumps({"status": report["status"], "reason": reason,
                          "report": str(output / "report.json")}), flush=True)
    return 0 if passed else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", required=True, type=Path)
    parser.add_argument("--next-scenario", type=Path, action="append", default=[],
                        help="Exit and relaunch this scenario using the same profiles and local hub")
    parser.add_argument("--catalog-import", type=Path, help="File for actual UI import; never preinstalled")
    parser.add_argument("--deck-manifest", type=Path, help="Real-card fixture manifest for UI deck import")
    parser.add_argument("--startup-services", action="store_true",
                        help="Run production automatic update checks and startup art audit")
    parser.add_argument("--network-isolated", action="store_true",
                        help="Run one offline client in a Linux network namespace; no hub")
    parser.add_argument("--file-dialog-helper", type=Path,
                        help="PID-scoped native X11 file chooser input helper")
    parser.add_argument("--fresh-settings", action="store_true",
                        help="Start without any settings file or dismissed first-launch notices")
    parser.add_argument("--binary", type=Path, default=ROOT / "build/client-qt/hexproof_native_audit")
    parser.add_argument("--server-binary", type=Path)
    parser.add_argument("--reconnect-window", type=int, choices=range(1, 601), help="Local hub reconnect grace in seconds")
    parser.add_argument("--player-hosted", action="store_true", help="Enable player hosting on the isolated local hub")
    parser.add_argument("--forge-games-per-jvm", type=int, choices=range(1, 5), default=1,
                        help="Use the packaged shared worker on the isolated hub")
    parser.add_argument("--output", type=Path, help="New directory; existing directories are refused")
    parser.add_argument("--catalog", type=Path, help="Read-only SQLite source for an independent backup")
    parser.add_argument("--fixture-dir", type=Path, help="Explicit decks/cache/images test fixture")
    parser.add_argument("--card-language", choices=("en", "zh"), default="en")
    parser.add_argument("--variant", default="modern", help="Scenario-specific format or variant")
    parser.add_argument("--players", type=int, choices=range(1, 9), default=1)
    parser.add_argument("--timeout", type=float, default=180)
    parser.add_argument("--hang-timeout", type=float, default=15)
    parser.add_argument("--windowed", action="store_true",
                        help="Use a fixed-size window for explicit layout probes; default is maximized")
    parser.add_argument("--width", type=int,
                        help="Logical window width; implies --windowed (windowed default: 1440)")
    parser.add_argument("--height", type=int,
                        help="Logical window height; implies --windowed (windowed default: 900)")
    parser.add_argument("--scale", type=float, default=1)
    args = parser.parse_args()
    args.windowed = args.windowed or args.width is not None or args.height is not None
    if args.windowed:
        args.width = 1440 if args.width is None else args.width
        args.height = 900 if args.height is None else args.height
    def interrupted(_signum, _frame):
        raise KeyboardInterrupt("Runner interrupted; stopping owned test processes")
    signal.signal(signal.SIGTERM, interrupted)
    for name in ("scenario", "binary", "server_binary", "catalog", "fixture_dir", "catalog_import", "deck_manifest", "file_dialog_helper"):
        if getattr(args, name):
            setattr(args, name, getattr(args, name).resolve())
    args.next_scenario = [path.resolve() for path in args.next_scenario]
    if not (1 <= args.timeout <= 7200 and 1 <= args.hang_timeout <= 120
            and (not args.windowed or (900 <= args.width <= 7680 and 620 <= args.height <= 4320))
            and 0.5 <= args.scale <= 3):
        parser.error("Invalid timeout, window dimensions, or scale")
    try:
        # Independent profiles do not isolate desktop focus. Running another
        # scenario during a drag or shortcut can invalidate real input evidence.
        if platform.system() != "Linux":
            raise ValueError("This runner currently supports Linux isolated XDG profiles.")
        import fcntl
        lock_path = ROOT / "build/native-verification/.display.lock"
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        with lock_path.open("w") as display_lock:
            try:
                fcntl.flock(display_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ValueError("Another native scenario owns the display; run scenarios sequentially") from None
            return run(args)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    sys.exit(main())
