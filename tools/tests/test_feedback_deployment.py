# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Feedback deployment validation and recovery; never contact a real host."""

import importlib.util
import base64
import copy
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import types
import unittest
import zipfile
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("feedback_install_tests", ROOT / "deploy/feedback/install.py")
INSTALL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INSTALL)


class FeedbackDeploymentTests(unittest.TestCase):
    def receiver_config(self, *, public=False, multica=False, smtp=False):
        config = {"schemaVersion": 2 if public else 1, "dataDir": str(INSTALL.DATA),
                  "operatorName": "Fixture operator", "monitoringConfigured": True,
                  "publicUrl": "https://support.example.invalid/feedback/v2" if public else
                               "https://support.example.invalid/feedback/v1",
                  "listen": "127.0.0.1:57324"}
        if smtp or not public:
            config["smtp"] = {"host": "smtp.example.invalid", "port": 587, "tlsMode": "starttls",
                              "from": "support@example.invalid", "to": "support@example.invalid"}
        if smtp:
            config["smtp"].update(username="fixture", passwordFile=str(INSTALL.PASSWORD))
        if public:
            config["public"] = {"dataDir": str(INSTALL.PUBLIC_DATA), "tokenFile": str(INSTALL.GITHUB_TOKEN),
                                "repository": "fixture/public", "repositoryId": 1, "publisherActorId": 2,
                                "noticeRevision": "fixture-v1", "noticeText": "Local fixture only.",
                                "providerPolicyRevision": "fixture-v1" if multica else "none-v1"}
        if multica:
            config["multica"] = {"webhookFile": str(INSTALL.MULTICA_WEBHOOK),
                                 "socket": str(INSTALL.DATA / "native.sock"),
                                 "workspaceId": "11111111-1111-4111-8111-111111111111",
                                 "autopilotId": "22222222-2222-4222-8222-222222222222",
                                 "providerPolicyRevision": "fixture-v1"}
        return config

    def input_files(self, base, config, *, schema=2):
        source = base / "config.json"
        source.write_text(json.dumps(config))
        value = {"schemaVersion": schema, "target": "test-alias", "arch": "amd64", "configFile": str(source)}
        if schema == 1:
            value["smtpPasswordFile"] = ""
        for field, name in (("smtpPasswordFile", "smtp-password"), ("githubTokenFile", "github-token"),
                            ("multicaWebhookFile", "multica-webhook")):
            if name in INSTALL.credential_paths(config):
                credential = base / name
                credential.write_text("fixture-only-" + name)
                credential.chmod(0o600)
                value[field] = str(credential)
        inputs = base / "inputs.json"
        inputs.write_text(json.dumps(value))
        return inputs, value

    def test_atomic_write_does_not_follow_preexisting_temporary_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            destination = base / "config.json"
            victim = base / "private-victim"
            victim.write_text("preserved")
            (base / "config.json.feedback-new").symlink_to(victim)
            INSTALL.atomic_write(destination, b"replacement", 0o600, os.getuid(), os.getgid())
            self.assertEqual(destination.read_text(), "replacement")
            self.assertEqual(victim.read_text(), "preserved")
            self.assertEqual(destination.stat().st_mode & 0o777, 0o600)
            self.assertEqual(list(base.glob(".config.json.feedback-*")), [])

    def test_release_entry_rejects_implicit_targets_and_version_without_network(self):
        for variables in ({}, {"HEXPROOF_VERSION": "2.5.0"},
                          {"HEXPROOF_VERSION": "2.5.0", "HEXPROOF_TARGETS": "cloud-b home-b"}):
            environment = {name: value for name, value in os.environ.items() if not name.startswith("HEXPROOF_")}
            environment.update(variables, HEXPROOF_COMPONENT="feedback")
            result = subprocess.run(["bash", str(ROOT / "deploy/deploy-release-server.sh")],
                                    env=environment, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 2)
            self.assertIn("explicit version, one target and feedback inputs", result.stderr)

    def test_actions_inputs_are_explicit_feedback_only_and_not_draft(self):
        common = {"HEXPROOF_COMPONENT": "feedback", "HEXPROOF_VERSION": "3.1.0",
                  "HEXPROOF_TARGETS": "cloud-b", "HEXPROOF_FEEDBACK_INPUTS": "/fixture/inputs.json"}
        complete = {"HEXPROOF_FEEDBACK_TEST_RUN_ID": "123", "HEXPROOF_FEEDBACK_TEST_ARTIFACT_ID": "456",
                    "HEXPROOF_FEEDBACK_TEST_HEAD_SHA": "a" * 40}
        changes = [{"HEXPROOF_FEEDBACK_TEST_RUN_ID": "123"},
                   {**complete, "HEXPROOF_ALLOW_DRAFT": "1"},
                   {**complete, "HEXPROOF_FEEDBACK_TEST_RUN_ID": "0"},
                   {**complete, "HEXPROOF_COMPONENT": "game"},
                   {"HEXPROOF_FEEDBACK_TEST_ARCHIVE": "/fixture/artifact.zip"}]
        for change in changes:
            with self.subTest(change=change):
                environment = {name: value for name, value in os.environ.items() if not name.startswith("HEXPROOF_")}
                environment.update(common)
                environment.update(change)
                result = subprocess.run(["bash", str(ROOT / "deploy/deploy-release-server.sh")],
                                        env=environment, capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 2)
                self.assertIn("Feedback", result.stderr)

    def actions_fixture(self, base):
        version, run_id, artifact_id, head = "3.1.0", 123, 456, "a" * 40
        payload = {f"Hexproof-{version}-linux-x86_64.tar.gz": b"linux",
                   f"Hexproof-{version}-windows-x64.zip": b"windows",
                   f"Hexproof-{version}-macos-arm64.zip": b"macos",
                   f"hexproof-server-{version}-linux-amd64.tar.gz": b"amd64",
                   f"hexproof-server-{version}-linux-arm64.tar.gz": b"arm64",
                   "hexproof-forge-overlay-source.tar.gz": b"source",
                   "compatibility.json": json.dumps({"schemaVersion": 1, "applicationVersion": version,
                                                       "gameProtocol": "hexproof.v2"}).encode()}
        payload["SHA256SUMS"] = "".join(hashlib.sha256(content).hexdigest() + "  " + name + "\n"
                                         for name, content in payload.items()).encode()
        archive = base / "artifact.zip"
        self.write_bundle(archive, payload)
        run = {"id": run_id, "repository": {"id": 10, "full_name": "fixture/public"},
               "head_repository": {"id": 10}, "event": "workflow_dispatch", "status": "completed",
               "conclusion": "success", "head_sha": head, "head_branch": "master",
               "path": INSTALL.RELEASE_WORKFLOW, "workflow_id": 20, "run_attempt": 1}
        artifact = {"id": artifact_id, "name": f"Hexproof-{version}-release", "expired": False,
                    "digest": "sha256:" + INSTALL.digest(archive), "size_in_bytes": archive.stat().st_size,
                    "workflow_run": {"id": run_id, "head_sha": head, "repository_id": 10, "head_repository_id": 10}}
        steps = [{"name": name, "conclusion": result} for name, result in (
            ("Upload combined release bundle", "success"), ("Attest release assets", "skipped"),
            ("Create or update draft release", "skipped"))]
        responses = {"actions/runs/123": run, "actions/artifacts/456": artifact,
                     "actions/workflows/release.yml": {"id": 20, "path": INSTALL.RELEASE_WORKFLOW},
                     "contents/" + INSTALL.RELEASE_WORKFLOW + "?ref=" + head:
                     {"encoding": "base64", "content": base64.b64encode((ROOT / INSTALL.RELEASE_WORKFLOW).read_bytes()).decode()},
                     "actions/runs/123/attempts/1/jobs?per_page=100":
                     [{"jobs": [{"name": "Assemble release", "conclusion": "success", "steps": steps}]}]}
        backend = types.SimpleNamespace(github=lambda *args: json.dumps(responses[args[-1].removeprefix("repos/fixture/public/")]))
        return backend, responses, archive, payload

    def write_bundle(self, path, payload):
        with zipfile.ZipFile(path, "w") as archive:
            for name, content in payload.items():
                archive.writestr(name, content)

    def test_successful_manual_build_binds_source_workflow_artifact_and_checksums(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            backend, _, archive, _ = self.actions_fixture(base)
            report = base / "report"
            report.mkdir()
            record, provenance = INSTALL.fetch_test_build(backend, "fixture/public", "3.1.0", "amd64",
                                                         report, 123, 456, "a" * 40, archive)
            self.assertEqual(Path(record["path"]).read_bytes(), b"amd64")
            self.assertFalse(provenance["releaseAttested"])
            self.assertEqual(provenance["mode"], "actions-test-initial-install")
            self.assertEqual(provenance["packageSha256"], hashlib.sha256(b"amd64").hexdigest())
            self.assertEqual(json.loads((report / "test-provenance.json").read_text()), provenance)

    def test_rejects_wrong_repository_run_source_workflow_or_tag_build(self):
        cases = [("actions/runs/123", "repository", {"id": 10, "full_name": "fork/public"}),
                 ("actions/runs/123", "head_repository", {"id": 99}),
                 ("actions/runs/123", "event", "pull_request"),
                 ("actions/runs/123", "conclusion", "failure"),
                 ("actions/runs/123", "status", "in_progress"),
                 ("actions/runs/123", "head_sha", "b" * 40),
                 ("actions/runs/123", "head_branch", "v3.1.0"),
                 ("actions/runs/123", "workflow_id", 99),
                 ("actions/runs/123", "path", ".github/workflows/untrusted.yml"),
                 ("actions/artifacts/456", "expired", True),
                 ("actions/artifacts/456", "id", 99),
                 ("actions/artifacts/456", "digest", None),
                 ("actions/artifacts/456", "name", "not-combined"),
                 ("actions/artifacts/456", "workflow_run", {"id": 123, "head_sha": "b" * 40,
                                                              "repository_id": 10, "head_repository_id": 10})]
        with tempfile.TemporaryDirectory() as directory:
            backend, responses, _, _ = self.actions_fixture(Path(directory))
            original = copy.deepcopy(responses)
            for key, field, value in cases:
                with self.subTest(key=key, field=field):
                    responses.clear()
                    responses.update(copy.deepcopy(original))
                    responses[key][field] = value
                    with self.assertRaises(ValueError):
                        INSTALL.test_build_metadata(backend, "fixture/public", "3.1.0", 123, 456, "a" * 40)
            responses.clear()
            responses.update(copy.deepcopy(original))
            responses["contents/" + INSTALL.RELEASE_WORKFLOW + "?ref=" + "a" * 40]["content"] = base64.b64encode(b"unreviewed").decode()
            with self.assertRaisesRegex(ValueError, "trusted local"):
                INSTALL.test_build_metadata(backend, "fixture/public", "3.1.0", 123, 456, "a" * 40)
            responses.clear()
            responses.update(copy.deepcopy(original))
            responses["actions/runs/123/attempts/1/jobs?per_page=100"][0]["jobs"][0]["steps"][1]["conclusion"] = "success"
            with self.assertRaisesRegex(ValueError, "non-tag"):
                INSTALL.test_build_metadata(backend, "fixture/public", "3.1.0", 123, 456, "a" * 40)

    def test_actions_download_rejects_zip_digest_bad_layout_and_every_package_checksum(self):
        for failure in ("digest", "layout", "checksum", "compatibility"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                base = Path(directory)
                backend, responses, archive, payload = self.actions_fixture(base)
                if failure == "layout":
                    payload["../escape"] = b"bad"
                elif failure == "checksum":
                    payload["Hexproof-3.1.0-windows-x64.zip"] = b"changed-other-platform"
                elif failure == "compatibility":
                    payload["compatibility.json"] = b'{"schemaVersion":1,"applicationVersion":"3.0.0","gameProtocol":"hexproof.v2"}'
                else:
                    payload["hexproof-server-3.1.0-linux-amd64.tar.gz"] = b"changed"
                self.write_bundle(archive, payload)
                if failure != "digest":
                    responses["actions/artifacts/456"].update(digest="sha256:" + INSTALL.digest(archive),
                                                             size_in_bytes=archive.stat().st_size)
                report = base / "report"
                report.mkdir()
                with self.assertRaises(ValueError):
                    INSTALL.fetch_test_build(backend, "fixture/public", "3.1.0", "amd64",
                                             report, 123, 456, "a" * 40, archive)
                self.assertFalse((base / "escape").exists())

    def test_test_build_rechecks_identity_after_download(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            backend, _, archive, _ = self.actions_fixture(base)
            first = INSTALL.test_build_metadata(backend, "fixture/public", "3.1.0", 123, 456, "a" * 40)
            report = base / "report"
            report.mkdir()
            with patch.object(INSTALL, "test_build_metadata", side_effect=[first, dict(first, runAttempt=2)]):
                with self.assertRaisesRegex(ValueError, "changed during verification"):
                    INSTALL.fetch_test_build(backend, "fixture/public", "3.1.0", "amd64",
                                             report, 123, 456, "a" * 40, archive)

    def test_feedback_binary_architecture_is_not_inferred_from_filename(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / "hexproof-feedback"
            for arch, machine in (("amd64", 62), ("arm64", 183)):
                binary.write_bytes(b"\x7fELF\x02\x01" + b"\x00" * 12 + machine.to_bytes(2, "little"))
                INSTALL.verify_feedback_architecture(binary, arch)
                with self.assertRaises(ValueError):
                    INSTALL.verify_feedback_architecture(binary, "amd64" if arch == "arm64" else "arm64")
            binary.write_bytes(b"not an ELF binary")
            with self.assertRaises(ValueError):
                INSTALL.verify_feedback_architecture(binary, "amd64")

    def test_default_deployment_still_uses_the_attested_release_backend(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            inputs, _ = self.input_files(base, self.receiver_config(public=True))
            archive = base / "hexproof-server-2.5.0-linux-amd64"
            (archive / "bin").mkdir(parents=True)
            binary = archive / "bin/hexproof-feedback"
            binary.write_bytes(b"release executable")
            binary.chmod(0o755)
            (archive / "deploy").mkdir()
            (archive / "deploy/hexproof-feedback.service.in").write_text(
                (ROOT / "packaging/server/hexproof-feedback.service.in").read_text())
            calls = []

            def fetch(*args):
                calls.append(args)
                return {"artifacts": {"amd64": {"path": str(base / "release.tar.gz"), "sha256": "a" * 64}}}

            backend = types.SimpleNamespace(fetch_release=fetch,
                PACKAGE=types.SimpleNamespace(checked_archive=lambda *args: archive))
            def remote(target, *args):
                return {("uname", "-s"): "Linux", ("uname", "-m"): "x86_64"}.get(args, "")
            with patch.object(INSTALL, "ROOT", base), patch.object(INSTALL, "ssh", side_effect=remote), \
                    patch.object(INSTALL, "load_backend", return_value=backend), \
                    patch.object(INSTALL, "fetch_test_build") as test_fetch, contextlib.redirect_stdout(io.StringIO()):
                INSTALL.deploy("test-alias", "2.5.0", inputs, "fixture/public", False, True)
            test_fetch.assert_not_called()
            self.assertEqual(len(calls), 1)
            self.assertEqual(calls[0][:4], ("fixture/public", "2.5.0", False, {"amd64"}))

    def test_inputs_bind_target_and_private_credential(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            config = base / "config.json"
            config.write_text(json.dumps({"schemaVersion": 1, "dataDir": str(INSTALL.DATA), "operatorName": "Operator",
                                          "monitoringConfigured": True,
                                          "smtp": {"username": "support", "passwordFile": str(INSTALL.PASSWORD)}}))
            secret = base / "secret"
            secret.write_text("test-only-credential")
            secret.chmod(0o600)
            inputs = base / "inputs.json"
            inputs.write_text(json.dumps({"schemaVersion": 1, "target": "test-alias", "arch": "amd64",
                                          "configFile": str(config), "smtpPasswordFile": str(secret)}))
            self.assertEqual(INSTALL.inputs(inputs, "test-alias")[3], "amd64")
            with self.assertRaises(ValueError):
                INSTALL.inputs(inputs, "different-alias")
            secret.chmod(0o644)
            with self.assertRaises(ValueError):
                INSTALL.inputs(inputs, "test-alias")
            secret.chmod(0o600)
            alias = base / "config-link"
            alias.symlink_to(config)
            value = json.loads(inputs.read_text())
            value["configFile"] = str(alias)
            inputs.write_text(json.dumps(value))
            with self.assertRaises(ValueError):
                INSTALL.inputs(inputs, "test-alias")

    def test_public_v2_credentials_are_bound_and_smtp_is_optional(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            config = self.receiver_config(public=True, multica=True)
            inputs, value = self.input_files(base, config)
            parsed, _, credentials, arch = INSTALL.inputs(inputs, "test-alias")
            self.assertNotIn("smtp", parsed)
            self.assertEqual(set(credentials), {"github-token", "multica-webhook"})
            self.assertEqual(arch, "amd64")
            for field in ("githubTokenFile", "multicaWebhookFile"):
                broken = dict(value)
                del broken[field]
                inputs.write_text(json.dumps(broken))
                with self.subTest(field=field), self.assertRaisesRegex(ValueError, "explicit private input"):
                    INSTALL.inputs(inputs, "test-alias")
            broken = dict(value, smtpPasswordFile=str(base / "github-token"))
            inputs.write_text(json.dumps(broken))
            with self.assertRaisesRegex(ValueError, "not referenced"):
                INSTALL.inputs(inputs, "test-alias")

    def test_v2_preserves_authenticated_smtp_for_legacy_deliveries(self):
        with tempfile.TemporaryDirectory() as directory:
            config = self.receiver_config(public=True, multica=True, smtp=True)
            inputs, _ = self.input_files(Path(directory), config)
            parsed, _, credentials, _ = INSTALL.inputs(inputs, "test-alias")
            self.assertEqual(set(credentials), {"smtp-password", "github-token", "multica-webhook"})
            self.assertEqual(parsed["smtp"], config["smtp"])

    def test_input_and_receiver_json_reject_boolean_versions_and_duplicate_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            config = self.receiver_config(public=True)
            inputs, value = self.input_files(base, config)
            for schema in (True, False, 2.0):
                inputs.write_text(json.dumps(dict(value, schemaVersion=schema)))
                with self.subTest(input_schema=schema), self.assertRaises(ValueError):
                    INSTALL.inputs(inputs, "test-alias")
                changed = dict(config, schemaVersion=schema)
                inputs.write_text(json.dumps(value))
                (base / "config.json").write_text(json.dumps(changed))
                with self.subTest(receiver_schema=schema), self.assertRaises(ValueError):
                    INSTALL.inputs(inputs, "test-alias")
            (base / "config.json").write_text(json.dumps(config))
            inputs.write_text(json.dumps(value)[:-1] + ', "target": "other-alias"}')
            with self.assertRaisesRegex(ValueError, "Duplicate"):
                INSTALL.inputs(inputs, "test-alias")
            inputs.write_text(json.dumps(value))
            (base / "config.json").write_text(json.dumps(config).replace(
                '"tokenFile":', '"tokenFile": "duplicate-path", "tokenFile":'))
            with self.assertRaisesRegex(ValueError, "Duplicate"):
                INSTALL.inputs(inputs, "test-alias")

    def test_public_credentials_reject_symlinks_permissions_and_unmanaged_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            config = self.receiver_config(public=True, multica=True)
            inputs, value = self.input_files(base, config)
            for name in ("github-token", "multica-webhook"):
                secret = base / name
                secret.chmod(0o644)
                with self.subTest(name=name), self.assertRaises(ValueError):
                    INSTALL.inputs(inputs, "test-alias")
                secret.chmod(0o600)
                link = base / (name + "-link")
                link.symlink_to(secret)
                field = "githubTokenFile" if name == "github-token" else "multicaWebhookFile"
                inputs.write_text(json.dumps(dict(value, **{field: str(link)})))
                with self.subTest(link=name), self.assertRaises(ValueError):
                    INSTALL.inputs(inputs, "test-alias")
                inputs.write_text(json.dumps(value))
            for section, field, path in (("public", "tokenFile", "/tmp/unmanaged-token"),
                                         ("public", "dataDir", str(INSTALL.DATA / "public")),
                                         ("multica", "webhookFile", "/tmp/unmanaged-webhook"),
                                         ("multica", "socket", str(INSTALL.PUBLIC_DATA / "native.sock"))):
                changed = json.loads(json.dumps(config))
                changed[section][field] = path
                (base / "config.json").write_text(json.dumps(changed))
                with self.subTest(field=field), self.assertRaises(ValueError):
                    INSTALL.inputs(inputs, "test-alias")

    def test_payload_snapshots_credentials_and_gives_public_state_sandbox_access(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            config = self.receiver_config(public=True, multica=True)
            inputs, _ = self.input_files(base, config)
            parsed, _, credentials, _ = INSTALL.inputs(inputs, "test-alias")
            (base / "github-token").write_text("changed-after-input-validation")
            binary = base / "binary"
            binary.write_text("fixture release binary")
            template = ROOT / "packaging/server/hexproof-feedback.service.in"
            payload = base / "payload"
            INSTALL.prepare_payload(payload, parsed, credentials, binary, template)
            self.assertEqual((payload / "github-token").read_bytes(), credentials["github-token"])
            self.assertEqual(json.loads((payload / "config.json").read_text()), config)
            unit = (payload / "hexproof-feedback.service").read_text()
            self.assertIn("StateDirectory=hexproof-feedback hexproof-feedback-public\n", unit)
            self.assertIn("ReadWritePaths=" + str(INSTALL.DATA) + " " + str(INSTALL.PUBLIC_DATA) + "\n", unit)
            for item in payload.iterdir():
                self.assertEqual(item.stat().st_mode & 0o777, 0o600)

    def install_fixture(self, base, *, public, multica=False, smtp=False):
        managed = {"DATA": base / "data", "PUBLIC_DATA": base / "public-data",
                   "CONFIG": base / "etc/config.json", "PASSWORD": base / "etc/smtp-password",
                   "GITHUB_TOKEN": base / "etc/github-token", "MULTICA_WEBHOOK": base / "etc/multica-webhook",
                   "BINARY": base / "bin/hexproof-feedback", "UNIT": base / "systemd/hexproof-feedback.service",
                   "BACKUPS": base / "backups", "TEST_PROVENANCE": base / "etc/test-provenance.json",
                   "SYSTEMD_UNIT_DIRECTORIES": tuple(base / name / "systemd/system"
                                                     for name in ("etc-units", "run", "usr-lib", "lib"))}
        for name in ("BINARY", "CONFIG", "UNIT", "PASSWORD", "GITHUB_TOKEN"):
            managed[name].parent.mkdir(parents=True, exist_ok=True)
            managed[name].write_text("old-" + name)
            managed[name].chmod(0o600)
        for name in ("DATA", "PUBLIC_DATA"):
            managed[name].mkdir()
            (managed[name] / "accepted-record").write_text("must survive binary rollback")
        binary = base / "release-binary"
        binary.write_text("fixture release binary")
        template = base / "unit-template"
        template.write_text((ROOT / "packaging/server/hexproof-feedback.service.in").read_text()
                            .replace(str(INSTALL.DATA), str(managed["DATA"]))
                            .replace(str(INSTALL.BINARY), str(managed["BINARY"])))
        with patch.multiple(INSTALL, **managed):
            config = self.receiver_config(public=public, multica=multica, smtp=smtp)
            inputs, _ = self.input_files(base, config)
            config, _, credentials, _ = INSTALL.inputs(inputs, "test-alias")
            stage = base / "stage"
            INSTALL.prepare_payload(stage, config, credentials, binary, template)
        (stage / "manifest.json").write_text(json.dumps({"version": "2.5.0", "files": {
            item.name: INSTALL.digest(item) for item in stage.iterdir() if item.name != "install.py"}}))
        return managed, config, stage

    def simulated_install(self, managed, stage, *, fail_activation=False, fail_validation=False, test_initial=False):
        calls = []
        checked = []

        def command(*arguments, **kwargs):
            calls.append(tuple(map(str, arguments)))
            if "-version" in arguments:
                return "hexproof-feedback 2.5.0"
            if arguments[:2] == ("systemctl", "show"):
                return "not-found"
            if "-validate-config" in arguments:
                path = Path(arguments[arguments.index("-config") + 1])
                checked.append(json.loads(path.read_text()))
                if fail_validation:
                    raise subprocess.CalledProcessError(1, arguments)
            if fail_activation and tuple(arguments) == ("systemctl", "enable", "--now", INSTALL.SERVICE):
                raise subprocess.CalledProcessError(1, arguments)
            return ""

        user = types.SimpleNamespace(pw_uid=os.getuid() or 1000, pw_gid=os.getgid(), pw_dir=str(managed["DATA"]))
        opener = types.SimpleNamespace(open=lambda *args, **kwargs: contextlib.nullcontext(types.SimpleNamespace(status=200)))
        output = io.StringIO()
        # Only this temporary tree can be mutated; no systemctl/useradd/network request executes.
        with patch.multiple(INSTALL, **managed), \
                patch.object(INSTALL, "run", side_effect=command), \
                patch.object(INSTALL.pwd, "getpwnam", return_value=user), \
                patch.object(INSTALL.os, "geteuid", return_value=0), \
                patch.object(INSTALL.os, "chown"), patch.object(INSTALL.os, "fchown"), \
                patch.object(INSTALL.urllib.request, "build_opener", return_value=opener), \
                patch.object(INSTALL.subprocess, "run", return_value=types.SimpleNamespace(returncode=3 if test_initial else 0)), \
                contextlib.redirect_stdout(output):
            if fail_activation or fail_validation:
                with self.assertRaises(subprocess.CalledProcessError):
                    INSTALL.local_install(stage, "2.5.0", test_initial)
            else:
                INSTALL.local_install(stage, "2.5.0", test_initial)
        return calls, checked, output.getvalue()

    def test_initial_install_rejects_existing_service_files_or_data_before_any_write(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            managed, _, stage = self.install_fixture(base, public=True)
            provenance = {"mode": "actions-test-initial-install", "version": "2.5.0", "releaseAttested": False}
            (stage / "test-provenance.json").write_text(json.dumps(provenance))
            manifest = json.loads((stage / "manifest.json").read_text())
            manifest["files"]["test-provenance.json"] = INSTALL.digest(stage / "test-provenance.json")
            (stage / "manifest.json").write_text(json.dumps(manifest))
            with patch.multiple(INSTALL, **managed), patch.object(INSTALL.os, "geteuid", return_value=0), \
                    patch.object(INSTALL, "run") as command:
                with self.assertRaisesRegex(ValueError, "absent feedback files"):
                    INSTALL.local_install(stage, "2.5.0", test_initial=True)
                command.assert_not_called()
            self.assertEqual(managed["BINARY"].read_text(), "old-BINARY")
            self.assertEqual((managed["PUBLIC_DATA"] / "accepted-record").read_text(), "must survive binary rollback")
            self.assertFalse(managed["TEST_PROVENANCE"].exists())

    def fresh_test_fixture(self, base):
        managed, _, stage = self.install_fixture(base, public=True)
        for name in ("DATA", "PUBLIC_DATA"):
            (managed[name] / "accepted-record").unlink()
            managed[name].rmdir()
        for name in ("BINARY", "CONFIG", "UNIT", "PASSWORD", "GITHUB_TOKEN"):
            managed[name].unlink()
        managed["CONFIG"].parent.rmdir()
        provenance = {"mode": "actions-test-initial-install", "version": "2.5.0", "releaseAttested": False}
        (stage / "test-provenance.json").write_text(json.dumps(provenance))
        manifest = json.loads((stage / "manifest.json").read_text())
        manifest["files"]["test-provenance.json"] = INSTALL.digest(stage / "test-provenance.json")
        (stage / "manifest.json").write_text(json.dumps(manifest))
        return managed, stage, provenance

    def test_initial_install_records_test_provenance_without_touching_game_services(self):
        with tempfile.TemporaryDirectory() as directory:
            managed, stage, provenance = self.fresh_test_fixture(Path(directory))
            calls, _, output = self.simulated_install(managed, stage, test_initial=True)
            self.assertEqual(json.loads(managed["TEST_PROVENANCE"].read_text()), provenance)
            self.assertTrue(json.loads(output)["testBuild"])
            systemctl = [call for call in calls if call[0] == "systemctl"]
            self.assertFalse(any(call[1] in ("stop", "restart") for call in systemctl))
            self.assertTrue(all("hexproof.service" not in call and "hexproof-test.service" not in call for call in systemctl))

    def test_initial_guard_rejects_alias_units_and_rechecks_before_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            managed, stage, _ = self.fresh_test_fixture(Path(directory))
            with patch.multiple(INSTALL, **managed), patch.object(INSTALL, "run", return_value="loaded"):
                with self.assertRaisesRegex(ValueError, "absent feedback service"):
                    INSTALL.require_empty_test_installation()
            with patch.object(INSTALL, "require_empty_test_installation", side_effect=[None, ValueError("appeared")]):
                with self.assertRaisesRegex(ValueError, "appeared"):
                    self.simulated_install(managed, stage, test_initial=True)
            self.assertFalse(managed["CONFIG"].parent.exists())
            self.assertFalse(managed["DATA"].exists())

    def test_both_initial_guards_reject_orphan_dropins_before_artifact_or_service_actions(self):
        for index in range(4):
            with self.subTest(directory=index), tempfile.TemporaryDirectory() as directory:
                base = Path(directory)
                managed, _, _ = self.fresh_test_fixture(base)
                dropin = managed["SYSTEMD_UNIT_DIRECTORIES"][index] / (INSTALL.SERVICE + ".d")
                dropin.mkdir(parents=True)
                (dropin / "override.conf").write_text("[Service]\nExecStart=/unexpected\n")

                def remote(target, *args):
                    if args[:4] == ("sudo", "-n", "python3", "-c"):
                        # The path guard fails before the probe can invoke systemctl.
                        exec(args[4], {})
                        self.fail("Orphan drop-in was accepted by the remote preflight")
                    return {("uname", "-s"): "Linux", ("uname", "-m"): "x86_64"}.get(args, "")

                with patch.multiple(INSTALL, **managed), patch.object(INSTALL, "run") as command:
                    with self.assertRaisesRegex(ValueError, "absent feedback files"):
                        INSTALL.require_empty_test_installation()
                    command.assert_not_called()
                    with patch.object(INSTALL, "ssh", side_effect=remote), \
                            patch.object(INSTALL, "load_backend") as backend:
                        with self.assertRaisesRegex(AssertionError, "absent feedback files"):
                            INSTALL.deploy("test-alias", "2.5.0", base / "inputs.json", "fixture/public",
                                           False, True, 123, 456, "a" * 40)
                        backend.assert_not_called()
                self.assertEqual((dropin / "override.conf").read_text(), "[Service]\nExecStart=/unexpected\n")

    def test_failed_initial_activation_removes_provenance_with_managed_files(self):
        with tempfile.TemporaryDirectory() as directory:
            managed, stage, _ = self.fresh_test_fixture(Path(directory))
            self.simulated_install(managed, stage, test_initial=True, fail_activation=True)
            for name in ("CONFIG", "BINARY", "UNIT", "GITHUB_TOKEN", "TEST_PROVENANCE"):
                self.assertFalse(managed[name].exists())

    def test_public_install_validates_staged_credentials_and_reads_back_modes(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            managed, config, stage = self.install_fixture(base, public=True, multica=True)
            calls, checked, output = self.simulated_install(managed, stage)
            self.assertNotIn("smtp", checked[0])
            self.assertEqual(checked[0]["public"]["tokenFile"], str(stage / "github-token"))
            self.assertEqual(checked[0]["multica"]["webhookFile"], str(stage / "multica-webhook"))
            self.assertEqual(checked[0]["multica"]["socket"], str(managed["DATA"] / "native.sock"))
            self.assertEqual(checked[1], config)
            for name in ("GITHUB_TOKEN", "MULTICA_WEBHOOK", "CONFIG"):
                self.assertEqual(managed[name].stat().st_mode & 0o777, 0o600)
            self.assertEqual(managed["PASSWORD"].read_text(), "old-PASSWORD")
            self.assertEqual(managed["PUBLIC_DATA"].stat().st_mode & 0o777, 0o700)
            readback = json.loads(output)
            self.assertTrue(readback["publicConfigured"])
            self.assertTrue(readback["multicaConfigured"])
            self.assertEqual(readback["configurationSchema"], 2)
            self.assertNotIn("fixture-only", output)
            self.assertIn(("systemctl", "restart", INSTALL.SERVICE), calls)

    def test_failed_activation_restores_all_credentials_and_preserves_both_stores(self):
        with tempfile.TemporaryDirectory() as directory:
            managed, _, stage = self.install_fixture(Path(directory), public=True, multica=True, smtp=True)
            calls, checked, _ = self.simulated_install(managed, stage, fail_activation=True)
            self.assertEqual(checked[0]["smtp"]["passwordFile"], str(stage / "smtp-password"))
            for name in ("BINARY", "CONFIG", "UNIT", "PASSWORD", "GITHUB_TOKEN"):
                self.assertEqual(managed[name].read_text(), "old-" + name)
                self.assertEqual(managed[name].stat().st_mode & 0o777, 0o600)
            self.assertFalse(managed["MULTICA_WEBHOOK"].exists())
            for name in ("DATA", "PUBLIC_DATA"):
                self.assertEqual((managed[name] / "accepted-record").read_text(), "must survive binary rollback")
            self.assertIn(("systemctl", "start", INSTALL.SERVICE), calls)

    def test_invalid_staged_config_never_changes_installed_files(self):
        with tempfile.TemporaryDirectory() as directory:
            managed, _, stage = self.install_fixture(Path(directory), public=True, multica=True)
            calls, _, _ = self.simulated_install(managed, stage, fail_validation=True)
            self.assertFalse(any(call[0] == "systemctl" for call in calls))
            self.assertEqual(managed["GITHUB_TOKEN"].read_text(), "old-GITHUB_TOKEN")
            self.assertFalse(managed["MULTICA_WEBHOOK"].exists())

    def test_missing_or_changed_staged_credentials_fail_before_installation(self):
        for failure in ("missing", "changed", "extra"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                managed, _, stage = self.install_fixture(Path(directory), public=True, multica=True)
                manifest = json.loads((stage / "manifest.json").read_text())
                if failure == "missing":
                    del manifest["files"]["multica-webhook"]
                elif failure == "changed":
                    (stage / "github-token").write_text("changed credential")
                else:
                    (stage / "unexpected-token").write_text("unmapped fixture credential")
                    manifest["files"]["unexpected-token"] = INSTALL.digest(stage / "unexpected-token")
                (stage / "manifest.json").write_text(json.dumps(manifest))
                with patch.multiple(INSTALL, **managed), \
                        patch.object(INSTALL.os, "geteuid", return_value=0), \
                        patch.object(INSTALL, "run", return_value="hexproof-feedback 2.5.0") as command:
                    with self.assertRaises(ValueError):
                        INSTALL.local_install(stage, "2.5.0")
                self.assertFalse(any(call.args[0] == "systemctl" for call in command.call_args_list))
                self.assertEqual(managed["GITHUB_TOKEN"].read_text(), "old-GITHUB_TOKEN")

    def test_public_sandbox_rendering_requires_expected_release_template(self):
        config = self.receiver_config(public=True)
        with self.assertRaisesRegex(ValueError, "fixed feedback state directives"):
            INSTALL.render_unit("[Service]\nReadWritePaths=/\n", config)

    def test_preparation_examples_cannot_be_deployed_without_real_operator_inputs(self):
        for name in ("receiver.public.example.json", "receiver.multica.example.json"):
            config = json.loads((ROOT / "deploy/feedback" / name).read_text())
            with self.subTest(name=name):
                self.assertFalse(config["monitoringConfigured"])
                self.assertEqual(config["public"]["repositoryId"], 0)
                self.assertIn(".invalid/feedback/v2", config["publicUrl"])
                with self.assertRaises(ValueError):
                    INSTALL.credential_paths(config)

    def test_legacy_v1_install_and_readback_remain_supported(self):
        with tempfile.TemporaryDirectory() as directory:
            managed, config, stage = self.install_fixture(Path(directory), public=False, smtp=True)
            _, checked, output = self.simulated_install(managed, stage)
            self.assertEqual(checked[0]["smtp"]["passwordFile"], str(stage / "smtp-password"))
            self.assertEqual(checked[1], config)
            self.assertFalse(json.loads(output)["publicConfigured"])


if __name__ == "__main__":
    unittest.main()
