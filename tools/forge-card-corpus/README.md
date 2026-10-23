# Constructed card resolution corpus

This campaign freezes ten published archetypes each for Standard, Pioneer,
Modern, and Legacy. Main decks and sideboards both count. Shared cards have a
single card record with links back to every registered deck. The upstream Forge
revision stays pinned; missing cards are reported rather than substituted.

The frozen manifest records public deck facts, source URLs, event dates, and
retrieval hashes. Raw HTML and generated test evidence belong in `build/`.
`collect.py` refreshes the sample only when explicitly run; normal tests must
use the committed manifest.

Coverage has distinct levels: registration support, actual native play and
resolution, individual activated/triggered branches, projection validation,
and player UI interaction. A resolved default cast is not proof of every
ability or combination. Unsupported cards and incomplete fixtures never count
as passing. Captured native frames used for UI replay must be identified as
replay, separately from live two-client tests.

The native runner uses the packaged human controllers, actual card scripts,
legal human responses, ordinary payment, stack resolution, and state-based
actions over deterministic synthetic boards. Mana and target fixtures are
recorded as test setup, not as an ordinary match. Every case is bounded and
retains prompts, responses, before/after states, and its exact failure.

Work sequence:

1. Freeze 40 source decks and map every card to the pinned native database.
2. Run every supported card through native play/resolution; extend fixtures
   for mechanics that need a different board or event.
3. Validate captured owner/opponent/spectator projections and actual QML
   prompt interactions; inspect the maximized native client.
4. Repair reproduced product defects, rerun affected cases, and publish a
   deck-by-deck coverage ledger with unresolved branches explicitly listed.

## Reproduce the frozen campaign

Prepare the matching native runtime with `tools/local-forge-runtime.py` and
build the current Qt test executable. From the repository root, choose a fresh
output directory; the native driver refuses an existing one:

```sh
python3 tools/forge-card-corpus/run.py --abilities --output build/corpus-recheck

cd apps/server
HEXPROOF_FORGE_CORPUS_INPUT="$PWD/../../build/corpus-recheck/native.jsonl" \
HEXPROOF_FORGE_CORPUS_OUTPUT="$PWD/../../build/corpus-recheck/ui.jsonl" \
  go test ./internal/server -run TestForgeCardCorpus -count=1
cd ../..

QT_QPA_PLATFORM=offscreen \
HEXPROOF_FORGE_CORPUS_UI="$PWD/build/corpus-recheck/ui.jsonl" \
  build/client-qt/hexproof_qml_test -input apps/client-qt/tests/corpus \
  -import apps/client-qt/qml -o build/corpus-recheck/qml.log,txt

python3 tools/forge-card-corpus/report.py \
  --native build/corpus-recheck/native.jsonl --ui build/corpus-recheck/ui.jsonl \
  --ui-log build/corpus-recheck/qml.log --output build/corpus-recheck/report
```

`--cards` is a Java full-match regex for a focused native run. `--current-host`
and `--patch-source` are explicit development overlays; their source hashes
are recorded, and they do not update the selected runtime. Final qualification
uses a newly packaged runtime without these overrides. `--abilities` includes
the initial native non-spell ability inventory, including hand/graveyard
activation setup, crew, class upgrades and other recorded fixture conditions.
It does not enumerate all alternate spell faces or dynamically gained abilities.

For an actual desktop replay, select the workstation's native Qt backend and
set `HEXPROOF_FORGE_CORPUS_NATIVE=1`. The runner maximizes its isolated test
window and records its display dimensions and DPR. Optional
`HEXPROOF_FORGE_CORPUS_CAPTURES` names an existing screenshot directory;
`HEXPROOF_FORGE_CORPUS_CAPTURE_CARDS` restricts captures by JavaScript regex.
Only that test window is captured. Replay uses production QML and the real
native decision stream, with a deterministic catalog stub and no card images;
it is not a live network match or OS-input-routing check.

The report rejects missing cards/initial abilities, unresolved native cases,
missing viewer projections, skipped replay cases and Qt failures/warnings.
`coverage.json` retains the case inventory, source-deck mapping, decision
families, final zones and evidence hashes. `cards.csv` provides the compact
per-card ledger. Neither artifact counts a successful default path as proof
of every rule branch; focused native regressions assert exact outcomes for
the repaired mechanics, and live desktop scenarios are reported separately.

## Limited product extension

`limited-2026-09-22.json` freezes the installed EOE Play product's 321 names and
41 Cube fixture printings (357 distinct names). Pass it with `--manifest` to
both `run.py` and `report.py`; use the same projection/replay pipeline above.
Fixtures explicitly establish required attacking creatures, creature types,
artifact counts and stack spells before restricted activations. Incremental
private choices retain Forge's selected markers, and the driver chooses a new
candidate rather than toggling the same card repeatedly. These are synthetic
resolution cases; native Sealed/Draft/Cube network matches use
`tools/ui-automation/scenarios/LimitedLifecycle.qml` separately.
