# Hexproof tournament management

- Status: **Implemented specification**
- Scope: connected-hub, individual 1v1 constructed tournaments
- Rules reference: *Magic: The Gathering Tournament Rules*, effective
  2026-02-27, especially sections 2.1, 3.1, 10.1–10.4 and appendices B, C, E

## Product boundary

Hexproof manages registration, check-in, pairings, result confirmation,
rounds, and standings. Events default to manual tabletop and may select
server-hosted Forge for their 1v1 matches. This immutable `rulesMode` appears
in discovery and event snapshots and is inherited by every paired room.
Unavailable Forge prevents creation/start or creating a new match table,
without silently changing its rules mode. Existing tables remain accessible
during a launch backoff. Players and tournament officials remain responsible
for deck legality, penalties and end-of-round procedure; in manual mode they
also resolve game rules. Hexproof tournaments are not automatically DCI/WPN
sanctioned and do not require a Wizards Account.

Tournaments live on one connected hub. They are not global matchmaking or a
ladder. Optional [official accounts](accounts.md) can own existing organizer
and participant rights across devices; the event itself stays on its hub.
For guests, a server-generated organizer or participant
credential identifies a user only inside one tournament and is stored locally
by the client for re-entry. Public tournament listings never expose those
credentials, decklists, connection identifiers, or IP addresses.
Re-entering with a credential transfers that tournament role to the newest
connection. Every mutation revalidates the current connection binding, so an
older transport cannot retain organizer or participant authority.
Account claims also invalidate anonymous use of those credentials and old guest
connections. An account cannot claim two participant seats in the same event.
Explicit spectator entry does not restore private participant projections.

The event browser keeps code entry, history, refresh, and creation actions
inside the window at supported interface scales. Actions wrap onto additional
rows when their combined width exceeds the available toolbar width.

The event lobby keeps pairings, standings, and participant actions within the
available width. Compact windows place event management and chat in a modal
side panel with separate tabs and scrollable content. During private drafting
or deck construction, this panel also leaves the card workspace unobstructed
until explicitly opened.

Set Sealed, Set Draft, and tournament-mode Cube Draft use this Swiss coordinator
after their private pool and deck-building stages. Ordinary Cube also offers a
separate free-play room, and Commander Cube is free-play-only: neither appears
in active or historical Events. Those room flows reuse the internal `casual`
coordinator for private pools and consent-based table groups, not Swiss pairings,
rounds, or standings. Their generation, construction, multiplayer table rules,
and privacy boundaries are defined in [limited-events.md](limited-events.md).

## First release scope

The first release supports individual 1v1 Swiss constructed tournaments:

1. An organizer creates a tournament and selects Standard, Pioneer, Modern,
   Legacy, Vintage, Pauper, or Duel Commander, plus its name, BO 1/BO 3 match
   structure, gameplay rules, round time, and capacity.
2. Players register, then check in. Registration remains editable until the
   organizer starts the event.
3. Starting the event locks the round count and includes checked-in players.
   Unchecked registered players remain listed but are not paired.
4. Each round publishes numbered tables and a bye when the active player count
   is odd. A pairing can open a private Hexproof 1v1 room that is hidden from
   the ordinary room browser. Paired players enter that room through
   `tournament.open_match`; viewers may join only as spectators from the event
   view or with the room code.
5. Either player reports game wins and drawn games. The opponent confirms or
   rejects the report. The organizer may correct and confirm a result.
6. Once every non-bye pairing is confirmed, standings for the round are final
   and the organizer may publish the next round.
7. A player may drop; dropped players remain in historical standings and are
   excluded from later pairings.
8. After the announced Swiss rounds, the event is complete and final standings
   remain available while the tournament exists on the hub. Completed and
   cancelled events are retained for 24 hours by default. Connected history
   viewers do not extend that retention. Operators may configure this TTL.
   Registration and running events without an online authenticated organizer or
   participant expire after a five-minute reconnect grace by default. The grace
   begins when the last such person leaves or disconnects, independently of chat,
   ordinary viewers, and subsequent list requests. A returning organizer or
   participant resets it. Active players in private pairing rooms also keep the
   event alive without needing to remain in its lobby; existing room reconnect
   holds remain valid until their normal expiry. Spectator-only rooms do not
   prevent cleanup. An organizer explicitly leaving an empty registration event
   with no registered participants removes it immediately; leaving an event
   with remaining participants does not remove their registration or card pools.
   Operators may configure the registration and running grace periods through
   `-tournament-inactive-ttl` and `-tournament-abandoned-ttl`; closed history uses
   `-tournament-closed-ttl`. Per-event timers reclaim unattended events even when
   nobody subsequently opens the event browser. List, create, and enter also
   apply eviction before serving the request, so a known ID cannot resurrect an
   expired empty event. Cleanup notifies remaining viewers and closes abandoned
   spectator-only tables; genuine pairing players and their existing reconnect
   holds are protected even when the associated event is already terminal.
   The client keeps registration
   and running events in the default event browser; completed and cancelled
   events appear only in the separate **Event history** dialog. The last
   deck each participant selected in a private pairing room is then published
   to every tournament viewer; it is never included in registration or
   running-event projections.

The public hub bounds the registry to 64 tournaments by default and accepts at
most three tournament creations per client IP per minute. Operators may adjust
both limits; reaching the capacity rejects new events without affecting running
tournaments. Abandoned registration and running events are evicted so a vanished
organizer cannot permanently fill those 64 slots.

Single-elimination playoffs, pre-round formal decklist submission and deck
checks, penalties, judge calls, prizes, scheduled registration, and
cross-process live-event recovery are later extensions. The data model
reserves a stage field so a Top 4/Top 8 cut can be added without changing
Swiss history.

## Official scoring and standings

Hexproof follows the current Magic Tournament Rules for match and game points:

- match win: 3 match points;
- match draw: 1 match point to each player;
- match loss: 0 match points;
- game win: 3 game points;
- drawn game: 1 game point to each player;
- game loss or unplayed game: 0 game points;
- bye: a 2–0 match win, 3 match points, and 6 game points.

Swiss standings sort by:

1. match points;
2. opponents' match-win percentage (OMW%);
3. game-win percentage (GW%);
4. opponents' game-win percentage (OGW%).

Match-win and game-win percentages use a 0.33 floor for tiebreaker
calculations. Byes are excluded from OMW% and OGW% opponent averages. If every
official tiebreaker is equal, Hexproof uses the server's stable initial player
order only to make the displayed order deterministic; this extra ordering has
no competitive score value.

## Round defaults

The standard client leaves the round count to the server, based on checked-in
attendance. It does not offer a round-count override. Once started,
the announced round count cannot change. Hexproof uses the MTR Appendix E
constructed-event recommendation where it directly applies; a two-player event
schedules a single head-to-head round, and larger small events use a
three-round minimum:

| Checked-in players | Default Swiss rounds |
|---:|---:|
| 2 | 1 |
| 3–8 | 3 |
| 9–32 | 5 |
| 33–64 | 6 |
| 65–128 | 7 |
| 129–226 | 8 |
| 227–409 | 9 |
| 410+ | 10 |

The default constructed round time is 50 minutes. Hexproof shows that round
timer but does not automatically decide unfinished manual games from it.

Forge two-player tournaments offer a 25-minute action clock per player for the
whole match. It defaults to on for constructed events and off for Limited;
the organizer can choose either setting at creation. The clock runs while a
playable decision is waiting for that player. Reaching zero loses the match
and records the result immediately. See [action-clock rules](action-clock.md)
for BO3 accumulation, pauses, recovery, and creation defaults.

## Pairing policy

The MTR requires Swiss pairing but does not publish the implementation of
Wizards EventLink's pairing engine. Hexproof therefore implements the
observable policy rather than claiming byte-for-byte EventLink parity:

- constructed and Sealed round one use a server-randomized initial order;
- Set Draft and Swiss Cube Draft round one pair opposite seats from the
  original randomized draft circle (1–5, 2–6, 3–7, 4–8 in an eight-player pod).
  After the usual bye assignment or a withdrawal, available exact opposite
  pairs take priority, followed by the greatest total circular seat distance.
  Odd pods use that distance rule because they have no exact opposite seat.
  This is Hexproof's opening-round policy; MTR sections 7.6 and 10.4 require
  pod-based Swiss play but do not mandate opposite seats in Swiss round one;
- later rounds prioritize equal match points;
- repeat opponents are avoided whenever a non-repeat pairing is available;
- a necessary score-group float is kept as small as possible;
- an odd field gives the lowest-ranked eligible active player a bye, preferring
  a player who has not already received one;
- playoff seeding can later use final Swiss rank (1 vs N, 2 vs N-1, and so on).

Pairing generation is deterministic after the tournament's secret initial
seed and recorded state are fixed. Historical pairings and confirmed results
are immutable except for an explicit organizer correction while the event is
running, which is marked on the corrected result. Completed and cancelled
events do not expose result-editing actions; an open score editor closes when
the event stops running.

## Roles and permissions

| Role | Permissions |
|---|---|
| Organizer | Start/cancel event, start next round, correct results, view all public tournament state |
| Participant | Check in, open their current match room, report/confirm/reject their match result, drop |
| Viewer | View public event details, pairings, and published standings; spectate open pairing rooms; register while registration is open |

The organizer may also register as a participant at Regular-style community
events, but organizer and participant credentials remain distinct.

These organizer-only registration rules apply to Swiss events, not free-play
Cube rooms: a Cube room creator is its first seated player automatically. In
Commander Cube, that player cannot pair other people without their consent;
each two-to-four-player invitation requires every selected participant to
accept before anyone opens the shared table.

Creating an event does not register its organizer. An organizing-only user
does not consume capacity, receive a Limited pool, or enter pairings. The event
desk labels registration as an optional choice for organizers; withdrawing
their registration before the start preserves organizer authority. Registration
shows the player list, names, online status, and check-in status by default.
During draft and deck building, non-competing viewers see public player
progress instead of private pick or deck controls.

## Event chat

Every session currently viewing an event may send public text to that event,
including an organizing-only user, a participant, and an ordinary viewer.
Chat is available in a sidebar tab throughout the event lifecycle and remains
separate from pairing-room chat. Messages never reveal card identities,
credentials, or connection details automatically.

- `tournament.chat.send` includes the current tournament ID and text; the
  server validates membership and any organizer/participant credential binding.
- `tournament.chat.message` carries server-authored display name, event-local
  sequence, timestamp, and text. Only the sender receives the request ID.
- Entering/re-entering an event receives `tournament.chat.history` containing
  at most the latest 100 messages. History lives only with the in-memory event
  and is discarded on eviction or server restart.
- Messages contain 1–500 Unicode characters after trimming; control characters
  other than line breaks are rejected. Each IP may send at most 30 event-chat
  messages per minute. Chat is rendered as plain text.
- Clients discard messages for another event, deduplicate by sequence, retain
  at most 100 messages, and clear unsent text when switching event identity.
- New messages follow the bottom while the viewer is reading the latest chat.
  Scrolling or dragging the scrollbar into older history preserves a retained
  visible message and its offset when messages arrive or the oldest retained message
  expires. Returning to the bottom resumes following; entering another event
  starts at that event's latest messages.

## Tournament-local room integration

The participant action shows **Open match** while the pairing has no room ID
(omitted or empty), and **Return to match** once a nonempty room ID is present.
Both labels send the pairing-specific tournament open command; a player does
not claim a private tournament seat through generic room-code joining.

A current pairing's **Open match** action creates or joins one ordinary
two-seat room:

- Duel Commander uses the existing `duel` table mode;
- every other 1v1 constructed format uses the existing generic `modern` wire
  mode, which deliberately does not enforce a Modern card pool;
- the tournament's BO setting is copied to the room;
- the room uses background card loading, allows at most the ordinary spectator
  cap, and always keeps spectator hand visibility disabled;
- the room is omitted from the ordinary hub room list;
- its room code accepts generic `room.join` only with `asSpectator: true`, so it
  can never be used to claim a tournament player seat;
- every event viewer receives a **Watch match** action after the pairing room
  exists; the same room code may be shared with somebody who has not entered
  the event view;
- each tournament participant identity may occupy at most one player seat, even
  if its credential was rebound to another connection;
- leaving or completing the room does not remove tournament registration.

The confirmed tournament result is authoritative for standings. After a pairing
room match finishes, the client may prefill **Report** from that tabletop
score, including the match's drawn-game count. Forge captures the same
suggestion as manual tables only for a live participant after the entire match
finishes, never during BO3 sideboarding or from spectator/replay views. Physical
table seats are mapped to the pairing's player order before prefilling.
The suggestion stays associated
with the participant's current event, round and pairing after the table closes
and its room ID disappears from later event snapshots. A changed participant
pairing, another event/round or a replacement live room invalidates it. Published
reported scores and corrections take precedence over a local suggestion.
Prefill never submits a result; participants still confirm and the organizer
can still correct.

Commander Cube tables are a separate free-play integration, not an extension
of the two-player Swiss result model. Their locked `commander_limited` decks
use EDH BO1 tables, 40 life, and the exact designated command-zone printings.
Every invited seat must join and ready before the game starts. A player,
including the table host, leaving an active game is eliminated while the
remaining players continue; returning to that game permits spectating only.
After the game ends, returning to the Cube room retires the table and releases
the whole group for another game. This table departure is distinct from the
Cube host explicitly leaving and closing the entire draft room.

Pairing rooms carry the tournament's named deck format, so the client offers
only matching locally validated decks. This is an advisory client gate rather
than an organizer-certified deck check. The server records the deck each participant selects in a constructed pairing
room. That deck can still be changed before the first match starts. From round
two onward the recorded deck is applied automatically and a different selection
is rejected. The waiting room shows the player's own registered deck name beside
the locked-deck status, including after reconnect or a fresh client session.
This recipient-private name is restored from `room.snapshot.ownDeckName`;
it does not publish an opponent's name or the registered cards. Sideboarding during a best-of-three match still uses that
registered deck. Recorded decklists remain private while the
event is registering or running and are added to participant projections only
after the event reaches `completed`. Cancelled events do not publish them.
Completed viewers can browse the recorded mainboard and sideboard as grouped
card art and export the same importable deck-list text used by the local
library. The export is a local copy; it does not change the published event
record.
