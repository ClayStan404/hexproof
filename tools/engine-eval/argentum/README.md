<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 Hexproof contributors -->
# Argentum bounded qualification

Official source: [wingedsheep/argentum-engine](https://github.com/wingedsheep/argentum-engine/tree/3f46367d87c88bcf156a843a9e69fd29e1693872),
pinned at `3f46367d87c88bcf156a843a9e69fd29e1693872`.
This is a test-source-only downstream fixture, not an engine fix or production
Hexproof integration.

The pinned root [LICENSE](https://github.com/wingedsheep/argentum-engine/blob/3f46367d87c88bcf156a843a9e69fd29e1693872/LICENSE)
contains the MIT license, copyright 2026 Vincent Bons, and a separate MTG
trademark/fan-use notice. This identifies source licensing, not clearance of
third-party card art/text or every dependency.

## Reproduce

Read the pinned checkout's `AGENTS.md` and `.agents/skills/verify/SKILL.md`.
The verification instructions route tests through `just` recipes and
`scripts/gradle-locked`. This host has JDK 21, but no `just` or `shlock`.
The evaluation invoked that declared script directly as the equivalent test entrypoint; it reports that
its optional shlock guard is unavailable. Never run simultaneous Gradle commands
against this checkout.

The wrapper declares Gradle 9.6.1. Its download and manifest-declared
dependencies were installed in the isolated artifact cache. No global/system
package was installed. The first unmodified-source build ran:

```sh
scripts/gradle-locked :rules-engine:test --tests '*MultiplayerSmokeTest' \
  --max-workers=2 -PkotlinCompileParallelism=1 \
  '-Pkotlin.daemon.jvmargs=-Xmx2g -XX:ActiveProcessorCount=2' \
  '-Dorg.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=512m -XX:ActiveProcessorCount=2' \
  --no-daemon --console=plain
```

It actually executed seven upstream smoke tests successfully. These use
different fixtures and do not count as seven shared scenario passes.

From the Hexproof root, use a fresh output directory:

```sh
python3 tools/engine-eval/argentum/run.py \
  --source build/engine-selection-20260909-pKWGrvLL/other/argentum \
  --output-directory build/engine-thorough-20260909-pcbfuvZp/argentum/fresh-run
python3 tools/engine-eval/report.py \
  build/engine-thorough-20260909-pcbfuvZp/argentum/fresh-run/results.json
```

The runner verifies the immutable source pin and no tracked upstream changes,
installs only a content-addressed downstream test, uses two workers and 2 GiB
Gradle/Kotlin heaps, and limits the attempt to 900 seconds. Its
[`--rerun` task option](https://docs.gradle.org/current/userguide/command_line_interface.html#sec:rerun_tasks)
forces real test execution even when compilation is cached. Raw observations,
stdout/stderr and normalized results are retained. Its timeout terminates only
the owned process group. Prior clearly identified laboratory test files move
to the new run's `previous-fixtures/` archive so that Gradle does not compile a
failed historical source iteration; nothing is discarded. `--cache-dir` can
select an existing isolated declared-dependency cache. Nothing here is a
performance benchmark.

## Fixture boundaries and result interpretation

The probe uses production `MtgSetCatalog` definitions, not `TestCards.all`,
which includes simplified named test overrides. Some production catalog entries
are generated/predictive; passing these selected behaviors does not validate
every generated card.

Opening uses real keep-hand actions with 60-Plains decks. Other core cases use
direct precombat-main fixtures with empty hands and 30 ordered Plains in each
library, then upstream card-placement helpers. Hidden views use named secret
hands/library tops and a public Bears. All actions under test pass through
`GameTestDriver -> ActionProcessor`; costs, targeting, priority and SBA remain
enabled. Combat's upstream driver supplies legal default decisions while
advancing between steps.

The initial round executed seven core cases and the exact four-player departure:
P0 holds an actionable main-phase decision, P2 concedes with owned Bears,
the Bears entity leaves, P0 plays the pending land, P1/P3 concede, and only then
P0 wins. Commander and remaining mechanics were then unverified, not unsupported;
the thorough follow-up below supersedes that initial coverage limit.
The first downstream attempt used `setupLands` incorrectly in counterspell:
that helper advances turns instead of placing fixture lands. It was replaced
with direct `putLandOnBattlefield`; the earlier exception is preserved in v1
logs and is a fixture error, not an engine failure.

The actual `ClientStateTransformer` owner/opponent/spectator projections hide
secret names/text and retain public Bears/counts in the tested fixture.
However, every projection exposes the exact ordered stable library entity IDs.
The strict shared library-order assertion therefore fails at the projection
layer. Raw recursive JSON is retained; this is not a claim that hidden card
names/text are directly serialized. A separately labeled runtime tracking
probe moves public Bears with real Time Ebb, then activates a paid Myr
Mindservant shuffle and tests whether the known ID's new hidden position
remains recoverable. In `argentum-run-3`, all four supplemental assertions
passed: Bears moved from the known top position to zero-based index 8 after
shuffle, and the spectator could still locate the same ID despite missing card
details. This is a real post-shuffle tracking proof. Remediating the projection
does not require concluding the whole rules engine is unsuitable.

Gradle reports one wrapper test as passed when observation collection finishes.
`normalize.py` counts the per-case assertions; it does not promote that banner
to a clean qualification. No WebSocket event-stream, session or native GUI
privacy certification is implied.

## Human-query adapter feasibility

The engine has suitable public data seams; a new integration is not yet built:

| Lab need | Pinned source seam |
| --- | --- |
| Apply one human action and return control | `rules-engine/.../core/ActionProcessor.kt`: `process(state, GameAction)` returns an immutable execution result or pending decision |
| Enumerate available actions and target choices | `legalactions/LegalActionEnumerator.kt`, `view/LegalActionEnricher.kt`, serializable `LegalActionInfo` includes action, targets, costs and combat choices |
| Ask/answer an in-effect choice | Serializable `PendingDecision` has id, playerId, prompt and context; `SubmitDecision` carries the matching typed response |
| Player/spectator state | `ClientStateTransformer.transform(..., isSpectator)`; library-ID redaction needs remediation before a trusted external host exposes it |
| Session authorization/freshness | `game-server/.../session/GameSession.kt` exposes `executeClientAction`, validates interactionEpoch/decisionId and actor seats, and returns per-player legal actions |

A small isolated JSON-lines JVM bridge can map the common lab's query IDs to
these existing typed actions/decisions. It must preserve actor ownership and
freshness, handle optional/target/combat/mana decisions explicitly, and project
only permitted state. Do not expose internal `GameState` or treat the current
fixture's convenience driver as a production session. The upstream server's
event transformer and spectator builder are separate surfaces requiring their
own tests; this evaluation has not validated them.

## Thorough follow-up

The unchanged seventeen-case contract now has 16 PASS and one FAIL (native
ordered library identity leakage), with no missing evaluator. Commander tests
start actual four-player 40-life games with four registered Isamaru commanders.
They execute paid W/2W casts, actual destruction and optional command return,
an independently cloned insufficient-W branch, actual 19+2 combat damage,
positive-life elimination, a surviving priority action, and a separate actual
noncombat-damage control. The latter uses Soul's Fire, not a direct life/counter
mutation. Prior 19 damage and control-since-turn-start are disclosed fixtures.

Lovestruck Beast, Bala Ged Recovery and Soul's Fire are not present in the
pinned catalog. The downstream test explicitly registers their printed data
using existing SDK primitives, including the Beast's 1/1 attack restriction and
Recovery's own-graveyard target restriction. Costs/text were checked against
the actual pinned card scripts used by the Rust fixture; Forge does not resolve
these scenarios. These passes prove native Adventure/MDFC/damage mechanisms
with supplied card data, not bundled-card coverage. No missing card is used as
evidence of a missing engine mechanism. Other tested cards use production
catalog definitions; predefined tokens are registered from the same declared
`PredefinedTokens.allTokens` data used by upstream `ScenarioTestBase`.

Morph now explicitly checks the engine's nameless-card display placeholder,
colorless 2/2 profile, no subtypes/keywords/ability flags/text/mana cost, recursive
opponent/spectator stack and battlefield identity privacy, payment of three and
then 1U, and preserved entity identity after turning face up. Replacement,
temporary-effect copy exclusion and token ownership/counts are actual rules
executions rather than catalog-presence checks.

The separate frozen Prepare report is generated with:

```sh
python3 tools/engine-eval/argentum/normalize.py \
  --source build/engine-selection-20260909-pKWGrvLL/other/argentum \
  --raw <run>/observations.json --log <run>/execution.log \
  --suite tools/engine-eval/extensions.json --output <run>/prepare-results.json
python3 tools/engine-eval/report.py --suite tools/engine-eval/extensions.json <run>/prepare-results.json
```

Goblin Glasswright is a real production catalog entry. The normal prepare
entry/linked-copy/payment/unpreparation/removal path is tested separately from
an isolated negative branch that tries the spell face directly from hand.
An advertised-action list is not treated as authorization: the raw actor-owned
action is submitted to the real processor too. Every actual exception and
failed assertion remains in the raw observation file for precise triage.

The final `run-6` report is one Prepare PASS and one FAIL. Normal paid 1R
Goblin entry produces one linked exile copy; paid R casting unprepares the
same source, resolves one Treasure and deletes the copy. Real Bolt removal
also deletes the uncast linked copy. However, `CastSpell(faceIndex=0)` sent
directly from the owner's hand is accepted, pays R and creates a Treasure
without first casting/preparing the creature. Legal-action enumeration
correctly excludes that action, so the concrete gap is processor admission
validation, not missing Prepare support. A host allowlist is a possible
integration mitigation; no such production fix is implemented here.

`run-4`'s missing-Treasure observation was a fixture error: the evaluator had
not registered the declared predefined tokens. `run-5` and `run-6` register
the same token data as upstream `ScenarioTestBase`; they produce the expected
Treasure. All earlier fixture sources and failed logs remain recoverable.

## Complete scripted games

The final `run-6` additionally executes real two- and four-player opening to
natural single-winner games with synthetic 30-Forest/30-Bears decks and 20
life. These are deliberately not tournament-legal or owner-supplied decks.
A separate thread selects from captured native legal actions/choices, with
a ten-second response bound and requested-seat validation. Each trace stores
both thread IDs; every action demonstrably crosses the controller boundary.
There is no forced concession or terminal-state mutation.

The two-player run took 270 decisions to turn 12, with 11 creature casts and
20 attack assignments. The four-player run took 865 decisions to turn 22,
with 24 creature casts and 39 attack assignments, and accepted actual actions
after the first elimination. Full traces are `complete-2p-trace.json` and
`complete-4p-trace.json` beside the raw observations. These prove a bounded
scripted human-control integration seam, not native GUI usability, arbitrary
deck/prompt coverage, or a comparative performance ranking.
