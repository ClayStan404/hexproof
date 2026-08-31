# Rules-engine integration

This document defines the architecture for Hexproof's optional enforced-rules
mode. It supersedes the former product-wide prohibition on a rules engine while
preserving the existing manual tabletop as a first-class mode.

## Product modes

Every room chooses one immutable gameplay mode:

| Mode | Authority | Intended use |
|------|-----------|--------------|
| `manual` | Hexproof room reducer | Existing free-form tabletop and unusual interactions resolved by players |
| `forge` | Forge rules runtime, hosted by the Hexproof server | Rules-enforced games with legal actions, priority, stack resolution, triggers, and state-based actions |

Manual rooms continue to use the current `game.*` commands and projections.
Forge rooms use a separate command and projection family. The two reducers must
not mutate the same live game, and a room cannot change mode after creation.

## Runtime choice

Forge is the first production rules backend because it has mature Magic rules
and card-script coverage. Hexproof integrates the maintained headless Forge
harness from the Manabrew project instead of adapting Forge's desktop UI.

The pinned upstream inputs are recorded under `third_party/forge-runtime/`.
The runtime is built from source and launched by `hexproof-server` as a child
process speaking newline-delimited JSON over stdin/stdout. Forge diagnostics
remain on stderr. The runtime is optional: a server without it continues to
host manual rooms but advertises Forge mode as unavailable.

Configure a built runtime with `-forge-harness`, `-forge-home`, and optionally
`-forge-java`, or with the corresponding `HEXPROOF_FORGE_HARNESS`,
`HEXPROOF_FORGE_HOME`, and `HEXPROOF_FORGE_JAVA` service environment values.
Explicit flags override environment defaults, and both runtime paths are
required together. The handshake exposes
`forgeRulesAvailable`, while room creation and public room projections carry
the immutable `rulesMode` (`manual` or `forge`). The server rejects Forge room
creation before publishing the room if its startup probe did not succeed.

Manabrew's Rust rules engine may become another backend later. Hexproof does
not adopt Manabrew's application UI, accounts, relay, or room service. All
backends implement the Hexproof-owned engine boundary so replacing or adding a
backend does not rewrite the Qt client or the public room protocol.

## Dependency direction

```text
Qt rules views
  -> typed WsClient rules commands
      -> hexproof.v1 rules envelopes
          -> Go rules-room coordinator
              -> RulesEngine interface
                  -> supervised Forge JSONL process
```

The process adapter owns process startup, bounded RPC, cancellation, stderr
capture, and shutdown. It does not understand WebSockets, rooms, spectators,
or QML. The rules-room coordinator maps authenticated seats to engine players,
requests viewer-specific state, and emits privacy-safe Hexproof projections.

## Engine process contract

The initial Forge backend uses the harness `--interactive-server` contract:

- `startGame` receives exact printing identities, player names, commanders,
  variant, starting life, and a server-generated seed;
- `getSnapshot` always specifies the authorized viewer index;
- `getPrompt` reads the current session prompt; the Hexproof coordinator
  validates its declared deciding player and projects it only to that
  authenticated seat;
- `submitAction` accepts the canonical prompt response for the authenticated
  deciding player;
- `getGameOver`, `endGame`, and `abortGame` close the lifecycle explicitly.

Only one goroutine may write a request and read its matching response at a
time because the upstream JSONL transport has ordered responses but no request
identifier. Calls have a deadline and bounded response size. A malformed
response, unexpected exit, or timeout makes affected Forge rooms unavailable;
it never falls back to manual mutation of a partially resolved game.

## State and privacy

Forge is authoritative for all rules-game state after `startGame`. Hexproof
stores only room membership, the engine session identifier, seat mapping, and
lifecycle metadata required for reconnect and cleanup. Private projections are
validated and sent without becoming a second authoritative state store.

The public `rules.snapshot` envelope is a Hexproof-owned normalized DTO. The
Forge adapter decodes the pinned harness shape privately, validates every
player reference, maps engine player indexes back to authenticated room seats,
and converts maps to deterministic arrays. Raw harness JSON never reaches the
WebSocket or QML layers. A shared room sequence is used for all viewer-specific
projections produced from one fan-out.

- A player's hidden zones and pending prompt are requested only for that seat.
- Spectators receive an explicit spectator projection; they never receive a
  player's raw engine snapshot as an implementation shortcut.
- Engine payloads and deck lists must not enter public logs, error details, or
  diagnostics.
- Hexproof validates room membership, seat ownership, request bounds, and
  prompt ownership before forwarding an action.
- The deciding player's `rules.prompt` exposes Hexproof-generated response ids;
  every other seated player receives an explicit `pending: false` projection
  and a generic waiting state without private decision details. `rules.respond`
  never accepts raw Forge action ids. The coordinator refetches the current
  private prompt under the room operation lock and maps the selected response
  back to the exact upstream action only after revalidating player, prompt id,
  family, and option.
- Reconnect obtains a fresh viewer projection and current prompt. It does not
  replay cached private frames.
- A spectator joining a running rules room immediately receives the explicit
  Forge spectator projection. A seated player departure aborts the engine game
  and returns the remaining room to the waiting gate; it never leaves an
  engine-controlled ghost player running.

## Availability and failure behavior

The server probes the configured Forge runtime during startup and exposes a
capability flag in the session handshake. Manual-room availability never
depends on Forge. Creating a Forge room is rejected with a stable availability
error when the runtime is absent or unhealthy.

An engine crash aborts only its active rules games, produces a public
non-sensitive termination reason, and leaves the hub able to host manual rooms.
The process supervisor may restart the runtime only for new games; it must not
attempt to reconstruct an in-progress game from Hexproof's manual reducer.

## Packaging

The Forge runtime, card scripts, license text, source offer, pinned revisions,
and third-party notices are a separate server runtime payload. The pure Go
`hexproof-server` binary remains usable without Java. Release and deployment
automation must either install the matching runtime payload or deliberately
run with Forge capability disabled.

Owner-operated deployment automation builds or reuses the pinned payload,
validates its revisions and checksum, stages all selected hosts, and installs a
persistent systemd environment drop-in. Activation remains a fleet transaction:
a failed probe, restart, or public health check restores the previous runtime
selection on every host activated by that invocation.

## Growth controls

- Keep `internal/rulesengine` independent from `internal/room`.
- Put Forge-specific wire DTOs under the Forge backend; expose normalized types
  at the package boundary.
- Do not add rules branches throughout the manual room reducer.
- Do not pass raw JSON through the WebSocket layer or QML.
- Split prompt presentation by prompt family instead of growing one universal
  QML dialog.
- Add another backend only through the engine interface and conformance tests.

## Delivery phases

1. **R0 — Runtime foundation:** licensing, pinned upstream revisions, build
   tooling, supervised process adapter, fake-runtime tests, and server health.
2. **R1 — Room lifecycle:** immutable room rules mode, server capability,
   exact deck handoff, start/abort, reconnect-safe normalized projection
   routing. Normal engine completion is connected with the first action loop
   in R2 so a final snapshot and result transition remain atomic.
3. **R2 — Core interaction:** typed state model plus mulligan, priority,
   choose-action, mana payment, targets, attackers, and blockers.
4. **R3 — Prompt coverage:** card selection, modes, numbers, colors, ordering,
   reveal acknowledgement, scry, damage assignment, replacement choices, and
   concede.
5. **R4 — Product hardening:** spectator projection, timers, engine failure UI,
   replay/diagnostics, packaging on supported server architectures, and
   end-to-end conformance games.

Each phase keeps manual mode green and ships only when owner, opponent, and
spectator privacy tests pass for every newly exposed state shape.

### Current implementation status

R0 and R1 are complete. The first R2 slice decodes `rules.snapshot` into a
typed Qt session with dedicated player, zone, visible-card, and stack list
models. Forge rooms use the established table geometry and visual hierarchy
through rules-specific presentation components: room/turn rail, shared stack
tray, viewer-relative battlefield lanes, local hand and zone dock, and a narrow
state rail. This presentation reuse does not connect Forge state to the manual
room reducer or expose manual mutation commands. QML never consumes raw harness
JSON or generic snapshot maps. Hidden library contents remain represented only
by normalized zone counts; only renderable battlefield, hand, graveyard, exile,
and command-zone card projections enter the card model. Forge prompts appear as
a decision layer over the battlefield without changing the underlying table
geometry.

R2 adds the private normalized `rules.prompt` projection,
authenticated `rules.respond` command, and typed Qt prompt state. The current
interactive families are first-player-roll acknowledgement, opening-hand
mulligan, London-mulligan put-back, priority/choose-action, mana payment, and
board targeting, attacker declaration, and blocker declaration.
Legal hand-card actions may be selected from the Forge prompt or by dragging
the card onto the local battlefield. A drop submits the matching normalized
action rather than mutating the projection; when Forge exposes multiple cast
modes for one card, the client asks the player to choose the exact mode.
The put-back family uses a dedicated card-selection component and the server
revalidates exact count, uniqueness, and membership in the current private hand
before constructing Forge's canonical response. Unknown prompt families are
shown as non-interactive soft errors and never expose raw backend JSON. Every
accepted response waits for Forge's asynchronous game thread to publish a new
prompt or terminal state before sending fresh viewer projections. A terminal
Forge snapshot is committed to the ordinary Hexproof result/return-to-room
lifecycle before the engine session is closed. Private prompt cards expose only
their object id and printable identity to the authenticated deciding player;
they do not expose rules text or raw engine state.

Board-target prompts use their own target-selection component. The server joins
each legal target against the deciding player's current viewer snapshot to add
only an already-visible player label or card identity. The client receives an
opaque `target:N` response id for each candidate; an optional `objectId` merely
echoes an id already present in that viewer's normalized snapshot for visual
highlighting and is never accepted as the response choice. Submission
revalidates the current minimum/maximum, uniqueness, candidate membership, and
cancellation permission before restoring Forge's canonical typed target
references.

Combat prompts use a separate typed assignment model and presentation. Every
attacker or blocker and every legal destination receives a prompt-local opaque
id. The deciding client submits only source-to-target pairs; it never receives
or returns Forge combat ids. The server refetches the current prompt, restores
the exact upstream ids, and rejects duplicate sources, illegal pairs, partially
satisfied minimum-blocker requirements, and assignments above Forge's maximum.
`must attack if able` and `must be blocked if able` remain visible hints rather
than absolute client constraints because multiple requirements can conflict;
Forge validates the complete declaration and may issue the next corrective
prompt. Card identities and player labels are joined only from the deciding
player's current normalized snapshot.

R3's first scalar-decision slice supports Forge
`chooseBoolean`, `chooseNumber`, `chooseColor`, and `chooseFromSelection`
prompts. Boolean labels, numeric bounds, color names, weighted totals, and
repeat permissions are normalized into dedicated protocol fields and typed Qt
models. Canonical response values and upstream indices remain server-owned:
the client submits only an in-range number or prompt-local `choice:N` ids, and
the server refetches the current prompt before reconstructing the exact
boolean, color-count map, or ordered selection indices. The Qt table uses
separate scalar-choice and number components rather than extending the action,
card, target, or combat views.

The second R3 slice now supports general Forge `chooseCards` prompts.
Candidates are normalized to the same minimal private printable identity used
by the London put-back flow, but use distinct card-selection minimum and
maximum fields so they cannot be confused with board-target cardinality. The
deciding client can submit any unique candidate set within that range,
including an empty set when Forge advertises an optional choice. The server
refetches the prompt and revalidates the range, uniqueness, and membership
before reconstructing the canonical `chooseCardsDecision`; no rules text or
unrelated engine card state crosses the WebSocket boundary.

The third R3 slice supports Forge `reorder` prompts for both cards and
simultaneous triggers. The server replaces every upstream item id with a
prompt-local `order:N` id and exposes only printable card identity plus bounded
trigger text. The typed Qt order model feeds a dedicated draggable presentation
whose first item is explicitly the first/top object. A response must contain
every current item exactly once; the server refetches the prompt and restores
the canonical item ids only after validating the complete permutation.

The fourth R3 slice supports Forge `revealCards` prompts. Only the authenticated
deciding player receives the bounded printable identities supplied by the
current disclosure; the prompt deliberately omits its upstream zone and owner
references. A dedicated read-only card strip accepts only `$ack`, including
Forge notification-only disclosures with no cards. The server refetches the
current prompt and reconstructs exactly `revealCardsAcknowledged`; selections,
foreign owners, stale prompt ids, and any other response are rejected.

The fifth R3 slice supports Forge `scry` prompts, including the same generalized
destination shape used for surveil and wider card sorts. Every upstream card id
is replaced with a prompt-local `scry:N` id before the deciding player receives
its printable identity and allowed destination list. The dedicated Qt
presentation partitions cards among those destinations and orders each pile.
Submission must repeat the exact destination sequence and place every current
card exactly once; the server refetches the prompt and restores canonical ids
only after validating that complete partition and ordering.

The sixth R3 slice supports both Forge combat-damage prompt families. Damage
assignment order exposes the complete current assignee list as prompt-local
`damage-target:N` ids and requires an exact permutation. Exact combat-damage
assignment additionally exposes the available total, deathtouch state, and a
lethal-damage threshold derived from the deciding player's current normalized
snapshot; the final defender has no threshold. The dedicated Qt presentation
offers incremental, reset, and automatic allocation while preventing damage to
a later assignee until every earlier assignee has lethal damage. The server
refetches both the private prompt and viewer snapshot, requires every current
target exactly once and every available damage point, revalidates sequential
lethal thresholds, and only then restores canonical Forge assignee ids.

The seventh R3 slice preserves the additional presentation context used by
replacement effects, optional prevention payments, optional triggers, and
related boolean decisions. The server normalizes an optional source card to a
display-only `context-card:N` identity, joins affected cards and players to the
deciding viewer's current snapshot under `context-target:N` ids, and bounds the
supplemental effect text. The Qt prompt layer renders that source, effect text,
and affected-object strip beside the existing typed confirm/deny choices.
These context ids are never accepted as response choices; the server still
refetches the private prompt and reconstructs only the existing typed boolean
or selection response.

The eighth and final R3 slice adds Forge concession without treating it as a
prompt answer. The existing authenticated `game.concede` command is translated
to the pinned harness's canonical out-of-band directive for the actor's mapped
engine player. The server first confirms that player's current Forge status,
waits until the asynchronous engine thread publishes `conceded` or `lost`, and
then refreshes owner, opponent, and spectator projections. In multiplayer
Commander, a non-terminal concession leaves the engine session active and
refreshes the prompt for the remaining players. When Forge reports game over,
the server closes the engine session and commits a `concede` result through
the ordinary score and return-to-room lifecycle. The Qt action rail shows
Concede only for an active local player and requires explicit confirmation.

Forge rooms are currently normalized to BO1. Engine-aware sideboard restart is
the next product-hardening slice; silently handing a second game to the manual
reducer would violate the authority boundary. R2 and R3 are complete; R4 is in
progress.
