#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Install/remove project-scoped AO 0.14.4 native review reporting compatibility."""

import argparse
import fcntl
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile


class SetupError(Exception):
    pass


class LocalAPI:
    def __init__(self, run_file):
        info = json.loads(Path(run_file).read_text())
        port = info.get("port")
        if type(port) is not int or not 1 <= port <= 65535:
            raise SetupError("Invalid AO run-file port")
        self.port = port

    def call(self, method, path, payload=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=15)
        body = None if payload is None else json.dumps(payload).encode()
        try:
            conn.request(method, "/api/v1/" + path, body,
                         {"Content-Type": "application/json"})
            response = conn.getresponse()
            raw = response.read(2 * 1024 * 1024 + 1)
            if not 200 <= response.status < 300 or len(raw) > 2 * 1024 * 1024:
                raise SetupError(f"AO {method} failed (HTTP {response.status})")
            result = json.loads(raw)
            if not isinstance(result, dict):
                raise SetupError("Invalid AO response")
            return result
        finally:
            conn.close()


def atomic_json(path, value):
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".reporting-")
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def bundle(state_dir):
    source = Path(__file__).resolve().parent
    files = {
        "ao_review_report.py": (source / "ao_review_report.py").read_bytes(),
        "bash-env.sh": (source / "ao-reporting/bash-env.sh").read_bytes(),
    }
    zsh_hook = (source / "ao-reporting/zshenv").read_bytes()
    for name in (".zshenv", ".zprofile", ".zshrc", ".zlogin", ".zlogout"):
        files[name] = zsh_hook
    digest = hashlib.sha256()
    for name, data in sorted(files.items()):
        digest.update(name.encode() + b"\0" + data + b"\0")
    target = state_dir / "bundles" / digest.hexdigest()
    if not target.exists():
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        temporary = Path(tempfile.mkdtemp(dir=target.parent))
        try:
            for name, data in files.items():
                (temporary / name).write_bytes(data)
                (temporary / name).chmod(0o400)
            temporary.chmod(0o500)
            temporary.rename(target)
        finally:
            if temporary.exists():
                temporary.chmod(0o700)
                shutil.rmtree(temporary)
    if target.is_symlink() or any((target / name).is_symlink() or
                                 (target / name).read_bytes() != data
                                 for name, data in files.items()):
        raise SetupError("Installed bundle differs from its content hash")
    return target


def executable(name):
    result = shutil.which(name)
    if not result:
        raise SetupError(f"Required executable missing: {name}")
    return str(Path(result).resolve())


def project_config(api, project):
    value = api.call("GET", "projects/" + project)["project"]
    config = value.get("config", {})
    if isinstance(config, str):
        config = json.loads(config)
    if value.get("id") != project or not isinstance(config, dict):
        raise SetupError("Project identity/config mismatch")
    return config


def apply(api, project, state_dir, operation):
    identity = api.call("GET", "identity")
    if identity.get("apiVersion") != 1 or not identity.get("hostId"):
        raise SetupError("Unsupported AO identity")
    record_path = state_dir / (project + ".json")
    record = json.loads(record_path.read_text()) if record_path.exists() else None
    config = project_config(api, project)
    env = dict(config.get("env", {}))
    if record:
        if record["project"] != project or record["hostId"] != identity["hostId"]:
            raise SetupError("AO host changed; use the original installation record")
        installed = all(env.get(k) == v for k, v in record["installed"].items())
        original = all(env.get(k) == v for k, v in record["previous"].items())
        pending = record.get("phase") == "prepared" and "before" in record and all(
            env.get(k) == v for k, v in record["before"].items())
        if not installed and not original and not pending:
            raise SetupError("Reporting environment changed; refusing to overwrite it")
    else:
        installed = False
    if operation == "status":
        return {"project": project, "installed": installed,
                "bundle": record.get("bundle") if record else None}
    if operation == "remove":
        if not record:
            return {"project": project, "installed": False}
        replacement = record["previous"]
    else:
        prior = record["previous"] if record else env
        if not record and any(k.startswith("HEXPROOF_AO_") for k in env):
            raise SetupError("Unmanaged reporting environment already exists")

        def previous_hook(name, fallback):
            if prior.get(name) is not None:
                return prior[name]
            if record:
                return record["installed"]["HEXPROOF_AO_PREVIOUS_" + name]
            return os.environ.get(name, fallback)

        previous_bash = previous_hook("BASH_ENV", "")
        if "$" in previous_bash or "`" in previous_bash or previous_bash.startswith("~"):
            raise SetupError("Existing BASH_ENV must be a literal path; shell expansions are unsupported")
        previous_zsh = previous_hook("ZDOTDIR", env.get("HOME", str(Path.home())))
        target = bundle(state_dir)
        replacement = {
            "BASH_ENV": str(target / "bash-env.sh"),
            "ZDOTDIR": str(target),
            "HEXPROOF_AO_PREVIOUS_BASH_ENV": previous_bash,
            "HEXPROOF_AO_PREVIOUS_ZDOTDIR": previous_zsh,
            "HEXPROOF_AO_REPORT_ADAPTER": str(target / "ao_review_report.py"),
            "HEXPROOF_AO_HOST_ID": identity["hostId"],
            "HEXPROOF_AO_PYTHON": executable("python3"),
            "HEXPROOF_AO_GIT": executable("git"),
            "HEXPROOF_AO_GH": executable("gh"),
        }
        # Save only the keys this adapter owns, never the rest of project env.
        previous = {k: prior.get(k) for k in replacement}
        record = {"hostId": identity["hostId"], "project": project,
                  "bundle": str(target), "previous": previous,
                  "before": {k: env.get(k) for k in replacement},
                  "installed": replacement, "phase": "prepared"}
        atomic_json(record_path, record)
    for key, value in replacement.items():
        if value is None:
            env.pop(key, None)
        else:
            env[key] = value
    updated = dict(config, env=env)
    # AO has no configuration CAS; avoid silently overwriting an observed edit.
    if project_config(api, project) != config:
        raise SetupError("Project configuration changed during setup; retry after checking it")
    api.call("PUT", "projects/" + project + "/config", {"config": updated})
    final = project_config(api, project)
    if final != updated:
        # AO omits empty fields; compare the actual owned environment keys.
        final_env = final.get("env", {})
        if any(final_env.get(k) != v for k, v in replacement.items()):
            raise SetupError("Configuration write not confirmed; inspect status before retry")
    if operation == "remove":
        record_path.unlink()
    else:
        record["phase"] = "installed"
        atomic_json(record_path, record)
    return {"project": project, "installed": operation == "install",
            "newSessionsOnly": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("install", "status", "remove"))
    parser.add_argument("--project", required=True)
    parser.add_argument("--run-file", default=os.environ.get("AO_RUN_FILE", str(Path.home() / ".ao/running.json")))
    parser.add_argument("--state-dir", type=Path,
                        default=Path.home() / ".local/share/hexproof/ao-reporting")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,100}", args.project):
        raise SetupError("Invalid project ID")
    state_dir = args.state_dir.expanduser().resolve()
    state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (state_dir / ".lock").open("a") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        print(json.dumps(apply(LocalAPI(args.run_file), args.project, state_dir, args.operation)))


if __name__ == "__main__":
    try:
        main()
    except (SetupError, OSError, ValueError, KeyError, TypeError, http.client.HTTPException) as error:
        # Do not print config dictionaries or arbitrary server bodies.
        print("AO reporting setup failed: " + (str(error) if isinstance(error, SetupError)
                                               else type(error).__name__), file=sys.stderr)
        sys.exit(1)
