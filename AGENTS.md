# Repository Guidelines

## Project Structure & Module Organization

Hexproof is a native manual-tabletop MTG application; an optional Forge rules mode (P14) hosts the external rules engine as a server-managed or creator-managed process rather than embedding one. Optional trusted player hosting uses a bundled Go helper and a private hub relay; see `docs/player-hosted-forge.md`. Its locked stack is a Qt 6/QML/C++20 client (`apps/client-qt/`) and Go WebSocket room hub (`apps/server/`), exchanging versioned `hexproof.v2` JSON. Optional official-server accounts share one authority; see `docs/accounts.md`. Electron/web clients and matchmaking are out of scope. `testdata/protocol/v2/` holds shared fixtures; `docs/` holds product specs and the phased plan; `deploy/` and `packaging/` hold deployment and release files. Keep generated output in `build/`.

For application development, builds, verification, or deployment, consult `docs/development-policy.md`. For other tasks, read only its relevant sections when needed. For application work, use the relevant sections of `docs/implementation-plan.md` to locate the English behavior specifications; do not reread the entire roadmap for unrelated tooling or documentation changes. When resuming work from another chat or checking the current development focus, consult `docs/development-handoff.md`; treat it as a status index, not as behavior authority. Completed plans are historical context, not permanent workflow instructions. Owner-only notes and operational evidence live outside the repository; do not publish them.

All development branches, pull requests, independent reviews, merges and release
work target `ClayStan404/hexproof`. A public merge publishes its source directly;
there is no private-repository mirror stage. Do not copy private Git history,
operator configuration, credentials or raw task logs into public commits.
Resolve operational authorization from `$HEXPROOF_OPERATIONS_FILE`, or
`${XDG_STATE_HOME:-$HOME/.local/state}/hexproof-operator/multica-operations.json`.
Keep actual host inventories and credentials in that private operator directory.

## Build, Test, and Development Commands

Run commands from the repository root. Choose verification by change risk; do not run every command for every edit:

```sh
cmake -S apps/client-qt -B build/client-qt -G Ninja
cmake --build build/client-qt
ctest --test-dir build/client-qt --output-on-failure
(cd apps/server && go vet ./... && go test ./...)
(cd apps/server && go test -race ./internal/room ./internal/server ./internal/tournament ./internal/forgehost ./internal/runtimepkg)
(cd apps/server && CGO_ENABLED=0 go build -o ../../build/server/hexproof-server ./cmd/hexproof-server)
```

For the basic two-client flow, start `./build/server/hexproof-server -bind 127.0.0.1 -port 57320` and follow `docs/manual-smoke.md`.

`./tools/verify.sh --scope static|client|server` selects shared static checks plus the requested domain. With no scope, it runs the complete automated suite. Builds are incremental; use `--clean` for a deliberate clean rebuild. `--quick` skips CTest and race tests and is not full verification. Format only changed Go files with `gofmt -w <paths>`.

## Deployment Diagnostics

For production home-node installation and upgrades, use only
`deploy/deploy-release-server.sh` with explicit targets and version. Supply
verified runtime/config inputs for first installation; routine upgrades reuse
the installed runtime. Backend, packager and target-host installer are internal
components. Do not recreate a separate source-deployment or automatic
uninstall/reinstall entry point. One-time cleanup requires its own owner-scoped
maintenance task. Scripts under `build/` are task artifacts, not deployment
entry points. See the [operator procedure](deploy/home/README.md).

Resolve the exact host alias, service unit, and listen address from the owner's requested target and the current deployment scripts/configuration; do not assume there is only one server or that an old host is still the active target. Use existing SSH aliases directly and do not inspect or modify `~/.ssh`. For read-only diagnostics, detect the remote OS and inspect the resolved service without paging.

Do not assume a repository build is deployed merely because local tests pass. Do not restart the service, replace the remote binary, or modify `/etc` unless the user explicitly requests that system change.

## Coding Style & Naming Conventions

Format Go with `gofmt`; use lowercase packages, `PascalCase` exported names, and `camelCase` locals. Follow existing Qt style: four spaces, `PascalCase` types, `lowerCamelCase` functions, and `m_` members. Use `lowerCamelCase` for QML IDs and properties. Keep SPDX GPL-3.0-or-later headers and applicable copyright notices in the leading comment, without a fixed line limit. Record new dependencies and material stack/architecture choices in `docs/decisions.md`; routine compatible version bumps need updated manifests, notices when applicable, and relevant checks, not a new decision essay.

## Testing Guidelines

Go tests use `*_test.go` and `TestXxx`; client tests use Qt Test through CTest. Update protocol fixtures when wire messages change. Test room state and hidden-information redaction where relevant, and run race tests for concurrency/shared-state changes. There is no numeric coverage target or blocking file-length cap.

Build and run automated and native GUI checks on the current agent workstation.

Native GUI verification is allowed for the requested layout, interaction, or platform behavior. For substantial layout changes, clipping/focus/dragging bugs, or native display issues, reproduce and inspect the final result in a real client when the environment supports it. Use maximized windows on the actual test display by default, including AI review and multi-client scenarios. Fixed or compact windows are explicit supplementary layout probes. Announce the scenario, use isolated test profiles and local services, and restrict input/capture to test windows. Do not require a real GUI run for every code edit or unrelated change. Follow `docs/development-policy.md` for test selection, process cleanup, and reporting validation gaps.

## Commit & Pull Request Guidelines

The owner authorizes normal public delivery of requested changes: commit after
appropriate checks, push the task branch, open a PR, obtain independent AI
review, and merge after the required checks pass. Continue without recurring
approval; release and deployment authorization remain separate. An explicit
local-only, draft-only or review-only request limits that task accordingly.

Use a feature branch or isolated worktree before editing; do not develop or
push directly on `master`. All coding agents, including owner-directed sessions
outside Multica, use the same [completion procedure](docs/autonomous-development.md#complete-an-owner-request).
A local commit or green CI alone is not completed delivery. Report the verified
public merge, or the concrete blocker and pending PR, rather than leaving
unpublished commits as an unmentioned follow-up. Preserve unrelated work.

Follow the concise, scoped history style, such as `client: fix room navigation`, `tools: improve local testing`, or `docs: clarify privacy`; phase prefixes remain appropriate for phase work. Version advances use `Release: advance application version to X.Y.Z`. Follow the owner's commit agreement above; release authorization remains separate. PRs should identify the affected feature or phase, summarize behavior changes, link an issue when one exists, and list commands with pass/fail results. Preserve all applicable third-party copyright notices.

## Agent-Specific Instructions

Work one coherent owner-scoped task at a time; a vertical slice may span client, server, tests, and docs. Do not force completed work back through the original greenfield phase order. Update English specifications when behavior changes and keep design records proportional to the change. Treat source-size thresholds as review hints: extract for cohesion and testability, not to satisfy a line count, and do not require unrelated refactoring before fixing a bug. Preserve trust-server privacy and redacted opponent/spectator projections. Resolve unclear game or room semantics from the English product specifications and current protocol invariants; ask the owner when those sources do not define the intended behavior.
