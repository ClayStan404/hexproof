# Hexproof documentation

[Back to the project overview](../../README.md)

This guide covers installation, everyday use, source builds, and project
workflows. Client and server application versions must match exactly. Hexproof
is actively developed, so consult the release notes for the version you use.

## Contents

- [Download](#download)
- [Using the client](#using-the-client)
- [Build from source](#build-from-source)
- [Card database](#card-database)
- [What is implemented](#what-is-implemented)
- [Product boundary](#product-boundary)
- [Privacy model](#privacy-model)
- [Verification](#verification)
- [Release automation](#release-automation)
- [Repository layout](#repository-layout)
- [Contributing](#contributing)
- [License](#license)

## Download

Prebuilt client packages for Windows x64, macOS Apple Silicon, and Linux
x86_64 are published on the
[Releases page](https://github.com/ClayStan404/hexproof/releases). The
in-client update check offers the same packages automatically at most once
per 24 hours. The card database is a separate download installed through
in-client **Settings**.

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
- Qt 6.5 or newer with Concurrent, Core, Gui, LinguistTools, Multimedia,
  Network, Quick, QuickEffects, QuickTest, ShaderTools, SQL, Test, and WebSockets
- Qt Image Formats for packaged WebP card-art support
- zlib and Ninja
- Go 1.26 or the version declared by `apps/server/go.mod`
- Python 3.12+, Git and JDK 21+ to build the bundled Forge adapter. Client users
  do not need a system Java installation. The first source build downloads
  pinned Forge binary/source inputs; later builds reuse them.
- Maven is also required when building the full optional Forge runtime with
  `./tools/run-local-forge-server.sh --prepare`.

Clone the public source and run the commands below from its root:

```sh
git clone https://github.com/ClayStan404/hexproof.git
cd hexproof
```

Building the server first makes it available to the client integration test.
Shell examples use a POSIX shell; see [packaging](../../packaging/README.md) for
platform-specific builds and dependencies.

### Quick incremental build

```sh
./tools/build.sh                  # Build the client and Go server
./tools/build.sh --scope client   # Build only the client
./tools/build.sh --scope server   # Build only the Go server
```

The script writes `build/client-qt/hexproof` and `build/server/hexproof-server`.
It locates the repository from its own path, so it can also be called from
another working directory. Client compilation uses all online logical CPUs by
default; use `--jobs N` to set an explicit limit. Existing build caches, the
prepared Forge runtime, and the card database are reused. Restart the corresponding
running programs after building to load the new binaries. Run `./tools/verify.sh`
separately for automated checks.

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

Manual rooms require no Java runtime. To enable the optional Forge rules room
selector, prepare the pinned official Forge runtime and local server together:

```sh
./tools/run-local-forge-server.sh --prepare
```

Additional arguments are passed directly to the server, for example
`./tools/run-local-forge-server.sh -port 57321`. Later launches can omit
`--prepare`. See the [rules-engine contract](../rules-engine.md) for the
authority and privacy boundary and the
[runtime build guide](../../third_party/forge-runtime/README.md) for source and
runtime preparation.

### Client

```sh
cmake -S apps/client-qt -B build/client-qt -G Ninja
cmake --build build/client-qt
ctest --test-dir build/client-qt --output-on-failure
./build/client-qt/hexproof
```

The `server-integration` CTest looks for `build/server/hexproof-server` or the
path in `HEXPROOF_SERVER_BINARY`. Use
`ctest --test-dir build/client-qt -LE integration --output-on-failure` only when
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
[`apps/client-qt/config/README.md`](../../apps/client-qt/config/README.md).

## Card database

The application runs without a card database, but deck search, printing
selection, localized metadata, token identity, and named-format validation
need the current schema-v10 catalog. Settings can install a prebuilt database
from the stable `card-data` release and display the installed and available
build versions. Card images are not embedded in the database and remain an
on-demand local cache.

To build the latest release database locally from current Scryfall, MTGJSON,
and MTGCH sources:

```sh
./tools/card-database-builder/build-latest.sh
```

The script downloads fresh upstream inputs on every run and writes the
database, manifest, hashes, and compressed release asset under
`build/card-database/`. See
[`tools/card-database-builder/README.md`](../../tools/card-database-builder/README.md)
for pinned-input and offline-import workflows.

## What is implemented

### Rooms and online play

- Join by room code or browse rooms on the connected hub.
- Generic 1v1, Duel Commander, and three- or four-player Commander/EDH tables.
- BO1 and BO3 match flow where applicable, including between-game sideboarding.
- Solo Playtest through the same authoritative table path used by multiplayer.
- Player and spectator roles, password-protected rooms, host controls, public
  chat/logs, and same-seat reconnect after a network interruption.
- Online server discovery with cached and bundled fallbacks, per-server Forge
  support labels, and a user-defined custom WebSocket server.

### Forge rules and practice

- Automated rules for supported 1v1 constructed, Duel Commander, Set Sealed,
  Set Draft, and regular Cube matches, including legal actions, priority,
  triggers, stack resolution, and state-based actions.
- Server-hosted Forge or optional trusted creator hosting for supported rooms.
  Tournament and Limited pairing rooms use server hosting. See
  [player-hosted Forge](../player-hosted-forge.md) for setup and trust limits.
- Native Forge AI at Beginner, Normal, and Hard difficulty for ordinary
  constructed 1v1 BO1, with independently selected human and AI decks.
- Experimental local and online model opponents in the same practice scope.
  Model failures can pause a game; reliable full-game play with real models
  has not been verified.
- Private visual replays for original participants after a whole Forge match
  completes, including both hands, turn/event navigation, and offline playback.

### Limited play: draft, sealed, and Cube

- Set draft for two to eight checked-in players, three packs each, passing
  left, then right, then left again, with server-authoritative pools and card
  movement.
- Set sealed gives every player exactly six boosters before deck building and
  can start with two checked-in players.
- Cube draft for two to eight players from a Cube deck registered in the
  local deck library; the Cube contents are locked when the draft starts.
- Authentic booster collation from installed set definitions where available,
  with approximate rarity collation otherwise; every participant sees which
  mode a set uses.
- Build 40-card Limited decks from opened pools in the deck editor. Set
  Draft and Set Sealed lead into Swiss rounds; regular Cube supports free play
  or Swiss tournaments.
- Commander Cube drafts for two to eight players, with 20-card packs and two
  picks per pack, lead into 60-card Commander decks and multiplayer free-play
  tables of up to four.
- A standalone pack simulator for opening packs without creating a tournament.

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
  commander color identity, main-deck size, and sideboard size. Manual tables
  do not enforce card rules or claim tournament certification; Forge rooms
  enforce their supported game rules.
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

Manual rooms preserve Hexproof's free-form tabletop: players and tournament
organizers remain responsible for card text, legal targets, triggers, priority,
replacement effects, penalties, and unusual interactions. Optional rules rooms
delegate game rules to a server-hosted or trusted creator-hosted Forge runtime.
The current Forge interface supports 1v1 matches, including Duel Commander;
three- and four-player Commander/EDH use manual tables. There are no core
accounts, ladder, global matchmaking service, collection economy, or web
client.

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

Creator-hosted Forge additionally requires trust in the creator who runs the
engine. Completed Forge visual replays reveal both hands to the original
participants, and exported replay files retain that information. Choosing an
online model opponent sends that AI seat's permitted view, including its own
hand, to the configured model provider.

## Verification

Run the complete local quality and regression suite with:

```sh
./tools/verify.sh
```

It checks formatting, SPDX headers, shell scripts, QML text safety, protocol
parity, translations, and quality-tool tests; reports non-blocking module-size
review hints; runs Go formatting, vet, tests, and race tests; incrementally builds
both binaries; verifies binary versions; and runs the complete CTest suite. It
does not launch the interactive client or touch a remote server.

Choose `--scope static`, `--scope client`, or `--scope server` for shared static
checks plus the relevant domain. Client CTest also builds a matching local
integration server; server-only checks do not require Qt. Use `--clean` for
forced rebuilds and uncached Go tests. `--quick` skips race tests and CTest and
is not a complete regression run. See `--help` for all options.

Select checks by change risk rather than rebuilding or launching a real client
after every edit. Native GUI verification is allowed when needed for visual or
interaction changes, using isolated test profiles and local services.

## Release automation

The repository contains four GitHub Actions workflows:

- [`ci.yml`](../../.github/workflows/ci.yml) keeps push and pull-request checks lean:
  shared static quality gates always run; application builds are skipped for
  documentation-only changes. Client-only work runs Qt/CTest with an integration
  server; server/shared changes or an uncertain comparison run both domains.
  A manual run additionally enables Go race/fuzz checks, Linux ASan/UBSan,
  and Windows/macOS build-and-test jobs.
- [`release.yml`](../../.github/workflows/release.yml) produces portable Windows x64,
  macOS Apple Silicon, Linux x86_64, and Linux amd64/arm64 server archives.
- [`card-database.yml`](../../.github/workflows/card-database.yml) rebuilds and
  publishes the official card database weekly or on demand.
- [`forge-runtime.yml`](../../.github/workflows/forge-runtime.yml) separately builds
  and verifies the optional official Forge runtime and matching source archives
  on Linux amd64/arm64. This workflow produces development artifacts; it does
  not publish a release or deploy a service. The full Forge runtime remains an
  optional download; client packages include the matching adapter and host helper.

Application release notes are recorded in [`CHANGELOG.md`](../../CHANGELOG.md).
Unpublished work stays under **Unreleased** until the matching
`vMAJOR.MINOR.PATCH` is published.

Tagged releases use `vMAJOR.MINOR.PATCH`. Release clients embed the server
directory supplied through the `HEXPROOF_PUBLIC_SERVERS_JSON` Actions secret;
ordinary CI and forks build with the tracked example directory. See
[`packaging/README.md`](../../packaging/README.md) for platform packaging details.
Published stable releases are discovered by the client at most once per 24
hours, with an explicit Settings refresh available. Draft releases are not
offered to users.

Unsigned macOS Actions artifacts are ad-hoc signed and not Apple-notarized.
For review builds, try to launch once, then open System Settings -> Privacy &
Security and click **Open Anyway**; on older macOS releases, right-click
`Hexproof.app`, choose **Open**, and confirm, or run
`xattr -cr /path/to/Hexproof.app` before launching it. Properly signed and
notarized releases do not require this bypass.

## Repository layout

| Path | Purpose |
|------|---------|
| `apps/client-qt/` | Qt 6/QML/C++20 desktop client |
| `apps/server/` | Go WebSocket room and tournament hub |
| `protocol/v1/` | Canonical `hexproof.v1` wire schema |
| `testdata/protocol/v1/` | Shared client/server protocol fixtures |
| `CHANGELOG.md` | Application release notes; unpublished work under Unreleased |
| `packaging/` | Client, server, and card-database release tooling |
| `third_party/forge-runtime/` | Pinned official Forge source, native host and optional runtime/source packaging |
| `tools/` | Verification, code generation, database builder, and UI test helpers |

## Contributing

Report bugs and suggest features by opening an issue at
https://github.com/ClayStan404/hexproof/issues. Include the application
version and card-database build shown in **Settings**, your operating system,
the hub you were connected to, and the shortest steps that reproduce the
problem. Do not paste room passwords or resume tokens into public issues.

Keep changes focused and preserve the manual-tabletop and privacy boundaries.
Rules-engine work must also follow [`docs/rules-engine.md`](../rules-engine.md).
Format Go with `gofmt`; follow the existing Qt style; retain SPDX headers; and
add owner/opponent/spectator tests for hidden-information changes.

For wire changes, update the relevant `protocol/v1/` constant/payload schemas,
shared fixtures, and handwritten payload mappings together, then run:

```sh
python3 tools/protocol_codegen.py
python3 tools/check-protocol-parity.py
```

Update shared fixtures under `testdata/protocol/v1/` when the wire contract
changes. Run relevant tests before submitting a change, and the complete
`./tools/verify.sh` suite for cross-boundary milestones or releases. Documentation
and small focused repairs do not require unrelated full rebuilds.

## License

Hexproof is licensed under GPL-3.0-or-later; see [LICENSE](../../LICENSE).
Third-party work retains its applicable copyright notices. Forge attribution
and runtime notices are in [THIRD-PARTY-NOTICES.md](../../THIRD-PARTY-NOTICES.md).
The project's [fan-software notice](../../README.md#license) also applies.
