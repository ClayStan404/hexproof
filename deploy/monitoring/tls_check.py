#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Bounded public TLS evidence for trusted Hexproof release origins.

The external monitor and the release promotion wrapper share this collector.
Endpoints come only from a private operator inventory whose coverage is checked
against the release bootstrap; nothing is discovered from downloaded catalogs
or alert payloads. Results contain IDs, enum errors, UTC times and counts only.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import ipaddress
import json
import re
import socket
import ssl
import sys
import multiprocessing
import time
import urllib.parse


SCHEMA = 1
KIND = "hexproof.public-tls.v1"
MAX_ENDPOINTS = 32
MAX_ADDRESSES = 4
PER_ORIGIN_SECONDS = 5.0
TOTAL_SECONDS = 60.0
MAX_OUTPUT = 64 * 1024
MAX_INPUT = 64 * 1024
DEFAULT_FLOOR_HOURS = 48
ID = re.compile(r"[a-z0-9][a-z0-9_-]{0,63}")
ENDPOINT_ID = re.compile(r"[a-z0-9_-]{1,64}")
OBSERVER_GROUP = "observer"
HEX64 = re.compile(r"[0-9a-f]{64}")
HOST = re.compile(r"(?=.{1,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)(\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*")
ERRORS = ("dns_failure", "dns_timeout", "connect_failure", "timeout", "untrusted",
          "name_mismatch", "expired", "not_yet_valid", "near_expiry", "tls_failure",
          "deadline_exceeded")
# OpenSSL X509_V_ERR_* codes reported by SSLCertVerificationError.verify_code.
VERIFY_CODES = {9: "not_yet_valid", 10: "expired", 62: "name_mismatch", 64: "name_mismatch"}


class ConfigError(ValueError):
    """The private inventory or bootstrap cannot define complete coverage."""

    def __init__(self, code):
        super().__init__(code)
        self.code = code


class ProbeError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


def utc(seconds):
    return datetime.fromtimestamp(seconds, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_utc(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", value):
        raise ValueError("invalid timestamp")
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()


def sanitized_id(value, pattern=ID):
    if not isinstance(value, str) or not pattern.fullmatch(value):
        raise ConfigError("invalid_id")
    return value


def service_group(value):
    group = sanitized_id(value)
    if group == OBSERVER_GROUP:
        raise ConfigError("invalid_id")
    return group


def origin(value, allow_path=False):
    """Return (normalized origin, host, port) for an explicit HTTPS/WSS URL."""
    if not isinstance(value, str) or len(value) > 512 or any(ord(c) < 33 or ord(c) > 126 for c in value):
        raise ConfigError("invalid_origin")
    try:
        parts = urllib.parse.urlsplit(value)
        port = parts.port if parts.port is not None else 443
    except ValueError:
        raise ConfigError("invalid_origin") from None
    if (parts.scheme not in ("https", "wss") or parts.username is not None or parts.password is not None
            or not 1 <= port <= 65535 or parts.netloc.endswith(":")
            or parts.query or parts.fragment or "?" in value or "#" in value or not parts.hostname
            or (not allow_path and parts.path not in ("", "/"))):
        raise ConfigError("invalid_origin")
    if "%" in parts.hostname or parts.hostname.endswith(".."):
        raise ConfigError("invalid_origin")
    host = parts.hostname.lower().rstrip(".")
    try:
        host = ipaddress.ip_address(host).compressed
    except ValueError:
        if not HOST.fullmatch(host):
            raise ConfigError("invalid_origin") from None
    shown = "[" + host + "]" if ":" in host else host
    return f"{parts.scheme}://{shown}:{port}", host, port


def bootstrap_origins(data):
    try:
        document = json.loads(data)
    except (ValueError, UnicodeDecodeError):
        raise ConfigError("invalid_bootstrap") from None
    if (not isinstance(document, dict) or type(document.get("schemaVersion")) is not int
            or document["schemaVersion"] != 2 or type(document.get("revision")) is not int
            or document["revision"] < 1 or not isinstance(document.get("directoryUrls"), list)
            or len(document["directoryUrls"]) > 4 or not isinstance(document.get("servers"), list)
            or len(document["servers"]) > MAX_ENDPOINTS):
        raise ConfigError("invalid_bootstrap")
    required, servers = set(), {}
    for url in document["directoryUrls"]:
        normalized = origin(url, allow_path=True)[0]
        if not normalized.startswith("https://"):
            raise ConfigError("invalid_bootstrap")
        required.add(normalized)
    for server in document["servers"]:
        if not isinstance(server, dict):
            raise ConfigError("invalid_bootstrap")
        identifier = sanitized_id(server.get("id"), ENDPOINT_ID)
        if identifier in servers:
            raise ConfigError("duplicate_bootstrap_id")
        normalized = origin(server.get("url"), allow_path=True)[0]
        if not normalized.startswith("wss://"):
            raise ConfigError("invalid_bootstrap")
        servers[identifier] = normalized
        required.add(normalized)
        legacy = server.get("legacyUrls", [])
        if not isinstance(legacy, list) or len(legacy) > 8:
            raise ConfigError("invalid_bootstrap")
        for url in legacy:
            required.add(origin(url, allow_path=True)[0])
    if not required:
        raise ConfigError("invalid_bootstrap")
    return required, servers


def load_inventory(config_data, bootstrap_data):
    """Validate the private endpoint inventory against the release bootstrap."""
    if len(config_data) > MAX_INPUT or len(bootstrap_data) > MAX_INPUT:
        raise ConfigError("oversized_input")
    try:
        config = json.loads(config_data)
    except (ValueError, UnicodeDecodeError):
        raise ConfigError("invalid_config") from None
    if not isinstance(config, dict) or type(config.get("schemaVersion")) is not int or config.get("schemaVersion") != SCHEMA:
        raise ConfigError("invalid_config")
    bootstrap_sha = hashlib.sha256(bootstrap_data).hexdigest()
    if not isinstance(config.get("bootstrapSha256"), str) or config["bootstrapSha256"] != bootstrap_sha:
        raise ConfigError("bootstrap_digest_mismatch")
    hours = config.get("minimumRemainingHours", DEFAULT_FLOOR_HOURS)
    if type(hours) is not int or not 1 <= hours <= 24 * 60:
        raise ConfigError("invalid_threshold")
    entries = config.get("endpoints")
    if not isinstance(entries, list) or not entries:
        raise ConfigError("empty_inventory")
    if len(entries) > MAX_ENDPOINTS:
        raise ConfigError("too_many_endpoints")
    endpoints, seen = [], set()
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != {"id", "origin", "serviceGroup"}:
            raise ConfigError("invalid_endpoint")
        identifier = sanitized_id(entry["id"], ENDPOINT_ID)
        if identifier in seen:
            raise ConfigError("duplicate_id")
        seen.add(identifier)
        normalized, host, port = origin(entry["origin"])
        endpoints.append({"id": identifier, "origin": normalized, "host": host, "port": port,
                          "serviceGroup": service_group(entry["serviceGroup"])})
    required, servers = bootstrap_origins(bootstrap_data)
    mapping = {item["id"]: item["origin"] for item in endpoints}
    if (not required <= set(mapping.values())
            or any(mapping.get(key) != value for key, value in servers.items())):
        raise ConfigError("incomplete_coverage")
    endpoints.sort(key=lambda item: item["id"])
    canonical = {"bootstrapSha256": bootstrap_sha, "minimumRemainingSeconds": hours * 3600,
                 "endpoints": [{key: item[key] for key in ("id", "origin", "serviceGroup")} for item in endpoints]}
    digest = hashlib.sha256(json.dumps(canonical, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return {"endpoints": endpoints, "bootstrapSha256": bootstrap_sha, "inventorySha256": digest,
            "minimumRemainingSeconds": hours * 3600}


def read_inventory(config_path, bootstrap_path):
    try:
        with open(config_path, "rb") as config, open(bootstrap_path, "rb") as bootstrap:
            return load_inventory(config.read(MAX_INPUT + 1), bootstrap.read(MAX_INPUT + 1))
    except OSError:
        raise ConfigError("unreadable_input") from None


def resolve(host, port, timeout, resolver):
    # Called only inside a killable worker: getaddrinfo has no timeout API.
    try:
        addresses = resolver(host, port, type=socket.SOCK_STREAM)
    except (OSError, UnicodeError):
        raise ProbeError("dns_failure") from None
    if not addresses:
        raise ProbeError("dns_failure")
    return addresses[:MAX_ADDRESSES]


def bounded_probe(host, port, deadline, context, resolver, clock, wall, floor):
    """A terminated/joined worker bounds DNS, connect and TLS together (Debian)."""
    processes = multiprocessing.get_context("fork")
    receive, send = processes.Pipe(duplex=False)

    def work():
        try:
            cert = handshake(host, port, deadline, context, resolver, clock)
            result = judge(cert, wall(), floor)
        except ProbeError as error:
            result = (error.code, None, None)
        except Exception:
            result = ("tls_failure", None, None)
        send.send(result)
        send.close()

    worker = processes.Process(target=work, daemon=True)
    worker.start()
    send.close()
    try:
        if receive.poll(max(0, deadline - clock())):
            try:
                return receive.recv()
            except EOFError:
                return "tls_failure", None, None
        return "timeout", None, None
    finally:
        if worker.is_alive():
            worker.kill()
        worker.join()
        receive.close()


def strict_context(cafile=None):
    # Only the shared verified context may produce a passing result. Tests
    # replace the trust store, never the verification mode.
    context = ssl.create_default_context(cafile=cafile)
    if context.verify_mode != ssl.CERT_REQUIRED or not context.check_hostname:
        raise ProbeError("tls_failure")
    return context


def handshake(host, port, deadline, context, resolver, clock):
    addresses = resolve(host, port, deadline - clock(), resolver)
    failure = "connect_failure"
    for family, kind, protocol, _, address in addresses:
        remaining = deadline - clock()
        if remaining <= 0:
            raise ProbeError("timeout")
        raw = socket.socket(family, kind, protocol)
        try:
            raw.settimeout(remaining)
            raw.connect(address)
        except (TimeoutError, socket.timeout):
            raw.close()
            failure = "timeout"
            continue
        except OSError:
            raw.close()
            continue
        try:
            raw.settimeout(max(deadline - clock(), 0.001))
            with context.wrap_socket(raw, server_hostname=host) as tls:
                return tls.getpeercert()
        except ssl.SSLCertVerificationError as error:
            raise ProbeError(VERIFY_CODES.get(error.verify_code, "untrusted")) from None
        except (TimeoutError, socket.timeout):
            raise ProbeError("timeout") from None
        except ssl.SSLError:
            raise ProbeError("tls_failure") from None
        except OSError:
            raise ProbeError("connect_failure") from None
        finally:
            raw.close()
    raise ProbeError(failure)


def judge(certificate, now, floor):
    try:
        not_before = ssl.cert_time_to_seconds(certificate["notBefore"])
        not_after = ssl.cert_time_to_seconds(certificate["notAfter"])
    except (KeyError, TypeError, ValueError):
        return "tls_failure", None, None
    remaining = int(not_after - now)
    if now < not_before:
        return "not_yet_valid", not_after, remaining
    if remaining <= 0:
        return "expired", not_after, remaining
    return ("near_expiry" if remaining < floor else ""), not_after, remaining


def collect(inventory, cafile=None, resolver=socket.getaddrinfo, clock=time.monotonic, wall=time.time,
            per_origin=PER_ORIGIN_SECONDS, total=TOTAL_SECONDS):
    """Probe each distinct TLS identity once and map results to every endpoint."""
    started_wall = wall()
    started = clock()
    stop = started + total
    floor = inventory["minimumRemainingSeconds"]
    context = strict_context(cafile)
    identities = {}
    for endpoint in inventory["endpoints"]:
        identities.setdefault((endpoint["host"], endpoint["port"]), []).append(endpoint)
    results = {}
    for key in sorted(identities):
        deadline = min(clock() + per_origin, stop)
        try:
            if deadline - clock() <= 0:
                raise ProbeError("deadline_exceeded")
            results[key] = bounded_probe(key[0], key[1], deadline, context, resolver, clock, wall, floor)
        except ProbeError as error:
            results[key] = (error.code, None, None)
    rows = []
    for endpoint in inventory["endpoints"]:
        error, not_after, remaining = results[(endpoint["host"], endpoint["port"])]
        rows.append({"id": endpoint["id"], "serviceGroup": endpoint["serviceGroup"],
                     "result": "fail" if error else "pass", "error": error,
                     "notAfter": utc(not_after) if not_after is not None else None,
                     "remainingSeconds": remaining})
    failed = sum(row["result"] == "fail" for row in rows)
    evidence = {"schemaVersion": SCHEMA, "kind": KIND, "collectedAt": utc(started_wall),
                "completedAt": utc(wall()), "inventorySha256": inventory["inventorySha256"],
                "bootstrapSha256": inventory["bootstrapSha256"], "minimumRemainingSeconds": floor,
                "result": "fail" if failed else "pass",
                "counts": {"endpoints": len(rows), "identities": len(identities),
                           "passed": len(rows) - failed, "failed": failed},
                "endpoints": rows}
    if len(json.dumps(evidence)) > MAX_OUTPUT:
        raise ProbeError("output_limit")
    return evidence


def verify_evidence(evidence, inventory, now, max_age):
    """Require fresh, complete, passing evidence for exactly this inventory.

    The remaining lifetime is recomputed at ``now`` so a caller can re-check it
    immediately before a mutation. Returns the minimum remaining seconds.
    """
    if (not isinstance(evidence, dict) or evidence.get("schemaVersion") != SCHEMA
            or evidence.get("kind") != KIND):
        raise ValueError("invalid_evidence")
    if (evidence.get("inventorySha256") != inventory["inventorySha256"]
            or evidence.get("bootstrapSha256") != inventory["bootstrapSha256"]
            or evidence.get("minimumRemainingSeconds") != inventory["minimumRemainingSeconds"]):
        raise ValueError("inventory_mismatch")
    collected = parse_utc(evidence.get("collectedAt"))
    completed = parse_utc(evidence.get("completedAt"))
    if completed < collected or completed > now or collected > now:
        raise ValueError("future_evidence")
    if now - collected > max_age:
        raise ValueError("stale_evidence")
    rows = evidence.get("endpoints")
    expected = [item["id"] for item in inventory["endpoints"]]
    if not isinstance(rows, list) or [row.get("id") for row in rows if isinstance(row, dict)] != expected:
        raise ValueError("incomplete_evidence")
    if evidence.get("result") != "pass" or any(row.get("result") != "pass" or row.get("error") for row in rows):
        raise ValueError("failing_evidence")
    if [row.get("serviceGroup") for row in rows] != [item["serviceGroup"] for item in inventory["endpoints"]]:
        raise ValueError("incomplete_evidence")
    remaining = min(parse_utc(row.get("notAfter")) - now for row in rows)
    if remaining < inventory["minimumRemainingSeconds"]:
        raise ValueError("near_expiry")
    return int(remaining)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--config", required=True)
    parser.add_argument("--bootstrap", required=True)
    args = parser.parse_args(argv)
    try:
        evidence = collect(read_inventory(args.config, args.bootstrap))
    except (OSError, ssl.SSLError):
        print(json.dumps({"error": "collector_failed"}), file=sys.stderr)
        return 1
    except (ConfigError, ProbeError) as error:
        print(json.dumps({"error": error.code}), file=sys.stderr)
        return 1
    print(json.dumps(evidence, sort_keys=True))
    return 0 if evidence["result"] == "pass" else 2


if __name__ == "__main__":
    raise SystemExit(main())
