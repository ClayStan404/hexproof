// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtCache.h"
#include "CardCatalog.h"
#include "CardCatalogCommon.h"
#include "CatalogRepository.h"

namespace hexproof::client {
using namespace catalog_internal;

CardCatalog::CardRecord CardCatalog::lookupCatalog(const CardRequest &request) const
{
    if (m_catalogBusy || !installed())
        return {};
    const QString key = request.name.toLower() + QChar(0x1f) + request.setCode.toUpper() +
                        QChar(0x1f) + request.collectorNumber + QChar(0x1f) + request.language +
                        QChar(0x1f) + QString::number(m_indexVersion);
    if (m_lookupCache.contains(key))
        return m_lookupCache.value(key);
    const CardRecord record = guiCatalog().lookup(CatalogCardQuery{
        request.name,
        request.setCode,
        request.collectorNumber,
        request.language,
    });
    if (record.valid())
        m_lookupCache.insert(key, record);
    return record;
}

CardCatalog::CardRecord
CardCatalog::lookupLocalizedPrinting(const CardRequest &request,
                                     const CardRecord &catalogIdentity) const
{
    if (m_catalogBusy || !installed())
        return {};
    return guiCatalog().lookupLocalizedPrinting(
        CatalogCardQuery{
            request.name,
            request.setCode,
            request.collectorNumber,
            request.language,
        },
        catalogIdentity, m_indexVersion);
}

CardCatalog::CardRecord CardCatalog::migrateLegacyCacheRecord(const CardRequest &request,
                                                              const CardRecord &record) const
{
    if (kCardResolutionVersion != kScryfallPlaceholderPolicyVersion || !record.valid() ||
        record.resolutionVersion != kCompatibleResolutionVersionBeforePlaceholderPolicy ||
        !QFileInfo::exists(record.imagePath) ||
        (record.reusesLocalArt && !request.allowsSubstituteArt(m_artCache->reuseLocalArt()))) {
        return {};
    }

    const QUrl imageUrl(record.imageUrl);
    const QString host = imageUrl.host().toLower();
    const bool isScryfall =
        host == QStringLiteral("scryfall.io") || host.endsWith(QStringLiteral(".scryfall.io"));
    if (isScryfall &&
        (m_catalogBusy || !installed() || !guiCatalog().cachedScryfallArtIsUsable(record))) {
        return {};
    }

    CardRecord migrated = record;
    migrated.resolutionVersion = kCardResolutionVersion;
    return migrated;
}

CatalogRepository &CardCatalog::guiCatalog() const
{
    if (!m_guiCatalog)
        m_guiCatalog = std::make_unique<CatalogRepository>(m_databasePath);
    return *m_guiCatalog;
}

void CardCatalog::clearGuiQueryCaches()
{
    m_printingsCache.clear();
    m_cardFacesCache.clear();
    m_lookupCache.clear();
}

void CardCatalog::persistLocalizedPrintings(const QJsonArray &printings)
{
    if (m_catalogBusy || !installed())
        return;
    const CatalogPersistResult result =
        guiCatalog().persistLocalizedPrintings(printings, m_indexVersion);
    if (!result.error.isEmpty()) {
        qCWarning(cardCatalogLog).noquote()
            << "Could not persist localized Scryfall printings:" << result.error;
        return;
    }
    if (result.localizedPrintingCount >= 0 &&
        result.localizedPrintingCount != m_localizedPrintingCount) {
        m_localizedPrintingCount = result.localizedPrintingCount;
        clearGuiQueryCaches();
        if (!saveCatalogMetadata()) {
            qCWarning(cardCatalogLog)
                << "Could not update catalog metadata after caching localized printings.";
        }
    }
}

} // namespace hexproof::client
