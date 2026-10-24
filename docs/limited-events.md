# Limited event modes

This document defines Hexproof's set Sealed, set Booster Draft, custom
Cube Draft, and Commander Cube modes. Limited support distributes private card identities and validates
that a submitted deck came from the generated pool. It does not resolve card
text or turn the tabletop into a rules engine.

## Corrected product taxonomy

Set Sealed, Set Draft, Cube Draft, and Commander Cube are explicit user-facing modes. They are
not a matrix of interchangeable pack sources and distribution algorithms.

| Mode | Source selected by organizer | Distribution | Online coordinators |
|------|------------------------------|--------------|---------------------|
| Set Sealed | One Magic set | Six Limited boosters per player | Individual Swiss tournament |
| Set Draft | One Magic set | Two-to-eight-player, three-pack pick-one draft | Individual Swiss tournament |
| Cube Draft | One saved custom Cube | Two-to-eight-player, three-pack pick-one draft without replacement | Free-play room (default) or individual Swiss tournament |
| Commander Cube | One saved custom Cube | Two-to-eight-player; 20-card packs with two picks per pack; smaller pods may open two independent packs together | Balanced multiplayer free-play tables of up to four |

The local pack simulator is a utility, not an event mode. It may open a chosen
product for inspection but never creates an event pool, modifies a deck, or
claims server-authoritative fairness.

Set Sealed and Set Draft are created through **Events → Create tournament**;
the main menu has no separate Limited creation shortcut. Cube Draft retains
its **Create room → Cube** entry, with **Regular Cube** and **Commander Cube**
variants. Both select a saved Cube from the ordinary deck library. **Pack simulator** occupies the former Replays
slot on the main menu and remains available offline or while in a room. Settings
has no duplicate simulator entry; the Limited tournament form keeps a simulator
shortcut. Opening the simulator never creates an online tournament.

Creation forms keep their controls usable after wheel scrolling reaches the
top or bottom. The next click on Create or another visible form control must
activate that control without an extra click to clear retained scroll motion;
active dragging and flicking remain uninterrupted.

Local simulation presents each generated booster through a skippable reveal
sequence: a booster opens and card backs are dealt in rarity order, with rare
and mythic cards at the end. Each card back is independently selectable, so the
user reveals the specific card they click rather than being forced through a
fixed sequence. Card art begins loading behind the card backs; missing or slow
art uses the card-name placeholder and never blocks revealing the pack.
Multiple boosters advance one at a time, while the complete generated result
remains available in the simulator after the overlay closes. Users may disable
pack-opening animations in Settings, including the Set Sealed reveal below. The simulator product chooser
searches installed products by set code, localized set name, and product name.

The previous configurable random Cube-pool presentation is obsolete. Cube is
managed in the deck library, selected as a format in the ordinary creation
screen, and enters online play as a configurable two-to-eight-player Cube
Draft. Ordinary room creation always uses **Free play**. **Events → Create
tournament → Cube draft** creates a Swiss tournament with the same Cube and
draft settings, but a separate registration and competition experience.

## Local draft practice

**Pack simulator → Draft practice** and the draft tournament creation shortcut
open a single-player, offline practice session. It uses installed Limited set
products or a saved regular Cube, with two to eight seats (eight by default):
one human and automated opponents. Set practice resolves the same preferred
Limited booster as online Set Draft and labels approximate collation before
starting. Cube practice uses three 15-card packs per seat and requires at least
45 physical cards per seat. Commander Cube profiles are not part of this mode.

All packs are generated together through the existing local product simulator,
preserving Cube quantities without replacement. Each human confirmation makes
one pick at every seat, then passes the remaining packs left, right, and left
over three rounds. The final card requires confirmation too. Each bot uses only
its current pack and own previous picks, with simple rarity, card-color, and
mana-curve preferences and small random variation. This is a basic practice opponent,
not a card-strength or archetype evaluator. There is no pick timer.

The C++ practice controller owns local physical instances, packs and pools and
projects them into an independent `LimitedSessionState` for the shared draft
and construction views. Only the human pack/pool and seat counts reach those
views. No WebSocket command, online event identity, account, opponent connection,
or tournament registration is needed. Local practice never changes online
draft projections, readiness, competition, or reconnect credentials.

After drafting, the human builds at least 40 cards using their pool and ordinary
basic lands. **Save to deck library** explicitly creates a local Custom deck
with exact drafted printings and unselected picks as the sideboard. A later
**Save new copy** preserves the previous saved deck. Saving validates instance
ownership and duplicate picks; a failed save preserves the current selection.
The deck can subsequently be renamed or exported through the ordinary library.

Practice and construction edits survive screen navigation for the current
application run, including edits after saving a copy. Closing the application
ends the in-memory practice. **New draft** confirms discarding the current
practice and unsaved edits; already saved library decks remain. No practice
state is written into online construction recovery storage.

## Arena-aligned set modes

### Set Sealed

- Creation selects a **set**, not a raw booster manifest and not a configurable
  pack count.
- Starting the event locks the participant list and the resolved Limited
  product for that set. The event may start once at least two players are
  checked in.
- The server generates exactly six independent Limited boosters for every
  participant and places all opened cards directly into that participant's
  private pool. The flat private pool preserves generation order: each
  consecutive `product.cardsPerPack` cards belongs to one generated booster.
- On first entry to construction, the owner sees a skippable six-pack reveal
  using those existing private instances. Opening or skipping the animation
  never generates new cards or changes the pool. The common pack-opening
  preference can disable automatic playback; **View opened packs** replays it
  explicitly. Local construction recovery remembers that it was already shown,
  so returning to the event does not replay it automatically. Leaving the
  builder closes the overlay. Submitted decks do not auto-open the reveal.
- Each participant builds a main deck of at least 40 cards. Unselected pool
  cards are that participant's sideboard.
- Plains, Island, Swamp, Mountain, and Forest are available without limit.
  Wastes or another special basic land must come from the generated pool unless
  a later product-specific rule explicitly provides it.

### Set Draft

- Creation selects a **set**. The application resolves the set's Limited
  booster automatically.
- The Arena-style player-draft profile supports two to eight checked-in draft
  seats and has no bots. The event may start once at least two players are
  checked in.
- Each seat receives three boosters. Pack one passes left, pack two passes
  right, and pack three passes left. In a two-seat draft both directions
  resolve to the same opponent, so packs simply alternate between the two
  players.
- A player privately selects one card from the current pack. The server adds
  that physical card instance to the player's drafted pool and passes the
  remaining pack.
- Passing may remain asynchronous: a pack that reaches a busy seat waits in a
  private queue. The next pack round starts only after every pack from the
  current round is empty.
- The final card stays in the current pack until its owner selects and confirms
  it, just like earlier picks. Disconnect/reconnect restores that pending
  selection opportunity, queued packs, prior picks, and pack round.
- The participant UI uses a large current-pack gallery on the left and a
  compact, printing-aware picked-card list on the right, with copy counts and
  a mana-value summary. An on-demand seat popup renders the authoritative
  participant order as a physical table,
  rotated so the viewer is at the bottom, and names both the player receiving
  the current pack and the player from whom the next pack arrives. Seat order
  increases clockwise, so left passes advance through the order and right
  passes reverse through it. The seat popup closes when the draft workspace
  or one of its ancestors becomes hidden, including the transition to deck
  construction; returning to the workspace does not reopen the old modal.
- Current-pack cards display rarity and both regions open a large card
  image on hover. The picked pool supports name, color, type, mana-value, and
  rarity filters, while the current
  pack always remains complete so a filter cannot hide a legal pick.
- The current pack and picked-pool regions remain side by side while each can
  render its minimum useful card width. Narrower views stack the complete pack
  above the picked pool when enough height remains. Short, narrow views use
  current-pack and picked-pool tabs; current-pack card height is bounded by its
  viewport so a complete card remains visible. The picked-pool header and
  filters scroll when necessary, preserving a list viewport tall enough for
  complete card rows. Scrolling at the list boundary continues through that
  surrounding content. Confirmation stays
  pinned below the pack's scrollable content; only a current, non-pending
  selection can be confirmed. Event management and chat remain available in
  an overlay without consuming the card workspace.
- After all three rounds, each participant builds a main deck of at least 40
  cards from drafted cards plus unlimited ordinary basic lands. Unselected
  drafted cards are the sideboard. Before initial construction, players choose
  whether to keep all picks in the main deck and trim it, or start with an empty
  main deck and add from the pool. This choice never overrides a submitted deck.
  Each click adds the current physical pool card. Rapid clicks at the same grid
  position continue adding the successive cards after the preceding card moves;
  the desktop's double-click classification must not discard the second card.
  Once wheel scrolling stops, including after reversing direction in the middle
  of a card grid or reaching its boundary, the next click selects the visible
  physical card without an extra click to clear stale scrolling state.
  Dragging within the grid continues to scroll without selecting a card.
  Double-clicking a current-pack card confirms it through the same pending/stale
  guards as the confirmation button. Pick/deck rows show localized names, actual
  card colors, and full costs when the installed catalog contains that metadata;
  Commander color identity is not used for row tinting.

Pick clocks and automatic timeout picks are not implied by the card rules.
They require a separate server-owned tournament-operability design before they
are enabled; the client must never invent a private pick locally. The explicit
free-play Cube controls below are not a timeout-pick policy for Swiss drafts.

### Free-play Cube seat control

Normal Cube and Commander Cube retain every physical draft seat and private
pool through disconnections. A short disconnect pauses that seat; it never
implicitly authorizes automatic drafting. During drafting, a participant can
explicitly enable or disable their own automatic drafting. The organizer can
only enable it for a seat continuously offline for strictly more than three
minutes, after a confirmation dialog. They cannot disable someone else's
automation, take over an online seat, or inspect another pool. The server owns
the offline timestamp and validates elapsed time again on the command. A new
connection clears the offline interval; returning does not silently reclaim
control. The player explicitly reclaims it.

`limited.set_draft_control { participantId, automatic }` returns
`limited.draft_control_set { tournamentId }`. Random server-side picks obey
the profile's one/two-card count and usual physical-card conservation and pass
direction. Public progress includes `autoDraft`; current packs and pools
remain visible only to their owners. `tournament.snapshot` participants expose
`disconnectedAt` for the client affordance, not as client-provided authority.

During building or free play, a participant may explicitly sit out using
`limited.set_participation { participating: false }`, acknowledged with
`limited.participation_set { tournamentId }`. Their seat, pool, submitted deck,
and local edits remain. The public `withdrawn` progress flag (and tournament
`dropped` flag) excludes them from deck-readiness requirements and invitations.
The room advances when at least two participating players have all submitted.
There is no automatic withdrawal or host-authorized withdrawal: an absent
player who has not opted out can still hold up deck building. Auto-draft does
not build or submit a deck for them.

The same command with `participating: true` restores participation. During
building, this restores the normal readiness requirement; after free play has
started, the player must already have a submitted deck before rejoining. A
withdrawn player may edit and submit first. Participation cannot change while
the player has an invitation or table assignment. The room never regresses to
building. These commands do not apply to Swiss events. Host sit-out preserves
the room; host leave still closes it.

The Cube room's Seats/Chat/Rules panel keeps these actions and a scrollable
profile summary reachable during draft, building and free play. Rules cover
pack/pick counts, construction minimums, Piper fallback for Commander Cube,
advisory partner/identity rules, basic lands, seat control and consent-based
free-play tables.

### Provisional Commander Cube planning

The picked-card sidebar offers a private, local-only plan for up to two exact
drafted instances. Possible-commander candidates are a shortcut; an unrestricted
view remains available for house rules. Search and preview do not select cards
or change the current pack. Combined color identity and outside-identity counts
are advisory, never pick restrictions. Missing metadata and unchosen Piper
colors remain unknown instead of being invented. Two same-name instances stay
distinct. The plan uses a separate event/participant/server-scoped draft-store
key and survives reconnects without overwriting construction drafts. Final
commander choices and Piper colors must still be confirmed during building.

## Set and booster data

The set chooser shows one entry per supported Limited set and can be searched
by set code, localized set name, or installed product name. Local simulation
and Limited tournament creation use the same search and selection semantics.
The chooser does not expose every retail booster variant. Each entry resolves
to one installed manifest with:

- set code, localized display name, and release date;
- the Limited booster kind (`draft` or `play`);
- cards per booster and the weighted collation definition;
- collation basis (`arena`, `tabletop`, or `approximate`);
- source revision and product hash.

Modern sets normally use Play Boosters while older sets use their appropriate
Draft Booster. The manifest, rather than a global fixed slot recipe, determines
whether a booster has 14, 15, or another supported number of playable cards.

MTGJSON booster sheets mapped to Scryfall printing identities remain a useful
source for tabletop-based collation. They must not be labelled `Arena exact`
unless Arena-specific substitutions and digital slot behavior are encoded in
the manifest. Sheet weights may exceed one billion when the source collation
requires it; Hexproof keeps those products while the weight stays inside the
JSON-safe integer bound. Each sheet's combined weight must also fit in a
signed 64-bit integer; the database builder and server reject overflowing
sheets, and local simulation stops safely if it encounters one.
When a set has no installed Play, Draft, Arena Play,
or default Limited product, a rarity approximation remains allowed only with a
prominent `approximate` label visible before registration and in the event
lobby. Leftover official products such as bundle promos do not replace that
approximate Limited booster.

### FRA upstream Play recipe

The card-data build installs `mtgjson-fra-play` from MTGJSON FRA booster data.
It preserves all upstream pack variants and sheet weights, including fixed
two-card echoed pairs and the conditional third-card sheets that exclude the
selected character's pair across treatments. Each Play Booster contains 14
playable cards. Fixed two-entry sheets sampled twice without replacement emit
both partners; this recipe does not require the paired-sheet extension below.
It is tabletop-based upstream collation (`official`/`authentic: true`), not an
Arena-exact or factory-sheet guarantee.

Release builds no longer install the historical `hexproof-fra-play` estimate.
If an archive contains FRA but lacks an importable upstream Play definition,
the build fails. Old installed catalogs keep their previous recipe until the
owner updates card data; existing events retain their locked product.

Products support at most 128 sheets, 256 variants, 10,000 weighted card entries
(5,000 for Cube), and 800 KiB of encoded JSON. Large definitions deduplicate
printing identities into an optional `cardPool`, whose entries have unit
weight. A sheet uses either inline `cards` or `cardRefs`; each reference has a
one-based `cardIndex` and a positive JSON-safe `weight`. Mixed representations,
missing/out-of-range references and non-unit pool weights are invalid. Pool
size and the total expanded entry count are bounded before allocation. The
catalog builder retains inline cards when sharing would increase size. Client
simulation and product-art downloads resolve references; the server expands
only its runtime sheets. The locked/transmitted definition and product hash
remain compact, and input mutation cannot change a locked pool or references.

The historical compact definition remains supported: a missing optional
`typeLine` inherits the nonempty type from the same set/collector identity.
Conflicting types are invalid. This compatibility does not change card weights.
Generators and servers must support the FRA recipe and its bounds. Changes to
the recipe representation or required bounds follow the
[protocol compatibility policy](protocol-compatibility.md); application-version
equality is not an admission gate or proof of recipe support.

Release builds require `FRA:play` explicitly, including when a set member is
missing or malformed. Slot counts and weights must be positive integers (not
booleans, floats or numeric strings). FRA validation requires 14 cards per pack,
a complete fixed two-card pair, and its corresponding third-card table excluding
both base and borderless partners. Failed validation preserves the prior output.
`metadata.limited_product_source` retains the upstream source, actual archive
version/date and SHA-256. Missing revision metadata in a required release build,
descriptor/archive version disagreement or mixed
archive revisions fail instead of recording misleading provenance.

Paired sheets use reciprocal `pairCollectorNumber` values within the same set
and finish. Every entry in such a sheet must be paired, with equal partner
weights and rarities. One slot draw emits both cards, counts as two physical
cards, and removes both when sampling without replacement. Cube sheets cannot
use this extension. `excludePrevious` excludes matching set/collector/finish
identities already drawn in the pack; an unavailable draw fails rather than
returning a short pack. Foil and nonfoil copies are distinct identities.
Both client simulation and authoritative server generation implement these
semantics. Products using this paired extension need the updated client and
server: older implementations count independent draws instead of physical cards and
reject it, rather than silently opening an incorrect pack. Existing manifests
without the optional fields keep their previous behavior.

The organizer client sends one bounded, fully resolved manifest because the
hub does not own the card database. The server validates, clones, hashes, and
locks it before generation. Every participant sees the set summary, collation
basis, and hash. Clients never report self-generated online pack results.

**Settings → Download set art** is the standalone entry for the same
product-art cache. Set Sealed and Set Draft registration lobbies still expose
an optional download for the event product. The client reads the matching
installed manifest,
deduplicates every printing across all sheets (including bonus sheets), expands
independent card faces, and stores the exact images in the ordinary local
cache. Automatic source selection uses MTGCH first for Chinese cards and
Scryfall first for English cards. MTGCH-first Chinese downloads use the set
card index as an acceleration hint and fall back to the normal per-card
Scryfall/MTGCH chain for every missing or failed entry. Progress and unavailable
image counts are local only and never block registration, picks, deck
submission, or event start.

## Custom Cube Draft

Cube persistence uses the ordinary deck library. A saved deck whose format is
**Cube** is the draft pool: its main-deck entries contain exact printing
identities and physical quantities, and it has no sideboard or commander
designation. It does not store a booster collation recipe or a `cards per
pack` setting. Users import, edit, export, delete, and filter it through the
same screens as every other saved deck; there is no separate Cube importer or
Cube library.

Cube products preserve each saved entry's rarity when known and leave missing
rarity empty; Cube membership does not make a printing `special`. Display
enrichment prefers a nonempty rarity from the installed exact-printing catalog,
including for existing event snapshots with the old `special` placeholder.
If the exact printing or its rarity is unavailable, retain the supplied value.
This never modifies the server's locked pool, collation, or instance identities.
Gallery badges and tooltips recognize genuine `special` and `bonus` rarities
alongside common, uncommon, rare, and mythic.

Selecting **Cube** in the ordinary creation screen chooses one saved Cube and
creates a free-play room with a configurable capacity of two to eight
players. Cube Swiss tournaments are created in Events. Either mode requires:

- every Cube entry resolves to an exact printing;
- the Cube contains at least 45 physical cards for every configured seat; and
- at least two participating players.

For free-play rooms, the creator occupies the host seat immediately; joining
by room list or room code occupies a seat without registration. Every seated
player must be online and ready before the host starts. An unready seat is
never silently excluded. Swiss tournaments retain registration and check-in.

For regular Cube, the server snapshots and hashes the Cube at start, expands quantities into
physical card instances, shuffles the full stock, and makes three private
15-card packs for every participating player without replacement. Each player
drafts three packs, passing
left, right, then left through the same asynchronous queue used by Set Draft.
Cards beyond the required 45 per active player remain undealt. Participants then use the same
40-card deck builder as Set Draft. Cube cards are phantom event objects and
never modify a user collection or saved constructed deck.

### Commander Cube profile

Commander Cube is a distinct `commander_cube` distribution and multiplayer
free-play mode. It is not a Swiss tournament, a saved 100-card Commander deck,
or an alternate label for regular Cube's 40-card construction. Community Cube
rules vary; this implementation uses the following bounded profiles rather
than claiming every Commander Cube uses the same rules:

- Two to eight draft seats, with a default room capacity of four. For a capacity
  of two to four, the host chooses 3/4/5/6/8 packs per player and opens one or
  two packs together. The recommended default is six packs, opened in pairs.
  Five-to-eight-seat rooms use the standard three packs, opened individually.
  At every capacity, the host can enter 10–40 cards per physical pack, with a
  default of 20. Odd card counts are allowed. Creation publishes and locks the
  `draftSettings`; joining fewer players does not silently change those rules.
  The source must cover `capacity * packsPerPlayer * cardsPerPack` physical cards.
  The client shows the total drafted per player and the required source size;
  invalid pack sizes and insufficient stock block creation on both endpoints.
  Older creation requests that omit `draftSettings.cardsPerPack` keep 20-card
  packs; room snapshots publish the resolved value alongside the other rules.
  Distribution uses only actual draft seats, without replacement; extra source
  cards stay undealt. Missing stock disables the corresponding creation option.
- Passing alternates left/right by batch, using the existing private asynchronous
  queues. Paired packs stay separate, move together to one next seat, and require
  two distinct selections from each pack in one atomic `limited.pick`. Taking
  three from one and one from the other is invalid. Every pack's quota is
  validated before any mutation; duplicate, foreign, or missing IDs change
  nothing. The final one or two cards of each pack remain visible and require
  the owner's selection and confirmation. Explicitly automated seats continue
  to complete their own selections automatically.
  Odd totals end with one ordinary pack: five packs open as 2+2+1. Six paired
  packs open as three left/right/left batches. Reentry restores both current
  packs and their quotas; automatic drafting independently obeys each quota.
- Every participant finishes with `packsPerPlayer * cardsPerPack` physical picks and builds at least
  60 total cards, **including** one or two selected commander instances.
  Commanders must be distinct selected instances, not distinct names: drafted
  copies of the same partner may both serve as commanders. Except for the Piper
  fallback below, commanders come from selected physical main-deck cards. The
  selected printing,
  including set and collector number, becomes the command-zone card; it is
  never substituted with the first same-name card in the submitted deck.
  The construction picker browses the entire drafted pool and adds a selected
  commander to the main deck automatically. Its default candidate view includes
  legendary creatures, legendary Backgrounds, explicit commander-permission
  text, and cards with missing type metadata. An unrestricted drafted-card view
  remains available, with independent name, color, type, mana-value, and rarity
  filters. Candidate recognition is a shortcut, not a full legality check.
- The five ordinary virtual basics are available as in other Limited modes.
  Unselected physical picks remain a private sideboard/available pool; draft
  duplicates are legal. Constructed singleton and no-sideboard restrictions
  must not be applied to this pool-contained format.
- After drafting, each player can optionally select up to two extra copies of
  **The Prismatic Piper** (CMR #1) as commanders. The server supplies two stable,
  owner-private `fallbackCommanders` candidates separately from the drafted
  cards. Only selected fallback copies enter the submitted main deck and count
  toward its 60-card minimum; unused copies never enter the pool or sideboard.
  Fallback IDs are accepted only in `commanderInstanceIds`, never as ordinary
  `mainboardInstanceIds`. They cannot introduce arbitrary outside cards.
- During construction and free-play editing, each owner also receives three
  stable, private `optionalCards`: one outside copy each of **Sol Ring**
  (CMR #472), **Command Tower** (CMR #350), and **Arcane Signet** (CMR #297).
  All start unselected. The basic-land popup adds/removes them individually;
  only selected IDs enter `mainboardInstanceIds` and count toward deck and
  transport limits. These candidates never consume stock, inflate pick counts,
  enter the drafted pool, or become sideboard cards when unused/removed.
  This grants one extra physical copy of each, including when a drafted copy
  already exists; ordinary Commander Limited duplicate rules still apply.
  Optional staples cannot be commanders. Foreign, duplicate, and invented
  candidate IDs are rejected atomically. Local drafts, submitted snapshots,
  reentry, and locked table decks preserve their exact selections and printings.
- Each selected Piper, including a naturally drafted copy, requires one explicit
  W/U/B/R/G color choice. `commanderColors` stores `{instanceId, color}` pairs in
  submissions and owner snapshots. Missing, duplicate, unsupported, nonselected,
  or non-Piper choices reject the submission atomically. Removing a Piper also
  removes its choice. The client preserves choices in local construction drafts,
  uses them for color-identity reminders, and treats color-only edits as unsaved
  changes. Two Pipers may choose either different colors or the same color.
- The fallback follows the [Commander Legends draft rules](https://magic.wizards.com/en/news/feature/commander-legends-release-notes-2020-11-06):
  outside copies serve only as commanders, and normal partner requirements
  still apply. A Piper is not permission to pair with any commander or to add
  arbitrary colors. Partner qualification remains a manual group reminder.
- Commander qualification, partner compatibility, color identity, bans, and
  release legality are advisory under the manual EDH policy. This flexibility
  does not disable the server's physical pool ownership (apart from the bounded
  Piper and optional-staple exceptions), one/two distinct commander instances, explicit Piper colors,
  or 60-card minimum requirements. A compact construction-screen reminder opens
  the commander details, including after later card or basic-land changes.
- The room uses `casual` coordination only. Supplying the Swiss coordinator is
  rejected; scheduled rounds, standings, and score reporting are not part of
  Commander free play. Once all active players submit, the server randomly
  assigns balanced tables of at most four: 5 -> 3+2, 6 -> 3+3, 7 -> 4+3,
  8 -> 4+4. Two-to-four active players share one table. Assignments are created
  once and preserve submitted offline players; sitting-out players are excluded.
  Every participant automatically enters their assigned locked-deck room and
  readies there. Later games keep the existing free-invitation flow.

The draft and construction screens retain card previews and filters. Their
large card previews display all faces together for catalog-defined
independent faces, including draft practice, pack reveal, and the simulator's
completed pack results. The preview can be inspected without picking a card,
changing a deck, or revealing another player's private identities. Face
display stays local to the preview and updates for a different card; meld
results use their own printing, and missing back art never reuses front art.
Commander selection is preserved with a saved local construction draft and restored from
the authoritative private snapshot after submission or authenticated reentry.
Public observers see the draft profile and progress, never selected commander
instances or other private deck-building identities. Commanders become public
only through the normal game projection after the table starts.
At game start, `game.snapshot.commanders[].chosenColor` publishes each Piper's
choice against its physical `cardId`. It survives zone, face, and control
changes; it is not a temporary counter. Same-name commanders retain independent
command-zone cast counts and commander-damage records, and table labels
distinguish their copies and selected colors. Constructed Commander retains its
existing validation; these Limited exceptions do not authorize forged
`deck.select` commander data.

## Coordinators and lifecycle

Limited generation and drafting are separate from competition coordination:

```text
Set Sealed:  registration -> deck_building
Draft modes: registration -> draft -> deck_building
Swiss:       deck_building -> competition -> completed
Cube rooms:  deck_building -> free play -> room closed
Any active stage may be cancelled.
```

Starting locks the participant list and source snapshot; late joins are not
allowed. Set Sealed enters `deck_building` after server generation. Set Draft
and both Cube variants enter `draft`, then transition to `deck_building` after
the configured final pack. The `completed` branch applies to Swiss events; free-play Cube stays
in competition until its room closes and does not generate tournament history.

Every Swiss Limited event uses the existing registration, check-in,
individual Swiss pairing, score confirmation, standings, and completed-decklist
publication. After all competing players submit decks, the organizer publishes
round one. The standard client always lets the server choose its round count
from checked-in attendance; a two-player Limited event schedules one round,
and a three-to-eight-player event schedules three rounds. The tournament
coordinator owns those concerns but delegates pack generation,
drafting, pools, and deck containment to the limited domain.

During drafting, the player's picked-card area uses the same multiselect
filters as deck building: cards must include every selected color (additional
colors are allowed). Other categories use OR within a category, and different
categories combine with AND.
Filtering never changes the current pack or the underlying pool. Missing type
metadata is enriched from the local catalog when available; cards with
unresolved types remain accessible in the unfiltered view.

Cube free play has a dedicated room screen and room discovery/code entry. It
reuses the `casual` coordinator internally for bounded sessions, private draft,
reconnect, and deck ownership; it does not expose an event-management workflow.
Once everyone submits a deck meeting the mode's minimum (40 for regular Cube,
60 including commanders for Commander Cube), free play opens automatically
without an organizer handoff. Regular Cube with two players creates one initial
accepted pairing; Commander Cube creates one or two balanced accepted groups
as described above. Each participating client enters its assigned
room using the existing authenticated match-entry command. No opponent choice,
invitation, acceptance, or extra entry click is required. The submitted decks
are installed and locked; players must still ready up individually. Spectators
and players sitting out are not entered. An offline player's place is preserved
until they reconnect, rather than silently excluding them from the table.
The same transition applies when a player sits out and all remaining active
players have submitted. It happens only once, on completion of construction;
leaving a table must not automatically pull the player back or create a rematch.
An explicit pod departure cancels an initial assignment whose table has not
opened, while retaining the guest's draft seat, pool, and submitted deck;
transport disconnection does not cancel that assignment.

An owner-only `autoEnter` flag on the initial pairing remains set until that
player successfully enters. Failed entry retains an explicit retry action,
without a repeated automatic-request loop. Clients wait for the corresponding
authoritative private deck snapshot before entering. If the player has edited
after submitting, the existing explicit discard confirmation protects those
edits; automatic entry never silently discards them.

Regular Cube groups larger than two players, and subsequent free-play matches,
retain invitations. Players invite an available opponent themselves. The
opponent must accept before either can open their table; the inviter may
withdraw and the invitee may decline. Either player can cancel an accepted
pairing before its table opens. No participant or host may arrange a match
between two other players. There are no Swiss rounds, standings, result
reports, or automatically assigned opponents across multiple tables. Each table uses the configured
BO1/BO3 match in the event's immutable `rulesMode` (`manual` or `forge`)
and automatically installs the submitted decks.
Invitations and accepted pairings reserve both players and lock their submitted
decks. Multiple disjoint tables are allowed.
In regular two-player Cube, either player's explicit table departure closes
that table, removes the casual pairing, and makes both players available again,
including for a new opponent.
Closing one table never releases players from another. Ordinary spectators may
watch opened tables but never receive private draft packs or original pools.
Spectator departure does not close a table, and network disconnection retains
the existing reconnect window. The result popup's **Return to room** action
returns Cube players directly to the draft pod, not to a reset two-player table.

Subsequent Commander Cube invitations contain the inviter plus one to three available
players (two to four total). Creating an invitation records only the inviter's
consent; every other named participant must accept personally. A viewer,
another group, or a stale credential holder cannot accept for them. Pending
invitations reserve every named player and prevent simultaneous invitations
or deck changes. Any invited player may cancel/decline an unopened group,
including after all have accepted; a disconnect releases unopened groups.
The public table list shows all names and accepted participant IDs.

The initial Commander table admits the entire active group automatically;
subsequent invited tables require unanimous consent and explicit entry.
The server installs their pool-contained deck with `format: edh`,
`deckFormat: commander_limited`, and BO1. All invited seats must be occupied and
ready; the ordinary EDH three-player minimum cannot start a four-person group
early. Games begin at 40 life and expose the existing command-zone, per-card
commander tax, commander damage, and elimination controls. Ordinary
`room.create` and local `deck.select` cannot manufacture or replace this
server-owned Limited table/deck.

A player's explicit departure from an active Commander table eliminates that
player and preserves the remaining game. If the departing player hosted the
table, ownership transfers to a remaining seat. Reopening that same pairing
after departure joins as a spectator; it never recreates a seat, deck, or
library. A transport disconnect instead preserves the existing reconnect hold.
After a completed game, returning from the table closes it, clears its group
reservation, and allows those players to edit decks or invite another group.
Departing spectators never close an active table. Explicitly closing the entire
Cube room as its host still closes every child table, including active games.

Free-play Cube rooms appear in **Rooms**, never in active or historical Events.
Swiss Cube tournaments remain in **Events**. The shared internal session
supports regular Cube draft pods of up to eight participants and Commander Cube
pods of two to eight; regular Cube tables have two seats and Commander Cube
tables have two to four. A known room credential restores its
participant when joining by room code again; spectator entry never uses that
credential. Leaving a free-play room before drafting frees a guest's seat;
after drafting starts it preserves the participant and private pool for reentry.
Explicit host departure closes the pod and its tables, notifies and detaches
remaining members, and immediately releases its session capacity and room code;
closed pods are not retained as event history. Disconnection preserves the
reconnect opportunity. Ordinary spectators never occupy draft seats or receive
pack/pool identities. A public session reentry without a credential does not
register a player; new players must explicitly join through the room entry.
The source Cube is never loaded as a player's entire game deck. The standard
client does not add casual Set Sealed or Set Draft creation.

Participants may update their pool-contained deck while they are not inside an
active pairing. Opening a pairing locks that submitted version for the match.
For BO3, every unselected pool card remains available through the existing
between-game sideboard workflow. That workflow also exposes the five ordinary
basic lands as an unlimited virtual supply: players may add them to or remove
them from the pending main deck without moving a physical pool card into the
sideboard. The mainboard and sideboard remain visible together and share color,
card-type, mana-value, and rarity filters. Filtering is presentational only:
deck counts and ready validation use the complete pending partition. Remove all
mainboard cards atomically returns every physical pool copy to the sideboard
and removes unlimited basic-land additions, regardless of active filters.
Printed virtual basics retain their selected art separately from physical pool
copies, including when both use the same printing; the basic-land controls
remember that printing after clearing the mainboard. Adding a previously unused
basic-land color prefers the current product's series, followed by the sets
used by remembered basic lands and the physical pool, when available, without
replacing an existing per-name selection. The product and pool fallback also
works after reconnecting with an already empty pending mainboard. If none of
those sets supplies that basic, the client chooses a stable catalog series
shared by all five basic lands, then a stable individual printing. Only a
missing catalog printing leaves the art unspecified.
An empty mainboard cannot
be readied. Hovering
either table opens the full-size card image. Returning from a match restores
the submitted main/sideboard partition before the next edit.

At small window sizes or enlarged UI scale, sideboard filters and basic-land
controls open in a bounded, scrollable tools popup. Both card tables and the
Ready action remain accessible, and closing the tools preserves filter choices
and the pending deck partition.

The pairing room installs that locked deck automatically. It does not ask the
participant to select a saved local deck. The five unlimited ordinary basic
lands are virtual pool additions and therefore may omit a printing identity;
all physical pool cards and every other basic land retain their exact set and
collector number. A printed virtual addition sets `DeckCard.virtualBasic` to
`true` so its supply identity stays distinct from a physical pool copy with the
same printing. Omitted printing identities remain supported for existing decks;
the marker does not authorize nonbasic additions.

## Construction and privacy

Every generated physical card has a unique `instanceId` independent of its
printing identity. A deck submission names exact pool instance IDs plus
ordinary basic-land counts, with the Commander Cube Piper and optional-staple exceptions described
above. The server rejects duplicate IDs, foreign instances, arbitrary non-pool
additions, and a main deck below the profile's minimum:
40 cards for Set Sealed/Set Draft/regular Cube or 60 including commanders for
Commander Cube.

Submissions also obey the table's transport limits: at most 1,000 cards and
500 entries across the main deck and sideboard combined. Added basic lands
and selected fallback Pipers and optional staples count toward that total alongside the complete
physical pool. Optional basic land printing identities must provide both set and collector number within
the ordinary identity bounds. A rejected replacement preserves the previously
submitted deck and its private construction state.

Deck construction presents the selected main deck and the unselected
sideboard/available pool as two persistent visible areas. Activating a card
moves that exact physical instance between them immediately. Both areas keep
their current scroll positions across moves, clamped to the remaining content
when a list becomes shorter. This visual model
does not change containment authority: the server validates the submitted ids,
and unselected pool instances remain the sideboard.

Before the first deck submission, construction is saved automatically in the
local client profile, scoped to the server endpoint, event ID, and participant
ID. Leaving the event view or restarting the client restores selected physical instances, ordinary
basic-land counts and chosen printings, the initial draft-pool choice, and
whether the Sealed reveal has already been shown. Restoration intersects
saved IDs and commander selections with the server's current private pool and
its separate eligible Piper candidates; it never adds foreign cards
or changes the server's submitted deck. An acknowledged submission takes
precedence and removes the obsolete local draft.

Local drafts use a separate, versioned `limited-deck-drafts.json` file with
atomic, coalesced writes. At most 32 recently edited drafts are retained for
seven days. Storage failures display a warning; in-memory editing remains
available, but restarting cannot be promised to preserve unsaved changes.
Unreadable or newer-schema files are not overwritten. This is device-local
recovery, not cloud synchronization or a substitute for submitting the deck.

The available pool has display-only organization by mana value, color,
card type, or name without changing selection or server state. It also has
independent color, type, mana-value, and rarity filters whose intersection is
shown immediately. Every gallery tile displays its rarity, and hovering either
region opens a full-size card image without changing the selection.
Mana, color, and rarity metadata comes from the installed exact-printing
catalog; cards missing local metadata remain usable in the unfiltered view.
The available pool owns the larger left-hand gallery, while the main deck
remains visible as a compact right-hand list with copy counts, a mana-value
summary, and land/nonland counts. Display rows aggregate exact printings only.
the main list retains its own search/color toolbar and advanced filters during
construction and later deck edits. Pool and main-deck filters are independent;
neither changes the complete deck's counts, mana plan, or submitted card IDs.
Activating a row removes one physical instance. Virtual basics remain distinct
from physical pool cards. The five unlimited ordinary basic-land controls open
in a scrollable popup; basic lands and submit/update actions remain pinned
outside the card scroller. See `ui-card-workbench.md`.
The popup closes when its builder or an ancestor becomes hidden, including
when a table invitation replaces the editing workspace. Reopening the builder
preserves its deck and basic-land edits without reopening a stale modal.
Commander Cube's three optional outside cards share that popup, leaving the
available-pool gallery free of permanently expanded addition controls.

Narrow windows use pool/main-deck tabs instead of vertically stacking two
scrolling card panes. The active pane fills the workspace; tapping a card moves
it between pool and main deck. Commander/basic-land controls and submission
remain reachable at 900×620 with 135% interface scale. During free-play deck
editing, opponent navigation remains in the page header and a compact warning
marks unsubmitted edits without reducing the main-deck list to zero height.

The five ordinary basic-land controls show the selected printing and open a
printing picker with art preview. New construction prefers printings from the
event product's set. When a basic is unavailable in that set, it prefers a
single installed set containing all five basics; if none exists, it uses an
available printing of that basic. Without a matching local printing, an
unspecified printing remains usable. Changing a printing leaves its count and
automatic quantity mode unchanged. Local drafts and acknowledged submissions
preserve selected printing identities, and a printing-only edit requires an
updated submission. Physical pool cards retain their original printing.

New Sealed, Set Draft, and Cube construction defaults to automatic ordinary
basic lands. Selected physical cards remain untouched, including selected
lands; the client suggests enough virtual basics to reach 40 total cards, or
60 including the selected commanders in Commander Cube.
Distribution follows the selected nonland cards' colored mana symbols, with
hybrid alternatives sharing a pip and Phyrexian life symbols adding no color.
Missing costs fall back to actual card colors, never Commander identity.
Known colored sources from selected lands offset demand before allocating new
basics. Flexible sources count as one shared source, not one whole land of each
color. Existing basic-land types and unambiguous literal tap-for-mana rules are
recognized; unresolved, conditional, filter and fetch sources are not guessed
from Commander identity. Unresolved sources are reported in the basic-land
popup. Stable WUBRG tie order produces an integer allocation. Front-face lands
count as lands; spell/land MDFCs remain spells in this conservative heuristic.
Type recognition supports saved English and Chinese Cube metadata, including
Chinese subtype separators. Subtype words such as Goblin (`地精`) do not turn
creatures into lands. Localized basic-land subtypes supply the same known mana
sources as their English equivalents.
An empty/colorless/unknown selection does not invent land colors and presents
manual guidance instead. Reaching the profile's minimum with selected physical cards requires no
virtual additions. This is a convenience suggestion, not mana-base validation.
A deck at or above its target with fewer lands than one third of its total
cards gets a nonblocking warning on the basic-land control and in its popup.
It remains submittable. The heuristic is not a format legality requirement or
a promise that the mana base will support every spell.
Manual basic-land changes switch automatic mode off; the basic-land popup can
re-enable it. Local construction drafts preserve the mode. Older drafts and
submitted decks restore in manual mode so an existing mana base is not silently
rewritten. Display filtering never changes the calculation.

- A participant receives only that participant's current pack queues and full
  pool.
- Other participants, organizers, and spectators receive only public progress:
  stage, pack round, pick count, cards remaining, and deck-ready state.
- Organizers have no extra access to another participant's private identities.
- Spectator hand visibility never grants Limited pack or pool access.
- Logs and acknowledgements do not name private picks or opened cards.
- Completed tournament decklists follow the existing publication policy. Full
  original pools remain private. After publication, any viewer can browse the
  recorded list as grouped card art and export a local importable copy.

Each projection is authorized against the event ID, current session membership
generation, and the participant's current connection, both when it is built
and immediately before it is queued. Switching events, re-entering as a viewer,
or transferring a credential cannot reuse an earlier private projection.

Entry, recovery, and non-pick changes send full snapshots. During a draft pick,
seats with changed private state still receive full `limited.snapshot` messages;
unaffected recipients receive `limited.progress`, containing only the event ID
and public participant progress. A stage transition also sends the full event
snapshot. Progress never clears or replaces private cards. Clients ignore
snapshots for events they have left, notify card-list changes only when those
lists change, and do not repeat art/metadata work in hidden workspaces or dismiss
a preview for an unrelated participant update. No compression-policy change or
client-owned pick timer is implied.

Departure, disconnect, and cross-event switching explicitly refresh the old
event's public presence. Its operation lock orders projections with picks, so
a delayed leave broadcast cannot replace a newer private pool. Event switches
release the new event's operation lock before refreshing the previous one.

## Protocol and implementation migration

The corrected wire model uses a discriminated mode instead of the old four-way
Cube matrix:

| Mode | Wire value | Mode-specific configuration |
|------|------------|-----------------------------|
| Set Sealed | `set_sealed` | locked set product; six packs inferred |
| Set Draft | `set_draft` | locked set product; three packs and a configurable 2–8 seat cap |
| Cube Draft | `cube_draft` | locked Cube snapshot; configurable 2–8 seat cap and 3 × 15 cards per active player |
| Commander Cube | `commander_cube` | locked Cube and draft settings; 2–8 draft seats, 10–40 cards per pack (default 20), atomic two-per-pack selection, 60-card construction, `casual` only |

Set modes and regular Cube retain fixed pack counts. Commander Cube creation
accepts only the bounded `draftSettings` profile above, exposed in public
`tournament.snapshot` before ready-up. Set Draft, regular Cube, and Commander
Cube accept a 2–8 seat cap; Set Sealed accepts 2–64. The obsolete `sealed`, `draft`, `cube_sealed`,
and `cube_pool` creation values are absent from the current protocol. Wire
changes follow the [protocol compatibility policy](protocol-compatibility.md);
admission compares game-protocol identifiers rather than application versions.

Commander mode extends existing payloads: `limited.pick.instanceIds` is the
multi-card alternative to `instanceId`; callers must not send both.
`limited.submit_deck.commanderInstanceIds` selects drafted main-deck instances
or allowed Piper candidates. Private `limited.snapshot` messages restore that
selection and publish `picksRequired`, `packsPerPlayer`, and `minimumDeckCards`
as profile metadata. `currentPack` remains the flattened current selection;
owner-private `currentPacks` identifies its one or two independent packs, cards,
and per-pack quotas. `picksRequired` is the combined quota. `packRound` counts
physical packs opened per seat through the current batch, while `packsThisBatch`
identifies its size (for example, 2/2, 4/2, 5/1 for five paired packs).
Only the current owner receives `optionalCards`, `currentPacks`, and pool/deck
identities; other seats and viewers retain public progress only.
Group invitations use `limited.create_casual_match` with
`action: invite` and `playerIds`; `accept`/`cancel` identify an existing
`pairingId` without replacing its membership. Public pairing projections add
`playerIds`, `playerNames`, and `acceptedPlayerIds`. The optional pairing
`autoEnter` boolean is true only for the current owner awaiting initial table
entry, never for public viewers or another participant. The ordinary Cube A/B
invitation and single-card-pick payloads retain their existing semantics.
Snapshots are replacements, not patches: omitted private optional fields must
be cleared when applying a new role-specific snapshot.

The installed catalog needs a set-level Limited index over its product
manifests. On first load, `DeckLibraryModel` imports each legacy `cubes.json`
entry as a Cube-format deck in `decks.json`, then archives the source file.
Migration preserves card lists and quantities but stops presenting the old
configurable pool size. A legacy Cube containing the old synthetic `CUBE`
printing marker, or fewer than 90 physical cards, remains visible and editable
  but cannot create a tournament until it is corrected. No generated online state is
migrated because tournaments and rooms are in-memory server sessions.

## Module boundaries

- `limited` owns product/Cube validation, server random generation, physical
  instances, Set Draft queues, pool-contained deck construction, and private
  projections. It does not own pairings, standings, or tabletop state.
- The event coordinator hosts Swiss Limited events and free-play Cube rooms;
  neither may copy private pack/pool state or reimplement its reducers.
- `LimitedSessionState` owns the typed client projection and reconnectable
  private state.
- `DeckLibraryModel` owns both constructed decks and Cube-format pool
  definitions. Cube-specific readiness and product projection live in its
  query layer rather than a second persistence model.
- Limited QML screens render typed state and emit commands. They never generate
  online cards, pass packs, validate pool ownership, or pair players.
- Visible pack and pool cards are prioritized through the existing art cache;
  missing art never blocks a pick or deck submission.

## Required verification

Coverage must include fixed six-pack Sealed, two-to-eight-seat Set
Draft, configurable two-to-eight-seat Cube Draft, left/right/left passing,
asynchronous queues, reconnect projections, set-manifest labelling, Cube
no-replacement packs, Cube capacity rejection,
instance ownership, five unlimited ordinary basics, pool-contained deck edits,
free-play pairing isolation and repeat matches, Swiss handoff, organizer/spectator redaction,
protocol fixtures, typed client state, QML flows, and removal of every obsolete
Cube-sealed/Cube-draft creation label.

Commander coverage additionally includes every 3/4/5/6/8-pack profile, paired
per-pack quotas and odd final batches, automatic picks, physical stock and pool
conservation, 60-card construction including exact commander printings,
duplicate-card pools, own-pool and commander containment, optional staple
ownership and opt-in persistence, balanced initial tables for up to eight draft
players, subsequent unanimous group
invitations, all-seat ready gating, 40 life and
EDH controls, elimination and host transfer on active departure, spectator-only
return after forfeiture, credential/transport recovery, and a subsequent game.
A real four-client WebSocket lifecycle must exercise the entire path, not only
domain reducers or fabricated final table snapshots.

## Design references

- Wizards' MTG Arena formats overview defines six-pack Sealed and the
  eight-player, three-pack, left/right/left Draft flow:
  <https://magic.wizards.com/en/news/mtg-arena/mtg-arena-formats>
- Wizards' format pages define the 40-card construction baseline:
  <https://magic.wizards.com/en/formats/sealed-deck> and
  <https://magic.wizards.com/en/formats/booster-draft>.
- Play Boosters are used for Arena Limited from Murders at Karlov Manor onward,
  with Arena-specific substitutions possible:
  <https://magic.wizards.com/en/news/mtg-arena/play-boosters-on-mtg-arena>.
- Wizards describes Arena Cube as a phantom player draft. Hexproof follows the
  same three-pack pick/pass shape while allowing smaller private pods and using
  the room owner's saved Cube:
  <https://magic.wizards.com/en/news/mtg-arena/arena-cube-draft>.

## Rules-enforced one-on-one matches

Set Sealed, Set Draft and regular Cube support immutable `rulesMode: manual |
forge`, selected at creation and displayed in discovery and event summaries.
Omission preserves manual behavior. Forge matches always use server hosting;
creation, event start and new table creation reject unavailable Forge instead
of falling back. A launch backoff does not block entry into an existing table.
Commander Cube remains manual. Drafting and pool construction
continue to belong to the Limited event reducer, independently of match rules.

Set Sealed, Set Draft, and regular Cube creators may also enable the optional
25-minute action clock for each two-player Forge match. It defaults to off,
applies across the whole BO3 match, and is inherited by every pairing room.
See [action-clock rules](action-clock.md) for pauses and timeout results.

Every paired Forge table installs the exact submitted 40-or-more-card main deck
and its unused pool as the sideboard. Forge runs its native Limited deck format
(the Sealed game type, shared by all three one-on-one products), including its
40-card minimum and access to outside-the-game cards from that sideboard. No
constructed four-copy restriction or 15-card sideboard cap applies. BO3 preserves
pool printing ownership and permits ordinary virtual basic-land changes using
the existing Limited sideboard flow. Each game starts a fresh native game with
the confirmed deck partition.
Private packs, pools and deck choices remain hidden from other participants and
spectators; choosing Forge does not broaden projections or room admission.

In manual Set Sealed and Set Draft games, the token picker initially limits
search to the event product set and its token set. Players can turn off this
filter to search the full catalog, including unusual tokens and emblems.
The database applies the set filter before deduplicating and limiting results.


## Official-account recovery

Optional [official accounts](accounts.md) own the existing participant ID, not
a copy of the draft. Explicit recovery on the original hub restores the same
current pack, picked pool and submitted deck, with normal role projections.
Login does not reverse seat release, withdrawal, forfeiture or expiry, and
explicit spectator entry does not bind the account to a private draft view.
Unsubmitted construction edits remain local to the existing draft store.
