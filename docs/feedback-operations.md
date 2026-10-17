# Feedback receiver operations

The optional `hexproof-feedback` binary is independent of game servers,
accounts and Forge. The release archive includes it but does not start it.
Production activation is a separately authorized operator action. Do not
enable a public client endpoint before its HTTPS route, mailbox, privacy notice
and independent monitoring have been reviewed.

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

The client uses a separate build input, `HEXPROOF_FEEDBACK_CONFIG_FILE`, with
`schemaVersion: 1`, `enabled`, `apiBase` including `/feedback/v1`,
`supportLabel`, `privacyUrl`, and `receiptOnlyApiBases`. Its default is disabled.
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

Provide a private input file on the workstation:

```json
{
  "schemaVersion": 1,
  "target": "owner-selected-ssh-alias",
  "arch": "amd64",
  "configFile": "/private/receiver.json",
  "smtpPasswordFile": "/private/smtp-password"
}
```

`smtpPasswordFile` is empty only for a relay configuration without authentication.
An authenticated relay requires an owner-only credential file. The input target
must match the explicit alias; the installer checks Linux and architecture.
The service uses dedicated `hexproof-feedback` identity/state, fixed protected
configuration locations and the release's service template. A validation or
activation failure restores prior managed files and prior service activity,
while retaining acknowledged feedback. The internal Python installer is not
an alternative deployment entry point.

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
no redirects and redacted Authorization/body logging. Mailbox/backup retention
and support contact must appear in the user privacy notice before enabling
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
