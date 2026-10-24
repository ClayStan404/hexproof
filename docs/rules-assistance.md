# Rules assistance architecture

This document defines small rules-related conveniences in **manual rooms**.
It remains the required design reference for P11 work and any feature that
observes manual-table state in order to warn, confirm, or combine actions.
Rules-enforced Forge rooms are a separate product mode governed by
`rules-engine.md`; do not place Forge behavior in these assistance modules.

`product-brief.md`, `match-flow.md`, `privacy.md`, and `decisions.md` remain the
product authorities. This document defines implementation boundaries.

## Product boundary

In a manual room, Hexproof is a server-authoritative free-form tabletop.
Players decide whether a play is legal and resolve card text themselves. Rules
assistance may make public coordination clearer, call attention to a common
mistake, or commit a small group of explicitly selected actions atomically. It
must not silently decide what a card permits.

An assist must fit one of these categories:

| Category | Meaning | Example |
|----------|---------|---------|
| Public coordination | Shared intent or progress that every viewer may see | Active phase, response status, attack target |
| Derived presentation | A non-authoritative visual fact derived from the viewer's current projection | Life at zero or less, empty library, hand over seven |
| Advisory confirmation | An overrideable warning before an explicit manual action | Warn about a non-Creature or tapped attacker |
| Atomic explicit helper | One user gesture submits several explicitly chosen state changes as one transaction | Declare attackers and tap selected attackers; record commander damage and subtract life |

The following behavior is outside this architecture:

- parsing card text to discover triggers, costs, targets, replacement effects,
  continuous effects, or state-based actions;
- automatically advancing priority, resolving the stack, choosing targets, or
  declaring a game result;
- rejecting a manual action only because printed card metadata suggests that
  ordinary Magic rules would reject it;
- inferring hidden card identity or sending private identity through a public
  snapshot, log, acknowledgement, error, or reminder;
- a general-purpose rule language, plugin registry, or central `RulesEngine`.

If the product later requires card-text-driven legality enforcement, treat it
as a separate product and architecture decision. Do not grow it incrementally
inside the assistance modules described here.

## State and authority

Every proposal must classify each value it reads or writes before code is
added.

| Data class | Authority and lifetime | Permitted use |
|------------|------------------------|---------------|
| Authoritative public state | Server room reducer; persisted for the match and projected to eligible viewers | Turn/phase, public relations, commander tax and damage |
| Authoritative private state | Server room reducer; projected only to an authorized viewer | A player's hand or library identities; never a source for another viewer's reminder |
| Client-derived advisory state | Recomputed from the typed snapshot; never sent as truth | Warning colors and confirmation text |
| Optimistic state | Client command tracker; rejection rolls back, success ends request correlation, snapshot reconciliation or bounded timeout clears the overlay | Immediate feedback for an already-submitted explicit command |
| Ephemeral interaction state | One popup, view, or narrow controller; discarded when the workflow closes | Selected attackers, optional tap choices, warning-dialog intent |

There must be only one authoritative copy of durable game state. A QML
controller must not retain a parallel phase, damage total, zone membership, or
other value that can diverge from `GameTableModel` and the room snapshot.

Derived reminders may inspect only information present in that viewer's typed
projection. The client must not request hidden data merely to improve a
warning.

## Dependency direction

Rules assistance follows the normal table dependency direction:

```text
feature view or popup
  -> narrow QML coordinator
      -> WsClient typed command facade
          -> hexproof.v2 payload
              -> server command handler
                  -> room reducer
                      -> privacy-aware projection
                          -> GameTableModel
                              -> feature view or derived reminder
```

`Table.qml` composes these collaborators and exposes stable aliases. It does
not implement a rule predicate, construct a protocol payload, or own a modal
workflow. `Hub` forwards a validated command under the room lock; it does not
duplicate reducer behavior. Protocol files define bounded shapes and wire
validation, not game policy.

## Module ownership

| Module | Rules-assistance responsibility | Must not own |
|--------|---------------------------------|--------------|
| `TableRulesAssistController.qml` | Cheap derived reminders and orchestration of the current navigation/combat confirmation flows | Durable state, generic card rules, protocol object construction, unrelated command families |
| Feature popup or view | One interaction's selection, explanation, and explicit continue/cancel path | Authoritative state or another workflow's policy |
| `TableOptimisticCommandController.qml` | Temporary overlays for submitted commands and reconciliation | Legality decisions or permanent state |
| `GameTableModel` and typed zone models | Stable typed projection of authoritative snapshot data | Transport and presentation policy |
| `WsClientCommands.cpp` | Validate basic client arguments and serialize a typed command | Server authorization or card-rule decisions |
| `protocol` | Bounded request/snapshot structures and shape limits | Reducer behavior or UI policy |
| `server` command handler | Decode, identify the session, call one room operation, and fan out the result | A second implementation of the transition |
| `room` domain reducer | Authorization, authoritative invariants, atomic transition, and public log/result data | Network I/O, QML concerns, or card-text interpretation |
| room projection | Viewer-specific visibility and redaction | Mutating room state |

Give a new durable state owner or independent lifecycle an explicit boundary.
A new command family or modal interaction is a reason to review cohesion, not
an automatic requirement to extract before any feature work. For example, a
substantial mana-payment workflow with its own state should receive its own
coordinator and reducer domain rather than turning
`TableRulesAssistController.qml` into a generic payment engine.

A small pure reminder may remain in `TableRulesAssistController.qml` when it
uses existing typed public inputs and belongs to the same responsibility.
Crossing a review threshold alone does not change that decision.

## Hard invariants versus advisory checks

The server enforces command integrity, not general Magic legality.

Hard validation is appropriate for:

- session, room, seat, ownership, or controller authorization required by the
  command contract;
- referenced object existence and the zone required by the explicit action;
- bounded counts, non-negative values, unique identifiers, and valid enum or
  payload shape;
- membership relationships needed for atomicity, such as every requested tap
  id also being one of the declared attackers;
- public coordination state that defines the operation, such as who may
  advance the current turn or submit the current combat declaration.

Advisory-only checks include:

- whether printed type, tapped state, or ordinary timing would normally make a
  card eligible;
- vigilance, haste, costs, legal targets, replacement effects, and continuous
  effects;
- maximum-hand-size modifications, poison/life/damage loss exceptions, and
  any other result that card text may change;
- whether a battlefield permanent is legally attackable under Magic rules.

Every advisory warning must identify what Hexproof observed, state that card
effects may override it when useful, and provide both an explicit continue
path and a cancel path. Continuing sends the same manual command; it must not
set a hidden “ignore rules” mode.

## Atomic helpers and reconciliation

An atomic helper is permitted only when every mutation is visible in the
confirmation UI and all mutations share one user intent.

1. The client submits one request with all selected ids and values.
2. The room reducer validates the complete request before changing state.
3. The reducer applies all changes or none of them.
4. Public/private projections are produced from the committed state.
5. Optimistic client values improve responsiveness but never become authority.
6. Rejection, timeout, or the next authoritative snapshot removes or replaces
   the optimistic overlay.

Do not implement a multi-step helper by sending unrelated commands in a loop.
That exposes partial success, produces intermediate snapshots, and makes
recovery ambiguous.

## Current assistance inventory

| Feature | Category | Client owner | Authoritative owner |
|---------|----------|--------------|---------------------|
| Turn, phase, and response status | Public coordination | Table action/phase views and typed table state | Room turn/response reducers |
| Navigation warnings | Derived presentation and advisory confirmation | `TableRulesAssistController.qml` | None; the eventual navigation command uses the existing room reducer |
| Life, empty-library, and oversized-hand reminders | Derived presentation | `TableRulesAssistController.qml` and status views | None |
| Combat declaration with optional taps | Advisory confirmation and atomic explicit helper | `CombatDeclarationPopup.qml`, `TableRulesAssistController.qml`, optimistic command controller | Room combat-relation reducer |
| Commander cast and tax | Atomic explicit helper | Command-zone browser/editor popup | Room commander reducer |
| Commander damage and optional life change | Atomic explicit helper | `CommanderDamagePopup.qml` | Room commander reducer |
| Recorded land play | Public coordination, advisory confirmation, and atomic explicit helper | `LandPlayPopup.qml`, `TableLandPlayController.qml` | Room land-play reducer |
| Battlefield attachments | Public coordination | `TableAttachmentController.qml`, `TableAttachmentStackLayer.qml` | Room relation reducer |
| Explicit zone selection, ordered/random placement, and recycling | Atomic explicit helper | `ZoneBrowserPopup.qml`, `TableCardMoveController.qml` | Room batch-move reducer; see [manual zone actions](manual-zone-actions.md) |

This table must be updated when a new assistance family becomes part of the
product. Detailed behavior and acceptance criteria belong in
`implementation-plan.md`, `match-flow.md`, and dated owner decisions.

## Required feature design record

Before implementing a new assist, add a short section to the implementation
plan or a focused English design document that answers all of the following:

This applies to a new assistance family or a changed trust/state boundary, not
every small repair to an existing assist. Reuse the existing record when its
contract is unchanged; follow `development-policy.md` for proportional checks.

1. What manual player intent does the feature shorten or clarify?
2. Which allowed assistance category does it use?
3. Which inputs are public, private, derived, optimistic, or ephemeral?
4. Which module owns each state value, and when does it reset or expire?
5. Which checks are hard invariants and which are overrideable warnings?
6. Does the operation need one atomic reducer transaction? If so, which
   mutations must succeed or fail together?
7. Which QML view and narrow coordinator own the interaction?
8. Does the wire protocol change? Which reducer, projection, and typed model
   receive the corresponding changes?
9. How are hidden identities redacted from snapshots, logs, acknowledgements,
   errors, and spectators?
10. Which protocol, reducer, projection, model, QML, localization, and manual
    interaction checks protect the behavior?
11. Does any touched file cross a review threshold or gain a second reason to
    change? Would an extraction improve cohesion or testing? A size hint alone
    does not require extraction before the feature.

If these answers require “the rules controller knows all cards” or another
central catch-all owner, the proposal is outside the current product boundary.

## Growth controls

- Apply the advisory size review and ownership guidance from `module-boundaries.md`.
- Do not turn `TableRulesAssistController.qml`, `Table.qml`, `WsClient`, `Hub`,
  or a protocol file into a central rules service.
- Split room code by reducer domain within the existing package before adding a
  package whose only purpose is reducing line count.
- Introduce a shared abstraction when concrete consumers share a state owner,
  lifecycle, validation boundary, and test shape. Prefer observed reuse over
  speculative frameworks; no fixed number of features is required. Similar UI
  wording alone is not a reusable rules framework.
- Prefer a pure predicate over cached state, a typed property over a
  `QVariantMap`, and one explicit command over inferred automation.

## Privacy and trust checklist

Every assistance change must preserve the trust-server privacy model:

- derive client reminders from the viewer's existing projection only;
- re-check authorization and identifiers in the room reducer even when the UI
  disables an action;
- keep private names and metadata out of public logs, errors, command
  acknowledgements, tournament/spectator views, and debug output;
- test owner, opponent, and spectator projections separately when private
  zones or face-down cards are involved;
- do not make hidden-state access a prerequisite for a public convenience.

## Verification matrix

Select the applicable rows for every assistance feature; an atomic or
privacy-sensitive feature normally requires all of them.

| Layer | Required evidence |
|-------|-------------------|
| Protocol | Valid and invalid payload shapes, generated parity, and shared fixtures when wire data changes |
| Room reducer | Authorized success, unauthorized/invalid rejection, boundary values, and no partial mutation on failure |
| Projection | Owner/opponent/spectator visibility and absence of hidden identity leaks |
| Server handler | Request-id behavior and exactly one reducer invocation/fan-out path |
| Client service/model | Typed command serialization, snapshot parsing, and reconciliation |
| QML | Warning text, continue/cancel behavior, selection state, and disabled-state recovery |
| Localization | English and Simplified Chinese strings, including long names and plural/count formatting |
| Native visual flow | When presentation/input is affected, relevant real-client scenarios and window sizes (including narrow layouts where relevant), following `development-policy.md`; not a GUI run for every backend-only change |

Tests must preserve the advisory boundary: include at least one ordinary-rules
exception that the user may explicitly continue past, while still proving
that malformed or unauthorized commands are rejected.
