# Changelog

All notable changes to Hexproof are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Hexproof versions the coordinated client and server together; both must match
exactly. Card-database releases use the separate **card-data** channel;
application changes that use new catalog metadata are included here.

## [Unreleased]

## [1.2.0] - 2026-09-10

Consolidates the application changes since 1.0.6 (source baseline **82f8110**).
Follow-up fixes are combined; reverted theme experiments are not included.

### Added

#### Cube, drafting, and deck construction

- Separate free-play Cube rooms with room-browser/code entry, seated players,
  Ready controls, room chat, and a rules summary. **Create room → Cube** drafts
  first, then opens free play; Swiss Cube tournaments remain under Events.
- Commander Cube for two to four players: three 20-card packs per player,
  two-card picks, and decks of at least 60 cards including one or two commanders.
  The group plays at one 40-life Commander table with commander tax, damage,
  and elimination controls, without Swiss rounds or pod splitting.
- Up to two optional **The Prismatic Piper** fallback commanders, each with an
  explicit color choice. Same-name commander copies retain distinct identities,
  tax, and damage records. Commander eligibility, partner compatibility, and
  color identity remain advisory; pool ownership and deck minimums remain enforced.
- Private provisional commander planning during Commander Cube drafting, with
  candidate/all-card views, previews, and advisory color-identity counts.
  Final commanders and Piper colors are confirmed during deck construction.
- Explicit automatic drafting and reclaim controls for free-play Cube seats.
  Short disconnections retain seats and private pools without enabling it.
  Hosts may confirm automatic drafting only for a seat continuously offline
  for over three minutes. Players can explicitly sit out during construction
  or free play; automatic drafting does not build or submit their decks.
- Automatic initial ready-up room entry after all participating players submit
  in two-player regular Cube or two-to-four-player Commander Cube. Decks are
  locked, but each player still readies individually. Larger regular Cube
  groups and subsequent matches use invitations with participant consent.
- Automatic basic-land suggestions for Sealed, Draft, and Cube construction,
  based on selected spells' colored mana costs and existing lands. Suggestions
  adapt to deck changes and the format minimum; manual adjustments disable
  automatic filling until re-enabled. Unknown color requirements are not guessed.
- Arena-inspired draft and deck-editing workspaces with large card galleries,
  hover previews, mana curves, and compact printing-aware deck rows. Rows show
  localized names, actual card colors, and full mana-symbol costs when the
  installed catalog supplies them, rather than using Commander color identity.
- Shared multiselect color, type, mana-value, and rarity filters for picked
  cards, Limited pools, saved decks, and catalog browsing. Catalog browsing
  keeps the live deck list alongside search results.
- Double-click draft confirmation and a post-draft choice to retain picks in
  the main deck and trim it, or rebuild from the available pool. Unwanted
  cards can be dragged back to the pool.
- Automatic local recovery of initial Limited construction, including selected
  physical cards, basics, commanders, and the post-draft choice. Recovery is
  isolated by server, event, and participant and expires after seven days.
  Pending edits require confirmation before they are discarded.
- Event-scoped chat for organizers, participants, and viewers, with bounded
  recent history on re-entry. Registration displays player names; organizers
  can run an event without competing or seeing private card pools.

#### Card art, tokens, and emblems

- **Export card art** from a deck's library row or editor, producing a
  **.hexproof-artpack** for that deck or Cube rather than the entire cache.
  Available languages, independent reverse faces, and saved tokens/emblems
  are included; missing or invalid images are reported. Export does not
  download missing images or include the deck list or database.
- Local-only custom card art with exact-printing or verified all-printings
  scope. JPG/JPEG, PNG, and WebP images can replace independent faces of
  double-faced cards/tokens and separate meld results; split, adventure, and
  prepare cards retain their physical single-image layout.
- A separate custom-art manager for folder/mapping import, previews, conflicts,
  individual/all restoration, and **.hexproof-custom-artpack** sharing. Overrides
  require explicit application and never change game identities, another
  player's display, or ordinary downloaded-art records.
- Configurable card-image storage with verified copying of ordinary and custom
  images, profile-specific directory ownership, and restart-based activation.
  Original images are retained; unavailable or locked destinations produce an
  explicit error instead of silently replacing the cache.
- Public emblems as distinct command-zone objects, separate from battlefield
  tokens, with owner-only removal. A shared Tokens and Emblems catalog offers
  kind filters and saved per-deck auxiliary printings, including double-faced
  tokens. Planeswalker-to-emblem recommendations are not automatic.
- Chinese token/emblem artwork, names, types, and rules when available, following
  the independent card-language setting. English art can coexist with Chinese
  rules text when no Chinese picture exists; resolved text is retained offline,
  and missing translations fall back to English.
- Inline deck-cache progress, percentage, and current operation status in the
  deck library and editor.

#### Optional Forge rules

- Forge BO3 match flow with registered-deck sideboarding, next-game starting
  player selection, host restart, scores/results, and retained public activity
  and chat. EDH remains BO1; this does not enable Forge by default.
- Read-only Forge spectator hand browsing when the room explicitly permits
  current hands, without exposing libraries, sideboards, or private decisions.
- One-command local Forge preparation/start with **--prepare**, pinned downstream
  sources, checksum-linked runtime/corresponding-source packages, and a manually
  dispatched Linux amd64/arm64 runtime verification workflow.

### Changed

- Build CI, release packages, and card databases with a shared Qt 6.11.2
  toolchain. Official macOS packages now require macOS 13 or newer.
- Consolidate Set Sealed/Draft creation under Events. Swiss round counts are
  selected automatically from checked-in attendance; round time remains
  configurable. Cube free-play rooms no longer appear as tournaments.
- Simplify the connected home menu and use a responsive two-column room-creation
  form. Room names start empty, redundant host-seat/spectator explanations are
  removed, and existing permission defaults are preserved.
- Group sponsors from highest to lowest: **Omniscience**, **Dockside Extortionist**,
  and **Ragavan, Nimble Pilferer**. Assign 豆豆(dodo) and M0nta9e不太奇 to Dockside;
  add Orangezihan, 寡妇门前是非多, and 贝蒂小熊-乱世不败 to Ragavan with bundled
  avatars and Afdian links. Keep the existing one-time acknowledgement behavior.
- Bound server event retention and abandoned-session cleanup. Completed/cancelled
  events expire after 24 hours by default; unattended registration/running
  events receive a configurable reconnect grace. Authenticated players in
  pairing rooms keep their event alive; ordinary viewers do not extend it.
- Keep large Cube imports and startup with large saved deck libraries responsive
  using indexed identity merging, virtualized large grids, and bounded deferred
  image resolution instead of synchronous whole-library lookups.
- Load table art asynchronously, with bounded cache discovery, match loading,
  face expansion, and sideboard type lookups. Exact art and visible cards retain
  priority; explicit token/emblem details outrank result-list prefetching.
- Reduce manual-table startup work by binding the game log directly to its C++
  model and creating sideboards and opponent docks only when needed.
- Reduce draft traffic with public progress updates instead of repeatedly
  sending unchanged private pools. Preserve unchanged card models and previews.
- Send joining spectators targeted snapshots and reuse identical encoded public
  envelopes within a broadcast, without sharing private player projections.
- Save card-art indexes through a bounded, coalescing background writer with
  generation-safe maintenance and shutdown. Reuse per-round Swiss pairing costs
  instead of repeatedly scanning match history.

### Fixed

#### Navigation and tabletop interaction

- Keep sponsor profile links within narrow cards at maximum UI scale, including
  longer English button labels.
- Preserve the saved/custom server selection at cold start and during latency
  refresh, keeping the displayed server and actual connection address aligned.
- Keep spectator resume credentials in memory only: reopening the application
  no longer reconnects to an old observation session. Player reconnects persist.
- Restore right-aligned home-menu settings and connection controls, with wrapping
  for narrow windows, enlarged text, long names, and update notices.
- Keep setup, deck editors, Limited workspaces, event controls, sideboarding,
  library searches, support QR codes, and confirmations usable in small/scaled
  windows. Import-form scrolling works across the content area and continues
  past the deck-text editor's scroll boundaries.
- Show disconnected room/event browsers with a connection action instead of a
  misleading empty list; guard unavailable actions and offline list requests.
- Use opponent-above/self-below battlefields for every two-player manual table,
  including Commander Cube. Three/four-player games retain their multiplayer
  layout after eliminations. Name and turn indicators overlay the battlefield
  instead of reserving a separate strip of playing space.
- Fit compact multiplayer cards, including tapped and optimistic placements,
  within their lanes. Preserve response-status indicators, keep game-log controls
  clear of opponent information, and retain read-only hand/public-zone inspection
  after a match ends.
- Reconcile incremental snapshots for selections, attachments, the game log,
  and Limited sideboards. Clear old selections, drags, menus, pending actions,
  and optimistic commands across restarts and BO3 game transitions, even when
  replacement games reuse card IDs.
- Expire private-zone grants and consent requests on restart, finish, and room
  return; serialize approval with room operations. Clear arrows and response
  status when the active Commander player's elimination advances the turn.
  Reject card moves into unused or eliminated seats before mutating state.
- Preserve locale-formatted integers and literal formatting tokens in manual
  activity. Display configured shortcuts in menus/counter hints and resolve
  shared QML translations through the correct contexts.

#### Decks, card data, and Limited events

- Preserve exact printings through import, printing changes, and drag-and-drop;
  merge duplicate rows of the same printing. Retain special collector symbols
  such as **Gifts Given (HHO) 7†** in decklists and cache requests.
- Backfill saved-deck and Cube rarity from the exact-printing catalog instead of
  marking Cube cards as universally special or unknown. Recognize genuine
  special/bonus rarities and leave unresolved data explicitly unknown.
- Retain official Limited products with large JSON-safe sheet weights, including
  **Final Fantasy (FIN) Play**, instead of falling back to a two-card promo.
  Use approximate collation only when no suitable Limited product is installed;
  reject overflowing combined sheet weights in generation and simulation.
- Scope event projections and mutations to the current membership and credential
  owner, including reconnect transfers and pairing entry. Keep organizers and
  observers out of private packs and pools.
- Reject oversized Limited submissions, incomplete basic-land printing identities,
  and overflowing score components. Hide score corrections after event completion
  or cancellation, and close stale result editors.
- Avoid stale deck-legality results after format changes, stale token searches
  or metadata after language/catalog changes, and obsolete cache completions
  after match changes. Pause face expansion during database installation instead
  of treating a temporary empty lookup as a complete single-face result.
- Keep tournament decklists readable and tolerate ordinary basics without exact
  printings in display metadata. Bound local draft cleanup for malformed/extreme
  timestamps and preserve valid drafts through reconnection.
- Return completed Cube tables to their original pod without losing the pool,
  forcing another match, or incorrectly reporting that the entire room closed.
- Reuse valid images during art-pack import without writing unused duplicates;
  replace corrupt cached images with validated imported content and refresh
  repaired same-path images.
- Restore custom art independently of ordinary downloads, searches, cached-path
  queries, and library maintenance. Use a separate bounded worker and refresh
  affected display bindings in batches, prioritizing the open deck, instead of
  restarting whole-library hydration. Keep storage-migration write guards.
- Prevent simultaneous clients using one profile from overwriting saved decks
  through a profile lock; retain independently isolated multi-client operation.

#### Optional Forge rules

- Preserve empty prompt arrays and real typed stack/zone state so opening and
  subsequent decisions render and remain actionable. Localize public activity
  and map combat steps to the existing phase display.
- Keep target, combat, ordering, and damage candidates visible, bound tall prompts
  and translated buttons, and prevent duplicate or stale responses.
- Hide face-down spell identities in casting previews and the public stack.
  Keep raw engine diagnostics and private decisions out of public logs; live
  spectator hand permission does not expose those hands in retained logs.
- Honor Duel Commander's 20 starting life and publish snapshots from stable
  game-thread boundaries. Reject obsolete responses across games, restarts,
  and runtime replacement; restore sideboard/result reconnects safely.
- Return affected rules games to their waiting rooms after runtime failure
  without disturbing manual games, and allow a healthy replacement runtime.
  Preserve older runtime installations when updating patches.
- Release Forge background loading from its own snapshots and cache only cards
  visible to the viewer. Keep overflowing hands reachable by scrollbar/wheel.

### Removed

- The client replay browser, viewer, and dedicated shortcuts. **Pack simulator**
  now occupies that main-menu position and remains available offline; its
  duplicate Settings entry is removed. Live logs/chat, server archives, and
  the privacy-filtered compatibility replay API remain unchanged.
- The duplicate home-menu Limited creation shortcut; use Events for Set
  Sealed/Draft and Create room for free-play Cube.

### Development and deployment

- Extend the isolated multi-client launcher with opt-in automatic local
  Sealed/Draft setup: connect, create, register, check in, and start every seat,
  then leave picking/building to the tester. Restore local endpoint/player
  defaults, validate missing arguments, preserve per-profile identities, and
  fall back to independent image copies when hard links are unavailable.
- Clone relocated ordinary/custom image trees safely for new test profiles,
  without sharing mutable indexes, credentials, or external-storage locks.
- Validate configured server URLs consistently with the client's strict parser,
  including malformed ports, whitespace, escapes, and IPv6 handling.
- Keep Forge test-server deployment explicitly opt-in across test binary updates.
  Default production deployment stays manual-only; ordinary test deployment
  does not recreate the removed Forge source-download website.
- Add pinned rules-engine qualification tools, reference workloads, real-engine
  probes, and English/Chinese findings. These evaluate alternatives; they do not
  add selectable production engines or certify every MTG rule.
- Make verification risk-based, with static/client/server scopes and changed-area
  CI selection. Documentation-only changes avoid application builds; full release
  checks remain. Source-size thresholds are advisory, and native GUI checks are
  supported for relevant layout/interaction work.
- Harden translation, license, protocol, QML-text, export, and deployment checks;
  fix runtime QML warnings and stabilize asynchronous/layout tests. Expand
  lifecycle, privacy, concurrency, and isolated native-workflow regression coverage.

## [1.0.6] - 2026-09-03

### Changed

- Set Sealed, Set Draft, and Cube Draft may start once two registered players
  are checked in. Set Draft accepts a two-to-eight seat cap. A saved Cube
  becomes selectable at 90 physical cards, the two-player pack requirement.
- Draft columns stay usable on shorter windows.

[Unreleased]: https://github.com/ClayStan404/hexproof/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/ClayStan404/hexproof/compare/v1.0.6...v1.2.0
[1.0.6]: https://github.com/ClayStan404/hexproof/releases/tag/v1.0.6
