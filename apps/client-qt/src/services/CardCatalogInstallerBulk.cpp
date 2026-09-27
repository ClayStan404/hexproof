// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalog.h"
#include "CardCatalogCommon.h"
#include "CatalogInstaller.h"

namespace hexproof::client {

void CardCatalog::finishCatalogOperation(const ImportResult &result)
{
    m_cardQueryTextCache.clear();
    clearGuiQueryCaches();
    if (result.ok) {
        const QString requestedPackage = m_catalogInstaller ? m_catalogInstaller->packageType()
                                                            : QStringLiteral("default_cards");
        m_packageName = result.packageType.isEmpty() ? requestedPackage : result.packageType;
        m_indexVersion = result.schemaVersion > 0 ? result.schemaVersion
                                                  : catalog_internal::kCatalogIndexVersion;
        m_catalogGeneratedAt = result.generatedAt.isEmpty()
                                   ? QDateTime::currentDateTimeUtc().toString(Qt::ISODate)
                                   : result.generatedAt;
        m_aliasCount = result.aliasCount;
        m_tokenCount = result.tokenCount;
        m_localizedPrintingCount = result.localizedPrintingCount;
        if (!saveCatalogMetadata())
            setLastError(QStringLiteral("Catalog installed, but its metadata could not be saved."));
        setProgress(1.0);
        setStatus(QStringLiteral("Catalog ready · %1 cards · %2 Chinese printings")
                      .arg(result.cardCount)
                      .arg(result.localizedPrintingCount));
    } else {
        setLastError(result.error.isEmpty() ? QStringLiteral("Catalog update failed.")
                                            : result.error);
        setStatus(QStringLiteral("Catalog update failed"));
        setProgress(0.0);
    }
    if (m_catalogInstaller)
        m_catalogInstaller->completeOperation();
    if (result.ok) {
        emit catalogChanged();
        emit catalogVersionChanged();
    }
    refreshSearches();
    restartCardFaceExpansion();
    restartLimitedArtFaceExpansion();
    scheduleResolutionWork();
}

} // namespace hexproof::client
