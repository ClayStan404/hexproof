# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "tools" / "run-multiclient.sh"


class MultiClientScriptTest(unittest.TestCase):
    def test_configured_art_location_is_cloned_not_shared(self):
        template = self.root / "template"
        template.mkdir()
        profile_key = hashlib.sha256(str(template.resolve()).encode()).hexdigest()[:20]
        base = self.root / "external disk"
        managed = base / ("hexproof-art-" + profile_key)
        for folder in ("images", "custom-art"):
            (managed / folder).mkdir(parents=True)
            (managed / folder / "test.png").write_bytes(folder.encode())
        (managed / ".hexproof-art-owner.json").write_text(json.dumps({"profileKey": profile_key}))
        (template / "card-art-storage.json").write_text(json.dumps({
            "format": "hexproof.card-art-storage", "version": 1,
            "profileKey": profile_key, "baseDirectory": str(base),
            "previousImageRoots": [str(template / "images")],
        }))
        (template / ".hexproof-art.lock").write_text("source process lock")
        (template / "card-cache.json").write_text(json.dumps({
            "imagePath": str(managed / "images" / "test.png"),
            "oldImagePath": str(template / "images" / "test.png"),
        }))
        self.run_script("--count", "1", "--binary", str(self.fake_client),
                        "--profiles-root", str(self.profiles), "--template", str(template))
        copied = self.profiles / "client-01" / "data" / "Hexproof" / "Hexproof"
        for folder in ("images", "custom-art"):
            self.assertEqual((copied / folder / "test.png").read_bytes(), folder.encode())
        self.assertFalse((copied / "card-art-storage.json").exists())
        self.assertFalse((copied / ".hexproof-art.lock").exists())
        index = json.loads((copied / "card-cache.json").read_text())
        self.assertEqual(index["imagePath"], str(copied / "images" / "test.png"))
        self.assertEqual(index["oldImagePath"], index["imagePath"])

    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.profiles = self.root / "profiles"
        self.fake_client = self.root / "fake-client"
        self.fake_client.write_text(
            """#!/usr/bin/env bash
set -eu
printf '%s\\n' \"$@\" >\"$HEXPROOF_TEST_PROFILE_ROOT/observed-args\"
env >\"$HEXPROOF_TEST_PROFILE_ROOT/observed-env\"
trap 'exit 0' TERM INT
while :; do sleep 1; done
""",
            encoding="utf-8",
        )
        self.fake_client.chmod(0o755)

    def tearDown(self):
        subprocess.run(
            [
                str(SCRIPT),
                "stop",
                "--profiles-root",
                str(self.profiles),
            ],
            cwd=REPO_ROOT,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.temporary_directory.cleanup()

    def run_script(self, *arguments, check=True, env=None):
        return subprocess.run(
            [str(SCRIPT), *arguments],
            cwd=REPO_ROOT,
            check=check,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )

    def wait_for(self, path):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if path.exists():
                return
            time.sleep(0.05)
        self.fail(f"timed out waiting for {path}")

    def test_starts_isolated_named_clients_and_stops_them(self):
        result = self.run_script(
            "start",
            "--count",
            "2",
            "--binary",
            str(self.fake_client),
            "--profiles-root",
            str(self.profiles),
            "--no-template",
            "--server",
            "ws://127.0.0.1:6000/ws",
            "--name-prefix",
            "Draft Seat",
            "--windowed",
        )
        self.assertIn("Started client-01 as 'Draft Seat 1'", result.stdout)
        self.assertIn("Started client-02 as 'Draft Seat 2'", result.stdout)

        for number in (1, 2):
            profile = self.profiles / f"client-{number:02d}"
            observed_environment = profile / "observed-env"
            observed_arguments = profile / "observed-args"
            self.wait_for(observed_environment)
            self.wait_for(observed_arguments)

            environment = observed_environment.read_text(encoding="utf-8")
            self.assertIn(f"XDG_DATA_HOME={profile / 'data'}", environment)
            self.assertIn(f"XDG_CONFIG_HOME={profile / 'config'}", environment)
            self.assertIn(f"XDG_CACHE_HOME={profile / 'cache'}", environment)
            self.assertIn(f"HEXPROOF_TEST_INSTANCE=client-{number:02d}", environment)
            self.assertIn(f"HEXPROOF_TEST_PROFILE_ROOT={profile}", environment)
            self.assertNotIn("HEXPROOF_SERVER_1_URL=", environment)

            arguments = observed_arguments.read_text(encoding="utf-8").splitlines()
            self.assertEqual(
                arguments,
                [
                    "--instance-label", f"Draft Seat {number}",
                    "--server-url", "ws://127.0.0.1:6000/ws",
                    "--display-name", f"Draft Seat {number}", "--windowed",
                ],
            )
            self.assertFalse((profile / "config" / "Hexproof" / "Hexproof.conf").exists())

        status = self.run_script("status", "--profiles-root", str(self.profiles))
        self.assertIn("client-01 running", status.stdout)
        self.assertIn("client-02 running", status.stdout)

        stopped = self.run_script("stop", "--profiles-root", str(self.profiles))
        self.assertIn("Stopping client-01", stopped.stdout)
        self.assertIn("Stopping client-02", stopped.stdout)

        settings_path = (
            self.profiles / "client-01" / "config" / "Hexproof" / "Hexproof.conf"
        )
        # Only Qt should interpret and update QSettings, including credentials.
        original_settings = (
            b'[network]\nresumeToken=preserved-token\n'
            b'resumeRoomRole=player\nresumeDisplayName=Draft Seat 1\n'
            b'resumeServerUrl=ws://127.0.0.1:6000/ws\n'
            b'[preferences]\nopaque=@ByteArray(\\0\\x1)\n'
        )
        settings_path.write_bytes(original_settings)

        self.run_script(
            "start",
            "--count",
            "2",
            "--binary",
            str(self.fake_client),
            "--profiles-root",
            str(self.profiles),
            "--template",
            str(self.root / "missing-template"),
            "--server",
            "ws://127.0.0.1:7000/ws",
            "--name-prefix",
            "New Seat",
        )
        self.assertEqual(settings_path.read_bytes(), original_settings)
        for number in (1, 2):
            arguments = (self.profiles / f"client-{number:02d}" / "observed-args").read_text()
            self.assertIn("--server-url\nws://127.0.0.1:7000/ws\n", arguments)
            self.assertIn(f"--display-name\nNew Seat {number}\n", arguments)

    def test_defaults_and_process_ownership_are_profile_scoped(self):
        arguments = (
            "start", "--count", "01", "--binary", str(self.fake_client),
            "--profiles-root", str(self.profiles), "--no-template",
        )
        self.run_script(*arguments)
        profile = self.profiles / "client-01"
        self.wait_for(profile / "observed-args")
        self.assertEqual(
            (profile / "observed-args").read_text().splitlines(),
            ["--instance-label", "Test Player 1", "--server-url",
             "ws://127.0.0.1:57320/ws", "--display-name", "Test Player 1"],
        )
        pid_file = self.profiles / "pids" / "client-01.pid"
        pid = pid_file.read_text()
        restarted = self.run_script(*arguments)
        self.assertIn("client-01 is already running", restarted.stdout)
        self.assertEqual(pid_file.read_text(), pid)

        other_root = self.root / "other-profiles"
        other_pid = other_root / "pids" / "client-01.pid"
        other_pid.parent.mkdir(parents=True)
        other_pid.write_text(pid)
        status = self.run_script("status", "--profiles-root", str(other_root))
        self.assertIn("stale pid file", status.stdout)
        self.run_script("stop", "--profiles-root", str(other_root))
        self.assertFalse(other_pid.exists())
        status = self.run_script("status", "--profiles-root", str(self.profiles))
        self.assertIn("client-01 running", status.stdout)

    def test_rejects_concurrent_profile_mutation(self):
        self.profiles.mkdir()
        with (self.profiles / ".launcher.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            for command in ("start", "stop"):
                result = self.run_script(command, "--profiles-root", str(self.profiles),
                                         check=False)
                self.assertEqual(result.returncode, 1)
                self.assertIn("Another launcher", result.stderr)
            self.assertFalse((self.profiles / "client-01").exists())
            self.run_script("status", "--profiles-root", str(self.profiles))

    def test_clones_mutable_data_and_hard_links_initial_art(self):
        template = self.root / "template"
        images = template / "images"
        images.mkdir(parents=True)
        (template / "cards.sqlite").write_bytes(b"database")
        (template / "profile.lock").write_text("live source profile lock", encoding="utf-8")
        image = images / "card.jpg"
        image.write_bytes(b"image")
        (template / "decks.json").write_text(
            json.dumps({"imagePath": str(image)}), encoding="utf-8"
        )

        self.run_script(
            "start",
            "--count",
            "1",
            "--binary",
            str(self.fake_client),
            "--profiles-root",
            str(self.profiles),
            "--template",
            str(template),
        )

        app_data = self.profiles / "client-01" / "data" / "Hexproof" / "Hexproof"
        database_copy = app_data / "cards.sqlite"
        self.assertFalse((app_data / "profile.lock").exists())
        image_copy = app_data / "images" / "card.jpg"
        self.assertEqual(database_copy.read_bytes(), b"database")
        self.assertNotEqual(
            os.stat(database_copy).st_ino,
            os.stat(template / "cards.sqlite").st_ino,
        )
        self.assertEqual(os.stat(image_copy).st_ino, os.stat(image).st_ino)
        cloned_deck = json.loads((app_data / "decks.json").read_text(encoding="utf-8"))
        self.assertEqual(cloned_deck["imagePath"], str(image_copy))

    def test_passes_one_unique_event_group_to_every_client(self):
        arguments = (
            "start", "--count", "2", "--binary", str(self.fake_client),
            "--profiles-root", str(self.profiles), "--no-template",
            "--event", "draft", "--set", "eoe", "--windowed",
        )
        result = self.run_script(*arguments)
        self.assertIn("Preparing draft for 2 players using EOE", result.stdout)
        groups = []
        for number in (1, 2):
            observed = self.profiles / f"client-{number:02d}" / "observed-args"
            self.wait_for(observed)
            args = observed.read_text().splitlines()
            for key, value in (("--test-event", "draft"), ("--test-set", "EOE"),
                               ("--test-players", "2"), ("--test-seat", str(number))):
                self.assertEqual(args[args.index(key) + 1], value)
            groups.append(args[args.index("--test-group") + 1])
        self.assertEqual(groups[0], groups[1])
        self.assertRegex(groups[0], r"^[a-f0-9]{32}$")
        restarted = self.run_script(*arguments, check=False)
        self.assertNotEqual(restarted.returncode, 0)
        self.assertIn("Stop the existing test group", restarted.stderr)
        self.run_script("stop", "--profiles-root", str(self.profiles))
        self.run_script(*arguments)
        args = (self.profiles / "client-01" / "observed-args").read_text().splitlines()
        self.assertNotEqual(args[args.index("--test-group") + 1], groups[0])

    def test_rejects_missing_values_before_consuming_the_next_option(self):
        for option in ("--count", "--binary", "--profiles-root", "--template", "--server",
                       "--name-prefix", "--event", "--set"):
            for suffix in ((), ("--count", "2")):
                with self.subTest(option=option, suffix=suffix):
                    result = self.run_script(option, *suffix, check=False)
                    self.assertEqual(result.returncode, 2)
                    self.assertIn(f"{option} requires", result.stderr)
                    self.assertNotIn("Unknown option", result.stderr)

    def test_falls_back_to_independent_copies_after_partial_hard_link_failure(self):
        template = self.root / "template"
        images = template / "images"
        images.mkdir(parents=True)
        original = images / "card.png"
        original.write_bytes(b"original image")
        wrappers = self.root / "wrappers"
        wrappers.mkdir()
        real_cp = shutil.which("cp")
        self.assertIsNotNone(real_cp)
        wrapper = wrappers / "cp"
        # Simulate a failed link tree after one or more links have succeeded.
        wrapper.write_text(
            '#!/usr/bin/env bash\n'
            f'if [[ "$1" == "-al" ]]; then "{real_cp}" "$@"; exit 1; fi\n'
            f'exec "{real_cp}" "$@"\n',
            encoding="utf-8",
        )
        wrapper.chmod(0o755)
        environment = dict(os.environ, PATH=f"{wrappers}:{os.environ['PATH']}")
        result = self.run_script(
            "start", "--count", "1", "--binary", str(self.fake_client),
            "--profiles-root", str(self.profiles), "--template", str(template),
            check=False, env=environment,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("copying card images", result.stderr)
        cloned = self.profiles / "client-01/data/Hexproof/Hexproof/images/card.png"
        self.assertEqual(cloned.read_bytes(), b"original image")
        self.assertNotEqual(cloned.stat().st_ino, original.stat().st_ino)
        cloned.write_bytes(b"edited clone")
        self.assertEqual(original.read_bytes(), b"original image")

    def test_rejects_invalid_or_remote_automatic_event_setup(self):
        for args in (
            ("--event", ""), ("--set", ""),
            ("--event", "cube", "--set", "EOE"),
            ("--event", "draft"), ("--set", "EOE"),
            ("--event", "draft", "--set", "EOE", "--count", "9"),
            ("--event", "sealed", "--set", "EOE", "--count", "1"),
            ("--event", "draft", "--set", "EOE", "--server", "ws://192.0.2.1/ws"),
            ("--event", "draft", "--set", "EOE", "--server", "ws://localhost:99999/ws"),
            ("--event", "draft", "--set", "EOE", "--", "--test-seat", "1"),
        ):
            with self.subTest(args=args):
                result = self.run_script("start", "--profiles-root", str(self.profiles),
                                         *args, check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.profiles / "client-01").exists())

    def test_prepares_all_profiles_before_any_event_client_starts(self):
        invalid_profile = self.profiles / "client-02"
        invalid_profile.mkdir(parents=True)
        (invalid_profile / "user-file").write_text("keep this file")
        result = self.run_script(
            "start", "--count", "2", "--binary", str(self.fake_client),
            "--profiles-root", str(self.profiles), "--no-template",
            "--event", "sealed", "--set", "EOE", check=False,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("no automatic event clients were launched", result.stderr)
        self.assertFalse((self.profiles / "client-01" / "observed-args").exists())
        self.assertEqual((invalid_profile / "user-file").read_text(), "keep this file")

    def test_rejects_invalid_count(self):
        for count in ("0", "17", "-1", "x", "18446744073709551617"):
            with self.subTest(count=count):
                result = self.run_script("start", "--count", count, check=False)
                self.assertEqual(result.returncode, 2)
                self.assertIn("--count must be an integer", result.stderr)

    def test_accepts_zero_padded_decimal_count(self):
        result = self.run_script("start", "--count", "08", "--profiles-root",
                                 str(self.profiles), "--binary",
                                 str(self.root / "missing-client"), check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Client binary is not executable", result.stderr)


if __name__ == "__main__":
    unittest.main()
