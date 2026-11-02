#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Isolated real TLS and process/state/transport regressions; no public traffic."""

import argparse
from contextlib import redirect_stdout
from datetime import datetime, timedelta, timezone
import hashlib
import io
import json
import multiprocessing
import os
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import time
import unittest
import urllib.error
from unittest.mock import patch

import health_alerts as alerts
import tls_check as tls


def inventory(host, port, ids=("hub-a",), groups=None):
    bootstrap = json.dumps({'schemaVersion': 2, 'revision': 1, 'directoryUrls': [],
                            'servers': [{'id': name, 'url': f'wss://{host}:{port}/ws'} for name in ids]}).encode()
    config = {'schemaVersion': 1, 'bootstrapSha256': hashlib.sha256(bootstrap).hexdigest(),
              'endpoints': [{'id': name, 'origin': f'wss://{host}:{port}',
                             'serviceGroup': (groups or {}).get(name, 'cloud-a')} for name in ids]}
    return tls.load_inventory(json.dumps(config).encode(), bootstrap), config, bootstrap


class TLSServer:
    def __init__(self, cert, key):
        self.socket = socket.socket()
        self.socket.bind(('127.0.0.1', 0))
        self.port = self.socket.getsockname()[1]
        self.socket.listen()
        self.socket.settimeout(.1)
        self.context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.context.load_cert_chain(cert, key)
        self.stop = multiprocessing.Event()
        self.counter = multiprocessing.Value('i', 0)
        self.process = multiprocessing.get_context('fork').Process(target=self.run)
        self.process.start()

    @property
    def connections(self):
        return self.counter.value

    def run(self):
        while not self.stop.is_set():
            try:
                raw, _ = self.socket.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            with self.counter.get_lock():
                self.counter.value += 1
            raw.settimeout(1)
            try:
                self.context.wrap_socket(raw, server_side=True).close()
            except (OSError, ssl.SSLError):
                raw.close()

    def close(self):
        self.stop.set()
        self.process.join(2)
        if self.process.is_alive():
            self.process.kill()
            self.process.join()
        self.socket.close()


class TLSFixtures(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        def openssl(*args):
            subprocess.run(['openssl', *map(str, args)], cwd=cls.root, check=True, capture_output=True)
        openssl('req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=Fixture CA',
                '-keyout', 'ca.key', '-out', 'ca.pem', '-days', '10',
                '-addext', 'keyUsage=critical,keyCertSign,cRLSign')
        openssl('req', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=localhost',
                '-keyout', 'leaf.key', '-out', 'leaf.csr')
        (cls.root / 'index').write_text('')
        (cls.root / 'serial').write_text('1000\n')
        (cls.root / 'ca.cnf').write_text('''[ca]
default_ca=issuer
[issuer]
database=index
serial=serial
new_certs_dir=.
certificate=ca.pem
private_key=ca.key
default_md=sha256
policy=names
unique_subject=no
x509_extensions=extensions
[names]
commonName=supplied
[extensions]
subjectAltName=DNS:localhost,IP:127.0.0.1
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
''')
        now = datetime.now(timezone.utc)
        for name, start, end in [('valid', -24, 120), ('near', -24, 1),
                                 ('expired', -72, -1), ('future', 24, 120)]:
            def stamp(hours):
                return (now + timedelta(hours=hours)).strftime('%Y%m%d%H%M%SZ')
            openssl('ca', '-batch', '-config', 'ca.cnf', '-in', 'leaf.csr', '-out', name + '.pem',
                    '-startdate', stamp(start), '-enddate', stamp(end))

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def probe(self, variant='valid', host='localhost', trusted=True, ids=('hub-a',)):
        server = TLSServer(self.root / (variant + '.pem'), self.root / 'leaf.key')
        self.addCleanup(server.close)
        selected, _, _ = inventory(host, server.port, ids)
        def loopback(host, port, **kwargs):
            return socket.getaddrinfo('127.0.0.1', port, **kwargs)
        result = tls.collect(selected, cafile=str(self.root / 'ca.pem') if trusted else None,
                             resolver=loopback, per_origin=1, total=2)
        return selected, result, server

    def test_valid_ca_dns_and_ip_san_with_coverage_and_identity_dedup(self):
        for host in ('localhost', '127.0.0.1'):
            with self.subTest(host=host):
                selected, result, server = self.probe(host=host, ids=('hub-a', 'hub-b'))
                self.assertEqual(result['result'], 'pass')
                self.assertEqual(result['counts'], {'endpoints': 2, 'identities': 1, 'passed': 2, 'failed': 0})
                self.assertEqual(server.connections, 1)
                self.assertGreater(tls.verify_evidence(result, selected, time.time(), 300), 48 * 3600)
                encoded = json.dumps(result)
                self.assertNotIn(host, encoded)
                self.assertNotIn('Fixture CA', encoded)
                self.assertNotIn('subjectAltName', encoded)

    def test_real_valid_but_less_than_48_hours_expired_future_untrusted_and_name_ip_mismatch(self):
        for variant, host, trusted, error in [('near', 'localhost', True, 'near_expiry'),
                                              ('expired', 'localhost', True, 'expired'),
                                              ('future', 'localhost', True, 'not_yet_valid'),
                                              ('valid', 'localhost', False, 'untrusted'),
                                              ('valid', 'wrong.invalid', True, 'name_mismatch'),
                                              ('valid', '127.0.0.2', True, 'name_mismatch')]:
            with self.subTest(error=error, host=host):
                _, result, _ = self.probe(variant, host, trusted)
                self.assertEqual(result['result'], 'fail')
                self.assertEqual(result['endpoints'][0]['error'], error)

    def test_unreachable_and_dns_failure_deadline_are_bounded_without_workers_left(self):
        with socket.socket() as unused:
            unused.bind(('127.0.0.1', 0))
            port = unused.getsockname()[1]
        selected, _, _ = inventory('127.0.0.1', port)
        result = tls.collect(selected, per_origin=.2, total=.3)
        self.assertEqual(result['endpoints'][0]['error'], 'connect_failure')
        def failure(*args, **kwargs):
            raise socket.gaierror('secret.invalid raw secret')
        result = tls.collect(selected, resolver=failure)
        self.assertEqual(result['endpoints'][0]['error'], 'dns_failure')
        def blocked(*args, **kwargs):
            time.sleep(5)
        before = set(multiprocessing.active_children())
        start = time.monotonic()
        result = tls.collect(selected, resolver=blocked, per_origin=.15, total=.2)
        self.assertEqual(result['endpoints'][0]['error'], 'timeout')
        self.assertLess(time.monotonic() - start, 1)
        self.assertEqual(set(multiprocessing.active_children()), before)

    def test_fresh_evidence_cannot_be_stale_future_partial_failing_or_lifetime_crossing(self):
        selected, evidence, _ = self.probe()
        now = time.time()
        for mutation, error in [(lambda e: e.update(collectedAt=tls.utc(now - 301)), 'stale'),
                                 (lambda e: e.update(completedAt=tls.utc(now + 10)), 'future'),
                                 (lambda e: e.update(endpoints=[]), 'incomplete'),
                                 (lambda e: e.update(result='fail'), 'failing'),
                                 (lambda e: e['endpoints'][0].update(notAfter=tls.utc(now + 47 * 3600)), 'near_expiry')]:
            candidate = json.loads(json.dumps(evidence))
            mutation(candidate)
            with self.subTest(error=error), self.assertRaisesRegex(ValueError, error):
                tls.verify_evidence(candidate, selected, now, 300)


class InputTests(unittest.TestCase):
    def test_invalid_urls_and_empty_duplicate_missing_coverage_bootstrap_identity(self):
        for value in ('http://a.invalid', 'https://user:secret@a.invalid', 'https://a.invalid/path',
                      'https://a.invalid?', 'https://a.invalid#', 'https://a.invalid:0',
                      'https://a.invalid:', 'https://a.invalid:65536', 'https://a.invalid/\n'):
            with self.subTest(value=value), self.assertRaises(tls.ConfigError):
                tls.origin(value)
        selected, config, bootstrap = inventory('localhost', 443)
        for mutate in (lambda c: c.update(endpoints=[]),
                       lambda c: c['endpoints'].append(c['endpoints'][0]),
                       lambda c: c['endpoints'][0].update(id='other'),
                       lambda c: c['endpoints'][0].update(origin='wss://other.invalid'),
                       lambda c: c.update(bootstrapSha256='0' * 64)):
            candidate = json.loads(json.dumps(config))
            mutate(candidate)
            with self.assertRaises(tls.ConfigError):
                tls.load_inventory(json.dumps(candidate).encode(), bootstrap)
        document = json.loads(bootstrap)
        document['directoryUrls'] = ['https://directory.invalid/catalog.json']
        raw = json.dumps(document).encode()
        config['bootstrapSha256'] = hashlib.sha256(raw).hexdigest()
        with self.assertRaisesRegex(tls.ConfigError, 'incomplete_coverage'):
            tls.load_inventory(json.dumps(config).encode(), raw)
        config['endpoints'].append({'id': 'catalog-a', 'origin': 'https://directory.invalid', 'serviceGroup': 'cloud-a'})
        self.assertEqual(len(tls.load_inventory(json.dumps(config).encode(), raw)['endpoints']), 2)
        self.assertEqual(selected['minimumRemainingSeconds'], 48 * 3600)


def increment_process(directory, count):
    for _ in range(count):
        with alerts.Store(directory) as store:
            state = store.load(time.time())
            alerts.observe(state, time.time(), 'observer-debian', 'cloud-a', 'tls', False, {'timeout': 1})
            store.save(state)


class AlertTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.now = int(time.time())
        self.state = alerts.empty_state()
        self.capability = self.root / 'capability'
        self.capability.write_text('https://notify.invalid/capability-secret')
        self.capability.chmod(0o600)

    def fail(self, signal='tls', group='cloud-a'):
        return alerts.observe(self.state, self.now, 'observer-debian', group, signal, False, {'timeout': 1})

    def test_repeated_renewal_failures_are_counted_and_recovery_retains_episode_evidence(self):
        first = self.fail('renewal')
        for _ in range(15):
            self.fail('renewal')
        self.assertEqual(len(self.state['outbox']), 4)  # first + 2/4/8 escalation
        event = alerts.observe(self.state, self.now + 1, 'observer-debian', 'cloud-a', 'renewal', True)
        self.assertEqual(event['consecutiveFailures'], 16)
        self.assertEqual(event['episodeId'], first['episodeId'])
        record = self.state['signals']['cloud-a/renewal']
        self.assertEqual(record['lastRecovery']['failures'], 16)
        self.assertEqual(record['totalFailures'], 16)
        self.assertIsNone(alerts.observe(self.state, self.now + 2, 'observer-debian', 'cloud-a', 'renewal', True))

    def test_real_systemd_invocation_dedup_without_transport_or_changing_result(self):
        config = self.root / 'renewal.json'
        config.write_text(json.dumps({'schemaVersion': 1, 'serviceGroup': 'cloud-a'}))
        args = argparse.Namespace(config=config, state=self.root / 'state', source='renewal-cloud', webhook_file=None)
        def forbidden(*args):
            self.fail('network called from certbot hook')
        env = {'INVOCATION_ID': 'a' * 32, 'SERVICE_RESULT': 'exit-code', 'EXIT_CODE': 'exited', 'EXIT_STATUS': '1'}
        with redirect_stdout(io.StringIO()):
            self.assertEqual(alerts.run_renewal(args, env, sender=forbidden), 0)
            self.assertEqual(alerts.run_renewal(args, env, sender=forbidden), 0)
            env.update(INVOCATION_ID='b' * 32, SERVICE_RESULT='success', EXIT_STATUS='0')
            self.assertEqual(alerts.run_renewal(args, env, sender=forbidden), 0)
        with alerts.Store(args.state) as store:
            state = store.load(self.now)
        self.assertEqual(len(state['outbox']), 2)
        self.assertEqual(state['signals']['cloud-a/renewal']['totalFailures'], 1)
        self.assertEqual(state['outbox'][1]['event']['kind'], 'recovery')

    def test_competing_processes_atomic_crash_and_corrupt_state_fail_closed(self):
        directory = self.root / 'state'
        context = multiprocessing.get_context('fork')
        processes = [context.Process(target=increment_process, args=(directory, 12)) for _ in range(3)]
        for process in processes:
            process.start()
        for process in processes:
            process.join(10)
            self.assertEqual(process.exitcode, 0)
        with alerts.Store(directory) as store:
            state = store.load(self.now)
            self.assertEqual(state['signals']['cloud-a/tls']['totalFailures'], 36)
            self.assertEqual(len(state['outbox']), 2)
            before = store.path.read_bytes()
            with patch.object(alerts.os, 'replace', side_effect=OSError('fixture crash')):
                with self.assertRaises(OSError):
                    store.save(state)
            self.assertEqual(store.path.read_bytes(), before)
            store.path.write_text('{corrupt')
            with self.assertRaisesRegex(alerts.AlertError, 'state_corrupt'):
                store.load(self.now)
            self.assertEqual(store.path.read_text(), '{corrupt')

    def test_outbox_capacity_and_immutable_event_retries_exhaustion_and_skipped_admission(self):
        self.fail()
        original = json.dumps(self.state['outbox'][0]['event'], sort_keys=True)
        attempted = []
        def sender(url, event, timeout):
            attempted.append(json.dumps(event, sort_keys=True))
            persisted = json.loads((self.root / 'state/state.json').read_text())
            self.assertEqual(persisted['outbox'][0]['event'], event)
            return 'timeout', None
        with alerts.Store(self.root / 'state') as store:
            for attempt in range(alerts.MAX_ATTEMPTS):
                alerts.deliver(store, self.state, self.capability, sender=sender, wall=lambda: self.now + attempt * 4000)
            self.assertEqual(self.state['outbox'][0]['status'], 'exhausted')
            self.assertEqual(attempted, [original] * alerts.MAX_ATTEMPTS)
            self.assertTrue(self.state['transport']['degraded'])
            alerts.redrive(self.state, self.now + 30000)
            alerts.deliver(store, self.state, self.capability, sender=lambda *args: ('skipped', 'a' * 36),
                           wall=lambda: self.now + 30000)
            self.assertTrue(self.state['transport']['degraded'])
            self.assertEqual(self.state['history'][0]['event']['eventId'], json.loads(original)['eventId'])
        # Backlog never grows without limit and overflow remains visible.
        self.state = alerts.empty_state()
        for number in range(alerts.OUTBOX_LIMIT + 5):
            self.fail(group='cloud-a')
            alerts.observe(self.state, self.now + number + 1, 'observer-debian', 'cloud-a', 'tls', True)
        self.assertEqual(len(self.state['outbox']), alerts.OUTBOX_LIMIT)
        self.assertGreater(self.state['counters']['droppedEvents'], 0)
        self.assertTrue(self.state['transport']['degraded'])

    def test_unrelated_accepted_delivery_and_healthy_sample_cannot_clear_exhausted_or_skipped(self):
        self.fail()
        self.state['outbox'][0].update(status='exhausted', attempts=alerts.MAX_ATTEMPTS, lastError='timeout')
        self.fail(group='cloud-b')
        with alerts.Store(self.root / 'mixed') as store:
            alerts.deliver(store, self.state, self.capability,
                           sender=lambda *args: ('accepted', '12345678-1234-1234-1234-123456789abc'),
                           wall=lambda: self.now)
            self.assertTrue(self.state['transport']['degraded'])
            self.assertTrue(alerts.summary(self.state)['transportDegraded'])
            self.state['outbox'].clear()
            self.fail(group='cloud-c')
            alerts.deliver(store, self.state, self.capability,
                           sender=lambda *args: ('skipped', '12345678-1234-1234-1234-123456789abc'),
                           wall=lambda: self.now)
            self.fail(group='cloud-d')
            alerts.deliver(store, self.state, self.capability,
                           sender=lambda *args: ('accepted', '12345678-1234-1234-1234-123456789abc'),
                           wall=lambda: self.now)
            self.assertTrue(self.state['transport']['degraded'])
            for group in ('cloud-a', 'cloud-b', 'cloud-c', 'cloud-d'):
                alerts.observe(self.state, self.now + 1, 'observer-debian', group, 'tls', True)
            self.assertTrue(alerts.summary(self.state)['transportDegraded'])
            store.save(self.state)
            reloaded = store.load(self.now)
            self.assertTrue(alerts.summary(reloaded)['transportDegraded'])

    def test_sender_reuses_exact_body_key_and_redacts_transport_errors(self):
        event = self.fail()
        requests = []
        class Response:
            def __enter__(self):
                return self
            def __exit__(self, *args):
                pass
            def read(self, limit):
                return json.dumps({'status': 'accepted', 'run_id': '12345678-1234-1234-1234-123456789abc'}).encode()
        class Opener:
            def open(self, request, timeout):
                requests.append(request)
                return Response()
        # Directly inspect the HTTP boundary; production uses a joined worker.
        with patch.object(alerts, 'bounded', side_effect=lambda fn, timeout: fn()), \
                patch.object(alerts.urllib.request, 'build_opener', return_value=Opener()):
            for _ in range(2):
                outcome, _ = alerts.post('https://notify.invalid/capability-secret', event, 1)
                self.assertEqual(outcome, 'accepted')
        self.assertEqual(requests[0].data, requests[1].data)
        self.assertEqual(requests[0].get_header('Idempotency-key'), event['eventId'])
        self.assertNotIn(b'capability-secret', requests[0].data)
        class Failure:
            def open(self, request, timeout):
                raise urllib.error.HTTPError(request.full_url, 503, 'raw-secret', {}, None)
        with patch.object(alerts.urllib.request, 'build_opener', return_value=Failure()):
            self.assertEqual(alerts.post('https://notify.invalid/capability-secret', event, 1), ('http_5xx', None))
        before = set(multiprocessing.active_children())
        self.assertEqual(alerts.bounded(lambda: time.sleep(5), .05), ('timeout', None))
        self.assertEqual(set(multiprocessing.active_children()), before)

    def test_secret_transport_errors_status_stale_and_capability_modes(self):
        self.capability.chmod(0o644)
        with self.assertRaisesRegex(alerts.AlertError, 'unprotected'):
            alerts.read_capability(self.capability)
        self.capability.chmod(0o600)
        self.capability.unlink()
        self.capability.symlink_to(self.root / 'secret')
        with self.assertRaises(alerts.AlertError):
            alerts.read_capability(self.capability)
        with alerts.Store(self.root / 'status') as store:
            state = alerts.empty_state()
            state['latest'] = {'collectedAt': tls.utc(self.now - 901), 'result': 'pass'}
            store.save(state)
        output = io.StringIO()
        with redirect_stdout(output):
            code = alerts.run_status(argparse.Namespace(state=self.root / 'status', max_age=900), wall=lambda: self.now)
        self.assertEqual(code, 3)
        self.assertTrue(json.loads(output.getvalue())['stale'])
        self.assertNotIn('capability-secret', output.getvalue())


if __name__ == '__main__':
    unittest.main()
