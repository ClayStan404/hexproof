<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 Hexproof contributors -->
# TypeScript Forge-port qualification

This adapter evaluates the pinned `Baldugar/mtg-forge-ts` revision
`e5f64769168b2a1ce20fb63d32e5684a85f13594`. It reuses its declared,
previously built core/game/cards bundles; it records their SHA-256 hashes
and rejects tracked package-source modifications. It needs no added
dependency and does not alter upstream sources or old evaluation logs.

```sh
node --max-old-space-size=2048 tools/engine-eval/ts/probe.mjs CHECKOUT NEW_OUTPUT_JSON PINNED_FORGE_CARDS_ZIP
```

Use a new output filename per run and preserve stdout/stderr alongside it;
the runner refuses to overwrite existing results. The card archive used here
is the packaged Forge `143a6b556ac365cea97929ffcebb48eed03ecde8`
`forge-gui/res/cardsfolder/cardsfolder.zip`. Its hash and extracted original
card scripts are recorded, not silently replaced with easier scripted effects.
The installed native `unzip` reads the entries; no dependency is downloaded.

Read `../scenarios.json`, `../extensions.json`, and the shared interchange
contract before treating any row as qualification. This follow-up actually
executes all seventeen shared cases and both frozen Prepare extension cases.
Unexpected exceptions remain `UNVERIFIED`, never presumed engine defects.
The process exits 1 for completed behavioral failures, 2 for unresolved
execution gaps, and 0 only when the selected evaluation contains no failure.
The extension rows are saved separately as `OUTPUT_JSON.extensions.json`;
they are never added to the seventeen-case count. Test source, exact command,
Node version, card scripts, and raw observations accompany the result.

## Boundary of the observations

Opening uses the real `runGame` generator and keep-seven decisions. Other
implemented cases use exported engine cast/action/resolve/SBA/combat
components with explicit fixture scheduling. Basic-land intrinsic mana
abilities are expressed as equivalent parsed `AB$ Mana` fixture text.
Costs, targeting, damage, triggers, replacement hooks, and SBA are not
disabled. No expected post-action card zone or life total is injected.

These component tests do not establish an interactive game driver. The
exported phase driver offers only pass/concede, while `runPriorityWindow`
enumerates richer legal actions and returns action routing to its caller.
The land test now exercises that native request with a test-only host
actor/request-ID guard, then routes the accepted action to native `playLand`.
Wrong-seat and stale responses leave engine state unchanged. This is host-added
authentication, not native transport protection. The Counterspell test enters
the responder's real cast pipeline; combat invokes native declaration/order
APIs at their fixture-scheduled phases. None is a completed production adapter.

The pinned cast pipeline pushes a stack item but leaves its source card
in hand. The Bolt/player assertion checks both the stack item and the
source card's zone, so it catches this inconsistency even though damage
later resolves. Spell-target enumeration then sees no Bolt in the stack
zone and rejects Counterspell. The evaluator does not repair that state
as the upstream golden runner does for some scenarios.

Private hand/library projection is tested through actual `makeGameView`.
The test adapter converts native state to its input DTO, validates that seat 99
is not a participant, and explicitly maps a spectator to that reserved seat.
The four frozen owner/opponent/spectator assertions pass at this **adapter**
layer, not as a claim of a dedicated native spectator API or a certified
transport. Distinct secret library cards and a public Bears are included.

Supplemental tracking actually moves the known Bears to the library with
Time Ebb, then calls native `GameAction.shuffle` and captures the changed
ordered internal IDs. All external projections remain count-only. Original
Myr Mindservant activation was also attempted, but native cost parsing rejects
its printed `2 T`; this is recorded separately as an engine diagnostic, not
repaired, not a successful paid shuffle, and not a failure of an unrelated
frozen hidden-view assertion. A separate face-down projection-only probe is
still supplemental, not a complete morph cast/turn-face-up pass.

## Thorough follow-up results

The completed shared suite is **7 PASS / 10 FAIL / 0 UNVERIFIED**. PASS cases
are opening, land/priority (host routing), Bolt/creature, Visionary ETB,
blocked combat, hidden views (host conversion), and tokens. These totals do
not imply comprehensive engine correctness or production readiness.

The additional executed failures are specific:

- Four-player native `GameAction.gameLoss(concede)` emits `PlayerLost` but
  does not update liveness or remove the departing objects; the subsequent
  SBA sweep does not consume that event. Separately, the default
  `PhaseHandler` concede branch immediately ends the entire four-player game.
  A **supplemental**, test-only host composition of `gameLoss`, private compiled
  `SbaEngine.markPlayerLost`, and exported `removePlayerFromGame` does pass
  the four departure assertions, including all-zone removal and an actual
  continuing land decision. It bypasses the incomplete business entrypoint
  and does not replace the canonical native FAIL.
- Commander return is automatic, without the required optional decision;
  the second real command-zone cast succeeds with only W. No expected tax,
  cast-count update, or proper 2W recast is supplied by the host. Commander
  combat really deals two damage, but a prior-19 ledger remains unchanged
  and the defender stays alive at 38. A separate real noncombat damage
  fixture checks that the ledger is not incremented by that damage.
- The unchanged Rest in Peace script's SVar-based exile replacement does
  not redirect the dying Bears/resolved Bolt. It is not rewritten to the
  simpler `DBExile` spelling that the engine supports.
- Real Giant Growth makes the original Bears 5/5, but the original Clone
  ETB-copy keyword does not produce the required 2/2 copy. No direct
  `copiedFrom` or post-action P/T assignment is used.
- The original Adventure and modal-DFC files parse their faces, and native
  face-choice input is exercised. In-flight observations show the requested
  `adventure`/`back` face while the layer engine still reports cached front
  characteristics. Source inspection separately shows a name-only selected-face
  derivation and total-cost fallback to the front definition. Adventure does
  not cast for G; the back-face attempt still asks for the front sorcery's
  targets and offers no land play. The abort restores `face: default`; the
  post-abort front characteristics are not misrepresented as selected-face
  observations. Untap/green-mana
  continuation is explicitly unexecuted after that failure, not a fabricated
  failed assertion for an action that never ran.
- Exact Willbender registers its Morph keyword/turn-up ability, but no Morph
  alternative-cost handler is registered. A real `altCostKey: "Morph"` cast
  attempt does not create a face-down spell. The fixture does not inject
  face-down state to turn this into a claimed whole-mechanic pass.

Both frozen Prepare cases also FAIL separately. Original Goblin Glasswright
really casts and enters as 2/2, but its Prepare ETB does not create an associated
Craft with Pride copy. The removal variant still deals real Bolt damage and
kills the creature. Prepared-copy casting/lifetime continuations that require
the absent copy are listed as unexecuted; its prior absence is not credited
as successful cleanup. No new Prepare rule implementation was added.

The historical partial screen and intermediate fixture mistakes remain in
their old evidence directories. A missing `Characteristics.keywords` field in
an early observation helper and the Myr-cost diagnostic initially interrupted
extended probing; neither is silently counted as a failure of the frozen
scenario it interrupted. The final run executes all rows and passes the common
result validator, including the separate Prepare validator invocation.

Final local evidence is under
`build/engine-thorough-20260909-pcbfuvZp/other/ts-run-PjPWkkfg/`:
`results.json` contains the seventeen cases, and
`results.json.extensions.json` contains the two Prepare failures. Actual Node
exit is 1. The earlier `ts-run-QaK2b2P5` has the same counts but predates the
in-flight face trace; both are preserved.

## Upstream test-count caveat

`packages/cards/test/golden-master.test.ts` hardcodes
`F:/BACKUP/Programacion/forge/forge-gui/res/cardsfolder`. Its three tests
return after printing a warning when card files are absent; Vitest still
counts them as three passes. A fresh isolated run reproduced all three
warnings on the evaluation host. They are three unexecuted validations,
not three rules assertions. The earlier 4,919-pass total must not be used
as behavioral coverage without this caveat or as shared qualification.

No timing recorded by this adapter is a performance measurement.
