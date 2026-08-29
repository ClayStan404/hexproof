// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CatalogReleaseManifest.h"

#include "CardCatalogCommon.h"

#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>

namespace hexproof::client::catalog_internal {

bool CatalogReleaseManifest::compatible() const
{
    return valid && schemaVersion == kCatalogIndexVersion;
}

CatalogReleaseManifest parseCatalogReleaseManifest(const QByteArray &payload)
{
    CatalogReleaseManifest result;
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject())
        return result;

    const QJsonObject manifest = document.object();
    result.generatedAt = manifest.value(QStringLiteral("generatedAt")).toString();
    result.schemaVersion = manifest.value(QStringLiteral("schemaVersion")).toInt();
    result.compressedSize = manifest.value(QStringLiteral("compressedSize")).toInteger();
    result.uncompressedSize = manifest.value(QStringLiteral("uncompressedSize")).toInteger();
    result.compressedSha256 =
        manifest.value(QStringLiteral("compressedSha256")).toString().toLatin1().toLower();
    result.databaseSha256 =
        manifest.value(QStringLiteral("sha256")).toString().toLatin1().toLower();
    const QDateTime generatedAt = QDateTime::fromString(result.generatedAt, Qt::ISODate);
    result.valid =
        manifest.value(QStringLiteral("format")).toString() ==
            QStringLiteral("hexproof-card-database-v1") &&
        manifest.value(QStringLiteral("package")).toString() == QStringLiteral("default_cards") &&
        manifest.value(QStringLiteral("asset")).toString() ==
            QStringLiteral("hexproof-default-cards.sqlite.gz") &&
        result.schemaVersion > 0 && generatedAt.isValid() && result.compressedSize > 0 &&
        result.compressedSize <= kMaximumOfficialCatalogBytes && result.uncompressedSize > 0 &&
        result.uncompressedSize <= kMaximumOfficialCatalogExpandedBytes &&
        isSha256(result.compressedSha256) && isSha256(result.databaseSha256);
    return result;
}

} // namespace hexproof::client::catalog_internal
