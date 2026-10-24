# Rules-engine integration

This document defines the architecture for Hexproof's optional enforced-rules
mode. It supersedes the former product-wide prohibition on a rules engine while
preserving the existing manual tabletop as a first-class mode.

## Current delivery scope — 2026-09-27

Forge supports ordinary two-player formats, Duel Commander, Set Sealed, Set
Draft and regular Cube, plus **two-, three- and four-player Commander/EDH**.
EDH rooms retain a four-seat cap and start with all occupied seats when at
least two players are ready. Unoccupied seats never become engine players.
EDH uses the native Commander variant, 40 starting life and BO1; two-player
EDH does not become 20-life Duel Commander.

Commander room creation offers Manual tabletop and Forge rules. Forge EDH
uses server hosting; creator hosting and AI practice retain their existing
1v1 restrictions. Commander Cube remains manual. The server preserves runtime
availability checks, cluster capacity admission and all viewer privacy rules.

The Forge UI is independent of manual-table geometry. Two participants use the
existing opposed 1v1 presentation, three use two opponents above the viewer,
and four use four equal battlefield panels with the viewer at bottom-left.
The actual participant roster, not the room capacity or surviving-player
count, determines the layout. Eliminated seats remain visible while native
Forge continues the game. Presentation details are specified
[below](#current-implementation-status).

This owner-authorized scope supersedes the September 15 1v1-only restriction.
It does not change manual rooms, engine authority, deployment or release scope.

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
1v1, including Duel Commander and BO3. Public tournament and Limited/Cube pairing rooms always use
server hosting. Events propagate their immutable `rulesMode` to every pairing;
Limited tables use the native Limited deck format and locked submitted pools.
See [Limited events](limited-events.md#rules-enforced-one-on-one-matches). Creation/listing/joining disclose the mode; joining a hosted
room, including as spectator, requires `acceptPlayerHost: true`. See
[player-hosted Forge](player-hosted-forge.md) for its protocol, lifecycle,
preparation, trust limits, and verification.

Supported two-seat Forge rooms and events also offer an immutable optional
25-minute action clock per player. Creation and lobby controls expose the
choice; timeout loses the whole match. Commander/EDH and Commander Cube remain
untimed. See [action-clock rules](action-clock.md) for the supported modes,
defaults, decision ownership, and pause/restart behavior.

## Runtime choice

### Native AI practice

Forge rooms may be created with an optional `aiDifficulty` of `easy`, `normal`,
or `hard`. This selects one human host and one room-owned AI opponent in
ordinary constructed 1v1 BO1; it is unavailable for manual Playtest, Commander,
Limited/Cube pairings, and tournaments. An AI room keeps two engine players.
AI admission requires explicit support from the selected runtime. AI games use
dedicated JVMs even if human rooms use shared workers.

The host chooses the AI deck independently in the waiting room using
`room.ai.configure`, which also accepts a difficulty change. The same deck
validation applies to the AI. An AI configuration change clears human readiness.
The AI readies automatically once a valid deck is configured and does not wait
for client asset loading. Public seat metadata identifies `controller: forgeAi`
and its difficulty; hidden zones and private decisions remain viewer-specific.
Only the host may configure the AI, and only while the room is waiting.

Beginner and Normal simplify selected native tactical behaviors; Hard uses
the official Default heuristic. Difficulty does not alter decks or shuffles,
and this delivery does not enable simulation-based AI. These are practice
presets, not certified ratings. Upstream AI strategies may use information
inside the trusted engine that ordinary players cannot see; normal protocol
privacy does not establish strict player-view fairness of the AI itself.

Forge's informational AI deck-quality advisory is not shown to the player.
The client silently acknowledges that specific single-action startup notice
and proceeds to opening hands, including with existing runtimes. It sends at
most one acknowledgement per game/prompt and does not act for spectators or
replays. Other notices and game decisions still require their normal input.
The advisory does not invalidate the deck or remove any cards.

AI seats have no player connection and cannot become host. They never preserve
an otherwise abandoned room. The human reconnect window, concession, restart,
post-match return, and resource cleanup remain supported. Difficulty and deck
changes take effect on the next game after returning to the waiting room.

Local and online model opponents use the same practice scope and independent
deck selection. Their `modelAi` seat receives the native human-compatible legal
decision queue rather than a native AI controller. The desktop runs inference
through a separate, revocable AI-seat connection with only that seat's permitted
view. See [model opponents](model-opponents.md) for configuration, information
boundaries, budgets and paused-decision recovery. Native difficulty presets do
not apply to model opponents.

### Official runtime

Official Forge is the production rules backend. Hexproof's native adapter
reuses Forge's human controller and input queue for human seats, and the native
AI controller for an optional AI opponent, without opening Forge's desktop UI.
The old Manabrew adapter, local selector and packaging path have been retired.
Current runtime inputs and build instructions are in the
[runtime guide](../third_party/forge-runtime/README.md).

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

The pinned host includes explicit, reproducible Hexproof patches; upgrading
the upstream version alone is not the complete runtime contract. Forge is the
supported production backend. The engine boundary separates its runtime from
the Qt client and public room protocol.

## Dependency direction

```text
Qt rules views
  -> typed WsClient rules commands
      -> hexproof.v2 rules envelopes
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

Deck and commander names may use the catalog's combined `Front // Back` form.
The native adapter first tries the full name, preserving Forge's split-card
names. If unavailable, it looks up the front with the same set and collector
number and verifies both face names against that card before accepting it.
Verification also accepts the selected printing's paired flavor names, including
Universes Within double-faced cards. It never mixes one native name with an
unrelated alternate face. NFC normalization and the catalog's modifier-letter
colon spelling are handled at lookup; submitted spelling remains the display
identity and does not rename the native game object.
Mainboard and sideboard use the same lookup; commander designation matches
either the native name or that verified combined name. The hub keeps the
submitted names and printing metadata unchanged.

When both set and collector number are supplied, registration first resolves that
exact printing, accepting Forge's equivalent edition aliases. Missing native
printings may use the bundled verified catalog index described below.
Unrecognized identities return the private-safe unavailable-printing error;
Forge's name-only fallback must not silently substitute a different printing.
Name-only and set-only deck entries retain their existing lookup behavior.

Catalog prerelease and promo-pack printings may use a `P`-prefixed three-character
parent set and a numeric collector number ending in `s` or `p` (for example,
`PMH3 199s`). When Forge lacks that promo entry, the adapter accepts it only if
the same card resolves to the exact parent set and unsuffixed collector number.
The native card retains that supported parent edition for engine operations;
the submitted promo set and suffixed number remain its display identity in
snapshots and prompts. Regular, prerelease and promo-pack copies stay distinct.
Unknown parents, mismatched cards/numbers and other suffixes remain rejected.

Seventh Edition foil numbers (`7ED` with a numeric `★` suffix) and Brothers'
War Retro Artifacts serialized numbers (`BRR` with a numeric `z` suffix) use
the exact same-name, same-set unsuffixed printing's rules when Forge lacks the
treatment entry. The native card is foil; snapshots and prompts retain the
submitted set and suffixed number. Treatment and ordinary copies remain
distinct in deck pools. These aliases apply only to those two known set/suffix
pairs; mismatched names/numbers and arbitrary suffixes still fail registration.

Adapter 22 also bundles an offline catalog printing index. Its generator joins
paper printings by catalog Oracle ID and full name, then selects an exact,
supported native printing from that same group. All printing languages use
their canonical catalog name; language-exclusive printings must not be dropped
by an English-only filter. Duplicate language records share the same printing
coordinates. Eligibility is checked on the
selected printing: ordinary printings remain eligible when another printing
has a variant. Cosmetic `FlavorName` and `UniversesWithin` variants are eligible only when every
face retains the same characteristics and executable abilities; other named
rules variants remain excluded. Forge's rewritten flavor-name Oracle display
text does not itself change rules. Adapter 26 includes `Ancient Tomb / LTC / 387z`
using its exact `LTC / 387` parent and preserves the parent's cosmetic variant.
Adapter 27 includes paired alternate face names, Unicode spelling differences,
and catalog-verified anchors for Forge's `F`-prefixed funny/playtest numbers.
The offline generator may use an exact digital-edition anchor for a paper
printing with the same catalog Oracle ID and full name (such as Aswan Jaguar);
this does not enable digital-only cards or runtime name-only substitutions.
Only enumerated name/set/number triples are
accepted: missing editions, collector-set prefixes, serialized numbers and
other treatments do not need individual heuristic exceptions. The first index
contains 10,719 aliases, including RVR 397z/407z, PTC bl244 and WC04 jn328.
Rules use the verified native parent while snapshots, prompts and deck pools
retain the submitted set and number. Different catalog sets remain distinct
even when they share a native parent and collector number. Foil conversion
retains that identity. No runtime network lookup or client-supplied rules
fallback is permitted. A genuinely missing native card script still fails;
the index does not implement unsupported cards. Every unresolved paper printing
is recorded with a reason: missing rules, an unimplemented functional variant,
a different same-name card, a meld result, a display/front card, or a game piece
outside the supported modes. Known exclusions return `card_unavailable` with
the same private-safe coordinates as other start failures; unknown printing
identities retain `printing_unavailable`. Generator/resolver changes require a
fresh full-catalog census, and `generate.py --check` rejects unexplained gaps or
changes to the reviewed compatibility baseline. Native regressions check both
every supported alias and every recorded exclusion. See
[index generation and provenance](../tools/forge-printings/README.md).

Public mana uses the native mana-type constants, including `{C}`, independently
of a card's color identity. Snapshots retain confirmed blocker-to-attacker IDs
in each battlefield card's optional `blocking` array, and each attacker's
defender in `attackingTarget` (a battlefield permanent) or `attackingPlayer`
(a seat). They survive prompt changes and disappear when native combat ends or
an object departs. Blocking, attack, and attachment references join only current
battlefield objects, including anonymous face-down permanents, and never reveal
private-zone references. A player attack names only a seat already present in
the snapshot.

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
fields are read-only and reset with a fresh engine game. When available, the
command zone has one pile per participant, immediately after exile. Its browser
shows the independent commander histories, including public designation and
hidden-location summaries; the battlefield does not repeat commander art or
summaries in a second panel. Commander cards use the same offered opaque action
controls as other cards. Forge's payment prompt determines the final payable cost.

Snapshot step names use the existing rules-table phase keys (`main1`,
`begin_combat`, `declare_attackers`, `declare_blockers`, `combat_damage`,
`end_combat`, `main2`, and `end`, alongside the unchanged beginning/cleanup
steps). First-strike and ordinary combat damage share the `combat_damage`
display category only; Forge still resolves their distinct rules steps.

- Each seat receives its own native viewer projection. During player control
  (for example, Emrakul, the Promised End), native permissions may expose the
  controlled player's hand to the controlling player. Decisions retain their
  native acting player for costs, targets and priority, but are delivered only
  to the authenticated seat of the current controller. This also supports a
  human controlling a Forge AI seat; the original controller and private-hand
  permissions return when the effect ends. Optional public `controllingSeat`
  identifies control without transferring ownership of cards or permanents.
  Either human may still concede their own seat during a controlled turn,
  including while a controlled priority input or synchronous menu is pending.
  Terminal concession releases every original and temporary controller's input
  queue so the native game thread can publish the result; restoring player
  control must not strand a temporary controller's pending decision.
- Spectators receive an explicit spectator projection; they never receive a
  player's raw engine snapshot as an implementation shortcut. The existing
  immutable `spectatorsSeeHands` opt-in may overlay current hand zones only
  from their authorized owner projections. It never overlays libraries,
  sideboards, prompts or face-down battlefield identities. Public journals
  always use the original hand-hidden spectator projection, even in these rooms.
- Engine payloads and deck lists must not enter public logs, error details, or
  diagnostics. A bounded startup rejection may identify individual submitted
  cards only to their deck owner (the room host for an AI deck), using the
  private projection described below; it never discloses an opponent's deck.
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

Live two-player BO3 tables keep the game number and current match score visible
beside Settings without opening the drawer. A seated player's wins appear
first; spectators retain stable seat order. The summary stays clear of player
identity/life/clock plates and the default floating stack. BO1 and multiplayer
EDH do not add this summary; the between-game screen owns its own score display.

The host may explicitly restart a live game after confirmation. It preserves
game number, score and original starting player while using a fresh session,
shuffle and opening hand. Restart is unavailable during sideboarding or after
the match result. If a new/restarted session cannot start, members remain in
the waiting room with readiness cleared and a non-sensitive failure message.

The final result offers Stay for public-board review/chat and Return to room.
Return is unavailable between BO3 games; after a finished match it archives the
public journal and restores the original registered deck partitions. Review
does not allow further rules responses or restart. Reconnect into sideboarding
or finished review restores metadata and the retained, explicitly public
terminal rules projection without recreating a completed engine. Between-game
Review opens a read-only card browser for visible battlefield, graveyard,
exile, and command-zone cards. Hidden hands and face-down identities are
excluded, including from retained review snapshots.

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

Adapter 17 additionally supports [private visual Forge replays](forge-replays.md)
through a separate capability-based API. Original participants can download
both-hand snapshots only after the whole match ends, including all BO3 games.
This does not broaden the public journal or ordinary live projections.

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

For an unexpected failure of a started game, supporting clients also receive
an independent **Forge crash report**. The native adapter advertises
`forge-crash-diagnostics-v1`; clients opt in with `rulesCrashReportSchema: 1` in
`session.hello`. The existing error payload may then carry `rulesCrashReport`.
Older otherwise-admitted clients retain the fixed generic failure behavior;
this capability does not relax application, helper or runtime admission.

A report records the observed failure category, available verified exception
classes/code frames, the executing API and a source identity only when the
original hand-hidden spectator could see it at capture time. A recorded card
or effect identifies execution context, not proof that its script alone caused
the defect. Native failures, resource exceptions, execution deadlines, invalid
communication/publications, process exits and hosting loss remain distinct.
A signal or exit code alone does not imply out-of-memory. Empty prompt polls,
ordinary rejected input, player waits, concession and acknowledged cleanup do
not create reports. Initial-start/deck-registration rejection continues through
the existing startup path below, without exposing submitted decks to this
room-wide report.

The hub freezes the first failure and public context before room reset. It
sends the available report immediately, then permits one final revision of the
same incident within five seconds for late native/exit evidence. Collection is
bounded and does not wait on disk or process reaping under the room lock.
Successful host migration produces no terminal-game notice; a failed
reconstruction can retain its separate failure stage. Reports neither retry
mutations nor restart a game.

The desktop offers details, complete formatted-JSON copy, JSON save and
notice dismissal, plus an offline **Forge crash reports** menu entry. History
survives room/page changes, reconnection and application restart. A newer
revision updates the existing record without reopening a dismissed notice.
Only original membership continuity authorizes hub redelivery; each successful
resume receives at most the newest eight eligible reports, and later room
occupants receive none. The hub does not restore this eligibility after restart.

Retention is **up to seven days, subject to storage limits**: 64 reports / 4 MiB
per client profile, and 256 reports / 16 MiB in hub memory and its optional
private archive. The archive has at most 256 pending coalesced writes, and at
most 256 incidents can collect late evidence concurrently. Revisions do not
renew expiry. No diagnostic report is uploaded automatically or added to game
logs or visual replays. See the [capture and delivery contract](forge-crash-diagnostics-design.md)
and [privacy rules](privacy.md#forge-crash-reports).

Every failed initial start, next game, or restart reports an explicit startup
reason to all current room members after returning the room to waiting.
Only the initiating connection receives its request correlation ID. The reason
distinguishes a rejected deck, capacity, unavailable runtime, timeout, runtime
failure, and an unclassified rejected start. A runtime without structured
diagnostics uses the last category; the hub never infers illegal cards from a
generic exception.

Known deck registration failures include an unavailable card printing, a
missing designated commander, and invalid mainboard/sideboard sizes. The
runtime reports fixed codes and indexes into the submitted startup request,
never raw exception text or card names. The hub validates these references and
reconstructs card names, set codes and collector numbers from its own inputs.
Only the affected human receives their deck's issues; the room host receives
AI-deck issues. Opponents and spectators receive the reason without card
identities, even with spectator hand visibility enabled. These diagnostics do
not enter public journals or logs. Lists are bounded to 32 issues and mark
truncation; repeated copies of the same failed printing need only one entry.
An unavailable printing means that this runtime cannot resolve the submitted
card/version, not that the card is format-illegal. No legality rule or printing
substitution changes as part of diagnosis.

The desktop displays the failure prominently at the top of the waiting room,
including actionable localized reasons and any authorized card details. It
also supports copying and dismissing the message. The diagnostic survives the
loading-to-waiting transition and unrelated commands; a new load, successful
game start, leaving the room, or explicit dismissal clears it. Asset-download
errors remain separate from Forge startup errors.

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

The Forge UI presents two-, three- and four-seat sessions. `ForgeDuelTable` uses the
existing typed session, native prompts, and WebSocket response path. Its shared
chrome retains the existing 1v1 layout for two participants. Three/four participants
use `ForgeMultiplayerBattlefield` and `ForgePlayerField`, independently of the
manual table. Multiplayer fields
combine player information and public zone piles along the outside edge: above
the upper fields and below the lower fields. Upright battlefield cards face the
central phase overlay. Land/other columns follow their public pile counts,
and the creature lanes use the remaining width and height. Turn and priority
are indicated on each player's field without a second center status banner.
When the phase strip is hidden, including starting-player selection and
mulligans, the fields reclaim its space and retain only the narrow column-sized
gutter between rows. The phase strip returns when the first turn begins.
Its labels follow the interface text scale rather than shrinking with the
battlefield. When all twelve labels fit, the strip shows their full short names,
including distinct first and second main phases. Otherwise it shows the current
phase and a disclosure control for a read-only, scrollable overview of all twelve
phases. The overview follows the authoritative current phase, closes with Escape
or its close control, and never changes phases or priority. Its modal state
suppresses card previews and board input. Wide tables keep the original
single-line phase-strip density; the compact disclosure allows a two-line label.
In two-player games the phase and status information overlay the original
12-unit battlefield seam; their visibility, text and scale never add a reserved
row or reduce either field's height. Multiplayer retains its narrow 22-unit
phase seam, enlarged only when needed for the actual phase text plus four
units of spacing, and its six-unit seam before the first turn. It does not
reserve a second status row. Advancing phases or opening the overview does
not resize the battlefield.
The phase strip follows the public overlay anchor: centered across the
battlefield midline, or immediately below the centered opponent-deciding banner.
It never searches for an empty card pocket. Its twelve cells have equal width,
with the original translucent past/future fills and transparent gaps; there is
no full-width background plate. Complete scaled labels and the read-only compact
overview remain available. Compact disclosure uses a bounded visible button on
the same overlay line. Recent-action summaries use nearby unoccupied space;
if a long redundant summary has no safe pocket, the complete log remains
accessible from Settings.
Phase rectangles exclude relationship and aiming strokes locally, preserving
transparent styling without rerouting the curve or changing its target. Other
public text surfaces retain their themed backings above those lines.
The hand caption also has a local opaque backing, so the active battlefield
border and priority glow cannot run through its count or spectator message.

R0 and R1 are complete. The first R2 slice decodes `rules.snapshot` into a
typed Qt session with dedicated player, zone, visible-card, and stack list
    models. Two-seat rooms use opposed creature lanes, left-side lands and other
    permanents, a bottom fanned hand with library, graveyard, exile and command
    piles at the left of that row, a floating stack and a bottom-right decision dock.
The view does not connect Forge state to the manual room reducer or expose
manual mutation commands. QML never consumes raw harness
JSON or generic snapshot maps. Hidden library contents remain represented only
by normalized zone counts. Renderable battlefield, hand, graveyard, exile,
command-zone cards and the explicitly viewer-authorized library top enter the
card model. No other library identity or ordering is exported. Two-seat Forge decisions
occupy a reserved area beside the local hand. Ordinary priority uses a compact
action bar; specialized choices expand upward within a bounded, scrollable
decision area. In every Forge format the stack appears as a floating panel only
while nonempty, newest-first with independent scrolling. Drag its header to
move it, right-click the header to restore its default position, or use the
header button to collapse/expand it. Collapsing keeps the stack count visible;
after the stack empties, its next appearance is expanded. Moving, opening or
collapsing the stack never resizes the battlefield. Positions remain bounded
when the window changes size and reset for a new game. Each entry shows the
ability text from the rules snapshot.
When the card language is Chinese and that printing's Chinese rules are
already cached, the entry shows the matching Chinese passage; otherwise it
keeps the snapshot text. The native stack and normalized array are top-first. Each entry's
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
stops, Full control, log/chat, match controls, and optional player-hosting
tools. Public-zone browsing opens on demand; command-zone
buttons and tabs appear in Duel Commander/EDH and whenever a participant has command-zone
objects, including dungeons and emblems in Constructed games. Zone headings use the server's
zone counts, independently of how many card identities are disclosed. All
player plates show hand and library counts, including updates within one turn.
Library counts never expose private library contents. When native rules allow
looking at the top card (for example, Traveling Chocobo), the library pile and
browser display that card. Clicking it can submit an offered native land-play
or spell action, subject to ordinary timing, payment and land limits. Without
permission the pile shows its back and the browser explains that its contents
are hidden. Snapshots immediately replace or remove the visible top as the
library or permission changes; opponents and spectators gain no private look.

During a controlled opponent's turn, the controlling player's two-seat table
shows the controlled player's battlefield and permitted hand on the near side,
with a control status in the decision dock. Native priority prompts, including
Pass, act for the controlled player; smart priority and phase stops evaluate
that acting player's turn. The controller's own responses remain separate
native decisions. Normal orientation and hand return when control ends. Extra
turn scheduling, including both Emrakul cast triggers and the Promised End's
uncontrolled compensatory turn, remains entirely within Forge.

Hover and keyboard-focus inspection show a full card beside its source, flipping
left near the window edge and staying within the viewport. A placement that would
cover the decision dock moves into a free area beside or above the source.
Ordinary inspection preserves the visible hand, inspected source, public
battlefield cards and their status badges, player identities/life/counters,
zone piles, the phase/status strip and active controls. Empty lane space remains
available; a whole lane is not excluded merely because it contains a card.
Readable faces first stay near their source: among areas that fit each face at
the scaled 180-unit readable size, placement prefers the nearest source-edge
distance, then larger faces within a scaled 48-unit nearby band. It does not
move across the table merely to gain extra size. The bounded free-area search
retains nearby candidates as well as large ones. If no nearby area can fit
readable art, a farther readable region remains available. Source tracking
includes ancestor transforms, with coordinate mapping deferred until their
notifications have settled so pile animations cannot leave a stale anchor.
Full-size faces are
preferred within that nearby band. Constrained free areas fit all
printed faces proportionally, side by side or stacked. Floating hover previews
show only complete card faces, without a state-summary footer or reserved space
for one. Current state and linked-card details remain on battlefield tiles and
in the right-click inspection column. Combat curve bounds are
also avoided when possible; if they alone prevent readable inspection, their
bounds may be relaxed with faces capped at the scaled 180-unit size and actual
arrows painted above the preview. Public content is never relaxed this way.
When no free area can fit readable 180-unit faces, a fully readable **Inspect
card** button replaces the floating gallery in available blank space. It avoids
combat curves when a suitable free area exists and paints above any unavoidable
curve so its label remains readable. It opens
the existing right-side inspection column, as does right-clicking the card.
A focused battlefield, attachment, stack or hand card supports the standard
Menu key and Shift+F10 for the same read-only inspection, without a game action.
If the remaining blank space cannot contain the complete label, the same action
uses a magnifier button at the normal compact-control size, with the full
translated accessible name and tooltip. The text button remains preferred.
Both forms preserve the source, public content, hand and action areas and open
the exact inspected object without submitting a game response. If even the icon
cannot fit, no floating overlay is shown: right-click or the focused card's
context keys still open the fixed inspector. Hover does not reflow the table or
expose hidden identity to make room for an inspection affordance.
Hovering alone does not move the battlefield. A concealed object
always previews one card back, independently of the previous card's printed
faces. The preview follows
ancestor scrolling and hides when its source is fully clipped; a card that keeps
keyboard focus restores its preview when it scrolls back into view. This read-only overlay
does not intercept targeting or combat input, open the fixed inspector, or move
the battlefield. Modal decisions and authority loss hide it. Explicitly pinned
card state opens on demand in a separate right-side column. At compact window
sizes or enlarged UI settings, this column can reserve up to 40% of the table
width to preserve readable content while leaving the board and decisions
accessible. Its title and Close control use separate rows when necessary;
state headings wrap instead of clipping. In two-seat tables, a near player plate
that would intersect the shifted decision dock moves above it or beside it,
keeping the name, counts, life and exact player target accessible. Combat arrows
follow the life disc's actual position. Known multi-face
cards display all independently printed faces together in hover previews,
including visible hand cards, pinned inspection and card decision previews.
The authoritative current face appears first, with exact printing preserved for
each face. Wider previews use adjacent images; narrow panels stack them. This
read-only display never submits a rules response or transforms the game object.
Leaving a multi-face source, or a source with the compact inspection button,
allows 350 ms to enter its preview;
hovering keeps it open and leaving both source and preview closes it. Explicit
dismissal and loss of visible identity close it immediately. Hidden and face-down
identities cannot request face metadata or alternate art. Forge still owns actual
transform and face
choices. Log/chat opens as a
floating panel from Settings: drag its title to move it, drag the
lower-right corner to resize it, or right-click the title to restore the
default size and top-right position. Opening the log does not
reserve a column or move the stack, lanes, or decision dock. Transient hover
inspection does not reserve any column. Decision and deck-construction
selection summaries and primary actions remain clear of hover previews.
Previews fit all printed faces into the available
space beside those controls, following control movement and window scaling.
The resting hand exposes approximately its upper half at the bottom of the
window, retaining
stable visible click/drag slots and horizontal scrolling for unusually large
hands. Battlefield grids use four stable regions within each player's field:
creatures toward the combat midline, lands at the left rear, planeswalkers at
the right front, and other permanents at the right rear. The opposing field
mirrors front and rear vertically, preserving the same left/right categories.
Widths and heights adapt to public pile counts and attachment depth, and empty
regions release their allocation. Both players use horizontal support rows;
there is no alternative side-column arrangement. Lands use the fewest rows
that fit at the readable floor before their faces grow, so a taller available
field cannot turn a horizontal land row into a vertical column. Changing a
prompt, loyalty count, or tapped state must not swap regions or move unrelated
cards.

The layout avoids the reserved rectangles of the player plates, settings and
resting decision controls. Creature allocations are symmetric about the whole
player field's horizontal center, including when planeswalkers occupy the right
front. A single creature stays on that axis; side controls can symmetrically
narrow its row but cannot move its center to the remaining left-hand pocket.
Lands remain at the left rear. Both right-hand groups keep the available right
edge, with other permanents above the resting decision corner and planeswalkers
in front of them. Obstacles can shorten these regions vertically; their removal
does not change the category directions. Stable support allocations reserve
potential pile fans before the creature allocation is fitted.

Sparse creatures can grow up to 200 layout units; lands, planeswalkers and other
support permanents share a 108-unit ceiling. All cards within a lane share its
fitted size. Once creatures reach the 180-unit preferred size, keep larger
support faces rather than shrinking all support rows for the last few units of
creature growth; remaining space can still grow creatures to their ceiling.
Crowded regions retain the 80-unit readable width floor and scroll
with exact-object keyboard/target reveal. Each occupied category must remain
reachable and able to reveal a complete card. Capacity is optimized within
these positional constraints, rather than moving groups between rows and side
columns to maximize card area.

Only rendered hosts reserve their attachment depth. Creature lanes reserve
both directional combat movement and the complete destination-label extent
before combat begins; support lanes do not inherit combat margins. Above-face
labels retain space at the viewport top and between rows. Revealing an exact
card includes its destination label when the viewport can fit both. Movement
and attachment space cannot lower the readable card-width floor. Creatures
align toward the combat midline; lands and other support cards align toward the
player's outside edge, while planeswalkers align toward the front. Right-hand
regions also align their contents to their right edge. Potential expanded-pile
spans are reserved before expansion, and dense or scrolling grids retain
conservative exclusion from controls.
Only the expanded pile may leave its scroll viewport. Other rows remain
clipped, including while that pile is expanded; the same physical delegates,
keyboard focus and readout/inspection exclusions follow the expanded cards.
A Settings button sits at the top-right corner of the table. Decision
instructions remain in the bottom-right dock rather than occupying a second
banner above the battlefield. The dock owns a compact constant reservation at
its position and width, 120 layout units tall or less on short windows, for the
resting controls. This reservation also applies to multiplayer fields. It does
not reserve the maximum height of an expanded decision while idle. Priority,
payment, direct board targets and attack/block declarations retain their larger
268-unit height cap, or the available window height on short windows, and
scroll inside it. Any decision extending above the compact reservation exposes
**Hide choice** / **Show choice** without moving the battlefield or clearing the
selection draft. Revealing or keyboard-focusing a battlefield card underneath
that expanded portion immediately hides the choice to expose the complete card;
the player can restore it to confirm the retained selection.
Board-target and combat instructions and candidates scroll above fixed
selection-count and confirmation footers. Combat's all-available action shares
that footer; assignment editing and specific minimum-blocker explanations stay
in the scrollable body. Repeated source rules text is folded from the target dock
while the source card and its full inspection remain available. Other
decisions, a target list containing offboard candidates, and an explicitly
opened combat list may cover the battlefield up to the window's top margin.
An offboard target row shows its full card and title initially when they fit;
short windows keep the candidates scrollable and the confirmation footer fixed.
While a choice is taller than the reservation, **Hide
choice** shrinks the dock to its resting rows. It stays hidden through board
updates and resizing until **Show choice**, the next decision or the game
result. On three- and four-player fields the dock overlays the corner of the
hand band and battlefield without changing lane widths or card positions.
The player metadata and public zone controls beside that corner stay to the
left of the dock's fixed reservation, including during ordinary priority;
the battlefield itself keeps its full width.
Board decisions use the same expanded height cap as the two-player dock and
scroll inside it. **Hide choice** and exact-card reveal keep cards underneath
reachable, and **Show choice** restores the decision and its draft.
Three/four-player fields extend to the right edge instead of reserving a
permanent sidebar. The movable stack overlays that space without changing
card positions; collapse or move it to inspect cards underneath. Its background
consumes pointer input so dragging or right-clicking it cannot activate covered
cards. Stack target arrows follow the panel and hide while it is collapsed.
At rest the dock shows turn owner, turn number,
phase, and priority passing; an open decision uses the space of these rows,
while the phase track and the active-player border keep showing the turn.
The phase track marks the current step as a central overlay. In two-player
games it does not occupy battlefield layout space. A card label that would
cross that strip is drawn on the outer side of the face instead. Life changes
keep the current total inside the disc; the signed change fades above the disc
in a permanently reserved band clear of the player identity, action clock,
zone counts, and viewport edge. Its full upward travel is reserved before a
life change, so animation and repeated changes do not move cards or metadata.
Recent public actions
appear in a bounded overlay near the phase track, in the space below the phase
labels when that gap is clear, and use the same localized wording as the full log, so a phase entry says
Begin combat rather than the engine step id. Clicking the row opens the
full log. New entries, priority changes, and opening or closing the log do
not reserve extra height or move cards. Multiplayer reclaims its phase seam
before the first turn while the phase track is hidden.
While the local player must act, a glow lines the top of the
hand, which stays in place, and the pass controls enlarge; while the opponent has priority, the center of the board
says they are deciding. In a two-player game this status temporarily replaces
the recent actions at the original center. The phase overlay prefers the space
below it at the original overlay anchor. Mana sources on the battlefield are clicked to pay. A
reversible source can be clicked again to undo that activation while its mana
is floating or has been used only for the current, unfinished payment. The
native payment restores that source's contribution to the unpaid cost before
undoing it, preserving the other sources and payments. A source whose native
activation history cannot identify an exact refund is not offered for undo.
Before starting a spell or ability payment, the ordinary priority prompt also
offers **Undo mana** on the latest native undo entry when it is a reversible
mana source whose complete output is still refundable from the pool. Clicking
that source retracts that activation and its native activation-fee refunds
through Forge's native undo stack; an earlier source becomes available after
the later activation is retracted. Unrelated same-color floating
mana is preserved by identity and amount. Completed payments, irreversible
activations, invalidated history and non-mana actions do not acquire an undo
option. The client uses the current private legal option rather than inferring
undo from a tapped card, and waits for the authoritative snapshot to untap the
source and refresh the pool. Escape retains its selection/dismissal behavior;
it is not a general game-action rollback.
Tapped copies of
the same name occupy the pile immediately after the ready copies; clicking a
spent source or its exposed corner undoes that activation. The closed pile's
front shows the action of the member its click would activate,
including an undoable source behind same-name tapped copies, without reordering
or moving the pile. The payment dock shows
the unpaid cost once, with auto-pay and cancel; it does not repeat the
effect's rules text. Confirmed attackers
shift toward the defending side for the rest of combat. The turn label and active-player border use `activeSeat`,
independently of the current priority holder. The legacy layout keeps its
separate allocation, with space for the actual fixed controls and a positive
scrollable prompt body at supported window sizes.

Known Forge decision headings, common choice labels and engine-authored prompt
templates use the client's selected language through `RulesText`.
The known permanent-or-stack selector with a minimum mana value of one has a
human-readable heading. Generic card targets are labeled as cards, including
graveyard cards. An unbounded signed-integer maximum uses minimum-only number
guidance without changing the authoritative response bounds. Opening-hand
abilities use neutral ability wording, and a rejection with no specific cause
uses a neutral correction message. Partially assigned blocker groups show the
affected attacker, assigned count, minimum and how to remove the assignments;
the engine still owns legality. Play/draw labels mean first/second player only
in the native starting-player question.
A modal choice uses rules text already stored with the cached Chinese printing.
Each Forge mode line is shown in Chinese only when it matches one printed mode
and the printed modes line up one for one. A line that does not match stays in
English. The open prompt does not request card text. A Chinese printing cached
without rules text is filled from the Chinese image provider the next time that
printing is prepared, without replacing the stored image. While a modal spell is choosing targets, the dock title is only
the mode currently asking for a target, and the short target instruction sits
under it. The rest of the chosen modes and the English rules block are not
repeated beside the card. Unrecognized effect text, inserted card/player names
and mana symbols remain literal. Localization changes presentation only:
prompt/choice IDs and response payloads retain their original values, including
after an in-place language change.

Background card-image preparation is released by a current snapshot from the
room's selected mode. A manual snapshot cannot release a Forge load or vice
versa. A coalesced visible-card batch additionally prioritizes only normalized
authorized identities from the current Forge game, including spectator-visible
cards and private prompt cards for their owner. It deduplicates exact printings
and uses the existing incremental catalog queue; delegates remain cache-only.
Leaving the room invalidates queued readiness and visible-card work. No card
identity is inferred from a hidden count, object id, or descriptive text.

Authorized native card-selection, reveal, order and source-context entries use
the same printing identity as snapshots of that physical card. Two copies with
the same name but different set/collector numbers remain distinct cache
requests, so moving a selected card into the hand or battlefield does not change
its requested art. Face-down visibility remains viewer-specific; anonymous
cards never gain printing metadata through these prompts. Local art-language
fallback and custom overrides still follow the card catalog's image policy.

R2 adds the private normalized `rules.prompt` projection,
authenticated `rules.respond` command, and typed Qt prompt state. The current
interactive families are first-player-roll acknowledgement, extra starting-hand
selection, opening-hand mulligan, London-mulligan put-back, priority/choose-action,
mana payment, board targeting, attacker declaration, and blocker declaration.
Legal cards on the table are the primary action controls. Clicking a highlighted
hand card plays a land or casts it; clicking a highlighted permanent activates
its ability, including a mana ability during payment. One legal action submits
directly; multiple actions open a chooser for that card. Space and Return perform
the same action on a focused card. Hovering or focusing a battlefield permanent
with a currently legal activated action shows an **Activate ability** hint. This
also applies to creatures that are already attacking: the current native prompt,
not the phase name or the attacking marker, determines the click action.
Legal hand cards can also be dragged onto the local battlefield. A click or drop
submits the matching normalized action rather
than mutating the projection. Actions without a directly operable table object,
including plays from other zones, remain available in the decision dock.

Human Auto-pay consumes usable floating mana first. For a remaining pure generic
cost of at least two, it prefers a legal, untapped, tap-only colorless land that
can pay the whole remainder in one activation, choosing the least excess mana.
Native amount/replacement prediction and spending restrictions still apply.
This avoids tapping multiple Tron lands under Trinisphere when one Tower pays
all three. Colored requirements, special payment preferences, converge/sunburst,
additional activation costs and native AI decisions retain the native policy;
manual source selection remains available.

Manually activating a mana source with an irreversible activation retains
Forge's full color choice, even while paying a colored spell. Standalone manual
activation clears any color preselection left by an affordability preview.
Lotus Bloom therefore asks for its sacrifice confirmation and
one of the five colors before producing three mana of that color. A choice
that does not pay the remaining symbol returns to the same payment; surplus
mana remains in the pool. Undoable mana sources keep their native
express-color behavior. Auto-pay retains its native color planning. Nested
confirmation and color decisions replace the payment controls temporarily;
queued source clicks do not cross these decisions. Native color-enum labels
use the client's language without changing response IDs.

Each ordinary London-mulligan redraw remains a complete hand while its owner
chooses whether to keep it or mulligan again. Keeping the hand opens the put-back
decision, with the accumulated number of cards owed after free mulligans.
Serum Powder is also available through its hand card during the native mulligan
decision. Accepting Forge's actual Powder confirmation after a paid London
mulligan first requests that redraw's owed put-back selection, then uses the
remaining hand for the native exile/redraw operation. If that selection puts the
chosen Powder on the bottom, the operation returns to the mulligan decision
without exiling anything. Declining the confirmation leaves the hand untouched.
Powder does not increase the ordinary mulligan count, draws the number of cards
actually exiled,
and does not repeat an already completed put-back selection when the replacement
hand is kept. A later ordinary mulligan starts a new full redraw and its own
accumulated put-back obligation. This follows CR 103.5 and 103.5b in the
[Comprehensive Rules](https://magic.wizards.com/en/rules).
Keeping the initial hand or owing zero cards skips put-back. Reaching a zero-card
opening hand ends further mulligans. The put-back decision requires an explicit
selection and confirmation; it cannot auto-select cards through cancellation.
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

Incremental native board choices may include an optional `selected` boolean on
each normalized target. This is the deciding player's existing native reservation
(for example, improvise or convoke), separate from the next response's selection.
The client preserves its visible border/checkmark across prompt refreshes and
keeps each directly selectable copy independently reachable. A click still submits
only one opaque response ID; confirming submits an empty next selection when permitted.
The server never echoes presentation flags into Forge's canonical response.
Reservations are private prompt state, not projected battlefield taps. Once
confirmed, native cost reduction records only the permanents actually tapped by
that payment. Cancelling it restores those taps together with native refundable
mana abilities, preserving earlier tapped permanents and convoke-specific rules
history. The client never locally untaps cards to simulate rollback.

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
game termination/change, or disconnect releases the guard. While the guard is
held, offered cards and players keep a dimmed highlight, and the card whose
action was sent shows a pulsing ring. Activating an offered card or player
then sends nothing; the card shakes and **Waiting for the game** appears above
the dock. A pointer press retains its decision and offered actions. If that
decision changes before release, the gesture sends no new action; it cannot
reinterpret an earlier mana click as the new decision's undo action.
Paired `rules.snapshot` and `rules.prompt` publications share the snapshot's
existing envelope `seq`, including explicit `pending: false` prompts. This
also applies to direct-peer receipts and restored state. A client discards a
sequenced prompt older than its latest rules snapshot, so a delayed hub
publication cannot replace a newer direct-peer decision or release its pending
response guard. Equal sequences remain valid. Unsequenced standalone prompts
from older servers remain accepted; they cannot provide the same ordering
protection when direct and hub deliveries cross.
A `payManaCost` prompt may carry `paymentId`, the Forge id of the
spell ability being paid. While that id is present, battlefield mana sources
from the pending prompt can be queued, up to eight, each once. The queue is not
a tap. The next prompt submits the first queued source only when it is the same
payment and that source has exactly one fresh mana action. Any other prompt, or
an error or timeout that releases the guard without one, clears the queue and
says **Queued mana was cleared**. A republication of the same pending prompt id
keeps the queue, the sent card's ring and a hidden decision. The source already
sent and hand sources are never queued. Escape or a second click on a single
card removes a queued source. Hosts that omit `paymentId`, including adapter 27 and
the adapter 25 creator-host base, keep the waiting cue instead. A malformed id
is dropped, which turns click-ahead off without blocking the payment. Adapter
28 is the first host revision that emits the field. Replays still accept adapter 17
and newer. Priority controls
remain in the bottom action bar; specialized decisions pin their basic payment
and cancellation responses above their scrolling body. Long spell and ability choices have
bounded widths and wrapped labels, with a scrollbar and keyboard-focus reveal
when they overflow. Scrolling ability choices or prompt context does not move
the basic responses out of view.

Smart priority is enabled by default for the deciding player's `chooseAction`
windows. With an empty stack it skips upkeep, draw, end of combat, cleanup,
and other players' main phases unless a stop is set.
The user's main phases, combat response windows, and all players' end steps
remain action points. It normally passes the user's response to a stack made
entirely of their own spells/triggers. Unknown or mixed stack ownership does not
qualify. Full control, explicit phase stops, and held response windows override
these defaults; users need one of those controls for special upkeep or own-spell
response timing. An empty stack during the user's end step does not itself
approve a pass: after an end-step trigger such as Necrodominance draws cards,
the fresh native hint must preserve any available action before cleanup.

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

The action bar offers **Next / Resolve** and a **Pass** menu for passing until
a response, for the rest of the current turn, or through the current stack.
Settings offers explicit **Smart priority** (the default) and **Full control**
choices. Full control disables automatic passing and remains active across
casting, target selection, and payment. Priority mode and separate phase stops
for the user's turns and other players' turns are saved in the local profile.
**Settings → Gameplay** and the in-game Settings drawer edit the same preferences;
changes apply immediately and survive new games, room changes, and application
restarts. Only a connected player in a live, unpaused game publishes
`rules.priority`; spectators and replay viewers never send player preferences.
The current saved preferences are republished when a player enters the table,
resumes a connection or hosted game, changes seats, or starts another game.
Starting a temporary Pass mode does not change the saved priority mode;
Full control resumes when that temporary mode ends. Reselecting either priority
mode at the table also ends a temporary yield. Full control has no persistent
explanatory status line in the action dock; its setting and pause behavior remain
available in Settings. A stop pauses the first priority
window in that phase; explicitly continuing acknowledges that phase only, so the stop
applies again on a later turn. Stops cannot create a priority window in untap
or another engine step that does not grant one.

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
are applied immediately. Consecutive snapshots name a public move when the same
object id changes zone, or when exactly one named card of that owner left one
zone and one entered another. A paint-only marker, card-shaped with the card's
public name or a plain back, flies from the object's old position to its new
one, at most six per update. The destination is read from the new layout when
the marker leaves: the card itself on the battlefield, in the hand or on the
stack, otherwise the owner's library, graveyard, exile or command pile, or the
hand count for another player's hand. A hidden opponent draw is a back from
their library to their hand count. A card entering play from their hidden hand,
or a spell they put on the stack while that hand shrinks, flies from that hand
count. Markers never take input.
An update is attributed to the controller of a stack object that left the stack,
otherwise to the active player for combat damage, otherwise to the viewer when
it is the first snapshot after the viewer's own answer, otherwise to the active
player. A viewer's own update moves at once. Another player's update starts its
markers in order—stack, moves, combat, damage, then deaths, 150 ms apart—and
outlines the changed cards for 1.5 seconds. Life, tap and counter changes are
not delayed. An automatic pass waits only while that update's markers are still
flying, and for at most 1.5 seconds. A card that arrived in the update fades in
when its marker lands; one that was already there, such as a card shown when a
zone browser opens, appears at once. Life totals count to the new value, and
the gain or loss floats beside the total; a newer value restarts the count from
the shown number. The card hover preview follows the source card's position instead of
redrawing every frame. With motion on it waits a moment, then fades in.
A card's picture fades in again when the art arrives.
The decision dock grows immediately so a newly enabled answer is not partially
clipped during expansion. Contraction eases inside the reserved area; window
resizes jump directly to the new height. A card's art and printed type refresh when that card's
own catalog entry arrives, rather than when any other card's image does.
Battlefield piles are built in the client model, so a new permanent is in its
lane as soon as the snapshot is applied. A snapshot re-piles each lane once,
and a tap inside a pile moves that card without recreating its neighbors. A
permanent that hosts an aura or equipment keeps its own pile, so the attachment
drawn on it stays visible and clickable. Within one name the plain pile comes
first, and its tapped copies take the next slot. Copies with counters or damage follow those. Each permanent carries its own
decision summary and relationship list, so one prompt does not make every card
scan the whole table. Clicking a card still reads that card's actions when the
choice list opens. Forge decision dialogs and the zone browser fade and
grow from 97% to full size when they open and close at once, so a closing modal
never swallows the next click; dialogs elsewhere in the application do not
animate. Stack spells fade in when added and fade out when removed; entries
displaced by a change keep their final position as the click target and only
paint the slide. Damage and counter badges pulse when their amount
changes. Motion is on by default. The opt-in
[update-cost benchmark](../apps/client-qt/tests/bench/tst_forgesmoothness.qml)
documents its command and advisory timing targets; those targets do not
establish rendered frame-rate qualification. Historical default-renderer
observations cover Linux Wayland/XWayland, not Windows rendering.
`HEXPROOF_MOTION=0` turns it off. Automated tests start with it off and turn
it on only to test motion. A `rules.snapshot` with `promptFollows` is held for
at most 100 ms and applied with the prompt that follows it in the same room
and game. Leaving, clearing or replacing the connection discards a held
snapshot. With smart priority on, the room passes an engine-eligible priority
step before collecting the snapshot and prompt to publish, unless the seat is
holding the next prompt or stopped on that step. If these passes finish the
game, the publication includes its final snapshot and rules result. An engine
prompt wait that expires without a changed prompt or a completed game is
reported as a timeout. A directly hosted input first publishes its committed
position and confirms it to the worker while the room operation is locked;
subsequent normal input can resume delegated passing. Its receipt replay keeps
that original position without advancing the engine.
With motion off, no marker flies, no update is
staged, an automatic pass never waits for markers, and changes apply at once;
the hand's hover lift still eases. A card's click target is that final slot at once. When
motion is on, the picture glides there over the normal duration. Any press or
key on the Forge table first finishes every running glide, turn, fade, count,
marker and dock resize. A lane resize, a reconnect or a new game jumps instead.

A battlefield pile acts on the card that was clicked. The front of a closed pile
stands for its ready members; for an activation it uses itself when it is
eligible, and for combat and targets it takes members in order. Members are
interchangeable only when they are equally tapped, share attack, block and
attack-target relationships, and are offered the same actions (labels compare
without a trailing count); combat and targets also compare entering this turn
and summoning sickness. When the eligible ready members are not interchangeable,
the click fans the pile instead of choosing one. A tapped member's exposed
corner acts on the most recently used tapped member, otherwise on the
interchangeable tapped members, otherwise fans the pile. Only the front, the
fanned members and the tapped members take pointer input, and each takes an
exclusive grab, so one click never activates two cards. While an answer is in
flight, a front click queues the next offered member that is neither queued nor
the one already sent, so several lands of one pile can be queued; a further
click never removes a queued land. The badge reads the pile size, then how many
members are tapped and how many entered this turn when only some are. A fan
opens on its slot's row, overlaps like a hand so it stays inside the lane, and
closes on Escape, its badge, a new decision or a fan opening elsewhere. The turn
callout fades in, then holds and fades out. A room or game change still clears
the previous state.
During a continuous pass, the action bar keeps its status, full-control and
cancel controls in a stable layout. Per-window pass buttons and optional action
lists return when continuous passing ends; required decisions remain immediate.

Battlefield cards visibly show the projected power/toughness, marked damage,
and counters. An attached aura or equipment is drawn on its host, offset
downward so each attachment retains its own named strip beneath the host.
Clicking or hovering a strip selects or inspects that exact attachment. The
host and each attachment take exclusive clicks, including when several
attachments share the same host. Host relationship and combat labels sit below
all of that host's attachment name strips. Confirmed attacks
draw an arrow to the defending player plate or permanent; the attacker is
labeled with that destination, and a permanent or player being attacked is
highlighted. Inspection details label confirmed blocks and attachments by their
actual relationship kind; attacks are never described as attachments.
Native `enteredThisTurn` and `summoningSick`
flags add localized entry and summoning-sickness labels. Same-name permanents share one slot across tap, attack, entry and summoning
sickness, including new lands. Tapped members sit behind the ready ones.
Labels follow native turn and haste updates rather than a client timer.
Unspent mana has a dedicated, unelided display
with colored mana symbols and counts, updated after each authoritative snapshot.
Crowded hands support horizontal wheel/trackpad scrolling over card faces, a
visible scrollbar above the cards, and keyboard focus that reveals each card
fully, including the last card. Player plates include public counter and mana
summaries. The near player's name and zone counts sit above the life disc and
clear of the hand faces; the life disc still meets the hand edge. Two-player
battlefield allocation reserves the actual near-player identity/life rectangle
so support permanents remain clear of it, independently of the open decision.
Hovering a visible card, or keyboard-focusing a battlefield or stack
object, shows a larger image and read-only details in the inspector, subject to
the specialized-decision hover suppression described above. Left click on an
inactive card does not pin the inspector; other hover previews temporarily
replace a pinned card and leaving restores it. Reserving the column after a
pin can move other cards beneath the pointer; those stationary layout enters
do not replace the just-pinned card. Actual pointer movement resumes the current
hover, even within the newly entered card, and explicit keyboard focus remains
an inspection intent. Clearing the pin or losing authority clears this guard.
Closing clears the inspection and returns keyboard focus to its original card
when that source is still available, otherwise to the table. Escape uses the
same return path; authority loss or automatic invalidation clears inspection
without moving focus away from another active dialog.
For an actionable card, left click performs the current action; right click pins
inspection without submitting a response. A layout drag must not activate or
select the card. The inspector uses the full cached image rather than the tabletop thumbnail.
It refreshes with snapshots and clears when the object is no longer visible or
the game changes. Hidden identities are never looked up in the catalog; a face-down permanent may still show its public game state. Cached
printed card art is labeled separately and is not presented as the engine's
current abilities or rules text.
Counter summaries render native stat names as symbols such as `+1/+1` and
localize common named counters such as Lore and Energy. Unknown names remain
visible. A multiplication separator distinguishes each counter name from its
quantity; loyalty badges retain the numeric quantity. This display mapping
does not change wire values or mana pools.

Battlefield presentation groups projected creatures toward the combat center,
lands at the left rear, planeswalkers at the right front, and other permanents
at the right rear; opponents mirror front and rear vertically. Current projected
power/toughness takes precedence over cached printed types, so animated lands
occupy the creature row.
After projected creature state, printed land types take precedence over
planeswalker types; all remaining public types use the other-permanent region.
Unknown or hidden printed types receive that neutral placement without an
identity lookup. Attached permanents remain with their host rather than
appearing a second time in a separate region. The new two-seat view keeps the
active player's half of the battlefield highlighted for the whole turn. When
that player changes, the original
table-centered announcement briefly shows "My turn" or "Opponent's turn".
It retains its 44-unit headline and horizontal center, passes input through,
and never reflows cards. Original vertical padding and center remain preferred;
when the restored field seam leaves public card names/statistics underneath,
only vertical background padding shrinks from 36 to four units, with at most a
12-unit vertical correction. The transient announcement may cover card art and
the central phase/status strip. With three participants, its preferred center
is the central battlefield seam of the full-width near field.
The corner indicator still names the turn and phase. The view uses
art-focused cards with public state overlays.
Every battlefield card paints the same fixed-proportion rectangle as its lane
slot, independent of image language, frame, or loading state. Battlefield tiles
prefer an independently cached illustration for the actual selected image.
For recognized Scryfall full-image URLs, the existing cache/preload flow can
fetch the matching `art_crop` variant in the background. This optional asset
shares the bounded download budget, follows required full-card work, and never
delays match readiness or makes a successful full-card download fail. Display
getters and local cache hydration do not initiate network requests. Existing
full-card caches and art packs remain valid; custom images retain priority.
Only a crop belonging to the same full-image URL and face may be attached.
Hand and inspection images keep the complete card. Missing, failed, or offline
crop loads leave the existing complete-image fallback visible, without changing
the tile geometry. Cache migration, cleanup and art-pack transfer include the
optional artwork asset when present.
Fallback artwork cropping follows the currently visible face and actual image printing, using local
canonical metadata independently of the selected display language. A substitute
image cached for another language cannot override the indexed frame of the
current exact printing. Planeswalker faces use a shorter artwork panel so
their higher type line stays outside the battlefield crop. Saga and Class
faces use their tall artwork panels; Battle and flip faces use their
artwork in the appropriate orientation. A substitute image may use a known
artwork crop only when its actual source printing is verified by the image URL
and same-card catalog metadata. Unknown frames, unverifiable substitute images,
and custom images fill the same viewport with an aspect-preserving center crop;
they never stretch or shrink the visible card to a narrow portrait. Full
inspection images retain their complete content. Hidden and face-down
identities never trigger frame metadata lookups.
Loaded artwork has no permanent padded or colored tile behind it. State
outlines follow the fixed battlefield face. Ordinary offered actions use a
subtle thin outline; selection, focus, combat and mana actions retain their
distinct restrained outlines and labels. Changing an image source cannot alter
lane positions, visible card dimensions, pile ordering or pointer hit areas.
A tapped card stays upright. Its art darkens and a large tap mark sits in the middle of the art. Power, toughness and counters stay undimmed on top of the mark. The legacy view reserves room for rotated tapped cards.
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

Combat declarations on the two-seat table use the board. An attacker with exactly one legal destination is assigned by one click, and clicking it again removes that assignment. An attacker with several destinations still uses two clicks: select the creature, then a highlighted legal player plate, planeswalker, or battle. **Attack with all** assigns every unassigned attacker to the single defending player, or opens a player menu when several players can be attacked. The menu closes when its defender is chosen. It never chooses a planeswalker or battle, and it stops when a defender is full. A blocker with exactly one legal attacker is assigned by one click, and clicking it again removes that assignment. When several attackers can be blocked, every one of them stays selectable on the board: click a blocking creature and then the attacker, or click the attacker first and then the creature. An attacker that still needs more blockers can be chosen; the declaration confirms only once that attacker's minimum is met. **Block with all** assigns every unassigned blocker that has exactly one legal attacker, and stops when that attacker is full. It does not choose among several attackers. Pending source badges say **Choose attack
target** or **Choose creature to block**, respectively. Selecting a source also
starts a live curved arrow that follows the pointer without a delayed trailing
animation. Hovering a legal visible destination snaps the arrow to that object
and strengthens its highlight; clicking fixes the assignment arrow there.
Hovering alone never changes an assignment. Reassigning dims the previous link
until the new destination is chosen; cancelling restores its normal appearance.
Large hover-card previews are suppressed while aiming. The live arrow hides
outside the active window, under a modal dialog, while a reply is pending, and
when the source is clipped. Arrow rendering uses scene-graph vectors rather
than repainting a table-sized image for each pointer movement.
Combat, replay and stack-target curves leave gaps around visible battlefield
card names, state and counter labels, stats, assignment hints and exposed
attachment names. Multiplayer player names, hand counts, turn/priority status,
life values and public zone/mana readouts receive the same protection. Only
their painted content interrupts a line; the surrounding player target remains
available. Their endpoints and remaining curvature stay unchanged;
an arrowhead overlapping a readout is hidden without changing its target.
The shared readout geometry follows scrolling, card motion and expanded piles,
and is collected only while a relationship is visible. Related layout updates
publish together during the frame's polish stage, before scene synchronization,
including the first frame of a new assignment hint. Resizing does not make every
curve recompute for each intermediate label position. Card endpoints follow
their painted translation throughout movement. Hidden cards contribute
only their existing anonymous labels; this presentation never requests identity.
Ability activation uses the native action/payment windows; a declaration prompt
accepts only combat assignments. Repeat for additional blockers or for a blocker that can block
several attackers within its native capacity. Both click orders preserve the
blocker's other assignments when adding or removing one pair. With an attacker selected first,
clicking a blocker that cannot block it or has no remaining capacity leaves
that attacker selected and preserves every draft assignment. The single-target
shortcut must not select another attacker in this case. Source and
destination capacities constrain highlighting; partially met minimum-blocker
requirements can be edited but prevent final submission. Combat candidates stay in their slots. Clicking the front of a pile uses the
next ready member that is not already chosen. Clicking the count badge spreads
that pile's members in a row inside the lane, without moving the lane, so one copy
can be chosen directly. With the front card focused, Return opens that row and Left or Right moves to the neighboring copy.
Selecting the same source again or pressing Escape cancels the pending selection,
including an attacker selected before its blocker, without discarding completed
assignments. Selecting an existing pair again
removes it; selecting a different destination reassigns an ordinary combatant.
The compact dock shows instructions, assignment counts, clear/remove controls,
and an explicit declaration button, disabled while a source awaits a destination.
An optional assignment list shares the same opaque choices and remains available
for offscreen objects and legacy player targets without an authenticated room
`seat`. Arrows show visible selected relationships; clipped objects do not acquire
invented positions. Submission retains the typed model's normal validation.
New prompts, game changes, disconnection, sideboarding, and changes of viewer
authority clear local choices.

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
final confirmation in the dock. Directly selectable copies in a same-name pile
temporarily occupy separate slots, including candidates covered by an ineligible
copy. These slots stay stable while toggling or awaiting a response;
new prompt candidates refresh them, and ending targeting restores ordinary
grouping. The dock retains candidates outside the current table view, legacy
player candidates without a seat, and ambiguous mappings. It
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
Single-choice menus submit the clicked option immediately, including optional
ability menus. Optional single choices offer a separate empty-choice action
(**Cancel** for an ability menu, **Choose none** otherwise). They do not show
quantity controls or a second confirmation. Multiple-choice and weighted-total
menus retain selection counts and explicit confirmation.

The second R3 slice now supports general Forge `chooseCards` prompts.
Candidates are normalized to the same minimal private printable identity used
by the London put-back flow, but use distinct card-selection minimum and
maximum fields so they cannot be confused with board-target cardinality. The
deciding client can submit any unique candidate set within that range,
including an empty set when Forge advertises an optional choice. When that
prompt is the opening-hand ability list and only one card is legal, the table
asks whether to use it instead of opening the ordering browser. Using it
submits that card; leaving it submits an empty selection. Two or more cards
still use the browser, because their order matters. The server
refetches the prompt and revalidates the range, uniqueness, and membership
before reconstructing the canonical `chooseCardsDecision`; no rules text or
unrelated engine card state crosses the WebSocket boundary.
Native cross-zone target menus omit Forge's presentation-only zone headings
from legal responses. Pure card lists use this card picker with printable
identities when a candidate is outside the battlefield. A list whose cards are
all on the battlefield is chosen by clicking those permanents, so two copies
remain distinct by their position and tapped state. Mixed lists retain the
explicit finish-targeting action and the original candidate objects. Selecting a section title must never restart the
same target prompt.
Standard native card-list inputs reuse the official `setSelectables` minimum
and maximum so multi-card decisions can be submitted as one complete batch.
Native subclasses with additional selection constraints keep their own
incremental validation and do not auto-confirm after the first click.
Their private candidates retain an optional `selected` marker for choices
already held by Forge. Both Qt pickers keep these cards visibly marked across
successive prompts and reconnect. A new click on a marked card means undo;
the response contains only this next click, never a resubmission of prior
selections. The marker does not change cardinality or disclose the choice to
another player or spectator.
Native cost inputs also preserve Forge's cancellation permission. Only a
`chooseCards` prompt with `cancellable: true` offers Cancel; `$cancel` carries
no selected cards and returns to the native cancellation/rollback path.
Mandatory selections and London put-back cannot gain cancellation from a
client-supplied response.
Private looks accompanying a card choice (including library searches, Collected
Company and revealed-hand discard) share one selection prompt. It contains the
exact authorized disclosure and legal candidates, without an earlier reveal
acknowledgement for the chooser. Additional visible cards carry `readOnly: true`
and prompt-local `reveal:N` display ids; neither those ids nor their engine ids
are accepted as selections. Bounds count only eligible cards. The native adapter
and server both retain candidate-membership validation. No disclosure is inferred
from a zone, a previous prompt or another player's snapshot.
The 1v1 Qt browser defaults to all cards in this current authorized list, labels
ineligible cards **Not selectable**, and offers **Selectable only** alongside the
existing selected-only view. Filtering does not change selected identities,
native cardinality or cancellation permissions. Prompt replacement and loss of
the deciding seat clear its transient state, including both filter switches.
Standalone reveals, notifications and looks with no ensuing choice retain their
explicit acknowledgement. Other recipients of a public reveal still receive
their own disclosure; combining the chooser's view does not broaden visibility.
A companion prompt may be confirmed with no card. That declines the companion
and continues into the opening hand; it does not move a missing card into the
command zone.
When a revealed imprint is chosen from its library and the script does not
already reveal that choice, each other player is shown the chosen cards. Atraxa,
Grand Unifier's hand takes are public because those cards were revealed.
A permission to cast an exiled card does not offer a modal card's land face.
The cast permission is checked against the face being played, so a spell front
remains castable while its land back stays unplayable.

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
The dock creates only the controls for the decision currently being answered.
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
printing. Token action labels also resolve names from the current authorized
card projection instead of querying engine-only names such as `Eldrazi Spawn
Token`. Hidden action controls do not localize unused labels. GUI catalog
lookups cache successful misses in a bounded cache, invalidated with catalog
replacement and language changes; database errors remain retryable.

Battlefield cards may expose `exiledCardCount` and `exiledCardIds` for
cards still exiled with that exact native object. The count includes face-down
cards, while links only join identities authorized in the viewer's current
exile projection. Battlefield summaries and pinned inspection show
linked names or anonymous counts. Leaving exile removes the relationship.
A planeswalker's loyalty count is a separate lower-right badge. The exile
summary sits above that badge and does not include the loyalty count.

Visible face-up battlefield permanents may also carry optional `annotations`
entries with `kind` and `value`. Supported kinds are `namedCard`, `chosenType`,
`chosenColor`, `chosenNumber`, `chosenMode`, and `classLevel`. Visible face-up
command-zone dungeons may carry `dungeonRoom` for their current room. These come from native
`CardView` revealed-choice fields, never raw secret choices or arbitrary
remembered objects. The server allows only these kinds on visible face-up
battlefield objects, and `dungeonRoom` only in the command zone; the client
applies the same zone/visibility boundary. Class levels and dungeon rooms update
from the current snapshot rather than from locally remembered decisions.
Named-card and linked-card display names follow the catalog language.
The compact tile shows a bounded summary; the scrollable right-click inspector
provides additional detail. Permanents with choices or linked exile stay in
separate piles, even when their printed names or choices match. Each summary
is rebuilt from the current viewer snapshot, including after reconnect or
zone changes; no stale annotation or linked identity is retained locally.

Visible face-up battlefield sources can also publish `chosenCardIds` for
native chosen-card relationships, such as Dauntless Bodyguard's chosen creature.
Each id must still identify the same native game object, including its game
timestamp, and must have an identity visible in the viewer's current snapshot.
Hidden choices are omitted. A zone change or blink clears the old link rather
than reconnecting it to a new object with the same numeric id. The tile and
inspector show localized chosen-card names; sources with these links stay
in separate piles. Choice links are rebuilt from snapshots after reconnect.

Specialized cost selectors keep Forge's completion condition: crew requires
enough total power, exact exile costs expose their full required count and a
separate cancel action, and convoke/improvise/waterbend expose only helpers that
can still reduce the remaining cost. Selected helpers remain clickable for
deselection. Conditional discard completes when its actual rule is satisfied;
selecting one creature or two other cards does not leave a hidden confirmation.
Small finite card-face choices, including available dungeons, are visible menus.
Unbounded card-name domains retain the catalog-backed text input.

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
When Forge allows deferring an attacker's damage assignment, the preceding
choice asks whether to assign this creature first or another creature first.
Deferral moves the creature to the end of the current assignment queue; it
does not waive its damage or pass priority. The known prompt and options are
localized while preserving the inserted creature name and response identity.

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
Independent modal callbacks use their own heading and never inherit the last
queued payment or targeting message. The native adapter supplies missing display
annotations for reviewed pinned card scripts: Duress, Deadly Cover-Up and
Shallow Grave use their existing readable spell descriptions, and Emptiness
names the graveyard zone and mana-value limit in its target prompt. This hook
accepts only missing `StackDescription` and `TgtPrompt` fields; native costs,
target restrictions and resolution stay authoritative. Unknown scripts are not
translated by guessing the meaning of internal selectors.
Mana payment headings include Forge's current unpaid cost separately from the
collapsible effect description, so long card text cannot hide the amount. The
heading refreshes from the native cost field as payment progresses; it is not
parsed from descriptive text or used to authorize payment.
Truncated prompt headings, descriptions and action labels have read-only hover
explanations below their labels. These stay within the decision sidebar, do not
receive pointer input, and leave the fixed payment/pass controls visible.
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

Forge BO3 transitions use the engine-aware restart boundary above. Runtime
qualification uses the [native regression guide](../third_party/forge-runtime/native-host/TESTING.md)
and separately packaged corresponding sources. Native engine regressions,
client interaction evidence and release/platform checks establish different
coverage; one does not substitute for the others.
