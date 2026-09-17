# Client-bundled native adapter

`build-overlay.py` compiles the current Hexproof native host and every upstream
Java class touched by the reviewed patch. It verifies the immutable adapter 2
binary and complete source archives, reverses that archive's old patch in a
disposable tree, and applies the current patch. The resulting small JAR loads
before the base JAR. Unchanged Forge code, resources and dependencies come from
the pinned base distribution. This preserves its source-backed XMLPull
replacement and other dependency notices.

The source identity covers every native Java source, the upstream pin and patch.
`apps/server/internal/forgehost/identity.go` must match
`python3 third_party/forge-runtime/build-overlay.py --identity`; tool tests and
the helper builder enforce this. The helper embeds the actual JAR checksum and
verifies both its metadata and private copy before starting Java. Missing or
mismatched files fail preparation instead of falling back to the old adapter.

Normal client builds need JDK 21+, Python 3.12+ and Git in addition to Qt/Go.
There is no Maven resolution. Initial build inputs total about 446 MiB; the
content-addressed cache is `build/forge-overlay/downloads`. `--base-archive` and
`--source-archive` accept predownloaded files, with the same mandatory checksums.
Only the small overlay ships beside `hexproof-forge-host`; players prepare the
large base and platform Java payload on demand. Java is not required to join.

## Complete source distribution and rebuild

Release quality gates produce `hexproof-forge-overlay-source.tar.gz`, which
contains the complete pinned source/dependency archive, current host/patch,
build recipe and metadata. It must accompany client binaries in every release.
The JAR also includes the exact modified Java files and Forge license; those
files alone are not the complete corresponding-source package.

From the extracted `hexproof-forge-overlay-source` directory:

```sh
python3 third_party/forge-runtime/build-overlay.py \
  --source-archive base-source.tar.gz --output build/forge-overlay
```

The build may download the pinned base binary archive. Supply `--base-archive`
to use an existing verified copy. Its corresponding complete sources and
original build recipe are in `base-source.tar.gz`; this path never fetches a
moving branch or silently updates card resources/dependencies. Output stays
outside preserved inputs.

To create the complete source bundle from a repository checkout:

```sh
python3 third_party/forge-runtime/build-overlay.py \
  --source-output build/packages/hexproof-forge-overlay-source.tar.gz
```
