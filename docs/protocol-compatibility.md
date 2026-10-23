# Application releases and communication compatibility

- Owner decision: 2026-10-21.
- Status: **Implemented in source; release and deployment pending.**
- Scope: one exact game-protocol identifier per client/hub build, independent
  application release versions. No feature negotiation or protocol ranges.
- Supersedes the 2026-07-30 exact application-version decision for the future
  implementation. Released 3.0.0 binaries still enforce that older decision.

## 1. Compatibility rule

The compatibility condition for an ordinary game connection is:

```text
client.gameProtocol == hub.gameProtocol
```

Different application versions must not cause rejection when that condition
holds. Equal application versions must not bypass a protocol mismatch. Normal
authentication, authorization, admission limits and message validation still
apply; protocol equality does not grant access to a room or enable an optional
service that the operator has disabled.

Keep three separate identities:

| Identity | Purpose | Rule |
| --- | --- | --- |
| Application version, such as `3.1.1` | Releases, update notices and diagnostics | Report the actual version; never use equality, a minimum, an allowlist or a range as the game compatibility gate. |
| Game protocol, such as `hexproof.v2` | Messages, actions, state, privacy and recovery semantics | Require exact equality at both ends. |
| Engine protocol and full Forge runtime identity | Helper execution and engine handover | Retain the existing independent exact checks and artifact verification. |

Every implementation bearing the same game-protocol identifier promises
bidirectional interoperability with the released baseline and subsequent
releases carrying that identifier. Application version numbers do not prove
or replace that promise. Update availability is advisory while the protocol
matches; there is no hidden application-version gate.

## 2. Protocol identifiers and the first baseline

Reuse the existing `session.hello.protocol` and `session.welcome.v` fields.
The canonical identifier is `hexproof.v<N>`, where `N` is a positive decimal
integer without leading zeroes, bounded to a signed 32-bit integer. Equality
is exact; numeric order is only for explaining which side needs an upgrade.
There is no separate `1.0` string, minor version, accepted range or list of
negotiable protocols. Each binary implements exactly one game protocol.

The first implementation of this policy uses **`hexproof.v2`**. The published
`hexproof.v1` contract includes application-version equality on both sides;
even a server-only relaxation cannot make the existing 3.0.0 client accept a
different server version. The new required protocol handshake and independent
release compatibility promise form an explicit new baseline. Do not relabel
old binaries, impersonate their application versions or silently fall back to
v1. Future incompatible changes advance the integer to v3, v4 and so on.

Protocol identifiers belong to the reviewed schema and generated Go/Qt
constants, not a deployment override. When implementing v2, migrate the
authoritative schemas, generator/checker paths and fixtures together. Retain
frozen v1 evidence for legacy rejection tests; do not maintain two active
implementations implicitly. The active schema and fixtures now live under `protocol/v2/` and
`testdata/protocol/v2/`; frozen v1 handshake evidence remains under
`testdata/protocol/legacy-v1/`. Production artifacts are unchanged.

## 3. Handshake, reconnection and errors

1. The client sends a required, well-formed `protocol` in `session.hello`.
   `clientVersion` remains required, bounded, nonempty diagnostic metadata.
2. The hub validates the offered protocol before account-session binding,
   seat restoration, cluster-ticket consumption or room/game actions. Missing,
   empty or malformed protocol data is an `invalid_message`; it never defaults
   to the hub's protocol. A well-formed unequal identifier is a
   `protocol_mismatch`.
3. A matching hello follows the existing authentication/admission flow. The
   welcome echoes the request ID, reports the hub's actual `serverVersion`
   and carries the authoritative `v`. Neither end compares application
   versions for admission.
4. The client requires welcome `v` to equal the protocol it offered before
   accepting credentials/membership or sending ordinary commands. Missing or
   invalid welcome protocol data also fails closed. A mismatch stops automatic
   retry and preserves a clear connection error, on either rejection path.
5. The protocol stays fixed for that connection. Every reconnect or cluster
   transfer performs the same handshake. Existing sequence, correlation,
   credential and fresh role-specific snapshot rules remain unchanged; there
   is still no version field on every game message.

An illustrative successful pair is a 3.1.1 client and a 3.1.0 server both
speaking `hexproof.v2`. These application numbers are examples, not a release
authorization or a minimum-version policy.

Use this stable mismatch envelope, with real observed values and the hello ID:

```json
{
  "type": "error",
  "id": "hello-request-id",
  "payload": {
    "code": "protocol_mismatch",
    "message": "Client and server communication protocols differ.",
    "clientProtocol": "hexproof.v2",
    "serverProtocol": "hexproof.v3"
  }
}
```

Optional application-version details remain diagnostic. Do not reuse
`requiredVersion` to mean either a protocol or an exact application build.
The client's local welcome rejection exposes the same client/server protocol
pair, without sending a fabricated server response. Error text must also be
understandable when a legacy client only displays the message.

The connection UI shows both protocol identifiers. If the client generation
is lower, ask the user to install a client supporting the server's protocol.
If the server generation is lower, explain that the server needs upgrading
or another compatible server can be selected. Never automatically downgrade
the client. For a recognized legacy compatibility rejection without trustworthy protocol
detail, show a generic incompatibility message instead of guessing from its application
version or parsing free-form English text. Other handshake validation errors
retain their normal messages; not every `invalid_message` is a compatibility
rejection.

The existing exact-server-version download action must change with this UI.
Select clients using verified release protocol metadata, not the server's
application version. Add a small `compatibility.json` release asset containing
`schemaVersion: 1`, the real `applicationVersion` and `gameProtocol`, covered by
the normal checksums and release attestation. If no verified matching metadata
is available, offer the fixed official release page. The current implementation
checks the latest stable candidate through the release API/checksum fallback;
it does not crawl release history or automatically downgrade. A peer never supplies a
download URL or authorizes executing an update.

## 4. When to keep or advance the protocol

| Change | Protocol decision |
| --- | --- |
| Layout, translations, sponsor lists, local settings or independent feedback configuration | Keep it, provided no game communication contract changes. |
| Performance or bug fix preserving documented messages, decisions and state semantics | Keep it after mixed-release verification. |
| Server-side rules fix represented entirely through existing states and decisions | Keep it if older clients can correctly play and recover; assess the engine identity separately. |
| Non-behavioral optional metadata at an already defined extension point | Keep it only if absence has a defined default and both old/new directions safely ignore or omit it. |
| New gameplay command/event, enum value, required decision, field or changed default that requires new peer knowledge | Advance it. |
| Changed action meaning, sequencing, reconnect/idempotency behavior, authorization or hidden-information projection contract | Advance it if the previous contract cannot be preserved. |
| Internal Forge/helper or cluster RPC changes | Review that component's contract separately; advance the game protocol only if its contract also changes. |

Unknown JSON fields being ignored by a decoder is not evidence of gameplay
compatibility. Optional metadata must not affect outcomes, permissions,
privacy, retries or progress when absent or ignored. Do not weaken closed
validation of gameplay commands or sensitive payloads to avoid a protocol bump.
Without feature negotiation, a new client cannot assume that an older server
has implemented a new command. Trying it and falling back after rejection is
not an implicit compatibility mechanism.

A corrective implementation that restores the documented contract is distinct
from changing the contract. If old clients cannot safely satisfy a newly
required invariant, define that invariant in a new protocol baseline and test
it. Do not increment the protocol solely to force installation of an unrelated
application release.

Existing service-availability fields, including Forge/player-hosting flags,
remain deployment observations with their existing semantics. They do not
become a general feature-negotiation system. The existing
`rulesCrashReportSchema` diagnostic opt-in also keeps its narrow delivery
semantics; it does not gate connection or cluster routing. No existing marker
is removed merely because a general negotiation framework is out of scope.
New room-specific protocol
requirements, multi-protocol translation and capability negotiation are outside
this design; a future need requires its own explicit decision.

## 5. Official cluster

All admitted clients on one hub have the hub's single game protocol. Therefore
the origin node's published protocol is sufficient for cluster selection;
no per-client compatibility profile is needed.

- Keep `Report.version` as the actual application release. Add required
  `Report.protocol`, sourced from the same game-protocol constant as hello.
  It cannot change during a node registration generation.
- Change placement, global room/event/account-resource discovery and aggregate
  service availability to select healthy nodes by exact game-protocol equality.
  All existing capacity, identity, realm and permission checks still apply.
  Never route or restore an account resource through an incompatible node.
- Bind `Ticket.protocol` to the source report's protocol alongside its current
  account/guest identity, target generation, command digest, expiry and
  single-use state. Validate the protocol before ticket consumption, during
  destination hello and before replaying the original command. A protocol
  change requires a new registration and invalidates old-generation routes.
- Introduce a separate required `rpcVersion: "hexproof.cluster.v1"` on internal
  requests and results. Validate it for both HTTP and in-process `Service.Do`
  calls. Cluster RPC compatibility is independent of game/app versions;
  missing or unequal RPC versions are configuration/protocol errors, with no
  fallback. Keep authenticated transport and strict request decoding.

Old cluster requests are unversioned and reject unknown fields. Adding the new
fields is therefore a coordinated internal-contract cutover, not a compatible
rolling extension to the old coordinator. Afterward, different application
releases can share a cluster when their game and internal RPC identifiers match.
Different game protocols may coexist behind a compatible coordinator, but their
discovery and placement remain separate. A hub still supports only one.

## 6. Engine and other component boundaries

Keep the helper wire protocol, full Forge `RuntimeID`, overlay/base linkage,
archive checksums and engine-migration checkpoint checks unchanged. Application
release differences alone do not invalidate an unchanged runtime package.
Ordinary players and spectators do not need a matching local Forge installation;
the exact runtime checks apply when executing, hosting or taking over an engine.

Feedback keeps its independent schema and destination. Application releases,
game protocols, cluster RPC, runtime manifests and persisted local-data schemas
are not aliases for each other. This policy does not promise application
downgrade safety or live game recovery after a hub restart.

## 7. Migration and release procedure

1. Implement the schema, both handshake checks, mismatch/update UI, cluster
   contract and verification together. Preserve real application versions.
2. Qualify and publish the first v2 client/hub artifacts and protocol metadata
   through the normal release process. Choose the application release number
   separately; design approval does not publish a release.
3. Schedule the initial coordinator, hub, paired home-connector and client
   transition. Existing
   3.0.0 clients need a new client; existing v1 hubs need the new hub. Do not
   claim that a server-only change enables old clients. Any temporary v1
   endpoint remains an explicitly operated legacy service, not a v2 fallback.
4. Treat live-room draining and restart authorization separately. The current
   deployer's occupied-room protection remains in force. Protocol compatibility
   does not make restarting an occupied hub nondisruptive or provide live
   cross-node game migration. An automated drain mechanism is a separate task.
5. For later releases, record the application version, game protocol, internal
   RPC protocol and runtime identity. Only deploy components that changed and
   require deployment. A compatible client-only release does not require hub,
   connector, gateway or Forge upgrades; component packaging remains coherent.

Same-protocol hub upgrades can be scheduled node by node after rooms finish.
The hub's read-only `-protocol` option exposes its wire identity. Home inventory
identifies legacy binaries without that CLI option as v1; deployment preflight
and rollback explicitly use the inspected protocol. The operator smoke tool can
check reviewed v1/v2 endpoints without negotiating or downgrading a game client.

Post-deployment checks still verify each selected node's intended artifact
version/hash. Such operational verification must not become a requirement that
every fleet node or connected client has the same application version.

## 8. Implementation acceptance and continuing verification

Implementation and release qualification use this matrix. Local results are
recorded in the development handoff; no released v2 peer exists yet:

| Combination or event | Required result |
| --- | --- |
| Older client/newer hub and newer client/older hub, same protocol | Connection, gameplay and reconnection succeed. |
| Equal application versions, unequal protocols | Hello rejection precedes hub admission side effects; welcome rejection precedes client-local credential/membership changes. |
| Missing, empty, malformed, overflowing or different protocol; legacy v1/v2 pairs | No default, downgrade or retry loop. The receiving side rejects before applying its own credential, room or ticket changes. |
| Different application releases in a same-protocol cluster | Discovery, creation, joining, watching and account recovery route correctly. |
| Different game protocols or invalid internal RPC versions | No cross-protocol placement or ticket consumption; errors are bounded and explicit. |
| Transfer ticket reused after target generation/protocol changes | Rejected; existing identity, digest and replay protections remain. |
| Same game protocol, different engine runtime | Normal connection works; hosting/handover obey independent exact runtime checks. |
| Compatible optional metadata omitted/present | Both directions preserve results, privacy and recovery. |
| New release available, same protocol | Advisory update only; no connect/reconnect block. |

Exercise manual play, Forge decisions, sideboarding/tournaments, state sequences,
duplicate commands and owner/opponent/spectator projections where affected.
Cover the client mismatch display and stop-retry behavior as well as Go checks.
Release qualification must use frozen baseline fixtures and independent released
peer artifacts in both directions; rebuilding two peers from the new schema
with different version strings is useful but insufficient. Include the first
release and latest earlier release of the same protocol, extending coverage
for any affected intermediate behavior. A failing pair blocks release under
that protocol until compatibility is restored or a justified new baseline is
introduced.

The first release of a new protocol has no earlier same-protocol peer. Bootstrap
it with reviewed frozen fixtures and immutable candidate client/hub artifacts,
the full acceptance matrix and legacy-protocol rejection checks. Differing
application-version test builds verify the removal of the old gate, without
claiming historical interoperability. Preserve the resulting first released
artifacts, source revision and checksums as the baseline for later releases;
the released-peer requirement above applies from the next same-protocol release.

The implementation spans the Go/Qt handshake, generated wire schema and fixtures,
cluster report/request/ticket paths, client update metadata, release packaging,
deployment smoke assertions and the living networking/operator documentation.
It must not be reduced to deleting the server's application-version comparison.
