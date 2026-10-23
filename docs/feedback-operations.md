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

On 2026-10-23 the owner selected **Server 2**, SSH alias **`aws`**, currently
`47.97.30.103`, for the feedback receiver. Use this alias as the explicit
`HEXPROOF_TARGETS` value and the private deployment input's `target`. The
[native operations manifest](../deploy/multica/operations.json) records it as
`feedback.receiverTarget`; that field is operator guidance, not an installer
input or automatic deployment trigger.

Run the receiver as its separate `hexproof-feedback.service`. The AI development
machine remains the workstation running Multica and can be migrated separately.
Selecting this host does not enable feedback, establish a public API/privacy
route or authorize deployment before the planned release. Keep official client
intake and native operations disabled until that activation.

The short read-only probe on 2026-10-23 passed seven GitHub API and seven webpage
requests over three minutes with application proxies disabled. This supports
the host selection but does not establish all-day network stability, GitHub
write permissions or Multica webhook delivery. Evidence is retained locally in
`build/github-connectivity/server2-probe.jsonl` and `comparison.json` in the same
directory. No server configuration was changed by that probe or host selection.

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
for new submissions; official source defaults and the example are disabled.
Source configuration does not start the receiver. The owner's 2026-10-22 scope
is code/build configuration only, with production activation deferred to the
next separately authorized release.
Do not edit the strict existing server directory or distribute SMTP secrets.
Production clients reject redirects and insecure endpoints. After endpoint
migration, retain an old endpoint only for receipt queries if it is still
trusted; users must explicitly authorize new submissions to the new endpoint.

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

The receiver isolates this compatibility work in its legacy startup/retention
component. Fresh public deployments need no SMTP; a store with unfinished
private mail still refuses SMTP-free startup without discarding that mail.
The refactor changes neither the configuration keys nor the established paths.

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

## Monitoring and incident handling

Monitor local readiness and aggregate queue state independently of the support
SMTP path. Name an operator before setting `monitoringConfigured`. Initial
targets: alert on uncertain/permanent delivery failures, an oldest pending
age exceeding one hour, or storage above 80%; review within one working day.
These targets are operational obligations, not a player-facing response SLA.

Use the receiver's local admin CLI through its protected socket to list pending
work, inspect a receipt, confirm relay handoff, deliberately retry, or discard
manually confirmed spam. The socket and all data use owner-only permissions.
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
