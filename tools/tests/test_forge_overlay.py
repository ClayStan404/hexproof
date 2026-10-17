# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Check adapter identity and safe, reproducible source/bytecode packaging."""

import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import tarfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

from test_forge_diagnostic_symbols import class_file

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("forge_overlay", ROOT / "third_party/forge-runtime/build-overlay.py")
OVERLAY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(OVERLAY)


class ForgeOverlayTests(unittest.TestCase):
    def test_jdk21_discovery_ignores_newer_system_compiler(self):
        compiler = Path("fixture JDK 21/bin/javac")
        def version(command, **_kwargs):
            text = "javac 27" if command[0] == "system-javac" else "javac 21.0.12.1"
            return subprocess.CompletedProcess(command, 0, stdout="", stderr=text)
        with patch.dict(OVERLAY.os.environ, {}, clear=True), \
                patch.object(OVERLAY.TOOLCHAIN.sys, "platform", "linux"), \
                patch.object(OVERLAY.shutil, "which", side_effect=lambda name: "system-javac" if name in ("javac", "javac.exe") else name), \
                patch.object(Path, "glob", return_value=[compiler]), \
                patch.object(OVERLAY.subprocess, "run", side_effect=version):
            self.assertEqual(OVERLAY.find_javac(), str(compiler.resolve()))

    def test_explicit_newer_compiler_is_rejected_without_fallback(self):
        result = subprocess.CompletedProcess([], 0, stdout="javac 27\n", stderr="")
        with patch.object(OVERLAY.subprocess, "run", return_value=result) as run:
            with self.assertRaisesRegex(ValueError, "requires JDK 21.*javac 27"):
                OVERLAY.find_javac("chosen-javac")
        self.assertEqual(run.call_args.args[0], ["chosen-javac", "-version"])
        self.assertEqual(run.call_count, 1)

    def test_missing_compiler_reports_required_version(self):
        with patch.dict(OVERLAY.os.environ, {}, clear=True), \
                patch.object(OVERLAY.shutil, "which", return_value=None), \
                patch.object(Path, "glob", return_value=[]):
            with self.assertRaisesRegex(ValueError, "Install JDK 21.*JAVA_HOME or --javac"):
                OVERLAY.find_javac()

    def test_environment_jdk_is_selected_before_system_compiler(self):
        home = Path("fixture JDK 21")
        compiler = home / "bin" / ("javac.exe" if OVERLAY.os.name == "nt" else "javac")
        result = subprocess.CompletedProcess([], 0, stdout="javac 21.0.12\n", stderr="")
        with patch.dict(OVERLAY.os.environ, {"JAVA_HOME": str(home)}, clear=True), \
                patch.object(OVERLAY.shutil, "which", side_effect=lambda name: name), \
                patch.object(OVERLAY.subprocess, "run", return_value=result) as run:
            self.assertEqual(OVERLAY.find_javac(), str(compiler.resolve()))
        self.assertEqual(run.call_args.args[0], [str(compiler), "-version"])

    def test_native_build_environment_preserves_parent_settings(self):
        compiler = str(Path("fixture JDK 21/bin/javac").resolve())
        original = {"PATH": "original-tools", "JAVA_HOME": "old-jdk", "BUILD_SETTING": "keep"}
        with patch.dict(OVERLAY.os.environ, original, clear=True), \
                patch.object(OVERLAY.TOOLCHAIN, "find_javac", return_value=compiler):
            selected = OVERLAY.TOOLCHAIN.build_environment()
            self.assertEqual(dict(OVERLAY.os.environ), original)
        self.assertEqual(selected["JAVA_HOME"], str(Path(compiler).parent.parent))
        self.assertEqual(selected["PATH"].split(OVERLAY.os.pathsep)[0], str(Path(compiler).parent))
        self.assertTrue(selected["PATH"].endswith("original-tools"))
        self.assertEqual(selected["BUILD_SETTING"], "keep")

    def test_java_runtime_selection_does_not_require_a_compiler(self):
        home = Path("fixture JRE 21")
        java = home / "bin" / ("java.exe" if OVERLAY.os.name == "nt" else "java")
        result = subprocess.CompletedProcess([], 0, stdout="", stderr='openjdk version "21.0.12.1"\n')
        with patch.dict(OVERLAY.os.environ, {"JAVA_HOME": str(home)}, clear=True), \
                patch.object(OVERLAY.shutil, "which", side_effect=lambda name: name), \
                patch.object(OVERLAY.subprocess, "run", return_value=result) as run:
            self.assertEqual(OVERLAY.TOOLCHAIN.find_java(), str(java.resolve()))
        self.assertEqual(run.call_args.args[0], [str(java), "-version"])

    def test_java_runtime_selection_accepts_version_after_jvm_option_notices(self):
        java = Path("fixture JRE 21/bin/java")
        for name in ("JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS"):
            with self.subTest(option=name):
                result = subprocess.CompletedProcess([], 0, stdout="",
                    stderr=f'Picked up {name}: -Djava.awt.headless=true\nopenjdk version "21.0.12.1"\n')
                with patch.object(OVERLAY.subprocess, "run", return_value=result), \
                        patch.object(OVERLAY.shutil, "which", side_effect=lambda name: name):
                    self.assertEqual(OVERLAY.TOOLCHAIN.find_java(str(java)), str(java.resolve()))

    def test_jvm_option_notice_cannot_make_an_incompatible_runtime_look_like_java21(self):
        for version in ("17.0.12", "27"):
            with self.subTest(version=version):
                result = subprocess.CompletedProcess([], 0, stdout="",
                    stderr=f'Picked up JAVA_TOOL_OPTIONS: -Dmessage="java 21"\nopenjdk version "{version}"\n')
                with patch.object(OVERLAY.subprocess, "run", return_value=result):
                    with self.assertRaisesRegex(ValueError, "requires a Java 21 runtime"):
                        OVERLAY.TOOLCHAIN.find_java("chosen-java")

    def test_printing_data_participates_in_runtime_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            host = Path(temporary) / "host"
            shutil.copytree(OVERLAY.HOST, host)
            with patch.object(OVERLAY, "HOST", host):
                before, records = OVERLAY.identity()
                name = "src/main/resources/org/hexproof/forge/printing-aliases.tsv"
                self.assertIn(name, records)
                resource = host / name
                resource.write_text(resource.read_text() + "# new reviewed catalog revision\n")
                after, _ = OVERLAY.identity()
                self.assertNotEqual(before, after)

    def test_symbol_generator_participates_in_runtime_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            generator = Path(temporary) / "diagnostic-symbols.py"
            generator.write_bytes(OVERLAY.SYMBOL_GENERATOR.read_bytes())
            with patch.object(OVERLAY, "SYMBOL_GENERATOR", generator):
                before, _ = OVERLAY.identity()
                generator.write_text(generator.read_text() + "\n# reviewed generator change\n")
                self.assertNotEqual(before, OVERLAY.identity()[0])

    def test_build_embeds_reviewed_symbols_from_actual_overlay_classes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            host = root / "host"
            resource = host / "src/main/resources/org/hexproof/forge/printing-aliases.tsv"
            resource.parent.mkdir(parents=True)
            resource.write_text("# fixture\n")
            (host / "native-hooks.patch").write_text("fixture patch")
            upstream = {"revision": "c" * 40, "adapterRevision": 31,
                        "patch": {"file": "native-hooks.patch", "sha256": OVERLAY.digest(host / "native-hooks.patch")}}
            native = class_file("org/hexproof/forge/NativeHost", ["main", "capture"])
            library = root / "forge.jar"
            with zipfile.ZipFile(library, "w") as archive:
                archive.writestr("forge/game/ability/ApiType.class",
                    class_file("forge/game/ability/ApiType", ["values"], ["Draw"]))
            base = root / "base.tar.gz"
            card = b"Name:Known Public Card\nSVar:PrivateScript\n"
            with tarfile.open(base, "w:gz") as archive:
                member = tarfile.TarInfo("hexproof-forge-runtime/forge-gui/res/cardsfolder/test.txt")
                member.size = len(card)
                archive.addfile(member, io.BytesIO(card))
            expected_stage = root / "expected"
            expected_stage.mkdir()
            expected_classes = expected_stage / "classes"
            expected_classes.mkdir()
            (expected_classes / "NativeHost.class").write_bytes(native)
            expected = OVERLAY.diagnostic_symbols(expected_classes, [library], base,
                                                 expected_stage, host, upstream)
            upstream["diagnosticSymbolsSha256"] = hashlib.sha256(expected).hexdigest()
            (host / "upstream.json").write_text(json.dumps(upstream))
            def prepare_sources(_archive, stage):
                (stage / "FORGE-LICENSE").write_text("fixture license")
                return []
            def compile_fixture(command, **_kwargs):
                arguments = json.loads("[" + ",".join(Path(command[1][1:]).read_text().splitlines()) + "]")
                classes = Path(arguments[arguments.index("-d") + 1])
                output = classes / "org/hexproof/forge/NativeHost.class"
                output.parent.mkdir(parents=True)
                output.write_bytes(native)
            args = SimpleNamespace(output=root / "output", cache=root / "cache", base_archive=base,
                                   source_archive=base, source_output=None, javac="fixture-javac")
            with patch.object(OVERLAY, "HOST", host), patch.object(OVERLAY, "pinned_file", return_value=base), \
                    patch.object(OVERLAY, "extract_sources", side_effect=prepare_sources), \
                    patch.object(OVERLAY, "extract_libraries", return_value=[library]), \
                    patch.object(OVERLAY.subprocess, "run", side_effect=compile_fixture):
                record, _ = OVERLAY.build(args)
                with zipfile.ZipFile(args.output / "forge-overlay.jar") as archive:
                    self.assertEqual(archive.read(OVERLAY.SYMBOL_RESOURCE), expected)
                    metadata = json.loads(archive.read("META-INF/hexproof-overlay.json"))
                    self.assertEqual(metadata["diagnosticSymbols"]["sha256"], hashlib.sha256(expected).hexdigest())
                self.assertNotIn(b"PrivateScript", expected)
                upstream["diagnosticSymbolsSha256"] = "0" * 64
                (host / "upstream.json").write_text(json.dumps(upstream))
                with self.assertRaisesRegex(ValueError, "reviewed index"):
                    OVERLAY.build(args)
                # A rejected rebuild preserves the last complete artifact.
                self.assertEqual(OVERLAY.digest(args.output / "forge-overlay.jar"), record["sha256"])

    def test_helper_identity_covers_current_native_sources(self):
        identity, records = OVERLAY.identity()
        source = (ROOT / "apps/server/internal/forgehost/identity.go").read_text()
        self.assertEqual(re.search(r'const RuntimeID = "([^"]+)"', source)[1], identity)
        self.assertGreater(len(records), 10)
        base = json.loads(OVERLAY.BASE_MANIFEST.read_text())
        self.assertEqual(re.search(r'const BaseRuntimeID = "([^"]+)"', source)[1], base["runtimeId"])

    def test_only_java_paths_enter_the_overlay(self):
        delta = (OVERLAY.HOST / "native-hooks.patch").read_text()
        self.assertGreater(len(OVERLAY.patched_paths(delta)), 10)
        for name in ("../../outside.java", "/tmp/outside.java", "forge-game/other.txt"):
            with self.assertRaises(ValueError):
                OVERLAY.patched_paths(f"diff --git a/{name} b/{name}\n")

    def test_deterministic_archives_and_pinned_offline_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first, second = root / "first.jar", root / "second.jar"
            OVERLAY.write_zip(first, {"b.class": b"two", "a.class": b"one"})
            OVERLAY.write_zip(second, {"a.class": b"one", "b.class": b"two"})
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(archive.namelist(), ["a.class", "b.class"])
            pin = {"size": first.stat().st_size, "sha256": hashlib.sha256(first.read_bytes()).hexdigest()}
            self.assertEqual(OVERLAY.pinned_file(pin, root, first), first)
            first.write_bytes(b"modified")
            with self.assertRaisesRegex(ValueError, "checksum"):
                OVERLAY.pinned_file(pin, root, first)

    def test_relocated_source_bundle_keeps_its_toolchain_and_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            base = root / "base-source.tar.gz"
            base.write_bytes(b"synthetic pinned source payload")
            bundle = root / "overlay-source.tar.gz"
            OVERLAY.package_source(bundle, base)
            with tarfile.open(bundle) as archive:
                archive.extractall(root / "relocated", filter="data")
            source = root / "relocated/hexproof-forge-overlay-source"
            builder = source / "third_party/forge-runtime/build-overlay.py"
            result = subprocess.run([sys.executable, str(builder), "--identity"], text=True,
                                    capture_output=True, check=True, timeout=15)
            self.assertEqual(result.stdout.strip(), OVERLAY.identity()[0])
            self.assertEqual((builder.parent / "java-toolchain.py").read_bytes(), OVERLAY.JAVA_TOOLCHAIN.read_bytes())
            self.assertEqual(list(source.rglob("__pycache__")), [])


if __name__ == "__main__":
    unittest.main()
