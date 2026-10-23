# Public feedback V2 fixtures

These fixtures belong to the independent feedback API, not the game protocol.
`valid-no-attachments.json` is an exact UTF-8 frozen multipart manifest, including
its final newline. `contract.json` records the notice bytes, their SHA-256 and
the manifest digest (`SHA256("hexproof-feedback-v2\n" + manifestBytes)`).
`receipt.json` acknowledges durable acceptance; publication remains pending.

`reply-valid.json` is an independently confirmed reply to the root fixture,
bound to a fixed question ID and revision. Its final newline is also part of the
frozen bytes. `reply-contract.json` uses the separate
`hexproof-feedback-reply-v2\n` digest domain and the same disclosure notice.
Replies authenticate with the parent's retained capability; neither fixture
contains that capability or the client's local confirmation nonce.

`thread-custom-question.json` is a public conversation response with a concrete
Chinese AI question (`code: custom`), rather than a fixed question template.
`thread-delivery-history.json` is an independent conversation response after
new user information: its current state is `assessing`, with no current
`outcome`, while two historical delivery facts retain the public source commit
and version `3.1.0` for the earlier input revision. Typed outcomes are also
present on their corresponding historical conversation entries. The examples
use the same synthetic root identifier for convenience; they are independent
snapshots, not successive pages of one conversation. Both fit the five-entry
page limit. Their public commit/version references are schema examples, not
receipts proving that any real release exists.

All destinations and content are synthetic. `none-v1` authorizes no external AI
processing. Tests that check first-acceptance freshness must use the fixture's
clock or regenerate both timestamp and digest. No receipt capability is stored
in these public fixtures. V1 fixtures remain unchanged to test legacy privacy.
