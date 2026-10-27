# Game table layout

- Status: **Active**
- Last updated: 2026-10-21
- Parent: `product-brief.md`

## Goals

- **Table geometry:** match physical tabletop intuition: remote battlefield above,
  local battlefield below, and local hand/zones along the bottom edge.
- **Feel:** smooth drag, readable art, low friction, and no permanently reserved
  card-inspector area.
- **Manual rules:** phase state and stack remain coordination data, not a rules
  engine.

## Overall chrome

Classic remains the default; `uiTheme` may select Glass. The withdrawn
`themeId`, ember palette and reduced-motion preference remain ignored on load.
Glass panels preserve backdrop orientation and sample their current position
while content scrolls or cards move. Secondary, highlight and ghost buttons
retain visible keyboard focus. Do not revive the retired felt-rail rewrite or
extra palettes from the completed FE experiment.

- Battlefield artwork is a device-local preference independent of interface
  appearance. Manual and Forge tables share a **Default background** without an
  image plus seven bundled images usable in both Classic and Glass. Default
  preserves Classic's opaque green battlefield and uses Glass's procedural
  night backdrop. Images fill the table with aspect-preserving cropping;
  a subtle scrim and outlined player labels
  preserve readability on lighter artwork. Glass surfaces limit highlights so
  bright images do not wash out their light labels. Classic battlefield lane
  fills become translucent when artwork is selected while its controls retain
  their Classic styling. Selecting Default restores the opaque fills.
- Settings and the in-table background picker apply a thumbnail selection
  immediately and persist `tableBackground` separately from `uiTheme`.
  Changing theme never changes the selected background. Missing or unknown
  background identifiers resolve to `default`; explicit image choices are
  preserved. Backgrounds require no downloads and do not change shared room
  state or any player's card placement.

```text
┌──────────────┬────────┬────────────────────────────┬──────────────┐
│ Room / turn  │ Shared │ Opponent battlefield       │ Game log     │
│ phases       │ tray   │                            │              │
│              │        ├────────────────────────────┤              │
│ signals      │        │ Local battlefield          │              │
│ next / end   │        ├──────────────┬─────────────┤ Chat         │
│              │        │ Hand         │ Zone dock   │              │
└──────────────┴────────┴──────────────┴─────────────┴──────────────┘
                                  floating card preview on hover
```

- The 144 px left action rail (120 px below 1100 px wide) keeps room controls
  at the top and uses its remaining height for the active player, eleven turn
  steps, coordination signals, and phase/turn actions. A strong vertical divider
  keeps it distinct from the shared tray and battlefield. The rail shows the
  room code directly below the room name, presents the BO3 match score in
  larger, bold type, and includes a Shortcuts entry (default `F1` / `?`). The
  list renders the device's current bindings rather than a hard-coded table.
  Short or scaled windows combine Settings, Shortcuts, Show game log, and
  Leave room into a row of accessible icon buttons. First reduce action-button
  heights and spacing while preserving all eleven complete phase rows. Only
  when this denser layout still cannot hold the phase rows alongside
  coordination, helpers, next-phase, and end-turn actions does a selector
  expose the same eleven phases.
  Reserve helper/signal space when choosing the navigation mode so phase
  changes do not move the controls or switch modes under the pointer.
- The 92 px shared stack/reveal tray is wide enough for its card thumbnails
  and two compact action buttons while returning unused width to the
  battlefield. On Glass it uses the same translucent rail wash as the left
  action rail instead of an opaque muted well; Classic keeps the muted fill.
- The optional 176 px right rail (148 px below 1100 px wide) is dedicated to
  the public game log and chat composer. Hiding it expands the central table; a
  restore control remains in the left action rail. Below 1100 px wide, the
  log rail and shared tray start collapsed so the battlefield keeps the extra
  width; restoring them in that compact session does not overwrite the saved
  wide-layout preference.
- The shared stack/reveal tray remains optional. The fixed player and inspector
  columns are removed.
- Hovering a visible card opens a pointer-adjacent, art-only preview without
  panel chrome, borders, or a duplicate title. It chooses the left or right
  side according to available space and never changes the card's upright
  orientation.
- The local zone dock sits to the right of the hand. Each remote seat has an
  independent compact floating zone panel at table-overlay level. All remote
  panels may be open at once, and none reserves space inside a battlefield.
  Each panel starts at its player's battlefield lower-right corner and arranges
  its zones in two compact rows below the player name and public counter pips.
  Life and hand counts remain in the battlefield header and are not duplicated
  here. Drag a player's name to move that panel anywhere in the table window,
  or right-click the name to restore its battlefield-corner position. Position
  and expanded/collapsed state are client-local and survive subsequent game
  snapshots, including battlefield card moves.
- All two-player tables, including EDH and Commander Cube, use
  opponent-above/local-below lanes. Two-player EDH keeps its 40 starting life,
  command zones, commander tax, and commander-damage controls; layout does not
  change the format's rules. Spectators see the two lanes in stable seat order.
  Three- and four-player EDH use the same floating panel behavior outside their
  viewer-relative multiplayer battlefield
  grid. For a seated EDH viewer, the local seat is fixed at bottom-left;
  clockwise, the next player in the server-authoritative rolled `turnOrder` is
  top-left, the following player is top-right, and the previous player is
  bottom-right. A spectator anchors the first player in that order at
  bottom-left and continues through the same order clockwise. Immutable seat
  numbers remain membership and ownership keys; they do not define visual or
  turn order. Every battlefield keeps its player name visible at the upper left,
  independently of the floating zone panel. A compact, noninteractive backing
  follows the player-name text so it remains readable over bright card art,
  including on the default background. Player names, turn/response badges
  and focus/zone controls are overlays, not a reserved title row. The card/drop
  viewport uses the entire lane with the same six-pixel inset on every edge;
  showing or hiding a badge never reduces usable height or shifts cards. Cards
  can be placed in the top strip beneath these overlays. Rendering, dropping
  and automatic arrangement share that full viewport; normalized game
  coordinates are not rewritten.
  The original game seats, including eliminated or disconnected players, remain
  in this layout; elimination or disconnect never unexpectedly reflows the table.
  A manual eliminated seat shows an explicit **Eliminated** status instead of
  ordinary turn/response badges and life/hand/library summaries. Its retained
  public battlefield and zone browsers remain available for review; the status
  does not alter authoritative values or decide elimination from life/counts.
  Narrow battlefields put public response signals and life/hand/library summaries
  below the name and focus/zone controls. Truncated player names expose their
  complete text on hover, including in compact primary-layout lanes. Short
  secondary lanes use denser overlay controls; card thumbnails still use the
  full available lane and hovering opens the full-size preview.
- Three- and four-player EDH may switch at any time between the **Overview layout** and a
  **Primary battlefield** layout. The primary battlefield uses the full table
  height and exactly three quarters of its width; the other three battlefields
  remain in a compact right column. Each lane's floating focus control can
  select the primary battlefield; activating the focused lane's control again
  returns to the overview layout.
- Battlefield card size is client-local presentation state. Automatic mode
  uses 70% in four-player EDH overview, 80% in three-player EDH overview, and
  100% in primary-battlefield, 1v1, and Playtest layouts. The user may adjust
  it from 50% through 125% in five-point steps with the overview and
  primary/ordinary values remembered separately. The percentage button resets
  the active value to automatic, and `Ctrl` + mouse wheel adjusts it directly
  over the battlefield. Hover previews remain full-size, and no scale value is
  sent to the server or written into normalized card positions.
  Actual card dimensions are additionally bounded by their lane's available
  size. A small focus-layout lane never paints a full-size card into the next
  battlefield, and tapped edge cards stay within that lane.
- EDH card-scale controls use a draggable floating button; layout switching
  remains on each battlefield's focus toggle. The floating controls never
  reserve a layout row or reduce any player's battlefield. Its default dock is
  the game-log header, outside every battlefield. When the log is hidden it
  falls back to the middle of the window's right edge. Hovering or selecting
  the button reveals the full controls, which collapse again after the pointer
  leaves. A dragged position is stored locally as normalized window
  coordinates; right-clicking the button restores its default dock.
- The game-log rail is deliberately only slightly wider than the action rail:
  176 logical pixels normally and 148 in compact layout. Log text wraps to
  preserve battlefield width. An interactive vertical scrollbar appears when
  the log exceeds the available height, while mouse-wheel and touch scrolling
  remain available.
- The table exposes keyboard access for every high-frequency top-level action
  and for card-selection operations that have an unambiguous destination.
  Configurable shortcuts call the same controllers as menus, so permission,
  confirmation, hidden-information, and advisory-rule gates remain identical. Contextual
  card moves are suppressed when both a hand card and battlefield cards remain
  selected rather than guessing which domain the player intended.

### Forge rules layout

- Forge rooms retain the same core table geometry as manual rooms: the room and
  turn rail, shared stack tray, viewer-relative battlefield lanes, local hand
  plus zone dock, and narrow right rail. A two-player viewer always sees the
  opponent above and their own battlefield below.
- Forge uses rules-specific typed presentation components behind that shared
  geometry. It never enables manual drag, zone-mutation, phase, life, or counter
  commands, and it never routes engine state through the manual room reducer.
- The left phase list is authoritative and read-only. Legal decisions appear in
  a bounded layer over the battlefield. The right rail shows the current
  normalized player and zone state until a dedicated Forge game-log projection
  is defined.
- Compact width follows the manual table policy by collapsing the shared and
  right rails so battlefield and hand space remain usable.
- Public Forge card titles on the battlefield, stack, commander strip, hover
  fallback, and inspection header follow the independent card-language setting
  through the local catalog. Engine identity, art lookup, and activateObject
  keep the canonical English name. Hidden or face-down cards never resolve a
  display name.

### Solo Playtest layout

- Playtest uses the same server-authoritative table, zones, drag targets,
  context menus, card loading, and shortcuts as multiplayer.
- Its only battlefield fills the complete battlefield grid; no empty opponent
  lane or opponent zone dock is created.
- The room code and Concede action are hidden. **End playtest** leaves the
  private room and returns to the main menu.
- Generic 1v1 and Duel Commander Playtest start at 20 life. Duel Commander
  retains the command zone and commander-tax controls; Commander Playtest
  starts at 40 with the same commander controls.
- Playtest remains a manual tabletop and does not infer rules, legal moves, or
  automatic triggers.

### Assisted battlefield placement

- New face-up permanents use printing metadata to choose the next compact slot:
  lands sit flush against their controller's edge, creatures occupy the middle
  band and expand from its horizontal center toward both sides, and noncreature
  permanents use distinct far clusters (enchantments/unknown at left, artifacts
  at center, and planeswalkers/battles at right). Instants and sorceries use a
  separate staging row between those clusters and creatures. Face-down cards
  remain in the neutral support cluster so their position does not reveal
  hidden type information. A multi-face permanent is classified from the face
  chosen as it enters the battlefield.
- Adding a card never repositions permanents already on the battlefield.
  Players retain unrestricted manual drag placement after entry.
- Only interchangeable lands and creatures use the compact diagonal fan: they
  must have the same canonical name, selected face, tapped state, and token
  status, even when their printings differ. A card stays independent when it
  has counters, is a commander, is owned by another seat, participates in an
  attachment or combat relation, is face down, or has any other permanent
  category. Each grouped card remains partially exposed for hover, selection,
  and dragging.
- Hover does not raise a card above overlapping neighbors. Moving the pointer
  from the exposed portion of one card to another updates the large preview;
  a stale exit event from the previous card cannot hide the newer preview.
- **Arrange battlefield** in the empty own-battlefield context menu explicitly
  applies the same type rows and clusters to all current cards and places only
  interchangeable matching lands and creatures together. The client sends
  every resulting coordinate in one atomic server command, preserving tapped
  state, counters, faces, attachments, and combat declarations.
- The display transform follows the battlefield's overview row rather than the
  viewer's relationship to its controller. Top-row battlefields vertically
  mirror stored coordinates, while bottom-row battlefields retain them. Land
  bands therefore stay against the table's outer top or bottom edge for both
  players and spectators. Horizontal order is never mirrored, and card artwork
  remains upright.

---

## Turn flow and table actions

The shared protocol/model step order is:

```text
Untap → Upkeep → Draw → Main 1 → Begin Combat → Attackers → Blockers
  → Damage → End Combat → Main 2 → End → Pass (or equivalent end/pass control)
```

- A compact vertical turn controller occupies the left action rail. It does not
  consume battlefield height. Every viewer sees the active player and selected
  step; the active player may jump to a step, advance one step, or end the turn.
  The active battlefield lane receives a matching highlight.
- Every battlefield header shows that player's public **Turn N** count,
  including the current turn. The starting player begins at 1 and the others at
  0; only the incoming player's count increases. Counts survive reconnects and
  reset on a new game or restart, as specified in `match-flow.md`.
- **Ctrl+Right** advances one step and **Ctrl+Enter** ends the active player's
  turn when modal input and chat do not own keyboard focus.
- A direct **End turn** command advances the active seat and resets the marker
  to Untap. Phase and turn changes append public coordination log entries.
- This first assisted-flow slice does not automatically untap cards, draw, or
  resolve spells. Later safe automation must be explicit and documented; the
  application still does not force legal card actions.
- During Declare Attackers, a player may multi-select controlled permanents and
  use the direct **Attack &lt;player&gt;** action, or choose **Attack a battlefield
  permanent…** and click an opposing permanent. A compact target marker on each
  attacker identifies player targets without relying on viewer-relative screen
  coordinates. Solid red arrows are reserved for permanent targets.
- During Declare Blockers, a defending player may multi-select controlled
  permanents, choose **Block an attacker…**, then click an attacker aimed at
  that player or one of their permanents. Dashed gold arrows distinguish blocks
  from attacks. A selected source's declaration can be cleared without
  changing other declarations.
- Combat declarations are coordination state, not card-rule validation. Attack
  target selection intentionally does not infer which permanent types may be
  attacked. Player-target markers and permanent-target attack arrows survive
  through End Combat; block arrows join them from Declare Blockers. A noncombat
  phase, a new combat, or the next turn removes them.
- Every seated player has a compact response menu with **No response**,
  **Please wait**, and **Clear signal**. The current pass/hold signal appears on
  that player's battlefield and in the public log, and never blocks another
  command or claims to implement priority. Both reset at each phase/turn;
  No response also clears on the next public event, while Please wait remains
  until cleared or the phase changes.
- The active player sees one contextual, explicit helper where applicable:
  **Untap all** in Untap, **Draw 1** in Draw, and **Tap attackers** in Declare
  Attackers after declarations exist. No helper runs when the phase changes,
  and each intentionally leaves replacement effects and special card rules to
  the players.
- Phase identifiers are the stable values defined by `hexproof.v2`; localized
  labels may evolve without changing those wire values. Changing the display
  language keeps the phase selector on the authoritative phase and never
  submits a phase action. Resizing the window or changing the interface scale,
  including transitions between the full list and selector, has the same
  presentation-only behavior. A deliberate selection sends one phase request
  with its stable phase identifier and waits for authoritative confirmation.
- The top of the left rail holds room/game context, table-layout settings, and
  room navigation only. Draw X, Shuffle, Search, top-X view, and moving the
  top X cards to graveyard/exile are on the library context menu. Untap all,
  Arrange battlefield, Create token, and Concede are on the own-battlefield background context menu;
  Reveal/Recall hand, random/whole-hand discard, and Mulligan are on the hand
  background context menu.
  Untap all clears the tapped state of every currently controlled permanent
  without advancing phases or drawing. Window shortcuts sit in a muted column
  to the right of each action. Context menus and the dialogs they open share
  the same compact elevated surface, modal scrim, and 18 px title. Post-match Return to room appears only after the
  match result. The phase controller fills the remainder of the left rail;
  nothing persistent spans the top of the battlefield. The background context
  menu opens only on empty battlefield space; right-clicking a permanent always
  keeps the permanent's card menu.

---

## Seat zone docks

For multiplayer players (2 or 4), other seats are ordered above the local
seat. Playtest renders only the local dock:

| Element | Behavior |
|---------|----------|
| Life | Manual adjust; **Generic 1v1 and Duel Commander default 20**; **EDH default 40** |
| Library count | Count only for opponents; owner may draw/search, and another player may request consent-gated search access |
| Hand count | Count only for opponents; render with the same prominence and typography as library/life counts |
| Opponent life | Read-only summary in that seat's floating remote-zone panel |
| Graveyard | **Two-line label/count + open browser** (all players may open any player’s GY) |
| Exile | **Two-line label/count + open browser** (including opponents’) |
| **Command zone (Duel Commander / EDH)** | Card-art tile in both local and expanded remote docks; two commanders appear as a compact overlapping pair. The local art tile is the only command-zone surface: click to browse, drag either commander to a valid zone, or drop an eligible commander onto it. There is no duplicate lower command-zone or Cast button. Its count badge overlays the actual painted card area like the library, graveyard, and exile badges. Dedicated per-commander controls (not pips) sit below the pinned identity/life row alongside optional counters and use the same ghost `−` / value / `+` row as local life, with the commander name in place of the player name and no filled well. Each commander occupies its own full-width row so the two names stay readable. This block scrolls vertically when the dock is short; the local pile row keeps a reserved height so extra tax rows do not shrink the zone tiles. Their central value shows the next additional cost as a bare number (`2` per command-zone cast), with the cast count and full name on hover. |
| **Commander damage** | A Commander damage button in the left action rail opens a public per-commander/per-seat ledger. Its label wraps within the rail width to keep the full action readable. `−`/`+` and exact editing correct only the ledger. Record damage atomically changes the ledger and target life. Values at 21 or more use danger treatment but do not declare a result. |
| **Counter pips** | The server publishes seven stable counter slots per player. Each seated player chooses how many own slots are shown (`0`–`7`, default `0`). Hidden slots retain synchronized state. Slots have no default names. **Poison is not special** — players may label any shown pip (e.g. poison) via **I**; no dedicated poison widget. |

Zone-dock controls are text-only: life uses `−`, the exact value, and `+`;
zone/action buttons do not show decorative icons. Both local and remote
graveyard buttons use the compact `GY` label in English. Local life controls
and graveyard/exile labels are centered. The local library, graveyard, and
exile are clean portrait card tiles without nested permanent outlines: the
library uses the standard card back, while public zones show their top card
when present. Each tile has a compact borderless label/count chip over the
lower edge.

Each remote battlefield header owns only the `▾`/`▴` visibility toggle. The
corresponding panel is a separate overlay child, so simultaneous panels can be
arranged over the log rail or unused window space without shrinking or clipping
any battlefield. Dragging one panel never moves or hides another.

Opening GY/exile shows public identities.  
Library/hand identities for opponents stay hidden on clients; **server holds full state** (trust-server). A spectator receives live hand identities only when the room's immutable creation policy explicitly allows it.
The local dock groups life, library draw/search, graveyard, exile, counters,
and commander-format controls beside the hand. It remains a compact card rack rather than
expanding across unused hand space. In commander formats it reserves enough width to keep the
library back, both public zones, up to two commander images, and tax visible.
Expanded remote docks use prominent, side-by-side life and hand values plus
card-style library, graveyard, exile, and commander-format command-zone tiles at the
upper-right of their battlefield. Remote details are collapsed by default and
may be expanded per seat. In the primary-battlefield layout, compact
non-primary lanes keep only their header summary. A collapsed remote dock shows
the compact
number-before-label summary `20HP / 7H / 53D` (Chinese `20血 / 7手 / 53库`).
The expanded dock reserves enough width for all seven published counter pips;
zone cards never cover the final pip.

Every public battlefield card stays upright. When its immutable `ownerSeat`
differs from the battlefield lane (the current controller), the card displays
a compact `◇` owner marker. Hovering the marker shows
`Owner · <player>` so control changes and cards taken from another library can
be identified without covering the card art with permanent text.
Cards designated as commanders keep an immutable public commander marker when
they move from the command zone to the battlefield.
Tokens use an 18-pixel circular **T** badge in the upper-right corner, scaled
with the interface. Hover and accessibility labels identify it as a token;
the card art has no permanent word-sized token label.

### Counter pips

Each player has **7 synchronized circular counter slots**. That player may
publish a display count of `0`–`7` for their own seat; every client renders the
same first N slots, and only the owning player may change N:

| Input | Effect |
|-------|--------|
| First left- or right-click | Select the pip without changing its number |
| **Left-click while selected** | Increment number (+1; show count on the pip) |
| **Right-click while selected** | Decrement (-1) |
| **I** while selected | Edit **label text** without changing the count (all clients see label + count) |
| **S** while selected | Enter an exact signed number directly |

Use for energy, experience, poison, custom markers, etc. — **all the same 7 pips**. Coexist with dedicated life and commander-tax UI (tax stays a dedicated non-pip control).

The local dock places enabled counter pips first below the pinned identity/life
row, ahead of mulligan status and commander tax. The pips share the available
width in one row so all enabled slots are visible at the initial scroll position,
including with two commanders and a compact or enlarged interface. Mulligan
status and each commander's tax remain reachable by scrolling this block; the
zone-pile row retains its reserved height.

The keys above are defaults. Counter hints and all manual-table menu hints
show the current configured bindings, including multiple bindings or no binding.
Integer dialogs submit the value accepted by their locale-aware validator;
grouping separators must never silently turn a valid value into zero.

---

## Shared stack / show tray

| Use | Behavior |
|-----|----------|
| **Play path** | Stack is available for spells that players put there; **from hand may also go directly to battlefield** (not forced through stack). Shared entries carry their owner seat. Only the caster may drag or click their stack card onward to battlefield, graveyard, reveal, or hand — fully manual, not GRE. |
| **Reveal hand** | `Reveal hand` atomically publishes the current hand into the shared reveal area. Individual cards may also be dragged there; only their owner may drag or click them back to hand. |

Server syncs stack contents and reveals to all clients, including spectators.
Moving a hidden hand card into either shared area makes its identity public;
moving it back to hand removes it from future public snapshots without erasing
the already-public log history.
Full-hand reveal and recall are previewed locally as one optimistic batch while
the server commits the atomic move; an error or timeout restores the
authoritative zones.
The tray is only wide enough for its overlapping portrait cards and compact
move actions. Each portrait fills the usable tray width.
Every stack portrait paints its owning player's display name in a compact chip
over the top edge, so simultaneous spells remain attributable even when card
names or artwork match. Revealed cards retain their existing per-player divider
instead of repeating the owner chip on every card.

The two protocol zones render as one continuous portrait-card tray. The UI
does not split the column into labeled stack/reveal halves. Cards retain
portrait proportions and overlap vertically, keeping the top of each card
readable in a narrow column. An empty tray shows the `Stack` label instead of
an unlabeled placeholder icon. When two or more players reveal cards at the
same time, reveal cards are grouped by owner and each group starts with a
labeled divider line.
Divider names wrap within the tray and elide after two lines, with the full
label available on hover. Move icons retain enough room to render their glyphs.

---

## Battlefield + own hand

- Main play area for permanents (and similar public objects).  
- **Own hand strip below the battlefield.** It uses a compact 176 px baseline
  height (196 px for commander formats), returning more height to the
  battlefield. Hand cards fill the strip height and stay at least 86 px wide.
  The heading is only the hand-count label; a thin proportional scrollbar sits
  on that same line when the strip overflows. Dragging its thumb follows the
  pointer without smoothing lag, and the mouse wheel eases the strip
  horizontally so large hands can be navigated without dragging the thumb.
  Dragging a hand card horizontally across another hand card reorders the strip
  with displaced-card animation. This order is private client presentation: it
  sends no room command or log entry, survives authoritative snapshot refreshes,
  and appends newly drawn cards after the existing order. Dragging a card out to
  a valid zone keeps the normal zone-move behavior.
- For a spectator in a hand-visible room, the same bottom strip becomes a
  read-only hand viewer. One compact tab per seated player shows the player
  name and hand count; selecting a tab displays that hand with hover preview
  but no drag, context menu, or action shortcut. In ordinary rooms the strip
  states that hands are hidden instead of presenting an empty local hand.
- Drag the **own-library top card** into hand to draw one. Left-click does not
  draw; right-click opens Draw X, Shuffle, Search, direct top-card inspection,
  top-X look/reorder, and top-X-to-graveyard/exile actions. The library tile
  has no hover instruction.
- A move from the hidden library renders immediately at its destination as a
  non-interactive card back with a compact syncing marker. The authoritative
  snapshot replaces it in place with the revealed face for public zones or the
  owner's hand; the placeholder never discloses the next library identity.
- Table-size thumbnails decode asynchronously on demand and share a bounded
  memory cache. Full-resolution art remains available to the hover inspector,
  while ordinary hand, battlefield, shared, graveyard, and exile cards reuse
  the thumbnail. Repairing an image at its existing path changes that file's
  display URL and invalidates its decoded entry, including earlier QML load
  failures; unrelated downloaded images retain their display URLs. Ordinary
  cache import/cleanup invalidates the table-image cache as a whole. Source
  revisions remain unique after eviction from their bounded lookup cache.
- The library context menu opens an exact-count draw dialog; the server
  applies the bounded request atomically and publicly logs only the count.
- **Shuffle** randomizes the acting player's remaining hidden library on the
  server and publishes only an identity-free acknowledgement/log.
- **Search library** (see below).  
- In library search, clicking a card changes the large preview immediately
  without changing the selection. Only the card's checkbox toggles it in the
  multi-selection. Right-click opens only the library-card destination menu;
  modal popup input never reaches table cards or zone backgrounds underneath.
- Drag from hand **directly to battlefield** or via stack as player chooses.  
- For transform, modal double-faced, double-faced token, and reversible
  printings, a move from a visible non-battlefield zone to the battlefield
  first presents both faces at readable size. The selected face is synchronized
  as public card state. A battlefield card's context menu can switch faces
  later without moving the card.
- Smooth drag, tap animation, art-first (product juice). Battlefield cards use
  a compact 80×112 px baseline because the pointer-adjacent preview supplies
  the readable detail view. Battlefield drops show a local pending preview
  while the server commits the normalized
  position; visible-zone moves hide the source and preview an own-hand
  destination immediately, while an error or timeout rolls the preview back.
  Drag visuals are reparented above table chrome so they never disappear under
  the hand strip or zone docks. Owned permanents can be repositioned or
  dragged onward to hand, graveyard, exile, stack, or reveal.
- Double-clicking a controlled permanent toggles its public tapped state
  optimistically and then reconciles with the authoritative snapshot. Life,
  generic counter, and commander-tax controls use the same immediate feedback.
- Right-clicking a controlled permanent opens its contextual actions. Public
  number counters render at lower-left without a name; named ability counters
  use a high-contrast marker whose hover detail lists every label/value. A
  cross-controller permanent similarly uses an owner marker with hover detail.
  The menu can set either counter type, move the card to library top/a
  one-based position/bottom, and create a nearby token copy.
- Right-clicking an own-hand card can move it to the battlefield face up or
  face down, and also offers library top, one-based insertion
  position, and library bottom in addition to battlefield/GY/exile actions.
  The hand-background Reveal/Recall and Mulligan menu opens only on empty hand
  space and never replaces a card's context menu.
- The acting player may drag their own library top, hand cards, or owned public
  cards to any seat's battlefield. `ownerSeat` remains stable while the
  battlefield lane represents the current controller. This manual control
  change never permits inspection of another player's hidden zones.
- A player may right-click cards in any public graveyard/exile. Moving cards
  out of another player's pile opens a confirmation for that player and does
  not change the table until the exact one-use request is approved. Locally
  owned public cards may move immediately and may also return to hand or
  transition between graveyard and exile, or return to either library end.
- Graveyard, exile, and own-hand browsers expose checkboxes and **Select visible**
  for the current filter. Once every filtered card is selected, the control becomes
  **Deselect visible**. A visible **Move selected** button opens the destination
  menu. **Individual cards** allows selecting particular copies of a printing.
  Right-clicking any checked card applies the chosen
  destination to the complete checked set in one atomic move; right-clicking
  an unchecked card preserves the single-card behavior. Library top/bottom
  support ordered and randomized selection placement; **Shuffle into library**
  shuffles the entire destination library in the same transaction. These are
  distinct operations: Endurance randomizes only the cards going to the bottom.
  The hand menu opens this browser through **Select and move hand cards…**.
  In compact windows, **Preview** / **Cards** switches the main content while
  keeping the move and close actions reachable. See [manual zone actions](manual-zone-actions.md)
  for transaction, ownership and privacy requirements.
- Graveyard/exile piles display and drag the most recently added card. Moving
  that top card hides it optimistically, immediately reveals the next card,
  and keeps the captured source identity stable until the server confirms.
- The library context menu exposes the owner's current in-game sideboard.
  Sideboard identities remain owner-private and may be moved manually to that
  player's hand, battlefield, graveyard, or exile. Each new BO3 game
  instantiates the sideboard from the most recently committed between-game
  partition.
- Every graveyard/exile pile accepts eligible owned or controlled cards as a
  convenient drop surface. The optimistic client and authoritative server both
  route the card to its immutable owner's graveyard/exile; current battlefield
  control and the particular drop surface cannot override zone ownership.
- Every seat owns a distinct public battlefield coordinate space; cards from
  different seats must never be flattened into one overlapping canvas.
  Battlefield drops are nudged away from a complete overlap, including when a
  permanent is tapped. Ctrl/Shift multi-selection exposes concise batch moves
  to hand, graveyard or exile, ordered/random moves to library top or bottom,
  and whole-library recycling. Cards return to their immutable owners and
  tokens disappear when leaving the battlefield. Both the optimistic layout
  and server placement spread ordinary batches enough to expose card centers;
  large batches compress within the bounded battlefield lane.
- P4 Generic 1v1 and Duel Commander use opponent-above / local-player-below lanes. Normalized card
  coordinates are stored from the controlling seat's local perspective. Every
  client, including spectators, vertically mirrors top-row battlefields
  (`x → x`, `y → 1-y`) and retains bottom-row coordinates. Drops use the inverse
  transform before sending. A land band therefore touches the outer edge of
  its displayed battlefield without changing horizontal order. Card artwork
  remains upright; only the vertical position changes.
- Spectators use the stable per-game authoritative turn order. P5 expands the
  same per-seat model to EDH. Four-player EDH uses the viewer-relative clockwise
  quadrants defined above.
  In three-player overview, the two remote battlefields split the upper half
  and the local battlefield spans the full lower half; spectators use a stable
  equivalent with the third seat spanning the lower half. Primary-battlefield
  mode gives the selected battlefield the full left-side height while the two
  remaining battlefields divide the right side evenly. Both layouts leave
  eliminated battlefields visible but muted.
- Tokens are selected from the local token catalog and created
  directly on the acting player's battlefield. A token moved to any non-
  battlefield zone disappears instead of entering that zone.
- Purpose-named attack/block actions use the public arrow protocol. For spells
  and abilities, the explicit **Choose target** menu replaces the ambiguous
  Draw arrow wording: one or more controlled battlefield cards, or one locally
  owned card on the shared stack, may point to any seated player or battlefield
  card. Target arrows span the shared tray and battlefield, clear when their
  source leaves its zone or changes battlefield controller, and otherwise
  expire on the next phase/turn transition.
- The source card's owner may **Attach to…** another battlefield card or
  **Detach**. Same-controller-lane attachments snap onto the host and follow
  host drags and **Arrange battlefield**. Cross-lane attachments stay in the
  controller's array and render stacked on the target in the table-level
  relation layer. Attach never changes controller and does not infer card
  legality.

---

## Forge multiplayer player information

In three- and four-player Forge fields, the player name, life and hand count
remain readable when a pinned inspector narrows the space beside the decision
dock. A narrow field puts its public zone buttons below the identity row,
wrapping them into a grid instead of shrinking their labels into the life disc.
Optional mana and spectator hand controls retain separate space. If even the
identity row cannot fit beside the dock, it moves above the visible decision;
that field's card area ends before the metadata and adapts to the remaining
height. Zone buttons continue to open the original player's exact zone.
Gaining, spending or clearing floating mana does not change this field height.
Wide headers retain their original inline layout; narrow headers use a stable
mana-row budget rather than adding and removing space as colors appear.
When only the mana readout is constrained inside an otherwise inline header,
it may use three columns within the original identity band. This does not turn
that whole header into a permanently taller layout. Ordinary mana displays
retain their original single row and symbol/text sizes.

## Floating card preview

- Hovering any visible table card shows large art and its name beside that card.
- Shared selection/context previews preserve readable nearby placement before
  choosing extra size farther away. Protected actions remain clear; an empty
  nearby area is not discarded merely because a remote area can enlarge art.
- Where the catalog supplies independently printed faces, the large preview
  displays all faces together without a switch. This includes visible hand
  cards in both manual and Forge tables, as well as public-zone
  browsers, token and emblem details, library search, Sideboard inspection, and
  rules-mode card inspection. The current face appears first. Faces are placed
  side by side when space permits and stacked in narrower inspection panels;
  floating previews fit their available viewport.
  Ordinary single-face library and public-zone inspection retains the original
  proportions. Additional width is reserved for actual multiple printed faces,
  rather than enlarging the default one-card layout. A gallery size change
  recomputes its source-side placement, including late metadata arrival.
  An ordinary public-zone browser retains its 960-unit window cap and
  320-unit/38-percent inspector cap. Multiple printed faces may use the wider
  1120-unit window and 580-unit/52-percent inspector caps.
- A multi-face hover preview stays open while the pointer is over either its
  source card or the preview, with a short interval to move between them. The
  preview has no face-switch action. Leaving both closes the preview without
  reserving permanent table width or retaining stale card details.
- Forge table previews use unoccupied space, preserving public cards, player
  counters, zone counts, the phase strip and actions. They show only complete
  card faces, with no state footer; battlefield tiles and the right-click
  inspection column retain current state and linked-card details. If readable
  full faces cannot fit, an **Inspect card** button in blank space opens the reserved
  inspection column on demand; right-click, or Menu / Shift+F10 on a focused
  card, opens the same view. Hover alone does not reflow the battlefield.
- Previewing another face never flips a tabletop card, transforms a rules-mode
  permanent, chooses a face to cast, or changes the selected physical card.
  Manual **Choose face** and engine-authorized game actions remain separate.
- Hidden identities and face-down cards expose no printed-face gallery or catalog
  lookup. A newly hidden card clears the displayed face data. Missing back
  art uses that face's name and available printed text; it does not
  substitute the front image or current-face rules.
- Language follows Settings (zh/en + MTGCH fill for Chinese art/text when needed).

## Game log and chat

The shared room stream fills its dedicated optional right rail, including at
least:

- Draws (public wording as allowed)  
- Casts / stack / battlefield moves  
- Life / damage  
- Chat  

The bottom of the pane contains a compact single-line chat composer. Players
and spectators may post while the table is open, including after a game
result. Messages appear only after the server appends them to the public log.

System log wording and built-in zone, phase, and counter labels follow the
interface language. Unambiguously identified public card names follow the
independent card-language setting, using the local catalog or cached metadata
and retaining the original name when no translation is available. Viewing logs
does not start card downloads. Existing entries refresh when either language or
the available local metadata changes. Player names, custom counter labels, and
chat remain literal; hidden-card descriptions never trigger identity lookups.
Legacy random-selection entries share a player/card text field, so their target
names remain literal rather than guessing which kind of name was selected.

### Server retention (owner direction)

| Policy | Meaning |
|--------|---------|
| **Server stores full match state** | Including hidden zones and **opening hands** under the trust-server model. |
| **Log retained for a period** | **TTL ≈ 1 week** for operator review/debug; the compatibility API exposes only its public log projection. |
| **Bounded live log** | Keep at most 10,000 authoritative entries per game and project the newest 500 with `logStartId` / `logTruncated`; ids remain monotonic. |
| **Not** a public permanent archive product | No matchmaking history site required for v1. |

**Is this reasonable?** **Yes**, given the product already **trusts the server** with hidden identities. Full server-side log + opening hands helps dispute resolution and debug; clients still must not show unauthorized private info in the live UI.

The client replay browser/viewer has been removed. Operator archive files remain
private and expire with the configured TTL; the public-log API is retained for
compatibility, not full-state reconstruction.

---

## Client vs server duties (table)

| Client | Server |
|--------|--------|
| Render viewer-relative table, zone docks, hover preview, drag juice | Authoritative phase, seats, zones, stack, life |
| Local art cache | Persist room state + event log (incl. private events) for TTL |
| Project what this viewer may see | Fan-out role-appropriate views; keep full state for storage |

---

## Library search

- The card list and inspector remain usable at the minimum window size with
  enlarged UI text. Inspector details, selection ordering, destinations, and
  toggles scroll; the selected count and completion action remain pinned.
  The preview keeps its full portrait visible within the available inspector
  height. Clearing a filter also cancels any pending delayed filter update.
  An ordinary single-face inspector retains its 340-unit column cap and
  220-unit art region, leaving the destination controls on the initial view
  when normal dimensions allow. Multiple printed faces may expand the gallery;
  details and destinations remain scrollable with completion controls pinned.
  Destination labels put the zone before the player name; hovering shows the
  full label when either part is elided. Display order never changes ownership
  or the target seat sent to the server.
- Opens **full own library** by default (find land / specific cards, etc.).  
- **View top card** opens the current top card privately; right-click can move
  it directly to the acting player's hand, battlefield, graveyard, exile, or
  the source library top/bottom. A single card has only ordinary top/bottom
  actions because ordered and randomized placement are equivalent.
  Moving the inspected card logs a top-card view and its destination. Its name
  stays private by default; the player may explicitly enable disclosure in the
  game log. The server rejects the move if the inspected card is no longer on
  top. Full-library searches keep their search log.
- Right-click also offers **view top X**. Each viewed card has its own
  destination selector: hand, battlefield (optionally face down), graveyard,
  exile, source library top, or source library bottom. Arrow order defines the
  relative order of cards assigned to the same library end, and top/bottom
  groups may be randomized independently. This directly supports effects such
  as Expressive Iteration without splitting one resolution into several
  commands. The server validates and applies the complete current prefix in
  one transaction. The public log exposes counts and the number of destination
  groups. Optional disclosure on each assignment adds the explicitly revealed
  names and their destinations to the public log for every player and spectator.
- Top-X assignment controls include an optional reveal-in-log choice, off by
  default. It applies only to the batch being assigned, then resets to off.
  Each card retains its own choice across reordering and later batch changes;
  the card preview allows review and editing before confirmation. Unassigned
  remainder cards stay private. Returning a card to the remainder clears its
  disclosure choice. Face-down placement suppresses name disclosure. Cancelling
  the popup or a rejected resolution reveals nothing. Revealing names in the
  log does not expose private hand contents in subsequent snapshots.
- Assigning a top-X destination, including returning cards to the remainder
  destination, deselects the affected cards and clears their Shift-selection
  anchor. The preview remains available; later assignments use the new
  selection. Context actions on an unselected card preserve unrelated selections.
- Name/type filtering accepts English and Simplified Chinese catalog aliases.
- After choosing card(s), pick destination:  
  **hand / battlefield / library top / library bottom / graveyard / exile**.  
- Multi-selection preserves the explicit selected order. Multiple selected
  cards may be placed on the requester's battlefield from one deterministic
  anchor. Selection changes only through the checkbox; row clicks update the
  preview immediately. Right-clicking a selected card applies to the whole
  selection, while right-clicking an unselected card applies only to that card.
  The card context menu retains hand, battlefield, and ordered/random
  library-top/library-bottom actions. Graveyard and exile each use one ordinary
  action rather than duplicate ordered/random variants.
- When finishing the search, choose:  
  - **Reveal search:** log includes **card name(s)**, e.g. “Player X searched library and put **CardName** into hand / …”.  
  - **Hidden search:** log **without** card names, e.g. “Player X searched library and put a card into hand / library top / …”.  
- Log is **visible to all** players (anti-cheat).

Library-search grants and pending library/public-zone consent belong to one
game. A restart, completed game, sideboarding, or leaving the active table
closes these requests, clears any privately revealed library cards and grant
IDs, and does not offer to shuffle the replacement game's library. Ordinary
snapshots preserve live requests. A same-number restart is announced to every
room member before the replacement snapshot.
Both same-number restarts and numbered subsequent games clear old selections,
targeting, menus, optimistic commands, and drag delegates before physical card
IDs can be reused by the replacement game.

## Concede

- In-game **concede / surrender** control for a seated player.  
- **Loses the current game**; updates BO score (e.g. 1:2).  
- Visible to the room via log. EDH multiplayer elimination follows the
  product behavior defined in `match-flow.md`.
- A completed match opens a modal result summary instead of reserving a
  permanent banner above the table. Members may stay at the table
  or return the whole room to its waiting state. Returning archives the
  completed match, preserves selected decks and seats, restores every deck's
  originally registered mainboard/sideboard partition, and clears Ready,
  loaded state, game state, and score.

## Tokens and emblems

Tokens use the installed local token catalog.

| Item | Behavior |
|------|----------|
| **Token DB download** | User can download/update a **token catalog** (metadata; like Oracle but for tokens). |
| **Add token** | In-game action: pick from token DB → **create on battlefield**. The picker list shows identity (P/T, type line, set number); hover and the rules popup keep oracle text. |
| **Art** | Follows card language: prefer Chinese art in Chinese mode, fall back to English when unavailable. Download into local cache on select. |
| **Zone rule** | If a token would enter **hand, library, graveyard, or exile**, it is **removed immediately** (does not stay in those zones). |
| **Battlefield** | Tokens remain on battlefield until moved/removed by player actions; manual tabletop only (no auto-spawn from spell text). |

Emblems share the catalog picker and language-aware art cache, but are separate public
objects in the command zone, not battlefield tokens or commanders. They are
available in every manual format. A compact floating badge on each battlefield
opens that player's emblem list without reserving battlefield layout space;
opponents and spectators can inspect the same identities and enlarged art.
Localized rules text remains readable alongside an English fallback image;
each viewer chooses their own card language without changing server identities.

- An active player may create an emblem for any active seated player, including
  an opponent. The picker defaults to the acting player. Effects are not executed
  automatically in manual mode.
- Each emblem is an independent instance. Only its owning player may explicitly
  remove it to correct a tabletop action. Spectators cannot create or remove it.
- Emblems cannot be dragged between card zones, tapped, targeted as permanents,
  cast, or included in commander tax, commander damage, deck, or zone card counts.
- Disconnect/reconnect preserves emblems. Eliminating an owner clears that
  owner's emblems, not emblems they created for other players. Restarting or
  advancing to a new game clears all emblems.
- The protocol uses `game.create_emblem` (`seat`, `name`, `setCode`,
  `collectorNumber`, optional `typeLine`) and `game.remove_emblem` (`emblemId`).
  Acknowledgments identify the room, owning seat, and emblem instance; public
  snapshots store the objects in `seats[].emblems`, separate from card arrays.
  The server validates identity text and enforces a limit of 128 per owner.

## Between games — sideboard (non-BO1 only)

| Mode | Sideboard between games? |
|------|---------------------------|
| **EDH** | **No** — one game only |
| **BO1** | **No** |
| **Generic 1v1 BO3** | **Yes** after a game ends (until match complete) |
| **Duel Commander BO3** | **Commander-selection Ready gate** — one or two mainboard cards may be designated for the next game while the registered card list remains unchanged |

### Sideboard phase rules

- Players edit **only** the deck already registered for this match.  
- **Allowed:** drag cards **main ↔ sideboard** (rebalance).  
- **Duel Commander:** deck movement is disabled; star controls on mainboard
  cards change only the next game's one or two commander designations. The
  timed workspace remains so both players can signal Ready for the next game.
- **Forbidden:** paste-import new cards; search-add from full card DB; any card not already in main+SB of this list.  
- **Timer: 5 minutes.** Players click **Ready**; when **both Ready**, start next game **immediately**.  
- **If 5 minutes elapse without both Ready:** **force start** next game using each player’s **main/SB from the end of the previous game** (unfinished sideboard discarded / not applied).  
- UI is a near-fullscreen, restricted two-table workspace. It fills the table
  without a framed modal inset or scrim ring; the playmat remains visible
  beneath glass, and only the top-right Settings control stays reserved on
  Forge. It expands entry
  quantities into compact physical-looking piles: copies with the same card
  name share one enlarged top-card image, visible staggered edges, and a
  quantity badge. Every registered card remains represented on the two
  tabletops at once, with no list or scrollbar; dragging a pile moves one copy.
  On a wide landscape viewport, the mainboard table occupies the larger left
  column and the sideboard occupies the right column, so both can use the full
  table height and display substantially larger cards. Narrow or tall
  viewports fall back to mainboard above sideboard. Each table is divided into
  explicit horizontal category lanes with a fixed left label/count; cards flow
  left-to-right and wrap only inside their own lane. Instants and sorceries are
  separate lanes. Type classification recognizes localized English and
  Simplified Chinese type lines. If an older registered partition has no type
  line, the owner client resolves it from the matching local catalog printing
  before placing the card in a lane. The adaptive lane grid shrinks cards only
  as needed, like laying a complete deck out on a physical table. Hovering a
  laid-out card shows a large, full-resolution art-only inspection image without
  surrounding chrome. A single-face hover retains its 320-unit/quarter-panel
  width cap; multiple printed faces may use additional space. Laid-out cards
  and the lightweight card-shaped drag preview reuse prepared table thumbnails;
  the preview follows the pointer while
  the source card remains fixed, enabling smooth cross-table moves.
  Import/search-add stay absent.
  Short or scaled windows use compact padding and keep Ready visible. Player
  names elide independently of ready/count badges. Limited filters and virtual
  basic lands move into a scrollable tools popup so the two card tables retain
  useful height; opening these tools does not replace or reset either partition.

After a match ends, the player may still inspect their visible hand and browse
their graveyard/exile. Preview and browsing do not enable card movement,
dragging, counter edits, or any other finished-game command.

The previous-game review preview follows its current player/zone filters and
the latest public projection: refresh a retained selection, select the first
remaining card when it disappears, and clear the preview when no cards remain.

## Non-goals for table chrome (v1)

- Automatic priority/stack legality engine  
- Legacy desktop chrome or a pixel clone of another client
- Permanent forever storage of every match without TTL  

## In-match keyword reference

The manual table action rail and the Forge table Settings drawer provide a
**Keyword reference** entry. The modal stays in the match, works without a
selected card, and searches the bundled English and Chinese keyword names,
aliases and rule numbers. Empty search browses the entire index; Reset clears
the search, and an unmatched search displays a clear empty state. Entries and
source/coverage notes scroll without truncating their explanations.

The reference reads only its bundled public catalog. It never reads a card or
room projection, sends gameplay/Forge input, enforces rules, or persists match
state. While visible it blocks underlying table shortcuts and pointer input.
Escape and the close button dismiss it and restore usable table focus.
See [keyword source and coverage](keyword-reference.md) for the pinned rules
version, maintenance process, translations and scope.
