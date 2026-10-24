# Production Forge JVM comparison

This opt-in Linux benchmark compares three separate production `NativeHost`
processes with one `NativeHost --max-games 3`, using the same supplied immutable
runtime. It does not compile, patch, replace or deploy the host.

Requirements: Java 21, Python 3, a current shared-worker Forge runtime, and
readable `/proc/<pid>/smaps_rollup`. Run separately from builds and other
performance tests, using a new output directory:

```sh
python3 tools/forge-shared-jvm/run.py \
  --runtime /absolute/path/to/hexproof-forge-runtime \
  --output build/forge-shared-jvm/new-run \
  --rounds 2 --waves 3 --abort-between-waves --heap 768
```

Each wave opens three concurrent 1v1 games, drives them to natural wins and
checks game/player identity, allowed cards and opponent/spectator redaction.
The synthetic Forest/Elvish Visionary and Plains/Glory Seeker decks exceed
copy limits; this exercises hosting and engine behavior, not format legality.
Separate mode starts fresh processes each wave; shared mode reuses one JVM.
`--abort-between-waves` also replaces one shared game while asserting that its
neighbors' prompts and public snapshots stay unchanged. Alternating mode order
reduces order bias. Defaults are two rounds, two waves and a 512 MiB heap per JVM.

Output retains runtime/source hashes, commands, decision transcripts, stderr,
latency summaries and memory samples, including on failure. The driver closes
its own JVMs. PSS and RSS are sampled every 100 ms and cover only the JVMs;
reported peaks are not exact kernel maxima or server capacity guarantees.
This benchmark does not replace the production isolation regressions in the
[native test suite](../../third_party/forge-runtime/native-host/TESTING.md) or
`TestLiveSharedForgePool` in the Go suite.

The retired adapter-2 prototype and its negative isolation probes remain in
Git history; they are no longer a runnable mode of this benchmark.
