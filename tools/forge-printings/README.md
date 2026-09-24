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
and the runtime identity and local validation cover them. Functional variants,
digital cards, tokens and absent native rules are not guessed into support.
Known parent/suffix rules remain available for new prerelease printings.

Regenerate using an explicit trusted catalog and a matching pinned native
runtime. Output is a new directory; inspect `report.json` for unresolved cards
and compare the index before copying the two `printing-aliases.*` files into
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

`NativePrintingAliasRegressionTest` tests every shipped alias and actual startup
of the reported decks. Existing rejection tests continue to reject mismatched
names/numbers, unrelated card faces and invented printings. Refresh the runtime
identity after a reviewed index change and rebuild the native packages/overlay.
