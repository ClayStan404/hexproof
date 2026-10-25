# Hexproof user guide

[简体中文版](user-guide.zh-CN.md)

- Audience: players and table hosts
- Applies to: Hexproof 3.1.0 and `hexproof.v2` hubs; unreleased changes are marked explicitly
- Updated: 2026-10-25

Hexproof provides manual Magic: The Gathering tables and optional Forge rules
rooms. Manual tables synchronize cards, zones, counters, life and public logs;
players resolve card text, priority, triggers and targets themselves. Forge
rooms use the selected rules engine for supported game actions. Local catalog
deck checks remain distinct from a game's rules mode.

Client and hub game protocols must match (`hexproof.v2` for 3.1.0); application
versions may differ while that protocol remains compatible. A 3.0.0/v1 client
must update before joining a v2 hub.

## 1. First launch

1. Open **Settings** and choose a category.
2. In **Language & cards** and **Appearance**, choose the interface language,
   card language/art preference, and interface scale.
3. In **Card database**, install or import a searchable card database.
4. Open **Deck library** and import at least one deck.
5. Connect to a hub before creating, joining, browsing, or starting
   a Playtest.

The deck library, deck editor, settings, installed database, and downloaded
card images are local to the current computer. Online rooms synchronize game
state, not image files.

## 2. Window and common navigation

- **Back** returns to the previous screen without disconnecting unless the
  current action explicitly says that it leaves a room.
- Pages opened from a waiting room, such as the deck library, cover the room;
  returning keeps the room session alive.
- Confirmation dialogs protect destructive actions such as deleting a deck,
  disbanding a room, and conceding.
- Hover a visible card to show a large art-only preview beside the pointer.
- `F11` toggles native full-screen mode.
- Below 1100 px wide, the main menu and waiting room stack into a single
  column and the table uses narrower rails. The window minimum is 900×620.
  The compact home page omits the decorative hero so play controls appear first.
  On a wide window the hero names Manual, Forge, and Limited.

## 3. Main menu

### Connection controls

- **Connect to server** opens the connection form.
- The status pill shows **Offline** or the current display name.
- The brand stays at the upper left; Settings, update notices, player/server
  status, and Disconnect stay right-aligned. Narrow windows and larger interface
  scales wrap these controls below the brand without hiding the server status.
- **Disconnect** closes the hub session. If the player is in a room, this also
  leaves that room.

### Play controls

- **Create room** creates a multiplayer table for the selected deck format.
- **Playtest** creates a private one-seat practice table.
- **Join with room code** joins a known six-character room code.
- **Browse hub** lists joinable multiplayer rooms on the connected hub.
- **Events** lists tournaments and provides the shared **Create tournament**
  entry for constructed, Set Sealed, and Set Draft events.

These controls require a live hub connection and are disabled while offline or
already in a room.

### Local controls

- **Deck library** is always available, including offline.
- **Settings** opens categories for appearance, language, card data, shortcuts,
  updates, and local Forge. Each category is a separate screen.
- **Pack simulator**, beside Browse hub, opens the local pack simulator, including
  offline. It does not create an online event or change a deck.
- **Sponsors & thanks** shows bundled avatars and sponsor groups from highest
  to lowest: Omniscience, Dockside Extortionist, and Ragavan, Nimble Pilferer.
  Sponsor profile buttons, when present, open in the system browser.
- **Feedback** opens a local composer and **My feedback** history, including
  offline. See [feedback and reports](#17-feedback-and-reports).
- **Quit Hexproof** closes the application.

The sponsor acknowledgement opens on the first launch of each application
version. Closing it or opening the full list remembers that version locally;
later launches of the same version do not repeat it. A new version shows it once
again.

## 4. Connect to a server

The connection screen contains:

- **Server**: choose **Official lobby (automatic)**, a configured official node,
  or **Custom server**. The directory supplies the current names and endpoints;
  do not depend on a fixed numbered server list. The automatic lobby routes
  rooms and events across available official nodes. Custom addresses use
  `ws://` or `wss://` and are saved locally. Health/latency checks show an
  unavailable endpoint explicitly.
- **Display name**: the name shown to room members during guest play. Official
  account sign-in is separate; see [accounts](accounts.md). This client remembers the last name used here and prefills
  it the next time the form opens, including after disconnect or restart.
- **Connect**: starts the WebSocket session. **Back** leaves the page and
  cancels a connection that has not finished.

After the connection succeeds, the top-right status area shows both the
session display name and the actual connected server label. Latency refreshes
do not change the server selected in the connection form.

Connection failures appear in the page banner. During an unexpected network
drop, table actions are disabled while Hexproof tries to restore the held seat.
The normal reconnect window is three minutes.

## 5. Solo Playtest

Playtest uses the real authoritative table flow with no opponent.

1. Connect to a hub.
2. Select **Playtest** on the main menu.
3. Choose the deck format. Custom, Standard, Pioneer, Modern, Legacy, Vintage,
   and Pauper use the ordinary 20-life 1v1 table:
   - Duel Commander starts at 20 life and keeps the command zone and commander tax.
   - Commander starts at 40 life and keeps the command zone and commander tax.
4. Choose the card-image loading policy:
   - **Preload before game** downloads every required image before opening the
     table.
   - **Load in background** opens immediately, prioritizes visible cards, and
     downloads the remainder in the background.
5. Select **Create playtest**.
6. Select a compatible ready deck and choose **Ready up**.

Playtest is BO1, has one seat, accepts no opponents or spectators, is not shown
in the hub room browser, and is not kept as a multiplayer replay. Its single
battlefield fills the table. Use **End playtest** to return to the main menu;
there is no Concede action in this mode.

Playtest remains manual: it does not execute card text or validate actions.

## 6. Create a multiplayer room

The creation screen provides:

- **Room name**: starts empty, without an example name; enter the title to show
  in the waiting room and room browser.
- **Format**:
  - **Custom, Standard, Pioneer, Modern, Legacy, Vintage, or Pauper** creates
    two ordinary 20-life seats. Custom applies no card-pool policy; named
    formats use local advisory deck validation.
  - **Duel Commander · 2** creates two player seats at 20 life with command
    zones. Manual rooms keep manual commander tax; Forge rules handle legal
    casting and tax. Deck construction and ban-list advice use the local catalog.
  - **Commander · 3–4** provides four player seats and may start once three or
    four seated players are Ready.
  - **Cube** creates a two-to-eight-player draft room from a saved Cube deck.
    Players take seats, get ready, draft, and build decks before choosing
    opponents for free play. This is not a tournament; use **Events → Create
    tournament → Cube draft** for Swiss rounds instead.
- **Match**:
  - **BO 1** plays one game.
  - **BO 3** is available for commander-free 1v1 and Duel Commander. Commander-free 1v1 uses
    between-game sideboarding; Duel Commander keeps the registered deck fixed.
  - Commander is always one multiplayer game.
- **Allow spectators**: permits up to eight spectators to view public state.
- **Spectators can see hands**: when enabled, every spectator can continuously
  inspect every player's current hand. It does not let players inspect each
  other's hands and remains fixed for the lifetime of the room. The room
  browser and waiting room display a warning when enabled.
- **Card images**: choose preload or background loading.
- **Room password**: optional access control in addition to the room code.
- **Create room**: enters the waiting room as host in seat one.

For native AI practice, choose **Forge rules**, an ordinary constructed format or
**Duel Commander**, then **Forge AI**. Practice always uses BO1. Choose your deck
and **Select AI deck** independently in the waiting room, select a difficulty,
and get ready. Duel Commander uses 20 life; both decks retain the 100-card policy
and their designated commanders. Forge handles casting, command-zone return
choices and each commander's tax. If the selected hosting option lacks Duel AI
support, creation remains unavailable. Local/online model opponents retain their
ordinary constructed scope; Commander/EDH does not offer AI practice.

Ordinary table hosts can copy the generated room code, remove non-host players
or spectators, and disband the room. In a Cube room, the host starts the draft
after everyone is ready; leaving as host requires confirmation and closes the
Cube room for everyone.

On a normal desktop window the form uses two compact columns. Short forms sit
in the vertical center with Cancel and Create on the card. If Cube or
player-host options overflow, the card scrolls so those actions stay reachable.
At narrow widths or enlarged interface scale, the columns stack and the form
scrolls.

## 7. Join and browse rooms

### Join with a code

- Enter the six-character **Room code**.
- Choose **Player** or **Spectator**.
- Enter the password when the room is protected.
- Select **Join table** or **Watch room**.

A player join fails when all format seats are occupied. Spectator joins require
host permission and an available spectator slot.

### Browse the connected hub

The room browser shows only multiplayer rooms on the current hub:

- room name, code, format, and BO1/BO3;
- occupied player and spectator counts;
- waiting/loading/in-game state;
- password status;
- server-authoritative **Join** and **Watch** availability.

Cube free-play rooms appear here too, with waiting, drafting, deck-building,
or free-play status. Join one from this list or with its room code; no event
registration or check-in is needed. New players cannot join after drafting
starts, but returning players can restore their original seat and pool.

The summary count is the unfiltered hub list. Each listed row is one of those
rooms; a non-zero count never appears with an empty table unless a search or
filter is hiding every match.

Filter the list by joinability, waiting vs in-game, password, and table type,
search by name or room code, and sort joinable tables first, by name, or by
open seats. Use **Refresh** to request a new list. Password-protected entries
route through the join form.

## 8. Waiting room and match loading

### Waiting room

- The seat list shows occupation, host, deck selection, and Ready state.
- **Select deck** lists compatible local decks. Preload rooms require every card
  image before selection; background-loading rooms allow a structurally valid
  deck to be selected while its missing images continue downloading.
- **Ready up** becomes available after every required seat is occupied and the
  local player has selected a deck.
- **Cancel ready** returns the player to an editable state.
- Changing the selected deck clears Ready.
- **Deck library** opens the local library without leaving the room.
- **Leave room** gives up the seat and returns to the main menu.
- The host can **Remove** another member or **Disband room**.
- Below 1100 px wide, **Deck library**, **Leave room**, and **Disband room**
  move into a **More** menu so Ready stays visible.

There is no Start button. All players Ready causes the selected loading policy
to start automatically.

### Preload screen

- The progress bar counts resolved match cards.
- Each seat shows whether its client has completed loading.
- **Retry failed downloads** retries failed metadata/art requests.
- **Cancel ready** cancels the local Ready state and returns the room to
  waiting.
- **Leave room** exits the room.

Background-loading rooms skip this blocking screen.

## 9. Deck library

### Deck list

- Filter by **All** or any supported deck format.
- Each row shows format, mainboard count, sideboard count, commander, and local
  readiness.
- Double-click a row or select **Edit** to open the deck editor.
- **Export** copies the deck list or saves a `.txt` file with explicit `Deck`,
  `Sideboard`, `Commander`, and optional `Consider` headings so the same text
  can be imported again.
- **Export → Export card art…** packages only that deck's downloaded images into
  a `.hexproof-artpack`, useful for sharing a large Cube. It includes locally
  available languages, reverse faces, and saved tokens/emblems, but does not
  download missing images or include the deck list itself. The result reports
  missing or invalid art; cache/repair it first if you need a complete pack.
- **Delete** removes only the local deck list. Shared downloaded art remains
  cached.
- **Import deck** opens the text/file importer.
- **Cache art** downloads missing images for every local deck.
- **Retry failed downloads** retries failed metadata/art requests for the
  library.
- **Settings** opens the settings categories, including card database and
  language.

A deck is not ready when it fails operational checks, has unresolved required
card data/art, or has a blocking verified violation for its named format.
Named formats check deck size, sideboard size, copy limits, Scryfall
legality/restrictions, and commander singleton/color identity where applicable.
Commander/EDH card-pool findings, including banned, not-yet-legal, and locally
unresolved cards, are advisory and do not prevent selection. A Commander/EDH
main deck that is not exactly 100 cards is also reported as an advisory warning.
Commander color identity is advisory: the status groups mismatches into one
warning and its tooltip lists the affected cards. Duel Commander retains the
ordinary size and card-pool gates. Missing or outdated catalog data displays an
unverified warning rather than a false violation.

### Import a deck

1. Enter a deck name.
2. Choose Custom, Standard, Pioneer, Modern, Legacy, Vintage, Pauper, Duel
   Commander, or Commander.
3. Paste a Moxfield/common plain-text deck export, or select **Choose file…**
   to load a local UTF-8 `.txt`/`.dec` list. The selected text remains editable,
   and an empty deck-name field uses the file name as its initial value.
4. Select **Import deck**.

The button immediately changes to a parsing state. Large Commander lists are
parsed in the background. Import saves the list locally, then performs a
local-only lookup that restores compatible card art already in the cache. The
missing-art count therefore reflects files that are actually absent. This
lookup never accesses the network, and import does not download art for the
whole deck. Saved decks with missing paths receive the same local-only lookup
at startup, after a card-language change, and after a catalog replacement.

Typical lines include:

```text
Deck
4 Lightning Bolt (M11) 149
1 Sol Ring

Sideboard
2 Wear // Tear

Commander

Consider
1 Doubling Season
```

**Export** writes this same form (commander cards only under
`Commander`, with `*CMDR*`) to the clipboard or a UTF-8 `.txt` file. Local
token preferences are not included. Importing that text restores mainboard,
sideboard, designated commanders, and optional Consider cards.

Recognized mainboard and sideboard entries are saved locally. Type and category
come from the installed local catalog; they do not wait on **Cache art**.
Choose printings in the editor if needed, then select **Cache art** to download
remaining missing images. Adding a card from search or changing a printing
downloads that one image immediately.

### Deck editor

- Changes save automatically. Click the header title to rename the deck.
- Use the format selector to change the current deck without re-importing it.
  Changes between ordinary 1v1 formats apply directly. Crossing into a
  commander format asks for confirmation, moves all sideboard cards into the
  main deck, and clears commander selection. Crossing back clears commander
  designations but keeps those cards in the main deck. No card is deleted.
- **More → Export** on the editor copies or saves the current deck in the same
  `Deck` / `Sideboard` / `Commander` / optional `Consider` text format.
  **Export card art…** shares the current deck's cached images instead.
- **More → Cache deck art** downloads remaining missing images for the current
  deck. Search, Consider, and Tokens stay on the main editor toolbar.
- The deck-local search filters cards already in the current deck.
- Use **View** to switch between the compact list and the visual card-art
  editor. Category headings show physical-copy totals. The visual editor keeps
  a large preview visible and can group by card type, mana value, or no
  grouping, then sort by name, mana value, or card type.
- The database search opens a catalog popup for finding and adding cards, like
  the token picker. It does not edit the live main-deck list inside the popup.
  It accepts English or Chinese card names and can filter by card type, set
  code, printing language, color identity, rarity, and every format legality
  carried by the current Scryfall catalog. This includes major paper formats,
  Commander variants, Arena formats, and community formats. Filters can be used
  without entering a name. Search first, select a result, then add it to the
  main deck, sideboard, or Consider. Commander and Cube decks omit Sideboard.
  Named decks are also validated asynchronously using the installed catalog;
  hover the deck status to see all detected issues.
- Use `+` and `−` to change copy count.
- Use **To side** / **To main**, or drag the row by its `⋮⋮` handle between the
  mainboard and sideboard.
- **Consider** opens a separate large manager so tentative cards do not consume
  the main editor layout. Add cards from database search, adjust their counts,
  or move one copy between Consider and the main deck. Consider is saved and
  exported, but it is editor-only: it is not registered for a game, validated
  as part of the deck, or used as a sideboard.
- Click the card thumbnail or the set/collector button to choose a different
  printing and preview its exact art. Preview downloads through the same local
  catalog cache as the rest of the client, not a direct website image request.
  The picker waits for that cached file and then shows it; it does not flash
  “no image for this version” while the download is still finishing.
  If that printing has no Simplified Chinese image, the picker loads the exact
  printing's English image instead of substituting another printing.
  A slow or timed-out CDN fetch is retried and does not disable other
  printings of the same card.
  Cards that do not yet have a set still expose **Select printing**. Cached art
  is shown even before **Cache art** writes the path into the deck list.
- In Duel Commander or Commander, use `☆`/`★` beside a main-deck card to designate or remove up
  to two commanders. Designated commanders stay in their card-type group,
  usually Creatures, with a Commander mark. There is no separate commander
  panel, so the gallery can use the full width.
- Mainboard cards default to type groups that distinguish creatures,
  planeswalkers, battles, artifacts, enchantments, instants, sorceries, lands,
  and other cards. The separate sideboard region is hidden for commander-format
  deck construction. Catalog search and token management stay in the main
  toolbar.

Hexproof remains a manual-tabletop tool. The editor allows arbitrary changes;
named-format violations are reported and block room selection only after a
current catalog verifies them, except Commander/EDH card-pool and color-identity
findings, which remain advisory. Card-text-driven exceptions that cannot be
determined safely remain the players' responsibility.

## 10. Settings and card databases

Settings is a list of categories. Open a category to change only that group;
**Back** returns to the category list.

### Language and display

- **Interface language** changes menus and application text.
- **Appearance** chooses Classic (the default forest-green interface) or Glass
  (Apple-style frost panels over a night menu backdrop). The choice is stored
  on this client only. Previously saved
  `themeId` values are ignored.
- **Battlefield background** starts with **Default background**, which uses no
  image. You can also independently select Dusk ruins, Emerald
  sanctuary, Arcane stars, Obsidian wastes, Silent frostlands, Ink mountains,
  or Woven sand. Click a thumbnail to apply it immediately. All backgrounds
  work with both appearances in manual and Forge games; changing appearance
  preserves the selected background. Select **Default background** to remove
  the image and restore the plain battlefield. The choice is saved on this device.
  During a manual game, open **Table layout → Battlefield background…**;
  Forge games have a **Background** button in the top-right Settings drawer. The picker scrolls
  on smaller windows. Installations without a saved background choice use
  Default background; existing image selections are preserved.
- **Card language and art** independently selects English or Simplified
  Chinese card presentation. Public names on the Forge battlefield, stack,
  commander strip, and card inspector follow this setting when the local
  catalog has a translation; menus still follow **Interface language**.
- **Preferred card art source** selects Automatic (default), Scryfall, or MTGCH
  for future downloads. Automatic prefers MTGCH for Chinese cards and Scryfall
  for English cards. Existing compatible local art always remains first, and a
  missing or unavailable preferred image automatically falls back to the other
  source. Chinese mode keeps Chinese candidates ahead of English candidates.
- **Prefer existing local art for the same card** is enabled by default. If the
  requested printing is not cached, Cache art and room preloading may reuse a
  cached printing of the same card, face, and card language. This avoids a
  duplicate image download without changing the printing identity used by the
  deck or server. Choosing a printing explicitly in the deck editor still
  fetches that exact printing. Disabling the option stops opportunistic local
  cross-printing reuse, but does not hide a Scryfall/MTGCH image already chosen
  by the card-language fallback chain. A deck-list entry with no set or
  collector number has no exact printing to preserve, so it always adopts
  compatible local art first even when this option is disabled.
- **Interface scale** adjusts theme-aware text, controls, spacing, and dialogs
  from 75% to 150% in 5% steps. **Reset to 100%** restores the default.

### Application updates

Open **Settings → Application updates**. Compare **Installed version** with
**Latest version**, then select **Check updates**. Hexproof first asks GitHub's
Releases API for the latest stable package for this device. If that API is
rate-limited or unreachable, it reads the public release `SHA256SUMS` on
github.com instead.

A failed live check keeps the last verified release as **cached** and shows
**Check failed**. That cache is not proof that the installed build is current.
Download still verifies the package against `SHA256SUMS` before offering the
folder. Exit Hexproof before replacing the portable application.

### Download set art

Open **Settings → Download set art** to cache every distinct printing and
independent face from an installed set or booster product, without opening a
Limited event. Search by set code, localized set name, or product name. The
download uses the current card language and preferred art source and keeps
compatible local images. The same screen is also available from **Settings →
Card art storage → Download set art…**. Set Sealed and Set Draft registration
lobbies still offer this action for the event product.

### Card art storage

Open **Settings → Card art storage** to inspect images already
downloaded on this computer. The overview shows disk usage, image-file and
index counts, and files no longer referenced by the cache index. Cached art is
grouped by set code and image language; use the filter to find a set, language,
or source provider.

Use **Check and repair** to inspect previously cached deck printings for an
independent double-faced back that was not cached by an older client, or for an
outdated special-card face mapping. The check reads only the local deck
library, catalog, cache index, and image files. It does not download anything.
If a repair is needed, Hexproof shows the number of local mappings it can reuse
and the number of missing faces before asking for confirmation. Confirming
repairs the mappings first, then downloads only the genuinely missing faces.
Printings that have never been cached are ignored by this check.

After upgrading from an affected cache version, Hexproof runs that local check
once. If it finds an issue, the main menu shows one notice on this device and
Settings keeps a **Repair recommended** marker until the repair succeeds.
Closing the notice does not repair or download anything; the permanent manual
action remains available under Card art storage.

- Select **Export all…** to create one portable `.hexproof-artpack`, or use a
  group's **Export…** action to share only that set and language.
  To share a single deck or Cube across multiple sets, use the deck library or
  editor's **Export → Export card art…** action. Import that pack here using the
  same **Import pack…** action; no server connection is needed.
- Select **Import pack…**, review its version, image count, size, new entries,
  and already-cached entries, then confirm. Hexproof verifies each image and
  keeps an existing valid entry when it uses an equal or newer cache policy.
- Select **Remove unused files** to delete only files not referenced by the
  index. Deleting a group preserves any image still shared by another group.
  **Delete all card art** removes downloaded art but leaves card databases and
  deck lists intact; needed images can be downloaded again later.

The pack contains no absolute path from the exporting computer. Imported
images are deduplicated by content, so importing overlapping packs does not
store another copy of the same image. Card art originates from third-party
providers; share packs only where you have permission to share those images.

### Card database

Hexproof uses one searchable database: **Default Cards**. It contains all
Scryfall printing-level metadata needed for search, printing choice, collector
detail, tokens, and emblems. It replaces the former Oracle/Default choice.

The application normally downloads Hexproof's prebuilt compressed Default
Cards database. It already combines Default Cards, the current MTGCH Chinese
name index, and a compact Scryfall Simplified Chinese printing index in the same
SQLite file. The release manifest, compressed file, and expanded database are
validated by byte size and SHA-256 before the existing database is atomically
replaced. The index stores image URLs and printing/face identity, not image
bytes. Card images are fetched and cached only when used.

### Download or update

1. Open **Settings → Card database**.
2. Compare **Installed version** and **Latest version**. Each row shows the
   database build date and schema version. Select **Check updates** to refresh
   the release manifest manually.
3. Select **Download Default** or **Update now**.
4. Confirm the network download and keep the application open until the
   verified database is installed.

Downloading again performs an update. Hexproof downloads a prebuilt release;
it does not rebuild the database from Scryfall or MTGCH on the player's device.
If the repository/release is temporarily unavailable, **Latest version** is
shown as unavailable and the existing database is preserved. Offline `.sqlite`,
`.sqlite.gz`, or `.db` import remains available.

When a later Scryfall lookup discovers a missing Simplified Chinese printing,
Hexproof stores the valid printing metadata in this same database and caches
the image separately. Future resolutions can therefore remain local.
Scryfall records marked `missing` or `placeholder` are not treated as card
art, even when they expose an image URL. Low-resolution scans remain usable.
For an exact printing whose localized entry is only a placeholder, Hexproof
falls back to that printing's English scan instead of displaying Scryfall's
“Localized Image Not Available” card.
After an art-resolution policy update, Hexproof keeps compatible local files.
It validates prior Scryfall mappings against the installed database as cards
are requested and upgrades safe cache entries in place. Only mappings that can
no longer be verified are resolved again, so deleting and re-importing a deck
does not normally download its existing art again.

### Import an offline database

1. Obtain a Hexproof `.sqlite`, `.sqlite.gz`, or `.db` package, or a supported
   Scryfall `.json`/`.gz` bulk source.
2. Under **Default Cards**, select **Import…**.
3. Choose the local file.
4. Wait for validation/copying or raw-data indexing to finish.

For the official GitHub card-data asset, import
`hexproof-default-cards.sqlite.gz` under **Default Cards**. The client
decompresses that gzip package before installing it, the same way **Download
Default** does. An uncompressed `hexproof-default-cards.sqlite` from a
distributable bundle also works. Both already contain the Chinese alias and
compact Chinese-printing indexes.

The current client requires catalog schema version 10. It retains Scryfall's
image-status metadata so missing and placeholder scans can be rejected, in
addition to the per-format legality statuses introduced by schema 8. Download
or rebuild the current package instead of importing an older bundle. A schema
mismatch is reported before the installed database is changed.

In that bundle, `import/` contains the single ready-to-use SQLite database.
`source/` contains only the Scryfall and MTGCH inputs retained for
reproducibility; `manifest.json` and `SHA256SUMS` describe and verify the
bundle. A raw Scryfall `.jsonl.gz` import can rebuild the English catalog but
does not automatically merge the adjacent MTGCH archive, and the MTGCH
`.tar.gz` is not a standalone import file.

The import is atomic: a valid imported database replaces the installed primary
database only after validation succeeds. Hexproof then uses the installed
`cards.sqlite` copy in its application data directory, not the original bundle
file.

### Import an offline Forge rules engine

Only the player hosting Forge on their computer needs the local rules engine.
If downloads are slow, obtain a shared `.hexproof-forgepack` for your system
(Windows x64, Linux x64, or macOS Apple Silicon).

1. Open **Settings → Local Forge**.
2. Select **Import offline pack** and choose the file without extracting it.
3. Wait for verification and installation to report that the rules engine is ready.

The pack includes both Forge and Java; import needs no network download. Keep at
least 1 GiB free for preparation. Packs must match the client's runtime version
and this computer's platform. A damaged or mismatched file is rejected; a failed
or cancelled import preserves the installed runtime. After installation the
shared file is no longer required. Joining the host's game still requires a
server connection.

If preparation, import or local hosting fails, choose **Export hosting
diagnostics** in the same dialog and send the saved JSON file with the steps
that triggered the problem. The report includes system and version information,
timed installation/hosting events and structured failure reasons. Recent history
is retained locally across client restarts; export soon after the failure so it
is not replaced by later activity. Reports exclude decks, cards, connection
credentials, server/mirror URLs, local paths and raw engine output. Export saves
a file on this computer; it does not upload it automatically.

**Send feedback with these diagnostics** opens the feedback composer with a
visible copy of this report. Add a description and review the attachment before
pressing **Send feedback**. Opening this form does not submit the report.

### Enable player direct connection (P2P)

In a two-player Forge room created with **Host on this computer**, the
lower-left waiting-room footer groups host status, compact **P2P** controls,
and **Downloads and diagnostics**. During a game, open the top-right
**Settings** button for the same P2P controls, Full control, log/chat, and
phase stops. The pass plate sits in the bottom-right corner; in two-player
games cards stay clear of that corner, so choices open there without moving
them. A tall choice can cover the battlefield; use **Hide choice** beside it
to look underneath and **Show choice** to return. If Forge is still processing
your last answer, clicking a highlighted card or player shows **Waiting for the
game** and sends nothing. A tapped card stays upright, its art darkens, and a large tap mark appears on the art. A card that changes slot
is clickable at its new place at once. A pile's
badge shows how many copies it holds and how many are new. Tapped copies of that card sit in the next pile. Clicking a
pile uses the card you clicked, or fans the pile out when its copies differ,
for example when one is blocking. Return or the badge also fans a pile, and
Escape folds it. In a pile of matching
lands, click the exposed corner of the spent land to undo that mana. An attacker
with only one legal destination attacks it on the first click. **Attack with all**
sends every ready creature at the defending player, or asks which player when
there are several; it is unavailable when only planeswalkers or battles can be
attacked. A blocker with only one legal attacker blocks it on the first click.
**Block with all** assigns every such blocker, and leaves a creature that can
block several attackers for you to choose. On three- and four-player tables the
decision panel covers the corner instead of pushing cards aside. Tall choices
offer **Hide choice** there as well. The two most recent public log lines stay
under the phase track while the log is closed; click that strip to open the
log. While a mana payment is being answered, further lands can be
queued, several from one pile if you like; a number marks each one, and the game
plays them in order if that payment is still the one being paid. An error or a
timeout clears the queue. Cards slide into a new slot and markers fly
between zones. A click still uses the card's new place at once.
`HEXPROOF_MOTION=0` turns those animations off.
**Show log / chat** opens a
floating panel over the playmat; drag
its title to move it, drag the lower-right corner to resize it, or
right-click the title to restore the default size and place below
Settings. The board and pass plate stay put.

**Settings → Gameplay → Prefer direct connection (P2P)** is enabled by default.
Direct connections share network addresses with the other player and use a STUN
service. Both human players must have this preference enabled.
The status first waits for the other player, then reports connection progress
or **Direct connection active**. If direct delivery fails, play uses server
relay; choose **Retry direct** to try again or **Use relay only** to turn it off.
The preference is saved across rooms and restarts; choose **Enable direct
connection** to enable it again. The public server remains required. AI practice,
spectators, and server-hosted rooms do not have this option; an older server without direct support shows a disabled button
and the reason.

### Save priority mode and phase stops

In **Settings → Gameplay**, choose **Smart priority** (the default) or **Full
control**, and select stops separately for your turns and other players' turns.
The in-game Settings drawer edits the same preferences. Both surfaces save
changes immediately for future games and application restarts. Temporary Pass
modes do not change the saved priority mode.

## 11. Table layout

The default table contains:

- a left rail with room controls and the turn/phase controller;
- an optional right rail dedicated to the public game log and chat;
- an optional shared stack/reveal tray;
- one battlefield per player;
- the local hand and local zone dock along the bottom;
- independently draggable remote-zone panels;
- an art-only hover preview.

Every battlefield always shows its player's name in the upper-left corner;
identifying a battlefield never depends on opening its remote-zone panel.

When a multiplayer Commander table finishes loading, the server publicly rolls
a d20 for every occupied player. Tied players reroll, and the descending result
shown in the game log becomes the complete turn order. Your own battlefield
stays at the local edge while the next players in that order continue clockwise;
spectators see the starting player at the local edge. Starting a new Commander
game rolls again, while **Restart game** preserves the remaining players'
relative order. If the original starting player has left a manual Commander
table, the next occupied seat in that order starts. Players who conceded but
remain seated return for the restarted game.

Hexproof keeps the battlefield visually dominant. Many manual tabletop
commands therefore live on right-click menus, drag targets, or hover tooltips
instead of permanent buttons. When an action is not visible, hover the relevant
card or pile, then try its right-click menu. A card menu and the surrounding
empty-area menu are intentionally different.

Use **Settings** on the table to:

- show or hide the game log/chat rail;
- show or hide the stack/reveal tray;
- choose zero to seven visible local counter slots.

If the log rail is hidden, **Show game log** restores it at the right edge. In
EDH, switch between **Overview layout** and **Primary battlefield**, or select a
battlefield as the primary view. Remote graveyard, exile, command zone, and
library controls are inside each player's compact floating zone panel; use
that battlefield's `▾`/`▴` button to show or hide it. Multiple panels may stay
open together. Drag a player name to move only that panel over the log rail or
other unused window space; right-click the name to restore its compact two-row
layout at the lower-right corner of that player's battlefield. Life and hand
counts stay in the battlefield header rather than being repeated in this
panel.

The small percentage button in the game-log header controls EDH battlefield
card size without taking space away from the battlefield. Hover or select it
to reveal the size controls; it collapses after the pointer leaves. Drag the
button anywhere in the table window to keep it clear of the current game, or
right-click it to restore the game-log dock. If the log is hidden, its default
dock moves to the middle of the window's right edge. Automatic mode uses 70%
for a four-player overview, 80% for a three-player overview, and 100% for the
primary battlefield. Select the active primary-battlefield button again to
return to the overview. Use `−`/`+` or hold `Ctrl` while scrolling over the
battlefield to select 50%–125% in 5% steps. The overview and primary/ordinary
sizes are remembered separately on this client. Select the percentage button
to restore automatic sizing. Card hover previews stay large.

The log records public manual actions. The chat composer sends explicitly
public messages to everyone at the table; use **Send** or press `Enter`.

### Turn, combat, and no-voice coordination

- The left turn controller shows the active player and the 11 shared turn
  steps without reducing battlefield height. Only the active player can select
  a step, use **Next phase**, or use **End turn**. `Ctrl+Right` advances one step
  and `Ctrl+Enter` ends the turn while chat and dialogs are unfocused.
- Each battlefield header shows that player's turns begun, including the
  current turn. The starting player begins at 1 and everyone else at 0; only
  the incoming player's count increases. Counts survive reconnects and reset
  for the next game or a restart.
- Select one or more controlled permanents during Attackers, right-click, and
  use the direct **Attack &lt;player&gt;** action, or choose **Attack a battlefield
  permanent…** and click an opposing permanent. During Blockers, select
  blockers, choose **Block an attacker…**, then click an attacker aimed at you
  or one of your permanents. An attacker badge names a player target, solid red
  arrows point to attacked permanents, and dashed gold arrows show blocks.
  **Clear combat declaration** removes only the selected sources. Hexproof
  intentionally does not decide which permanent types are legally attackable.
- Before committing a declaration, the combat dialog lists every selected
  card. For each attacker, keep **Tap** selected or clear it for vigilance or
  another effect. Tapping and declaring happen atomically. Tapped cards and
  cards whose printed type is not Creature show a warning, but the declaration
  remains available because card effects may permit it.
- For a spell or ability, right-click one or more controlled battlefield cards
  and use **Choose target**, then choose a player directly or click a target
  battlefield card. A locally owned spell on the shared stack exposes the same
  choices through its compact `◎` button. These arrows are public coordination
  markers, not legality checks; use **Clear target** to remove one, or move a
  stack source away to clear it automatically.
- **Signal** offers **No response**, **Please wait**, and **Clear signal**. The
  current state is visible on that player's battlefield and in the public log.
  Both states reset at every phase/turn change; No response also clears when a
  new public table event changes the situation. This is coordination only—not
  enforced priority.
- The active player may see **Untap all**, **Draw 1**, or **Tap attackers** in
  the relevant phase. These helpers run only when clicked; Hexproof does not
  infer vigilance, replacement effects, triggers, or other card rules.
- The turn controller shows **Land · N**, the public number of land plays
  explicitly recorded this turn. The active player can correct it with `−` or
  `+`. This is a coordination value, not a rules limit, and it resets on the
  next turn.
- Phase and turn controls ask for confirmation when the shared stack still has
  cards or a player has selected **Please wait**. Ending a turn also warns when
  your hand contains more than seven cards. Life at zero or less, an empty
  library, and a hand over seven are highlighted as reminders only; Hexproof
  does not automatically end the game or enforce a maximum hand size.

## 12. Core card and zone interactions

### Mouse and context-menu quick reference

| Surface | Left click / double-click | Right-click / drag |
|---|---|---|
| Battlefield card | Click to select; `Ctrl`/`Shift`-click toggles multi-selection; double-click an own controlled card to tap/untap | Right-click for card actions, including **Attach to…** / **Detach** for owned cards and **Choose target** for controlled cards; drag an owned/controlled card to reposition it or move it to a valid zone |
| Empty own battlefield | Clears ordinary selection when appropriate | Right-click for **Untap all**, **Arrange battlefield**, **Create token**, and **Concede** |
| Hand card | Hover to preview | Right-click for **Play land…** or exact move actions; drag horizontally across other hand cards to reorder them locally, or drag out to battlefield, public zones, or the shared tray |
| Empty hand area | No card action | Right-click for **Reveal hand/Recall hand**, **Discard a random card**, **Discard entire hand…**, and **Mulligan** |
| Own library | Left click intentionally does not draw | Right-click for library commands; drag the card back to move the unknown top card |
| Another player's library | Left click does nothing | Open that player's floating zone panel with `▾`, then right-click for consent-gated full search, top-card view, or top-X view |
| Graveyard, exile, or command pile | Click to browse; hover its visible top card to preview | Drag an eligible top card from your own graveyard/exile; in Duel Commander or Commander, drag either card from the local command-zone art pile; or right-click a card inside the browser |
| Library-search card | Click the row to preview; click its checkbox to select | Right-click the card, or the selected group, for destination actions |
| Shared stack/reveal card | Stack cards show their owner's player name; click an owned card to show its compact destination buttons; stack cards also expose `◎` **Choose target** | The owner may drag it back to a valid zone |

New face-up permanents are placed into compact type bands automatically:
lands flush against their controller's edge, creatures in the middle expanding
from the center toward both sides, enchantments at the far left, artifacts at
the far center, and planeswalkers or battles at the far right. Instants and
sorceries placed manually on the battlefield use their own staging row instead
of mixing with permanents. A multi-face card uses the face chosen when it
enters. Face-down cards use the neutral support cluster. Existing permanents do
not jump when a new card arrives, and every controlled permanent remains freely
draggable. Use **Arrange battlefield** only when you want to regroup the whole
local battlefield at once.

Only interchangeable lands and creatures form a slightly offset stack instead
of consuming one full slot each, including matching cards from different
printings. A card remains separate when it has counters, is a commander, is
owned by another player, participates in combat or an attachment, has a
different selected face, tapped state, or token status, is face down, or has
another card type. Every grouped card keeps an exposed edge for previewing,
selecting, or dragging it individually.

Hovering a visible card shows the large art preview without reserving table
space. When battlefield cards partially overlap, move across their visible
portions to switch the preview between them. Disabled menu items normally mean
the current player does not own or
control that card, the source/destination is not valid, the game is not
actionable, or the viewer is a spectator.

### Battlefield cards

- Drag an owned/controlled card to reposition it or move it to a valid zone.
- Dropping an owned card onto another player's battlefield puts it under that
  battlefield's control without changing its owner. The card stays upright
  from every player's viewing direction.
- For a face-down battlefield card, only its current controller can inspect the
  identity, choose its rendered face, or turn it face up/down. If its immutable
  owner is another player, that owner still sees only the card back.
- Expanded remote graveyard and exile piles are also convenient drop targets
  for eligible owned/controlled cards. A card always appears in its immutable
  owner's graveyard/exile, even when another pile accepted the drop.
- Double-click an own battlefield card to tap or untap it.
- Click a card to select it. `Ctrl`-click or `Shift`-click toggles cards in a
  multi-selection. Plain click starts a new selection.
- Right-click a card for:
  - double-faced card face selection when available;
  - adding or setting a number counter;
  - adding or editing named ability counters;
  - **Attach to…** another battlefield card, or **Detach**, when you own the
    source card. Same-lane attachments sit on the host and follow it; an
    attachment on another player's permanent is drawn on that card without
    changing controller;
  - moving one card to hand, graveyard, exile, library top/position/bottom;
  - moving a multi-selection to hand, graveyard or exile, to library top/bottom
    in selected or random order, or shuffling it into the entire library;
  - creating a token copy.
- Moving a multi-faced card to the battlefield prompts for the face to use; its
  right-click menu can change that choice later.
- Battlefield badges show the number-counter value, a small circular `T` for
  tokens, `♛` commander status, and `◆` named ability counters. Hover `T` for
  the localized token label or `◆` to see counter labels and values.
- With one controlled permanent selected, press `-` / `=` to decrease or
  increase its number counter by one. A number counter cannot go below zero.
- A `◇` ownership marker appears when a battlefield lane controller differs
  from the immutable owner; hover it to see the owner.
- Right-click empty own battlefield space for **Untap all**, **Create token**,
  and multiplayer **Concede**.

### Hand

- Drag a card horizontally across other hand cards to change the private local
  display order. The other cards slide aside, authoritative room updates retain
  the chosen order, and newly drawn cards are appended at the end. This action
  is not sent to the server and creates no game-log entry.
- Drag cards from hand to battlefield or public/shared drop targets.
- As the active player, use **Play land…** on a hand card to choose its face,
  review any advisory warning, and atomically place it while increasing the
  public recorded count. A second play, a non-main phase, a non-empty stack,
  or a face not identified as a Land produces a warning but can still be
  continued because card effects and table agreements may allow it.
- Right-click a hand card to move it to battlefield, graveyard, exile, library
  top, an exact library position, or library bottom.
- Use **Select and move hand cards…** in the hand-area menu to select several
  hand cards and move them together. This uses your private hand view and does
  not reveal the hand to opponents or unauthorized spectators.
- Ordinary right-click moves and drag/drop do not count as a land play. Use
  the `−`/`+` controls in the turn rail to correct the record when needed.
- Right-click empty hand space for **Reveal hand/Recall hand**, **Discard a
  random card**, **Discard entire hand…**, and **Mulligan**. Random discard is
  selected by the server; whole-hand discard asks for confirmation and moves
  the complete hand atomically.
- **Reveal hand** publishes the whole current hand to that player's labeled
  section in the shared tray. **Recall hand** atomically returns all cards that
  player revealed.
- Use the hand's horizontal overflow control when not every card fits.

### Own library

Left-clicking the library does not draw.

- Drag the card back from the library to move the unknown top card to a valid
  target such as hand or battlefield.
- Drop an eligible card onto the own-library pile to return it to the top of
  its owner's library.
- Right-click the library for:
  - Draw X cards;
  - Shuffle;
  - Search library;
  - View sideboard;
  - View top card;
  - View top X cards;
  - Put top X into graveyard;
  - Put top X into exile.

The full search view is private to its authorized viewer:

- filter using English or Chinese card names and types;
- click a row to update the large preview; only its checkbox changes the
  selection;
- use **Select all** to select all currently filtered cards;
- if several cards are selected, use the arrow controls under **Selected card
  order** to define their command order;
- choose a destination and whether selected card names are revealed in the
  public game log, then use **Complete search**;
- right-click one card for immediate destination actions. If that card is
  already part of a multi-selection, the action applies to the whole selected
  group;
- ordinary destinations are hand, battlefield, graveyard, and exile. Library
  top/bottom additionally offer ordered and randomized variants in the
  right-click menu;
- moving several selected cards to a battlefield lays them out together at
  deterministic nearby positions.

**Searching or viewing cards does not automatically shuffle the remaining
library.** After a full own-library search closes, Hexproof asks whether to
shuffle now. Decline the prompt when the card effect does not require a
shuffle. If selected cards are being returned to the library top or bottom,
the decision happens before placement: confirming sends the shuffle first and
then places the selected cards, while cancelling places them without
shuffling. **View top card** is private and allows that card to be moved by
right-click, including explicitly returning it to the source library top or
putting it on the bottom for effects such as Scry 1. The single-card view does
not show redundant randomized-order variants. **View top card** and **View top
X cards** do not show the shuffle prompt. In **View top X cards**, choose a
destination separately on every card row: your hand, your battlefield
(optionally face down), the source graveyard or exile, or the source library
top/bottom. Use the arrows to define relative order for cards returning to the
same library end; top and bottom groups can be randomized independently. This
resolves split-destination effects such as Expressive Iteration in one atomic
action. Assigning unwanted cards to the bottom and the rest to the top remains
the ordinary Scry helper; there is no separate Scry menu.

### Requesting access to another player's library

This action is deliberately discoverable from the pile rather than a permanent
button:

1. Use the `▾` control on the other player's battlefield to open their
   floating zone panel.
2. Right-click that player's library pile and choose **Search library**,
   **View top card**, or **View top X cards**. Left-click does not send a
   request.
3. The library owner receives a modal request naming the requester and chooses
   **Allow** or deny.
4. If allowed, only the requester receives the full library or requested top
   prefix. Other players and spectators continue to see only the library
   count/card back and an identity-free public log entry.
5. A full search or top-card view exposes its ordinary allowed destinations.
   In a top-X view, every approved card receives one destination. Hand and
   battlefield assignments go to the requester; graveyard, exile, and library
   assignments remain with the source player. The public log records only the
   viewed count and number of destination groups, never card identities.

Approval is short-lived, bound to that requester and source library, and
one-use. Request access again for a later search. Denial, expiry, disconnect,
or a mismatched request reveals no card identities.

### Graveyard, exile, command zone, stack, and reveal

- Click any player's graveyard, exile, or command pile to browse visible cards.
  In a graveyard or exile browser, use the checkboxes or **Select visible**
  (which follows the current filter), then **Move selected** or right-click
  any selected card to move the selection together. The selection control
  becomes **Deselect visible** when all filtered cards are selected.
  Right-clicking an unselected card moves only that card.
  Identical printings are grouped by quantity; filtering accepts English and
  Chinese card names/types. Enable **Individual cards** to choose particular
  copies. Clicking a row changes its preview; compact windows provide a
  **Preview** / **Cards** switch while keeping move actions visible.
- For **Endurance**, the affected player opens their graveyard, clears the
  filter, selects all visible cards, then chooses **Move selected → Bottom of
  library · random order**. The existing library order stays unchanged.
  Select only the relevant exile cards for cascade-style cleanup. Ordered
  placement follows your selection sequence. **Shuffle into library** instead
  shuffles the entire destination library, including the cards already there.
- Drag the displayed top card of your own graveyard or exile to a valid
  destination.
- Right-click a card in a graveyard or exile browser to move it to the acting
  player's battlefield, graveyard, exile, or library as permitted. If the source pile
  belongs to another player, no card moves until that player approves the exact
  short-lived request; rejection, expiry, or disconnect cancels it. Successful
  logs name that player and source zone. Graveyard/exile destinations always
  use the card owner. **Move to hand** and library actions are
  available only when every affected card is locally owned.
- Your command zone also allows right-click moves to battlefield, hand,
  graveyard, or exile. **Cast commander** instead moves the chosen commander to
  the shared stack and advances only that commander's command-zone cast count.
  Its dock control displays the next additional cost (`+2` per previous cast)
  and shows the underlying cast count on hover. Another player's
  command zone is inspect-only.
- Your sideboard is opened from the own-library right-click menu. It is private;
  its browser can move a card to battlefield, hand, graveyard, or exile.
- Drop an eligible owned/controlled card into the shared tray to represent a
  spell on the stack or a manual reveal. Library cards and cards already in a
  shared zone cannot be dropped there.
- Click an owned shared card to expose the compact `↗` battlefield, `†`
  graveyard, and `⌂` hand buttons, or drag it to a valid destination. An owned
  stack card also exposes `◎` for a player or battlefield-card target. Only its
  owner may move it out; stack resolution remains fully manual.
- The command-zone card-art pile beside the hand is the only local command-zone
  control. Click it to browse, drag either commander directly to battlefield,
  hand, graveyard, exile, library, or the shared tray, and drop an eligible
  commander back onto it to return that card to the command zone. Ordinary
  dragging remains a manual move and never implies a cast. The cast count may
  still be corrected with the `−` and `+` controls below the player name and
  life total.
- In Commander formats, select **Commander damage** in the left rail to open
  the public ledger. Each physical commander has one total for every player.
  Use `−`, `+`, or the value button for correction without changing life. Use
  **Record damage…** to subtract an entered combat-damage amount from life and
  add it to the same ledger entry atomically. A value of 21 or more is only a
  reminder; Hexproof does not automatically eliminate the player.

### Life and player counters

- Use life `−`/`+` controls for incremental changes.
- Select the life value to enter an exact total; negative life is permitted.
- A counter pip's first click selects it.
- While selected, left-click adds one and right-click subtracts one.
- Use the shortcuts below to rename or set the exact value.
- Table Settings controls how many of the seven synchronized counter slots are
  visible. Hidden slots retain their labels and values.

## 13. Mulligan, tokens, concede, and sideboarding

- **Mulligan** returns the current hand to the library, shuffles, draws up to
  seven, increments the public mulligan count, and logs the action. Hexproof
  does not enforce London bottoming.
- **Tokens and emblems** searches the installed token-capable database. The
  picker lists identity (name, P/T, type, set number); hover or click a row
  for rules. Tokens appear on the battlefield and disappear when moved away
  from it; emblems have a separate public list. Names, rules and artwork
  follow Settings' card language. If Chinese artwork is unavailable, an
  English image can be shown alongside Chinese rules text. Only the emblem's
  owner can remove it.
- **Concede** requires confirmation:
  - Commander-free 1v1 formats award the game/match to the opponent.
  - Duel Commander also awards the game/match to the opponent.
  - Commander eliminates the conceding player while remaining players
    continue.
  - Playtest has no Concede action; end the Playtest instead.
- A completed match opens a result dialog. **Return to room** preserves seats
  and registered decks but clears Ready, game state, and score.

For a commander-free 1v1 BO3 match, a non-final game opens the five-minute
sideboard workspace. It covers the table without a framed border:

- the entire registered mainboard and sideboard are laid out by card type;
- identical copies are stacked with a quantity badge;
- hover shows a large art preview;
- drag one copy between mainboard and sideboard;
- both players Ready starts the next game immediately;
- timeout discards unfinished edits and restores the previous partition.

For Duel Commander BO3, the same five-minute inter-game screen is a Ready gate
only. Mainboard/sideboard movement is disabled and the registered deck remains
unchanged for the next game.

### Connected-hub events

The **Events** browser contains constructed and Limited Swiss tournaments.
Cube free-play rooms are listed in **Browse hub**, not Events.
Constructed tournaments use the fixed Standard, Pioneer, Modern, Legacy,
Vintage, Pauper, and Duel Commander format selector. Register before the
organizer starts an event, then check in;
withdrawing registration removes the check-in controls and restores the
Register action.

For Limited play:

- Use **Events → Create tournament** and choose **Set Sealed** or **Set Draft**.
  There is no separate Limited-play entry on the main menu.
- **Pack simulator** on the main menu is available offline; the Limited
  creation form also has a simulator shortcut. Local simulation never creates
  a playable pool. Simulated boosters animate into a
  card-back reveal with rare and mythic cards arranged last. Click any card
  back to reveal that specific card, or use **Reveal all** or **Skip animation**
  at any time. Search simulator products by set code, localized set name, or
  booster product name. The animation can be disabled under **Settings →
  Appearance** without changing the generated result.
- When creating a Limited tournament, search the set chooser by set code,
  localized set name, or booster product name.
- In a Set Sealed or Set Draft registration lobby, choose **Download product
  art** to cache every distinct printing and independent face in that product
  before play. The same download is available without an event from
  **Settings → Download set art**. The progress bar reports completed and
  unavailable images. A failed MTGCH set-index lookup automatically continues
  with normal per-card fallback, and downloading never blocks check-in or
  event start.
- Set products installed in catalog schema 10 use exact MTGJSON collation when
  available. An older or incomplete catalog offers a clearly marked rarity-
  based approximation instead.
- **Set Sealed** always opens exactly six boosters for every checked-in player
  and can start with two checked-in players.
- **Set Draft** starts with at least two checked-in human players and a
  two-to-eight-player cap. Each player drafts three boosters, passing left,
  right, then left. Picks may wait in a private queue, and reconnecting
  restores the current pack and prior picks. The Draft screen keeps all of
  your prior picks visible and shows the physical seats with you at the
  bottom, including who receives this pack and who passes the next one to you.
  On narrow windows, the seats and prior picks move below the current pack so
  both regions remain accessible.
- Import or edit a Cube in the ordinary **Deck library** by choosing the
  **Cube** format. Its count/name/set/collector entries form one pool; there is
  no separate Cube import screen or sideboard. Select **Cube** alongside Modern
  or Commander in **Create room**, then choose that Cube-format deck for a
  free-play room. For a tournament instead, choose **Events → Create tournament
  → Cube draft**. Both have a configurable two-to-eight-player cap and draft
  three 15-card packs per player, passing left, right, then left; with two players the packs simply
  alternate between the two of you. The locked Cube needs 45 physical
  cards for every configured seat (90 for two, 360 for eight), and no physical
  Cube card is placed in two packs. Cube imports accept up to 10,000 physical
  cards and 5,000 distinct printing entries; this is separate from the smaller
  constructed-deck import safeguard.
- During deck building, click cards to move them between the visible **Main
  deck** and **Sideboard / available pool** areas. Select at least 40 main-deck
  cards. Plains, Island, Swamp, Mountain, and Forest are unlimited; Wastes and
  other special basics must be in the pool. Cards left in the available pool
  become the sideboard. Use **Mana value**, **Color**, **Card type**, or
  **Name** above the workspace to reorganize both areas without changing the
  deck. The separate color, type, and mana selectors filter the available pool
  together, so choosing Blue, Creatures, and mana value 3 shows only cards
  matching all three. Clear the filters to restore the full pool. The larger
  pool workspace keeps card art readable; the compact main-deck panel separates
  lands from nonlands. Basic lands are added automatically to reach 40 cards,
  in proportion to the selected spells' colored mana costs. The suggestion
  updates as you add or remove cards, and respects lands already selected from
  the pool. Expand **Basic lands** to inspect or adjust the counts; a manual
  adjustment switches automatic filling off. Enable **Automatically add basic
  lands** there to resume it. If no colored requirements can be determined,
  choose basic lands manually. This is a starting suggestion, not an optimal
  mana-base calculation.
  Exact-printing metadata is read locally; an unresolved card remains
  selectable in **Unknown**.
- Cube rooms use seats and **Ready**, not event registration or check-in. The
  host is automatically seated, and other players join through **Browse hub**
  or the room code. With at least two players, the host can **Start drafting**
  when every occupied seat is online and ready. The **Room / chat** button
  keeps seat progress and room chat available during drafting and deck building.
  Before drafting, a guest leaving frees their seat. After drafting starts,
  leaving the view preserves a guest's drafted pool for returning later;
  leaving as host closes the room after confirmation.
- **Commander Cube** supports two to eight draft players. Two-to-four-seat
  rooms default to six 20-card packs per player; the host can choose
  3/4/5/6/8 packs and single or paired opening. In paired mode, select two
  cards from each separate pack and confirm all four together. Direction
  alternates by batch; an odd final pack is drafted alone. Five-to-eight-seat
  rooms use three packs, opened individually, with two picks each time.
  At any capacity, the host can enter **10–40 cards per pack**, defaulting to
  20. The last one or two cards are collected automatically. Creation shows
  the required stock and blocks configurations that exceed the Cube's size;
  room settings stay fixed after creation. With the default pack size, six
  packs give each player 120 picks and three give 60. Build at least 60 cards
  including one or two commanders.
- During Commander Cube construction, **Optional cards** offers one outside
  copy each of **Sol Ring**, **Command Tower**, and **Arcane Signet**. Add only
  those you want; remove them to return them to this panel. Selected copies
  count toward your deck, and choices survive reconnecting. They do not use
  Cube stock. Basic lands and the existing Piper fallback remain available.
- Once all participating Commander Cube players submit, everyone automatically
  enters an assigned locked-deck room and clicks **Ready**. Eight players split
  into two tables of four; five, six, and seven split into 3+2, 3+3, and 4+3.
  Two to four share one table. No initial invitation or acceptance is needed.
- A regular Cube with two participating players also opens the ready-up room
  automatically after both submit. Players sitting out and spectators stay in
  the pod. A submitted player who disconnects keeps their place; entering the
  room does not automatically mark anyone ready. If you edit after submission,
  pending edits require confirmation before the client can discard them and
  enter with your last submitted deck.
- Larger regular Cube groups and subsequent **Free play** matches retain
  opponent selection. Choose **Invite to play** beside an available
  player; the opponent must **Accept invitation** before either player can
  **Enter match**. Invitations can be declined or cancelled; an accepted match
  can also be cancelled until its table opens. There are no rounds, standings,
  or host-assigned matches. Closing a table releases its players to choose new
  opponents. **Edit deck** returns to the original pool between matches; submit
  changes before choosing an opponent. An active invitation or match locks deck
  editing. Unsubmitted edits remain in the editor when an invitation arrives;
  decline or cancel it to resume editing. Inviting, accepting, entering a match,
  watching, or leaving requires explicit confirmation before discarding pending
  edits and using the last submitted deck. Other available players may **Watch
  match** on an opened table.
- For Swiss events, after every competing player submits a deck, the organizer
  publishes round one. Set Sealed, Set Draft, and Swiss Cube Draft use normal
  Swiss pairings, result confirmation, standings, and organizer-published rounds. The server
  automatically sets the round count from checked-in attendance; a two-player
  event schedules one Swiss round and a three-to-eight-player event schedules three.
- Entering a Limited pairing automatically installs the submitted event deck.
  Do not select a saved local deck in the pairing room; confirm **Ready** after
  the room shows **Limited deck locked**.
- The server owns random generation, physical card instances, passing queues,
  pools, and deck validation. Card rules at the pairing table remain manual.

Pairing-room decklists remain private during every tournament. After the final Swiss
round is completed, open the **Decklists** tab to view every deck recorded from
participants' pairing rooms. **View decklist** opens a grouped card-art gallery
with hover previews. **Export** copies the same importable
`Deck` / `Sideboard` / `Commander` text used by the deck library, or saves it
as a `.txt` file. When a pairing match finishes on the tabletop,
**Report** prefills that tabletop score, including drawn games. Confirm or edit
it before submitting; the confirmed tournament result remains authoritative.

## 14. Retained logs

The client no longer includes a replay browser or playback controls. Live game
logs and chat remain available during play. The hub's existing archive retention
and privacy-filtered public-log API are unchanged; removing playback does not
delete saved server data. Archives expire according to the operator's retention
settings (seven days by default).

## 15. Keyboard shortcuts

Shortcuts use the active Hexproof window and are suppressed while a text field
or modal editor needs keyboard input. Selection shortcuts act only when either
a hand card or one or more battlefield cards are selected. If both domains
still contain a selection, the move is deliberately ignored to prevent moving
the wrong card. Clicking a hand card, battlefield card, or editable player
counter returns keyboard focus to the table and restores its shortcuts without
clearing an unsent chat draft.

Open **Settings → Keyboard shortcuts** to search every application,
table, and selection action. Select **Change**, then press one key
combination. Backspace or Delete leaves that action unassigned. Hexproof rejects
a binding already used by another action and names the conflict. Each action can
be reset independently, or **Reset all** restores every default. Changes are
stored only on this device and apply immediately; the table's `F1` help shows
the current bindings. Mouse gestures and hand focus-navigation controls are
fixed interactions rather than rebindable keyboard actions.

The following table lists the defaults:

| Shortcut | Action |
|---|---|
| `F11` | Toggle full screen |
| `F1` / `?` | Show or hide the table shortcut list |
| `Ctrl+,` | Open table settings |
| `Ctrl+G` | Show or hide the game log/chat rail |
| `Ctrl+Shift+V` | Show or hide the stack/reveal tray |
| `Ctrl+Right` / `Ctrl+Enter` | Advance the current phase / turn |
| `Ctrl+D` | Open Draw X cards, defaulting to 2 |
| `Ctrl+Alt+D` | Draw one card |
| `Ctrl+F` | Search own library |
| `Ctrl+L` | View the top X cards, defaulting to 5 |
| `Ctrl+Shift+L` | View the top library card |
| `Ctrl+B` | View sideboard |
| `Ctrl+Shift+G` | Put top X library cards into graveyard |
| `Ctrl+Shift+E` | Put top X library cards into exile |
| `Ctrl+Shift+S` | Confirm shuffle of own library |
| `Ctrl+U` | Untap all own permanents |
| `Ctrl+Shift+A` | Arrange own battlefield |
| `Ctrl+T` | Create token |
| `Ctrl+R` / `Ctrl+Shift+C` | Roll dice / flip a coin |
| `Ctrl+Alt+P` / `Ctrl+Alt+R` | Select a random player / battlefield card |
| `Ctrl+M` | Confirm mulligan |
| `Ctrl+H` | Reveal hand or recall own revealed cards |
| `Ctrl+Alt+X` / `Ctrl+Shift+X` | Discard a random card / confirm discarding the entire hand |
| `Ctrl+Shift+H` | Set own life total |
| `Ctrl+K` | Open commander damage |
| `Ctrl+Shift+D` / `Ctrl+Shift+R` | Confirm declaring a draw / restarting the game |
| `Ctrl+Shift+Q` | Confirm Concede; disabled in Playtest |
| `Ctrl+Shift+W` | Leave room or end Playtest, with confirmation |
| `Ctrl+Backspace` | Return to the room after a finished match |
| `I` | Rename the selected player counter |
| `S` | Set the selected player counter to an exact value |
| `[` / `]` | Decrease / increase the selected player counter |
| `Alt+-` / `Alt+=` | Decrease / increase own life |
| `P` | Play the selected hand card as a land |
| `Alt+B` / `Alt+Shift+B` | Move selected hand card to battlefield face up / face down |
| `Alt+H` / `Alt+G` / `Alt+E` | Move selected card(s) to hand / graveyard / exile |
| `Alt+Up` / `Alt+Down` | Move selected card(s) to library top / bottom in selected order |
| `Alt+Shift+Up` / `Alt+Shift+Down` | Move multiple selected battlefield cards to library top / bottom in random order |
| `T` | Tap or untap selected permanents |
| `F` / `V` | Turn the selected permanent face down/up / choose a printed face |
| `A` / `Shift+A` | Attach / detach the selected permanent |
| `R` / `Shift+R` | Choose a target / clear target arrows for selected cards |
| `X` / `Shift+X` | Attack a permanent / block an attacker |
| `Shift+C` | Clear the selected combat declaration |
| `-` / `=` | Decrease / increase the selected permanent's number counter |
| `N` / `Shift+N` / `Ctrl+N` | Add a number counter / add an ability counter / set the number counter |
| `Alt+C` | Create a token copy of the selected permanent |
| `Ctrl`-click / `Shift`-click | Toggle battlefield cards in a multi-selection |
| `Ctrl` + mouse wheel over battlefield | Adjust local battlefield card size by 5% |
| `←` / `→` / `Home` / `End` | Move between hand cards |
| `Enter` | Open the focused hand card menu |
| `Esc` | Close the active popup/dialog when that popup permits it |

## 16. Privacy and operational notes

- The room server is trusted with full deck, hand, and library identities so
  it can authoritatively shuffle and synchronize hidden zones.
- Clients receive role-specific projections. Opponents always receive
  counts/backs rather than another player's hidden identities. Spectators do
  the same by default; a room may explicitly grant them current-hand access,
  which never includes libraries, sideboards, private searches, face-down
  battlefield cards, logs, or replays.
- Card image bytes remain in each client's local cache.
- Room passwords, reconnect credentials, and transport connection IDs are not
  exposed in room snapshots or public replay APIs.
- If an action is disabled, first check connection state, player role, selected
  deck/Ready state, zone ownership/control, game completion, and whether a
  modal popup is open.

## 17. Feedback and reports

Official 3.1.0 feedback is **public**. Approved text, technical information,
attachments and later replies are published to `ClayStan404/hexproof` on GitHub.
Anyone may read and copy them. There is no private submission or contact-email
field. Do not include credentials, contact details, private conversations,
hidden game information or other people's personal data, including in images.

Open **Feedback** from the main menu, page navigation or a table action menu.
It works independently of the game-hub connection and account login. A custom
hub does not become the feedback recipient. The game and its clock continue
while the form blocks game input. Offline drafts and export remain available;
disabled/invalid build configuration and temporary connection failures have
separate messages.

### Review and publish

1. Choose **Problem**, **Suggestion** or **Other**. Describe the steps, expected
   result and actual result; the description limit is 8 KiB of UTF-8 text.
2. Optionally add up to two static PNG/JPEG images, one Forge crash report and
   one hosting diagnostic report. Use **Preview**, **Remove** and **Technical
   information** to inspect the selected snapshots. Nothing captures your
   desktop automatically; clipboard access requires **Paste image**.
3. Wait for **Draft saved**, then choose **Review public feedback**. Check the
   exact text, technical context, attachments and public repository. **Read
   full notice** opens the complete disclosure inside the client, including
   the AI providers and retention/removal terms.
4. Select **I have reviewed this content and the notice, and agree to publish
   it publicly**, then choose **Publish feedback**. Viewing the preview, reading
   the notice or selecting the checkbox alone sends nothing. Editing the draft
   invalidates its previous preview and confirmation.

In 3.1.0, an image input and its normalized PNG must each fit 2 MiB, with a
maximum edge of 8192 pixels and at most 16 million pixels. Metadata removal
cannot hide private information visible in the image. If a large screenshot
is rejected, resize or crop a separate copy and review it before attaching.
**Unreleased source change:** later source accepts PNG/JPEG files up to 32 MiB
within the same pixel bounds and downscales when necessary to the unchanged
2 MiB transmitted PNG limit. That fix is not in the published 3.1.0 packages;
the original image file remains unchanged.

### Status and conversation

Open **My feedback** and select the record. **Refresh status** reads the receipt
and conversation through the feedback service; direct GitHub access is not
required. Keep the local record: its private access credential enables status,
replies and removal. **Copy receipt** and **Export** do not contain that
credential and cannot restore access after every local copy is lost.

| Displayed progress | Meaning |
| --- | --- |
| Queued / Sending / Receipt unconfirmed | Upload is pending, active or not yet confirmed. Keep the record and check status before submitting another copy. |
| Accepted / publication pending or delayed | The service saved the approved payload; GitHub publication is not yet verified. |
| Partially published | Only part of the approved content is confirmed public. Assessment waits for complete publication. |
| Published | The complete approved content is public; this does not confirm a bug or promise a fix. |
| Assessing / waiting for information / AI team working | The team is evaluating or handling the report; read its latest explanation. |
| Awaiting release | A change may be merged or its source published, but an installed release does not yet contain it. |
| Released | A verified outcome identifies the published version. Earlier deliveries remain in the history if new information reopens assessment. |

AI questions appear in **Conversation with the AI team**. Use **Reply to this
question** or **Add public information** for more evidence. Each reply has its
own public preview and explicit confirmation. It becomes part of the same
public discussion; it is not private chat. A delayed question deadline does
not silently prohibit later evidence. Refresh failures retain the last known
thread with its sync time rather than claiming a new result.

The official notice names GitHub, Multica and OpenAI for publication and
processing. Automation does not guarantee human review, an immediate response,
acceptance of a suggestion or a fix. Network or development-machine downtime
may delay processing. Do not resubmit a delayed case to make a second queue.

### Stop, close or request removal

- **Stop sending** stops future client uploads; it cannot recall a request
  already sent or content already accepted.
- **Close feedback** asks to stop further follow-up and new replies while
  keeping the public discussion and attachments. Running tasks and public
  issue closure may still be settling; their pending/delayed status remains
  visible. Closure is not deletion, and this case cannot be reopened in place.
- **Request content removal** separately requests removal of the whole case
  from project-controlled locations. Use it for accidentally disclosed
  sensitive content, and contact the support address in the notice. Keep the
  record until progress is resolved. Current Multica task history may prevent
  completion, so a request can remain pending; provider records, GitHub
  history, notifications, backups and others' copies may remain.
- **Delete locally** removes this device's record and its access. It does not
  remove accepted or public content; request remote removal first if needed.

Drafts remain locally until deleted. Accepted content is normally kept locally
for up to 30 days, subject to storage limits; public receipts remain available
for status/removal under the shown access window. The official service defaults
to 365 days for public content and access credentials, then starts cleanup.
Unresolved removal retains its status and authorization. After removal, status
records remain at least another 120 days to prevent republication. Expiry is
not a promise that every external copy disappears on that date.

Earlier private V1 records are never automatically published or supplied to the
public AI workflow. Their trusted receipts may still be queried. To contribute
old visible content publicly, deliberately create a new public draft and review
it; the old contact email and access credential are not copied.
