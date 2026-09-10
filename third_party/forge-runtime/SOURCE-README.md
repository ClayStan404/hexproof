# Forge runtime source package

Distribute the matching `hexproof-forge-source-<revision>-patch<N>.tar.gz`
alongside the runtime archive. The runtime's `SOURCE.json` records that exact
source archive's filename, SHA-256, upstream revisions, and downstream patch
revision. The adjacent `.sha256` file covers both archives. An upstream GitHub
URL, a version number, or the patch alone is not this source package.

## Contents and rebuild

The source package contains:

- `manabrew/`: the complete pinned Manabrew Git tree, with the complete pinned
  Forge submodule populated and the exact Hexproof changes already applied;
- the generated protocol TypeScript inputs from the same build, plus their
  original Rust definitions, generator, and Cargo lockfile;
- `hexproof-build/`: the exact build/package scripts, version file, patch
  manifest, patch text, and real-engine regression used for this runtime;
- `third-party/maven/`: locally preserved source JARs and POMs for every
  code-bearing external dependency in the resolved runtime classpath. Empty
  Maven conflict-avoidance carriers preserve their inspected metadata-only JAR
  and POM, explicitly identified as `metadata-only` in the manifest;
- `third-party/upstream/`: complete pinned source archives for the original
  XMLPull API, LZ4 Java JNI/build sources and its exact native LZ4 gitlink,
  Netty's native build scripts, and its exact optional JNI utility C dependency;
- `SOURCE-MANIFEST.json`: hashes of every preserved source file and symlink,
  exact dependency coordinates, binary hashes, and source origins/checksums.

After extracting the source archive, with Git, Python 3.12+, Node.js, JDK 21,
Maven 3.8.1+, Bash, GNU tar, and coreutils installed:

```sh
cd hexproof-forge-source
HEXPROOF_FORGE_OUTPUT_DIR="$PWD/../forge-rebuild-output" \
  bash hexproof-build/build.sh --from-source "$PWD"
```

The supplied tree is verified and copied to a fresh build directory; the
original source package is not modified. Keep the output outside that source
package. This path does not clone/fetch Git or
require Rust/Cargo. It regenerates Java protocol classes from the preserved
TypeScript, compiles the same Maven reactor, checks the resolved runtime
dependencies against the source manifest, runs the upstream and Hexproof
real-engine regressions, and cold-starts the packaged runtime.

This is a source-preservation/rebuild workflow, not a fully offline toolchain
image. Maven may still download its unmodified general-purpose build plugins,
their dependencies, and runtime dependency binaries from their declared
repositories. Runtime dependency versions and binary hashes must match the
source manifest; a changed resolution fails. The source for those runtime
dependencies is preserved locally in this archive. To modify the protocol's
preferred Rust definitions, install a compatible Rust toolchain and regenerate
with the included Cargo lockfile and generator before rebuilding Java.

The old `xmlpull:xmlpull:1.1.3.4a` binary has no published source artifact and
its original download is no longer available. The hosted harness instead uses
a local Maven reactor module built from the four unmodified official XMLPull
1.1.3.4b API classes. The complete source tree and original notices are preserved
at the exact revision in `hexproof-build/dependency-sources.json`. We do not call
that tree the source of the old 1.1.3.4a binary. Packaging compares all four
public/protected APIs and constants against the old binary's recorded signatures,
and runs real parser-provider and XStream read/write regressions. Existing
MXParser and XStream versions and provider selection stay unchanged.

LZ4's Maven source JAR omits JNI and native compression source. Extract the
archived `lz4-java` tree and populate its `src/lz4` directory with the root
contents of the separately archived `lz4-native` gitlink tree. Their exact mount,
revisions, origins and checksums are in `SOURCE-MANIFEST.json`. Netty's native
source JARs already include their C/H files and are preserved with its Java
source JARs and POMs. The full pinned Netty tree preserves the native
configure/Makefile inputs, and `netty-jni-util` preserves the optional C build
dependency selected by that Netty parent's dependency management.

The runtime also carries `DEPENDENCIES.json` and `THIRD-PARTY-LICENSES/`, with
separately retained license/notice files from the resolved JARs and source JARs
instead of relying on colliding fat-JAR `META-INF/LICENSE` entries.

Archives normalize source entry ordering, owners, times, and gzip metadata.
The same source bytes, dependency bytes, and build scripts reproduce the source
archive. We do not claim byte-identical JARs: upstream ZIP entries and Maven
build metadata can contain build-time timestamps.

## License and distribution boundary

Keep the upstream full license texts, copyright notices, POMs, dependency
source notices, and Hexproof modification notices intact. The pinned
Manabrew `LICENSE.md` describes its own code and built artifacts as
AGPL-3.0-or-later, while its `THIRD-PARTY-NOTICES.md` describes the Java harness
as GPL-3.0-or-later. These upstream statements conflict. Packaging preserves
both statements and both full license texts; it does not resolve the conflict
or claim a GPL-only exception for the hosted harness. Forge remains covered by
its upstream GPL-3.0-or-later notices. Card content and trademarks have separate
upstream notices and are not newly licensed by Hexproof.

Before public distribution or network hosting, arrange free, durable access to
the exact corresponding source archive and a prominent source link for the
users of that modified runtime. Keep the source available with the matching
binary, including older deployed patch revisions. A private CI artifact with
login requirements or expiring retention is not a public source service.
This tooling creates and verifies files locally; it does not publish them,
make a legal determination, or enable Forge on any server.
