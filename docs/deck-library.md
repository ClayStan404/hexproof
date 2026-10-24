# Deck library & editor

- Status: **Active**
- Last updated: 2026-09-27
- Parent: `product-brief.md`

## List screen

- Lists **imported decks**.  
- **Format filter** (All / Custom / Standard / Pioneer / Modern / Legacy /
  Vintage / Pauper / Duel Commander / Commander / Cube).
- **Double-click** deck → editor.  
- Import, **export**, and **delete**.  
- **Export** copies the same explicit `Deck` / `Sideboard` / `Commander` /
  `Consider` text
  the importer accepts, or saves it as a `.txt` file. Local token preferences
  are not included.  
- Status: ready / missing images / missing commander (commander formats), etc.
- **Cache library art** covers all saved decks; the editor's
  **More → Cache deck art** covers only the current deck. Both reuse compatible
  local files.
- Explicit image caching shows an inline progress bar, percentage, and current
  operation status. Speculative search previews do not contribute to these
  counters or appear as deck downloads.
- The editor reserves the measured height of its cache-progress row while the
  indicator is hidden. Starting or finishing hover-image work or explicit
  caching must not move the deck filters, gallery or card action buttons.
- Search previews load only the current viewport after input/scrolling settles.
  A new search, viewport, or closed popup replaces the pending preview list.
  At most one preview face is admitted at a time, behind explicit deck/match
  work; an already started request may finish. Selecting a card keeps its
  explicit cache request even if the search closes.
- **Duel Commander and EDH ready** require **one or two designated commanders**. Hexproof does
  not enforce Partner, Friends forever, Choose a Background, or similar
  construction rules; players remain responsible for legality.
- Named-format decks are checked asynchronously against catalog schema 10.
  Verified structural and copy-limit violations disable room selection.
  Commander/EDH card-pool and color-identity findings remain advisory and
  never block selection; Duel Commander retains card-pool enforcement. A
  missing/outdated database is shown as unverified and does not falsely mark
  the deck illegal. See `deck-formats.md` for the exact boundary.

## Import

- User pastes deck text from Moxfield, plain lists, etc.  
- App parses and stores under deck library with format metadata.
- With an installed local catalog, a name-only entry adopts and persists the
  catalog's default set and collector number. An explicit printing is retained;
  a late metadata result cannot overwrite a newer user selection. Resolved
  duplicate printing rows merge quantities and refresh legality validation.
  Unresolved mainboard or sideboard printings prevent ordinary room selection,
  including background-art mode. Consider cards do not affect registration.
  Resolving metadata does not initiate image downloads.
- The import form scrolls across the page's content area, including its side
  gutters. The deck-list editor has a bounded, independently scrollable
  viewport. Vertical wheel input over a short list, or past a long list's top
  or bottom, scrolls the surrounding form so the import actions remain
  reachable at small window sizes and larger interface scales.
- Moxfield foil (`*F*`), etched (`*E*`), and commander (`*CMDR*`) markers
  are accepted in any trailing order. Decorative `★`/`☆` suffixes on exported
  collector numbers are removed. Single- and double-slash card-name separators,
  with or without surrounding whitespace (such as
  `Unholy Annex/Ritual Chamber`), are normalized to Scryfall's ` // ` form.
  Loading saved decks applies the same normalization to all card sections and
  commander designations, so previously unresolved entries recover through
  normal local metadata hydration without removing and re-adding cards. Counts
  and explicit set/collector selections are retained. Named-format legality also
  accepts a double-faced card listed by either face, such as `Esika, God of the Tree`
  for `Esika, God of the Tree // The Prismatic Bridge`.
- Alternate printed titles such as Secret Lair flavor names remain visible in
  the deck while their set and collector number resolve the canonical card
  identity and image.
- When a set and collector number are supplied, legality and copy limits use
  that exact printing before resolving the displayed name. A Prepare spell
  title that also names a standalone card must retain its containing card's
  Oracle identity and format legality; name-only entries still resolve the
  standalone card.
- Collector numbers preserve non-whitespace Unicode symbols such as the
  dagger in `Gifts Given (HHO) 7†`. Import, export, and cache requests retain
  the exact printing identity, except for the decorative foil suffixes above.
- Paste input is capped at 1 MiB before line splitting to bound memory use.
- Parsing runs on a worker thread. Final model insertion is shown as a distinct
  import phase. After persistence, a queued local-only pass reconnects imported
  entries to compatible files already present in the art cache. It never
  starts a network request, and import does not enqueue image downloads for the
  whole list. The same local-only reconciliation runs for missing paths when a
  saved library is hydrated, the card language changes, or the catalog is
  replaced.
  If a local card catalog is installed, missing type lines and localized names
  are resolved in one deduplicated worker-thread batch so the editor can group
  cards by category before any art is cached without blocking the UI thread.
  When the player later chooses **Cache art**, or adds/changes a single
  printing, image-cache requests are deduplicated and admitted in bounded
  event-loop batches so a large Commander list does not monopolize the UI
  thread. **Cache art** rechecks every entry in its selected deck scope before
  filtering resolved faces, so an older front-only double-faced cache can add
  its independent back face without redownloading valid art. Resolved metadata
  updates are applied with one pass over the library.
  A downloaded front face also refreshes entries imported with the complete
  two-face name. Reverse-face notifications never replace the main display
  image, and availability remains specific to the selected printing.
  Structural and metadata edits enqueue versioned snapshots on one background
  writer; newer generations supersede stale queued snapshots, so interactive
  edits never wait for JSON serialization, disk I/O, or the writer lock.
  Persistence failures remain visible and retry in the background. The
  destructor still waits for an in-flight write and flushes the latest snapshot
  so pending edits are not lost on exit.
  Adding, removing, or changing a card updates only the affected library row;
  saving an ordinary edit must not start a full-library image reconciliation.
  Repeated presentation reads reuse card projections and per-deck image counts
  until their source cards or art mappings change. Match registration still
  checks the current files. Gallery rows are virtualized at every deck size,
  preserving category headings, exact printing actions and scroll position;
  hidden collection views do not instantiate cards or resolve image sources.
  Grouping reads the front face's main types, excluding subtype text; localized
  Gnome/Goblin names containing the character for land do not make a creature
  a land. A restored image at an unchanged saved path invalidates that card's
  earlier missing-art result and refreshes deck readiness without a new edit.
- For Custom and named commander-free 1v1 imports, an unlabeled blank-line section remains the
  sideboard convention. For Duel Commander and EDH imports, that section designates the commander
  and remains part of the main deck; explicit `Commander`/`Commanders`
  headings and `*CMDR*` markers remain supported. Up to two distinct marked
  cards are retained.
- Cube imports use the same entry point and plain-text format. Explicit
  sideboard cards are merged into one Cube pool, commander markers are cleared,
  and unresolved or undersized pools remain editable. A Cube becomes selectable
  for a two-player draft after it contains at least 90 physical cards
  and every entry has an exact set code and collector number. Constructed deck
  imports retain the 1,000-card / 500-entry transport safeguard; Cube imports
  instead accept up to 10,000 physical cards and 5,000 entries, matching the
  server-side Cube product limits.
- On upgrade, legacy `cubes.json` entries are imported once into `decks.json`
  as Cube-format decks and the old file is archived. Synthetic `CUBE`
  printings remain visible for correction rather than being discarded.

## Export

- From the library row or the deck editor **More** menu, **Export** offers **Copy list**,
  **Save as file**, and **Export card art…**.
- The written text always uses explicit English headings in this order:
  `Deck`, `Sideboard`, `Commander`, then `Consider` when the editor-only
  Consider area is not empty. Commander cards appear only under
  `Commander` (with `*CMDR*`) so a later import does not double-count them.
- Lines keep `count name` and, when known, `(SET) collector`. The file is
  UTF-8. Tokens and foil/etched markers are omitted.
- Re-importing that text restores mainboard, sideboard, designated commanders,
  and Consider cards.
- **Export card art…** saves a portable `.hexproof-artpack` for just the chosen
  deck, including Cube lists. The deck identity and requests are snapshotted
  before choosing a destination; changing the editor selection cannot change
  that export. Mainboard (including commanders), sideboard, Consider, and
  saved tokens/emblems participate. Copies and repeated printings are
  deduplicated. An invalid or empty selection never exports the whole cache.
- Art export reads only the local cache and catalog, without starting downloads.
  It includes available languages and cached independent faces for the selected
  printings, using the same validated, deduplicated pack format as the storage
  manager. Selection, image validation, and writing run on the maintenance
  worker, with visible activity and a persistent result in the export dialog.
- Catalog-linked meld results are included using their own exact printing
  identifiers. Multiple front cards or printings may reference the same result
  image; its lookup mappings are retained while identical image bytes are
  stored once. A same-named result from another printing cannot fill a missing
  catalog-linked face.
- The result reports exported images/bytes, missing printings/faces, and skipped
  invalid cache entries. If the catalog cannot establish face coverage, the UI
  warns that back-face completeness could not be verified. A partial export is
  explicitly identified, not presented as a complete offline deck. With no
  usable images, export fails without replacing an existing destination.
- Recipients import the pack from **Settings → Card art storage →
  Import pack…**. A card-art pack does not include or import a deck list or the
  metadata database; share the text deck list separately when needed.

## Editor

The editor uses a card-art-first desktop layout, guided by the owner's Arena
references (see `ui-card-workbench.md`):

1. The format selector may change an existing deck without deleting cards.
   Commander-free formats preserve mainboard and sideboard. Duel Commander and
   Commander preserve commander designations when switching between each
   other. Crossing into either commander format asks for confirmation, merges
   the sideboard into the main deck, and clears commander designations;
   different printing selections remain separate during that merge;
   crossing back keeps every card in the main deck and clears only the
   designation metadata. The changed deck alone is revalidated.
2. The main deck defaults to visual card art and retains a compact list mode. Both show
   physical-copy totals in their category headings. The visual mode keeps a
   large hover preview beside taller card tiles and can group by card type,
   mana value, or no grouping, then sort by name, mana value, or card type.
   Card-type groups distinguish creatures, planeswalkers, battles, artifacts,
   enchantments, instants, sorceries, lands, and other cards.
3. **Sideboard** region for commander-free 1v1 decks. Commander and Cube formats have no sideboard region; the
   main gallery uses the full width. Designated commanders stay in their
   card-type group with a Commander mark. Catalog search and token controls
   stay in the main toolbar. Cube uses the main region as its full pool.
4. **Drag-and-drop** cards between main and sideboard for commander-free 1v1 decks (and
   within lists as needed for counts).
5. **Search bar always visible on the deck editor** (not buried under Advanced only):
   - A deck-local search/color toolbar and advanced-filter sheet immediately
     narrow cards already in the deck by type, mana value, color, and rarity.
     Counts and legality continue to use the complete deck.
   - With local full metadata DB: open the add-only catalog popup, type a
     Chinese or English name, or filter by card type, set code, printing
     language, color identity, mana value, rarity, and any format legality exposed by the
     current Scryfall catalog. Filters can be used without a name. Add a hit to
     main or, for commander-free 1v1, SB →
     **download that card’s art**. A double-faced card listed by either face
     still lists every playable printing (not art-series or token rows) and
     previews that version's image. A database query failure is shown in the
     printing picker instead of being presented as an empty version list.
     Catalog search stays in the fixed page header, so reaching it does not
     require scrolling through a large main-deck gallery.
   - Legality filters narrow search results. Separately, the deck legality
     service checks the selected named format without implementing gameplay
     rules or card-text-driven pairing exceptions.
   - Without the full DB: search bar still shown; prompt to download/update
     the Default Cards database.
6. **Download/update card database**: user action installs searchable
   **metadata** only (not all images in the installer or in one giant art
   pack). The primary path downloads Hexproof's compressed, prebuilt
   single-file database and verifies its release manifest, byte sizes, and
   compressed/expanded SHA-256 values before atomic installation. Interrupted
   transfers retry automatically. Settings compares the installed database's
   embedded build timestamp and schema with the small official release
   manifest, and exposes a manual refresh plus an update action. If the
   official package is unavailable, the update stops and keeps the installed
   database; normal clients never rebuild it from upstream sources.
   Settings can also import a shared Hexproof SQLite database or a Scryfall
   JSON/GZip bulk file from local storage.
7. **Deck tokens and emblems:** each deck may save a local list of auxiliary printings it commonly
   creates. The editor keeps a compact toolbar control; a large modal manager shows readable card art and metadata while
   adding or removing entries through the token and emblem catalog. Entries retain
   their object kind, so an emblem cannot become a battlefield token. They are local
   presentation preferences, are not sent in `deck.select`, and do not affect
   deck construction or game rules.
8. **Consider:** a compact count opens a large modal manager instead of taking
   permanent editor space. Search can add cards directly to this area, and one
   physical copy can move between the main deck and Consider at any time while
   editing. Consider is persisted locally and round-trips through the text
   format, but it is excluded from deck validation, room registration,
   `deck.select`, and between-game sideboarding.

### Viewing printed card faces

Large card previews display all faces together when the installed catalog or
verified cached provider metadata identifies independently printed faces. This
includes the main deck, Sideboard, Consider, catalog search, printing selection,
tournament decklists, and token or emblem details. The current face appears first;
sufficient width places the images side by side, and narrow panels stack them.
Viewing the back requires no
click. Leaving both the card and preview closes the hover preview after a short
handoff interval.

In the main-deck gallery, metadata and copy-count refreshes preserve inspection
of the same visible printing while the pointer remains on its card or preview.
The refreshed preview uses the current card data. Replacing, removing, filtering
or pooling the source must not reopen the previous card's preview.

Face inspection belongs only to that preview. Adding, removing, moving,
registering, or customizing a card retains its original identity and printing.
Selecting another card or reopening a preview shows that card's current face
first. Art and available printed text follow the card-language setting, including
custom art assigned to each face. Missing back art shows that face's
name and available text without reusing its front image or front rules.
Preview images decode at their displayed pixel size, including display scaling,
and reuse per-file source revisions so repairing existing artwork refreshes an
open preview without reloading unrelated cards.

Transform cards, modal double-faced cards, double-faced tokens, and reversible
cards use the catalog's face records. Meld components may preview their related
meld result using the result's own printing. Split, adventure, and other layouts
printed on one physical side keep their single image. Custom-art editing keeps
its explicit face selector and scope controls; changing a preview never changes
an art binding.

Face inspection also works for exact printings cached without the full card
database, and for cached printings absent from an installed database. New
provider resolutions retain ordered physical-face identities and meld-result
relationships in the local cache. Legacy entries without layout evidence stay
single-faced until an explicit preview or cache operation completes a bounded
metadata-only refresh. Repeated previews do not repeat a failed request within
the same run; a later run may retry it. This refresh preserves existing art and
does not download images. An old, unverified same-named token reverse may have
cached its front by mistake: confirmed face metadata discards only that
ambiguous reverse art and text, and normal caching obtains the correct back.
Known single-image layouts do not need a refresh.
Ordinary cache hits remain local. Automatic legacy backfill is limited to paired
canonical names with existing art for the requested printing; reused artwork
does not initiate a background metadata fetch. An explicit visible inspection
may check unknown single-name printings, including meld components.
Meld inspection requires the related result's actual printing metadata and never
assigns the component's collector number to that result.

## Full card database vs images (analysis summary)

| Asset | What it is | Size / role | Source and installation |
|-------|------------|-------------|-------------------------|
| **Metadata DB** | Names, types, mana, sets, ids… for **search** | About 80 MiB compressed JSONL plus a local SQLite index | Hexproof uses Scryfall **Default Cards** via the [bulk-data API](https://api.scryfall.com/bulk-data) and installs a verified prebuilt database |
| **Image cache** | JPEG/PNG/WebP per face | Grows with use; no global all-printings download | Art is fetched lazily, or explicitly prefetched for every distinct printing in an installed Set Limited product |

**Owner choices (2026-07-22):**

1. **One full metadata package:** Hexproof downloads Scryfall **Default
   Cards** (~80 MiB compressed JSONL class as of 2026-07-29). It preserves
   printing and collector identity and replaces the former Oracle/Default
   package choice.
2. **Independent language preferences in Settings:** interface language and card text/art language are separate. A player may use an English UI with Chinese card names and art, or the reverse.
3. **Card-art provider preference:** compatible local art remains first. The
   default Automatic mode selects MTGCH first for Chinese cards and Scryfall
   first for English cards. A client may instead pin Scryfall or MTGCH as the
   first network provider; missing or unavailable art automatically falls back
   to the other provider. Chinese mode keeps Chinese candidates ahead of
   English candidates. **Parallel** is an opt-in mode for large batches such
   as EDH match loading: both providers fetch different cards concurrently.
   Automatic remains the default.
4. On **select from search**, **Cache art**, or Ready: download the needed
   card art into local cache (not all art with the bulk file). Deck text
   parsing runs off the UI thread, and locally resolved image URLs are
   downloaded with a bounded six-request pool, including resolver-owned
   downloads, delayed image retries and optional battlefield illustrations.
   In Parallel mode, each provider can
   own up to three card resolutions; a free slot takes another card without
   waiting for the other provider. Each metadata host allows at most three
   in-flight requests, with at least 110 ms between request starts, shared
   across all resolution workers. Response latency does not extend this
   interval; a slow lookup cannot block the host's other slots. Shared host
   cooldowns still prevent queued requests after a rate-limit response.
   Downloaded images must fully decode before they are cached or counted as
   ready. Validation uses a dedicated two-thread pool and retains the
   download slot until completion; a recognized header alone is insufficient.
   Repeated deck imports
   share one deduplicated metadata worker. Existing-art hydration yields the
   event loop before starting and admits at most one local lookup per
   frame-paced tick, so startup and consecutive imports cannot start competing
   SQLite scans or monopolize the GUI thread.
5. Do not bundle upstream bulk dumps or card art in client release packages.
   Publish the compact searchable SQLite metadata as a separate updateable
   `card-data` release.

Battlefield illustrations are optional assets attached to the selected full
card image. Recognized Scryfall CDN JPEG URLs can acquire their matching
`art_crop` variant during cache requests, match preparation and visible-card
prioritization, including when the complete image is already cached. The
printing UUID and front/back path remain the same; there is no additional
name-based choice of printing or language. Other providers retain the existing
full-image crop fallback. A crop uses at most one shared download slot, behind
queued full-card work. Failure leaves full-card progress and match readiness
unchanged; repeated failures are suppressed briefly and explicit Retry can
repair the optional asset. Image getters and local hydration remain offline.
Cached crops are checked asynchronously before being exposed to the renderer;
repeated reads share the validation result until the file changes or the cache
is refreshed. The renderer keeps the full-card fallback visible until the crop decodes.
Custom artwork retains priority, while hand and inspection views keep the
complete image. No database or resolution-policy migration is needed.

### Language + MTGCH

Preferred network chains:

| Setting | Chinese mode | English mode |
|---------|--------------|--------------|
| Common local first | Reuse verified local art for the same Oracle card, face, and language when enabled | Same |
| Automatic (default) | MTGCH `zhs_image_uris` → exact Scryfall zhs → same-Oracle Scryfall zhs → MTGCH `image_uris` → Scryfall English | Scryfall English → MTGCH `image_uris` |
| Scryfall | Exact Scryfall zhs → same-Oracle Scryfall zhs → MTGCH `zhs_image_uris` → Scryfall English → MTGCH `image_uris` | Scryfall English → MTGCH `image_uris` |
| MTGCH | MTGCH `zhs_image_uris` → exact Scryfall zhs → same-Oracle Scryfall zhs → MTGCH `image_uris` → Scryfall English | MTGCH `image_uris` → Scryfall English |
| Parallel | Split cards between the Scryfall-first and MTGCH-first chains above; exhaust Chinese candidates before English fallback | Split cards between the two provider-first chains above |

Parallel scheduling preserves request deduplication, printing/face identity,
interactive priority, and compatible local-art reuse. Each request owns one
slot until completion, including provider fallback and retry backoff; it does
not race duplicate downloads of the same card. A provider preference change
affects new assignments while existing requests finish with their assigned
chain. Host cooldowns are shared by all workers, so queued requests respect
another worker's rate-limit response. A successful response already in flight
does not clear an unexpired cooldown.

Scryfall's published API rate limit applies to `api.scryfall.com`, not its
`*.scryfall.io` image hosts ([upstream clarification](https://scryfall.com/docs/faqs/i-m-having-trouble-accessing-the-scryfall-api-or-i-m-blocked-17)).
The six-request pool is Hexproof's own bound, not a claimed upstream image
concurrency limit. Parallel mode improves source utilization; actual speed
depends on latency, bandwidth, and available artwork.

Double-faced cards resolve each face independently. Provider metadata must identify the requested
face before its image can be cached; a top-level front-face image is never accepted as the back
face. A legacy whole-card entry with no face marker may be inferred only as the front and reused;
an unmarked entry is never accepted as the back. Other mismatched face entries are ignored and
resolved again.

On upgrade, a versioned local-only audit examines deck printings that already
have at least one cache-index entry. It expands independent double-faced
layouts using the installed catalog, reuses a valid legacy whole-card image as
the front mapping, identifies a genuinely missing back face, and clears the
stale face marker left by older Prepare-card metadata. Printings that were
never cached are outside this repair audit. The audit records only its result;
it does not contact an art provider. When issues are found, the client shows a
one-time notice and keeps **Repair recommended** visible in Settings until the
player reviews and confirms the repair. Only then are missing faces queued for
download. **Settings → Card art storage** remains available
for a manual recheck.

The MTGCH lookup is `GET https://mtgch.com/api/v1/card/{set}/{collector_number}/`.
Set Limited product prefetch may first load
`GET https://mtgch.com/api/v1/set/{set}/cards/?page_size=9999` when Chinese
resolution is MTGCH-first. This is a metadata acceleration path only: missing,
invalid, or unavailable set-index entries continue through the ordinary
per-card provider chain. The same prefetch is available from
**Settings → Download set art** and from Set Sealed or Set Draft registration.
The product manifest is flattened and deduplicated by
name, set, collector number, and face before exact-printing images are queued.
Provider preference changes only future cache misses. It does not delete,
replace, or redownload an existing compatible local image.

Provider-selected language fallback art is tracked separately from
opportunistic local cross-printing reuse. Disabling local reuse must not hide a
previously downloaded Scryfall/MTGCH fallback; exact printing-picker previews
continue to reject both kinds of substitute art.

Art cache requests are identified by language, canonical card name, set code,
and collector number. Distinct printings of the same name must not collapse
into one request. A request without both set code and collector number has no
exact printing identity, so compatible local art remains eligible even when
cross-printing reuse is disabled for explicit versions. Interactive retry
clears the selected requests' negative
cache entries and the temporary provider cooldown before enqueueing them again.
An explicit printing-picker preview is an exact-art request: it may use that
printing's Simplified Chinese image or its English image from either provider,
but it must skip cross-printing Chinese/local-art substitutes. Under an
explicit Scryfall-first configuration, an exact English image already present in the
installed catalog may be used directly instead of repeating metadata fallback
requests.

Card metadata and image requests to Scryfall use HTTP/1.1. Qt's default HTTP/2
multiplexing fails against Scryfall's CDN with protocol errors that abort every
in-flight image at once. Other hosts, including GitHub catalog downloads and
MTGCH, keep HTTP/2. Metadata requests use a 15-second inactivity timeout; card-image
fetches use 30 seconds. A phase may retry once only for transport errors,
HTTP 408/5xx, a timeout, or a successful status with a malformed response.
A remote host closing one image connection is treated like a per-request
timeout rather than proof that the whole CDN is unavailable. Retry attempts
are debug diagnostics; the detailed warning is reserved for a failed phase
that proceeds to another provider.
Retry backoff remains part of the active cache operation: progress stays visible
and exclusive art-index maintenance stays blocked until the request finishes.
HTTP 429 honors a short `Retry-After`; absent or long delays open a provider
cooldown instead of blocking the whole deck. A single image timeout does not
open that cooldown, so other printings can still fetch from the same CDN.
HTTP 400/403/404 are not blindly retried. A provider that remains unavailable
after its retry for a non-timeout failure enters a short per-host cooldown so
later cards fail over without repeating the full timeout.

When Settings language is Chinese and Scryfall is preferred:

```text
need name/art (zh)
  → local cache
  → Scryfall /cards/{set}/{number}/zhs
  → another Scryfall zhs printing with the same oracle_id
  → MTGCH CJK name + zhs_image_uris (set/number)
  → Scryfall English
  → MTGCH English mirror
```

Chinese names are accepted only when they contain a CJK ideograph. Cache
entries persist art-language provenance and a resolution-policy version, so
legacy entries are not trusted blindly. During the policy-5 to policy-6
placeholder migration, an existing local file is upgraded in place when its
exact Scryfall image URL or illustration identity is still a usable row in the
current catalog; non-Scryfall files are retained because this policy change is
Scryfall-specific. Entries that cannot be proven safe, including former
localized placeholder images, are re-resolved. This preserves downloaded art
across the compatible upgrade without restoring images rejected by the new
policy. Future policy changes require an explicit compatibility decision.

With MTGCH preferred, the same flow starts with MTGCH Chinese and later tries
the MTGCH English mirror before Scryfall English. English card mode likewise
uses the selected provider first and keeps the other as fallback.

The release builder understands Scryfall's current `jsonl_download_uri` plus
`compressed_size` streaming-gzip descriptor. It also accepts the legacy
`download_uri` plus `size` JSON-array descriptor. The importer validates each
record, caps compressed and expanded sizes, and builds SQLite without loading
the full catalog into memory.
The release builder also downloads the current MTGCH
[`magic-cards-zhs`](https://github.com/HeliumOctahelide/magic-cards-zhs) name export
(about 75 MiB compressed as of 2026-07-22) and imports only Chinese names, former
names, translated types, and oracle identifiers into the same local SQLite index.
The source export is CC BY-SA 4.0 and is attributed in Settings. Temporary
source archives are not part of the normal client update. If official release
discovery or verification fails, the update stops and preserves the previously
installed database rather than building a partial catalog on the user's device.

The official and ready-to-import database stores a compact
`localized_printings` table built from Scryfall All Cards. It contains only
Simplified Chinese printing identities, localized fields, layout/face
identity, illustration identifiers, and image URLs; it is not a second
database and contains no image bytes. An Oracle-ID Scryfall search fills any
future missing Chinese printing on first use. Valid returned printing rows are
upserted into the same SQLite table, while downloaded image bytes and the
resolved presentation choice remain in the regular local art cache.
Both the primary and localized indexes retain Scryfall's `image_status`.
`missing` and `placeholder` records are metadata-only and never become art
sources; `lowres` and `highres_scan` remain usable. Schema-8 databases do not
contain this proof, so the client validates their Chinese image candidates
online instead of trusting their stored URLs.

### Card image download diagnostics

Card image failures emit a warning in the `hexproof.cardcatalog` logging
category. The warning records the requested card and printing, original and
final URLs, HTTP and network status, selected response headers, payload size
and signature, Qt's detected image format and decoder error, supported image
formats, and Qt plugin search paths. Text or JSON responses include only a
bounded printable preview; binary image bodies are never logged.

Per-request resolution and response logs are disabled by default. Enable them
for a diagnostic run from the repository root:

```sh
QT_LOGGING_RULES='hexproof.cardcatalog.debug=true' \
    ./build/client-qt/hexproof 2>&1 | tee build/card-download.log
```

If Qt cannot load its WebP image plugin, startup emits a warning before any
download because MTGCH card art currently uses WebP.

### Card-art storage management

Ordinary resolution saves the index from an immutable snapshot on a bounded,
coalescing background writer. JSON serialization and disk I/O do not run on the
GUI thread. Synchronous transactional maintenance shares a generation guard
with that writer: an older save cannot restore removed or replaced mappings.
Failed saves retain dirty state for retry, and shutdown flushes the latest
generation before releasing profile ownership.

The application holds a process-wide lock for its application-data directory
before constructing settings, deck, or cache services. A second launch using
that directory shows an explanatory window without opening another writable
library. Independent profiles remain supported. Lock age alone never expires
ownership of a running client; dead-process recovery follows Qt's
[QLockFile contract](https://doc.qt.io/qt-6/qlockfile.html). Clients predating
this guard do not participate in it and should be closed before upgrading.

Settings exposes a card-art storage manager for the existing device-local
cache. The cache remains split into `card-cache.json`, which is the
authoritative lookup index, and the `images/` directory (beside it by default). Existing
downloaded files and index entries remain compatible; opening the manager does
not migrate or redownload them. Inventory is derived from both locations and
reports indexed entries, image files, bytes, missing indexed entries, and
unreferenced files. Indexed entries are grouped by exact set code and the
resolved image language, with their provider provenance retained.

The manager can export the complete indexed cache or one set/language group to
a `.hexproof-artpack` file. Pack format `hexproof.card-art-pack` version 1 is a
portable, application-owned container with a JSON manifest followed by
deduplicated image blobs. It stores printing, face, language, provider, source
URL, resolution-policy version, and SHA-256 identity, but it
never stores an absolute device path. Missing or invalid indexed images are
skipped and reported after export.

Version-1 packs may include an optional artwork blob for each full-card entry.
Its source must match the full image's recognized Scryfall variant. Missing or
invalid local crops are omitted without dropping a usable full card. Import
may supplement an existing full image only with its own crop; a different
winning image never inherits that crop. Old packs and caches remain valid.
All declared blobs, including optional artwork, retain the same validation and
rollback requirements. Inventory, shared-file cleanup and storage relocation
account for both assets.

Pack inspection reads a cache snapshot and can proceed while background card
image lookup or metadata hydration is active, including when that work starts
while the native chooser is open. Storage relocation, catalog replacement and
other art maintenance still block inspection. A rejected inspection clears the
previous preview and reports completion with an error. Import writes continue
to require exclusive cache access.

Import validates the container version and bounded manifest, entry, image, and
total sizes before writing anything to the index. Every image blob must match
its declared byte count and SHA-256 and decode as a supported image within the
dimension and pixel limits, including blobs for already-cached entries. New
imported files use content-addressed names under `images/`. A pack can reuse
matching bytes from its existing managed mappings for new aliases or metadata
upgrades instead of creating another file. An existing valid entry with an
equal or newer resolution-policy version wins over the imported entry. Blobs
used only by such retained entries are validated but are not written as unused
copies. Source URLs are retained only for known HTTPS Scryfall or MTGCH hosts. Imports never
trust archive paths, and an invalid pack cannot replace the current index.
New image files belong to the import transaction until its index commit
succeeds. Late blob failures, failed index saves, and orderly shutdown before
completion roll back only those newly created, unreferenced files. Files that
existed before the import and files referenced by the restored index remain.

Cleanup can remove unreferenced image files, one set/language group, or all
card art. Group deletion commits the index first and then deletes only files
that no remaining entry references; shared image files are preserved. File
removal is restricted to ordinary, non-symlink files inside the managed image
directory. Card metadata databases and deck lists are never removed. Scanning,
validation, import, export, and cleanup run on the catalog-maintenance worker;
new art resolution pauses while a management operation owns the cache.
Index commits also run in the background. Maintenance remains busy until its
own index generation has been saved; an older download-cache save cannot mark
the operation complete. Imported mappings and subsequent library display
refreshes yield between bounded batches. Custom-art previews build their
display/lookup snapshots and remove discarded staging directories on workers.
Image-arrival notifications shared by visible cards are coalesced within a
frame while individual cache-completion events remain independent.

Card-art packs are a player-to-player transport, not a release bundle or a
server feature. The room server still receives no image bytes. The UI reminds
players that upstream image rights and sharing permission remain their
responsibility.

Local custom artwork has a separate index, image tree, manager and explicit
sharing format. The image location can be changed with verified, source-retaining
copy followed by restart; neither operation changes the deck or server identity.
See [Local custom card art](custom-card-art.md) for scopes, independent faces,
bulk mapping, pack validation and migration behavior.

## Catalog search behavior

- Group results by canonical English card name; select an exact printing after a
  card enters the main deck or sideboard. The deck row thumbnail and the
  set/collector control both open the printing picker; a card without a set yet
  still shows **Select printing**. Cached art is displayed from the local image
  cache even when the deck list has not stored `imagePath`. The printing picker
  shows the selected version's exact card image before the player confirms the
  change. A same-card local-art substitute may remain useful elsewhere, but it
  must not stand in for a different set/collector preview.
  Preview uses the local art cache and the catalog's HTTP/1.1 download path; it
  does not fetch Scryfall URLs through QML `Image`. While that download is in
  flight the picker stays on a loading state and refreshes when the catalog
  cache reports the file, instead of treating an empty first look as a missing
  printing.
- Search canonical English names, Scryfall printed names, MTGCH Simplified Chinese
  names, and former Chinese translations.
- Rank exact, prefix, substring, then character-subsequence fuzzy matches.
- The deck editor exposes type, set, printing-language, color-identity, rarity,
  and all format legalities carried by the current Scryfall catalog in the
  search popup. Filter-only browsing is supported; legality never becomes a
  deck-construction gate.
- Search opens a centered catalog popup, like the token picker: a search field,
  filters, and a card-art gallery. Search first, select a result, then add one
  copy to the main deck, sideboard, or Consider. Commander and Cube omit
  Sideboard. The popup does not show or edit the live deck list; counts stay in
  the editor. Existing count limits still apply. Color shortcuts remain on the
  toolbar; advanced filters have a scrollable body. Overflowing results keep a
  high-contrast scrollbar.
- Color choices require every selected color, including cards that also have
  additional colors. Type, rarity, and mana-value choices support OR within
  each category, and different categories combine with AND. Database predicates
  run before the existing 40-result limit. Search remains generation-tagged and asynchronous.
  A query or filter edit immediately removes the previous clickable results,
  including the debounce interval before the next database request starts.
  Closing the workspace releases its result delegates; late replies must not
  recreate a hidden gallery or enqueue its previews.
  Replacing the installed catalog invalidates pending searches and clears their
  results immediately. When replacement finishes or fails, only the latest
  still-requested query is searched again; closing search during replacement
  must not revive it afterward.
- Saved cards retain optional rarity metadata, refreshed by the existing
  background catalog batch. Old libraries stay compatible and missing rarity
  metadata is backfilled without downloading art.
- Catalogs without Chinese aliases remain usable for basic English search but
  are marked **Update needed** until rebuilt with the Chinese name index.

## Damaged local files

The client stores the deck library, its preferences, and the resolved card-art
cache as separate JSON files under the application data directory. A file that
fails to parse is never treated as an empty one, because the next save would
overwrite it and destroy the remaining content with no diagnostic. Instead the
damaged file is renamed with a `.corrupt-<epoch-ms>` suffix and the client
continues from an empty state for that file only:

- The deck library reports the preserved path so the player can recover decks. If
  the rename fails, the library becomes read-only rather than losing decks.
- Preferences fall back to defaults (language, interface scale, table layout). If
  the rename fails, later preference saves are refused so the damaged file stays
  the only copy.
- The card-art cache is rebuilt by re-resolving art, so only network work is lost.

## Out of scope for editor without a current full DB

- Free search-add across all cards.  
- Verified named-format legality; the deck remains explicitly unverified.
- Online cloud deck accounts.

## Token and emblem database

Separate from (or alongside) the full card metadata DB:

- User can **download/update a token catalog**.
- Source may be Scryfall token-related data or an equivalent documented,
  redistributable user-local cache.
- Used for **in-game Tokens and emblems** (and art fetch), not for main-deck building legality.
- The shared picker has All, Tokens, and Emblems filters applied before the
  catalog result limit. Token results include double-faced tokens; emblems use
  their own `emblem` layout. Ordinary playable-card search excludes these
  auxiliary layouts. Search results and saved deck entries preserve the kind.
- Token and emblem art follows the independent **card language** setting, not
  the interface language. Chinese mode uses the same provider chain as normal
  cards: Chinese images first, English images when no usable Chinese image is
  available. Existing English files are retained but do not satisfy an
  unresolved Chinese request.
- Token search accepts canonical English names/types and indexed Simplified
  Chinese aliases/types. In Chinese card mode it displays the localized alias
  while preserving the English name, set code, and collector number as the
  canonical game identity.
- The in-game token picker lists the active deck's saved token printings first,
  removes duplicates from the general catalog results, and continues to search
  the complete token catalog below them. Saved entries remain selectable if the
  catalog is temporarily unavailable, although full search requires the catalog.
- The picker, saved-entry manager and emblem browser show localized names,
  types and rules text when available. Missing Chinese artwork does not discard
  Chinese rules text; the detail view can show an English image with readable,
  scrollable Chinese rules. Missing translations fall back to English rather
  than generated translations. Resolved rules text is retained with the cache
  for offline use, separately from the artwork's actual language.
- Explicit hover, detail and selected-emblem requests take priority over
  background result-list prefetching. Transient metadata failures do not mark
  Chinese rules as permanently checked; later requests can retry under the
  existing provider cooldown policy without discarding usable cached artwork
  or previously resolved Chinese text.
- Saved emblems use the same language-aware caching and deck cache/repair paths
  as tokens. Existing full catalogs already containing emblem records need no
  database rebuild for manual search and selection. Automatic planeswalker-to-
  emblem recommendations via Scryfall `all_parts` are not implemented by this
  change; players explicitly save or select the desired printings.

## Art / metadata pipeline (with multiplayer)

1. **Import:** persist the list locally. **Cache art** (or a later search-add /
   printing change) downloads missing info + images → local cache. Transform,
   modal double-faced, double-faced token, and reversible cards expand into
   independent requests for every face. Single-image multi-characteristic
   layouts such as split, adventure, and prepare cards retain their top-level
   art instead of being mislabeled as an independent reverse face.
2. **Room Ready:** every client receives the aggregate selected-deck printing
   keys. A `preload` room expands supported double-faced printings and waits for
   every face before play; a `background` room enters immediately and queues
   every face without blocking.
   The client checks compatible local files and custom-art overrides in bounded
   batches before requesting missing art. The loading screen distinguishes all
   deduplicated assets (including independent faces), assets available locally,
   and completed/missing downloads. Local hits contribute to readiness without
   entering the download count or starting network requests. Failed downloads
   remain retryable and are not counted as downloaded assets.
3. **In match:** prefer cache; background loading prioritizes the viewer's
   currently visible cards, then completes the remaining match set.

Server still does **not** bulk-host card JPEGs; it may share **deck card-name lists** (or equivalent ids) at ready time so clients know what to fetch.
