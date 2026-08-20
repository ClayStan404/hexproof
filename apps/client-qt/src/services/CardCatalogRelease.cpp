// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalog.h"

#include "CardCatalogCommon.h"
#include "CatalogReleaseManifest.h"
#include "NetworkLimits.h"
#include "NetworkRequestFactory.h"

#include <QDateTime>
#include <QNetworkReply>

namespace hexproof::client {
using namespace catalog_internal;

bool CardCatalog::latestCatalogCompatible() const
{
    return latestCatalogKnown() && m_latestCatalogSchemaVersion == kCatalogIndexVersion;
}

bool CardCatalog::catalogUpdateAvailable() const
{
    if (!latestCatalogCompatible())
        return false;
    if (!installed() || m_indexVersion != m_latestCatalogSchemaVersion)
        return true;

    const QDateTime installedAt = QDateTime::fromString(m_catalogGeneratedAt, Qt::ISODate);
    const QDateTime latestAt = QDateTime::fromString(m_latestCatalogGeneratedAt, Qt::ISODate);
    return !installedAt.isValid() || (latestAt.isValid() && latestAt > installedAt);
}

void CardCatalog::checkCatalogUpdate()
{
    if (!m_network || m_checkingCatalogVersion)
        return;

    m_checkingCatalogVersion = true;
    m_catalogVersionError.clear();
    emit catalogVersionChanged();

    QNetworkReply *reply =
        m_network->get(makeNetworkRequest(QUrl(QString::fromLatin1(kOfficialCatalogManifestUrl)),
                                          QByteArrayLiteral("application/json")));
    network_limits::limitNetworkReply(reply, network_limits::kMaximumJsonResponseBytes);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const bool networkOk = reply->error() == QNetworkReply::NoError;
        const QByteArray payload = reply->readAll();
        reply->deleteLater();

        m_checkingCatalogVersion = false;
        m_latestCatalogGeneratedAt.clear();
        m_latestCatalogSchemaVersion = 0;
        if (!networkOk) {
            m_catalogVersionError =
                QStringLiteral("Latest database version is temporarily unavailable.");
            emit catalogVersionChanged();
            return;
        }

        const CatalogReleaseManifest manifest = parseCatalogReleaseManifest(payload);
        if (!manifest.valid) {
            m_catalogVersionError = QStringLiteral("The database release manifest is invalid.");
        } else {
            m_latestCatalogGeneratedAt = manifest.generatedAt;
            m_latestCatalogSchemaVersion = manifest.schemaVersion;
            if (!manifest.compatible()) {
                m_catalogVersionError =
                    QStringLiteral("The latest database requires a newer Hexproof version.");
            }
        }
        emit catalogVersionChanged();
    });
}

} // namespace hexproof::client
