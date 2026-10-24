# Native feedback withdrawal procedure

This procedure applies to a request to remove content. Ordinary **Close
feedback** stops follow-up while retaining history and does not invoke this
purge procedure or wait for a cleanup acknowledgment; see
[case closure](public-feedback-v2.md#close-follow-up-while-retaining-history).

This procedure delivers cancellation, supported native content cleanup and local
deletion or containment for one withdrawn feedback case. It does not acknowledge purge to the
receiver. The [native connection](multica-feedback.md#removal-acknowledgement-is-not-exposed)
still accepts only `snapshot` and `project`; keep the original processor binding,
revocation revision and outstanding cleanup obligation.

The native operations below are grounded in Multica CLI 0.6.5 and server source
`654b8ca95`. Check the deployed version and authorization before using them on a
real case. This document and its local helper do not activate production intake,
change an Autopilot or remove any existing report. Follow the
[privacy contract](privacy.md#in-app-feedback) and
[receiver removal rules](public-feedback-v2.md#delivery-provenance-and-removal).

## One bounded case manifest

Keep a private, metadata-only manifest for the exact case/binding/revocation
tuple. Use opaque IDs and evidence labels; do not copy withdrawn text, attachment
names, signed URLs, credentials or model transcripts into it. Evidence labels
refer to private readback records, not an agent's assertion of success.

The manifest is a work inventory, not a receiver capability or trusted proof of
purge. Record incomplete inventory as a named gap. Record each known surviving
native copy by its actual object ID, including copies whose current body was
cleared but whose retained history is unresolved. Keep provider/third-party
retention separately described under the existing privacy notice.

The local helper accepts this closed schema; replace the synthetic values:

```json
{
  "schemaVersion": 1,
  "caseId": "00000000-0000-4000-8000-000000000001",
  "binding": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "revocationRevision": 4,
  "family": {
    "issues": ["native-root-uuid", "native-child-uuid"],
    "tasks": ["native-task-uuid"],
    "inventoryEvidence": ["family-readback-1", "all-issue-runs-1"]
  },
  "containmentEvidence": ["triggers-disabled-1", "tasks-stopped-1"],
  "localCopies": [
    {"id": "task-env-1", "path": "native-task-uuid"}
  ],
  "nativeResiduals": [
    {
      "id": "native-task-uuid",
      "surface": "execution-history",
      "evidence": ["task-readback-1"]
    }
  ],
  "inventoryGaps": ["unqualified-provider-session-context"]
}
```

`localCopies.path` is relative to one explicitly selected dedicated artifact
root. It must identify an entire task environment or a specific derived copy,
never the shared source checkout, daemon profile, global cache or owner home.
Use separate manifests when copies belong to different roots. Merge their
residual inventories into the case record; a successful invocation covers only
its own explicit paths.

## Execute the supported native operations

Related reports can share a native development task. Inventory report-bearing
copies separately from clean shared work; remove only the withdrawn report's
content. Stop tasks that are still processing that content, then continue clean
work supported by other active reports from fresh permitted context. Never
delete a shared task, chat or directory merely because one associated report
was removed. If the platform cannot isolate a retained copy, record that copy
as unresolved rather than claiming purge or deleting another reporter's data.

1. Fetch the receiver's current snapshot through its existing protected native
   connection. Confirm that it is revoked and bind the manifest to the exact
   case ID, pinned binding and fixed revocation revision. Preserve that tuple
   through every retry. Do not rotate configuration to discharge the obligation.

2. Disable only the affected native dispatch sources: the case's wakeups,
   recovery/replay paths and dedicated triggers. A paused trigger does not stop
   admitted tasks. Keep this control operation independent of the development
   resource held by a worker. Block resume, replay and publication for the case;
   later notifications must fetch the revoked snapshot again.

3. Inventory the case association before deleting its source records. Starting
   from every associated root issue, enumerate `issue children` recursively,
   including grandchildren, and reconcile cross-linked issues, review tasks,
   Autopilot deliveries/runs and any chat used for the case. Read each individual
   issue's complete run list, not the capped `--siblings` activity view. Repeat
   after dispatch is disabled and again after cancellation to detect late work.
   A missing/unauthorized/truncated read remains an inventory gap.

   These native commands can reduce readback to IDs/statuses without saving
   report bodies; repeat them for every discovered issue:

   ```sh
   multica issue children NATIVE_ISSUE_UUID --output json | jq '(.stages[].issues[], .unstaged[]) | {id, parent_issue_id}'
   multica issue runs NATIVE_ISSUE_UUID --output json | jq '.[] | {id, task_id, issue_id, status}'
   multica issue comment list NATIVE_ISSUE_UUID --full --output json | jq '.[] | {id, revision, parent_id}'
   ```

   Preserve all IDs from earlier case associations even when a current list no
   longer returns them. A complete current projection is not a service-storage
   audit: the handler applies `visibleTaskHistory` to its response. Account for
   unqualified storage coverage as an explicit gap until a supported service
   inventory establishes it.

4. Cancel every queued, dispatched, running or `waiting_local_directory` task
   in the inventoried case family by full task UUID, including review and
   controller tasks that fetched the content:

   ```sh
   multica issue cancel-task NATIVE_TASK_UUID --issue NATIVE_ISSUE_UUID --output json
   ```

   Independently read back terminal state and check that the corresponding
   worker has stopped. For local processes, compare the captured PID **and
   process start identity**, not PID alone; inspect only the test/task processes
   in scope. Check tracked descendants and side effects separately. A status
   edit to `cancelled`, HTTP success or an agent's last comment does not prove
   physical interruption. Do not move a task's files while it can still write
   them. Put exact stop evidence labels in `containmentEvidence`.

5. Delete or sanitize report-bearing current native content through native
   author/admin surfaces. Inventory comments and attachments before deleting
   their parent. Prefer deletion where no clean content needs preservation;
   comment edits can enqueue replacement work, so repeat cancellation/readback
   after edits. Preserve unrelated clean code fixes separately.

   | Copy | Supported operation on the pinned server | Independent readback |
   | --- | --- | --- |
   | Current comment | `multica issue comment delete COMMENT_UUID` (`DELETE /api/comments/{commentId}/keep-replies`); authorized revision-checked update for a necessary clean remainder | Read the complete unfurled thread; a parent with replies may remain with an empty body. |
   | Issue title, description and owned records | Native issue update, or `DELETE /api/issues/{issueId}` after inventory | Read by exact ID and reread the child inventory. Issue deletion detaches direct children; remove case-bearing descendants explicitly, leaves first. |
   | Attachment | `DELETE /api/attachments/{attachmentId}` and the owning source-context cleanup | Check exact attachment metadata **and** the previously recorded object/download locations under the applicable cache policy. A missing row or a queued deletion intent does not establish object absence. |
   | Case-owned Chat session | `DELETE /api/chat/sessions/{sessionId}` as its authorized owner | Read the exact session/messages and verify related local copies separately. Never delete a shared chat. |
   | Wakeup instruction | Native wakeup instruction edit or `DELETE /api/issues/{issueId}/wakeups/{wakeupId}` | Read the exact wakeup and verify that it cannot replay removed instructions. |

   Use the existing native authenticated UI/API client; do not introduce a new
   credential store or extract account tokens for this procedure. Record
   supported operations and independent readback per exact ID. If a read is
   denied or storage/cache absence is unknown, retain that object as a native
   residual. Do not relabel it as provider retention merely because the native
   service is hosted in a cloud.

6. Contain local copies: task `logs/`, `output/`, downloaded attachments,
   checkpoints, source-context exports and private operator/test artifacts.
   Native `local_directory` GC deliberately retains its task environment and
   logbook. A clean source checkout does not remove these copies. Select only
   stopped task-owned paths; do not run broad filesystem searches across owner
   profiles or delete shared state.

## Quarantine or delete explicit local copies

`tools/multica-removal.py` is a one-shot local cleanup tool. It reads file
metadata, not file content, and makes no network calls. It preflights every
selected path, rejects symlinks, hardlinks, overlapping paths and cross-filesystem
root moves, and defaults to a plan without changes. It does not verify the
native inventory or stop evidence; perform steps 1–4 first.

Create a private parent on the same filesystem, outside every development
resource and automatic context/search path. Supply absolute canonical paths:

```sh
umask 077
mkdir -p /PRIVATE/withdrawal-quarantine
python3 tools/multica-removal.py /PRIVATE/case-manifest.json \
  --source-root /PRIVATE/dedicated-task-artifacts \
  --quarantine-root /PRIVATE/withdrawal-quarantine/CASE_REVISION
```

After reviewing the explicit selection, repeat with `--apply`. This atomically
moves each selected root to an opaque `copy-NNNN` name and sets that root's mode
to `000`. It writes a private `report.json` after each move and independently
checks original-path absence, destination identity and permissions. All sources
must remain quiescent throughout; this is not a defense against a process that
continues writing or deliberately changes paths. If interrupted, inspect the
partial report and account for **every** `localCopies` row before any retry.
The tool does not roll moved content back into a resumable task automatically.

For exact stopped **case-owned** paths whose deletion is authorized, add both
`--apply --purge` to the same command. The helper still preflights every path
and relocates each selected root first, then deletes that private copy using
ordinary filesystem removal. It verifies absence at both the original and
relocated path before recording that copy as `purged`. Directory purge requires
the platform's symlink-safe `rmtree` support; otherwise it refuses before moving
anything. Keep the default quarantine operation for unresolved or mixed context
that cannot yet be safely deleted.

An interrupted purge can leave a partially deleted copy. The private report
preserves every original relative path and destination label, observed presence
at both locations, completed local deletions, unverified copies and untouched
pending copies. Remaining relocated copies are returned to mode `000` when
possible. Inspect this exact residual inventory before retrying; do not treat a
missing subset of files as completed cleanup. `purged` establishes only ordinary
deletion from these exact local paths. It does not claim secure erasure or
removal from backups, snapshots, open file handles, provider storage or other
uninventoried locations.

The report lists the declared native residuals, inventory gaps and each local
copy's observed state. Successfully purged copies remain in `localCopies` with
state `purged` and are absent from `localResiduals`; native residuals and
inventory gaps remain. A quarantined copy is always reported as
`retained-in-quarantine`; its bytes remain. Mode `000` and relocation
prevent ordinary path reuse, but do not isolate content from the same OS owner
or an administrator. Keep the quarantine excluded from agents, indexing,
backups and publication. Later inspection/sanitization or deletion of retained
copies needs an exact scoped inventory and the existing retention policy; do not
resume the old environment or feed its retained logs to a new agent.

## Exact completion record and remaining upstream gap

Finish this bounded operation with: the pinned case tuple; the complete known
family and named inventory gaps; exact task cancellation/process-stop evidence;
per-object supported cleanup/readback results; and the merged native/local
residual lists. Keep those records private and metadata-only. This is useful
containment even while receiver status remains `coordinator_cleanup_pending`.

Full native purge is still unqualified on the pinned implementation. In
particular, [Chat deletion](https://github.com/multica-ai/multica/blob/654b8ca95/server/internal/handler/chat.go#L678)
removes current chat messages/bindings/draft restores, while its
[SQL contract](https://github.com/multica-ai/multica/blob/654b8ca95/server/pkg/db/queries/chat.sql#L466)
expressly preserves completed/failed task history. Issue deletion and automatic
[local-directory GC](https://github.com/multica-ai/multica/blob/654b8ca95/server/internal/daemon/gc.go#L479)
also do not establish deletion of task prompts/results/messages, agent-provider
resume context, run-only execution history, service copies or local logs/output.

The missing upstream deliverable is a supported content-level purge/sanitization
operation and bounded inventory/readback for those exact retained records,
including object/cache semantics and in-flight creation races. Quarantine is
containment, not that proof. The helper always emits `removed: false` and
`receiverAcknowledgementSupported: false`; even an empty declared residual list
cannot authorize an ACK. Only a separately qualified trusted cleanup boundary
may acknowledge the exact original binding and revocation revision under the
existing receiver contract. No scheduler or AI-authored success claim supplies
that boundary.
