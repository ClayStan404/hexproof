# Player-hosted Forge

## Delivery contract

Player hosting is an optional trusted-host mode for two-player Forge games,
including Duel Commander and BO3. Manual tables and server-hosted Forge remain
available. The room creator initially hosts the engine; public tournament rooms cannot use
player hosting. An explicitly approved opponent can take over a verifiably
replayable game. Both players may opt into direct WebRTC delivery with automatic
hub-relay fallback. There is no automatic cloud takeover.

The public hub retains membership, seat authorization, operation ordering,
match lifecycle, public journals, and viewer-specific projections. Relay is the
default; optional direct delivery still requires hub confirmation of mutations. A bundled Go helper, supervised
by Qt, opens a separate authenticated outbound WebSocket to the same endpoint
and supervises one fresh Forge JVM per game. BO3 and restart never reuse a JVM.
The existing local process adapter and rules normalization are reused.

The host necessarily controls complete engine state. Normal clients preserve
opponent/spectator privacy, but neither TLS nor runtime checksums can protect
hidden cards or results from a malicious host. Creation, room listings and
joining must identify this mode as trusted-host play.

## Transport and lifecycle

Engine connections use a room-scoped capability obtained over the creator's
normal authenticated session. They have an independent receive loop: completing
an engine request must not acquire the room operation lock held by its caller.
Requests bind a room, engine instance, game instance and monotonic operation ID.
Connection epochs fence old sockets without changing operation identity.

Each mutation returns a stable publication containing both player views, the
spectator view, current private prompt, terminal status and a revision. These
privileged bundles never become ordinary player messages. Cached reads within
one publication avoid serial network round trips for every view/prompt query.

The helper retains bounded deduplication state across transport reconnects.
The same operation and payload return the recorded result; altered payloads,
expired operation IDs and cross-game requests are rejected. Unknown outcomes
must fail the game instead of applying an action twice. Network interruption
has a bounded grace period and does not itself destroy the running engine.
A surviving helper resumes directly. Engine loss and grace expiry can restore
on a connected approved successor; otherwise they use the existing aborted-game
flow without declaring a winner. Reconstruction never silently starts a new game.

Queues, frame sizes, connection counts, requests and deadlines are bounded.
Explicit leave, close, restart, timeout and server shutdown revoke bindings and
release pending calls. Parent death/stdio closure stops the helper and JVM.

## Runtime distribution

The native helper and matching native-adapter overlay ship with the client. Java 21 and the pinned Forge base payload
are prepared on demand in application-private versioned storage. Trusted release
metadata pins platform, sizes and SHA-256 hashes, including adapter/resource
identity. Downloads are cancellable, bounded and installed atomically; active
runtimes are never overwritten. A cached verified installation works offline.
Only the engine host needs this payload. Server-side runtime availability,
permission to relay player hosting, and local runtime readiness are separate.

The base archive remains the immutable adapter 2 resource/dependency bundle.
Its old adapter classes are superseded by the packaged overlay, compiled from
the current reviewed source. The helper embeds that JAR's checksum, verifies
its source identity and base dependency identity, and copies it to an immutable
private path before Java loads it first on the classpath. Peers and the hub use
the current source identity, not the base archive's historical adapter label.
Missing/mismatched packaged adapters fail readiness. Every client release must
also publish the complete adapter source bundle; see
[the overlay build contract](../third_party/forge-runtime/OVERLAY-README.md).

The Local Forge dialog is available from Settings, room creation and the host's
waiting room. Downloads retain size-bounded partial files across cancellation
and interruption, retry three times, and resume with HTTP Range. A server that
ignores Range restarts the file safely; every completed archive must match its
pinned size and SHA-256 before extraction. New installations require at least
1 GiB of free workspace. This is a minimum preparation budget, not a reservation
against unrelated programs consuming disk space during extraction.

Players can also choose **Import offline pack** and select a local
`.hexproof-forgepack`. Each pack includes the unchanged pinned Forge archive
and Java archive for one supported OS/architecture. Import validates the pack
schema, package identity, platform, archive sizes and SHA-256 hashes using the
client's embedded pins, then uses the same installation and native adapter probe
as online preparation. It never downloads missing components. Invalid packs,
cancelled imports and failed extraction do not replace the current generation;
leased generations remain intact. Import is disabled while the local helper is
busy, including active hosting. Verified imported archives also support later
offline repair through **Prepare / retry**.

After a failed or cancelled import, the client rechecks the installed runtime
without downloading. Hosting readiness is restored only if that check reports
ready and exits successfully. The original import error remains visible, and
other preparation or hosting operations stay disabled until recovery finishes.

An optional user-configured HTTPS mirror directory serves files named
`<sha256>.tar.gz` or `<sha256>.zip`. The original pinned URL remains a fallback.
Mirror selection is local, never supplied by a room, and cannot select a new
runtime identity, checksum or executable. No additional public mirror is
provisioned by this change.

Cache cleanup removes content-addressed downloads (including partial files) and
unused generations carrying the managed-cache marker. Current, leased, legacy
and unrecognized directories are retained. Native file locks serialize
preparation/cleanup and keep active generations alive until their JVMs exit.
The helper's `--clear-cache`, `--download-mirror` and `--import-pack` flags expose
the same paths.
Diagnostic export writes an explicit allowlist of versions, platform, readiness
and recent hosting states; it excludes cards, decks, credentials, URLs, local
paths and raw engine output.

## Implementation and verification stages

1. Introduce a runtime interface and preserve local-engine regression behavior.
2. Integrate the relay, host helper, room protocol and native client flow.
3. Complete interruption/recovery, fault coverage, runtime preparation and
   packaging; run automated/race tests and local native GUI scenarios.

Verification covers host/opponent/spectator visibility; ordinary constructed and
Duel Commander matches; BO3/restart/reconnect; helper/JVM loss; duplicate/late
operations and replaced connections; wrong seats and cross-room bindings.
Evidence must distinguish local Linux execution, cross-compilation, and actual
Windows/macOS execution. No production deployment or release is part of this
task. Server-managed shared JVMs are a separate optional deployment setting;
player-hosted games retain dedicated JVMs.

## Build and use

Build the matching client and server from the same checkout:

```sh
./tools/build.sh --scope all
```

The client CMake build now also requires the Go version declared in
`apps/server/go.mod`. It builds `hexproof-forge-host` beside the client and
includes it in installation/package staging (inside `Contents/MacOS` on macOS).
Keep the helper with the client; copying only the main executable is insufficient.
Source builds require JDK 21+ for the bundled overlay. Joining a game needs no Java installation. The optional pinned host payload
supports Linux x86-64, Windows x86-64 and macOS arm64.

For an isolated local relay server:

```sh
./build/server/hexproof-server -bind 127.0.0.1 -port 57320 \
  -allow-player-hosting -max-player-hosted-games 32
```

No server-side Forge configuration is required for that mode. Existing Forge
flags independently enable server-hosted games. `-allow-player-hosting` defaults
to false; the binding limit includes waiting player-hosted rooms. Each helper
uses one additional connection within the server's existing connection limit.
The normal `-reconnect-window` defaults to three minutes; engine reconnect grace
uses that value clamped to one second through ten minutes.

1. Connect both clients to this server. Create a two-player room, select Forge
   rules and **Host on this computer** as its host.
2. Prepare local Forge by downloading the pinned Forge and Temurin Java archives,
   or choose **Import offline pack** for a shared pack matching this computer.
   Both paths check hashes, install into private storage and probe the native
   JVM. Progress, cancellation and retry are available.
3. Share the room code. Opponents and spectators must acknowledge that they
   trust the host; they do not prepare or run Java. Once the helper is connected
   and decks are selected, both players can ready up.
4. Keep the current engine host's client open. A transport interruption pauses
   input and can resume the same surviving helper/engine. Without an approved
   available backup, engine loss aborts the game without declaring a winner; the room retains its decks and returns to
   waiting. The creator can reconnect local Forge and players can ready again.

Preparation uses `<application storage>/forge-runtime`. The explicit
`HEXPROOF_FORGE_HOST_RUNTIME_DIR` override supports isolated testing. Repair
publishes a new immutable generation instead of modifying a running one.
Verified cached archives can repair damaged installed files without another
download. An intact prepared runtime works offline, apart from the required
connection to the game server.

### Preparing offline packs for distribution

Obtain the original Forge archive and the platform's Java archive listed in
[`runtimepkg/manifest.json`](../apps/server/internal/runtimepkg/manifest.json).
An existing prepared client's `forge-runtime/downloads` directory contains the
same verified archives, named by SHA-256. Do not zip an installed runtime tree:
packs preserve the original archives, including their notices and licenses.
The adapter overlay continues to ship with the matching client.

Run the packaging tool on any development platform; it verifies the supplied
archives without downloading or executing Java:

```sh
python3 tools/package-forge-offline.py \
  --platform windows-amd64 \
  --archive-dir /absolute/path/to/downloaded-archives
```

Use `linux-amd64` or `darwin-arm64` for the other supported platforms. The
directory may contain original release filenames or `<sha256>.<format>` cache
filenames. Alternatively, specify `--forge-archive /path/to/archive.tar.gz` and
`--java-archive /path/to/platform-java.zip` (or `.tar.gz`). The platform choice
selects embedded pins; it cannot authorize a different Java or Forge build.

The default output is
`build/forge-offline/hexproof-forge-<platform>-<packageId>.hexproof-forgepack`.
Use `--output` to select a different new file. The tool prints its size and
SHA-256 and refuses to overwrite an existing output. Distribute that single file
to players of the corresponding platform; they need a client with the import
feature and matching runtime pins. Packaging does not publish a release.

The pack is a ZIP containing exactly `forge-pack.json`, `forge.tar.gz` and
`java.tar.gz` or `java.zip`. Metadata contains `schemaVersion: 1`, the platform,
and `packageId` (the first 20 hexadecimal SHA-256 characters of the client's
embedded runtime manifest bytes). Metadata does not supply trusted checksums,
download URLs or executable paths. Existing archive extraction bounds,
generation publication, cache locks and cancellation apply unchanged.

## Protocol and operational limits

- The regular welcome advertises `playerHostingAvailable` separately from
  `forgeRulesAvailable`. Room settings, listings and snapshots carry
  `hostingMode`; `hostConnected` reports engine transport state.
- A private `forge.host_grant` goes only to the current or consenting standby host. Its capability reaches
  the helper over stdin, not command-line arguments or QML. The helper connects
  outward to the same WebSocket URL with `engine=1`. Public room messages never
  contain the engine capability or combined private publication.
- Engine protocol version, pinned runtime identity, room, engine ID, operation
  ID and connection epoch must match. Operations are serialized with one pending
  result. Requests are limited to 4 MiB and engine frames to 16 MiB; connections,
  message rate, preparation and execution time are bounded.
- Each host JVM uses a 768 MiB maximum Java heap, Serial GC and two active
  processors. Heap size is not a limit on total process memory. The public hub
  still pays for projections, journaling and network traffic.
- Room ownership remains with the creator after an engine handover. Explicit
  creator departure or expiry of the creator's normal session still disbands
  the room. Verified engine migration and optional direct delivery follow the
  contracts below; persisted-game restore and automatic cloud takeover remain
  unsupported.
- Cancellation retains bounded partial downloads for resume. Verified archives
  and leased/current generations remain available; explicit cache cleanup
  removes only unused managed content. Version mismatches require a matching
  client update.
- This is trusted-host play: checksums detect damaged/mismatched runtime files,
  not a host deliberately changing the engine or reading hidden information.

## Reproducible qualification

Run the complete automated suite with `./tools/verify.sh`. The race suite includes
the relay and installer. Native runtime download/probe, actual relay BO1/BO3 and
real-JVM reconnect/crash/revocation checks can be repeated on each supported OS:

```sh
python tools/qualify-player-host.py \
  --runtime-dir /absolute/path/to/private-runtime-cache \
  --output build/player-host-qualification-new
```

Choose a new evidence directory for each run. The manual **Player-hosted Forge
runtime** GitHub workflow runs this qualification on Linux, Windows and macOS;
it does not publish artifacts as a release or change deployed servers.
Qualification also checks dedicated/shared JSONL output under a non-UTF-8
console encoding and exports `synthetic-checkpoint.json`. Pass that fixture
to another OS with `--checkpoint-import /absolute/path/to/synthetic-checkpoint.json`
to compare every decision and exercise the production restore operation.
These exchange artifacts contain synthetic test decks and complete test state;
ordinary game checkpoints remain private and are never exported by this tool.

The native GUI runner accepts `--player-hosted` for a local relay-only server.
`PlayerHostingSetup.qml` verifies preparation/cancellation/retry and join consent.
`ForgeDuelMatch.qml` supports three windows (host/opponent/spectator), Modern and
Duel Commander BO3, real Boros fixtures, and the `recovery` variant that kills
the owned helper and verifies the aborted-room/new-game flow. The latter can use
`--reconnect-window 3` to exercise grace expiry without a three-minute wait.
All profiles, inputs, screenshots and resource samples remain local to the
explicit evidence directory.

## Verified host migration (adapter 4)

The waiting room and in-game Hosting dialog expose the current engine host,
backup identity/readiness, approval, migration availability and failure state.
Room ownership and engine ownership are distinct. A non-host player first
prepares local Forge and explicitly volunteers; the current engine host then
approves the trust disclosure. Spectators cannot volunteer, approve or transfer.
The approval permits that successor to receive both decks, the game seed and
private choices during a transfer. It does not promise security against a
malicious host. Neither player needs an inbound port.

The current host may request a planned transfer. After engine loss or reconnect
grace expiry, the hub attempts automatic recovery only on a connected approved
backup whose seat still belongs to the consenting member. A disconnected host
can also be replaced through the backup's recovery action. Normal transient
reconnects continue to prefer the surviving original engine.

The hub retains a volatile journal of accepted mutations, bounded to 3 MiB and
10,000 actions per game. The fresh JVM replays the exact decks, seed and choices
and checks every complete publication, including a private logical-state digest
of hidden zone order, remembered/chosen card relationships, per-game IDs and RNG
state. Unknown remembered values or journal exhaustion disable migration rather
than truncate history. This is a determinism guard, not complete JVM serialization
or an anti-cheat boundary. Only an exact matching runtime may replay it.

Replay has a three-minute deadline. Game input pauses while the old runtime
remains bound. A verified replacement preserves the game ID, seat map and match
score but gets a new engine capability and public prompt IDs; old requests and
old host sockets cannot operate it. Planned failure retains a healthy original;
failure after engine loss uses the existing aborted-game flow, never a fabricated
result. Withdraw/revoke is disabled during replay. Leaving/disbanding, restart
and server shutdown cancel the owned replacement work and processes.

Each game starts a fresh journal. BO3, sideboard partitions and restart remain
hub-controlled and continue on the new host after a successful handover. The
journal is neither written to disk nor included in ordinary player/spectator
messages or diagnostic exports. Server restart recovery and moving between
public hubs are not supported.

## Optional direct transport

The waiting room shows compact **P2P** controls in the lower-left footer.
During a game, the same status and actions are in the top-right Settings
drawer, including between games. Both players select **Agree to P2P**; opening
the Hosting dialog is not required. Before opting in, the inline disclosure
explains network-address sharing and the STUN service. Waiting for consent,
connecting, direct delivery, relay fallback and recovery states remain visible.
Eligible players on older servers see a disabled action with the unsupported
reason. Server-hosted rooms and spectators do not show these controls.

Consent is scoped to this room and survives an authenticated in-app reconnect;
leaving the room clears it. The disclosure explains that peers learn each other's
network address and contact a STUN service. Spectators cannot enable, negotiate,
or receive this channel. `session.welcome.peerTransportAvailable` distinguishes
servers implementing the feature from older player-host relay servers.

The bundled helper's `--peer` mode needs no runtime directory or Java. Only an
outbound authenticated hub connection is required for signaling. WebRTC can use
LAN or Internet UDP candidates; this implementation uses
the managed discovery endpoints `stun:47.122.120.151:3478` (Server 1) and
`stun:47.97.30.103:3478` (Server 2), with no TURN allocation. Operators can
override both through `-peer-stun-servers` or `HEXPROOF_PEER_STUN_SERVERS` using
a comma-separated list of at most two `stun:host[:port]` URLs. An explicit empty
value disables STUN discovery while retaining LAN/direct-address ICE and hub
relay. Invalid URLs fail hub startup; changing discovery settings does not
enable player hosting or bypass the two players' consent. Verify external UDP
binding responses after deploying a discovery endpoint; service startup alone
does not establish public reachability. Existing release binaries retain their
original behavior until a matching update.
Incompatible NAT, blocked
UDP, failed authentication, or a failed/slow direct delivery leaves relay play
available. **Use relay only** is available after opting in; **Retry direct**
appears when that connection has fallen back to relay. Both actions are on the
waiting-room/table surface.

Messages are bounded to 4 MiB, carried in ordered 16 KiB fragments with one
bounded reassembly. Signaling is limited to 32 KiB, 66 frames per seat/binding;
the endpoint allows at most 64 ICE candidates. Queues, receive buffers, setup,
fragment deadlines and parent-pipe lifetimes are bounded. A random 256-bit room
binding/key handshake supplements DTLS fingerprint signaling through the hub.
The helper offers no remote executable, download URL, path or shell operation.

The remote player's response goes directly to the host. The host validates its
short-lived hub-issued decision lease and uses the same response builder as
relay play, including native combat-damage restrictions. It holds the resulting
publication pending until the hub validates seat/game/prompt/response, records
it once and creates the usual redacted viewer projection. Only then does the
opponent receive its own acknowledgement/snapshot/prompt over WebRTC. Raw engine
publications and migration journals never go onto this channel. Host actions,
spectator updates and room/match control still use the hub. Terminal projections
also use reliable hub fan-out before match transitions.

After 1.5 seconds without authoritative progress, or after transport failure,
the client retries the identical operation ID/binding over its normal socket.
The helper reuses an already computed result and the hub reuses a confirmed
receipt. Changed duplicates, stale prompts, different seats/rooms/engines are
rejected. At most eight retained decision leases per room allow already executed
inputs to commit across a transport/consent change; obsolete revisions are
pruned. Both old and new connections cannot advance the same decision twice.
Direct operations join the same bounded replay journal as relayed operations.
Migration/restart rotates bindings and new games get fresh native engines.

The public hub remains essential for order, validation, recording and recovery;
this is not offline peer play or a claim that all bytes bypass the hub. Direct
transport has no guaranteed latency advantage. Diagnostics include only the
transport state and direct/fallback counts, excluding addresses and card data.
Qualification must distinguish local real WebRTC/GUI runs from tests across
unrelated Internet NATs and actual native Windows/macOS execution.
The Internet qualification report in the development repository
records the tested Linux network pair, public route evidence, fault injection,
native execution counts, VPN interruption and remaining environment gaps.
