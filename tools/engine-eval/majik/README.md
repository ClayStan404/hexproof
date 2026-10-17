# Majik actual .NET evaluation

Pin: `d7ada5fe8327fe5e638b28dccc801dbe3281ffad`,
<https://github.com/bg9m9r/majik>. The pinned `global.json` accepts the installed
.NET SDK 10.0.111 through `latestFeature`; runtime 10.0.11. Arch native packages
`dotnet-sdk`, `aspnet-targeting-pack`, and `aspnet-runtime` were installed. No
upstream source or card rule was repaired for evaluation.

The declared solution tests were actually launched, retaining TRX and logs.
Core, API, bot-unit and server test projects ran; the full bot-integration run
must be inspected separately for failures, skipped tests and termination rather
than being folded into the passing unit count. The real Dimir mirror test
raised `ArgumentOutOfRangeException` in `DestroySpellFactory.cs:24` via modal
casting. These are observed upstream tests, not the frozen seventeen-case suite.

Completed TRX files contain 30,105 passes and four skips across those four
projects. The full solution run hit its 1,200-second bound. The Dimir mirror
exception reproduced in two of three isolated targeted reruns (one passed),
so it is not described as deterministic. An additional 60-second inactivity
diagnostic recorded 60 passes, one failure and 37 skips before aborting while
`SearchVsHeuristicMultiArchetypeTests.MeasureAllArchetypes` was active. That
identifies the active test, not proof of deadlock or an engine crash: the test
host was terminated by the inactivity collector. These supplemental/partial
results are not folded into the completed-project passing count.

Use `capture.py` for a bounded command and an isolated .NET CLI profile. Keep
all generated files under `build/`; build the supplemental reference probe with:

```sh
dotnet build tools/engine-eval/majik/ReferenceGames.csproj \
  -p:MajikRoot=/absolute/pinned/majik --disable-build-servers \
  --artifacts-path /absolute/build/majik-probe -m:2
dotnet /absolute/build/majik-probe/bin/ReferenceGames/debug/ReferenceGames.dll \
  tools/engine-eval/workloads.json limited_green_40 /new/evidence/limited
dotnet /absolute/build/majik-probe/bin/ReferenceGames/debug/ReferenceGames.dll \
  tools/engine-eval/workloads.json burn_red_60 /new/evidence/burn
```

The probe materializes every card through `EmbeddedCardRepository` and the
same `DeckCardShellBuilder`/`GameFacade` binder path used by the server. It never
substitutes vanilla placeholders for missing cards. Two native heuristic bots
drive actual shuffle, mulligan, mana, casting, combat and SBA. The workload's
card counts and seed are frozen, but **the native bot policy is not the shared
Forge/XMage human policy**, so elapsed time is not comparable. A 200-turn cap is
a safety bound, never a winner: PASS requires one real surviving winner and a
registered opponent whose actual `HasLost` is true. Event JSONL and final state
are retained; the fixture never concedes or mutates running game state.

The tested 40-card game naturally ended on turn 13 (life 11/-1), and the
60-card game on turn 10 (life 0/3). Native `GetStateFor(Guid.Empty)` returns null;
this is recorded as absence of a spectator view at that factory boundary, not
proof of safe spectator support. The actual `GameFacade.Create` accepts exactly
Alice/Bob: four-player hosting is not invented by this probe. Lower-level
multiplayer remains a separate requirement, not a passed case.

Evidence: `build/engine-thorough-20260909-pcbfuvZp/majik-build/`,
`majik-tests/`, `majik-server-tests/`, and `majik-reference-*/`.
