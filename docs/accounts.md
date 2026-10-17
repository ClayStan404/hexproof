# Official-server accounts

Status: implemented. Owner-approved scope, 2026-09-27.

## Identity and authority

Official hubs share one account authority. One Go hub owns a private account
directory; other official hubs call its authenticated HTTPS account endpoint.
Self-hosted servers remain account-free in the standard client. The client
only sends official credentials to account-enabled endpoints in the trusted
server directory, with a matching configured account realm. Local test
directories use a separate realm and isolated profile.

An account has an immutable random public id and a display name. A generated
256-bit login code authenticates it without an email address or user-chosen
password. A separately generated recovery code replaces both codes and revokes
all previous device sessions. Codes are displayed for backup when generated;
the server stores only SHA-256 digests of random secrets. Login issues a
revocable device session, valid for 90 days, with at most 16 devices per account.
Rotating the login code preserves identity and revokes other device sessions.
Losing every credential, backup and valid device session makes recovery
impossible. Display names never prove ownership.

The account authority commits each account atomically to a private file and
holds an operating-system lock on its directory. Only the authority writes
these records. Internal HTTP calls require an operator service key, a matching
realm and HTTPS (loopback HTTP is permitted for local tests); redirects are
never followed. Account operations are bounded and failures do not fall back
to a guest identity. Guest entry remains available explicitly.

Admission and durable writes serialize per account; unrelated identities do not
share a hash-bucket lock or wait for another account's disk flush. Waiting and
authority RPCs inherit the caller's cancellation, with a five-second RPC limit.
An atomic file commit already in progress finishes before publishing its memory
state. Closing the store waits for these operations before releasing the
directory lock. Frequent internal credential checks return only profile/session
identity; explicit status requests still return the device inventory. Every
authenticated command still checks the authority; valid credentials are not
cached to bypass immediate revocation.

## First-version behavior

- Create, login, recovery, code rotation, display name update, logout, device
  listing and session revocation are available in the native client. Session
  credentials use the platform credential vault; unavailable vaults leave
  credentials in memory and visibly disable cross-launch automatic login.
- An account has one controlling game connection per hub. Handover serializes
  with old commands, detaches the old connection and resumes through the
  existing room projection path. The old connection receives `account_replaced`
  before transport closure and stops automatic reconnection. Every authenticated
  command validates the device
  session with the authority; idle cross-node revocations close connections
  within the periodic two-second validation interval plus request latency.
- Room seats, organizer and participant roles, Limited/Cube draft seats,
  current packs, picked pools and submitted decks retain their original
  scope, privacy, lifecycle and deadlines. Ownership permits recovery while
  the resource exists; it does not undo a concession, elimination, withdrawal,
  host transfer or expiration. Account login does not restore spectator views
  automatically. Organizer and participant permissions remain separate.
- Original Forge replay participants can list and download their private
  recordings from the original hub while archives remain available. The whole
  match must finish first. Account ownership is persisted with the archive;
  unrelated players and spectators receive no access. Exported files still
  cannot be revoked.
- Existing local tournament, Cube and replay credentials may be claimed only
  after verification. A bound credential cannot be used by another account or
  anonymously. One account cannot claim two participant seats in an event.
  Current guest authority may be adopted when creating/logging into an account;
  conflicting seats reject the transition.
  Recovery requires leaving a current guest room/event first, so a seat
  conflict cannot consume the only recovery code before new codes are shown.

Account storage survives authority restarts. Live games and events keep their
existing in-memory lifetime; cross-process game recovery is a separate feature.
No deck library, unsubmitted construction draft, preferences, API keys, or
device-local files are uploaded by this version. Those are separate optional
sync features. Persistent lifetime statistics and social features are also
outside this account slice.

## Protocol and client storage

The optional `session.hello.accountSession` carries a device credential.
`session.welcome.accountRealm`, `accountId` and `accountName` describe the
authenticated identity. A cached credential that arrives after the hello can
attach through `account.command` without restarting a guest connection.
`account.command` supports `create`, `login`, `recover`, `attach`, `status`,
`rename`, `rotate`, `revoke`, `revoke_others`, `logout`, `resume`, `claim` and
`replays`. The private, request-correlated `account.state` contains devices,
current-node resource references (or global references when the
[official cluster](official-cluster.md) is enabled) and node-local paginated replay grants. Generated secrets
are returned only to that requesting connection. The schemas and fixtures in
`protocol/v1/` and `testdata/protocol/v1/` define the payloads.

`tournament.enter.useAccount` explicitly restores an existing event role.
Ordinary player entry into a Cube room also recognizes the current account;
explicit spectator entry remains public-only. Account ownership is checked
both at mutation and private-projection boundaries, including after claiming
an older guest credential. It is not included in public room/event snapshots.

The Windows Credential Manager, macOS Keychain and Linux Secret Service store
only the revocable device token. The vault key includes both the isolated local
profile path and the account realm. Login/recovery codes remain transient and
masked until explicitly shown/copied, and are cleared after backup. Linux vault
requests run off the UI thread with a five-second cancellation deadline.
Command-correlation signals redact account credentials, including failed sends.
An endpoint-only development override removes the inherited account realm;
local account fixtures need an explicit test directory and separate realm.

## Operator configuration

Accounts are disabled unless a local authority or a remote authority is
configured. Deploying this implementation does not create an independent
account store on every node. Configure exactly one authority, then connect
every other official node to it with the same realm and service key.

| Flag | Environment default | Purpose |
|------|---------------------|---------|
| `-account-dir` | `HEXPROOF_ACCOUNT_DIR` | Private authority directory; never share it between running processes |
| `-account-authority` | `HEXPROOF_ACCOUNT_AUTHORITY` | Satellite HTTPS URL ending at the authority's `/internal/accounts` route |
| `-account-realm` | `HEXPROOF_ACCOUNT_REALM` | Defaults to `hexproof-official`; identical on all official nodes |
| `-account-service-key-file` | `HEXPROOF_ACCOUNT_SERVICE_KEY_FILE` | Readable private file containing the same random service key on trusted hubs |

The key must have at least 32 bytes of random secret material. Keep it in a
0600 file owned by the service user; pass its path, never its contents, on the
command line. The authority's account directory is 0700 with 0600 records and
an exclusive process lock. Use a persistent path already writable by the
resolved service, and include it in protected backups. Backup rollback can
restore formerly revoked credentials; account authority snapshots are security
state, not disposable room caches.

For example, the authority uses `HEXPROOF_ACCOUNT_DIR=/var/lib/hexproof/accounts`
and the key-file setting. Satellites omit the directory and set
`HEXPROOF_ACCOUNT_AUTHORITY=https://<authority-origin>/internal/accounts` and
their key-file path. The HTTPS reverse proxy must forward only this exact
route to the authority and retain the Authorization and realm headers; do not
log request/response bodies or authorization headers. An authority outage
rejects account actions and closes authenticated transports; it never converts
them into guest authority. Live node progress keeps its existing expiry rules.

Add `"accountRealm": "hexproof-official"` to each account-enabled official
entry in the trusted server directory and advance its revision. Publish that
directory through the existing directory publisher, and update the private
release directory input; the tracked example documents the field. Public
official endpoints require WSS, while isolated test realms may use loopback WS.
No credential is forwarded merely because an arbitrary server advertises an
account realm in its welcome. Existing releases cannot parse this new directory
field, so coordinate the directory revision with the matching client release.

Production binary installation and upgrades still use only
`deploy/deploy-release-server.sh` with the owner's explicit targets/version.
Enabling the authority, distributing operator secrets, adding service settings
and proxying its route are separate authorized deployment inputs. No live
server configuration is changed by the implementation task.
