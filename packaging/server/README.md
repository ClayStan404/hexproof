# Hexproof server package

The archive contains a static Linux server binary and a systemd service
template. It does not contain deployment credentials, TLS certificates, or a
reverse-proxy configuration.

Run the server directly for a local installation:

```sh
./bin/hexproof-server -bind 127.0.0.1 -port 57320
```

Use `./bin/hexproof-server -help` to review the available retention, capacity,
rate-limit, and trusted-proxy options before exposing a hub.

For systemd, copy `deploy/hexproof-server.service.in`, replace these
placeholders, and install the resulting unit using the normal procedure for
your distribution:

- `@HEXPROOF_USER@`: unprivileged service account;
- `@HEXPROOF_GROUP@`: service account group;
- `@HEXPROOF_DATA_DIR@`: writable runtime and retained-log directory;
- `@HEXPROOF_BIN@`: absolute path to the server binary.

The template binds to localhost. Put a TLS-capable reverse proxy or tunnel in
front of it when clients connect over the Internet, and pass only the proxy
addresses through `-trusted-proxies`.
