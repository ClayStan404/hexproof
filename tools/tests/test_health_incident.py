#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise the supported CLI boundary without creating native test issues."""

import hashlib
import base64
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import json
from pathlib import Path
import re
import sys
import tempfile
import time
import unittest
from unittest import mock
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
        self.fail_get = False
        self.fail_list = False
        self.fail_route = False
        self.fail_run_offsets = set()
        self.no_task = False
        self.all_pages = False
        self.calls = []
        self.route = {'id': trust['autopilotId'], 'workspace_id': trust.get('workspaceId'),
                      'project_id': trust['projectId'], 'assignee_id': trust['coordinatorId'],
                      'assignee_type': 'agent', 'execution_mode': 'run_only'}
        self.triggers = [{'id': key, 'autopilot_id': trust['autopilotId'], 'kind': 'webhook',
                          'provider': 'generic'} for key in trust['triggers']]

    def __call__(self, *args):
        self.calls.append(args)
        if args[:2] == ('autopilot', 'get'):
            if self.fail_route:
                return None, None
            return 0, {'autopilot': self.route, 'triggers': self.triggers}
        if args[:2] == ('autopilot', 'runs'):
            offset = int(args[args.index('--offset') + 1])
            if offset in self.fail_run_offsets:
                return None, None
            if self.all_pages:
                return 0, {'runs': [dict(self.runs[0], id=identifier()) for _ in range(50)], 'total': 501}
            rows = sorted(reversed(self.runs), key=lambda item: item['triggered_at'], reverse=True)
            return 0, {'runs': rows[offset:offset + 50], 'total': len(rows)}
        if args[:2] == ('issue', 'list'):
            if self.fail_list:
                return None, None
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
            if self.fail_get:
                return None, None
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
        self.trust = {'stateDirectory': self.root, 'workspaceId': identifier(),
                      'projectId': identifier(), 'coordinatorId': identifier(),
                      'autopilotId': identifier(), 'triggers': {self.trigger: 'observer-debian',
                                                             self.cloud_trigger: 'renewal-cloud'},
                      'serviceGroups': {'cloud-a', 'observer'},
                      'signalBindings': {self.trigger: ['tls'], self.cloud_trigger: ['renewal']},
                      'configVersion': {'schemaVersion': 1, 'sha256': 'a' * 64}}
        self.native = NativeCLI(self.trust)
        self.state = health_alerts.empty_state()
        self.now = int(time.time())
        self.failure = health_alerts.observe(self.state, self.now, 'observer-debian', 'cloud-a', 'tls',
                                             False, {'near_expiry': 1}, ['hub-a'], 3600)

    def run_for(self, event, status='skipped', trigger=None):
        run = {'id': identifier(), 'source': 'webhook', 'trigger_id': trigger or self.trigger,
               'autopilot_id': self.trust['autopilotId'],
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


class RuntimeIngestTests(unittest.TestCase):
    setUp = ReconciliationTests.setUp
    run_for = ReconciliationTests.run_for
    journal = ReconciliationTests.journal
    reconcile = ReconciliationTests.reconcile
    original_file = ReconciliationTests.original_file

    def current_run(self, event=None):
        run = self.run_for(event or self.failure, 'completed')
        run['trigger_payload'] = None
        return run

    def ingest(self, run, event=None, raw=None):
        with mock.patch.dict(incident.os.environ, {'MULTICA_TASK_ID': run['task_id'],
                             'MULTICA_AGENT_ID': self.trust['coordinatorId']}):
            return incident.Reconciler(self.trust, runner=self.native).ingest(
                raw if raw is not None else health_alerts.event_bytes(event or self.failure))

    def test_complete_current_input_null_history_and_cross_run_duplicates(self):
        run = self.current_run()
        self.assertTrue(self.reconcile()['unresolved'])  # Historical null is not consumption.
        raw = json.dumps(self.failure, indent=2).encode()
        report = self.ingest(run, raw=raw)
        self.assertFalse(report['unresolved'])
        digest = hashlib.sha256(health_alerts.event_bytes(self.failure)).hexdigest()
        self.assertEqual(report['runtimeReceipt']['payloadSha256'], digest)
        receipt = next(iter(self.journal()['runtimeInputs'].values()))
        self.assertEqual(base64.b64decode(receipt['rawInputBase64']), raw)
        self.assertEqual(receipt['payload'], self.failure)
        self.assertEqual(receipt['nativeRun']['task_id'], run['task_id'])
        self.assertEqual(receipt['nativeRun']['id'], run['id'])
        self.assertEqual(receipt['configVersion'], self.trust['configVersion'])
        self.assertEqual(receipt['historicalPayload'], 'null')
        self.assertFalse(self.ingest(run, raw=raw)['unresolved'])
        second = self.current_run()
        self.assertFalse(self.ingest(second)['unresolved'])
        self.assertFalse(self.reconcile()['unresolved'])
        stored = json.loads(next(iter(self.native.metadata.values())))
        self.assertEqual(stored['eventCount'], 1)
        self.assertEqual(stored['firstProvenance']['payloadOrigin'], incident.RUNTIME_ORIGIN)
        self.assertEqual(stored['provenance']['webhookRunId'], second['id'])
        self.assertIsNotNone(stored['maintenanceTaskId'])
        self.assertEqual(self.native.creates, 1)
        self.assertEqual(sum(call[:2] == ('issue', 'update') for call in self.native.calls), 1)

    def test_missing_or_wrong_identity_never_uses_cli_or_owner_profile(self):
        for values in ({}, {'MULTICA_TASK_ID': identifier()},
                       {'MULTICA_TASK_ID': 'invalid', 'MULTICA_AGENT_ID': self.trust['coordinatorId']},
                       {'MULTICA_TASK_ID': identifier(), 'MULTICA_AGENT_ID': identifier()}):
            with self.subTest(values=values), mock.patch.dict(incident.os.environ, values, clear=True):
                report = incident.Reconciler(self.trust, runner=self.native).ingest(
                    health_alerts.event_bytes(self.failure))
                self.assertIn('runtime_identity_unavailable', [i['phase'] for i in report['unresolved']])
        self.assertEqual(self.native.calls, [])
        self.assertEqual(self.native.creates, 0)
        self.assertTrue(self.journal()['runtimeInputs'])

    def test_wrong_route_workspace_project_agent_mode_and_trigger_fail_closed(self):
        run = self.current_run()
        for key, bad in (('id', identifier()), ('workspace_id', identifier()),
                         ('project_id', identifier()), ('assignee_id', identifier()),
                         ('assignee_type', 'squad'), ('execution_mode', 'create_issue')):
            with self.subTest(key=key), mock.patch.dict(self.native.route, {key: bad}):
                self.assertTrue(self.ingest(run)['unresolved'])
                self.assertEqual(self.native.creates, 0)
        for key, bad in (('kind', 'manual'), ('autopilot_id', identifier()), ('provider', 'github')):
            with self.subTest(key=key), mock.patch.dict(self.native.triggers[0], {key: bad}):
                self.assertTrue(self.ingest(run)['unresolved'])
                self.assertEqual(self.native.creates, 0)
        for key, bad in (('source', 'schedule'), ('trigger_id', identifier()),
                         ('autopilot_id', identifier()), ('task_id', identifier()), ('status', 'skipped')):
            with self.subTest(key=key), mock.patch.dict(run, {key: bad}):
                # Keep the actual environment task fixed when the returned task is wrong.
                context = dict(run, task_id=identifier()) if key == 'task_id' else run
                self.assertTrue(self.ingest(context)['unresolved'])
                self.assertEqual(self.native.creates, 0)
        final = self.ingest(run)
        self.assertIsNone(final['runtimeReceipt']['unresolved'])
        self.assertEqual(self.native.creates, 1)

    def test_task_match_must_be_unique_and_pagination_complete(self):
        run = self.current_run()
        self.native.runs.append(dict(run, id=identifier()))
        self.assertTrue(self.ingest(run)['unresolved'])
        self.assertEqual(self.native.creates, 0)
        self.native.runs.pop()
        self.native.all_pages = True
        self.assertTrue(self.ingest(run)['unresolved'])
        self.assertEqual(self.native.creates, 0)
        receipt = next(iter(self.journal()['runtimeInputs'].values()))
        self.assertEqual(receipt['payload'], self.failure)  # Saved before incomplete scanning.
        self.assertEqual(receipt['unresolved'], 'run_pagination_limit')

    def test_untrusted_source_group_signal_and_modified_historical_body(self):
        for changed in ({'source': 'other'}, {'serviceGroup': 'other'}, {'signal': 'renewal'},
                        {'sequence': True}, {'occurredAt': '2026-02-30T00:00:00Z'},
                        {'errors': {'arbitrary_command': 1}}, {'sequence': 2**53}):
            with self.subTest(changed=changed):
                run = self.current_run()
                self.assertTrue(self.ingest(run, dict(self.failure, **changed))['unresolved'])
                self.assertEqual(self.native.creates, 0)
        run = self.current_run()
        run['trigger_payload'] = self.failure
        self.assertTrue(self.ingest(run, dict(self.failure, sequence=999))['unresolved'])
        self.assertEqual(self.native.creates, 0)

    def test_absent_malformed_duplicate_keys_oversize_and_extra_fields_are_retained(self):
        for raw in (b'', b'null', b'{invalid', b'\xff', b'x' * (incident.MAX_EVENT + 1),
                    b'{"schema":1,"schema":2}',
                    health_alerts.event_bytes(dict(self.failure, command='do something')),
                    health_alerts.event_bytes(dict(self.failure, minRemainingSeconds=float('nan')))):
            with self.subTest(prefix=raw[:20]):
                run = self.current_run()
                report = self.ingest(run, raw=raw)
                self.assertTrue(report['unresolved'])
                self.assertEqual(self.native.creates, 0)
        self.assertEqual(len(self.journal()['runtimeInputs']), 8)
        self.assertTrue(all(row['pending'] for row in self.journal()['runtimeInputs'].values()))

    def test_changed_digest_same_run_or_same_event_cannot_recount(self):
        run = self.current_run()
        self.assertFalse(self.ingest(run)['unresolved'])
        changed = dict(self.failure, totalFailures=999)
        report = self.ingest(run, changed)
        self.assertIn('runtime_digest_conflict', [i['phase'] for i in report['unresolved']])
        second = self.current_run()
        report = self.ingest(second, changed)
        self.assertIn('event_identity_conflict', [i['phase'] for i in report['unresolved']])
        self.assertEqual(self.native.creates, 1)
        self.assertEqual(next(iter(self.journal()['incidents'].values()))['eventCount'], 1)
        self.assertEqual(len(self.journal()['runtimeInputs']), 3)

    def test_concurrent_duplicate_inputs_share_lock_count_and_admission(self):
        run = self.current_run()
        raw = health_alerts.event_bytes(self.failure)
        with mock.patch.dict(incident.os.environ, {'MULTICA_TASK_ID': run['task_id'],
                             'MULTICA_AGENT_ID': self.trust['coordinatorId']}):
            with ThreadPoolExecutor(max_workers=2) as pool:
                reports = list(pool.map(lambda _: incident.Reconciler(
                    self.trust, runner=self.native).ingest(raw), range(2)))
        self.assertTrue(all(not report['unresolved'] for report in reports))
        self.assertEqual(self.native.creates, 1)
        self.assertEqual(next(iter(self.journal()['incidents'].values()))['eventCount'], 1)

    def test_fsync_failure_before_file_and_directory_commit_has_no_issue_effects(self):
        run = self.current_run()
        fsync = incident.os.fsync
        for fail_at in (1, 2):
            calls = []
            def fail(fd):
                calls.append(fd)
                if len(calls) == fail_at:
                    raise OSError('simulated fsync failure')
                fsync(fd)
            with self.subTest(fail_at=fail_at), mock.patch.object(incident.os, 'fsync', side_effect=fail):
                with self.assertRaises(OSError):
                    self.ingest(run)
            self.assertEqual(self.native.creates, 0)
        self.assertFalse(self.ingest(run)['unresolved'])
        self.assertEqual(self.native.creates, 1)

    def test_crash_after_bound_fsync_resumes_without_current_carrier(self):
        class Crash(BaseException):
            pass
        run = self.current_run()
        save = incident.Reconciler.save
        saves = []
        def crash_after_bound(reconciler, journal):
            save(reconciler, journal)
            saves.append(1)
            if len(saves) == 2:
                raise Crash()
        with mock.patch.object(incident.Reconciler, 'save', crash_after_bound):
            with self.assertRaises(Crash):
                self.ingest(run)
        self.assertEqual(self.native.creates, 0)
        receipt = next(iter(self.journal()['runtimeInputs'].values()))
        self.assertTrue(receipt['bindingVerified'])
        self.assertTrue(receipt['pending'])
        self.assertFalse(self.reconcile()['unresolved'])
        self.assertEqual(self.native.creates, 1)
        self.assertFalse(self.reconcile()['unresolved'])
        self.assertEqual(self.native.creates, 1)

    def test_transient_issue_read_resumes_verified_input_from_another_task(self):
        self.ingest(self.current_run())
        event = dict(self.failure, eventId=identifier(), kind='escalation', sequence=2,
                     consecutiveFailures=12, totalFailures=12)
        run = self.current_run(event)
        self.native.fail_get = True
        report = self.ingest(run, event)
        self.assertIn('incident_unreadable', [row['phase'] for row in report['unresolved']])
        receipt = next(row for row in self.journal()['runtimeInputs'].values() if row['taskId'] == run['task_id'])
        self.assertTrue(receipt['bindingVerified'])
        self.assertTrue(receipt['pending'])
        self.assertEqual(receipt['payload'], event)
        self.native.fail_get = False
        with mock.patch.dict(incident.os.environ, {'MULTICA_TASK_ID': identifier(),
                             'MULTICA_AGENT_ID': self.trust['coordinatorId']}):
            self.assertFalse(self.reconcile()['unresolved'])
        receipt = next(row for row in self.journal()['runtimeInputs'].values() if row['taskId'] == run['task_id'])
        self.assertFalse(receipt['pending'])
        self.assertNotIn('unresolved', receipt)
        self.assertIn(event['eventId'], self.journal()['events'])
        self.assertEqual(next(iter(self.journal()['incidents'].values()))['eventCount'], 2)
        self.assertEqual(self.native.creates, 1)
        self.assertFalse(self.reconcile()['unresolved'])

    def test_transient_discovery_clears_processed_receipt_obligation_after_restart(self):
        run = self.current_run()
        self.native.fail_list = True
        report = self.ingest(run)
        self.assertIn('incident_discovery_incomplete', [row['phase'] for row in report['unresolved']])
        receipt = next(iter(self.journal()['runtimeInputs'].values()))
        self.assertTrue(receipt['bindingVerified'])
        self.assertFalse(receipt['pending'])
        self.native.fail_list = False
        self.native.fail_run_offsets = {0}
        retry = self.ingest(run)['runtimeReceipt']
        self.assertEqual(retry['unresolved'], 'incident_discovery_incomplete')
        self.assertEqual(retry['lastAttemptError'], 'runs_unavailable')
        self.native.fail_run_offsets.clear()
        self.assertFalse(self.reconcile()['unresolved'])
        receipt = next(iter(self.journal()['runtimeInputs'].values()))
        self.assertNotIn('unresolved', receipt)
        self.assertEqual(next(iter(self.journal()['incidents'].values()))['phase'], 'admitted')
        self.assertEqual(next(iter(self.journal()['incidents'].values()))['eventCount'], 1)
        self.assertEqual(self.native.creates, 1)

    def test_verified_pending_input_survives_same_task_native_lookup_outages(self):
        self.ingest(self.current_run())
        event = dict(self.failure, eventId=identifier(), kind='escalation', sequence=2,
                     consecutiveFailures=12, totalFailures=12)
        run = self.current_run(event)
        run['status'] = 'running'
        raw = json.dumps(event, indent=2).encode()
        self.native.fail_get = True
        self.assertEqual(self.ingest(run, raw=raw)['runtimeReceipt']['unresolved'], 'incident_unreadable')
        self.native.fail_get = False
        saved = next(row for row in self.journal()['runtimeInputs'].values() if row['taskId'] == run['task_id'])
        self.assertTrue(saved['bindingVerified'])
        for failure in ('runs', 'route'):
            with self.subTest(failure=failure):
                self.native.fail_run_offsets = {0} if failure == 'runs' else set()
                self.native.fail_route = failure == 'route'
                report = self.ingest(run, raw=raw)
                receipt = next(row for row in self.journal()['runtimeInputs'].values() if row['taskId'] == run['task_id'])
                self.assertEqual(receipt['unresolved'], 'incident_unreadable')
                self.assertEqual(report['runtimeReceipt']['lastAttemptError'],
                                 'runs_unavailable' if failure == 'runs' else 'runtime_route_unavailable')
                self.assertTrue(receipt['pending'])
                for field in ('nativeRun', 'payload', 'rawInputBase64', 'payloadSha256', 'configVersion'):
                    self.assertEqual(receipt[field], saved[field])
                self.assertNotIn(event['eventId'], self.journal()['events'])
        self.native.fail_run_offsets.clear()
        self.native.fail_route = False
        with mock.patch.dict(incident.os.environ, {'MULTICA_TASK_ID': identifier(),
                             'MULTICA_AGENT_ID': self.trust['coordinatorId']}):
            self.assertFalse(self.reconcile()['unresolved'])
            self.assertFalse(self.reconcile()['unresolved'])
        receipt = next(row for row in self.journal()['runtimeInputs'].values() if row['taskId'] == run['task_id'])
        self.assertFalse(receipt['pending'])
        self.assertNotIn('unresolved', receipt)
        self.assertNotIn('lastAttemptError', receipt)
        self.assertEqual(receipt['nativeRun'], saved['nativeRun'])
        self.assertEqual(next(iter(self.journal()['incidents'].values()))['eventCount'], 2)
        self.assertEqual(self.native.creates, 1)
        self.assertEqual(sum(call[:2] == ('issue', 'update') for call in self.native.calls), 1)

    def test_accounted_input_configuration_conflict_blocks_canonical_reconcile(self):
        operations = {'activation': 'active', 'native': {key: self.trust[key] for key in
                      ('workspaceId', 'projectId', 'coordinatorId')}}
        config = {'schemaVersion': 1, 'autopilotId': self.trust['autopilotId'],
                  'triggers': self.trust['triggers'], 'signalBindings': self.trust['signalBindings'],
                  'serviceGroups': ['cloud-a'], 'stateDirectory': str(self.root)}
        ops_path, config_path = self.root / 'operations.json', self.root / 'incident.json'
        ops_path.write_text(json.dumps(operations))
        config_path.write_text(json.dumps(config))
        self.trust.update(incident.load_trust(ops_path, config_path))
        original_trust = dict(self.trust)
        run = self.current_run()
        self.native.fail_list = True
        self.assertEqual(self.ingest(run)['runtimeReceipt']['unresolved'], 'incident_discovery_incomplete')
        self.native.fail_list = False
        original = self.journal()
        receipt = next(iter(original['runtimeInputs'].values()))
        marker, intent = next(iter(original['incidents'].items()))
        self.assertFalse(receipt['pending'])
        self.assertEqual(intent['phase'], 'pending')
        self.assertIsNone(intent['issueId'])
        self.assertEqual(intent['eventCount'], 1)
        operations['native']['projectId'] = identifier()
        ops_path.write_text(json.dumps(operations))
        self.trust.update(incident.load_trust(ops_path, config_path))
        self.native.route['project_id'] = self.trust['projectId']
        self.assertNotEqual(self.trust['configVersion'], receipt['configVersion'])
        self.assertEqual(self.ingest(run)['runtimeReceipt']['unresolved'], 'runtime_configuration_changed')
        self.native.fail_route = True
        self.assertEqual(self.ingest(run)['runtimeReceipt']['unresolved'], 'runtime_configuration_changed')
        self.native.fail_route = False
        for restore_config in (False, True):
            if restore_config:
                self.trust.update(original_trust)
                self.native.route['project_id'] = self.trust['projectId']
            with self.subTest(restore_config=restore_config), mock.patch.dict(incident.os.environ, {
                    'MULTICA_TASK_ID': identifier(), 'MULTICA_AGENT_ID': self.trust['coordinatorId']}):
                start = len(self.native.calls)
                for _ in range(2):
                    self.assertIn('runtime_configuration_changed', [row['phase'] for row in self.reconcile()['unresolved']])
                self.assertFalse(any(call[:2] in (('issue', 'create'), ('issue', 'update'))
                                     or call[:3] == ('issue', 'metadata', 'set')
                                     for call in self.native.calls[start:]))
                saved = self.journal()
                self.assertEqual(saved['incidents'][marker], intent)
                stored = next(iter(saved['runtimeInputs'].values()))
                self.assertEqual(stored['unresolved'], 'runtime_configuration_changed')
                for field in ('configVersion', 'payload', 'nativeRun', 'rawInputBase64', 'payloadSha256'):
                    self.assertEqual(stored[field], receipt[field])
        # Restoring a config is not explicit reconciliation of the saved conflict.
        self.assertEqual(self.ingest(run)['runtimeReceipt']['unresolved'], 'runtime_configuration_changed')
        self.assertEqual(self.native.creates, 0)
        self.assertEqual(self.journal()['incidents'][marker], intent)

    def test_direct_advance_configuration_gate_covers_all_delivery_phases(self):
        for phase in ('pending', 'uncertain', 'created', 'indexed', 'admission_pending', 'admitted'):
            for binding in ('runtime', 'legacy_runtime', 'native_pin'):
                with self.subTest(phase=phase, binding=binding):
                    case = RuntimeIngestTests()
                    case.setUp()
                    self.addCleanup(case.doCleanups)
                    run = case.current_run()
                    case.native.fail_list = phase == 'pending'
                    case.native.lost_create = phase == 'uncertain'
                    case.native.fail_metadata = phase == 'created'
                    case.native.fail_get = phase == 'indexed'
                    case.native.no_task = phase == 'admission_pending'
                    case.ingest(run)
                    journal = case.journal()
                    marker, intent = next(iter(journal['incidents'].items()))
                    self.assertEqual(intent['phase'], phase)
                    if binding == 'legacy_runtime':
                        # Old schema-1 incidents have a receipt but no incident pin.
                        intent.pop('configVersion', None)
                    elif binding == 'native_pin':
                        journal['runtimeInputs'].clear()
                    if phase == 'admitted':
                        intent['metadataDirty'] = True
                    before = json.loads(json.dumps(journal))
                    case.native.fail_list = case.native.fail_metadata = case.native.fail_get = False
                    case.native.lost_create = case.native.no_task = False
                    original_trust = dict(case.trust)
                    case.trust.update(projectId=identifier(), coordinatorId=identifier(),
                                      configVersion={'schemaVersion': 1, 'sha256': 'b' * 64})
                    reconciler = incident.Reconciler(case.trust, runner=case.native)
                    start = len(case.native.calls)
                    reconciler.advance(journal, marker)
                    self.assertEqual(reconciler.report['incidents'][marker]['phase'],
                                     'incident_configuration_changed' if binding == 'native_pin' else 'runtime_configuration_changed')
                    self.assertEqual(case.native.calls[start:], [])
                    self.assertEqual(journal, before)
                    if binding != 'native_pin':
                        case.trust.update(original_trust)
                        next(iter(journal['runtimeInputs'].values()))['unresolved'] = 'runtime_digest_conflict'
                        before = json.loads(json.dumps(journal))
                        reconciler.advance(journal, marker)
                        self.assertEqual(reconciler.report['incidents'][marker]['phase'], 'runtime_digest_conflict')
                        self.assertEqual(case.native.calls[start:], [])
                        self.assertEqual(journal, before)

    def test_existing_intent_rejects_changed_config_before_attaching_any_provenance(self):
        run = self.current_run()
        self.native.fail_list = True
        self.ingest(run)
        self.native.fail_list = False
        for legacy in (False, True):
            for origin in ('native_payload', 'operator_original', incident.RUNTIME_ORIGIN):
                for duplicate in (False, True):
                    with self.subTest(legacy=legacy, origin=origin, duplicate=duplicate):
                        journal = self.journal()
                        if legacy:
                            next(iter(journal['incidents'].values())).pop('configVersion', None)
                        before = json.loads(json.dumps(journal))
                        changed_trust = dict(self.trust, projectId=identifier(),
                                             configVersion={'schemaVersion': 1, 'sha256': 'b' * 64})
                        reconciler = incident.Reconciler(changed_trust, runner=self.native)
                        event = self.failure if duplicate else dict(self.failure, eventId=identifier(), sequence=2)
                        with self.assertRaisesRegex(incident.IncidentError, 'runtime_configuration_changed'):
                            reconciler.process(journal, run if duplicate else dict(run, id=identifier()), event, origin)
                        self.assertEqual(journal, before)
        self.assertEqual(self.native.creates, 0)

    def test_native_intent_pin_and_unbound_legacy_recovery_remain_distinct(self):
        self.run_for(self.failure)
        self.native.fail_list = True
        with self.assertRaisesRegex(incident.IncidentError, 'incident_discovery_incomplete'):
            self.reconcile()
        self.native.fail_list = False
        journal = self.journal()
        marker, intent = next(iter(journal['incidents'].items()))
        self.assertFalse(journal['runtimeInputs'])
        self.trust['configVersion'] = {'schemaVersion': 1, 'sha256': 'b' * 64}
        self.assertIn('incident_configuration_changed', [row['phase'] for row in self.reconcile()['unresolved']])
        self.assertEqual(self.native.creates, 0)
        # A historical incident with no saved runtime authority remains recoverable.
        intent.pop('configVersion')
        (self.root / 'journal.json').write_text(json.dumps(journal))
        self.assertFalse(self.reconcile()['unresolved'])
        self.assertFalse(self.reconcile()['unresolved'])
        self.assertEqual(self.native.creates, 1)
        self.assertEqual(sum(call[:2] == ('issue', 'update') for call in self.native.calls), 1)

    def test_verified_conflicts_survive_subsequent_lookup_outage(self):
        self.ingest(self.current_run())
        event = dict(self.failure, eventId=identifier(), kind='escalation', sequence=2)
        run = self.current_run(event)
        self.native.fail_get = True
        self.ingest(run, event)
        self.native.fail_get = False
        saved = next(row for row in self.journal()['runtimeInputs'].values() if row['taskId'] == run['task_id'])
        for field, bad, expected in (
                ('project_id', identifier(), 'runtime_route_unproven'),
                ('id', identifier(), 'runtime_binding_conflict')):
            with self.subTest(field=field):
                if field == 'id':
                    # Advance discovery normally before the original run's
                    # identity changes, so this is a binding conflict, not a gap.
                    self.ingest(self.current_run())
                target = self.native.route if field == 'project_id' else run
                with mock.patch.dict(target, {field: bad}):
                    self.assertEqual(self.ingest(run, event)['runtimeReceipt']['unresolved'], expected)
                self.native.fail_run_offsets = {0}
                report = self.ingest(run, event)
                self.native.fail_run_offsets.clear()
                self.assertEqual(report['runtimeReceipt']['unresolved'], expected)
                with mock.patch.object(incident.Reconciler, 'apply_runtime', side_effect=AssertionError('conflict replayed')):
                    self.assertTrue(self.reconcile()['unresolved'])
                receipt = next(row for row in self.journal()['runtimeInputs'].values() if row['taskId'] == run['task_id'])
                self.assertEqual(receipt['nativeRun'], saved['nativeRun'])
        # Configuration must be checked even before an unavailable native read.
        self.trust['configVersion'] = {'schemaVersion': 1, 'sha256': 'b' * 64}
        self.native.fail_run_offsets = {0}
        self.assertEqual(self.ingest(run, event)['runtimeReceipt']['unresolved'], 'runtime_configuration_changed')
        self.native.fail_run_offsets.clear()
        with mock.patch.object(incident.Reconciler, 'apply_runtime', side_effect=AssertionError('configuration replayed')):
            self.assertTrue(self.reconcile()['unresolved'])
        self.trust['configVersion'] = saved['configVersion']
        changed = dict(event, totalFailures=99)
        self.assertEqual(self.ingest(run, changed)['runtimeReceipt']['unresolved'], 'runtime_digest_conflict')
        self.native.fail_run_offsets = {0}
        self.assertEqual(self.ingest(run, event)['runtimeReceipt']['unresolved'], 'runtime_digest_conflict')
        self.native.fail_run_offsets.clear()
        with mock.patch.object(incident.Reconciler, 'apply_runtime', side_effect=AssertionError('digest conflict replayed')):
            self.assertTrue(self.reconcile()['unresolved'])
        self.assertNotIn(event['eventId'], self.journal()['events'])
        self.assertEqual(self.native.creates, 1)

    def test_verified_identity_and_configuration_conflicts_do_not_replay(self):
        self.ingest(self.current_run())
        conflict = dict(self.failure, totalFailures=99)
        report = self.ingest(self.current_run(conflict), conflict)
        self.assertIn('event_identity_conflict', [row['phase'] for row in report['unresolved']])
        with mock.patch.object(incident.Reconciler, 'apply_runtime', side_effect=AssertionError('conflict replayed')):
            self.assertTrue(self.reconcile()['unresolved'])
        event = dict(self.failure, eventId=identifier(), kind='escalation', sequence=2)
        self.native.fail_get = True
        self.ingest(self.current_run(event), event)
        self.native.fail_get = False
        self.trust['configVersion'] = {'schemaVersion': 1, 'sha256': 'b' * 64}
        with self.assertRaisesRegex(incident.IncidentError, 'runtime_configuration_changed'):
            self.reconcile()
        with mock.patch.object(incident.Reconciler, 'apply_runtime', side_effect=AssertionError('configuration replayed')):
            self.assertTrue(self.reconcile()['unresolved'])
        self.assertEqual(next(iter(self.journal()['incidents'].values()))['eventCount'], 1)
        self.assertEqual(self.native.creates, 1)

    def test_continuous_automatic_ingest_crosses_default_discovery_window(self):
        for _ in range(incident.RUN_PAGE * incident.RUN_PAGES + 1):
            run = self.current_run()
            self.assertFalse(self.ingest(run)['unresolved'])
            self.assertIsNotNone(self.journal()['discovery'])
            self.assertEqual(self.journal()['discovery']['runId'], run['id'])
        event = dict(self.failure, eventId=identifier(), kind='escalation', sequence=2)
        fresh = self.current_run(event)
        self.assertFalse(self.ingest(fresh, event)['unresolved'])
        journal = self.journal()
        self.assertEqual(journal['discovery']['runId'], fresh['id'])
        self.assertEqual(len(journal['runs']), len(self.native.runs))
        self.assertEqual(next(iter(journal['incidents'].values()))['eventCount'], 2)
        self.assertIn(event['eventId'], journal['events'])
        self.assertEqual(self.native.creates, 1)
        self.assertFalse(self.reconcile()['unresolved'])

    def test_automatic_discovery_retains_unknown_history_and_pins_inflight_run(self):
        first = self.current_run()
        self.ingest(first)
        boundary = self.journal()['discovery']
        pending = self.run_for(self.failure, 'pending')
        missing = self.current_run()
        fresh = self.current_run()
        report = self.ingest(fresh)
        phases = [row['phase'] for row in report['unresolved']]
        self.assertIn('native_pending', phases)
        self.assertIn('original_payload_unavailable', phases)
        journal = self.journal()
        self.assertEqual(journal['discovery'], boundary)
        self.assertEqual(journal['runs'][missing['id']]['unresolved'], 'original_payload_unavailable')
        pending.update(status='failed')
        report = self.ingest(fresh)
        self.assertNotIn('native_pending', [row['phase'] for row in report['unresolved']])
        self.assertEqual(self.journal()['discovery']['runId'], fresh['id'])
        self.assertIn('original_payload_unavailable', [row['phase'] for row in report['unresolved']])
        self.assertEqual(self.native.creates, 1)

    def test_delayed_current_input_crosses_default_page_without_rewinding_discovery(self):
        self.ingest(self.current_run())
        event = dict(self.failure, eventId=identifier(), kind='escalation', sequence=2)
        delayed = self.current_run(event)
        delayed.update(status='running', triggered_at=incident.utc(self.now + 1))
        for index in range(51):
            newer = self.current_run()
            newer['triggered_at'] = incident.utc(self.now + 2 + index)
            self.ingest(newer)
        before = self.journal()
        self.assertEqual(before['runs'][delayed['id']]['unresolved'], 'original_payload_unavailable')
        previous_calls = len(self.native.calls)
        self.native.fail_get = True
        self.assertEqual(self.ingest(delayed, event)['runtimeReceipt']['unresolved'], 'incident_unreadable')
        self.native.fail_get = False
        self.native.fail_run_offsets = {50}
        retry = self.ingest(delayed, event)['runtimeReceipt']
        self.assertEqual(retry['unresolved'], 'incident_unreadable')
        self.assertEqual(retry['lastAttemptError'], 'runs_unavailable')
        self.native.fail_run_offsets.clear()
        with mock.patch.dict(incident.os.environ, {'MULTICA_TASK_ID': identifier(),
                             'MULTICA_AGENT_ID': self.trust['coordinatorId']}):
            self.assertFalse(self.reconcile()['unresolved'])
        self.assertFalse(self.ingest(delayed, event)['unresolved'])
        journal = self.journal()
        self.assertEqual(journal['discovery'], before['discovery'])
        self.assertIn(('autopilot', 'runs', self.trust['autopilotId'], '--limit', '50', '--offset', '50'),
                      self.native.calls[previous_calls:])
        receipt = next(row for row in journal['runtimeInputs'].values() if row['taskId'] == delayed['task_id'])
        self.assertTrue(receipt['bindingVerified'])
        self.assertEqual(receipt['nativeRun']['id'], delayed['id'])
        self.assertEqual(receipt['historicalPayload'], 'null')
        self.assertEqual(receipt['payload'], event)
        self.assertEqual(journal['events'][event['eventId']]['runId'], delayed['id'])
        self.assertFalse(self.ingest(delayed, event)['unresolved'])
        self.assertFalse(self.reconcile()['unresolved'])
        self.assertEqual(next(iter(self.journal()['incidents'].values()))['eventCount'], 2)
        self.assertEqual(self.native.creates, 1)
        self.assertEqual(sum(call[:2] == ('issue', 'update') for call in self.native.calls), 1)

    def test_delayed_current_proof_requires_actual_unique_readable_native_run(self):
        self.ingest(self.current_run())
        event = dict(self.failure, eventId=identifier(), kind='escalation', sequence=2)
        delayed = self.current_run(event)
        for _ in range(51):
            self.ingest(self.current_run())
        before = self.journal()
        self.assertIn(delayed['id'], before['runs'])
        self.native.fail_run_offsets = {50}
        self.assertEqual(self.ingest(delayed, event)['runtimeReceipt']['unresolved'], 'runs_unavailable')
        self.native.fail_run_offsets.clear()
        self.native.runs.remove(delayed)
        self.assertEqual(self.ingest(delayed, event)['runtimeReceipt']['unresolved'], 'runtime_task_unproven')
        self.native.runs.insert(1, delayed)
        duplicate = dict(delayed, id=identifier())
        self.native.runs.insert(1, duplicate)
        self.assertEqual(self.ingest(delayed, event)['runtimeReceipt']['unresolved'], 'runtime_task_unproven')
        self.native.runs.remove(duplicate)
        self.assertNotIn(event['eventId'], self.journal()['events'])
        self.assertEqual(self.journal()['discovery'], before['discovery'])
        self.assertEqual(self.native.creates, 1)
        self.assertFalse(self.ingest(delayed, event)['unresolved'])

    def test_bootstrap_inventory_failure_event_and_consumer_share_identifier_contract(self):
        import tls_check
        spec = importlib.util.spec_from_file_location('write_directory', ROOT / 'tools/write-server-directory.py')
        writer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(writer)
        schema = json.loads((ROOT / 'deploy/monitoring/health-event.schema.json').read_text())
        endpoint_pattern = schema['properties']['endpoints']['items']['pattern']
        for name in ('hub_a', 'a' * 64, '_hub', '-hub'):
            with self.subTest(name=name):
                document = {'schemaVersion': 2, 'revision': 1, 'directoryUrls': [],
                            'servers': [{'id': name, 'name': 'Fixture hub', 'forge': False,
                                         'url': 'wss://hub.invalid/ws'}]}
                writer.validate_directory(document)
                bootstrap = json.dumps(document).encode()
                config = {'schemaVersion': 1, 'bootstrapSha256': hashlib.sha256(bootstrap).hexdigest(),
                          'endpoints': [{'id': name, 'origin': 'wss://hub.invalid', 'serviceGroup': 'cloud_a'}]}
                selected = tls_check.load_inventory(json.dumps(config).encode(), bootstrap)
                evidence = {'endpoints': [dict(row, result='fail', error='expired', remainingSeconds=-1)
                                          for row in selected['endpoints']]}
                event = health_alerts.observe_tls(health_alerts.empty_state(), self.now,
                                                 'observer-debian', evidence)[0]
                self.assertEqual(event['endpoints'], [name])
                self.assertIsNotNone(re.fullmatch(endpoint_pattern, name))
                self.assertEqual(incident.validate_event(event, 'observer-debian'), event)
                self.trust['serviceGroups'].add('cloud_a')
                self.assertFalse(self.ingest(self.current_run(event), event)['unresolved'])
                self.assertIn(event['eventId'], self.journal()['events'])
        self.assertEqual(self.native.creates, 1)
        for name in ('', 'a' * 65, 'hub/a', 'Hub', 'hub\n'):
            with self.subTest(invalid=name):
                self.assertIsNone(re.fullmatch(endpoint_pattern, name))
                self.assertIsNone(incident.validate_event(dict(self.failure, endpoints=[name]), 'observer-debian'))
                with self.assertRaises(tls_check.ConfigError):
                    tls_check.sanitized_id(name, tls_check.ENDPOINT_ID)
        for field in ('source', 'serviceGroup'):
            pattern = schema['properties'][field]['pattern']
            for name in ('cloud_a', 'a' * 64):
                event = dict(self.failure, **{field: name})
                self.assertIsNotNone(re.fullmatch(pattern, name))
                self.assertIsNotNone(incident.validate_event(event, event['source']))
            self.assertIsNone(incident.validate_event(dict(self.failure, **{field: 'a' * 65}), 'observer-debian'))

    def test_crash_before_receipt_retains_null_obligation_and_original_recovery(self):
        run = self.current_run()
        with mock.patch.object(incident.os, 'fsync', side_effect=OSError('before persist')):
            with self.assertRaises(OSError):
                self.ingest(run)
        report = self.reconcile()
        self.assertEqual(report['unresolved'][0]['phase'], 'original_payload_unavailable')
        self.assertEqual(self.native.creates, 0)
        path = self.original_file(self.failure)
        self.assertFalse(incident.Reconciler(self.trust, runner=self.native).reconcile(
            path, self.trigger, run['id'])['unresolved'])
        stored = json.loads(next(iter(self.native.metadata.values())))
        self.assertEqual(stored['provenance']['payloadOrigin'], 'operator_original')

    def test_absent_runtime_body_is_enriched_by_original_recovery_without_erasing_receipt(self):
        run = self.current_run()
        self.assertTrue(self.ingest(run, raw=b'null')['unresolved'])
        path = self.original_file(self.failure)
        self.assertFalse(incident.Reconciler(self.trust, runner=self.native).reconcile(
            path, self.trigger, run['id'])['unresolved'])
        receipt = next(iter(self.journal()['runtimeInputs'].values()))
        self.assertEqual(base64.b64decode(receipt['rawInputBase64']), b'null')
        self.assertEqual(receipt['historicalPayload'], 'null')
        self.assertIsNone(receipt['payload'])
        self.assertEqual(receipt['recoveredBy']['origin'], 'operator_original')
        self.assertEqual(receipt['recoveredBy']['eventId'], self.failure['eventId'])
        self.assertEqual(self.native.creates, 1)

    def test_current_complete_reentry_enriches_absent_input_without_history_reconstruction(self):
        run = self.current_run()
        self.assertTrue(self.ingest(run, raw=b'null')['unresolved'])
        self.assertFalse(self.ingest(run)['unresolved'])
        receipts = list(self.journal()['runtimeInputs'].values())
        self.assertEqual(len(receipts), 2)
        absent = next(row for row in receipts if row['payload'] is None)
        self.assertEqual(absent['enrichedBy']['origin'], incident.RUNTIME_ORIGIN)
        self.assertEqual(base64.b64decode(absent['rawInputBase64']), b'null')
        self.assertEqual(json.loads(next(iter(self.native.metadata.values())))['eventCount'], 1)

    def test_crash_after_first_fsync_is_unbound_until_explicit_original_recovery(self):
        class Crash(BaseException):
            pass
        run = self.current_run()
        save = incident.Reconciler.save
        def crash_after_receipt(reconciler, journal):
            save(reconciler, journal)
            raise Crash()
        with mock.patch.object(incident.Reconciler, 'save', crash_after_receipt):
            with self.assertRaises(Crash):
                self.ingest(run)
        self.assertEqual(self.native.calls, [])
        self.assertTrue(self.reconcile()['unresolved'])
        self.assertEqual(self.native.creates, 0)
        path = self.original_file(self.failure)
        self.assertFalse(incident.Reconciler(self.trust, runner=self.native).reconcile(
            path, self.trigger, run['id'])['unresolved'])
        receipt = next(iter(self.journal()['runtimeInputs'].values()))
        self.assertEqual(receipt['recoveredBy']['origin'], 'operator_original')
        self.assertFalse(receipt.get('bindingVerified', False))

    def test_configuration_requires_workspace_and_explicit_signal_bindings(self):
        operations = {'activation': 'active', 'native': {key: self.trust[key] for key in
                       ('workspaceId', 'projectId', 'coordinatorId')}}
        config = {'schemaVersion': 1, 'autopilotId': self.trust['autopilotId'],
                  'triggers': self.trust['triggers'], 'serviceGroups': ['cloud-a'],
                  'stateDirectory': str(self.root)}
        ops_path, conf_path = self.root / 'operations.json', self.root / 'incident.json'
        ops_path.write_text(json.dumps(operations))
        conf_path.write_text(json.dumps(config))
        legacy = incident.load_trust(ops_path, conf_path)
        self.assertIsNone(legacy['signalBindings'])
        run = self.current_run()
        receipt = {'payload': self.failure, 'payloadSha256': incident.canonical_digest(self.failure)}
        with self.assertRaisesRegex(incident.IncidentError, 'runtime_event_untrusted'):
            incident.Reconciler(legacy, runner=self.native).runtime_event(receipt, run)
        config['signalBindings'] = self.trust['signalBindings']
        conf_path.write_text(json.dumps(config))
        loaded = incident.load_trust(ops_path, conf_path)
        self.assertNotEqual(loaded['configVersion'], legacy['configVersion'])
        self.assertEqual(incident.Reconciler(loaded, runner=self.native).runtime_event(receipt, run), self.failure)
        self.assertIn('observer', loaded['serviceGroups'])
        config['serviceGroups'] = ['observer']
        conf_path.write_text(json.dumps(config))
        with self.assertRaisesRegex(incident.IncidentError, 'invalid_configuration'):
            incident.load_trust(ops_path, conf_path)
        config['serviceGroups'] = ['cloud-a']
        conf_path.write_text(json.dumps(config))
        operations['native'].pop('workspaceId')
        ops_path.write_text(json.dumps(operations))
        with self.assertRaisesRegex(incident.IncidentError, 'inactive_operations'):
            incident.load_trust(ops_path, conf_path)

    def test_uncertain_create_metadata_and_admission_after_runtime_input(self):
        run = self.current_run()
        self.native.lost_create = True
        self.assertTrue(self.ingest(run)['unresolved'])
        self.native.lost_create = False
        self.native.fail_metadata = True
        self.assertTrue(self.reconcile()['unresolved'])
        self.native.fail_metadata = False
        self.native.no_task = True
        self.assertEqual(self.reconcile()['unresolved'][0]['phase'], 'admission_pending')
        self.native.no_task = False
        self.assertFalse(self.reconcile()['unresolved'])
        self.assertEqual(self.native.creates, 1)
        self.assertEqual(json.loads(next(iter(self.native.metadata.values())))['eventCount'], 1)

    def test_known_history_over_500_and_unknown_gap_do_not_discard_input(self):
        for _ in range(650):
            self.current_run()
        newest = self.native.runs[-1]
        journal = incident.empty_journal()
        journal['discovery'] = {'runId': newest['id'], 'triggeredAt': newest['triggered_at']}
        incident.Reconciler(self.trust, runner=self.native).save(journal)
        run = self.current_run()
        self.assertFalse(self.ingest(run)['unresolved'])
        for _ in range(501):
            self.current_run()
        fresh = self.current_run(dict(self.failure, eventId=identifier()))
        report = self.ingest(fresh, dict(self.failure, eventId=identifier()))
        self.assertIn('run_pagination_limit', [i['phase'] for i in report['unresolved']])
        self.assertEqual(len(self.journal()['runtimeInputs']), 2)
        self.assertEqual(self.native.creates, 1)

    def test_runtime_recovery_before_failure_preserves_episode_sequence(self):
        recovery = health_alerts.observe(self.state, self.now + 1, 'observer-debian', 'cloud-a', 'tls', True)
        first = self.current_run(recovery)
        self.assertTrue(self.ingest(first, recovery)['unresolved'])
        self.assertEqual(self.native.creates, 0)
        failure = self.current_run()
        self.assertFalse(self.ingest(failure)['unresolved'])
        stored = json.loads(next(iter(self.native.metadata.values())))
        self.assertTrue(stored['recoveryObserved'])
        self.assertEqual(stored['eventCount'], 2)
        self.assertEqual(next(iter(self.native.issues.values()))['status'], 'todo')

    def test_reversed_recovery_retains_full_runtime_receipt_and_native_run_under_pressure(self):
        recovery = health_alerts.observe(self.state, self.now + 1, 'observer-debian', 'cloud-a', 'tls', True)
        run = self.current_run(recovery)
        self.ingest(run, recovery)
        journal = self.journal()
        receipt_key = next(iter(journal['runtimeInputs']))
        for collection in ('runs', 'events', 'runtimeInputs'):
            journal[collection]['removable'] = {'at': '2099-01-01T00:00:00Z'}
        with mock.patch.object(incident, 'JOURNAL_LIMIT', 1):
            incident.Reconciler(self.trust, runner=self.native).save(journal)
        kept = self.journal()
        self.assertIn(recovery['eventId'], kept['events'])
        self.assertIn(run['id'], kept['runs'])
        self.assertIn(receipt_key, kept['runtimeInputs'])

    def test_capacity_never_evicts_pending_input_or_uncertain_incident(self):
        first, second, third = self.current_run(), self.current_run(), self.current_run()
        with mock.patch.object(incident, 'JOURNAL_LIMIT', 2):
            self.ingest(first, raw=b'null')
            self.ingest(second, raw=b'null')
            with self.assertRaisesRegex(incident.IncidentError, 'journal_capacity'):
                self.ingest(third, raw=b'null')
        self.assertEqual(len(self.journal()['runtimeInputs']), 2)
        self.assertEqual(self.native.creates, 0)

    def test_retention_pins_full_event_and_provenance_for_uncertain_issue(self):
        run = self.current_run()
        self.native.lost_create = True
        self.ingest(run)
        journal = self.journal()
        original_receipt = next(iter(journal['runtimeInputs']))
        for collection in ('events', 'runs', 'runtimeInputs'):
            journal[collection]['removable'] = {'at': '2099-01-01T00:00:00Z'}
        with mock.patch.object(incident, 'JOURNAL_LIMIT', 1):
            incident.Reconciler(self.trust, runner=self.native).save(journal)
        kept = self.journal()
        self.assertIn(run['id'], kept['runs'])
        self.assertIn(self.failure['eventId'], kept['events'])
        self.assertIn(original_receipt, kept['runtimeInputs'])
        self.assertEqual(next(iter(kept['incidents'].values()))['phase'], 'uncertain')


if __name__ == '__main__':
    unittest.main()
