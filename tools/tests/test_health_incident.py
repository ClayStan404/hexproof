#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise the supported CLI boundary without creating native test issues."""

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'deploy/monitoring'))
import health_alerts

spec = importlib.util.spec_from_file_location('health_incident', ROOT / 'tools/health-incident.py')
incident = importlib.util.module_from_spec(spec)
spec.loader.exec_module(incident)


def identifier():
    return str(uuid.uuid4())


class NativeCLI:
    def __init__(self, trust):
        self.trust = trust
        self.runs = []
        self.issues = {}
        self.metadata = {}
        self.creates = 0
        self.lost_create = False
        self.fail_metadata = False
        self.no_task = False
        self.all_pages = False
        self.calls = []

    def __call__(self, *args):
        self.calls.append(args)
        if args[:2] == ('autopilot', 'runs'):
            offset = int(args[args.index('--offset') + 1])
            if self.all_pages:
                return 0, {'runs': [dict(self.runs[0], id=identifier()) for _ in range(50)], 'total': 501}
            return 0, {'runs': self.runs[offset:offset + 50], 'total': len(self.runs)}
        if args[:2] == ('issue', 'list'):
            offset = int(args[args.index('--offset') + 1])
            rows = list(self.issues.values())[offset:offset + 100]
            return 0, {'issues': rows, 'has_more': len(self.issues) > offset + 100}
        if args[:2] == ('issue', 'create'):
            self.creates += 1
            key = identifier()
            self.issues[key] = {'id': key, 'status': 'backlog', 'assignee_id': None,
                                'description': Path(args[args.index('--description-file') + 1]).read_text(),
                                'created_at': '2026-01-01T00:00:00Z'}
            return (None, None) if self.lost_create else (0, {'id': key})
        if args[:3] == ('issue', 'metadata', 'get'):
            return (0, self.metadata[args[3]]) if args[3] in self.metadata else (1, None)
        if args[:3] == ('issue', 'metadata', 'set'):
            if not self.fail_metadata:
                self.metadata[args[3]] = args[args.index('--value') + 1]
            return None, None  # Even a lost response is reconciled by exact readback.
        if args[:2] == ('issue', 'get'):
            return 0, self.issues[args[2]]
        if args[:2] == ('issue', 'update'):
            self.issues[args[2]].update(status='todo', assignee_id=self.trust['coordinatorId'])
            return None, None  # Lost admission response.
        if args[:2] == ('issue', 'runs'):
            return 0, [] if self.no_task else [{'id': identifier(), 'agent_id': self.trust['coordinatorId'],
                                               'status': 'running'}]
        raise AssertionError(args)


class ReconciliationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.trigger = identifier()
        self.cloud_trigger = identifier()
        self.trust = {'stateDirectory': self.root, 'projectId': identifier(), 'coordinatorId': identifier(),
                      'autopilotId': identifier(), 'triggers': {self.trigger: 'observer-debian',
                                                             self.cloud_trigger: 'renewal-cloud'},
                      'serviceGroups': {'cloud-a', 'observer'}}
        self.native = NativeCLI(self.trust)
        self.state = health_alerts.empty_state()
        self.now = int(time.time())
        self.failure = health_alerts.observe(self.state, self.now, 'observer-debian', 'cloud-a', 'tls',
                                             False, {'near_expiry': 1}, ['hub-a'], 3600)

    def run_for(self, event, status='skipped', trigger=None):
        run = {'id': identifier(), 'source': 'webhook', 'trigger_id': trigger or self.trigger,
               'status': status, 'task_id': identifier() if status == 'completed' else None,
               'triggered_at': event['occurredAt'], 'trigger_payload': event}
        self.native.runs.append(run)
        return run

    def reconcile(self):
        return incident.Reconciler(self.trust, runner=self.native).reconcile()

    def journal(self):
        return json.loads((self.root / 'journal.json').read_text())

    def test_skipped_failed_and_accepted_preserve_original_event_run_and_verifiable_issue_task(self):
        for status in ('skipped', 'failed', 'completed'):
            with self.subTest(status=status):
                event = dict(self.failure, eventId=identifier())
                run = self.run_for(event, status)
                report = self.reconcile()
                self.assertFalse(report['unresolved'])
                self.assertEqual(self.native.creates, 1)
                stored = json.loads(next(iter(self.native.metadata.values())))
                self.assertEqual(stored['provenance']['eventId'], event['eventId'])
                self.assertEqual(self.journal()['events'][event['eventId']]['payload'], event)
                self.assertEqual(stored['provenance']['webhookRunId'], run['id'])
                self.assertEqual(stored['provenance']['nativeStatus'], status)
                self.assertIsNotNone(stored['maintenanceTaskId'])
                self.assertEqual(stored['firstProvenance']['eventId'], self.native.runs[0]['trigger_payload']['eventId'])
        # A second delivery of the SAME event cannot create or add work.
        self.run_for(self.native.runs[0]['trigger_payload'])
        self.reconcile()
        self.assertEqual(self.native.creates, 1)

    def test_uncertain_create_response_then_marker_readback_never_recreates(self):
        self.run_for(self.failure)
        self.native.lost_create = True
        report = self.reconcile()
        self.assertEqual(report['unresolved'][0]['phase'], 'uncertain')
        self.assertEqual(self.native.creates, 1)
        self.native.lost_create = False
        self.assertFalse(self.reconcile()['unresolved'])
        self.assertEqual(self.native.creates, 1)
        # If an uncertain intent has no visible issue it remains unresolved.
        journal = self.journal()
        next(iter(journal['incidents'].values())).update(phase='uncertain', issueId=None)
        (self.root / 'journal.json').write_text(json.dumps(journal))
        self.native.issues.clear()
        self.assertTrue(self.reconcile()['unresolved'])
        self.assertEqual(self.native.creates, 1)

    def test_missing_metadata_and_uncertain_task_admission_do_not_claim_success(self):
        self.run_for(self.failure)
        self.native.fail_metadata = True
        self.assertTrue(self.reconcile()['unresolved'])
        self.assertEqual(next(iter(self.native.issues.values()))['status'], 'backlog')
        self.native.fail_metadata = False
        self.native.no_task = True
        self.assertEqual(self.reconcile()['unresolved'][0]['phase'], 'admission_pending')
        self.native.no_task = False
        self.assertFalse(self.reconcile()['unresolved'])
        self.assertEqual(self.native.creates, 1)
        # Read metadata before retrying its idempotent write.
        sets = [i for i, call in enumerate(self.native.calls) if call[:3] == ('issue', 'metadata', 'set')]
        self.assertTrue(all(any(call[:3] == ('issue', 'metadata', 'get')
                                for call in self.native.calls[:i]) for i in sets))

    def test_renewal_tls_correlation_and_late_recovery_never_close_new_fault(self):
        self.run_for(self.failure)
        self.reconcile()
        recovery = health_alerts.observe(self.state, self.now + 1, 'observer-debian', 'cloud-a', 'tls', True)
        newer = health_alerts.observe(self.state, self.now + 2, 'observer-debian', 'cloud-a', 'tls', False,
                                      {'timeout': 1})
        renewal = health_alerts.observe(self.state, self.now + 3, 'renewal-cloud', 'cloud-a', 'renewal', False,
                                        {'renewal_exit_code': 1})
        self.run_for(newer)
        self.run_for(renewal, trigger=self.cloud_trigger)
        self.reconcile()
        self.run_for(recovery)
        self.reconcile()
        self.assertEqual(self.native.creates, 1)
        stored = json.loads(next(iter(self.native.metadata.values())))
        self.assertFalse(stored['recoveryObserved'])
        self.assertEqual(next(iter(self.native.issues.values()))['status'], 'todo')
        self.assertIn('tls:failing', stored['episodes'].values())
        self.assertIn('renewal:failing', stored['episodes'].values())
        self.assertNotIn(('issue', 'status'), [call[:2] for call in self.native.calls])

    def test_pagination_limit_duplicate_marker_corrupt_journal_and_forged_payload_fail_closed(self):
        self.run_for(self.failure)
        self.native.all_pages = True
        with self.assertRaisesRegex(incident.IncidentError, 'pagination_limit'):
            self.reconcile()
        self.assertEqual(self.native.creates, 0)
        self.native.all_pages = False
        bad = dict(self.failure, errors={'raw_secret': 1})
        self.assertIsNone(incident.validate_event(bad, 'observer-debian'))
        bad = dict(self.failure, source='other')
        self.assertIsNone(incident.validate_event(bad, 'observer-debian'))
        self.reconcile()
        original = next(iter(self.native.issues.values()))
        key = identifier()
        self.native.issues[key] = dict(original, id=key)
        marker = next(iter(self.journal()['incidents']))
        with self.assertRaisesRegex(incident.IncidentError, 'duplicate_incident_marker'):
            incident.Reconciler(self.trust, runner=self.native).find_marker(marker)
        (self.root / 'journal.json').write_text('{corrupt')
        with self.assertRaisesRegex(incident.IncidentError, 'journal_corrupt'):
            self.reconcile()
        self.assertEqual(self.native.creates, 1)


if __name__ == '__main__':
    unittest.main()
