# Manabrew Rust qualification

<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 Hexproof contributors -->

This runner executes independent fixtures from the frozen common suite. It does
not aggregate upstream test counts or use Forge resolution as an oracle. Card
scripts are pinned data inputs from the matching Forge submodule.

```sh
python3 tools/engine-eval/rust/run.py --checkout build/engine-eval-20260909-U3WEaS/rust-eval/manabrew --target-dir build/engine-eval-20260909-U3WEaS/rust-eval/target --output build/engine-thorough-20260909-pcbfuvZp/rust-phase
python3 tools/engine-eval/rust/run.py --checkout build/engine-eval-20260909-U3WEaS/rust-eval/manabrew --target-dir build/engine-eval-20260909-U3WEaS/rust-eval/target --output build/engine-thorough-20260909-pcbfuvZp/rust-phase --privacy --state-dir <semantic-run-directory>
python3 tools/engine-eval/rust/run.py --checkout build/engine-eval-20260909-U3WEaS/rust-eval/manabrew --target-dir build/engine-eval-20260909-U3WEaS/rust-eval/target --output build/engine-thorough-20260909-pcbfuvZp/rust-phase --games
python3 tools/engine-eval/rust/finalize.py --candidate rust --runs <semantic-run-directory> <privacy-run-directory> --output <results.json>
python3 tools/engine-eval/report.py <results.json>
```

The runner checks the full upstream revision, copies a content-addressed test
into the isolated checkout, limits Cargo to two jobs, caps execution at 20
minutes, and preserves exact fixtures, logs, observations and compatibility
diffs in unique output directories. Runs are offline by default; `--online`
permits only Cargo's manifest/lockfile dependency resolution. Run candidates
sequentially when sharing a two-job compilation budget.

`qualification.rs` uses real card parsing, legal-action enumeration, payments,
priority, resolution, combat and state-based actions. Direct initial zone
fixtures and the previously-recorded turn state are disclosed setup. The
external channel fixture demonstrates an engine-thread callback blocked until
the evaluated host receives the correct actor's response.

`privacy.rs` separately tests the native external DTO and a minimal evaluated
host redactor. Native DTO failure is not erased by host-remediation success.
Neither result certifies all private prompts, a production adapter, native GUI,
owner deck coverage or comparative performance. `--state-dir` reconstructs the
exact saved real Morph stack/battlefield state (including the nonserialized
ZoneStore) and inspects native DTOs; it does not change card characteristics.
The same replay also checks the actual first-concession state: the departed
Bears must be absent from every zone/index and from the complete native DTO
for all four seats and the spectator. Finalization requires the DTO replay's
source-state directory to match the selected semantic run.

The privacy probe additionally moves a previously public card into a multi-card
library through engine zone primitives and invokes its real seeded shuffle.
It asserts count-only library DTOs and absence of the previously public ID and
name from the entire projected payload for all three viewers. This is a
projection-boundary audit, not an additional spell-specific qualification.

All earlier fixture iterations remain preserved. In particular, the historical
Flying/Haste report-label mistake is not repeated or counted here.

## Thorough follow-up, 2026-09-09

All seventeen scenarios now have executed outcomes: 14 PASS, 2 FAIL (native
hidden views and Morph), 1 UNSUPPORTED (Adventure). No missing evaluator is
classified as an engine failure. Canonical observations are in
`build/engine-thorough-20260909-pcbfuvZp/rust-phase/rust-results.json`.

Commander tax and damage use registered four-player Commander games, actual
normal payment, a separate insufficient-mana branch, actual noncombat damage,
actual combat and a subsequent surviving controller decision. MDFC uses the
native BackFaceLand choice and normal mana activation after a real untap.

Adventure data is present and parsed, but `card/card_assembly.rs` only preserves
alternate faces for `is_dual_faced`; Adventure is excluded.
`card/card_factory_util.rs::setup_adventure_ability` returns `None`. Executing
the normal option confirms it casts the creature, not the Adventure spell.
Morph pays three but remains face-up with printed characteristics on the stack.
Resolution creates a face-down 2/2; subsequent legal choices contain no face-up
activation. Native DTO and the minimal hand-redactor expose the stack name to
opponent/spectator; battlefield DTO names are correctly hidden. These are
specific engine/adapter gaps, not a language-based selection judgment.

The two frozen Prepare extensions also execute using the actual bundled
Goblin Glasswright/Craft with Pride script. Both are UNSUPPORTED: the parser
does not recognize the Prepare split type and AlterAttribute has no Prepared
handling. Paid creature entry and a separate real Bolt-removal control succeed,
but no prepared copy exists. Generate the separate extension report with:

```sh
python3 tools/engine-eval/rust/finalize.py --candidate rust --suite tools/engine-eval/extensions.json --runs <prepare-run-directory> --output <prepare-results.json>
python3 tools/engine-eval/report.py --suite tools/engine-eval/extensions.json <prepare-results.json>
```

Adventure and Prepare are explicitly incomplete capability diagnostics:
their executed missing-hook assertions establish UNSUPPORTED at this pin,
but `coverageComplete=false` prevents a future successful initial hook check
from being promoted to a complete lifecycle PASS. A future implementation
requires a full normal token/exile/recast or prepared-copy lifecycle probe.

`games.rs` separately completes two- and four-player games from normal opening
hands to natural combat elimination. Each seat has a synthetic 30 Forest / 30
Grizzly Bears deck (not a legal tournament deck or an owner-provided deck).
Priority, opening keeps, payment confirmation, combat choices and discards
cross a bounded external controller channel with actor validation. The script
chooses first legal casts, all available attacks and no blocks; this exercises
the human-controller interface, not actual human users or a native GUI. The
four-player run continues after elimination and naturally produces one winner.
Exact decision/state traces are preserved; prompt counts are not speed metrics.
