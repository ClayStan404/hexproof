# Changelog

All notable changes to Hexproof are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Hexproof versions the coordinated client and server together; both must match
exactly. Card-database releases use the separate **card-data** channel;
application changes that use new catalog metadata are included here.

## [2.2.0] - 2026-09-24

### Upgrade notes

- Upgrade clients and the Go server together to **2.2.0**; application versions
  must match exactly. The WebSocket protocol and native Forge adapter revision
  remain unchanged from 2.1.0.

### Fixed

- Restore the startup sponsor acknowledgement once per application version,
  while retaining reminders for newly added sponsors. Both reasons share one
  popup, and only unacknowledged sponsors receive a new-supporter label.
- Preserve existing sponsor acknowledgements when upgrading from older
  clients. Closing the popup acknowledges the running version and the displayed
  roster; entering a room before it appears leaves the notice for the next
  launch, and sponsors added while it is open remain pending.

## [2.1.0] - 2026-09-23

### Upgrade notes

- Upgrade clients and the Go server together to **2.1.0**; application versions
  must match exactly. The `hexproof.v1` WebSocket protocol gained messages for
  AI seats, model opponents, controlled turns and private replays.
- The bundled native adapter overlay advanced to revision 21, adding AI
  presets, exact printings, structured startup diagnostics, visual replays and
  controlled turns. Rebuild server-managed and creator-hosted Forge runtimes
  from this release to enable those behaviors; older runtimes keep serving
  ordinary Forge games with generic fallbacks.

### Added

- Connect operator-owned home hubs using direct WebRTC, authenticated TURN, or
  ordinary WSS forwarding. Show the active route and preserve room identity,
  hidden information, and authenticated reconnect across transport changes.
- Add native Forge AI practice against Beginner, Normal, and Hard presets,
  with separate human/AI decks in ordinary constructed BO1 rooms. Server-run
  AI requires the matching capable Forge runtime.

- Add Gameplay settings with explicit Smart priority / Full control choices and
  saved own/other-turn phase stops shared with the table. Prefer P2P by default
  in supported human player-hosted rooms, retaining a saved relay-only choice.

- Add the owner's BGM 2 and BGM 3 recordings to the background-music selector.
- Add skippable Sealed pack reveals, per-basic printing selection with
  environment defaults, and environment-filtered Limited token searches.
- Add public-board inspection during manual and Forge sideboarding, plus an
  atomic Limited mainboard clear action for rebuilding between games.
- Let the previous loser choose play or draw in manual BO3, start EDH with
  two players, and continuously reveal the manual library's current top card.
- Configure experimental local Ollama/LM Studio and online OpenAI-compatible
  model opponents for Forge constructed BO1 practice. Responses may fail and
  pause the game; full-game reliability with real models remains unverified.
  Model connections run on the desktop with session-only API keys, restricted
  AI observations, bounded requests and explicit recovery when a decision fails.
  Native Forge AI and its presets are unchanged.
- Let a human take over a Forge AI's turn: control decisions route to the
  controlling seat while the native engine keeps the acting player. The client
  shows the controlled hand, supports Pass for that player, and can play
  authorized library-top cards. Public entry and summoning-sickness markers
  separate fresh permanents from older identical copies. This requires native
  adapter revision 21; the official Forge source pin is unchanged.
- Record Forge matches as private visual replays. Original participants receive
  both-hand recordings only after the whole match ends; BO3 sideboarding and
  spectators remain excluded. The replay player supports event/turn seeking,
  playback speed, table flipping, inspection and offline `.hpr` import/export.
  This requires native adapter revision 17; the official Forge source pin is
  unchanged.

### Fixed

- Prefer one legal tap-only colorless land for a remaining pure generic cost
  of at least two in human auto-pay, choosing the least excess mana. This
  avoids tapping multiple Tron lands under Trinisphere when one Tower pays all
  three; manual source selection remains available.
- Silently acknowledge Forge's informational AI deck-quality advisory and
  proceed to opening hands, and drop the persistent full-control status line
  from the action dock. Other notices and game decisions still require their
  normal input.
- Explain Forge startup failures to every room member when loading returns to
  the waiting room. Keep a visible, copyable reason and show rejected card
  names/printings only to their deck owner (or the host for an AI deck).
  Native adapter 16 supplies structured deck diagnostics; older runtimes retain
  a clear generic failure. No format-legality or printing-substitution rule changes.
- Replace the cast cue with the owner's `cast.wav` and the spell/ability
  resolution cue with `Accept.mp3`, preserving each complete sound at the
  existing cue volume levels.
- Allow Forge games to start with catalog prerelease and promo-pack printings
  whose exact parent printing is supported by Forge. Preserve their selected
  art in prompts and zones, including mixed regular/promo copies. This fixes
  md2-versus-md1 practice returning immediately to the lobby and requires native
  adapter revision 15; the official Forge source pin is unchanged.
- Preserve exact Forge card printings in selection, reveal and ordering dialogs,
  so cached imported art stays consistent when cards move into the hand or
  battlefield. Reject unavailable explicit printings instead of silently
  substituting another version. This requires native adapter revision 14;
  the official Forge source pin is unchanged.
- Keep manual-table card, zone, attachment and arrow lookups consistent while
  card-model notifications are delivered.
- Classify compact deck-list lands by the front face's card types, including
  localized subtype separators, so spell/land cards and Goblins stay with spells.
- Reject sideboard moves that would split the pending deck beyond its entry
  limit before changing cards or readiness.
- Avoid duplicate Forge metadata snapshots and unnecessary Limited deck sorting;
  changing pool grouping preserves the selected deck and mana-plan calculations.
- Preserve Limited pool/deck scroll positions during card moves, require the
  final manual draft pick to be confirmed, and pair opposite draft seats in
  the first Swiss round (with distance-based fallback after byes or drops).
- Display remaining Forge mana by color and scroll crowded hands through the
  final card. Retain the completed public Forge table for sideboard reconnects.
- Give model opponents the exact response shape for each decision, preventing
  structured choices such as play/draw from being returned as ordinary action
  IDs. Keep sensitive input text out of native test observations and traces.
- Keep independent Forge dialogs from repeating an earlier spell's payment
  text. Duress, Deadly Cover-Up, Shallow Grave and Emptiness now show readable
  effect or target descriptions in the native adapter. This requires adapter
  revision 10; the official Forge source pin is unchanged.
  Payment headings retain the live unpaid mana cost even when the effect's
  description is too long to fit in the decision panel.
- Show Dauntless Bodyguard's chosen creature on its battlefield card and hover
  details, clearing the link when that creature changes zones. Private chosen
  cards remain hidden. This requires native adapter revision 9.
- Preserve the first form-button click after wheel scrolling reaches the end
  of room and tournament creation forms.
- Keep long Forge hover explanations from covering the fixed payment controls
  or receiving pointer input after a target-to-payment transition.
- Complete conditional discards and end-turn cleanup in Forge, expose finite
  dungeon/name menus, and retain legal completion, selection and cancellation
  for crew, exile and convoke/improvise/waterbend costs. Show class levels and
  dungeon rooms, with a command-zone entry whenever it contains objects.
  Decision transitions no longer reset incubating Qt option delegates.
  These fixes require native adapter revision 7; the official Forge pin stays unchanged.
- Show named cards, chosen types/colors/numbers/modes, and linked exile names
  directly on Forge battlefield permanents, with fuller hover and inspection
  summaries. Stateful copies remain separate, returned cards clear their links,
  and hidden exile identities remain anonymous. This requires native adapter
  revision 6; the official Forge source pin is unchanged.
- Show selected improvise/convoke permanents with checkmarks and separate piles
  during Forge payment. Cancelling an insufficient payment restores its artifact
  and mana-source taps, including repeated Kappa Cannoneer casting attempts.
  This requires native adapter revision 5; the official Forge source pin is unchanged.
- Select one eligible creature per click when declaring combat from a Forge
  pile of identical permanents. Covered cards no longer receive the same tap
  and undo the selection; the pile highlights legal choices beneath its front.
- Keep Forge player life badges above the hand so hovered cards cannot hide
  their values or intercept clicks when choosing the player as a target.

## [2.0.5] - 2026-09-21

### Upgrade notes

- Upgrade clients and the Go server together to **2.0.5**; application versions
  must match exactly. The WebSocket protocol, the native adapter overlay and
  the online server directory are unchanged from 2.0.4, so server-managed
  Forge runtimes need no rebuild.

### Added

- Add a standalone **Download set art** screen under Settings and Card art
  storage. It reuses the Limited product-art cache so a set or booster
  product can be downloaded without opening a Set Sealed or Set Draft lobby.
- Let completed-event decklists export as the same importable
  Deck / Sideboard / Commander text used by the deck library.
- Import gzipped Hexproof card databases. Local import treated official
  `sqlite.gz` files as Scryfall JSONL; a gzipped SQLite header is now detected
  and decompressed the same way the GitHub update path already does.
- Fall back when the GitHub update API fails: a stale cached release no longer
  looks current, and the latest package can be discovered from public
  github.com checksums when `api.github.com` is rate-limited.
- Remember the last connect display name across restarts and disconnects,
  without tying it to resume credentials or the hub.

### Changed

- Rework the connect screen: it is now a full page simplified to server,
  name, and connect, centered on tall windows, instead of a floating card.
- Describe Manual, Forge, and Limited (Sealed, Draft, Cube) on the home hero
  instead of the old seat-count statistics.
- Split Settings into category modules behind a hub, so appearance, language,
  catalog and updates each get their own screen.
- Tighten and center the create-room form: table identity on the left, join
  options on the right, with glass inner cards and animated rules extras.
- Group waiting-room player-host status, direct-connection actions and
  diagnostics into one compact footer strip.
- Keep the Forge lower-right dock to phase and priority passing. Settings,
  Full control, log/chat, and player-hosting controls open from a top-right
  Settings button.
- Park the Forge phase and pass plate on the bottom-right hand band so the
  battlefield can use the full right side. Turn and phase show once, with
  full-width Pass and Next actions.
- Float the Forge log and chat over the playmat as a full-height panel that
  can be dragged and resized, with a pinned header; the board and pass plate
  stay still while it is open.
- Localize Forge table card names: public labels use the catalog display name
  for the current card language instead of the engine's English identity.
- Show complete card faces on Forge zone piles at the standard ratio so art
  and names are not cropped.
- Lay out the between-game sideboard as a full-bleed table workspace without
  a framed inset or scrim ring.
- Replace the cramped overflowing-hand slider with a proportional thumb that
  tracks the pointer and eased wheel notches for large hands; hand cards grow
  into the strip instead of letterboxing under a fixed width.
- Restyle commander tax to match the life steppers, with partner tax as
  full-width rows on one dock row.
- Restore classic panel outlines and limit the glass wash to the stack tray
  and hand strip, dropping the opaque zone-dock well.
- Unify table dialog chrome and restyle table context menus.
- Show completed-event decklists as grouped card art with hover previews
  instead of a cramped two-column text list.
- Keep the deck editor's view, group, and sort controls on the same toolbar
  row as the deck-local search when the window can fit them.
- Make catalog search an add-only popup, like the token picker, instead of a
  second live deck editor beside the results.
- Let catalog search add a selected result to the main deck, sideboard, or
  Consider after searching. Commander and Cube hide Sideboard.
- Make overflowing catalog-search results use a high-contrast scrollbar.
- Use the shared popup chrome for Consider and the printing picker, and the
  same high-contrast scrollbar on the editor gallery and Consider list.
- Move deck-editor export and current-deck art caching into a More menu.

## [2.0.4] - 2026-09-19

### Upgrade notes

- Upgrade clients and the Go server together to **2.0.4**; application versions
  must match exactly. The WebSocket protocol remains `hexproof.v1`, and existing
  card databases and saved decks remain compatible.
- The native adapter overlay is unchanged from 2.0.3, so server-managed Forge
  runtimes do not need rebuilding for this release.
- The maintained FRA Play product arrives through the separate card-data
  channel and needs that release. Paired-product events require both the
  updated client and server: older implementations treat a paired draw as one
  independent card instead of two.

### Added

- Add the maintained FRA Play recipe with paired sheets. The card-data build
  installs the `hexproof-fra-play` product from the imported FRA and SPG
  printings, following the published Collecting Reality Fracture Play Booster
  slots including reciprocal echoed pairs, the third distinct printing, the
  foil and land slots, and the 1/55 Special Guests replacement. The recipe is
  always `approximate`: estimated sub-1% probabilities are normalized, missing
  printings redistribute their category's weight or exclude both halves of a
  missing pair, and the product stays labelled `partial preview, estimated`
  until the set is complete. Limited sheet definitions gain the optional
  `pairCollectorNumber` card field and `excludePrevious` sheet flag; one paired
  slot draw emits both cards and counts as two physical cards. Both the client
  simulation and the authoritative server generation implement these semantics.

### Changed

- Rework the Forge table. The selected battlefield playmat stays visible under
  the lane wells, and both players' permanents share one battlefield instead of
  separate halves.
- Show zones as face-up card piles with a single-plate browser and a sectioned
  Settings drawer, replacing the generic zone buttons and nested menus; the
  piles sit in the hand row.
- Show lands as a centered, compact table row aligned with the shared card
  faces, kept compact in the near corner.
- Stack identical Forge permanents and tokens, and drop the empty padding
  under Forge card previews.
- Pin compact life badges to the board seam instead of reserving two empty
  bands for floating player cards.
- Flatten the Forge decision dock to a single plate, with the prompt copy and
  actions directly on it.
- Stop pinning Forge card inspection on idle left-clicks; the preview follows
  the hover instead.

## [2.0.3] - 2026-09-18

### Upgrade notes

- Upgrade clients and the Go server together to **2.0.3**; application versions
  must match exactly. The WebSocket protocol remains `hexproof.v1`, and existing
  card databases and saved decks remain compatible.
- The bundled native adapter overlay changes identity through the combined
  card face resolution. Player-hosted clients receive the new overlay with the
  package; server-managed Forge runtimes must be rebuilt with the matching
  current adapter for the fix.

### Fixed

- Start Forge games whose decks or commanders contain modal double-faced cards.
  The catalog's combined `Front // Back` names are now resolved at startup: the
  adapter first tries the full name, then falls back to the front-face printing
  with the same set and collector number, verifying both face names before
  registering the card. Split cards such as Fire // Ice keep working through
  their native combined names.
- Restore player-hosting readiness after a rejected or cancelled offline Forge
  import when the previously installed runtime remains usable. The client
  rechecks that installation without downloading, keeps the original import
  diagnostic visible and leaves preparation or hosting operations disabled
  until the recheck finishes.

## [2.0.2] - 2026-09-17

### Upgrade notes

- Upgrade clients and the Go server together to **2.0.2**; application versions
  must match exactly. The WebSocket protocol remains `hexproof.v1`, and existing
  schema-v10 card databases and saved decks remain compatible.
- Client packages now include the Forge hosting helper and the current native
  adapter 4 overlay. The host prepares the pinned Forge/Java base by download
  or offline import; joining players do not need Java. Server-managed Forge
  runtimes must be built with the matching current adapter to use its fixes.
- Player hosting remains an explicit server option (`-allow-player-hosting`).
  Direct connections require consent from both players; the room server stays
  authoritative and supplies fallback relay when direct transport fails.

### Added

- Host trusted two-player Forge games on the creator's computer, including
  Duel Commander and best-of-three matches, through the existing room hub.
- Offer optional WebRTC data channels with authenticated signaling, confirmed
  redacted publications and automatic relay fallback. Configure up to two STUN
  endpoints; the managed defaults use Servers 1 and 2.
- Expose direct-connection consent, status and retry controls on the waiting
  room and game table, with no hosting-menu navigation required.
- Support an explicitly approved backup host, verified game reconstruction,
  planned handover and recovery after host loss.
- Import platform-specific `.hexproof-forgepack` files for offline Forge and
  Java installation, with checksum validation and cancellation.
- Resume runtime downloads, manage the local cache, export bounded hosting
  diagnostics and show independent server hosting/direct/migration capabilities.
- Optionally share server Forge workers between two to four games per JVM;
  dedicated game processes remain the default.

### Fixed

- Preserve native sideboarding, scry and cleanup choices, linked exile views,
  token printings and nested mana decisions in the Forge adapter and table.
- Emit native Forge messages as UTF-8 on every platform, preventing Windows
  code pages from corrupting action labels and rejecting cross-platform host
  migration replays.
- Wrap hosting and context controls within the Forge decision dock so they
  remain accessible in smaller maximized windows.
- Exclude section headings from Forge target choices. Cross-zone spells such
  as Sink into Stupor now offer actual card targets with card previews instead
  of allowing a heading to restart the target prompt.

## [2.0.1] - 2026-09-16

### Upgrade notes

- Upgrade clients and the Go server together to **2.0.1**; application versions
  must match exactly. The WebSocket protocol remains `hexproof.v1`.
- Reuse the published 2.0.0 official Forge runtime and matching source archive
  (pinned upstream revision, adapter 2). No Java, Forge runtime, card database,
  or saved-deck migration is required for this update.
- Forge-enabled servers now default to **one simultaneous Forge match**.
  Operators can set `-max-forge-games` or `HEXPROOF_FORGE_MAX_GAMES` to a positive
  integer sized for their host; the flag takes precedence. Memory limits alone
  do not configure this admission limit.

### Changed

- Load the public server list over HTTPS from a primary directory and backup
  mirror, with a last-known-good local cache, bundled fallback and custom
  addresses available during directory outages.
- Add manual list refresh and per-server Forge support labels. Successful
  connections correct the advertised capability using the actual server
  welcome. Catalog changes take effect without another client rebuild.
- Preserve server selection by stable ID across reordering; clear a removed
  selection instead of choosing another node. Refresh does not move existing
  connections or their reconnect credentials. Reject stale catalog revisions.
- Update the maintained fleet to Server 1 (manual only), Server 2 and the new
  Server 3 (Forge enabled). Remove retired public nodes and the old test server
  from the default list. Update connected-server labels for the dynamic list.

### Fixed

- Bound simultaneous Forge games before starting Java to prevent unrestricted
  engine creation from exhausting small servers. A full hub rejects a new
  start with a capacity message, preserving the room's seats and decks.
  Existing Forge games, manual games and waiting rooms remain available.
- Count starting and exiting engines until cleanup completes. BO3 sideboarding
  and host restarts retain their match slot; completed, abandoned and failed
  matches release capacity. A restart waits for the previous process to exit.

## [2.0.0] - 2026-09-16

Rebuilds rules battles around the official Forge engine and a dedicated native
1v1 table, including Duel Commander. The manual tabletop remains available.
This release consolidates the changes since 1.2.0.

### Upgrade notes

- Upgrade clients and the Go server together to **2.0.0**; application versions
  must match exactly. The WebSocket protocol remains `hexproof.v1`.
- Forge is an optional, separately configured server runtime. New rules-table
  delivery covers 1v1 formats and Duel Commander; multiplayer EDH is outside
  this scope. Existing manual Commander play remains available.
- Replace legacy Manabrew installations with the pinned official Forge runtime
  and its matching sources. The application archives contain clients and Go
  servers; they do not bundle Java, the Forge runtime, or card data.
- Servers already using official Forge should rebuild its runtime from the
  2.0.0 sources to include the face-down payment correction.
- Existing schema-v10 card databases remain compatible. Card-data updates
  continue through the separate `card-data` release channel.

### Added

- Add three sponsor acknowledgements, including a featured Omniscience supporter
  with a gold frame, gentle glow, special thanks and a profile introduction in
  both sponsor lists.
- Add independent local battlefield backgrounds with an optional built-in
  playmat, and parallel card-art downloads with inline progress.
- Drag the manual library's top card directly to the stack. Exile it face down
  through the library menu or Shift-drag without revealing it to any player,
  including its owner, for effects such as Bomat Courier. Battlefield face-down
  rules retain their existing behavior.
- Show native stack target relationships with exact-object navigation,
  highlighting and arrows in the Forge table.
- Show Forge-authored commander cast counts, tax and visible locations in the
  Duel table, with direct legal commander actions and independent histories.
- Use the new Forge-specific table for 1v1 rules rooms, with opposed creature
  lanes, a fanned hand, a separate stack and decision dock, public-zone browsing,
  and direct combat selection shared with the native assignment controls.
- Add a Forge action bar beside the hand, smart priority for quiet phases and
  own-spell responses, full control, own/opponent phase stops, and cancellable
  passing through a turn or the current stack.
- Add an official Forge runtime using native human inputs, with a pinned local
  builder and matching runtime/source packages.
- Play Forge hand cards and activate permanents directly on the table. Select
  highlighted cards, stack objects, and players as targets, with immediate
  single-target submission and shared confirmation for multiple targets.
- Commander Cube supports up to eight draft players, configurable 10–40-card
  packs, and small-room choices of 3/4/5/6/8 packs per player. Small rooms default
  to six packs opened in pairs; larger rooms use three packs opened separately.
- Commander Cube deck building offers one outside copy each of Sol Ring,
  Command Tower, and Arcane Signet alongside basic lands. The local multi-client
  launcher can set up a saved Cube and automatically draft through deck building.

### Fixed

- Keep Morph payment decisions actionable when Forge supplies an anonymous
  source-card view. Omit the optional preview without disclosing its identity;
  casting face down, resolving, and turning the card face up retain their
  normal rules flow.
- Resolve Commander legality for **Pym Particles (MSH 70)** using its playable
  printing instead of a same-name auxiliary front card. Keep explicitly chosen
  printing identities intact.
- Keep manual library-top drags attached to the actual grab point, including
  fast movement and drops onto the stack or exile zone. Face-down exile shows
  card backs and a no-look label for owners, opponents, and spectators.
- Show sponsor acknowledgements once per application version, so supporters
  remain visible to existing users after an upgrade.
- Merge Forge turn/phase, Settings and log/chat controls into the lower-right
  decision dock, returning the entire top toolbar's height to the battlefield.
- Prevent Forge phase and priority updates from rebuilding unchanged cards,
  resetting focus or scroll positions, and shifting continuous-pass controls.
- Translate common Forge decisions, opening play/draw choices, optional-trigger
  confirmations and payment prompts using the client's selected language.
- Place Forge log/chat on the right beside the decision controls, label the
  menu Settings, and show live library counts in both player summaries and
  zone browsers. Hide command-zone controls outside Duel Commander.
- Show the actual card during native Forge surveil confirmations, with adjacent
  full-card inspection and rules-text fallback when artwork is unavailable.
- Remove the duplicate central Forge action banner, keeping instructions in
  the decision dock and returning its height to the battlefield.
- Preserve Forge's top-first ordering when displaying multiple stack entries.
- Select player, planeswalker and battle attack destinations directly on the
  Forge table, and keep damage controls reachable in compact windows.
- Prevent repeated sideboard Ready submissions while the next Forge game starts.
- Keep Forge decisions beside the hand at every window size, with independent
  card inspection; retain a response window after cancelling continuous passing.
- Make the Forge current-stack control continue through the existing stack and
  stop on new spells or triggers instead of silently passing only once.
- Keep Forge inspection on hover/right-click and layout dragging independent
  of gameplay actions; recognize native land plays when dragging from hand.
- Keep Forge player controls reachable in narrow multiplayer lanes without
  moving placed cards when turn, priority, or arrangement controls appear.
- Retire the Manabrew runtime, legacy launcher and build path; use official
  Forge throughout local startup, package validation, deployment tooling and CI.
- Make overflowing rules decisions reachable with mouse wheels, scrollbars and
  keyboard focus, including large combat declarations and nested scry piles.
- Keep rules-table base actions visible above long ability lists, and show
  current power/toughness, damage, counters, energy and public card details.
- Preserve native cost cancellation and full authorized card reveals before
  selection, including Collected Company.
- Preserve full selection sizes for standard native card lists, including
  Seasoned Pyromancer's discard, and Forge's computed combat-damage thresholds.
- Restore Forge scry/surveil card placement and reject incomplete partitions.
- Resolve name-only deck imports to local catalog printings before registration.
- Preserve anonymous face-down permanents in combat-damage decisions.
- Isolate each rules game in its own runtime process so a failed game cannot
  abort another room, and release the process after the game ends.
- Use native human X payment and searchable public card-name candidates in
  official Forge decisions.
- Clear outdated card searches during database replacement, including pending
  responses and searches closed while the replacement is running.
- Keep image caching active during automatic retry delays, preserving progress
  and preventing conflicting card-art maintenance.
- Close the Limited basic-land editor when its deck-building workspace hides,
  so table invitations remain accessible without losing deck edits.
- Reduce temporary allocations in exact Swiss pairing while preserving its
  minimum-cost pairings and deterministic tie handling.
- Allow card-art pack previews while background card lookup is active, so a file
  selected in the native chooser is not rejected by unrelated read activity.
- Clear a rejected card-art inspection's old preview and report its error.
- Keep battlefield, stack and revealed-card drags aligned with the actual
  grab point, including card edges and tapped permanents, so drops reach the
  intended zone.
- Include catalog-linked meld result printings in deck art exports while keeping
  identical image files deduplicated.
- Keep battlefield face choices synchronized with left-click selection, so the
  choose-face shortcut works without first opening a card's context menu.
- Keep fast hand drags aligned with the pointer so dropping later or partly
  clipped cards onto the stack cannot leave them in hand or move them elsewhere.
- Refresh full-name double-faced deck entries after their front art downloads,
  so completed caching no longer leaves those entries marked as missing images.
- Use the selected printing for legality when a Prepare characteristic shares
  its name with a standalone card.
- Classify saved-deck cards by their front-face main types, so localized Gnome
  or Goblin subtypes containing the character for land do not become lands.
- Hide obsolete search results immediately when queries or filters change,
  and release result delegates when the search workspace closes.
- Refresh a deck's missing-art status when a replacement image arrives at the
  same saved path, without requiring another edit or a restart.
- Roll back newly created card-art files when an import fails late, its index
  cannot be saved, or the application closes before the import commits.
- Keep deck editing and filtering responsive by refreshing only the changed
  deck, reusing card projections and rendering only visible gallery rows.
- Keep card-art import, export, cleanup and custom-art maintenance responsive
  through asynchronous index commits, bounded display updates and background
  cleanup of temporary artwork.
- Deck building retains independent pool/main-deck filters, recognizes localized
  land types, and offers filtered commander candidates from the drafted pool.
  Selecting multiple colors requires every selected color.
- Search-art previews now follow the visible results, discard obsolete pending
  candidates, and yield to explicit deck caching without inflating its progress.
- Match preparation distinguishes locally available art from missing downloads,
  reusing cached card faces before enqueueing network work.

### Development

- Add `./tools/build.sh` for incremental client/server builds, with separate
  scopes and all online CPU cores used by default for client compilation.
- Extend isolated native review with real-deck Forge scenarios, manual-table
  lifecycle checks, and privacy/decision regression coverage. Passing these
  scenarios does not certify every card interaction or format ban list.
- Synchronize multi-client test teardown so an early worker disconnect cannot
  alter another worker's recorded Cube setup state.
- Add an offline QML Forge table preview for combat, targeting, payment,
  commander controls, and crowded battlefields.

## [1.2.0] - 2026-09-10

Consolidates the application changes since 1.0.6 (source baseline **82f8110**).
Follow-up fixes are combined; reverted theme experiments are not included.

### Added

#### Manual tabletop actions

- Atomic graveyard/exile selections to either library end in chosen or random
  order, including Endurance and cascade cleanup. The existing library order
  is preserved; a separate **Shuffle into library** action shuffles the whole
  library. All affected owners are validated and prepared before any mutation.
- Private hand selection and batch movement, battlefield batch return to
  owners' hands, and whole-library recycling. Tokens disappear as appropriate.
- A visible zone-move menu button, individual-copy selection, explicit filtered
  selection labels, and compact card/preview switching with pinned actions.

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
- Large batch library-top insertion avoids repeated array shifts: the local
  1000-card benchmark improved from about 2.56 ms to 0.50 ms per operation.

### Fixed

#### Navigation and tabletop interaction

- Batch battlefield placement no longer covers earlier cards' centers in
  ordinary small batches; client previews and authoritative placement agree.
- Compact home pages show play controls before decorative content.
- Table chat uses the application input styling, and the themed hand scroll
  control appears only when cards overflow.
- Chinese game logs translate batch placement, token cleanup, BO3 next-game
  first player, concession, and Commander outcomes.
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

[Unreleased]: https://github.com/ClayStan404/hexproof/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/ClayStan404/hexproof/compare/v1.2.0...v2.0.0
[1.2.0]: https://github.com/ClayStan404/hexproof/compare/v1.0.6...v1.2.0
[1.0.6]: https://github.com/ClayStan404/hexproof/releases/tag/v1.0.6
