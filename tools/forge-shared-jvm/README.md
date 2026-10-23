# Shared Forge JVM experiment

This opt-in Linux experiment measures multiple concurrent 1v1 games in one JVM.
It compiles two experiment classes against an existing immutable Forge runtime;
it does not rebuild, patch, replace, or deploy that runtime. The production
`NativeHost` and Go supervisor retain one fresh process per game by default.

## Adapter 3 qualification

For the implemented shared worker, use `--production --only games`. This runs
the packaged `NativeHost --max-games 3`, without compiling the historical
prototype or interpreting its negative probes as passing isolation tests:

```sh
python3 tools/forge-shared-jvm/run.py --production --only games \
  --runtime /absolute/path/to/adapter-3-runtime \
  --output build/forge-next-iteration/shared-comparison \
  --rounds 2 --waves 3 --abort-between-waves --heap 768
```

Positive RNG/ID/cache, blocked-menu, callback ownership and task-collection
regressions run in `build-native.py`. `TestLiveSharedForgePool` separately
qualifies the actual Go pool and native transport with concurrent complete
games and slot replacement. Historical instructions below require their
original runtime and retain their original meaning.

## Run locally

Requirements: Java/Javac 21, Python 3, the pinned adapter 2 runtime, and readable
`/proc/<pid>/smaps_rollup`. No additional packages are needed. Use a new output
directory for every invocation; existing evidence is never overwritten.

```sh
systemd-run --user --unit=hexproof-shared-jvm-experiment --wait --pipe \
  -p MemoryMax=3G -p MemorySwapMax=0 -p CPUQuota=200% -p RuntimeMaxSec=900 \
  --working-directory="$PWD" \
  /usr/bin/python3 tools/forge-shared-jvm/run.py \
  --runtime /absolute/path/to/hexproof-forge-runtime \
  --output build/forge-shared-jvm/new-run
```

The user service bounds only this experiment, requires no root access, and
terminates its children on timeout. The Python driver also closes its own JVMs
on normal completion or failure. `--only games` or `--only isolation` selects a
subset. `--rounds` and `--waves` default to two; `--heap` defaults to 512 MiB per
JVM. Ambient Java option variables are removed from child environments.

## What is measured

- **Separate baseline:** three instances of the packaged production
  `org.hexproof.forge.NativeHost`, each with one game. The next wave uses fresh
  processes, matching the production lifecycle.
- **Shared prototype:** one `SharedJvmHost`, holding three unmodified
  `NativeSession` instances and the original shared `NativeGuiBase`. It loads
  the card database once, serializes game construction, and introduces request
  IDs and three RPC workers solely in this experimental transport. The next
  wave reuses the JVM. This is concurrent game hosting, not just sequential
  process reuse. Each game has one outstanding RPC, while different games can
  submit and resolve actions concurrently.
- Every wave opens all three games before starting three independent player
  drivers. Two use Forest/Elvish Visionary and one uses Plains/Glory Seeker.
  The synthetic 60-card decks exceed copy limits; this is Constructed engine
  mechanism coverage, not legal deck validation. Drivers explicitly keep,
  select lands, cast creatures, pay mana, attack, decline blocks, and discard
  at cleanup. Native Forge owns all game changes and lethal combat outcomes.
  ETB draw resolution must be observed in each Visionary game.
- Every decision checks game IDs, player names, allowed card identities, both
  players' snapshots, and spectator redaction. Closing each wave records heap
  use after explicit GC, thread count, and weak references to closed sessions
  that remain reachable.
- `/proc` is sampled every 100 ms. Summed simultaneous **PSS** attributes
  shared mapped pages proportionally; summed **RSS** counts them in each JVM.
  Both are reported as sampled peaks, not exact maxima or server-wide memory.
  Go, Qt, Python and filesystem page cache are outside these JVM metrics.
  All JVMs use `-Xms32m`, the selected heap ceiling, Serial GC, and two visible
  processors. Alternating baseline/shared order reduces order bias. Startup,
  snapshot serialization, JIT and GC remain included in the workload.

## Negative isolation controls

`hazardReproduced: true` means the unsafe behavior was reproduced. It is not a
claim that the shared prototype passed production qualification.

1. **Random state:** a real `Player.shuffle` repeats with the same library and
   RNG seed. Starting another real session replaces the global RNG and changes
   the first game's shuffle. This proves interference, not disclosure or a
   measured statistical bias.
2. **Blocked input:** a real synchronous native number callback is injected
   into the first game's opening hook on the shared GUI dispatcher. The second
   game's mulligan reply cannot advance for at least 750 ms. Answering the
   first menu releases both. The probe exercises native input infrastructure,
   not a particular card's complete casting sequence.
3. **Failure routing:** a deliberately thrown callback error belonging to the
   first game goes to the last installed failure handler, marking the second
   game failed. This demonstrates the routing defect in a naive multi-session
   host; it is not a crash observed in the single-game production host.

For the separate abort/replacement lifecycle probe, add
`--only games --rounds 1 --waves 2 --abort-between-waves`. In later shared
waves, one opening game is aborted; the other games' prompt and public snapshot
must remain byte-identical immediately afterwards. Its slot is reused and all
survivors/replacement are driven toward natural wins. The unmodified host can
fail this test when an old callback reaches the shared dispatcher after close.
The driver exits nonzero and retains the failing game IDs and stderr. Do not
merge that interrupted workload into a successful memory comparison.

## Evidence and limits

Output includes source/JAR hashes, JVM version, commands, per-game JSONL decision
transcripts, stderr, memory samples and JSON results. Failures retain their
evidence. Isolated profiles live only under the chosen output directory.

The prototype is intentionally incomplete and must not be deployed. It does
not offer per-game RNG, GUI dispatch or failure isolation, authenticated
viewer/action routing, cancellation-safe multiplexing, or protection against a
worker-wide JVM crash/OOM. The Qt UI, Go coordinator, BO3, Duel Commander,
arbitrary card interactions, and long-running leak behavior are not qualified
by these tests. See [the experiment report](../../docs/forge-shared-jvm-experiment.md)
for measured results and the next implementation boundary.
