# Native host regression scenarios

`build-native.py` runs the Java regression programs against the immutable JARs
and frozen host source that it has just packaged. Their constructed boards
isolate native decisions; the Go and Qt suites below exercise the application
boundary separately.

`NativeDeckRegistrationRegressionTest` registers the reported MH3 250 Disciple
of Freyalise and ZNR 215 Turntimber Symbiosis printings using combined catalog
face names, in both mainboard and sideboard. It checks exact printings and
section counts, name-only and set-only lookup, transforming and Adventure
cards, unchanged split/aftermath names, and an actual initial native decision
without opponent/spectator identity disclosure. Commander cases match the
native front name and combined name across deck entries and designation.
Unrelated or missing faces must still fail with the fixed private-safe error.

`NativeCallbackRegressionTest` covers canonical remote responses to native
scry, generic amount, combat damage, and Phyrexian life payment. Damage
cases include unordered blockers, deathtouch, a sole defender, and deferring an
optional assignment. Free-division validation has separate Go/Qt regressions in
`forge_damage_mode_test.go` and `tst_rulesdamageprompt.qml`; those do not exercise
a native free-division spell. `NativeMechanicsRegressionTest` uses real
Forge scripts and human cost payment for choosing either counter source,
canceling with rollback, Chord of Calling at X=2 with convoke, Pithing Needle and
Meddling Mage naming, and canceling Cathartic Reunion's
discard cost. It also resolves Seasoned Pyromancer's real discard/draw/token
script with an explicit two-card batch and verifies an optional native card
subset completes without another hidden selection step.
The Eye of Ojer Taq craft-cost regression retains two explicit incremental
choices for its specialized shared-type input and verifies native payment
exiles both selected creatures. Selecting the first card must not prematurely
confirm and cancel that cost.
Three stack-resolution cases use actual Lightning Bolt and Counterspell scripts:
an unanswered Bolt deals exactly three damage, a countered Bolt deals none, and
countering that Counterspell preserves the original Bolt until it resolves.
They check the exact stack and graveyard objects after each resolution. These
synthetic stack fixtures complement native GUI target inspection; they do not
claim to test casting costs or human target selection themselves.
`NativeLethalDamageRegressionTest` runs actual combat assignment and damage
application with a shared blocker, then with Zilortha's power-based lethal
threshold. Those damage boards are separate from declaration coverage.
`NativeMultiBlockRegressionTest` operates actual `InputBlock` with Watcher in
the Web blocking eight attackers and an ordinary creature blocking a ninth.
Duplicate pairs and per-blocker capacity overflow must be rejected before
combat mutation while retaining the prompt. The regression checks the exact
native assignments and private-hand redaction. Go protocol and Qt model/QML
tests cover normalization, opaque response pairs, explicit zero capacities,
old-server compatibility, and selecting/deselecting multiple targets; native
GUI evidence for the popup is recorded separately.

`NativeStartingHandRegressionTest` starts actual matches with one or two
Backup Plans in the native Conspiracy deck section. Four cases keep the
original, second, or third hand and cycle back through the available hands.
They require actual `InputChooseStartingHand`, a fresh prompt and updated owner
hand after each cycle, no private identities for opponents/spectators, and
conservation of all sixty library/hand cards. Keeping seven cards must leave
fifty-three in the library and emit exactly one native shuffle event
after every unused hand has returned, before the ordinary mulligan prompt.
This catches the pinned upstream service's missing shuffle, not merely the
remote button mapping.
`NativeProfileRegressionTest` verifies process-local preferences
without writing into the shared resource checkout.

`NativePromptContextRegressionTest` performs actual one-card surveil on a
constructed library containing Troll of Khazad-dûm. It keeps the card on top,
then moves it to the graveyard, checking its private printable identity and
Swampcycling text at both confirmations. A later cardless confirmation and
an opponent's anonymous face-down card must not retain or disclose that
context. An owner-visible face-down view with no printable name also omits
optional context, keeping Morph payment prompts acceptable to the Go adapter.
The direct `confirm(CardView, ...)` callback also preserves its
explicit card. Opponent/spectator snapshots exclude the privately looked-at
card, and the unrelated library card never enters prompt context. This is a
native callback regression; Qt rendering is verified separately.

`NativePriorityRegressionTest` drives actual `InputPassPriority` with empty,
mana-only, land-play, payable/unpayable burn, mixed permanent abilities,
exile-casting, and optional-payment boards. Automatic-pass metadata uses the
complete set of exposed native candidates, including all abilities on each
card. Optional/alternative payment uncertainty, floating mana, predictive
failures, and a soft scan budget preserve the explicit priority window.

`NativeSnapshotRegressionTest` builds synthetic boards and checks the actual
Forge projection for owner, opponent, and spectator. It covers private zones,
face-down permanents and spells, temporary look permissions, public card state,
detached JSON publications, and terminal outcomes. It does not exercise a whole
match or prove that the host publishes every snapshot at a safe thread boundary.

`NativeOrderingRegressionTest` calls the actual `PlayerControllerHuman` exert
and enlist callbacks with synthetic Glorybringer and Guardian of New Benalia
boards. It explicitly selects or declines attackers, reverses the selected
order, rejects invalid replies without consuming the prompt, and verifies exact
original object references. Additional GUI cases cover removable initial
destination entries, equal display labels, unrestricted selection, and insertion
while preserving existing order. It shares the canonical response driver in
`NativeCallbackRegressionTest`; it does not run a complete combat phase or prove
that every optional attack trigger resolves.

`NativeLethalDamageRegressionTest` uses real `Combat.assignCombatDamage` and
`Combat.dealAssignedDamage` on synthetic boards. Two Colossal Dreadmaws share a
Watcher in the Web: after the first assigns five damage, the second receives a
zero lethal threshold and assigns all six damage to the defender. Forge deals
seven total damage to the defender. A separate board applies Zilortha's actual
continuous script, reducing that blocker's lethal threshold from five toughness
to two power; Forge deals four trample damage. Every prompted allocation is
explicit, and published thresholds cover only the native candidate list.

`test_full_game.py` starts two human controllers with 60-card synthetic decks,
keeps both hands, selects lands and creatures, selects every mana source through
the native payment input, attacks, and declines blocks. Forge owns all draws,
triggers, state changes, combat damage, and the natural lethal outcome. The
Visionary scenario requires observed ETB draw-trigger resolution; Glory Seeker
provides a separate combat game. The copy counts intentionally exceed Constructed
deck limits, so these are mechanism tests rather than format-legal deck tests.

Use a completed, immutable packaged runtime, especially while another build is
writing upstream Maven target JARs:

```sh
python3 third_party/forge-runtime/native-host/test_full_game.py \
  --jar "$runtime/forge-harness.jar" --forge-home "$runtime/forge-gui" \
  --scenario visionary --seed 42 --life 20 --starting-player 0 \
  --output build/native-tests/visionary
python3 third_party/forge-runtime/native-host/test_full_game.py \
  --jar "$runtime/forge-harness.jar" --forge-home "$runtime/forge-gui" \
  --scenario glory-seeker --seed 43 --life 20 --starting-player 1 \
  --output build/native-tests/glory-seeker
```

The alternate starting seat checks the runtime's explicit starting-player
contract. It does not establish the application's complete best-of-three flow.

`test_lifecycle.py` starts four human seats. At a mulligan or priority boundary,
it rejects an invalid response without changing the publication, concedes a
different player while preserving the original decision, then concedes that
decision's owner and reaches a real engine victory for the surviving player.
It verifies stable registered seat IDs and spectator privacy throughout:

```sh
python3 third_party/forge-runtime/native-host/test_lifecycle.py \
  --jar "$runtime/forge-harness.jar" --forge-home "$runtime/forge-gui" \
  --phase mulligan --output build/native-tests/lifecycle-mulligan
python3 third_party/forge-runtime/native-host/test_lifecycle.py \
  --jar "$runtime/forge-harness.jar" --forge-home "$runtime/forge-gui" \
  --phase priority --output build/native-tests/lifecycle-priority
```

Both Python drivers send the canonical `type`/`output` action envelope used by
the Go client; concession directives retain their separate envelope. Evidence
includes exact runtime artifact hashes, setup/policy parameters, JSONL decisions
or RPC transcripts, engine stderr, and a machine-readable result. The tests do
not cover adversarial target selection, every native GUI callback, Modern-wide
card interactions, or the Qt/Go end-to-end integration. Those require separate
scenarios and evidence.

`NativeDelayedRevealRegressionTest` resolves the real Collected Company script
on a constructed library. It requires all six authorized cards to be revealed
before the eligible-creature selection, exercises both native delayed-reveal
callback overloads, and excludes unrelated private cards from the prompt and
opponent/spectator projections. Choosing zero creatures intentionally bounds the
probe to reveal/selection/order behavior rather than proving the whole spell in
a multiplayer game.

`NativeSynchronousConcedeRegressionTest` runs actual native openings and game
loops, injecting a name/number menu through the existing start-game hook. Its
cases cover game-thread and GUI-dispatcher menus, two-player owner
and other-seat terminal concessions, a four-seat game reduced to a terminal
pair, unrelated multiplayer departures with subsequent explicit answers, and
deciding-seat multiplayer departure. Each concession
must reach a stable boundary within two seconds; terminal cases verify Forge's
real winner and that no answer was invented. Rule-required name/number choices
pass to the next surviving player with a new prompt and explicit response.
For a surviving object, its controller explicitly selects a replacement chooser
from the native eligible players, then that chooser supplies the original
answer. The game must continue to native priority and a real terminal result.
These are host lifecycle regressions, not full spell-resolution or Qt tests.

`NativeObjectDepartureRegressionTest` resolves actual native stack effects with
constructed sources, targets, and followup life gain. It covers the object's
controller leaving while another player chooses, nested replacement selection
on either dispatcher, an owned spell leaving while controlled by another player,
and an independently controlled ability surviving its source owner's departure.
Repeated child effects must unwind to the removed object's root without another
iteration or followup effect. Choosing a candidate who departed during replacement
selection must rebuild the eligible set before the original explicit answer.
These cases require released stack state and priority for a surviving player.

`NativeQueuedInputRegressionTest` holds the native GUI dispatcher with two
latches and queues a stale priority refresh ahead of an accepted pass or
concession. Before the native action starts, the old prompt must remain
consumed and the RPC must still wait. Releasing the action must produce the
next real native input. The same interleaving fails without the publication
barrier; strict changed-input rejection remains enabled. Nested synchronous
menus must still publish after the dispatched action begins.

`test_synchronous_concede.py` starts a real four-player `NativeHost` subprocess
with synthetic Forest/Pithing Needle decks. It plays through ordinary JSONL
opening, casting, mana payment, and priority to Pithing Needle's native naming
menu. An invalid name must be rejected while the original prompt and child
remain alive. The deciding player's nonterminal concession must then complete
within three seconds while the JVM remains alive and the game continues.
The departed player's Needle must not be restored by the abandoned entry
replacement. A surviving player then plays a land, casts another Needle,
explicitly names Lightning Bolt, and resolves it onto the battlefield. Later
concessions must reach Forge's real terminal outcome. This tests the production
host main, native casting/resolution cleanup, and priority progression without
injecting a session or replacing a native callback. The synthetic copy counts
exceed Constructed deck limits and are an explicit mechanism-test policy.

```sh
python3 third_party/forge-runtime/native-host/test_synchronous_concede.py \
  --jar "$runtime/forge-harness.jar" --forge-home "$runtime/forge-gui" \
  --output build/native-tests/synchronous-concession
```

The opt-in Go integration suite accepts the same runtime directory through
`HEXPROOF_REAL_FORGE_ROOT`:

```sh
cd apps/server
HEXPROOF_REAL_FORGE_ROOT="$runtime" go test -tags engineintegration \
  ./internal/rulesengine/forge -run '^TestLiveForgeRuntime$' -count=1 -v
HEXPROOF_REAL_FORGE_ROOT="$runtime" go test -tags engineintegration \
  ./internal/server -run '^TestLiveForgeWebSocket(BO3)?Match$' -count=1 -v
HEXPROOF_REAL_FORGE_ROOT="$runtime" go test -tags engineintegration \
  ./internal/server -run '^TestLiveForgeIsolatedRuntimeRooms$' -count=1 -v
```

Set `runtime` to an absolute path before changing directory. The direct adapter
suite includes combat, burn, multiple-blocker trample, Commander variants,
Adventure, modal double-faced cards, ETB triggers, Prepare, and Morph privacy.
The WebSocket suite uses authenticated client messages and checks reconnect,
spectator redaction, natural outcomes, and BO3/sideboard transitions. The room
stress scenario starts multiple fresh JVMs through one shared Go handler. These
programmatic players do not validate Qt controls; real native UI evidence and
its exact deck/driver limits are recorded in `docs/forge-native-migration.md`.
