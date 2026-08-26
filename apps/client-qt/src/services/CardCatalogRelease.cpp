// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalog.h"

#include "CardCatalogCommon.h"
#include "CatalogReleaseManifest.h"
#include "NetworkLimits.h"
#include "NetworkRequestFactory.h"

#include <QDateTime>
#include <QNetworkReply>
#include <QSettings>

namespace hexproof::client {
using namespace catalog_internal;

namespace {

constexpr auto kCatalogLastCheckKey = "updates/catalogLastCheckUtc";
constexpr auto kCatalogLatestGeneratedAtKey = "updates/latestCatalogGeneratedAt";
constexpr auto kCatalogLatestSchemaVersionKey = "updates/latestCatalogSchemaVersion";
constexpr qint64 kCatalogCheckIntervalSeconds = 24 * 60 * 60;

} // namespace

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

    QSettings settings;
    settings.setValue(QString::fromLatin1(kCatalogLastCheckKey),
                      QDateTime::currentDateTimeUtc().toString(Qt::ISODate));

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
            QSettings settings;
            settings.setValue(QString::fromLatin1(kCatalogLatestGeneratedAtKey),
                              m_latestCatalogGeneratedAt);
            settings.setValue(QString::fromLatin1(kCatalogLatestSchemaVersionKey),
                              m_latestCatalogSchemaVersion);
            if (!manifest.compatible()) {
                m_catalogVersionError =
                    QStringLiteral("The latest database requires a newer Hexproof version.");
            }
        }
        emit catalogVersionChanged();
    });
}

void CardCatalog::loadCachedCatalogRelease()
{
    QSettings settings;
    const QString generatedAt =
        settings.value(QString::fromLatin1(kCatalogLatestGeneratedAtKey)).toString();
    const int schemaVersion =
        settings.value(QString::fromLatin1(kCatalogLatestSchemaVersionKey)).toInt();
    if (!QDateTime::fromString(generatedAt, Qt::ISODate).isValid() || schemaVersion <= 0)
        return;
    m_latestCatalogGeneratedAt = generatedAt;
    m_latestCatalogSchemaVersion = schemaVersion;
    if (!latestCatalogCompatible()) {
        m_catalogVersionError =
            QStringLiteral("The latest database requires a newer Hexproof version.");
    }
}

void CardCatalog::checkCatalogUpdateIfDue()
{
    QSettings settings;
    const QDateTime lastCheck = QDateTime::fromString(
        settings.value(QString::fromLatin1(kCatalogLastCheckKey)).toString(), Qt::ISODate);
    if (lastCheck.isValid()) {
        const qint64 elapsed = lastCheck.toUTC().secsTo(QDateTime::currentDateTimeUtc());
        if (elapsed >= 0 && elapsed < kCatalogCheckIntervalSeconds)
            return;
    }
    checkCatalogUpdate();
}

} // namespace hexproof::client
