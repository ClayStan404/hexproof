# Official Forge runtime source package

Distribute the matching `hexproof-forge-source-<revision>-adapter<N>.tar.gz`
alongside the runtime archive. `SOURCE.json` identifies its exact filename,
SHA-256, official Forge revision, native adapter revision and reviewed native patch.
The adjacent `.sha256` file covers both archives. A URL or patch alone is not
this complete source package.

## Contents and rebuild

The source archive contains:

- `forge/`: the complete official pinned Git tree, with the reviewed native patch
  already applied. Adapter revision 2 includes GUI metadata/profile hooks,
  Backup Plan's unused-hand shuffle, and narrow multiplayer decision/priority
  lifecycle fixes. These downstream core changes are preserved explicitly.
- `hexproof-build/`: the exact native Java host, patch, pin, build/package scripts
  and regression sources used for the runtime.
- `third-party/maven/`: preserved source JARs and POMs for every code-bearing
  external runtime dependency. Empty conflict-avoidance carriers explicitly
  preserve their exact metadata-only JAR and POM.
- `third-party/upstream/`: complete pinned XMLPull API, LZ4 Java/JNI and native
  LZ4 source trees, Netty native build inputs and its optional JNI utility.
- `SOURCE-MANIFEST.json`: inventory, source hashes, dependency coordinates and
  exact runtime dependency binary hashes.

After extracting the source archive, with Python 3.12+, JDK 21+, Maven 3.8.1+
(as required by the pinned upstream POM), and Bash installed:

```sh
cd hexproof-forge-source
bash hexproof-build/build.sh --from-source "$PWD" --output "$PWD/../forge-rebuild-output"
```

The verified source is copied into a new build directory. Keep output outside
that preserved package. This path does not require an upstream Git checkout,
Git network access, Node.js or Rust. Maven may download its declared build
plugins and dependency binaries; their runtime graph and binary hashes must
match the source manifest. This is source preservation and a rebuild workflow,
not an offline toolchain image. The packaged runtime copies all card/resources
and runs from a relocated extracted directory with no build-tree symlinks.

The original `xmlpull:xmlpull:1.1.3.4a` binary has no available exact source
artifact. Standalone packaging explicitly replaces it with the four unmodified
original XMLPull 1.1.3.4b API classes compiled from the pinned full official
source. It does not mislabel that tree as source for the old binary. The build
checks public/protected API signatures and constants and runs real MXParser
provider and XStream read/write regressions. Maven's cached original binary is
never modified. The replacement JAR is a separate deterministic build artifact.

LZ4's Maven sources omit JNI and compression sources. Its preserved full tree
uses the separately archived `lz4-native` gitlink at `src/lz4`; the manifest
records exact mounts, revisions and checksums. Netty's preserved full tree
adds native configure/Makefile inputs to the source JARs; `netty-jni-util`
preserves its optional native build dependency. The runtime also retains
`DEPENDENCIES.json` and individual `THIRD-PARTY-LICENSES/` notices.

Archive ordering, owners, timestamps and gzip metadata are normalized. The same
source/dependency/build-script bytes reproduce the source archive. Forge Maven
JARs may carry build timestamps, so byte-identical runtime archives are not
claimed. Rebuild verification locks external dependency bytes, official source,
host source, patch and resources, then runs real-engine regressions and a cold
start on the packaged classpath.

## License and distribution

Preserve Forge's GPL-3.0-or-later notices, complete license text, all dependency
source notices and Hexproof modification notices. Card content and trademarks
retain their separate upstream notices. Before distributing a runtime, make its
exact corresponding source archive durably available alongside it, including
older deployed versions. Local build verification does not publish artifacts or
enable Forge on any server.
