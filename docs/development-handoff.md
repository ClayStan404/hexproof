# Hexproof development handoff

This is a status index, not a product specification or execution diary. Follow
[AGENTS.md](../AGENTS.md), the [development policy](development-policy.md) and the
relevant [behavior specifications](implementation-plan.md).

## Current workflow

Development, PRs, independent review, merges and releases use the public
`ClayStan404/hexproof` repository. Read the canonical task's compact handoff and
current GitHub state for unfinished work; a source merge is not a release.
Official release versions and assets are listed on
[GitHub Releases](https://github.com/ClayStan404/hexproof/releases).

Actual deployment inventory, service bindings, native task IDs and operation
activation are private operator state. Resolve them through
[operator configuration](multica-operations.md#operator-configuration) and live
readback before maintenance; this document is not a fleet inventory.

## Unresolved limits

- Native copy removal is not fully qualified. Completed task history and
  execution copies may remain; cleanup acknowledgment stays disabled until the
  required copies can be verified removed. Ordinary closure remains separate.
- Native recovery does not establish global concurrent task uniqueness, every
  partially executed development recovery path or provider configuration
  fidelity. Keep the bounded [recovery procedure](multica-recovery.md) and
  [feedback boundary](multica-feedback.md).
- An enabled release trigger is not a completed unattended release. Each actual
  execution needs its exact source, review, qualification and artifact evidence.
- Configured fleet capacity is not measured throughput. A release deployment
  does not automatically requalify RTC/TURN, all architectures or all game modes.

## Entry points

| Work | Maintained entry |
| --- | --- |
| Product change | [Specification map](implementation-plan.md), then scoped checks |
| AI intake and operations | [Architecture](autonomous-development.md), [operations](multica-operations.md) |
| Source delivery | [Confirmed public merge](autonomous-development.md#public-merge-and-source-delivery) |
| Release | [Release procedure](multica-release.md) |
| Production upgrade | [Deployment procedure](../deploy/home/README.md) |

Keep candidate/check identities and remaining actions on the canonical native
task. Keep logs and operator paths outside source control. Finalize version and
release notes before freezing a candidate; a subsequent source commit needs its
own matching qualification.
