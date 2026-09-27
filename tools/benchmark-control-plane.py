#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Run isolated control-plane interference benchmarks and preserve raw evidence."""

import argparse
from datetime import datetime, timezone
import difflib
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import statistics
import subprocess
import tarfile


ROOT = Path(__file__).resolve().parents[1]
PACKAGES = ("accounts", "cluster", "server")
FIXTURES = (
    "apps/server/internal/benchutil/interference.go",
    *(f"apps/server/internal/{package}/control_plane_benchmark_test.go" for package in PACKAGES),
)
SCENARIOS = {
    "BenchmarkControlPlaneAccountAdmission/Independent",
    "BenchmarkControlPlaneAccountAdmission/LegacyCollision",
    "BenchmarkControlPlaneAccountAdmission/SameAccount",
    "BenchmarkControlPlaneAccountStore/Independent",
    "BenchmarkControlPlaneAccountStore/SameAccount",
    "BenchmarkControlPlaneCluster/CacheDuringReport",
    "BenchmarkControlPlaneCluster/RPCDuringReport",
    "BenchmarkControlPlaneCluster/RPCDuringRPC",
}
REQUIRED_METRICS = {
    "ns/op", "stall-ms", "probes/batch", "cohort-requests/s",
    *(f"{group}-{metric}" for group in ("probe", "slow")
      for metric in ("p50-ms", "p95-ms", "p99-ms", "max-ms", "fail-%")),
}


def output(*args, cwd=ROOT):
    return subprocess.run(args, cwd=cwd, check=True, text=True, capture_output=True).stdout.strip()


def parse_benchmarks(raw, rounds):
    results = {}
    for line in raw.splitlines():
        if not line.startswith("BenchmarkControlPlane"):
            continue
        fields = line.split()
        name = re.sub(r"-\d+$", "", fields[0])
        if len(fields) < 4 or len(fields) % 2 or name in results:
            raise ValueError(f"malformed or duplicate benchmark: {line}")
        if int(fields[1]) != rounds:
            raise ValueError(f"unexpected sample count: {line}")
        metrics = {}
        for index in range(2, len(fields), 2):
            value, unit = float(fields[index]), fields[index + 1]
            if not math.isfinite(value) or value < 0 or unit in metrics:
                raise ValueError(f"invalid benchmark metric: {line}")
            metrics[unit] = value
        if not REQUIRED_METRICS <= metrics.keys():
            raise ValueError(f"missing benchmark metrics: {name}")
        if metrics["stall-ms"] != 20 or metrics["probes/batch"] != 8:
            raise ValueError(f"unexpected workload configuration: {name}")
        if metrics["probe-fail-%"] or metrics["slow-fail-%"]:
            raise ValueError(f"failed requests invalidate the latency comparison: {name}")
        results[name] = metrics
    if results.keys() != SCENARIOS:
        raise ValueError(f"incomplete scenario set: {sorted(results.keys() ^ SCENARIOS)}")
    return results


def add_store_hook(source):
    """Add only the existing persistence injection seam to a historical copy.

    Preserve the original save call's lock scope and real fsync. No historical
    runtime behavior changes unless the benchmark installs the delay callback.
    Refuse unknown layouts rather than silently running unequal workloads.
    """
    if re.search(r"\bsaveRecord\s+func\(record\) error", source):
        return source
    declaration = "type Store struct {\n"
    save = "\t\tif err := s.save(r); err != nil {"
    if source.count(declaration) != 1 or source.count(save) != 1:
        raise ValueError("baseline store has no supported persistence hook; inspect it before comparing")
    source = source.replace(declaration, declaration + "\tsaveRecord func(record) error\n", 1)
    return source.replace(save, "\t\tpersist := s.saveRecord\n"
                          "\t\tif persist == nil {\n\t\t\tpersist = s.save\n\t\t}\n"
                          "\t\tif err := persist(r); err != nil {", 1)


def prepare_baseline(revision, destination):
    if revision.startswith("-"):
        raise ValueError("baseline must be a commit or ref, not a Git option")
    commit = output("git", "rev-parse", "--verify", revision + "^{commit}")
    archive = destination / "baseline.tar"
    subprocess.run(["git", "archive", "--format=tar", f"--output={archive}", commit, "apps/server"],
                   cwd=ROOT, check=True)
    source = destination / "baseline-source"
    source.mkdir()
    with tarfile.open(archive) as bundle:
        bundle.extractall(source, filter="data")
    for relative in FIXTURES:
        target = source / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
    store = source / "apps/server/internal/accounts/store.go"
    before = store.read_text()
    after = add_store_hook(before)
    store.write_text(after)
    (destination / "baseline-instrumentation.diff").write_text("".join(difflib.unified_diff(
        before.splitlines(keepends=True), after.splitlines(keepends=True),
        fromfile="original/internal/accounts/store.go", tofile="instrumented/internal/accounts/store.go")))
    return source, commit


def render_report(metadata, runs):
    grouped = {}
    for run in runs:
        for name, metrics in run["scenarios"].items():
            grouped.setdefault((run["label"], name), []).append(metrics)

    lines = ["# Control-plane interference benchmark", "",
             f"- UTC: {metadata['startedAt']}",
             f"- Current revision: `{metadata['currentRevision']}` (working tree status in metadata.json)",
             f"- Baseline: `{metadata.get('baselineRevision', 'none')}`",
             f"- Toolchain: `{metadata['goVersion']}`",
             f"- Platform: `{metadata['platform']}`",
             f"- GOMAXPROCS: {metadata['cpu']}; rounds/run: {metadata['rounds']}; runs/revision: {metadata['repeat']}",
             "- Each round: one 20 ms dependency stall, eight concurrent probes, then a full drain.",
             "- Values below are medians of per-run p95s, not pooled percentiles. The range is current per-run p95 min–max.",
             "", "| Scenario | Baseline p95 ms | Current p95 ms | Current p95 range ms | Current gate mean ms | Probe failures |",
             "|---|---:|---:|---:|---:|---:|"]
    for name in sorted(SCENARIOS):
        current = grouped[("current", name)]
        p95 = [entry["probe-p95-ms"] for entry in current]
        previous = grouped.get(("baseline", name), [])
        old = f"{statistics.median(entry['probe-p95-ms'] for entry in previous):.6f}" if previous else "n/a"
        gate = [entry["gate-mean-ms"] for entry in current if "gate-mean-ms" in entry]
        mean = f"{statistics.median(gate):.6f}" if gate else "n/a"
        short = name.removeprefix("BenchmarkControlPlane")
        lines.append(f"| {short} | {old} | {statistics.median(p95):.6f} | "
                     f"{min(p95):.6f}–{max(p95):.6f} | {mean} | 0 |")
    lines += ["", "## Interpretation", "",
              "Independent probes should remain responsive during the injected stall. SameAccount is a serialization control: "
              "it should still wait for the earlier operation. LegacyCollision deliberately uses distinct IDs that shared the former hash bucket; "
              "it measures that failure mode, not its frequency in a live population.", "",
              "Account/cluster RPCs use authenticated loopback HTTP. The store fixture uses 16 devices per account and retains "
              "the real file write, fsync and rename after the artificial delay. Account gate mean/max come from readiness telemetry "
              "when available and include the slow operation plus all probes; older revisions may not expose them.", "",
              "Raw logs and results.json retain p50/p95/p99/max, errors, stall duration and cohort request rate. "
              "The rate and Go ns/op describe this deliberately paced nine-request batch, not server capacity. "
              "These are closed-loop interference measurements, not WAN, WebSocket saturation, cancellation, GUI or Forge qualification. "
              "Background load, timer granularity and filesystem placement affect the numbers. "
              "No absolute latency threshold is imposed on CI.", "",
              "If a historical store needs the persistence hook, baseline-instrumentation.diff contains the complete adjustment. "
              "Only an archived source copy is changed; its original lock scope is preserved. "
              "Benchmark fixture hashes and exact commands are recorded in metadata.json.", ""]
    return "\n".join(lines)


def bounded_integer(limit):
    def parse(value):
        number = int(value)
        if not 1 <= number <= limit:
            raise argparse.ArgumentTypeError(f"expected an integer from 1 to {limit}")
        return number
    return parse


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", help="optional Git revision; runs the same fixtures in an archived server source copy")
    parser.add_argument("--rounds", type=bounded_integer(1000), default=100)
    parser.add_argument("--repeat", type=bounded_integer(10), default=3)
    parser.add_argument("--cpu", type=bounded_integer(256), default=4, help="GOMAXPROCS for each benchmark process")
    parser.add_argument("--output", type=Path, help="new artifact directory beneath build/")
    args = parser.parse_args()
    started = datetime.now(timezone.utc)
    destination = (args.output or ROOT / "build" / started.strftime("control-plane-bench-%Y%m%dT%H%M%S%fZ")).resolve()
    if not destination.is_relative_to((ROOT / "build").resolve()) or destination == (ROOT / "build").resolve():
        parser.error("--output must be a new directory beneath build/")
    destination.mkdir(parents=True, exist_ok=False)
    temporary = destination / "tmp"
    temporary.mkdir()
    sources = {"current": ROOT}
    metadata = {
        "startedAt": started.isoformat(), "currentRevision": output("git", "rev-parse", "HEAD"),
        "workingTreeStatus": output("git", "status", "--short"),
        "goVersion": output("go", "version"), "platform": platform.platform(),
        "logicalCPUs": os.cpu_count(), "cpu": args.cpu, "rounds": args.rounds, "repeat": args.repeat,
        "goEnvironment": json.loads(output("go", "env", "-json", "GOOS", "GOARCH", "CGO_ENABLED", "GOEXPERIMENT", "GOFLAGS")),
        "fixtureSHA256": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                          for name in (*FIXTURES, "tools/benchmark-control-plane.py")},
        "commands": [],
    }
    if args.baseline:
        sources["baseline"], metadata["baselineRevision"] = prepare_baseline(args.baseline, destination)
    for label, source in sources.items():
        if output("go", "version", cwd=source / "apps/server") != metadata["goVersion"]:
            raise ValueError(f"{label} selects a different Go toolchain; use matching toolchains before comparing")
    fixtures = destination / "fixtures"
    for relative in (*FIXTURES, "tools/benchmark-control-plane.py"):
        target = fixtures / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
    (destination / "working-tree.diff").write_text(output("git", "diff", "HEAD", "--", "apps/server", "tools/benchmark-control-plane.py"))
    runs = []
    env = {**os.environ, "TMPDIR": str(temporary), "TMP": str(temporary), "TEMP": str(temporary)}
    for repetition in range(args.repeat):
        order = ["baseline", "current"] if "baseline" in sources else ["current"]
        if repetition % 2:
            order.reverse()
        for label in order:
            command = ["go", "test", "-p", "1", "-run", "^$", "-bench", "^BenchmarkControlPlane",
                       "-benchtime", f"{args.rounds}x", "-count", "1", "-cpu", str(args.cpu), "-timeout", "10m",
                       *(f"./internal/{package}" for package in PACKAGES)]
            working = sources[label] / "apps/server"
            log = destination / f"{label}-{repetition + 1}.log"
            metadata["commands"].append({"label": label, "repetition": repetition + 1,
                                         "cwd": str(working), "argv": command, "log": log.name})
            (destination / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
            print(f"Running {label} {repetition + 1}/{args.repeat}; log: {log}", flush=True)
            with log.open("w") as stream:
                subprocess.run(command, cwd=working, env=env, stdout=stream, stderr=subprocess.STDOUT, check=True)
            runs.append({"label": label, "repetition": repetition + 1,
                         "scenarios": parse_benchmarks(log.read_text(), args.rounds)})
            (destination / "results.json").write_text(json.dumps(runs, indent=2) + "\n")
    report = destination / "report.md"
    report.write_text(render_report(metadata, runs))
    print(f"Report: {report}")


if __name__ == "__main__":
    main()
