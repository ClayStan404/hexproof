# Native lifecycle verification

This extends [native scenario verification](ai-verification.md) with
reproducible installation, import, caching, restart and manual-game workflows.
Choose the relevant scenarios under [development-policy.md](development-policy.md);
Forge scenarios retain their separate rules-mode assertions. A scenario name
does not imply complete product coverage: each run records the actions and
assertions it actually completed.

Use the runner's default maximized windows for primary lifecycle and AI review
coverage, including every seat and restarted process. Explicit fixed-size or
minimum-size runs supplement this baseline as described in
[project verification](ai-verification.md#running-the-first-scenarios).

## Real card fixtures

Generate portable text decks from a read-only database snapshot:

```sh
python3 tools/ui-automation/make-card-fixtures.py \
  --catalog /absolute/path/to/cards.sqlite \
  --output build/card-shape-fixtures
```

The manifest records the database hash/version, each exact printing, Oracle
identity, legal status, layout and independent image faces. It contains ten
deck formats, separate invalid lists and an explicit list of unavailable
shapes for each format. Tokens, emblems and meld results are auxiliary cards,
not registered main-deck cards. No installed decks or image cache are seeded.
Legality expectations refer to this pinned snapshot, not today's tournament
rules. A single format cannot contain every unusual layout legally.
Use `--formats modern legacy pauper duel`, for example, to generate only the
formats needed by a task. The ten-format import matrix below checks import
compatibility independently of gameplay coverage.

`DeckMatrix.qml` imports all ten formats and fourteen negative cases through
the interface, edits counts, checks every printing against the manifest and
tests the selection model's acceptance. It also imports a Prepare card by a
characteristic name that collides with a standalone spell. Image readiness is
recorded separately from legality. This matrix does not claim match entry or
cache-download coverage.

## Clean installation and restart

```sh
QT_QPA_PLATFORM=xcb python3 tools/ui-automation/run-native.py \
  --scenario tools/ui-automation/scenarios/BootstrapLifecycle.qml \
  --next-scenario tools/ui-automation/scenarios/BootstrapLifecycle.qml \
  --deck-manifest build/card-shape-fixtures/manifest.json \
  --variant modern --fresh-settings --startup-services --timeout 650
```

The first process starts without settings, a database, decks or images. It
dismisses first-launch notices and sets language through visible controls,
installs the official database, imports the chosen text deck and explicitly
caches art. After validating every printing and the actual image inventory,
it exits. The runner launches a new process against the same profile and
verifies persistence. Before/after checkpoints include file hashes and image
counts; separate stage artifacts prevent an earlier pass from satisfying a
later stage. A failed stage prevents subsequent launches.

`--catalog` is an explicitly preinstalled SQLite backup for targeted tests.
`--catalog-import` instead supplies a file to the actual Settings file chooser.
They establish different evidence and must not be reported interchangeably.
`--fresh-settings` removes the usual language/announcement presets;
`--startup-services` enables the production automatic update checks and startup
art audit. The startup artifact records the actual mode and download location.
Downloads are isolated with XDG user-directory configuration as well as XDG
application data, configuration and cache directories.

To test an actual database upgrade, supply an older compatible database using
`--catalog-import` and set `HEXPROOF_AUDIT_BOOTSTRAP_MODE=online-update` for that
command. The scenario requires a newer official version, clicks Update and
verifies that the installed version advanced. An already-current database is
not an upgrade pass. Network failures remain failures with the original state
and error retained.

## Native file operations

Build the optional Linux helpers:

```sh
cmake -S tools/ui-automation/x11 -B build/ui-automation
cmake --build build/ui-automation
ctest --test-dir build/ui-automation --output-on-failure
```

Supply `--file-dialog-helper build/ui-automation/xfile-dialog` for a same-process
native X11 file chooser. The helper requires the test client's exact PID,
dialog title, window type, transient owner and input focus. Save mode permits
only a new path in an existing writable directory. It never creates a dummy
file or overwrites an existing file to simulate a save. Qt Quick file choosers
use actual path-field input. External portal dialogs and other platforms need
their own verification; no fallback changes the production dialog options.

Set `HEXPROOF_AUDIT_MATRIX_ROUNDTRIP=1` when running `DeckMatrix.qml` to include
native file export and file import for its positive cases. This is a separate
coverage branch; the metadata-only matrix does not establish file-dialog
support.

On Linux installations with GTK 3 development files, the audit target also
builds an optional GTK widget-input adapter. Set
`HEXPROOF_AUDIT_GTK_FILE_DIALOG=1` for a command to exercise the actual
same-process GTK chooser through Ctrl+L, text entry and a click on Open/Save. It verifies
the exact title, open/save mode and same-process transient owner. It never
calls the chooser's file-selection setters or application import methods.
The selected file and downstream import/export effects must both match.
Evidence is labeled `native-gtk-input` with `osInputRoutingVerified: false`:
this checks real widget handlers, not compositor input routing. This matters
on XWayland environments where the input portal prevents XTest delivery.
The normal release target has no GTK test-adapter dependency.

For `--network-isolated`, the runner also sets the child process's
`GIO_USE_VFS=local` and records that override. This limits the chooser to local
files and avoids host GVFS D-Bus calls from the isolated user/network namespace,
as documented by [GIO](https://gnome.pages.gitlab.gnome.org/gtk/gio/overview.html).
Normal runs retain their inherited environment. This is test environment
isolation; host GVFS mounts and OS-level input routing need separate coverage.

## Games and application packages

For a continuous two-player chain, use `--players 2 --variant modern` with a
local `--server-binary`, Bootstrap as the first scenario, and `FullMatch.qml`
as the next scenario. Bootstrap serializes each seat's input while preserving
independent profiles. FullMatch uses those saved decks and caches, creates and
joins the room through the interface, then exercises mulligan, zones, stack,
manual resolution, life, counters, privacy, phases, turns and the match result.
The Duel Commander variant adds command-zone casting and tax checks. Layout
branches use the manifest to find and operate real double-faced and Prepare
cards. Each branch reports its own physical-card and image-face assertions.
Allow a longer watchdog for real network downloads.

```sh
QT_QPA_PLATFORM=xcb python3 tools/ui-automation/run-native.py \
  --scenario tools/ui-automation/scenarios/BootstrapLifecycle.qml \
  --next-scenario tools/ui-automation/scenarios/FullMatch.qml \
  --next-scenario tools/ui-automation/scenarios/BootstrapLifecycle.qml \
  --server-binary build/server/hexproof-server \
  --deck-manifest build/card-shape-fixtures/manifest.json \
  --players 2 --variant modern --fresh-settings --startup-services \
  --output build/modern-new-user-match --timeout 900
```

For a focused game on explicit prepared profiles, use `FullMatch.qml` directly
with `--catalog` and `--fixture-dir`. Match `--card-language` to the fixture's
actual cached art. Set `HEXPROOF_AUDIT_DRAG_EDGES=1` to add the tapped permanent,
stack and revealed-card edge-drop cycle; its extra screenshots and assertions
are required only when that branch is selected. Two-player Duel runs use
`--players 2 --variant duel`. These prepared-profile runs
establish gameplay differences, not fresh-install coverage.

`ApplicationUpdate.qml` checks for a newer official application release and
downloads its platform archive through the real updater. It requires an
observed download and successful production checksum verification. It does
not claim that downloading installs the application. The update branch can
be exercised with an isolated build using `HEXPROOF_VERSION_OVERRIDE` set to
an older version: this is a version-selection fixture, not the historical
application binary or proof of historical data migration. The resulting
official archive must be separately unpacked and launched before package
startup is counted as verified.

After the updater client exits with complete passing input evidence, the
runner records the archive path, byte count and SHA-256 in a new
`download-evidence.json`. Package startup requires that record to match the
run, stage, scenario result and current archive. Reports without this binding
must be rerun; computing a hash later cannot establish what was downloaded.

```sh
python3 tools/ui-automation/verify-update-package.py \
  --source-run build/actual-updater-run \
  --profile-run build/verified-bootstrap-run \
  --output build/release-package-check --launch
```

The package checker validates archive members before extraction, runs the
actual binary's version command, and clones only known profile data from a
previous isolated run. `--launch` opens the release GUI in a network namespace,
captures its PID-bound primary X11 window, requests normal window closure and
compares persisted data. Without that option its result is only `prepared`.
It does not install over the owner's application, exercise historical schema
migrations, or establish that every release screen works.

All runners keep their owned processes, profiles, source/binary hashes,
screenshots, input traces and assertions under a new `build/` output directory.
Component tests and fake subprocesses used to verify the runner are explicitly
tool tests, never native product evidence. Report uncovered operations and
platforms alongside passes; do not infer coverage from visits or filenames.

## Card art packs

`ArtTransferLifecycle.qml` separates export from a cached sender and import into
a new recipient profile. It uses the production deck export menu, Settings art
manager, native file choosers and confirmation buttons. The portable
`.hexproof-artpack` is an `HXPART01` container with a JSON manifest and image
blobs, not a ZIP archive. The commands below use the optional GTK widget-input
adapter described above; keep each output path new and use the real-card
manifest generated earlier.

First bootstrap the complex Modern deck online. Then make an explicit portable
copy of only its deck/cache/images test data for a separate offline export run.
The bootstrap and transfer cannot share one runner invocation: the bootstrap
needs network access, while transfer must use `--network-isolated`.

```sh
HEXPROOF_AUDIT_GTK_FILE_DIALOG=1 \
  python3 tools/ui-automation/run-native.py \
  --scenario tools/ui-automation/scenarios/BootstrapLifecycle.qml \
  --deck-manifest build/card-shape-fixtures/manifest.json \
  --variant modern --players 1 --output build/card-art-transfer-bootstrap \
  --timeout 650

python3 - <<'PY'
from pathlib import Path
import shutil

art_source = Path("build/card-art-transfer-bootstrap/seat-1/data/Hexproof/Hexproof").resolve()
art_fixture = Path("build/card-art-transfer-sender-fixture")
for name in ("decks.json", "card-cache.json", "images"):
    origin = art_source / name
    entries = [origin, *origin.rglob("*")] if origin.is_dir() else [origin]
    if any(path.is_symlink() or not (path.is_file() or path.is_dir()) for path in entries):
        raise ValueError("Portable fixtures require ordinary files: " + str(origin))
art_fixture.mkdir()
for name in ("decks.json", "card-cache.json"):
    (art_fixture / name).write_text((art_source / name).read_text().replace(str(art_source), "@PROFILE@"))
shutil.copytree(art_source / "images", art_fixture / "images")
PY

HEXPROOF_AUDIT_GTK_FILE_DIALOG=1 HEXPROOF_AUDIT_ART_TRANSFER_MODE=export \
  python3 tools/ui-automation/run-native.py \
  --scenario tools/ui-automation/scenarios/ArtTransferLifecycle.qml \
  --catalog build/card-art-transfer-bootstrap/seat-1/data/Hexproof/Hexproof/cards.sqlite \
  --fixture-dir build/card-art-transfer-sender-fixture \
  --deck-manifest build/card-shape-fixtures/manifest.json \
  --network-isolated --variant modern --players 1 \
  --output build/card-art-transfer-export --timeout 180

python3 tools/ui-automation/verify-art-transfer.py \
  --pack build/card-art-transfer-export/seat-1/artifacts/complex-deck.hexproof-artpack \
  --manifest build/card-shape-fixtures/manifest.json \
  --catalog build/card-art-transfer-bootstrap/seat-1/data/Hexproof/Hexproof/cards.sqlite \
  --export-artifacts build/card-art-transfer-export/seat-1/artifacts \
  --make-invalid build/card-art-transfer-damaged.hexproof-artpack \
  --output build/card-art-transfer-export-check.json
```

The verifier independently reads every image blob, checks its declared size
and SHA-256, and compares all expected printing faces with the fixture. It
also compares each face's blob hash with the sender's observed local image and
checks that the completed native export summary agrees with the actual
container. Meld results are separate exact printings: `--catalog` is required
when the deck includes meld cards, and its read-only logical SHA-256 must equal
the fixture's original `source.sha256`. Use the recorded source catalog if a
later online install supplies a different snapshot. The verifier resolves each
`relatedCards.id` from that pinned catalog, requires every related result in
the pack, and compares its bytes with the sender's persisted exact cache
mapping. The separate `relatedResultCoverage` report does not rewrite the
fixture or native observations. Two exact result printings may share one blob;
deduplication must preserve both mappings.

`--make-invalid` creates a separate new copy with the last image
payload byte changed; it never alters the valid export or any profile. Omit
that option for strictly read-only pack inspection apart from the new report.
This Python check verifies hashes and format signatures; full image decoding
remains a production import check, not an independent decoder claim.

Now start a different profile with only a read-only backup of the sender's
catalog. Do not supply `--fixture-dir` or copy its image cache. The recipient
imports the deck text through the UI, establishes zero cached images, rejects
the damaged payload without partial files, cancels a valid pack confirmation,
then imports the valid pack twice:

```sh
HEXPROOF_AUDIT_GTK_FILE_DIALOG=1 HEXPROOF_AUDIT_ART_TRANSFER_MODE=import \
  HEXPROOF_AUDIT_ART_PACK="$PWD/build/card-art-transfer-export/seat-1/artifacts/complex-deck.hexproof-artpack" \
  HEXPROOF_AUDIT_INVALID_ART_PACK="$PWD/build/card-art-transfer-damaged.hexproof-artpack" \
  python3 tools/ui-automation/run-native.py \
  --scenario tools/ui-automation/scenarios/ArtTransferLifecycle.qml \
  --catalog build/card-art-transfer-export/seat-1/data/Hexproof/Hexproof/cards.sqlite \
  --deck-manifest build/card-shape-fixtures/manifest.json \
  --network-isolated --variant modern --players 1 --output build/card-art-transfer-import \
  --timeout 300

python3 tools/ui-automation/verify-art-transfer.py \
  --pack build/card-art-transfer-export/seat-1/artifacts/complex-deck.hexproof-artpack \
  --manifest build/card-shape-fixtures/manifest.json \
  --catalog build/card-art-transfer-bootstrap/seat-1/data/Hexproof/Hexproof/cards.sqlite \
  --export-artifacts build/card-art-transfer-export/seat-1/artifacts \
  --profile build/card-art-transfer-import/seat-1 \
  --import-artifacts build/card-art-transfer-import/seat-1/artifacts \
  --output build/card-art-transfer-import-check.json
```

The final check compares the recipient's persisted mappings and every managed
image file with the exported blob hashes. It requires no missing or unused
files and unchanged mappings/storage after duplicate import. Before the
duplicate, the UI waits for catalog hydration and refreshes inventory, then
records `cache-before-duplicate.json` and `inventory-before-duplicate.json` as
the comparison baseline. Hydration may add a complete `front // back` name
lookup for an imported double-faced front image. The verifier independently
derives the permitted keys from the fixture and pack; each added record must
equal the original front record in every field except `requestedName`, with
the same exact printing, language and image path. Original packaged metadata
must remain unchanged. Unrelated keys, back-image aliases and later changes
cannot pass. The UI scenario
also reopens the deck and observes each independent front/back image using the
fixture's face names. Both transfer processes run inside a Linux network
namespace through the recorded `unshare --user --map-root-user --net` launcher.
The verifier requires that runner provenance and the completed native input
evidence. Local cache activity is recorded separately and may occur without
downloads; it is not used as a network-traffic oracle. The recipient must also
have a startup checkpoint with no preseeded images, deck or cache index.
Input failures, QML warnings or business-state injection invalidate the evidence. If the damaged-pack
environment variable is omitted, its negative case is explicitly not covered.
Cancellation here means cancelling the import confirmation; interruption
during a write is outside this scenario. These commands are procedures, not a
claim that a particular run passed: retain both native reports and both hash
verification reports before reporting the complete transfer as verified.

## Targeted download and large-library review

`BootstrapLifecycle.qml` also supports `HEXPROOF_AUDIT_BOOTSTRAP_MODE=art-download`.
Use this mode with `--catalog` and `--deck-manifest`: it records the database as
a prepared read-only backup, asserts an empty image inventory, selects the art
provider through Settings, imports the deck through UI, and searches/switches
views while the explicit download runs. It does not claim database installation
or version-check coverage. `HEXPROOF_AUDIT_CARD_ART_PROVIDER` selects `auto`,
`scryfall`, `mtgch`, or `parallel` (the targeted mode defaults to `parallel`).
Repeating the scenario with `--next-scenario` checks the saved provider, deck,
local art and inventory after a new process starts. The final deck observation
also waits for the visible status badge to reflect coalesced metadata updates.

Record download duration, interaction overlap, and GUI timer interval
median/P95/maximum separately from screenshots. These intervals include native
event dispatch; they are not measured frame times. Use new profiles and output
directories for repetitions. The runner records selected graphics environment
variables, including `QSG_NO_VSYNC`, so a compositor-workaround run cannot be
mistaken for default-renderer performance.

`LibraryStress.qml --deck-manifest ...` accepts a generated singleton Cube with
960 printing rows. Supply a fixture directory containing only that saved deck;
the scenario validates its identities/counts against `manifest.decks.cube`,
derives color-filter expectations from that independent manifest, and exercises
eight filter cycles, twenty increment/decrement cycles, persistence and pending
catalog searches. Without a manifest it retains the original real-library
fixture contract. State whether art was seeded; placeholder-gallery timings
cannot substitute for a fully cached library. Screenshot time is excluded from
the next interaction's heartbeat sample.
