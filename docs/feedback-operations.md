# Feedback receiver operations

This runbook covers the public V2 receiver and retained private V1 deliveries.
The owner has adopted public-only feedback with autonomous AI processing and
releases. The [V2 contract](public-feedback-v2.md) defines public consent,
publication, threads, closure and content removal. The release installer below
supports private V1 and public V2 staging; its local qualification does not
activate production or complete cutover. Retain V1 receipt access for previously
accepted records without accepting new private submissions.

The optional `hexproof-feedback` binary is independent of game servers,
accounts and Forge. The release archive includes it but does not start it.
Production activation is a separately authorized operator action. Do not
enable a public client endpoint before its HTTPS route, GitHub destination,
privacy notice and independent monitoring have been checked. SMTP is needed
only while unfinished legacy deliveries require it.

## Selected deployment host

Resolve the selected host from `feedback.receiverTarget` in the operator's
trusted native operations configuration. Use its SSH alias
as the explicit `HEXPROOF_TARGETS` and private deployment input's `target`.
The field is operator guidance, not an installer input or deployment trigger.
Confirm installed state from the operator's current deployment records and
service readback.

Run the receiver as the separate `hexproof-feedback.service`. The AI development
workstation migrates independently. Host selection or enabled client defaults
do not open an HTTPS route, establish GitHub write permission or activate native
operations. Verify connectivity and complete the coordinated cutover below for
an authorized installation or upgrade.

## Configuration

Keep configuration and relay credentials out of source control, client
packages and issue bodies. An illustrative receiver configuration is:

```json
{
  "schemaVersion": 1,
  "listen": "127.0.0.1:57324",
  "publicUrl": "https://support.example.invalid/feedback/v1",
  "dataDir": "/var/lib/hexproof-feedback",
  "adminSocket": "/var/lib/hexproof-feedback/admin.sock",
  "operatorName": "Support operator",
  "monitoringConfigured": true,
  "trustedProxyCidrs": [],
  "smtp": {
    "host": "smtp.example.invalid",
    "port": 587,
    "tlsMode": "starttls",
    "username": "support@example.invalid",
    "passwordFile": "/etc/hexproof-feedback/smtp-password",
    "from": "support@example.invalid",
    "to": "feedback@example.invalid"
  }
}
```

The names above are non-deliverable placeholders. The command
`hexproof-feedback -config /private/receiver.json -validate-config` checks
configuration without starting a listener or sending email. Use a literal
loopback listener and a TLS reverse proxy. Explicitly configure trusted proxy
CIDRs before using forwarded client addresses; untrusted forwarding headers
must not bypass limits. Do not proxy `/healthz`, `/readyz` or the Unix admin
socket to the public Internet.

The legacy client used the separate build input `HEXPROOF_FEEDBACK_CONFIG_FILE`
with `schemaVersion: 1`, `enabled`, `apiBase` including `/feedback/v1`,
`supportLabel`, `privacyUrl`, and `receiptOnlyApiBases`. Current clients require
[V2 public configuration](public-feedback-v2.md#build-and-receiver-configuration)
for new submissions. Official 3.1.0 source defaults enable the qualified Server 2
destination; the generic example remains disabled. Source configuration does
not start the receiver. The owner's initial 2026-10-22 code-only scope was
superseded by the formal release authorization on 2026-10-24.
Do not edit the strict existing server directory or distribute SMTP secrets.
Production clients reject redirects and insecure endpoints. After endpoint
migration, retain an old endpoint only for receipt queries if it is still
trusted; users must explicitly authorize new submissions to the new endpoint.

### Formal 3.1.0 public configuration

The reviewed public build configuration is
[`feedback.official.json`](../apps/client-qt/config/feedback.official.json), with
API `https://47.97.30.103/feedback/v2`, notice
`https://47.97.30.103/feedback/privacy` and public repository
`ClayStan404/hexproof`. The matching [notice page](https://47.97.30.103/feedback/privacy)
is rendered from `deploy/feedback/privacy.html` and contains the same disclosure
text; install that template at
`/var/www/hexproof-feedback/privacy.html`. It is a static public resource and
contains no receiver credentials. Before a release build, check the public
repository's `HEXPROOF_FEEDBACK_CONFIG_JSON` Actions variable: a nonempty value
overrides the source defaults and must either match them or be removed.

The pending 3.1.0 notice UI revision uses `hexproof-public-20261024-v2`.
It moves the full notice behind an in-app reading action and removes IP addresses,
model/effort names and internal coordination details from user-facing prose.
The currently deployed `hexproof-public-20261024-v1` notice remains unchanged
until the coordinated update. Keep provider policy
`hexproof-test-openai-multica-20261023-v1` unchanged in the client, receiver
`public` object and receiver `multica` object. Despite its historical name,
this identifier still means the same qualified Multica/OpenAI processing
permission: Mika coordinates with `gpt-6-astra`, Sol develops with `gpt-6.1-sol`
and Astra independently reviews with `gpt-6-astra`, all at `ultra`. It does not enable Claude, GLM,
DeepSeek, agy or Cursor/Grok. The revised formal notice simplifies user-facing wording
without broadening the processors that can receive historical contributions.

Change only `public.noticeRevision` and `public.noticeText` for this notice
transition. Preserve repository and actor identities, token references, both
stores, sockets, native workspace/Autopilot IDs and the webhook credential.
The native binding includes the webhook destination, so a routine launch must
not rotate it. A different provider-policy identifier would prevent old cases
from being exported even if its display name looked equivalent.

Before switching the notice, inspect the outbox and finish any pending,
uncertain or stalled issue/reply publication under the old notice. The publisher
rejects an unpublished contribution whose notice no longer matches. Already
published contributions keep their immutable original notice and processing
permission; changing the current notice does not rewrite or revoke that
consent. Their receipt access, AI status projections, closure and removal remain
available. New replies require the new client disclosure.

The trial route in `/etc/nginx/snippets/hexproof-feedback-test.inc` restricts
`/feedback/v2/` to selected source addresses. Formal activation removes that
location's IP `allow`/`deny` rules while retaining the 5 MiB cap, literal
loopback upstream, trusted forwarded-address handling, bounded timeouts,
disabled request-body/access logging and the separate public attachment/notice
routes. Do not expose `/healthz`, `/readyz` or either Unix socket. Validate the
proxy configuration before reload and verify HTTPS from outside the former
allowlist. Keep intake restricted until the notice, receiver, monitoring and
native workflow match the released client.

The trial's 32-record/64-identity/64 MiB capacity is not the production budget.
Use the receiver's existing defaults for the initial public launch: 1,000
records, 10,000 identities, 2 GiB payload storage, 512 MiB minimum free space,
5 submissions and 20 MiB per source per hour, and 100 submissions and 256 MiB
globally per hour. Verify available disk and independent monitoring before
activation; `monitoringConfigured: true` is an operator assertion, not a monitor.
Capacity exhaustion rejects new intake and must not evict outstanding removal
obligations. Fresh V2 deployment needs no SMTP configuration.

## Release deployment

Use the existing release entry point with one explicitly selected SSH alias
and version. This component downloads and verifies prebuilt release bytes,
including the release checksum attestation; it does not build or deploy source.
It operates on the feedback unit only. Existing game/home units and inbox
content are not part of binary rollback.

Provide a private input file on the workstation. Existing strict schema-v1
inputs remain supported for legacy SMTP deployment:

```json
{
  "schemaVersion": 1,
  "target": "owner-selected-ssh-alias",
  "arch": "amd64",
  "configFile": "/private/receiver.json",
  "smtpPasswordFile": "/private/smtp-password"
}
```

For public V2, use deployment-input schema 2. It requires `target`, `arch` and
`configFile`; the three credential-file fields are optional unless referenced
by the receiver configuration. For example, public intake without external AI:

```json
{
  "schemaVersion": 2,
  "target": "owner-selected-ssh-alias",
  "arch": "amd64",
  "configFile": "/private/receiver.public.json",
  "githubTokenFile": "/private/github-token"
}
```

The [public receiver example](../deploy/feedback/receiver.public.example.json),
[Multica receiver example](../deploy/feedback/receiver.multica.example.json)
and matching [public](../deploy/feedback/inputs.public.example.json) /
[Multica](../deploy/feedback/inputs.multica.example.json) input examples are
**disabled preparation templates, not launch-ready configuration**. They use
`.invalid` endpoints, missing numeric identities, disabled monitoring and
placeholder disclosures. Replace those with verified owner-supplied values;
do not reuse an old V1 endpoint as evidence of a current V2 route. `none-v1`
authorizes no external AI. A Multica configuration needs the actual approved
provider policy and matching disclosure in the receiver and client. Compare
those public fields without reading credentials or enabling either side:

```sh
python3 tools/write-feedback-config.py build/feedback.prepared.json \
  --defaults /private/feedback.client.json \
  --receiver-config /private/receiver.public.json
```

This checks the exact endpoint, repository, notice and provider-policy revision;
the release binary's validator still checks the complete receiver configuration.

| Private workstation input | Required receiver reference / fixed remote file |
| --- | --- |
| `smtpPasswordFile` | `smtp.passwordFile`: `/etc/hexproof-feedback/smtp-password` |
| `githubTokenFile` | `public.tokenFile`: `/etc/hexproof-feedback/github-token` |
| `multicaWebhookFile` | `multica.webhookFile`: `/etc/hexproof-feedback/multica-webhook` |

An authenticated SMTP relay requires its private credential input. A V2 receiver
may omit SMTP after legacy delivery has drained; retain SMTP configuration and
its input while pending, uncertain or attention-required legacy deliveries
remain. The receiver's startup check enforces this and an unsuccessful cutover
rolls back the managed installation. Existing legacy records are not converted
into public cases. Supplied credentials must be nonempty, owner-only regular
files of at most 4096 bytes, without a final symlink. The installer rejects a
missing configured credential, an unreferenced supplied credential or an
arbitrary remote credential path. It snapshots the validated bytes rather than
rereading a mutable source file during packaging.

Legacy startup is isolated from public V2. With no V1 records or tombstones,
a public receiver retains only the legacy directory lease, preventing a second
V1 process from writing there. It starts no V1 routes, admin socket, mail or
retention workers. Existing history retains its private receipt/retention path;
unfinished mail still refuses SMTP-free startup. Configuration keys, schemas
and established paths are unchanged.

The target must match the explicit alias; the installer checks Linux and
architecture. Legacy state remains `/var/lib/hexproof-feedback`; public state is
the separate `/var/lib/hexproof-feedback-public`. Both use mode `0700` and the
dedicated service identity. For V2 the verified release unit is rendered with
that additional fixed `StateDirectory` and `ReadWritePaths`, preserving its
sandbox. Multica's restricted socket must be exactly
`/var/lib/hexproof-feedback/native.sock`, outside the public store. The release
binary's Go validator checks the full configuration and credential contents
against staged private files before any installed file changes; the installed
configuration is then validated again at its final paths. Credential files use
mode `0600` and service ownership. Failure restores prior managed files,
credential modes/ownership and service activity, removing newly introduced
credential files while preserving both inboxes. Installation readback records
schema/public/Multica configuration booleans without credential values.

Installing the receiver-side Multica configuration does not create or activate
a native Autopilot, webhook, schedule or remote socket connection. At activation,
configure and verify the restricted native connection to the receiver's real
socket under the approved access policy. Keep webhook credentials in the private
input file mechanism; do not copy owner API credentials into task text or source.
The internal Python installer is not an alternative deployment entry point.

First verify the target and prebuilt artifact without remote modifications:

```sh
HEXPROOF_COMPONENT=feedback HEXPROOF_TARGETS=owner-selected-ssh-alias \
  HEXPROOF_VERSION=2.5.0 HEXPROOF_FEEDBACK_INPUTS=/private/feedback-inputs.json \
  HEXPROOF_VERIFY_ONLY=1 ./deploy/deploy-release-server.sh
```

Only with explicit deployment authorization, repeat without verify-only:

```sh
HEXPROOF_COMPONENT=feedback HEXPROOF_TARGETS=owner-selected-ssh-alias \
  HEXPROOF_VERSION=2.5.0 HEXPROOF_FEEDBACK_INPUTS=/private/feedback-inputs.json \
  ./deploy/deploy-release-server.sh
```

Use the actual release containing the feature; the illustrative version does
not imply that any current release or production host includes it. Deployment
does not edit the TLS proxy or publish the client endpoint. Prepare a reviewed
route separately, with a 5 MiB request cap, coherent upload/response timeouts,
no redirects and redacted Authorization/body logging. The actual attachment
host, public destination, processing/removal policy, applicable mailbox/backup
retention and support contact must appear in the notice before enabling
submission. Deployment backups can contain old credentials; retain them only
under the operator's private backup/expiry policy.

### Initial test installation from a qualified Actions build

An owner-authorized end-to-end trial may use the existing deployment entry
point before creating a release tag. This exception applies only to the
feedback component and an **initial installation**: the target must have no
feedback service, binary, configuration, state directories or installer backups.
Orphan service drop-ins under `/etc`, `/run`, `/usr/lib` and `/lib` also block
the initial installation, even when systemd reports the unit as not found.
It never upgrades an existing receiver or replaces game services. A retained
failed installation requires separately scoped cleanup; the installer does not
erase feedback stores to make another test installation possible.

Provide all three exact build identities, with the same private receiver inputs
described above:

```sh
HEXPROOF_COMPONENT=feedback HEXPROOF_TARGETS=aws HEXPROOF_VERSION=3.1.0 \
  HEXPROOF_FEEDBACK_INPUTS=/private/feedback-inputs.json \
  HEXPROOF_FEEDBACK_TEST_RUN_ID=39937074828 \
  HEXPROOF_FEEDBACK_TEST_ARTIFACT_ID=12496905925 \
  HEXPROOF_FEEDBACK_TEST_HEAD_SHA=b1baa269395a9c78d673625f1aacb06b5cf6ec87 \
  HEXPROOF_VERIFY_ONLY=1 ./deploy/deploy-release-server.sh
```

These example IDs identify the qualified 3.1.0 artifact-only build; expired or
changed artifacts are rejected. After verification, repeat without
`HEXPROOF_VERIFY_ONLY=1` to install under the owner's authorization. An optional
`HEXPROOF_FEEDBACK_TEST_ARCHIVE=/absolute/path/artifact.zip` reuses the original
downloaded ZIP, not an extracted directory. GitHub metadata is still read and
its ZIP size/digest must match. This mode cannot be combined with
`HEXPROOF_ALLOW_DRAFT=1` and is rejected for game deployments.

The installer requires a successful `workflow_dispatch` run from the selected
repository's `master`, the exact reviewed source SHA, the registered
`.github/workflows/release.yml`, and byte-identical workflow content to the
trusted local checkout. Successful combined assembly and skipped tag-only
attestation/publication steps establish an artifact-only build. It verifies
artifact ownership, expiry and ZIP digest, all eight bundle entries and seven
checksums, compatibility metadata, package root, executable architecture, and
the receiver's version before changing installed files. GitHub build metadata
is read again after download. Configuration validation and rollback reuse the
normal receiver installer.

Local evidence and `/etc/hexproof-feedback/test-provenance.json` identify this
as an **unattested test build**, including run/artifact/source and package
identities. The default release path still requires the release checksum
attestation; this test mode does not create a tag, publish a release, enable
Multica schedules, or configure HTTPS. Public V2 endpoints retain the exact
`/feedback/v2` path, even for a test receiver; use a separate host/HTTPS port
if that route is already occupied.

## Monitoring and incident handling

Monitor local readiness and aggregate queue state independently of the support
SMTP path. Name an operator before setting `monitoringConfigured`. Initial
targets: alert on uncertain/permanent delivery failures, an oldest pending
age exceeding one hour, or storage above 80%; review within one working day.
These targets are operational obligations, not a player-facing response SLA.

The legacy admin socket exists only in V1 mode or when V1 records/tombstones
remain. Fresh public V2 deployments use loopback HTTP readiness plus configured
public-outbox and native-task monitoring; absence of `admin.sock` is expected
there. For retained V1 data, use the protected local admin CLI to list
pending work, inspect a receipt, confirm relay handoff, deliberately retry, or
discard manually confirmed spam. The socket and all data use owner-only permissions.
Detailed feedback is private support content; aggregate status can be recorded
without descriptions, contact, attachments or bearer capabilities. Do not paste
an inspect result into a public issue without reviewing and minimizing it.

Run the CLI as the dedicated service identity (or the authorized operator) on
the receiver host. For example:

```sh
sudo -u hexproof-feedback /usr/local/bin/hexproof-feedback \
  -admin-socket /var/lib/hexproof-feedback/admin.sock -action stats
sudo -u hexproof-feedback /usr/local/bin/hexproof-feedback \
  -admin-socket /var/lib/hexproof-feedback/admin.sock -action list
```

For `inspect`, `confirm`, `retry` and `discard`, also supply `-receipt` with the
exact receipt UUID. `retry` is an explicit resend decision and warns about
possible duplicate mail. Confirm handoff only after checking the relay/mailbox;
discard only manually confirmed spam or abuse. These actions change the live
queue through its single owner rather than editing files externally. Aggregate
stats expose storage availability/headroom, capacity, queue counts and oldest
undelivered age; they do not include feedback text or access credentials.

- An accepted feedback receipt means the durable inbox contains the submission.
  SMTP `handed_off` means the configured relay accepted it, not that a maintainer
  read it. Monitor the envelope sender mailbox for asynchronous bounces.
- Known temporary non-acceptance retries automatically. An ambiguous final
  SMTP response or restart during transmission requires checking the relay or
  dedicated mailbox by the stable receipt/Message-ID before deliberate resend.
  A resend may duplicate an already handed-off message.
- Disk/quota exhaustion rejects new work without deleting ordinary unexpired
  acknowledged submissions. Stop public intake or tighten admission while
  investigating; audited spam discard frees content capacity but preserves a
  receipt/digest tombstone. Do not use spam discard as routine capacity eviction.
- Content normally expires at 90 days; identity/authentication/digest tombstones
  expire at day 120. Retries do not extend retention. An undelivered submission
  approaching expiry is a failure requiring operator attention.
- Client drafts and unreceived feedback remain until the user deletes them.
  Their seven-day automatic retry budget is not a content deletion period.
  Client local deletion does not erase the inbox, delivered email or backups.

Exercise recovery with a copied isolated data directory and test relay. Do not
restart a real receiver, edit its live data or send a real support email merely
to validate a local implementation. See [feedback behavior](feedback-design.md)
and the [deployment procedure](../deploy/home/README.md).
