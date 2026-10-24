# Local server monitoring

Install optional local recording through the existing release entry point,
with explicit configured targets and version. Target inventory is operator-owned;
see [configuration setup](../home/README.md#production-release-upgrades).
Notification delivery is a separate configuration.

```sh
HEXPROOF_TARGETS="cloud-a cloud-b" HEXPROOF_VERSION=2.4.0 \
  HEXPROOF_INSTALL_MONITORING=1 ./deploy/deploy-release-server.sh
HEXPROOF_TARGETS="home-a home-b" HEXPROOF_VERSION=2.4.0 \
  HEXPROOF_INSTALL_MONITORING=1 ./deploy/deploy-release-server.sh
```

Monitoring installs only after the application deployment succeeds and its
running version is checked. A monitoring installation failure leaves the
successfully upgraded application in place and returns an error for diagnosis;
it does not restart or roll back the application. Read-only verification rejects
the installation option. Ordinary upgrades preserve the installed monitor.
`install.py` is an internal component, not an application deployment entry point.

`hexproof-monitor.timer` runs an unprivileged, restricted Python standard-library
probe every 30 seconds. It contacts only the local hub's `/healthz` and `/readyz`
on port 57320 (cloud) or 57323 (home). No public proxy route, listener, account,
room or remote notification channel is created. Each request has a three-second
timeout and a 64 KiB response limit. The service has a 15-second execution limit.

Only allowlisted aggregate fields are recorded. Collection covers liveness,
dependency readiness, probe latency, account RPC/admission and cluster directory
timings, queue send failures, and cluster publication failures. Alerts indicate
unavailable dependencies, probe or interval-mean latency over one second, and
new failed operations/publications/queue sends. Restarted counters reset the
interval baseline; an unchanged historical failure does not generate a new
alert. The first observation establishes the counter baseline. A healthy sample
after an alert records recovery. These are operational signals, not a capacity
or availability guarantee; a stopped host cannot run its own local monitor.

Root can inspect the local evidence:

```sh
sudo systemctl status hexproof-monitor.timer --no-pager
sudo cat /var/lib/hexproof-monitor/latest.json
sudo tail /var/lib/hexproof-monitor/alerts.jsonl
sudo journalctl -u hexproof-monitor.service --no-pager -n 20
```

The private state directory contains `latest.json`, up to eight 4 MiB sample
logs and up to eight 1 MiB alert logs. systemd owns the dynamic service identity;
the files use mode 0600 and are retained over restarts. Journald also receives
brief collection summaries. Install records and previous monitor files remain
under `/var/lib/hexproof-monitor-install/`; workstation installation/readback
evidence is under `build/release-VERSION/monitoring/`.

Verification: `python3 -m unittest discover -s deploy/monitoring -p 'test_*.py'`
covers real loopback collection, failure/recovery, interval and reset behavior,
schema redaction and bounded log rotation. Deployment checks a fresh ready
sample and an active timer on each selected node.

## Public feedback readiness

`hexproof-feedback-monitor.service` and its separate timer reuse `probe.py`
against the public V2 receiver's loopback port 57324. This receiver returns
JSON `{ "ok": true }`, rather than the hub's control-plane schema; select
`--component feedback` explicitly. The dedicated dynamic identity has no
access to feedback stores, GitHub credentials, native sockets or receipt
capabilities. State and bounded logs use `/var/lib/hexproof-feedback-monitor`.

The templates are operator-installed monitoring support files, not a new
application deployment entry point. Deploy the receiver itself with
`HEXPROOF_COMPONENT=feedback ./deploy/deploy-release-server.sh` and its explicit
version, target and private inputs. Install the reviewed probe and the two
feedback monitor units as part of the authorized proxy/monitoring activation;
preserve the existing hub monitor and take backups before replacing its shared
probe. Validate units with `systemd-analyze verify`, reload systemd, enable the
feedback timer and start one fresh sample. A ready sample and active timer are
required before opening intake. Ordinary game-monitor installation updates the
same backwards-compatible probe without removing the feedback units.

This monitor records local liveness, storage readiness, latency and recovery;
it does not attest HTTPS reachability, GitHub publication, native AI task
execution or successful removal. The current public V2 readiness response
contains no queue aggregates. Existing private V1 admin statistics must not be
reported as public V2 outbox monitoring. Check pending publication and native
recovery separately under the feedback operations procedure. Notification
delivery remains unconfigured, and a stopped host cannot monitor itself.
