# Operator-owned home servers

## Product contract

An operator-owned home node runs a complete Hexproof hub and, when enabled,
its local Forge runtime. It is a normal trusted server, not a seated player or
a player-hosted engine. Room membership, authentication, operation ordering,
game state, and viewer-specific projections belong to that home hub. The cloud
gateway never executes a second copy of its rooms.

The existing cloud servers remain independently selectable. Each home node has
a stable catalog ID and WSS URL ending in `/home/<node>/ws`. Room discovery is
local to the selected hub; this feature adds neither a global lobby nor
cross-hub matchmaking. Exact client/hub application-version checks still apply.

New clients prefer an authenticated WebRTC data channel to the home node.
STUN discovery and ICE negotiation find a direct route where possible; bounded,
authenticated TURN allocations provide an RTC relay route when configured.
The gateway also supports ordinary WSS forwarding for existing clients and
networks where RTC setup fails. Different members of one room can use different
routes to the same home hub. No player installs a VPN or runs Forge merely to
connect to a home server.

The client displays the established server route as direct or relayed. This
status is separate from the existing bilateral player-hosted Forge transport
preference. A home-server connection reveals network addresses to the selected
operator-owned server, as an ordinary server connection does; it does not create
a peer mesh between the other players.

## Connection and trust boundaries

The home connector authenticates an outbound persistent registration to the
cloud gateway using a node-specific operator secret. Only allowlisted nodes can
register. Replacing a registration fences its previous generation and closes
associated sessions. Stale or unavailable nodes cannot receive new clients.
The gateway's public health response reflects a bounded, recent health report
from the actual home hub, including its existing capability header.

Each incoming client receives a separate connection grant, signaling channel,
and backend WebSocket. ICE/DTLS identity and a random connection binding are
delivered through the authenticated gateway. TURN credentials are short-lived;
node and TURN secrets are supplied in protected operator files, never URLs,
command-line arguments, the public catalog, or diagnostics.
The default credential lifetime is 24 hours so a long table can refresh its
allocation. Credentials are issued per connection endpoint; a new connection
gets new credentials. An uninterrupted session beyond that lifetime is not
guaranteed and must use the normal reconnect flow.

The connector opens only its configured loopback hub. Public callers cannot
select a host, port, filesystem path, or executable. The normal game protocol
is forwarded unchanged, including the existing version check, room passwords,
reconnect credentials, and owner/opponent/spectator projections. Separate
player-host engine connections retain their existing room capability checks.
The gateway normalizes the original client address through explicitly trusted
proxies; the loopback hub trusts only its local connector for that address.

Connection counts, signaling size and count, message sizes, pending queues,
setup time, heartbeat lifetime, and slow-consumer handling are bounded at the
gateway, connector, and client helper. The desktop helper remains supervised
by its parent input pipe and requires no Java for transport.

## Route selection and reconnect

Route selection must never execute the same command on multiple independent
game streams. A connecting client may fall back from RTC setup to ordinary WSS
before it sends game messages. After a game session exists, loss of its
transport closes that stream and uses the normal authenticated reconnect flow.
Unacknowledged ordinary game commands are not blindly replayed. The original
remote WSS URL remains the reconnect identity, regardless of transport.

Within one RTC association, direct and TURN candidates carry the same ordered,
reliable data channel. Initial preference for direct candidates is bounded;
this does not promise seamless live upgrades from TURN or survival of an ICE
restart. Reconnection restores the current authorized projection from the same
home hub, not another cloud or home node.

Cloud forwarding can recover a failed direct route while the home node remains
reachable. It cannot recover a home power failure, complete WAN outage, or lost
hub/JVM process. Automatic cloud takeover, durable live-game recovery, and
cross-hub migration are outside this feature.

## Deployment and qualification

Keep legacy stopped home services and their data intact. Run the new home hub,
connector, and cloud gateway as independently managed services with fixed
artifacts, protected configuration, resource limits, and a rollback path.
Production game hubs use fixed, verified matching server/runtime artifacts.
The initial deployment uses published artifacts; an explicitly authorized
private version deployment can use locally packaged artifacts with recorded
source identity, checksums, matching complete runtime sources, and qualification
on each target architecture. Source development does not silently replace the
existing cloud game services.

Qualification includes actual message delivery through direct RTC, forced TURN,
and ordinary WSS; two players and an observer through one authoritative hub;
node isolation; invalid node credentials and expired grants; node restart;
client cancellation and reconnect; and shutdown of every test-owned process.
Test server-authoritative hidden-information projection with mixed routes.
Native client checks use isolated profiles and maximized test windows.

Report the distinction between workstation/local transport tests and public
WAN probes. A successful STUN response, a healthy process, or a displayed
connection label alone does not prove that a game crossed the claimed route.
Measure confirmed game operations separately from ICMP or connection setup.

Operator deployment commands and verification evidence are recorded alongside
the home-node deployment tooling and in the maintained fleet documentation.

## Connector configuration

`hexproof-home gateway -config <private-file>` runs the public gateway behind
the operator's HTTPS reverse proxy. `hexproof-home node -config <private-file>`
runs an outbound home connector. Both accept `-check` to validate configuration
without starting network services. The gateway listens only on loopback;
production registration and client URLs require WSS. Configuration files must
be readable only by the operator and the dedicated service account.

A gateway file has this shape (replace both credential placeholders with
independent random secrets of at least 32 characters):

```json
{
  "listen": "127.0.0.1:57322",
  "nodes": {"home-example": "REPLACE_WITH_A_RANDOM_NODE_SECRET"},
  "stun": ["stun:example.com:3478"],
  "turnUrls": ["turn:example.com:3479?transport=udp"],
  "turnSecret": "REPLACE_WITH_A_RANDOM_TURN_SECRET",
  "turnLifetimeSeconds": 86400,
  "maxSessions": 64,
  "maxSessionsPerNode": 32,
  "maxSessionsPerIP": 8
}
```

The matching node file contains only its own node secret:

```json
{
  "nodeId": "home-example",
  "token": "REPLACE_WITH_A_RANDOM_NODE_SECRET",
  "gatewayUrl": "wss://example.com/home/register",
  "backendUrl": "ws://127.0.0.1:57323/ws",
  "healthUrl": "http://127.0.0.1:57323/healthz",
  "maxSessions": 32
}
```

The public game endpoint is `wss://example.com/home/home-example/ws` and its
capability probe is `https://example.com/home/home-example/healthz`. The node
ID and endpoint remain stable across connector restarts. Omit both TURN fields
when no working TURN service is available; WSS forwarding remains available.
`hexproof-forge-host --home-connect` is the desktop's supervised transport
helper. Its internal JSON pipe is separate from the unchanged game protocol.
