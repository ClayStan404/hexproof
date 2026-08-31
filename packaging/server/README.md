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

Forge rules rooms require the separately built runtime payload. The command
line flags `-forge-harness`, `-forge-home`, and `-forge-java` take precedence;
the same values can be persisted in a systemd drop-in as:

```systemd
[Service]
Environment="HEXPROOF_FORGE_HARNESS=/srv/hexproof/forge-runtime/current/forge-harness.jar"
Environment="HEXPROOF_FORGE_HOME=/srv/hexproof/forge-runtime/current/forge-gui"
Environment="HEXPROOF_FORGE_JAVA=java"
```

The server probes this runtime before accepting connections. If the runtime is
absent, leave the variables unset and manual rooms remain available.

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
