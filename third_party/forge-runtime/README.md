# Forge runtime source and build

Hexproof rules rooms use Forge through Manabrew's maintained headless harness.
`VERSIONS.env` pins both the harness repository and its Forge fork gitlink,
plus the Hexproof host-patch revision in `patches/`.
They must move together; changing only one can produce runtime-only class or
card-script failures.

For local testing, build the server, prepare the runtime, and start it with:

```sh
./tools/run-local-forge-server.sh --prepare -port 57321
```

This does not install packages or change remote services. Subsequent launches
can omit `--prepare`. An existing mismatched runtime is preserved: select a
fresh `HEXPROOF_FORGE_LOCAL_ROOT` to prepare the new version.

To build only the separate runtime archive from the repository root:

```sh
./third_party/forge-runtime/build.sh
```

The build requires Git, Python 3.12+, Node.js, Rust/Cargo, JDK 21, Maven 3.8.1+,
GNU tar, and coreutils. It
checks out source under `build/forge-runtime/source-<revision>-patch<N>`, verifies and applies the
versioned host patch, runs upstream protocol generation and harness tests plus
the real-engine regression in `patches/`, and writes a runtime archive under
`build/forge-runtime/`. Override those locations with
`HEXPROOF_FORGE_SOURCE_DIR` and `HEXPROOF_FORGE_OUTPUT_DIR`.
Packaging also restores Forge's language bundles and deck-generation matrices,
which the upstream desktop staging allow-list omits, and restores Forge's
custom Tinylog writer registration after the fat-JAR assembly. It cold-starts
the packaged Java runtime and rejects known initialization errors before
creating the archive.
The source manager accepts only the exact pinned clean or already-patched
state. It refuses to overwrite tracked, untracked, staged, or colliding ignored
user files. See `patches/README.md` for source-safety checks and patch provenance.

After extracting the archive, enable the runtime on the Hexproof server with:

```sh
./tools/run-local-forge-server.sh
```

The local launcher derives the pinned versioned runtime directory, sets the
three `HEXPROOF_FORGE_*` variables, and passes any arguments directly to the
server. Override `HEXPROOF_FORGE_LOCAL_ROOT` when extracting somewhere other
than the default
`build/forge-runtime/local-<revision>-patch<N>/hexproof-forge-runtime`.

The server probes the configured runtime at startup. Internally it launches:

```sh
java -jar /path/to/forge-harness.jar \
  --interactive-server \
  --forge-home /path/to/forge-gui
```

The Java runtime is optional. A Hexproof server without it can host manual
rooms but cannot create Forge rules rooms.

## Updating

1. Advance Manabrew intentionally and read its Forge gitlink.
2. Update both revisions in `VERSIONS.env`.
3. Review/rebase the downstream patch and update its checksum and patch revision.
4. Run this build from a clean source checkout and run the real-engine Go
   conformance suites described in `docs/rules-backend-evaluation.md`.
5. Preserve the upstream license texts and notices in every runtime package.

Do not commit the checkout, JAR, card scripts, generated protocol sources, or
runtime archive. They belong under `build/` and are reproduced from the pinned
sources.

The default source checkout and local runtime paths include both the upstream
revision and downstream patch revision. An upgrade leaves previous checkouts
and runtime packages intact. Explicit `HEXPROOF_FORGE_SOURCE_DIR` overrides
remain subject to the strict clean/managed-patch checks; owner edits are never
discarded or replaced to make an upgrade succeed.

## Matching source and optional architecture checks

Every successful build also produces
`hexproof-forge-source-<Manabrew revision>-patch<N>.tar.gz` and a checksum file
covering both archives. The runtime contains `SOURCE.json` linking the exact
source archive by hash. Source collection is mandatory: missing dependency
source fails packaging. The source archive includes both complete pinned Git
trees, the applied downstream change, generated protocol inputs, build scripts,
and locally preserved sources/POMs for the resolved runtime dependencies.
See [SOURCE-README.md](SOURCE-README.md) for contents, rebuilding without
upstream Git access, reproducibility limits, and the conservative handling of
the contradictory upstream harness-license notices.

The separate **Forge runtime (optional)** GitHub workflow runs only when
explicitly dispatched. It builds and tests on native Linux `amd64` and `arm64`
runners, including packaged cold start and the opt-in Go real-engine suite.
It does not publish a release, deploy, restart a service, or change the normal
CI/release/deployment defaults. Those defaults still omit Forge. CI artifacts
are development evidence, not a durable public source offer.
