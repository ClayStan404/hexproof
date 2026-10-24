# Multi-client testing

This guide runs multiple complete Hexproof GUI clients on one Linux
workstation. It is intended for real manual testing of two-to-eight-seat Set Draft,
two-to-eight-seat Cube Draft, and tournament flows. The clients are not protocol bots and do not
bypass normal server validation, hidden-information projection, deck
submission, pairing, or result reporting.
The final section covers opt-in [Forge checks across networks](#forge-checks-across-networks)
with separate test desktops and an isolated hub.

The helper starts maximized windows by default. Keep every seat maximized and
switch the active client while testing; this is also the baseline for AI review.
Use `--windowed` only for an explicit supplementary layout or window-state check.

## Prerequisites

Build the client and server from the repository root:

```sh
cmake -S apps/client-qt -B build/client-qt -G Ninja
cmake --build build/client-qt
mkdir -p build/server
(cd apps/server && CGO_ENABLED=0 go build \
  -o ../../build/server/hexproof-server ./cmd/hexproof-server)
```

Use a client supporting the launcher's `--server-url` and `--display-name`
options instead of the older resume-settings workaround. Rebuild when an
updated launcher needs new client options or behavior; a shell-only change
does not by itself require a client rebuild. An older binary missing these
options exits with an error in the instance log.

The default profile template is the current Linux Hexproof application-data
directory:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/Hexproof/Hexproof
```

Install the card database and prepare any reusable test decks in the normal
client before initializing the multi-client profiles. Profiles are cloned only
on their first use. Later changes to the template are not automatically copied
into existing profiles; update those profiles in the client or use a fresh
`--profiles-root`. Reusing initialized profiles does not require the original
template to remain available.

## Start a local test group

Start the server in one terminal:

```sh
./build/server/hexproof-server -bind 127.0.0.1 -port 57320
```

Start eight clients in another terminal:

```sh
./tools/run-multiclient.sh start --count 8
```

The launcher creates `Test Player 1` through `Test Player 8`, labels every
window, selects **Custom server**, and prefills the local endpoint. Each
process has separate XDG configuration, application data, cache, logs, and
resume credentials. Public server entries remain unchanged. The launcher only
prefills connection details; it does not connect automatically or start a server.

The default persistent profile root is:

```text
build/multiclient/default/
```

Every instance contains:

```text
client-NN/
  config/              QSettings and connection identity
  data/                 decks, catalog, cache metadata, and image directory
  cache/                Qt runtime cache
  logs/client.log       process output for this instance
```

Mutable files such as `cards.sqlite`, `decks.json`, and `card-cache.json` are
copied independently. QSettings and room resume credentials are not cloned
from the normal client; each profile creates its own. Existing card-image bytes are
hard-linked into separate directories by default to reduce disk use. Hexproof
writes new and replaced images atomically, so each profile can add or replace
its own directory entries without changing another profile. Use
`--copy-images` when physically independent image bytes are required.

On a filesystem without copy-on-write support, eight copies of the catalog
database require approximately eight times the size of `cards.sqlite`. Cached
image bytes do not require eight copies unless `--copy-images` is used.

## Operate the clients

The instance label is display-only; it does not change the application name or
storage location. Each data directory is locked for the lifetime of its client,
so accidentally launching it twice opens a profile-in-use notice. Independent
launcher profiles can still run concurrently.

Use the window title or desktop task switcher to identify each seat. In every
client:

1. Open **Connect to server**.
2. Keep **Custom server** selected and confirm the prefilled local endpoint.
3. Confirm the prefilled `Test Player N` name.
4. Connect and join the event or room normally.

One client acts as the organizer or room host. The other seven clients join,
register, and check in as normal players. All Draft picks, deck construction,
matches, and result reports remain manual.

## Automatically prepare Sealed, Draft, or Commander Cube

With the local server already running, start an eight-seat Draft or a four-seat
Sealed event directly:

```sh
./tools/run-multiclient.sh start --event draft --set EOE --count 8
./tools/run-multiclient.sh start --event sealed --set EOE --count 4
./tools/run-multiclient.sh start --event commander-cube --cube "My Cube" --count 4
```

These are alternative launches; stop the first group before starting the next.
All requested profiles are prepared before any client starts, so slow template
or image copies do not consume the event setup timeout. If profile preparation
fails, no automatic event clients are launched.
`--set` is case-insensitive and must identify an installed Limited set in the
first profile's catalog. The same preferred booster selection as the normal
creation screen is used. The launcher does not download a database or silently
substitute another set if it is missing. Template data is still copied only
when a profile is first initialized.

For Commander Cube, `--cube` replaces `--set` and selects a saved Cube by exact
name or ID in client 1's deck library. Names must be unique; use the ID if two
Cubes share a name. The source must contain enough physical cards for the
selected capacity. No synthetic Cube or replacement pool is generated.
Two-to-four-player setup uses the normal recommended six-pack paired preset;
five-to-eight-player setup uses three single packs. Change `--count` to 8 to
prepare the standard eight-player draft. Use a fresh `--profiles-root` when
testing changes to the template's saved Cube.

Add `--auto-draft` to a Commander Cube launch to finish all packs automatically
and go directly to deck building:

```sh
./tools/run-multiclient.sh start --event commander-cube --cube "My Cube" --count 4 --auto-draft
```

Each client enables its own ordinary Cube auto-draft control. The server makes
random picks and observes the configured pack/pick rules; it does not optimize
a deck or share private cards between clients. Four-player defaults produce
120 drafted cards per player; eight-player defaults produce 60. Automation
stops at deck building, with commanders, optional Sol Ring/Command Tower/Arcane
Signet copies, deck construction, and submission left to the tester. This flag
requires `--event commander-cube`; without it, drafting remains manual.

Automatic setup performs only these ordinary client actions:

1. Every isolated client connects to the requested loopback endpoint.
2. Client 1 creates a uniquely named Set Draft/Sealed Swiss event with BO3
   matches and 50-minute rounds, or a casual Commander Cube room with BO1
   matches. Capacity equals `--count`.
3. Other clients find that exact launch-group name and enter the event.
4. Every client, including the organizer, registers and checks itself in.
5. The organizer starts only after **all** requested participants are checked in.
6. Each client opens the normal event UI. Automation stops after receiving its
   private current pack (Draft), or deck-building pool (Sealed or Commander Cube
   with `--auto-draft`).

Draft and Commander Cube support 2–8 clients; Sealed supports 2–16 in this launcher.
Picks remain manual unless `--auto-draft` is requested. Deck construction,
deck submission, subsequent rounds, and match play remain manual.
Pools, credentials, and card choices are never passed between clients. The
ordinary server performs all product validation and pack generation.

`--event` is opt-in and accepts only loopback servers (`localhost`, `127.0.0.1`,
or `::1`); it cannot create events on the configured public hubs. A new launch
uses a fresh group identity and does not resume an old room. Already-running
clients in the profile group cause the launch to be rejected. To resume an
existing event, omit `--event` and re-enter normally with the preserved
profile-specific tournament credentials.

Setup stops on a connection/server error or after 90 seconds waiting for a
missing participant. The error appears in the client banner and
`client-NN/logs/client.log`; connected clients remain available for manual
recovery. The script reports process startup, not event readiness. Look for
`Local test setup complete` in each log to confirm the handoff. Existing test
events are not automatically cancelled or deleted.
The launcher directs Qt diagnostic output to each client log, including when
the desktop would otherwise route those messages to its journal.

In this explicit automation mode, startup sponsor/cache-repair notices and
scheduled startup update/audit checks are suppressed without marking notices
as acknowledged. Regular launches keep their existing behavior. Card art may
still load on demand; prepare/cache the desired set before testing offline.

## Recommended real-flow checks

### Set Draft

1. Create an eight-seat Set Draft using an installed Limited product.
2. Join and check in all eight clients.
3. Confirm every seat receives only its own current pack and picked pool.
4. Confirm each client sees itself at the bottom of the same physical seat
   order and that its named outgoing/incoming neighbors match the pass direction.
5. Make one pick in each window for every pick step and confirm every prior
   pick remains visible only to its owner.
6. Confirm pack direction and named neighbors reverse for the next pack.
7. Close and restart one client during the draft, then verify private state is
   restored without disclosing another player's pool.
8. Move cards between the visible main-deck and sideboard areas, then submit a
   legal 40-card deck in every client.
9. Complete pairings, report results, and verify standings and the next round.

### Cube Draft

1. Prepare the Cube-format deck in the normal deck library before cloning a
   fresh profile group, or import it into the organizer profile.
2. Create the Cube tournament with a two-to-eight-player cap and fill at least
   two seats. Repeat with eight seats when validating the maximum pod size.
3. Complete the three-pack Draft manually.
4. Verify that cards come only from the selected Cube pool and cannot be
   duplicated beyond the pool contents.
5. Submit decks, play or concede paired matches, and verify tournament
   progression.

### Set Sealed and tournaments

1. Confirm each player receives an independent six-pack pool.
2. Verify that private pools survive reconnects.
3. Submit a 40-card deck and confirm cards outside the player's pool are
   rejected.
4. Exercise registration, cancellation, re-registration, check-in, round
   pairing, result confirmation, drops, byes, standings, and final public
   decklists.

## Status, logs, and stopping

Inspect recorded processes:

```sh
./tools/run-multiclient.sh status
```

Read an individual client log:

```sh
less build/multiclient/default/client-01/logs/client.log
```

Terminate the test group:

```sh
./tools/run-multiclient.sh stop
```

The server is not started or stopped by the launcher. Stop it separately when
the test is complete.

Profiles survive `stop` and the next `start`, which permits disconnect/resume
testing. Use a different root for an independent or fresh test group:

```sh
./tools/run-multiclient.sh start \
  --profiles-root build/multiclient/draft-session-2 \
  --count 8
```

Each `start` passes the requested endpoint and generated display name to the
client, which applies them before opening the Connect screen. The launcher
does not rewrite the Qt settings file. Player reconnect credentials survive
only when both the normalized endpoint and display name match; changing
`--server` or `--name-prefix` clears the old room identity. Spectator credentials
remain session-only, and launch defaults never create fake resume credentials.
This also repairs profiles initialized by older versions of the script.

Already-running clients are left unchanged; use `stop` before restarting with
new arguments. Start/stop operations take a non-blocking, profile-root-specific
`flock` lock to prevent concurrent launches from writing the same profiles.
PID checks match both the instance number and its absolute profile path, so a
stale PID file cannot mistake another test group's same-numbered client for
its own.

Do not point two running clients at the same profile root and instance number.
The launcher detects its own recorded processes, but unrelated manual launches
with the same XDG directories can still race on settings, catalog, and cache
files.

## Useful options

Use a different prepared AppData template:

```sh
./tools/run-multiclient.sh start \
  --template /absolute/path/to/prepared-app-data \
  --count 8
```

Use another server or display-name prefix:

```sh
./tools/run-multiclient.sh start \
  --server ws://192.0.2.10:57320/ws \
  --name-prefix "Draft Seat" \
  --count 8
```

Create empty client profiles without cloning a catalog or decks:

```sh
./tools/run-multiclient.sh start --no-template --count 8
```

Run `./tools/run-multiclient.sh --help` for the complete option list.

## Forge checks across networks

Use explicit authorized test machines and a dedicated public TLS ingress.
The harness does not provision servers, edit nginx, disable VPNs or modify
firewalls. Arrange bounded cleanup and recovery before changing network
configuration. Never point these tests at production rooms.

Build the opt-in hub and scripted-seat executable from the repository root:

```sh
(cd apps/server && go test -tags engineintegration -c \
  -o ../../build/wan.test ./internal/server)
```

Create a private JSON configuration per process, with mode `0600`. Hub and
participants share a randomly generated 64-character lowercase hexadecimal
`token`. The hub uses `role: "hub"`, `url: "https://<test-endpoint>"` and
`listen: "127.0.0.1:<isolated-port>"`. Proxy only `/<token>/` to this listener,
preserving the path and WebSocket upgrade headers. Alternatively, explicit
`cert` and `key` paths enable the harness's TLS listener.

Each scripted participant configuration includes:

| Key | Value |
| --- | --- |
| `role` | `host` or `guest` |
| `url`, `token` | Same private endpoint/namespace as the hub |
| `case` | Fresh lowercase alphanumeric/hyphen run identifier |
| `mode` | `relay`, `direct`, `blocked`, `drop-replies` or `disconnect` |
| `requireP2P` | `true` for direct, dropped-reply and interruption checks |
| `interface` | Required route interface: Linux device name or Windows `InterfaceAlias` |
| `output` | Absolute private result JSON path in an existing directory |
| `runtime` | Host only: verified extracted pinned Forge base directory |
| `overlay` | Host only: matching client-bundled `forge-overlay.jar` |
| `java` | Host only: absolute Java 21 executable path |

Run the hub with `-test.run='^TestWANQualificationHub$'` and each participant
with `-test.run='^TestWANQualificationSeat$'`, setting `HEXPROOF_WAN_CONFIG`
to its private configuration path. Supply an explicit process timeout; seats
also have an internal seven-minute bound. Both seats coordinate readiness and
completion through the isolated hub. The hub holds at most 64 coordination
records; restart only the test hub between larger batches. Do not reuse cases.

Scripted seats use a synthetic 24-Mountain/36-Lightning-Bolt deck to isolate
transport and native resolution; it is not a legal tournament deck. Direct
checks require a public selected candidate on the declared interface and at
least eight confirmed direct operations. `blocked` blackholes candidates and
requires relay; it is not a sample of a naturally incompatible NAT.
`drop-replies` drops four confirmations and checks fallback without duplicate
execution; `disconnect` closes the established channel after twelve confirmed
host operations. Both seats must agree on the resulting game.

For race coverage, add `-race` when compiling a seat executable. The
candidate-isolation test needs no external network configuration:

```sh
(cd apps/server && go test -race -tags engineintegration ./internal/server \
  -run '^TestWANPublicCandidateIsolation$' -count=1)
```

### Native Qt seats on separate desktops

`tools/ui-automation/run-wan-native.py --config <private-json>` runs the existing
`ForgeDuelMatch.qml` production-input scenario against the same isolated hub on
Linux or Windows. Each machine needs an unlocked desktop and a current
`hexproof_native_audit` build. Both configurations share `url`, `token`, a fresh
`case` and the real-deck `variant`. The URL must be an HTTPS origin without
credentials, a path, query or fragment. A case has 1–48 lowercase alphanumeric
or hyphen characters. One machine owns `seats: [1, 3]` and the other `[2]`, or
use `[1]` and `[2, 3]` to place the spectator on the second machine.
Supply absolute `binary`, `runtime`, `catalog`, `manifest` and new `output`
paths per machine. The runtime must pass the matching helper's `--check`.
Optional `timeout` is 30–1,800 seconds, defaulting to 900.

`migration: "1"` requests planned transfer; `"loss"` terminates only the owned
host helper after in-game backup approval. `peer: true` enables direct consent.
Set `publicICE: true` in the isolated hub configuration to filter private/VPN
candidates while exercising the shipped helper. Hub `blockICE: true` drops
all candidates for failure injection. For that fixture, use
`peerExpected: "relay"` with `peer: true` on both native runners. It must observe
setup then relay fallback, complete the game naturally and finish with zero
direct confirmations; the default expects a successful direct connection.
This test proxy does not alter normal application signaling. Without candidate
isolation or independently verified routes, GUI direct state alone does not
prove public ICE.

Only scenario coordination markers cross the test hub; settings, credentials
and profiles stay on their machines. The runner records input, maximized
geometry, screenshots, source/helper/adapter identities and per-seat outcomes.
Peer failure, missing/stale heartbeats or watchdog expiry fails the run;
process exit zero without complete evidence is insufficient. Driver progress
uses the audit's independent timer and snapshot revisions, so a long turn does
not imply a stalled spectator. The runner manages only its own process groups.
Collect Windows archives after owned clients exit: archiving a live input trace
can deny its writer access. Windows CPU/memory sampling is unavailable and must
not be reported as zero resource usage.

The manual `native-desktop-artifact.yml` workflow provides a Windows test bundle
with the matching helper, adapter, Qt dependencies, scenarios and runner. Its
component tests and file hashes do not qualify interactive GUI behavior. Extract
to a fresh directory and run from an unlocked desktop. Native audit profiles use
`HEXPROOF_TEST_PROFILE_ROOT/data/Hexproof/Hexproof` explicitly on every platform.

A successful run qualifies only its recorded machines, networks, mappings,
transport/migration modes and decks. It does not certify every NAT, another
platform or fleet capacity. The hub remains required and supplies WSS fallback;
these checks make no TURN-allocation claim. Preserve failed attempts separately
from passing outcomes.
