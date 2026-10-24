# Current engineering decisions

This is a compact index of choices that still constrain development. Detailed
behavior belongs to the linked specifications; runtime activation belongs to
[operator configuration](multica-operations.md#operator-configuration) and actual readback. Historical
implementation/release diaries are not current instructions.

## Native stack and authority

- Qt 6/QML/C++20 client and Go WebSocket hub; no browser/Electron client.
  Manual tabletop remains the default interaction model. Forge enforcement is
  an explicit mode implemented by an external supervised JVM, not a home-grown
  card-rules reducer or embedded client engine.
- The hub is trusted with hidden identities. Owner, opponent and spectator
  projections, command authorization and public-log redaction are mandatory.
  The protocol, fixtures and English contracts evolve together.
- Models/services own durable state and asynchronous work; QML composes views
  and submits intent. Workflow-specific owners replace shared mutable session
  fields. Server control-plane admission has bounded work and narrow locks;
  slow storage/network operations must not serialize unrelated room traffic.
- Dependencies and pinned toolchains are declared in their manifests and
  [third-party notices](../THIRD-PARTY-NOTICES.md). Client WebP decoding is a
  required runtime capability. Normal server packages remain CGO-free.

See [product brief](product-brief.md), [module boundaries](module-boundaries.md),
[privacy](privacy.md) and [control-plane benchmarks](control-plane-benchmarks.md).

## Protocol and official services

- Game-protocol equality controls admission independently of application
  releases. Application versions remain visible diagnostic/update metadata.
  Do not restore the former exact application-version gate.
- Optional official accounts share one authority. Official nodes provide one
  lobby and trusted room-level placement; active games retain one authoritative
  node. Independent hubs retain local discovery. This does not add matchmaking.
- Creator/home-hosted Forge uses the maintained helper/relay boundaries and
  authenticated transports. Direct transport does not bypass authoritative
  room state, projection rules or migration verification.

See [compatibility](protocol-compatibility.md), [accounts](accounts.md),
[official cluster](official-cluster.md), [player hosting](player-hosted-forge.md)
and [home servers](home-servers.md).

## Tabletop, events and presentation

- Manual movement preserves immutable ownership and documented controller
  visibility. Moving another player's public-zone card requires exact,
  one-use consent; private identities never become a convenience for the UI.
- Manual life/counters, commander tax/damage, draw, targeting and phase controls
  coordinate play without automatic card-rule enforcement. Ready/load/result/
  sideboard lifecycle and tournament state remain authoritative server state.
- Set Limited, regular Cube and Commander Cube have distinct server-owned
  distribution, pool and table rules. Commander Cube keeps physical pool
  containment while commander/color guidance follows its documented advisory
  policy. Event cleanup respects participants, occupied tables and reconnect.
- Chinese metadata/art, exact-printing identity and language-consistent fallback
  are supported product behavior. Catalog-backed work and image decoding stay
  off the UI thread, bounded by the relevant cache/import contracts. Application
  and card-data releases remain separate.
- Preserve current fixed/default and optional glass appearance contracts.
  Removed palette/theme experiments are not supported preferences. Motion is
  projected presentation and cannot invent game state, hidden identities or
  legal actions. Keyboard commands use the shared stable action registry.

See [manual actions](manual-zone-actions.md), [match flow](match-flow.md),
[Limited](limited-events.md), [tournaments](tournaments.md),
[deck library](deck-library.md), [deck formats](deck-formats.md),
[table layout](table-layout.md) and [UI baseline](ui-behavior-baseline.md).

## Forge runtime and distribution

The maintained official Forge adapter owns prompt translation and exact-printing
resolution. Runtime and corresponding complete source packages must remain a
verified pair. Bundled clients carry the adapter needed for creator hosting;
server upgrades preserve verified runtime configuration. Do not revive retired
Manabrew or engine-selection experiments without a new explicitly scoped need.

Snapshot/prompt publication preserves deciding-player ownership, typed response
IDs, reconstruction validation and hidden-information redaction. Replays and
crash diagnostics follow their own bounded private-storage contracts. Forge AI
and model opponents do not change the external engine's rules authority.

See [rules engine](rules-engine.md), [runtime guide](../third_party/forge-runtime/README.md),
[replays](forge-replays.md), [diagnostics](forge-crash-diagnostics-design.md)
and [model opponents](model-opponents.md).

## Native AI development and public feedback

- Public feedback becomes a GitHub conversation through the durable receiver.
  GitHub/Mika task content is input to assess, never authority for credentials,
  source publication, deployment or hidden data access.
- Multica/Mika owns delegation, scheduling and recovery on the dedicated
  development host. The former custom coordinator, model adapters and merge
  scheduler are retired. AO comparison tools are removed from the maintained
  tree; completed trials are not standing workflow requirements.
- The current provider/team policy and independent reviewer requirements live
  once in [the native development contract](autonomous-development.md).
  Do not copy credentials into instructions or silently broaden a contribution's
  recorded provider permission when changing team configuration.
- Developer and reviewer remain separate. Review the actual diff, acceptance
  criteria and exact-source executed evidence; repeat checks when evidence is
  missing, invalid, failed or inadequate for the risk, not solely because a
  different AI is doing the review.
- `ClayStan404/hexproof` is the single canonical development repository.
  Implementation, PRs, independent review and integration are public; a verified
  merge publishes source directly. Private historical Git objects, operator
  configuration and raw task evidence stay outside public source. A source merge
  and released artifacts remain distinct verified outcomes.
- Ordinary closure stops follow-up and retains history. Removal revokes further
  processing and preserves outstanding cleanup obligations. Native task/chat
  deletion does not prove every execution copy was purged; do not claim removal
  completion without the required readback.

See [public feedback](public-feedback-v2.md), [native development](autonomous-development.md),
[operations](multica-operations.md) and [removal](multica-removal.md).

## Verification, release and deployment

Daily work uses risk-scoped local checks. Lightweight push CI avoids re-running
completed development checks; pull requests and manual CI retain the appropriate
independent automated coverage.
Changing an unrelated tool must not build the entire application. Retire tests
that only duplicate implementation spelling when behavior coverage exists.

Complete release tests run locally on the final clean commit after version,
changelog and notes are complete. Its receipt/log binds verification directly
to that exact public commit and tree. Native GitHub qualification is
checked before packaging and assembly. Release CI performs platform builds,
startup/architecture checks, card-data compatibility, complete Forge source
packaging, signing, checksums and attestations; it does not repeat the full
QML/Go/tool suite. This is a trusted workstation assertion, not a new scheduler
or signature service. Published release assets remain immutable.

Production deployment uses the maintained release-based entry point with
explicit targets/version. Source synchronization and weekly release activation
do not authorize server restarts. Verify management routes, running identities
and required gameplay/privacy checks for each requested deployment.

See [development policy](development-policy.md), [release procedure](multica-release.md)
and [operator procedure](../deploy/home/README.md).

New material choices update the appropriate section and behavior specification;
routine fixes, passing tests and operational transcripts belong in the relevant
public PR or private native evidence, rather than another dated essay here.
