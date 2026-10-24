# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
# Install separately after verifying the test runtime's matching source archive.

location ^~ /test/forge-source/ {
    alias /var/www/hexproof-test-forge/;
    autoindex off;
    default_type application/octet-stream;
    add_header X-Content-Type-Options nosniff;
}
