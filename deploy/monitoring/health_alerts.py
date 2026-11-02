#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Durable metadata-only health alerts for public TLS and certificate renewal.

One locked state file per host owns signal episodes, a capacity-bounded outbox
and transport status. Each event is persisted with its original eventId before
any network attempt; retries reuse that ID as the Idempotency-Key and send the
same payload. Only first failure, bounded escalation and recovery are emitted.
Alerts are evidence for the fixed native route, never commands or targets.
"""

import argparse
import errno
import fcntl
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import re
import socket
import ssl
import sys
import multiprocessing
import time
import urllib.error
import urllib.request
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tls_check  # noqa: E402


SCHEMA = 1
EVENT_SCHEMA = "hexproof.health-alert.v1"
OBSERVER_GROUP = "observer"
# Consecutive failed observations that trigger the bounded escalations: about
# 1h/6h/24h for the 5-minute TLS timer and 12h/24h/48h for 6-hour renewal.
ESCALATE = {"tls": (12, 72, 288), "renewal": (2, 4, 8)}
OUTBOX_LIMIT = 64
HISTORY_LIMIT = 32
INVOCATION_LIMIT = 64
MAX_STATE = 1024 * 1024
SIGNAL_LIMIT = 64
MAX_ATTEMPTS = 6
BASE_BACKOFF = 60
MAX_BACKOFF = 3600
DELIVERY_SECONDS = 20
REQUEST_SECONDS = 8
PER_RUN_LIMIT = 8
LOCK_SECONDS = 30
STALE_SECONDS = 900
MAX_RESPONSE = 64 * 1024
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
INVOCATION = re.compile(r"[0-9a-f]{32}")
SERVICE_RESULTS = {"success", "protocol", "timeout", "exit-code", "signal", "core-dump",
                   "watchdog", "start-limit-hit", "resources", "oom-kill"}


class AlertError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


utc = tls_check.utc
parse_utc = tls_check.parse_utc


def empty_state():
    return {"schemaVersion": SCHEMA, "sequence": 0, "signals": {}, "outbox": [], "history": [],
            "invocations": [], "latest": None,
            "transport": {"degraded": False, "consecutiveFailures": 0, "lastError": "", "lastErrorAt": None},
            "counters": {"droppedEvents": 0, "skippedAdmissions": 0, "exhausted": 0, "stateRecoveries": 0}}


def valid_state(state):
    try:
        if (not isinstance(state, dict) or set(state) != set(empty_state())
                or state["schemaVersion"] != SCHEMA or type(state["sequence"]) is not int
                or any(not isinstance(state[key], dict) for key in ("signals", "transport", "counters"))
                or any(not isinstance(state[key], list) for key in ("outbox", "history", "invocations"))
                or len(state["signals"]) > SIGNAL_LIMIT or len(state["outbox"]) > OUTBOX_LIMIT
                or len(state["history"]) > HISTORY_LIMIT or len(state["invocations"]) > INVOCATION_LIMIT
                or any(not INVOCATION.fullmatch(item) for item in state["invocations"])):
            return False
        for record in state["signals"].values():
            if (record["status"] not in ("ok", "failing")
                    or any(type(record[key]) is not int or record[key] < 0
                           for key in ("consecutiveFailures", "totalFailures", "escalations"))
                    or not isinstance(record["lastErrors"], dict)):
                return False
            for key in ("firstFailureAt", "lastFailureAt", "lastSuccessAt"):
                if record[key] is not None:
                    parse_utc(record[key])
            if record["status"] == "failing" and not UUID.fullmatch(record["episodeId"]):
                return False
        for entry in state["outbox"] + state["history"]:
            if (entry["status"] not in ("pending", "exhausted", "accepted", "skipped")
                    or type(entry["attempts"]) is not int or entry["attempts"] < 0
                    or not UUID.fullmatch(entry["event"]["eventId"])
                    or not UUID.fullmatch(entry["event"]["episodeId"])):
                return False
            parse_utc(entry["nextAttemptAt"])
        if (type(state["transport"]["degraded"]) is not bool
                or type(state["transport"]["consecutiveFailures"]) is not int
                or any(type(state["counters"][key]) is not int for key in empty_state()["counters"])):
            return False
        return True
    except (KeyError, TypeError, ValueError):
        return False


def fsync_directory(directory):
    fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def atomic_write(path, data):
    temporary = path.with_name(f"{path.name}.tmp-{os.getpid()}-{uuid.uuid4().hex[:8]}")
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise
    fsync_directory(path.parent)


class Store:
    """Exclusive process lock plus crash-safe state replacement."""

    def __init__(self, directory, lock_seconds=LOCK_SECONDS):
        self.directory = Path(directory)
        self.path = self.directory / "state.json"
        self.lock_seconds = lock_seconds
        self.fd = None

    def __enter__(self):
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.fd = os.open(self.directory / "lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        deadline = time.monotonic() + self.lock_seconds
        while True:
            try:
                fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError as error:
                if error.errno not in (errno.EAGAIN, errno.EACCES) or time.monotonic() >= deadline:
                    os.close(self.fd)
                    raise AlertError("lock_timeout") from None
                time.sleep(0.05)
        return self

    def __exit__(self, *unused):
        fcntl.flock(self.fd, fcntl.LOCK_UN)
        os.close(self.fd)

    def load(self, now):
        for leftover in self.directory.glob("state.json.tmp-*"):
            leftover.unlink(missing_ok=True)
        try:
            with self.path.open("rb") as stream:
                data = stream.read(MAX_STATE + 1)
            if len(data) <= MAX_STATE:
                state = json.loads(data)
                if valid_state(state):
                    return state
        except FileNotFoundError:
            return empty_state()
        except (OSError, ValueError, UnicodeDecodeError):
            pass
        # Do not discard unsent events or recreate episodes after corruption.
        # Leave the evidence in place and require explicit operator recovery.
        raise AlertError("state_corrupt")

    def save(self, state):
        data = (json.dumps(state, sort_keys=True, indent=1) + "\n").encode()
        if not valid_state(state) or len(data) > MAX_STATE:
            raise AlertError("state_capacity")
        atomic_write(self.path, data)


def emit(state, now, source, group, signal, kind, record, errors, endpoints=(), remaining=None):
    if len(state["outbox"]) >= OUTBOX_LIMIT:
        state["counters"]["droppedEvents"] += 1
        state["transport"].update(degraded=True, lastError="outbox_capacity", lastErrorAt=utc(now))
        return None
    state["sequence"] += 1
    event = {"schema": EVENT_SCHEMA, "eventId": str(uuid.uuid4()), "source": source,
             "serviceGroup": group, "signal": signal, "kind": kind, "episodeId": record["episodeId"],
             "sequence": state["sequence"], "occurredAt": utc(now),
             "firstFailureAt": record["firstFailureAt"], "consecutiveFailures": record["consecutiveFailures"],
             "totalFailures": record["totalFailures"], "lastSuccessAt": record["lastSuccessAt"],
             "errors": dict(sorted(errors.items())), "endpoints": sorted(endpoints)[:tls_check.MAX_ENDPOINTS],
             "minRemainingSeconds": remaining,
             "droppedEvents": state["counters"]["droppedEvents"],
             "stateRecoveries": state["counters"]["stateRecoveries"]}
    state["outbox"].append({"event": event, "status": "pending", "attempts": 0,
                            "nextAttemptAt": utc(now), "lastError": "", "runId": None})
    return event


def observe(state, now, source, group, signal, ok, errors=None, endpoints=(), remaining=None):
    """Advance one signal's episode and enqueue an event only on a transition."""
    if f"{group}/{signal}" not in state["signals"] and len(state["signals"]) >= SIGNAL_LIMIT:
        raise AlertError("state_capacity")
    record = state["signals"].setdefault(f"{group}/{signal}", {
        "status": "ok", "episodeId": None, "firstFailureAt": None, "lastFailureAt": None,
        "consecutiveFailures": 0, "totalFailures": 0, "lastSuccessAt": None, "escalations": 0,
        "lastErrors": {}, "lastRecovery": None})
    if ok:
        record["lastSuccessAt"] = utc(now)
        if record["status"] != "failing":
            return None
        event = emit(state, now, source, group, signal, "recovery", record, record["lastErrors"],
                     remaining=remaining)
        record["lastRecovery"] = {"episodeId": record["episodeId"], "failures": record["consecutiveFailures"],
                                  "recoveredAt": utc(now)}
        record.update(status="ok", episodeId=None, consecutiveFailures=0, escalations=0)
        return event
    record["totalFailures"] += 1
    record["lastFailureAt"] = utc(now)
    record["lastErrors"] = dict(errors or {"unavailable": 1})
    if record["status"] != "failing":
        record.update(status="failing", episodeId=str(uuid.uuid4()), firstFailureAt=utc(now),
                      consecutiveFailures=1, escalations=0)
        return emit(state, now, source, group, signal, "failure", record, record["lastErrors"], endpoints, remaining)
    record["consecutiveFailures"] += 1
    thresholds = ESCALATE[signal]
    if record["escalations"] < len(thresholds) and record["consecutiveFailures"] >= thresholds[record["escalations"]]:
        record["escalations"] += 1
        return emit(state, now, source, group, signal, "escalation", record, record["lastErrors"],
                    endpoints, remaining)
    return None


def observe_tls(state, now, source, evidence):
    groups = {}
    for row in evidence["endpoints"]:
        groups.setdefault(row["serviceGroup"], []).append(row)
    events = []
    for group, rows in sorted(groups.items()):
        failing = [row for row in rows if row["result"] != "pass"]
        errors = {}
        for row in failing:
            errors[row["error"]] = errors.get(row["error"], 0) + 1
        known = [row["remainingSeconds"] for row in rows if row["remainingSeconds"] is not None]
        events.append(observe(state, now, source, group, "tls", not failing, errors,
                              [row["id"] for row in failing], min(known) if known else None))
    # A healthy run also clears a previous observer/configuration failure.
    events.append(observe(state, now, source, OBSERVER_GROUP, "tls", True))
    return [event for event in events if event]


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def bounded(function, timeout):
    """Join/kill DNS and HTTP work so no transport continues after return."""
    context = multiprocessing.get_context("fork")
    receive, send = context.Pipe(duplex=False)

    def work():
        try:
            send.send(function())
        except Exception:
            send.send(("network", None))
        finally:
            send.close()

    worker = context.Process(target=work, daemon=True)
    worker.start()
    send.close()
    try:
        if receive.poll(timeout):
            try:
                return receive.recv()
            except EOFError:
                return "network", None
        return "timeout", None
    finally:
        if worker.is_alive():
            worker.kill()
        worker.join()
        receive.close()


def post(url, event, timeout):
    body = json.dumps(event, sort_keys=True, separators=(",", ":")).encode()
    request = urllib.request.Request(url, data=body, method="POST", headers={
        "Content-Type": "application/json", "Idempotency-Key": event["eventId"],
        "User-Agent": "hexproof-health-alerts/1"})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect(),
                                         urllib.request.HTTPSHandler(context=ssl.create_default_context()))

    def attempt():
        try:
            with opener.open(request, timeout=timeout) as response:
                data = response.read(MAX_RESPONSE + 1)
        except urllib.error.HTTPError as error:
            error.close()
            return ("http_5xx" if error.code >= 500 else "http_4xx" if error.code >= 400 else "http_redirect"), None
        except (TimeoutError, socket.timeout):
            return "timeout", None
        except urllib.error.URLError as error:
            return ("timeout" if isinstance(error.reason, (TimeoutError, socket.timeout)) else "network"), None
        except (OSError, ValueError):
            return "network", None
        try:
            reply = json.loads(data) if len(data) <= MAX_RESPONSE else None
        except (ValueError, UnicodeDecodeError):
            reply = None
        if (isinstance(reply, dict) and reply.get("status") in ("accepted", "skipped")
                and isinstance(reply.get("run_id"), str) and UUID.fullmatch(reply["run_id"])):
            return reply["status"], reply["run_id"]
        return "invalid_response", None

    return bounded(attempt, timeout + 1)


def read_capability(path):
    """Read the webhook capability from a protected file; never log it."""
    if path is None:
        raise AlertError("capability_unavailable")
    path = Path(path)
    credentials = os.environ.get("CREDENTIALS_DIRECTORY")
    allowed = 0o037 if credentials and path.parent == Path(credentials) else 0o077
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        raise AlertError("capability_unavailable") from None
    try:
        info = os.fstat(fd)
        if not (info.st_mode & 0o170000 == 0o100000) or info.st_mode & allowed or info.st_size > 2048:
            raise AlertError("capability_unprotected")
        url = os.read(fd, 2049).decode("ascii", "replace").strip()
    finally:
        os.close(fd)
    try:
        if not url.startswith("https://"):
            raise tls_check.ConfigError("invalid_origin")
        tls_check.origin(url, allow_path=True)
    except tls_check.ConfigError:
        raise AlertError("capability_invalid") from None
    return url


def default_capability():
    credentials = os.environ.get("CREDENTIALS_DIRECTORY")
    return Path(credentials) / "webhook-url" if credentials else None


def outstanding_transport(state):
    # Skipped admission and queue loss are sticky operator obligations. An
    # unrelated successful delivery cannot establish their reconciliation.
    return bool(state["counters"]["skippedAdmissions"] or state["counters"]["droppedEvents"]
                or any(entry["status"] == "exhausted" or entry.get("lastError")
                       for entry in state["outbox"]))


def deliver(store, state, capability, sender=post, clock=time.monotonic, wall=time.time,
            budget=DELIVERY_SECONDS, limit=PER_RUN_LIMIT):
    """Attempt due outbox events in order with bounded retries and backoff."""
    transport = state["transport"]
    due = [entry for entry in state["outbox"]
           if entry["status"] == "pending" and parse_utc(entry["nextAttemptAt"]) <= wall()]
    if not due:
        return 0
    try:
        url = read_capability(capability)
    except AlertError as error:
        transport.update(degraded=True, lastError=error.code, lastErrorAt=utc(wall()))
        return 0
    stop = clock() + budget
    sent = 0
    for entry in due:
        remaining = stop - clock()
        if sent >= limit or remaining < 1:
            break
        if entry["attempts"] >= MAX_ATTEMPTS:
            entry["status"] = "exhausted"
            transport["degraded"] = True
            state["counters"]["exhausted"] += 1
            store.save(state)
            continue
        sent += 1
        entry["attempts"] += 1
        entry["lastAttemptAt"] = utc(wall())
        store.save(state)  # Count the attempt before any network effect.
        outcome, run_id = sender(url, entry["event"], min(REQUEST_SECONDS, remaining))
        if outcome in ("accepted", "skipped"):
            entry.update(status=outcome, runId=run_id, lastError="", completedAt=utc(wall()))
            state["outbox"].remove(entry)
            state["history"] = (state["history"] + [entry])[-HISTORY_LIMIT:]
            transport.update(degraded=outstanding_transport(state) or outcome == "skipped", consecutiveFailures=0,
                             lastError="admission_skipped" if outcome == "skipped" else "")
            if outcome == "skipped":
                # This is transport acceptance, not native task admission.
                # The supported issue fallback still requires qualification.
                state["counters"]["skippedAdmissions"] += 1
        else:
            entry["lastError"] = outcome
            transport.update(consecutiveFailures=transport["consecutiveFailures"] + 1,
                             lastError=outcome, lastErrorAt=utc(wall()))
            if entry["attempts"] >= MAX_ATTEMPTS:
                entry["status"] = "exhausted"
                transport["degraded"] = True
                state["counters"]["exhausted"] += 1
            else:
                delay = min(BASE_BACKOFF * 2 ** (entry["attempts"] - 1), MAX_BACKOFF)
                entry["nextAttemptAt"] = utc(wall() + delay)
        transport["degraded"] = transport["degraded"] or outstanding_transport(state)
        store.save(state)
    return sent


def redrive(state, now):
    """Operator recovery: retry exhausted events with their original identity."""
    count = 0
    for entry in state["outbox"]:
        if entry["status"] == "exhausted":
            entry.update(status="pending", attempts=0, nextAttemptAt=utc(now))
            count += 1
    return count


def append_log(path, record):
    handler = RotatingFileHandler(path, maxBytes=1024 * 1024, backupCount=4, encoding="utf-8")
    try:
        handler.emit(logging.LogRecord("hexproof-health", logging.INFO, "", 0,
                                       json.dumps(record, sort_keys=True, separators=(",", ":")), (), None))
    finally:
        handler.close()


def summary(state):
    return {"pending": sum(entry["status"] == "pending" for entry in state["outbox"]),
            "exhausted": sum(entry["status"] == "exhausted" for entry in state["outbox"]),
            "transportDegraded": state["transport"]["degraded"] or outstanding_transport(state),
            "skippedAdmissions": state["counters"]["skippedAdmissions"],
            "nativeAdmission": "unverified",
            "failing": sorted(key for key, record in state["signals"].items() if record["status"] == "failing")}


def run_tls(args, wall=time.time, collector=tls_check.collect):
    with Store(args.state) as store:
        now = wall()
        try:
            evidence = collector(tls_check.read_inventory(args.config, args.bootstrap))
            observer_error = None
        except (tls_check.ConfigError, tls_check.ProbeError) as error:
            evidence, observer_error = None, error.code
        except (OSError, ssl.SSLError):
            evidence, observer_error = None, "collector_failed"
        state = store.load(now)
        if evidence is None:
            observe(state, now, args.source, OBSERVER_GROUP, "tls", False, {observer_error: 1})
            sample = {"collectedAt": utc(now), "result": "fail", "observerError": observer_error}
        else:
            observe_tls(state, now, args.source, evidence)
            sample = {key: evidence[key] for key in ("collectedAt", "completedAt", "result", "counts",
                                                     "inventorySha256")}
            append_log(Path(args.state) / "samples.jsonl", evidence)
        state["latest"] = sample
        store.save(state)
        atomic_write(Path(args.state) / "latest.json", (json.dumps(sample, sort_keys=True) + "\n").encode())
        deliver(store, state, args.webhook_file)
        store.save(state)
        print(json.dumps({**sample, **summary(state)}, sort_keys=True))
    return 0 if sample["result"] == "pass" else 2


def renewal_outcome(environ):
    invocation = environ.get("INVOCATION_ID", "")
    if not INVOCATION.fullmatch(invocation):
        raise AlertError("invalid_invocation")
    result = environ.get("SERVICE_RESULT", "")
    ok = result == "success" and environ.get("EXIT_CODE") == "exited" and environ.get("EXIT_STATUS") == "0"
    return invocation, ok, ("" if ok else result if result in SERVICE_RESULTS - {"success"} else "exit-code")


def run_renewal(args, environ=os.environ, wall=time.time, sender=post):
    """ExecStopPost hook: record each real invocation once; never alter its result."""
    try:
        config = json.loads(Path(args.config).read_text(encoding="utf-8"))
        if not isinstance(config, dict) or config.get("schemaVersion") != SCHEMA:
            raise AlertError("invalid_config")
        group = tls_check.sanitized_id(config.get("serviceGroup"))
        invocation, ok, failure = renewal_outcome(environ)
        now = wall()
        with Store(args.state) as store:
            state = store.load(now)
            if invocation in state["invocations"]:
                print(json.dumps({"invocation": "duplicate"}))
                return 0
            state["invocations"] = (state["invocations"] + [invocation])[-INVOCATION_LIMIT:]
            observe(state, now, args.source, group, "renewal", ok, {"renewal_" + failure.replace("-", "_"): 1})
            state["latest"] = {"collectedAt": utc(now), "result": "pass" if ok else "fail",
                               "renewal": "success" if ok else failure}
            store.save(state)
            append_log(Path(args.state) / "renewals.jsonl", state["latest"])
            # A separate bounded sender timer owns transport. The certbot hook
            # only records the real invocation and never waits on cloud DNS.
            print(json.dumps({**state["latest"], **summary(state)}, sort_keys=True))
    except (AlertError, tls_check.ConfigError) as error:
        print(json.dumps({"error": error.code}))
    except (OSError, ValueError, UnicodeDecodeError):
        print(json.dumps({"error": "renewal_hook_failed"}))
    return 0


def run_deliver(args, wall=time.time):
    with Store(args.state) as store:
        state = store.load(wall())
        redriven = redrive(state, wall()) if args.redrive_exhausted else 0
        store.save(state)
        sent = deliver(store, state, args.webhook_file)
        store.save(state)
        print(json.dumps({"attempted": sent, "redriven": redriven, **summary(state)}, sort_keys=True))
    return 0


def run_status(args, wall=time.time):
    """Report health without contacting the network; stale samples are unhealthy."""
    with Store(args.state) as store:
        state = store.load(wall())
    latest = state.get("latest") or {}
    try:
        age = int(wall() - parse_utc(latest.get("collectedAt")))
    except ValueError:
        age = None
    stale = age is None or age < 0 or age > args.max_age
    report = {**summary(state), "latest": latest, "ageSeconds": age, "stale": stale,
              "counters": state["counters"]}
    report["healthy"] = (not stale and latest.get("result") == "pass" and not report["failing"]
                         and not report["transportDegraded"] and not report["exhausted"]
                         and not report["pending"] and not report["skippedAdmissions"]
                         and not state["counters"]["droppedEvents"])
    print(json.dumps(report, sort_keys=True))
    return 0 if report["healthy"] else 3


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("tls", "renewal", "deliver", "status"):
        command = commands.add_parser(name)
        command.add_argument("--state", required=True)
        if name in ("tls", "renewal", "deliver"):
            command.add_argument("--webhook-file", type=Path, default=default_capability())
        if name in ("tls", "renewal"):
            command.add_argument("--source", required=True, type=tls_check.sanitized_id)
            command.add_argument("--config", required=True)
    commands.choices["tls"].add_argument("--bootstrap", required=True)
    commands.choices["deliver"].add_argument("--redrive-exhausted", action="store_true")
    commands.choices["status"].add_argument("--max-age", type=int, default=STALE_SECONDS)
    args = parser.parse_args(argv)
    try:
        return {"tls": run_tls, "renewal": run_renewal, "deliver": run_deliver, "status": run_status}[args.command](args)
    except (OSError, ValueError, KeyError, TypeError, ssl.SSLError):
        print(json.dumps({"error": "health_operation_failed"}), file=sys.stderr)
        return 1
    except AlertError as error:
        print(json.dumps({"error": error.code}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
