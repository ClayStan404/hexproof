# Online server directory and operator inventory

The public server catalog advertises client-facing names, stable IDs, URLs and
capabilities. It is not a management inventory, deployment authorization or a
concurrency guarantee. Keep SSH aliases, units, management routes, installed
hashes, room inventories and rollback records in private operator storage.

Resolve `$HEXPROOF_DEPLOYMENT_TARGETS_FILE` and `$HEXPROOF_NODES_FILE` as described
in [operator configuration](multica-operations.md#operator-configuration).
Inspect the selected service before maintenance. Install and upgrade through the
[operator procedure](../deploy/home/README.md), with explicit targets and version;
record the resulting checks privately instead of adding dated fleet tables here.

The [home-server contract](home-servers.md), [official cluster contract](official-cluster.md)
and [self-hosting guide](self-hosting.md) define ownership and configuration.
Each game/event has one authoritative hub; optional official coordination can
provide a shared lobby. Use effective service settings and measured evidence for
capacity. Forge runtime/source requirements remain in
[the runtime guide](../third_party/forge-runtime/README.md).

## Directory publication

Public origins come from the client bootstrap and operator configuration. Serving
the static catalog requires no application-server restart. See the
[client catalog contract](../apps/client-qt/config/README.md) for validation,
revision ordering, caching and capability discovery. Refresh origins never come
from a downloaded catalog; adding one requires a bootstrap update or explicit
runtime override.

To change catalog entries:

1. Read the newest published JSON and increment its `revision`.
2. Edit the operator's local catalog input, keeping only intended public fields.
3. Publish to explicitly selected configured targets, then verify public HTTPS
   bytes. For example, after resolving the input and targets privately:

   ```sh
   python3 deploy/publish-server-directory.py "$HEXPROOF_CATALOG_FILE" \
     --targets "$HEXPROOF_SELECTED_TARGETS"
   ```

The publisher validates selected revisions, stages updates and atomically replaces
live files. A digest recheck prevents overwriting a concurrent operator update.
Each target retains a previous document. After partial failure, reconcile and retry
the same document. Clients reject revision regressions; rollback publishes desired
entries under a new higher revision.

A catalog advertises capabilities; it does not install Forge. Health probes and
protocol welcomes establish observations only for that exact URL. Player hosting,
direct transport and host migration are independent capabilities. Catalog refresh
never relocates an active connection or transfers reconnect credentials; trusted
cluster transfers follow their separate request-correlated protocol.

## Client distribution and compatibility

Clients must match the hub's game protocol, independently of application versions.
Catalog-only changes can reach installed schema-2 clients through existing origins.
Release builds obtain the bootstrap from `HEXPROOF_PUBLIC_SERVERS_JSON`; keep that
public release input consistent with the intended catalog. Catalog revision and
release version are independent. A catalog update alone cannot change a hub's
protocol, runtime or deployed binaries.

Keep operational qualification and authorization evidence outside source control.
Use current inventory and the deployment procedure for each new maintenance task;
previous successful rollouts do not prove current service readiness.
