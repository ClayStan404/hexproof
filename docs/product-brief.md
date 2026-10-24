# Hexproof — Product Brief

- **Product name: Hexproof**
- Status: **Active owner requirements**
- Spec directory: **`docs/`** (this folder, under the Hexproof repo root)
- Implementation: **same repo root** — code under `apps/` etc.; specs stay in `docs/`

## One-liner

**Hexproof** is a **native desktop** multiplayer tabletop for Magic: The Gathering online, with a free-form manual table and an optional externally hosted Forge rules mode for enforced games.

## Current delivery scope — 2026-09-27

Forge supports 1v1 games, including Duel Commander, and server-hosted Commander/EDH
with two, three or four participants. EDH remains 40-life BO1, including at two
seats. Its Forge presentation is independent of the manual table: opposed halves
for two, two opponents above the viewer for three, and four equal panels for four.
The [rules-engine specification](rules-engine.md) defines the supported scope
and table presentation.

## Product positioning (core)

**Hexproof = a focused, modern, smooth native MTG tabletop with manual and optional rules-enforced play, plus first-class Chinese and English support.**

| Principle | Meaning |
|-----------|---------|
| **Product-owned semantics** | Rooms, zones, phases, stack, library search, tokens, counters, and hidden information follow Hexproof's English specifications and protocol invariants. |
| **Focused interaction** | Keep the product surface compact while supporting the manual actions players need at a real tabletop. |
| **Experience** | **Modern visuals**; **fluid drag/ops**; **Chinese-first** comfort (UI language, Scryfall/MTGCH names and art). |
| **Modes, not compromise** | Manual rooms remain free-form. Forge rooms are separately authoritative and never mix partial automation into the manual reducer. |
| **Not us** | Matchmaking/ladder, trading economy, web/Electron shell. Connected-hub tournament organization and optional official-server accounts are supported workflows. |

Implementer rule of thumb:

```text
Unsure about gameplay/room behavior → check English specs and protocol invariants → ask the owner if still undefined
Presentation and feel → modern desktop polish from this brief
Card art → local cache first; Automatic/Scryfall/MTGCH network priority with provider fallback
```

**Owner-only (do not use when coding):** `产品说明.md`.

## Goals

| Goal | Meaning |
|------|---------|
| Assisted multiplayer | Host/join manual rooms with a shared public board, authoritative turn/phase state, and explicit combat/status signals; players resolve card text and unusual interactions themselves. |
| Rules-enforced multiplayer | Host/join optional Forge rooms in which the server-side engine owns legal actions, priority, stack resolution, triggers, and state-based actions. |
| Solo playtest | A connected player can open a private one-seat Generic 1v1, Duel Commander, or Commander table with no opponent or spectators. |
| Online play | Default connection to the **owner-operated cloud hub**; others may **self-host** room servers. |
| Real decks | Deck library management; download card metadata and art; start games with real lists. |
| Formats (v1) | Table behavior remains **Generic 1v1**, **Duel Commander**, or **Commander/EDH**. Deck construction is selected separately as Custom, Standard, Pioneer, Modern, Legacy, Vintage, Pauper, Duel Commander, or Commander; see `deck-formats.md`. |
| Seats (v1) | **1** private Playtest seat, or **2**/**4** multiplayer seats; spectators are multiplayer-only. |
| Experience | **Focused, modern, and fluid native tabletop interaction**. |
| Reference | Product behavior is defined by the English specifications and versioned protocol. |
| Locales | **Chinese + English** UI from v1 (Chinese-friendly). |
| Platforms (v1) | **Linux, Windows, and macOS** shippable builds. |
| Organized play | A connected hub may host individual 1v1 Swiss tournaments with guest credentials or optional official-account recovery, registration, pairings, confirmed results, and official-style standings. See `tournaments.md` and `accounts.md`. |

## Non-goals

- Reimplementing Magic rules inside QML, the Go manual-room reducer, or a new
  Hexproof-specific card scripting language. Rules-enforced rooms delegate this
  responsibility to Forge through the boundary in `rules-engine.md`.
- Automatic player matchmaking, ladder/ranking, or a directory spanning
  unrelated operators. Optional [official accounts](accounts.md) and the
  [unified official lobby](official-cluster.md) are supported; independent hubs
  retain local discovery.
- Trading / collection economy (MTGO-style).
- Browser / Electron / WebView client (native desktop only).
- Cryptographic privacy against a **trusted** server operator (see `privacy.md`).

## Networking (v1)

```text
Default: owner-operated public multi-room hubs (room codes)
Client: choose a named public hub or enter a locally saved custom ws/wss endpoint
Discovery: HTTPS catalog, last-known-good cache, bundled fallback
Development: environment overrides may point named entries at a test hub
```

No requirement that every player runs a server for normal play.

## Pre-table (v1 must-have)

1. **Deck library** — import/manage decklists (see below)  
2. **Card data + images** — download/cache enough to play with real cards  
3. **Rooms** — create/join and play a normal game  

Placeholder-only formal play is not the product path.

## Deck library

Available from main menu **without** a server connection.

### List

- Show **imported decks** (name, format, main/SB counts, ready status as needed).  
- **Filter by deck format** (All plus every supported format in `deck-formats.md`).
- **Double-click** a deck → **deck editor**.  
- Support delete, import, and export entry points.

### Import

- **Paste** a decklist copied from elsewhere; **parse and import**.  
- Support common plain-text / Moxfield-style lists.  
- Associate both a **table mode** and a **deck format**. Named formats receive
  local catalog-backed advisory validation; Custom remains unrestricted.

### Deck editor

| Feature | v1 behavior |
|---------|-------------|
| Layout by **card category** | Spread main deck by type (creatures, spells, lands, and other useful categories) |
| **Sideboard** | Separate sideboard region |
| **Drag main ↔ sideboard** | Rebalance main/SB only |
| **Search bar (always on editor)** | Search the full local metadata DB by English or Chinese name; the large popup also filters by type, set, printing language, color identity, rarity, and every format legality exposed by the current Scryfall catalog. Filters may be used without a name and never enforce deck legality. If the DB is missing, prompt a Default Cards download. |
| **Add from search** | Select hit → main/SB + download art for **current language** |
| Art | Cached images; local art first, then the player's preferred Scryfall/MTGCH source with automatic provider fallback |

Named-format validation blocks confirmed structural and copy-limit violations.
Card-pool violations also block formats other than Commander/EDH, where
unresolved, banned, and not-yet-legal cards remain visible advisory warnings so
variants and agreed house rules stay playable. Commander color-identity
mismatches are grouped advisory warnings with per-card details and never
prevent room selection.

Save writes back to the library. If opened as overlay from a room, closing returns to the same room.

### Full card database + language

- Deck editor always shows a **search bar**.  
- User **downloads/updates** one local searchable catalog: Hexproof's
  compressed, prebuilt **Default Cards** SQLite database, preserving all
  printing and collector identities plus a compact Simplified Chinese
  printing index. Manifest sizes and SHA-256 values are verified before atomic
  installation. Settings shows installed/latest build dates and schema versions.
  Normal clients download only this official prebuilt package; an unavailable
  release keeps the installed database and never triggers an upstream rebuild.
- Metadata only in bulk; **images on demand**. Card DB download is **in-client** (no separate Oracle app).  
- **Settings → Language & cards:** **Chinese** or **English**.
- **Settings → Language & cards → preferred card-art source:** **Automatic** (default),
  **Scryfall**, or **MTGCH**. Automatic prefers MTGCH for Chinese cards and
  Scryfall for English cards. Local compatible art remains first and the
  other network provider remains an automatic fallback.
  - Chinese keeps Chinese art ahead of English art. Scryfall-first uses exact
    and same-Oracle Scryfall zhs before MTGCH zhs; MTGCH-first tries MTGCH zhs
    before those Scryfall candidates.
  - English tries the selected provider's English art before the other
    provider.
- Selecting a search hit: add to deck + download art for **current language preference**.

### Operation audio

- **Settings → Audio** provides persistent mute, a 0–100% effects volume,
  and preview buttons for all 15 operation cues. Default: enabled at 35%.
  Both manual and Forge table settings link to this page without leaving the
  current match; Back returns to the table.
- The temporary sound audition catalog allows choosing replacement resources.
  Each explicit preview stops existing effects and can immediately replay the
  same cue, while respecting effects mute and volume. It does not change music
  settings. `AudioSettings.soundPreviewEnabled` can hide the catalog after the
  replacement pack is finalized without disabling normal operation sounds.
- Manual and Forge operations use brief paper/card, combat, and magic cues.
  Sound is feedback for explicit local decisions, not authoritative evidence
  that the server accepted an action. Normal acknowledgments do not replay it.
- Hover, pointer movement, and automatic passes are silent. Repeated sounds
  are throttled and simultaneous playback is bounded.
- Background music loops from application startup until exit, including menus,
  waiting rooms, settings, and manual or Forge matches. Saved preferences are
  applied before playback starts. Music has independent persistent mute,
  volume, and track selection in **Settings → Audio**, defaulting to enabled
  at 20% with Gitana. Gitana, BGM 2, and BGM 3 are available in the selector. Muting or
  setting zero volume stops music immediately; unavailable audio never blocks
  gameplay. Navigation, entering or leaving a match, and reconnects do not
  interrupt or restart the current track.
- Operation sounds use only the viewer's permitted state. Initial snapshots and
  reconnects establish a silent baseline. Missing devices or unready sounds
  never delay gameplay or queue sounds for later playback.
- The sound pack is bundled offline; preview and playback require no account
  or network access. Sources and licenses are documented with the assets.

### Application and database updates

- Startup checks are asynchronous and rate-limited to once per 24 hours;
  Settings retains explicit application and database check actions.
- Application discovery accepts only published, non-prerelease GitHub Releases
  named `vMAJOR.MINOR.PATCH`. It prefers the GitHub Releases API, then falls
  back to the public `github.com` latest-download checksums when that API is
  rate-limited or unreachable. It selects the exact Windows x64, Linux x86_64,
  macOS arm64, or macOS x86_64 portable archive for the running build. A failed
  live check may keep the last verified release as cached metadata; it does not
  present that cache as a current successful latest-version result.
- The client downloads the selected archive in-process, verifies its entry in
  the Release `SHA256SUMS` and, when GitHub reports a size, that declared
  size, and only then offers its download directory. The user exits Hexproof
  and replaces the portable application; this phase does not overwrite a
  running executable or app bundle.
- A protocol-mismatch update action verifies the candidate release's
  `compatibility.json` against the server's required game protocol before
  offering it. The ordinary update check compares semantic versions against
  the latest stable release; matching application versions do not prove
  protocol compatibility.
- Database updates remain independent of the application version: the stable
  `card-data` manifest determines the latest build timestamp and schema, and a
  confirmed update installs the verified SQLite file atomically.

### Card art / metadata download timing (owner direction)

Server syncs **card identity and table state**, not image bytes. Each client keeps a **local** art/metadata cache.

| When | What |
|------|------|
| **On text/file import** | Persist pasted text or a selected local deck-list file through the same parser. Do **not** bulk-download art. |
| **On Cache art** | Download missing metadata + images for the current deck (editor) or all library decks (library). Progress/errors OK. |
| **On search-add / printing change** | Download that one card's exact art. |
| **On Ready / pre-game load** | Use the room creator's policy: either show a blocking **loading** UI until every player has all match art, or enter immediately and prefetch in the background. Both receive the aggregate printing-key set for seated players' selected decks. |
| **In game** | Render from local cache. In background mode, prioritize cards currently visible to the viewer while the remaining match art continues downloading. |

Notes:

- Exact printing cache hits are always reused. A default-on Settings option also
  lets Cache art and match prefetch reuse an already-cached printing of the same
  Oracle card, face, and image language when the requested printing is absent.
  This substitutes image bytes only; synchronized card identity remains the
  requested printing. An explicit printing choice in the deck editor still
  downloads that exact printing.
- Prefetch uses **deck composition** so everyone can display public (and their own) cards with art; it does **not** mean revealing hand order to opponents.  
- Hidden-info policy unchanged: projections still hide unauthorized hand identities.  
- Do not make the room server a full card-image CDN for v1.

## Main menu (first screen after launch)

Entries:

| Entry | Behavior |
|-------|----------|
| **Connect to server** | Required before create/join |
| **Create room** | **Disabled (greyed out)** until connected |
| **Playtest** | **Disabled until connected**; creates a private one-seat table |
| **Join room** | **Disabled (greyed out)** until connected |
| **Events** | Browse and create constructed, Set Sealed, and Set Draft tournaments; disabled until connected or while in a room |
| **Pack simulator** | Open installed set products locally; always available, including offline or while in a room |
| **Deck library** | Always available (local; no server required) |
| **Sponsors & thanks** | Always available; shows the cached online sponsor list and optional profile links |
| **Announcements** | Always available; shows current and historical announcements with persistent unread state |
| **Quit** | Exit application |

Set Sealed and Set Draft share **Events → Create tournament**, without a
duplicate Limited-play entry on the main menu. Pack simulator replaces the
former Replays button beside Browse hub, without inheriting its connection or
room guard. There is no duplicate simulator entry in Settings. Cube Draft keeps
its **Create room → Cube** entry.

The client no longer offers a replay browser, log-timeline viewer, or replay
shortcuts. Live game logs and chat remain supported; removing the client feature
does not delete server archives or change the privacy-filtered compatibility API.

The menu panel keeps the heading **Start playing** both offline and connected.
The connection introduction appears only offline; once connected, the top-right
identity/server status is sufficient and no repeated welcome sentence is shown.

The sponsor acknowledgement is shown at startup when the local profile has not
acknowledged the running application version or has unacknowledged sponsor IDs.
Both triggers share one popup, offered at most once per launch, showing the
current roster and highlighting only new supporters. Dismissal (including Escape
or clicking outside) or opening the full list acknowledges the version and only
the IDs captured when that popup opened. Each new application version therefore
receives one acknowledgement even when the roster is unchanged; ordinary roster
edits do not repeat it. An empty roster opens no popup or version acknowledgement.
The permanent main-menu entry remains available offline.
Both the announcement and full list group sponsors from highest to lowest:
**Omniscience**, **Dockside Extortionist**, and **Ragavan, Nimble Pilferer**.
Tier assignments are operator-managed presentation data, not account entitlements or
gameplay privileges. Each sponsor appears once with a locally cached avatar, display
name, and optional profile link; an empty tier keeps a compact placeholder.
Sponsors may also have a localized introduction below their identity row in
both lists. The text wraps across the card width, with the profile button below
the introduction on narrow layouts.
An explicitly featured supporter keeps their assigned tier and receives a
larger avatar, a gold frame with a slow decorative glow, and a localized special
thanks label in both lists. The effect does not move content and pauses while
the list is hidden or its window is inactive.
New sponsors received after the startup popup remain pending for the next
launch. Tier changes do not trigger another acknowledgement. Successful online
roster snapshots replace the local list: removed sponsors and unreferenced
cached avatars are deleted, while failed refreshes retain the previous data.
Announcements retain history independently, with operator-controlled visibility
and per-entry read revisions. See [public content](public-content.md) for
caching, startup timing, history, migration and publication. Long names and profile
buttons remain usable on narrow layouts; the list scrolls independently of
the announcement's always-reachable actions.

### Connect to server

1. **Server** — choose a named operator-managed entry from the online HTTPS
   catalog, or **Custom server** and enter a locally stored `ws://` or `wss://`
   endpoint. The selector shows the server name and latency. Use cached and bundled
   fallbacks during directory outages; keep custom addresses available. The
   current fleet consists of Servers 1, 2 and 3. See the
   [catalog contract](../apps/client-qt/config/README.md).
2. **Display name (username)** — required; session display name only (**not** an account/login system).  
3. Connect → on success, app is in **connected** state: Create room / Join room enabled; the top-right status shows the session display name, actual connected server entry, and disconnect action.
4. Directory refreshes preserve selection by stable ID, clear it if removed,
   and never migrate an active connection or reconnect credentials. Latency
   refreshes preserve the explicitly selected server. Editing the
   custom endpoint invalidates only its outstanding probe; other server probes
   still finish and update their latency.
5. The header back action remains available during a pending connection. It
   cancels that connection before returning to the menu, so a late welcome
   cannot navigate the user back into a cancelled session.

Do not run create/join flows while disconnected.

```text
Launch → Main menu
  ├─ Deck library → back
  ├─ Connect (server choice + username) → connected
  │     ├─ Create room → settings form → enter room as host
  │     ├─ Playtest → choose a deck format → select a matching deck → solo table
  │     └─ Join room → id (+ password) → enter room
  └─ Quit
```

### Create room (fields — owner specified)

| Field | Notes |
|-------|--------|
| **Room name** | Required human-readable title; initially empty, with no example name or placeholder. |
| **Deck format / seat count** | Custom and named 1v1 formats (2), Duel Commander (2), or Commander (four-seat cap, two-player minimum); the mapped table mode binds max seats and the start threshold |
| **Gameplay rules** | Manual tabletop or Forge for supported 1v1 formats and 2–4 player Commander/EDH. Commander retains Forge when selected, clears AI, and uses server hosting. |
| **Allow spectators** | On/off |
| **BO1 / BO3** | Match length; BO3 may unlock sideboard flows later |
| **Password** | Optional; required on join if set |

The form uses two equal-width columns at widths of at least 1,000 scaled pixels:
name, format/match, and gameplay rules on the left; optional password,
spectator permissions, and card loading on the right. Cube pool selection
occupies the right column when creating a Cube event. The card stays compact
enough that fields are not stretched across the full window. When the form is
shorter than the remaining viewport, the card sits in the vertical center with
Cancel and Create on the card. When Cube or player-host options overflow, the
whole card scrolls. Narrow or enlarged layouts stack the columns and keep the
form scrollable.
Omit the redundant inner heading/host-seat sentence and helper copy under the
spectator toggles; default hand privacy and permission normalization are unchanged.

Creator becomes host and receives a shareable **room id** (see networking notes).
Playtest is a separate one-seat creation mode: it forces BO1, disables
spectators/password sharing, and is omitted from the public hub room browser.
The mapped Generic 1v1/Duel Commander/Commander table mode controls starting
life and the command zone. The separate deck format controls library filtering
and local advisory construction checks. Duel Commander uses 20 life and
commander controls on the two-player layout. Hexproof does not execute card
rules or make server-side legality judgments.

### Join room (owner specified)

Direct join remains available without a lobby. P7 also provides a simple
browser for public metadata on the currently connected hub; it pre-fills this
same join flow and does not add join fields.

| Field | Notes |
|-------|--------|
| **Room id** | Required |
| **Role** | **Player** or **Spectator** |
| **Password** | Only if the room has one (optional empty field always shown is fine) |

Display name: reuse the **username from Connect to server** only (no second name field on join).

- **Player** — takes a seat; rejected if seats full.  
- **Spectator** — only if the room allows spectators; **max 8 spectators** per room.  
- Seat caps: **2** or **4** players from create-room format; overflow only as spectators if allowed. If spectators disallowed and seats full → deny join.  
- No other join fields in v1.

### Room waiting (after create or join)

Do **not** jump straight to the live table. See `match-flow.md`.

- Creator is **player + host**.  
- Fill player seats (the creator already fills the only Playtest seat); each
  player **selects a ready deck** (art complete; **Duel Commander and EDH
  require one or two designated commanders**).
- Each **player** clicks **Ready** (spectators do not).  
- The creator chooses **preload before game** or **load in background**. When all
  players are Ready, preload rooms wait for every seated client; background
  rooms enter the table immediately, prioritize visible cards, and continue
  downloading the rest. There is no separate Start button.
- Deck library overlay from room still returns to same waiting room.

### Multi-screen / multi-window

Prefer **separate screens or windows**, not one permanent single-page shell that never leaves context:

- Main menu, room waiting, deck library, table can be distinct views.  
- Opening **deck library from a room** should **cover/stack over** the room UI; closing it returns to the **same room waiting** session (stay connected; do not drop the room).  
- Implementation may use multiple OS windows or full-screen stacked pages; product rule is **overlay + return**, not “deck library = leave room.”

### Lobby / room browser

**v1: no public lobby.** Share room id out-of-band.  
Optional later: list open rooms on the connected hub only.  
See `networking-notes.md`.

## Table / play (v1 must-have direction)

Full detail: `table-layout.md`, `match-flow.md`.

- **Battlefield-first table:** room/turn actions in the left rail, a dedicated
  optional log/chat rail on the right, remote zones at the upper-right of their
  battlefield, and local zones beside the hand.
- Card detail is a pointer-adjacent hover preview; no fixed inspector or player
  columns reserve battlefield width.
- A compact 11-step turn controller fills the existing left action rail instead
  of consuming battlefield height. Explicit attack/block declarations
  cover ordinary combat coordination; card text and unusual rules remain
  manual.
- **Hand under battlefield**; drag library top to hand or use Draw X; library
  left-click does not draw.
- **Library search:** full library multi-select plus top-X custom reorder;
  bilingual name/type filtering; ordered/random destinations to
  hand/BF/top/bottom/GY/exile; **reveal vs hidden** public log.
- Hand may go **straight to battlefield**; stack optional; **caster** resolves.  
- Own library top and owned public cards may be dragged to any seat's
  battlefield for manual control changes; double-click toggles tapped state.
- Public graveyard/exile cards have right-click move actions. Moving cards out
  of another player's pile requires that player to approve the exact one-use
  request; successful logs name the source player and zone. Graveyard and exile
  browsers share filtered checkbox selection and Select all; right-clicking a
  selected card moves the full selection atomically, including returning
  locally owned cards to the library top. Every graveyard/exile destination is
  grouped by immutable owner, regardless of current control or which convenient
  public pile accepted a drop.
- The hand-background menu supports server-random single-card discard and a
  confirmed atomic whole-hand discard. Hand reveal toggles to atomic recall.
  GY/exile browsers group identical printings and remain inspectable by all.
- **7 counter pips** (first click selects; selected LMB+1 / RMB-1 / **I** label); everyone sees.
- Opening hand **7** + manual **mulligan** (shuffle and redraw 7, publicly counted and logged); **Generic 1v1 and Duel Commander life 20** / **EDH 40**; game 1 **roll+log**; multiplayer Commander rolls every player and uses the descending result as its full cyclic turn order and virtual seating; later manual BO3 games let the **previous loser choose play or draw** during sideboarding (initial choice: play); hand on client+server.
- **Duel Commander:** two-player layout and match flow; command-zone art pile;
  dedicated tax; BO1/BO3 with a fixed registered deck between games.
- **EDH:** command-zone art pile in the local dock beside the hand; either commander can be dragged directly; **dedicated** tax; **no special poison UI** (use any of the **7** custom pips); single game; concede = **eliminate player**.
- **Concede** (1v1) = lose current game; **BO3 = first to 2 wins**; show score.  
- **Sideboard:** 5 min countdown **both see**; both Ready → next; **timeout force start with previous main/SB**.  
- Full seats required, including the one Playtest seat; host **kick/disband**;
  intentional leave frees seat; network drop **3 min** reconnect; max **8**
  multiplayer spectators; Ready+deck change → unready.
- Playtest reuses the authoritative table and card-loading path, renders one
  full battlefield, and ends by leaving the table; it does not create a local
  rules engine.
- Tokens: DB, battlefield only, art follows card language with English fallback. A compact circular **T** corner badge identifies a token without a word label covering its art; the localized token label remains available on hover and to accessibility tools. Settings; delete deck; log TTL **1 week**.

## Recommended tech stack (default)

The current approach is designed for a native desktop tabletop, multiplayer
hub, and an optional server-hosted rules runtime. Hexproof is not a commercial
3D client and does not recreate Forge's rules engine.

| Layer | Choice | Notes |
|-------|--------|--------|
| **Client** | **Qt 6 + QML + C++20** | Native Linux / Windows / macOS; table UI and deck library |
| **Room server** | **Go** | WebSocket multi-room hub; default deploy on the owner-operated cloud server; self-host OK |
| **Rules runtime** | **Forge headless harness** | Optional server child process for rules-enforced rooms; manual rooms do not require it |
| **Wire** | WebSocket + JSON (versioned protocol) | Evolve through the canonical schema and shared fixtures |
| **Card data** | Local cache + HTTP providers (e.g. Scryfall / MTGCH) | Import decks; download metadata/images |
| **License direction** | GPL-3.0-or-later | Preserve applicable third-party notices and Forge source obligations |

### Explicitly not the default stack

| Avoid as product default | Why |
|--------------------------|-----|
| Unity / Unreal | Overkill for manual tabletop; rewrite cost high |
| Godot as rewrite mandate | Fine for experiments; not required after stack check |
| Electron / browser client | Out of scope (native desktop only) |
| A second home-grown rules engine | Forge is the first backend; a future backend must implement the same boundary |

### Implementation policy

- Product requirements are **owned only by `docs/`** in the Hexproof repo.  
- **Repo root** is for code (`apps/`, build, packaging) — not for product essays.  
- **Default stack:** Qt 6 + Go; binaries `hexproof` / `hexproof-server`.  
- Changing stack requires a new entry in `decisions.md`.  
- Implementation code lives in the **same repo** as these docs (root = code).

## Doc authority

1. Owner chat / latest **implementation** specs under **`docs/`**  
2. Specs for agents: `product-brief.md`, `privacy.md`, `decisions.md`, `match-flow.md`, `table-layout.md`, `deck-library.md`, `networking-notes.md`, `implementation-plan.md`  
3. **Do not use when coding:** `产品说明.md` (owner Chinese only)
4. Code under repo root (`apps/`, …) — code reality

## Open for later (not blocking this brief)

- Host transfer after reconnect expiry: the original host keeps authority while
  its seat is held, then the lowest occupied player seat becomes host;
  spectators are never promoted.
