# Hexproof v1 protocol schema

`wire-schema.json` is the source of truth for stable protocol names shared by
the Go server and Qt client. It covers message types, error codes, roles,
formats, phases, zones, match modes, and other stable enum-like values.

`payload-schema.json` and the adjacent `payload-*.json` fragments are the
incremental source of truth for payload fields. The loader rejects fragment
version mismatches, duplicate definitions, duplicate message schemas, unknown
wire-constant enum references, and fixture values outside declared enums.
Covered payloads include the complete handshake, room entry, deck selection,
ready, and match-loading flow, plus core game actions for drawing, shuffling,
moving cards, tapping, face-down state, card counters, phase changes, token
creation, complete room/game snapshot projections, sideboarding, and retained
replay discovery/loading. Each covered payload is checked against its Go struct
and every matching shared fixture; transport messages with an empty payload use
the shared `EmptyPayload` contract. Core Qt command builders are also statically
checked so their emitted field names cannot drift independently.

The `replay.*` messages remain server compatibility endpoints after removal of
the client replay UI. Their wire constants, payload schemas, Go mappings, privacy
checks, and fixtures stay intact; they no longer have Qt command builders.

`game.move_card.faceDown` supports hand/library entry to battlefield or exile.
Battlefield identity remains visible to its controller; face-down exile strips
identity fields from every `game.snapshot` recipient. A library source always
selects the actor's actual top card, including when the destination is stack.
See [manual zone actions](../../docs/manual-zone-actions.md#unseen-face-down-exile)
for the command, privacy, and client/server compatibility contract.

Update affected schemas, fixtures, and handwritten Go/Qt payload mappings
together, then regenerate both language bindings:

```sh
python3 tools/protocol_codegen.py
```

The generated files are:

- `apps/server/internal/protocol/wire_constants_generated.go`
- `apps/client-qt/src/protocol/WireConstantsGenerated.h`

`python3 tools/check-protocol-parity.py` verifies that the generated files are
current, rejects duplicate handwritten declarations, checks that every shared
JSON fixture uses a registered message type, and strictly validates covered
payload fields, required/optional tags, nested object types, controlled string
values, and unknown fields. Payload coverage is complete except the reserved,
unused `room.event` type; every other registered message has a payload schema
and shared fixture.

The generator validates schemas, fixtures, and handwritten payload mappings
before writing generated files. Validation failure leaves previous bindings
untouched. Parity checks inspect the resulting contracts, not the spelling of
an import in the generator; package-local source organization may change while
the wire shape stays identical.
