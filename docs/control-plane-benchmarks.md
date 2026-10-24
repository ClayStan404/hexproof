# Control-plane interference benchmarks

Run from the repository root:

```sh
python3 tools/benchmark-control-plane.py
python3 tools/benchmark-control-plane.py --baseline FULL_COMMIT_SHA --rounds 100 --repeat 3
```

The first command measures the working tree. Replace `FULL_COMMIT_SHA`
with the exact revision to compare. The second command also measures that revision using the same benchmark fixtures, Go toolchain,
filesystem and GOMAXPROCS (default 4). It archives only the historical server
source into a new directory under `build/`; it does not change the checkout or
Git index. Go and Python 3.12 or later are required. Existing Go module
dependencies use the normal module cache; no extra packages are needed.

Each round starts one dependency call, holds it, starts eight probes together,
releases the held call after 20 ms, and drains all nine operations. Probe latency
starts at cohort release, including goroutine scheduling. Every response is
validated; failed requests or missing scenarios invalidate the run. Each
scenario runs 100 rounds per repetition by default, with three repetitions.
Revision order alternates between repetitions and Go packages run sequentially.
Avoid other builds or stress tests while collecting measurements.

| Scenario | Stalled operation | Concurrent probes |
|---|---|---|
| AccountAdmission/Independent | Account A validation over loopback HTTP | Eight other accounts, all in different former hash buckets |
| AccountAdmission/LegacyCollision | Account A validation over loopback HTTP | Eight distinct accounts deliberately sharing A's former hash bucket |
| AccountAdmission/SameAccount | Account A validation over loopback HTTP | Eight commands for the same account/connection |
| AccountStore/Independent | Account A rename at persistence | Credential checks for eight other accounts |
| AccountStore/SameAccount | Account A rename at persistence | Eight credential checks for account A |
| Cluster/CacheDuringReport | Publication over loopback HTTP | Cached capability reads |
| Cluster/RPCDuringReport | Publication over loopback HTTP | Independent directory RPCs |
| Cluster/RPCDuringRPC | One directory RPC over loopback HTTP | Eight more directory RPCs |

The account/cluster HTTP fixtures use the real authenticated transport and
production dispatcher/agent. Account-store fixtures fill all 16 device slots and
keep the real JSON write, file sync and atomic rename after the injected delay.
Same-account cases are serialization controls: they should continue waiting.
The deliberate collision case characterizes the old defect, not its frequency
in a live account population. The store's temporary directories live on the
artifact directory's filesystem and are removed by Go after the run.

The output directory contains `report.md`, all raw Go benchmark logs,
`results.json`, `metadata.json` and a fixture source snapshot. Metadata includes revisions, working-tree
status/diff, fixture hashes, platform/toolchain and exact commands. A historical
store that predates the test persistence hook receives that hook in the archived
copy only. Its original lock scope and save implementation remain intact; the
complete change is recorded in `baseline-instrumentation.diff`. Unsupported
historical source layouts fail explicitly. Keep the artifact directory when
sharing a comparison so this adjustment is reviewable.

The report shows the median of per-run probe p95s and the current p95 range.
Raw data also contains p50/p99/max, failures, and actual slow-call latency.
Current account admission reports include mean/max gate wait from `/readyz`;
those values cover both the slow call and probes. Older revisions without that
telemetry omit it. All account IDs and service keys are synthetic test fixtures.

Go `ns/op` is per nine-request batch. `cohort-requests/s` is the completion rate
of this deliberately paced workload, not maximum server throughput. Do not
turn these numbers into a production capacity or WAN latency claim. Open-loop
saturation, cancellation, live client workflows, GUI and Forge verification are
separate checks. These opt-in benchmarks have no absolute time threshold in CI.

For a quick fixture check or race check:

```sh
python3 tools/benchmark-control-plane.py --rounds 2 --repeat 1
go -C apps/server test -race -p 1 -run '^Test(Stall|Percentile)' \
  -bench '^BenchmarkControlPlane' -benchtime 2x -count 1 -cpu 4 \
  ./internal/benchutil ./internal/accounts ./internal/cluster ./internal/server
python3 -m unittest discover -s tools/tests -p test_control_plane_benchmark.py
```

Race-instrumented timings validate the fixtures only; use a normal run for the
performance report. The short run has too few samples for useful tail estimates.
