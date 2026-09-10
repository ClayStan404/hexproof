# Forge qualification and local human bridge

This probe targets the existing Hexproof patch-2 runtime: Manabrew
`143a6b556ac365cea97929ffcebb48eed03ecde8`, Forge
`753b3dd544d6f02061d796ff7a0b54806631edcb`. Its exact tested JAR SHA-256 is
`b6945da0eb250eea66208a6064b29cdc64434a52d0e4a710c74b3698e9363d1e`.
The runner refuses a different binary instead of silently changing the tested
baseline. A separately rebuilt JAR may differ because of archive metadata;
qualifying another artifact requires recording its source/patch provenance and
intentionally updating this pin. Build prerequisites and source provenance are
documented in [the runtime guide](../../../third_party/forge-runtime/README.md).

```sh
python3 tools/engine-eval/forge/run.py \
  --runtime build/forge-runtime/local-143a6b556ac365cea97929ffcebb48eed03ecde8-patch2/hexproof-forge-runtime \
  --output build/engine-selection/forge
python3 tools/engine-eval/report.py <new-run-directory>/results.json
```

Each run creates a fresh directory and Java home, captures exact probe and
scenario source, compiler/runtime commands, stdout/stderr, JSON observations,
and normalized results. It uses the real Java game loop and hosted decisions.
Except for normal opening, fixture setup replaces zones while the game thread
waits on its action queue and then refreshes legal actions. Subsequent casts,
payment, targets, stack, triggers, combat and SBA use normal engine paths.
No production runtime source is patched by this evaluator.

Fixture qualifications are explicit:

- The low-level host submission API has no authenticated actor argument. Build
  `apps/server/cmd/engine-eval-authority` and supply `--authority-helper` to run
  the actual Go `NormalizePrompt`/`BuildPromptResponse` boundary against this
  exact Java land fixture. Wrong actor/stale prompt responses are rejected with
  unchanged state; the owner response is forwarded to Java and moves one land.
  This is explicitly a joint **adapter** PASS, not native Java authentication.
  Without that helper the case remains unverified. Actual authenticated
  WebSocket, spectator and reconnect tests remain separate evidence.
- The command zone also contains internal effect objects; the fixture checks
  the actual named commander instead of incorrectly requiring one total object.
- Commander damage seeds the previous 19-point counter, then uses actual combat
  for the final two damage. Its separate prevention-free noncombat fixture calls
  the engine damage-classification and life-processing methods and verifies
  life 40 → 38 without changing the commander counter.
- A departed card must leave all active game zones and the complete spectator
  projection. A surviving player must complete a new decision after a Commander
  elimination; a nonterminal flag alone is insufficient.
- Morph checks actual stack and permanent characteristics, redacted projections,
  three-mana casting and a further 1U turn-up payment. Temporary copy effects,
  token count/characteristics, and exact spell destinations are asserted.

The `--negative-control` flag intentionally expects Bolt to deal four damage.
It must produce an assertion failure and return exit 1. This demonstrates an
executed wrong expectation is rejected; it is not a Forge defect or a normal
qualification result.

`--extensions` executes the separately frozen Prepare contract in
`extensions.json`. Goblin Glasswright actually pays 1R, enters prepared, and
creates its associated exiled spell copy. The copy pays R, enters the stack,
unprepares the original permanent, creates one Treasure and ceases to exist.
A separate real Lightning Bolt removes the prepared source and checks copy
cleanup. The original hand object is not reused after the engine's zone-change
copy: observations resolve the current battlefield object by stable ID.

`LiveBridge.java` is a separate trusted stdio hot-seat host for the shared native
Qt laboratory. Compile it against the same JAR and pass the runtime's
`forge-gui/` directory, optionally followed by `workloads.json` and a workload
ID. Default remains 30 Forest/30 Bears; the frozen reference file adds mixed
40-card, 60-card burn and four-player 100-card Commander decks. Commands remain
actual offered engine choices, including mana, targets and cleanup discard.
The host rejects wrong actors, stale IDs and unoffered payloads but is not a
public authorization boundary. No production GUI integration or card-image
loading is claimed.

The production WebSocket qualification uses the real Java runtime and
`apps/server/internal/server/forge_live*_test.go`. Its shared-runtime test
reuses one JVM for five successive waves of four concurrent rooms. Each room
finishes naturally through paid Bolt casts, with spectator/wrong-actor checks,
real socket reconnect and terminal cleanup. Only the test's message/room-create
rate limits are raised for accelerated local input; production defaults remain
unchanged. `-race` checks Go races, not Java data races.
