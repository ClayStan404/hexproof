#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Bounded, local-only collection of hub or public-feedback readiness."""

import argparse
from datetime import datetime, timezone
import json
import logging
from logging.handlers import RotatingFileHandler
import math
from pathlib import Path
import time
import urllib.error
import urllib.request


ERRORS = {"", "cancelled", "timeout", "rejected", "capacity", "unavailable",
          "fenced", "registration_required"}
TIMINGS = ("accountRpc", "accountGate", "clusterView")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def fetch(port, route):
    started = time.monotonic()
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        try:
            response = opener.open(f"http://127.0.0.1:{port}/{route}", timeout=3)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            body = response.read(65537)
            if len(body) > 65536:
                raise ValueError("oversized response")
            return response.code, body, round((time.monotonic() - started) * 1000, 3)
    except (OSError, ValueError, urllib.error.URLError):
        return 0, b"", round((time.monotonic() - started) * 1000, 3)


def number(value):
    if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
        raise ValueError("invalid aggregate")
    return value


def diagnostics(value):
    """Copy only the documented aggregate schema, never arbitrary response text."""
    if type(value.get("ready")) is not bool:
        raise ValueError("missing readiness")
    result = {"ready": value["ready"], "sendFailures": number(value["sendFailures"])}
    for name in ("accounts", "cluster"):
        source = value.get(name)
        if source is None and name == "cluster":
            continue
        if not isinstance(source, dict) or type(source.get("ready")) is not bool:
            raise ValueError("invalid dependency")
        result[name] = {"ready": source["ready"]}
        error_key = "error" if name == "accounts" else "lastError"
        error = source.get(error_key, "")
        result[name][error_key] = error if error in ERRORS else "unavailable"
        if name == "cluster":
            for field in ("reportFailures", "inFlight", "pendingCompletions"):
                result[name][field] = number(source[field])
    for name in TIMINGS:
        source = value[name]
        result[name] = {field: number(source[field]) for field in
                        ("calls", "failed", "cancelled", "inFlight", "totalMs", "maxMs")}
        buckets = source["buckets"]
        if not isinstance(buckets, list) or len(buckets) != 7:
            raise ValueError("invalid latency buckets")
        result[name]["buckets"] = [number(item) for item in buckets]
        error = source.get("lastError", "")
        result[name]["lastError"] = error if error in ERRORS else "unavailable"
    return result


def delta(current, previous):
    # Process restart resets counters; report only the new process's values.
    return current - previous if current >= previous else current


def feedback_ok(body):
    try:
        return json.loads(body).get("ok") is True
    except (ValueError, TypeError, AttributeError):
        return False


def collect(port, previous=None, component="hub"):
    health_code, health_body, health_ms = fetch(port, "healthz")
    ready_code, ready_body, ready_ms = fetch(port, "readyz")
    sample = {"schemaVersion": 1, "collectedAt": datetime.now(timezone.utc).isoformat(),
              "live": health_code == 200 and (feedback_ok(health_body) if component == "feedback" else health_body == b"ok\n"),
              "ready": False, "healthHttp": health_code, "readyHttp": ready_code,
              "healthMs": health_ms, "readyMs": ready_ms, "alerts": []}
    try:
        if component == "feedback":
            sample["component"] = "feedback"
            sample["ready"] = ready_code == 200 and feedback_ok(ready_body)
            state = None
        else:
            state = diagnostics(json.loads(ready_body))
            sample["diagnostics"] = state
            sample["ready"] = ready_code == 200 and state["ready"]
    except (ValueError, KeyError, TypeError, AttributeError):
        state = None
    alerts = sample["alerts"]
    if not sample["live"]:
        alerts.append("liveness_unavailable")
    if not sample["ready"]:
        alerts.append("dependencies_unavailable")
    if max(health_ms, ready_ms) > 1000:
        alerts.append("probe_over_1s")
    old = (previous or {}).get("diagnostics")
    if state and old:
        if delta(state["sendFailures"], old["sendFailures"]):
            alerts.append("queue_send_failures")
        if "cluster" in state and "cluster" in old:
            if delta(state["cluster"]["reportFailures"], old["cluster"]["reportFailures"]):
                alerts.append("cluster_report_failures")
        sample["interval"] = {}
        for name in TIMINGS:
            now, before = state[name], old[name]
            calls = delta(now["calls"], before["calls"])
            failed = delta(now["failed"], before["failed"])
            mean = round(delta(now["totalMs"], before["totalMs"]) / calls, 3) if calls else 0
            sample["interval"][name] = {"calls": calls, "failed": failed, "meanMs": mean}
            if failed:
                alerts.append(name + "_failures")
            if mean > 1000:
                alerts.append(name + "_mean_over_1s")
    if previous and previous.get("alerts") and not alerts:
        sample["recovered"] = True
    return sample


def append_log(path, sample, size):
    handler = RotatingFileHandler(path, maxBytes=size, backupCount=7, encoding="utf-8")
    try:
        record = logging.LogRecord("hexproof-monitor", logging.INFO, "", 0,
                                   json.dumps(sample, separators=(",", ":")), (), None)
        handler.emit(record)
    finally:
        handler.close()


def run(port, directory, component="hub"):
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    latest = directory / "latest.json"
    try:
        previous = json.loads(latest.read_text())
        if "diagnostics" in previous:
            previous["diagnostics"] = diagnostics(previous["diagnostics"])
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        previous = None
    sample = collect(port, previous, component)
    append_log(directory / "samples.jsonl", sample, 4 * 1024 * 1024)
    if sample["alerts"] or sample.get("recovered"):
        append_log(directory / "alerts.jsonl", sample, 1024 * 1024)
    temporary = directory / "latest.json.tmp"
    temporary.write_text(json.dumps(sample, indent=2) + "\n")
    temporary.replace(latest)
    print(json.dumps({key: sample[key] for key in ("collectedAt", "live", "ready", "alerts")}))
    return sample


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, choices=(57320, 57323, 57324), required=True)
    parser.add_argument("--component", choices=("hub", "feedback"), default="hub")
    parser.add_argument("--state", type=Path)
    args = parser.parse_args()
    if (args.component == "feedback") != (args.port == 57324):
        parser.error("Feedback uses port 57324; hubs use port 57320 or 57323")
    directory = args.state or Path("/var/lib/hexproof-feedback-monitor" if args.component == "feedback"
                                   else "/var/lib/hexproof-monitor")
    run(args.port, directory, args.component)
