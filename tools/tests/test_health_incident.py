#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise the supported CLI boundary without creating native test issues."""

import hashlib
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
            rows = sorted(reversed(self.runs), key=lambda item: item['triggered_at'], reverse=True)
            return 0, {'runs': rows[offset:offset + 50], 'total': len(rows)}
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

    def test_recovery_before_failure_reassociates_after_restart_without_clearing_new_fault(self):
        recovery = health_alerts.observe(self.state, self.now + 1, 'observer-debian', 'cloud-a', 'tls', True)
        recovery_run = self.run_for(recovery)
        first = self.reconcile()
        self.assertEqual(first['unmatchedRecoveries'], 1)
        late = self.run_for(self.failure)
        late['triggered_at'] = incident.utc(self.now + 2)
        self.assertFalse(self.reconcile()['unresolved'])
        stored = json.loads(next(iter(self.native.metadata.values())))
        self.assertTrue(stored['recoveryObserved'])
        self.assertEqual(first['unresolved'][0]['phase'], 'recovery_unmatched')
        journal = self.journal()
        marker = journal['events'][recovery['eventId']]['marker']
        self.assertIsNotNone(marker)
        self.assertEqual(journal['events'][recovery['eventId']]['runId'], recovery_run['id'])
        self.assertEqual(journal['events'][recovery['eventId']]['payload'], recovery)
        self.assertEqual(journal['incidents'][marker]['episodes'][recovery['episodeId']]['lastSequence'],
                         recovery['sequence'])
        newer = health_alerts.observe(self.state, self.now + 3, 'observer-debian', 'cloud-a', 'tls', False,
                                      {'timeout': 1})
        self.run_for(newer)
        self.run_for(recovery)  # Duplicate retained recovery after a newer fault.
        self.reconcile()
        stored = json.loads(next(iter(self.native.metadata.values())))
        self.assertFalse(stored['recoveryObserved'])
        self.assertIn('tls:failing', stored['episodes'].values())
        self.assertEqual(self.native.creates, 1)
        self.assertEqual(next(iter(self.native.issues.values()))['status'], 'todo')

    def test_incremental_boundary_survives_large_known_history_and_restart(self):
        for _ in range(450):
            self.run_for(self.failure)
        self.reconcile()
        for _ in range(200):
            self.run_for(self.failure)
        new_event = dict(self.failure, eventId=identifier())
        newest = self.run_for(new_event)
        self.assertFalse(self.reconcile()['unresolved'])
        self.assertIn(new_event['eventId'], self.journal()['events'])
        self.assertEqual(self.journal()['discovery']['runId'], newest['id'])
        self.native.calls.clear()
        self.assertFalse(self.reconcile()['unresolved'])
        self.assertEqual(sum(call[:2] == ('autopilot', 'runs') for call in self.native.calls), 1)
        self.assertEqual(self.native.creates, 1)

    def test_legacy_known_history_migration_and_genuine_missed_window(self):
        journal = incident.empty_journal()
        for _ in range(501):
            run = self.run_for(self.failure)
            journal['runs'][run['id']] = {'outcome': 'duplicate_event', 'at': incident.utc(self.now)}
        (self.root / 'journal.json').write_text(json.dumps(journal))
        new_event = dict(self.failure, eventId=identifier())
        self.run_for(new_event)
        self.reconcile()
        self.assertIn(new_event['eventId'], self.journal()['events'])
        cursor = self.journal()['discovery']
        for _ in range(501):
            self.run_for(dict(self.failure, eventId=identifier()))
        with self.assertRaisesRegex(incident.IncidentError, 'run_pagination_limit'):
            self.reconcile()
        self.assertEqual(self.journal()['discovery'], cursor)
        self.assertEqual(self.native.creates, 1)
        self.native.runs.clear()
        with self.assertRaisesRegex(incident.IncidentError, 'run_boundary_missing'):
            self.reconcile()

    def test_pending_run_pins_discovery_and_later_admission_is_reread(self):
        self.run_for(self.failure)
        self.reconcile()
        cursor = self.journal()['discovery']
        event = dict(self.failure, eventId=identifier())
        run = self.run_for(event, 'queued')
        report = self.reconcile()
        self.assertEqual(report['unresolved'][0]['phase'], 'native_pending')
        self.assertEqual(self.journal()['discovery'], cursor)
        run['status'] = 'completed'
        self.assertFalse(self.reconcile()['unresolved'])
        self.assertIn(event['eventId'], self.journal()['events'])
        self.assertEqual(self.journal()['discovery']['runId'], run['id'])

    def test_retention_keeps_unmatched_recovery_and_unavailable_provenance(self):
        recovery = health_alerts.observe(self.state, self.now + 1, 'observer-debian', 'cloud-a', 'tls', True)
        self.run_for(recovery)
        unknown = self.run_for(self.failure, 'completed')
        unknown['trigger_payload'] = None
        self.reconcile()
        journal = self.journal()
        # Old unresolved records cannot be evicted by more recent resolved history.
        for index in range(incident.JOURNAL_LIMIT):
            journal['runs'][identifier()] = {'outcome': 'duplicate_event', 'at': '2099-01-01T00:00:00Z'}
            event = dict(self.failure, eventId=identifier())
            journal['events'][event['eventId']] = {'kind': 'failure', 'marker': 'closed',
                                                 'payload': event, 'at': '2099-01-01T00:00:00Z'}
        incident.Reconciler(self.trust, runner=self.native).save(journal)
        stored = self.journal()
        self.assertIn(recovery['eventId'], stored['events'])
        self.assertEqual(stored['runs'][unknown['id']]['unresolved'], 'original_payload_unavailable')
        self.assertLessEqual(len(stored['events']), incident.JOURNAL_LIMIT)
        self.assertLessEqual(len(stored['runs']), incident.JOURNAL_LIMIT)

    def original_file(self, event):
        directory = self.root / 'original-events'
        directory.mkdir(mode=0o700, exist_ok=True)
        path = directory / (event['eventId'] + '.json')
        # Preserve original bytes including whitespace, not a reconstructed payload.
        path.write_text(json.dumps(event, indent=2) + '\n')
        path.chmod(0o600)
        return path

    def test_null_payload_stays_unresolved_until_protected_original_reconciliation(self):
        run = self.run_for(self.failure, 'completed')
        run['trigger_payload'] = None
        report = self.reconcile()
        self.assertEqual(report['incidents'], [])
        self.assertEqual(report['unresolved'][0]['phase'], 'original_payload_unavailable')
        self.assertTrue(self.reconcile()['unresolved'])
        legacy = self.journal()
        legacy['runs'][run['id']].pop('unresolved')
        (self.root / 'journal.json').write_text(json.dumps(legacy))
        reader = incident.Reconciler(self.trust, runner=self.native)
        self.assertTrue(reader.obligations(reader.load()))
        path = self.original_file(self.failure)
        report = incident.Reconciler(self.trust, runner=self.native).reconcile(path, self.trigger, run['id'])
        self.assertFalse(report['unresolved'])
        self.assertEqual(self.native.creates, 1)
        stored = json.loads(next(iter(self.native.metadata.values())))
        self.assertEqual(stored['provenance']['payloadOrigin'], 'operator_original')
        self.assertEqual(stored['provenance']['webhookRunId'], run['id'])
        self.assertEqual(stored['provenance']['originalBytesSha256'], hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertEqual(self.journal()['events'][self.failure['eventId']]['originalBytes'], path.read_text())
        self.assertIsNotNone(stored['maintenanceTaskId'])
        self.assertFalse(incident.Reconciler(self.trust, runner=self.native).reconcile(path, self.trigger, run['id'])['unresolved'])
        self.assertEqual(self.native.creates, 1)
        path.write_text(json.dumps(dict(self.failure, sequence=999)))
        with self.assertRaisesRegex(incident.IncidentError, 'event_identity_conflict'):
            incident.Reconciler(self.trust, runner=self.native).reconcile(path, self.trigger, run['id'])

    def test_original_fallback_distinguishes_skipped_failed_unknown_and_no_run(self):
        path = self.original_file(self.failure)
        # Rejected/response-lost ingress does not imply that a native run exists.
        report = incident.Reconciler(self.trust, runner=self.native).reconcile(path, self.trigger)
        self.assertEqual(report['unresolved'][0]['phase'], 'original_run_unobserved')
        stored = json.loads(next(iter(self.native.metadata.values())))
        self.assertIsNone(stored['provenance']['webhookRunId'])
        self.assertEqual(stored['provenance']['nativeStatus'], 'unobserved')
        self.assertIsNotNone(stored['maintenanceTaskId'])
        run = self.run_for(self.failure, 'queued')
        run['trigger_payload'] = None
        report = incident.Reconciler(self.trust, runner=self.native).reconcile(path, self.trigger, run['id'])
        self.assertIn('original_admission_unverified', [item['phase'] for item in report['unresolved']])
        for status in ('skipped', 'failed', 'completed'):
            run['status'] = status
            report = incident.Reconciler(self.trust, runner=self.native).reconcile(path, self.trigger, run['id'])
            self.assertFalse(report['unresolved'])
            stored = json.loads(next(iter(self.native.metadata.values())))
            self.assertEqual(stored['provenance']['nativeStatus'], status)
        self.assertEqual(self.native.creates, 1)
        path.chmod(0o644)
        with self.assertRaisesRegex(incident.IncidentError, 'unprotected_original_event'):
            incident.Reconciler(self.trust, runner=self.native).reconcile(path, self.trigger, run['id'])
        path.chmod(0o600)
        with self.assertRaisesRegex(incident.IncidentError, 'original_run_unproven'):
            incident.Reconciler(self.trust, runner=self.native).reconcile(path, self.trigger, identifier())

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
