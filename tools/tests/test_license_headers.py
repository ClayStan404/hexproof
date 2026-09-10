#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "license_headers", Path(__file__).resolve().parents[1] / "check-license-headers.py"
)
licenses = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(licenses)
NOTICE = "SPDX-License-Identifier: GPL-3.0-or-later\nSPDX-FileCopyrightText: 2026 Example"


class LicenseHeaderTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def test_long_leading_notice_does_not_have_to_fit_five_lines(self):
        source = "/*\n" + "Preserved upstream notice.\n" * 40 + NOTICE + "\n*/\nint main() {}\n"
        self.assertEqual(licenses.check_header(self.write("apps/main.cpp", source)), [])

    def test_license_inside_code_does_not_satisfy_header(self):
        source = 'const char *text = R"(' + NOTICE + ')";\n'
        self.assertEqual(len(licenses.check_header(self.write("apps/main.cpp", source))), 2)

    def test_python_shebang_and_module_docstrings_are_supported(self):
        source = '#!/usr/bin/env python3\n"""\n' + NOTICE + '\n"""\nimport sys\n'
        self.assertEqual(licenses.check_header(self.write("tools/example.py", source)), [])

    def test_missing_or_wrong_license_still_fails(self):
        for notice in ("", NOTICE.replace("GPL-3.0-or-later", "MIT"),
                       NOTICE.replace("GPL-3.0-or-later", "GPL-3.0-or-later-invalid")):
            with self.subTest(notice=notice):
                self.assertTrue(licenses.check_header(self.write("apps/main.go", "/*" + notice + "*/\n")))

    def test_powershell_and_cmake_block_comments(self):
        for name, opening, closing in (("tools/test.ps1", "<#", "#>"),
                                      ("packaging/test.cmake", "#[=[", "]=]")):
            with self.subTest(name=name):
                self.assertEqual(licenses.check_header(self.write(name, opening + NOTICE + closing)), [])

    def test_git_scope_includes_new_python_but_not_ignored_outputs(self):
        subprocess.run(["git", "init", "--quiet", str(self.root)], check=True)
        self.write(".gitignore", "apps/client-qt/generated-local/\n")
        expected = self.write("tools/example.py", "# " + NOTICE.replace("\n", "\n# "))
        self.write("apps/client-qt/generated-local/moc.cpp", "generated\n")
        self.write("apps/client-qt/build/moc.cpp", "generated\n")
        self.write("apps/client-qt/vendor/foreign.cpp", "upstream\n")
        self.assertEqual(licenses.source_files(self.root), [expected])

    def test_source_archive_scope_keeps_first_party_templates(self):
        expected = self.write("packaging/server/hexproof-server.service.in", "# " + NOTICE.replace("\n", "\n# "))
        self.write("apps/server/data/local.py", "runtime\n")
        self.write("third_party/library/file.cpp", "foreign\n")
        self.assertEqual(licenses.source_files(self.root), [expected])

    def test_data_named_source_module_is_not_runtime_output(self):
        expected = self.write("apps/client-qt/src/data/model.cpp", "/*\n" + NOTICE + "\n*/")
        self.assertEqual(licenses.source_files(self.root), [expected])

    def test_symlink_target_is_not_treated_as_owned_source(self):
        target = self.write("outside.cpp", "foreign\n")
        link = self.root / "apps/linked.cpp"
        link.parent.mkdir()
        link.symlink_to(target)
        self.assertEqual(licenses.source_files(self.root), [])

    def test_source_archive_can_be_checked_without_git_installed(self):
        expected = self.write("tools/example.py", "# " + NOTICE.replace("\n", "\n# "))
        with patch.object(licenses.subprocess, "run", side_effect=FileNotFoundError("git")):
            self.assertEqual(licenses.source_files(self.root), [expected])


if __name__ == "__main__":
    unittest.main()
