# Verified catalog printing compatibility

Forge's rules database and the card catalog do not have identical printing
inventories. The adapter first uses an exact native printing. A missing
printing can use a bundled index entry whose parent was independently resolved
by the native database and belongs to the same catalog Oracle ID and full name.
The native rules/edition stay usable, while the submitted set/number identify
the displayed and registered copy. No runtime network service is needed.

The source index and its provenance live in
`third_party/forge-runtime/native-host/src/main/resources/org/hexproof/forge/`.
Both the dedicated builder and creator-hosted overlay package these resources,
and the runtime identity and local validation cover them. The generator and
runtime share a printing-level eligibility check. An ordinary printing is not
excluded merely because another printing has a variant. Cosmetic `FlavorName`
and `UniversesWithin` variants must preserve every face's characteristics and executable abilities;
Forge may rewrite their Oracle display text with the flavor name. Other named
rules variants, digital cards, tokens and absent native rules are not guessed into support.
Known parent/suffix rules remain available for new prerelease printings.
Alternate front/back names must match as a pair. NFC normalization and the
modifier-letter colon spelling are accepted without renaming native rules.
The submitted catalog name, set and number survive snapshots and foil changes.
The census includes every language's paper printings using canonical catalog
names, including editions without an English printing. Duplicate language
records share the same name/set/number key. Existing exact English anchors
remain preferred so adding language coverage does not remap old aliases.

An exact same-name, same-set `F`-prefixed Forge printing can anchor its catalog
number during offline generation. Other printings of that Oracle card can then
share that verified anchor. An exact digital-edition printing can serve as a
last-resort anchor for a paper printing of the same Oracle identity, but is
never emitted as a paper candidate. Neither mechanism strips arbitrary numbers
or falls back to names at runtime.

Regenerate using an explicit trusted catalog and a matching pinned native
runtime. Output is a new directory; inspect `report.json` for unresolved cards
and compare the index before copying `printing-aliases.*` and `printing-unavailable.tsv` into
the resource directory:

```sh
python3 tools/forge-printings/generate.py \
  --catalog /absolute/path/to/cards.sqlite \
  --runtime /absolute/path/to/native-runtime \
  --output build/printing-index-review
```

The first index uses the default catalog generated on 2026-09-20, identified by
its SHA-256 in `printing-aliases.json`. The census found 86,381 exact native
printings and 10,719 additional aliases. Another 3,525 catalog printings had no
eligible native parent; these include absent scripts and out-of-scope variant
cards, and remain unresolved. A successful lookup is not evidence that every
ability on every card is correctly implemented by upstream Forge.

Adapter 26's refreshed index resolves 87,050 printings exactly and another
10,920 through verified aliases, leaving 2,655 unresolved. It adds 564 aliases
without removing previous mappings, including `Ancient Tomb / LTC / 387z`
through `LTC / 387`. Its cosmetic Balin's Tomb variant and submitted serialized
identity are both retained.

Adapter 27 resolves 87,646 printings exactly and 12,988 through verified aliases,
for 100,634 of the 103,225 eligible paper printing identities in this catalog.
It fixes 64 gaps from the earlier English-only census: 31 alternate-name printings,
three Unicode-colon printings, 29 funny/playtest printings, and Aswan Jaguar PMIC 1.
It also includes all 2,600 language-exclusive printings previously omitted by
the census: 591 resolve exactly and 2,009 use verified aliases.
No existing aliases were removed or remapped. This is a registration census,
not a guarantee that every upstream ability is implemented correctly.

The remaining 2,591 records are enumerated individually in
[`printing-unavailable.tsv`](../../third_party/forge-runtime/native-host/src/main/resources/org/hexproof/forge/printing-unavailable.tsv):

| Reason | Count | Meaning |
| --- | ---: | --- |
| `native_rules_missing` | 1,637 | No corresponding supported native rules card is present. |
| `native_variant_missing` | 13 | The edition declares this functional variant, but Forge does not implement it. |
| `different_rules_same_name` | 9 | The native same-name card belongs to a different catalog Oracle identity. |
| `meld_result` | 21 | An independently cataloged meld back cannot be registered as a deck card. |
| `not_a_playing_card` | 315 | A deck/theme/display front card, rather than a playable card. |
| `unsupported_game_piece` | 596 | A plane, scheme, Vanguard, attraction, sticker or other piece outside this adapter's deck modes. |

`unmatched_native_printing` is an actionable gap and must not enter the shipped
baseline. The current census has zero such gaps. A deliberately unsupported
same-name card must not borrow another card's rules to improve coverage numbers.

After a catalog or engine change, run the generation command above with
`--check` and a fresh output directory. It fails on an actionable gap or any
difference in the alias, unavailable or provenance files. Review added/removed
exclusions as well as alias changes; investigate every new gap before updating
the baseline. Provenance covers the catalog, both TSV files, the generator and
the shared lookup sources, so the static tests require a refreshed census after
a resolver/generator change. Rebuilding the native runtime also checks every
exclusion against the actual registration lookup and reports newly supported
entries that need a baseline refresh.

`NativePrintingAliasRegressionTest` tests every shipped alias and actual startup
of the reported decks. Existing rejection tests continue to reject mismatched
names/numbers, unrelated card faces and invented printings. Refresh the runtime
identity after a reviewed index change and rebuild the native packages/overlay.
The client CMake overlay dependencies include the resource directory so an
index-only change rebuilds the packaged adapter before helper validation.
