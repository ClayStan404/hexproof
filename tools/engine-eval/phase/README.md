# Phase qualification

<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 Hexproof contributors -->

```sh
python3 tools/engine-eval/phase/run.py --checkout build/engine-eval-20260909-U3WEaS/rust-eval/phase --target-dir build/engine-eval-20260909-U3WEaS/rust-eval/phase-target --output build/engine-thorough-20260909-pcbfuvZp/rust-phase
python3 tools/engine-eval/phase/run.py --checkout build/engine-eval-20260909-U3WEaS/rust-eval/phase --target-dir build/engine-eval-20260909-U3WEaS/rust-eval/phase-target --output build/engine-thorough-20260909-pcbfuvZp/rust-phase --games
python3 tools/engine-eval/rust/finalize.py --candidate phase --runs <reviewed-run-directory> --output <results.json>
python3 tools/engine-eval/report.py <results.json>
```

The shared bounded runner checks revision
`87b8355cc1b0771f5152bd33cee8f81a5f0550cb`. The isolated checkout's only
compatibility change removes unstable Cargo feature/codegen-backend manifest
settings; each run records that diff. Engine source is unchanged.

The independent fixture uses GameScenario's inline Oracle parser and the real
action reducer, cast/payment builder, priority, combat, and viewer projection.
It is not a full card-database/deck-ingestion qualification. Direct zone and
format setup is explicit; commander-damage prior history and the separate
insufficient-mana branch are initial conditions, not expected outcomes.

The canonical Morph fixture uses normal casting with the explicit face-down
alternative and real three-mana payment, then the paid face-up special action.
An earlier fixture incorrectly used the separate PlayFaceDown setup-like
action; its observations are retained but excluded from canonical results.

Inspect each assertion and exact saved fixture when interpreting a result.
Missing evaluators remain UNVERIFIED. Debug runs are not performance rankings,
and successful headless tests do not certify Hexproof's native GUI or production
adapter.

The strengthened privacy case also casts Time Ebb on a publicly identified
Grizzly Bears, invokes the engine's real seeded shuffle on the 31-card library,
and compares the three viewer projections with the authoritative shuffled
order. Stable opaque IDs can disclose identity and order even when names are
blank. This supersedes the earlier names-only privacy PASS; it does not alter
the frozen privacy requirement.
The final audit enumerates every authoritative private library ID across all
players and checks its absence from every projected library list and object
map. Removing only the once-public Bears ID cannot pass this assertion.
Identity comparisons use exact ObjectId integers, not number substrings.

## Thorough follow-up, 2026-09-09

All seventeen scenarios now have executed outcomes: 14 PASS, 3 FAIL (library
identity/order privacy, departing owned objects left in public exile, and a
Commander damage elimination leaving an eliminated seat's choice pending).
Continuation now requires an actual non-eliminated priority actor, successful
native submission of that actor's pass, and a changed state; an absent actor
or merely a nonterminal flag cannot pass.
The new Adventure and MDFC cases both pass actual face selection and normal
payment/land-mana paths. Their independently parsed second faces are attached
as initial card data through the native face-snapshot API, never as outcomes.
MDFC's mana action comes from the human grouped legal actions: the flat AI
candidate list intentionally excludes manual mana taps outside payment.

The separate frozen Prepare extension has two FAIL results. Actual Oracle
entry parsing and normal paid casting make Goblin Glasswright prepared but
create zero associated copies in exile. A later real CastPreparedCopy action
lazily materializes a stack copy, pays R, unprepares the same creature and
resolves to one Treasure; the copy then disappears. This later success cannot
replace the missing pre-cast copy assertion. The separate Bolt-removal control
destroys the creature, but cannot prove cleanup of a copy that never existed.
No rules source is repaired. The engine has substantial Prepare support. This
is an explicit exile-object/projection mismatch against the frozen contract,
not by itself proof of a rules-observable defect: a lazy internal representation
can be valid if all game interactions remain correct. The failed contract is
retained while this distinction is explicit, rather than labeling Prepare broken.
An additional real Drannith Magistrate control passes: the creature can enter
from hand, but its prepared copy is neither offered nor accepted for casting;
the rejected attempt leaves state unchanged. This supports correct exile-cast
restriction handling despite lazy copy materialization.

```sh
python3 tools/engine-eval/rust/finalize.py --candidate phase --suite tools/engine-eval/extensions.json --runs <prepare-run-directory> --output <prepare-results.json>
python3 tools/engine-eval/report.py --suite tools/engine-eval/extensions.json <prepare-results.json>
```

Complete-game probes use synthetic 30 Forest / 30 Grizzly Bears decks, not
tournament-legal or owner-provided decks. A separate scripted controller selects
from viewer-authorized native legal actions and returns the actor plus action
to the real reducer. Simultaneous opening decisions use the engine's pending
actor set. No AI policy implementation, forced concession, outcome mutation or
Hexproof GUI is involved; traces and failures are retained independently of the
seventeen-case result contract.
