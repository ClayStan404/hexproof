# Implementation specification map

Hexproof's original P0–P14 / R0–R4 greenfield plan is complete historical
context. Current work follows the owner's requested task, [AGENTS.md](../AGENTS.md)
and the [development policy](development-policy.md). This map locates behavior
contracts; it does not impose the old phase order or another checklist.
Do not read the owner-only `产品说明.md` when implementing.

## Find the behavior contract

| Change | English specifications |
| --- | --- |
| Product scope and stack | [Product brief](product-brief.md), [current decisions](decisions.md) |
| Hidden information and public/private projection | [Privacy](privacy.md) |
| Handshake, reconnect, rooms and discovery | [Networking](networking-notes.md), [protocol compatibility](protocol-compatibility.md) |
| Official identity and room placement | [Accounts](accounts.md), [official cluster](official-cluster.md) |
| Ready, loading, game result, BO3 and sideboarding | [Match flow](match-flow.md) |
| Manual card movement, ownership, search and consent | [Manual zone actions](manual-zone-actions.md), [rules assistance](rules-assistance.md) |
| Table layout, counters, keyboard/pointer behavior | [Table layout](table-layout.md), [UI acceptance baseline](ui-behavior-baseline.md) |
| Deck persistence, import, catalog and images | [Deck library](deck-library.md), [deck formats](deck-formats.md), [custom art](custom-card-art.md) |
| Sealed, Draft, regular/Commander Cube and pool ownership | [Limited events](limited-events.md) |
| Swiss lifecycle, pairing and unattended cleanup | [Tournaments](tournaments.md) |
| Forge rules, prompt response and projections | [Rules engine](rules-engine.md), [action clock](action-clock.md) |
| Creator/home hosting and transport | [Player hosting](player-hosted-forge.md), [home servers](home-servers.md) |
| Forge/model opponents | [Model opponents](model-opponents.md) |
| Public feedback and AI work | [Public feedback V2](public-feedback-v2.md), [native development](autonomous-development.md) |
| Module ownership and dependencies | [Module boundaries](module-boundaries.md) |
| Local checks, release and deployment | [Development policy](development-policy.md), [release](multica-release.md), [deployment](../deploy/home/README.md) |

## Shared implementation invariants

- The native client is Qt 6/QML/C++20; the Go hub is authoritative. Manual
  tabletop does not implement card legality or automatic priority. Optional
  Forge rooms use a supervised external rules engine through the typed boundary.
- Canonical message names and payloads live in
  [wire-schema.json](../protocol/v2/wire-schema.json), its referenced schemas and
  [shared fixtures](../testdata/protocol/v2/). Change those and generated
  constants together when wire behavior changes.
- The handshake negotiates exact game-protocol equality once. Application
  versions are diagnostic metadata, not an admission gate. The client checks
  welcome protocol before accepting resume credentials or sending commands.
- Reply-bearing commands carry `id`; the matching success event or `error`
  echoes it. Success names are events (`room.created`), not `*.ok`. Subsequent
  messages omit the handshake version. Room publication sequence is per room;
  paired Forge snapshot/prompt publications follow the rules-engine sequencing
  contract rather than imposing global monotonicity on every message type.
- The server holds full state, while every outbound snapshot and log uses the
  viewer's projection. Reconnect rebuilds current projections; it never replays
  a cached private view. Face-down card identity follows the documented
  controller visibility rule, not immutable ownership.
- Validate and commit authoritative mutations atomically before publication.
  Preserve immutable card ownership, explicit cross-seat consent and all
  relevant owner/opponent/spectator projections. Tokens have battlefield-only
  lifetime; counters and commander tax remain manual in manual rooms.
- Ready plus the configured preload/background policy controls automatic
  entry. Match score, sideboard timers and previous-loser starting choice are
  server state. No client-only shadow state may break reconnect.
- Public-log replay server endpoints remain compatibility APIs even though the
  old client replay UI was removed; do not expose hidden operator archive fields.
- Official shared discovery and optional accounts are supported. Matchmaking,
  ladder/ranking, judge tooling, browser/Electron clients and cryptographic
  secrecy from the trusted hub remain outside the current product scope.

Product semantics come from the applicable English contract and canonical
protocol, not from a passing implementation test alone. If the owner changes a
contract, update its existing specification; routine work does not require
parallel updates to this map, decisions, handoff and an extra plan.

Completed phase plans are not a new task queue. Use the current specifications
above and the current protocol when implementing changes.
