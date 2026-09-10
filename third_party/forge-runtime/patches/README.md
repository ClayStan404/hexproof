# Hexproof downstream Forge host patch

This directory contains the complete local delta to the exact Manabrew and
Forge revisions in `manifest.json`. The patch applies to Manabrew's Java host,
not the Forge rules implementation. Upstream license texts and notices remain
in the runtime package. The upstream notices describe `forge-harness/` as GPL,
but the top-level `LICENSE.md` states that Manabrew's own code and built artifacts
are AGPL-3.0-or-later. Do not interpret the narrower notice as an exemption from
the top-level license: treat the harness artifact as AGPL-3.0-or-later and preserve
both statements and full license texts. The vendored Forge tree remains GPL.
Hexproof's helper and regression sources are GPL-3.0-or-later.

Patch revision 2 retains the revision 1 fixes:

- Cross-thread snapshots: only the game thread traverses Forge's mutable graph.
  It publishes immutable, individually redacted views for each player and the
  public spectator at a decision boundary and after the final outcome. RPC
  readers reuse a complete publication. An out-of-turn concession also republishes
  when the same pending prompt is resumed; idle polling does not rebuild views.
- A game-thread failure replaces the stale prompt with a stable RPC failure.
  The Hexproof server can then abort the failed rules game explicitly.
- Abort requests finalize the game on its own thread, not on the RPC reader.
- The host's requested starting life overrides the variant default, preserving
  20-life Duel Commander and 40-life multiplayer Commander.

Revision 2 also adds:

- An optional private starting-player index and public starting-player metadata
  so BO3 next games and host restarts retain the Hexproof match contract.
- Identity-free face-down casting previews and stack entries, and a distinct
  private face-down cast label. A face-down card's printing is not public.
- A source-built XMLPull API reactor dependency with the same public/protected
  API signatures and constants as the replaced binary. The existing MXParser
  and XStream implementations remain unchanged; their behavior is checked by
  `../XmlDependencyRegressionTest.java` against the final packaged JAR.

`build.sh` verifies the manifest pins and patch SHA-256 before checkout, refuses
staged/untracked edits or any tracked delta other than this exact patch, and
validates the Forge submodule independently. A previously patched checkout is
reused without resetting it. A changed patch/pin with a modified old checkout
requires a separate clean `HEXPROOF_FORGE_SOURCE_DIR`; owner edits are never
discarded. An exact reverse-application check confirms an already applied patch.
Revision switches also refuse to overwrite ignored files that become tracked
upstream. Both the harness and an initialized Forge submodule use this guarded
checkout, with implicit submodule recursion disabled.

After the upstream build and package-resource fixes, the build compiles and runs
`HexproofSessionRegressionTest.java` against the **packaged JAR and resources**
using an isolated temporary Java profile. These real games cover requested life,
player/spectator privacy, cached idle reads, three four-player concurrent
concession sequences, repeated-prompt publication, terminal winner, waiting-game
abort, explicit two/four-player starting positions, real face-down spell
publication, and intentional failure propagation. The expected invalid-action stack
trace is marked `[hexproof-test]`; it is not a spontaneous engine failure.

Run the source-management safety regressions without building Forge:

```sh
node --test third_party/forge-runtime/patches/source.test.mjs
```

To advance the upstream pin or change the patch, rebase it in a separate source
checkout, update its full-index diff and SHA-256 in `manifest.json`, and advance
`HEXPROOF_FORGE_PATCH_REVISION` in `VERSIONS.env` when behavior changes. Run both
these packaging regressions and Hexproof's real-engine conformance tests. Do not
treat upstream card-coverage counts as conformance of every card or mechanic.

This directory and `VERSIONS.env` are copied into every runtime archive so the
exact downstream sources, validation procedure, and provenance accompany the
binary. The archive filename continues to use the pinned Manabrew revision;
runtime identity additionally includes the downstream patch revision.
