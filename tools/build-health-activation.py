#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Export immutable monitoring files and hashes from one committed public candidate."""

import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile

from git_evidence import git, repo_root, require_official_origin

FILES = (
    'deploy/monitoring/tls_check.py',
    'deploy/monitoring/health_alerts.py',
    'deploy/monitoring/hexproof-public-tls.service',
    'deploy/monitoring/hexproof-public-tls.timer',
    'deploy/monitoring/hexproof-health-send.service',
    'deploy/monitoring/hexproof-health-send.timer',
    'deploy/monitoring/hexproof-cert-renew-health.conf',
    'deploy/monitoring/health-bootstrap.example.json',
    'deploy/monitoring/health-inventory.example.json',
    'deploy/monitoring/health-renewal.example.json',
    'deploy/monitoring/health-incident.example.json',
    'deploy/monitoring/health-event.schema.json',
    'deploy/monitoring/health-runtime-instructions.md',
    'tools/health-incident.py',
    'tools/promote-release.py',
    'docs/health-monitoring.md',
)


def build(repo, output):
    repo = repo_root(repo)
    require_official_origin(repo, 'ClayStan404/hexproof')
    commit = git(repo, 'rev-parse', 'HEAD').decode().strip()
    tree = git(repo, 'rev-parse', 'HEAD^{tree}').decode().strip()
    contents = {name: git(repo, 'show', commit + ':' + name) for name in FILES}
    sums = {name: hashlib.sha256(data).hexdigest() for name, data in contents.items()}
    manifest = {'schemaVersion': 1, 'repository': 'ClayStan404/hexproof', 'sourceCommit': commit,
                'sourceTree': tree, 'files': sums,
                'note': 'Monitoring-only package; use full frozen checkout for release tools. No private inputs.'}
    contents['MANIFEST.json'] = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
    contents['SHA256SUMS'] = ''.join(hashlib.sha256(data).hexdigest() + '  ' + name + '\n'
                                   for name, data in sorted(contents.items())).encode()
    output = Path(output)
    if output.exists():
        raise ValueError('Refusing to overwrite an activation package')
    output.parent.mkdir(parents=True, exist_ok=True)
    # Deterministic archive identity; no machine paths, uid or current timestamps.
    with output.open('xb') as raw, gzip.GzipFile(fileobj=raw, mode='wb', mtime=0, filename='') as compressed:
        with tarfile.open(fileobj=compressed, mode='w') as archive:
            for name, data in sorted(contents.items()):
                entry = tarfile.TarInfo(name)
                entry.size = len(data)
                entry.mode = 0o644
                archive.addfile(entry, io.BytesIO(data))
    return {'sourceCommit': commit, 'sourceTree': tree, 'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
            'files': sums}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.repo, args.output), sort_keys=True))
