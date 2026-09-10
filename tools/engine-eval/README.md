# Rules-engine selection laboratory

This is an isolated evaluation, not a production rules-engine integration. The
production Forge feature stays opt-in. Never point a probe at a public server.

The first reviewed run is historical. The substantially expanded actual builds,
shared-case results, native trials and remaining selection gates are recorded in
[the empirical follow-up](../../docs/engine-thorough-results.md). Raw evidence
paths are local and are not uploaded with the tools.

`scenarios.json` version `2026-09-09.1` freezes the first shared qualification
round; `.2` corrects only the unexecuted commander-damage fixture (Isamaru is
2/2: 19 previous damage plus 2, not 20 plus 1). Its defaults and **every assertion** of a case apply. A result from a
different setup is supplemental evidence, not a pass for that case. Direct
fixture setup is acceptable when disclosed; mutating the outcome instead of
executing the action is not. A seed does not guarantee equivalent shuffles
between engines. Keep explicit library order or assert order-independent facts.

## Result interchange

Every runner writes a JSON object with `schemaVersion: 1`, `suiteVersion`,
`candidate`, `source` (URL, immutable `revision`, and `patches` list), `cases`,
and optional `notes`. Each case is an object:

```json
{
  "id": "bolt_player",
  "status": "PASS",
  "layer": "engine",
  "reason": "Actual casting, payment, stack and resolution assertions passed.",
  "assertionsPassed": 3,
  "assertionsFailed": 0,
  "setup": "Direct opening fixture; normal cast action and legality checks.",
  "observed": {"lifeBefore": 20, "lifeAfter": 17},
  "evidence": ["bolt-player.log"]
}
```

Status meanings:

- `PASS`: the exact frozen fixture and **all** its assertions actually ran.
  Passing compilation, parsing a card, empty/skipped tests, and partial tests
  cannot be promoted to `PASS`.
- `FAIL`: an executed assertion violated the expected behavior. State whether
  the root cause is confirmed engine behavior, an adapter defect, or unknown.
- `UNSUPPORTED`: a known missing capability, with runtime or pinned-source
  evidence. An unimplemented evaluator is **not** an unsupported engine.
- `UNVERIFIED`: not executed, incomplete fixture, or no suitable external seam
  implemented yet. Preserve useful partial observations without inventing a pass.
- `BLOCKED`: attempted execution could not proceed (e.g. missing declared build
  tool); record the exact failure and what would unblock it.

`layer` is `engine`, `adapter`, `fixture`, `build`, or `unknown`. Store evidence
paths relative to the result file; retain raw stdout/stderr in the same artifact
tree. Include observed state transitions, not merely a success banner. Preserve
event ordering, target identities, amounts and multiplicity when comparing traces.
Record timeouts and exceptions; do not silently skip a failed test. Missing cases
remain unverified in aggregate reports. Do not count upstream test totals as
shared qualification results. Keep patched and unpatched results distinguishable.

## Selection policy

The target is interactive 1v1, four-player EDH, and limited deck play in Hexproof,
not an AI-only simulator. External human decisions, hidden-information projection,
four-player continuity, correctness of priority/stack/combat, integration effort,
maintenance and licensing are qualification dimensions. A thin host projection
may remediate a missing native view; record that work rather than equating absence
with an inherent engine failure. Existing Forge adapter maturity is disclosed,
not silently treated as engine superiority. Hexproof's current server implementation
uses concrete Forge client types: a second engine is not a drop-in switch today.

The initial candidates are Forge Java, Manabrew Rust, XMage, Phase, mtg-forge-ts,
Magarena and Wagic. Expand the inventory when credible candidates are found;
`UNVERIFIED` candidates cannot be called eliminated or silently omitted. Freeze
added scenarios before running them and explain changes to the suite version.

Upstream rules, not a selected implementation, are the behavioral authority:
[Wizards Comprehensive Rules](https://magic.wizards.com/en/rules), currently
linking [this text](https://media.wizards.com/2026/downloads/MagicCompRules%2020260819.txt).
The filename is dated 2026-08-19 but its header says effective 2026-08-07;
pin the downloaded bytes and record both. Card-specific fixtures require Oracle
text/rulings where the rulebook alone does not specify the effect. A missing new
card needs to be distinguished from an unsupported mechanic.

Performance is a later phase, not a score inferred from these diagnostic runs.
Run identical semantic workloads sequentially, with release settings, documented
CPU/memory budgets, separate cold-start/warmup, repeated p50/p95 latency and
aggregate process-tree RSS. Keep engine compute, adapter serialization, wire size,
network delay and card-image downloads separate. No production network shaping.
Finalists then get the same local native-client interaction trial; incomplete
adapters and unseen GUI states remain explicit gaps. Do not announce a final
winner until those stages and representative decks have been evaluated.

## Local human-interface trial

`gui/` is a small native Qt Widgets hot-seat laboratory, **not** the production
Hexproof client. It proves that a real external GUI can drive human decisions,
not that another engine is already integrated with Hexproof's QML table. It
deliberately has no card images, network authentication, matchmaking, or public
listener. Its trusted process receives separate owner/opponent/spectator views;
the shared process must never be exposed as an untrusted player's transport.

Build it with the existing Qt toolchain:

```sh
cmake -S tools/engine-eval/gui -B build/engine-lab -G Ninja
cmake --build build/engine-lab -j2
build/engine-lab/engine-lab /new/isolated/evidence -- backend-command arguments
```

With `--auto`, actual Qt mouse events click the displayed buttons. The same
policy prefers keep, land, creature cast, payment confirmation, mana, all legal
attackers, no blockers, and pass. Both test decks contain 30 Forest and 30
Grizzly Bears. These are synthetic engine fixtures, not legal constructed decks.
Do not claim AI strength, sophisticated strategy, or coverage of other prompts.
Only this test window is captured. Profiles, logs and screenshots belong under
a unique `build/` directory. Run on the user's actual native display when
available; offscreen rendering must be reported as offscreen.

The stdin/stdout JSONL bridge exchanges `decision` objects with `id`, `actor`,
`kind`, `actions` (`label`, `category`, opaque `response`) and normalized `views`.
Responses echo the decision id and actor. A `result` must include the final
public `view.players` life totals and `gameOver`. This is a **test protocol**,
not a new `hexproof.v1` schema or a production authorization boundary.

## Sequential responsiveness diagnostics

`drive.py` drives the same bridge without GUI think time. It requires Linux
`/proc` for process-tree RSS and rejects unsupported platforms instead of
reporting zero memory. Run candidates
**sequentially after builds stop**, on the same machine, with the same documented
JVM settings (`ActiveProcessorCount=2`, maximum heap 2 GiB) and three new processes
per candidate. These are JVM settings, not OS CPU affinity or a total-RSS cap:

```sh
python3 tools/engine-eval/drive.py --candidate NAME --repeat 3 \
  --output build/engine-responsiveness -- backend-command arguments
```

The frozen workload is `interactive_bears_v1`: the decks and policy above,
20 starting life, two players, natural lethal result required, 120-second and
1,500-decision bounds. `{profile}` in a backend argument expands to a fresh
isolated profile. The first 20 decisions are excluded from warmed IPC latency;
startup-to-first-decision, per-view JSON sizes, p50/p95 response-to-next-decision
latency, and sampled aggregate process-tree RSS remain separate. No caches are
flushed; "new process" does not mean cold disk cache. Shuffles and prompt
granularity can differ, so these are interactive responsiveness/reliability
diagnostics, **not** an engine-only speed ratio or a production capacity ranking.
OS scheduling, GC and instrumentation noise remain visible in raw traces.

## Expanded reference games and repeated cohorts

`workloads.json` freezes three reference decks and policies: 40-card mixed
creatures, 60-card burn, and four-player 100-card Commander. These are synthetic
workloads, not owner decks or competitive-format deck recommendations.
`workload_driver.py` supports both Forge and XMage trusted bridges:

```sh
python3 tools/engine-eval/workload_driver.py --output build/reference-games \
  --workload-id commander_green_100 --repeat 4 --concurrency 2 -- \
  backend-command arguments
build/engine-lab/engine-lab /new/isolated/gui-evidence --auto \
  --workload tools/engine-eval/workloads.json commander_green_100 -- \
  backend-command arguments
```

The backend must select the same workload; see `forge/README.md` and
`xmage/README.md` for launch arguments. The driver checks actual initial
life/card/commander counts, every player and spectator view, every chosen land
transfer and every newly paid cast, and natural terminal state for all players.
The GUI uses actual Qt mouse events; it is still a test interface, not a second
production engine integration.

Use sequential cohorts only after competing builds/tests finish. Concurrency
means separate trusted host processes, **not** shared-server games. Report
startup, warmed IPC p50/p95, sampled process-tree RSS, JSON size, run counts and
failures separately. The real shared-JVM Forge lifecycle stress instead lives
in `TestLiveForgeSharedRuntimeRooms` under the opt-in `engineintegration` tag.
Its high test-only room/rate limits do not change production limits.

`extensions.json` freezes the separate Prepare cases. Passing a partial parser
or catalog probe cannot satisfy these gameplay assertions. A representation
contract failure is not automatically a gameplay-rule defect.

`capture.py` preserves a bounded command, process identity, output and exit
status under a fresh directory. `upstream_report.py` counts actual JUnit/TRX
case records, including failures and skips; an upstream suite is never counted
as the seventeen shared cases. All adapters are local test code, and raw engine
state must not become a public service.
