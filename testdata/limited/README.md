<!--
SPDX-License-Identifier: GPL-3.0-or-later
SPDX-FileCopyrightText: 2026 Hexproof contributors
-->

# FRA collation regression data

`fra-mtgjson.json` pins the MTGJSON 5.3.0+20261007 FRA Play booster definition,
with only the printing identity fields needed by the builder. Referenced SPG
identities come from the same day's SPG export. The upstream weights, variants,
and sheets are unmodified. Sources: <https://mtgjson.com/api/v5/FRA.json> and
<https://mtgjson.com/api/v5/SPG.json>. MTGJSON uses the MIT License; its complete
notice is preserved in `MTGJSON-LICENSE.txt`. Magic card names and identities
remain Wizards of the Coast data.

`fra-upstream-product.json` is the deterministic compact result produced by
`build_limited_products.build_product` from that snapshot. Python tests compare
the result to the pinned product and every upstream slot/weight. Client and
server tests use the same product to check generation, private projections and
reconnects over loopback WebSockets. Both the pooled representation and the
historical large inline representation exercise the default transport byte limit.
The catalog CLI integration test checks durable source provenance and atomic
rejection of invalid references.
These fixtures are not release build inputs.
