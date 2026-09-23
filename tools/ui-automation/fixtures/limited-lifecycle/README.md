# Limited lifecycle fixture

`decks.json` is an isolated saved regular Cube: 135 physical cards across 41
exact printings, with three or four copies of each printing. It is a UI and
physical-stock fixture, not a recommended Cube. No event state or opened packs
are seeded. The native scenario creates the room and confirms each draft pick
through production controls; the server assigns the final singleton in each
pack. Three seats consume all 135 copies without
replacement, leaving 45 distinct instances in each private pool.

Run from the repository root with an installed card catalog containing EOE's
Limited product. The runner backs up the catalog read-only into new isolated
profiles. Cached images may be supplied in a separate explicit fixture copy;
missing images do not prevent the scenario from operating.

```sh
QT_QPA_PLATFORM=xcb QSG_NO_VSYNC=1 python3 tools/ui-automation/run-native.py \
  --scenario tools/ui-automation/scenarios/LimitedLifecycle.qml \
  --server-binary build/server/hexproof-server \
  --catalog /absolute/path/to/cards.sqlite \
  --fixture-dir tools/ui-automation/fixtures/limited-lifecycle \
  --players 3 --variant cube_draft --timeout 900 \
  --output build/limited-cube-new-run
```

Use `set_sealed` or `set_draft` for the two Swiss workflows and a fresh output
directory for each run. They resolve the installed EOE Limited product; the
saved Cube does not affect their packs. All three modes check pool identities,
40-card construction, ordinary basics, draft or construction recovery, locked
deck handoff and a BO1 result by concession. This does not complete a Swiss
tournament or resolve Oracle text automatically.

Append `-forge` to any of these variants to select server-hosted Forge in the
creation UI and play the resulting 1v1 match to a natural conclusion through
production controls. Supply the matching packaged `HEXPROOF_FORGE_HARNESS`
and `HEXPROOF_FORGE_HOME` paths. `set_sealed-forge-bo3` also exercises pool
sideboarding, ordinary basic-land changes, reconnect with an edited deck and
subsequent games. Forge variants build color-focused pool decks and verify the
40-card opening, stack/combat decisions and live combat reconnect; the third
client remains in the event lobby when it has a bye.

`LimitedSimulator.qml` uses one offline client, no server argument and the
installed `mtgjson-eoe-play` product. It checks two packs, independent card
reveals, rarity ordering, advancing/skipping animation and retained results.

```sh
QT_QPA_PLATFORM=xcb QSG_NO_VSYNC=1 python3 tools/ui-automation/run-native.py \
  --scenario tools/ui-automation/scenarios/LimitedSimulator.qml \
  --catalog /absolute/path/to/cards.sqlite \
  --fixture-dir tools/ui-automation/fixtures/limited-lifecycle \
  --players 1 --timeout 180 --output build/limited-simulator-new-run
```

The selected native Qt platform is workstation-specific; XCB is the recorded
Linux review platform. Every primary window is maximized by the shared runner.
