# Native Multica operations

Multica Autopilots, the approved team and ordinary Git/GitHub tools manage the
public `ClayStan404/hexproof` repository. Hexproof adds no AI scheduler or model
adapter. All development and integration happen there; a confirmed public merge
is source delivery, not a release or deployment.

## Operator configuration

Resolve the trusted manifest from `$HEXPROOF_OPERATIONS_FILE`, defaulting to
`${XDG_STATE_HOME:-$HOME/.local/state}/hexproof-operator/multica-operations.json`.
Its repository binding is:

```json
{"repositories":{"canonical":"ClayStan404/hexproof","ref":"refs/heads/master"}}
```

Actual native IDs, runtime paths, schedules, provider bindings and selected hosts
belong in that operator-owned file, not in source or task prompts. The manifest
is trusted input, not a Multica API schema or scheduler database. Check native
pause/trigger state independently; configuration does not prove execution.
Secrets use supported credential storage or protected files, not this manifest.

`native.team` records role agent IDs, at most two concurrent developers and two
no-progress attempts before reassessment. These are native dispatch instructions,
not server-enforced task locks or an added scheduler. Skip agents recorded in
`native.team.unavailableAgentIds` until their named blocker is resolved.
`native.feedbackPolicyAgents`
maps each permitted contribution policy to its allowed agent IDs; always intersect
that set with `native.allowedAgentIds` and the current task scope. Missing policy
bindings fail closed. Owner-scoped source work may use the broader configured
team without inheriting permission to share restricted feedback context.

Deployment target and home-node inventories are also external:
`$HEXPROOF_DEPLOYMENT_TARGETS_FILE` and `$HEXPROOF_NODES_FILE`, defaulting to
`deployment-targets.json` and `nodes.json` in the same operator state directory.
Resolve exact aliases, units, routes and endpoints from those files and current
readback. Public catalogs contain only intended client-facing service details.
See [deployment](../deploy/home/README.md) and
[feedback receiver operations](feedback-operations.md#selected-deployment-host).

## Native operations

| Operation | Trigger | Purpose |
| --- | --- | --- |
| Feedback intake | Bound metadata webhook | Read current permitted public input and assess work. |
| Known task continuation | Issue-scoped one-shot event, condition or timer | Resume the same task/candidate after reconciling its current state. |
| Daily reconciliation | Native schedule from operator configuration | Reconcile interrupted tasks, pending feedback outcomes and release work. |
| Weekly release | Native schedule from operator configuration | Select one eligible candidate and finish a qualified release under its publish mode. |

Control tasks have no serialized development resource. They may read the trusted
checkout and use isolated output/verification directories, but must not reserve
or modify an active developer checkout. Code changes follow the normal public
PR path and the [team policy](autonomous-development.md#team-assignment-and-independence).
Continue from the latest compact handoff and new events; inspect older history
only for missing evidence, conflicts or uncertain effects. Preserve existing
feedback case, connection and provider-policy bindings during host replacement.
Standing authorization does not bypass platform approval controls or authorize
new providers, credentials, destinations or deployments.

## Public merge and source delivery

Follow [the merge procedure](autonomous-development.md#public-merge-and-source-delivery).
Verify the actual public PR merge and its exact candidate/review/check evidence,
then report the public commit through the receiver's typed outcome. An ended run
or accepted GitHub request is not proof of a merge. Reconcile uncertain writes
before retrying. There is no export task or second repository to synchronize.
For fully resolved reports, use reviewed PR closing references and verify
GitHub's automatic closure at merge. Recover a missed closure only for a new
reviewed merge's recorded closure set, after reconciling current case/merge/issue
activity; do not retroactively close historical issues. GitHub closure leaves
the receiver case open; retain follow-up and release delivery for it. Scan known case
associations regardless of the GitHub issue's open/closed state.

## Known task continuation

When `native.continuations.enabled` is true, the approved team may register
bounded [native issue wakeups](multica-recovery.md#native-wakeups-for-known-work)
for existing tasks. This permits one-shot waits, not changes to schedules,
models, destinations or activation. Finish completed review subtasks; name the
next action or exact wait for unfinished business. Short same-run steps need no
wakeup. Daily reconciliation is fallback, not a mandatory delay between stages.

## Daily reconciliation task

Read current operator configuration, known handoffs and new events. When disabled,
exit with `PREPARED_DISABLED`; do not replay or write GitHub. When enabled:

1. Inspect canonical tasks and current public PR/branch state before replacing
   interrupted work. Preserve an existing candidate, approval and confirmed merge.
   Reconcile associated receiver outcomes with the same saved operation ID; a
   failed handoff does not require repeating completed development or review.
2. Apply [native intake recovery](multica-recovery.md) only after `feedback.enabled`
   and the real receiver connection are configured. Read current closure,
   removal and input revisions first. Closed cases are not replayed; retain shared
   work still justified by other active reports.
3. A failed developer/reviewer may be replaced only within the approved team,
   retaining independent sessions and the highest configured effort. Record the
   actual model and cancel the superseded retry. Preserve the contribution-specific
   provider intersection and the required reviewer for its risk. If Mika cannot
   start because of model capacity, an approved Codex substitute may handle the
   bounded control task without changing global models or gaining broader authority.
   Finish in-flight review/delivery before opening more development when Codex
   capacity is scarce; no silent reviewer downgrade or paid overage.
4. Continue the existing release candidate/tag/run. Keep the configured action
   and time limits; an unresolved or incomplete scan remains visible. Do not
   turn a limit into success or create a replacement CI run without reconciliation.

These are native runbook rules, not a new application recovery engine. Receiver
idempotency, GitHub expected-head operations and qualification checks remain
independent safeguards.

## Workstation startup and connection readiness

Use Multica's supported login autostart with a persistent installed CLI, not an
AppImage's temporary mount path or a new Hexproof launcher. Resolve the actual
profile/runtime from operator configuration and inspect daemon/autostart status.
Only one owner should manage daemon lifetime; reopening the GUI must not create
a duplicate service. Login autostart does not promise execution while powered
off. A replacement runtime still needs authentication, model and binding readback.

The receiver snapshot tunnel, if used, is operator configuration outside source.
Its service must wait for its own listener, remove only its own stale socket and
retry bounded startup failures. A live SSH process or local socket alone does not
prove the remote endpoint: read the restricted current snapshot and binding.
Tunnel configuration never authorizes changes to the remote receiver.

Keep long-running work separate from bounded network operations. A semantic
inactivity watchdog may not recognize an active long tool call. Verify the
installed platform's behavior before changing thresholds; prompt time limits
are not an independent hard deadline or alert while an agent is stalled.
Use the bounded reads and reconciliation in
[interrupted-work recovery](multica-recovery.md#continue-interrupted-work-without-repeating-it).

## Weekly release task

Use [the release procedure](multica-release.md): one frozen public SHA, complete
local qualification, packaging CI and independent final AI review. `draft-only`
ends at a verified draft; explicitly configured `publish-after-checks` permits
publication without a recurring human gate. No eligible change means no version
bump or CI run. Release tasks do not deploy servers or enable feedback.

## Withdrawal cleanup

Use [the removal procedure](multica-removal.md) for task cancellation, supported
content deletion and explicit local deletion or containment. The local helper
plans by default; `--apply --purge` deletes only inventoried stopped case-owned
copies and reports partial failures. Retained sessions, execution logs and
quarantine remain outstanding obligations. Chat deletion is not task-history
purge; do not acknowledge removal until all required copies are verified.
Ordinary closure retains history and does not await purge.

## Activation and host replacement

Activation is a separately authorized operation. Check the installed tools,
GitHub permissions, actual team/provider policy, receiver readiness and current
native configuration. Store webhook URLs/signing secrets privately. Enable only
the desired operations and read them back. Feedback also needs its notice,
restricted snapshot connection, monitoring and truthful closure/removal states.

Before replacing the machine, stop dispatch and settle active tasks. Preserve
operation intents, current handoffs, case bindings and removal obligations; then
verify the new paths, runtime, credentials and GUI access. Do not leave duplicate
schedules on both hosts. Copying the repository does not authenticate a host.
