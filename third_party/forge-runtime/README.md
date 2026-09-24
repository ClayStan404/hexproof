# Official Forge runtime source and build

Hexproof hosts official Forge's human and AI controllers through its own JSONL adapter
in `native-host/`. `native-host/upstream.json` is the single source of the
upstream revision, native adapter revision and reviewed native patch.
The adapter reuses native inputs, costs, legal choices and cancellation.
The old Manabrew harness, fork patches and build path have been retired.

The current adapter is revision 22, retaining upstream `2be4858216742009afe8a7cffb035fc7671e960d`.
Revision 22 reads actual colorless mana, publishes confirmed blocking pairs,
and includes a verified offline catalog printing index. The index's source and
provenance travel with dedicated packages and creator-hosted overlays; changing
them changes the runtime identity. See [printing compatibility](../../tools/forge-printings/README.md).
Revision 17 adds a bounded private observation journal and acknowledged
`getReplay` reads on both native transports. It captures intermediate automatic
resolutions, both hands and combat relationships without changing normal viewer
redaction. The hub releases visual recordings only after whole-match completion;
see [private visual replays](../../docs/forge-replays.md).
Revision 16 reports bounded deck-start rejection coordinates in both JSONL
transports without exposing submitted card names, exception details or paths.
Revision 13 keeps each complete London-mulligan redraw available for the keep
decision. Only keeping the hand opens the explicit library-bottom selection;
initial keeps and free mulligans skip that selection when no cards are owed.
Revision 12 presents native informational messages as a single explicit
acknowledgement. AI deck advisories retain their card names and sections and
allow the human to continue to opening hands without changing either deck.
Revision 11 supports one human and one AI in Constructed, with `easy`, `normal`
and `hard` tactical presets. Hard retains every official Default profile value;
the other presets reduce selected planning behavior. All use native heuristic
AI without simulation or enabled preference-based cheats. The native AI still
has Forge's engine-level information access; these presets are not a claim of
strict player-view fairness or universally ordered win rates.
AI sessions require a dedicated JVM. Both reset transports advertise the
`forge-ai-v1` product capability, but shared workers reject AI game creation.
Evaluation workers inherit the owning game's RNG and cancellation scope;
evaluation failure ends the session instead of leaving a worker mutating it.
Revision 10 retains readable live native cost and target descriptions.

| Preset | Changes from official Default |
| --- | --- |
| `hard` | None; native heuristic AI, no simulation. |
| `normal` | Does not delay unused land drops for concealment; two-damage-spell planning chance is 45% instead of 90%. |
| `easy` | Normal's land behavior; disables paired damage planning, advanced flash planning, holding combat tricks until blocks, avoidance of already-doomed removal targets, and evasion prediction for assault/attrition attacks. |

These probabilities belong to specific native planning branches, not a global
chance to play correctly. Basic mana payment, legal targets, attacks, blocks and
mulligans remain native. Forge can still override a positive chaining chance
when it considers itself in danger. The easy zero value disables that planner
even in danger; no tier intentionally misses land drops or spends extra resources.

Revision 9 projects visible chosen-card relationships with native object
timestamp checks. Revision 8 adds native Limited deck rules and incremental
private card selections.
Revision 7 preserves conditional-discard completion and empty-stack cleanup,
shows finite card-face menus, validates crew/exile/helper cost choices, and
projects class levels and dungeon rooms. The frozen 40-deck corpus and its
native/projection/UI replay tooling live in `tools/forge-card-corpus/`.
It publishes revealed battlefield choices (named cards, types, colors, numbers
and modes) from native `CardView`, excluding secret choices and face-down cards.
Revision 5 exposes native improvise/convoke reservations and restores permanents tapped
for cost reduction when payment is cancelled, without treating improvise as
convoke for card rules. Revision 3 added complete sideboard/scry/
cleanup choices, linked exile and token metadata, and isolated shared workers;
revision 4 adds private logical-state integrity for verified host replay.
The official source pin is unchanged. Earlier native fixes remain: Backup Plan shuffles
returned unused hands, and multiplayer concession safely unwinds abandoned
objects, transfers surviving choices, and advances priority past departed
players. The patch is part of the reviewed source contract, not an unchanged
upstream rules core. Go and Qt use native legality and assignment limits.

## Local development

Prepare the official development runtime and server, then start a local hub:

```sh
./tools/run-local-forge-server.sh --prepare -port 57321
```

Subsequent launches can omit `--prepare`. `--native` remains an optional explicit
selector; `--legacy` is rejected. The builder needs Git, Python 3.12+, JDK 21+
and Maven. It builds the official `forge-gui` dependency reactor and native host,
then runs the native regression programs. No Node.js or Rust toolchain is used.

Development packages live in fresh directories under `build/forge-native/`.
The launcher validates the pin, reviewed patch, current host source, main JAR,
dependencies and resource checkout before use. Its index is
`build/forge-native/local-runtime.json`. `--prepare` advances that index only
after validation and preserves old packages and unreviewed source changes.

Use `HEXPROOF_FORGE_SOURCE_DIR` for an existing checkout at the exact pin,
`HEXPROOF_FORGE_OUTPUT_DIR` for build output, or `HEXPROOF_FORGE_LOCAL_ROOT` for
an explicit verified runtime. A development package references its source
checkout's card resources and must not be distributed as a standalone archive.
The launcher also accepts a verified extracted official standalone package.

## Runtime and matching source archives

Build the official standalone pair:

```sh
./third_party/forge-runtime/build.sh
# Reuse the existing reviewed official checkout:
./third_party/forge-runtime/build.sh --source /absolute/path/to/forge --output /absolute/path/to/output
```

The output contains `hexproof-forge-runtime-<revision>-adapter<N>.tar.gz`, its
matching `hexproof-forge-source-<revision>-adapter<N>.tar.gz`, and checksums.
The runtime contains real resource files and dependency JARs, with no reference
to the build checkout. `SOURCE.json` binds it to the exact source archive;
provenance and inventories bind its official source, patch, host and dependencies.
Source collection is mandatory, including sources/notices omitted from Maven
source JARs. Missing source is a packaging failure.

See [SOURCE-README.md](SOURCE-README.md) for complete contents, the explicit
source-backed XMLPull API substitution, and rebuilding without upstream Git
access. Rebuilding may still use Maven's declared plugins/dependencies; this is
not an offline toolchain image. Extract the runtime at any chosen location and
launch it with `HEXPROOF_FORGE_LOCAL_ROOT` pointing to `hexproof-forge-runtime`.

The optional Forge workflow builds and validates the same paired packages on
native Linux amd64 and arm64 runners. It verifies a rebuild from preserved
source and runs real Go-to-Java games. Artifacts are development evidence; the
workflow does not publish a release or deploy a service. The deployment script
validates the runtime/source pair before contacting any target and preserves
transactional staging/rollback. Running it still requires owner authorization.

## Updates and validation

Advance the official revision in `native-host/upstream.json`, review/rebase the
native patch and its hash, then rebuild and run the native Java and Go
conformance suites. Keep source and runtime provenance aligned. Preserve all
upstream notices and make matching source available with distributed runtimes.
Generated checkouts, JARs and archives belong under ignored `build/`.

See [native-host/TESTING.md](native-host/TESTING.md) for reproducible scenarios
and [the migration record](../../docs/forge-native-migration.md) for actual
verification and remaining game-input/platform limits. A server without a
configured runtime still hosts manual rooms and advertises Forge unavailable.
