# Manual zone actions

This contract covers the 2026-09-11 owner request in `fe`. Manual players
choose targets and resolve card text; Forge rules are outside this work.

## Effect families and interaction

| Player intent | Manual workflow |
|---|---|
| Cast the unknown library top | Drag the library card back directly onto the stack. The server moves the actual top card and reveals it in the public stack without a preceding private look. |
| Bomat Courier attack | Hold Shift while dragging the library top to exile, or choose **Exile top card face down (no player may look)** from the library menu. Neither action opens a top-card view. |
| Bomat Courier returns its cards | Open exile, select the relevant face-down entries, and move them to hand. Hidden entries remain individually selectable even when printing grouping is enabled. Players track which Courier exiled which cards. |
| Endurance | The affected player opens their graveyard, clears any filter, selects all visible cards, and chooses **Bottom of library · random order**. Only the selected cards are randomized; the existing library order stays intact. |
| Cascade-style cleanup | Select only the relevant exiled cards and place them on the bottom in random order. Unselected exile cards stay where they are. |
| Put cards back in a chosen order | Choose cards in the desired sequence and select library top or bottom in order. Switch to individual cards to select specific copies of a printing. |
| Shuffle cards into the library | Select the relevant cards and choose **Shuffle into library**. Each destination library, including its old cards, is shuffled in the same transaction. |
| Return several permanents to hand | Select the controlled/owned permanents and choose **Move to hand**. Cards return to their immutable owners; tokens disappear. |
| Discard, exile, or put several hand cards back | Open **Select and move hand cards…** from the hand menu. Select individual cards or the whole visible hand and choose a destination. |
| Mass reanimation / graveyard exile | Select matching graveyard cards and move them to the battlefield or exile. All selected cards move together; players still decide which cards qualify. |
| Wheel / graveyard-and-hand recycling | Perform the required graveyard and hand selections separately, using shuffle-into-library for each, then draw the instructed count. No card text is inferred and no multi-zone resolution is presented as atomic. |
| Look at the top X and keep some cards | Open the top-X view, check the cards to keep, assign the selection to hand, and set the remainder destination to library bottom or the destination required by the effect. Confirm once for the complete viewed set. |
| Scry / surveil / split a top-X view | Assign exceptions to library bottom, graveyard, exile, or battlefield; leave the remainder on top. Review the destination groups and arrange each group's order before confirming. Battlefield assignments may be face down. |

Endurance's exact distinction is established by the
[official Modern Horizons 3 release notes](https://magic.wizards.com/en/news/feature/modern-horizons-3-release-notes).
Cascade and mass-reanimation examples are described in the
[Modern Horizons 2 release notes](https://magic.wizards.com/en/news/feature/modern-horizons-2-release-notes-2021-06-04).
These are reusable manual verbs, not a claim to implement every Magic card.

## Unseen face-down exile

- `game.move_card` accepts `faceDown: true` from hand/library to exile as well
  as the existing battlefield destination. The library drag/menu uses only
  the unknown-top sentinel; it does not fetch or resolve the identity first.
- Exile card backs expose public instance ids, counts, and ownership, but no
  identity to any player or spectator, including the owner and hand-visible
  spectators. Public logs and replay replies also omit the hidden identity.
  Battlefield face-down controller visibility is unchanged.
- Ordinary library-to-exile dragging remains face up. Shift applies only to
  library-to-exile drops. Drop hotspots track the pointer even during a fast
  initial movement or a grab away from the center of the pile.
- The exile browser shows backs and a no-look label. It never queries card art
  or filters on hidden identities, and never combines hidden cards by name.
  Moving a hidden card out of exile clears face-down state; hand/library remain
  private and public destinations expose the card under their normal policy.
- Client and server must both be updated for face-down exile. Older servers
  reject that destination/flag combination without moving or revealing a card.

## Top-X draft and privacy

- The top-X popup owns a local draft. All, None, Invert, and Shift-click range
  selection operate on the displayed cards; clicking a row previews it without
  changing the selection. Assign applies to the selected set. Right-clicking a
  selected card stages the entire selection; an unselected target stages only
  that card. These actions do not send commands or close the view.
- The remainder initially stays on library top in its original order. Changing
  its destination or face-down setting affects only cards without an explicit
  assignment. The reset action removes selected assignments so those cards
  follow the remainder again. Selection alone never creates an assignment.
  Rows omit the default remainder label; only explicit assignments and
  face-down status need a subtitle beneath the card name.
- Destination groups follow library top, hand, battlefield, graveyard, exile,
  then library bottom. Drag handles and arrows reorder within a group without
  changing other groups. The first top card is drawn next; the last bottom
  card is bottommost. Randomizing an end disables its manual ordering controls
  until randomization is turned off; it never shuffles the untouched library.
- Confirmation expands the draft into the existing complete `assignments`
  payload for `game.resolve_library_view`. Every viewed physical card appears
  exactly once. The server retains atomic validation and mutation, including
  approved remote scopes. Hand/battlefield go to the requester; graveyard,
  exile, and library ends stay with the source owner. Closing or invalidating
  the popup discards the draft without moving cards.
- A private top-card view always sends `reveal: false`, including moves to
  hand and either library end, irrespective of a previous full-search reveal
  preference. Top-X resolution likewise does not opt into name disclosure.
  Ordinary public-zone projections still show face-up cards. Full-library
  search retains its explicit reveal control; face-down battlefield placement
  always suppresses name disclosure.

## Authority and transaction

- Category: atomic explicit helper. A menu choice names the destination and
  ordering policy and applies to the displayed selection count.
- The room reducer owns card locations, immutable ownership, library order,
  token lifetime, and public logs. The client owns only ephemeral selection,
  filters and preview, plus the existing bounded optimistic overlay.
- `ZoneBrowserPopup`, `TableCardMoveController` and the typed `WsClient`
  facade own the interaction. `room_game_batch_move.go` validates the complete
  selection, prepares randomization and destination libraries, then commits.
  Random failures, invalid ids, permissions and invalid destinations leave
  every source, destination, relation and log unchanged.
- `game.move_cards` accepts own hand, controlled/owned battlefield cards, or
  a specified public graveyard/exile source. Its existing optional
  `libraryPlacement` string supports `top` (default), `bottom`, and `shuffle`.
  `randomize` randomizes just the selected cards and is incompatible with
  `shuffle`. Indexed insertion remains a single-card action.
- Full-library shuffling is prepared independently for each immutable owner.
  Top/bottom insertion preserves relative selection order per owner, and
  token removal and permanent-state/relation cleanup still apply.
- Opponent public-zone movement retains exact one-use consent. Moving cards
  from another player's graveyard/exile into a hidden zone remains disallowed;
  the affected player performs their own Endurance/recycling operation.
  Opponent hands/libraries cannot be supplied as batch sources.
- Logs and acknowledgements contain counts, zones and ordering policy, never
  hidden card names, ids, or resulting order. Normal owner/opponent/spectator
  projection rules are unchanged. Opening the hand manager uses the existing
  authorized hand projection and does not reveal the hand.
- A stale selection is pruned as snapshots arrive. Closing the browser or
  changing games clears selections; queued commands use captured explicit
  ids. Filtered selection is labelled **Select visible**. An unselected
  right-click target acts on that single card; the visible move button acts
  on the explicit selection.

## Acceptance evidence required

Reducer tests cover every source/placement, untouched library order, complete
shuffle scope, immutable ownership, stale/duplicate ids, random failure,
spectators and hidden projections. Client tests cover payloads, selection,
single versus batch dispatch, compact layout, and menu/shortcut routing.
Native current-source clients must exercise the graveyard operation, hand
management, battlefield bounce, and opponent/spectator views. The wider
multi-round application review is recorded separately in the dated audit.
