// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QByteArray>
#include <QString>
#include <QtTypes>

namespace hexproof::client::catalog_internal {

struct CatalogReleaseManifest
{
    QString generatedAt;
    int schemaVersion = 0;
    qint64 compressedSize = 0;
    qint64 uncompressedSize = 0;
    QByteArray compressedSha256;
    QByteArray databaseSha256;
    bool valid = false;

    bool compatible() const;
};

CatalogReleaseManifest parseCatalogReleaseManifest(const QByteArray &payload);

} // namespace hexproof::client::catalog_internal
