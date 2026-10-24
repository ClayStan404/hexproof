# Public feedback V2

This implementation covers public intake, GitHub publication, authenticated
case threads and replies, AI questions and progress, typed public outcomes,
retained delivery history, closure and separate whole-case content removal. It is
a slice of the [native development workflow](autonomous-development.md). The
receiver supplies authorized public context to Multica; native tasks handle
development, review, integration and release. The receiver itself does not
launch models, develop patches, merge code or publish releases. Current
activation is recorded in the [handoff](development-handoff.md) and must be
confirmed from the trusted configuration and service state before operations.

## Client confirmation and compatibility

The composer prepares a local public draft. Review displays the frozen
description, category, bounded technical context, each attachment and repository.
The composer and preview keep a short public/AI-processing/privacy warning; a
clearly labeled in-app notice dialog provides the full disclosure without
requiring network access. The preview opens its frozen `noticeText`, not the
current service value. Reading or closing the notice never selects consent or
authorizes transmission; the unchecked explicit publication confirmation
remains required. The notice dialog is scrollable, selectable plain text,
keyboard accessible and part of the feedback input-blocking scope. The manifest also binds the disclosure and processing-policy
revisions. Images are normalized and diagnostic
schemas validated before this preview. Nothing is uploaded by previewing or
checking the confirmation box. The final public-submission action authorizes
only that exact snapshot. Editing the draft invalidates the preview; a stale
confirmation cannot send different content.

There is no public email field. Legacy V1 drafts, queued uploads and accepted
records retain their private origin. New clients stop legacy upload retries and
allow trusted legacy receipt queries. Copying old visible content creates a
new draft without the old email or capability; publication still requires the
new public preview. In public receiver mode, already accepted V1 IDs retain
lookup/deduplication and private processing, while new V1 uploads are rejected.

The [official source configuration](../apps/client-qt/config/feedback.official.json)
enables the reviewed public destination and matching disclosure; the generic
example remains disabled. The previous official V1 URL remains a receipt-only
destination. Source configuration does not start or reconfigure a remote service.

## Submission contract

The independent API prefix is `/feedback/v2`; it does not change the game's
protocol identifier. Requests use the existing anonymous 32-byte capability in
`Authorization: Feedback <base64url>`. Never put the capability in a URL,
public marker, attachment, export, QML model, issue or AI context.

| Method and path | Meaning |
| --- | --- |
| `PUT /submissions/{UUID}` | Durably accept the exact approved multipart submission. |
| `GET /submissions/{UUID}` | Read authenticated acceptance, publication and removal status. |
| `POST /submissions/{UUID}/close` | Close follow-up while retaining the approved public record; empty body, same receipt capability. |
| `DELETE /submissions/{UUID}` | Durably request removal; repeat safely with the same capability. |
| `GET /assets/{UUID}/{attachmentId}/{sha256}` | Read a public attachment while its publication authorization remains active. |

The first multipart part is `manifest`, a closed JSON object with
`schemaVersion: 2`, `submissionId`, `createdAt`, `category`, `description`,
`context`, `attachments` and `disclosure`. Context and attachment allowlists and
size bounds retain the [V1 limits](feedback-design.md), but `replyEmail` is not
accepted and public image payloads must be normalized PNG. The client accepts
local PNG/JPEG input up to 32 MiB, with the same 8192-pixel edge and 16,000,000-pixel
decode bounds. It removes metadata and, only when necessary, proportionally
downscales the image to the unchanged 2 MiB transmitted PNG limit before preview.
The original file is unchanged; the exact normalized bytes are frozen and shown
for approval. The receiver fully decodes the PNG once to validate its format and
limits, then preserves the approved bytes without an unused re-encoding.
Disclosure is a closed object containing `revision`, `sha256`,
`repository` and `providerPolicyRevision`. The receiver compares these with its
pinned configuration. The notice hash is SHA-256 of the exact UTF-8 notice text;
the repository is an exact `owner/name` string.

`X-Feedback-Digest` is the hex SHA-256 of `hexproof-feedback-v2\n` followed by
the exact manifest bytes. A submission UUID is an idempotency key, separate
from this content digest. Retries cannot change content under an accepted ID;
equal text under different IDs does not transfer receipt rights. Attachment
descriptors bind their exact bytes. The receiver validates public-safe formats
and refuses unsupported data instead of silently rewriting approved content.
The shared [fixtures](../testdata/feedback/v2/README.md) bind both implementations
to the same byte-level contract.

Successful `PUT` returns 201 on first acceptance and 200 for an authenticated
duplicate. The response contains `schemaVersion: 2`, `submissionId`, `receipt`,
`acceptedAt`, `contentExpiresAt`, `accessExpiresAt`, `state: "accepted"`,
`publicationState`, `removalState`, and optional `issueUrl`, `reason` and
`publishedAt`. The latter records verified publication separately from durable
acceptance. Wrong or
unknown capabilities do not disclose another submission. HTTP failure is not
evidence of successful publication or content rejection.

| Publication state | Client meaning |
| --- | --- |
| `pending` | Accepted; awaiting publication. No need to submit again. |
| `partial` | Some content is visible; the complete projection is not verified. |
| `stalled` | Publication could not finish within the bounded recovery policy. |
| `published` | The complete approved projection is verified; awaiting assessment. |
| `rejected` | Reserved for explicit post-acceptance content rejection; this slice rejects invalid input with HTTP 422 before acceptance. |

Removal independently reports `none`, `requested`, `pending`, `stalled` or
`removed`. An issue link is optional navigation, not the status transport: the
client obtains these states from the feedback receiver without reaching GitHub.
The client retains its local content and an authenticated thread cache. It does
not mirror arbitrary GitHub comments. Intentional AI updates explain the team's
assessment and progress; verified public outcomes identify the associated issue,
public source or published release without requiring the player to visit GitHub.

## Close follow-up while retaining history

Closing a feedback case means the submitter no longer requests follow-up. It
does not delete the issue, attachments, discussion, task history or clean code
already produced. The client presents **Close feedback** separately from
**Request content removal**, with an explicit explanation before each action.
Deleting the local draft/receipt remains a third, independent operation.

GitHub's development issue may be closed as completed when a reviewed fix
merges. That state is independent of this author-controlled case closure:
the receiver case remains open, accepts follow-up, and can publish a later
release update to the closed GitHub issue. A source outcome still means
`source-published-awaiting-release`, not a released fix. Native agents must use
the receiver state to determine whether follow-up is permitted, rather than
equating GitHub `closed` or task completion with a user request to stop.

An authenticated empty-body `POST /submissions/{UUID}/close` records closure
durably and returns the ordinary receipt with HTTP 200. Retrying that same
operation is idempotent; it does not reopen the case, reset retry budgets or
grant new processing authority. No reopen endpoint is introduced. A submitter
can deliberately create a new public submission if they later need follow-up.

Receipts and thread responses add the following independent fields. Older
records and responses without them mean `open`/`none`; loading them never
authorizes a close request automatically.

| Field | Meaning |
| --- | --- |
| `caseState: open \| closed` | Whether the receiver accepts further follow-up input. `closed` confirms acceptance of closure, not physical termination of every AI process. |
| `closedAt` | UTC time at which the receiver accepted closure; present for a closed case. |
| `closurePublicationState: none \| pending \| closed \| stalled` | Independent delivery of closure to the mapped public issue. `closed` means verified closure, or no issue ever created and no uncertain creation remains. |
| `closureReason` | Bounded delivery reason when synchronization is delayed; it is not a deletion result. |

The receiver rejects new replies and AI projections for a closed case, and
removes the active question from its current thread projection. Existing
history and attachments remain readable under their original retention rules.
Already accepted user publication/replies continue or reconcile their existing
intent; closure does not silently discard content whose publication the user
already authorized. An official projection not yet dispatched is suppressed;
an admitted or uncertain external write is reconciled rather than guessed away.

After those obligations settle, the same serial outbox closes the verified
GitHub issue, checks the result and records pending/stalled outcomes truthfully.
It never deletes the issue as part of closure. Closure delivery has its own
bounded retry budget; repeatedly pressing Close does not replenish it.

Closure increments the case input revision and uses the existing metadata-only
`hexproof.feedback.changed` notification. The restricted native snapshot returns
`State: "closed"` without feedback text, replies or attachments. Mika must stop
case-specific follow-up, cancel related pending/running work and avoid replay
from earlier context. The receiver blocks fresh context/projections immediately;
the notification is not proof that cancellation has completed. A closed case
needs no purge acknowledgment. Deletion requests, original processor bindings,
existing cleanup obligations and automatic content expiry remain unchanged.

## Delivery, provenance and removal

New GitHub issues use a short category prefix and the first nonempty line of
the approved description, with whitespace collapsed and the complete title
limited to 100 Unicode code points. Chinese UI locales use Chinese labels;
other locales use English labels. This is a deterministic excerpt, not an AI
diagnosis or confirmation of a bug. Mentions are neutralized in the title.
The full description remains literal text in the body. Common environment
fields and readable attachment links appear first; technical JSON, attachment
descriptors, submission IDs and disclosure evidence remain in a collapsed
details section. A neutral introduction points to replies for current progress
instead of freezing an initial assessment status in the issue body.

The publication marker and digest are unchanged. Ownership checks accept only
the complete exact current projection or the complete exact legacy UUID-title
projection, with all author/repository/mapping checks retained. Mixed formats,
arbitrary title/body edits and copied markers do not establish ownership.
Existing issues retain their original projection; changing their presentation
requires a coordinated receiver upgrade and explicit migration, not manual
GitHub edits while an older receiver still expects the frozen legacy content.

The receiver owns a separate public store and serial durable outbox. No V1 data
directory is converted to public content. Attachments are per-submission
objects; no shared-object reference counting or source-history hosting is used.
Public URLs carry IDs and hashes, never access capabilities. Public responses
must not be cached after removal; proxy/CDN behavior is an activation check.

GitHub credentials stay in an owner-readable server file. The publisher pins
the public repository identity, numeric publisher identity and public asset
base at acceptance. Changing configuration cannot redirect an old queue or
serve its objects from a new destination. A mismatched destination remains
stalled; the original configuration is needed to process that mapping. Publication
requires the expected author, exact frozen projection and verified attachments;
matching a user-copyable marker alone does not prove ownership. A crash or
ambiguous create response enters reconciliation. An empty search/list result
does not authorize a second create request. Retry and reconciliation limits
remain finite, with visible stalled outcomes when uncertainty cannot be settled.
This slice has no general publication requeue interface after that budget is
exhausted; a later controlled repair capability must preserve the original
mapping, target and finite lifetime budget. Users should not resubmit stalled
content as a workaround.

Removal revokes attachment serving and queued publication before confirming
completion. Possible in-flight creation must be settled first. GitHub issue
deletion uses the issue's verified identity; closing or editing its body is not
deletion. It first locks the issue and then rechecks content and comments.
GitHub locks exclude ordinary contributors, but privileged repository actors
must honor the same removal lock; this is an activation prerequisite for other
automated writers. The receiver first reconciles and removes comments whose
case binding, exact frozen body, numeric author and mapped identity it owns.
It verifies their absence before deleting the issue. An issue still containing
unowned comments remains visibly stalled for a future qualified moderation
path. Edited or ambiguously owned comments and permission failures also remain
stalled, not falsely removed.
No task or retry may resurrect a confirmed removed submission. An operation
has at most 12 delivery attempts, with bounded backoff. Authenticated removal
recovery allows two further lifetime repair cycles after a six-hour cooldown;
repeatedly pressing the button cannot grant an unlimited retry budget.

The first implementation fixes the public-content window at 365 days from acceptance. Attachment
expiry starts automatic removal; `contentExpiresAt` is not a promise that
GitHub content or external copies disappear at that instant. Receipt ownership
is available for at least the same window, and unresolved removal continues to
retain status and authorization. Removed identities retain a further tombstone
window for deduplication. Capacity limits reject new intake rather than evicting
unresolved removal records. Losing every local copy of the capability has no
ownership recovery through a public issue ID.

Removal covers qualified project-controlled locations. It cannot recall
notifications, search indexes, third-party copies, GitHub's internal retention
or provider records. When a case has been exported to an external processor,
receiver completion additionally requires its same pinned instance to acknowledge
cancellation and purge of its context and derived assessment/question data.
Retiring the old bridge does not remove previously recorded obligations. Each contribution retains its original processing
policy; a later provider-list update does not broaden historical permission.

## Build and receiver configuration

Client configuration is closed schema version 2 with `enabled`, `apiBase`,
`supportLabel`, `privacyUrl`, `receiptOnlyApiBases`, `publicRepository`,
`noticeRevision`, `noticeText` and `providerPolicyRevision`. Enabling requires
all public destination/disclosure fields. Main API URLs use HTTPS and
`/feedback/v2`; receipt-only destinations may use V1 or V2. The loopback exception
exists only in explicit local tests. `tools/write-feedback-config.py` validates
release inputs without printing them or embedding server credentials.

Official source defaults select the reviewed public endpoint and formal disclosure
from [the client configuration](../apps/client-qt/config/feedback.official.json). The
[cutover procedure](feedback-operations.md#official-public-configuration-and-notice-upgrades)
keeps the existing Multica/OpenAI policy and native binding while advancing
only the notice revision. This preserves previously published contributions'
original processing permission; it does not reauthorize unpublished payloads
under a changed notice or enable additional providers.

When online submission is disabled or no qualified V2 configuration is supplied,
the composer explains that online submission is not enabled in this build and
keeps local draft saving and export available. Invalid configuration has its own
configuration error that remains visible through creating, editing, selecting,
exporting and reopening local drafts, independently of transient operation errors.
Request/network failures retain their separate connection
error and local-save guidance; neither configuration state implies a network outage.

Receiver configuration uses schema version 2, a loopback listener, HTTPS
`publicUrl` ending in `/feedback/v2`, the legacy `dataDir`, operator/monitoring
configuration and a `public` object. That object supplies its own `dataDir`,
`repository`, numeric `repositoryId` and `publisherActorId`, private `tokenFile`,
`noticeRevision`, exact `noticeText` and `providerPolicyRevision`. SMTP is not
needed for public intake after legacy delivery has drained. Pending, uncertain
or attention-required private deliveries still require the legacy SMTP
configuration; their content is never sent to GitHub. Existing private records
retain receipt routes and retention cleanup even after SMTP drains. A public
receiver with no V1 records or tombstones keeps only the legacy directory lease
to exclude concurrent V1 writers; it does not start legacy routes, admin socket,
mail or retention workers. This does not delete historical data or change schema.

The notice must identify the service responsible for public attachment hosting, public repository,
retention/removal terms and eligible AI providers. A user-facing notice names
the hosting service without requiring a literal IP address, model identifier,
reasoning setting or internal task-routing details. Connection URLs remain
trusted build/receiver configuration, not a disclosure-text requirement. The local fixtures use
`none-v1`, authorizing no external AI processing. They are test inputs, not a
production privacy notice or approval to enable an AI provider.

An optional [`multica` configuration](multica-feedback.md) connects verified
public inputs to an existing native Autopilot webhook. Notifications contain
only case/revision metadata; a separate private `native.sock` serves current,
policy-checked public snapshots and explicit assessment/question projections.
It never exposes legacy records or receipt capabilities. The same GitHub outbox
verifies these projections before they appear to clients. New user input is
tracked by `InputRevision`, not general thread/status changes. Notification
acceptance or native `done` never becomes a release assertion. This first
connection exposes no purge acknowledgment: native cleanup remains a separate
qualification requirement. Omission of `multica` keeps the connection disabled.

Production qualification must verify TLS/proxy routing, public object access,
cache revocation, GitHub identity/permissions and removal, capacity/monitoring,
legacy behavior and the supported native clients. The existing
[release deployment component](feedback-operations.md#release-deployment)
supports V1 and V2 inputs, separate public state and private GitHub/Multica
credentials. Its staged binary validation and rollback do not establish live
TLS routing or native connectivity. Use `tools/write-feedback-config.py
--receiver-config` to compare the public client/receiver settings before release;
this comparison does not activate either side. Actual installation and cutover
remain a separately authorized deployment round. Do not turn a local test
harness into a deployment entry point.

GitHub integration follows the official [issue REST API](https://docs.github.com/en/rest/issues/issues),
[issue GraphQL mutations](https://docs.github.com/en/graphql/reference/issues#deleteissue)
and [API retry guidance](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api).
Verification uses fake GitHub endpoints and isolated local state; it creates no
real public issue and sends no email.


## Replies and ordered thread snapshots

A reply belongs to one original submission, called its case. It uses that case's
capability at request time; client reply records contain no copy of it. There is
no separate reply-owner identity or independent reply-removal endpoint. The client uses a separate local confirmation nonce
for cancellation journals, so stopping one authorization cannot cancel a later
explicit confirmation of the same reply after restart. The parent capability is
never copied into that nonce or into a reply record.

| Method and path, under `/feedback/v2` | Meaning |
| --- | --- |
| `PUT /submissions/{caseId}/replies/{replyId}` | Durably accept an immutable public reply. |
| `GET /submissions/{caseId}/replies/{replyId}` | Read its receipt using the parent capability. |
| `GET /submissions/{caseId}/thread?limit=5&cursor=REVISION:SEQUENCE` | Read one authenticated page of a fixed thread snapshot. |
| `GET /assets/{caseId}/replies/{replyId}/{attachmentId}/{sha256}` | Read an authorized public reply attachment. |

The reply multipart manifest reuses schema 2 and adds `parentSubmissionId`.
`submissionId` is the reply UUID and both IDs must agree with the path.
`category` inherits the original case category. Optional `questionId` and
`questionRevision` must identify a verified, published question in that case;
both are omitted for additional evidence unrelated to a particular question.
The original submission endpoint rejects these reply/question fields, including
empty placeholders. The reply digest is SHA-256 of
`hexproof-feedback-reply-v2\n` followed by the exact manifest bytes. Root and
reply digest domains are deliberately different. The shared reply fixtures
include a final newline and bind the Go and Qt implementations to those bytes.

Each reply receives its own public preview and explicit confirmation, including
its parent/question association, exact text, context, attachments and disclosure.
The receiver validates and stores the approved bytes without rewriting them.
Acceptance may precede publication of the original case; the reply waits for its
verified parent issue. Its receipt adds `parentSubmissionId`; `issueUrl` remains
the parent issue URL. `acceptedAt` is the durable receiver timestamp and
`publishedAt` is assigned only after public comment and attachment verification.
A timely reply is not treated as user silence merely because GitHub publication
is delayed. Historical question IDs remain valid for late evidence, without
silently binding the reply to a newer question.

Thread JSON contains `schemaVersion`, `submissionId`, `revision`, `items`,
`nextCursor`, `workState`, `summary`, `workflowRevision`, `projectionState`,
`removalState`, `accessExpiresAt`, `contentExpiresAt`, optional `reason`/`question`/`outcome`,
`deliveryHistory`,
and receiver-only `assessmentDeliveryState`/`assessmentDeliveryReason` strings.
Delivery health is independent of official assessment state. It can report
`unavailable` while preserving the last published assessment, and changes back
to `available` only after verified synchronization with its pinned integration.
These compatibility fields remain present after retiring the old bridge; they
do not establish that Multica is connected.
Repeated identical failures do not rewrite state or reset execution budgets.

Published `workState` values are `new`, `assessing`, `needs-information`, `ready`,
`implementing`, `verifying`, `verified-awaiting-review`, `reviewing`,
`verifying-integration`, `merge-ready`, `merging`, `merged-awaiting-release`,
`source-published-awaiting-release`, `released`, `duplicate`, `declined`,
`deferred` and `blocked`. Development progress distinguishes implementation,
independent verification, independent review, integration checks and a pending
or confirmed merge. They are published through the same verified
projection path as assessments; an unverified pending projection never replaces
the last published state. The client shows each phase distinctly. In particular,
`verified-awaiting-review` does not mean reviewed, merged, released, or delivered
to users. Removal remains a separate field rather than a development outcome.
Review/merge summaries use fixed public explanations, excluding reviewer text,
raw task logs, operator-only references and check evidence. A failed or unavailable
gate remains deferred or blocked. An uncertain merge result says that the
existing attempt is being checked; it does not claim that the write succeeded
or that nothing happened. Source publication and an observed released version
are later, separately verified milestones. See the
[native development and delivery workflow](autonomous-development.md).
The restricted native connection accepts intentional progress updates. These
are reports from the AI team, not independent proof of a public merge. Public
source and release outcomes use the verification described below. The client
groups development/check/review phases into concise progress labels while
preserving the underlying wire states for compatibility.

Each ordered item has a UUID `submissionId`, immutable positive `sequence`,
`kind` (`submission`, `reply`, `assessment` or `question`), `description`,
`context`, attachment descriptors with receiver-hosted `url`, receipt/publication
timestamps and publication state. User items also retain their disclosure and
category; replies and official items carry `parentSubmissionId`. Question items
carry `questionId`/`questionRevision`; an official item can also carry `outcome`.
Pending user replies are visible only to
the authenticated submitter here and never enter AI context. Official text and
questions enter the thread only after verified GitHub publication. Arbitrary
GitHub comments, labels and worker prose do not create official state.

The top-level question contains `id`, `revision`, `code`, `description`,
`publishedAt` and `answerDeadline`. Its code is one of the contract's six
fixed clarification templates or `custom`. A `custom` question displays its
bounded plain-text `description` verbatim, in the language chosen by the AI
using the user's approved context. Existing template codes retain localized
fallback behavior. The published deadline begins at first verified
publication of that ID/revision and cannot be extended by another status
comment. An existing question ID/revision cannot change its code, text or
promised timeout. The UI localizes the code and retains the public original as
fallback. After newly published user evidence changes the assessment input,
previous assessments remain historical items but cannot be shown as the
current result for that new input. A previously published delivery fact remains
in `deliveryHistory`, scoped to its original input revision; it does not resolve
the newly supplied information automatically.

### Public outcomes and delivery history

An optional `outcome` has a fixed `repository` matching the case's pinned public
destination and one of these closed shapes:

| Kind | Additional fields | Meaning |
| --- | --- | --- |
| `duplicate` | `issueNumber` | Related public issue in the same repository; never the case's own issue or a pull request. |
| `source` | `commit` | Exact public source commit associated by the AI team with this report. |
| `release` | `commit`, `tag`, `version` | Published stable release whose resolved tag contains that public commit. `tag` is `v` followed by `version`. |

Commits use exact lowercase 40-character GitHub SHAs. References are structured,
not arbitrary agent-supplied URLs. The GitHub publisher checks repository
identity and public visibility, the exact issue/commit, and release publication,
tag resolution and commit ancestry before making a new outcome visible.
Drafts, prereleases, absent or unrelated commits and mismatched targets cannot
establish a delivered release. An uncertain write retains its existing identity
and reconciliation; failed verification never authorizes another comment.

The AI's assessment and independent development checks establish why a change
addresses the case. Reference verification establishes that the named public
release exists and its tag includes that source commit; it is not a replacement
code review or binary verification. The existing release procedure verifies
packages, checksums, attestations and update readiness. Native `done` alone
establishes neither fact. Verify the actual public PR merge and use the release
procedure to choose exact public references.

The top-level `outcome` describes only the current published projection.
`deliveryHistory` retains source/release entries with `projectionId`,
`inputRevision`, `workflowRevision`, `publishedAt` and `outcome`, including after
new input or ordinary closure. Pending/unverified outcomes and historical
unstructured `released` prose never become verified delivery history. Removal
and expiry continue to suppress content and derived history under the existing
contract. This adds no per-agent task database or independent release authority.

The client lists original cases in **My feedback**, with progress and last sync.
Local reply drafts and interrupted replies remain reachable inside their case;
orphaned local records remain accessible. These views reuse the existing local
records and thread cache, rather than changing accepted payloads or their hashes.

Pagination starts without a cursor. The returned cursor is `revision:lastSequence`
and is only for the remaining pages of that snapshot. Any intervening thread
change produces HTTP 409 `thread_changed`; the client keeps its prior complete
cache and starts a new refresh. It never combines revisions or treats the cursor
as an indefinite incremental feed. Cached thread payloads are independently
reclaimable under the local payload retention/capacity policy while receipt
authority remains available for refresh and removal. Pages have at most five
items and 128 KiB;
the client accepts at most 49 items and 1 MiB for one complete cached thread.
Removed/removing cases return status without content and stop new reply work.

## Durable reply publication and case limits

The original case record remains the single-writer transaction boundary.
Immutable reply/projection payloads are protected sidecar files, written and
synced before their parent reference is committed. A reply is acknowledged only
after that durable reference. Recovery discards unreferenced sidecars and fails
closed if a referenced payload, digest or frozen target is missing or invalid.
No sidecar contains a receipt capability. Quotas include both parent state and
sidecar bytes; unresolved removal never loses its slot to make room.

A case accepts at most 16 user replies and 32 official projections, with 32 MiB
of total stored case/payload bytes. A reply retains the existing four-attachment,
5 MiB upload, 16 KiB manifest and 8192-byte description bounds. Official summary
and question text are each limited to 4096 bytes. Capacity exhaustion is an
explicit admission failure rather than silent payload eviction.

Comments publish in case sequence after the parent issue is verified. Terminal
stalled contributions remain visible as gaps; they do not grant an unbounded
retry budget. Each contribution has at most 12 delivery/reconciliation attempts
and a seven-day publication window. An interrupted or uncertain comment create
reconciles the exact case/reply/digest projection, expected publisher and issue
identity. An empty bounded comment listing never authorizes another create.
Mapped comments require authenticated and anonymous verification plus exact
attachment delivery before becoming published. A projection built against an
older input revision is blocked before creation; already written or uncertain
objects still follow ownership reconciliation. Current status cannot be derived
from an obsolete assessment merely because its GitHub comment exists.

Root deletion and expiry immediately revoke every case attachment, stop reply
admission and prevent future projection creation. In-flight creation is settled,
owned comments are removed and verified, then the locked issue can be deleted
only after its remaining comment count is zero. Original finite removal repair
budgets apply to the entire case, including its child operations. Replies inherit
the parent's content/access expiry; a late reply does not extend case retention.
The original 365-day window and at least 120-day post-removal/access tombstone
window remain unchanged. A stored pre-thread V2 publication lacking a verified
publication timestamp is reverified once through a bounded migration before it
can be exported as assessment input.

## Native integration boundary and derived-data removal

The old receiver `assessment` configuration and its `/autonomy/v1` bridge are
retired. Any configuration containing `assessment`, including `null`, is rejected
with an explicit error. Omit that field. The optional Multica connection uses
its own configuration; it is never enabled implicitly.

The platform-neutral receiver contracts remain. `ExportCase` records an immutable
processor binding and ever-exported fact before returning content. Only verified
public user contributions are exported; pending replies are represented by ID,
question association, receipt time and delivery state. `SourceRevision` tracks
the complete receiver projection, while `InputRevision` changes only for newly
verified user context. Official comments do not become user evidence. Native
integration must honor each contribution's original provider policy, including
`none-v1`, before supplying context to any model.

The restricted native interface may enqueue an intentional official projection. It
binds an immutable ID and monotonic workflow revision to the exact input revision.
No public HTTP endpoint accepts official status, arbitrary question text,
provider identity, execution allowances or arbitrary GitHub comment writes.
Task dispatch belongs to the native platform, not the receiver.

Removal exports a permanently empty revoked snapshot with a fixed revocation
revision. Before reporting `removed`, the receiver must have verified GitHub/asset
removal and received the matching cancellation/purge acknowledgement for any
previous export. Retiring a bridge, changing configuration or restarting does
not clear that obligation. The historical wire reason
`coordinator_cleanup_pending` is retained while processor cleanup is outstanding.
This acknowledgement covers controlled storage, not provider retention or
third-party copies. No successful purge is inferred from removing source code.

The opt-in test-only `TestPublicNativeHarness` accepts
`HEXPROOF_FEEDBACK_NATIVE_THREAD=1` to exercise the real receiver/outbox and Qt
thread flow against fake GitHub comments and simulated official projections.
Its artifact explicitly marks the simulation. Retained receiver tests cover
publication, replies, input-revision invalidation and removal obligations; they
do not qualify production Multica dispatch or create a real GitHub issue/comment.
