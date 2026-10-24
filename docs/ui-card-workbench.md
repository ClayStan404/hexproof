# Card selection workspace

## Scope and reference

The owner-supplied MTG Arena draft and deck-editor screenshots guide this
client-only refresh. Use a large card-art workspace, a compact deck/pick list
on the right, a pinned primary action, and a compact search/color toolbar
with a scrollable advanced-filter sheet. Keep Hexproof navigation and assets;
do not change opening-hand or battlefield screens.

## State and boundaries

- `LimitedSessionState` remains authoritative for private packs and picks.
  Selecting a candidate is local; confirmation sends its current instance ID.
  A stale selection or pending command cannot submit a second pick. No local
  pick timer, timeout selection, pool generation, or hidden information is added.
  Double-clicking a current card uses the same guarded confirmation path.
- The Limited builder retains exact-instance selection and five virtual basic
  land counts. Filters and grouped display rows never change those identities.
  Its pool and main-deck panes have independent search, color, and advanced
  filters. Deck totals and mana suggestions always use the unfiltered selection.
- Saved-deck edits still pass through `DeckLibraryModel`; format changes,
  commander designation, printing selection, tokens, Consider, and export stay
  available. Catalog search is an add-only popup: search first, select a
  result, then add it to the main deck, sideboard, or Consider. Commander and
  Cube omit Sideboard. The live main-deck list stays in the editor, not beside
  search results.
- Shared QML components own visual card grids, compact printing-aware lists,
  mana-value summaries, previews, and display-only filters. Screens compose
  them; server rules and tabletop components are untouched.
- Color choices combine with AND: selecting white and blue requires both colors,
  and a card may also contain additional colors. Colorless and multicolor
  shortcuts also constrain the result when combined with color choices.
  Type, rarity, and mana-value choices combine with OR within their category;
  different categories combine with AND.
  Advanced-filter choices are independent toggles with persistent check marks
  and a filled selected background in both themes. Focus alone is not a
  selection indicator; closing the sheet preserves every selected option.
  Catalog filters run before the existing result limit, not on a partial page.
  A query or filter change keeps asynchronous latest-generation semantics.
- Art remains cache-backed. Search galleries prefetch only the settled visible
  viewport, one face at a time behind explicit cache work. Changing the query,
  scrolling, or closing the search discards unstarted preview requests. Preview
  work is excluded from deck-cache progress; missing art shows a usable name
  placeholder.

## Layout and interaction

- Draft packs are never filtered. The complete pack owns the wide left region;
  the right list aggregates picks by exact printing and displays copy counts.
  Hover either region for a large preview. Seat details open on demand.
- Card names follow the selected card language using the local Chinese alias
  index, falling back to English when no translation exists. Keep canonical
  names and printing/instance IDs unchanged. Row colors use actual card colors,
  never Commander color identity; costs show individual symbols, not mana value.
- Compact rows use an independent dark quantity badge, a beveled color frame,
  and a pale inset name plate with dark text (including black cards). Multicolor
  cards use a gold frame; colorless cards stay neutral even with a colored
  Commander identity. Name elision reserves space for right-aligned costs.
  The bundled Mana font renders colored, generic, variable, colorless, snow,
  hybrid, and Phyrexian symbols offline. Split-card costs retain their separator;
  empty land costs have no icon. Hover highlights and drag previews retain the
  row styling and exact-instance actions. Color filters reuse the same glyphs and retain
  their localized accessible labels. Missing catalog data is not fetched or inferred.
- Bulk import and the database builder retain optional `card_colors` and
  `mana_cost` columns. This additive schema-10 extension preserves existing
  `colors` (color identity) semantics. Existing databases remain readable;
  missing fields use neutral rows and a `?` cost with an update notice. Updating
  the client alone cannot recover data absent from an old database: publish a
  rebuilt card-data package to make those fields available offline.
- Confirm/submit actions remain outside scrolling content. Short and narrow
  windows scroll card regions and filter bodies without hiding those actions.
- Saved-deck search, Consider, and Tokens stay in the page header so catalog
  search remains reachable without scrolling the gallery. Export and current-deck
  art caching sit in a More menu. Deck-local search shares one toolbar row with
  view/group/sort when that row can fit those controls; the combos keep a
  fixed width so localized labels do not push Sort onto a second row. The
  toolbar wraps at narrow or highly scaled widths. They must not rely on clipping or
  overlap the sidebar at the supported 900-by-620 minimum window size. The deck
  name is edited from the page header. Commander and Cube decks hide the right
  column so the card gallery can use the full width.
- Enlarged UI text also participates in responsive layout: saved-deck action
  fields and card-row actions may occupy separate rows, and the editor stacks
  its sidebar below the main deck when they cannot fit side by side. Nested
  lists pass wheel scrolling to the page at their boundaries so the remaining
  controls stay reachable. Deck-library and import pages use the same behavior.
- The deck editor's visual gallery uses a larger, smoothly accumulated mouse
  wheel step suited to its card-sized rows. Touchpad pixel deltas remain direct.
  Hover previews pause during scrolling and resume after it settles. Repeated
  card tiles and list rows use inexpensive glass wells inside the page's glass
  panels rather than capturing a live backdrop for every card.
- Participants use the full Limited workspace. Event management/chat remain
  accessible from a separate overlay; nonparticipants retain the public desk.
- Deck building uses an available-pool gallery on the left and a compact main
  deck on the right. Clicking moves one exact instance. Basic lands can be
  added and removed without searching for a physical pool card.
- On initial deck construction after Set/Cube Draft, ask whether to keep all
  picks in the main deck or start again from the pool. This is a local choice,
  never an automatic submission. Keeping picks allows a click or a drag from
  the right list into the available pool to remove one exact instance. Sealed
  still starts from the pool. Snapshot refreshes do not repeat the choice or
  reset edits, and a restored submitted deck always takes precedence.

## Verification

Cover stale/pending picks, exact-printing aggregation and single-copy moves,
combined filters, server-side catalog filtering before truncation, existing
saved-deck operations, image fallback/preview, overlay access, and pinned
actions at narrow/short sizes through headless QML and C++ tests. Follow
`development-policy.md` for focused/integration checks and use isolated native
clients when the requested appearance or interaction needs visual confirmation.
Do not require a native run for every edit.
