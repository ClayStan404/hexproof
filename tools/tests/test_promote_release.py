#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Mock GitHub mutation only; exercise fresh evidence and frozen release gates."""

import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
spec = importlib.util.spec_from_file_location('promote_release', ROOT / 'tools/promote-release.py')
promotion = importlib.util.module_from_spec(spec)
spec.loader.exec_module(promotion)
tls = promotion.tls_check


class PromotionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.now = int(time.time())
        self.source = {'sourceCommit': 'a' * 40, 'sourceTree': 'b' * 40, 'sourceVersion': '4.5.6',
                       'sourceRepository': promotion.REPOSITORY}
        (self.root / 'protocol/v2').mkdir(parents=True)
        (self.root / 'protocol/v2/wire-schema.json').write_text(json.dumps({'protocol': 'hexproof.v2'}))
        self.assets = self.root / 'assets'
        self.assets.mkdir()
        (self.assets / 'package.tar.gz').write_bytes(b'Fixture binary package')
        (self.assets / 'compatibility.json').write_text(json.dumps({'schemaVersion': 1,
            'applicationVersion': '4.5.6', 'gameProtocol': 'hexproof.v2'}))
        sums = {path.name: promotion.qualification.sha256(path) for path in self.assets.iterdir()}
        (self.assets / 'SHA256SUMS').write_text(''.join(f'{sha}  {name}\n' for name, sha in sorted(sums.items())))
        self.release = {'id': 123, 'tag_name': 'v4.5.6', 'name': '4.5.6', 'draft': True, 'prerelease': False,
                        'body': 'Frozen bilingual notes', 'assets': [
                            {'id': index, 'name': path.name, 'size': path.stat().st_size,
                             'state': 'uploaded', 'updated_at': '2026-01-01T00:00:00Z',
                             'digest': 'sha256:' + promotion.qualification.sha256(path)}
                            for index, path in enumerate(sorted(self.assets.iterdir()), 1)]}
        self.ops = {'activation': 'active', 'release': {'publishMode': 'publish-after-checks'},
                    'native': {'allowedAgentIds': ['reviewer', 'author']}}
        self.write('operations', self.ops)
        bootstrap = json.dumps({'schemaVersion': 2, 'revision': 1, 'directoryUrls': ['https://directory.invalid/catalog'],
                                'servers': [{'id': 'hub-a', 'url': 'wss://hub.invalid/ws'}]}).encode()
        (self.root / 'bootstrap').write_bytes(bootstrap)
        self.write('inventory', {'schemaVersion': 1, 'bootstrapSha256': hashlib.sha256(bootstrap).hexdigest(),
                               'endpoints': [{'id': 'hub-a', 'origin': 'wss://hub.invalid', 'serviceGroup': 'cloud-a'},
                                             {'id': 'catalog-a', 'origin': 'https://directory.invalid',
                                              'serviceGroup': 'cloud-a'}]})
        self.inventory = tls.read_inventory(self.root / 'inventory', self.root / 'bootstrap')
        self.evidence = {'schemaVersion': 1, 'kind': tls.KIND,
                         'collectedAt': tls.utc(self.now), 'completedAt': tls.utc(self.now),
                         'inventorySha256': self.inventory['inventorySha256'],
                         'bootstrapSha256': self.inventory['bootstrapSha256'],
                         'minimumRemainingSeconds': 48 * 3600, 'result': 'pass', 'endpoints': [
                             {'id': row['id'], 'serviceGroup': 'cloud-a', 'result': 'pass', 'error': '',
                              'notAfter': tls.utc(self.now + 60 * 3600)} for row in self.inventory['endpoints']]}
        frozen = promotion.identity(self.release, self.source['sourceCommit'], self.source['sourceTree'])
        self.readiness = {'schemaVersion': 1, 'identitySha256': promotion.identity_digest(frozen),
                          'bootstrapSha256': self.inventory['bootstrapSha256'],
                          'review': {'verdict': 'APPROVE', 'reviewerId': 'reviewer', 'implementerId': 'author',
                                     'evidenceRef': 'native exact frozen draft review'},
                          'updateReadiness': {'result': 'pass', 'evidenceRef': 'private exact fleet check'},
                          'packaging': {'runId': 456, 'sha256': {path.name: promotion.qualification.sha256(path)
                                                               for path in self.assets.iterdir()}}}
        self.write('readiness', self.readiness)
        self.args = argparse.Namespace(command='promote', repo=self.root, operations=self.root / 'operations',
            inventory=self.root / 'inventory', bootstrap=self.root / 'bootstrap', assets=self.assets,
            readiness=self.root / 'readiness', journal=self.root / 'journal', release_id=123, tag='v4.5.6')
        self.mutations = []
        self.attested = []
        self.qualified = 0
        self.revoked = False
        self.drift = False
        self.uncertain = False
        self.remains_draft = False

    def write(self, name, document):
        (self.root / name).write_text(json.dumps(document))

    def github(self, path, payload=None):
        if payload:
            self.mutations.append(payload)
            if not self.remains_draft:
                self.release['draft'] = False
            if self.uncertain:
                raise OSError('lost response')
        if '/git/ref/tags/' in path:
            return {'object': {'type': 'commit', 'sha': self.source['sourceCommit']}}
        if '/actions/runs/' in path:
            return {'head_sha': self.source['sourceCommit'], 'conclusion': 'success', 'event': 'push',
                    'head_branch': self.args.tag, 'path': '.github/workflows/release.yml'}
        if '/releases/' in path:
            result = copy.deepcopy(self.release)
            if self.drift and self.qualified >= 2:
                result['body'] += ' altered'
            return result
        raise AssertionError(path)

    def qualify(self, args):
        self.qualified += 1
        if self.revoked and self.qualified >= 2:
            raise promotion.qualification.VerificationError('revoked')
        return {'publicTree': self.source['sourceTree']}

    def execute(self, collector=None, wall=None):
        return promotion.promote(self.args, github=self.github, collector=collector or (lambda inv: self.evidence),
                                 wall=wall or (lambda: self.now),
                                 attest=lambda path, tag, sha: self.attested.append(path.name),
                                 qualify=self.qualify, clean=lambda repo: dict(self.source))

    def test_fresh_complete_gate_promotes_and_uncertain_success_reads_back_without_second_mutation(self):
        self.uncertain = True
        result = self.execute()
        self.assertEqual(result['result'], 'PUBLISHED')
        self.assertEqual(len(self.mutations), 1)
        self.assertEqual(set(self.attested), {path.name for path in self.assets.iterdir()})
        journal = json.loads(self.args.journal.read_text())
        self.assertEqual(journal['binding']['bootstrapSha256'], self.inventory['bootstrapSha256'])
        self.assertEqual(journal['binding']['commit'], self.source['sourceCommit'])
        self.assertTrue(self.execute()['reconciled'])
        self.assertEqual(len(self.mutations), 1)

    def test_check_never_mutates_and_missing_failing_stale_future_incomplete_gate_refuses(self):
        original = copy.deepcopy(self.evidence)
        variants = [None, dict(original, result='fail'), dict(original, collectedAt=tls.utc(self.now - 301)),
                    dict(original, completedAt=tls.utc(self.now + 1)), dict(original, endpoints=[])]
        for evidence in variants:
            self.evidence = evidence
            with self.subTest(evidence=evidence), self.assertRaises(ValueError):
                self.execute()
            self.assertEqual(self.mutations, [])
        self.evidence = original
        self.args.command = 'check'
        self.assertEqual(self.execute()['result'], 'READY')
        self.assertEqual(self.mutations, [])

    def test_lifetime_recomputed_immediately_before_mutation(self):
        calls = 0
        def advancing():
            nonlocal calls
            calls += 1
            return self.now if calls == 1 else self.now + 2
        # Give fresh timestamps at boundary but less than the floor left.
        def evidence(inv):
            value = copy.deepcopy(self.evidence)
            for row in value['endpoints']:
                row['notAfter'] = tls.utc(self.now + 48 * 3600 + 1)
            return value
        with self.assertRaisesRegex(ValueError, 'near_expiry'):
            self.execute(collector=evidence, wall=advancing)
        self.assertEqual(self.mutations, [])

    def test_revoked_qualification_and_notes_asset_tag_bootstrap_identity_drift_block_mutation(self):
        self.revoked = True
        with self.assertRaisesRegex(ValueError, 'revoked'):
            self.execute()
        self.assertEqual(self.mutations, [])
        self.revoked = False
        self.qualified = 0
        self.drift = True
        with self.assertRaisesRegex(ValueError, 'identity_drift'):
            self.execute()
        self.assertEqual(self.mutations, [])
        self.drift = False
        (self.assets / 'package.tar.gz').write_bytes(b'tampered')
        with self.assertRaisesRegex(ValueError, 'asset_identity_drift'):
            self.execute()
        self.assertEqual(self.mutations, [])

    def test_actual_bootstrap_binding_tag_and_asset_inventory_drift_are_refused(self):
        self.readiness['bootstrapSha256'] = '0' * 64
        self.write('readiness', self.readiness)
        with self.assertRaisesRegex(ValueError, 'release_bootstrap_mismatch'):
            self.execute()
        self.readiness['bootstrapSha256'] = self.inventory['bootstrapSha256']
        self.write('readiness', self.readiness)
        original = self.github
        def changed_tag(path, payload=None):
            if '/git/ref/tags/' in path:
                return {'object': {'type': 'commit', 'sha': 'c' * 40}}
            return original(path, payload)
        self.github = changed_tag
        with self.assertRaisesRegex(ValueError, 'tag_identity_drift'):
            self.execute()
        self.github = original
        self.release['assets'].pop()
        with self.assertRaisesRegex(ValueError, 'invalid_assets'):
            self.execute()
        self.assertEqual(self.mutations, [])

    def test_unqualified_readiness_mode_and_published_release_are_refused(self):
        self.ops['release']['publishMode'] = 'draft-only'
        self.write('operations', self.ops)
        with self.assertRaisesRegex(ValueError, 'not_enabled'):
            self.execute()
        self.ops['release']['publishMode'] = 'publish-after-checks'
        self.write('operations', self.ops)
        self.readiness['review']['reviewerId'] = 'author'
        self.write('readiness', self.readiness)
        with self.assertRaisesRegex(ValueError, 'independent_readiness'):
            self.execute()
        self.release['draft'] = False
        with self.assertRaisesRegex(ValueError, 'immutable'):
            self.execute()
        self.assertEqual(self.mutations, [])

    def test_uncertain_promotion_that_stays_draft_is_never_blindly_retried(self):
        self.uncertain = True
        self.remains_draft = True
        with self.assertRaisesRegex(ValueError, 'uncertain'):
            self.execute()
        self.assertEqual(len(self.mutations), 1)
        with self.assertRaisesRegex(ValueError, 'operator_reconciliation_required'):
            self.execute()
        self.assertEqual(len(self.mutations), 1)


if __name__ == '__main__':
    unittest.main()
