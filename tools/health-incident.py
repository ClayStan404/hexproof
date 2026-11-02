#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Reconcile health-alert Autopilot runs into canonical maintenance issues.

Every entry point runs on the fixed Debian operator host under one lock and
journal. Runs are read through the supported `multica autopilot runs` pages;
accepted, skipped and failed webhook runs can be reconciled from their
original payload into an issue fallback with preserved provenance. Missing native
payloads remain unresolved; protected original bytes can be imported explicitly.
This does not replay webhook admission; isolated native qualification remains required. An incident issue is
created in backlog with an exact marker, indexed by metadata, read back and
only then admitted to the coordinator. Uncertain writes are reconciled by
paginated marker/metadata readback before any retry. Recovery observations
never close an issue or imply that maintenance is complete.
"""

import argparse
from datetime import datetime, timezone
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import time
import uuid


SCHEMA = 1
EVENT_SCHEMA = "hexproof.health-alert.v1"
METADATA_KEY = "hexproofHealthIncident"
OBSERVER_GROUP = "observer"
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
ID = re.compile(r"[a-z0-9][a-z0-9-]{0,62}")
ERROR = re.compile(r"[a-z0-9_]{1,40}")
ERRORS = {"dns_failure", "dns_timeout", "connect_failure", "timeout", "untrusted", "name_mismatch",
          "expired", "not_yet_valid", "near_expiry", "tls_failure", "deadline_exceeded", "collector_failed",
          "invalid_config", "invalid_bootstrap", "invalid_origin", "invalid_id", "invalid_endpoint",
          "empty_inventory", "duplicate_id", "duplicate_bootstrap_id", "too_many_endpoints",
          "bootstrap_digest_mismatch", "incomplete_coverage", "oversized_input", "unreadable_input",
          "invalid_threshold", "output_limit", "unavailable"} | {
          "renewal_" + item for item in ("protocol", "timeout", "exit_code", "signal", "core_dump",
              "watchdog", "start_limit_hit", "resources", "oom_kill")}
TIME = re.compile(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ")
EVENT_FIELDS = {"schema", "eventId", "source", "serviceGroup", "signal", "kind", "episodeId", "sequence",
                "occurredAt", "firstFailureAt", "consecutiveFailures", "totalFailures", "lastSuccessAt",
                "errors", "endpoints", "minRemainingSeconds", "droppedEvents", "stateRecoveries"}
ADMITTED = {"issue_created", "running", "completed", "succeeded", "success"}
NOT_ADMITTED = {"skipped", "failed"}
CLOSED = {"done", "cancelled"}
RUN_PAGE = 50
RUN_PAGES = 10
ISSUE_PAGE = 100
ISSUE_PAGES = 20
MAX_JOURNAL = 2 * 1024 * 1024
MAX_INCIDENTS = 128
MAX_EPISODES = 32
MAX_RUN_SECONDS = 120
LOCK_SECONDS = 120
JOURNAL_LIMIT = 1024
CLOSED_INCIDENT_LIMIT = 64


class IncidentError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


def utc(seconds):
    return datetime.fromtimestamp(seconds, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def default_operations():
    explicit = os.environ.get("HEXPROOF_OPERATIONS_FILE")
    base = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    return Path(explicit) if explicit else base / "hexproof-operator/multica-operations.json"


def default_config():
    explicit = os.environ.get("HEXPROOF_HEALTH_INCIDENT_FILE")
    base = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    return Path(explicit) if explicit else base / "hexproof-operator/health-incident.json"


def load_trust(operations_path, config_path):
    """Fixed project/coordinator from the trusted manifest; routes from private config."""
    try:
        operations = json.loads(Path(operations_path).read_text(encoding="utf-8"))
        config = json.loads(Path(config_path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise IncidentError("unreadable_configuration") from None
    if not isinstance(config, dict):
        raise IncidentError("invalid_configuration")
    native = operations.get("native") if isinstance(operations, dict) else None
    if (not isinstance(native, dict) or operations.get("activation") != "active"
            or not UUID.fullmatch(str(native.get("projectId", "")))
            or not UUID.fullmatch(str(native.get("coordinatorId", "")))):
        raise IncidentError("inactive_operations")
    triggers = config.get("triggers") if isinstance(config, dict) else None
    groups = config.get("serviceGroups") if isinstance(config, dict) else None
    directory = config.get("stateDirectory") if isinstance(config, dict) else None
    if (config.get("schemaVersion") != SCHEMA or not UUID.fullmatch(str(config.get("autopilotId", "")))
            or not isinstance(triggers, dict) or not triggers
            or not all(UUID.fullmatch(str(key)) and isinstance(value, str) and ID.fullmatch(value)
                       for key, value in triggers.items())
            or not isinstance(groups, list) or not groups
            or not all(isinstance(group, str) and ID.fullmatch(group) for group in groups)
            or not isinstance(directory, str) or not Path(directory).is_absolute()):
        raise IncidentError("invalid_configuration")
    return {"projectId": native["projectId"], "coordinatorId": native["coordinatorId"],
            "autopilotId": config["autopilotId"], "triggers": dict(triggers),
            "serviceGroups": set(groups) | {OBSERVER_GROUP}, "stateDirectory": Path(directory)}


def multica(*args, stdin=None, cwd=None, timeout=30):
    """Run one CLI call; JSON stdout only, never merged with stderr."""
    try:
        completed = subprocess.run(["multica", *args, "--output", "json"], capture_output=True, text=True,
                                   timeout=timeout, input=stdin, cwd=cwd)
    except (OSError, subprocess.SubprocessError):
        return None, None
    if len(completed.stdout) > MAX_JOURNAL:
        return None, None
    try:
        return completed.returncode, json.loads(completed.stdout) if completed.stdout.strip() else None
    except ValueError:
        return completed.returncode, None


def validate_event(payload, source):
    if isinstance(payload, str):
        try:
            payload = json.loads(payload)
        except ValueError:
            return None
    if isinstance(payload, dict) and set(payload) <= {"body", "payload"} and len(payload) == 1:
        payload = next(iter(payload.values()))
    if not isinstance(payload, dict) or set(payload) != EVENT_FIELDS:
        return None
    integers = ("sequence", "consecutiveFailures", "totalFailures", "droppedEvents", "stateRecoveries")
    try:
        valid = (payload["schema"] == EVENT_SCHEMA and payload["source"] == source
                 and UUID.fullmatch(payload["eventId"]) and UUID.fullmatch(payload["episodeId"])
                 and ID.fullmatch(payload["serviceGroup"]) and payload["signal"] in ("tls", "renewal")
                 and payload["kind"] in ("failure", "escalation", "recovery")
                 and all(type(payload[key]) is int and payload[key] >= 0 for key in integers)
                 and TIME.fullmatch(payload["occurredAt"])
                 and ID.fullmatch(payload["source"])
                 and all(payload[key] is None or TIME.fullmatch(payload[key])
                         for key in ("firstFailureAt", "lastSuccessAt"))
                 and isinstance(payload["errors"], dict) and len(payload["errors"]) <= 16
                 and all(key in ERRORS and type(value) is int and 0 <= value <= 2**53 - 1
                         for key, value in payload["errors"].items())
                 and isinstance(payload["endpoints"], list) and len(payload["endpoints"]) <= 32
                 and all(isinstance(item, str) and ID.fullmatch(item) for item in payload["endpoints"])
                 and (payload["minRemainingSeconds"] is None or type(payload["minRemainingSeconds"]) is int))
    except TypeError:
        return None
    if valid:
        try:
            for key in ("occurredAt", "firstFailureAt", "lastSuccessAt"):
                if payload[key] is not None:
                    datetime.strptime(payload[key], "%Y-%m-%dT%H:%M:%SZ")
        except (ValueError, TypeError):
            valid = False
    return payload if valid else None


def empty_journal():
    return {"schemaVersion": SCHEMA, "runs": {}, "events": {}, "incidents": {}, "open": {},
            "discovery": None}


class Reconciler:
    def __init__(self, trust, runner=multica, wall=time.time):
        self.trust = trust
        self.deadline = time.monotonic() + MAX_RUN_SECONDS
        def bounded_runner(*args):
            remaining = self.deadline - time.monotonic()
            if remaining <= 0:
                raise IncidentError("reconciliation_deadline")
            if runner is multica:
                return runner(*args, cwd=self.directory, timeout=min(30, remaining))
            return runner(*args)
        self.runner = bounded_runner
        self.wall = wall
        self.directory = trust["stateDirectory"]
        self.path = self.directory / "journal.json"
        self.report = {"processedRuns": 0, "processedOriginalEvents": 0, "duplicates": 0, "invalid": 0, "unmatchedRecoveries": 0,
                       "incidents": {}}

    # Journal and lock -----------------------------------------------------

    def lock(self):
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd = os.open(self.directory / "lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        deadline = time.monotonic() + LOCK_SECONDS
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return fd
            except OSError as error:
                if error.errno not in (errno.EAGAIN, errno.EACCES) or time.monotonic() >= deadline:
                    os.close(fd)
                    raise IncidentError("lock_timeout") from None
                time.sleep(0.1)

    def load(self):
        for leftover in self.directory.glob("description-*.md"):
            leftover.unlink(missing_ok=True)
        try:
            with self.path.open("rb") as stream:
                data = stream.read(MAX_JOURNAL + 1)
            if len(data) > MAX_JOURNAL:
                raise IncidentError("journal_capacity")
            journal = json.loads(data)
        except FileNotFoundError:
            return empty_journal()
        except (OSError, ValueError):
            # Fail closed: a damaged journal could otherwise create duplicates.
            raise IncidentError("journal_corrupt") from None
        if (not isinstance(journal, dict) or journal.get("schemaVersion") != SCHEMA
                or any(not isinstance(journal.get(key), dict) for key in ("runs", "events", "incidents", "open"))
                or any(not isinstance(value, dict) for key in ("runs", "events", "incidents")
                       for value in journal[key].values())
                or any(value not in journal["incidents"] for value in journal["open"].values())):
            raise IncidentError("journal_corrupt")
        boundary = journal.get("discovery")
        if boundary is not None and (not isinstance(boundary, dict)
                or not UUID.fullmatch(str(boundary.get("runId", "")))
                or not TIME.fullmatch(str(boundary.get("triggeredAt", "")))):
            raise IncidentError("journal_corrupt")
        for record in journal["runs"].values():
            if record.get("outcome") == "invalid_payload":
                record.setdefault("unresolved", "original_payload_unavailable")
        return journal

    def save(self, journal):
        for name in ("runs", "events"):
            if len(journal[name]) > JOURNAL_LIMIT:
                removable = sorted((key for key, item in journal[name].items()
                                    if not item.get("unresolved") and not (
                                        name == "events" and item.get("kind") == "recovery"
                                        and item.get("marker") is None)),
                                   key=lambda key: journal[name][key].get("at", ""))
                for key in removable[:len(journal[name]) - JOURNAL_LIMIT]:
                    del journal[name][key]
                if len(journal[name]) > JOURNAL_LIMIT:
                    raise IncidentError("journal_capacity")
        closed = [marker for marker, item in journal["incidents"].items() if item.get("closed")]
        for marker in sorted(closed, key=lambda key: journal["incidents"][key].get("lastEventAt", ""))[
                :max(0, len(closed) - CLOSED_INCIDENT_LIMIT)]:
            del journal["incidents"][marker]
        data = json.dumps(journal, sort_keys=True, indent=1).encode()
        if len(data) > MAX_JOURNAL or len(journal["incidents"]) > MAX_INCIDENTS:
            raise IncidentError("journal_capacity")
        temporary = self.path.with_name(f"journal.json.tmp-{os.getpid()}")
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(journal, stream, sort_keys=True, indent=1)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, self.path)
        directory_fd = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)

    # Native reads ---------------------------------------------------------

    def runs(self, journal):
        """Read newest-first pages through a previously proved coverage boundary.

        A cursor is committed only after the entire discovered prefix is saved.
        Legacy journals get one bounded migration scan of retained known history;
        unknown history beyond the normal window still fails closed.
        """
        found = []
        boundary = journal.get("discovery")
        previous_time = None
        seen = set()
        pages = RUN_PAGES if boundary or not journal["runs"] else (JOURNAL_LIMIT + RUN_PAGE - 1) // RUN_PAGE
        for page in range(pages):
            code, reply = self.runner("autopilot", "runs", self.trust["autopilotId"], "--limit", str(RUN_PAGE),
                                      "--offset", str(page * RUN_PAGE))
            if code != 0 or not isinstance(reply, dict) or not isinstance(reply.get("runs"), list):
                raise IncidentError("runs_unavailable")
            rows = reply["runs"]
            if len(rows) > RUN_PAGE:
                raise IncidentError("runs_unavailable")
            for run in rows:
                if (not isinstance(run, dict) or not UUID.fullmatch(str(run.get("id", "")))
                        or not TIME.fullmatch(str(run.get("triggered_at", "")))):
                    raise IncidentError("runs_order_unproven")
                at = run["triggered_at"]
                if (previous_time is not None and at > previous_time) or run["id"] in seen:
                    raise IncidentError("runs_order_unproven")
                previous_time = at
                seen.add(run["id"])
                if page >= RUN_PAGES and run["id"] not in journal["runs"]:
                    raise IncidentError("run_pagination_limit")
            found += rows
            reached = boundary is not None and any(run["id"] == boundary["runId"]
                and run["triggered_at"] == boundary["triggeredAt"] for run in rows)
            if reached:
                return found
            if len(rows) < RUN_PAGE or reply.get("total") == len(found):
                if boundary is not None:
                    raise IncidentError("run_boundary_missing")
                return found
        raise IncidentError("run_pagination_limit")

    def find_marker(self, marker):
        """Return the issue carrying this exact marker, False if absent, None if unproven."""
        line = marker_line(marker)
        matches = []
        for page in range(ISSUE_PAGES):
            code, reply = self.runner("issue", "list", "--project", self.trust["projectId"], "--limit",
                                      str(ISSUE_PAGE), "--offset", str(page * ISSUE_PAGE),
                                      "--fields", "id,description,metadata,created_at")
            if code != 0 or not isinstance(reply, dict) or not isinstance(reply.get("issues"), list):
                return None
            for issue in reply["issues"]:
                metadata = issue.get("metadata") if isinstance(issue.get("metadata"), dict) else {}
                try:
                    indexed = json.loads(metadata.get(METADATA_KEY, "null"))
                except (ValueError, TypeError):
                    indexed = None
                indexed = isinstance(indexed, dict) and indexed.get("marker") == marker
                if line in str(issue.get("description") or "").splitlines() or indexed:
                    matches.append(issue)
            if not reply.get("has_more"):
                break
        else:
            return None
        if not matches:
            return False
        if len(matches) != 1:
            raise IncidentError("duplicate_incident_marker")
        return matches[0]["id"] if UUID.fullmatch(str(matches[0].get("id", ""))) else None

    def issue(self, issue_id):
        code, reply = self.runner("issue", "get", issue_id)
        return reply if code == 0 and isinstance(reply, dict) and reply.get("id") == issue_id else None

    # Incident lifecycle ---------------------------------------------------

    def open_incident(self, journal, group):
        marker = journal["open"].get(group)
        if not marker:
            return None
        incident = journal["incidents"][marker]
        if incident.get("issueId"):
            issue = self.issue(incident["issueId"])
            if issue is None:
                raise IncidentError("incident_unreadable")
            if issue.get("status") in CLOSED:
                # Maintenance closed this incident; a later failure is new work.
                incident["closed"] = True
                del journal["open"][group]
                return None
        return marker

    def advance(self, journal, marker):
        incident = journal["incidents"][marker]
        now = self.wall()
        if incident["phase"] == "uncertain":
            found = self.find_marker(marker)
            if found:
                incident.update(issueId=found, phase="created")
            # An absent marker cannot prove an in-flight create failed.
            # Remain uncertain; never issue another create automatically.
            self.save(journal)
        if incident["phase"] == "pending":
            existing = self.find_marker(marker)
            if existing is None:
                raise IncidentError("incident_discovery_incomplete")
            if existing:
                incident.update(issueId=existing, phase="created")
                self.save(journal)
        if incident["phase"] == "pending":
            incident.update(phase="uncertain", attemptAt=now, attempts=incident.get("attempts", 0) + 1)
            self.save(journal)  # Record the intent before the uncertain write.
            description = self.directory / f"description-{uuid.uuid4().hex}.md"
            description.write_text(describe(marker, incident), encoding="utf-8")
            try:
                code, reply = self.runner("issue", "create", "--title", title(incident), "--description-file",
                                          str(description), "--project",
                                          self.trust["projectId"], "--status", "backlog")
            finally:
                description.unlink(missing_ok=True)
            if code == 0 and isinstance(reply, dict) and UUID.fullmatch(str(reply.get("id", ""))):
                incident.update(issueId=reply["id"], phase="created")
            self.save(journal)
        if incident["phase"] in ("created", "indexed", "admitted") and (
                incident["phase"] == "created" or incident.get("metadataDirty")):
            value = metadata_value(marker, incident)
            code, reply = self.runner("issue", "metadata", "get", incident["issueId"], "--key", METADATA_KEY)
            stored = reply.get("value") if isinstance(reply, dict) else reply
            if code != 0 or stored != value:
                self.runner("issue", "metadata", "set", incident["issueId"], "--key", METADATA_KEY,
                            "--value", value, "--type", "string")
            code, reply = self.runner("issue", "metadata", "get", incident["issueId"], "--key", METADATA_KEY)
            stored = reply.get("value") if isinstance(reply, dict) else reply
            if code == 0 and stored == value:
                incident["metadataDirty"] = False
                if incident["phase"] == "created":
                    incident["phase"] = "indexed"
            self.save(journal)
        if incident["phase"] == "indexed":
            issue = self.issue(incident["issueId"])
            if issue is not None and issue.get("status") == "backlog":
                self.runner("issue", "update", incident["issueId"], "--status", "todo",
                            "--assignee-id", self.trust["coordinatorId"])
                issue = self.issue(incident["issueId"])
            if (issue is not None and issue.get("assignee_id") == self.trust["coordinatorId"]
                    and issue.get("status") != "backlog"):
                incident["phase"] = "admission_pending"
            self.save(journal)
        if incident["phase"] == "admission_pending":
            code, tasks = self.runner("issue", "runs", incident["issueId"])
            # Native task association, not status alone, establishes admission.
            if code == 0 and isinstance(tasks, list):
                linked = [task for task in tasks if task.get("agent_id") == self.trust["coordinatorId"]
                          and UUID.fullmatch(str(task.get("id", task.get("task_id", ""))))]
                if linked:
                    task = linked[0]
                    incident.update(phase="admitted", maintenanceTaskId=task.get("task_id") or task.get("id"),
                                    maintenanceTaskStatus=task.get("status"), metadataDirty=True)
                    value = metadata_value(marker, incident)
                    self.runner("issue", "metadata", "set", incident["issueId"], "--key", METADATA_KEY,
                                "--value", value, "--type", "string")
                    code, stored = self.runner("issue", "metadata", "get", incident["issueId"], "--key", METADATA_KEY)
                    if code == 0 and stored == value:
                        incident["metadataDirty"] = False
            self.save(journal)
        self.report["incidents"][marker] = {"serviceGroup": incident["serviceGroup"],
                                            "phase": "metadata_pending" if incident["phase"] == "admitted" and incident.get("metadataDirty") else incident["phase"],
                                            "issueId": incident.get("issueId")}

    def attach(self, journal, marker, run, event, origin, original_bytes=None, count=True):
        incident = journal["incidents"][marker]
        if run.get("id") and run["id"] not in incident["runIds"]:
            incident["runIds"] = (incident["runIds"] + [run["id"]])[-16:]
        provenance = {"event": event, "webhookRunId": run.get("id"),
                      "originalTaskId": run.get("task_id"), "triggerId": run["trigger_id"],
                      "nativeStatus": run["status"], "payloadOrigin": origin}
        if original_bytes is not None:
            provenance["originalBytesSha256"] = hashlib.sha256(original_bytes.encode()).hexdigest()
        incident["provenance"] = provenance
        if ("firstProvenance" not in incident
                or incident["firstProvenance"]["event"]["eventId"] == event["eventId"]):
            incident["firstProvenance"] = provenance
        incident.update(eventCount=incident["eventCount"] + int(count), lastEventId=event["eventId"],
                        lastEventAt=max(incident.get("lastEventAt", ""), event["occurredAt"]),
                        lastRunId=run.get("id"), metadataDirty=True)

    def process(self, journal, run, event, origin="native_payload", original_bytes=None):
        run = {key: run.get(key) for key in ("id", "source", "trigger_id", "status", "task_id", "triggered_at")}
        admission = "admitted" if run.get("status") in ADMITTED else "not_admitted" if run.get("status") in NOT_ADMITTED else "unverified"
        record = {"eventId": event["eventId"], "admission": admission, "originalTaskId": run.get("task_id"),
                  "nativeRun": run, "at": utc(self.wall()), "marker": None}
        original_run = journal["runs"].get(run.get("id"), {})
        if original_run.get("eventId") and original_run["eventId"] != event["eventId"]:
            raise IncidentError("run_identity_conflict")
        if admission == "unverified" and run.get("id"):
            record["unresolved"] = "original_admission_unverified"
        previous = journal["events"].get(event["eventId"])
        if previous:
            if previous["payload"] != event or previous["triggerId"] != run["trigger_id"]:
                raise IncidentError("event_identity_conflict")
            if (original_bytes is not None and previous.get("originalBytes") is not None
                    and previous["originalBytes"] != original_bytes):
                raise IncidentError("event_identity_conflict")
            if previous.get("runId") and run.get("id") and previous["runId"] != run["id"]:
                # Preserve multiple native delivery records without changing the first association.
                if origin == "operator_original":
                    raise IncidentError("run_identity_conflict")
            record.update(outcome="duplicate_event", marker=previous.get("marker"))
            # A supported import can bind previously unobserved ingress without new incident work.
            if origin == "operator_original":
                previous.update(originalBytes=original_bytes, origin=origin)
                if run.get("id"):
                    previous.update(runId=run["id"], nativeRun=run, unresolved=record.get("unresolved"))
                if record["marker"]:
                    self.attach(journal, record["marker"], previous.get("nativeRun", run), event,
                                origin, original_bytes, count=False)
            if run.get("id"):
                journal["runs"][run["id"]] = record
            self.report["duplicates"] += 1
            return record["marker"]
        group = event["serviceGroup"]
        marker = self.open_incident(journal, group)
        closed_episode = next((key for key, item in journal["incidents"].items()
                               if item.get("closed") and item["serviceGroup"] == group
                               and event["episodeId"] in item["episodes"]), None)
        if closed_episode:
            record.update(outcome="closed_episode_observation", marker=closed_episode)
        elif event["kind"] == "recovery":
            incident = journal["incidents"].get(marker) if marker else None
            episode = incident["episodes"].get(event["episodeId"]) if incident else None
            if episode is None or episode["source"] != event["source"] or episode["signal"] != event["signal"]:
                record["outcome"] = "recovery_unmatched"
                self.report["unmatchedRecoveries"] += 1
            elif event["sequence"] <= episode["lastSequence"]:
                record.update(outcome="stale_recovery", marker=marker)
            else:
                episode.update(status="recovered", lastSequence=event["sequence"])
                record.update(outcome="recovery_recorded", marker=marker)
        else:
            if marker is None:
                if len(journal["incidents"]) >= MAX_INCIDENTS:
                    raise IncidentError("journal_capacity")
                marker = f"hexproof-health-incident:{group}:{event['eventId']}"
                journal["incidents"][marker] = {"serviceGroup": group, "phase": "pending", "issueId": None,
                                                "createdAt": utc(self.wall()), "episodes": {}, "runIds": [],
                                                "eventCount": 0, "firstEventAt": event["occurredAt"]}
                journal["open"][group] = marker
            if (event["episodeId"] not in journal["incidents"][marker]["episodes"]
                    and len(journal["incidents"][marker]["episodes"]) >= MAX_EPISODES):
                raise IncidentError("episode_capacity")
            episode = journal["incidents"][marker]["episodes"].setdefault(event["episodeId"], {
                "signal": event["signal"], "source": event["source"], "status": "failing", "lastSequence": 0})
            if episode["source"] != event["source"] or episode["signal"] != event["signal"]:
                raise IncidentError("episode_identity_conflict")
            if event["sequence"] > episode["lastSequence"] and episode["status"] != "recovered":
                episode["lastSequence"] = event["sequence"]
            record.update(outcome="incident", marker=marker)
        if record["marker"] and not closed_episode:
            self.attach(journal, record["marker"], run, event, origin, original_bytes)
        stored = {"runId": run.get("id"), "marker": record["marker"], "kind": event["kind"],
                  "payload": event, "triggerId": run["trigger_id"], "nativeRun": run,
                  "origin": origin, "at": record["at"]}
        if original_bytes is not None:
            stored["originalBytes"] = original_bytes
        if run.get("id") is None:
            stored["unresolved"] = "original_run_unobserved"
        elif record.get("unresolved"):
            stored["unresolved"] = record["unresolved"]
        journal["events"][event["eventId"]] = stored
        if run.get("id"):
            journal["runs"][run["id"]] = record
        self.report["processedRuns" if run.get("id") else "processedOriginalEvents"] += 1
        if event["kind"] != "recovery" and not closed_episode:
            # Reassociate retained recovery even after restart. Sequence/source/signal
            # scope this to its original episode, so newer faults remain failing.
            for prior in journal["events"].values():
                recovery = prior["payload"]
                if (prior["marker"] is None and recovery["kind"] == "recovery"
                        and all(recovery[key] == event[key] for key in
                                ("serviceGroup", "source", "signal", "episodeId"))):
                    if recovery["sequence"] > episode["lastSequence"]:
                        episode.update(status="recovered", lastSequence=recovery["sequence"])
                    prior["marker"] = marker
                    prior_run = prior.get("nativeRun")
                    if prior_run is None:
                        # Migration of retained schema-1 unmatched recovery.
                        old = journal["runs"].get(prior["runId"], {})
                        prior_run = {"id": prior["runId"], "trigger_id": prior["triggerId"],
                                     "status": "unverified", "task_id": old.get("originalTaskId")}
                    self.attach(journal, marker, prior_run, recovery, prior.get("origin", "native_payload"),
                                prior.get("originalBytes"))
                    if prior.get("runId") in journal["runs"]:
                        journal["runs"][prior["runId"]].update(marker=marker, outcome="recovery_recorded")
        return record["marker"]

    def original_event(self, path, trigger_id):
        # Only a protected staging directory under the fixed journal root is accepted.
        # The operator copies the durable original bytes here; no payload comes from a prompt.
        directory = self.directory / "original-events"
        if trigger_id not in self.trust["triggers"] or Path(path).parent.resolve() != directory.resolve():
            raise IncidentError("invalid_original_event_path")
        for item in (directory, Path(path)):
            info = item.lstat()
            expected_type = stat.S_ISDIR if item == directory else stat.S_ISREG
            if (not expected_type(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077):
                raise IncidentError("unprotected_original_event")
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, "rb") as stream:
            raw = stream.read(65537)
        if len(raw) > 65536:
            raise IncidentError("original_event_capacity")
        try:
            original = raw.decode("utf-8")
            event = validate_event(json.loads(original), self.trust["triggers"][trigger_id])
        except (ValueError, UnicodeDecodeError):
            event = None
        if event is None or event["serviceGroup"] not in self.trust["serviceGroups"]:
            raise IncidentError("invalid_original_event")
        return event, original

    def obligations(self, journal):
        unresolved = [{"runId": key, "phase": value["unresolved"]}
                      for key, value in journal["runs"].items() if value.get("unresolved")]
        for key, value in journal["events"].items():
            if value.get("unresolved"):
                unresolved.append({"eventId": key, "phase": value["unresolved"]})
            if value["kind"] == "recovery" and value.get("marker") is None:
                unresolved.append({"eventId": key, "phase": "recovery_unmatched"})
        return unresolved

    def reconcile(self, original_file=None, trigger_id=None, run_id=None):
        fd = self.lock()
        try:
            journal = self.load()
            original = self.original_event(original_file, trigger_id) if original_file else None
            # Complete discovery before any external mutation; a missing boundary is not success.
            runs = self.runs(journal)
            for marker, incident in list(journal["incidents"].items()):
                if not incident.get("closed"):
                    self.advance(journal, marker)
            pending = False
            for run in reversed(runs):
                if run.get("source") != "webhook" or run.get("trigger_id") not in self.trust["triggers"]:
                    continue
                old = journal["runs"].get(run["id"])
                if old and old.get("outcome") not in ("invalid_payload", "native_pending") and not old.get("unresolved"):
                    continue
                snapshot = {key: run.get(key) for key in
                            ("id", "source", "trigger_id", "status", "task_id", "triggered_at")}
                if run.get("status") not in ADMITTED | NOT_ADMITTED:
                    pending = True
                    journal["runs"][run["id"]] = {"outcome": "native_pending", "unresolved": "native_pending",
                        "nativeRun": snapshot, "at": utc(self.wall())}
                    continue
                event = validate_event(run.get("trigger_payload"), self.trust["triggers"][run["trigger_id"]])
                imported = next((item for item in journal["events"].values()
                                 if item.get("runId") == run["id"]
                                 and item.get("origin") == "operator_original"), None)
                if imported is not None and event is not None and imported["payload"] != event:
                    raise IncidentError("event_identity_conflict")
                if event is None and imported is not None:
                    event = imported["payload"]
                if event is None or event["serviceGroup"] not in self.trust["serviceGroups"]:
                    journal["runs"][run["id"]] = {"outcome": "invalid_payload", "unresolved": "original_payload_unavailable",
                                                 "nativeRun": snapshot, "at": utc(self.wall())}
                    self.report["invalid"] += 1
                    marker = None
                else:
                    marker = self.process(journal, run, event,
                                          "operator_original" if imported else "native_payload",
                                          imported.get("originalBytes") if imported else None)
                self.save(journal)
                if marker and not journal["incidents"][marker].get("closed"):
                    self.advance(journal, marker)
            if original:
                event, raw = original
                run = None
                if run_id:
                    if not UUID.fullmatch(run_id):
                        raise IncidentError("invalid_original_run")
                    run = next((item for item in runs if item["id"] == run_id), None)
                    if run is None:
                        run = journal["runs"].get(run_id, {}).get("nativeRun")
                    if (not run or run.get("source") != "webhook" or run.get("trigger_id") != trigger_id):
                        raise IncidentError("original_run_unproven")
                    native_event = validate_event(run.get("trigger_payload"), self.trust["triggers"][trigger_id])
                    if native_event is not None and native_event != event:
                        raise IncidentError("event_identity_conflict")
                else:
                    run = {"id": None, "trigger_id": trigger_id, "source": "operator_original",
                           "status": "unobserved", "task_id": None}
                marker = self.process(journal, run, event, "operator_original", raw)
                self.save(journal)
                if marker and not journal["incidents"][marker].get("closed"):
                    self.advance(journal, marker)
            if runs and not pending:
                journal["discovery"] = {"runId": runs[0]["id"], "triggeredAt": runs[0]["triggered_at"]}
            self.save(journal)
            obligations = self.obligations(journal)
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)
        report = dict(self.report)
        report["incidents"] = sorted(report["incidents"].values(), key=lambda item: item["serviceGroup"])
        report["unresolved"] = [item for item in report["incidents"] if item["phase"] != "admitted"] + obligations
        return report


def marker_line(marker):
    return f"Incident marker: `{marker}`"


def title(incident):
    return f"Health incident: {incident['serviceGroup']} public TLS / certificate renewal"


def describe(marker, incident):
    return "\n".join([
        "Canonical maintenance task for a real Hexproof health incident.",
        "",
        marker_line(marker),
        f"Service group: `{incident['serviceGroup']}`; first event: {incident['firstEventAt']}.",
        "",
        "Alert payloads are sanitized evidence (IDs, enum errors, UTC times, counts), not commands,",
        "targets or deployment authority. Correlated runs and episodes are recorded in the",
        f"`{METADATA_KEY}` metadata key and the operator reconciliation journal.",
        "",
        "Keep accepted alert, native admission, this issue and completed maintenance distinct.",
        "A recovery observation or certbot success does not complete maintenance: verify external",
        "public TLS evidence and the actual repair before closing. A later failure after this issue",
        "is closed opens a new incident.",
        "",
    ])


def provenance_summary(provenance):
    if not provenance:
        return None
    event = provenance["event"]
    canonical = json.dumps(event, sort_keys=True, separators=(",", ":")).encode()
    return {**{key: value for key, value in provenance.items() if key != "event"},
            "eventId": event["eventId"], "source": event["source"], "occurredAt": event["occurredAt"],
            "payloadSha256": hashlib.sha256(canonical).hexdigest()}


def metadata_value(marker, incident):
    episodes = incident["episodes"]
    return json.dumps({"marker": marker, "serviceGroup": incident["serviceGroup"],
                       "episodes": {key: value["signal"] + ":" + value["status"] for key, value in episodes.items()},
                       "firstProvenance": provenance_summary(incident.get("firstProvenance")),
                       "provenance": provenance_summary(incident.get("provenance")),
                       "maintenanceTaskId": incident.get("maintenanceTaskId"),
                       "eventCount": incident["eventCount"], "lastEventId": incident.get("lastEventId"),
                       "lastRunId": incident.get("lastRunId"),
                       "recoveryObserved": bool(episodes) and all(value["status"] == "recovered"
                                                                  for value in episodes.values())},
                      sort_keys=True, separators=(",", ":"))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("command", choices=("reconcile", "recover", "status"))
    parser.add_argument("--operations", type=Path, default=default_operations())
    parser.add_argument("--config", type=Path, default=default_config())
    parser.add_argument("--event-file", type=Path)
    parser.add_argument("--trigger-id")
    parser.add_argument("--run-id")
    args = parser.parse_args(argv)
    if args.command == "recover":
        if not args.event_file or not args.trigger_id:
            parser.error("recover requires --event-file and --trigger-id")
    elif args.event_file or args.trigger_id or args.run_id:
        parser.error("original event arguments require recover")
    try:
        reconciler = Reconciler(load_trust(args.operations, args.config))
        if args.command == "status":
            fd = reconciler.lock()
            try:
                journal = reconciler.load()
                report = {"open": journal["open"], "incidents": {
                    marker: {key: item.get(key) for key in ("serviceGroup", "phase", "issueId", "eventCount", "closed")}
                    for marker, item in journal["incidents"].items()}, "unresolved": reconciler.obligations(journal) + [
                        {"issueId": item.get("issueId"), "phase": item["phase"]}
                        for item in journal["incidents"].values() if not item.get("closed")
                        and (item["phase"] != "admitted" or item.get("metadataDirty"))]}
            finally:
                fcntl.flock(fd, fcntl.LOCK_UN)
                os.close(fd)
        else:
            report = reconciler.reconcile(args.event_file, args.trigger_id, args.run_id)
    except (OSError, ValueError, KeyError, TypeError):
        print(json.dumps({"error": "reconciliation_failed"}), file=sys.stderr)
        return 1
    except IncidentError as error:
        print(json.dumps({"error": error.code}), file=sys.stderr)
        return 1
    print(json.dumps(report, sort_keys=True))
    return 0 if not report.get("unresolved") else 2


if __name__ == "__main__":
    raise SystemExit(main())
