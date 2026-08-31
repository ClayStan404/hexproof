# Forge runtime source and build

Hexproof rules rooms use Forge through Manabrew's maintained headless harness.
`VERSIONS.env` pins both the harness repository and its Forge fork gitlink.
They must move together; changing only one can produce runtime-only class or
card-script failures.

Build the runtime from the repository root:

```sh
./third_party/forge-runtime/build.sh
```

The build requires Git, Node.js, Rust/Cargo, JDK 18–21, Maven, and `tar`. It
checks out source under `build/forge-runtime/source`, runs upstream protocol
generation and harness tests, and writes a versioned runtime archive under
`build/forge-runtime/`. Override those locations with
`HEXPROOF_FORGE_SOURCE_DIR` and `HEXPROOF_FORGE_OUTPUT_DIR`.
Packaging also restores Forge's language bundles and deck-generation matrices,
which the upstream desktop staging allow-list omits, and restores Forge's
custom Tinylog writer registration after the fat-JAR assembly. It cold-starts
the packaged Java runtime and rejects known initialization errors before
creating the archive.

After extracting the archive, enable the runtime on the Hexproof server with:

```sh
./tools/run-local-forge-server.sh
```

The local launcher derives the pinned versioned runtime directory, sets the
three `HEXPROOF_FORGE_*` variables, and passes any arguments directly to the
server. Override `HEXPROOF_FORGE_LOCAL_ROOT` when extracting somewhere other
than the default `build/forge-runtime/local-<revision>/hexproof-forge-runtime`.

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
3. Run this build from a clean source checkout.
4. Run Hexproof's Forge adapter tests and a rules-mode conformance game.
5. Preserve the upstream license texts and notices in every runtime package.

Do not commit the checkout, JAR, card scripts, generated protocol sources, or
runtime archive. They belong under `build/` and are reproduced from the pinned
sources.
