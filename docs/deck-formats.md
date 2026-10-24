# Deck formats and legality validation

This document separates tabletop behavior from deck-construction policy. It is
the authority for adding formats without turning the table into a card-rules
engine.

## Two independent axes

Every room and local deck carries both values:

| Axis | Values | Owns |
|------|--------|------|
| Table mode | `modern`, `duel`, `edh` | Seat count, starting life, command zones, commander tax, sideboarding, and match flow |
| Deck format | `custom`, `standard`, `pioneer`, `modern`, `legacy`, `vintage`, `pauper`, `duel`, `commander`, `cube` | Deck-library filtering and advisory construction/card-pool validation |

`modern` remains the wire value for the commander-free two-player table mode
for compatibility. It does not mean that the table enforces the Modern card
pool. Standard, Pioneer, Modern, Legacy, Vintage, Pauper, and Custom 1v1 all
map to that table mode. Duel Commander maps to `duel`; Commander maps to
`edh`. Cube also uses the commander-free storage shape, but selecting it in
ordinary creation starts a configurable two-to-eight-player Cube Draft and
40-card deck building. Free play is the default: the organizer chooses players
for ordinary two-seat manual tables without Swiss rounds. A Swiss tournament
is still an explicit alternative. The source Cube is never a game deck.

An old persisted Generic 1v1 deck has no trustworthy specific format. It
migrates to `custom`, never to Modern. Existing Duel Commander and Commander
decks migrate to `duel` and `commander` respectively.

Client deck-format selectors present the common formats first: Modern,
Commander, Duel Commander, Legacy, Standard, Pioneer, Pauper, Vintage, Cube,
then Custom 1v1. Room creation and deck import default to Modern. Custom 1v1
remains the final explicit escape hatch, while an `All formats` filter stays
ahead of this sequence where applicable. Playtest omits Cube without changing
the relative order of the remaining formats.

## Changing a saved deck's format

The deck editor may update the construction policy and its derived table mode
without re-importing the list:

- commander-free format changes preserve mainboard and sideboard;
- Duel Commander and Commander changes preserve mainboard and designated
  commanders;
- changing from commander-free to either commander format merges all sideboard
  cards into the main deck and clears commander designations, so the user must
  explicitly choose one or two commanders; entries merge only when card name,
  set, and collector number all match, preserving distinct printing choices;
- changing from a commander format to a commander-free format clears only the
  commander designations because those cards are already stored in the
  mainboard;
- changing to Cube merges the sideboard into its single main pool, clears
  commander designations, and preserves distinct printing choices; changing
  away from Cube keeps every pool card in the main deck and starts with an
  empty sideboard.

Cross-axis changes require UI confirmation. No conversion deletes a card. The
deck format, table mode, zone conversion, and timestamp are persisted as one
model mutation. An unavailable writer rejects and rolls it back; retryable
background persistence failures remain visible under the normal deck-library
save policy. Only that deck receives a new legality-validation revision.

## Validation authority and privacy

The client owns catalog-backed deck validation because the searchable
Scryfall database is local. Validation runs off the GUI thread and stores only
derived results in the deck-library model. The server still validates bounded
payload shape, the room/table-mode match, the selected deck format, commander
presence, and operational limits. It does not host a card database or infer
card-text rules.

Validation is incremental during ordinary library use. Importing or editing a
named-format deck validates that deck only; deleting or renaming a deck and
editing its preferred tokens do not revalidate the remaining library. Client
startup and card-catalog replacement are the only normal full-library refresh
points. Each request carries a per-deck revision so an older asynchronous
result cannot overwrite a newer edit.

Deck identities remain private under `privacy.md`. Validation results are local
and are not projected to opponents or spectators. A selected deck still sends
its complete private identity only to the trusted room server.

## Validation levels

Name-only catalog resolution prefers playable printings over tokens, emblems,
art cards, and `front_card` theme inserts. Same-name theme inserts (for example
FMSC 28 versus the MSH 70 Pym Particles spell) must not supply a spell's legality,
Oracle identity, or imported printing. Explicit set/collector selections remain
exact and retain their own legality; the client never substitutes a legal spell
for an explicitly selected non-playable insert.

`custom` keeps the existing operational checks and does not apply a card-pool
policy. Named formats add these deterministic checks when a current card
database is installed:

- every card resolves in the local catalog, including a double-faced card
  listed by either face name, and has a legal or restricted Scryfall status
  for the selected format; Commander/EDH reports unresolved, banned, and
  `not_legal` cards as non-blocking warnings instead;
- commander-free constructed decks contain at least 60 main-deck cards and at
  most 15 sideboard cards;
- ordinary cards have at most four copies across main deck and sideboard;
- a Vintage-restricted card has at most one copy;
- Duel Commander and Commander use a singleton main deck, no sideboard, and
  one or two designated commanders. Duel Commander requires exactly 100
  main-deck cards; Commander/EDH reports a different main-deck size as a
  non-blocking warning;
- commander-format card color identities are compared with the combined color
  identity of the designated commanders, but mismatches are advisory warnings
  and never block room selection.

Basic lands and cards whose Oracle text explicitly changes their deck-copy
limit are exempt from the ordinary copy limit. Partner/background/companion
pairing legality and other card-text-driven construction exceptions remain
advisory gaps; they must not be guessed.

A missing or outdated catalog produces an **unverified** warning instead of a
false illegal result. Verified size, sideboard, and copy-limit violations
disable selecting a deck for a room with the named format, except that the
Commander/EDH exact-100 main-deck size is advisory. Ban-list and
catalog-resolution violations also block other named formats, including Duel
Commander, but are advisory for Commander/EDH so variants, preview cards, and
agreed house rules remain playable. Commander color-identity mismatches are
grouped into one non-blocking warning; hovering the status shows the individual
card names.
Hexproof does not special-case commanders whose color identity depends on a
pregame choice. Custom rooms remain available for variants and for players who
intentionally resolve construction rules themselves.

`cube` does not run constructed-format legality. It is selectable for room
creation only when all cards are in the main pool, every entry has a real set
code and collector number, and the pool contains at least 90 physical cards.
Creation additionally requires 45 physical cards for every configured seat.
Missing art remains an image-loading concern and does not change the locked
printing identities sent to the limited-event server.

## Growth boundary

Format constants and table-mode mapping belong in a small deck-format module.
Catalog-backed checks belong in a dedicated asynchronous legality service.
`DeckLibraryModel` owns cached per-deck results and presentation roles only;
it must not open SQLite or accumulate format-specific SQL. QML renders results
and emits selection intent; it must not implement construction rules.

Adding another named format requires:

1. a stable deck-format value and table-mode mapping;
2. catalog legality-status support and a validator test;
3. import, library, room, playtest, and tournament labels;
4. translations in every supported interface language
   (see [ui-translations.md](ui-translations.md));
5. protocol fixtures when the value crosses the room/deck wire boundary.
