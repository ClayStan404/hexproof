# Official Forge runtime source and build

Hexproof hosts official Forge's human and AI controllers through its own JSONL adapter
in `native-host/`. `native-host/upstream.json` is the single source of the
upstream revision, native adapter revision and reviewed native patch.
The adapter reuses native inputs, costs, legal choices and cancellation.
The old Manabrew harness, fork patches and build path have been retired.

Revision 34 also exposes source undo at ordinary priority after producing
floating mana. Only the next native undo entry is offered, and only for an
entirely unspent, reversible mana activation owned by the current priority
player. Qualification checks exact mana identities and multiplicities,
including native recursive activation-fee refunds; ambiguous repeated-ability
history is left unavailable. The action rechecks its input and native history
on the game thread, without invoking generic cancellation or passing priority.
It never rolls back land plays, spells or non-mana actions. Existing payment
undo remains separate, and the revision-25 base is unchanged.

Revision 33 fixes source undo during an unfinished mana payment. The native
payment retains its cost history, refunds that source's exact mana contribution
and performs the reversible activation rollback on the game thread. Undo
availability checks include mana already used by the current payment, while
mana consumed by a completed action remains unavailable. Exact mana identity
and multiplicity preserve other sources, including equal-color floating mana.
It retains revision 32's manual mana-color decisions and the revision-25 base.

Adapter revision 27 uses upstream `0485ad49fb10c8ef5b3eda2a002c963d59be71dc`.
Revision 27 completes the reviewed catalog printing census with paired
alternate names, Unicode spelling, funny/playtest numbers and same-Oracle
digital-edition anchors for paper cards. It preserves catalog display names
and records each remaining unsupported printing with a reason. Full-catalog
checks detect unexplained gaps and compatibility changes; see
[printing coverage](../../tools/forge-printings/README.md).
Revision 26 corrected printing compatibility for cosmetic flavor-name variants,
including Ancient Tomb LTC 387z. The generator and runtime verify the selected
printing's characteristics and executable abilities; genuine rules variants
remain excluded. It retains the revision-25 base and works through both
dedicated packages and creator-hosted overlays.
Revision 25 updates the official rules engine, card resources and verified
printing index together. Upstream changes include token-resolution performance,
alternative-cost stability and AI copy-target selection. The upgrade requires
a matching complete base distribution for creator hosting; an overlay cannot
replace the previous base's rules and card resources. Publish and verify that
base before activating its download manifest. The immutable
[adapter-25 base release](https://github.com/ClayStan404/hexproof/releases/tag/forge-runtime-0485ad49fb10c8ef5b3eda2a002c963d59be71dc-adapter25)
contains the paired runtime and complete source assets. Their exact URLs,
sizes and checksums are pinned in the
[runtime manifest](../../apps/server/internal/runtimepkg/manifest.json) and
[source manifest](overlay-base.json). The explicitly named Forge source asset,
including dependency sources, is required; GitHub's automatic repository source
archive is not a substitute.
Revision 24 releases controlled-player input when that player concedes, allowing
an Emrakul-controlled turn to unwind without stranding the native decision loop.
Revision 23 corrects companion decline, cast-only exile choices and taking cards
from a revealed selection. Both revisions retain native legality and privacy.
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
`forge-ai-v1` product capability and `forge-duel-ai-v1` for two-player,
20-life Commander AI, but shared workers reject AI game creation.
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
Earlier native fixes remain: Backup Plan shuffles
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
selector; `--legacy` is rejected. The builder needs Git, Python 3.12+, JDK 21
and Maven. It builds the official `forge-gui` dependency reactor and native host,
then runs the native regression programs. No Node.js or Rust toolchain is used.
Install these dependencies with the workstation's native package manager before
preparing; on Arch Linux, use `sudo pacman -S --needed maven jdk21-openjdk`.
The builder selects JDK 21 and supplies its `JAVA_HOME` and `PATH` only to Maven
and Java subprocesses. The launcher selects an installed Java 21 runtime unless
`HEXPROOF_FORGE_JAVA` explicitly selects another executable. Neither changes the
system Java default.

Development packages live in fresh directories under `build/forge-native/`.
The launcher validates the pin, reviewed patch, current host source, main JAR,
dependencies and resource checkout before use. Its index is
`build/forge-native/local-runtime.json`. `--prepare` advances that index only
after validation and preserves old packages and unreviewed source changes.
Reviewed source is compared against the complete patched Git tree using a
temporary index and object directory. Patch hunk order or context formatting
does not invalidate identical source; extra edits, staged work and untracked
files remain rejected. Validation preserves the checkout, index and objects.

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

Forge-sensitive push/PR changes run a bounded real-engine gate using the pinned
base and current overlay; see [native regression scenarios](native-host/TESTING.md).
The separate optional Forge workflow builds and validates the same paired
packages on native Linux amd64 and arm64 runners. It verifies a rebuild from
preserved source and runs real Go-to-Java games. Artifacts are development
evidence; the workflow does not publish a release or deploy a service. The deployment script
validates the runtime/source pair before contacting any target and preserves
transactional staging/rollback. Running it still requires owner authorization.

## Updates and validation

Advance the official revision in `native-host/upstream.json`, review/rebase the
native patch and its hash, then rebuild and run the native Java and Go
conformance suites. Keep source and runtime provenance aligned. Preserve all
upstream notices and make matching source available with distributed runtimes.
Generated checkouts, JARs and archives belong under ignored `build/`.

See [native-host/TESTING.md](native-host/TESTING.md) for reproducible scenarios
and their coverage limits. Engine regressions do not certify every card/input
combination or replace client/platform qualification. A server without a
configured runtime still hosts manual rooms and advertises Forge unavailable.
