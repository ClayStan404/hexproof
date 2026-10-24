# UI behavior acceptance baseline

The maintained acceptance command covers the phase rail and the glass-theme
image-view deck editor. The historical interaction reference is the public
[v2.5.0 release](https://github.com/ClayStan404/hexproof/releases/tag/v2.5.0).
This identifies the reference version; it does not require restoring its
implementation or claim that every defect was introduced after that version.

The [contract manifest](../tools/ui-automation/ui-behavior-baseline.json)
separates compatibility expectations from extensions protecting current
double-face previews and cache progress. Change an expectation only alongside
an explained behavior/specification change. A larger test count or a generic
scenario `passed` result cannot replace the required observations.

| Area | Required behavior |
| --- | --- |
| Phase rail | The reported 1280 × 686 logical viewport at scale 1 retains all eleven rows and reachable compact actions. |
| Phase transitions | Resize, interface scale and language changes retain the authoritative phase and submit no action. A deliberate selection sends one stable phase identifier. |
| Gallery wheel | Single-notch travel stays above the historical 48-unit floor, allowing rounding. Same-direction travel accumulates without reversal; opposite input reverses travel. Scrolling pauses inspection and a stationary pointer recovers it. |
| Preview input | Wheel input over both actual preview face images reaches the gallery. |
| Preview refresh | Real metadata publication retains the exact printing while inspection is sourced from a tile or held over the preview. |
| Count controls | The first click increments exactly the selected printing once, including while hover-triggered cache activity starts. Gallery and button geometry stay stable. |
| Cache and scrollbar | Explicit caching visibly reports progress without moving the gallery. Dragging its scrollbar takes control without later pullback. |

The automated suites additionally cover fine wheel deltas and phase-command
routing. Native scenarios use the production QML/backend with an isolated
manual-table projection and a generated deck containing 80 mainboard and 20
sideboard rows, multiple printings, full face metadata, and synthetic PNG art.
No installed catalog, saved owner deck, public room or real artwork is needed.
Two deliberately stale saved metadata fields exercise actual backend
publication; an absent publication or cache pulse fails its case.

## Run the checks

Build the audit client and QML test runner incrementally on the test workstation:

```sh
cmake -S apps/client-qt -B build/client-qt -G Ninja -DHEXPROOF_BUILD_NATIVE_AUDIT=ON
cmake --build build/client-qt --target hexproof_native_audit hexproof_qml_test
```

On the supported authenticated GNOME/XWayland workstation, with its display
and session bus available, run:

```sh
QT_QPA_PLATFORM=xcb python3 tools/ui-automation/run-ui-baseline.py \
  --output build/ui-behavior-baseline/review-001 \
  --os-input-helper tools/ui-automation/mutter-input.py
```

Use a new output directory for each attempt. The command runs seven focused QML
suites, prepares the portable fixture, and runs the phase and deck scenarios
sequentially. The primary windows start maximized on the actual display; the
phase scenario then makes an explicit fixed-window supplement. Review the
retained screenshots for the requested visual behavior. See the
[system-input guide](system-input-verification.md#input-method) for helper
prerequisites and its owned-window input restrictions. Unsupported desktop or
helper startup failures do not select a Qt-event fallback.

For automated guards alone:

```sh
python3 tools/ui-automation/run-ui-baseline.py \
  --checks-only --output build/ui-behavior-baseline/checks-001
```

This reports `qualification: automated-only` and `native.status: not-run`,
never full native acceptance. The QML guards also remain in normal CTest
coverage; validator, fixture and orchestration tests run through existing
`tools/tests` discovery in static verification and CI.

## Optional Forge smoothness benchmark

For a Forge update-cost investigation, the existing opt-in benchmark is
separate from the interaction acceptance command above and normal CTest:

```sh
QT_QPA_PLATFORM=offscreen ./build/client-qt/hexproof_qml_test \
  -input apps/client-qt/tests/bench/tst_forgesmoothness.qml \
  -import apps/client-qt/qml ForgeSmoothness::test_reportBudgets
```

Each case takes the trimmed mean of 30 settled samples: the update and its
event-loop work, minus the same passes while idle. Running motion finishes
between samples. Both ordinary and crowded fixture boards run with motion off
and on; output ends with a `FORGE_BENCH` JSON record. Advisory budgets are 4 ms
for quiet snapshots, 6 ms for structural snapshots, 5 ms for prompts, 10 ms for
whole decisions and 8 ms for crowded updates. Timing does not fail tests;
deterministic invariants, including no repeat card lookup on a global image
revision, still do. Run comparable before/after cases on the same workstation,
separately from builds and race tests. This offscreen update-cost measurement
does not establish rendered frame pacing or native input responsiveness.

The historical default-renderer check on 2026-10-07 used maximized
1920 × 1010 logical windows at DPR 2 on a 160 Hz GNOME display, under native
Wayland and XWayland. `HEXPROOF_MOTION=1` was set; `QSG_NO_VSYNC`,
`QSG_RENDER_LOOP` and `QSG_RHI_BACKEND` were unset. Both fixture runs recorded
a 6 ms frame median and 9 ms p95, with longer fixture-induced pauses; these are
bounded historical observations, not current frame-rate guarantees. The owner
waived the Windows sample for that decision; Windows rendering was not
qualified. Motion was enabled despite a crowded update of about 9 ms against
the advisory 8 ms target. The original measurements and retained evidence paths
remain in the retired smoothness design through the [history index](README.md).
New rendering/performance changes require evidence appropriate to the affected
platform; the historical waiver is not a permanent platform exemption.

## Evidence and limits

`report.json` reaches `qualification: passed` only when all required automated
suites and native contracts pass. Each native run retains isolated profiles,
frozen scenario sources, screenshots, startup geometry, action receipts,
observed metrics and audit summaries. The independent validator requires the
expected case IDs, typed bounds, fixture capabilities, maximized startup,
verified system input, and zero failed actions or QML warnings. Previous failed
attempts remain separate; missing prerequisites are failures, not skips.

The runner supplies a local refusing HTTP(S) proxy without forwarding requests.
This keeps synthetic fixture checks independent of online artwork while
retaining the compositor session bus. It is not network-namespace isolation.
The existing native runner owns process cleanup and serializes display access.

These checks establish interaction and layout acceptance. They do not measure
GPU/frame-time performance, physical mouse polling, whole-display flashing,
real-artwork rendering cost, or an old-binary/new-binary performance comparison.
Reports explicitly retain `performance: not-assessed`. Investigate unresolved
visual or performance feedback with a separate trace and native observation;
do not infer its resolution from this baseline's green result.
