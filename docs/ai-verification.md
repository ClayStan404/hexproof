# AI-assisted project verification

## Scope and coverage strategy

This guide describes the maintained native scenarios for manual tabletop,
optional Forge rules mode and shared offline workflows. Select scenarios for
the requested change using [development-policy.md](development-policy.md).
The inventories below help identify affected behavior; they do not require a
full campaign for each fix or carry forward a past campaign's exclusions.
Testing one format cannot establish commander, Limited or tournament behavior.
Share common flows and add the relevant format-specific assertions.

| Coverage family | Required formats and differences |
|---|---|
| Constructed deck policy | Custom, Standard, Pioneer, Modern, Legacy, Vintage, Pauper: selection, persistence, matching rooms, size/copies/sideboard, catalog legality, missing-catalog warning |
| Two-player table | Deep Modern manual flow; matching-room/start/result smoke for every commander-free format; BO1 and BO3, sideboarding and loser starts |
| Forge constructed | Actual official-runtime matches with distinct decks and catalog-eligible pools; typed decisions, priority, costs, targets, stack order, resolved outcomes, BO1/BO3 and recovery |
| Duel Commander | Two seats, 20 life, 100-card policy, one/two commanders, independent taxes; commander selection between BO3 games without changing the registered cards |
| Ordinary Cube | Draft/build policy and 40-card 1v1 table assignment; source Cube is not a match deck |
| Set Draft / Sealed | Installed product selection, all seats opening/picking, pool conservation, deck building, saved recovery, assignment and actual table entry |
| Events | Creation, registration, check-in, start/cancel, pairing/byes, table join, result reporting, standings, next round and completion |
| Solo playtest | Each table-mode mapping, private one-seat room, no browser listing, start/actions/exit |

The English behavior specifications remain the test oracle. In manual mode,
phase advancement does not automatically draw or untap; resolving a spell does
not execute Oracle text; 21 commander damage is a warning, not elimination.
Never change a test to accept behavior just because every client shows it.
In Forge mode, assert independently expected life, zone, controller, counter,
token, target and stack changes after real native resolution. An offered action
or an accepted response alone does not prove that its effect resolved correctly.
Use the pinned engine's card scripts and the recorded catalog as versioned
inputs; distinguish mechanism fixtures from format-legal and competitive decks.

## Product inventory

Track screens together with their states and actions. A screen visit alone is
navigation coverage, not a claim that its functions passed.

| Area | Screens / workflows | Required assertions and variants |
|---|---|---|
| Entry and preferences | MainMenu, Connect, Settings, ShortcutSettings, Sponsors | Offline/connected, validation/errors, language/theme/scale, keyboard conflicts, persistence, compact layout and focus |
| Decks | DeckLibrary, ImportDeck, DeckEditor | Empty/large libraries, file/paste import, printing identity, save/reopen/export, add/delete/undo where offered, main/side counts, commander selection, multicolor intersection, advanced filters, gallery/list scroll identity |
| Images | CardArtManager, CustomCardArtManager | Cold/warm cache, missing/corrupt files, import/export preview, cancel/retry/failure, conflicting art, worker progress and responsiveness, managed-location migration |
| Ordinary rooms | RoomBrowser, CreateRoom, JoinRoom, WaitingRoom, MatchLoading | Correct modes, password/errors, seats/spectators, deck restrictions, readiness, generation cancellation, deduplicated local hits versus downloads, leave/disband |
| Manual games | Table and its dialogs/docks | Opening/mulligan, draw/search/consent, drag every zone, stack, face-down privacy, tap, life/counters, command zone/tax/damage, control/attachments, combat/targets, phases/turns, random tools, chat, results/BO3 |
| Forge games | RulesTable, ForgeDuelTable and typed decision controls | Current legal actions and opaque identities, priority/yields, payment/cancellation, targets, stack relationships, private choices/reveals, ordering, scry/surveil, naming, combat damage, command zones, terminal results and reconnect |
| Limited | LimitedHub, TournamentCreate, CubeRoom and builders | Product/source validation, opening/passing/picking, pool and printing conservation, filters/lands/outside cards, submission, table entry and recovery |
| Tournament | TournamentBrowser, TournamentCreate, TournamentLobby | Player and organizer actions, registration/check-in, paired/unpaired states, reports/disputes, progression and completion |
| Lifecycle and platform | All applicable screens | Reconnect/restart, invalid/stale commands, owner/opponent/spectator projection, profile lock, persistence, shutdown during work, scaling/window changes, packaging/startup |

Inventory new screens from `apps/client-qt/qml/screens/` when expanding coverage; do not derive
coverage percentages from a historical screen count.

## Rules-mode review matrix

Record concrete decks, assertions and results for the selected scope. Use
fresh profiles/games and relevant recovery or negative branches. Repeat when
failures, variability or the requested coverage justify it, rather than imposing
a fixed number of rounds. Review screenshots as well as machine results;
reduce failures before rerunning the affected scenario and neighboring states.

| Family | Required independent outcomes |
| --- | --- |
| Modes and formats | Manual and Forge remain separate; 1v1 constructed and Duel Commander start with their actual policies and initial life. Catalog legality is tied to its snapshot. |
| Priority and stack | Respond/counter, multiple targets, trigger order, full control and cancellable yields; exact stack objects and visible targets survive rerendering. |
| Costs and choices | Colored/X/alternative/additional costs, cancellation with rollback, optional and mandatory selections, exact same-name copies, name/color/number inputs, scry/surveil and read-only acknowledgement. |
| Card outcomes | ETB/draw/discard/tokens/counters, activated/triggered abilities, replacement/prevention, graveyard/exile casting, Adventure/MDFC/face-down transitions; assert relevant final state, not just a prompt kind. |
| Combat | Attacks/blocks, multi-block capacity, ordered/free damage and trample/deathtouch guidance; independently check destroyed objects and life deltas. |
| Commander and matches | Repeated tax, zone-return choices, independent commanders, natural results, BO3 sideboarding/loser starts and live/sideboard/result recovery. |
| Privacy and invalid input | Owner/opponent/spectator projections, stale prompts/targets, duplicate/foreign choices, seat/game changes and disconnect during private input. |
| Manual operations | Equivalent player-driven stack/zone/counter/face/attachment/control actions, consent/privacy, turns and results; automatic Oracle-text execution is not the manual contract. |

Combine three forms of evidence: (1) real native Qt controls over the loopback
hub and official Forge, (2) real-engine Go/WebSocket conformance and narrowly
constructed native rule regressions, and (3) deterministic client/server tests.
Keep these layers separate. Constructed boards qualify their exercised rules;
they do not count as full native matches or broad card-pool certification.
List unexercised mechanics and products explicitly; no finite campaign proves
every Magic card combination or replaces release/platform qualification.

The engine test commands and their boundaries are in
[the native host guide](../third_party/forge-runtime/native-host/TESTING.md).
For actual system-input routing, use [the system-input guide](system-input-verification.md).
Completed review reports are available through the [historical source index](README.md).

## Execution layers and evidence

1. **Deterministic component and protocol regression.** Existing CTest/Go tests
   establish model invariants and actual WebSocket behavior. New constructed
   format integration scenarios use the real hub and per-viewer snapshots.
2. **Native Qt input scenarios.** The optional `hexproof_native_audit` target
   builds the same production `main.cpp`, services, QML, translations and
   shaders with a test-only adapter. Drivers find current visible controls,
   send Qt mouse/keyboard events, and wait for independent visible/model/server
   outcomes. No direct `clicked()`/`activated()` or model mutations count as
   input coverage. Explicit profile fixtures are preparation only.
   The adapter's `interruptTransport(ws)` aborts a connected loopback test
   socket and records fault injection separately from input. The production
   reconnect controller must restore membership, private projections, and the
   pending decision; the driver cannot manufacture a reconnect outcome. This
   helper is linked only into audit executables.
3. **AI exploration and triage.** An AI selects uncovered branches, inspects
   owned-window screenshots and structured observations, runs/revises bounded
   scenarios, minimizes failures, fixes confirmed bugs, and repeats the failed
   scenario plus relevant regression checks. A confirmed issue becomes a
   repeatable regression scenario; observations without a reliable oracle
   remain UX suggestions or investigation items.

Native Qt events validate real rendering and event handling, but do not prove
OS-level input routing, compositor focus, window occlusion by another app, or
system file dialogs. The optional GTK file-chooser adapter records its own
`native-gtk-input` evidence for real widget handlers, explicitly without an
OS-routing claim. Record OS/manual coverage separately when actually exercised.
Offscreen component tests never count as native
visual evidence. Setup through `LocalTestSession` is useful but does not prove
that creation/check-in buttons work.

Native scenarios and AI screenshot review default to maximized windows on the
actual test display, matching normal player use. The adapter waits for the
maximized state and settled geometry before starting the driver. Multi-client
runs keep every client maximized and switch activation for each seat's input
burst. Drivers must preserve this baseline unless they explicitly test a
window-state transition. Minimum-size, fixed-size, scaling and F11 fullscreen
checks provide supplementary coverage when relevant.

The adapter resolves one visible, enabled target inside its current viewport,
with optional identity fields and scoped lookup. Re-resolve virtualized rows
after scrolling and mutations. Use printing identity for deck rows and physical
card identity plus game generation for table cards. Wait for navigation
transitions to finish before acting. An accepted input event is not success:
each scenario must verify the resulting state within a bounded timeout.

Guard scenario dispatch against reentrancy: Qt input helpers can process the
event loop while an action is in progress. On a shared workstation, serialize
each seat's focus-sensitive input burst; network sessions remain independent.
The runner holds a workspace display lock so separate scenarios cannot steal
focus during a drag or shortcut. Profile isolation alone does not isolate
desktop focus. Wait for scrolling to settle before clicking into a Flickable.

The adapter is built only when `HEXPROOF_BUILD_NATIVE_AUDIT=ON`. It has no
network control listener and is not installed or packaged as the application.
Trusted local QML scenarios can access application context objects, so this is
a testing facility, not a sandbox for untrusted scripts. Player decisions must
use their own projection; a separate oracle can compare public fields across
seats without leaking hidden data to the acting players.

## Running the first scenarios

For clean database installation, real card-layout fixtures, consecutive
process restarts and file operations, see
[native lifecycle verification](ai-verification-lifecycle.md).

From the repository root, build incrementally:

```sh
cmake -S apps/client-qt -B build/client-qt -G Ninja -DHEXPROOF_BUILD_NATIVE_AUDIT=ON
cmake --build build/client-qt
```

The Linux runner creates a new output directory, independent XDG profiles, a
read-only SQLite backup when requested, and optionally its own loopback hub.
It never joins a public server or reuses normal reconnect credentials. Images
in explicit fixtures are copied independently, so fault injection cannot alter
the source image bytes. Existing output directories are refused.

Omit window sizing flags for the primary maximized run. `--windowed` selects an
explicit fixed-size probe with a 1440×900 logical-pixel default; `--width` or
`--height` also selects that mode. For example, use `--width 900 --height 620`
for a separate minimum-size run. `--scale` can be combined with either mode;
record the actual display and window geometry when comparing screenshots.

```sh
python3 tools/ui-automation/run-native.py \
  --scenario tools/ui-automation/scenarios/OfflineLibrary.qml \
  --catalog /absolute/path/to/cards.sqlite --timeout 420

python3 tools/ui-automation/run-native.py \
  --scenario tools/ui-automation/scenarios/manual-match.qml \
  --server-binary build/server/hexproof-server \
  --catalog /absolute/path/to/cards.sqlite \
  --fixture-dir /absolute/path/to/prepared-fixture \
  --players 2 --variant modern
```

`TableBackgrounds.qml` needs no catalog, fixture directory, or server. It
prepares a local view fixture in the production manual table, then uses native
Qt input to select all seven images and restore the default background without
an image in both appearances. It also checks that new profiles use the default.
Pass the same file through `--next-scenario` to check restored preferences and picker state
after process restart. This verifies appearance and settings interaction;
the prepared table is not evidence of room creation or gameplay commands.

The offline scenario needs metadata for its explicitly listed printings and
`Dovin's Veto`; optional `--fixture-dir` art avoids external downloads. The
match scenario expects exactly one matching selectable deck per tested format
with cached art for preload. Use `--players 2 --variant duel` for Duel Commander and prepare the corresponding
fixture. `--card-language zh` selects Chinese card metadata/art while keeping
the scenario UI in English. These are deliberately small deterministic decks
for operation coverage, not strategic gameplay benchmarks.

Keyboard shortcuts require an active native window. The adapter requests and
checks activation before typing; it fails explicitly when the window manager
refuses. On a workstation with XWayland, use `QT_QPA_PLATFORM=xcb` for the
runner when Wayland denies automated activation. Keep the actual backend in
the report; success on XWayland does not establish Wayland compositor support.
The documented workstation workaround `QSG_NO_VSYNC=1` may be used only as a
command-scoped test setting when required. Record it alongside the platform;
such a run does not certify production-default compositor performance.

For Forge, use `ForgeDuelMatch.qml` and `tools/run-local-forge-server.sh` with
the selected pinned runtime. Its `boros-zones`, `stack`, `pauper`, `modern-bo3` and
`duel-bo3` variants cover different deck/decision families; the Boros variant
requires `--deck-manifest tools/ui-automation/fixtures/boros-energy.json`.
The Pauper pilot uses separate eligible red/blue lists and checks exact hand and
library deltas after Preordain and creature ETB draws, plus the same Firebolt's
graveyard-to-stack-to-exile path. The pinned Preordain script presents a private
card subset and ordering callback; do not require a callback named `scry` as a
substitute for checking the actual script and resulting draw.
Room/deck seeding is fixture preparation. Actual decisions must use production
controls, and a required natural result cannot be replaced by a concession.
Record scenario-specific coverage requirements, every failed attempt and the
final runtime/binary/scenario hashes rather than counting historical passes.

Additional frozen-deck and Limited variants use the following inputs. Scenario
paths are relative to `tools/ui-automation/scenarios/`; supply an installed
read-only catalog source, isolated profiles and a new output directory.

| Scenario | Variant | Players | Fixture |
| --- | --- | --- | --- |
| `ForgeDuelMatch.qml` | `format-standard`, `format-pioneer`, `format-modern`, `format-legacy`, `format-vintage` | 2; use 3 for a spectator check | `--deck-manifest tools/ui-automation/fixtures/format-matches.json` |
| `ForgeDuelMatch.qml` | `duel-phelia` | 2 | `--deck-manifest tools/ui-automation/fixtures/duel-phelia.json` |
| `LimitedLifecycle.qml` | `set_sealed-forge-bo3`, `set_draft-forge`, `cube_draft-forge` | 3 | `--fixture-dir tools/ui-automation/fixtures/limited-lifecycle`; installed EOE product |

For server-hosted Forge, set `HEXPROOF_FORGE_HARNESS` and `HEXPROOF_FORGE_HOME`
to the matching packaged runtime's JAR and `forge-gui` directory. The Limited
[fixture guide](../tools/ui-automation/fixtures/limited-lifecycle/README.md)
defines pool construction, recovery, BO3 and natural-result checks. The
[card-corpus guide](../tools/forge-card-corpus/README.md) separately documents
synthetic card-resolution and replay checks; those do not count as live games.
Choose bounded run/watchdog timeouts for the scenario; opening hands and match
outcomes are not fixed. Record the actual Qt backend and renderer settings.

A fixture directory may contain `decks.json`, `card-cache.json`, `images/`,
and `custom-art/`; JSON paths use `@PROFILE@` for the destination app-data root.
No settings, locks or reconnect credentials are copied. File links and special
files are rejected. Production profiles must not be used as writable fixtures.

The runner executes scenarios and records artifacts; native AI tasks can use
the same commands and evidence. It does not schedule development or select a
model provider.

## Failure and performance protocol

Every run records source revision/dirty state, binary and scenario digests,
requested window mode/size/scale, actual window mode/geometry/DPR/platform and
display geometry, per-seat input trace, step assertions, screenshots,
client/server logs, process CPU/RSS
samples, heartbeat and final status. Logs and shared files remain in the
isolated run directory. Network logs are not a license to expose hidden cards
in a public report.

Startup observations and each input trace include the actual window state and
display geometry, so AI review can check that the tested viewport matches the
declared mode throughout the scenario.

An external watchdog detects stalled GUI heartbeats and total deadlines, then
stops only processes it created. Exit code zero without an explicit passing
scenario result fails verification. Input failures, QML warnings, crashes,
missing artifacts and setup failures cannot become passes. A timeout captures
the last completed step and available observations; a fully stalled GUI cannot
produce a fresh in-process screenshot, so retain the last valid one.

Separate timing fields:

- input dispatch time;
- input-to-visible feedback and authoritative acknowledgment;
- navigation/layout settling;
- heartbeat stalls and CPU/RSS trends;
- disk/network work, downloads and local cache hits.

Step polling intervals and screenshots add measurement overhead. Current step
durations are diagnostic measurements, not precise frame-time benchmarks. AI
thinking time is excluded from application latency. Before asserting a
performance regression, repeat the same input workload on the same machine,
build type, data, DPI, cache condition and concurrency; compare median/P95/max
and keep the raw samples. Separate a one-client performance run from a four- or
eight-client load run. Establish empirical budgets before making them gates.

## Iteration and completion tracking

### Release risk coverage

Small editor fixtures and basic-land match decks establish operation smoke
coverage. Select the following additional cases when their risks are affected,
and report them separately from normal-flow passes:

| Risk | Required independent outcome |
|---|---|
| Real library data | A copied 960-card Cube and diverse 100-card decks; localized main types/subtypes, multiple faces, same-name printings and unknown metadata; verify groups against card main types, not existing grouping code |
| In-flight interaction | Observe immediately after editing a query/filter, then during debounce, pending response, close and reopen; obsolete cards must not be clickable or rebuild hidden delegates |
| Cache recovery | Delete only a fixture image between launches, restore it at the same path through the availability path, and verify image display, missing counts and deck readiness together |
| Import transaction | Damage a late blob, fail the index commit, and close at worker/apply/save boundaries; compare the filesystem and reopened index with the pre-operation state, preserving existing/shared files |
| Repeated editing | Repeat color intersections, exact-printing increment/decrement, gallery/list switching and reopen on the large fixture; compare counts and printing identity with a separately recorded baseline |
| Performance | Repeat comparable workloads with no concurrent build or other GUI scenario; record action samples and heartbeat separately from screenshots and setup; report the actual tested scale and remaining gaps |

A component reused across screens does not prove that every screen uses the
same parser or state rules. For example, correct Limited land detection does
not certify saved-deck grouping. Test the same problematic input through each
user entry point that has independent logic. Existing user reports should
produce both a minimal regression and a neighboring-state variant; do not only
rerun the exact happy path that previously passed.

Use `LibraryStress.qml` with the isolated 960-printing singleton Cube and
independent manifest described in [the lifecycle guide](ai-verification-lifecycle.md#targeted-download-and-large-library-review).
It supports `--variant search` to isolate rapid search replacement.
Fixture-specific identities/counts must be explicit; a different library
requires a new independent baseline rather than accepting the current output.

Do not report release readiness when any applicable high-risk workflow is
unrun or blocked. A release report must name its residual gaps and the actual
platforms, data scales, cache conditions and interruption points exercised.
Neither a required bug quota nor a passing test count measures coverage.

Each execution report must distinguish **passed**, **failed**, **blocked by
environment/fixture**, **not run**, and **excluded** for concrete scenarios.
Report confirmed bugs separately from performance concerns and UX suggestions.
Do not convert navigation smoke, seeded data, or historical evidence into a
claim that the whole project passed.

For a discovered defect: save the failing run, determine whether the cause is
application behavior, fixture, runner, or environment, reduce the case, fix the
actual cause, rerun it, and commit the verified coherent change under the
owner's standing local-commit agreement. Publication and deployment follow the
current task authorization and [development policy](development-policy.md).
