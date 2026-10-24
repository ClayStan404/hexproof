# Forge crash diagnostics

- Status: **Implemented in source; deployment remains a separate action**
- Owner request: 2026-10-08, actionable reports for unexplained EDH crashes
- Design review and implementation: 2026-10-08
- Authorities: [rules engine](rules-engine.md#availability-and-failure-behavior),
  [privacy](privacy.md#forge-crash-reports), [player hosting](player-hosted-forge.md#game-crash-reports)

## User outcome

An unexpected failure of a started Forge game returns its room to waiting and
retains a **Forge crash report**. The notice explains the observed failure type
and, when captured reliably, the executing API or publicly known source. It
provides **Show details**, **Copy report**, **Save report** and **Dismiss**. The
main-menu **Forge crash reports** entry opens retained history while offline.
Copy and save both contain the complete sanitized, formatted JSON; saving uses
an occurrence-time/report-ID filename. Sending it to support is a user action,
without automatic upload or a debug toggle.

The report is evidence about where execution failed, not proof that one card
alone caused a defect. Unknown causes and missing evidence remain explicit.
Initial startup/deck-registration rejection stays in the existing startup
feedback path; its owner-only deck details never enter the room-wide schema.

## Resolved capture gaps

The former failure path retained an exception in `NativeSession`, printed it
to discarded stderr, returned a generic fatal error and cleared the live game.
Independent stdout/stderr readers and process reaping could also finish in a
different order, and disconnected members missed a one-time broadcast.

Adapter 31 captures bounded evidence before cleanup, carries the first terminal
capsule inline, and keeps the client report outside live rules state. The hub
retains original delivery eligibility and permits one bounded enrichment. This
works independently of the two-seat visual replay and its finished-match gate.

Relevant implementation boundaries:

| Layer | Components |
| --- | --- |
| Native capture | `NativeDiagnostics`, `NativeDiagnosticStream`, `NativeDiagnosticSymbols`, `NativeExecution`, effect hooks in `AbilityUtils` |
| Native terminal RPC | `NativeSession`, `NativeHost`, `NativeSharedHost` |
| Process/helper | `rulesengine/forge` failure collection, `forgediag` sanitizer, `forgehost` retained evidence |
| Hub | `forge_crash_context`, report/collection/store/archive and existing termination/migration paths |
| Client | `ForgeCrashReportService`, report validation, notice/history panels and WebSocket dispatch |

## Evidence and attribution

| Failure | Evidence and meaning |
| --- | --- |
| `engine_exception` | A terminal native failure; verified exception/code details when available |
| `resource_exhausted` | An explicit resource exception such as `OutOfMemoryError` or `StackOverflowError` |
| `execution_timeout` | A failed native input-boundary deadline or dispatched operation deadline |
| `protocol_failure` | A validated framing, size, publication or reconstruction boundary failure |
| `process_exit` | An actual process exit without stronger available native evidence |
| `host_connection_lost` | Hosting transport loss; this alone does not prove an engine/card defect |

Exit code 137, SIGKILL or EOF alone never proves OOM. Empty successful
`awaitPrompt` polls, time waiting for a player, rejected answers, normal
completion, concession cancellation and acknowledged cleanup do not create
crash reports. V1 does not sample heap, CPU, operating-system resource events or
thread dumps. A synthetic resource exception test is not an actual OOM test.

Attribution is separate from failure category:

- `execution_site`: the terminal throwable matched evidence captured within an
  execution span; the card/API is context, not proof of an independently bad script.
- `resolution_context`: a resolution context is available without an exact
  throwing location.
- `recent_context`: preceding observations only; causation is unproven.
- `unknown`: no reliable execution/source attribution.

V1 does not infer a culprit from the last submitted action or top stack object.
The native spans, typed event tail and coarse hub action history stay distinct.

## Capture before failure cleanup

### Native execution

A game-owned recorder instruments actual API dispatch, including Gift and
subability dispatch, no-API resolution, decision scopes and game/EDT/delayed
callbacks. Scheduled work inherits immutable parent evidence, not mutable game
objects or another shared session's ThreadLocal. Each lease has a new diagnostic
producer UUID, even when a replacement reuses the same logical game ID. The
start handle advertises that producer for stderr fencing.

Escaping throwables first acquire bounded candidate context before a `finally`
restores the enclosing scope. Only a terminal session/RPC path promotes matching
evidence to the first-failure slot. Recovered exceptions cannot occupy it.
`submit`/Callable wrappers preserve throwable evidence before `FutureTask`
consumes it; already-completed caller-supplied `FutureTask` results are observed
without blocking or converting a handled exception into a terminal failure.
Candidate keys are weak and bounded so diagnostics do not retain private
throwables/game objects indefinitely.

The native terminal capsule includes fixed kind/boundary/attribution codes,
producer/session/sequence, relative elapsed time, verified throwable classes and
class/method/line frames, bounded spans and a typed event tail. Exception
messages, `toString`, stack-trace prose, file names/paths, scripts and arbitrary
ability descriptions are excluded. A finite list preserves common JDK throwable
classes; unverified classes become `unknown`, and unverified frames are omitted
with counts. Cause/frame limits reserve evidence across the retained cause chain.

`diagnostic-symbols.py` reads actual class files and pinned card resources to
generate the code-method/API/canonical-name index. Alternate card faces and
reviewed printing aliases contribute names; unknown custom/token names remain
anonymous. `upstream.json` pins `diagnosticSymbolsSha256`; the full builder,
overlay builder, JAR resource and Go embedded index must agree on the exact
index bytes. There is no reflection or symbol download during failure handling.
The hub needs no JVM or full card database to validate those symbols/names.

The primary capsule is in the terminal RPC response, stored by Go before any
kill/invalidation. Shared mode freezes it before removing the lease, preserves
it if cleanup also fails and sets `fatal`; resource/worker-integrity failure can
also set `workerFatal` and retire the process. Neighboring games receive only
their own context and process-loss evidence.

A dedicated asynchronous writer emits `HEXPROOF_DIAG_V1` JSON lines to the
original stderr pipe. Production upstream stdout/stderr goes to discard. The
writer has separate bounded observation and terminal queues; producers never
wait for a stalled pipe. Context-only records have `kind: context` and never
become terminal exceptions. Ordinary/malformed/oversized input is discarded and
the collector resumes at later line boundaries.

Limits: 128 retained native events, eight retained spans, four causes and 32
verified frames in a capsule, 16 KiB per encoded capsule/line, and a 32-event
exported native tail before hub merging. The event ring remains below the
64 KiB game budget. Deeper scopes retain the innermost site and nearest parents;
loss/omission counts make truncation visible. Metadata emission is coalesced;
there is no full snapshot or RPC per spell. Capture failure is best effort,
especially after a hard kill or severe allocation failure.

### Public observations between snapshots

At effect/decision entry on the owning execution thread, the recorder applies
`NativeSnapshot`'s original hand-hidden spectator identity rules. An eligible
source records immutable object incarnation, observation sequence, public zone
and printing/name reference. Hidden and face-down sources have no identifying
source observation. Later movement to a hidden zone cannot rewrite an earlier
public observation.

The capsule carries this evidence even if the next hub snapshot never succeeds.
The common Go sanitizer validates ownership, shape and bounds; the hub resolves
the name against the pinned canonical-name index and exports only that verified
name/token flag, not native printing coordinates. Index membership alone cannot
prove visibility: trusted native projection code and privacy tests supply that
boundary. Missing observations remain anonymous; the hub never guesses a source.

### Process and helper

An optional `FailureSource` interface remains readable after engine shutdown
without querying the dead engine. The collector records the first request
boundary separately from eventual exit code/signal and supervisor-initiated
kill. Stdout terminal evidence is primary; stderr is supplemental. Collection
and drain loops do not write archives or acquire room locks.

Shared workers keep lease-specific producer records and process-level exit
outcomes. Collateral process loss cannot copy another game's throwing context.
The helper captures failures, including publication failures, before `Cancel`
clears ownership. Cached failed responses, authenticated failure notifications
and same-engine reconnect hellos can carry retained evidence even with
`Alive: false`; the hub consumes it before invalidating that dead engine.
The whole pre-authentication hello is capped at 32 KiB with existing credential
bounds preserved. Data grants no execution/restart authority or extended grace.

Helper retention is in memory for its current engine, surviving cancellation
and socket reconnect. Replacement/new engine or helper exit releases it; there
is no separate persistent helper crash archive/export. Immutable engine/lease
producer identity remains distinct from transport epoch, RPC ID and report
revision. Reconnection may re-envelope evidence but cannot reassign its producer.

### Hub incident lifecycle

Before resetting a started room, capture its first failure boundary, original
recipient bindings and the last verified public turn/phase/sequence with age.
A bounded hub ring records coarse submitted-action families and automatic
smart-priority flags. It never copies choices, response tokens, journal text,
chat or arbitrary event prose. It does not query more game state after failure.

Revision 1 is delivered immediately with available facts. A collector independent
of room lifetime may add same-producer native/exit evidence for at most five
seconds, ending earlier when collection completes. It sends at most one final
revision 2; an already-final initial report remains revision 1. The final state
is `complete` or `partial`, with missing-evidence reasons. Original occurrence,
first boundary, frozen hub context and recipient eligibility are immutable.
Old or expired collectors cannot change a replacement game or resurrect an
evicted incident. At most 256 incidents collect concurrently.

Successful backup migration creates no terminal-game notice. Failed
reconstruction may preserve its separate failure/cause stage alongside the
original failure; it does not relabel reconstruction as the last played card.
Diagnostics never invent a result, retry a mutation or restart a game.

## Safe report and delivery

Clients declare `rulesCrashReportSchema: 1` in `session.hello`. The additive
`rulesCrashReport` field on the existing error payload carries a complete safe
record. Missing capability retains the existing generic error path. Revision
updates/resume delivery are unsolicited and cannot fail an unrelated pending
request; new clients route them to the report service before generic handling.
Initial operation failure retains its existing correlation where applicable.

Schema 1 contains incident ID/revision/collection state, UTC occurrence time,
versioned fingerprint, Hexproof/Forge/adapter/runtime identifiers, hosting mode,
format/participant count/game number, failure codes/causes/exit outcome,
public execution context and completeness counters. It has no sampled resource,
Java environment or machine inventory fields in this implementation.

An admitted helper supplies its full package runtime ID. Server-local native
evidence can establish the pinned Forge revision plus adapter via the verified
symbol index; this is **not an exact executable/package build identity**.
Unavailable identifiers remain unknown. The index's own identity is always a
content SHA; its internal runtime label is `revision-adapterN`, independent of
the overlay package's full content identity, avoiding a checksum cycle.

Fingerprint v1 hashes failure kind, available validated runtime/adapter identity,
verified cause classes and ordered class/method frames, excluding line numbers.
Without causes it uses the fixed boundary/request family and known exit outcome.
It excludes card names, IDs, times and other user state. It groups within the
available identity, not across builds automatically; local identities provide
weaker grouping than a fully admitted helper package hash. A final revision may
improve the fingerprint; deduplication always uses incident ID/revision.

Reports exclude registered decks, hands, library order, sideboards, RNG state,
private decisions, player/account names, credentials, host addresses, local
paths and other rooms. Seat indexes replace names. Reports stay outside room
snapshots, public journals and private visual replay.

The hub binds delivery to original room membership continuity, including held
disconnected members. Authorized resume rebinds that eligibility and receives
at most the newest eight eligible reports. Later occupants get none. Report
IDs are not credentials; there is no public index, download endpoint or report
acknowledgement protocol. Eligibility is not restored after hub restart.
Existing queue backpressure and runtime/application admission remain unchanged.

A report is at most 64 KiB, with 32 recent events and four public sources.
The failing span/source and nearest parents take precedence over older context.
Native and hub sequences remain separate timelines; their monotonic clocks are
never compared. Omission counts accompany truncation.

## Client and retention

`ForgeCrashReportService` owns independent validated history, upserting only a
strictly newer revision with unchanged occurrence time. Duplicate/older reports
cannot reopen a notice. Room reset, page navigation, reconnect and a new game do
not clear history. Dismissal leaves the report saved; restored history after
application restart never reopens notices. Details and complete formatted-JSON
copy/save work offline and render as plain text. Storage/export failure is
visible while an in-memory report remains usable.

Retention is **up to seven days, subject to storage limits**:

| Store | Deadline origin | Count/byte bounds |
| --- | --- | --- |
| Client profile | First receipt | 64 reports / 4 MiB |
| Hub memory | Incident creation | 256 reports / 16 MiB |
| Optional server archive | Incident occurrence | 256 reports / 16 MiB |

Revisions/redelivery never renew expiry. The archive has a single asynchronous
writer and at most 256 coalesced pending reports; a slow/unavailable disk cannot
block room cleanup. Private directories/files use `0700`/`0600` or platform
equivalent and atomic replacement. Startup/load/write and periodic maintenance
prune history; copy/save rechecks expiry. Physical deletion is best effort on
storage failure. Only the sanitized schema and minimal local lifecycle metadata
persist. No automatic upload is introduced.

## Delivery and acceptance

The implementation covers server-hosted dedicated/shared games, including
multiplayer EDH, and existing two-seat player hosting without expanding hosting
or migration eligibility. The runtime capability, adapter 31, source/binary
packaging, protocol fixtures and client translations form one vertical slice.
Installation/hosting reports and private visual replays retain their contracts.

Validation is deliberately separated by layer:

- `NativeCrashDiagnosticsRegressionTest` uses real Forge dispatch with an
  injected exception, four-participant Commander fixtures and public/hand/library/
  face-down sources. Separate recorder tests cover deep nesting, recovered
  exceptions, submitted/caller-supplied Futures, immutable scheduled provenance,
  blocked stderr, timeouts, cleanup, shared inline evidence and synthetic OOM.
- The actual base-plus-overlay JAR and an independent compilation of all 1,599
  pinned Forge core/game/AI/GUI source files passed that native regression.
  Their generated symbol index matched the Go/pin bytes. Actual Java output
  passed the Go sanitizer with verified frames, API and public source intact.
  This offline source compilation does not claim a completed fresh Maven build:
  the fresh Git fetch stalled and was stopped.
- Go regressions exercise stdout/stderr ordering, malformed drains, lease
  isolation, exit/deadline distinctions, helper cancellation/dead reconnect,
  relay bounds, membership/revision rules, archives and retention. Qt/QML tests
  exercise schema validation, durable history, expiry, notices and error routing.
- The `TestLiveForgeCrashDiagnostics*` tests passed with the packaged base plus final
  overlay, both normally and under the Go race detector. It externally kills
  owned dedicated/shared JVMs in three- and four-participant Commander games
  while waiting at the mulligan prompt, checks exit evidence and neighboring
  lease isolation, and verifies normal waiting/abort do not become failures.
  These process-loss tests do not inject a card-effect exception.
- Native GUI qualification passed in an isolated, maximized 2560 × 1371 Qt
  client using a safe four-participant wire fixture through production dispatch.
  It covered initial/final/duplicate reports, dismissal, offline history, actual
  clipboard/file export, partial evidence and restart without repeated notices.
  This presentation test is separate from Java fault injection; it is not a live
  EDH engine-crash reproduction, copied-trigger crash or actual OS OOM test.

Keep live EDH interaction stress, additional Gift/copied-trigger
fault scenarios and real hosting-network/OS-resource incidents as further
qualification, not as already completed tests. This feature does not claim to
fix the unknown reported card interaction. Resource sampling, deterministic
reproduction, full private bundles, automatic cross-build clustering and a
support-upload service remain outside v1. Full decks, seeds and private actions
must not silently become diagnostic inputs.
