# XMage qualification adapter

This laboratory compiles new probes against the unmodified XMage revision
`181b465f3667a015592e5102b69b861dfcf69fd9`. It does not use XMage's Swing UI,
change Hexproof production behavior, or treat upstream test totals as shared
qualification results.

The initial build cache lives at
`build/engine-eval-20260909-U3WEaS/xmage-eval/mage`. It contains compiled engine
modules, dependencies declared by XMage's Maven manifests, and Surefire reports
with the exact working Java classpath. The runner discovers the classpath in any
standard `Mage.Tests` Surefire XML; no earlier custom Hexproof probe is required.
Alternatively pass `--classpath-file <UTF-8-classpath-file>`. The runner checks
that the classpath contains the pinned checkout's own engine, cards, and test
classes and that its dependency JARs exist. It checks the revision and
required compiled modules, compiles only these independent sources, and writes
each execution into a new directory. Previous logs are preserved.

```sh
python3 tools/engine-eval/xmage/run.py \
  --checkout build/engine-eval-20260909-U3WEaS/xmage-eval/mage \
  --output build/engine-thorough-20260909-pcbfuvZp/xmage
python3 tools/engine-eval/report.py <run-directory>/results.json
```

`--cases opening bolt_player` runs selected cases. Unselected cases are explicitly
unverified in that run's normalized report. `commands.json` pins source and suite
hashes, the full compiler/runtime arguments, and working directory. Each new run
also retains evaluator sources and the frozen suite under `source/`, and uses
its own `profile/` as the JVM's `user.home`; older runs are not backfilled with
newer source. `run.log` and `raw-results.json` retain actual observations and exception traces. Compiler
and runtime heaps are capped at 2 GiB with two active processors. These diagnostic
runs are not performance benchmarks.

For a fresh clone checked out at the pinned revision, bootstrap the normal Maven
build and a standard upstream test to obtain compiled modules and Surefire
classpath metadata. This is a setup step, not a shared-scenario result:

```sh
# Run inside the pinned XMage checkout. Dependencies come from its Maven manifests.
MAVEN_OPTS='-Xmx2g -XX:ActiveProcessorCount=2 -Djava.awt.headless=true' \
  mvn -B -T 2 -pl Mage.Tests -am test -Dtest=GameViewTest \
  -Dsurefire.failIfNoSpecifiedTests=false \
  '-DargLine=-Xmx2g -XX:ActiveProcessorCount=2 -Djava.awt.headless=true'
```

The current evaluation reused the existing compiled cache; it did not repeat a
cold build under the new resource budget. Fresh-build time and memory remain
unmeasured. Use `--compile-only` when refreshing the human bridge: this writes
`commands.json` but produces no scenario pass or qualification result.

The normal opening uses actual `HumanPlayer` queries. Other scenarios use new
fixture code and the existing `TestPlayer` action API with strict choices, normal
cost payment, legality, stack resolution, combat and state-based actions. The
default library is exactly thirty Plains at the scenario's first main phase.
Commander fixtures account for the multiplayer starting player's first draw and
use valid Isamaru commanders in all four seats; synthetic library contents do not
claim Commander deck-construction validation. Commander return is exercised by
Murder followed by a consumed optional choice. Commander damage includes separate
fresh combat and noncombat games.

`land_priority` tests actor validation at `Player.playLand`: another player's
action cannot use the active player's land or decision. This is engine-level
ownership and timing evidence. Production host authentication is a separate
integration requirement.

Owner/opponent/spectator privacy uses the real
`GameSessionPlayer.prepareGameView` seam and recursively serialized native views,
including hand identities/text, private library identities/text, public cards,
and public counts. Every actual library card UUID must be absent from every
view, and private hand UUIDs must be absent from non-owner views. The Morph probe additionally checks stack and battlefield
views and permanent identity across turning face up.

The departure fixture tracks the departing Bears' actual ID through battlefield,
stack, exile, command, and every player's hand/library/graveyard, then rejects
its ID or name in every surviving-player and spectator projection. It checks
the finalized winner after the game loop returns. The Commander damage fixture
requires a surviving player to receive the next main-phase priority and complete
a legal land action after the defender loses.

The thorough Morph result is `FAIL` at the engine layer. The ordinary five-land
cast, secrecy, turn-up identity, and 1/2 final creature pass. A fresh fixture
also proves that Chalice of the Void with zero counters actually counters the
face-down spell, as required by its zero mana value. However, another fresh
fixture cannot cast face-down Willbender using Jasmine Boreal of the Seven's
restricted GW plus a Plains' W. The same Jasmine mana alone successfully casts
Grizzly Bears in a positive control. The actual spell's no-ability predicate is
false, so this is a rule-observable restriction failure, not just internal
blueprint metadata. No upstream rule implementation was patched.

Independent authorities: the [Dominaria United release notes](https://magic.wizards.com/en/news/feature/dominaria-united-release-notes-2022-08-26)
define Jasmine's restriction to ability-free creature spells; the
[Time Spiral Remastered release notes](https://magic.wizards.com/en/news/feature/time-spiral-remastered-release-notes-2021-03-23)
explicitly explain Chalice countering face-down morph spells at zero counters.
The previously unresolved metadata runs and earlier fixture errors are retained;
they are not retroactively reported as engine failures.

The separately frozen Prepare extension uses the official
[Secrets of Strixhaven release notes](https://magic.wizards.com/en/news/feature/secrets-of-strixhaven-release-notes).
Both cases are `UNSUPPORTED` because the shipped catalog and live SOS set registry
omit Goblin Glasswright. Pinned `SecretsOfStrixhaven.java` explicitly lists it as
unfinished and removes it from the registry. A class existing on disk is not
claimed as shipped support; no synthetic replacement card is injected.

```sh
python3 tools/engine-eval/xmage/run.py \
  --checkout build/engine-eval-20260909-U3WEaS/xmage-eval/mage \
  --output build/engine-thorough-20260909-pcbfuvZp/xmage \
  --suite tools/engine-eval/extensions.json
python3 tools/engine-eval/report.py --suite tools/engine-eval/extensions.json \
  <extension-run-directory>/results.json
```

## Human interaction bridge

The `HumanBridge` entry point starts two actual `HumanPlayer` instances with
30 Forest / 30 Grizzly Bears decks, fixed starting player zero, alternating deck
insertion order, and initial shuffling disabled. It emits the common laboratory
JSONL decisions to stdout and engine logs to stderr. Replies select the offered
opaque typed responses. `id` and `actor` must match the pending decision.

```sh
python3 tools/engine-eval/xmage/bridge.py --run-dir <compiled-run-directory> \
  --profile <isolated-profile-directory>
python3 tools/engine-eval/xmage/bridge_smoke.py \
  --run-dir <compiled-run-directory> \
  --output build/engine-selection-20260909-pKWGrvLL/xmage
```

Add `--block-once` to the smoke driver to select a real blocker and attacker
through human callbacks and require both Bears to reach their graveyards before
the rest of the match completes naturally.

The bridge creates a unique profile under the compiled run directory if
`--profile` is omitted. The JVM does not use the owner's normal preferences
directory. The smoke driver checks that every requested land and creature spell
actually appears on the battlefield; offered or rejected actions do not count.

The bridge supports opening choices, legal land/spell/mana selection, explicit
mana-pool spending, attack declarations, blocker selection and target callbacks,
and passing priority. It completes through normal game rules; no artificial
concession is used by the smoke driver. The smoke driver also submits an incorrect
actor once and requires rejection before the valid reply.

Historical evaluation evidence under
`build/engine-selection-20260909-pKWGrvLL/xmage/`:

- `run-or9zpvci/results.json`: all 17 frozen flows executed; 16 semantic PASS,
  Morph UNVERIFIED. Accepted by the shared report validator.
- `human-smoke-bq5_74n4/summary.json`: real blocker/target selection, both Bears
  die, then a natural turn-13 result at life 4/-6. All 13 requested creature IDs
  and 12 requested land IDs are observed entering the battlefield, and a reply
  by the wrong actor is rejected. Compiled source is `run-pf1t7l3_`; its bridge
  source is unchanged in `run-or9zpvci`.
- The parent evaluator separately operated the shared native Wayland Qt
  laboratory; `../gui-xmage-wdTsJd/` retains its event log and window captures.
  That earlier bridge completed 204 native button clicks and a natural turn-11
  result at life 6/-4. It is not an upstream Swing test or production-client proof.

Each packet contains separately redacted owner/opponent/spectator views because
the process is a local hot-seat test controller. This is not a production network
transport or authentication design. A stdio smoke is not native GUI evidence;
the shared Qt laboratory is a separate test and is not the production Hexproof
client integration. The extensions below add only frozen-manifest deck ingestion
and an ephemeral socket recovery adapter; arbitrary owner decks, broader mechanics,
and production lifecycle support remain outside this bounded bridge.

## Frozen reference workloads and lifecycle

The optional workload entry point consumes the shared `workloads.json` file and
its selected ID. It loads the pinned catalog's real card classes, seeds the native
shuffle, and uses two or four actual HumanPlayers. Commander cards are included
in the manifest total and moved from the library to the sideboard before native
Commander initialization. Every terminal result retains all registered players'
life, won/lost/left flags and recorded incoming commander damage.

```sh
python3 tools/engine-eval/xmage/bridge.py --run-dir <compiled-run-directory> \
  --workload tools/engine-eval/workloads.json --workload-id commander_green_100 \
  --profile <isolated-profile-directory>
python3 tools/engine-eval/xmage/workload_smoke.py --run-dir <compiled-run-directory> \
  --output build/engine-thorough-20260909-pcbfuvZp/xmage --repeat 2
```

The smoke uses opaque offered replies. It checks actual initial life/deck sizes
and command zones, every viewer's private hand IDs, nonempty required actions,
paid spell/source IDs reaching ordinary priority on the stack or battlefield,
and actual engine winners/losers. Source card IDs and stack object IDs are
different in XMage: normalized stack entries retain `id` and add `cardId` from
the real stack object's source. Provisional stack objects during target/payment
prompts do not count as completed casts. A normal-priority mana ability is not
activated merely to avoid passing; payment prompts still pay through HumanPlayer.
Each game is bounded by 180 seconds and 15,000 decisions, with no invented winner.

Test-only stdio controls are `test_snapshot` with `viewer`/`requestId` (one view,
no decisions/actions), `test_reissue` with current `id`/`actor` (the unchanged
pending decision), and `test_cancel` with `requestId` (cancelled result, never
natural completion). Add `--cancel-only` to the smoke to verify cancellation.
These controls are not a durable network reconnect protocol.

`broker.py` adds an independent ephemeral loopback adapter for actual socket
disconnect/reconnect verification. It uses random test-only seat/spectator/operator
tokens, derives the actor and view from the attached role, forwards only offered
typed replies, and sends only one redacted view plus the authorized actor's
decision. Its port and ephemeral credentials are retained under the isolated
test output; it is not XMage's native server or Hexproof production authentication.

```sh
python3 tools/engine-eval/xmage/broker_smoke.py --run-dir <compiled-run-directory> \
  --output build/engine-thorough-20260909-pcbfuvZp/xmage
```

The socket smoke rejects invalid tokens, cross-seat/spectator actions, actor and
viewer spoofing, old IDs and numeric substitutes for boolean replies; reconnects
both real TCP sockets while their HumanPlayer decisions remain pending; verifies
unchanged decisions and subsequent real land movement; then cancels the exact
worker and closes every accepted connection. Socket recovery is adapter-layer
evidence. It does not cover crash persistence, arbitrary hostile load, TLS,
production authorization, or Hexproof protocol integration.

The 17-case sample and three synthetic reference decks are not exhaustive Magic
coverage and do not establish an overall engine winner. Do not infer support
from upstream test names or count these decks as owner-deck compatibility evidence.

## Explicit curated Prepare-class supplement

The normal frozen Prepare report remains two catalog-level UNSUPPORTED results:
Goblin Glasswright is excluded by the pinned SOS unfinished-card registry.
That catalog result does not by itself establish the underlying mechanic's state.
To evaluate the existing code fairly, a separate, explicit opt-in directly
constructs the unchanged upstream `GoblinGlasswright` (SOS 117) and its native
`PrepareSpellCard` named Craft with Pride. It only supplies the initial hand card;
normal casting, mana, stack, targets and state-based actions remain enabled.
No registry, card definition, rule implementation or production adapter is patched.

```sh
python3 tools/engine-eval/xmage/run.py \
  --checkout build/engine-eval-20260909-U3WEaS/xmage-eval/mage \
  --output build/engine-thorough-20260909-pcbfuvZp/xmage \
  --suite tools/engine-eval/extensions.json --curated-prepare
```

`run-qu1sxz7w/results.json` is separately labelled `XMage curated Prepare` and
passes report-schema validation. Both cases are runtime-level UNSUPPORTED:
the actual 1R payment resolves the 2/2 creature and sets prepared=true, but creates
zero exile copies. An actual attempt to cast Craft with Pride has no available
ability. The removal branch waits for entry, pays B's R for Bolt, and observes
Glasswright and Bolt in their respective graveyards with an empty stack. Because
no prepared copy existed before removal, zero remaining copies is not a cleanup
PASS. The failed first iteration `run-qvsu1emq` is retained: its removal branch
scheduled Bolt too early, while Glasswright was still a spell; that was corrected
as fixture ordering, not attributed to the engine. Default catalog results in
`run-r84s0q_z` are preserved and not overwritten by the curated supplement.

## Working-directory and catalog isolation correction

The initial concurrency experiment found a laboratory isolation defect:
`user.home` was private, but `bridge.py` changed every process to the shared
`Mage.Tests` directory. XMage's unmodified database URL is relative
`./db/cards.h2`; two of four startup attempts then failed with H2's
"Lock file recently modified" and a downstream CardRepository initialization
error. Those failed runs are preserved under the original `performance/` tree
and are not valid isolated-process performance samples.

The bridge now creates `profile/runtime` exclusively and uses it as cwd. It
copies only `cards.h2.mv.db` from the closed prebuilt catalog, never a hardlink
or a lock/trace/history file. Relative classpath entries (including Surefire's
empty trailing entry) are resolved against the original build directory, so
class/resource loading retains its original meaning after cwd changes. Already
used runtime directories, profile symlinks and existing evidence/workload files
are rejected rather than overwritten. `gamesHistory`, which an upstream
collector constructor creates even when saving is disabled, is also confined
to the private runtime directory.

Optional `--database-template /absolute/path/cards.h2.mv.db` selects another
closed prebuilt catalog. The default is the compiled checkout's existing file.
The launcher checks H2 lock absence and source stat/hash stability around copying;
observed same-UID writable descriptors are rejected. Some processes deny `/proc`
inspection: their PIDs are explicitly recorded, not represented as checked, and
no permission escalation is attempted. Linux `/proc` is required for this
supplemental diagnostic. These checks are safeguards around a deliberately
quiescent template, not a live-H2 backup protocol.

Every profile retains `bridge-command.json` with source/destination paths,
identical copy SHA256 values, byte size, copy/validation duration, original and
private cwd, and the process-inspection limitations. It also retains the exact
launcher in `bridge-source.py`. Copying and validating the approximately 272 MiB
prebuilt catalog are included in first-decision startup measurements. This is a
fresh JVM with a private prebuilt catalog, not cold construction from an empty
card database or a pure JVM-only startup measurement.

Verification in `build/engine-thorough-20260909-pcbfuvZp/xmage/isolation/`:

- `command-kglv7l4f`: all 13 focused isolation tests pass, including four concurrent
  copies, distinct inodes, mutation/corruption rejection, writable-FD/lock controls,
  profile/evidence preservation, and classpath compatibility.
- `workload-2povyrmk/results.json`: four simultaneous real HumanPlayer
  `limited_green_40` games pass the common strict workload driver. Each completes
  192 decisions, 14 individually checked casts and nine checked lands, ending
  naturally at life 6/-8. All four private database inodes and cwd paths differ.
- `command-avj21g3h` and `command-f1eoh0kq`: shared source database/trace and
  history-file inventory, hashes, sizes and modification times are identical
  before and after the four games. Runtime history directories exist privately.

The first unit iteration (`command-wgmro8xg`) exposed inaccessible unrelated
process descriptors; the first smoke (`workload-ihrkyrbx`) exposed an absent
optional Surefire classpath directory. Both launcher issues were corrected and
their failed evidence retained. No upstream database locking behavior was changed.
