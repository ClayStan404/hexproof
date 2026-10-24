# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

location = /hexproof/servers.json {
    alias /var/www/hexproof/servers.json;
    default_type application/json;
    add_header Cache-Control "public, max-age=60";
    add_header X-Content-Type-Options nosniff;
}

location = /hexproof/content/index.json {
    alias /var/www/hexproof/content/index.json;
    default_type application/json;
    etag on;
    add_header Cache-Control "no-cache";
    add_header X-Content-Type-Options nosniff;
}

location ^~ /hexproof/content/releases/ {
    alias /var/www/hexproof/content/releases/;
    default_type application/json;
    add_header Cache-Control "public, max-age=31536000, immutable";
    add_header X-Content-Type-Options nosniff;
}
