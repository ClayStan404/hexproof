# Protocol v1 golden fixtures

Shared JSON fixtures for the `hexproof.v1` wire protocol (client + server).

## Wire rules

- Protocol version `v` lives ONLY in the `session.welcome` payload. No other
  message carries a top-level `v`.
- Client commands that need a reply include `id`; the server echoes the same
  `id` on the success event or on `error`.
- Success types are events (`room.create` -> `room.created`), not `*.ok`.

## Current fixtures

| File | Direction | Purpose |
|------|-----------|---------|
| `session-hello.json` | C -> S | Handshake offer (no top-level `v`) |
| `session-welcome.json` | S -> C | Authoritative `v` and opaque resume credential in payload; echoes `id`. No `seq` (session-level, not per-room) |
| `session-resume-hello.json` | C -> S | Reconnect offer with the opaque credential and last observed room sequence |
| `session-resumed.json` | S -> C | Accepted reconnect with role and seat metadata; fresh room/game projections follow |
| `session-ping.json` / `session-pong.json` | both | Correlated transport heartbeat envelopes |
| `error.json` / `room-full-error.json` / `wrong-password-error.json` | S -> C | Correlated generic and room-entry errors with echoed `id` |
| `room-create.json` / `room-created.json` | both | Ordinary room creation request and host acknowledgement |
| `room-join-player.json` / `room-join-spectator.json` / `room-joined.json` | both | Player/spectator entry requests and correlated membership acknowledgement |
| `room-leave.json` / `room-left.json` | both | Explicit leave request and correlated acknowledgement |
| `room-kick.json` / `room-kicked.json` | both | Host kick request, correlated host reply, and terminal target notification |
| `room-disband.json` / `room-disbanded.json` | both | Host disband request and terminal room notification |
| `room-snapshot-owner.json` / `room-snapshot-opponent.json` | S -> C | Role-neutral waiting-room projections for different viewers |
| `room-create-playtest.json` / `room-created-playtest.json` / `room-snapshot-playtest.json` | both | Private one-seat Playtest creation and waiting-room projection |
| `room-list.json` / `room-listed.json` | both | Hub-local room discovery request and public join metadata without member or password data |
| `deck-select.json` | C -> S | Full private deck identity submitted to the trust server |
| `deck-selected.json` | S -> C | Correlated selection acknowledgement without deck identities |
| `player-ready.json` | C -> S | Player ready toggle |
| `player-ready-changed.json` | S -> C | Correlated ready acknowledgement |
| `room-snapshot-ready.json` | S -> C | Public deck-selected and ready state; no hidden deck identities |
| `match-load-required.json` | S -> C | Deduplicated printing keys for the active prefetch generation |
| `client-load-complete.json` | C -> S | Client reports that one load generation is complete |
| `client-load-completed.json` | S -> C | Correlated completion acknowledgement |
| `room-snapshot-loading.json` | S -> C | Public per-seat loading progress |
| `match-started.json` | S -> C | Automatic transition after every player completes loading |
| `game-snapshot-owner.json` | S -> C | Owner sees their seven private hand identities and only opponent counts |
| `game-snapshot-opponent.json` | S -> C | Opponent gets their own hand while Alice's hand identities remain absent |
| `rules-snapshot-owner.json` | S -> C | Normalized Forge projection with seat-mapped players and viewer-authorized card identities |
| `rules-prompt.json` / `rules-prompt-reveal.json` / `rules-prompt-scry.json` / `rules-prompt-damage-order.json` / `rules-prompt-damage-assignment.json` / `rules-prompt-replacement.json` / `rules-respond.json` / `rules-respond-scry.json` / `rules-respond-damage-order.json` / `rules-respond-damage-assignment.json` / `rules-responded.json` | both | Deciding-player-only normalized Forge choices, including private card disclosure, scry ordering, combat-damage assignment, and read-only replacement-effect context, stable response ids, and identity-free acknowledgements |
| `game-draw.json` / `game-drawn.json` | both | Bounded multi-card draw request and identity-free acknowledgement |
| `game-return-to-room.json` / `game-returned-to-room.json` | both | End completed-match review and restore the room waiting flow |
| `game-shuffle-library.json` / `game-library-shuffled.json` | both | Shuffle the acting player's hidden library with an identity-free acknowledgement |
| `game-mulligan.json` / `game-mulliganed.json` | both | Manual mulligan request and resulting public hand-size/count acknowledgement |
| `game-discard-hand.json` / `game-hand-discarded.json` | both | Server-random single-card or atomic whole-hand discard with an identity-free acknowledgement |
| `game-move-card.json` / `game-card-moved.json` | both | Move a card with explicit source/target seats; a remote public source uses the consent exchange below, while library destinations may use top/index/bottom placement |
| `game-public-zone-move-pending.json` / `game-public-zone-move-requested.json` / `game-respond-public-zone-move.json` / `game-public-zone-move-responded.json` | both | One-use source-player consent for an exact move out of another player's graveyard or exile |
| `game-arrange-battlefield.json` / `game-battlefield-arranged.json` | both | Atomically update normalized positions for existing permanents on the acting player's battlefield |
| `game-move-cards.json` / `game-cards-moved.json` | both | Atomic ordered/random battlefield multi-selection move |
| `game-move-library-cards.json` / `game-library-cards-moved.json` | both | Atomic movement of an exact private-library selection after authorized viewing |
| `game-set-tapped.json` / `game-tapped-set.json` | both | Toggle one controlled battlefield permanent's public tapped state |
| `game-set-response-status.json` / `game-response-status-set.json` | both | Set one player's public no-voice coordination status |
| `game-set-card-counter.json` / `game-card-counter-set.json` | both | Create or update one public number/ability counter on a controlled permanent |
| `game-snapshot-move-owner.json` | S -> C | Owner keeps remaining private hand identity and sees the moved public card |
| `game-snapshot-move-opponent.json` | S -> C | Opponent sees the public card and coordinates but not the remaining private hand |
| `game-reveal.json` / `game-revealed.json` | both | Explicit full-hand reveal request and identity-free acknowledgement |
| `game-recall-revealed.json` / `game-revealed-recalled.json` | both | Atomic return of the acting player's shared revealed cards to hidden hand |
| `game-dump-zone.json` / `game-zone-dumped.json` | both | Private own-library top-prefix request and requester-only identity response |
| `game-dump-zone-opponent.json` / `game-zone-dump-pending.json` / `game-zone-dump-requested.json` / `game-respond-zone-dump.json` / `game-zone-dump-responded.json` / `game-zone-dumped-opponent.json` | both | Consent-gated opponent-library request, target response, and requester-only approved dump |
| `game-search-library.json` / `game-library-searched.json` | both | Atomic multi-card library search with ordered/random movement and reveal-aware public logging |
| `game-search-library-opponent.json` / `game-library-searched-opponent.json` | both | Approved remote-library search into either the requester or source player's destination zone |
| `game-reorder-library.json` / `game-library-reordered.json` | both | Count-only acknowledgement for returning the exact viewed top prefix in a custom order |
| `game-resolve-library-view*.json` / `game-library-view-resolved.json` | both | Atomic top-X resolution using either the compatible selected/remainder form or one destination assignment per viewed card |
| `game-snapshot-shared.json` | S -> C | Stack and revealed cards are public with an authoritative owner seat |
| `game-set-phase.json` / `game-phase-set.json` | both | Active player changes the shared 11-step phase marker |
| `game-next-turn.json` / `game-turn-advanced.json` | both | Active player advances the turn and resets the marker to Untap |
| `game-play-land.json` / `game-land-played.json` | both | Atomic explicit hand-to-battlefield land play and public recorded count |
| `game-set-land-play-count.json` / `game-land-play-count-set.json` | both | Active-player correction of the current turn's public recorded land-play count |
| `game-set-counter.json` / `game-adjust-counter.json` / `game-rename-counter.json` / `game-counter-set*.json` | both | A player assigns life or adjusts/renames one of their seven public counter slots |
| `game-set-counter-count.json` / `game-counter-count-set.json` | both | A player chooses how many of their own public counter slots every client renders |
| `game-concede.json` / `game-conceded.json` | both | A seated player concedes and receives the public game outcome and series score |
| `game-set-card-face.json` / `game-card-face-set.json` | both | Owner selects one visible face of a multi-face battlefield card |
| `game-set-face-down.json` / `game-face-down-set.json` | both | Owner/controller toggles persistent battlefield redaction without echoing identity |
| `tournament-*.json` | both | Hub-local tournament discovery, registration, Swiss rounds, results, pairing rooms, and public standings |
| `limited-*.json` | both | Private draft picks, reconnectable pool/deck-building projection, and identity-free limited acknowledgements |
| `game-snapshot-face-down-owner.json` / `game-snapshot-face-down-spectator.json` | S -> C | Owner retains a face-down identity while uninformed viewers receive only public instance state |
| `game-declare-draw.json` / `game-draw-declared.json` | both | A no-winner game result with unchanged series score |
| `game-restart.json` / `game-restarted.json` | both | Host rebuilds the same game while preserving score and starting seat |
| `game-roll.json` / `game-rolled.json` | both | Public bounded server-generated dice results |
| `game-flip-coin.json` / `game-coin-flipped.json` | both | Public server-generated coin result |
| `game-random-select.json` / `game-random-selected.json` | both | Random selection from explicit public battlefield candidates |
| `game-snapshot-log-truncated.json` | S -> C | Bounded public log tail with an explicit first id and truncation marker |
| `game-say.json` / `game-said.json` | both | A public table-chat command and its identity-free, log-id acknowledgement |
| `game-snapshot-finished.json` | S -> C | Completed game projection with winner, conceding seat, score, and public log |
| `game-snapshot-departure.json` | S -> C | Remaining player projection after an opponent leaves an active match |
| `game-create-token.json` / `game-token-created.json` | both | Create an English-catalog token directly on the battlefield |
| `game-adjust-commander-tax.json` / `game-commander-tax-adjusted.json` | both | Per-card manual Commander tax control |
| `game-cast-commander.json` / `game-commander-cast.json` | both | Atomic command-zone cast and per-card cast-count update |
| `game-set-commander-damage.json` / `game-commander-damage-set.json` | both | Public physical-commander damage update with optional atomic life change |
| `game-snapshot-edh.json` | S -> C | Four public EDH seats, command zone, tax, elimination, and token state |
| `sideboard-move.json` / `sideboard-moved.json` | both | Move one registered printing between pending BO3 mainboard and sideboard |
| `sideboard-set-commander.json` / `sideboard-commander-set.json` | both | Change the next-game Duel Commander designation without changing the registered deck partition |
| `sideboard-ready.json` / `sideboard-ready-changed.json` | both | Lock or unlock one player's pending sideboard partition |
| `sideboard-completed.json` / `sideboard-completed-timeout.json` | S -> C | All-ready and deadline-timeout transitions to the next game |
| `game-snapshot-sideboard-owner.json` | S -> C | Owner-only pending deck partition plus public readiness/counts |
| `game-snapshot-sideboard-spectator.json` | S -> C | Public readiness/counts with all pending card identities redacted |
| `game-set-arrow.json` | C -> S | Set the acting seat's single public battlefield arrow |
| `game-arrow-set.json` | S -> C | Correlated arrow update acknowledgement |
| `game-set-attachment.json` | C -> S | Attach or detach one owner-controlled battlefield card |
| `game-attachment-set.json` | S -> C | Correlated attachment update acknowledgement |
| `game-snapshot-p7-owner.json` | S -> C | Owner sees their latest private draw plus public battlefield relations |
| `game-snapshot-p7-spectator.json` | S -> C | Spectator sees public arrows/attachments but no private draw |
| `replay-list.json` / `replay-listed.json` | both | Retained replay discovery with public match metadata |
| `replay-get.json` / `replay-loaded.json` | both | Load only the retained public log, never the operator archive's hidden state |

`room-snapshot-ready.json` pins the P3-A waiting-room privacy boundary: all
viewers receive only public `deckSelected`/`ready` flags, never the selected
deck identity. The paired `game-snapshot-*` fixtures pin the P3-C hidden-hand
boundary: a viewer receives their own hand identities, public counts for every
seat, and no opponent hand or library identities. The paired P4 move fixtures
also pin that a card becomes public, including its normalized battlefield
position, while the rest of the source hand remains redacted. Game snapshots
also carry the public `activeSeat` and `currentPhase` coordination state. The
`score` array is public match state; `result` is absent while a game is active
and immutable once it is finished. The finished fixture pins the 1v1 concede
outcome without exposing either player's hidden cards. The
shared-zone fixture pins that stack and explicit reveal identities are visible
to every viewer while `ownerSeat` controls who may continue moving them. The
library dump fixture is intentionally requester-only; it must never appear in
room fan-out, while a hidden search acknowledgement and public log omit the
selected card identity.

The P5 EDH fixture pins four simultaneous public seats, explicit elimination,
the command zone, dedicated commander tax, and token identity. The paired
sideboard snapshots pin the trust-server boundary: only the seated owner sees
their pending mainboard and sideboard identities; opponents and spectators see
aggregate counts and readiness only.

The P7 fixtures pin hub-local discovery and retained-log replay as public
projections. Room listings contain join metadata only, and replay loading
returns a public log rather than the full operator archive. Undo availability
is owner-only and never reveals the returned card identity; battlefield arrows
and attachments are public coordination state.
