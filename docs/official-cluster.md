# Unified official lobby and room placement

Owner-approved implementation scope, 2026-09-27. This supersedes the historical
connected-hub-only discovery restriction for official servers. Independent hubs
keep their existing behavior; automatic player matchmaking remains out of scope.

The [protocol compatibility policy](protocol-compatibility.md#5-official-cluster)
is implemented in source. Node reports retain actual application `version` as
metadata and carry required game `protocol`; selection and discovery filter by
protocol. Tickets bind that protocol to their existing identity, command and
target-generation constraints. Internal requests/results require
`rpcVersion: "hexproof.cluster.v2"`, including local calls. This baseline adds
coordinator-wide tournament creation identity and requires matching RPC versions
before registration, ticket or operation-history changes. Frozen cluster v1
peers are rejected in both directions; no downgrade or negotiation is added.
Changing game protocol requires a new node registration. Source changes do not
release or deploy services.

## Ownership and routing

Official nodes share one bounded coordination service and the existing account
realm. The coordinator maintains expiring node reports, public room/event
metadata, private account resource locations and short-lived placement leases.
It does not receive hands, decks, draft packs, game commands or Forge state.
Each room, whole draft and whole tournament stays on its original authoritative
hub. Existing privacy projections and event lifetimes remain authoritative.

Global invitation codes are `NODE:LOCALCODE`, with a stable operator-assigned
uppercase node ID. Local codes still work on their originating hub. Public
discovery aggregates only the existing public room/event projections from
healthy, matching-protocol nodes; private playtests and pairing tables remain
unlisted. A global code can locate a private/password-protected resource but
never grants admission or bypasses its existing permission checks.

Creation reserves capacity before directing a client to a node. Placement
considers mode/runtime capabilities, configured limits, existing demand,
in-flight reservations, available memory, relative load and client latency
hints. Waiting Forge rooms and whole events contribute estimated demand, while
local runtime limits remain the final admission boundary. An unavailable/full
cluster rejects new allocation explicitly. A failure after a create is sent is
never retried as another create on a different node.

Cross-node transitions use expiring, single-use tickets bound to the target
node generation, account identity (or guest), command type and command digest.
Clients retain the original command privately and only follow a correlated
route to a trusted directory endpoint in the same account realm. Codes, device
tokens and transfer tickets never enter URLs or command diagnostic metadata.
Routing cannot abandon an active room or change an ongoing Cube seat.

`session.hello.clusterRealm` opts in only at a trusted directory endpoint.
`session.welcome.clusterNode` advertises the node's invitation prefix. Custom
connections without this opt-in keep node-local creation, discovery and account
resources, even when that hub also participates in a cluster. A route includes
only `url`, `realm`, `nodeId` and a private `ticket`, echoes the original request
ID, and is not command success. The destination checks the ticket during hello
and validates the original command digest before applying normal domain checks.
The client does not show a second welcome/menu transition during a transfer.
An accepted route shows one blocking progress indicator until the original
request succeeds or fails; it keeps the discovery list and its filters visible
instead of presenting the deliberate socket replacement as a disconnection.
Ordinary commands are not sent during the destination handshake. The progress
indicator clears on rejection, transport loss, cancellation or the existing
bounded transfer timeout; real connection failures retain their normal errors.

The automatic entry option selects a configured official endpoint using current
latency probes, preferring reachable nodes over unchecked or failed probes.
Continuing a saved room session preserves its original node. Explicit node
selection and custom addresses remain available. Guest event
credentials stay scoped to their originating endpoint; a remembered, trusted
node-to-endpoint mapping allows global invitations to restore those credentials.

The client restores a unique account room from any official entry node. If
multiple account rooms exist, the account resource list lets the player choose;
it never guesses which concurrent seat to replace. Network reconnection to an
existing game keeps its original node and sequence/credential semantics.

## Tournament creation identity

The official client preserves one explicit `tournament.create.operationId`
through routing, reconnect and uncertain results. A new custom Set plan requires
that identity. The entrance validates its bounded format and forwards it unchanged
as internal `createOperationId`; the full payload digest remains separately bound
to the ticket, account, target generation and expiry. An operation ID is not an
authentication credential, and `Token` retains only its existing ticket purpose.

After node identity, generation and request-shape checks, the coordinator claims
`(gameProtocol, operationId)` atomically under its existing state lock before
reserving capacity. The identity does not change with entrance node, destination,
account or modified payload. The target also claims an explicit identity before
generating event credentials. Both histories retain up to 4,096 attempted
creations per process; they never evict old entries to admit another create.
Failed allocation, an unknown response, ticket expiry/completion and node
re-registration retain the coordinator tombstone. Replay returns a specific
non-retryable operation error (HTTP 422 internally); full operation history
returns a distinct history-full error (HTTP 507). Neither is generation fencing,
ordinary capacity exhaustion or authority to create a new operation automatically.
No replay reissues event credentials.

The guarantee lasts for the coordinator process and corresponding target process;
it adds no durable cross-process recovery. Restarting or selecting another node
is not a retry policy. Legacy single-product requests may omit the explicit ID;
their connection plus envelope ID prevents duplicate creation only within that
connection. It does not provide cross-entrance/reconnect deduplication.

## Availability

Node reports expire, restarting node registrations fence previous generations,
and allocation leases expire if a client disappears. Monotonic report sequences
prevent delayed HTTP requests from overwriting newer capacity snapshots. Coordinator interruption
stops new placement/discovery; already-established games continue on their hubs.
Each accepted report replaces the node's complete directory snapshot. Omitted
optional room/event fields and removed account-resource entries do not carry
over from a previous report, including when rooms are reordered or removed.
Account-authority availability is a separate dependency and retains the
existing account validation behavior described in `accounts.md`.
Coordinator memory is rebuilt by node reports after restart. It is not a game
backup. Node/Forge process loss still follows existing failure behavior; live
cross-node migration, replicated games and process-restart recovery are outside
this slice.

The node agent orders publications separately from its cached state and allows
up to eight independent directory/allocation RPCs. Each wait and call shares a
three-second budget and inherits caller and agent-shutdown cancellation.
Concurrent discovery requests can share a publication whose snapshot began
after their read, preserving immediate local discovery. Completed reservations
are queued independently of a disconnected player and released only with a
subsequent snapshot; unsuccessful publications retain them for retry. Late
responses from an older registration cannot fence a replacement generation.

`GET /healthz` remains the existing liveness response. `GET` or `HEAD /readyz`
returns 503 when a configured account authority is unreachable or the cluster
report is stale/fenced; disabled dependencies do not prevent readiness. Account
probes use an empty credential, a one-second deadline and a one-second shared
probe cache, separate from gameplay credential validation. JSON includes only
dependency status, bounded error categories, report/completion counts, queue
send failures and aggregate account RPC, account admission and discovery
timings. Timing buckets are exclusive upper bounds of 10, 50, 100, 500, 1,000,
5,000 milliseconds and infinity. No account IDs, room IDs, tokens, payloads or
endpoint details are exposed. Publication logs record error-category changes
and recovery without credentials. Exposing the new probe through a production
proxy remains an operator deployment choice.

## Operator setup

Enable with `-cluster-config` / `HEXPROOF_CLUSTER_CONFIG`, a private JSON file.
Every participating node must use the same configured official account realm
and shared account authority. One node hosts the coordinator; satellites make
outbound HTTPS calls, which also works for home nodes behind NAT. Existing home
connector/direct/WSS paths continue carrying the actual game connection.

The config contains `realm`, `nodeId`, `coordinator` (empty on the coordinator),
`keyFile`, and `nodes` entries with stable `id`, `name`, public `url`, and positive
placement `weight`. Public URLs must match the trusted client directory. The
coordinator endpoint is its private `/internal/cluster` POST route; use a shared
random service key in a protected file. HTTPS is required except literal
loopback addresses in isolated test realms. Neither startup nor this source
change modifies production service/proxy settings or publishes a directory.

Start from [`deploy/cluster.example.json`](../deploy/cluster.example.json).
On satellites set `coordinator` to the coordinator's HTTPS `/internal/cluster`
URL and `nodeId` to the satellite's stable ID. All nodes use the same node list,
realm and secret; use a separate random secret from the account service key.
Protect the files with owner-only permissions. Keep node IDs stable across
upgrades because saved invitations refer to them. Public home-node URLs may
use the existing `/home/<node>/ws` gateway path from the client directory.

Reports are published every two seconds and expire after ten seconds. Placement
tickets expire after thirty seconds; at most 2,048 may be outstanding. Reports
and directory RPCs are bounded to 4 MiB. Up to sixteen nodes may be configured.
A replacement registration fences the previous process; the old process does
not automatically reclaim its ID. Coordinator restart causes nodes to register
and republish; no game state is recreated by that registration.

`weight` is a relative placement preference, not a capacity override. Existing
room/event/connection limits and `MaxForgeGames` remain hard local limits.
Waiting server-hosted Forge rooms reserve one estimated game; a nonterminal
Forge event reserves `ceil(maxPlayers / 2)` so a whole round can stay together.
Choose event capacity that fits a single node. Linux available memory and
CPU-normalized load are advisory placement inputs; configured capacity remains
authoritative when host counters are unavailable. Client probes use milliseconds, with `-1` for an unavailable endpoint; missing
probes carry an unknown-latency penalty. These hints cannot override health, protocol, mode or capacity checks.

Application installation continues through `deploy/deploy-release-server.sh`
with explicit owner-authorized targets and version. Do not create another
deployment entry point for the coordinator.

## Verification

`internal/cluster` exercises concurrent reservations, capability/protocol/health
selection, failed latency probes, ticket expiry and identity, generation fencing,
out-of-order reports, directory privacy and authenticated coordinator restart.
Creation regressions include concurrent entrances, changed payload/account/target,
unknown responses, completed/expired tickets, replacement node generations,
history limits, explicit errors and frozen v1/v2 RPC rejection without mutation.
`internal/server/cluster_test.go` uses two real WebSocket hubs and a shared account
authority for creation, discovery, password/spectator admission, UID recovery,
whole-Cube ownership, source rate limits and coordinator outage behavior.
Qt tests cover trusted routing, request correlation, guest event credentials,
failed transfers without replay, and unique-versus-ambiguous account recovery.
They also retain transfer progress through destination admission, preserve
discovery views, block duplicate input and clear progress after success,
rejection, cancellation, a dropped handshake or the transfer deadline.

`tools/ui-automation/scenarios/OfficialCluster.qml` is the three-profile native
scenario. Supply two local nodes named `N1`/`N2`, one shared test account realm,
and a trusted test directory with N1 first. Give N2 higher placement weight so
creation enters through N1 and runs on N2. The third profile discovers and
spectates the same N2 room through N1. It uses isolated disposable credentials,
maximized native windows and no production services.

`tools/ui-automation/scenarios/ClusterEntry.qml` uses three isolated guests to
check room creation, player entry and spectator entry across N1/N2. Delay N2's
WebSocket application traffic without delaying directory probes to inspect the
progress overlay, retained list/filter and final room role in maximized windows.
