# Frozen cluster v1 peer

These four Go files are byte-identical public sources from
`ClayStan404/hexproof` commit `7f6ee48ebdefb15ef64e949e3d22720ba0022842`.
`provenance.json` records their source blobs and SHA-256 values. Do not update
the frozen peer when changing the current cluster implementation.

The compatibility tests use its actual agent, remote client, strict HTTP
decoder and coordinator through loopback HTTP. Its protocol/account/sync
imports come from the current module; their types used by these tests are
unchanged. This is a frozen internal RPC boundary, not a complete historical
application artifact or release qualification.
