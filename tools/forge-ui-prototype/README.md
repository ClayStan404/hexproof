# Forge UI design study

An offline Qt Quick prototype for reviewing the new Forge table before wiring
it to the production rules session. It uses original QML components and takes
visual/interaction inspiration from [Phase](https://github.com/phase-rs/phase).

## Run

From the repository root in a graphical desktop session:

```sh
python3 tools/forge-ui-prototype/run.py --prepare-assets
```

Later launches are offline and omit `--prepare-assets`. The runner opens a
maximized window using the installed Qt `qml6`/`qml` executable. It writes only
under `build/forge-ui-prototype/`: card images/metadata, isolated settings, and
cache. No application server, JVM, account, or normal Hexproof profile is used.

The first preparation downloads 19 public Scryfall card records and their
normal/art-crop JPEGs. Repeated preparation reuses the cache. Images and card
metadata are generated research assets, not committed source. Artist and
printing attribution is retained in the cached Scryfall JSON and full card
faces. See [Scryfall](https://scryfall.com/) for image provenance.

## Scenes and controls

| Control | Behavior |
| --- | --- |
| Toolbar / F1 | Ordinary battlefield and hand |
| Toolbar / F2 | Two-object stack with a target relationship |
| Toolbar / F3 | Select a creature or player for Lightning Bolt |
| Toolbar / F4 | Reserve mana for Lightning Bolt targeting Walking Ballista |
| Toolbar / F5 | Attack, block, and damage-assignment examples |
| Toolbar / F6 | Duel Commander casting and command-zone choice examples |
| Toolbar / F7 | Crowded board: 24 own / 20 opposing creatures, 15 hand cards, 8 stack objects |
| Click Lightning Bolt in hand | Begin target selection |
| Click a highlighted creature/player | Select it and advance to payment |
| Click a highlighted land | Toggle the mana reservation; no tap is committed yet |
| Pay R | Commit selected mana and put the spell on the sample stack |
| Auto pay | Choose an available prescribed red source and commit |
| Change target | Clear mana reservation and return to target selection |
| Cancel / Escape during payment | Clear the pending cast without changing hand or tapped lands |
| Resolve top | Advance the prescribed resolution fixture |
| Space | Activate the current scene's primary action |
| Attack / Block / Damage | Reset to an independent combat example |
| Click own creature in Attack | Toggle it as an attacker; confirm to keep the submitted choice visible |
| Click blocker, then attacker in Block | Assign, reassign, or remove that block; multiple blockers can share an attacker |
| Damage − / + | Adjust the two recipients; submission requires all 6 damage |
| Reset / Escape in Combat | Clear the example's submitted or pending choices |
| Commander card / Cast Isamaru | Start the prescribed second cast for 2 W |
| Casting / Zone choice in Duel | Reset to casting or the post-graveyard destination prompt |
| Command zone / Keep in graveyard | Choose the commander destination without resetting its cast count |
| Wheel / scrollbar over a crowded creature lane or stack | Scroll within that region |
| Drag / scrollbar in the crowded hand | Reveal later cards without shrinking the entire hand |
| Stack target button | Scroll to and highlight the exact target copy on the battlefield |
| Hover / right-click | Inspect a full card / pin inspection |
| Phase buttons | Toggle displayed phase stops |
| Game log | Toggle the preview's history panel |

`--scene board|response|target|payment|combat|commander|crowded` chooses the
initial scene. Each toolbar selection resets its fixture; selecting a toolbar
scene or a combat/Duel example is not a game action.

## Scope

The study covers 1v1 composition, a fixed current-action location, visible
stack/target and combat relationships, direct creature/player selection,
cancellable mana reservation, and the Duel command zone. Crowded creature lanes
show two rows and scroll vertically; repeated tokens retain separate IDs.
The bounded stack panel scrolls independently. The hand remains substantially
visible at rest and scrolls horizontally when crowded. Hover inspection does
not resize battlefield lanes.

The product scope is 1v1, including Duel Commander. Multiplayer EDH is excluded,
not a subsequent prototype/integration milestone. The Duel fixture displays
20 life and one commander per player, with no commander-damage ledger.

`StudyModel.qml`, `CombatStudyModel.qml`, and `CommanderStudyModel.qml` are
fixture controllers. Their candidates, mana sources, costs, and outcomes are
prescribed examples. They are **not** a rules engine, legal-action calculation,
or production Forge adapters:

- Combat uses independent attack, block, and six-damage examples. The damage
  sample allows an unordered split between two blockers; it does not infer
  lethal thresholds, trample, first strike, or damage resolution. Confirmation
  holds the chosen relationships rather than advancing a real combat phase.
- The Duel sample starts after one previous Isamaru cast. Reserving three Plains
  leaves the cast count unchanged; confirmed payment spends them and puts the
  second cast on the sample stack. The subsequent displayed cost is 4 W.
  The destination example starts with Isamaru already in the graveyard; either
  choice preserves its two previous casts. Reset the example to cast again.
  Partners, multiple commander choices, and other destination prompts remain
  outside this fixture.
- Only the original Lightning Bolt hand ID has a cast flow. Other hand cards,
  including copied faces in the crowded sample, support inspection. Zone counts
  are display samples, not authoritative card accounting. These are visual board
  states, not complete format-legal decklists.
- Pass, combat transition, and Full Control do not execute a real turn. Phase
  stop toggles do not drive an engine.

Production integration will bind presentation to the existing authenticated,
redacted rules models and prompt-local responses. Real combat/Duel decisions,
multi-target cardinality, alternative costs, triggers, zone navigation,
spectators, reconnect, and localization still require integration and
qualification. The existing application UI and wire protocol are unchanged.

## Verification and capture

```sh
python3 tools/forge-ui-prototype/verify.py
python3 tools/forge-ui-prototype/run.py \
  --capture-dir build/forge-ui-prototype/review
```

The focused tests exercise visible controls: Bolt targeting/payment, combat
selection and assignment, Duel casting/cancellation/destinations, scroll input,
exact-copy target location, hand inspection, and scene reset. Layout checks
cover 1600×1000, 1280×800, and 2560×1408, plus 1920×1010 for the new scenes.
The wrapper fails on QML diagnostics even when Qt Test returns success. No
network/card preparation is required for tests.

Capture mode saves the owned QML window's contents after each stage change.
F9 captures the current state; F8 prints control geometry. For captured native
evidence, set `QT_FORCE_STDERR_LOGGING=1` if the desktop otherwise sends Qt logs
to its journal. Log records include viewport size, display size, scale, and
maximized state. Captures do not include other desktop windows.

Use the owner's **local desktop** for native review by default. The initial
remote `arch` review is historical evidence; it is not the preferred test target.
The local Wayland desktop has a 3840×2160 display at 200% scaling: a maximized
1920×1010 logical client area, with 3840×2020 pixel Qt Test captures.
The round-two harness, logs, screenshots, and process ownership records live
under `build/forge-ui-prototype/round2-native/`. It operates the real maximized
window with Qt Test mouse events and uses isolated profile directories.

Final verification on 2026-09-16: the focused Qt suite reports 27 passed with
no QML warnings; `./tools/verify.sh --scope static` passes, including 344 tool
tests. Native `final-review.log` and `final-layout.log` both pass without QML
warnings. Earlier attempts remain available in that evidence directory.

Native scenarios cover attack/block relationships, damage adjustment, commander
reservation cancellation, confirmed casting and resolution, both destination
choices, crowded-lane/stack/hand scrolling, exact-copy targeting, and the
ordinary Bolt response. The hand uses a stationary input surface while its art
lifts. This evidence does not claim physical input-device or real Forge match
qualification.

See [the design proposal](../../docs/forge-ui-redesign.md) for the product
direction, reference revision, and production integration boundaries.
