# Client server directory

The client loads an operator-managed JSON catalog over HTTPS. It stores the
last valid catalog locally and ships a bootstrap list for first launch or
network outages. Users can always enter a custom WebSocket address.

## Bootstrap and release builds

Real endpoints remain ignored deployment data. For a local build, copy
`servers.example.json` to `servers.json` and replace the example directory
origins and server URLs. CMake prefers `servers.json`; clean checkouts use the
example. An explicit build can set
`-DHEXPROOF_SERVER_DIRECTORY_FILE=/absolute/path/to/servers.json`.

Release workflows validate the complete document from the Actions secret
`HEXPROOF_PUBLIC_SERVERS_JSON`. This secret supplies both the directory origins
and the fallback list. It must be migrated to schema 2 before releasing the
online-directory client. Existing installed clients need one client update to
use online discovery; later catalog changes do not require a rebuild.

## Catalog contract

```json
{
  "schemaVersion": 2,
  "revision": 1,
  "directoryUrls": [
    "https://directory.example/hexproof/servers.json",
    "https://mirror.example/hexproof/servers.json"
  ],
  "servers": [
    {
      "id": "server-1",
      "name": "Server 1",
      "sponsor": "Example sponsor",
      "url": "wss://server-1.example/ws",
      "forge": false
    },
    {
      "id": "server-2",
      "name": "Server 2",
      "url": "wss://server-2.example/ws",
      "forge": true
    }
  ]
}
```

- Increment `revision` whenever changing the document; keep IDs stable when
  renaming or reordering nodes. The client rejects older revisions and changed
  entries at the same revision. Zero to 32 entries are supported; an empty list
  intentionally retires all public entries without disabling custom addresses.
- Entries require unique `id` and URL, a nonempty `name`, and boolean `forge`.
  `sponsor` and up to eight `legacyUrls` are optional. A legacy URL migrates a
  saved endpoint only during startup, preserving the previous local behavior.
- The directory is at most 64 KiB. Up to four HTTPS origins are tried in order,
  with a five-second deadline per origin. Redirects stay on the same origin.
  Public server URLs require WSS without credentials, query or fragment;
  loopback HTTP/WS is allowed for isolated development.
- Sources come from the bootstrap, never from a downloaded replacement. TLS
  authenticates the operator; there is no separate account or registry service.
  A catalog operator can change offered endpoints, but refresh never moves an
  active connection or its reconnect credentials to another endpoint.
- Opening the connection screen requests a refresh, throttled to once per five
  minutes. **Refresh list** bypasses this interval. Latency probes run separately
  every five seconds. Selection follows stable IDs; a removed selection is
  cleared and requires an explicit new choice.
- Server Forge labels initially use the catalog. The separate player-hosting,
  direct-connection and migration capabilities start unknown. Successful health
  probes or version-matched welcomes update that exact URL's observed values
  for the current process, including custom endpoints. Unknown player-hosting
  support must not be labelled manual-only merely because `forge` is false.
- Valid updates are saved atomically under the application's local data
  directory, scoped by the bootstrap origins. A fetch failure retains the
  current catalog. An absent, invalid, or outdated cache uses the bootstrap.

## Live capability discovery

The existing HTTP(S) `/healthz` response retains its plain `ok` body/status and
adds a noncached `X-Hexproof-Capabilities` header:

```json
{"forge":false,"playerHosting":true,"directPeer":true,"hostMigration":true}
```

The client accepts at most 1 KiB and requires all four known fields to be
booleans. Missing, oversized or invalid headers leave previous values intact;
older servers remain compatible. A welcome received during an in-flight probe
takes precedence over that probe. Catalog refresh cannot overwrite observations.
These are supported modes, not available room slots or local runtime readiness.
No runtime paths, engine identities or player data are published. This leaves
schema 2 catalog files compatible with installed clients; no extra catalog
fields or directory publication is needed when enabling these server features.

## Local configuration and testing

`HEXPROOF_SERVER_DIRECTORY_FILE` at runtime selects a local bootstrap file.
Schema 1 remains supported for local compatibility, with unknown Forge status
and no online sources. `HEXPROOF_SERVER_n_URL` overrides a numbered entry and
disables online replacement. `HEXPROOF_SERVER_DIRECTORY_URL` explicitly sets a
single test origin (empty disables requests); `HEXPROOF_SERVER_DIRECTORY_CACHE`
selects a test cache file (empty disables disk caching). A local schema 2 file
may supply its own `directoryUrls`.

Operators publish changes using `deploy/publish-server-directory.py` in the
private deployment repository. See `docs/server-directory.md` there for the
maintained fleet and publication procedure. Public forks can serve the same
static JSON with their own HTTPS host. Endpoint deployment data is observable
in the client and network traffic, not confidential.
