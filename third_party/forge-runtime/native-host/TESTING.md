# Native host regression scenarios

`build-native.py` runs the Java regression programs against the immutable JARs
and frozen host source that it has just packaged. Their constructed boards
isolate native decisions; the Go and Qt suites below exercise the application
boundary separately.

`NativeAiRegressionTest` checks all official Default profile values against
the hard preset, rejects missing/unknown difficulties and production two-AI
setups, and runs Forge's actual two-Lightning-Bolt planner with 100 controlled
percentage rolls on the same board: easy selects no chain, normal selects 45,
and hard selects 90. It also invokes the real asynchronous ability evaluator
and requires its random draws to use the owning execution context. These are
tactical behavior checks, not win-rate calibration. Each tier starts with the
AI in either registered seat; remote prompts remain human-owned, AI hands stay
private, human concessions produce the correct native winner, and worker
cleanup completes.
The deck-advisory case registers Prismatic Ending in the AI main deck and
Wrath of the Skies in its sideboard. It reproduces Forge's actual startup
warning, requires a single `acknowledge` input with separate readable sections,
rejects a boolean answer without consuming the notice, and then acknowledges
the warning and reaches mulligans with both flagged cards still registered.
An invalid human response must retain the same prompt and keep the AI session
healthy. An expired native boundary must instead mark the session failed and
reject further reads; dedicated JSONL responses expose that distinction through
the private `fatal` field before retiring a failed process.

`test_full_game.py --ai-difficulty easy|normal|hard --ai-seat 0|1` replaces
exactly one deterministic human driver with Forge's AI. It checks the advertised
capability, forbids remote prompts from the AI, retains the requested starting
seat, and requires a natural lethal outcome with observed creature casting,
mana payment and combat. The existing synthetic deck limitations still apply.

`NativeAiCalibration` is an optional test-only program which directly constructs
two native AI controllers. It does not relax the production JSONL admission
rules. It plays mirror matches with two fixed 60-card lists using at most four
of each nonbasic card, each pair of tiers, seeds 42 and 43, and both starting
seats, with the tiers also swapping registered seats (48 games). It records
decks, tiers, seeds, starting seats, winners, turns
and durations as JSON. Its small sample does not establish a universal skill
ordering, and these lists do not claim legality in a particular rotating format.

```sh
java -Xmx2g -Djava.awt.headless=true \
  -cp "$runtime/test-classes:$runtime/forge-harness.jar:$runtime/lib/*" \
  org.hexproof.forge.NativeAiCalibration "$runtime/forge-gui" \
  build/native-tests/ai-calibration.json
```

`NativeDeckRegistrationRegressionTest` registers the reported MH3 250 Disciple
of Freyalise and ZNR 215 Turntimber Symbiosis printings using combined catalog
face names, in both mainboard and sideboard. It checks exact printings and
section counts, name-only and set-only lookup, transforming and Adventure
cards, unchanged split/aftermath names, and an actual initial native decision
without opponent/spectator identity disclosure. Commander cases match the
native front name and combined name across deck entries and designation.
Unrelated or missing faces must still fail with the fixed private-safe error.
Explicit unavailable set/collector pairs must fail for both mainboard and
sideboard instead of accepting Forge's fallback printing. Lowercase set codes
and native edition aliases still resolve to the expected printing.
Promo registration covers the five missing prerelease/promo-pack printings
from the reported md2-versus-md1 startup failure, mixed regular/promo copies,
both deck sections, combined face names, initial input and private projections.
Unsupported promo suffixes, wrong card/number pairs and missing parents must
still fail without accepting Forge's name-only fallback.

`NativePrintingAliasRegressionTest` resolves every entry in the bundled catalog
index through native databases and checks retained display identity and foil
conversion. It starts a real native match with the four reported RVR/PTC/WC04
printings, exercises both mainboard and sideboard, and checks that CED/CEI/2ED
copies of Ancestral Recall remain distinct without disclosing the owner's deck.
`NativeSnapshotRegressionTest` now checks all six actual `ManaAtom` types for
owner/opponent/spectator views and disappearance after the pool is cleared.
The multiple-block regression also checks all eight confirmed relationships in
all three projections after leaving the declaration input.

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
The conditional-discard cases resolve Winternight Stories with either one
creature or two other cards. Ultima's end-turn case verifies its destruction,
an empty stack and the subsequent cleanup discard. Psychic Frog requires an
exact three-card exile choice, rejects a short reply without changing the
prompt, and preserves all cards on cancellation. Esika's Chariot rejects
confirmation below four total power and retains selection markers; success
and cancellation check exact taps and animation. Invasion Submersible reaches
the waterbend helper limit, rejects an extra helper, deselects and reselects,
then resolves its actual animation and three counters.
Three stack-resolution cases use actual Lightning Bolt and Counterspell scripts:
an unanswered Bolt deals exactly three damage, a countered Bolt deals none, and
countering that Counterspell preserves the original Bolt until it resolves.
They check the exact stack and graveyard objects after each resolution. These
synthetic stack fixtures complement native GUI target inspection; they do not
claim to test casting costs or human target selection themselves.
`NativeImproviseRegressionTest` casts actual Kappa Cannoneer with human input.
It checks incremental selection/deselection flags before any tap, two cancelled
insufficient payments followed by a successful retry, exact artifact and mana
source rollback, preservation of previously tapped/unselected/opponent cards,
and the separation of improvise from rules-visible convoke history. A separate
Siege Wurm case cancels convoke twice through the shared refund path.
The `improvise` variant of `tools/ui-automation/scenarios/ForgeDuelMatch.qml`,
with `tools/ui-automation/fixtures/kappa-improvise.json`, exercises selection
markers, deselection, confirmation, repeated cancellation and successful retry
through two maximized native clients. It uses a synthetic legal-size deck and
stops after that interaction; it is not a completed-match AI evaluation.

`NativeCardStateRegressionTest` checks revealed choices for owners, opponents
and spectators, including number zero, while suppressing secret number/type
choices and face-down sources. Its `labyrinth` case resolves actual Ugin's
Labyrinth exile and return scripts on two different sources, checking eligible
cards, independent links and cleanup. The real Pithing Needle and Meddling Mage
naming cases also assert the resulting public annotation. Qt tests exercise
tile summaries, duplicate separation, hover/details, translation and updates;
Go tests reject annotations on hidden cards and outside their applicable zones.
The `class-level` case resolves Artist's Talent's actual upgrade and checks all
three viewers, then removes the battlefield annotation after the card returns
to hand. The dungeon mechanics case chooses a visible legal dungeon and checks
its current room in the public command-zone projection.
The `chosen-card` case resolves Dauntless Bodyguard's actual entry choice,
checks owner/opponent/spectator links, then returns and replays the creature to
prove that a reused id cannot inherit a stale choice. Private chosen cards and
face-down sources have separate redaction checks.
The native `persistent-state` variant of `ForgeDuelMatch.qml` uses
`tools/ui-automation/fixtures/persistent-state.json` to name a card, imprint and
return a card through production controls, with both players checking the
current battlefield summaries. This is a bounded synthetic interaction check.

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

`NativeMulliganRegressionTest` drives actual London mulligans with two and
three human seats. Every redraw keeps seven cards until an explicit keep;
only then does one typed put-back prompt request the accumulated paid count.
It covers repeated mulligans, initial keeps, the multiplayer free mulligan,
forced keeping at zero remaining cards, exact library-bottom order, and private
owner/opponent/spectator snapshots. Wrong counts, duplicate or foreign cards,
and cancellation must preserve the prompt, hand, and library. The live Go
`TestLiveForgeRuntime/london_mulligan_keep_before_bottom` case checks
normalization and responses against the packaged runtime; Qt checks repeated
keep decisions followed by the explicit private card-selection dialog.

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

`NativePromptPrintingRegressionTest` checks actual native selection, reveal and
ordering callbacks with two printings of the same card. Prompt identities must
match the later hand and battlefield snapshots, while face-down and stale
views retain their visibility boundary. The native `promos` variant also checks
that registered prerelease and promo-pack copies retain their catalog identities through selection, reveal,
ordering, and actual moves from the library to the hand and battlefield.
The Qt match-load regression separately uses distinct local images for two
exact printings and a conflicting name-only cache entry. It checks prompt and
zone model identities, decoded table images, full image paths and absence of
network requests through the production cache
binding. Native GUI evidence uses isolated synthetic art to inspect rendering;
it is separate from the engine callback tests.

`NativeCardTextRegressionTest` uses the actual Duress, Deadly Cover-Up and
Shallow Grave scripts with human casting and cancellation. Payment text must
retain its live cost and readable restrictions without internal selector tokens
or duplicated subeffects. Deadly Cover-Up's optional-cost menu must not reuse
the previous spell's payment description. Emptiness's actual graveyard target
input must show its mana-value limit, exclude a four-mana creature, and return
only the explicitly selected legal creature. These are bounded prompt and
resolution checks on constructed boards, not completed games.

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

`NativeDelayedRevealRegressionTest` resolves real Collected Company, Polluted
Delta and Thoughtseize scripts on constructed boards. Authorized looked-at cards
and eligible choices must share one prompt; read-only submissions preserve the
pending choice. Both delayed-reveal callback overloads retain the full private
look without exposing unrelated identities or changing opponent/spectator
projections. No-candidate looks and Thoughtseize against a land-only hand retain
their standalone disclosure. These are bounded resolution checks, not full games.

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
