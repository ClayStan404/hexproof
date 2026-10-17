<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 Hexproof contributors -->
# Magarena qualification adapter

Pinned source: `magarena/magarena` at
`efa0aba85e681816a92b4938b28741d540384e35`.

This candidate is filtered by the four-player requirement using source
inspection, independently of whether its desktop application can build here.
`MagicDuel.nextGame` constructs exactly two players;
`MagicGame.getOpponent` indexes `players[1 - player.getIndex()]`, its APNAP
list contains exactly two players, and any losing player ends the game.
These are engine assumptions, not a missing network wrapper.

The public `advanceToNextEventWithChoice` / `executeNextEvent(Object[])`
methods provide a promising external-decision seam. This has not been
production-integrated; the test controller below qualifies it at runtime.
`hideHiddenCards` mutates an AI simulation copy;
it is not evidence of a serialized owner/opponent/spectator view boundary.

The first bounded screen lacked Ant and never reached compilation. That
historical build gap was remedied in the thorough follow-up: the owner installed
Arch's native `ant` and `jdk8-openjdk`; the default system Java was not changed.
The upstream CircleCI configuration uses OpenJDK 8. `ant -f build.xml jar test`
actually built the unmodified engine and ran three JUnit tests with zero
failures, errors, or skips. Declared Maven dependencies come from `build.xml`.

The first JUnit invocation used the wrong resource root and failed to create
`Magarena/decks`; the retained failure is an invocation error. Passing the
same `-Dmagarena.dir=<source>/release` used by upstream's Makefile fixed it.
Upstream tests emit an initialization warning; it remains in the raw log.

Reproduce with an existing pinned checkout and native dependencies:

```sh
python3 tools/engine-eval/magarena/run.py \
  --source /absolute/path/to/pinned/magarena \
  --output /absolute/path/to/evidence \
  --java-home /usr/lib/jvm/java-8-openjdk
```

The runner uses fresh evidence directories, snapshots the suite/test source,
records exact commands and any source diff, and limits every JVM to 2 GiB/two
available processors. `--skip-upstream-build` reuses an already built checkout;
it does not claim a new upstream build/test run. `--case <id>` narrows debugging.
`--case bolt_player --negative-control` deliberately expects the wrong damage
result after a real cast and must exit 1; this is runner verification, not an
engine result. Normalization requires a cleanup-completion marker and normal
exit (or a reported assertion-failure exit), so truncated/crashed runs cannot
silently retain PASS rows.

`Qualification.java` uses actual pinned card definitions and upstream
`TestGameBuilder` only for direct initial state. Casts, mana payment, targeting,
priority, ETB, combat, replacement, copy, and tokens use engine event paths.
The test host enumerates human-legal source activations rather than making AI
strategic decisions. Cost/target choice enumeration can use the engine's
generated choice domain, with exact requested targets. Keep is an explicit
human "no mulligan" result, not an AI mulligan recommendation.

The host-added pending actor/decision-ID guard is tested by rejected wrong-seat
and stale-ID replies, followed by a real accepted land play. This qualifies the
test adapter, not native seat authentication. Native serialized viewer DTOs
remain unsupported by the inspected seam. Separately, a test-only whitelist
projection passes owner/opponent/spectator privacy checks, including a known
public Bears moved by real Time Ebb and shuffled by a paid Myr Mindservant
activation. Libraries are count-only; raw internal oracle state is retained
separately and is not exposed by that projection. No comprehensive production
privacy certification is claimed.

Four configured seats actually produce two game players in the runtime probe.
Lovestruck Beast, Bala Ged Recovery, and Willbender are actually requested from
the pinned catalog and rejected; no substitute card is credited. Commander
cases cannot instantiate their required four-player fixture. These are scoped
unsupported capabilities, not build failures or claims about unrelated cards.

The separate frozen Prepare suite is reproducible with `--suite prepare`
added to the same runner command (`--skip-upstream-build` may reuse the
verified Ant output). The actual `CardDefinitions.getCard` calls reject both
Goblin Glasswright and Craft with Pride with exact missing-script paths;
runtime `MagicSets` has no SOS entry and `MagicAbility` has no Prepare entry.
The two extension cases are scoped UNSUPPORTED with zero semantic passes,
not omitted or credited as successful casting/removal. No new card/mechanic
is supplied. Source-search matches for the older card Prepare // Fight are
unrelated to this keyword. Final extension evidence is
`build/engine-thorough-20260909-pcbfuvZp/other/magarena-run-3nijypuj/results.json`;
Java version, probe compile, probe cleanup, and runner all exited 0. This is
separate from the seventeen-case `magarena-run-6ayhwjhi/results.json` result.

Early fixture development failures and an audio-executor shutdown omission are
preserved separately. The final controller calls upstream `MagicSound.shutdown`
and exits normally. No upstream rules or production sources were repaired.

`screen.py` remains the historical source-only screen. Its counts must not be
substituted for the thorough runtime results.
