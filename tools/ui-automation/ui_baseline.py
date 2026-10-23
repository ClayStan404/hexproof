#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Validate declared UI behavior contracts independently of scenario pass flags."""

import json
import math
from pathlib import Path
import re


MANIFEST_SCHEMA = "hexproof.ui-behavior-baseline.v1"
EVIDENCE_SCHEMA = "hexproof.ui-baseline-evidence.v1"
RULE_TYPES = {"boolean", "integer", "number", "string"}
RULE_KEYS = {"type", "eq", "min", "max", "gt", "lt"}
SYSTEM_EVIDENCE = "system-input"


def _require(condition, message):
    if not condition:
        raise ValueError(message)


def _number(value):
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def _typed(value, kind):
    return {"boolean": lambda: type(value) is bool,
            "integer": lambda: type(value) is int and _number(value),
            "number": lambda: _number(value),
            "string": lambda: isinstance(value, str)}[kind]()


def _json_value(value, label):
    """Reject non-JSON and nonfinite data, including unvalidated diagnostics."""
    if isinstance(value, dict):
        for key, child in value.items():
            _require(isinstance(key, str), f"{label}: object keys must be strings")
            _json_value(child, f"{label}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _json_value(child, f"{label}[{index}]")
    else:
        _require(value is None or type(value) in (bool, str) or _number(value),
                 f"{label}: expected finite JSON data")


def _object(value, label):
    _require(isinstance(value, dict), f"{label}: expected an object")
    return value


def _text(value, label):
    _require(isinstance(value, str) and bool(value.strip()), f"{label}: expected nonempty text")
    return value


def _matches(rule, value, label):
    _require(_typed(value, rule["type"]), f"{label}: expected {rule['type']}")
    for operator, expected in rule.items():
        if operator == "type":
            continue
        matches = {"eq": lambda: value == expected,
                   "min": lambda: value >= expected,
                   "max": lambda: value <= expected,
                   "gt": lambda: value > expected,
                   "lt": lambda: value < expected}[operator]()
        _require(matches, f"{label}: violates {operator} {expected!r}")


def _rule(rule, label):
    _object(rule, label)
    _require(not rule.keys() - RULE_KEYS, f"{label}: unknown rule constraint")
    kind = rule.get("type")
    _require(isinstance(kind, str) and kind in RULE_TYPES, f"{label}: unsupported observation type")
    _require(len(rule) > 1, f"{label}: a rule must constrain its observation")
    if "eq" in rule:
        _require(_typed(rule["eq"], kind), f"{label}: equality has the wrong type")
    bounds = {name: rule[name] for name in ("min", "max", "gt", "lt") if name in rule}
    if bounds:
        _require(kind in ("integer", "number"), f"{label}: only numeric rules support bounds")
        _require(all(_number(value) for value in bounds.values()), f"{label}: bounds must be finite numbers")
        if kind == "integer":
            lower = math.ceil(bounds["min"]) if "min" in bounds else -math.inf
            if "gt" in bounds:
                lower = max(lower, math.floor(bounds["gt"]) + 1)
            upper = math.floor(bounds["max"]) if "max" in bounds else math.inf
            if "lt" in bounds:
                upper = min(upper, math.ceil(bounds["lt"]) - 1)
            _require(lower <= upper, f"{label}: contradictory integer bounds")
        else:
            lower = max(bounds.get("min", -math.inf), bounds.get("gt", -math.inf))
            upper = min(bounds.get("max", math.inf), bounds.get("lt", math.inf))
            strict = ("gt" in bounds and bounds["gt"] == lower) or (
                "lt" in bounds and bounds["lt"] == upper)
            _require(lower < upper or (lower == upper and not strict),
                     f"{label}: contradictory numeric bounds")
    if "eq" in rule:
        _matches(rule, rule["eq"], label)


def _rules(rules, label):
    _object(rules, label)
    _require(bool(rules), f"{label}: expected at least one required observation")
    for name, rule in rules.items():
        _require(re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", name) is not None,
                 f"{label}: invalid observation name")
        _rule(rule, f"{label}.{name}")


def _manifest(manifest):
    _object(manifest, "manifest")
    _json_value(manifest, "manifest")
    _require(manifest.get("schema") == MANIFEST_SCHEMA, "Unsupported UI baseline manifest schema")
    _require(manifest.get("performance") == "not-assessed", "UI baseline does not certify performance")
    reference = _object(manifest.get("reference"), "manifest.reference")
    _text(reference.get("tag"), "manifest.reference.tag")
    _require(isinstance(reference.get("commit"), str)
             and re.fullmatch(r"[0-9a-f]{40}", reference["commit"]) is not None,
             "manifest.reference.commit: expected an immutable full commit")
    _text(reference.get("meaning"), "manifest.reference.meaning")
    scenarios = _object(manifest.get("scenarios"), "manifest.scenarios")
    _require(bool(scenarios), "manifest.scenarios: expected at least one scope")
    names = set()
    for scope, scenario in scenarios.items():
        _require(re.fullmatch(r"[a-z][a-z0-9_]*", scope) is not None, "Invalid baseline scope")
        _object(scenario, f"manifest.scenarios.{scope}")
        name = _text(scenario.get("name"), f"manifest.scenarios.{scope}.name")
        _require(name not in names, "Manifest scenarios must have unique names")
        names.add(name)
        filename = _text(scenario.get("file"), f"manifest.scenarios.{scope}.file")
        _require(Path(filename).name == filename and "\\" not in filename and filename.endswith(".qml"),
                 "Invalid scenario filename")
        if "fixtureRequirements" in scenario:
            _rules(scenario["fixtureRequirements"], f"manifest.scenarios.{scope}.fixtureRequirements")
    suites = manifest.get("qmlSuites")
    _require(isinstance(suites, list) and bool(suites), "manifest.qmlSuites: expected a nonempty list")
    _require(all(isinstance(name, str) and Path(name).name == name and name.endswith(".qml")
                 for name in suites) and len(set(suites)) == len(suites), "Invalid or duplicate QML suite")
    cases = manifest.get("cases")
    _require(isinstance(cases, list) and bool(cases), "manifest.cases: expected a nonempty list")
    ids, scopes = set(), set()
    for case in cases:
        _object(case, "manifest case")
        scope = case.get("scenario")
        _require(isinstance(scope, str) and scope in scenarios, "Case has an unknown scenario scope")
        identity = case.get("id")
        _require(isinstance(identity, str) and identity.startswith(scope + ".")
                 and re.fullmatch(r"[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+", identity) is not None,
                 "Case has an invalid stable ID")
        _require(identity not in ids, f"Duplicate baseline case: {identity}")
        ids.add(identity)
        scopes.add(scope)
        _require(case.get("origin") in ("compatibility", "extension"), f"{identity}: invalid case origin")
        _text(case.get("description"), f"{identity}.description")
        _rules(case.get("observations"), f"{identity}.observations")
    _require(scopes == scenarios.keys(), "Each scenario scope must declare baseline cases")
    return manifest


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        _require(key not in result, f"Duplicate JSON field: {key}")
        result[key] = value
    return result


def load_manifest(path):
    """Load a revisioned baseline, refusing malformed or unconstrained rules."""
    manifest = json.loads(Path(path).read_text(encoding="utf-8"), object_pairs_hook=_unique_object)
    return _manifest(manifest)


def _observe(rules, observations, label):
    _object(observations, label)
    for name, rule in rules.items():
        _require(name in observations, f"{label}: missing required observation {name}")
        _matches(rule, observations[name], f"{label}.{name}")


def _positive_integer(value):
    return type(value) is int and value > 0 and _number(value)


def _native(startup, summary, actions, scope):
    _object(startup, "startup")
    _object(summary, "summary")
    _require(startup.get("evidence") == SYSTEM_EVIDENCE and summary.get("evidence") == SYSTEM_EVIDENCE,
             "Behavior acceptance requires system-input evidence")
    pid = startup.get("pid")
    _require(_positive_integer(pid), "Startup must identify the owned process")
    window = _object(startup.get("window"), "startup.window")
    platform = window.get("platform")
    _require(isinstance(platform, str) and bool(platform)
             and platform.split(":", 1)[0].lower() not in ("offscreen", "minimal")
             and window.get("visible") is True and window.get("exposed") is True,
             "Startup must establish an exposed native window")
    for name in ("width", "height", "dpr"):
        _require(_number(window.get(name)) and window[name] > 0, f"startup.window.{name}: expected positive geometry")
    for name in ("requestedWindowMode", "windowMode"):
        modes = [source[name] for source in (window, startup) if name in source]
        _require(bool(modes) and all(mode == "maximized" for mode in modes),
                 f"Primary startup {name} must be maximized")
    _require(summary.get("osInputVerified") is True, "System input delivery was not verified")
    for name in ("exitCode", "failedInputs", "artifactFailures"):
        _require(type(summary.get(name)) is int and summary[name] == 0, f"Summary has failed or missing {name}")
    _require(isinstance(summary.get("qmlWarnings"), list) and not summary["qmlWarnings"],
             "Summary must have no QML warnings")
    _require(isinstance(actions, list) and bool(actions) and _positive_integer(summary.get("inputs"))
             and summary["inputs"] == len(actions), "Summary input count must match a nonempty action trace")
    kinds = set()
    for sequence, action in enumerate(actions, 1):
        _object(action, f"action {sequence}")
        kind = action.get("action")
        _require(kind in ("activate", "hover", "click", "rightClick", "doubleClick", "drag", "wheel", "key", "type"),
                 f"action {sequence}: unsupported system action")
        _require(type(action.get("sequence")) is int and action["sequence"] == sequence
                 and action.get("accepted") is True and action.get("evidence") == SYSTEM_EVIDENCE,
                 f"action {sequence}: failed or incomplete input trace")
        receipt = _object(action.get("systemInput"), f"action {sequence}.systemInput")
        _require(receipt.get("status") == "passed" and receipt.get("backend") == "mutter-virtual-device"
                 and type(receipt.get("pid")) is int and receipt["pid"] == pid
                 and receipt.get("focusVerified") is True and receipt.get("deliveryVerified") is True
                 and _positive_integer(receipt.get("window")) and _positive_integer(receipt.get("ownerWindow")),
                 f"action {sequence}: missing owned-window system delivery")
        events = _object(receipt.get("spontaneousEvents"), f"action {sequence}.spontaneousEvents")
        _require(all(type(count) is int and count >= 0 for count in events.values()),
                 f"action {sequence}: event counts must be nonnegative integers")
        presses = events.get("mousePress", 0) + events.get("mouseDoubleClick", 0)
        if kind in ("click", "rightClick", "drag"):
            _require(presses > 0 and events.get("mouseRelease", 0) > 0,
                     f"action {sequence}: missing mouse press/release delivery")
        if kind == "doubleClick":
            _require(presses >= 2 and events.get("mouseRelease", 0) >= 2,
                     f"action {sequence}: missing double-click delivery")
        if kind == "drag":
            _require(events.get("mouseMove", 0) > 0, f"action {sequence}: missing drag motion")
        if kind == "wheel":
            _require(events.get("wheel", 0) > 0 and _number(action.get("delta")) and action["delta"] != 0,
                     f"action {sequence}: missing actual wheel delivery")
        if kind in ("key", "type"):
            _require(events.get("keyPress", 0) + events.get("shortcutOverride", 0) > 0
                     and events.get("keyRelease", 0) > 0,
                     f"action {sequence}: missing keyboard press/release delivery")
        kinds.add(kind)
    _require("click" in kinds, "Behavior acceptance requires an actual click")
    if scope == "deck":
        _require("wheel" in kinds, "Deck acceptance requires actual wheel input")


def validate_evidence(manifest, scope, evidence, startup, summary, actions):
    """Require every declared behavior and prerequisite, independent of pass flags."""
    _manifest(manifest)
    _require(isinstance(scope, str) and scope in manifest["scenarios"], "Unknown UI baseline scope")
    for label, value in (("evidence", evidence), ("startup", startup), ("summary", summary), ("actions", actions)):
        _json_value(value, label)
    _object(evidence, "evidence")
    _object(startup, "startup")
    _require(evidence.get("schema") == EVIDENCE_SCHEMA, "Unsupported UI baseline evidence schema")
    reference = manifest["reference"]["commit"]
    _require(evidence.get("referenceCommit") == reference, "Evidence names a different baseline reference")
    scenario = manifest["scenarios"][scope]
    _require(evidence.get("scenario") == scenario["name"], "Evidence names a different baseline scenario")
    _require(evidence.get("performance", "not-assessed") == "not-assessed",
             "Behavior evidence cannot certify FPS or rendering performance")
    if "runId" in evidence:
        _require(bool(evidence["runId"]) and evidence["runId"] == startup.get("runId"),
                 "Evidence belongs to a different native run")
    if "fixtureRequirements" in scenario:
        _observe(scenario["fixtureRequirements"], evidence.get("fixture"), "evidence.fixture")
    expected = {case["id"]: case for case in manifest["cases"] if case["scenario"] == scope}
    cases = evidence.get("cases")
    _require(isinstance(cases, list), "Evidence must declare its completed case list")
    seen = set()
    for case in cases:
        _object(case, "evidence case")
        identity = case.get("id")
        _require(isinstance(identity, str) and identity in expected, f"Unknown or out-of-scope evidence case: {identity}")
        _require(identity not in seen, f"Duplicate evidence case: {identity}")
        seen.add(identity)
        _observe(expected[identity]["observations"], case.get("observations"), f"{identity}.observations")
    _require(seen == expected.keys(), f"Missing required baseline cases: {sorted(expected.keys() - seen)}")
    _native(startup, summary, actions, scope)
    return {"scope": scope, "cases": list(expected), "referenceCommit": reference, "performance": "not-assessed"}
