# Public feedback tools for native AI tasks

`tools/feedback-ai.py` performs a fresh read or one intentional publication through
the receiver's restricted Unix socket. It can also prepare a progress intent
locally without publishing it. Mika and the native team decide what to investigate, implement,
review and publish. This tool owns no scheduling, model selection, task state,
credentials, network forwarding or automatic retries. It does not activate a
receiver or a Multica task.

Use the [native connection](multica-feedback.md) and
[public feedback contract](public-feedback-v2.md). Only intentional public prose
belongs in an operation: write for the player in the language of their report.
Do not send raw task output, operator-only references, raw review
transcripts, credentials or other players' private data. Typed references belong
in `outcome`; the receiver restricts their repository and verifies public delivery.

## Connection and private local files

An already provisioned receiver socket or separately authorized forwarding
connection must be available. The CLI never opens SSH or reads receiver storage.
Store this connection file with mode `0600`, owned by the task account:

```json
{
  "schemaVersion": 1,
  "socket": "/run/user/1000/hexproof-feedback-native.sock",
  "binding": "<64-lowercase-hex-current-native-binding>",
  "publicRepository": "<configured-owner>/<configured-public-repository>"
}
```

The repository is a fixed connection setting, not a destination selected by a
feedback message. The receiver checks the current binding and processing policy
on every operation. This file contains no GitHub token or user receipt secret.
It cannot authorize arbitrary receiver administration or private V1 access.
The endpoint must be a private Unix socket; a final symlink is rejected.

Input JSON files and saved operation receipts must also be owned private
regular files (`0600`, no final symlink). JSON input is limited to 16 KiB;
responses are limited to 2 MiB. `--input -` reads JSON from stdin. The default
stdout is exactly the requested snapshot or publication receipt; no debug log,
connection binding or internal operation history is printed.
Explicit compact views include the configured association binding and repository;
these are not credentials and must not be copied into a public reply.
Use `--output /absolute/private/path/result.json` to atomically save the result
with mode `0600`; its parent directory must already exist. Output cannot replace
the connection or input file. Keep these files outside
published source and logs.

## Read before deciding

Save `{"caseId":"<case-uuid-v4>"}` as a private input file, then run:

```sh
python3 tools/feedback-ai.py read \
  --connection /private/feedback-connection.json \
  --input /private/read-case.json \
  --output /private/current-case.json
```

The JSON result is `{"snapshot": ...}`. Snapshot field names retain their Go
capitalization: `CaseID`, `State`, `InputRevision`, `LatestProjection`,
`Contributions`, `PublishedProjections` and `DeliveryHistory`. Verified user
contributions include structured `Category`, `Description` and `Context` as well
as compatibility `Text`. Pending replies expose delivery metadata, not their
unpublished content. Published projection history contains intentional public
conversation; it is not a raw AI transcript.

For `State: "closed"`, stop case-specific follow-up and retain history. For
`State: "removed"`, stop work and follow the existing
[removal procedure](multica-removal.md). Neither state authorizes a fresh reply.
Shared development may continue for other active cases. A stale notification
must not override current state. Historical delivery facts do not prove that a
new symptom or later user message is already fixed.

### Compact fresh reads

Use `--view summary` when only current state, revisions, the latest projection and
contribution counts are needed. It still performs a fresh receiver read. Its
`--output` is required and retains the **complete** snapshot privately; stdout
contains only the compact `view` object:

```sh
python3 tools/feedback-ai.py read \
  --connection /private/feedback-connection.json \
  --input /private/read-case.json --view summary \
  --output /private/case-before.json
```

To see new or changed published contributions and projections, compare with that
saved snapshot. An optional projection UUID requests its currently observable
receipt, without asking the AI to scan the whole conversation:

```sh
python3 tools/feedback-ai.py read \
  --connection /private/feedback-connection.json \
  --input /private/read-case.json --view changes \
  --since /private/case-before.json \
  --receipt <stable-output-uuid-v4> \
  --output /private/case-after.json
```

Compact-read files use a local `feedback-snapshot` envelope with schema version,
binding, public repository and the full `snapshot`. `--since` accepts only this
format for the same connection and case, not an arbitrary old task summary.
Each read contacts the receiver again; saved data never authorizes stale processing
or substitutes for its consent, binding and removal checks. Active revision
regression is rejected. Closed or removed cases return current state without
replaying old content, even when their tombstone revision differs from an old
active source revision.

The compact output omits repeated compatibility `Text` when a new contribution
already contains structured `Description` and `Context`. The complete original
remains in the saved snapshot. `LatestPublishedProjection` is limited to the
current input revision; a requested historical receipt keeps its original input
revision. `not-in-current-snapshot` means unobserved, **not** absent or failed:
the current wire format does not expose every older unpublished projection.
Pending remains pending, and neither summary nor changes is a complete assessment.
`UnpublishedReplies` contains only current delivery observations, never unpublished
user content. No new published contribution does not mean the user has not replied.
The view is not a complete state diff and omits full delivery history; consult the
saved complete snapshot when that evidence is needed.

Compact output files are created atomically with mode `0600` and never replaced
with different content. Use a new path for each changed snapshot. The previous
reference, connection file and input file cannot be the output path. Ordinary
`read` without `--view` retains its original output format and behavior.

### Prepare one progress intent without sending

For the existing progress states only, the AI supplies its decision and the input
revision on which that decision was based:

```json
{
  "caseId": "<case-uuid-v4>",
  "expectedInputRevision": 3,
  "workState": "implementing",
  "summary": "AI 团队正在修复这个问题。"
}
```

Save that decision privately, then prepare its immutable publication fields:

```sh
python3 tools/feedback-ai.py prepare \
  --connection /private/feedback-connection.json \
  --input /private/progress-decision.json \
  --output /private/progress-intent.json
```

`prepare` makes only a fresh snapshot request (`POST /public-native` with action
`snapshot`, not `project`). This submits no public message; the receiver may record
the existing coordinator binding on its first export. It requires an active case whose
current input revision matches the supplied decision, generates one UUIDv4 and
the next workflow revision, and durably creates a `0600` `prepared-progress`
envelope bound to the connection and repository. It does not infer the work state,
write a GitHub comment or send a projection. An unresolved existing publication
blocks creation of another intent. Repeating the same decision and output path
returns the original identity after checking fresh state; concurrent creation
uses one complete file without overwriting it. Different text, a changed binding,
new user input or a workflow conflict fails and preserves the old file.

This is file-level idempotency, not a global case lock or workflow reservation.
Independent preparations at different paths can still conflict; the receiver
remains authoritative. A matching existing projection may be reported in
`observedReceipt`, but `sent: false` means this preparation invocation sent nothing.

After reviewing the prepared intent, intentionally publish it with the existing
operation. The tool checks and unwraps the local envelope; receiver JSON is unchanged:

```sh
python3 tools/feedback-ai.py progress \
  --connection /private/feedback-connection.json \
  --input /private/progress-intent.json \
  --output /private/progress-receipt.json
```

Do not edit the prepared file or choose another path merely to suppress a conflict.
`prepare` does not prepare questions, assessments, duplicate/source/release outcomes
or automatically retry publication. Those operations retain their existing
explicit intent and evidence requirements below.

## Ask, reply or report progress

Every public operation must explicitly supply its stable output UUIDv4,
`workflowRevision`, current `expectedInputRevision` and public summary. Publishing
commands never generate replacement IDs, increment revisions or infer approval;
the optional local progress preparation described above only constructs an intent.
Preserve the
intent in native task history and the private input file before the first send.

An `ask` input uses the existing projection envelope:

```json
{
  "caseId": "<case-uuid-v4>",
  "projection": {
    "id": "<stable-output-uuid-v4>",
    "workflowRevision": 5,
    "expectedInputRevision": 3,
    "workState": "needs-information",
    "summary": "需要确认触发问题的牌和游戏模式。",
    "question": {
      "id": "<stable-question-uuid-v4>",
      "revision": 1,
      "code": "custom",
      "description": "是哪张牌结算时出现这个问题？当时使用的是手动模式还是 Forge 规则模式？",
      "timeoutSeconds": 86400
    }
  }
}
```

```sh
python3 tools/feedback-ai.py ask \
  --connection /private/feedback-connection.json \
  --input /private/question-intent.json \
  --output /private/question-receipt.json
```

`custom` displays the intentional question text. Existing question codes remain
supported. Ask only for public-safe details the snapshot does not already supply.
Each summary/question is at most 4096 UTF-8 bytes; question timeout is 60 seconds
through 30 days and starts from verified publication, not native submission.

Use the same envelope without `question` for these operations:

| Command | Accepted `workState` |
| --- | --- |
| `reply` | `assessing`, `ready`, `declined`, `deferred`, `blocked`, or a progress state below |
| `progress` | `implementing`, `verifying`, `verified-awaiting-review`, `reviewing`, `verifying-integration`, `merge-ready`, `merging`, `merged-awaiting-release` |
| `outcome` | `duplicate`, `source-published-awaiting-release`, `released`, each with its matching typed outcome |

A reply retains or intentionally changes the chosen public state; fetch current
state before selecting it. Attribute progress to the AI team. Publish useful
questions, replies and milestones, not every internal step: existing bounds of
16 user replies and 32 official projections per case remain enforced.

## Report a public outcome

Add `outcome` to the same projection and use command `outcome`. The configured
public repository must match exactly. Do not put links in the summary.

| `workState` | `outcome` |
| --- | --- |
| `duplicate` | `{"kind":"duplicate","repository":"ClayStan404/hexproof","issueNumber":123}` |
| `source-published-awaiting-release` | `{"kind":"source","repository":"ClayStan404/hexproof","commit":"<full-public-merge-sha>"}` |
| `released` | `{"kind":"release","repository":"ClayStan404/hexproof","commit":"<full-public-merge-sha>","tag":"vX.Y.Z","version":"X.Y.Z"}` |

Duplicate outcomes identify the public issue. Source/release outcomes explicitly
include the full public merge SHA in `outcome.commit`. Before reporting it,
verify the actual PR merge in `ClayStan404/hexproof`, its exact reviewed candidate
and required checks. Neither task completion nor an accepted merge request is
proof that the intended source landed.

```sh
python3 tools/feedback-ai.py outcome \
  --connection /private/feedback-connection.json \
  --input /private/release-outcome-intent.json \
  --output /private/release-outcome-receipt.json
```

The CLI validates the fixed repository, commit format and typed outcome. The
receiver independently verifies public GitHub issue/commit/release evidence,
including that a reported release contains the public change, before publishing
it. There is no private-source receipt or SHA translation. A source merge, tag
string, local intent file or successful native run alone cannot make the client
show a delivered release.

## Retry and reconcile

The publication result is `{"projection":{"id":"...","publicationState":"pending"}}`
or another receiver publication state, optionally with `publishedAt`. Pending
means accepted durable publication work; it does not mean a visible reply or a
verified release. Read the current snapshot and match `LatestProjection.ID` /
`PublicationState`, plus published history, to observe completion.

After a timeout or lost response, retry the **same saved intent**, including
the same ID, revisions, text and explicit public outcome. The helper performs no
automatic retry and prints no raw server error body. Do not manufacture a new
ID to make a conflict disappear. A deliberately new publication needs a new
stable ID, an advancing workflow revision and the current input revision.
If new user input makes an earlier attempt stale, fetch current state and
reconcile whether the prior output was accepted before preparing a new one.
An output-file failure after sending can also leave publication unconfirmed.

Errors exit nonzero with a bounded explanation on stderr. No command marks
processor cleanup complete, merges code, publishes source, releases software or
changes native task scheduling.
