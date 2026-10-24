# Development and verification policy

This is the current engineering workflow policy. It replaces older blanket
GUI prohibitions, mandatory clean builds for every change, and line-count
gates. Product rules, privacy guarantees, and deployment permissions are not
relaxed by this policy.

## Scope and authority

- The accepted [autonomous development target](autonomous-development.md)
  removes required human product/development/review/release gates from its
  operating loop. It uses independent AI assessment and deterministic
  verification/merge/publication controls. Activation is specific to each
  operation: consult the trusted [operator configuration](multica-operations.md#operator-configuration)
  and actual native/service readback, rather than treating the whole workflow
  as enabled or disabled. Current task authorization and verification
  requirements still apply.
- Follow the current owner request and applicable agent instructions. Consult
  the English specifications relevant to the behavior being changed. Resolve
  conflicting dated decisions in favor of the latest applicable decision;
  ask when the intended product behavior remains unclear.
- Follow `AGENTS.md` and consult this policy for application development,
  builds, verification, or deployment. For other tasks, read only relevant
  sections when needed. Read roadmap sections, domain specs, and tool guides
  only as the task requires. Use the handoff to recover
  current focus, not as a mandatory transcript to maintain after every fix.
  A tooling-only change does not require reading the whole gameplay roadmap.
  Code/tests are implementation evidence, not permission to redefine a
  documented contract to match a bug.
- Implementation phases describe the original roadmap, not a requirement to
  restart completed work. Deliver one coherent owner-scoped task at a time;
  a vertical slice may include client, server, tests, and documentation.
- Handoffs are status indexes. Completed plans and repair briefs are historical
  task context, not permanent bans on future work or mandates to use a specific
  agent, skill, or delegation workflow.
- For communication or release compatibility work, follow the accepted
  [protocol compatibility policy](protocol-compatibility.md). Admission uses exact game-protocol equality, independently of application
  versions. Legacy 3.0.0 clients use v1 and cannot join v2 hubs; current fleet
  deployment state is recorded in the handoff.
  Review wire semantics and mixed-release evidence before retaining a protocol
  identifier. Do not reintroduce an application-version admission gate.
- Keep design records proportional. A narrow bug fix normally needs the fix,
  regression coverage, and a concise explanation, not a new design document.
  New state ownership, trust boundaries, protocol behavior, or substantial
  architecture changes need a short durable design/decision record. Update
  existing specifications when their behavior contracts change.
- Write new engineering documentation and code comments in English. Match an
  existing document's language when editing it; translated UI and localized
  user guides keep their intended languages. Keep live owner conversation in
  Chinese under the working agreement.

## Choose verification by risk

Run focused checks during development, then verify the coherent final change.
Do not rebuild the entire project or launch a native client after every edit.
Do not run overlapping complete suites in parallel. Reuse an applicable active
run; stop superseded checks promptly, targeting only processes this task started.

| Change | Normal verification | When to expand |
|--------|---------------------|----------------|
| Documentation or comments | Diff, links, examples, and applicable text/schema checks | Executable examples or policy tooling also changed |
| Scripts or quality tools | Syntax checks and focused tool tests | Exercise changed orchestration paths; use integration checks if builds/protocols are affected |
| Server logic | Relevant Go unit/integration tests and vet | Race tests for concurrency, room lifecycle, or shared state; owner/opponent/spectator tests for private data |
| Client logic | Incremental build and relevant CTest targets | Cross-component/session changes need integration tests |
| Layout or interaction | Focused QML tests and relevant size/input states | Native GUI checks for appearance, clipping, focus, dragging, DPI, platform behavior, or an unresolved visual report |
| Cross-boundary milestone or release | Complete automated verification and relevant smoke scenarios | Clean build for build-system/dependency changes, stale-build suspicion, or release reproducibility |

Available local scopes:

```sh
./tools/verify.sh --scope static
./tools/verify.sh --scope client
./tools/verify.sh --scope server
./tools/verify.sh
./tools/verify.sh --clean
```

Every scope runs cheap shared static checks, including ShellCheck through
`tools/check-shell-scripts.sh`; a missing required checker is an error.
`client` and `server` skip unrelated Python tool tests. `static` and the default
`all` scope run the full tool suite. Add repeatable `--tool-tests test_name.py`
options when a domain change also needs particular tool checks.
`client` builds a matching local server for CTest integration tests without
running the Go suite; `server` does not require Qt. The default `all` scope runs
both builds, Go tests/race tests and CTest. Builds and Go tests reuse normal
caches; `--clean` explicitly rebuilds and runs uncached Go tests. `--quick`
restricts client builds to the application target, skips CTest and races, and is
not complete verification. Individual focused commands are also valid; wrappers
are not compulsory for every edit.

CMake automatically uses an installed `ccache` unless a compiler launcher was
explicitly configured. `-DHEXPROOF_USE_CCACHE=OFF` disables that automatic
detection; it does not override an explicit launcher.

For a focused client check, pair repeatable explicit build targets with a CTest
regular expression; these options require `--scope client` and reject `--quick`:

```sh
./tools/verify.sh --scope client --target hexproof_appupdate_test --tests '^appupdate$'
./tools/verify.sh --scope client --qml-per-file --target hexproof_qml_test \
  --tests '^qml_(forgephaseoverlay|forgeduel_readouts)$'
```

CTest must select at least one test. Its actual `integration` labels trigger a
matching server build; selecting `limited-catalog-builder` also builds its catalog
builder dependency. Other targets are explicit, so list every executable needed
by the selected tests. A focused run builds only those targets and dependencies,
does not require an unrelated application binary, and is not full release
qualification. Normal and release scopes retain the complete build/test path.

A reviewer independently inspects the complete candidate and the existing
executed evidence for its exact SHA. Reuse passing applicable evidence; rerun
only missing, failed, stale or risk-relevant checks. An independent review is
not an instruction to repeat an identical complete suite.

For a review handoff's diff digest, use the exact base/head and
`git diff --binary --full-index <base> <head> --`; retain the full object IDs and
hash those diff bytes, not a shortened-ID rendering or Markdown summary.
Trailing whitespace in an evidence document is presentation, not a source
change. Actual tracked changes still require affected checks, and a release
receipt remains valid only for its exact source under the rules below.

Local release verification uses `./tools/verify.sh --qml-per-file` and two
CTest workers. The option enables `-DHEXPROOF_QML_TESTS_PER_FILE=ON` at CMake
configuration. This registers
each QML test file with the same runner and isolated fixture state, retaining
every case while allowing CTest to overlap independent files. Each process has
its own text and JUnit reports under `qml-test-results/`; `ctest -L qml` selects
the whole QML group. The option defaults to OFF, preserving the existing single
`qml` test and report paths for other callers. Parallelism is bounded; do not
replace the full test set with a sample. Reuse of a completed release result
requires the exact source and evidence checks described below.

For repeatable control-plane interference measurements and historical source
comparisons, see [control-plane benchmarks](control-plane-benchmarks.md). Keep
performance runs separate from concurrent builds and race-instrumented checks.

The Qt Quick test runner fails on QML engine warnings, including warnings
during component construction before test setup. Fix their source in the
application or fixture rather than treating passing assertions as sufficient.

Push CI runs cheap shared static checks without duplicating the development
machine's completed heavy checks. Pull request CI runs the full tool suite and the application
domains selected by `tools/ci-scope.py`; manual dispatch runs all domains and
additional platform, sanitizer and fuzz jobs. Documentation and known tooling,
deployment or non-build workflow changes do not compile applications. Client-only
changes include a matching integration server; server/shared build/protocol or
unknown changes retain the required domain coverage. On full-validation paths,
an unavailable comparison selects all domains. Forge-sensitive changes on these
paths retain bounded real-engine checks over the pinned base and native overlay.
The main CI workflow also runs focused Windows/macOS Forge host-service tests
for relevant pull request changes. Linux runs them through the client
CTest suite; manual dispatch includes them in the full platform suites. This
uses the same event policy rather than a separate heavy push workflow.
The separate manual Forge workflow retains the full native build, source rebuild
and architecture matrix. None of these scopes reduce release requirements.

For a release, first finalize and commit the version, changelog and notes, then
freeze a clean source checkout. `tools/release-verification.py run` runs the
complete local static/tool, Go vet/test/race and client CTest suite, including
QML, through the existing verification script. It records success only when
every command passes and the clean source commit/tree remains unchanged.
The private receipt binds the source version, complete-check profile and log
digest to that exact commit. Keep subsequent operational notes in native task
history or private evidence; do not append handoff-only commits after the freeze
and then reuse the earlier SHA's receipt. An existing valid receipt and matching log for
the same source may be reused; evidence for another SHA, incomplete checks,
missing/tampered logs or a changed worktree cannot qualify the candidate.
Daily development and public merges still use checks selected
by change risk; this does not require the full release suite on every merge.

Before pushing a release tag, `tools/release-verification.py publish` verifies
that local receipt against the exact clean public source commit/tree, then writes
the commit's
`hexproof/local-release` GitHub status. Only generic verification metadata is
public; private receipts, operator paths and raw logs stay private.
The status is the trusted development machine's assertion, using the existing
GitHub identity with commit-status write permission; it is not an independent
remote execution or a new signature service. See the command sequence in
[the native release procedure](multica-release.md#validate-the-frozen-source-locally).

Release CI reads that exact public SHA's latest matching status before any
package job. Missing, pending or failed qualification blocks the build; a
historical success or another commit's result does not satisfy it. Manual
artifact builds use the same gate and must keep the committed source version.
Assembly reads the qualification again after packaging to catch a revoked
result before assembling or uploading release assets.
CI does not repeat QML/CTest, Go vet/test/race or the static/tool suite. It keeps
the stable card-data schema check, complete Forge source package, all supported
platform builds and package startup/version/architecture checks, signing,
checksums and attestations. Assembly requires successful preparation, Forge
source packaging and every platform job. CI needs only commit-status read
permission and receives no local validation credentials or private evidence.
Immutable Forge downloads retain cache size/checksum validation on every use;
compiled adapters and verification outcomes are not cached by that action.

Run the bounded engine checks locally with
`python3 tools/run-forge-regression.py`. They are separate from the normal local
verification scopes, require JDK 21 and Go, and reuse checksum-verified base
archives under `build/forge-overlay/downloads` on a POSIX workstation. See the
[native regression guide](../third_party/forge-runtime/native-host/TESTING.md)
for their scope and evidence.

Local scope selection does not excuse a failed applicable test, disable
compiler diagnostics, or remove release/platform coverage. Report what actually
ran, what failed, and any remaining validation gap. Never claim visual
confirmation from compilation or offscreen assertions alone.
The accepted Qt minimum is 6.5; checks on newer Qt versions do not certify the
entire supported version range. Changing that minimum requires an explicit
support decision and corresponding build configuration changes.

## Native GUI verification is allowed when useful

An agent may launch and operate real Hexproof test clients when needed to
reproduce or verify the requested behavior. Briefly explain the scenario first.
Do not automatically hand every visual check back to the owner, and do not
make native GUI execution a ritual for unrelated changes or every code edit.

For substantial layout changes, clipping/focus/dragging bugs, or native display
issues, reproduce and inspect the final result in a real client when the
environment supports it. Small copy/style changes with adequately covered
behavior do not automatically require a native run. Batch visual confirmation
after a coherent fix, rather than relaunching after each intermediate edit.

For changes to phase-rail density, deck-gallery scrolling, shared hover
previews, or cache progress that can move interactive content, use the affected
contracts in the [UI behavior baseline](ui-behavior-baseline.md). Run its focused
automated guards and relevant native scenarios when the change needs native
verification under the rules above. Keep compatibility expectations explicit;
an automated-only result does not establish native acceptance. This does not
add a GUI requirement to unrelated changes.

- Use maximized windows on the actual test display for the primary native GUI
  checks and AI review, including multi-client runs. Switch the active test
  window between seats without resizing or tiling them. Wait for maximized
  geometry to settle before input or capture; scenarios must preserve this
  baseline unless testing an explicit window-state transition.
- Record the requested and actual window mode, logical dimensions, display
  geometry and device pixel ratio in native evidence. Fixed sizes, minimum
  windows, scaling variants and F11 fullscreen transitions are explicit
  supplementary checks when relevant, rather than substitutes for the primary
  maximized run.
- Use isolated test profiles and a loopback test server by default. The local
  multi-client helper can prepare separate profiles and test events. Avoid
  modifying the owner's normal settings, reconnect credentials, or saved decks.
- Resolve the exact test window before sending input or taking a screenshot.
  Restrict capture/input to those Hexproof windows; do not capture unrelated
  desktop content or interact with the owner's live games.
- GUI verification does not itself authorize creating public-server rooms,
  joining real events, bypassing desktop isolation, or changing remote services.
  Follow the applicable installation policy when additional tools are needed;
  do not treat GUI verification as permission to use an unapproved source.
- Track and stop only processes started for the check. Do not kill all client
  or server processes. Preserve useful logs/screenshots in a task-specific
  location and explain any test profiles left for follow-up.
  Once an isolated test profile is no longer in use, its regenerable card-data,
  image and Qt caches may be removed. Preserve verification logs, screenshots
  and rollback packages; do not clear the owner's normal profile or live state.
- If the environment cannot provide native verification, use the available
  focused/offscreen tests, state the limitation, and request only the specific
  remaining observation needed from the owner.

## Size is a review hint, not a build limit

`tools/check-module-size.py` reports advisory thresholds from
`tools/module-size-policy.json`. A file exceeding 700 lines (or any configured
threshold) does not fail local checks, CI, or release packaging. Tests receive
extra allowance for fixtures and scenarios. Generated and vendored files are
excluded. An unreadable source or invalid checker configuration still fails:
that is a broken check, not an oversized module.

Review cohesion, authoritative state ownership, dependency direction,
testability, and actual growth. Extract a module when it creates a meaningful
boundary. Do not scatter cohesive code, add forwarding-only shells, abbreviate
names, compress formatting, or weaken tests to meet a number. Small local
presentation helpers are not forbidden merely because a file is a screen.
An unrelated refactor is not a prerequisite for a focused bug fix. Numeric
thresholds may be adjusted with a rationale in the change, without a separate
owner exception or an automatic downward-only ratchet.

## Quality tools check contracts, not incidental spelling

- Formatting applies to changed first-party C/C++ lines (including C automation
  helpers) and Go source. Do not reformat unrelated files as part of a bug fix.
- License checks cover Git-tracked and nonignored new first-party sources,
  including Python and packaging templates, not ignored build/data output or
  vendored code. SPDX and applicable copyright notices belong in the leading
  comment/docstring, without a five-line cap. Preserve upstream notices;
  exempting vendor files from the project-header checker does not remove their
  license obligations.
- Protocol checks validate actual schemas, field/type mappings, generated
  bindings, and fixtures. They must not prescribe the spelling/location of a
  Python import. Generation validates contracts before writing output, so an
  invalid schema/fixture/source mapping does not partially refresh bindings.
- Prefer behavior tests. Narrow source guards remain useful for known unsafe
  API usage, ownership boundaries, and packaging/workflow wiring; they are not
  a general ban on helper functions, method reordering, or moving a module.
  Update such guards with a legitimate refactor while retaining evidence for
  the invariant. Do not replace functional coverage with token/count checks.
- Maintain tests by the failures they prevent. Preserve regressions for reported
  faults, privacy, atomic state changes, cancellation and session transitions.
  Merge checks that protect the same boundary, and remove obsolete presentation
  assertions or source-spelling checks when behavior coverage already protects
  the contract. Checking that another test contains a particular call does not
  demonstrate that behavior. Test counts and repeated green runs are not coverage
  targets; distinguish simulated boundaries from real-engine and native GUI runs.
- Checkers should distinguish invalid input or broken execution from advisory
  findings, and have regression cases for both accepted and rejected inputs.
  Correct false positives without turning off the protected contract.

## Dependencies and release scope

- Keep declared dependencies and reproducible lock/pin workflows. Record a new
  dependency, changed trust boundary, or material stack choice in the decision
  log. A routine compatible version bump needs the manifest/pin update,
  relevant checks and notices, not a separate architecture document.
- Develop, review and merge directly in `ClayStan404/hexproof`. Never commit
  operator configuration, credentials, owner-only notes or private Git history.
  Confirm the actual public merge before reporting source delivery; see
  [delivery boundaries](autonomous-development.md#public-merge-and-source-delivery).
- Production release deployment uses verified matching release artifacts.
  Use `deploy/deploy-release-server.sh` as the owner-operated version upgrade
  entry point, with explicitly resolved target names. It supports the cloud
  hubs and configured home nodes; see
  [home release upgrades](../deploy/home/README.md#production-release-upgrades)
  for Draft opt-in, read-only checks and runtime scope.
  Dedicated local/test-server workflows may build source. Do not turn that
  test exception into an unrequested production deployment or enable Forge.
- Release tags, version parity, asset checksums, provenance, supported-platform
  packaging, and update-channel compatibility remain meaningful gates. Changes
  to supported platforms or client/server compatibility need an explicit
  product/maintenance decision, not an exemption to make a check pass.

## Substantive safeguards remain

- Preserve server authority and redacted owner/opponent/spectator projections,
  atomic mutations, authentication, bounded queues, and cancellation semantics.
- Keep manual gameplay separate from optional Forge enforcement; do not enable
  Forge in default deployment as a side effect of development or testing.
- Keep canonical protocol schemas, generated names, and fixtures consistent
  when the wire contract changes. No schema churn is required for non-wire work.
- Retain SPDX/third-party notices, formatting, translations, and explicit safe
  QML text rendering. `Text.PlainText` may appear anywhere among a `Text` item's
  direct properties; it need not be the first property. Plain `MenuItem` and
  `MenuSeparator` visibility still uses the conditional wrappers to avoid
  invisible rows occupying space.
- Preserve unrelated working-tree edits. Follow the owner's commit agreement;
  a commit does not authorize pushing, publishing, deployment, restarting
  services, or rewriting history. Verify the requested deployment target from
  current configuration instead of assuming an old host remains authoritative.
