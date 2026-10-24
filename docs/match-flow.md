# Match flow — ready, start, games, sideboard, reconnect

- Status: **Active**
- Last updated: 2026-08-28
- Parent: `product-brief.md`, `table-layout.md`

## Room waiting → start

| Rule | Detail |
|------|--------|
| Host | Creator joins as **player + host** (takes a seat). |
| Seats | Ready/start requires one private seat for Playtest, both seats for Generic 1v1 or Duel Commander, or **at least two occupied seats** for EDH. EDH retains a four-seat cap; after every seated player becomes Ready, the match starts and unoccupied seats stay out of the game. |
| Deck | Each **player** selects a structurally playable deck: at least 7 main-deck cards and the required commander designation. `preload` rooms additionally require local art to be complete before selection; `background` rooms allow selection while art is missing and keep the missing-art warning visible. This local availability state is distinct from the player's room Ready state. |
| Deck transport safeguards | The mainboard must contain at least **7 cards** so setup can produce an opening hand. The server caps a submitted deck at 500 entries / 1,000 total cards and bounds identity strings; these are operational limits, not format-legality checks. |
| Commander-format ready | Duel Commander and EDH decks must have **one or two designated commanders**. Construction legality remains manual. |
| Ready | Each **player** clicks **Ready** only. **Spectators do not ready.** |
| After all players Ready | The room's card-loading policy applies: `preload` shows a blocking loading bar; `background` starts immediately and cooperatively queues metadata and image work in small batches so card selection and table interactions remain available. Both use all selected decks' deduplicated printing keys. |
| After load complete | `preload` auto-starts when every seated player completes; `background` is already at the table and prioritizes currently visible cards. There is no separate Start button. |
| Load progress | Asset totals cover all selected decks' deduplicated printings and independent faces, including local hits. A bounded local check separates available art from missing downloads; the UI reports both counts. Compatible local files/custom art never require another download merely because a match starts. |
| Load gate | All connected clients may prefetch; only seated players gate auto-start, so a spectator cannot stall the room. |
| Load invalidation | Changing a deck, cancelling Ready, or losing a player seat cancels the active load generation. Stale completion messages are ignored/rejected. |
| Host powers | Host may **kick** a player/spectator, **restart the current game**, and **disband** the room. Kicking a player after the match starts forfeits that player's two-player match or eliminates that EDH seat. |
| Intentional leave | User disconnects to main menu → **seat freed immediately**. Before a match starts, the room may accept a new occupant. After start, a non-host player forfeits the whole two-player match or is eliminated from EDH so the active turn cannot become stranded; an intentional host leave retains the existing disband behavior. |
| Network drop | Seat **held 3 minutes** for **reconnect to same seat**; after timeout the membership is released. A started-match timeout forfeits the whole two-player match or eliminates that EDH seat. If the released member was host, host authority transfers to the lowest occupied player seat; spectators are never promoted. Both endpoints send WebSocket transport heartbeats so an idle waiting/loading/table connection survives intermediary timeouts and stale transports are detected. If a replacement connection reaches the hub before the old transport is marked resumable, the client retains and retries the original credential instead of becoming a fresh session. Table controls are disabled while reconnecting, and application commands attempted without a live room transport are rejected locally instead of being silently dropped. |
| Change deck after Ready | Selecting/changing deck (or opening editor in a way that changes the registered list) → that player becomes **not Ready** again. |
| Spectators | Max **8** spectators per room (when allowed). At creation the host may explicitly allow all spectators to inspect every current hand; the default remains hidden and the policy cannot change after creation. Opponents remain unable to see each other's hands. |
| Playtest | Server-backed private room with one seat, BO1, no spectators, and no public room-browser entry. The selected deck mode still determines Generic 1v1, Duel Commander, or EDH setup. |

The manual table presents one blocking recovery overlay with its countdown;
the application-level reconnect banner is suppressed while that screen handles
recovery. Other screens keep the application banner. This presentation rule
does not change transport retry, seat retention, or command gating.

## Opening a game

Forge AI practice is a two-seat exception to human readiness: one seat is a
room-owned native AI whose configured deck is selected by the human host. The
AI becomes ready automatically and never gates art loading. Changing its deck
or difficulty while waiting clears human readiness. It cannot become room host
or keep an abandoned room alive. See [native AI practice](rules-engine.md#native-ai-practice)
for its constructed BO1 scope and engine lifecycle.

| Rule | Detail |
|------|--------|
| Opening hand | **7** cards |
| Starting life | **Generic 1v1 and Duel Commander: 20**. **EDH: 40**. Manual adjust after. |
| Mulligan | **Supported (v1):** the manual Mulligan action returns the hand to the library, shuffles, draws up to 7, increments that player's public per-game mulligan count, and logs the action. Hexproof does not enforce London bottoming or format-specific free-mulligan rules. |
| Discard hand | The empty-hand-area context menu can discard one server-random card or, after confirmation, the complete hand. Both are atomic server actions; discarded identities become public only through the graveyard/log while every remaining hand card stays owner-private. |
| First game of match | Generic 1v1 and Duel Commander choose a random starting player and log the result. In multiplayer Commander, every occupied player publicly rolls a server-generated d20; tied groups reroll, descending results define the complete cyclic turn order, and the highest player starts. |
| Later manual games (non-BO1) | **Previous game’s loser** chooses play or draw during sideboarding; Play is selected initially. Choosing again clears their Ready state. |
| Draw | Any active, non-eliminated seated player may declare a draw after local confirmation. BO1 and EDH finish with no winner. BO3 score is unchanged, the match's `drawnGames` count increments, and the ordinary sideboard gate opens; because there is no previous loser, the next starting player is random and logged. |
| Restart | The host may restart the current game after local confirmation. The same game number is rebuilt from committed registered decks with a new shuffle/opening hand, while score and the remaining occupied players' relative cyclic turn order are preserved. For manual EDH, released seats are omitted; if the original starting player has left, the next occupied seat in that cycle starts. Conceded or eliminated players who still occupy their seats return for the restarted game. Existing minimum-player and host-membership rules still apply. Every member receives a sequenced `game.restarted` event with the resulting starting seat before the replacement snapshot; old private-zone grants, pending consent, and card interactions do not carry into the replacement game. |
| BO3 match end | **First to 2 game wins** (best of 3). Show score e.g. 1:1 → next game or match over at 2. |
| Hand storage | **Client + server** both hold hidden hand identities (trust-server); opponents see count/backs only. Spectators also see count/backs unless the immutable room policy explicitly exposes current hands to them. |
| Shuffle | The trusted server shuffles the registered deck without revealing its order |
| Projection | `game.snapshot` is generated per viewer: public counts/logs plus shared stack/reveal identities are visible to all. A player receives only their own hand. A hand-visible spectator receives every current hand, but no sideboard, library order, private search result, or face-down battlefield identity. Library order remains server-only until an authorized search flow. |

Each manual-game seat has an authoritative public `turnCount`: the starting
player begins at 1 and all other players at 0. It counts turns begun by that
player, including the current turn. Phase changes, mulligans and reconnects do
not increment it. Eliminated players retain their count and are skipped;
ending a game does not add a turn. New games and restarts reset these counts.
The client displays each seat's count in its battlefield header for players
and spectators. Snapshots carry the counts independently of the bounded log;
an older snapshot without the field leaves the count hidden.

## In-game zones & actions (player)

| Action | Detail |
|--------|--------|
| Hand UI | **Below battlefield** |
| Draw | Use **Draw X cards** from the library context menu (or its shortcut) to request 1–1,000 cards atomically, or drag the own-library top card into hand for one manual draw; left-clicking the library does not draw. Drawing past the remaining library clamps to its current size. |
| Play with library top revealed | The owner can toggle continuous public visibility from the library context menu. Only the current top card is projected to every player and spectator, updating after each atomic library mutation. Disabling the mode removes its identity; an empty library retains the mode without a stale card. The mode resets each game. |
| Shuffle library | Randomize the acting player's remaining hidden library on the server. Counts stay unchanged; acknowledgement/log never reveal a card or resulting order. |
| Library actions | Right-click the own-library tile to draw X, shuffle, search the **full own library**, privately inspect the top card, privately resolve the top X cards, or move the top X cards to graveyard/exile. Top-card inspection can move that card to hand/battlefield/graveyard/exile or explicitly return it to the source library top/bottom; the single-card view omits redundant randomized-order variants and defaults to a private log, with an explicit option to reveal the moved card's name. When a full own-library search places selected cards on the library top or bottom, the shuffle decision is resolved before placement: confirming sends shuffle first and placement second, while cancelling places without shuffling. In a top-X view, select cards and assign their destination together, optionally revealing that batch's names in the public log when the resolution succeeds. Disclosure defaults to off and resets after each batch; it is stored per card and may be edited before confirming. Cards without an explicit assignment follow a separate remainder destination and remain private. Destinations are grouped for review, and drag handles or arrows set the relative order within each group. Each library end may be randomized independently. Closing the popup discards this local draft; confirming supplies exactly one destination per viewed card. The whole top-X resolution is atomic. |
| Library search | Search filters match canonical/localized names and English/Chinese card types. A row click updates the preview immediately, while only its checkbox changes the multi-selection. Right-clicking another player's library offers consent-gated full search, top-card view, and top-X view; each request reveals only the approved scope to the requester. Own and consent-approved remote searches support multi-selection, including deterministic multi-card battlefield placement. A remote top-X resolution uses the same one-use grant: hand/battlefield assignments go to the requester, while graveyard/exile/library assignments remain with the source owner. Every approved card must receive one destination in the same atomic request. The card context menu mirrors hand/battlefield/public-zone destinations and keeps ordered/random variants for library top/bottom; graveyard and exile each have one ordinary action without redundant order variants. Popup input is isolated from table cards and zone backgrounds underneath. Remote identities are sent only after that player explicitly approves through a short-lived one-use grant. **Reveal** vs **Hidden** log; log visible to **all** without leaking unselected identities. |
| Play from hand | **May go directly to battlefield**, either face up or face down (stack path optional). The hand-card menu also offers **Play land…** to choose a face, review advisory timing/type/count warnings, and atomically move that card while incrementing the public recorded-land-play count. Ordinary moves never increment this count. |
| Manual control change | Drag an owned card or own library top to any seat's battlefield. The destination lane is the controller while immutable `ownerSeat` determines hidden-zone return and does not reveal any other library card. |
| Battlefield layout | A newly visible card receives an assisted slot based on its current face and type: lands are flush with that controller's edge; creatures are center-out in the middle; enchantments/unknown cards, artifacts, and planeswalkers/battles use separate far clusters; and instants/sorceries use a staging row. Face-down cards use the neutral support cluster. Existing cards never move merely because another card entered. Players may freely reposition any controlled card, or explicitly use **Arrange battlefield** to atomically regroup the whole local battlefield. This is metadata-driven layout, not rules enforcement. |
| Cross-seat public zones | Any visible graveyard/exile may be browsed without approval. Right-click or drag may request a single/batch move, but moving cards out of another player's pile requires that player to approve the exact short-lived request before any mutation. Graveyard and exile browsers share filtered checkbox selection and Select all; right-clicking a checked card requests the selected set atomically. Locally owned selections may return to hand or the library top. Successful public logs name the source player and zone. Battlefield lanes represent current control, but every card entering graveyard or exile is grouped under immutable `ownerSeat`, regardless of the pile used as the drop surface. Hidden destinations also return to the owner. |
| Tap / untap | Double-click a controlled battlefield permanent to toggle its public orientation immediately. The own-battlefield background menu may also untap all controlled permanents at once. The client reconciles optimistic animation with authoritative server snapshots. No automatic phase or rules action. |
| Face down / up | A hand card or searched library card may enter the battlefield face down. Only its current battlefield controller receives the hidden identity and may change its selected face or persistently turn it face down/up; an immutable owner on another seat sees the same card back and public instance state as other players. Leaving the battlefield clears face-down state. Face-down library moves log only counts, destination, and face-down status. |
| Choose battlefield face | Left-click one controllable multi-face card and use **Choose card face** (default `V`), or use its context menu. Face choices follow the active selection, including selection fallback after another card is deselected or leaves the battlefield, and refresh when metadata arrives. Multiple selected cards do not enable this single-card action. |
| Hand dragging | Dragging a hand card preserves its grab position when the drag threshold is crossed, including fast movement and partly clipped cards. A drop onto the shared stack must target the stack without an offset into another zone. Reordering inside the hand remains local; rejected drops leave the card in hand. |
| Battlefield and shared-card dragging | Battlefield, stack and revealed cards preserve the actual grab point through drag activation and lift, including edge grabs, tapped permanents and reveal-owner dividers. The pointer's release position determines the receiving zone for the same physical card. Existing ownership and destination permissions still apply. |
| Stack resolve | **Caster** may click to resolve/advance their spell on stack; **fully manual**; others do not resolve for them |
| Reveal hand | Use the hand background context menu or shortcut to publish the full hand, or drag selected cards into the shared reveal area. While the acting player has cards there, the action becomes **Recall hand** and atomically returns all of their revealed cards to hand. Multiple owners' reveals are separated by labeled divider lines. |
| Phase state | The compact 11-step controller in the left action rail is server-authoritative coordination state. Only the active player advances it; phase changes do not automatically untap or draw. |
| Combat and target relations | Player-target attacks render a target-name marker on each attacker; permanent-target attacks use solid red arrows, and blocks use dashed arrows to incoming attackers. A declaration dialog may tap each chosen attacker in the same server transaction. Separately, **Choose target** draws a public arrow from controlled battlefield cards or a locally owned stack card to any seated player or battlefield card. The server does not infer target legality. Combat relations survive through combat; ordinary targets clear explicitly, when their source leaves its zone or changes battlefield controller, or on the next phase/turn transition. |
| Response status | Each player may publish No response or Please wait, then clear it. Status is public and never enforces priority. Both reset on phase/turn; No response also clears on the next public event while Please wait remains explicit. |
| Explicit phase helpers | Untap all, Draw 1, and Tap attackers appear only in their relevant phase and run only when clicked. |
| Attach | The source card's **owner** uses **Attach to…** then clicks another battlefield card, or **Detach**. Same-lane sources snap onto the host and follow when that host is dragged or arranged. Cross-lane sources stay in the controller's battlefield array and are drawn on the target in the table relation layer. Attach does not change controller or check Aura/Equipment legality. |
| Next turn | Active turn player advances through the authoritative cyclic turn order, skipping eliminated seats; only the incoming player's public `turnCount` increases. Phase and the public recorded-land-play count reset to Untap and zero. Arrows and response statuses clear, including when the active EDH player's elimination advances the turn. This does not automatically untap permanents or draw a card. The client asks for confirmation when the shared stack is non-empty, a player is waiting, or the active player has more than seven cards in hand. |
| Concede | **Loses the current game**; logged; updates BO score; at 2 wins match ends (BO3) |
| Random tools | Seated, non-eliminated players may publicly roll 1–20 dice of 2–1,000 sides, flip a coin, select a random active player, or select one card from an explicit set of public battlefield cards. Results are server-generated and logged. |
| Post-match review | A completed match opens a result dialog. Stay keeps the immutable table available for review/chat; Return to room archives the match, restores each selected deck's originally registered mainboard/sideboard partition, and restores the waiting room for every member. The command is unavailable during a live game, EDH partial elimination, or BO3 sideboarding. |
| Match score | Show BO score e.g. **1:1** during multi-game matches. A seated player's own wins are always displayed first; spectators retain stable seat order. |
| Reconnect | Network drop: **3 min** window → same seat + server state restore |

## Commander-format extras

| Item | Detail |
|------|--------|
| Life default | **Duel Commander: 20**. **EDH: 40**. |
| Multiplayer order | The opening public d20 ranking is authoritative for both turn advancement and viewer-relative clockwise battlefield placement. Stable seat ids remain identity/ownership keys only. |
| Command zone | **Local dock beside the hand**, visible to all through public zone browsers; one or two designated commanders start there. Click the local art pile to browse it, or drag either commander directly to any valid tabletop zone. The same pile accepts eligible commanders returning to the command zone. |
| Commander tax | **One dedicated control per commander card** (not one of the 7 pips); partner commanders keep independent command-zone cast counts. The primary value is the derived next additional cost (`+2` per previous cast), while the tooltip shows the count. Manual `−`/`+` correction remains available. **Cast commander** in the own command-zone browser moves that commander to the shared stack and advances only its count in one action. Ordinary dragging does not imply a cast. |
| Commander damage | A public panel shows every physical commander against every seat. Authorized players may adjust by one or set an exact total without changing life. A controller may record a positive combat-damage amount, atomically subtracting the same amount from target life. A total of 21 or more is warning treatment only; the application never automatically eliminates the target. |
| Counter pips | **7 synchronized, initially unnamed slots** per player; each client renders the first 0–7 (default 0). The first click selects without changing the value; while selected, circle LMB +1, RMB -1, **I** edits the label, and **S** sets an exact number. All see synchronized labels + counts for slots they display. **No special poison UI** — if players need poison, they rename/use any generic slot. |
| Concede (EDH) | Conceding player is **eliminated from the game**; others may continue (table stays up) |
| Concede (Duel Commander) | Uses the ordinary two-player game/match loss flow. |
| EDH games | **Single game** only (no sideboard phase) |
| Room series | Room creation exposes only BO1 for EDH. Duel Commander exposes BO1 and BO3. The server canonicalizes every EDH room to BO1 even if an older client submits BO3. |
| Concede | Allowed |
| Elimination authority | Eliminated players retain their public board projection but cannot issue game actions; turn advancement skips them. |

## Sideboard (BO3 / non-BO1 only)

These match-level rules also apply to Forge rooms. Each next game is created by
the Forge coordinator from the committed partition; the manual game initializer
is not used. Live engine state remains in the rules projection, while existing
game metadata carries the timer, score, result, public log and owner-private
sideboard. See `rules-engine.md` for restart/failure and replay boundaries.

| Rule | Detail |
|------|--------|
| Timer | **5 minutes**; **countdown visible to both players** |
| Match score | The workspace keeps the authoritative BO3 score visible with both player names. A seated player's own wins appear first; spectators keep stable seat order. Long names elide independently so the wins, countdown and Ready control remain visible. Reconnect restores the same score. |
| Actions | Main ↔ SB drag only on **registered match decklist**. The owner view lays out every copy at once: mainboard table above sideboard, with explicit horizontal type lanes and no scrolling. |
| Duel Commander | No mainboard/sideboard card movement. During the timed Ready gate, the owner may designate one or two mainboard cards as the next game's commanders; the registered card list stays unchanged. |
| Forbidden | Paste-import, full-DB search-add |
| Ready | Players click **Ready**; a pending mainboard still needs at least **7 cards**; **all Ready → start next game immediately**. The button waits for the authoritative readiness change, transition, error, or disconnect before accepting another submission, including while Forge starts the next JVM. |
| Timeout | **Force start** after 5 min using **previous game main/SB** |
| Privacy | Pending card identities are projected only to their seated owner. Opponents and spectators receive readiness plus mainboard/sideboard counts. |
| Review | Players may open a read-only browser of the previous game's visible battlefield, graveyard, exile, and command-zone cards while sideboarding. It does not expose hands, libraries, pending decks, or face-down identities. The retained public state remains available after reconnect. |
| Next game | Committed partitions replace the registered split only after all players Ready; in manual mode the previous game's loser chooses the next starting player. The choice defaults to Play and is retained on timeout; a drawn game has no chooser and uses a random start. |

## Log

- Dedicated optional **right log/chat rail**; **visible to all** in the room.
- Includes draws, casts, damage, chat, **opening/searching a library**, concede,
  etc. Opening the owner's own library immediately appends a public,
  identity-free “is searching their library” entry; the private dump remains
  visible only to that owner.
- Players and spectators may send explicitly public chat while the table is
  open, including after the current game has ended. The server validates and
  appends the message before it appears in any client log.
- Server retention **TTL ≈ 1 week**.

## Retained public-log API

- The client replay browser, viewer, and shortcuts have been removed. Live logs
  and chat are unchanged.
- The server retains the existing `replay.list` / `replay.get` API for
  compatibility. It contains public match metadata and the authoritative public
  log only; it is not exposed as a feature in the current client.
- Replay is not a hidden-state table reconstruction. Operator-only hands,
  libraries, decks, and sideboard partitions never cross the replay API.
- Replay availability follows the operator's retention TTL and archive
  cleanup; it is not permanent match history or an account feature.

## Settings & library

- **Settings page** required (language zh/en at minimum; extensible).  
- In-table layout settings persist visibility for the shared tray, right
  log/chat rail, and rendered counter-slot count. Seat zone docks remain
  available.
- **Delete deck** required.  
- **Solo Playtest** is available through the connected hub and deliberately
  reuses the authoritative multiplayer table rather than maintaining a second
  local game-state implementation.

## Defaults from product review (locked)

- Full player seats required; host kick/disband; mulligan; roll+log; EDH eliminate on concede; sideboard countdown both sides.
- Generic 1v1 and Duel Commander life 20; BO3 first-to-2; Duel Commander keeps
  its registered deck fixed; intentional leave frees seat; network drop 3 min
  hold; max 8 spectators; Ready+deck change → unready.
- **No dedicated poison control** — poison is just player use of one of the **7** generic pips.

## Out of scope reminders

- Manual rooms do not use automatic priority; Forge rooms follow the separate
  engine lifecycle in `rules-engine.md`.
- No global lobby, accounts, or matchmaking; the P7 browser lists only rooms
  on the currently connected hub.
- No peer-to-peer or rules-engine sandbox; Playtest is a server-backed
  single-seat table.
