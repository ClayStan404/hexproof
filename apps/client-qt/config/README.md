# Client server directory

Hexproof embeds exactly five operator-managed WebSocket endpoints in
each client build. Real endpoint values are deployment data and are not tracked
in Git. The fifth entry is the pre-release test server shown with a distinct
localized label.

For a local build, copy `servers.example.json` to the ignored `servers.json`
and replace all five example URLs:

```sh
cp apps/client-qt/config/servers.example.json \
  apps/client-qt/config/servers.json
cmake -S apps/client-qt -B build/client-qt -G Ninja
cmake --build build/client-qt
```

CMake automatically prefers the local `servers.json`; a clean checkout falls
back to `servers.example.json` so ordinary CI and forks remain buildable. An
explicit build may instead pass:

```sh
cmake -S apps/client-qt -B build/client-qt -G Ninja \
  -DHEXPROOF_SERVER_DIRECTORY_FILE=/absolute/path/to/servers.json
```

Each server object requires `url` and may include `legacyUrls`. A persisted URL
matching a legacy entry migrates to that object's current URL:

```json
{
  "schemaVersion": 1,
  "servers": [
    {
      "url": "wss://server-1.example/ws",
      "legacyUrls": ["ws://retired-server-1.example:57320/ws"]
    },
    {"url": "wss://server-2.example/ws"},
    {"url": "wss://server-3.example/ws"},
    {"url": "wss://server-4.example/ws"},
    {"url": "wss://server-1.example/test/ws"}
  ]
}
```

Release jobs create a temporary file from the repository Actions secret
`HEXPROOF_PUBLIC_SERVERS_JSON` and pass it through the same CMake option. The
secret value must contain the complete JSON document above. It is never needed
by pull-request or ordinary CI builds.

This keeps deployment values out of the source tree and workflow logs. It does
not make the endpoints confidential: a published client must contain and
connect to them, so they remain observable in release binaries and network
traffic.
