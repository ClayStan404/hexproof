#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "benchmark-control-plane.py"
SPEC = importlib.util.spec_from_file_location("control_plane_benchmark", SCRIPT)
bench = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bench)


def log_fixture():
    metrics = ("20000000 ns/op 450 cohort-requests/s 20 stall-ms 8 probes/batch "
               "0 probe-fail-% 0 slow-fail-% "
               "0.1 probe-p50-ms 0.2 probe-p95-ms 0.3 probe-p99-ms 0.4 probe-max-ms "
               "20 slow-p50-ms 21 slow-p95-ms 22 slow-p99-ms 23 slow-max-ms")
    return "\n".join(f"{name}-4 100 {metrics}" for name in sorted(bench.SCENARIOS))


class ControlPlaneBenchmarkTests(unittest.TestCase):
    def test_reads_all_scenarios_and_optional_gate_telemetry(self):
        raw = log_fixture().replace("0.1 probe-p50-ms", "0.004 gate-mean-ms 0.1 probe-p50-ms", 1)
        result = bench.parse_benchmarks(raw, 100)
        self.assertEqual(len(result), 8)
        self.assertEqual(result[sorted(result)[0]]["gate-mean-ms"], 0.004)

    def test_rejects_incomplete_duplicate_failed_and_nonfinite_measurements(self):
        raw = log_fixture()
        cases = ["\n".join(raw.splitlines()[:-1]), raw + "\n" + raw.splitlines()[0],
                 raw.replace("0 probe-fail-%", "1 probe-fail-%", 1),
                 raw.replace("0 slow-fail-%", "1 slow-fail-%", 1),
                 raw.replace("0.2 probe-p95-ms", "nan probe-p95-ms", 1),
                 raw.replace("0.2 probe-p95-ms", "inf probe-p95-ms", 1),
                 raw.replace("0.2 probe-p95-ms", "-1 probe-p95-ms", 1),
                 raw.replace("0.2 probe-p95-ms ", "", 1),
                 raw.replace("20 stall-ms", "10 stall-ms", 1)]
        for case in cases:
            with self.subTest(case=case[:100]), self.assertRaises(ValueError):
                bench.parse_benchmarks(case, 100)
        with self.assertRaises(ValueError):
            bench.parse_benchmarks(raw, 200)

    def test_historical_hook_keeps_the_original_lock_scope(self):
        original = ("type Store struct {\n\tmu sync.Mutex\n}\n"
                    "func (s *Store) Do() {\n\ts.mu.Lock()\n\tdefer s.mu.Unlock()\n"
                    "\t\tif err := s.save(r); err != nil {\n\t\t\treturn err\n\t\t}\n}\n")
        modified = bench.add_store_hook(original)
        self.assertIn("\tdefer s.mu.Unlock()\n\t\tpersist := s.saveRecord", modified)
        self.assertIn("persist = s.save", modified)
        self.assertIn("if err := persist(r); err != nil", modified)
        self.assertEqual(bench.add_store_hook(modified), modified)

    def test_unknown_baseline_is_rejected_instead_of_changing_the_workload(self):
        with self.assertRaises(ValueError):
            bench.add_store_hook("type Store struct {\n}\n")

    def test_report_uses_median_of_runs_and_shows_range(self):
        runs = []
        for index, latency in enumerate((1, 2, 9)):
            data = bench.parse_benchmarks(log_fixture(), 100)
            for metrics in data.values():
                metrics["probe-p95-ms"] = latency
            runs.append({"label": "current", "repetition": index + 1, "scenarios": data})
        metadata = {"startedAt": "fixture", "currentRevision": "current", "goVersion": "go fixture",
                    "platform": "fixture", "cpu": 4, "rounds": 100, "repeat": 3}
        report = bench.render_report(metadata, runs)
        self.assertIn("| n/a | 2.000000 | 1.000000–9.000000 |", report)
        self.assertIn("not pooled percentiles", report)


if __name__ == "__main__":
    unittest.main()
