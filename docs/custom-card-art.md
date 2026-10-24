# Local custom card art

Custom artwork is a client-side cosmetic layer, not a new card identity or a
server feature. Its files, mappings, paths, and preferences never enter room,
deck-registration, tournament, spectator, or Forge messages. A local override
may change any **visible** matching card on this device, including an opponent's
public card. Hidden identities and face-down objects still use the generic back.

## Individual cards and faces

The deck editor's card actions and token/emblem details open **Custom card art**.
Choose an image slot, preview a local JPG/JPEG, PNG, or WebP, and confirm Apply.
The preview uses a validated private copy; saving does not depend on keeping the
original file. Imported bytes are copied into managed storage under a SHA-256
filename. Changing an image therefore invalidates decoded texture URLs as well
as ordinary QML image bindings.

- The default scope is one exact printing (set and collector number), one
  independent image face, across both card-language settings.
- **All printings** is explicit and requires a verified Oracle identity. A
  shared token name such as Goblin is never sufficient to select that scope.
  A printing-specific override takes precedence over a card-wide override.
- Transform, modal double-faced, reversible cards, and double-faced tokens have
  separate front/back slots. Unchanged faces retain their original art.
- Split, adventure, and prepare cards with a single physical image have one
  slot even when their canonical names contain ` // `.
- Meld components and their result have distinct identities. A newly built
  catalog retains Scryfall `all_parts` meld relationships in the optional
  `related_cards` column. The result slot binds to the result's actual printing,
  not an invented back of either component. Catalogs without that metadata
  still support direct customization of the result printing, but need updating
  to discover it automatically from a component. No schema-version bump or
  forced migration is required for this additive metadata.
- Restore removes the selected override, or all faces at the selected scope.
  Removing an exact override can reveal a card-wide override beneath it; neither
  action modifies or deletes downloaded official art.

Hand, battlefield, inspectors, limited-card views, deck cards, and auxiliary
objects use the same presentation lookup. Printing-selection previews remain
official. Local overrides count as available presentation during match loading,
without creating successful-download records in the ordinary cache. Explicit
ordinary download/repair/export commands still operate on official images.
Deck image readiness is a transient projection and is not saved as a custom
image path in deck files.

Initializing that projection must not block window creation on the saved deck
library. Startup checks run in bounded event-loop batches (up to 32 lookups or
8 ms per batch), using the existing case-insensitive printing index for exact
face queries. Unchecked paths remain unavailable until resolved; a stale path
from a previous storage location must not appear ready in the meantime. Normal
edits resolve only changed entries, and replacing the resolver cancels pending
startup work.

Applying or restoring custom art invalidates only its affected presentation
bindings; it does not restart ordinary cache hydration or modify downloaded-art
records. Exact-printing changes prioritize the open deck and matching saved
printings. Card-wide changes and catalog reloads conservatively recheck the
library in bounded event-loop batches, since saved deck entries do not contain
Oracle identities. Existing startup work is preserved, and unchanged
projections do not rebuild the visible deck grid.

## Bulk import and sharing

The separate **Custom card art** manager is reachable from the card-art storage
manager. It lists overrides with search, per-entry removal, selected/all export,
and an explicit restore-all confirmation. It does not share delete or import
actions with downloaded-art management.

**Import folder** first builds a preview. With an installed catalog, filenames
may use `SET/collector.front.png`, `SET/collector.back.jpg`, or
`SET/collector.face-N.webp` (1-based slots). Collector numbers may be percent
encoded, for example `HHO/7%E2%80%A0.front.jpg`. A reverse filename is rejected
for a single-image layout. Ambiguous duplicate mappings are shown as errors,
not resolved by directory order.

For arbitrary names, include `custom-art-map.json` in the chosen directory:

```json
{
  "format": "hexproof.custom-art-directory",
  "formatVersion": 1,
  "entries": [
    {
      "file": "front.png",
      "scope": "printing",
      "name": "Delver of Secrets // Insectile Aberration",
      "faceName": "",
      "setCode": "ISD",
      "collectorNumber": "51"
    },
    {
      "file": "back.png",
      "scope": "printing",
      "name": "Delver of Secrets // Insectile Aberration",
      "faceName": "Insectile Aberration",
      "setCode": "ISD",
      "collectorNumber": "51"
    }
  ]
}
```

Only ordinary files contained in the chosen folder are accepted. A card-wide
entry uses `"scope": "card"` plus the card's catalog-verified `oracleId`.
Missing or invalid entries and conflicts are shown before confirmation. The
default keeps existing overrides; replacement requires an explicit choice.
The confirmed import uses the inspected snapshot, not changed source files.

Sharing uses `.hexproof-custom-artpack`, format `hexproof.custom-art-pack`,
version 1, with a distinct `HXPCST01` magic, a bounded JSON manifest, and
deduplicated SHA-256-verified image blobs. There are no device paths, archive
extraction paths, remote fetches, or automatic activation. The recipient first
inspects the pack and explicitly applies it. Ordinary `.hexproof-artpack`
exports/imports never contain or install these overrides. Users must have
permission to share their selected images.

Image decoding, validation, copying and archive work run on a dedicated bounded
single-worker custom-art pool. Ordinary image downloads, searches, cached-path
lookups and library maintenance do not block applying or restoring overrides.
Inventory sorting, image-path checks and lookup-table preparation also run on
that worker after an operation; the GUI publishes a prepared snapshot. Reloads
populate inventory image URLs asynchronously and discard stale results after a
new operation or image-root change. Exact image lookups still check that a
managed file is available before returning it. Replacing or discarding an
inspection preview releases its private extraction directory to the worker for
cleanup, so removing a large preview cannot block input on the GUI thread.
Custom operations remain serialized and pause during catalog installation,
storage migration, unavailable storage, or the required post-migration restart.
Limits are 32 MiB per image, 12,000 pixels per edge, 40 million
pixels, 20,000 mappings, 16 MiB manifests, and 4 GiB per transfer. Still images
only; untrusted unsupported, oversized or corrupted content cannot replace the
active mapping index. Imports commit the index atomically after image copies
are verified. Shared content files survive removal while still referenced.

## Storage location and migration

The default image directories are `<profile>/images/` and
`<profile>/custom-art/`. Their authoritative indexes, `card-cache.json` and
`custom-art.json`, remain in the application profile alongside the database and
deck library. Selecting another parent directory uses an application-owned,
profile-specific `hexproof-art-<profile-key>/` child with both image directories;
it is not an implicit cross-profile/shared writable cache.

Changing location requires confirmation of the exact managed destination. The
client waits for art operations to be idle, asynchronously flushes the latest
ordinary-index generation while further art operations are paused, copies
both image trees and checks SHA-256, then atomically commits
`card-art-storage.json`. The running session continues reading the old files;
all image changes are paused until **restart**. A failed migration leaves the
original configuration and image trees usable. Source files are never deleted
automatically. Returning to the default directory follows the same procedure.

On restart, historical ordinary-index paths are remapped to the selected root;
custom entries already use relative content filenames. An unavailable,
read-only, foreign, or locked directory gives a visible error and does not
silently select an empty default cache or recreate a missing mount. The managed
directory has exclusive process ownership in addition to the profile lock.

`tools/run-multiclient.sh` clones the currently configured image trees into each
new isolated profile, rewrites normal index paths, and omits source locks and
location configuration. Test profiles never acquire the user's external image
directory as their own writable cache.

## Verification evidence (2026-09-10)

The `customcardartstore`, `cardartstorage`, and `cardcatalog-customart` CTest
targets cover file validation, atomic imports, conflicts, dedicated archive
round trips, exact/card scope, independent faces (including same-named token
faces), prepare-name isolation, partial localized aliases, meld relationships,
normal-cache separation, readiness, directory ownership, unavailable disks,
and restart path rebasing. Deck-model tests bound path resolution to changed
entries during normal editing and custom-art changes, including current-deck
priority, startup overlap, card-wide fallback, and no-op notification suppression.
Restoration tests cover unrelated background work and a saturated maintenance
pool, while retaining storage-migration and unavailable-storage guards. Missing
or damaged shared custom-image blobs invalidate every affected binding when
repaired. QML tests exercise dialogs, reachable actions, bulk review,
high-scale scrolling, and deferred inventory refresh.

The startup regression checks cover zero synchronous resolver calls during
deferred initialization, bounded batches, edits/deletions between batches, and
resolver replacement/destruction. An `EXPLAIN QUERY PLAN` test uses the shared
production printing predicate against imported catalog indexes to reject a
full-card scan. A native startup check with an isolated copy of a 203 MiB
catalog and 1,153 saved printing entries reached the production executable's
first scene-graph render in 0.394 seconds on the development machine. A driver
using production startup wiring then passed 10 window/navigation checks,
including the library filter and settings; evidence is retained locally in
`build/startup-regression-20260910/`. These timings are diagnostic observations,
not portable pass/fail thresholds.

A follow-up native restore regression uses the same large-library fixture and
queues about 960 ordinary cached-path lookups before clicking Restore. The old
build rejects that deck-editor action with a wait error; the corrected build
restores from the editor in 25 ms and from the settings manager in 12 ms on the
development machine, with the rendered image and inventory updated. The same
isolated session verifies right-aligned connection controls at normal and 180%
interface scale and descending sponsor tiers. Evidence is retained locally in
`build/restore-ui-regression-20260910/` and the isolated
`build/restore-regression-before-*` / `build/restore-regression-after-*` profiles.

`./tools/verify.sh --scope client` passed the shared static/tool checks and all
28 client CTest targets. Server implementation, protocol, and deployment were
not changed by this feature.

Native Wayland checks use the production client resources and services with
isolated profiles. The offline flow exercises deck-card actions, validated
image application, the independent `PHEL #1★` Demon slot, mixed valid/invalid
folder entries, keep-existing conflicts, custom-pack export/restore/import,
180% scaling, and confirmed migration. A real close-and-restart of that same
isolated profile verifies the active destination, recovered inventory, and
ordinary/custom images rendered together from the new roots (70 workflow and
15 restart checks passed). A separate two-client local-server game
checks different artwork for the same public permanent, unchanged shared card
identity, generic face-down backs, and a locally replaced double-faced token
back (29 checks passed). Captures and repeatable drivers are retained locally under
`build/custom-art-native-ui-20260910/` and `build/custom-art-game-20260910/`;
generated fixtures are not part of the source distribution. Native Windows
and macOS file-picker/volume behavior has not been exercised in this session.
