# Manual smoke scenarios

Use the scenarios relevant to the changed behavior. These are manual actions
and expected results, not a required full sweep for every fix. Verification
selection and process cleanup follow [the development policy](development-policy.md).
The [specification map](implementation-plan.md) identifies behavior authority;
this checklist does not replace those specifications or the protocol schema.

## Prerequisites

Keep client windows maximized on the test display for the primary smoke run,
including multi-client steps. Switch between seats without resizing them.
Run any requested minimum-size, scaling or fullscreen checks separately and
record their window state and display dimensions.

Build both binaries (from repo root):

```sh
# Server
mkdir -p build/server
(cd apps/server && CGO_ENABLED=0 go build -o ../../build/server/hexproof-server ./cmd/hexproof-server)

# Client
cmake -S apps/client-qt -B build/client-qt -G Ninja
cmake --build build/client-qt
```

## 1. Start the hub

```sh
./build/server/hexproof-server -bind 127.0.0.1 -port 57320
```

Expected ready line:

```
hexproof-server <application-version> listening on 127.0.0.1:57320 (ws path /ws, protocol hexproof.v2)
```

Use the actual binary version in the log. Client and hub must share the game
protocol; application version numbers need not match. Skip the hub and two-client
steps for offline deck-library checks.

## 2. Start two isolated clients

On Linux, use the maintained launcher instead of starting two processes against
the same default profile:

```sh
./tools/run-multiclient.sh start --count 2 --no-template \
  --profiles-root build/multiclient/manual-smoke
```

The clients use separate settings, data and resume credentials, open maximized,
and prefill **Custom server** with `ws://127.0.0.1:57320/ws`. Import the test decks
and catalog into those profiles as needed. Alternatively supply an explicitly
prepared test `--template`; do not use personal decks or credentials as fixtures.
Use a fresh profile root for a new independent run. For larger Draft, Cube or
tournament groups, see [multi-client testing](multi-client-testing.md).

After the scenario, stop only this group's clients:

```sh
./tools/run-multiclient.sh stop --profiles-root build/multiclient/manual-smoke
```

The launcher does not own the separately started hub; stop that test process in
its original terminal. Other platforms need equivalent isolated test profiles.

## 3. Connect both

In each client window:
- Main menu -> **Connect to server**.
- Server: **Custom server**, `ws://127.0.0.1:57320/ws`.
- Display name: `Alice` (client A), `Bob` (client B).
- Click **Connect** and verify the connected name/status.

If the name is empty, the server rejects with `name_required`.

## 4. Create a room (client A)

- Client A: **Create room**
  - Room name: `Friday EDH`
  - Format: `edh (4 seats)`
  - Allow spectators: on
  - Series: `BO1` (Commander disables BO3)
  - Password: leave empty
  - Click **Create** -> enters **Waiting room**.
- The waiting room shows the **Room id** (6 chars, e.g. `K7P2QX`). Note it.

Client A is host (derived from create, not the name).

## 5. Join the room (client B)

- Client B: **Join room**
  - Room id: the id from step 4
  - Role: `Player`
  - Password: empty
  - Click **Join** -> enters **Waiting room**, seated in seat 1.

Both clients now see seat 0 = Alice (host) and seat 1 = Bob occupied. The room
id is identical on both.

## 6. Negative cases

- **Wrong password**: create a password-protected room with A; B joins with the
  wrong password -> error `wrong_password`, B stays on the join form.
- **Spectator cap**: join as spectator 8 times (8 extra clients); the 9th
  spectator gets `spectator_limit`.
- **Seats full**: Modern room (2 seats) with A + B seated; a 3rd player gets
  `room_full`.
- **Create while in room**: A clicks Create again while in the room ->
  `already_in_room`.

## 7. Kick (host)

- In A's waiting room, seat 1 (Bob) has a **Kick** button.
- Click it -> Bob is removed:
  - A receives `room.kicked` (echo id) + a snapshot with seat 1 empty.
  - B receives a server-push `room.kicked` (no echo id) and is returned to the
    main menu with a "You were kicked" banner. B is still connected to the hub.
- Kicking the host seat is rejected (`cannot_kick_host`); the host leaves via
  **Leave** or **Disband room**.

## 8. Leave / Disband

- **Non-host leave**: B (player) clicks **Leave** -> B gets `room.left` + a
  snapshot is broadcast; A sees seat 1 empty. B returns to main menu, still
  connected.
- **Host leave = disband**: A clicks **Leave** or **Disband room** -> A gets
  `room.disbanded` (echo id); B gets `room.disbanded` (broadcast, no echo id)
  and is returned to the main menu. The room is gone.

## 9. Disconnect

- **Leave room** sends `room.leave` and frees the seat immediately.
- An unexpected network drop holds the seat for the P6 reconnect window; see
  section 25.

## 10. Offline deck library

Start one client with no hub running, then:

- Open **Deck library** -> **Import deck**.
- Name it `Burn`, choose **Modern**, and paste:

  ```text
  Deck
  4 Lightning Bolt
  4 Monastery Swiftspear

  Sideboard
  2 Smash to Smithereens

  Commander
  ```

- Import and confirm `8 main · 2 side`. Art must **not** start downloading for
  the whole list. Open the editor: Lightning Bolt and Monastery Swiftspear must
  already sit under Spells / Creatures from the local catalog, not **Other**.
  Use **Cache art** when the printings look right; adding a card or changing a
  printing still fetches that one image immediately.
- **Export** the deck, copy the list, and confirm it contains `Deck`, `Sideboard`, and `Commander` headings. Save a `.txt` file and re-import or reopen it to confirm the same counts.
- Open the editor. Move one Lightning Bolt to the sideboard using both the button and drag handle; counts must update and survive an app restart.
- Confirm the editor still permits manual copy-count changes. For a named
  format, wait for the legality result and confirm an ordinary fifth copy is
  reported while basic lands remain exempt. A catalog-verified illegal deck
  must not be selectable for a room using that named format; a Custom 1v1 deck
  remains usable for deliberate variants.
- Open **Settings**, keep the interface in English and choose **Chinese cards**.
  Confirm menus stay English while art prefers Scryfall Simplified Chinese,
  including another printing of the same card when necessary, before MTGCH and
  English fallbacks. Then switch only the interface to **简体中文** and confirm
  card language remains unchanged.
- Without a bulk metadata package, the search panel stays visible and links to database settings.
- Download **Default Cards**. Confirm the manifest-verified official package
  installs and already contains the current MTGCH Chinese name index. Return to
  the editor, search both `Lightning Bolt` and `闪电击`, and confirm both resolve
  to the same canonical result. Try a fuzzy query such as `Lghtnng` and filters
  for red, common, and Modern-legal cards.
- Search a heavily reprinted card such as `Lightning Bolt`: the result list
  must show one card-name result with a printing count. Add it, click the
  set/collector label or the card thumbnail on its deck row, and choose a
  different printing. The picker must show a loading state, then the cached
  art for that version, without first claiming the version has no image.
  Cards without a set still expose **Select printing**.
- Import an EDH deck without a commander marker: its status must remain `Commander required` until a main-deck card is designated as commander and all art is cached.
- Import an EDH plain-text list whose commander follows the main deck after a
  blank line. Confirm that card becomes the commander, stays in its type group
  with a Commander mark, the editor has no sideboard column, and no sideboard
  add/move action is available.
- In the EDH editor, use the deck-local search field and confirm it filters only
  cards already in that deck without changing the catalog search query.

## 11. Select decks, load, and start

- Create a **Modern** room and join it as a player from the second client so
  both seats are filled. Each client needs a local Modern deck whose status is
  `Ready`.
- On each waiting-room screen, click **Select deck**. The picker lists only
  Modern decks; decks with missing art or metadata remain visible but cannot be
  selected. A complete local deck is labeled `Playable`; this is deck
  availability, not the player's room-ready state.
- Select one playable deck on A. Both clients must show A as `Deck selected, not
  ready`, but only A shows its local deck name on the selection button.
- Create the room with **Preload before game**. Click **Ready** on A, then on B.
  Both clients automatically enter the loading screen and prefetch the
  aggregate card-printing set for the match. Each seat shows its public loaded
  state.
- When both seated players finish, both clients automatically enter the
  battlefield-first table shell with no Start button. A spectator may prefetch
  the same assets but cannot delay this transition.
- Each player sees their own seven card identities/art in the hand strip. The
  opponent and spectators see only `handCount: 7`; their projected seat has no
  `hand` identities. Library order is absent from every live projection.
- Click the owning player's library once. Their hand grows by one, library
  count drops by one, and the public log says only that the player drew a card.
- Right-click empty space in the hand area and choose **Mulligan**. The hand
  returns to the library, the server shuffles, the owner receives seven
  identities, and every client sees the public mulligan count increase and the
  public log entry.
  Repeat once and confirm the count becomes 2. The opening-roll winner is also
  present in the log.
- With at least three cards in hand, use **Discard a random card** and confirm
  exactly one server-selected card becomes public in the owner's graveyard,
  while opponents still see only the remaining hand count. Then use **Discard
  entire hand…**, confirm the warning, and verify every remaining card moves in
  one snapshot with one count-only acknowledgement and a public log entry.
- Repeat with the same resolved printings. Name-only cache entries created
  during deck import must be reused for their resolved set/collector identity;
  the loading gate may flash briefly but must not redownload metadata or art.
- If a download fails, the affected client remains on the loading screen and
  can retry failed cards. It must not report load completion until all cards
  succeed.
- Repeat with **Load in background**. Both clients must enter the table as soon
  as all players are Ready; visible hand/public-zone cards should appear first
  while the remaining match art continues downloading without a loading page.
- Change A's selected deck. Both clients must immediately show A as not ready.
- Join as a spectator in a third client. Waiting-room snapshots expose only
  each seat's `deckSelected`/`ready` state. During prefetch the spectator also
  receives the aggregate printing-key set, but never its seat ownership,
  quantities, sideboard grouping, or future library/hand order.
- Negative cases: a player cannot become ready before the format minimum is
  seated (`seats_not_filled`) or without selecting a deck (`deck_required`),
  and a spectator cannot select a deck or ready (`not_player`). The minimum is
  three for EDH and the full seat count for one- and two-player modes.

## 12. Move a card onto the battlefield

- In client A, drag a land, several creatures, an enchantment, an artifact, a
  planeswalker, and an instant or sorcery from the hand strip into the
  battlefield. Their release points do not determine initial placement: the
  land is flush with the near edge, creatures expand from the horizontal center
  of the middle band toward both sides, the three noncreature-permanent groups
  occupy separate far clusters, and the instant/sorcery uses the staging row.
  Existing cards do not move when the next card enters.
- Move a multi-face card whose front is a creature and back is a planeswalker,
  choosing the back face. Confirm it uses the other-permanent band rather than
  the creature band.
- Each client shows top-row land bands against the top edge and bottom-row land
  bands against the bottom edge. In four-player EDH this applies equally to the
  two upper and two lower battlefields, so the lower-right player's lands are
  not flipped merely because that player is an opponent. Horizontal order and
  card art remain upright, and no card overlaps another seat's battlefield.
- Move a card from B's hand as well. Both clients show both public cards in
  separate labeled lanes while B's snapshot still omits every identity
  remaining in A's hand.
- The shared log names the card and records `hand` to `battlefield`.
- A spectator applies the same row-based transform: both upper land bands are
  at the top and both lower land bands are at the bottom. It still receives no
  private hand identities, and its lanes remain in stable seat order.
- Double-click the permanent. It rotates smoothly to the tapped orientation on
  both clients; double-click again to untap it.
- Drag A's permanent, A's graveyard top, and A's library top into B's
  battlefield lane. A battlefield-to-battlefield drag keeps the chosen
  position; newly entering visible cards use B's assisted type band and retain
  `ownerSeat = A` while B becomes the battlefield controller. No other library identity is
  disclosed. B can tap or return a controlled permanent; hidden destinations
  go back to its owner.
- Releasing outside a supported zone does not send a move. A client still
  cannot inspect or originate a move from another seat's hand or library.
- As the active player, right-click a hand card and choose **Play land…**.
  Confirm a multi-face card can choose its battlefield face and that Continue
  atomically removes it from hand, places it in the assisted battlefield slot,
  and changes **Land · 0** to **Land · 1** on every client and spectator.
- Repeat with the stack non-empty, outside a main phase, after one recorded
  play, and with a face not identified as a Land. Each condition appears in
  the confirmation without disabling Continue. Cancel changes neither the
  card nor count.
- Drag another hand card onto the battlefield normally and confirm the count
  does not change. Correct the count with `−`/`+`; only the active player may
  do so. Advance the phase and confirm the count remains, then advance the
  turn and confirm it resets to zero.

## 13. Coordinate phases and advance the turn

- Confirm both clients render the same compact 11-step bar above the
  battlefield, the opening-roll winner's lane is highlighted, and that player
  sees **Your turn** while every other viewer sees **Current turn**.
- On the active client, select **Attackers**, then use **Next phase**. Confirm
  both clients show Blockers and the public log records both changes. Repeat
  with **Ctrl+Right** while chat and dialogs are unfocused.
- Confirm phase controls are disabled on the inactive client and spectator.
  A direct inactive command remains rejected with `not_active_player`.
- In Attackers, select two controlled permanents, right-click either selection,
  use the direct **Attack &lt;player&gt;** action. In the declaration dialog, leave
  one attacker's **Tap** selected and clear it on the other. Confirm both clients and a
  spectator show the defending player's name on both attacker badges, with no
  player-target attack arrow, only the selected attacker is tapped, and that
  the public log records the batch declaration. Clear the declarations, choose **Attack a battlefield
  permanent…**, and click an opposing permanent; confirm the solid red arrows
  end at that card.
- Advance to Blockers on the active client. On the defender, select one or more
  controlled permanents, choose **Block an attacker…**, and click one of the
  incoming attackers aimed at the player or their permanent. Confirm dashed
  gold block arrows coexist with player-target badges or permanent-target
  attack arrows. Clear one selected declaration and confirm unrelated relations
  remain.
- Advance through Damage and End Combat; all combat markers and arrows remain visible.
  Advance to Main 2 and confirm they clear. Invalid phase, non-controller, and
  block-against-an-unrelated-card requests remain rejected.
- On either player, choose **No response** and confirm every viewer shows that
  player's Passed badge and localized public log. Perform another public action
  and confirm Passed clears. Set **Please wait**, perform an action and confirm
  it remains, then advance the phase; the badge must reset.
- In Untap, confirm the contextual helper untaps controlled tapped permanents
  only when clicked. In Draw, **Draw 1** draws exactly one only when clicked. In
  Attackers, declare attackers and use **Tap attackers**; only untapped declared
  sources are tapped. These helpers do not run merely by changing phases.
- Select **End turn** or press **Ctrl+Enter**. Confirm the active lane changes,
  the step resets to Untap, and no card is automatically untapped or drawn.
- Put one card in the shared stack or set another player to **Please wait**,
  then attempt to advance. Confirm the advisory dialog appears and that both
  Cancel and Continue preserve the expected server state. End a turn with
  eight cards in hand and confirm the same advisory path.
- Set life to 0, empty the library, and hold eight cards. Confirm each affected
  count is visually highlighted without an automatic result or rejected manual
  action.
- In Duel Commander or EDH, open the own command-zone browser and choose
  **Cast commander**. Confirm the card moves to the shared stack and only that
  commander's tax advances. Return it manually, then drag it to another zone;
  confirm a manual move does not advance tax.

## 14. Use the shared card tray

- Drag one card from A's hand into the narrow shared tray. Both clients show
  the same portrait card and A as owner; A's public hand count drops by one.
- On B, confirm A's shared card is readable and drives the large hover image,
  but cannot be dragged or resolved. A can select it and use the compact
  battlefield, graveyard, or hand actions. Dragging it onto the battlefield
  preserves the chosen normalized drop position.
- On A, use the eye action to reveal the hand. Every remaining hand card moves
  atomically into the same continuous portrait tray and is visible on B and a
  spectator; there is no separate labeled reveal half.
- Select one of A's revealed cards and click **Back to hand**, then repeat by
  dragging another card into A's hand panel. Those cards disappear from future
  public reveal projections and return to A's private hand; B still receives
  only A's updated hand count.
- Reveal multiple A cards again. Confirm the action-rail button reads
  **Recall hand**, then click it and confirm every A-owned reveal card returns
  atomically while cards revealed by other seats remain public.

## 15. Search the private library

- In client A, right-click A's card-back library tile. A large modal lists A's
  complete remaining library with bilingual name/type filtering, card art,
  multi-selection, a destination selector, and a reveal-log toggle.
- Click a card outside its checkbox and confirm the large preview changes
  immediately without changing selection. Click only its checkbox to toggle
  selection. Right-click it and confirm only the library destination menu
  opens; neither the battlefield card menu nor the Token/Concede background
  menu may appear underneath or replace it.
- Confirm client B and a spectator receive no `game.zone_dumped` event and no
  library identities. Their normal snapshots continue to carry only A's
  `libraryCount`.
- Select a card, choose **Hand**, turn off **Reveal card name in the game
  log**, and complete the search. A receives the card identity in hand; B and
  the spectator see only the updated hand/library counts. The shared log says
  `a card` and does not contain the selected name.
- Repeat with reveal enabled and choose **Graveyard** or **Exile**. The shared
  log names the selected card and every viewer sees its public-zone identity.
- Exercise **Battlefield**, **Top of library**, and **Bottom of library**.
  Battlefield placement starts at the center of A's own lane; top/bottom
  reorder the private library without exposing its order.
- Select multiple cards and right-click. Confirm hand and battlefield remain
  available, battlefield accepts the full selection, and library top/bottom
  retain ordered/random actions. Graveyard and exile must each appear exactly
  once, without ordered/random variants. Confirm each operation is atomic and
  the public acknowledgement identifies only the count unless reveal is
  enabled.
- Reopen the library menu and view the top 5 cards. Reorder that private prefix,
  return it, reopen top 5, and confirm the custom order. The public log exposes
  only that five cards were viewed/reordered.
- Reopen the library menu and choose **View top card**. Right-click the displayed
  card and exercise hand, battlefield, graveyard, exile, source-library-top,
  and source-library-bottom destinations. Confirm the ordinary top/bottom
  actions support Scry 1 while the redundant random-order variants remain
  hidden in this focused view.
- On client B, open A's floating zone panel and right-click A's library. Confirm
  the menu offers **Search library**, **View top card**, and **View top X
  cards**. Exercise each action: A must receive an approval request, denial
  reveals nothing, and approval sends only the requested full library or top
  prefix to B. Left-clicking A's library must not send a request. In the remote
  top-X view, assign at least two cards face down onto B's battlefield, one to
  A's exile, and one to A's library bottom. Confirm B can inspect the
  battlefield identities, while A and a spectator see only card backs even
  though A owns the cards. Confirm the public log names only the viewed count
  and destination-group count without naming any card.
- Canceling the modal performs no move and clears the private list from the
  closed UI. A spectator or non-member command is rejected.

## 16. Browse graveyards and exile

- Move at least two distinguishable cards into each of A's graveyard and exile
  zones. Confirm both counts update in A's player dock.
- In client B, click A's **Graveyard** count. The public-zone browser should
  name A and the graveyard, list both card identities, support local filtering,
  and show the selected printing's cached art.
- Close the browser and open A's **Exile** count. Confirm the exiled cards are
  visible and that graveyard/exile both expose filtered checkboxes, **Select
  all**, and the same card destinations. As A, select multiple locally owned
  cards in each zone and move them to the library top; confirm the chosen order
  is preserved. Repeat browsing from a spectator client and from A for B's
  public zones.
- Open an empty graveyard or exile zone and confirm the browser reports that
  the zone is empty without disabling access.
- Keep a browser open while another client changes the public zone. The list
  should follow the next role-specific `game.snapshot`; no extra dump command
  or private payload is used.
- As A, open B's graveyard, right-click one card, and move it to A's
  battlefield. Confirm no card moves until B receives a modal naming A, the
  source zone, card count, and destination. Reject once and confirm the table
  remains unchanged. Repeat and approve; confirm every viewer sees the
  public-source removal and battlefield placement while the card retains B as
  its owner. Confirm the public log explicitly says the card moved from B's
  graveyard. Reusing or answering an expired request must fail.
- Let A control one card owned by B, then drag it onto A's graveyard and exile
  targets in turn. Confirm the convenient drop is accepted but the card appears
  in B's corresponding owner zone on every client. Repeat with an A-owned card
  dropped onto B's pile and confirm it still appears in A's owner zone.

## 17. Adjust life totals

- Confirm both clients initially show 20 life in Generic 1v1 or Duel Commander
  (40 in EDH). Duel Commander also shows the command zone and commander tax.
- In client A, use the minus and plus controls around A's life total. Confirm
  A and B both receive the new value and a public log entry describes the
  signed change.
- Click A's life number, enter an exact negative value, and confirm it. The
  table must preserve the negative total rather than clamping it to zero.
- Confirm A cannot edit B's life controls. A spectator sees every life total
  and log update but has no editable life controls.
- Send an unknown counter name or attempt `game.set_counter` as a spectator.
  The server should return `invalid_counter` or `not_player` respectively and
  leave every life total unchanged.

## 18. Use the seven player counters

- In Table settings, choose seven own counter slots. Confirm the dock shows
  seven public circular counters with labels initially empty and values at 0.
  Other clients render the display count published by that player.
- With two designated commanders, confirm all enabled own pips appear below
  life before scrolling, including after a mulligan and with a compact or
  enlarged interface. Scroll down to reach both commanders' tax controls;
  confirm the zone tiles retain their reserved height.
- On client A, click A's first pip once and confirm it becomes selected without
  changing its value. Left-click it twice and right-click it once. Confirm the
  final value is 1 on clients A and B and on a spectator, with each signed
  change recorded in the public log.
- With the pip selected, press `I` without changing the count.
  Rename it to `Energy`; confirm every viewer sees the new label and the
  rename appears in the public log.
- Confirm A cannot edit B's pips, while B can edit only B's own seven slots.
  A spectator can read every label and value but cannot select or change them.
- Send a delta other than +/-1, a blank/control-character label, a label over
  24 Unicode characters, or more than one of `value`/`delta`/`label`. The
  server should return `invalid_counter` without changing state.

## 19. Concede a 1v1 Modern game

- In a running Modern game, confirm only seated players see the red
  **Concede** control. Click it on client A and cancel the confirmation once;
  no command, score change, or log entry should occur.
- Click **Concede** again and confirm. Client A receives `game.conceded`, and
  both clients receive the same role-specific `game.snapshot` with
  `activeSeat: -1`, `result.reason: "concede"`, A as `concededSeat`, and B as
  `winnerSeat`.
- Both clients show the public result banner and concede log. In BO3, confirm
  the score changes from 0–0 to 0–1 without declaring the match complete and
  the sideboard phase opens. In BO1, the result marks the match complete.
- Confirm phase, turn, draw, mulligan, movement, library, life, and counter
  mutations are disabled in the client after the result. A direct command is
  rejected with `game_finished`, and a duplicate concede cannot increment the
  score again.
- A spectator receives the same public result and score but cannot concede.
  EDH elimination remains a P5 flow and does not use the 1v1 winner shortcut.

## 20. Use shared table chat

- In client A, type an English message into the composer at the bottom of the
  game-log pane and press Enter. A receives `game.said`; A, B, and a spectator
  then receive the same `chat` log entry in their role-specific snapshots.
- Send a Simplified Chinese message from client B with the **Send** button.
  Confirm both input methods clear the composer, the log scrolls to the newest
  entry, and the sender name and Unicode message are not clipped.
- Send a message from the spectator and confirm it is public to both players.
  Empty, control-character, or over-500-character commands must return
  `invalid_chat` without adding a log entry.
- Concede the game, then send one more message. Chat remains enabled while
  gameplay mutations remain locked by `game_finished`.

## 21. Verify drag preview and authoritative settling

- Drag a hand card around without releasing. The card follows the pointer,
  scales slightly, and valid stack, reveal, battlefield, graveyard, and exile
  targets highlight without changing authoritative state.
- Drop it near a battlefield corner. A pending card preview appears at the
  next assisted type slot, then disappears when the server snapshot places the
  real card there on both clients.
- Drag the owned battlefield permanent to another point in the same lane.
  Confirm it moves smoothly under the pointer, settles at the server-confirmed
  location, and produces no extra public move log for repositioning.
- Partially overlap two battlefield cards, then move the pointer directly from
  the exposed portion of one card to the other. Confirm the large preview
  switches immediately and is not hidden by the previous card's exit event.
- Put multiple untapped copies of the same land and creature onto the
  battlefield, using different printings for at least one pair. Confirm each
  group forms a compact diagonal fan with every card still hoverable and
  draggable. Give one matching creature a counter and add two matching
  artifacts; those cards must remain in separate slots. Tapped/untapped copies,
  commanders, cards owned by another seat, cards in combat or attachment
  relations, and face-down cards must not be regrouped together by **Arrange
  battlefield**.
- Right-click empty local battlefield space and choose **Arrange battlefield**.
  Confirm all current cards update together: enchantments, artifacts, and
  planeswalkers/battles occupy separate left/center/right far clusters;
  instants/sorceries use the staging row; creatures remain center-out in the
  middle; and lands stay flush with the local player's edge. Tapped
  state, counters, face selection, attachments, and combat declarations remain
  unchanged, and the remote client sees the vertically mirrored arrangement.
- Drag the permanent to A's graveyard, exile, stack, reveal area, and hand,
  returning it between checks. Counts and public identities update on both
  clients; B cannot drag A's card.
- Right-click a hand card and move it to battlefield, graveyard, and exile in
  turn. Right-click a controlled battlefield permanent and move it to hand,
  graveyard, and exile. Confirm each action reaches the same authoritative
  destination as drag-and-drop. Confirm the card menu remains open instead of
  the empty-battlefield Token/Concede menu, including with multiple permanents
  selected. Also confirm a hand card keeps its movement/library actions instead
  of being replaced by the hand-background Reveal/Mulligan menu.
- Put two distinguishable cards into the local graveyard and drag its visible
  top card to the battlefield. Confirm that exact card moves and the next card
  image appears immediately. Repeat with a one-card exile pile; the pending
  battlefield card must be confirmed instead of timing out and returning.
- Confirm the left rail places room actions above the vertical turn/phase
  controller, the rail is compact, and a strong vertical divider separates it
  from the table. Confirm the public log/chat occupies a separate right rail.
  Confirm the room code appears directly below the room name and the BO3 score
  is noticeably larger than the game-number text. In table settings, hide the
  game-log/chat rail and confirm the battlefield expands; use the remaining
  edge control to restore the rail.
  The left rail contains Settings, Leave room, phases, signals, and turn
  navigation. Draw X and Shuffle remain on the library menu; Token and Concede
  remain on the battlefield menu; Mulligan and Reveal hand remain on the hand
  menu. Hover the room name, Mulligan, and Reveal hand; none should show a
  redundant label tooltip.
- Confirm the compact hand strip and smaller hand/battlefield cards leave more
  height for both battlefield lanes. Confirm the local
  life/library/public-zone dock sits beside the hand. Open every opponent zone
  panel at once and confirm each compact two-row panel starts at the lower-right
  corner of its matching battlefield without changing battlefield geometry or
  repeating the life/hand summary already shown in the battlefield header.
  Hide every panel and confirm each battlefield still identifies its player in
  the upper-left corner.
  Drag each player name independently over the log or unused window space,
  then right-click the name and confirm that panel alone returns to its
  battlefield corner.
  The local library uses a real card back; graveyard and exile tiles show
  their top card and a lower-edge label/count chip. Publish all seven opponent
  counters and confirm every pip remains visible beside the library. Collapse
  an opponent panel, move a card onto either battlefield, and confirm the panel
  stays collapsed after the snapshot; then reopen it. Hover visible cards near
  both screen edges and confirm the art-only floating preview has no
  surrounding panel or duplicate title,
  flips sides, and does not reserve a fixed inspector column.
- Put enough cards in hand to overflow the strip. Hover the hand cards and use
  the mouse wheel in both directions; the strip must scroll horizontally while
  the heading slider remains synchronized and usable.
- Release a card outside every valid target or interrupt the server response.
  The visual returns to its authoritative location, and a pending preview
  disappears on error or after the short timeout.

## 22. Create and remove tokens and emblems

- Open **Settings** and install the optional token-capable catalog. Return to a
  running table and open **Tokens and emblems**.
- Filter by token name, select one printing, and create it. Every viewer sees
  the token on the creating player's battlefield with its token badge and
  art in that viewer's card language, with English fallback if needed.
- Reposition the token within its owner's battlefield. It remains a token and
  synchronizes like any other permanent.
- Move it to hand, graveyard, exile, or another non-battlefield zone. The
  server removes the token instead of placing it in that destination.
- Confirm a token cannot be created by a spectator, an eliminated player, or
  during sideboarding.
- Switch to **Emblems**, search by a planeswalker name or exact printing such as
  `TCMM #79`, and create it for yourself. Repeat with another player selected as
  Recipient. Each owner gets a compact emblem badge; no permanent is added to
  the battlefield and commander tax remains unchanged.
- Open both badges from each player and a spectator. Verify large card art,
  localized names where the installed catalog provides them, owner-only removal,
  and a usable popup at 1000x720. Repeat in a four-player focused layout.
- Save an emblem to a deck, reopen the deck, and cache its art. The saved kind
  and cached image survive restart without counting toward deck size. The
  ordinary card search must not offer emblems as mainboard cards.
- Disconnect/reconnect an owner without leaving; their emblems persist. Restart
  the game; emblems disappear. In multiplayer, eliminating an owner clears only
  their own emblems, including any granted to them by opponents.
- With Chinese card language, search `TM21 #1` (Angel) and verify Chinese art
  when the provider supplies it. Search `TDOM #16` (Teferi emblem): if there is
  no Chinese image, its English art must still have readable Chinese rules.
  Switch between English and Chinese while a picker/browser is open; the
  display and subsequent cache requests must follow the new language.
- Repeat with an old English-only cache. It may remain visible while Chinese
  resolution runs but must not suppress the Chinese lookup. Restart offline
  after successful resolution and verify the art and translated rules persist.

## 23. Play three- and four-player Commander

- Start an EDH room with three playable Commander decks and one empty seat.
  Confirm all three players may Ready, only those three participate in preload,
  the game starts without the fourth seat, and every player starts at 40 life.
  Repeat with four players. Confirm the create screen offers BO1 only.
- Confirm the public log shows one server d20 result for every occupied player,
  rerolls only tied groups, and then shows the descending complete turn order.
  Advance several turns and confirm that exact cyclic order is used. Restart
  the game and confirm the complete order is preserved.
- In the three-player overview, confirm the two opponents divide the upper
  half while the local battlefield spans the complete lower half. Focus each
  player in turn and confirm the two compact battlefields divide the right-side
  lane evenly without an empty third slot.
- From each player client, confirm no player-name header reserves a row inside
  any battlefield and that player identity remains available in the zone/status
  docks. Confirm the four quadrants follow tabletop orientation: the local
  battlefield is bottom-left, the next player in the rolled turn order is
  top-left, the following player is top-right, and the previous player is
  bottom-right. Card art remains upright. As a spectator, confirm the starting
  player uses bottom-left and the same order continues clockwise.
- Use each battlefield's focus button to switch between **Overview layout** and
  **Primary battlefield** at any time. Select each seat in turn and confirm it
  uses the full table height and three quarters of the width while the other
  three remain visible as smaller lanes. Select the focused seat again and
  confirm the overview returns.
- Confirm opponent details are collapsed by default. Expand each opponent dock
  and confirm its commander art and commander tax are visible. Collapse it
  again and confirm the compact public summary remains
  usable. The local dock must show the library card back, graveyard, exile,
  commander art, and commander tax.
- Confirm all four public command zones are accessible. Use a two-commander
  deck for one seat; both designated cards must start in the command zone,
  remain individually selectable, and retain the commander marker on the
  battlefield. Drag each commander independently from the local art pile to
  the battlefield and another valid zone, then drag it back onto that same
  pile. Confirm no duplicate lower command-zone or Cast button is present.
- Use the manual commander-tax minus/plus controls. Every viewer receives the
  updated non-negative value; no mana or casting-cost rules are applied.
- Concede as one player. That seat becomes visibly eliminated, its existing
  public battlefield stays visible, and its gameplay controls are disabled.
  The game continues for the remaining players and turn advancement skips the
  eliminated seat.
- Eliminate players until only one remains. The final snapshot names that seat
  as winner and marks the game complete. No EDH sideboard phase appears.
## 24. Complete a BO3 sideboard cycle

- Start a two-player Modern BO3 match and concede Game 1. Both players receive
  the public 0–1 score and a five-minute sideboard overlay; a spectator sees
  only public counts/readiness, never either registered partition.
- On each owner client, move registered copies only between **Mainboard** and
  **Sideboard**. Confirm the overlay fills most of the table and every distinct
  card name appears simultaneously as enlarged card art, with no scrollbar.
  Same-name copies must form one staggered pile with an accurate `×N` badge;
  dragging it moves one copy and updates or removes that pile as appropriate.
  At a wide fullscreen size, the larger mainboard table must be on the left and
  the sideboard on the right, with noticeably larger cards and no unused
  half-width card area; at a narrow/tall size they return to a vertical
  mainboard-above-sideboard layout. Both are divided into labeled/count
  horizontal type lanes, including separate instant and sorcery lanes. Confirm
  cards registered with Chinese type lines and older
  cards whose registered type line is absent both appear in the correct lane
  rather than falling into Other. Hover each table card and confirm a large,
  frameless card image makes the printing readable. Drag a card smoothly
  across the two tabletops without moving its source tile. Confirm the opponent
  and spectator learn only the resulting counts and ready state.
- Mark one player ready, then the other. Game 2 starts immediately, the Game 1
  loser is the starting seat, and the locked partitions become the next
  game's deck registration.
- Repeat but let the timer expire without readying. The server restores each
  previous legal mainboard/sideboard partition and starts the next game
  automatically.
- Finish a second game for the same winner. The displayed score reaches two
  wins, the match is complete, and no further sideboard phase opens.

## 25. Resume the same seat and private state

- Start a two-player game and note at least one distinctive card in Alice's
  hand. Terminate Alice's client process without clicking **Leave room** or
  **Disconnect**. Bob must continue to see Alice's occupied seat and only her
  public hand count.
- Restart Alice's client within three minutes. Connect to the same server with
  the saved server address and display name, which the form pre-fills. The
  client returns to the same room, role, seat, and host status. Alice's exact
  private hand is restored from server state; Bob still cannot see it.
- While Alice remains in the room, interrupt only the network connection and
  keep the client process running. The reconnect overlay appears immediately
  and clears after connectivity returns.
- Leave clients idle on the waiting, loading, and table screens for longer than
  the tunnel or reverse-proxy idle interval. WebSocket ping/pong traffic keeps
  them connected.
- Reconnect during the brief interval before the hub has released the previous
  transport. The client must retry the original resume credential instead of
  accepting a fresh session that cannot reclaim the occupied seat; it returns
  to the same room rather than reporting that the room is full.
- Repeat with a spectator. After resume, the spectator receives both players'
  hand counts but no hand identities.
- To check expiry without waiting three minutes, restart the test hub with
  `-reconnect-window 5s`. Drop a non-host client, wait beyond five seconds,
  and confirm the seat becomes available. A client process that remained open
  during the outage shows the reconnect-expired message and returns to a
  disconnected state; a restarted client falls back to a fresh connected
  session.
- Drop the host beyond the short test window. The room stays available to
  remaining members, but the expired seat and host authority are cleared.

## 26. Check retention and public-hub limits

- Start the hub with a temporary operator-only directory:

  ```sh
  ./build/server/hexproof-server \
    -bind 127.0.0.1 -port 57320 \
    -retention-dir ./build/retained-smoke \
    -retention-ttl 168h \
    -retention-max-files 2 \
    -retention-max-bytes 1048576 \
    -replay-page-size 1 \
    -replay-requests-per-minute 30
  ```

- Finish a game and intentionally disband its room. Confirm one JSON archive
  is written with file mode `0600`. An operator may see full hands, libraries,
  deck registrations, and logs in this file. It must not contain password
  hashes, resume credentials, or transport connection IDs.
- Finish at least three rooms. Confirm the oldest archive is evicted by the
  two-file quota and `replay.list` returns one summary at a time. Lower
  the byte quota enough to retain only one valid archive and confirm the newest
  archive replaces the oldest.
- For an expiry smoke, use `-retention-ttl 2s`, create an archive, wait, then
  restart the server or archive another ended room. The expired file is
  removed.
- Start with deliberately low values such as `-max-rooms 1`,
  `-max-tournaments 1`, `-max-connections 2`, `-messages-per-second 2`,
  `-replay-requests-per-minute 1`, `-room-creates-per-minute 1`,
  `-tournament-creates-per-minute 1`, `-tournament-closed-ttl 2s`,
  `-tournament-inactive-ttl 2s`, `-tournament-abandoned-ttl 2s`,
  `-password-joins-per-minute 1`, and `-max-concurrent-password-checks 1`.
  Confirm excess work receives the documented HTTP rejection, `server_limit`,
  or `rate_limited` response without affecting existing rooms or tournaments.
- For unattended-event cleanup, keep one ordinary viewer connected while the
  organizer disconnects. Do not refresh the event browser: after the configured
  grace the viewer must receive the closing snapshot and `tournament.left`.
  Chat or additional viewers must not restart the grace. Reconnecting with the
  organizer credential before the deadline must preserve the event. An online
  participant or player in a pairing table must keep it alive after the
  organizer leaves; a disconnected table player's existing room resume token
  must remain valid until its normal hold expiry. Explicitly leaving a
  registration with no registered participants removes it immediately.

## 27. Smoke release artifacts and languages

- Run `./packaging/linux/build-tarball.sh` on Linux and
  `./packaging/server/build-tarball.sh`. Extract each archive into a temporary
  directory. Launch the staged client and run the staged server's `-help`.
- Run the macOS and Windows scripts on their native build hosts before a
  release; cross-compiling those GUI artifacts is not part of the Linux smoke.
- In the client, inspect the main menu, Settings, deck library/editor, waiting
  room, table, dialogs, dynamic deck/seat counts, errors, and reconnect overlay
  in both English and Simplified Chinese. Check long names, 75% and 150% UI
  scales, fullscreen layout, scrolling, and button-label clipping.

## 28. Browse rooms on this hub

- Connect clients Alice and Bob to the same hub. Have Alice create an unlocked
  room, then return Bob to the main menu and open **Browse hub**.
- Confirm the summary count is at least 1 and that Alice's waiting room is a
  visible row, not an empty table with a non-zero count.
- Confirm the row shows room id/name, format, series, public player/spectator
  counts, phase, and join/watch availability. Bob can join through the enabled
  action.
- Repeat with a password. The browser shows only a lock indicator and routes
  Bob through the password form; no password, member name, deck detail, or
  table state appears in the listing.
- Fill/start the room and refresh. Player/Watch actions follow the
  server-authoritative capacity, phase, and spectator settings.

## 29. Shuffle and card context actions

- In a running two-player game, click **Shuffle** and confirm library counts do
  not change and no acknowledgement/log reveals a card or resulting order.
- Right-click a controlled permanent. Add/set the unnamed number counter and
  one named ability counter; confirm all viewers see both in distinct places.
- Tap several controlled permanents, right-click empty space on the own
  battlefield, and choose **Untap all**. Confirm every tapped permanent
  immediately returns upright on both clients while untapped cards are
  unchanged.
- Exercise library top, one-based position, and bottom moves. Confirm the card
  disappears into the owner's hidden library and only public counts/logs remain.
- Create a token copy and confirm it appears nearby with the same printing.
- From a controlled battlefield card, use **Choose target** to point first to a
  player and then to another battlefield card. Put an instant or sorcery on the
  shared stack, select it, use its `◎` target action, and repeat both target
  shapes. Confirm every client sees the arrows across the shared tray and
  battlefield, clearing the target removes only that source relation, and
  moving the stack source away removes its arrow automatically.
- From an owned battlefield card, use **Attach to…** and click another
  battlefield card. Same-lane attachments snap onto the host and follow a host
  drag. An attachment onto another player's permanent is drawn on that card
  while the source stays in its controller's lane. **Detach** returns it.
  Confirm spectators see the public relation and that attach never changes
  controller or infers Aura/Equipment legality.

## 30. Verify Pack simulator navigation and retained-log compatibility

- Without connecting to a hub, open **Pack simulator** beside **Browse hub** on
  the main menu. With installed products, open a pack and return to the menu.
  No online event or deck is created. Repeat in English and Simplified Chinese
  and at the 900×620 minimum window size with increased UI scale.
- Confirm **Replays** is absent from the menu, replay actions are absent from
  **Settings → Keyboard shortcuts**, and Settings has no duplicate simulator
  entry. The Limited tournament creation form retains its simulator shortcut.
- Live table logs and chat must still work. The removal must not delete server
  archives or change their privacy projection. Run the retained-log checks:

  ```sh
  (cd apps/server && go test ./internal/server -run 'Test.*(Replay|Retention)')
  ```

  The compatibility replies must contain public metadata/logs only, never hands,
  libraries, deck registrations, sideboard partitions, resume credentials,
  connection ids, or the raw archive object.

## 31. Check manual-tabletop completeness

- Put a permanent onto the battlefield face down. Confirm its owner still sees
  the identity while an opponent, a spectator, the public game log, and a
  retained replay do not. Turn it face up and confirm the identity becomes
  public again.
- Declare a draw, then exercise host-only same-game restart. Confirm score, game
  number, and starter follow the documented BO1/BO3 behavior.
- Exercise dice, coin, random active-player, and random public-permanent tools.
  Invalid bounds, eliminated seats, duplicate candidates, and private cards must
  be rejected.
- Let a host reconnect hold expire and confirm host transfers to the lowest
  occupied player seat. If only spectators remain, the next player joining must
  become host.
- Generate enough activity to hit snapshot/log bounds, then inspect a retained
  replay. Log ids remain monotonic and hidden identities remain redacted.

## 32. Concede a Forge rules game

For local testing of the official Forge human controller, prepare and start the
development runtime with:

```sh
./tools/run-local-forge-server.sh --prepare -port 57321
```

The launcher builds the Go server and prepares the pinned native runtime when
needed. Later runs can omit `--prepare`. The launcher supports only official
Forge. `--` passes the remaining arguments to the server unchanged.
The server retains its loopback bind unless overridden.

Native preparation records a runtime in `build/forge-native/local-runtime.json`
and preserves earlier packages. `HEXPROOF_FORGE_LOCAL_ROOT` selects an explicit
runtime directory; `HEXPROOF_FORGE_SOURCE_DIR` and `HEXPROOF_FORGE_OUTPUT_DIR`
override the native builder's source and output directories. The launcher checks
the pinned source, host source, main JAR, and dependency hashes before starting.
These packages are for development; this command changes no remote service and
does not prepare a release artifact.

- Start a two-player Forge room and wait until one player has a decision open.
  From either active player, click **Concede**, cancel once, and confirm that no
  command was sent. Open it again and confirm while the other player owns the
  prompt; concession must not depend on prompt ownership.
- The conceding client receives correlated `game.conceded`, all viewers receive
  fresh privacy-scoped `rules.snapshot` projections, private prompts are
  cleared, and the terminal `room.snapshot` enables the return-to-room flow.
  Confirm the server result records reason `concede`, the winner, and the
  updated score. The engine session is closed. Repeating the command returns
  `game_finished` and cannot increment the score again.
- In a three- or four-player Commander Forge room, concede before only one
  player remains. The actor's Forge status becomes `conceded` or `lost`, all
  viewers receive fresh projections, the remaining private prompt is routed to
  its authenticated owner, and the game continues without a terminal room
  result. Continue conceding until Forge reports game over, then confirm the
  ordinary terminal result and return-to-room flow.
- A spectator has no Concede action. After the local player is no longer
  `playing`, its Concede action disappears.

### Retract mana before casting

- In a local Forge game, use **Full control** and naturally play two basic lands
  of the same type. Before selecting a spell, tap the first land for mana.
  Confirm its **Undo mana** hint and click it again: the engine untaps the land
  and removes only the mana it produced. Repeat in Simplified Chinese.
- Tap both lands before casting. Only the most recent eligible activation is
  offered for undo. Retract it and confirm the other land stays tapped with its
  mana still floating; retract that earlier activation next. Identical tapped
  copies must remain reachable through their pile or exposed corner.
- Produce mana again and use it to cast a spell normally. Completed payment
  must not offer its consumed source for undo. Pass priority or advance the
  step and confirm old undo actions disappear according to native history.
- Retest clicking a source to retract its contribution during an unfinished
  payment. Cancelling that spell still follows native payment rollback. A
  sacrifice source such as Lotus Bloom must not acquire a standalone undo.
- Repeated clicks while a response is pending send only one action. The client
  never locally untaps cards or clears a mana pool. Opponents and spectators
  see the public tap/pool changes without receiving the player's private undo
  option.

### Optional Forge action clock

- Create a two-player Forge room with the 25-minute action clock enabled;
  confirm the waiting-room summary and both table clocks. Create another with
  it off and confirm neither table clock is shown. Check ordinary/AI/Cube and
  constructed/Limited event creation controls; EDH and manual rooms omit it.
- Leave a playable decision open: only its owner's budget decreases. Respond
  and confirm engine processing does not consume the previous owner's budget.
  Confirm target/card choices charge their deciding player.
- In BO3, finish Game 1, wait in sideboarding, and start Game 2: budgets remain
  paused while waiting and resume with saved time. Restart the game and confirm
  saved time; finish the match, return to the room, and confirm fresh 25 minutes.
- Disconnect/reconnect a player host or recover a failed model worker: clocks
  pause while input is unavailable and resume at the current decision. An
  ordinary player's disconnect leaves their live decision clock running.
- Automated short-budget tests verify expiry without another action, stale
  timer rejection, and deadline-time restart preserving the timeout result.
  A Swiss timeout commits the match result; casual Cube has no standings entry.

### Forge token update responsiveness

Use an installed full catalog and Chinese card language; a mock or empty catalog
does not exercise failed name lookups. The deterministic native probe applies
0, 1, 2, 4, 8 and 16 Eldrazi Spawn tokens, refreshing the snapshot and priority
prompt ten times for each count. It uses Forge's real `Eldrazi Spawn Token`
action labels alongside the public `Eldrazi Spawn` identity. It keeps the table
mounted between updates, hovers a token, and captures the maximized test window.

```sh
cmake --build build/client-qt --target hexproof_native_audit
python3 tools/ui-automation/run-native.py \
  --scenario tools/ui-automation/scenarios/ForgeTokenResponsiveness.qml \
  --catalog /path/to/cards.sqlite --card-language zh --players 1 \
  --output build/forge-token-responsiveness
```

Inspect `seat-1/artifacts/tokens-*.json`: `applyMs` measures synchronous
snapshot/prompt processing; `eventMs` includes the 100 ms timer interval and
render/event processing. Separate each count's initial construction sample
from repeated updates. Repeated prompts must not cause multi-second GUI stalls
as token counts grow. This is a native client fixture, not a live engine match
or a measurement of network/AI latency. QML regression coverage also checks
that token labels use projected identities without changing spell-face names;
catalog tests cover cached misses, replacement invalidation, and retryable
database failures.

## Related automated checks

Use [the development policy](development-policy.md#choose-verification-by-risk)
for focused checks or release qualification. Native visual confirmation and
component/CTest results are separate evidence. The active wire schemas and
shared fixtures live in `protocol/v2/` and `testdata/protocol/v2/`; update those
contracts together when wire behavior changes.
