# Home-node deployment

Use **`deploy/deploy-release-server.sh`** for home-node installation and
upgrades. It downloads verified GitHub hub/connector binaries, prepares every
selected host, then activates and tests each changed node sequentially.

## Production release upgrades

For an owner-authorized upgrade to a published 2.4.0 release:

```sh
HEXPROOF_TARGETS="home-a home-b" HEXPROOF_VERSION=2.4.0 \
  ./deploy/deploy-release-server.sh
```

For an explicitly authorized unpublished draft, also supply
`HEXPROOF_ALLOW_DRAFT=1`. Draft access never publishes the release.
Always select the targets and version explicitly; the shell entry
point reads cloud defaults from the operator inventory. Home names and their
configured SSH aliases are both accepted; no SSH configuration is inspected.

Keep machine-specific configuration outside Git. The loader reads
`HEXPROOF_DEPLOYMENT_TARGETS_FILE` and `HEXPROOF_NODES_FILE`, or by default
`$XDG_STATE_HOME/hexproof-operator/deployment-targets.json` and
`$XDG_STATE_HOME/hexproof-operator/nodes.json` (`XDG_STATE_HOME` defaults to
`~/.local/state`). Start from
[deployment-targets.example.json](../deployment-targets.example.json) and
[nodes.example.json](nodes.example.json), replace every target/address with
reviewed operator values, then remove `_example` and protect the files with
mode `0600`. Examples are deliberately rejected as live inventories; missing
configuration fails before remote actions. Cloud keys are existing SSH aliases;
home entries map logical names to `ssh`, `arch` and public `endpoint`.

The cloud inventory also selects the explicit `forgeEnabled`, `testEnabled`
and `publishEnabled` capabilities. Its `defaults` preserve an operator's chosen
release, Forge, test and content-publication targets. These are configuration,
not authorization to deploy; the requested target/version and existing
maintenance permissions still apply. `origin` is the HTTPS hostname or IPv4
origin on the standard TLS port, without credentials or URL parameters.
The checked-in nginx and standalone systemd files are examples; review their
hostname, certificate paths, service identity and directories before installation.

For a read-only verification, add `HEXPROOF_VERIFY_ONLY=1` to that command.
An already matching installation receives inventory and public welcome checks
without uploads, restarts or test rooms. A newer installed version is never
silently downgraded. Ordinary upgrades preserve private configuration, retained
match data, Forge, Java and the corresponding Forge source identity. Complete
source archives remain on the build/release host rather than being deployed to
each game node.

To install the optional local readiness/latency/error collector after a
successful writable upgrade, add `HEXPROOF_INSTALL_MONITORING=1`. See the
[monitoring procedure](../monitoring/README.md) for collection, retention and
readback. Ordinary application upgrades preserve an existing monitor.

Requirements: authenticated `gh` with attestation verification, Python 3.11+
with tarfile data-filter support, SSH/SCP, and noninteractive sudo on each target.
Initial installation and runtime updates also require rsync on both ends.
The backend checks GitHub asset digests, `SHA256SUMS` and the checksum file's
attestation against the pinned release tag commit and workflow. It rejects a
release that changes during verification.

## First installation and runtime inputs

The same command handles a host with no home-node installation. Supply
`HEXPROOF_HOME_INPUTS=/absolute/private/inputs.json` alongside the explicit
version. GitHub server archives contain the hub and connector; verified Forge,
its complete corresponding source archive, Java 21 and private node settings
are supplied separately. The deployment verifies the runtime/source pair on the
workstation, but transfers only the runtime and its source name/checksum reference,
not the complete source archive. No previous server installation is required.

```json
{
  "forge": {
    "runtime": {"path": "/absolute/forge-runtime.tar.gz", "sha256": "verified SHA-256"},
    "source": {"path": "/absolute/forge-source.tar.gz", "sha256": "verified SHA-256"}
  },
  "java": {
    "amd64": {"path": "/absolute/java21-amd64.tar.gz", "sha256": "vendor SHA-256"},
    "arm64": {"path": "/absolute/java21-arm64.tar.gz", "sha256": "vendor SHA-256"}
  },
  "config": {
    "home-a-ssh": "/absolute/private/home-a-node.json",
    "home-b-ssh": "/absolute/private/home-b-node.json"
  }
}
```

Use real versioned archive filenames and verified checksums. Runtime/source
archives must match the pinned Forge recipe; the backend verifies that pair
before any upload. All paths are absolute workstation paths. Node JSON follows
[the home-server contract](../../docs/home-servers.md), uses backend
`ws://127.0.0.1:57323/ws` and health URL `http://127.0.0.1:57323/healthz`, and must
have matching gateway registration. Keep credentials outside Git and bundles.
The gateway and its registration must already be provisioned.

Retain the verified complete source inputs centrally, including sources for older
distributed runtimes, and maintain their availability through the release/source
distribution process. Runtime `SOURCE.json` and the sealed node manifest record
the matching archive name and SHA-256; this reference is not a replacement for
retaining and providing corresponding sources. The source-publication pipeline
and license/dependency notices are unchanged.

Ordinary upgrades also accept legacy sealed nodes containing a local `sources/`
archive. After verifying the complete baseline and its candidate copy, packaging
removes only that matching archive from the new candidate and retains its source
identity. The installed baseline and rollback tree are not edited; unrelated
source-directory entries are preserved. No live-node cleanup or restart is needed
just to adopt the new tooling; migration happens on the next requested upgrade.

For an explicitly requested Forge/Java update, supply the same runtime inputs
on an installed node; its live config and match data are preserved, and the
reviewed service templates accompany the new runtime. Existing-node config
is never overwritten by the input file. Omit the input file for ordinary
application upgrades. The deployment command does not build application or
Forge sources. Build/verify runtime artifacts separately before supplying them.
Input files cannot be combined with read-only verification.

Missing installation is detected automatically. Partial installations, existing
home services without a valid current tree, or an occupied backend port cause
an error for operator diagnosis. Deployment does not uninstall or wipe state.
One-time removal of an old installation is a separately scoped maintenance
action; there is no automatic uninstall/reinstall mode.

## Verification and recovery

All targets must pass preparation before the first activation. By default,
existing nodes must have no rooms or service-owned Java processes before restart.
When the owner explicitly authorizes interrupting those rooms, add
`HEXPROOF_ALLOW_ACTIVE_ROOMS=1` with the selected home targets and an explicit
version. The opt-in is recorded in deployment evidence and cannot be combined
with read-only verification. It permits the normal service restart to terminate
existing games; artifact, baseline, rollback and post-activation checks still
apply. Each changed node then passes public WSS and real native Forge
decision/privacy checks. A
failure rolls back the nodes activated by that invocation in reverse order,
including a lost activation SSH response. Failed initial installation stops its
new services; inert files and evidence remain for diagnosis before retrying.

Evidence is under `build/home-deploy/runs/*-release-*`. Successful runs remove
their temporary uploads. Failed runs retain `uploads.json`, staging files and
`failure.json`. Initial uploads may include the private node config, protected
by the upload directory's permissions. Installed release trees and root-only
rollback records under `/var/lib/hexproof-home/deployments/` are retained.
A reviewed recovery can use the target-host installer's `--rollback <record>
--activate`; this is a recovery primitive, not an alternative deployment flow.

`deploy/deploy-home-release.py`, `deploy/install-home-node.py` and
`tools/package-home-node.py` are internal backend/installer/packager components
used by the single shell entry point. The separate home source-deployment driver
and experimental clean-reinstall mode have been removed. Deployment evidence
under `build/` is historical and must not be used as an executable entry point.

Cloud hub releases use the same shell entry point with configured cloud aliases; invoke
cloud and home targets separately. They require the same explicit version,
support the same draft opt-in, and use the same authenticated asset, checksum
and attestation verification as home nodes. This does not publish a draft or
alter the cloud hubs' Forge/resource settings.
Cloud gateway/TURN provisioning and the
inactive legacy home services are separate infrastructure. The gateway uses
loopback 57322 and each home hub uses 57323.

## Forge capacity configuration

The current home service template uses `-max-forge-games 256`, matching the
hub's default total room limit, with no systemd memory ceiling. Review these
settings against the target machine's capacity before installation.
It is a configuration ceiling, not a measured promise of 256 simultaneous
games. Waiting rooms and manual games still count toward the total room limit;
only live server-hosted Forge leases consume Forge slots. Player-hosted
bindings retain their separate limit of 16.

The existing server binaries accept this configuration; application and Forge
rebuilds are unnecessary. There is no literal unlimited Forge setting in the
current binary: omitting `-max-forge-games` defaults to one, while zero and
negative values are invalid. Removing the service memory limits does not
remove the host's physical resource limits.

For an existing sealed installation, this owner-scoped configuration change
uses `/etc/systemd/system/hexproof-home-hub.service.d/90-forge-capacity.conf`.
The drop-in resets `ExecStart` to the command in
[the service template](hexproof-home-hub.service) with capacity 256 and sets
both memory limits to `infinity`. Keep the installed base unit and
release tree intact so their checksums remain valid. Check for no rooms or
owned Java processes before restarting the hub, then verify the effective
process arguments, memory limits, public welcome and native Forge behavior.
Ordinary release upgrades preserve this host-local drop-in; new installations
use the updated template. Installation and upgrades still use the single
release entry point above, not a separate deployment script.

WSS/native-game verification does not qualify direct RTC, forced TURN or full AI
games. Those require their dedicated checks from the
[home-server contract](../../docs/home-servers.md). Client and hub communication protocols must match; application release versions
may differ under the [compatibility policy](../../docs/protocol-compatibility.md).
Deployment still verifies the explicitly selected release artifact version and
does not publish a desktop release. A legacy 3.0.0 installation uses v1 and requires a coordinated transition
before these v2 source rules apply online.

Home inventory records the verified hub's `-protocol` output; legacy binaries
without that CLI option are identified as v1. Room preflight and rollback use
that inspected protocol, so the initial v1-to-v2 deployment retains its occupied
room protection. This operator probe does not relax client admission.
