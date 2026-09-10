# Third-party notices

Hexproof preserves the notices and license terms of the software and data it
uses. Runtime packages may contain additional notices beside the relevant
component.

## Mana symbol font

The client bundles the unmodified Mana 1.18 font by Andrew Gioia under the SIL
Open Font License 1.1. The font and complete license are in
`apps/client-qt/qml/assets/mana/` and embedded in the client resources. Portable
client packages also include readable notices in `licenses/mana/`.
Upstream revision: `6ca9e696d3bda2519dcf3eebd96598f84ad9ddd8`.
Source: <https://github.com/andrewgioia/mana>.

All mana, tap, and card type symbol images are copyright Wizards of the Coast
(https://magicthegathering.com), as stated by upstream. No upstream text fonts
or stylesheets are bundled.

## Forge rules engine

Rules-enforced rooms optionally use the Forge engine and card scripts from the
Manabrew-maintained Forge fork. Forge remains licensed under
GPL-3.0-or-later. The exact source revision is recorded in
`third_party/forge-runtime/VERSIONS.env`.

Upstream source: <https://github.com/witchesofthehill/forge>

## Manabrew Forge harness

The optional server runtime uses Manabrew's headless Forge harness and its
generated protocol adapter. Manabrew code is licensed under
AGPL-3.0-or-later; its published protocol specification is CC-BY-4.0. The exact
source revision and complete upstream notices are included in every generated
runtime archive.

Upstream source: <https://github.com/witchesofthehill/manabrew>

Card-data and localized-name attributions remain displayed by the client and
documented with the card-database builder.
