# Feedback v1 fixtures

These are independent HTTPS feedback fixtures, not `hexproof.v1` game messages.
The client and receiver must agree on fields and the immutable original bytes.
The example contact uses a reserved, non-deliverable domain. Tests inject the
clock near `createdAt`; a frozen timestamp must never be refreshed in retries.

`valid-no-attachments.json` is a UTF-8 manifest. Its digest is SHA-256 over
`hexproof-feedback-v1`, one LF byte and the exact file bytes, including the
terminal LF. The multipart manifest part contains those same bytes. Attachments
are bound by their declared byte lengths and SHA-256 hashes, not by transport
boundaries. `receipt.json` illustrates acceptance of that submission; the
receipt is a reference, never an authentication credential.

See [feedback behavior](../../../docs/feedback-design.md) for the API, consent,
retention and privacy contract. Invalid schema, duplicate-key, credential,
idempotence and attachment cases are generated in focused client/receiver tests
so their behavior is exercised rather than copied into golden text.
