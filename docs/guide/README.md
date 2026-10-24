# Hexproof documentation

[Back to the project overview](../../README.md)

This guide covers installation, everyday use, source builds, and project
workflows. Client and server game protocols must match; application version
numbers may differ. Hexproof 3.1.0 uses `hexproof.v2`, while 3.0.0 clients use
v1 and must update to join a v2 hub. See [protocol compatibility](../protocol-compatibility.md)
and the release notes for the version you use.

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
- Python 3.12+, Git and JDK 21 to build the bundled Forge adapter. Client users
  do not need a system Java installation. The first source build downloads
  pinned Forge binary/source inputs; later builds reuse them.
  Newer JDK compilers generate different diagnostic symbols even with
  `--release 21`. An installed JDK 21 is selected automatically on Linux;
  otherwise select it with `JAVA_HOME` or CMake's `HEXPROOF_FORGE_JAVAC`.
- Maven is also required when building the full optional Forge runtime with
  `./tools/run-local-forge-server.sh --prepare`.
  On Arch Linux, install `maven` and `jdk21-openjdk` with `pacman`. The full
  builder selects JDK 21 for Maven and Java tools, and the local launcher uses
  Java 21 by default without changing the system Java installation.

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

## Official accounts and shared lobby

Choose **Official lobby (automatic)** to enter through a reachable official node.
The lobby lists rooms across those nodes; new rooms and whole events are placed
according to available capacity, load and latency. A global invitation such as
`N1:ROOM01` routes to its original node. An ongoing game stays on that node.
Explicit server selection and custom self-hosted addresses remain available.

Official accounts use a generated secret login code instead of a password.
Back up both the login and recovery codes privately. The recovery code replaces
lost credentials and revokes old device sessions; losing every backup and valid
session prevents recovery. The client stores only its revocable device session
in the operating system credential vault when available.

The same account works on every configured official node and can recover its
room seat, event participation and eligible completed replays. A single room
can resume automatically; if several exist, choose one from the account page.
Guest play remains available, and local deck libraries and settings remain local.
See [accounts](../accounts.md) and [official cluster setup](../official-cluster.md)
for operator settings and availability limits.

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

| Area | Supported workflows |
| --- | --- |
| Online rooms | Official shared lobby or custom hubs, room codes, guests or optional accounts, players/spectators, passwords and same-seat reconnect. |
| Manual tables | Card/zone movement, hidden hands, life/counters, commander tools, phases/combat/target coordination and BO1/BO3 where supported. Players resolve card text. |
| Forge rules | Supported constructed and Limited matches, Duel Commander and server-hosted Commander/EDH; native AI practice and optional trusted player hosting. |
| Limited and events | Set Draft, Set Sealed, regular Cube and Commander Cube; pool-constrained deck construction, Swiss events where supported, and offline pack simulation. |
| Decks and card data | Local import/export and editing, advisory format checks, schema-v10 catalog, exact printing choices, local-first images and art-pack transfer. |
| Updates and feedback | Verified platform downloads, separate card-data updates, and public feedback with AI questions, progress and release outcomes inside the client. |

Server-hosted and creator-hosted Forge have different trust boundaries; see
[player hosting](../player-hosted-forge.md) and [rules mode](../rules-engine.md).
Experimental model opponents may pause on provider/model failures; ordinary
native Forge AI and model opponents are separate features. Completed Forge
visual replays expose both hands only to the original participants after the
whole match. Tournament decklists stay private until the event completes.

## Product boundary

Manual rooms preserve Hexproof's free-form tabletop: players and tournament
organizers remain responsible for card text, legal targets, triggers, priority,
replacement effects, penalties, and unusual interactions. Optional rules rooms
delegate game rules to a server-hosted or trusted creator-hosted Forge runtime.
The Forge interface supports 1v1 matches, including Duel Commander, and
server-hosted Commander/EDH with two to four players. Commander starts at 40 life
and uses BO1. Two players use opposed halves, three place both opponents above
you, and four use four equal battlefield panels. Official accounts are
optional. There is no ladder, automatic player matchmaking, collection economy,
or web client.

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

The main automated entry points are:

- [`ci.yml`](../../.github/workflows/ci.yml) runs cheap static checks on pushes
  without repeating the full application suite. Pull requests run the full tool
  tests and affected application domains; relevant Forge-helper changes also receive
  Windows/macOS helper checks. A manual run includes complete application
  checks, race/fuzz coverage, sanitizers and full Windows/macOS CTest suites.
- [`release.yml`](../../.github/workflows/release.yml) packages source qualified
  by complete local verification, bound to the exact public commit. It checks
  that qualification, builds the supported client/server packages and verifies
  package startup, versions, architecture, checksums and signing. It does not
  repeat the workstation's QML/CTest or Go test suites.
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
| `protocol/v2/` | Canonical `hexproof.v2` wire schema |
| `testdata/protocol/v2/` | Shared client/server protocol fixtures |
| `CHANGELOG.md` | Application release notes; unpublished work under Unreleased |
| `packaging/` | Client, server, and card-database release tooling |
| `third_party/forge-runtime/` | Pinned official Forge source, native host and optional runtime/source packaging |
| `tools/` | Verification, code generation, database builder, and UI test helpers |

## Contributing

Use in-client **Feedback** to report bugs or suggest features without direct
GitHub access, or open an issue at
https://github.com/ClayStan404/hexproof/issues. In-client submissions and replies
require a public preview and explicit confirmation before publication. Text,
technical information and approved attachments are public and may be processed
by the AI providers named in the client notice. Do not include credentials,
private conversations, hidden game information or personal data.

Include the application/card-database versions, platform and minimal steps to
reproduce. The client distinguishes acceptance, public publication, assessment,
source delivery and a released fix. Keep its receipt to follow AI questions or
request content removal; closing feedback preserves public history. The
in-client full notice explains retention and removal limits.

Keep changes focused and preserve the manual-tabletop and privacy boundaries.
Rules-engine work must also follow [`docs/rules-engine.md`](../rules-engine.md).
Format Go with `gofmt`; follow the existing Qt style; retain SPDX headers; and
add owner/opponent/spectator tests for hidden-information changes.

For wire changes, update the relevant `protocol/v2/` constant/payload schemas,
shared fixtures, and handwritten payload mappings together, then run:

```sh
python3 tools/protocol_codegen.py
python3 tools/check-protocol-parity.py
```

Update shared fixtures under `testdata/protocol/v2/` when the wire contract
changes. Run relevant tests before submitting a change, and the complete
`./tools/verify.sh` suite for cross-boundary milestones or releases. Documentation
and small focused repairs do not require unrelated full rebuilds.

## License

Hexproof is licensed under GPL-3.0-or-later; see [LICENSE](../../LICENSE).
Third-party work retains its applicable copyright notices. Forge attribution
and runtime notices are in [THIRD-PARTY-NOTICES.md](../../THIRD-PARTY-NOTICES.md).
The project's [fan-software notice](../../README.md#license) also applies.
