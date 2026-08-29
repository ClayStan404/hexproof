# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import configparser
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "tools" / "run-multiclient.sh"


class MultiClientScriptTest(unittest.TestCase):
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

    def run_script(self, *arguments, check=True):
        return subprocess.run(
            [str(SCRIPT), *arguments],
            cwd=REPO_ROOT,
            check=check,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
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
            self.assertIn(f"HEXPROOF_TEST_INSTANCE=client-{number:02d}", environment)
            self.assertNotIn("HEXPROOF_SERVER_1_URL=", environment)

            arguments = observed_arguments.read_text(encoding="utf-8").splitlines()
            self.assertEqual(
                arguments,
                ["--instance-label", f"Draft Seat {number}", "--windowed"],
            )

            settings = configparser.ConfigParser(interpolation=None)
            settings.optionxform = str
            settings.read(profile / "config" / "Hexproof" / "Hexproof.conf")
            self.assertEqual(
                settings["network"]["resumeDisplayName"], f"Draft Seat {number}"
            )
            self.assertEqual(
                settings["network"]["resumeServerUrl"],
                "ws://127.0.0.1:6000/ws",
            )
            self.assertEqual(
                settings["network"]["customServerUrl"],
                "ws://127.0.0.1:6000/ws",
            )

        status = self.run_script("status", "--profiles-root", str(self.profiles))
        self.assertIn("client-01 running", status.stdout)
        self.assertIn("client-02 running", status.stdout)

        stopped = self.run_script("stop", "--profiles-root", str(self.profiles))
        self.assertIn("Stopping client-01", stopped.stdout)
        self.assertIn("Stopping client-02", stopped.stdout)

        settings_path = (
            self.profiles / "client-01" / "config" / "Hexproof" / "Hexproof.conf"
        )
        settings = configparser.ConfigParser(interpolation=None)
        settings.optionxform = str
        settings.read(settings_path)
        settings["network"]["resumeToken"] = "preserved-token"
        with settings_path.open("w", encoding="utf-8") as output:
            settings.write(output, space_around_delimiters=False)

        self.run_script(
            "start",
            "--count",
            "2",
            "--binary",
            str(self.fake_client),
            "--profiles-root",
            str(self.profiles),
            "--no-template",
            "--server",
            "ws://127.0.0.1:7000/ws",
        )
        updated = configparser.ConfigParser(interpolation=None)
        updated.optionxform = str
        updated.read(settings_path)
        self.assertEqual(
            updated["network"]["customServerUrl"],
            "ws://127.0.0.1:7000/ws",
        )
        self.assertEqual(
            updated["network"]["resumeServerUrl"],
            "ws://127.0.0.1:7000/ws",
        )
        self.assertNotIn("resumeToken", updated["network"])

    def test_clones_mutable_data_and_hard_links_initial_art(self):
        template = self.root / "template"
        images = template / "images"
        images.mkdir(parents=True)
        (template / "cards.sqlite").write_bytes(b"database")
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
        image_copy = app_data / "images" / "card.jpg"
        self.assertEqual(database_copy.read_bytes(), b"database")
        self.assertNotEqual(
            os.stat(database_copy).st_ino,
            os.stat(template / "cards.sqlite").st_ino,
        )
        self.assertEqual(os.stat(image_copy).st_ino, os.stat(image).st_ino)
        cloned_deck = json.loads((app_data / "decks.json").read_text(encoding="utf-8"))
        self.assertEqual(cloned_deck["imagePath"], str(image_copy))

    def test_rejects_invalid_count(self):
        result = self.run_script("start", "--count", "0", check=False)
        self.assertEqual(result.returncode, 2)
        self.assertIn("--count must be an integer", result.stderr)


if __name__ == "__main__":
    unittest.main()
