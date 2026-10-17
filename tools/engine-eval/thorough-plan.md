# Thorough engine qualification follow-up

Owner request: 2026-09-09, after the first qualification round left unimplemented
fixtures and prematurely stopped two builds. This is an execution checklist,
not permission to change production backends or an assertion that all MTG rules
can be exhaustively certified.

Evidence root for this run: `build/engine-thorough-20260909-pcbfuvZp/`.
Keep the original `2026-09-09.2` seventeen-case contract unchanged. New mechanics
use separately frozen extensions; keep old and new evidence distinguishable.

## Completion criteria

1. Finish the seventeen shared scenarios for the eight initial runtime/build
   candidates. A missing evaluator is work to complete, not evidence of engine
   failure. Resolve the Forge authenticated-actor seam and XMage Morph ambiguity
   with observable actions. Investigate failures to distinguish fixture,
   adapter, bundled card data and engine behavior. Preserve failing tests rather
   than repairing the engine to improve its score.
2. Build Magarena and Wagic with their upstream-compatible native toolchains.
   Install declared tools using the machine's native package manager. If sudo
   requires the owner's password, request installation without requesting the
   password and continue independent work. Try supported alternatives before
   calling a candidate blocked. Execute real two-player rules tests even where
   source evidence excludes four-player Commander.
3. Verify the frozen Prepare scenarios against official rules/card information;
   distinguish absence of the named card from absence of the mechanic. Extend
   core testing to complete two-player and four-player games, hidden views and
   post-elimination continuation. Reference decks must be labeled synthetic
   unless the owner provides actual decks; deck parsing is not gameplay proof.
4. Verify the actual Hexproof/Forge authenticated WebSocket boundary, spectator
   projections, wrong/stale responses, reconnect, BO3 sideboarding and terminal
   cleanup against the real Java runtime. Independently drive shortlisted
   alternative backends through the same native test UI; do not present this as
   production integration or substitute Forge-only tests for an alternative.
5. Run repeatable serial and concurrent local workloads, including longer
   runs, after builds finish. Record JVM/process settings, startup, response
   latency, memory, failures and cleanup. Do not claim equal-state engine speed
   ratios from different shuffles, workloads or prompt granularity. Do not
   project local synthetic results onto AWS capacity or card-image latency.
6. Revisit the additional public-source candidates using verified declared
   prerequisites and actual execution where a credible rules path is available.
   Document source-access and architectural exclusion evidence separately from
   unattempted builds. Do not call a candidate eliminated only because it is
   old, uses another language, or lacks an evaluation adapter.
7. Independently review assertions, rerun applicable tests, retain negative
   controls, publish a candid evidence matrix and remaining precise blockers.
   Commit the laboratory changes; do not push, release or deploy.

## Coordination

- Root: Forge authenticated seam, extension contract, cross-engine orchestration,
  further candidates and final native/performance verification.
- Rust/Phase worker: missing scenarios and complete interactive games.
- XMage worker: Morph, Prepare and broader human/multiplayer lifecycle.
- Other-engine worker: supported Magarena/Wagic builds and semantic probes,
  then Argentum/TypeScript gaps once capacity is available.

Builds use at most two workers each and bounded JVM heaps. Performance runs
wait until competing builds stop. Test profiles, services and process groups
are local and owned by this evaluation. The user's untracked `hex-img/` files,
normal application profiles, default Java selection and Qt 6 configuration
remain untouched.

## Evidence resolution

The seventeen-case evaluators now cover all eight candidates without a missing
evaluator status. Unsupported named cards/architectures remain explicitly
unsupported, rather than being fabricated as executed gameplay. Magarena and
Wagic run with compatible native toolchains; all eight candidates also have a
separate Prepare result, including catalog probes where casting cannot begin.
XMage's unregistered existing Prepare classes were additionally exercised in
an explicitly curated variant.

Native Forge/XMage reference games, real Forge WebSocket lifecycle cases,
additional candidate execution, independent assertion review and negative
controls are recorded in `docs/engine-thorough-results.md`. The complete
200-game shared-JVM cohort passed. After correcting the test-only XMage
working-directory/database isolation, all 72 independent-process reference
games passed across the eighteen final serial/concurrent cohorts. Their
startup, response percentiles, sampled memory, projection sizes and normal
cleanup are indexed in the report, separately from the shared-JVM run.

Two external-access boundaries remain: Incantus needs owner approval for the
isolated legacy-runtime fallback and a usable card database; DeepScry has no
established public engine source/local artifact. Neither is silently omitted,
passed, or rejected for its implementation language. No production backend,
remote deployment, release or upstream rules patch is part of this work.
