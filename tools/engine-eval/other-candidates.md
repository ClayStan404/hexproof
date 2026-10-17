<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 Hexproof contributors -->
# Additional rules-engine inventory

Discovery date: 2026-09-09. This inventory prevents a small initial shortlist
from being mistaken for an exhaustive search or a final winner. Source/README
claims below are not runtime qualifications. Unknown candidates are not
eliminated. The shared laboratory separately evaluates Forge, XMage,
Manabrew, Phase, mtg-forge-ts, Magarena, and Wagic.

The [empirical follow-up](../../docs/engine-thorough-results.md) records actual
execution beyond the initial source inventory. Additional-engine probes and
upstream suites remain distinct from the matched seventeen-case contract.

| Candidate and pinned upstream | Evidence and current disposition |
| --- | --- |
| [Argentum](https://github.com/wingedsheep/argentum-engine/tree/3f46367d87c88bcf156a843a9e69fd29e1693872) | Kotlin/JDK 21 standalone engine; actual full seventeen-case follow-up and Prepare probes now run. Real shuffle exposes ordered stable library IDs. Several missing catalog cards use explicitly declared SDK data fixtures, not repaired rules. See `argentum/README.md` for exact coverage and the additional Prepare admission finding; native Hexproof integration is not implemented. |
| [Majik](https://github.com/bg9m9r/majik/tree/d7ada5fe8327fe5e638b28dccc801dbe3281ffad) | Installed native .NET 10 and actually ran declared core/API/bot/server suites: 30,105 passes, four skips in completed projects. Full bot-integration execution timed out; a modal-casting exception reproduced in two of three Dimir mirror reruns. Two actual-catalog reference bot games naturally ended. `GameFacade`/server hosting remains two-player; lower-level multiplayer unqualified. See `majik/README.md`. |
| [jMagic](https://github.com/jmagicdev/jmagic/tree/40e573f8e6d1cf42603fd05928f42e7080ce0f0d) | Declared JDK 8 Maven engine/cards/test-common/integration reactor actually built and ran: 337 passes, five skips, no failed/error cases. These upstream rules fixtures are not the shared seventeen. Modern data maintenance and missing source-license grant remain separate gates, not inferred rule failures. See `jmagic/README.md`. |
| [Incantus](https://github.com/Incantus/incantus/tree/34487c2be3ba12a72f8dcba186d247a2b07677e8) | Actual Python 3 import fails on legacy Python 2 syntax. No appropriate native Python 2 package/runtime or bundled card DB was found. An isolated official PyPy 2 fallback was proposed for owner approval; it has not been installed. No shared gameplay PASS is inferred from inspecting the historical implementation. |
| [mtghub-engine](https://github.com/mtghub-ru/mtghub-engine/tree/b4214c1be2c253a253e95ce1d96d282dc37d85b1) | SBCL actually ran; ASDF loading is missing CL-MATCH, but independent Lisp form inspection also confirms four central rules files contain zero forms and no implemented game loop at this pin. Research scaffold, not excluded solely because a dependency is absent. |
| [Witchcraft / python-mtg](https://github.com/yevbar/witchcraft/tree/6b703960979b801882db8bf054ac125aed1811f6) | Built declared pinned Souffle and verified actual CI data bytes. Real native API probes observe an opening-draw discrepancy, ordered library-ID exposure, and premature four-player game-over. These supplemental failures are not an exhaustive shared-suite result. Separate root/package licenses still require artifact-scoped adoption review. |
| [Hyperdraft](https://github.com/discordwell/Hyperdraft/tree/1e17b41f05a134b33ebcc00f93b84be14a0a3363) | Installed declared isolated dependencies and actually drove core rules and hidden-view probes. Four-player elimination leaves an owned Bears public; the real concede route ends the entire four-player session after one departure. Forty-three selected upstream regressions also passed; they do not substitute for the shared suite or erase those failures. |
| [DeepScry](https://deepscry.net/) | Official site describes an experimental Rust engine, Forge-derived card data and head-to-head WebSocket play. No public source repository was established from that page in this pass. Source access, reproducible local build, four-player support and licensing remain unverified. Its performance claims are not imported into this comparison. |

Manual tabletop programs, card catalogs, deck trackers, and API aggregators
are not alternative rules engines. Cockatrice, Drawspell, and Shuffle Up
and Play therefore do not enter the
rules qualification matrix. Projects that wrap Forge or XMage (for example
Commander AI Lab and mage-bench) may offer useful adapters, but are not
independent rules implementations and must not count as additional engine
votes.

## Pinned source-license inventory

These are observed source-license documents, not legal advice or clearance
of card art, Oracle text, trademarks, generated data, or dependency licenses.
`PRESENT` means the actual license text was found; it is not a legal
compatibility or redistribution verdict. Missing/ambiguous evidence is explicit.

| Candidate | Evidence status and primary text |
| --- | --- |
| Argentum | PRESENT: [root LICENSE](https://github.com/wingedsheep/argentum-engine/blob/3f46367d87c88bcf156a843a9e69fd29e1693872/LICENSE), MIT, copyright 2026 Vincent Bons; separate MTG notice follows. Read from the pinned local clone. |
| Majik | PRESENT: [LICENSE](https://github.com/bg9m9r/majik/blob/d7ada5fe8327fe5e638b28dccc801dbe3281ffad/LICENSE), Apache-2.0. [NOTICE](https://github.com/bg9m9r/majik/blob/d7ada5fe8327fe5e638b28dccc801dbe3281ffad/NOTICE) identifies copyright 2026 Brett Gamerson and separately discusses embedded card data and third-party components. Read from the pinned local clone. |
| jMagic | UNKNOWN at this pin: recursive tracked tree contains no filename matching LICENSE/COPYING/NOTICE; source/README/POM text search found no explicit license grant. [Pinned tree](https://github.com/jmagicdev/jmagic/tree/40e573f8e6d1cf42603fd05928f42e7080ce0f0d) and [README.txt](https://github.com/jmagicdev/jmagic/blob/40e573f8e6d1cf42603fd05928f42e7080ce0f0d/README.txt) are evidence of the inspected scope, not permission inferred from public hosting. |
| Incantus | PRESENT, custom-titled [LICENSE](https://github.com/Incantus/incantus/blob/34487c2be3ba12a72f8dcba186d247a2b07677e8/LICENSE): MIT/X11-style permission/warranty text plus a no-advertising-name clause. Do not flatten it to a bare MIT identifier without reviewing the extra clause. |
| mtghub-engine | PRESENT: [LICENSE](https://github.com/mtghub-ru/mtghub-engine/blob/b4214c1be2c253a253e95ce1d96d282dc37d85b1/LICENSE) is GNU GPL version 2 text. Whether the project's grant is version-2-only or allows later versions remains unverified; generic license-appendix examples are not a project-specific grant. |
| Witchcraft / python-mtg | PRESENT, distinct scopes: [root LICENSE](https://github.com/yevbar/witchcraft/blob/6b703960979b801882db8bf054ac125aed1811f6/LICENSE) is UPL-1.0; [packages/mtg/LICENSE](https://github.com/yevbar/witchcraft/blob/6b703960979b801882db8bf054ac125aed1811f6/packages/mtg/LICENSE) is MIT. Resolve the exact artifacts, native runtime and bundled dependency scopes before adopting the package; these are actual separately scoped texts, not necessarily a contradiction. |
| Hyperdraft | README-ONLY: [pinned README](https://github.com/discordwell/Hyperdraft/blob/1e17b41f05a134b33ebcc00f93b84be14a0a3363/README.md#license) says MIT, but the inspected root tree shows no full license file. Full source-grant text remains unverified; no broad redistribution clearance is inferred. |
| DeepScry | UNKNOWN: public source repository and corresponding license text were not established from the [official site](https://deepscry.net/). |

## Follow-up that preserves fairness

Apply the same immutable pin, build provenance, external-decision, hidden-view,
four-player continuity, and frozen scenario checks before promoting any
additional candidate. A project's age, technology choice, self-reported test
count, or small card catalog can motivate investigation; none is a substitute
for a tested requirement. The current evidence supports a bounded shortlist,
not the statement that every MTG rules project has been fully compared.
