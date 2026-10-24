# Hidden Information Policy

- Status: **Active**
- Last updated: 2026-10-22
- Parent: `product-brief.md`

## Owner decision

**Trust the room server.**

The server **may store and manipulate** hidden card identities (hand, library order, sideboard, face-down cards, etc.).  
**Opponent clients** must **not** receive those identities until a card is
revealed or becomes public. Spectators follow the same rule unless the host
explicitly creates the room with the immutable `spectatorsSeeHands` policy;
that policy grants every spectator live access to current hand identities only.

In the waiting room, the public snapshot exposes each seat's `deckSelected`,
`deckLocked` and `ready` status without deck names, card names, printings or
quantities. An authenticated human player additionally receives optional
`ownDeckName` metadata for that player's selected registered deck. It is
rebuilt from current membership on entry and resume, rather than a previous
client's local cache. Opponents never receive another player's deck name;
spectators and unrelated or replaced connections receive no owner metadata.

The pre-match or in-match `match.load_required` event is the explicit asset-prefetch
exception recorded in `decisions.md`: it carries one aggregate, deduplicated
set of printing keys so clients can cache art. It omits deck ownership,
quantities, sideboard grouping, and future library/hand order. These keys must
not be copied into room snapshots or the shared game log. In `preload` mode it
gates entry to the table; in `background` mode it does not gate play.

A server operator (including the owner’s home hub) **can** see hidden state. That is accepted for v1.

Optional [official accounts](accounts.md) recover only existing unexpired rights.
Login/recovery/device credentials are private to the requesting connection and
the trusted account authority; neither public account IDs nor display names
grant hidden-card access. Event/room projections omit account ownership fields.
After account handover or a verified legacy claim, stale connections lose both
mutation and private-projection authority. Spectator entry stays public-only.

## Why this exists

Both manual and rules-enforced online play need:

- Fair opponent views (no free peek at hands via the normal protocol)  
- Spectator boundaries  
- A clear answer to “who is allowed to know what”

It does **not** stop modified clients, voice reveals, or screen share.

## Visibility matrix

| Actor | Hidden identities (hand / library / …) |
|-------|----------------------------------------|
| Owning player client | Yes |
| Other seated players | No until reveal/public |
| Spectators | No until reveal/public, unless the room explicitly enables live hand visibility; that exception applies only to current hands |
| Room server | **Yes (allowed)** |

For model practice, a separately authorized desktop worker receives only the
model seat's permitted snapshot and current legal decision. The human's normal
connection and all spectator connections retain their existing projections.
Selecting an online model explicitly allows the configured provider to process
that AI observation, including its hand. The endpoint and API key stay on the
desktop; keys are session-only. The desktop owner can inspect worker memory,
so this is trusted practice rather than an anti-cheat boundary against its
owner. Model credentials never grant access to full Forge host publications.
See [model opponents](model-opponents.md).

## Target behavior

```text
Client loads deck → server stores deck identities
Server shuffles / draws / moves zones as designed
Owner gets private events with card names
Opponents get redacted views (counts, card backs)
Reveal or public zone → identity visible to room
```

The wire protocol and every role-specific projection must follow the trust and
visibility rules in this file.

The live `game.snapshot` projection carries each seat's public life and zone
counts. A seated player receives full identities only for their own `hand`.
Other seated players never receive that field. Spectators receive every
seat's current `hand` only when the room was created with
`spectatorsSeeHands: true`; otherwise it is omitted. This permission never
extends to sideboards, library order, private search results, face-down
battlefield identities, replays, or public logs. The server keeps library
order private even from the normal owner snapshot until an explicit
library-search command requests it.

When a spectator joins an already-running manual game, send its role-redacted
`game.snapshot` only to that new session; existing members receive the room
membership update without redundant game snapshots. The targeted projection
reuses the membership `room.snapshot` sequence without allocating a gap, and
projection failure closes only the affected session. Normal fanout may reuse
one immutable envelope among spectators with the same visibility; each player's
private projection remains separate.

The room-wide `stack` and `revealed` arrays are explicit public zones. Their
identities and `ownerSeat` are projected to players and spectators; only the
owner may issue a subsequent move for those instances.

Public battlefield placement separates ownership from control. A card keeps
its immutable `ownerSeat` when the acting player places it on another seat's
battlefield; that lane's seat may manipulate and tap the controlled permanent,
while hidden destinations return to the owner. Dragging from a library means
only the acting player's top card and does not disclose its identity until it
reaches a face-up public destination.

Face-down battlefield state is the exception to ordinary public-zone identity.
The server retains the full card, but only the current battlefield controller's
projection retains identity fields. Immutable ownership alone does not reveal
the card, and only the current controller may change its selected face or turn
it face up/down. Every other player, including the card owner on another seat,
plus every spectator (including hand-visible spectators), replay, and
public-log projection removes `name`,
`setCode`, `collectorNumber`, `typeLine`, and `faceName` while preserving public
instance state and `faceDown: true`. Table placeholders and hover-name fallbacks
must not paint `name` while `faceDown` is true, even if a projection bug still
carries the identity. Turning the card face up makes the identity
public again. Moving it out of the battlefield clears face-down state before
the destination projection is created.

Face-down exile withholds the same identity fields from **every** viewer,
including its owner and hand-visible spectators. The server retains the card;
logs and replay replies use generic face-down wording. Direct hand/library
moves may enter exile face down without a private look. The zone browser uses
backs and generic labels and keeps hidden instances separate for selection.
Leaving exile clears face-down state, then applies the destination's ordinary
visibility; returning to hand/library does not reveal the name in public logs.
The battlefield-only flip command cannot inspect or turn up an exiled card.

Graveyard and face-up exile identities are public, but public readability does
not grant public mutation authority. An explicit `fromSeat` may select a card
from another seat's graveyard/exile without revealing new information, but the
server retains the exact request and performs no move until that source-zone
player grants short-lived one-use approval. Rejection, expiry, disconnect, or
changed source state fails closed. A successful public log names the source
player and zone. A legacy public `toSeat` is accepted for compatibility but is
normalized to immutable `ownerSeat`; current battlefield control and the drop
surface cannot place a card under another player's graveyard/exile projection.
Public-seat fields remain invalid for hidden sources, and moving to hand or
library also targets the immutable owner rather than exposing another player's
hidden zone. A player cannot originate that private-zone move from another
owner's graveyard or exile; foreign public cards may move only to a battlefield
or back to their owner's public graveyard/exile.

A direct library-top move to the command zone is rejected before the server
examines that hidden card. This prevents a caller from probing whether the
unknown top card is a designated commander; a commander must return from a
zone where its identity is already available to the acting player.

P7 battlefield arrows and attachments are also public coordination state.
They contain only public battlefield instance ids. An attachment source
remains owner-controlled, and both relation types are removed when their
public endpoints leave the battlefield.

Library shuffle never creates a card-identity acknowledgement or reveals the
resulting order. Every viewer receives normal public library counts and
an identity-free log entry. If the owner enabled continuous top visibility,
the newly shuffled top card is also public; the remaining order is private.

The explicit land-play request contains one private hand-card instance id, but
its acknowledgement echoes only that opaque id and the resulting public
count. The card name appears only after the same atomic transaction has moved
the card onto the public battlefield; rejected requests do not add a log entry
or expose the hand identity. The recorded count is public to players and
spectators and resets with the active turn.

Except for an explicitly public library top, library identities are available
only through a private `game.zone_dumped` reply. An owner may request their own library directly; doing so also appends
an identity-free public log entry saying that the owner is searching their
library. Inspecting another
player's library first creates a private approval prompt for that player;
approval sends the requester a short-lived, requester-bound, source-seat-bound,
one-use grant alongside the private dump. The grant is consumed only after a
requested selection passes its scope and card-id checks, so a malformed
selection cannot burn an otherwise valid approval. A bounded `topCount`
returns only that current prefix; the full-library form remains the explicit
search view.
Every approved remote dump also appends an identity-free public log entry;
only the requester receives the private identities.
Rejection, expiry, disconnect, or a
mismatched requester/source cannot disclose cards or authorize a move. Dumps
are never room-fanned-out or stored in public snapshots. A subsequent
atomic multi-card search updates every viewer through role-specific snapshots:
hidden destinations expose only counts and a name-free log unless the
requester explicitly selects the reveal option. A remote top-prefix resolution
must submit every identity from the approved prefix as either selected or
remaining; the same grant authorizes exactly one atomic commit and is retained
when validation or reduction fails so the requester can correct the choice.

An approved remote-library search may place selected cards in either the
requester's or source player's allowed destination. Only a player whose hand
receives a card obtains that hand identity in subsequent projections;
`ownerSeat` remains the source seat and no unselected library identity is
retained or broadcast. Resolving a privately viewed own or approved remote
library top prefix validates that selected and remaining ids together are
exactly the current source prefix; selected cards enter the requester's hidden
hand or battlefield, or stay in the source library on top or bottom, while
remainder placement updates the rest of that source library.
Both changes commit atomically and publicly log only the count.

Random and whole-hand discard are also trust-server hidden-zone operations.
The correlated `game.hand_discarded` acknowledgement carries only seat and
count. A random choice is made on the server; discarded identities become
public in the graveyard and log, while cards left in hand remain visible only
to their owner.

The optional deck-card `typeLine` used to categorize the between-game
sideboard and its pending commander designation are private registered-deck
metadata. They are projected only to that deck's seated owner with the rest of
the pending partition and are absent from opponent, spectator, replay, and
public-log projections.
At game setup the committed sideboard is instantiated as a private game zone.
Its count is public, but identities are projected only to the owning seat.
Moving one of those cards into a public zone reveals only that moved card;
moving it into hand keeps its identity and log text private.
When that private field is absent on an older registration, the owner client
may read the matching printing's type line from its own installed catalog for
local layout only. This fallback does not add card identity or metadata to any
network command, public projection, or replay.

`game.say` is an explicit public disclosure: player and spectator chat is
validated by the server and then copied into every role-specific game
projection. Automatic game logs must still obey hidden-information redaction;
chat does not authorize the server to append private zone identities on a
user's behalf.

Tournament chat is a separate explicit public disclosure to sessions viewing
that event, including viewers who did not register. Sender display names are
server-authored, and no private pool, deck, credential, connection ID, or IP is
appended. The server retains only the latest 100 messages in the live event;
eviction or restart discards them. Event chat is not copied into room archives.

## Server retention (logs & full state)

Under trust-server policy, the room server retains ended-room archives:

- Full room/match state including **opening hands** and other hidden zones  
- Event **log** (draws, plays, damage, chat, library search, phase changes, …) for **TTL ≈ 1 week** (review / debug)  
- Live room **log pane is visible to all players** (anti-cheat / transparency); private hand **identities** still not shown in opponents’ hand UI
- Each game keeps at most 10,000 authoritative entries and each live snapshot
  projects the newest 500. `logStartId` and `logTruncated` make a dropped
  public prefix explicit while ids continue increasing monotonically.

Live UIs still project per role. Retention is for operators and replay
generation, not for leaking private hands to opponents in real time.

The P7 replay API is a separate public projection over those archives:

- `replay.listed` contains public match metadata and retention timestamps.
- `replay.loaded` contains that metadata plus the already-public table log.
- Hands, libraries, registered decks, pending sideboards, resume credentials,
  connection ids, and every other hidden archive field are excluded.

The client replay browser, timeline viewer, and shortcuts have been removed.
Server archives and this privacy-filtered compatibility API remain unchanged;
removing the client feature neither deletes archives nor exposes hidden state.

Forge's public compatibility API uses the same bounded public-log/replay contract. Its journal is derived
only from an explicit hand-hidden spectator projection, even if the room
grants live hand visibility to spectators. That grant overlays only current
hands in the live rules view; neither those identities nor owner-side pending
sideboards enter the journal. Face-down spells also omit name, edition and
collector number from the public stack and casting preview. Private prompts
and raw engine diagnostic text are never replay inputs. An interrupted rules
session may retain already-public journal entries without fetching or copying
the engine's hidden state into a manual game object.

The separate [private visual Forge replay](forge-replays.md) feature records
current hands and board observations for the original two participants. It
releases them only after the whole match finishes, never between BO3 games.
The waiting room discloses this policy. Spectators/later seat occupants receive
no capability; authenticated reconnect preserves the participant binding.
Private archives contain download capabilities with owner-only permissions;
portable exports omit those capabilities and transport credentials. Exported
files reveal both hands and remain readable offline by whoever holds the file.
They do not include registered decks, library order or RNG state. This feature
does not restore the removed public log browser or broaden its API.

The default TTL is seven days and is configurable by the operator. Archive
directories use mode `0700` and files use `0600`. Password hashes, reconnect
credentials, and transport connection identifiers are excluded. Cleanup runs
at server startup and before writing a new archive. See `self-hosting.md`.

Room-scoped private grants, reconnect credentials, and sideboard timers are
discarded immediately when their authoritative room is removed. A transport
drop is registered for reconnect only after the server revalidates that the
connection still occupies the room, so a concurrent kick or disband cannot
leave a usable stale credential.

Reconnects do not replay a cached historical projection. The opaque
credential rebinds the held membership, then the server creates a fresh room
snapshot and a fresh projection for the resumed player or spectator. This
prevents a role change or stale client cache from exposing another player's
hidden identities.

The connected-hub room list is another deliberately public projection. It
contains only room id/name, format and match settings, capacity/counts, phase,
joinability, spectator policy, and a password lock boolean. It excludes
password material, member display names, deck state, connection ids, and game
state. Tournament pairing rooms are omitted from that list. Paired players
enter only through `tournament.open_match`; generic `room.join` accepts a
pairing-room code only with `asSpectator: true`. Consequently, an event viewer
or somebody given the code can watch the public tabletop projection but cannot
occupy a seat or receive `match.load_required` printing keys. Tournament rooms
force `spectatorsSeeHands: false`, and their spectator projection never exposes
hands, current sideboards, Limited packs, pools, or unpublished decklists.

Tournament pairing-room decklists are a deliberate time-bounded exception to
normal deck privacy. The server retains the last deck each participant selects
in a private tournament pairing room, but registration and running-event
snapshots omit it. Once the tournament reaches `completed`, tournament detail
snapshots expose all recorded participant decklists to every viewer. Cancelled
events do not expose them, and the public tournament browser never includes
deck data.

Tournament credentials are single-current-connection capabilities. Rebinding
one immediately revokes the older connection's mutation and private-projection
authority, including opening an existing pairing room. An organizer who no
longer owns their participant connection retains only their organizer controls
and the public Limited projection. Event membership generations prevent an
in-flight projection from outliving a leave/re-enter transition. Pairing
rooms reject a second seat for the same participant identity. The opaque
credential remains in local client settings to support deliberate event
re-entry; Hexproof does not claim platform-vault protection against a local
account or process that can already read the user's application settings.

See `table-layout.md`.

## Forge crash reports

The independent crash-report schema is a safe diagnostic projection, not a
copy of the trusted server's full game archive or a private visual replay.
It contains fixed failure codes, verified code symbols, bounded native API/span
evidence, public turn/phase scalars and coarse submitted-action families.
Automatic smart-priority submissions are marked without copying their answer.
The hub never copies journal prose, chat, arbitrary ability descriptions,
exception messages or raw stdout/stderr into a report.

A source name is eligible only if the trusted native projection observed it
under the original hand-hidden spectator rules at that execution boundary.
The hub validates it against the pinned canonical card-name index; published
reports use that verified name and omit native printing coordinates. A catalog
name alone is not evidence of visibility. Hidden hands, libraries and face-down
sources remain anonymous regardless of live spectator-hand permissions. The
schema excludes decklists, private choice contents, response tokens, RNG seeds,
credentials, player/account names, host addresses, local paths and other games'
evidence. Resource dumps and environment dumps are not captured. The client
validates the schema again before persistence, clipboard copy or export and
renders values as plain text.

Reports go only to members bound to the failed game's room when the incident
was created, including held disconnected memberships. Authorized resume moves
that existing eligibility to the resumed connection; it does not grant it by
seat number, nickname or a new join. At most eight newest eligible reports are
redelivered per resume. There is no public report index or report-download API,
and a report ID is not a credential. Hub restart does not recover delivery
eligibility from the operator archive.

Client history retains up to seven days from first receipt, at most 64 reports
and 4 MiB. Hub memory and the optional private server archive each retain up to
seven days from incident creation, at most 256 reports and 16 MiB. The client
and archive use private directories/files (`0700`/`0600` or platform equivalent)
and atomic replacement. Revisions and redelivery do not renew the deadline.
Startup/load/write maintenance and periodic pruning enforce these bounds;
copy/save checks expiry again. Physical deletion is best effort when storage
fails; failures do not prevent the in-memory notice or room cleanup.

Details, copying the complete sanitized JSON and saving a local JSON file work
without hub access. Sharing either with support is an explicit user action.
Dismissing a notice keeps its unexpired history; restoring history after an
application restart does not reopen old notices. There is no automatic upload.
The player-host helper retains only its current engine's bounded failure capsule
in memory across transport reconnect and cancellation; a new engine or helper
exit releases it. This does not add a helper crash-history disk archive or alter
the separate installation/hosting support report.

## In-app feedback

### Public-feedback contract

The [public V2 contract](public-feedback-v2.md) covers
preview, acceptance, publication status, separately approved public replies,
client-visible clarification and authenticated removal. The
[native Multica workflow](autonomous-development.md) receives only verified
public contributions under their recorded provider policies. Activation and
deployment status live in the [handoff](development-handoff.md) and trusted
configuration; a tooling trial or source change does not itself activate intake.

New in-app feedback is a public contribution to Hexproof's development.
Every accepted submission, including its text, technical context, screenshots,
diagnostic attachments and subsequent user replies, is intended for publication
in the project's public GitHub issues. There is no private-submission mode,
private-attachment option or contact-email field in this contract. A user who
does not want the content to become public must keep it as a local draft or
cancel submission.

The composer must identify the public destination and present the exact content
and attachments that will be published before the user confirms **Publish
feedback**. Preparing or previewing a draft sends nothing. User-authored content
must not be silently rewritten after approval; AI analysis and summaries are
separately attributed. Changed content and follow-up replies require their own
public preview and confirmation. A detected credential or other content that
cannot be published must be rejected for correction, rather than redirected to
a private support queue. Automated screening cannot guarantee that user text
or image pixels contain no personal information. The preview must remind users
that the resulting issue and attachments can be viewed and copied by anyone.

Existing limits on automatic technical context, diagnostic sanitization, image
metadata removal and explicit attachment selection remain in force. Publishing
feedback does not authorize automatic collection of room state, hidden cards,
chat, desktop captures or other players' data. Secrets used to authenticate a
submission, receipt access capabilities, abuse-control data, internal transport
metadata and operator credentials are not public feedback content and must
never be included in issues, attachments or AI task context. The public issue
association must not reveal the private capability used by its submitter.
Direct GitHub contributions are also screened before entering AI task context;
being public is not an exemption from these data limits. Automated clarification
must not ask users to disclose content prohibited by this contract.

The service first durably accepts the approved public payload and then retries
publication asynchronously. A receipt must distinguish acceptance from actual
publication and provide the public issue reference once available. Acceptance
does not establish that a bug is confirmed, a request is accepted, or a fix has
been released. Client-side deletion or cancellation cannot recall an upload
already received, an already published issue, or copies made by others.
The client must show publication delays and failures, including partial delivery
of the approved text and attachments. Development assessment begins only after
the complete approved contribution has been verified as published. A temporary
delivery failure must not be disguised as either successful publication or a
private support submission.

Public feedback is intended to be processed by automated development agents,
potentially through multiple AI providers, for classification, reproduction,
implementation, review and release preparation. The deployed notice must name
the providers used by the configured workflow and explain their data-processing
terms before this intake is enabled; the actual configuration must match that
notice. Only approved public content and the task's permitted project context
may be supplied to those agents. AI access does not expose receipt secrets,
legacy private submissions or unrelated account and game data. Routine
development and review are intended to run without a required human reviewer;
publication is not a promise of human review or a guaranteed fix. The workflow
and release gates are specified in
[autonomous development](autonomous-development.md).
Activation and provider changes must bind the notice revision to the actual
configured workflow; an undisclosed provider cannot receive submissions first
and be added to the notice afterward.
The processing policy applicable to each contribution also governs historical
context supplied to an agent. Updating the provider list alone does not expand
that contribution's authorization. Direct GitHub contributions retain their
public origin and applicable collaboration-policy record; the service must not
fabricate a client confirmation or infer authority solely from a later notice.

The official 3.1.0 disclosure is maintained in the
[public notice page](https://47.97.30.103/feedback/privacy) and the
[matching build configuration](../apps/client-qt/config/feedback.official.json).
It currently names GitHub for publication and Multica/OpenAI for automated
processing; other configured development tools are not thereby permitted to
receive feedback. The 2026-10-24 notice revision retains the qualified
processing-policy identifier so already published contributions keep their
original authorization. See the [cutover procedure](feedback-operations.md#official-public-configuration-and-notice-upgrades)
for draining old-notice publications before changing the current disclosure.

Public issues, comments and required public attachments form the ongoing
development record. The legacy private receiver's 90-day content expiry does
not promise deletion of this public record. The public-feedback implementation
must document its local draft, transient upload, receipt and operational-data
retention separately from public-record retention. The deployed notice must
identify the service responsible for project-controlled public attachment hosting; public attachments need
not be physically stored on GitHub. Their stable public links and retention
must not silently inherit the transient receiver's expiry. The notice must
explain how to report accidentally published sensitive content and request
removal from locations controlled by the project. Closing a feedback case stops
the request for further follow-up while retaining its public discussion and
development history. It is available separately from requesting content removal;
the client must explain the distinction before sending either operation.
Closure does not promise deletion or immediate physical cancellation of every
already running AI task. The receiver stops accepting new case replies and AI
projections, and the native team reconciles and cancels case-specific work.
Related reports may share development, but each retains its own consent,
conversation and closure/removal rights. Closing one report does not cancel
shared work still needed by other active reports; removing it does not remove
another reporter's content. Unrelated clean fixes and the existing public record
may remain. A delayed public issue closure or task notification must be shown
honestly.

Content removal is a separate request, including when sensitive content was
published accidentally. It may remain pending when an external service retains
a project-controlled copy that cannot yet be cleared; do not display complete
removal merely because current messages were hidden or the issue was closed.
Removal from project-controlled locations cannot guarantee deletion
from GitHub history, notifications, third-party copies, search indexes, backups
or AI-provider records; those systems have their own retention rules. No
complete-erasure claim is made.
Confirmed removal from project-controlled locations must stop queued retries
and stale automated tasks from republishing that content. Removal requests need
scoped authorization; third parties may also report exposed sensitive material
for moderation without obtaining control of the submitter's receipt.
The client must offer this request and show its progress without requiring
GitHub access; deleting a local draft or receipt is a separate operation.
Project-controlled summaries, checkpoints and other derived material containing
removed content must be quarantined or sanitized before further processing or
publication. Unrelated clean code fixes may remain. This does not extend the
removal promise to third-party copies or AI-provider records.

This contract takes effect only through a versioned public-feedback API and a
client that implements the public preview and publication confirmation. It must
not be enabled merely by changing the existing receiver configuration or this
document. Existing private submissions and drafts must never be automatically
published or supplied to the public AI workflow. A user may deliberately create
a new public submission from their old local content only after the new public
preview and confirmation. Legacy clients retain the contract below and cannot
be silently redirected to public publication. When public-only intake is
activated, new V1 submissions are no longer accepted. Existing accepted records
retain receipt lookup and the original protection/retention promises; old
clients must update and explicitly prepare a new public submission. There is
no parallel private intake channel in the successor service.

### Implemented feedback v1: legacy private contract

The following describes the retained legacy receiver and record contract. It
continues to govern content submitted under
feedback API v1 and content accepted under its private-disclosure notice.

Feedback is an explicit private disclosure to the official support organization
shown in the composer. It uses a separate build-configured HTTPS receiver;
neither a room nor a custom game hub can supply that destination. The bundled
example remains disabled; current official defaults disable new intake pending
qualified V2 activation. Production activation is separately authorized. Local
drafts, attachment previews and exports work without a receiver or account.

Opening the composer, receiving a Forge crash report, selecting an attachment,
or saving a draft sends nothing. **Send feedback** freezes the visible content
and authorizes bounded automatic retries while Hexproof is running. The
receiver uses an anonymous submission capability, without account association,
game cookies, reconnect credentials or current-hub authentication. Access
secrets stay in private client storage and request headers; they are excluded
from QML projections, exports, receipts, URLs and logs.

Automatic technical context is limited to application, platform, language,
feature, catalog/runtime versions and relevant game mode/format/priority mode.
It excludes account/player names, room identities, endpoints, decklists, hands,
chat, raw snapshots, action payloads, paths, access codes and credentials.
The user may deliberately attach up to two static PNG/JPEG images, one existing
sanitized Forge crash report and one allowlisted hosting diagnostic snapshot.
Images are decoded within size/pixel bounds and reencoded without metadata;
the application never captures the desktop or monitors the clipboard. Explicit
Paste reads an image only when requested. Selected reports are copied into the
draft, preserving their capture time and revision independently of source
history expiry. Both client and receiver validate attachment content.

Descriptions and image pixels may still reveal private cards, chat or personal
details. The entire submission is support-private; diagnostic sanitization does
not anonymize user-written text or pixels. Maintainers receive private email at
a configured dedicated mailbox. The optional contact address is unverified,
included in the message body, and never used for an automatic confirmation
email. Feedback is not automatically published as a GitHub issue.

Drafts and unreceived submissions remain locally until explicit user deletion,
within the fixed count/payload quota; an exhausted retry budget does not erase
them. Received metadata is retained locally for up to 90 days and at most 100
records. Received content is retained for up to 30 days and may be reclaimed
earlier to make room, with an explicit unavailable-content state. **Stop
sending** durably revokes future uploads; requests already sent may have reached
support. **Delete locally** also cancels remaining local work and prevents late
responses from recreating the record. Neither action recalls server or mailbox
copies, and exporting creates another local copy under the user's control.

A **Received** receipt acknowledges durable receiver storage, not developer
review, SMTP delivery, confirmation of a bug or resolution. Receiver content
expires no later than 90 days after acceptance; audited spam/abuse removal may
occur sooner. Minimal receipt, digest and hashed-authentication tombstones last
until day 120 to prevent duplicate delivery. The receiver uses owner-only files
and directories. This is access control, without a claim of encryption at rest
or universal protection from a process that already owns the local profile.
Source addresses are retained only in bounded transient abuse-limit state.
Descriptions, contact, images, bearer secrets and request bodies are not logged.

Mailbox access, mailbox retention, backup expiry and support deletion contact
must be documented in the deployed privacy notice before intake is enabled.
Receiver expiry and local deletion do not retract delivered emails or backups.
No complete-erasure claim is made. See the [feedback contract](feedback-design.md)
and [receiver operations](feedback-operations.md).

## Explicit non-goals (v1)

- Server must not learn hidden identities  
- Cryptographic proof of fair shuffle  
- Protecting players from a malicious server operator  
- Forever-keeping every match with no TTL  

If the owner later wants a stricter model, record a new decision in `decisions.md` and update this file.

A manual player may opt into continuous public library-top visibility. Every
viewer receives only the current top card, computed from authoritative state
after each atomic operation; no library order or additional identities are
projected. Disabling visibility removes the top-card projection immediately.
