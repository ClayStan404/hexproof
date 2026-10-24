# Networking notes — rooms, lobby, and server

Official nodes can opt into [one shared lobby and room placement service](official-cluster.md).
Clients choose an entry node automatically, discover rooms across healthy nodes,
and follow trusted, request-correlated transfers. Each game/event still has one
authoritative hub. Independent hubs retain the local behavior described below.

- Audience: owner + implementers  
- Language: English (durable)  
- Related: `product-brief.md`

## Compatibility policy and implementation status

The [protocol compatibility policy](protocol-compatibility.md) is implemented
in source as `hexproof.v2`. Client and hub application versions can differ;
communication protocols must match exactly. Legacy 3.0.0 clients use v1 and
need an update for v2 hubs. Read deployment state from the
[current handoff](development-handoff.md), not from protocol-source availability.

## Mental model

```text
Client  ──WebSocket──►  Room Server (hub)
                              │
                    ┌─────────┼─────────┐
                    ▼         ▼         ▼
                 Room A    Room B    Room C
                 (state)   (state)   (state)
```

- **Connect to server** = open a guest or optional official-account session to
  the hub. Display names are presentation, never proof of ownership; see
  [accounts.md](accounts.md) for shared official identity and recovery.
- **Protocol gate** = client and hub must speak the same exact communication
  protocol. Application versions remain visible release/diagnostic metadata,
  independently of admission. A mismatch is rejected before account binding,
  seat restoration or room access, and stops client reconnect retries. The
  Connect screen shows both protocols and distinguishes an older client from
  an older server. Update selection checks `compatibility.json` against release
  checksums; unavailable/mismatched metadata falls back to the official release
  page. An already-shipped v1 client cannot acquire this rule retroactively.
- **Create room** = hub allocates a room, applies settings, puts creator inside.  
- **Join room** = hub puts this connection into an existing room if id/password OK.  
- **Game table** = all seated players (and allowed spectators) receive room events/snapshots.
  Role-specific `game.snapshot` projections are required after a committed game
  command. If projection build fails, the hub fail-closes those members
  (unsolicited `internal_error`, then disconnect) so reconnect can resume.
  A full send buffer disconnects only the affected member; required snapshots
  are never silently dropped. A later projection/delivery failure does not
  roll back an already committed command or its successful reply.
- **Playtest** = a private one-seat room on the connected hub. It is not listed
  in room discovery and does not accept opponents or spectators.

The client bounds one incoming WebSocket frame/message to 8 MiB before JSON
parsing. Ordinary HTTP metadata responses are capped at 4 MiB, card images at
32 MiB, and health-probe responses at 64 KiB. The streamed official database
download keeps its separate manifest-declared compressed and expanded limits.
These limits fail closed without changing normal protocol or catalog behavior.

Incoming messages, parse errors, and end-of-transport notifications retain the
client transport generation through background JSON parsing. Starting another
connection invalidates deliveries from the previous transport, including its
queued disconnect; they cannot change the new session or cancel its handshake.
Within the current transport, the final message is applied before an unexpected
disconnect, preserving reconnect and command-correlation behavior. Explicit
cancellation also drops queued replies from the cancelled connection.

The **server is required** for online multiplayer. Operator-owned home hubs
can additionally accept the same game protocol through authenticated WebRTC,
with cloud relay fallback; see [home servers](home-servers.md). A direct route
still connects to the authoritative hub and preserves server-side privacy.

## Create room — typical implementation

1. Client (already connected) sends something like:  
   `room.create { name, format, deckFormat, maxSeats, playtest?, allowSpectators, spectatorsSeeHands, matchMode: bo1|bo3, password? }`
2. Server validates (limits, rate limits, max rooms).  
3. Server creates room state, generates **room id** (short code, e.g. 6–8 chars).  
4. Server assigns creator a seat / host flag.  
5. Server replies: `room.created { roomId, settings… }` and starts sending that client room snapshots/events.

**Password:** store a hash or compare on join; never broadcast the password to other clients.

`playtest: true` forces one seat, BO1, no spectators, and no password. The
format values are `modern`, `duel`, and `edh`. The UI presents them as Generic
1v1, Duel Commander, and Commander. `modern` and `duel` select two seats in
multiplayer and start at 20 life; `duel` additionally enables command zones and
manual commander tax. `edh` provides up to four seats, may start with three or
four seated players, and starts at 40 life. No mode enforces a card pool or
rules legality.

**Room name vs room id:**

| | Room name | Room id |
|--|-----------|---------|
| Purpose | Display (“Friday EDH”) | Join key (“K7P2QX”) |
| Unique | Soft (can collide) | Hard unique on that server |
| Share | Optional | **What people copy to friends** |

## Join room — typical implementation

1. Client sends: `room.join { roomId, password?, asSpectator? }`  
2. Server checks room exists, not full, password, spectator flag.  
3. Server assigns seat or spectator role.  
4. Client receives a role-specific snapshot; hidden identities are included
   only where `privacy.md` authorizes them.

## Do you need a “game lobby” (room list)?

| Approach | How players meet | v1 fit |
|----------|------------------|--------|
| **A. Room code** | Host creates → shares id in Discord/QQ → guest types id | Supported |
| **B. Server room list** | Connected users see rooms on *this* hub, click join/watch | Supported in P7 |
| **C. Global matchmaking** | Auto-pair strangers, ranks | **Out of scope** (product non-goal) |

**Current product behavior:**

1. Room code remains the direct invitation path.
2. The connected-hub browser shows room id/name, format, series, player and
   spectator counts, phase, joinability, and a password lock flag. A locked
   room routes through the normal password form.
3. Listings never contain the password or hash, member identities, deck
   selection, connection ids, or game state.
4. Official cluster discovery is defined in `official-cluster.md`. Ranking and
   automatic player pairing remain out of scope.

Discovery requires a connection to a hub. An official cluster aggregates its
configured nodes; a standalone hub lists only its own public rooms.

## What the server must do (minimum)

| Responsibility | Notes |
|----------------|--------|
| Accept WebSocket connections | Guest names or optional shared official accounts (`accounts.md`); require exact communication-protocol equality before welcome; transport ping/pong heartbeats keep idle sessions alive through tunnels and detect stale peers |
| Multi-room hub | Many rooms on one process (the owner-operated cloud hub) |
| Create / join / leave / destroy empty rooms | TTL for abandoned rooms |
| Enforce seat caps & spectator flag | Playtest 1 with no spectators; multiplayer 2/4 with **max 8 spectators** when allowed |
| Optional password check | On join |
| Room state | Seats, life, zones, and cards; the trusted server may hold hidden identities |
| Fan-out events | Project per role (owner vs opponent vs spectator) |
| Disconnect policy | Intentional leave → release membership now; network drop → **hold seat 3 min** for reconnect. Once a match has started, releasing a player membership forfeits the whole Generic 1v1/Duel Commander match or eliminates that EDH seat so turn ownership never points permanently at an empty seat. A reconnect that races the server's stale-transport detection retains and retries the original credential instead of joining as a fresh session. The client persists active player credentials across application restarts, while spectator credentials remain memory-only for transient transport recovery so reopening the client never resumes an old observation session. |
| Limits | Max rooms, max tournaments, max connections, room/tournament create rates per IP, closed-tournament TTL, and abandoned registration/running-tournament TTLs (anti-abuse on public hub) |

P7 adds the public room-list query. Durable live-room persistence across a
server process restart remains out of scope. P6 reconnect credentials and
ended-room retention are documented in `self-hosting.md`.

Client still owns: UI, deck import, local image cache, rendering.

## Connected-hub tournaments

Tournament management is an additional hub-local registry beside rooms. It is
not global matchmaking and does not introduce accounts. A tournament-local
credential lets an organizer or participant re-enter one event, while public
listings expose only event metadata and counts.
Credential re-entry moves that role to the newest transport; tournament
mutations always verify that current binding. A pairing room also records the
server-private participant identity on each seat so one credential cannot
occupy both player seats through two connections.

The lifecycle is:

```text
list/create tournament → register → check in → Swiss pairing
    → open private pairing room → report + confirm result
    → standings → next round → final standings
```

Pairing rooms reuse the existing trust-server tabletop and are hidden from the
ordinary room browser. Seated players enter through `tournament.open_match`;
generic `room.join` as a player is rejected with `tournament_forbidden`.
Spectators may enter from the event view or use the pairing room code with
`asSpectator: true`, subject to the event's active-match restrictions and the
usual spectator limits/redaction. Tournament registration survives leaving a
pairing room. Detailed scoring, tiebreakers, permissions, and spectator
eligibility are defined in `tournaments.md` and `privacy.md`.

## Suggested v1 UX copy (for implementers)

**Create room**

- Room name (text; recommend including the exact format, such as Modern or Pioneer)
- Table mode: Generic 1v1 (2) | Duel Commander (2) | Commander (3–4) [wire values `modern` | `duel` | `edh`]
- Spectators: checkbox  
- Series: EDH shows BO1 only; Generic 1v1 and Duel Commander show BO1 | BO3
- Password: optional  
- Button: Create → show **Room id** + “Copy” + enter **room waiting**

**Join room** (complete v1 form)

- Room id  
- Role: **Player** | **Spectator**  
- Password (if needed)  
- Display name = session name from **Connect to server** (not re-entered on join)  
- Server enforces multiplayer max players (2/4); spectators **max 8** when allowed
- No other fields in v1  

**Room waiting**

- Room id, settings, player slots, spectator list  
- Select ready deck / open deck library (overlay; stay in room)  
- Players **Ready** only → load all decks → **auto-start** (see `match-flow.md`)  
- Playtest has one already-filled seat; selecting a deck and Ready follows the
  same load/start path.

**Browse hub rooms**

- Available only after connecting to a specific hub.
- Refreshes the current hub's public room projection.
- Join and Watch buttons reflect server-authoritative joinability.
- The list can be filtered (joinable/watchable, waiting/in-game, password,
  table type), searched by name or room code, and sorted without changing the
  public projection.
- This screen is not an account-backed or global matchmaking lobby.

## Owner decisions (summary)

1. After create/join: **room waiting** first.  
2. Join: player/spectator; multiplayer seat cap is 2 for Generic 1v1/Duel
   Commander or 4 for EDH. EDH can auto-start once three seated players are
   Ready. Playtest is private and not joinable.
3. Multi-screen: deck library covers room.  
4. BO3 inter-game gate is 5 min. Generic 1v1 may edit main/SB; Duel Commander
   keeps its registered deck unchanged.
5. Full flow: `match-flow.md`.  
