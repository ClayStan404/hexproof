# Cached sponsors and announcements

The desktop obtains operator-managed public content independently of the room
hub. This is presentation data, with no accounts, sponsor entitlements, remote
QML, gameplay configuration, or protocol changes. Payment destinations and QR
codes remain bundled. All downloaded text is rendered as plain text.

## Discovery and local storage

Content index URLs are derived from the **bundled** server directory URLs by
resolving the sibling `content/index.json`. A downloaded server directory or
the selected game server cannot change these sources. Up to four trusted HTTPS
origins are supported. `HEXPROOF_CONTENT_INDEX_URL` explicitly overrides the
source for local verification; an empty value disables requests. HTTP is
accepted only for loopback fixtures. Redirects must remain on the same origin.

Startup renders local content immediately and checks the small index using
`If-None-Match`. A `304` reuses that index; a changed index downloads only data
whose SHA-256 differs from the installed document. Each document has its own
revision, so an announcement update does not download the roster again. Failed
document downloads remain pending even if the index itself has been cached.
Decreasing revisions and changed documents at the same revision are rejected.
Startup checks once per process; subsequent automatic/page checks are throttled
to five minutes, with a background check every 30 minutes and an explicit
Refresh action. No gameplay connection is required.

Cache data lives in `<profile>/public-content/<source-scope>/cache/`. Reading
and acknowledgement state lives separately in `state.json` in that scope.
Documents are size-limited, validated, and committed atomically before becoming
visible. Avatars are downloaded into files named by their content hash, decoded
and checked before use, and never loaded over HTTP by QML. Unchanged images are
reused across roster revisions and restarts. Missing/corrupt images are retried
even when the index has not changed. Images are limited to 1 MiB and 2048×2048;
PNG, JPEG and WebP are supported. A missing image uses the name placeholder.

A successful sponsor document is a **complete replacement**, including an
explicitly empty list. Removed sponsors disappear from all views and from the
cached roster. In-flight obsolete image downloads are cancelled, and cached
avatars with no remaining roster references are deleted. Shared images survive
until their final reference disappears. There is no sponsor history or merge
with bundled donors after an online snapshot is accepted. A damaged/cleared
previously installed roster does not resurrect bundled donors. Fetch failures
retain the last valid snapshot; offline clients learn removals on their next
successful synchronization. Small acknowledged-ID records remain to avoid
treating the same person as new if they later return.

## Sponsor acknowledgement

Every application version receives one startup sponsor acknowledgement per
local profile. New sponsor IDs that have not been acknowledged also trigger a
popup without waiting for a version upgrade. The two reasons share one popup:
it shows the current roster and highlights only unacknowledged sponsor IDs.
Already acknowledged supporters do not receive a new-supporter label merely
because the application version changed. Names, avatars, descriptions, tier
changes, and removal/readdition of an acknowledged ID alone do not trigger it.

The acknowledged application version and sponsor IDs are stored independently.
Legacy `sponsors:<version>` acknowledgements migrate both the version and the
bundled sponsor IDs; upgrading still shows the new version's acknowledgement.
Existing ID-only state retains all acknowledged IDs when the version record is
added. An empty roster opens no popup and does not acknowledge the version.

Startup notices wait at most four seconds for fresh content without blocking
the window. The popup is offered at most once per process, in the main menu;
entering a room or leaving the main menu before the startup decision defers it
to the next launch. Content learned later remains pending for the next launch.
Closing, Escape, clicking outside, and View full sponsor list acknowledge the
running version and only the roster IDs captured when that popup opened. Merely
offering or deferring a popup does not persist an acknowledgement. New arrivals
during the popup are not accidentally acknowledged. Sponsor and card-art-repair
popups do not overlap.

## Announcements and history

The menu has a persistent Announcements entry, an explicit unread count and
the first unread title. Current and History tabs are usable offline. Expanding
an announcement marks it read; merely downloading it or opening the list does
not. Mark all as read affects current announcements. Normal announcements do
not create additional startup modal dialogs or interrupt a game.

Announcement IDs are stable. `notificationRevision` is separate from the data
revision: correcting text does not make a read item unread; incrementing its
notification revision intentionally announces an important correction. Read
state survives restarts and resource-cache repair. Archived items do not count
as unread, and the initial history download does not produce historical badges.

The server retains a complete archive so new installations can retrieve it.
Publication rejects dropping an existing announcement; use `withdrawn` to
hide it. Clients also retain previously downloaded entries omitted by an
external publisher, in History. The latest record for an ID supersedes its
older text. A withdrawn entry is excluded from both tabs after synchronization.

`display.mode` controls the Current tab:

- `recent`: include announcements within `recentDays`, plus pinned older items.
- `selected`: include exactly `selectedIds`; pinning sorts but does not bypass
  selection.
- `all`: include all published, nonwithdrawn announcements that have not expired.

Other published, nonwithdrawn entries remain in History. `startsAt` delays
visibility in both tabs; `expiresAt` moves an item to History. Future publication
dates are also hidden. Times use UTC with an explicit `Z`; the client reevaluates
visibility every minute using its local clock, including offline. Pinning,
sorting, and display-policy changes never reset an existing read revision.

## Documents and publishing

The index has schema version 1, a monotonically increasing `revision`, and
`sponsors` / `announcements` descriptors containing `revision`, relative `path`,
and `sha256`. It is capped at 32 KiB. Each content document is capped at 2 MiB.
Relative paths cannot escape the content release tree.

Bundled examples are under `apps/client-qt/config/content/`. Sponsors use
`id`, `name`, `tier`, `profileUrl`, optional `featured`, optional localized
`description`, and optional `avatar: {path, sha256}`. The three existing tiers
remain client-owned. Avatars have paths under `avatars/`; profile links must
use HTTPS. Localized fields require `en`, with an optional `zh` translation.

The gold frame, slow glow, larger avatar, and special-thanks text require
`featured: true`; assigning a tier alone only selects the group. Include
`featured: true` when adding an Omniscience supporter to the operational roster
so every supporter in that tier receives the same recognition. An introduction
is optional and does not control the effect.

An announcement example:

```json
{
  "schemaVersion": 1,
  "revision": 2,
  "display": {"mode": "recent", "recentDays": 90, "selectedIds": []},
  "announcements": [{
    "id": "maintenance-2026-09",
    "notificationRevision": 1,
    "publishedAt": "2026-09-23T08:00:00Z",
    "title": {"en": "Planned maintenance", "zh": "计划维护"},
    "body": {"en": "Maintenance details.", "zh": "维护详情。"},
    "pinned": true,
    "withdrawn": false
  }]
}
```

Maintain operational source JSON in `deploy/content/sponsors.json` and
`deploy/content/announcements.json`; avatar sources are shared with
`apps/client-qt/assets/sponsors/`. The bundled JSON under
`apps/client-qt/config/content/` is an offline bootstrap, not the source for
subsequent publications. Before editing, start from the latest published
documents. Increment each changed document's `revision`, and increment the
index revision for the publication. Do not increment `notificationRevision`
for ordinary wording corrections.

```sh
python3 tools/public-content.py \
  --sponsors deploy/content/sponsors.json \
  --announcements deploy/content/announcements.json \
  --avatars apps/client-qt/assets/sponsors \
  --revision 3 --output build/public-content/revision-3
python3 deploy/publish-public-content.py build/public-content/revision-3 --target aws
```

Choose the next index revision from the live index; `3` above is an example.

The package contains immutable release paths and an index. The publishing
script validates the existing revision and announcement history, uploads and
verifies the referenced files through public HTTPS, then atomically replaces
the index after a concurrency check. A previous index is retained on the
server, but rollback must republish the desired content with higher document
and index revisions; clients reject lower revisions. Repeating the same package
is supported after interrupted publication. It does not restart the game hub.

First activation requires installing the new locations from
`deploy/hexproof-server-directory.inc` into the resolved nginx configuration
and reloading nginx after validation. This is a separate operator deployment,
not an effect of building or testing the client. Later content publications
need no configuration reload. No initial public announcement is invented by
the client; the bundled announcement archive is empty.

The owner authorized initial public activation on 2026-09-24. The `aws` nginx
snippet now serves the content paths above. Operational announcement history
is maintained in `deploy/content/announcements.json`; the bundled empty file is
only an offline bootstrap, not the source for subsequent publications. Before
the next edit, compare this operational source with the latest published
document and preserve every existing ID.

The first publication used index/announcement revision 2 and the unchanged
bundled sponsor document at revision 1. Its global test announcement,
`announcement-test-20260924-032223`, was initially scheduled from
`2026-09-24T03:27:13Z` until `2026-09-25T03:27:13Z`. The owner withdrew it on
2026-09-24; its retained `withdrawn: true` record hides it from both Current
and History after synchronization, including on clients that cached it earlier.
Public HTTPS payload hashes and conditional `304` responses passed; the server
directory bytes and game-hub/gateway process IDs were unchanged. Evidence is in
`build/public-announcement-test/publish-20260924-032650/`. The prior nginx snippet
is backed up under
`/var/backups/hexproof-public-content/publish-20260924-032650/` on `aws`.

Verification covers real loopback HTTP, conditional responses, disk reuse,
partial failures, removal/empty snapshots, shared-avatar collection, cancellation,
restart/corruption recovery, announcement visibility and acknowledgement state,
plus QML reading, history navigation, long text and large interface scales.

The native fixture supports a three-launch check on an actual display. Leave
the fixture running in one terminal; run the client verification from another
terminal with the printed URL exported as `HEXPROOF_CONTENT_INDEX_URL`. Stop
the fixture with Ctrl+C after the runner finishes.

```sh
python3 tools/ui-automation/fixtures/public-content.py \
  --state-file build/public-content-fixture/state.json
# Set HEXPROOF_CONTENT_INDEX_URL to the loopback URL printed above.
HEXPROOF_AUDIT_STARTUP_NOTICES=1 python3 tools/ui-automation/run-native.py \
  --scenario tools/ui-automation/scenarios/PublicContent.qml \
  --next-scenario tools/ui-automation/scenarios/PublicContent.qml \
  --next-scenario tools/ui-automation/scenarios/PublicContent.qml
```

On 2026-09-23 this passed on the workstation's native Wayland display with
maximized 1914×1015 logical-pixel test windows on a 1920×1080 display at DPR 2,
using isolated profiles. It covered the startup popup,
unread menu, announcement detail/history, sponsor expiration, cached restart,
and a newcomer announced on the following launch. The fixture observed five
index checks with only three index bodies, one announcement-body download,
and one avatar download across all three launches. Final evidence is retained in
ignored `build/public-content-native-final/` and
`build/public-content-native-final-fixture/`. The complete client verification
scope passed all 36 CTest targets and the shared static/tool checks; focused
cache, popup, and publication regressions also passed after the final changes.
No public content or remote service was changed by this verification.
