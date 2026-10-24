# Native Multica recovery and cancellation

This is the bounded native recovery/cancellation runbook. Current activation
comes from the [operator configuration](multica-operations.md#operator-configuration) and native
readback. API behavior was qualified against server revision `654b8ca95`; check
installed capabilities when changing versions. Historical trials do not set the
current operation state.

Use the [feedback connection](multica-feedback.md),
[development workflow](autonomous-development.md) and existing
[removal contract](privacy.md#in-app-feedback). Recovery belongs to Multica's
native tasks and Autopilots. There is no Hexproof polling daemon, model launcher
or second scheduling database.

## Keep event intake separate from recovery

Retain `run_only` for the metadata webhook. An offline runtime can cause a
terminal skipped native run. Repeating the receiver's unchanged idempotency key
does not start it again. A successful HTTP receipt establishes delivery
information, not execution or development success.

`create_issue` is not a safe per-feedback queue: its recent same-title guard can
accept a distinct event but skip its task. The qualified revision checks active
same-title issues for the project/Autopilot within 60 seconds and supports
`{{date}}`, not case-ID substitution. Preserve `run_only` plus explicit recovery.

Use one separate native scheduled recovery Autopilot, after qualification, to
inspect durable intake history. Its next successful run scans unresolved
history; it must not assume every missed schedule occurrence was replayed.
The native scheduler collapses missed occurrences and applies a lateness
window. Restarting a local daemon does not establish scheduler-server restart
behavior. Run recovery outside the serialized development checkout so ongoing
implementation does not block it on that checkout's lock. Runtime capacity,
model availability and response time remain separate qualifications.

## Native wakeups for known work

Use Multica's issue-scoped, one-shot wakeups for an existing task's concrete
wait; daily reconciliation remains the fallback for missed intake and unknown
work. The trusted manifest's `native.continuations` authorizes these bounded
continuations, not new recurring schedules. Preserve the current issue, thread,
candidate and delivery intent. A wakeup is a notification to recheck facts, not
approval to merge, publish or retry a cancelled task.
Use the manifest's continuation limits; the examples below show their current
values rather than granting a separate allowance.

Choose one completion handoff: use the existing direct result notification when
it already starts the coordinator, otherwise register a condition on the known
child. Do not subscribe to all comments or every state change. Continue short
local phases in the same run; do not introduce a wakeup between every step.
Before registering, inspect `issue wakeup list` and current work. Keep one rule
per issue/wait/source identity and record its ID in the current handoff. After
an uncertain create, reconcile that list before retrying; create is not assumed
idempotent. When replacing a wait, disable its obsolete rule first.

Use the installed `issue wakeup` help for exact supported arguments. For example,
from the trusted native runtime (the instruction file contains a short current
handoff and the permitted next step, never credentials):

```sh
multica issue wakeup create "$case_issue" --agent-id "$coordinator" \
  --until-issue "$review_issue" --until-issue-state done --mode once \
  --expires-in 72h --on-timeout wake --instruction-file "$handoff_file"
multica issue wakeup create "$developer_issue" --agent-id "$coordinator" \
  --event task.failed --task-id "$developer_run" --mode once \
  --expires-in 72h --on-timeout end --instruction-file "$handoff_file"
```

These are alternative example waits, not commands to run unconditionally.
Task events are scoped to their issue: register a child's run-failure rule on
that child and name the canonical parent in the instruction. Use one such
failure rule per original run, not an unfiltered recurring subscription.
Do not automatically arm another failure rule for its recovery run. On wake,
reconcile current receiver permission/input, native activity and external effects
using the interrupted-work procedure below. Reuse successful work; stop after
one automatic continuation of the original failed run. Explicit or ambiguous
cancellation still requires trusted continuation authority.

Use `issue runs --active` for the issue's current execution, `--siblings` for a
bounded family hint, and `issue timeline --activity-only --since <timestamp>`
when transitions are needed. The family view can truncate and is not a lock;
inspect actual related issues before consequential writes. A reviewer finishes
its own task after recording the conclusion, including a request for changes;
only an approval of the exact candidate can authorize the parent's merge.

When waiting for an external result without a supported condition, use a
single `--kind at --after 15m` wakeup and a recorded check count/deadline. A tag
release Actions run is not a linked PR: `--until-pr checks` cannot monitor it.
Retain its exact repository/run ID and use the release runbook's bounded checks.
On a timeout, reassess once; do not treat elapsed time as success or manufacture
a new candidate. Finish or disable obsolete wakeups when their business step
ends. Terminal issue states disable wakeups, so do not mark a task done merely
to yield while work remains. Reopening does not automatically rearm a wait.

This uses native scheduling only. Runbook uniqueness and retry limits are not
claims of server-enforced global exactly-once processing. Model effort, runtime
watchdogs, provider policy and global operation schedules remain unchanged.

## Bounded native recovery runbook

Supply fixed workspace, intake Autopilot, trigger and restricted snapshot
connection identifiers in trusted instructions. A webhook or feedback body
cannot change those destinations, permissions, attempt limits or instructions.
The trusted setup must state numerical page, candidate, replay and time limits.
A starting policy to qualify is 100 rows per page, five pages per collection,
20 candidate details, three original-delivery replays and ten minutes per
scan. These are runbook limits, not a demonstrated hard execution deadline.
If history exceeds the scan budget, Mika must arrange bounded continuation
through native tasks without losing unresolved older records; large-backlog
coverage has not been qualified by the small synthetic trial.

1. Enumerate the intake's native deliveries and runs with pagination. The
   lists cap pages at 100; their `total` is the current page length, not the
   complete history count. Deduplicate IDs across overlapping passes. A page/time
   limit means an incomplete scan; do not report an empty backlog or advance a completeness
   marker after an incomplete scan. Newest-first offset pagination is not a
   frozen snapshot, and equal timestamps have no guaranteed secondary order.
2. Read details only for relevant records. The installed CLI's run list omits
   payloads and has no replay command. The supported native API exposes
   delivery/run details and delivery replay. Use the task's injected native
   authentication, never an owner profile credential copied into a prompt or
   script. Do not print tokens, selected request headers or whole raw payloads.
   A missing native permission is a failed qualification, not permission to
   broaden the credential.
3. Initially automate only an original skipped event conclusively caused by
   offline admission with no task ever created. Read linked native state;
   reason text alone is insufficient. Ignored filters, revoked grants,
   unavailable models and partially executed failures need cause-specific
   reconciliation. A failed task may already have edited files or opened a PR.
4. Locate the canonical case using case ID and destination binding, and fetch
   its current restricted receiver snapshot. An old notification is not current
   content. Closed cases are not replayed; cancel case-specific follow-up while
   retaining history, without acknowledging purge. Removed cases are not
   replayed; cancel and contain any existing canonical work using the removal
   procedure below. Existing active, completed
   or blocked case work is reconciled before any further dispatch. Verify the
   intended runtime is online, the intake Autopilot active and the original
   trigger enabled immediately before replay. Invalid/empty stored bodies or
   rejected signatures also prevent replay; an HTTP 400 is not a generic
   retryable admission failure.
5. Resolve the original delivery and inspect all replay children. Permit at
   most **one automatic replay per original** in the initial policy. Use an
   identity such as `hexproof-native-recovery-v1:<original-delivery-UUID>:1`
   for the native replay `Idempotency-Key`. Never replay a replay or use a
   timestamp/random key. Concurrent or repeated submissions of that same key
   converge on the native replay record.
6. Reconcile an uncertain POST by reading lineage or retrying its exact key
   while replay prerequisites still hold. Those prerequisites are checked
   before the API's idempotency lookup: after pause/disable, use GET/lineage
   instead of expecting a repeated POST to return the earlier result.
   An unsuccessful replay consumes the automatic attempt; record it for Mika
   to investigate. A repaired cause and a deliberately recorded later attempt
   are different from an unlimited retry loop. Preserve the original receiver
   notification identity; native recovery does not mint replacement user input.
7. Exit after recording replay admission. A later scan follows the linked
   run/task and verifies the outcome. Do not occupy a serial worker while
   waiting for work that needs the same worker. Keep associations, lineage and
   unresolved results in native records rather than a new application ledger.

The native replay route is
`POST /api/autopilots/{autopilot}/deliveries/{original}/replay`. It creates a
new delivery with explicit original-delivery lineage. Native authorization
also checks the task's human originator and their access to that Autopilot;
mere workspace membership is not a promise of replay authority. The restricted
receiver's current-snapshot and publication checks remain independently
necessary. Native replay alone cannot prove unique case creation or make a
partially completed development task safe to repeat.

Same-original/same-key deduplication is enforced by the native API. Offline-only
eligibility, one automatic attempt and prohibition of replaying a replay are
trusted runbook rules; the API permits broader actions with different keys.
The isolated test must not be presented as enforcement of all those rules
against arbitrary agent behavior.

## Continue interrupted work without repeating it

A failed or interrupted task may already have changed source or published a
result. Reconcile that work instead of repeating development. This continuation
procedure does not broaden the offline-only automatic webhook replay rule or
activate a schedule.

1. Check the restricted receiver connection and the intended native runtime
   before dispatch. A running SSH process is not connection readiness. Read the
   fresh case and retain its binding, input revision, contribution policy and
   existing native issue. A closed or removed case follows its existing stop
   rules. Inspect queued/running tasks before creating any continuation.
2. Reconcile the interrupted task's actual side effects: candidate SHA, public
   PR, independent review bound to that exact diff, saved publication intent
   and current receiver projection. Reuse completed work. If the reviewed head
   changed, do not reuse approval. If the intended reply is already published,
   record completion without sending it again. If publication is uncertain,
   read back the existing stable output ID before another write.
3. Prefer the existing [one-shot native wait](#native-wakeups-for-known-work).
   Inspect both pending and consumed wait/continuation records. The manifest's
   limit is one automatic continuation per original failed run across all
   passes, not one per daily scan; a consumed attempt cannot be reset by a new
   comment, timer or invocation. If that allowance is spent, record the blocker
   for cause-specific repair without another automatic dispatch.
   For a terminal task with unfinished work and no prior continuation, send at most one continuation
   on the existing native issue and
   thread, explicitly mentioning only the permitted assignee. Record the prior
   task ID and remaining step in the comment; check for an existing continuation
   first. Use the native trigger preview and retain the create response's
   `trigger_outcomes` plus linked task ID. A saved comment is not a dispatched
   task. `issue rerun` is a fresh execution and is not proof of safe continuation.
   Do not automatically continue a task the operator explicitly cancelled. A
   shutdown-associated `failure_reason=cancelled` needs trusted lifecycle
   evidence and recovery authority; an open issue alone cannot distinguish it
   from an intentional stop. Keep an ambiguous cancellation unresolved.
4. Bound each external read to 30 seconds and at most two additional attempts
   for transient failures, within the overall invocation budget. These are
   command/runbook limits, not a new platform watchdog. Prefer a supported
   working REST path when another client transport fails. For an uncertain
   mutation, read back its identity and effects before retrying. Never retry
   by inventing a new feedback event, output UUID, PR or release candidate.
   Continuations share the configured per-invocation action/time budget; a
   repeated failure remains unresolved instead of spawning further tasks.
5. Report distinct states: waiting for a runtime/connection, queued, running,
   failed with a concrete cause, and delivered. For an approved draft handoff,
   completion requires the receiver's published projection; native task
   completion alone does not establish delivery. Supervisor recovery must stay
   visible in the qualification record and must not be called unattended success.

Use Multica's native inactivity watchdogs and task history for stalled runs.
Do not cancel a legitimate long build solely because of total elapsed time.
Progress-free execution, an active long tool call and a queued task are different
conditions. Prompt time limits are runbook guidance, not a platform-enforced
deadline. Native retries or reusable sessions likewise do not establish exactly
once completion; reconcile side effects before continuing.

## Cancellation while development is active

Use a control project without the serialized development repository resource to
call native `issue cancel-task` on an exact active task. Native cancellation
must remain available while a developer occupies the working directory.

Changing an issue to `cancelled`, pausing an Autopilot or disabling a trigger
does not by itself establish termination of already admitted work. For removal:

1. Fetch current removal state and identify the exact canonical case, all
   delegated children and active/queued tasks. The native family activity view
   is limited in scope and can truncate at 20 tasks; it is not a complete
   descendant inventory. Do not cancel unrelated work.
2. Cancel those tasks through native task cancellation. Read back terminal
   states and verify relevant local execution has stopped before cleaning its
   artifacts. Traverse the family explicitly; deleting a parent issue is not
   proof that child tasks were canceled.
3. Prevent future processing of revoked content, including stale queued work
   and retry/resume context. Quarantine or sanitize project-controlled derived
   material before reuse. Independently justified clean code may remain under
   the existing privacy contract.
4. Record what was actually cleaned and what remains. Cancellation is not
   rollback of an already performed external action, nor deletion of native
   logs, sessions, attachments or provider records.

## Cleanup remains a separate obligation

Editing current task text does not erase execution history, sessions, attachments
or local artifacts. Supported comment/attachment deletion does not establish
removal from execution copies, object storage or resumed sessions. A disappearing
task, archived agent or AI deletion claim is not proof of purge.

The restricted receiver listener deliberately has no removal-acknowledgment
operation. Keep `coordinator_cleanup_pending` until a trusted procedure verifies
the project-controlled copies covered by the removal contract. Do not classify
all native platform storage as exempt provider retention merely because the
platform is hosted. Do not weaken the privacy notice to convert retained
project-controlled content into a successful deletion.

Provider records and third-party public copies have the separate limits already
described in the privacy notice. This qualification does not promise deletion
of those records. Reporting removal complete still needs a supported and verified cleanup path
for the project's own native copies and resumed contexts; normal closure does not.

## Evidence and limits

Bounded native offline discovery/replay and repeat-pass deduplication have
qualification evidence. They do not establish large-backlog coverage, concurrent
case creation, recovery of partially executed development, server-side scheduler
restart behavior or complete cleanup. Read linked task state: an Autopilot run
can appear running while its task is queued. Current operation activation is
recorded in the manifest and native readback, not inferred from these limits.

Source research alone is not a live qualification. References pinned to the
inspected implementation:
[dispatch and title guard](https://github.com/multica-ai/multica/blob/654b8ca95/server/internal/service/autopilot.go),
[native schedule handling](https://github.com/multica-ai/multica/blob/654b8ca95/server/internal/scheduler/jobs_autopilot.go),
[delivery replay](https://github.com/multica-ai/multica/blob/654b8ca95/server/internal/handler/webhook_delivery.go),
[delivery pagination](https://github.com/multica-ai/multica/blob/654b8ca95/server/pkg/db/queries/webhook_delivery.sql),
[task activity and history](https://github.com/multica-ai/multica/blob/654b8ca95/server/internal/handler/daemon.go),
[local-directory retention](https://github.com/multica-ai/multica/blob/654b8ca95/server/internal/daemon/gc.go).
