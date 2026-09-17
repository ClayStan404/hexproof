# Rules-engine integration

This document defines the architecture for Hexproof's optional enforced-rules
mode. It supersedes the former product-wide prohibition on a rules engine while
preserving the existing manual tabletop as a first-class mode.

## Current delivery scope — 2026-09-15

The owner limits the new UI and further rules integration to **1v1 games**:
ordinary two-player formats and **Duel Commander**. Each game has two players;
spectators and participants in a larger tournament are not additional game seats.

Multiplayer Commander/EDH is **out of scope**, not deferred work. Do not require
three/four-player layouts, multiplayer priority rotation, or continuation after
a non-terminal player elimination for this delivery. Duel Commander still
requires its native commander designation, command-zone, casting, payment, and
match-flow interactions. Apply the selected format's native rules; excluding
multiplayer EDH does not remove the commander support needed by Duel Commander.

This scope supersedes earlier multiplayer EDH delivery requirements. Existing
EDH capabilities and dated verification below describe prior implementation;
this documentation update does not claim that those runtime paths have been
removed or disabled. See [the UI redesign](forge-ui-redesign.md) for the current
presentation plan.

## Product modes

Every room chooses one immutable gameplay mode:

| Mode | Authority | Intended use |
|------|-----------|--------------|
| `manual` | Hexproof room reducer | Existing free-form tabletop and unusual interactions resolved by players |
| `forge` | Forge rules runtime, hosted by the server or consenting room creator | Rules-enforced games with legal actions, priority, stack resolution, triggers, and state-based actions |

Manual rooms continue to use the current `game.*` commands and projections.
Forge rooms use a separate command and projection family. The two reducers must
not mutate the same live game, and a room cannot change mode after creation.

Forge rooms additionally choose immutable `hostingMode`: `server` (also the
omitted default) or `player`. Player hosting is optional trusted-host play for
1v1, including Duel Commander and BO3. Public tournament rooms always use
server hosting. Creation/listing/joining disclose the mode; joining a hosted
room, including as spectator, requires `acceptPlayerHost: true`. See
[player-hosted Forge](player-hosted-forge.md) for its protocol, lifecycle,
preparation, trust limits, and verification.

## Runtime choice

Official Forge is the production rules backend. Hexproof's native-human
adapter reuses Forge's human controller and input queue without opening
Forge's desktop UI. The old Manabrew adapter, local selector, and packaging
path have been retired; see `forge-native-migration.md` for evidence.

The official source pin includes reviewed downstream changes recorded in
`native-host/native-hooks.patch`. Besides GUI metadata and isolated profiles,
adapter revision 2 repairs Backup Plan's unused-hand shuffle and native
multiplayer decision cancellation, chooser handoff, and priority advancement.
These changes stay in Forge's native lifecycle; Go and Qt do not implement
replacement game rules. Each change requires a reproducible native regression
and corresponding-source provenance.

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

The 2026-09-09 [backend evaluation](rules-backend-evaluation.md) retains Java
Forge after source inspection, local builds, and real-game tests of XMage,
Manabrew Rust, Phase, and mtg-forge-ts. The pinned host includes explicit,
reproducible Hexproof patches; upgrading the upstream version alone is not the
complete runtime contract.

The historical candidate evaluations do not enable additional production
backends. Hexproof's engine boundary separates the runtime from the Qt client
and public room protocol.

## Dependency direction

```text
Qt rules views
  -> typed WsClient rules commands
      -> hexproof.v1 rules envelopes
          -> Go rules-room coordinator
              -> forge.Runtime interface
                  -> local supervised Forge JSONL process
                  OR
                  -> private authenticated engine WebSocket
                      -> desktop Go helper -> local Forge JSONL process
```

The process adapter owns process startup, bounded RPC, cancellation, stderr
capture, and shutdown. It does not understand WebSockets, rooms, spectators,
or QML. The rules-room coordinator maps authenticated seats to engine players,
requests viewer-specific state, and emits privacy-safe Hexproof projections.

## Engine process contract

The initial Forge backend uses the harness `--interactive-server` contract:

- `startGame` receives exact printing identities, player names, commanders,
  variant, starting life, a server-generated seed, and an optional explicit
  starting-player index for later games or a host restart;
- `getSnapshot` always specifies the authorized viewer index;
- `getPrompt` reads the current session prompt; the Hexproof coordinator
  validates its declared deciding player and projects it only to that
  authenticated seat;
- `submitAction` accepts the canonical prompt response for the authenticated
  deciding player;
- `getGameOver`, `endGame`, and `abortGame` close the lifecycle explicitly.

By default each game receives a fresh process, including restart and the next
game of BO3. JSONL input and output are explicitly UTF-8, independent of the
operating system's console encoding, in both dedicated and shared workers.
This ordered JSONL transport allows one outstanding call. Operators
can explicitly select adapter 3's shared workers with `-forge-games-per-jvm 2`
(valid range 1–4; 1 retains dedicated processes). Shared requests carry positive
monotonic request IDs; different games may complete out of order while each
game lease remains serial. The startup probe must acknowledge the shared
protocol and exact capacity; an older runtime is rejected.

Each shared game owns its dispatchers, random source, object-ID counters,
mutable counter/UI-card caches and failure handler. Waiting inside one game's
synchronous menu must not block another game's input. Closing a game releases
choices, interrupts native waits, cancels timers and waits for tasks to stop
before its slot can be reused. A worker retires after 64 leases or one idle
minute. FModel's card database and immutable resources remain shared.

Requests, queues, response sizes and deadlines remain bounded. An ordinary
game exception or invalid projection invalidates only that lease. A malformed
transport, unknown response ID, in-flight timeout, fatal exit/OOM or native
cleanup that does not terminate invalidates every lease in that worker. The
blast radius is bounded by its configured 2–4 games. No uncertain mutation is
retried on a different JVM; affected games use the existing aborted-game flow.
Neither mode falls back to manual mutation of a partially resolved game.

The host constructs immutable per-viewer publications on the game thread at
stable decision boundaries and termination. RPC readers never traverse live
mutating Forge collections. An out-of-turn concession republishes the updated
views even when the original decision remains pending. Terminal and failed
game threads cannot leave an actionable stale prompt. Requested initial life
overrides the variant default without discarding Commander rules.

## State and privacy

Forge is authoritative for all rules-game state after `startGame`. Hexproof
stores only room membership, the engine session identifier, seat mapping, and
lifecycle metadata required for reconnect and cleanup. Private projections are
validated and sent without becoming a second authoritative state store.

The public `rules.snapshot` envelope is a Hexproof-owned normalized DTO. The
Forge adapter decodes the pinned harness shape privately, validates every
player reference, maps engine player indexes back to authenticated room seats,
and converts maps to deterministic arrays. Raw harness JSON never reaches the
ordinary player/spectator WebSocket or QML layers. The dedicated engine
connection carries privileged bundled publications between the helper and hub;
it cannot join as a player or bypass seat authorization. A shared room sequence is used for all viewer-specific
projections produced from one fan-out.

Each player also carries a `commanders` array (empty for ordinary decks).
Entries contain the public designation `name`, native command-zone `casts`,
and native `tax` surcharge before other cost adjustments. Optional `objectId`
and `zone` are joined only to an identity-visible card in that viewer's current
zones or stack. Otherwise `objectId` is absent and `zone` is `hidden`; the
summary cannot reveal a hidden hand object, face-down identity, or non-top
library card. Independent commanders retain independent cast histories. These
fields are read-only and reset with a fresh engine game. The Duel table shows
both players' summaries and routes offered commander actions through the same
opaque action controls as other cards. Forge's payment prompt determines the
final payable cost.

Snapshot step names use the existing rules-table phase keys (`main1`,
`begin_combat`, `declare_attackers`, `declare_blockers`, `combat_damage`,
`end_combat`, `main2`, and `end`, alongside the unchanged beginning/cleanup
steps). First-strike and ordinary combat damage share the `combat_damage`
display category only; Forge still resolves their distinct rules steps.

- A player's hidden zones and pending prompt are requested only for that seat.
- Spectators receive an explicit spectator projection; they never receive a
  player's raw engine snapshot as an implementation shortcut. The existing
  immutable `spectatorsSeeHands` opt-in may overlay current hand zones only
  from their authorized owner projections. It never overlays libraries,
  sideboards, prompts or face-down battlefield identities. Public journals
  always use the original hand-hidden spectator projection, even in these rooms.
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
- Public prompt ids are allocated monotonically by the hub and mapped to the
  current session's private engine prompt id. Repeated publications of the same
  decision retain that public id; a new game, restart or replacement JVM gets
  new ids even if Forge starts its local prompt counter at one again. Late
  responses from an earlier game cannot answer a decision in its replacement.
- Reconnect obtains a fresh viewer projection and current prompt. It does not
  replay cached private frames.
- A spectator joining a running rules room immediately receives the explicit
  Forge spectator projection. A seated player departure aborts the engine game
  and returns the remaining room to the waiting gate; it never leaves an
  engine-controlled ghost player running.

## Multi-game matches and review

Generic 1v1 and Duel Commander rules rooms support BO1 and BO3. Multiplayer EDH
remains BO1. BO3 is first to two wins, not an unconditional three-game limit;
drawn games do not add a win. Between games the existing five-minute sideboard
gate applies: registered mainboard/sideboard cards only, owner-private pending
partitions, all-ready early completion, and timeout fallback to the previous
committed partition. Duel Commander permits commander redesignation but no
card movement. The previous game's loser starts; after a draw Forge selects
the first player normally.

Every next game is a fresh Forge session built from the committed deck
partition. The manual zone initializer is never called for a rules room.
`game.snapshot` supplies only the existing typed match number, score, result,
owner-authorized sideboard and public-log metadata; live cards, life, phases,
actions and prompts remain exclusively in `rules.snapshot` / `rules.prompt`.
This metadata shell does not create a second rules reducer. Spectators see
readiness/counts, not pending sideboard identities.

The host may explicitly restart a live game after confirmation. It preserves
game number, score and original starting player while using a fresh session,
shuffle and opening hand. Restart is unavailable during sideboarding or after
the match result. If a new/restarted session cannot start, members remain in
the waiting room with readiness cleared and a non-sensitive failure message.

The final result offers Stay for public-board review/chat and Return to room.
Return is unavailable between BO3 games; after a finished match it archives the
public journal and restores the original registered deck partitions. Review
does not allow further rules responses or restart. Reconnect into sideboarding
or finished review restores metadata without recreating a completed engine.

## Public activity, chat and replay

The hub derives a bounded public journal from explicit spectator publications:
game/turn/phase boundaries, life/status changes, public zone and tap changes,
hidden-zone count changes without identities, generic stack activity, and
results. It does not infer a cast or resolution from a button click, scrape a
private prompt, or append raw engine text. Face-down spell/casting projections
also remove printing metadata and use a public placeholder; face-down casting
modes have a distinct label in the owner's private action list.

Players and spectators can use the existing `game.say` command during play,
sideboarding and finished review. The hub validates membership and text and
broadcasts only metadata; chat does not query or wake the rules engine. The
client uses the existing scrollable public log/chat rail.

Journal ids remain monotonic through BO3 games and restarts. A new match resets
them. The existing limits apply: 10,000 retained entries and the newest 500 in
live projections, with explicit prefix-truncation metadata. Interrupted games
can also retain their already-public observations, without reconstructing or
fetching private Forge state for an archive.

The existing `replay.list` / `replay.get` flow exposes public match metadata and
this journal only. This API remains for compatibility after removal of the
client replay browser/viewer; it is not deterministic engine replay or
hidden-state board reconstruction. Existing retention TTL,
byte/file bounds and private archive permissions remain in force.

## Availability and failure behavior

The server probes its configured Forge runtime and exposes
`forgeRulesAvailable` in the session handshake. `playerHostingAvailable` is an
independent operator permission: relaying player-hosted rooms requires no Java
on the hub. Manual-room availability never depends on either capability.
Server-hosted room creation requires the local runtime; player-hosted creation
requires the relay permission. The latter starts only after the creator's helper
connects. Normal commands cannot supply executable paths or runtime downloads.

An engine crash aborts its active rules game(s), produces a public
non-sensitive termination reason, and leaves the hub able to host manual rooms.
The process supervisor observes actual child termination, not only the next
player action. It returns the rules room using that process to `waiting`,
retains membership and selected decks, clears readiness, and reports a fixed
non-sensitive failure. Authoritative-query/projection failures invalidate the
runtime; ordinary rejected actions and unsupported-deck startup do not abort
unrelated games.

A subsequent new game acquires an isolated lease on demand. Concurrent cold
startups are serialized and failed startups have a short retry cooldown. Normal
completion and abortion reap the dedicated process or acknowledge shared-game
cleanup before releasing its slot. Server shutdown also reaps idle shared
workers and children still starting a game.
Server-hosted games have no automatic reconstruction or background restart
loop. Old-process cleanup cannot reset a game on its replacement.

For server hosting, the hub also enforces an operator-configured Forge capacity before spawning a
process. `-max-forge-games` overrides `HEXPROOF_FORGE_MAX_GAMES`; the default is
one. Both CLI and environment values must be positive integers. Cold startup
and closing leases consume capacity until native cleanup is acknowledged (or
the dedicated/failed process has been reaped). BO3 sideboarding and host
restarts retain the match's slot during cleanup, so another room cannot
interrupt an ongoing match by taking its place. `-forge-games-per-jvm` controls
grouping, not the total game admission limit or a guarantee of memory usage.
Heap/process limits still need to fit the operator's host budget.
An abandoned match, failed transition, or completed match releases its slot.

If all slots are occupied, a new match returns the existing `server_limit`
error before starting Java. Its room returns to `waiting` with seats and decks
preserved and readiness cleared; players can ready again after capacity is
available. Capacity rejection does not disable the Forge capability, trigger
the runtime-failure cooldown, or affect existing games and manual rooms.
Waiting rooms consume no Forge slot. The limit applies to one hub process;
separate services sharing a host need a combined memory budget.

Without a connected approved backup, player-hosted games use the same aborted-game flow on engine loss or expired
transport grace, with `player_host_lost` instead of a fabricated winner. A
surviving helper can reconnect within the bounded grace; new decisions pause
while it is offline. Adapter 4 supports explicitly approved backup hosts and
verified reconstruction through a bounded private operation journal; see
[the migration contract](player-hosted-forge.md#verified-host-migration-adapter-4).
Unsupported positions or a failed replay keep a healthy original, or use the
existing aborted-game flow after loss. They never create a winner. Remote
bindings have a separate capacity and do not consume server JVM slots.

## Packaging

The Forge runtime, card scripts, license text, source offer, pinned revisions,
and third-party notices are a separate runtime payload. The pure Go
`hexproof-server` binary remains usable without Java. Release and deployment
automation must either install the matching runtime payload or deliberately
run with Forge capability disabled.

Desktop packages also contain the native Go `hexproof-forge-host` helper.
Players who volunteer as the initial or backup host download the pinned Forge payload and
platform-specific Temurin JRE 21 into private, versioned application storage.
Other players and spectators need neither Java nor Forge. The helper verifies
archives, extracted engine files and Java files, probes startup, and installs
repairs into a new immutable generation. Client builds now require the pinned
Go toolchain as well as Qt/C++, Python 3.12+ and JDK 21+ for the bundled adapter
overlay; release/CI jobs select the matching tools. Joining players need no JDK.

`tools/run-local-forge-server.sh --prepare` builds and starts the local optional
runtime. It validates the full pin/patch manifest and required resource files,
and preserves mismatched existing installations. It neither installs system
packages nor changes production defaults.

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

The owner-requested replacement UI now presents real two-seat Forge sessions;
see [the Forge table redesign](forge-ui-redesign.md). `ForgeDuelTable` uses the
existing typed session, native prompts, and WebSocket response path. Its geometry
is independent of the manual table. Existing rooms with more than two seats
retain `RulesLegacyLayout`; that compatibility path does not extend the current
delivery scope to multiplayer EDH.

R0 and R1 are complete. The first R2 slice decodes `rules.snapshot` into a
typed Qt session with dedicated player, zone, visible-card, and stack list
models. Two-seat rooms use opposed creature lanes, left-side lands and other
permanents, a bottom fanned hand, and a right-side stack and decision dock.
The view does not connect Forge state to the manual room reducer or expose
manual mutation commands. QML never consumes raw harness
JSON or generic snapshot maps. Hidden library contents remain represented only
by normalized zone counts; only renderable battlefield, hand, graveyard, exile,
and command-zone card projections enter the card model. Two-seat Forge decisions
occupy a reserved area beside the local hand. Ordinary priority uses a compact
action bar; specialized choices expand upward within a bounded, scrollable
decision area. The stack is displayed newest-first above it and scrolls
independently. The native stack and normalized array are top-first. Each entry's
optional `targets` array contains read-only `{kind, label, objectId?, seat?}`
relationships for cards, players and spells, including native sub-instance
targets. The host omits hidden or departed card objects; the server rejoins each
reference against the same viewer's zones, stack or mapped players. Anonymous
public objects retain an ID with an empty label. Neither target relationships
nor their IDs grant visibility or authorize a rules response.

The stack exposes a target button for every published relationship. Selecting
one scrolls to and highlights the exact battlefield or stack object, or highlights
the mapped player; visible cards in other zones open their existing inspection.
The selected relationship has an arrow while both endpoints are in their scroll
viewports. The default relationship is the first target of the top entry.
Scrolling never substitutes a different same-name card. Selection resets on new
prompts, game changes, disconnection, sideboarding and viewer-seat changes.
Targets are read from native metadata, independently of current target-selection
prompts and without parsing rules text. The Settings drawer retains phase
stops and match controls. Public-zone browsing opens on demand; command-zone
buttons and tabs appear only in Duel Commander. Zone headings use the server's
zone counts, independently of how many card identities are disclosed. Both
player plates show hand and library counts, including updates within one turn.
Library counts never expose private library contents, and the library browser
explains that its contents are hidden instead of presenting an empty library.

Hover and keyboard-focus inspection show a full card beside its source, flipping
left near the window edge and staying within the viewport. This read-only overlay
does not intercept targeting or combat input, open the fixed inspector, or move
the battlefield. Modal decisions and authority loss hide it. Explicitly pinned
card state and log/chat open on demand in a separate right-side column. The
stack and decision dock shift beside it, keeping lands, other permanents and
decision controls accessible. Closing the column restores the battlefield's
width; transient hover inspection does not reserve any column. The resting
hand exposes approximately its upper half at the bottom of the window, retaining
stable visible click/drag slots and horizontal scrolling for unusually large
hands. Battlefield grids choose readable card sizes from both available width
and height; lands and other permanents share vertical space according to their
counts. Extreme boards retain scrolling and exact-object keyboard/target reveal.
The compact top row combines the turn owner, turn number, phase and game/log
controls. Decision instructions remain in the right dock rather than occupying
a second banner above the battlefield. The turn label and active-player border
use `activeSeat`, independently of the current priority holder. The legacy
layout keeps its separate allocation.

Known Forge decision headings, common choice labels and engine-authored prompt
templates use the client's selected language through `RulesText`. Play/draw
labels mean first/second player only in the native starting-player question.
Unrecognized effect text, inserted card/player names and mana symbols remain
literal. Localization changes presentation only: prompt/choice IDs and response
payloads retain their original values, including after an in-place language change.

Background card-image preparation is released by a current snapshot from the
room's selected mode. A manual snapshot cannot release a Forge load or vice
versa. A coalesced visible-card batch additionally prioritizes only normalized
authorized identities from the current Forge game, including spectator-visible
cards and private prompt cards for their owner. It deduplicates exact printings
and uses the existing incremental catalog queue; delegates remain cache-only.
Leaving the room invalidates queued readiness and visible-card work. No card
identity is inferred from a hidden count, object id, or descriptive text.

R2 adds the private normalized `rules.prompt` projection,
authenticated `rules.respond` command, and typed Qt prompt state. The current
interactive families are first-player-roll acknowledgement, extra starting-hand
selection, opening-hand mulligan, London-mulligan put-back, priority/choose-action,
mana payment, board targeting, attacker declaration, and blocker declaration.
Legal cards on the table are the primary action controls. Clicking a highlighted
hand card plays a land or casts it; clicking a highlighted permanent activates
its ability, including a mana ability during payment. One legal action submits
directly; multiple actions open a chooser for that card. Space and Return perform
the same action on a focused card. Legal hand cards can also be dragged onto the
local battlefield. A click or drop submits the matching normalized action rather
than mutating the projection. Actions without a directly operable table object,
including plays from other zones, remain available in the decision dock.
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

Backup Plan uses Forge's actual `InputChooseStartingHand` before mulligans.
The existing boolean decision presents **View next hand** and **Keep this hand**;
viewing advances cyclically through the native extra hands and publishes a new
prompt with the hand index and the owner's current hand. Other players and
spectators receive no private hand identities or candidate list. Keeping a hand
lets Forge return every unused hand to the library, shuffle once after those
cards have returned, and continue to the ordinary mulligan decision. The host
resolves Conspiracy printings from the native variant-card database when needed
and assigns them to `DeckSection.Conspiracy`, separate from the main library.

Qt correlates an outstanding response with its request, game, and prompt.
All response paths, including hand-card drops, share the pending guard. A
transport acknowledgement or duplicate snapshot of the same decision does not
permit a second answer; a new decision, a matching error, a bounded timeout,
game termination/change, or disconnect releases the guard. Priority controls
remain in the bottom action bar; specialized decisions pin their basic payment
and cancellation responses above their scrolling body. Long spell and ability choices have
bounded widths and wrapped labels, with a scrollbar and keyboard-focus reveal
when they overflow. Scrolling ability choices or prompt context does not move
the basic responses out of view.

Smart priority is enabled by default for the deciding player's `chooseAction`
windows. With an empty stack it skips upkeep, draw, end of combat, cleanup,
other players' main phases, and the user's own end step unless a stop is set.
The user's main phases, combat response windows, and other players' end steps
remain action points. It normally passes the user's response to a stack made
entirely of their own spells/triggers. Unknown or mixed stack ownership does not
qualify. Full control, explicit phase stops, and held response windows override
these defaults; users need one of those controls for special upkeep, own-end-step,
or own-spell response timing.

At the remaining action points the client can also pass when the private prompt
explicitly carries `autoPassEligible: true`. Missing hints retain control at
those points. The native host examines all abilities of the same exposed cards
admitted by native selection, including non-hand zones.
Mana abilities alone do not require a stop. Forge's predictive payment check can
also rule out ordinary costs using ordinary basic lands. This is a conservative
hint: floating mana, alternative or optional payments, complex mana sources,
uncertain target chains, exceptions, and expired computation budgets prevent
that hint from approving a pass. It is not a new client-side implementation of
MTG costs.
The hint is sent only to the deciding player and never changes the legal options.

The action bar offers **Next / Resolve**, **Full control**, and a **Pass…** menu
for passing until a response, for the rest of the current turn, or through the
current stack. Full control disables automatic passing and remains active across
casting, target selection, and payment. The phase rail exposes separate stop
toggles for the user's turns and other players' turns. A stop pauses the first
priority window in that phase; explicitly continuing acknowledges that phase
only, so the stop applies again on a later turn. Stops cannot create a priority
window in untap or another engine step that does not grant one.

Continuous modes send individually validated `$pass` responses. Stack and
response modes stop when a new stack-instance id appears; stack mode also ends
when its original stack is empty. Every mode ends at a turn/game/seat boundary
and respects phase stops. Required decisions remain manual and end a continuous
mode. User cancellation and a new response opportunity hold the next local
priority even when it would otherwise be eligible for automatic passing.
Disconnection, sideboarding, loss of seat, and game completion clear transient
automation. Modal controls and action choosers suspend it. Duplicate publications,
errors, and response timeouts never automatically retry an already answered
prompt. Space continues from the table when no child control handles the key;
card activation and text entry retain their own Space behavior. Escape first
cancels continuous passing, then closes inspection.

Priority and phase publications update snapshot rows by stable object identity.
Unchanged battlefield, hand, player and stack delegates retain their artwork,
focus and scroll state; insertions, removals and changed public or private fields
are applied immediately. A room or game change still clears the previous state.
During a continuous pass, the action bar keeps its status, full-control and
cancel controls in a stable layout. Per-window pass buttons and optional action
lists return when continuous passing ends; required decisions remain immediate.

Battlefield cards visibly show the projected power/toughness, marked damage,
counters, and attachment status. Player plates include public counter and mana
summaries. Hovering a visible card, or keyboard-focusing a battlefield or stack
object, shows a larger image and read-only details in the inspector, subject to
the specialized-decision hover suppression described above. Clicking an inactive card pins it; other hover previews temporarily
replace it and leaving restores the pinned card. Closing clears the inspection.
For an actionable card, left click performs the current action; right click pins
inspection without submitting a response. A layout drag must not activate or
select the card. The inspector uses the full cached image rather than the tabletop thumbnail.
It refreshes with snapshots and clears when the object is no longer visible or
the game changes. Hidden identities are never looked up in the catalog; a face-down permanent may still show its public game state. Cached
printed card art is labeled separately and is not presented as the engine's
current abilities or rules text.
Counter summaries render native stat names as symbols such as `+1/+1` and
localize common named counters such as Lore and Energy. Unknown names remain
visible, and this display mapping does not change wire values or mana pools.

Battlefield presentation groups projected creatures toward the combat center,
lands toward the player's outer edge, and other permanents beside the lands;
opponents mirror the arrangement. Current projected power/toughness takes
precedence over cached printed types, so animated lands occupy the creature row.
Unknown or hidden printed types receive a neutral placement without an identity
lookup. The new two-seat view uses art-focused cards with public state overlays
and a visible tap mark. The legacy view reserves room for rotated tapped cards.
Crowded lanes scroll. Legacy short lanes use smaller card footprints and compact zone-count
footers so ordinary creature and land rows remain visible. When even the minimum
card size cannot fit, the initial scroll position prioritizes the creature row.
Public zone docks have their own footer space.

In the legacy layout, dragging a permanent changes only this viewer's local
arrangement, never card zones, controller, tapping, or other Forge rules state. Positions survive snapshot
refreshes and resize proportionally within the lane. Departed objects, changes of
controller, and a new game discard the relevant saved placement. **Auto arrange**
restores a lane's default grouping. The last moved permanent stays above overlapping
cards, and a click selects only the top card. These positions are session presentation state
and are not synchronized to other players or stored as manual-table commands.
The new two-seat layout uses automatic grouping and stable card slots. It
supports dragging a legally playable hand card onto the own battlefield, using
the current Forge action; permanent dragging does not issue gameplay commands.

Combat prompts share opaque source/target assignments between the two-seat
board and the existing assignment controls. Click an attacker to toggle its
single native destination. With multiple destinations, select the attacker and
then a legal player plate, planeswalker, or battle. Combat player targets carry
an optional authenticated room `seat`; missing seats retain the dock fallback.
Select a blocker and then eligible attackers up to its native capacity.
Arrows show visible selected relationships; clipped objects do not acquire
invented positions. All choices also remain available in the native assignment
controls. Submission uses their
normal validation and explicit declaration button. New prompts, game changes,
disconnection, sideboarding, and changes of viewer authority clear local choices.

The hand strip also exposes a horizontal scrollbar and wheel scrolling when
cards overflow, without replacing the legal hand-card drag action.

Horizontal decision lists for combat, cards, targets, ordering, damage, scalar
choices, reveals, and scry expose a scrollbar whenever candidates overflow.
Mouse wheels and touchpads navigate those lists horizontally; the scrollbar has
its own strip below the candidate controls. Focused controls are brought into
view. Tab and Shift+Tab traverse combat assignments beyond the initial viewport,
while declaration and confirmation actions remain outside the scrolling list.
Card and target selections also accept Space or Return when focused. In nested
scry lists, one wheel event moves the inner cards or, at their boundary, the
outer destination piles; it must not scroll both levels at once. Reveal cards
remain passive content, with keyboard scrolling available on the list.

Board-target prompts share one selection controller between the table and the
decision dock. Legal cards and stack objects are highlighted in place, and player
targets highlight the corresponding player plate. Clicking a target submits
immediately when the maximum selection is one; multiple targets toggle and use a
final confirmation in the dock. The dock retains candidates outside the current
table view, legacy player candidates without a seat, and ambiguous mappings. It
does not duplicate directly selectable objects. Every publication of a prompt,
including a repeated id, clears local selections; so do disconnection, loss or
change of player seat, sideboarding, and game changes. Responses recheck current
membership and share the existing pending-response guard.

The server joins
each legal target against the deciding player's current viewer snapshot to add
only an already-visible player label or card identity. The client receives an
opaque `target:N` response id for each candidate; an optional `objectId` merely
echoes an id already present in that viewer's normalized snapshot for visual
highlighting and is never accepted as the response choice. Player candidates may
also carry an optional normalized `seat`; clients never infer this mapping from a
name or label. Card and spell mappings are distinguished by target kind. Submission
revalidates the current minimum/maximum, uniqueness, candidate membership, and
cancellation permission before restoring Forge's canonical typed target
references.

Combat prompts use a separate typed assignment model and presentation. Every
attacker or blocker and every legal destination receives a prompt-local opaque
id. The deciding client submits only source-to-target pairs; it never receives
or returns Forge combat ids. The server refetches the current prompt, restores
the exact upstream ids, and rejects duplicate source-target pairs, illegal
pairs, partially satisfied minimum-blocker requirements, and assignments above
Forge's maximum. Attackers have one destination. A blocker may have several
distinct attackers when its native assignment limit permits it. The native
`blockerAssignmentLimits` array must contain exactly one explicit nonnegative
limit for every available blocker; missing, duplicate, or out-of-range metadata
is rejected, rather than inferred from printed card text. The public optional
`combatSources.maxAssignments` field carries this limit, including an explicit
zero. A client receiving an older prompt without the field defaults to one.
Qt presents multiple target checkboxes and a selected/maximum count for a
blocker whose limit exceeds one; deselection remains available at the limit.
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
Native cross-zone target menus omit Forge's presentation-only zone headings
from legal responses. Pure card lists use this card picker with printable
identities; mixed lists retain the explicit finish-targeting action and the
original candidate objects. Selecting a section title must never restart the
same target prompt.
Standard native card-list inputs reuse the official `setSelectables` minimum
and maximum so multi-card decisions can be submitted as one complete batch.
Native subclasses with additional selection constraints keep their own
incremental validation and do not auto-confirm after the first click.
Native cost inputs also preserve Forge's cancellation permission. Only a
`chooseCards` prompt with `cancellable: true` offers Cancel; `$cancel` carries
no selected cards and returns to the native cancellation/rollback path.
Mandatory selections and London put-back cannot gain cancellation from a
client-supplied response.
The 1v1 Qt browser filters only this current candidate set. Filtering does not
change selected identities, native cardinality or cancellation permissions;
selected cards remain available through a selected-only view. Prompt replacement
and loss of the deciding seat clear its transient state.

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
references. A dedicated read-only card view accepts only `$ack`, including
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

The native human controller exposes scry as this complete two-pile decision,
including scry 1 and retaining multiple cards on top. The 1v1 table presents
scry and order decisions in a centered card dialog with visible reorder buttons
and position numbers; the compact decision dock does not duplicate those inputs.
Cleanup discards use a complete exact-count card choice, including discarding
several cards at once; selected cards do not disappear into an incremental
native input between confirmations.

Native registration includes the player's current sideboard as a separate Forge
deck section. Wish effects such as Karn, the Great Creator operate on that real
section; sideboarding between games supplies the revised sections. Sideboard
identities are never part of ordinary opponent/spectator publications. Only
native selection/reveal decisions grant their intended temporary visibility.

Token printings use the edition's explicit token set code and collector number,
not the parent set's ordinary-card numbering. Named token suffixes used only by
Forge are normalized for the catalog; copied ordinary cards retain their actual
printing. Battlefield cards may expose `exiledCardCount` and `exiledCardIds` for
cards still exiled with that exact native object. The count includes face-down
cards, while links only join identities authorized in the viewer's current
exile projection. Board badges distinguish identical permanents; inspection
shows linked names or anonymous counts. Leaving exile removes the relationship.

The sixth R3 slice supports both Forge combat-damage prompt families. Damage
assignment order exposes the complete current assignee list as prompt-local
`damage-target:N` ids and requires an exact permutation. Exact combat-damage
assignment additionally exposes the available total, deathtouch state, and a
lethal-damage threshold; the final defender has no threshold. Native prompts
carry `blockerDamageHints` bound to the complete current blocker candidate set.
Their engine-computed thresholds include damage already assigned by other
combatants and effects such as Zilortha's power substitution. The server rejects
missing entries, duplicate or foreign ids, and thresholds outside `0..100000`,
then publishes the value only after its ordinary viewer-visibility check.
Missing native hints are rejected; Hexproof does not reconstruct thresholds
from printed toughness or marked damage. The typed
`damageAssignmentMode` carries Forge's current dialog constraints: `ordered`
requires lethal damage before later assignees, `unordered` allows any split
between blockers while still requiring lethal damage to all blockers before
the defender receives damage, and `divideFreely` permits the native exception
without either lethal gate. The native host derives this mode from Forge's
actual order override and divide-damage flags. Missing or unknown native modes
are rejected. The public v1 field remains optional for wire compatibility, while
the supported native runtime always supplies its mode. The dedicated Qt presentation
offers incremental, reset, and automatic allocation under that mode. The server
refetches both the private prompt and viewer snapshot, requires every current
target exactly once and every available damage point, checks the advertised
constraints, and only then restores canonical Forge assignee ids.

The seventh R3 slice preserves the additional presentation context used by
replacement effects, optional prevention payments, optional triggers, and
related boolean decisions. The server normalizes an optional source card to a
display-only `context-card:N` identity, joins affected cards and players to the
deciding viewer's current snapshot under `context-target:N` ids, and bounds the
supplemental effect text. The Qt prompt layer renders that source, effect text,
and affected-object strip beside the existing typed confirm/deny choices.
The native host preserves the explicit card supplied by `showPromptMessage`
and `confirm`, including the privately viewed card in a one-card surveil.
Context is scoped to the current native input; cardless confirmations do not
inherit another input's card or description. Unauthorized face-down identities
are omitted. Native views with no printable name also omit optional source
context, including owner-visible face-down cards during Morph payment; the
decision and its legal payment actions remain available. No card is inferred
from descriptive text or a hidden zone.
Scalar decisions show a larger card face with adjacent hover/focus inspection
placed outside the decision dock so both answers remain unobscured;
Forge's card text supplies an artwork-failure fallback. Disconnect, seat/role
changes and prompt/game replacement close the private preview. The dock fits
its contents within the window instead of reserving a fixed tall empty panel.
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

After accepting a native input response or concession, the host suppresses
queued refreshes until that action begins on the native dispatcher. A stale
refresh must not acknowledge an unexecuted action. The barrier is released
before executing the action so nested human decisions can publish; changed
native inputs still fail strict response validation.

Synchronous native name/number menus dispatch concession on their waiting
callback thread, including the GUI dispatcher. Terminal concession releases
abandoned callbacks without inventing an answer and publishes Forge's actual
outcome. In a continuing multiplayer game, an unrelated departure preserves
the pending choice unless its originating object leaves with that player.
Departed-owned or controlled objects use a typed native cancellation to unwind
only the affected cast or resolution; cleanup must not restore departed cards,
publish a false resolution, or offer priority to a departed player.

If an object survives but its deciding player departs, that object's surviving
controller explicitly chooses the replacement player through the native
controller. When the original chooser was an opponent, the replacement must
be another opponent if one remains. A choice required by the rules rather than
an object passes to the next surviving player in turn order. The replacement
receives a fresh private prompt and explicitly supplies the original decision;
the host never chooses a default name or number. These cases follow rules
800.4a, 800.4g–h and 800.4j of the
[official Comprehensive Rules](https://media.wizards.com/2026/downloads/MagicCompRules%2020260819.txt).

Forge BO3 transitions now use the engine-aware restart boundary above. R2 and
R3 are complete. R4's final validation covers the full multi-game lifecycle,
public journal/replay, explicit spectator hand permission, hidden stack
printing, and separately packaged corresponding sources. Default deployment
still excludes Forge; validation does not imply a public runtime release.
See `forge-completion-verification.md` for the local acceptance record, paired
source rebuild, native-client evidence and outstanding release gates.
