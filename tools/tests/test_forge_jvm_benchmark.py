#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

SCRIPT = Path(__file__).resolve().parents[1] / "forge-shared-jvm/run.py"
SPEC = importlib.util.spec_from_file_location("forge_jvm_benchmark", SCRIPT)
benchmark = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(benchmark)


class ForgeJvmBenchmarkTests(unittest.TestCase):
    def test_both_modes_launch_packaged_host_with_only_shared_capacity_different(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = SimpleNamespace(runtime=root / "runtime", classpath="packaged.jar", heap=512)
            commands = []
            for shared in (False, True):
                process = Mock(stdin=io.StringIO(), stdout=io.StringIO())
                with patch.object(benchmark.subprocess, "Popen", return_value=process) as launch, \
                     patch.object(benchmark.threading, "Thread"):
                    host = benchmark.Host(args, root / str(shared), shared)
                    commands.append(launch.call_args.args[0])
                    host.close()
            self.assertEqual(commands[1], commands[0] + ["--max-games", "3"])
            self.assertEqual(commands[0][-4:], ["org.hexproof.forge.NativeHost",
                             "--interactive-server", "--forge-home", str(args.runtime / "forge-gui")])

    def test_cli_runs_both_modes_each_round_without_compiling_an_experiment(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime = root / "runtime"
            runtime.mkdir()
            (runtime / "forge-harness.jar").write_bytes(b"fixture host")
            (runtime / "lib").mkdir()
            (runtime / "lib/dependency.jar").write_bytes(b"fixture dependency")
            output = root / "result"
            calls = []
            def scenario(args, shared, index):
                self.assertEqual(args.classpath, os.pathsep.join(map(str, [
                    runtime / "forge-harness.jar", runtime / "lib/dependency.jar"])))
                self.assertTrue(args.abort_between_waves)
                calls.append((shared, index))
                return {"passed": True}
            with patch.object(sys, "argv", [str(SCRIPT), "--runtime", str(runtime),
                              "--output", str(output), "--abort-between-waves"]), \
                 patch.object(benchmark.platform, "system", return_value="Linux"), \
                 patch.object(benchmark.platform, "platform", return_value="Linux fixture"), \
                 patch.object(benchmark, "scenario", side_effect=scenario), \
                 patch.object(benchmark.subprocess, "run", return_value=SimpleNamespace(stderr="Java fixture")) as run:
                benchmark.main()
            self.assertEqual(calls, [(False, 0), (True, 0), (True, 1), (False, 1)])
            run.assert_called_once_with(["java", "-version"], capture_output=True, text=True)
            report = json.loads((output / "result.json").read_text())
            self.assertTrue(report["completed"])
            self.assertEqual(len(report["scenarios"]), 4)
            artifacts = json.loads((output / "provenance.json").read_text())["artifacts"]
            self.assertEqual(len(artifacts), 4)
            self.assertTrue(all(not item["path"].endswith(".java") for item in artifacts))

    def test_cli_help_has_no_retired_prototype_modes(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--help"],
                                capture_output=True, text=True, check=True)
        self.assertIn("--abort-between-waves", result.stdout)
        self.assertNotIn("--production", result.stdout)
        self.assertNotIn("--only", result.stdout)


if __name__ == "__main__":
    unittest.main()
