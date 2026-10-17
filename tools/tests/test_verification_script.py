#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise verification orchestration without compiling or opening any GUI."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "verify.sh"


class VerificationScriptTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.write("apps/client-qt/CMakeLists.txt", 'set(HEXPROOF_VERSION "1.2.3")\n')
        (self.root / "apps/server").mkdir(parents=True)
        self.script = self.write("tools/verify.sh", SCRIPT.read_text(encoding="utf-8"))
        for name in ("check-license-headers.sh", "check-qml-text-safety.sh", "first.sh", "second.sh"):
            self.write(f"tools/{name}", "#!/usr/bin/env bash\nexit 0\n", executable=True)
        dispatcher = f"#!{sys.executable}\n" + '''
import json
import os
from pathlib import Path
import sys
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["VERIFY_TEST_LOG"], "a") as log:
    log.write(json.dumps([name, *args]) + "\\n")
if name == os.environ.get("VERIFY_TEST_FAIL_TOOL"):
    sys.exit(13)
if name == "git" and args[:1] == ["clang-format"]:
    print("no modified files to format")
elif name == "git" and args[:2] == ["ls-files", "-co"]:
    sys.stdout.write("tools/first.sh\\0tools/second.sh\\0")
elif name == "hexproof-server":
    print("hexproof-server " + os.environ.get("VERIFY_TEST_SERVER_VERSION", "1.2.3"))
elif name == "hexproof":
    print("Hexproof 1.2.3")
'''
        for name in ("cmake", "ctest", "git", "go", "gofmt", "ninja", "python3", "rg",
                     "clang-format", "git-clang-format"):
            self.write(f"bin/{name}", dispatcher, executable=True)
        self.write("build/client-qt/hexproof", dispatcher, executable=True)
        self.write("build/server/hexproof-server", dispatcher, executable=True)
        self.log = self.root / "commands.jsonl"
        self.env = {**os.environ, "PATH": f"{self.root / 'bin'}:{os.environ['PATH']}",
                    "VERIFY_TEST_LOG": str(self.log),
                    "HEXPROOF_CLIENT_BUILD_DIR": str(self.root / "build/client-qt"),
                    "HEXPROOF_SERVER_BINARY_PATH": str(self.root / "build/server/hexproof-server")}

    def write(self, relative, content, executable=False):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        if executable:
            path.chmod(0o755)
        return path

    def run_script(self, *args, succeeds=True):
        result = subprocess.run([shutil.which("bash"), str(self.script), *args],
                                cwd=self.root, env=self.env, text=True,
                                capture_output=True, timeout=15)
        if succeeds:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result, calls

    def test_static_never_builds_or_runs_application_tests(self):
        _, calls = self.run_script("--scope", "static")
        self.assertFalse({call[0] for call in calls} & {"go", "gofmt", "cmake", "ctest", "hexproof"})
        self.assertIn(["python3", "-m", "unittest", "discover", "-s", "tools/tests"], calls)

    def test_server_does_not_need_qt_but_keeps_race_tests(self):
        _, calls = self.run_script("--scope", "server")
        self.assertFalse({call[0] for call in calls} & {"cmake", "ctest", "hexproof"})
        self.assertIn(["go", "vet", "./..."], calls)
        self.assertTrue(any(call[:3] == ["go", "test", "-race"] for call in calls))
        self.assertIn(["hexproof-server", "-version"], calls)

    def test_client_builds_matching_integration_server_without_go_test_suite(self):
        _, calls = self.run_script("--scope", "client")
        self.assertTrue(any(call[:2] == ["go", "build"] for call in calls))
        self.assertFalse(any(call[:2] in (["go", "test"], ["go", "vet"]) for call in calls))
        self.assertTrue(any(call[0] == "ctest" for call in calls))

    def test_quick_client_skips_go_and_ctest(self):
        _, calls = self.run_script("--scope", "client", "--quick")
        self.assertFalse({call[0] for call in calls} & {"go", "gofmt", "ctest"})
        self.assertTrue(any(call[:2] == ["cmake", "--build"] for call in calls))

    def test_default_is_complete_but_incremental(self):
        _, calls = self.run_script()
        self.assertIn(["go", "test", "./..."], calls)
        self.assertTrue(any(call[:3] == ["go", "test", "-race"] for call in calls))
        self.assertTrue(any(call[0] == "ctest" for call in calls))
        for call in calls:
            self.assertNotIn("--clean-first", call)
            self.assertNotIn("-a", call)
            self.assertNotIn("-count=1", call)

    def test_clean_rebuilds_are_explicit(self):
        _, calls = self.run_script("--clean")
        self.assertTrue(any(call[:3] == ["go", "build", "-a"] for call in calls))
        self.assertTrue(any(call[:3] == ["go", "test", "-count=1"] for call in calls))
        self.assertTrue(any(call[0] == "cmake" and "--clean-first" in call for call in calls))

    def test_all_shell_scripts_are_syntax_checked(self):
        self.write("tools/second.sh", 'if true; then\necho "unclosed if"\n')
        result, calls = self.run_script("--scope", "static", succeeds=False)
        self.assertIn("tools/second.sh", result.stderr)
        self.assertFalse(any(call[0] in ("go", "cmake") for call in calls))

    def test_invalid_scope_fails_before_work(self):
        result, calls = self.run_script("--scope", "typo", succeeds=False)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(calls, [])

    def test_missing_scope_value_is_an_error(self):
        result, calls = self.run_script("--scope", succeeds=False)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(calls, [])

    def test_build_failure_is_not_hidden(self):
        self.env["VERIFY_TEST_FAIL_TOOL"] = "cmake"
        result, calls = self.run_script("--scope", "client", "--quick", succeeds=False)
        self.assertEqual(result.returncode, 13)
        self.assertFalse(any(call[0] == "hexproof" for call in calls))

    def test_version_parity_is_still_enforced(self):
        self.env["VERIFY_TEST_SERVER_VERSION"] = "1.2.2"
        result, _ = self.run_script("--scope", "server", succeeds=False)
        self.assertIn("does not match source version", result.stderr)


if __name__ == "__main__":
    unittest.main()
