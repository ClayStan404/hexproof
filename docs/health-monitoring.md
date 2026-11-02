# Public TLS, renewal alerts and release readiness

The existing loopback monitor still measures local liveness/readiness. The
separate Debian observer checks **trusted intended release origins**, even when
the cloud host or its DNS is broken. Neither establishes native maintenance
completion. No game binary, game unit, DNS rule or renewal command is changed.

## Inputs and trust

`deploy/monitoring/tls_check.py` is the shared Python standard-library collector.
Schema-1 inventory maps unique endpoint `id` to HTTPS/WSS `origin` and
`serviceGroup`; see the synthetic `health-inventory.example.json` and matching
`health-bootstrap.example.json`. Keep real inventory outside Git, mode 0600.
Endpoint IDs follow the packaging bootstrap contract: 1–64 lowercase ASCII
letters, digits, underscores or hyphens, including a leading underscore/hyphen.
Source and service-group IDs require a leading letter/digit followed by up to
63 letters, digits, underscores or hyphens. The external inventory, renewal
configuration and incident `serviceGroups` list must not use `observer`: that
group is reserved for collector/configuration failure and recovery events and
is automatically trusted by the incident consumer. Its events remain valid in
the event schema. This keeps an endpoint failure separate from collector health.
The bootstrap is the **actual raw release input** supplied as
`HEXPROOF_PUBLIC_SERVERS_JSON` to `tools/write-server-directory.py`, not the
tracked client example or a fetched catalog. `bootstrapSha256` hashes those
exact input bytes (including whitespace). Bind that digest in the private
packaging/readiness evidence before publishing. If CI's input cannot be
established, readiness is unqualified; do not substitute a sample digest.

All bootstrap server IDs must map to their exact primary WSS origins; every
bootstrap directory and legacy origin needs coverage too. Directory/legacy
paths are reduced to origins; inventory entries themselves accept no path
except `/`, credentials, query or fragment. Only HTTPS/WSS is accepted, so an
insecure legacy/bootstrap endpoint blocks readiness. Empty/missing input,
duplicate IDs and incomplete coverage fail closed. Hosts normalize case,
trailing dots and IP spelling. The TLS probe deduplicates `(host,port)` across
schemes while retaining every endpoint ID; different names never merge because
they happen to resolve to the same IP or use the same certificate.

Normal system CA, hostname/IP SAN and current validity verification is mandatory;
the default lifetime floor is 48 hours. Test CA injection changes only the trust
store, never verification mode. Limits: 32 endpoints, four addresses per
identity, 5 seconds per identity, 60 seconds total including DNS, 64 KiB per
input/result. A killable, joined worker contains each DNS/connect/handshake;
there are no outstanding resolver threads after collection. Linux/Debian is
required. Output contains only IDs, UTC times, expiry, digests, counts and enum
errors, never origins, SANs, certificate subjects, response bodies or exceptions.
This is TLS observation, not an application-health HTTP request or cloud-DNS
diagnosis. There is no redirect or downloaded target discovery.

```sh
python3 deploy/monitoring/tls_check.py --config "$HEXPROOF_TLS_INVENTORY" \
  --bootstrap "$HEXPROOF_RELEASE_BOOTSTRAP"
```

## Durable observations and transport

`hexproof-public-tls.timer` runs on the external Debian observer every five
minutes. Its credential-mounted private inputs and state are separate from the
loopback monitor. `health_alerts.py status --state DIRECTORY` refuses stale
samples (default 15 minutes), future samples, pending/exhausted transport and
recorded queue loss. Skipped admissions, unconfirmed duplicate admissions and queue loss remain sticky operator
obligations in this local record, including after unrelated successful delivery;
reconcile their event/run evidence privately rather than clearing history to
make local status green. Observer offline, observer clock error and its own network
failure are explicit blind spots; a timer cannot alert while its host is down.
Use an independently operated observer availability check if needed; no new
service or AI schedule is configured here.

The cloud renewal drop-in adds only `ExecStopPost`, records real systemd
`INVOCATION_ID`/result once within a bounded 64-invocation deduplication window,
and ignores hook failure so certbot's result is preserved. It performs no
network I/O; a separate one-minute sender timer drains its durable outbox.
Success means certbot exited successfully, not that it renewed a certificate
or that external TLS recovered. Subsequent external observation owns TLS
recovery. Do not manually replay an old systemd invocation after the deduplication
window; the status hook is for actual invocations, not historical log import.

Each signal retains first/last failure, total/consecutive failures, last success
and the previous recovery's failure count. Alerts occur on first failure,
TLS failure counts 12/72/288 or renewal counts 2/4/8, and recovery. Healthy
samples do not send alerts. Episode UUIDs survive restart. The event UUID and
entire payload and canonical request-body SHA-256 are fsynced **before** sending; every retry sends identical JSON
and `Idempotency-Key`. At most six attempts, exponential 60s to 3600s backoff,
eight events/20s per sender invocation. A crash consumes an attempt before the
network effect; the same identity is reconciled on retry. Exhausted events
remain for operator recovery:

```sh
sudo python3 /usr/local/lib/hexproof-health/health_alerts.py deliver \
  --state /var/lib/hexproof-health-cloud \
  --webhook-file /etc/hexproof-health/webhook-url --redrive-exhausted
```

The capability is an HTTPS URL in a root-owned 0600 private file or a systemd
credential. The sender disables proxy environment use and redirects, verifies
TLS and bounds DNS/response/deadline. Do not print the URL, put it in arguments
or send it to a model. The health sender uses a flat JSON health event. No
supported generic envelope that guarantees native payload retention has been
established: the current native CLI can return `trigger_payload: null` for this
wire format. Do not borrow the feedback event format or guess a private API.

HTTP acceptance is distinct from run admission. `accepted` and `skipped` require
a valid original `run_id`. A same-key `duplicate` response also requires that
run ID and records its association, but says nothing about whether the original
run was admitted, skipped, failed or remains unknown. It stops automatic retries
and leaves a sticky `unconfirmedAdmissions` obligation. An optional delivery ID
is not admission evidence. Neither a duplicate nor an unrelated successful send
clears degraded state. Rejection, malformed/unsupported responses and paused
routes may produce **no run**; the original event stays in the bounded outbox
without a fabricated run/skipped record. Retries always keep the original ID and
bytes. Never mint a replacement UUID to recover admission.

A single `flock`, atomic replacement, file+directory fsync and 1 MiB state limit
protect each host's state. Outbox 64, history 32, signals 64 and bounded invocation
history prevent growth. Skipped/duplicate history is pinned; if all 32 history
slots hold those obligations, additional terminal events remain in the bounded
outbox without automatic retry. Successful traffic cannot evict those original
payloads. Queue overflow increments permanent loss evidence and
degraded status; there is no claim of lossless delivery through arbitrary
outage. Logs rotate at 1 MiB with four backups. Corrupt state fails closed in
place, preserving unresolved events for private operator recovery. Never delete
state to make a check green. Back up and reconcile unresolved event IDs before
any explicitly authorized restoration; normal rollback preserves all state.

## Fixed native admission and canonical incident

Activation configures a dedicated webhook Autopilot in the **existing trusted
Operations project**, fixed Mika coordinator, `run_only` execution mode. Use
separate fixed source trigger mappings for observer and renewal. Do not use the
feedback receiver, `create_issue` recent-title guard, another AI schedule, shell
commands from payloads or arbitrary projects/targets. Store capability files
privately. Configure only the existing approved route under parent task scope.
The maintained [fixed run instruction](../deploy/monitoring/health-runtime-instructions.md)
forwards the complete directly injected `Trigger payload.eventPayload` object
through a file-write tool into `health-runtime-event.json` in that task's
directory. It then invokes `health-incident.py ingest` on stdin. Event values
never enter shell syntax, arguments, configuration or state paths. The activation
coordinator fills in the instruction's three absolute trusted paths using the
immutable candidate, reads the resulting native description back, and retains
that exact invocation with its source/file hashes. No envelope, payload-file API,
credentials or model adapter is inferred. Missing carrier means forwarding JSON
`null` and reporting absence; summaries/history cannot supply missing fields.

Private `health-incident.json` follows `health-incident.example.json`. Project
and coordinator, plus workspace, come only from the active operations manifest;
alert group/source and `signalBindings` for the actual trigger must match the
configured allowlists. Legacy configurations without `signalBindings` support
historical recovery only; runtime admission fails closed until the operator
supplies them. This is an explicit activation migration, including isolated
qualification manifests which previously omitted `native.workspaceId`.
All entry points, including
operator recovery, use **the same fixed Debian state directory/lock/journal**.
Use a private state directory owned by the existing authenticated Multica CLI
operator (create it under that operator's private state root). Run with that
identity, never a new root CLI identity/credential or on multiple hosts. The helper creates a backlog issue with
an exact incident marker, writes bounded original event/run/trigger provenance,
reads metadata back, then admits to fixed Mika. Metadata stores event/run/trigger
IDs and canonical payload digests; full original payloads remain in the bounded
private journal and, only when actually retained, the original native run. Native `issue runs` association
is required to record a maintenance task ID; status alone is insufficient.
TLS and renewal episodes for a still-open service group share that issue.
Late/duplicate recovery changes only its matching episode and never closes
maintenance or a newer fault.

CLI 0.7.0 supports paginated `autopilot runs` with status, `task_id` and a
nullable `trigger_payload`; it has no delivery query/replay, and manual
`autopilot trigger` has no payload. Native runs with null, invalid or unsupported
payload remain explicit `original_payload_unavailable` obligations on every
reconciliation/status read; they never disappear into an empty successful
report. A current runtime receipt can resolve that obligation while retaining
the separate historical-null fact. The normal automatic path is **ingest**;
historical reconciliation also accepts original valid native payloads:

```sh
python3 tools/health-incident.py ingest --operations "$HEXPROOF_OPERATIONS_FILE" \
  --config "$HEXPROOF_HEALTH_INCIDENT_FILE" < ./health-runtime-event.json
python3 tools/health-incident.py reconcile --operations "$HEXPROOF_OPERATIONS_FILE" \
  --config "$HEXPROOF_HEALTH_INCIDENT_FILE"
python3 tools/health-incident.py status --operations "$HEXPROOF_OPERATIONS_FILE" \
  --config "$HEXPROOF_HEALTH_INCIDENT_FILE"
```

`ingest` itself reads documented `MULTICA_TASK_ID` / `MULTICA_AGENT_ID`; no event
or argument may supply identity. A missing/wrong identity causes no CLI call or
profile fallback. Supported task-scoped `autopilot get` must prove exact
workspace/project/agent/run_only bindings, and bounded paginated `autopilot runs`
must return exactly one run whose actual `task_id` equals the current task.
Its autopilot, webhook source and configured generic webhook trigger must match.
Neither latest-run selection, `auth status`, nor a historical task proves this.
Route status may have been paused after dispatch; it does not change an actual
run/task association. Missing/ambiguous binding, incomplete pagination, a
coverage gap or a conflicting non-null historical body remain unresolved.

The [event schema](../deploy/monitoring/health-event.schema.json) requires all 19
fields and rejects extra properties. The parser additionally rejects duplicate
keys, non-finite numbers, invalid UTC calendar dates, boolean counts and inputs
above 65536 UTF-8 bytes. UUIDs are lowercase; IDs/error enums/counts/endpoint
arrays and trusted source/group/signal are bounded. A schema-valid modified
event without independent original bytes cannot be authenticated by this path.

Under the same journal lock, **before native discovery**, `runtimeInputs` saves
the full received bytes (base64), parsed complete event/canonical SHA-256 when
valid, receipt time, environment identity, provenance and configuration version
(schema plus digest of the trusted binding/configuration). Invalid input is
retained too; oversized input is explicitly truncated/rejected. After native
binding, it saves actual run/task/trigger/source/status and historical payload
presence separately. Both file and directory fsync must succeed before issue
effects. Metadata identifies `payloadOrigin=runtime-injected/model-forwarded`.
Task binding proves the route; it does not independently authenticate the body
or resist the same OS user changing local state. A digest proves consistency,
not a signature. Same-run reentry and same-event cross-run delivery only add
provenance; changed event/run identity or digest fails closed without recounting
or creating/admitting another issue.

After a verified binding is fsynced, `reconcile` resumes its pending receipt
without the ephemeral carrier. Temporary incident reads, marker discovery or
processing deadlines retain a retryable obligation, including failures after
the event was saved but before issue admission. If same-task/body reentry hits
a temporary native route/run lookup outage, `lastAttemptError` records that
attempt without replacing the saved processing obligation or a permanent
conflict. A fresh proof cannot replace the original run/task/trigger binding.
Reconciliation reuses the saved
verified input and clears that obligation only after processing succeeds;
identity, digest, historical-body and configuration conflicts are never retried
as availability failures. Earlier absent/invalid input remains retained
and may be enriched by a later complete input in that same actual task. Before
binding is saved, rerun ingest only in that same current task; another task
cannot adopt its identity. A crash before first fsync can lose the sole received
body. The next history scan must retain the actual null-payload run obligation;
a duplicate webhook may reuse the old run and never wake another task. The
supported original-event recovery below therefore remains necessary. Never
call import, prompt completion or HTTP acceptance normal automatic delivery.
Changed trusted configuration on a saved receipt requires operator
reconciliation; it does not silently rebind authority.
Canonical incidents pin their original configuration before external effects.
Creation, metadata updates and admission/resume enforce that pin and linked
receipt conflicts even when the input was already counted (`pending=false`).
New input or historical recovery cannot overwrite an existing intent's
provenance under a changed configuration. Restoring a configuration alone does
not clear a recorded permanent conflict. Legacy incidents without a saved pin
remain recoverable, subject to any retained runtime receipt's original binding.

When the native payload is absent or ingress produced no observed run, the
operator may use the supported deterministic **original-event recovery**. Copy
only the exact durable event bytes from the sender outbox/history or its
pre-request qualification record to `original-events/EVENT_ID.json` beneath the
same configured `stateDirectory`. Keep that directory 0700 and the regular file
0600, owned by the existing CLI operator. Do not reconstruct events from a
summary, alter their IDs, delete the sender journal, or copy a capability file.
For a sender state entry, its original request body is the UTF-8 result of
`json.dumps(entry["event"], sort_keys=True, separators=(",", ":"))`, without a
newline. Back up the original protected source state before extracting it.

```sh
python3 tools/health-incident.py recover --operations "$HEXPROOF_OPERATIONS_FILE" \
  --config "$HEXPROOF_HEALTH_INCIDENT_FILE" \
  --event-file "$HEXPROOF_HEALTH_ORIGINAL_EVENT_FILE" \
  --trigger-id "$HEXPROOF_HEALTH_ORIGINAL_TRIGGER_ID" \
  --run-id "$HEXPROOF_HEALTH_ORIGINAL_RUN_ID"
```

The operator must bind the original event to the original response/run evidence;
the tool cannot infer that relationship from a null native payload. `--run-id`
requires a matching actual run from bounded CLI readback (or the journal's
previously observed native snapshot), fixed route/trigger/source and no
conflicting native event. Omit it when no run was observed; this admits canonical
maintenance through the issue fallback while retaining an explicit
`original_run_unobserved` obligation. A later invocation can bind that **same**
event to its proved original run. Unknown native status remains
`original_admission_unverified`; skipped/failed runs are never called admitted.
The journal stores exact imported bytes and their SHA-256, event/source/sequence,
original run/task/status and `payloadOrigin=operator_original`; metadata carries
bounded provenance/digests, never a claim that native retained the payload.
Conflicting event bytes, trigger mapping or run associations fail closed.
Existing old `invalid_payload` journal entries remain unresolved and may use
this same import path; do not reset the original qualification records.

The same lock, canonical marker, metadata readback and real `issue runs` task
association apply to normal ingestion and recovery. An original import may
enrich an absent/invalid runtime receipt bound to that actual run, retaining its
raw input and separate `recoveredBy=operator_original` provenance. It cannot
erase a conflicting valid event/digest. Canonical admission does not rewrite the
original native outcome. A recovery delivered before its failure remains an
unresolved retained observation, then reassociates by group/source/signal/episode
and sequence when the failure arrives, including after restart. It cannot clear
a newer episode or close maintenance.
This does not replay webhook admission. If no later ingress starts Mika, the
operator invokes this deterministic recovery helper; no extra AI scheduler is added.
The activation owner must qualify the normal automatic path on a clearly isolated native
route/project with approved non-production fixtures: accepted, skipped/failed,
lost response, same original event, one canonical issue and its actual task
association. At least one failure must reach a canonical maintenance task
without the owner copying its body, and the saved canonical digest must match
the sender's pre-request original. Also prove supported original-record recovery;
import cannot substitute for automatic-path evidence. Production fake incidents are forbidden. Mock tests prove helper
behavior but **do not qualify live native admission**. Lack of an isolated
qualification target or required CLI readback is an explicit activation gap.

Discovery reads newest-first native pages up to 500 runs/2000 issues and 120s.
Both normal `ingest` and explicit `reconcile` process the complete discovered
prefix, saving events or unresolved run obligations before durably recording
the newest run boundary. Normal automatic ingress maintains this boundary without
a manual scheduled reconciliation. Later scans stop after the page containing that
exact boundary; already covered history may grow beyond 500 without stopping new
incidents. Current-task binding has an independent stopping condition: when its
run predates that boundary page, ingest continues the bounded native scan until
the actual task association is found. Retained snapshots alone never prove a
current task. Extra pages do not rewind discovery or reprocess covered history;
the same ordering, page budget and known-history constraints still apply.
Unknown in-flight runs pin the previous boundary until re-read.
Missing/changed boundaries, non-monotone timestamps, duplicate pagination rows
or more than 500 newly undiscovered records fail closed before issue writes.
Legacy journals without a boundary, or a stale boundary from an older ingest
version, may scan up to the 1024 retained runs (rounded up to whole pages);
records beyond the normal 500 window must already be saved in that journal.
This bridge does not permit
a missed unknown history window. Null-payload obligations are stored independently
of discovery progress, so a coverage boundary never means incident admission.
A marker conflict stops reconciliation. Uncertain creation first reads all marker
pages; finding the issue completes reconciliation. Absence does not prove a
pending create failed, so it never automatically creates again. An operator
must reconcile the request/result before any repair of that intent. Metadata
writes read back before retrying the same idempotent value; lost admission is
read back through issue/task linkage. Journal corruption stops work, keeping
native/local evidence. Runs/events retain 1024 records, closed incidents 64,
incidents 128, episodes 32 per incident, journal 2 MiB. Runtime receipts have the
same 1024-record bound. Pending/unresolved inputs, active incident event/run
provenance, unmatched recovery and unresolved provenance records are pinned rather than
silently evicted; exceeding their bounds fails closed. A paused/failed ingress
must be reconciled before more than 500 unknown runs accumulate; a genuine coverage gap or capacity refusal requires
operator maintenance of the preserved evidence, not a cursor reset. This lock provides local serialization, not server uniqueness or
cross-host CAS. Maintenance completion requires actual repair evidence.

## Fresh release promotion

Use `tools/promote-release.py` from the full clean frozen public checkout,
replacing the bare draft-promotion command. It calls the existing
`release-verification.py check` engine, including the latest exact-source
qualification; it never reruns or reimplements the full release suite. The
private readiness schema is:

```json
{
  "schemaVersion": 1,
  "identitySha256": "sha256 of snapshot identity canonical JSON",
  "bootstrapSha256": "sha256 of actual raw packaging bootstrap input",
  "review": {
    "verdict": "APPROVE", "reviewerId": "approved independent agent UUID",
    "implementerId": "approved author UUID", "evidenceRef": "exact native review"
  },
  "updateReadiness": {"result": "pass", "evidenceRef": "exact supported-client/fleet qualification"},
  "packaging": {"runId": 123, "sha256": {"every-asset-name": "64 lowercase hex digits"}}
}
```

Keep this reviewer-owned receipt private (0600). Its evidence references must
represent actual final independent review, complete platform/source packaging,
compatibility and update readiness. The wrapper checks the allowlisted distinct
reviewer/author but cannot establish review authorship from a self-written JSON
file; native independent review is still mandatory. `snapshot` returns the
identity/digest used by that review. The packaging digest must be tied to the
actual private release bootstrap input; the wrapper cannot read GitHub's secret
back. Downloaded assets must exactly match the whole draft inventory, checksums,
canonical compatibility and constrained GitHub attestations from the successful
exact-source tag workflow. There is no real release publication in tool tests.

```sh
python3 tools/promote-release.py snapshot --repo "$HEXPROOF_RELEASE_CHECKOUT" \
  --operations "$HEXPROOF_OPERATIONS_FILE" --inventory "$HEXPROOF_TLS_INVENTORY" \
  --bootstrap "$HEXPROOF_RELEASE_BOOTSTRAP" --readiness "$HEXPROOF_RELEASE_READINESS" \
  --assets "$HEXPROOF_RELEASE_ASSETS" --tag "$HEXPROOF_RELEASE_TAG" --release-id "$HEXPROOF_RELEASE_ID"
# After independent assessment, use the same arguments with check, then promote.
```

`check` collects fresh complete TLS without mutation; `promote` collects again
inside its own publication boundary. Evidence binds full commit/tree/version,
tag/release ID, notes/assets, inventory and raw bootstrap digests. Five-minute
maximum age, no future/incomplete/failing evidence, and a new remaining-lifetime
calculation immediately before PATCH prevent reusable stale TLS approvals.
Mode, qualification, clean source, tag, readiness and draft identities are
rechecked. A fixed operator-state lock and per-release journal serialize local
attempts. After an uncertain PATCH, reconcile published state and latest without
another mutation. A still-draft uncertain result blocks for operator
reconciliation, including after restart. Never delete that journal to retry.
Already-published assets/notes/tags are immutable. No cross-operator GitHub CAS
is claimed; maintain the existing single release writer.

## Immutable activation handoff (monitoring only)

The developer exports one committed candidate; final independent review and
integration belong to Mika. This does not authorize executing an unreviewed
package or publishing an application release:

```sh
python3 tools/build-health-activation.py --output "$HEXPROOF_ACTIVATION_PACKAGE"
```

Record the returned commit/tree/archive SHA-256 privately. Extract into a new
0700 directory, compare the expected archive digest, then `sha256sum -c
SHA256SUMS`. `MANIFEST.json` lists exact source/file hashes. The archive has no
real inventory/capabilities. Use the full frozen checkout for the native helper
and release wrapper (their existing supporting modules are intentionally not
installed into the monitoring directory).

Before installation, the owner supplies secure local files:

| Destination under `/etc/hexproof-health` | Private input |
| --- | --- |
| `inventory.json` (observer) | All intended endpoint IDs/origins/groups and actual raw bootstrap hash |
| `bootstrap.json` (observer) | Actual raw intended release bootstrap bytes |
| `renewal.json` (each cloud) | Schema 1 and that host's trusted `serviceGroup` |
| `webhook-url` (each host) | Protected dedicated trigger capability for its fixed source |

The observer uses `observer-debian`; the cloud hook uses `renewal-cloud`.
Configure those exact sources in the native trigger mapping. Match service
groups to correlate renewal/TLS. Do not ship synthetic samples as live input.
Systemd 252/257/262 support the supplied directives. Verify on each actual host
before activation. Cloud installation is performed by the supervising owner
session using its existing SSH alias if Debian cannot resolve that alias; no
SSH discovery/key unlock/credential copying is needed.

From the verified extracted package, use a private root shell. Select **only
one** role and its files; do not replace the original renewal unit or loopback
monitor. The following backup records missing files and previous enable/active
states, and retains original file metadata:

```bash
set -euo pipefail
umask 077
role=observer # use cloud on the explicitly selected cloud host
backup=/var/lib/hexproof-health-install/$(date -u +%Y%m%dT%H%M%S%N)
mkdir -p "$backup/old"
paths=(/usr/local/lib/hexproof-health/tls_check.py /usr/local/lib/hexproof-health/health_alerts.py)
if [[ $role == observer ]]; then
  units=(hexproof-public-tls.service hexproof-public-tls.timer)
  paths+=(/etc/hexproof-health/inventory.json /etc/hexproof-health/bootstrap.json)
else
  units=(hexproof-health-send.service hexproof-health-send.timer)
  paths+=(/etc/hexproof-health/renewal.json /etc/systemd/system/hexproof-cert-renew.service.d/health.conf)
fi
paths+=(/etc/hexproof-health/webhook-url)
for unit in "${units[@]}"; do paths+=("/etc/systemd/system/$unit"); done
printf '%s\n' "${units[@]}" > "$backup/units"
printf '%s\n' "${paths[@]}" > "$backup/paths"
for path in "${paths[@]}"; do
  if [[ -e $path || -L $path ]]; then cp -a --parents -- "$path" "$backup/old/";
  else printf '%s\n' "$path" >> "$backup/absent"; fi
done
for unit in "${units[@]}"; do
  systemctl is-enabled "$unit" > "$backup/$unit.enabled" || true
  systemctl is-active "$unit" > "$backup/$unit.active" || true
done
systemctl show hexproof-cert-renew.timer -p UnitFileState -p ActiveState > "$backup/renewal-timer-before"
```

Install only the immutable files and protected private inputs. Here the four
`HEXPROOF_*_INPUT` variables resolve to owner-supplied secure local files:

```bash
sha256sum -c SHA256SUMS
install -d -m 0755 /usr/local/lib/hexproof-health
install -m 0644 deploy/monitoring/{tls_check,health_alerts}.py /usr/local/lib/hexproof-health/
install -d -m 0700 /etc/hexproof-health
install -m 0600 "$HEXPROOF_WEBHOOK_INPUT" /etc/hexproof-health/webhook-url
if [[ $role == observer ]]; then
  install -m 0600 "$HEXPROOF_INVENTORY_INPUT" /etc/hexproof-health/inventory.json
  install -m 0600 "$HEXPROOF_BOOTSTRAP_INPUT" /etc/hexproof-health/bootstrap.json
else
  install -m 0600 "$HEXPROOF_RENEWAL_INPUT" /etc/hexproof-health/renewal.json
  install -d -m 0755 /etc/systemd/system/hexproof-cert-renew.service.d
  install -m 0644 deploy/monitoring/hexproof-cert-renew-health.conf /etc/systemd/system/hexproof-cert-renew.service.d/health.conf
fi
for unit in "${units[@]}"; do install -m 0644 "deploy/monitoring/$unit" "/etc/systemd/system/$unit"; done
systemd-analyze verify "${units[@]/#//etc/systemd/system/}"
if [[ $role == cloud ]]; then systemd-analyze verify hexproof-cert-renew.service; fi
systemctl daemon-reload
if [[ $role == observer ]]; then
  systemctl enable --now hexproof-public-tls.timer
  systemctl start hexproof-public-tls.service
else
  systemctl enable --now hexproof-health-send.timer
  systemctl start hexproof-health-send.service
fi
```

No renewal/game service is started/restarted. Before accepting activation:
compare installed file hashes to `MANIFEST.json` (for example,
`cmp deploy/monitoring/tls_check.py /usr/local/lib/hexproof-health/tls_check.py`);
privately hash actual
inputs; read back `systemctl show/is-active/list-timers` for the selected units,
`systemctl cat hexproof-cert-renew.service` for the additive hook and unchanged
ExecStart, original monitor/renewal timer enable states, fresh external TLS and
`health_alerts.py status`. Observe the next real renewal invocation and retained
failure/recovery counters. Use `systemctl show "${units[@]}" -p UnitFileState -p ActiveState -p SubState
-p Result -p ExecMainStatus` and `systemctl list-timers --all`. A sender-only
success without events proves no
incident delivery. Record isolated native qualification event/run/issue/task
linkage separately and preserve any unresolved capability gap. Do not emit real
inventory/hashes or raw service logs into public PRs.

Rollback uses the exact private backup path returned above. Disable the new
native trigger through Mika's recorded native activation rollback first. In the
same root shell (or set `backup` to that exact recorded directory):

```bash
mapfile -t units < "$backup/units"
for unit in "${units[@]}"; do
  systemctl stop "$unit"
  systemctl disable "$unit" || true
  systemctl disable --runtime "$unit" || true
done
while IFS= read -r path; do
  if [[ -e "$backup/old$path" || -L "$backup/old$path" ]]; then
    cp -a --remove-destination -- "$backup/old$path" "$path"
  elif [[ -f "$backup/absent" ]] && grep -Fxq -- "$path" "$backup/absent"; then
    rm -f -- "$path"
  fi
done < "$backup/paths"
systemctl daemon-reload
for unit in "${units[@]}"; do
  case $(cat "$backup/$unit.enabled") in
    enabled) systemctl enable "$unit" ;;
    enabled-runtime) systemctl enable --runtime "$unit" ;;
    masked) systemctl mask "$unit" ;;
    masked-runtime) systemctl mask --runtime "$unit" ;;
    disabled|not-found|static|indirect|linked|linked-runtime|alias) : ;;
    *) echo "Inspect saved unit state before continuing"; exit 1 ;;
  esac
  if [[ $unit == *.timer && $(cat "$backup/$unit.active") == active ]]; then
    systemctl start "$unit"
  fi
done
systemctl show "${units[@]}" -p UnitFileState -p ActiveState -p SubState
```

Compare restored file hashes/modes and original enable/active states. Keep
`/var/lib/hexproof-health-*`, the operator incident journal, and the backup;
never delete unsent events or restart games/renewal to make rollback look green.
Unknown/masked prior state must be reconciled before installation, not silently
unmasked. No application unit is enabled, disabled, started or restarted here.

## Focused verification

```sh
python3 -m unittest discover -s deploy/monitoring -p 'test_*.py'
python3 -m unittest discover -s tools/tests -p test_health_incident.py
python3 -m unittest discover -s tools/tests -p test_promote_release.py
python3 -m unittest discover -s tools/tests -p test_release_verification.py
```

Fixtures use a private local CA, real isolated TLS servers and no production
traffic. External mutations are mocked. Cover short valid certificates, validity,
trust/name/IP failures, DNS deadline, endpoint coverage/dedup, repeated renewal,
competing processes, crashes/corruption, queue limits, stable retry identity,
uncertain creates/metadata/admission, late recovery and release refusal/revocation.
Local tooling tests and unit syntax checks are source evidence; final review,
actual private inputs, supported native admission qualification and installed
readbacks remain activation obligations owned by the parent task.
