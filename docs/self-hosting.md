# Self-hosting the Hexproof room hub

Hexproof uses one native WebSocket endpoint at `/ws` plus a plain HTTP health
check at `/healthz`. Independent hubs use display names and room codes, without
a browser UI. Connected native clients can also browse public room metadata.
Optional official-server identity follows the separate
[account contract](accounts.md).

## Build and run locally

From the repository root:

```sh
(cd apps/server && go test ./...)
mkdir -p build/server
(cd apps/server && CGO_ENABLED=0 go build -trimpath \
  -o ../../build/server/hexproof-server ./cmd/hexproof-server)
./build/server/hexproof-server \
  -bind 127.0.0.1 \
  -port 57320 \
  -retention-dir ./build/server/retained
```

Connect a client to `ws://127.0.0.1:57320/ws`. Check health with:

```sh
curl http://127.0.0.1:57320/healthz
```

The server command defaults are suitable for a small home hub:

| Flag | Default | Purpose |
|------|---------|---------|
| `-reconnect-window` | `3m` | Hold a dropped player's seat and hidden state |
| `-hello-timeout` | `10s` | Require a new WebSocket to complete `session.hello` |
| `-retention-ttl` | `168h` | Expire operator-only match archives |
| `-retention-dir` | `data/retained` | Archive directory; empty disables storage |
| `-retention-max-files` | `512` | Maximum retained archive files |
| `-retention-max-bytes` | `536870912` | Maximum aggregate retained archive bytes |
| `-replay-page-size` | `50` | Maximum replay summaries returned per page |
| `-max-rooms` | `256` | Maximum live rooms |
| `-max-tournaments` | `64` | Maximum live and retained closed tournaments |
| `-max-connections` | `1024` | Maximum simultaneous WebSocket connections |
| `-max-message-bytes` | `1048576` | Maximum inbound WebSocket message |
| `-messages-per-second` | `60` | Per-connection inbound rate |
| `-replay-requests-per-minute` | `30` | Per-client-IP replay list/load rate |
| `-room-creates-per-minute` | `6` | Per-client-IP room creation rate |
| `-tournament-creates-per-minute` | `3` | Per-client-IP tournament creation rate |
| `-tournament-closed-ttl` | `24h` | Retention from completion/cancellation; ordinary viewers do not extend it |
| `-tournament-inactive-ttl` | `5m` | Reconnect grace after registration loses its last online organizer/participant |
| `-tournament-abandoned-ttl` | `5m` | Reconnect grace for running events without online organizers/players; existing pairing-room holds remain valid |
| `-password-joins-per-minute` | `20` | Per-client-IP protected-room join rate |
| `-max-concurrent-password-checks` | `8` | Maximum concurrent bcrypt checks |
| `-trusted-proxies` | loopback CIDRs | Proxies allowed to supply `X-Forwarded-For` |
| `-forge-harness` | `$HEXPROOF_FORGE_HARNESS` or empty | Path to `forge-harness.jar`; empty disables Forge rules rooms |
| `-forge-home` | `$HEXPROOF_FORGE_HOME` or empty | Matching Forge runtime home containing card scripts |
| `-forge-java` | `$HEXPROOF_FORGE_JAVA` or `java` | Java command used to launch the Forge runtime |
| `-max-forge-games` | `$HEXPROOF_FORGE_MAX_GAMES` or `1` | Maximum concurrent Forge slots, including startup, process cleanup, BO3 sideboarding, and restarts; positive integer required |
| `-peer-stun-servers` | `$HEXPROOF_PEER_STUN_SERVERS` or configured managed discovery endpoints | At most two comma-separated UDP `stun:host[:port]` URLs for optional player direct connections; empty disables STUN discovery |

Run `hexproof-server -help` for the installed binary's exact options.

The managed STUN defaults are `stun:47.122.120.151:3478` and
`stun:47.97.30.103:3478`. They provide address discovery, not TURN relay.
Hosting your own discovery endpoint requires allowing its UDP listening port
in both the host firewall and cloud security group. The room hub still supplies
signaling, authoritative confirmation and fallback relay. STUN configuration
does not enable player hosting; that remains an explicit `-allow-player-hosting`
option. See [STUN deployment](stun-deployment.md) for the maintained Coturn setup.

Forge is an optional server capability. Build and extract the pinned runtime as
described in the [runtime and corresponding-source guide](../third_party/forge-runtime/README.md), then pass both
`-forge-harness` and `-forge-home`. The server probes the runtime before it
accepts connections and advertises Forge room creation only after a successful
probe. Omitting both flags leaves all manual rooms available without Java.
Command-line values override the corresponding environment defaults. For a
persistent systemd installation, place all three variables in a service
drop-in; keep the harness and home paths on one matching extracted runtime.

Forge uses a dedicated JVM per game by default; `-forge-games-per-jvm` can
explicitly select supported shared workers. Player-hosted games remain dedicated.
See the [rules-engine contract](rules-engine.md#engine-process-contract)
for lifecycle and isolation requirements. The default capacity of one protects
small hubs from several simultaneous cold starts exhausting their memory.
Full capacity rejects only a new match with `server_limit`; manual games and
waiting rooms remain available. BO3 sideboarding holds the same match's slot
without keeping its finished JVM alive. Increase `HEXPROOF_FORGE_MAX_GAMES`
only after measuring simultaneous gameplay within the service's memory budget.
Include Java native memory, the Go hub, the OS, and any other services; Java's
`-Xmx` bounds its heap, not the entire process. A systemd `MemoryMax` alone
cannot prevent too many game processes from competing inside that limit.
Historical small-deck measurements are not capacity recommendations for a
different runtime, deck or host. Observe service memory/pressure and runtime
exits under the actual workload before increasing concurrency.

## Public TLS and `wss`

Keep the Go process bound to loopback and terminate TLS in a reverse proxy.
Clients should use `wss://your-host.example/ws`; do not expose an unencrypted
`ws://` endpoint to the public internet.

Minimal Caddy configuration:

```caddyfile
your-host.example {
    reverse_proxy /ws 127.0.0.1:57320
    reverse_proxy /healthz 127.0.0.1:57320
}
```

Minimal nginx location blocks inside an HTTPS server:

```nginx
location /ws {
    proxy_pass http://127.0.0.1:57320;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}

location = /healthz {
    proxy_pass http://127.0.0.1:57320;
}
```

The default trusted-proxy list accepts forwarded client addresses only from
loopback. If the reverse proxy connects from another address, pass its exact
CIDR with `-trusted-proxies`. Passing an empty value disables forwarded-header
trust. Do not trust a broad public network: a directly connected client could
otherwise forge its rate-limit identity. Forwarding chains are evaluated from
the trusted connection backwards, so an append-mode proxy does not accept a
client-supplied leftmost address as the rate-limit identity.

## Service and data permissions

Create a dedicated unprivileged service user and an operator-only archive
directory. The server release archive includes
`deploy/hexproof-server.service.in`; replace `@HEXPROOF_USER@`,
`@HEXPROOF_GROUP@`, `@HEXPROOF_BIN@`, and `@HEXPROOF_DATA_DIR@`, then install
the rendered unit with the operating system's normal systemd workflow. The
repository's `deploy/hexproof-server.service` (hostname-based hubs, run by the
operator login) and `deploy/hexproof-ip.service` (IP-based hub, dedicated
`hexproof` user with hardened sandboxing) are the owner-specific public-hub
units and are not shipped as reusable templates.

The retention directory is created with mode `0700`; archive files use
`0600`. Archives intentionally contain complete trust-server game state,
including deck lists, hands, libraries, and logs. Restrict backups and
operator access accordingly. Password hashes, resume credentials, and
transport connection IDs are not archived. Expired archives are removed at
startup and whenever a new archive is written. File-count and aggregate-byte
quotas evict the oldest archives first, and abandoned temporary files are
removed during the same cleanup. Malformed archives, unsupported schema
versions, missing required metadata, and files with trailing JSON data are
removed before quota accounting, so an invisible corrupt replay cannot evict a
valid match.

The WebSocket `replay.list` / `replay.get` endpoints remain available for
compatibility, though the current client no longer offers replay UI. Those
replies are generated server-side from each archive and
contain only public match metadata plus the public game log. They never return
the archive JSON, hidden zones, deck registrations, or pending sideboards.
Disabling retention with an empty `-retention-dir` also disables replay
availability.

Intentional `room.leave` frees a seat immediately. A network drop keeps the
membership for the configured reconnect window. The client presents an opaque
resume credential and receives newly generated role-specific snapshots; the
server never replays an old player's hidden projection to a different role.

## Release archive

On Linux, the repository can build a self-hosting archive:

```sh
./packaging/server/build-tarball.sh
```

The resulting archive under `build/packages/` contains the static Go binary,
service template, license, and this guide.

## Isolated test hub

An authorized test deployment uses an explicitly selected target from the private
operator inventory. Confirm that the target supports an isolated test service;
do not infer it from a historical host name. To prepare that service:

```sh
HEXPROOF_TEST_TARGET="$HEXPROOF_SELECTED_TEST_TARGET" ./deploy/deploy-test-server.sh
```

The helper detects the target architecture, builds the current local server or
uses `HEXPROOF_TEST_BINARY`, verifies the matching application version, and
transactionally activates the test unit and path-scoped nginx include. A failed
activation restores prior files; an identical deployment skips upload/restart.
`HEXPROOF_TEST_VERSION` can select the version of an explicitly supplied matching
binary. The test client must speak the same communication protocol; its application version may differ.

Test paths stay separate from production:

- binary: `/usr/local/bin/hexproof-server-test`;
- data: `/var/lib/hexproof-test/`;
- unit: `hexproof-test.service`;
- loopback listener: `127.0.0.1:57321`;
- public routes: `wss://47.97.30.103/test/ws` and
  `https://47.97.30.103/test/healthz`;
- player hosting enabled with bounded room bindings;
- server Forge disabled until a test-only runtime drop-in is explicitly installed.

These are the script's deployment paths, not confirmation that a test instance
is running. Publishing a test catalog entry is a separate operator action; see
[server directory operations](server-directory.md). Test deployment leaves the
production binary, unit and data unchanged. Source builds are permitted for
this isolated test workflow, rather than production release upgrades.

To enable Forge on an authorized test service, first deploy the test binary and
provide Java 21 on the selected target. Supply the verified pinned runtime/source pair:

```sh
HEXPROOF_FORGE_SCOPE=test HEXPROOF_TARGETS="$HEXPROOF_SELECTED_TARGETS" \
  HEXPROOF_FORGE_ARCHIVE=/absolute/path/to/pinned-runtime.tar.gz \
  HEXPROOF_FORGE_SOURCE_ARCHIVE=/absolute/path/to/pinned-source.tar.gz \
  HEXPROOF_FORGE_BUILD_IF_MISSING=0 ./deploy/deploy-forge-runtime.sh
```

Replace the example archive paths with the matching canonical pinned filenames
from the [runtime guide](../third_party/forge-runtime/README.md). Test scope
requires a configured test-capable target. It installs below `/var/lib/hexproof-test/forge-runtime/`,
configures `hexproof-test.service.d/forge-runtime.conf`, and restarts only the
test service. It verifies the paired archives, hashes and provenance before
activation. A failed activation restores the runtime selection and complete
drop-in. Ordinary test-binary updates retain an explicitly installed runtime.

Make the complete corresponding source archive identified by `SOURCE.json`
available before offering Forge over the network. The runtime guide and source
archive provide rebuilding instructions and notices; runtime deployment does
not publish the source or configure its download URL. Test service resource
limits belong to the effective unit/drop-in and are not a measured concurrency
guarantee. Verify the public welcome's Forge capability and a native game after
startup; `/healthz` alone does not exercise gameplay.

## Owner production release upgrades

Use [the production operator procedure](../deploy/home/README.md#production-release-upgrades)
and `deploy/deploy-release-server.sh` for maintained cloud and home nodes.
Always select **both targets and version explicitly** from the private operator
inventory. Invoke target groups separately when the deployment procedure requires
separate transactions. For example, with an already resolved target group/version:

```sh
HEXPROOF_TARGETS="$HEXPROOF_SELECTED_TARGETS" HEXPROOF_VERSION="$HEXPROOF_SELECTED_VERSION" \
  ./deploy/deploy-release-server.sh
```

Script defaults are not an operator target/version decision. An authorized unpublished draft also requires
`HEXPROOF_ALLOW_DRAFT=1`; that opt-in never publishes a release. The operator
procedure covers authenticated asset/checksum/attestation verification, baseline
checks, staging, activation, rollback and retained evidence.

Ordinary upgrades preserve installed configuration, match data, Forge, Java and
complete corresponding runtime sources. First home-node installation or an
explicit runtime update supplies reviewed `HEXPROOF_HOME_INPUTS` through the
same release entrypoint. Prepare and verify matching runtime/source/Java inputs
separately as described in the operator and runtime guides. Release deployment
does not build production application or Forge sources.

For home-node read-only verification, add `HEXPROOF_VERIFY_ONLY=1` to the explicit
target/version command. Interrupting occupied home rooms requires the separately
authorized `HEXPROOF_ALLOW_ACTIVE_ROOMS=1`; ordinary preparation expects no
rooms or service-owned Java processes. Monitoring installation has its own
`HEXPROOF_INSTALL_MONITORING=1` option and
[operating procedure](../deploy/monitoring/README.md).

Resolve the service, listen address and runtime configuration from the selected
target's current scripts/configuration before any maintenance. The
[server-directory guide](server-directory.md) separates public catalog data from
the private operator inventory. Read current service identities and qualification
records from that inventory, not a dated source document.
Clients and hubs require the same game-protocol identifier; application
versions may differ when their protocol remains compatible. See the
[compatibility policy](protocol-compatibility.md) for admission and update behavior.

## Production TLS maintenance

TLS, gateway/TURN provisioning and certificate renewal are separate
infrastructure from an application upgrade. For IP-based installations using
`hexproof-cert-renew.timer`, inspect the selected target's effective unit and
certificate inventory. For example, after resolving the authorized SSH target:

```sh
ssh "$HEXPROOF_SELECTED_SSH_TARGET" 'systemctl status --no-pager --full hexproof-cert-renew.timer && \
  /opt/hexproof-certbot/bin/certbot certificates'
```

Keep WSS behind the configured TLS proxy and recheck the selected public
endpoint after an authorized infrastructure change.
