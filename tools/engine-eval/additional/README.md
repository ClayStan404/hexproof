# Additional candidate execution

These test-only probes supplement the frozen 17-case evaluation. Their custom
diagnostic IDs and upstream regression totals must not be imported as completed
shared scenarios. Direct fixture setup is disclosed; actions and observations use
the pinned engine or its shipped adapter. No upstream rules patch, remote-game
action, system installation, or production integration is included.

Evidence root: `build/engine-thorough-20260909-pcbfuvZp/additional-evidence/`.
Source root: `build/engine-thorough-20260909-pcbfuvZp/additional-sources/`.
Each `command-*` directory retains exact command/cwd/exit/timeout and combined
stdout/stderr through `../capture.py`. Each independent Python probe retains its
own source snapshot, observed results, exceptions and actual view payloads.

## Hyperdraft

Source: [discordwell/Hyperdraft](https://github.com/discordwell/Hyperdraft/tree/1e17b41f05a134b33ebcc00f93b84be14a0a3363),
revision `1e17b41f05a134b33ebcc00f93b84be14a0a3363`.
The shallow clone's large asset checkout timed out after 180 seconds. The Git
objects and pinned revision were present; only `src`, `tests`, README, pytest
configuration and the dependency manifest were restored with LFS smudging disabled.
This does not modify rules or require card images. The failed clone log remains.

Dependencies were installed into a local `uv venv` from
`requirements-server.txt`; pytest is the README's declared test runner.
The selected upstream tests (`test_server_priority_window`,
`test_additional_casting_costs`, `test_replacement_effects`,
`test_restricted_mana`) passed 43 tests, with pytest configuration warnings.
An earlier wrong-filename invocation is retained as a fixture invocation error,
not an engine failure.

```sh
<source-root>/hyperdraft/.venv/bin/python tools/engine-eval/additional/hyperdraft_probe.py \
  --checkout <source-root>/hyperdraft --output <evidence-root>/hyperdraft
```

Latest `hyperdraft/independent-t2a6kfgb/results.json`:

- PASS: normal 60-Plains opening with real keep and first-main callbacks;
  one-land limit plus validator actor rejection; paid Bolt against player and
  Bears; actual `GameSession.get_client_state` owner/opponent/spectator privacy
  with distinct hand/library names, private text, 60 library IDs and public counts.
- FAIL, engine: four players are registered, Carol loses from life-zero SBA and
  three players survive, but her owned Bears remains on the battlefield and in
  another player's real public projection. This is an independent CR 800.4a
  diagnostic, not the frozen concession sequence.
- FAIL, adapter: the actual `concede_match` route finishes a four-player session
  immediately after one player concedes, assigns the first other seat as winner,
  and leaves the underlying engine ongoing. This independently demonstrates the
  shipped session's two-player assumption; it is not a production Hexproof test.

The actual catalog has 4010 entries. Counterspell, Elvish Visionary, Isamaru,
Willbender and Goblin Glasswright were absent in the recorded catalog query.
Catalog gaps do not imply that every corresponding mechanic is absent.
The pinned README claims MIT, but a complete source grant is not established by
that claim alone; see the shared license inventory before any adoption.

## Witchcraft / python-mtg

Source: [yevbar/witchcraft](https://github.com/yevbar/witchcraft/tree/6b703960979b801882db8bf054ac125aed1811f6),
revision `6b703960979b801882db8bf054ac125aed1811f6`.
The installable `packages/mtg/pyproject.toml` declares pydantic and setuptools;
the package was installed in a local venv. Initial actual `mtg.Game()` startup
failed because generated `datalog/cards.dl` was not in Git. We then followed the
declared CI workflow, rather than treating that setup failure as engine failure:

- Initialize only the declared `third_party/souffle` submodule, pinned at
  `d3caa943fc99797c75a060b655ad1dd6869b984f`.
- Configure the same Release CMake settings with curses/sqlite disabled; build
  locally with two jobs. The build succeeded. No system Souffle or AUR package
  was installed. The upstream script's all-CPU default was not used.
- Download the CI-declared `mtg-data.tar.gz` from the project's `data` release.
  The GitHub asset metadata and actual SHA256 agree:
  `445ff5587474bc5a0f1456905601f41c5d4eb741721ea7eb5bae5a39c4383ecc`.
  Only its inspected `datalog/cards.dl` and `mtgjson/oracle_corpus.json` entries
  were extracted. This separately hashed rolling data asset is not falsely
  represented as pinned by the source revision.

```sh
cmake -S <source-root>/witchcraft/third_party/souffle \
  -B <source-root>/witchcraft/third_party/souffle/build \
  -DCMAKE_BUILD_TYPE=Release -DSOUFFLE_USE_CURSES=OFF -DSOUFFLE_USE_SQLITE=OFF
cmake --build <source-root>/witchcraft/third_party/souffle/build -j2
<source-root>/witchcraft/.venv/bin/python tools/engine-eval/additional/witchcraft_probe.py \
  --checkout <source-root>/witchcraft --output <evidence-root>/witchcraft
```

The probe uses the actual pinned local Souffle interpreter with native-code
autocompilation disabled, an isolated temporary directory and two OpenMP threads.
No timing is a performance comparison. Latest
`witchcraft/independent-50rd7bks/results.json` has three engine-layer failures:

- A normal two-player opening has seven cards each before the turn, but the
  starting player's first precombat main has eight cards and 52 library cards.
  The Game API's supplied policies are installed after mulligan, so this probe
  explicitly uses the native default keep and does not claim human keep callbacks.
- `Game.observation(owner).serialize()` exposes the owner's 52/53 individual
  library card IDs. Opposing hand IDs are removed, but that partial redaction does
  not satisfy the frozen library privacy requirement. Actual payloads are retained.
- Four Commander players start at 40. Positioning Carol at zero in the fixture
  and executing a real public `Game.push(pass)` stops the whole game: terminal
  true, no winner, zero legal actions, despite three players remaining at 40.

The earlier probe's opening assertion stopped at the absent policy callback;
the latest probe checks the rule-observable seven-to-eight transition directly.
No upstream correction was made. Root license is UPL-1.0, while the package's
separate license is MIT; retain both scopes and submodule notices.

## mtghub-engine

Source: [mtghub-ru/mtghub-engine](https://github.com/mtghub-ru/mtghub-engine/tree/b4214c1be2c253a253e95ce1d96d282dc37d85b1),
revision `b4214c1be2c253a253e95ce1d96d282dc37d85b1`.
The normal ASDF load was attempted with SBCL and reported missing CL-MATCH.
More importantly, actual SBCL form reading (`mtghub/command-s_tmj32w`) establishes
that all three state-machine files and the duel file contain zero Lisp forms;
the game and REPL files contain only their `IN-PACKAGE` form. These are actual
empty core implementations, not just a README roadmap or missing compiler.
The candidate is excluded from usable engine qualification at this revision for
that source architecture gap. Additional Quicklisp bootstrap was not pursued.

```sh
# Run with cwd set to the pinned mtghub checkout.
sbcl --dynamic-space-size 2048 --noinform --script \
  /absolute/path/to/tools/engine-eval/additional/mtghub_forms.lisp
```

## Incantus

Source: [Incantus/incantus](https://github.com/Incantus/incantus/tree/34487c2be3ba12a72f8dcba186d247a2b07677e8),
revision `34487c2be3ba12a72f8dcba186d247a2b07677e8`.
An actual `import engine.GameKeeper` on available Python 3 fails on Python 2
`exec` syntax. The source explicitly targets Python 2.6-era libraries; GUI imports
Twisted, pyglet and cocos, and the otherwise mostly pure-Python core hard-imports
`bsddb`. No Cython source, container workflow or complete dependency manifest was
found. The repository does not include `data/cards` or Berkeley DB card databases.
Existing runtime paths contain no Python 2; Docker exists but cached images are
Ubuntu 24.04 and shellcheck, not a Python 2 runtime.

This remains an unresolved historical candidate, not a failed rules engine.
An exact official PyPy 2.7 download has been proposed for owner-approved isolated
fallback execution; no vendor binary or global package was installed in this pass.
Its custom-titled license includes an extra no-advertising-name clause; do not
flatten it to plain MIT without checking that scope.

## DeepScry

The [official homepage](https://deepscry.net/) and public
[guide](https://deepscry.net/guide/index.html) were read, including CLI, gameplay
and server chapters. They describe a Rust engine and local CLI, but these pages
did not establish a source repository, immutable revision or available local
binary. The only homepage GitHub source link points to Forge card data, not the
DeepScry engine. The raw homepage is retained under `deepscry/command-uv9bsn18`.
No login, game creation, WebSocket connection or remote load was performed.
Status remains UNVERIFIED/source-access gap, not an engine failure or measured
performance claim.

## Rule authority and limits

The independent diagnostics use the shared pinned Wizards Comprehensive Rules,
including 103.8a, 305.2, 400.2/401.2, 601/608 and 800.4a. Card-specific actions use
the canonical cards' Oracle text, not Forge outputs. New diagnostic fixtures are
explicitly separate from the frozen case IDs where their setup or action differs.
No overall engine winner or exhaustive game compatibility follows from these
small probes. Runtime/build failures, native adapter defects and observable rule
violations remain distinguishable in the retained evidence.
