# Module boundaries and growth policy

This document defines how Hexproof should absorb new product requirements
without recreating large, multi-responsibility source files. It defines current
ownership and review guidance; workflow and verification policy lives in
`development-policy.md`.

Rules-related conveniences also follow `rules-assistance.md`. That document
defines the product boundary between advisory assistance and enforcement, and
adds state, atomicity, privacy, and verification requirements to the general
module-growth rules below.

Deck-construction checks additionally follow `deck-formats.md`: format mapping
is a small domain module, catalog-backed validation is an asynchronous service,
and the deck-library model owns only cached results and presentation roles.

Limited products and events additionally follow `limited-events.md`: product
definitions, random distribution, private pools, and submitted-pool containment
must remain separate from ordinary saved-deck and tournament standings state.

## Principles

1. One module owns one primary reason to change.
2. Screens primarily assemble features. Small local presentation helpers are
   appropriate; authoritative state and cross-feature workflows belong to
   their models/controllers, not to the screen.
3. Visual delegates render data and emit intent; controllers coordinate intent;
   C++/Go models own durable or authoritative state.
4. Use a compatibility facade when it reduces migration risk across consumers.
   A small, verified change may update its callers together; forwarding-only
   shells are not mandatory for every extraction or rename.
5. Line count is a warning signal, not a quality score. Responsibility count,
   dependency direction, and testability decide whether a split is useful.
6. Size thresholds are advisory. An unrelated extraction is not a prerequisite
   for a focused fix, and thresholds may change with a documented rationale.

## Source-size policy

`tools/check-module-size.py` reads `tools/module-size-policy.json` and reports
non-blocking review hints locally, in CI, and during release checks. No line
count fails a build. Invalid policy or unreadable input still fails the check.
Generated protocol constants, translations, build output, and vendored/generated
data are excluded. Test sources remain visible but receive a 1.5x default
threshold for fixtures and scenarios; path-specific rules take precedence.

| Source kind | Advisory threshold | Review question |
|-------------|-------------------:|-----------------|
| QML screen/view | 1,000 lines | Are distinct visual regions or workflows entangled? |
| QML controller/shortcut module | 700 lines | Does it mix command families or state owners? |
| C++ implementation | 1,200 lines | Would a service/model collaborator improve testability? |
| C++ header | 800 lines | Is the public surface cohesive? |
| Go implementation | 1,200 lines | Are reducer/handler domains or lock responsibilities mixed? |
| Python/tooling | 800 lines | Are parsing, policy, and rendering responsibilities separable? |

Review hints on touched files in proportion to the change. A cohesive facade,
declarative view, fixture suite, or list of protocol structures may remain above
its threshold. Do not extract arbitrary fragments, omit tests, or compress
formatting to silence a hint. Explain meaningful boundary/threshold decisions
in the change; no separate owner exception is required for an extra line.

## Client table boundaries

The table uses the following dependency direction:

```text
Table.qml (composition and stable aliases)
  -> TableSceneShell.qml (visual-region composition)
      -> region views and popups
  -> narrow controllers
      -> WsClient command facade / typed models
```

### Stable responsibilities

| Module | Owns | Must not own |
|--------|------|--------------|
| `Table.qml` | Required dependencies, shared properties, controller composition, small composition helpers | Domain workflows, authoritative state, full delegate/menu/dialog implementations |
| Table menu facade | Compose library, area, and selected-card menu domains; preserve stable aliases | Reimplement command policy or grow one menu for every zone |
| Table shortcut facade | Compose view, library, game, and selection shortcut domains | Duplicate permission, modal, or selection-domain gates |
| `BattlefieldView.qml` | Battlefield-region composition | Zone commands, card-placement policy, full remote-dock implementation |
| Battlefield seat/card components | One seat or one permanent's presentation and pointer intent | WebSocket calls, authoritative state |
| Battlefield placement controller | Card category, automatic slot, stacking and collision policy | Sending zone commands or opening editors |
| Card move controller | Stable facade for move intent | Placement algorithms, pointer-event implementation |
| Attachment coordinator | Owner attach/detach intent and cross-lane overlay model | Controller changes, Aura/Equipment legality, card-text inference |
| Drop controller | Interpreting drag sources and drop destinations | Card classification or modal UI |
| `SideboardPanel.qml` | Sideboard overlay composition | Card delegate implementation, drag state machine, category projection |
| `LibrarySearchPopup.qml` | Private-library workflow composition | Card-list interaction, inspector rendering, or destination-menu rendering |
| `TournamentLobby.qml` | Tournament page composition, participant-derived state, list views | Event-desk controls or score-editor implementation |
| Tournament event components | Registration/organizer actions or result entry | Tournament snapshot ownership or transport implementation |
| `GameTableModel` | Typed snapshot projection and stable zone models | Transport, optimistic commands, visual layout |
| `WsClient` | Command and connection facade; publishes `roomSession` / `gameSession` | Table presentation, card placement, or owning snapshot fields as QML properties |
| `LimitedDeckBuilder.qml` | Construction layout, filtering, previews, scroll preservation and transport wiring | Independent copies of selections, recovery state or submission baselines |
| `LimitedDeckConstructionController.qml` | Local selection, commanders, basic printings, draft recovery and submission reconciliation | Layout, WebSocket access or mutation of the authoritative Limited pool |

Deep QML delegates receive a narrow controller object and emit intent. They
must not reach through unrelated siblings or keep independent copies of
authoritative room/game state.

Manual-table optimistic overlays are temporary presentation. A correlated
failure rolls back immediately; success ends request correlation but leaves
the overlay until the authoritative snapshot reconciles it. Unreconciled
overlays have a bounded 2,500 ms fallback and never become durable game state.

## Client service and build boundaries

- `hexproof_deck_core` owns deck data, parsing, format mapping, and mutation
  rules without depending on the QML-facing library model.
- `hexproof_deck_library` owns saved-deck orchestration, editing, import/export,
  metadata persistence, validation state, and read-only projections.
- `hexproof_session` owns transport/session state and command facades.
- `FeedbackService`, linked in `hexproof_session`, owns the separate local
  feedback state machine, consent/frozen identity, persistence, attachment
  normalization and receipt transport. It has its own bounded I/O lane and
  network manager; it must not use `WsClient`, account cookies or room-supplied
  endpoints. `FeedbackWorkflow.qml` owns app-level modal composition; composer,
  history and preview components present projections and emit user intent.
  The executable supplies trusted configuration; `Main.qml` supplies bounded
  context and combines the interaction gate with existing table input gates,
  without owning submission state.
- `ClusterTransfer` owns the private pending command, ticket, destination,
  identity checks and transfer timeout. `WsClient` supplies trusted directory
  context and performs transport I/O. A verified welcome consumes the retained
  wire command once; a failed transfer does not create another replay.
- `hexproof_table_models` owns typed table projections and optimistic overlays.
- `hexproof_card_services` owns catalog storage, installation, lookup,
  resolution, image caching, and legality lookup. The executable composes these
  libraries; tests link the same domain libraries instead of recompiling private
  source lists.
- `hexproof_update_service` owns application Release discovery, platform-asset
  selection, update-download streaming, and checksum verification. It does not
  replace a running installation, deploy servers, or own card-database updates.
- `BackgroundTaskPools` supplies separate bounded pools for catalog search,
  catalog maintenance, deck parsing, and deck persistence. Do not use the
  process-global Qt thread pool for these workflows. Interactive searches are
  generation-tagged latest-wins operations so stale completions cannot replace
  newer input.
- `CatalogSearchController` owns card/token query parameters, generations,
  results and worker admission. Each channel retains one running task and one
  replaceable latest request. Catalog/language changes invalidate the old
  generation; worker closures capture values rather than the facade. Search
  state is committed before notifying observers so a synchronous new query
  cannot be overwritten by an older completion. `CardCatalog` retains its QML
  API, error aggregation and coordination with install/art services.
- Synchronous deck import is a C++/test surface. QML invokes asynchronous import
  so parsing a large Commander list cannot block the GUI thread.

## Server boundaries

- `protocol` defines wire payloads and validation only.
- `feedback` is an independent HTTP/schema boundary used by
  `cmd/hexproof-feedback`, without game/account storage or Forge processes.
  Its store owns durable acceptance/publication, capability authentication,
  retention, closure/removal and per-record synchronization. HTTP validation and
  bounded admission precede acceptance. V2 publishes authorized public content
  to GitHub and connects native AI work through restricted interfaces; Multica
  owns development orchestration. Accepted receipts and confirmed publication
  are separate states. Legacy V1 storage/SMTP workers remain isolated from V2;
  old private reports never become public automatically. Keep this service
  separate from game hub handlers and the game protocol.
- `room` reducers own authoritative game transitions and hidden-information
  projection. They contain no network I/O or wall-clock reads.
- `server` handlers decode commands and fan out reducer results. Hub methods may
  coordinate locks but should not reimplement reducer behavior.
- `limited` owns product validation, pack generation, sealed pools, draft
  queues, pool-contained deck construction, and role-specific projection. It
  has no network I/O and does not own Swiss pairing or tabletop state.
- `tournament` hosts every standard online `limited.Event` and must not copy
  its private pack/pool state or reimplement its reducers. The dormant casual
  coordinator is a compatibility surface, not a second product workflow.
- Card moves are planned and validated by the room reducer before mutation.
  Single-card and batch commands share source-seat, destination, ownership,
  approval, face, and library-placement validation helpers; handlers must not
  fork those rules.
- IP-keyed fixed-window limiters have bounded retained state and fail closed for
  an unseen identity while full. New public-hub limiters must use the shared
  bounded implementation rather than adding another unbounded map.
- After a committed game transition, role-specific `game.snapshot` fan-out is
  fail-closed: projection errors disconnect members instead of leaving them on
  a silent stale table.
- Lock order is tournament `opMu` (when pairing rooms are created or pairing
  `RoomID` is updated) → room `opMu` → `Hub.mu` (registry lookup) →
  `entry.mu`. `resumeMu` is a leaf: it may be taken while `opMu` is held
  (`removeRoom`, `restoreResumeHold`), but no room lock may be acquired while
  it is held. `expireResumeHold` therefore releases it before
  `lockRoomOperation`, and must itself run only after any room `opMu` is
  released. Pairing-room deletion is two-phase: `removeRoom` may run while
  room `opMu` is held and only drops the hub entry; `commitPairingRoomCleanup`
  takes tournament `opMu` after room `opMu` is released. Callers that already
  hold tournament `opMu` must not commit that cleanup.
- Authenticated command admission takes a cancellable per-account gate before
  domain locks, preserving handover ordering without shared identity buckets.
  Account storage uses its own per-account admission; the registry mutex never
  spans disk writes. Cluster publication has a separate ordered gate; cached
  state locks never span network calls. Independent RPC admission is bounded.
  Transport cancellation stops pending admission and remote reads, while
  admitted domain commits and post-commit cleanup retain their bounded owner
  lifecycle.
- Split files by domain inside the existing package before introducing another
  package. Package boundaries should express trust or dependency boundaries,
  not merely reduce line count.

## Feature-change checklist

Use these questions when reviewing a feature. Record a short design for new
state/trust boundaries or substantial architecture changes; a small repair can
answer them through its tests and change explanation without a separate plan:

1. What state changes, and which existing model/reducer is authoritative?
2. Is any information private, public, optimistic, or derived?
3. Which existing module owns the user intent? If no single module does, create
   a narrow collaborator rather than adding another responsibility to a large
   facade.
4. Does the feature add a new visual region, reusable delegate, or workflow?
5. Does growth reveal a real cohesion or testability problem in a touched file?
6. What protocol fixture, reducer test, typed-model test, or QML interaction
   test protects the boundary?
7. Does the English specification and user guide need to change?

For a rules-related warning, confirmation, derived reminder, or atomic helper,
complete the more specific feature design record in `rules-assistance.md` as
well.

## Split triggers

Consider extraction when these signals reveal multiple responsibilities or
poor testability. Neither a count nor a combination automatically mandates a
refactor before the requested fix:

- the file is above its review threshold;
- the change adds another command family or modal workflow;
- a delegate needs several unrelated controller dependencies;
- a controller exposes unrelated public workflow families;
- tests require constructing unrelated features to exercise one behavior;
- merge conflicts repeatedly occur in independent product work.

Do not split solely to move lines. A successful extraction has an explicit
input surface, one owner, no duplicated state, and a smaller dependency graph.
Duplicating authoritative state remains a correctness problem regardless of
file size and must be resolved, not merely reported as an advisory hint.

## Growth review workflow

1. Run `python3 tools/check-module-size.py` as part of relevant static checks.
2. Review touched hotspots for ownership, dependencies, and testability.
3. Extract only when it improves those properties; keep unrelated cleanup out
   of a narrow repair and record a follow-up if necessary.
4. Thresholds may be adjusted with a rationale in the change, in either
   direction. Do not add hidden line-count failures to architecture tests.
5. Verify affected behavior and boundaries after an extraction. CI and release
   packaging use the same advisory checker as local development.

## Test structure and performance baselines

- Split tests by behavior domain while retaining shared fixtures in a small
  header or QML harness. Do not make one test translation unit or QML `TestCase`
  the integration point for unrelated features.
- Portable Qt benchmarks record relative baselines without hard-coded elapsed
  time thresholds. Current baselines cover a 100-card Commander parse, empty
  deck-library construction, a four-player battlefield with 100 permanents per
  seat, and sideboard grouping for a Commander-sized deck.
- Cache/search concurrency is protected primarily by deterministic queue,
  cancellation, and latest-generation tests. Wall-clock assertions are not a
  substitute for those invariants and are intentionally avoided in shared CI.
