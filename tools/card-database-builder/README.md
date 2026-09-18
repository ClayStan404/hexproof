<!--
SPDX-License-Identifier: GPL-3.0-or-later
SPDX-FileCopyrightText: 2026 Hexproof contributors
-->

# Offline card database builder

This utility builds Hexproof's single ready-to-import SQLite card database from
Scryfall Default Cards, MTGJSON booster products, and an MTGCH Simplified
Chinese data archive. An
optional Scryfall All Cards source adds the compact cross-printing Simplified
Chinese art index to the same SQLite file, including layout and per-face
identity. Card images are not embedded. Complete release databases use schema
version 10. They retain token power, toughness, and Oracle text so token
identities with the same name remain distinguishable offline, preserve the
full Scryfall legality status for local deck-format validation, and retain
Scryfall image statuses so missing and localized-placeholder scans are not
used as card art. MTGJSON products are stored as compact weighted sheets and
pack variants; products too large for the bounded online event command are
excluded rather than truncated.
Every completed database embeds its UTC `generated_at` build timestamp. The
release manifest copies that value so clients can compare installed and latest
versions without downloading the database asset.

The current schema-10 builder also retains optional `related_cards` metadata for
Scryfall meld parts/results, used by independent face selection and local custom
artwork. Existing catalogs remain valid; rebuild to populate these relationships.

The current schema-10 builder also writes optional `card_colors` and `mana_cost`
columns for draft/deck presentation. `colors` remains Commander color identity.
Card-level colors/costs are retained when present (including split cards);
otherwise the front face supplies them. Empty costs/colors are distinct from
missing metadata. Older clients can still read these databases, but a client
upgrade cannot add fields to an already-installed older database. Rebuild and
publish card-data, then update the client database to enable full presentation.

For a normal local or release build, run this command from the repository root:

```sh
./tools/card-database-builder/build-latest.sh
```

Every invocation queries the current Scryfall bulk-data descriptor and latest
MTGCH release plus the current MTGJSON `AllSetFiles.zip`, downloads fresh
source archives, verifies their container
integrity, builds the database, and creates the release files under
`build/card-database/`. It never uses source archives left by an earlier run.
Pass another output root as the only argument when needed. Network proxy
variables such as `https_proxy` are honored by `curl`.

For a reproducible build from already pinned source files, build the utility:

```sh
cmake --build build/client-qt --target hexproof_card_database_builder
```

Then build the full-printing database explicitly:

```sh
./build/client-qt/hexproof_card_database_builder \
  --source source/default-cards.jsonl.gz \
  --chinese-index source/magic-cards-zhs-data.tar.gz \
  --localized-source source/all-cards.jsonl.gz \
  --limited-products source/limited-products.json \
  --output import/hexproof-default-cards.sqlite
```

`--localized-source` is optional. Without it, zhs rows present in Default Cards
are indexed and the client queries Scryfall by Oracle ID when another Chinese
printing is first needed. The destination is replaced atomically only after a
successful import. `--limited-products` is optional for developer fixtures but
required for a complete release database. `build-latest.sh` derives that
compact file from the freshly downloaded MTGJSON archive.

Package a complete database for the stable `card-data` release with:

```sh
./packaging/card-database/build-release-assets.sh \
  import/hexproof-default-cards.sqlite \
  build/card-database/release
```

## Maintained FRA collation

`build-latest.sh` also runs `build_fra_product.py --database DATABASE.sqlite`
after importing all sources and before packaging. This derives the FRA recipe
from the database's current English printings, preserves Scryfall booster flags,
and records coverage/source revision in `metadata.fra_collation`. An incomplete
preview is labelled explicitly; a missing entire slot category fails the build.
See `docs/limited-events.md` for estimated rates and paired-draw semantics.
This recipe requires the paired-sheet client/server update. Building or packaging
it does not publish card-data or deploy the application/server.

The CLI updates an explicitly selected build database in a transaction. Run it
on build output, not a live client profile. The usual full build stages the
result before replacing its final output. The reviewed pair-name reference
comes from Draftmancer under the adjacent MIT license.
