# Managed STUN operations

Managed STUN supports peer discovery for player-hosted Forge. It is separate
from game-server upgrades and from the home-node TURN relay. Resolve configured discovery endpoints and management targets from the private
[operator inventory](multica-operations.md#operator-configuration). Public
client-facing STUN endpoints may be distributed in client/hub configuration;
SSH aliases and deployment records do not belong in this document. Inspect the
selected service's effective configuration before maintenance.

## Service and application configuration

The distribution `coturn.service` runs as `turnserver` with
[`deploy/hexproof-stun.conf`](../deploy/hexproof-stun.conf) installed at
`/etc/turnserver.conf` and the
[resource drop-in](../deploy/hexproof-stun-resources.conf) at
`/etc/systemd/system/coturn.service.d/hexproof-resources.conf`.
The templates enable only UDP STUN binding discovery on port 3478. TURN
allocation, TCP/TLS/DTLS listeners and the management CLI are disabled.
Cloud ingress must permit the intended public UDP 3478 traffic.

The game hub distributes the configured STUN list in its room-bound peer grant
after player consent. `-peer-stun-servers` overrides `HEXPROOF_PEER_STUN_SERVERS`;
unset configuration uses the defaults, while an explicitly empty value disables
discovery. At most two UDP `stun:` URLs are accepted. Credentials, paths, queries,
unsupported schemes and invalid ports are rejected. An example override is:

```ini
[Service]
Environment="HEXPROOF_PEER_STUN_SERVERS=stun:stun-one.example.invalid:3478,stun:stun-two.example.invalid:3478"
```

Installing Coturn does not change an already running hub's configuration or
enable player hosting. Application and infrastructure changes retain their
separate deployment authorization and verification.

## Verification and recovery

After an authorized template/configuration change, reload systemd and restart
only the selected `coturn.service`. Check its journal and UDP listener, then
send an external STUN binding request and verify the transaction ID and
XOR-MAPPED-ADDRESS. A TCP port check is not a STUN test. Check that a TURN
Allocate request receives no allocation and that another binding request still
succeeds. Recheck the cloud firewall when no packets reach the host.

A matching `hexproof-forge-host -peer` can confirm server-reflexive ICE discovery;
that alone does not qualify every NAT or a complete cross-network Forge match.
Use the [WAN verification procedure](multi-client-testing.md#forge-checks-across-networks)
when testing actual player-hosted connectivity.

To withdraw discovery after explicit authorization, stop and disable the
selected service and remove its public UDP ingress rule. Keep the STUN-only
configuration while stopped: restoring and starting the distribution default
may enable unwanted TURN behavior. The Hexproof room relay is independent.
