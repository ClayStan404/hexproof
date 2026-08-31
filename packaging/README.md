# Hexproof release packaging

These scripts build release artifacts from a clean staging directory. They do
not install system packages and do not modify a user's normal Hexproof data.
Qt's CMake deployment API copies the platform runtime, plugins, and QML
dependencies into the client install tree.

Run the matching script from any working directory:

```sh
./packaging/linux/build-tarball.sh
./packaging/macos/build-bundle.sh
pwsh ./packaging/windows/build-package.ps1
./packaging/server/build-tarball.sh
```

Artifacts are written to `build/packages/` by default. Set
`HEXPROOF_OUTPUT_DIR` to choose another output directory and
`HEXPROOF_VERSION` to override the archive version. The client scripts require
Qt 6.5 or newer with the WebSockets and Image Formats modules, CMake, a C++20
compiler, and zlib. The server script requires the Go version declared by
`apps/server/go.mod`.

Client builds select their bundled public-server directory in this order:

1. `-DHEXPROOF_SERVER_DIRECTORY_FILE=/path/to/servers.json`;
2. the ignored local `apps/client-qt/config/servers.json`;
3. the tracked non-production `servers.example.json` fallback.

The Linux, Windows, and macOS packaging scripts forward the
`HEXPROOF_SERVER_DIRECTORY_FILE` environment variable to CMake. See
`apps/client-qt/config/README.md` for the schema and local setup.

The supported release matrix is:

| Artifact | Target | Format |
|----------|--------|--------|
| Client | Windows 10/11 x64 | Portable `.zip` |
| Client | macOS 12+ Apple Silicon | Zipped `.app` |
| Client | macOS 12+ Intel | Zipped `.app` |
| Client | Linux x86_64, Ubuntu 24.04 runtime baseline | `.tar.gz` |
| Server | Linux amd64 | Static-binary `.tar.gz` |
| Server | Linux arm64 | Static-binary `.tar.gz` |

The Linux archive is a relocatable Qt install for compatible Linux systems,
not a distribution-native package. It intentionally uses the target system's
C/C++ runtime, graphics stack, and base libraries. The macOS script produces a
zipped `.app`, and the Windows script produces a zip containing the executable
and deployed Qt runtime. The server archive carries a `.service.in` systemd
template; replace its four `@HEXPROOF_*@` placeholders before installation.
Client packages use the lightweight, cross-platform Qt Quick Controls Basic
style, keep only the SQLite database driver, and omit Qt Test and QML debugging
runtime components that are not used by release builds. They explicitly include
Qt's WebP image plugin because MTGCH card art uses WebP; release verification
rejects a package that omits the plugin. Linux packages also retain Qt's IBus
and Compose platform input-context plugins so the portable Qt runtime supports
desktop input methods instead of being limited to direct keyboard input.

## Card database release

The separate `.github/workflows/card-database.yml` workflow builds the single
schema-v10 Default Cards SQLite database from current Scryfall Default Cards,
Scryfall All Cards, MTGJSON booster definitions, and the MTGCH Simplified
Chinese name export. It publishes `hexproof-default-cards.sqlite.gz`,
`card-database-manifest.json`, and `SHA256SUMS` to the stable `card-data`
GitHub Release. The client verifies the manifest, compressed payload, expanded
size, and expanded SHA-256 before the existing atomic database installer
replaces a user's catalog.

The workflow and local database builds share
`tools/card-database-builder/build-latest.sh`. Every invocation resolves and
downloads all four current upstream inputs before building; cached or
previously downloaded source archives are not accepted as implicit inputs.

To package an already-built complete database on Linux:

```sh
./packaging/card-database/build-release-assets.sh \
  import/hexproof-default-cards.sqlite \
  build/card-database/release
```

The script requires `gzip`, `python3`, `sha256sum`, and `sqlite3`. It rejects
databases without schema version 10, legality and image statuses, booster
eligibility, limited-product definitions, token identity metadata, localized
layout metadata, Chinese aliases, or a full localized-printing index.
It also requires the database's embedded UTC `generated_at` value and writes
that same value to the release manifest used by the Settings update check.

`packaging/server/build-tarball.sh` cross-compiles the server when
`HEXPROOF_ARCH=amd64` or `HEXPROOF_ARCH=arm64` is set. The target OS is Linux
and may be made explicit with `HEXPROOF_GOOS=linux`.

## GitHub release workflow

`.github/workflows/release.yml` builds the six platform archives without
rebuilding or attaching card data. Its quality gate checks that the stable
`card-data` manifest uses the catalog schema expected by the client. A manual
run creates Actions artifacts only. A tag named exactly `vMAJOR.MINOR.PATCH`
also creates or updates a draft GitHub Release, uploads the platform packages
and combined `SHA256SUMS`, and attests every release asset. The tag version is
injected into the client application metadata, protocol hello, server welcome,
server CLI, and archive filenames.

Release clients require the `HEXPROOF_PUBLIC_SERVERS_JSON` repository Actions
secret. Each platform job validates the complete JSON document, writes it with
owner-only permissions under the runner's temporary directory, and embeds it
through `HEXPROOF_SERVER_DIRECTORY_FILE`. Ordinary CI deliberately builds with
the tracked example directory and never receives this secret. Endpoint values
are absent from Git and logs, but remain observable in published binaries and
their network traffic. The directory contains four stable public hubs plus
the path-scoped pre-release test server as its fifth entry.

macOS packages remain unsigned when release secrets are absent. To sign and
notarize them, configure all of the following GitHub Actions secrets:

- `MACOS_CERTIFICATE_P12`: base64-encoded Developer ID Application certificate
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_SIGNING_IDENTITY`
- `MACOS_NOTARY_APPLE_ID`
- `MACOS_NOTARY_PASSWORD`
- `MACOS_NOTARY_TEAM_ID`

The Release remains a draft so its signatures, startup checks, filenames, and
notes can be reviewed before publication.

After publication, the client discovers the latest stable release through the
GitHub API, selects the archive matching its operating system and architecture,
and verifies the streamed download against the combined `SHA256SUMS`. These are
portable archives rather than installers: the first in-client updater phase
opens the verified download directory and requires the user to exit Hexproof
before replacing the application. Version-mismatch recovery queries the exact
`vMAJOR.MINOR.PATCH` required by the server instead of substituting Latest.
