<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 Hexproof contributors -->
# Wagic runtime qualification adapter

Pinned source: `WagicProject/wagic` at
`830604d239fb00a6dfbe943664683603ccb64c79`.

The initial Qt 6 screen did not qualify runtime behavior. The thorough follow-up
actually built and ran upstream's Qt **5** console route, declared in
`.travis.yml` and `tools/travis-script.sh`. Arch's native `qt5-base` and
`qt5-multimedia` provide `qmake-qt5` and the required Qt 5 headers/libraries.
The earlier missing `QMediaPlaylist` under Qt 6 was a toolchain mismatch,
not an engine rules failure.

## Compatibility changes

The complete `compatibility.patch` is limited to:

- Renaming Wagic's `QT_CONFIG` macro to `WAGIC_QT_CONFIG` to avoid Qt's reserved
  function-like macro. This is a mechanical rename, not conditional rule changes.
- Selecting C++11, avoiding GCC 16's newer `std::filesystem` ambiguity.
- Removing `-Werror`; compiler diagnostics remain enabled and retained in logs.
- Adding test-only `WAGIC_EVAL_PROFILE` handling before normal profile access,
  so test runs never create or write the owner's desktop Wagic profile.

No upstream rule algorithm or card definition was repaired. The preserved
unpatched Qt 5 build failure documents why these changes were required.

## Reproduce

Use a fresh checkout at the exact pin and native dependencies already installed
under the host's package policy. Set absolute, task-specific paths:

```sh
wagic_source=/absolute/path/to/pinned/wagic
wagic_build=/absolute/path/to/new/qt5-build
wagic_evidence=/absolute/path/to/evidence
wagic_profile=/absolute/path/to/new/upstream-test-profile
mkdir -p "$wagic_build" "$wagic_evidence" "$wagic_profile"
git -C "$wagic_source" apply /absolute/path/to/hexproof/tools/engine-eval/wagic/compatibility.patch
(cd "$wagic_build" && qmake-qt5 "$wagic_source/projects/mtg/wagic-qt.pro" CONFIG+=console CONFIG+=debug DEFINES+=CAPTURE_STDERR && make -j2)
(cd "$wagic_source/projects/mtg" && WAGIC_EVAL_PROFILE="$wagic_profile" timeout 600s "$wagic_build/wagic")
python3 tools/engine-eval/wagic/run.py --source "$wagic_source" --build "$wagic_build" --output "$wagic_evidence"
python3 tools/engine-eval/wagic/run.py --source "$wagic_source" --build "$wagic_build" --output "$wagic_evidence" --case upstream_boosters
```

`projects/mtg/Res` is upstream's resource link; the console must run from that
directory (or `projects/mtg/bin`, which also contains `Res`). Save the actual
`$wagic_profile/test/results.html`, not merely the console exit code. The run
here executed **720** named card fixtures, with 720 success markers and no
failure markers. The console's direct `ThreadProc` route does not expand its
`+pregametests` directive; the separate `upstream_boosters` invocation actually
executes the five upstream `ShopBooster::unitTest` checks. These upstream tests
are supplemental and never counted as the shared 17 semantic cases.

`run.py` reuses the declared build's compiler/linker flags and object files,
replacing only its console main with the test controller. Each case starts a
new executable process, with an isolated profile and a 90-second limit. Exact
commands, source diff, fixture source, suite, and observations are snapshotted
in a new evidence directory. Exit 0 means the selected probes completed without
failed assertions; exit 1 means behavioral assertions failed; exit 2 means a
fixture/build/execution problem. Scoped unsupported outcomes are not failures.

`--case <id>` narrows debugging. `--case bolt_player --negative-control`
deliberately fails the damage assertion after the real cast and must exit 1;
it is runner verification, not engine qualification evidence. Six standalone
regression checks (`python3 tools/engine-eval/wagic/test_runner.py`) reject empty,
duplicate, wrong-case, and crash-after-observation output.

## Test boundaries and findings

The controller uses native human `Player`, public `GameObserver::cardClick`,
target/menu input, real mana abilities, interrupt offers, stack resolution,
combat, and state-based effects. It does not use `TestSuiteAI`, whose update
path resets the game loser. Direct initial placement is disclosed: library
cards use the catalog, hand insertion emits native zone-change events to
register `autohand`/`anyzone` abilities, and initial permanents use `Spell::resolve`.
Costs, target legality, land limits, and damage/SBA remain active.

The synthetic player subclass only suppresses `Player::End`'s disk statistics
save: synthetic decks have no persisted deck filename. The first empty-deck
cleanup failure, skipped zone-initialization events, automatic single-choice
menu assumptions, and color-mask/name-cache mistakes are preserved as fixture
errors, not engine defects. A process that crashes after printing successful
assertions is never promoted to PASS.

Opening keep and pending actor/request-ID checks are explicit **host-added**
decisions. Wrong-seat and stale responses are rejected before calling the
trusted engine; an owning seat then performs a real land play. This is an
adapter qualification, not native network authentication.

Actual native `Player`/zone serializers used by `GameObserver` network
synchronization expose hand and ordered library catalog IDs. The emitted bytes
and catalog lookup demonstrate identity recovery; no actual network socket
exchange is claimed. A separate whitelist host projection is tested for owner,
opponent and spectator, including a known public Bears moved into a library by
Time Ebb and then shuffled by a paid Myr Mindservant activation. Libraries are
count-only. Native projection FAIL and test-only host remediation PASS remain
separate; the latter is not comprehensive production privacy certification.

Visionary actually enters and draws one, but the draw runs synchronously inside
creature `Spell::resolve`. The retained debugger trace reaches
`AADrawer::resolve` from `AbilityFactory::magicText/addAbilities`; there is no
separately answerable ETB stack object. This is a shared-case engine FAIL.

Willbender is excluded by the default supported/borderline grade. Loading the
entire unsupported grade actually overflows the stack while parsing another
card's `{PW}` cost (`ManaCost::parseManaCost` ↔ `LifeorManaCost`). For the exact
Willbender semantic test, the runner copies its original, unchanged card block
from `unsupported.txt` into a non-auto-loaded isolated asset and explicitly
loads it through the native catalog parser, then refreshes the native name
cache. This is a **curated unsupported-card variant**, not a repair or a claim
that the entire unsupported catalog works. Preserve this distinction in any
matrix. The variant exposes native face-down catalog identity; its real
turn-face-up path also creates an extra copy token in the tested empty-stack
fixture. Raw stack, battlefield, payments, identity, and final state are saved.

The initialized rules game has two players. `Rules::initPlayers`, event dispatch,
opponent lookup, fixed interrupt state, and extra-rules arrays encode two seats.
The three frozen four-player/Commander cases are scoped UNSUPPORTED, not
replaced by easier 1v1 cases. This does not prevent the other shared 1v1 tests
from being built and executed. `screen.py` remains the historical source-only
screen, not the current runtime result.

Use `--suite prepare` on the same runner to execute the separate frozen
Prepare extension screen. After real native initialization loads 336 sets,
`getCardByName` returns null for both Goblin Glasswright and Craft with Pride,
and `setlist["SOS"]` returns -1. The two extension cases are therefore scoped
UNSUPPORTED with zero semantic passes: their required cards cannot be put
into the initial fixture, and no replacement cards or Prepare implementation
are injected. The source search finds an ordinary vector-preparation comment
and the older split card Prepare // Fight, not this keyword or these cards.
Final evidence is
`build/engine-thorough-20260909-pcbfuvZp/other/wagic-run-p013i4wb/results.json`;
probe compile, link, both catalog processes, and runner exited 0. This stays
separate from the seventeen-case `wagic-run-fi4782p6/results.json` result.

Final evidence-serialization correction restores eight CR bytes in the
`WResource_Fwd.h` patch hunk, whose upstream source uses CRLF. Earlier saved
patches had normalized that hunk to LF, although the tested source retained
CRLF. The corrected patch payload is byte-identical to the tested source's
raw `git diff --binary`; strict forward checking against the pinned tree and
reverse checking against the tested source both succeed. The runner now saves
source diffs as bytes, with a CRLF/binary regression test. This corrects patch
reproduction, not engine source, rules, or gameplay results; earlier raw
artifacts remain unchanged.
