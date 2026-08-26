# Hexproof

[![CI](https://github.com/ClayStan404/hexproof/actions/workflows/ci.yml/badge.svg)](https://github.com/ClayStan404/hexproof/actions/workflows/ci.yml)

Hexproof is a native desktop multiplayer tabletop for Magic: The Gathering.
Players move cards and resolve card rules themselves, while the application
keeps shared zones, hidden information, turns, combat declarations, and match
state synchronized.

It is intentionally **not a card-rules engine**. Hexproof provides a fast,
flexible table for real decks without accounts, matchmaking, or a browser
shell. The client supports English and Simplified Chinese on Linux, Windows,
and macOS.

Current version: **1.0.0**. Client and server application versions must match
exactly.

## What is implemented

### Rooms and online play

- Join by room code or browse rooms on the connected hub.
- Generic 1v1, Duel Commander, and three- or four-player Commander/EDH tables.
- BO1 and BO3 match flow where applicable, including between-game sideboarding.
- Solo Playtest through the same authoritative table path used by multiplayer.
- Player and spectator roles, password-protected rooms, host controls, public
  chat/logs, and same-seat reconnect after a network interruption.
- Named bundled servers plus a user-defined custom WebSocket server.
- Public-log replay for matches retained by the connected hub.

### Manual tabletop

- Drag cards among library, hand, battlefield, graveyard, exile, stack,
  reveal, command zone, and sideboard.
- Automatic battlefield lanes for lands, creatures, planeswalkers,
  enchantments, artifacts, and other permanents, with adjustable card scale
  and a focused battlefield view for large multiplayer boards.
- Tap/untap, face-down cards, double-faced card selection, counters, life,
  commander tax, commander damage, tokens, dice, coin flips, and mulligans.
- Multi-card selection, library search and top-X resolution, public-zone
  browsers, shuffle/order controls, random or whole-hand discard, and
  owner-approved access to another player's library or public-zone cards.
- Turn/phase synchronization, response signals, attack/block declarations,
  target arrows, attachments, land-play tracking, and optional atomic helpers.
- Context menus and discoverable keyboard shortcuts for high-frequency actions.

### Decks, card data, and art

- Paste or file import for common plain-text and Moxfield-style deck lists;
  copy or file export with printing identifiers preserved.
- Local deck library and editor with category layout, main/sideboard drag,
  commander selection, printing selection, and deck-local preferred tokens.
- Custom, Standard, Pioneer, Modern, Legacy, Vintage, Pauper, Duel Commander,
  and Commander deck formats.
- Local, asynchronous advisory validation using Scryfall legality, copy limits,
  commander color identity, main-deck size, and sideboard size. The server does
  not enforce card rules or claim tournament certification.
- One versioned SQLite card database for English metadata, Simplified Chinese
  names, localized-printing lookup, tokens, and offline search.
- In-client update checks for the application and card database. Application
  packages are downloaded for the current platform and verified against the
  Release checksums before the download folder is offered.
- On-demand, local-first card art. Chinese mode prefers real Simplified Chinese
  printings and falls back through MTGCH and English sources; English mode
  prefers Scryfall English art.

### Connected-hub tournaments

- Account-free individual 1v1 Swiss tournaments on one connected hub.
- Registration, check-in, pairings, private match rooms, reported and confirmed
  results, drops, round timers, standings, and official-style tiebreakers.
- Standard, Pioneer, Modern, Legacy, Vintage, Pauper, and Duel Commander event
  formats with BO1 or BO3 matches.
- Participant deck lists remain private during the event and become visible
  after tournament completion.

## Product boundary

Hexproof automates shared state and safe tabletop operations, not Magic card
rules. Players and tournament organizers remain responsible for card text,
legal targets, triggers, priority, replacement effects, penalties, and unusual
interactions. There are no core accounts, ladder, global matchmaking service,
collection economy, or web client.

Deck validation is advisory and depends on the installed local catalog. A
missing or outdated catalog produces an unverified result instead of a false
legality claim. Custom decks remain available for variants and unrestricted
manual play.

## Privacy model

Hexproof uses a trusted-server model. The room server holds authoritative game
state, including hidden card identities, but sends each client a role-specific
projection:

- a player receives their own permitted private-zone identities;
- opponents receive counts and card backs for hidden zones; spectators do the
  same unless the room explicitly enables live current-hand visibility;
- public and explicitly revealed cards are visible to the room;
- another player's library or public-zone card requires an explicit,
  short-lived approval before a remote action can commit.

This protects normal play from accidental disclosure; it is not cryptographic
privacy against the server operator. Self-host when that trust boundary matters.

## Using the client

1. Open **Settings** to choose the interface/card language and install or
   import the current card database.
2. Open **Deck Library** to paste or load a deck list, choose its format,
   resolve any printing or commander choices, and cache missing art.
3. Use **Solo Playtest** for a private table, or connect to a bundled/custom
   server and create, join, browse, spectate, or manage a tournament.
4. In a waiting room, choose a deck matching the room format and mark Ready.
   Preload rooms wait for required art; background-load rooms enter the table
   immediately and continue caching.

Most zone operations live in context menus so the battlefield remains the
primary surface. Right-click a library, hand background, battlefield card,
graveyard, exile pile, command zone, or selected card group to see the actions
valid for that source. The in-table shortcut help lists keyboard equivalents.

## Build from source

### Requirements

- CMake 3.21 or newer and a C++20 compiler
- Qt 6.5 or newer with Concurrent, Core, Gui, LinguistTools, Network, Quick,
  QuickTest, SQL, Test, and WebSockets
- Qt Image Formats for packaged WebP card-art support
- zlib and Ninja
- Go 1.26 or the version declared by `apps/server/go.mod`

Build from the repository root. Building the server first makes it available
to the client integration test.

### Server

```sh
mkdir -p build/server
(cd apps/server && go test ./...)
(cd apps/server && CGO_ENABLED=0 go build \
  -o ../../build/server/hexproof-server ./cmd/hexproof-server)
./build/server/hexproof-server -bind 127.0.0.1 -port 57320
```

Use `./build/server/hexproof-server -help` to inspect capacity, retention,
rate-limit, and trusted-proxy options before exposing a public hub. Put a
TLS-capable reverse proxy or tunnel in front of the localhost listener for
Internet-facing `wss://` service.

### Client

```sh
cmake -S apps/client-qt -B build/client-qt -G Ninja
cmake --build build/client-qt
ctest --test-dir build/client-qt --output-on-failure
./build/client-qt/hexproof
```

The `server-integration` CTest looks for `build/server/hexproof-server` or the
path in `HEXPROOF_SERVER_BINARY`. Use `ctest -LE integration` only when
intentionally running client-only tests.

A clean checkout embeds the non-production endpoints from
`apps/client-qt/config/servers.example.json`; the custom-server field remains
available for local testing. To package named default servers, copy that file
to the ignored `apps/client-qt/config/servers.json`, or configure with:

```sh
cmake -S apps/client-qt -B build/client-qt -G Ninja \
  -DHEXPROOF_SERVER_DIRECTORY_FILE=/absolute/path/to/servers.json
```

The complete schema and release-secret workflow are documented in
[`apps/client-qt/config/README.md`](apps/client-qt/config/README.md).

## Card database

The application runs without a card database, but deck search, printing
selection, localized metadata, token identity, and named-format validation
need the current schema-v10 catalog. Settings can install a prebuilt database
from the stable `card-data` release and display the installed and available
build versions. Card images are not embedded in the database and remain an
on-demand local cache.

To build the latest release database locally from current Scryfall and MTGCH
sources:

```sh
./tools/card-database-builder/build-latest.sh
```

The script downloads fresh upstream inputs on every run and writes the
database, manifest, hashes, and compressed release asset under
`build/card-database/`. See
[`tools/card-database-builder/README.md`](tools/card-database-builder/README.md)
for pinned-input and offline-import workflows.

## Verification

Run the complete local quality and regression suite with:

```sh
./tools/verify.sh
```

It checks formatting, SPDX headers, shell scripts, QML text safety, protocol
parity, translations, module-size budgets, and quality-tool tests; runs Go
formatting, vet, tests, and race tests; performs clean server and client builds;
verifies binary versions; and runs the complete CTest suite. It does not launch
the interactive client or touch a remote server.

Use `./tools/verify.sh --quick` to skip race tests and CTest, or
`./tools/verify.sh --help` for build-path and formatting-base options.

## Release automation

The repository contains three GitHub Actions workflows:

- [`ci.yml`](.github/workflows/ci.yml) keeps push and pull-request checks lean:
  static quality gates, Go vet/tests/build, and the Linux Qt build/CTest suite.
  A manual run additionally enables Go race/fuzz checks, Linux ASan/UBSan,
  and Windows/macOS build-and-test jobs.
- [`release.yml`](.github/workflows/release.yml) produces portable Windows x64,
  macOS Apple Silicon and Intel, Linux x86_64, and Linux amd64/arm64 server
  archives, and packages the latest official card database into the same
  versioned release.
- [`card-database.yml`](.github/workflows/card-database.yml) rebuilds and
  publishes the official card database weekly or on demand.

Tagged releases use `vMAJOR.MINOR.PATCH`. Release clients embed the server
directory supplied through the `HEXPROOF_PUBLIC_SERVERS_JSON` Actions secret;
ordinary CI and forks build with the tracked example directory. See
[`packaging/README.md`](packaging/README.md) for platform packaging details.
Published stable releases are discovered by the client at most once per 24
hours, with an explicit Settings refresh available. Draft releases are not
offered to users.

Unsigned macOS Actions artifacts are ad-hoc signed and not Apple-notarized.
For review builds, right-click `Hexproof.app`, choose **Open**, and confirm, or
run `xattr -cr /path/to/Hexproof.app` before launching it. Properly signed and
notarized releases do not require this bypass.

## Repository layout

| Path | Purpose |
|------|---------|
| `apps/client-qt/` | Qt 6/QML/C++20 desktop client |
| `apps/server/` | Go WebSocket room and tournament hub |
| `protocol/v1/` | Canonical `hexproof.v1` wire schema |
| `testdata/protocol/v1/` | Shared client/server protocol fixtures |
| `packaging/` | Client, server, and card-database release tooling |
| `tools/` | Verification, code generation, database builder, and UI test helpers |

## Contributing

Keep changes focused and preserve the manual-tabletop and privacy boundaries.
Format Go with `gofmt`; follow the existing Qt style; retain SPDX headers; and
add owner/opponent/spectator tests for hidden-information changes.

Wire changes begin in `protocol/v1/wire-schema.json`, followed by:

```sh
python3 tools/protocol_codegen.py
python3 tools/check-protocol-parity.py
```

Update shared fixtures under `testdata/protocol/v1/` and run
`./tools/verify.sh` before submitting a change.

## License

Hexproof is licensed under GPL-2.0-only; see [`LICENSE`](LICENSE). Files that
incorporate third-party work retain their applicable upstream copyright
notices.
