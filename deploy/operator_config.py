#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Read operator-owned deployment inventory; never fall back to example targets."""

import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit


def inventory_path(name):
    variable = "HEXPROOF_NODES_FILE" if name == "nodes" else "HEXPROOF_DEPLOYMENT_TARGETS_FILE"
    state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    return Path(os.environ.get(variable) or state / "hexproof-operator" / (name + ".json"))


def read_inventory(name, required=True):
    path = inventory_path(name)
    variable = "HEXPROOF_NODES_FILE" if name == "nodes" else "HEXPROOF_DEPLOYMENT_TARGETS_FILE"
    if not path.exists() and not required and not os.environ.get(variable):
        return {}
    try:
        data = json.loads(path.read_text())
    except FileNotFoundError:
        raise ValueError(f"Missing operator inventory: {path}; configure it from the reviewed example before deployment") from None
    if not isinstance(data, dict) or data.get("_example"):
        raise ValueError("Operator inventory must be an object; example inventories cannot deploy")
    return data


def alias(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", value):
        raise ValueError("Targets must use plain existing SSH aliases")
    return value


def origin(value, scheme="https"):
    try:
        parsed = urlsplit(value) if isinstance(value, str) else None
        port = parsed.port if parsed else None
    except ValueError:
        raise ValueError("Invalid deployment endpoint port or host") from None
    if (parsed is None or parsed.scheme != scheme or not parsed.hostname or parsed.username or parsed.password
            or parsed.query or parsed.fragment or any(char.isspace() for char in value)
            or (port is not None and port < 1) or parsed.netloc.endswith(":")
            or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", parsed.hostname)
            or (scheme == "https" and parsed.netloc != parsed.hostname)
            or (scheme == "https" and parsed.path not in ("", "/"))):
        raise ValueError("Invalid deployment endpoint; credentials and URL parameters are forbidden")
    return value.rstrip("/")


def load_targets(required=True):
    data = read_inventory("deployment-targets", required)
    if not data and not required:
        return {}
    if data.get("schemaVersion") != 1 or not isinstance(data.get("cloudTargets"), dict):
        raise ValueError("Deployment inventory requires schemaVersion 1 and cloudTargets")
    for name, target in data["cloudTargets"].items():
        alias(name)
        if not isinstance(target, dict):
            raise ValueError("Invalid cloud target")
        target["origin"] = origin(target.get("origin"))
        for flag in ("forgeEnabled", "testEnabled", "publishEnabled"):
            if type(target.get(flag, False)) is not bool:
                raise ValueError(f"{flag} must be boolean")
        java = target.get("java", "java")
        if not isinstance(java, str) or not re.fullmatch(r"[A-Za-z0-9_./+-]+", java):
            raise ValueError("Invalid target Java executable")
    return data


def load_nodes(required=True):
    nodes = read_inventory("nodes", required)
    seen = set()
    for name, node in nodes.items():
        alias(name)
        if not isinstance(node, dict) or node.get("arch") not in ("amd64", "arm64"):
            raise ValueError("Home targets require a supported architecture")
        host = alias(node.get("ssh"))
        if host in seen:
            raise ValueError("Duplicate home SSH alias")
        seen.add(host)
        origin(node.get("endpoint"), "wss")
    return nodes


def home_name(name, nodes):
    matches = [key for key, node in nodes.items() if name in (key, node["ssh"])]
    if len(matches) != 1:
        raise ValueError("Unknown or ambiguous home deployment target: " + name)
    return matches[0]


def cloud_target(name, capability=None):
    alias(name)
    targets = load_targets()["cloudTargets"]
    if name not in targets:
        raise ValueError("Unknown deployment target: " + name)
    target = targets[name]
    if capability and not target.get(capability + "Enabled", False):
        raise ValueError(f"Target is not enabled for {capability} deployment: {name}")
    return target


def defaults(operation):
    data = load_targets()
    value = data.get("defaults", {}).get(operation)
    values = [value] if operation == "testTarget" else value
    if not isinstance(values, list) or not values or any(not isinstance(item, str) for item in values):
        raise ValueError("No operator default configured for " + operation + "; select explicit targets")
    for value in values:
        alias(value)
        if value not in data["cloudTargets"]:
            raise ValueError("Default names an unknown cloud target")
    return values


def classify(name):
    alias(name)
    cloud = name in load_targets(required=False).get("cloudTargets", {})
    nodes = load_nodes(required=False)
    home = any(name in (key, node["ssh"]) for key, node in nodes.items())
    if cloud and home:
        raise ValueError("Ambiguous cloud/home deployment target: " + name)
    if not cloud and not home:
        raise ValueError("Unknown deployment target: " + name + "; configure operator inventories first")
    return "cloud" if cloud else "home"


def main():
    operation, *args = sys.argv[1:]
    if operation == "defaults" and len(args) == 1:
        print(" ".join(defaults(args[0])))
    elif operation == "kind" and len(args) == 1:
        print(classify(args[0]))
    elif operation == "cloud" and len(args) in (1, 2):
        target = cloud_target(*args)
        print(origin(target["origin"]))
        print(target.get("java", "java"))
        print(urlsplit(target["origin"]).netloc)
    else:
        raise ValueError("Expected defaults OPERATION, kind TARGET, or cloud TARGET [CAPABILITY]")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        sys.exit("Operator configuration: " + str(error))
