# Private visual Forge replays

Forge adapter 17 records a read-only visual history of two-seat matches. The
Qt player reuses the Forge table, displaying both hands, public zones, stack,
life, mana, counters and combat relationships. Playback never runs Java or
re-executes actions, so changes to the rules engine cannot change an archived
result. Card artwork continues to use the ordinary local catalog/cache.

## Access and completion

Only the original participants receive recipient-specific, random replay
capabilities. The hub refuses frame downloads until `GameResult.MatchFinished`:
a BO3 game ending or opening sideboarding is insufficient. Spectators and later
occupants of the same seat receive no grant. Authenticated resume transfers the
original participant binding; a nickname or seat number is not authentication.
The waiting room discloses that both hands become visible after the match.

For guests, a private capability saved in the local profile permits download
from the original hub after leaving the room. Optional [official accounts](accounts.md)
bind the original participant's replay access and list it on a new device.
Verified legacy capabilities can be claimed once; subsequent downloads require
that account as well as the recipient-specific token. Claims persist in a private
ownership index, independently of live room lifetime.
It survives a completed archive's hub restart, but is not a public replay URL.
Access is bounded by the archive TTL. Lost local capabilities are not recovered
by claiming the same display name. A downloaded/exported file includes both
hands and can be opened offline by its holder. Export deliberately strips hub
addresses and access tokens; the product cannot revoke a file already exported.

The existing `replay.list` / `replay.get` public-log API remains separate. Normal
player, opponent and spectator projections retain their existing redaction.
Registered decks, library order, RNG state, migration checkpoints, resume
credentials and native RPC response tokens are not part of this visual format.
The replay reveals current hands at recorded moments, not all hidden engine
state. Private selection menus and unexposed face-down identities are not
reconstructed. Native event descriptions may remain in English.

## Capture and transport

The native adapter observes meaningful engine events, including automatic spell
resolutions between human inputs, and records decision boundaries and the final
board. Each observation freezes a public snapshot plus each owner's hand on the
engine thread. Frames have a monotonic sequence, elapsed milliseconds, event
kind/description, actor independently of turn owner, and attack/block links.
The native `getReplay` cursor acknowledges an already-received prefix; retries
do not create duplicate frames. A bounded journal cannot block or reject legal
gameplay: an overflow/capture failure marks the recording incomplete.

The Go hub normalizes card/player identifiers using the same schema as live
Forge views, accumulates the whole match across games, and maintains a global
sequence and nondecreasing elapsed times. Creator-hosted helpers relay the
private batches only over their existing trusted hub channel. Observation
timestamps and batches are excluded from migration/peer position hashes.
Migration re-execution is not a new game in the visual history; duplicates are
ignored, while detectable gaps make completeness false. This does not claim
that an interrupted or failed host can recover observations never delivered.

Public protocol additions:

| Message | Purpose |
| --- | --- |
| `replay.forge_grant` | Private per-participant metadata and download capability; sent at initial capture and completion. |
| `replay.forge_get` | Capability, replay ID and frame offset. |
| `replay.forge_page` | Schema version, offset, total, completeness and bounded normalized frames. |

There is no public index for private replays. Native adapters below 17 can
continue gameplay but do not provide recordings. An empty retention directory
disables this archive path. An interrupted/abandoned match that never reaches
the match result gate is not downloadable.

## Storage and playback

The first format stores complete normalized frames. This makes arbitrary seeks
and backwards steps direct snapshot loads, without inverse game actions or
version-dependent reducers. Native pending data is limited to 3 MiB/2,000
frames; a hub recording to 128 MiB/20,000 frames, and one frame to 512 KiB.
Downloads contain at most 64 frames and approximately 768 KiB per page. New
downloads and uncached archive reads use the replay rate budget. The hub bounds
memory and compressed disk archives using its configured retention byte/file
limits (default 512 MiB/512 files); disk pruning runs at archive writes. These
budgets are independent of the legacy public-log archive store. TTL defaults
to seven days from match completion. Private directory/file modes
are `0700`/`0600`. The private Forge archive directory is `retained/forge`.

The client validates version, frame sequence and size, then saves `.hpr` files
atomically. Format: `HEXPROOF-REPLAY-1\n`, a four-byte big-endian uncompressed
length, and a zlib stream containing `{schemaVersion, metadata, frames}` JSON.
Both declared and actual decompression sizes are bounded. The local library
stores download capabilities separately with owner-only permissions. No engine
installation or network connection is required to view a downloaded file.
Each download page is correlated with its current request. A timeout ends that
request; delayed pages or errors from it cannot complete or cancel a later
retry, and duplicate pages cannot interrupt the next page request.

The player supports pause/play, event stepping, previous/next turn, timeline
seeking, speed selection, table flip, card inspection and export/import.
The selected speed is retained while navigating between replay pages, and the
speed menu always reflects the playback service's current setting.
Playback folds idle decision boundaries but manual stepping retains every
captured frame. Speed is event pacing, not wall-clock reenactment; displayed
elapsed times retain native game timing, excluding sideboard downtime. Incomplete recordings show a visible
notice. Recorded frames cannot submit game actions or modify a live room.

Future improvements can introduce periodic keyframes plus state deltas after
measuring real archive sizes, as well as bookmarks, searchable actions and an
original-player perspective. They must retain the same whole-match gate and
versioned offline snapshot semantics.
