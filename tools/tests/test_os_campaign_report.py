# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location("campaign_report", Path(__file__).resolve().parents[1]
                                             / "ui-automation/report-os-campaign.py")
REPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORT)


class CampaignReportTests(unittest.TestCase):
    def plan(self):
        return {"requiredRuns": 70, "requiredInput": "system-input", "runs": [
            {"id": f"{name}-{index}", "format": name}
            for name in REPORT.REQUIRED for index in range(10)]}

    def test_a_shortened_or_duplicated_plan_cannot_complete(self):
        for damage in [lambda p: p.update(requiredRuns=1),
                       lambda p: p["runs"].pop(),
                       lambda p: p["runs"][1].update(id=p["runs"][0]["id"]),
                       lambda p: p["runs"][0].update(format="modern"),
                       lambda p: p.update(requiredInput="native-qt-input")]:
            with self.subTest(damage=damage), tempfile.TemporaryDirectory() as directory:
                root, plan = Path(directory), self.plan()
                damage(plan)
                (root / "plan.json").write_text(json.dumps(plan))
                with self.assertRaises(ValueError):
                    REPORT.report(root)

    def test_failed_retries_do_not_inflate_or_erase_completed_games(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "plan.json").write_text(json.dumps(self.plan()))
            for attempt in ["r1", "r2", "r3"]:
                run = root / ("standard-0-" + attempt)
                run.mkdir()
                (run / "report.json").write_text("{}")
            def inspect(run):
                return {"status": "passed", "actions": {"click": 3}} if run.name.endswith("r2") else {"status": "failed"}
            with mock.patch.object(REPORT, "inspect", side_effect=inspect):
                result = REPORT.report(root)
            self.assertEqual(result["completedGames"], 1)
            self.assertEqual(result["actions"], {"click": 3})
            self.assertEqual(result["status"], "in-progress")
            self.assertTrue(result["cases"][0]["accepted"]["path"].endswith("r2"))

    def test_top_level_pass_still_requires_system_evidence_from_every_seat(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "report.json").write_text(json.dumps({"status": "passed", "seats": [
                {"exitCode": 0, "artifacts": str(root / "seat-1/artifacts")}]}))
            with mock.patch.object(REPORT.RUNNER, "seat_result", return_value={"status":"failed", "reason":"Missing system input"}) as verify:
                self.assertEqual(REPORT.inspect(root), {"status":"failed", "reason":"Missing system input"})
            self.assertEqual(verify.call_args.kwargs["expected_evidence"], "system-input")
