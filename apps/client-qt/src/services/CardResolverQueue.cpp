// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalogCommon.h"
#include "CardResolver.h"

namespace hexproof::client {
using namespace catalog_internal;

void CardResolver::resolve(CardRequest request)
{
    if (m_active)
        return;
    m_active = true;
    m_currentRequest = std::move(request);
    m_currentMtgchTried = false;
    m_currentArtStage = ArtStage::None;
    m_currentPhase = Phase::None;
    m_currentPhaseRetries = 0;
    m_currentConfirmedMissing = false;
    m_currentFailureDetail.clear();
    m_mtgchEnglishRecord = {};
    m_catalogRecord = m_currentRequest.catalogHint.valid()
                          ? m_currentRequest.catalogHint
                          : (m_callbacks.lookupCatalog ? m_callbacks.lookupCatalog(m_currentRequest)
                                                       : CardRecord{});
    m_currentRecord = m_catalogRecord;
    const bool requestedFace =
        m_catalogRecord.name.contains(QStringLiteral(" // ")) &&
        m_catalogRecord.name.compare(m_currentRequest.name, Qt::CaseInsensitive) != 0 &&
        m_catalogRecord.name.split(QStringLiteral(" // "), Qt::SkipEmptyParts)
            .contains(m_currentRequest.name, Qt::CaseInsensitive);
    if (requestedFace)
        m_currentRecord.imageUrl.clear();
    qCDebug(cardCatalogLog).noquote()
        << "Card cache resolution"
        << "card=" + m_currentRequest.name << "language=" + m_currentRequest.language
        << "requestedPrinting=" + (m_currentRequest.setCode.isEmpty()
                                       ? QStringLiteral("<name-only>")
                                       : m_currentRequest.setCode + QLatin1Char('/') +
                                             m_currentRequest.collectorNumber)
        << "catalogHit=" +
               QString(m_currentRecord.valid() ? QStringLiteral("true") : QStringLiteral("false"))
        << "resolvedPrinting=" +
               (m_currentRecord.setCode.isEmpty()
                    ? QStringLiteral("<none>")
                    : m_currentRecord.setCode + QLatin1Char('/') + m_currentRecord.collectorNumber)
        << "imageLanguage=" + (m_currentRecord.imageLanguage.isEmpty()
                                   ? QStringLiteral("<none>")
                                   : m_currentRecord.imageLanguage);
    if (m_callbacks.setStatus)
        m_callbacks.setStatus(QStringLiteral("Caching %1…").arg(m_currentRequest.name));
    if (m_currentRecord.valid())
        m_currentRecord.requestedName = m_currentRequest.name;

    if (m_currentRequest.language == QStringLiteral("zh")) {
        if (!requestedFace && m_currentRecord.imageLanguage == QStringLiteral("zh") &&
            !m_currentRecord.imageUrl.isEmpty()) {
            beginImageRequest(ArtStage::ScryfallChineseExact);
        } else {
            beginChineseExactRequest();
        }
    } else if (!requestedFace && m_currentRecord.imageLanguage == QStringLiteral("en") &&
               !m_currentRecord.imageUrl.isEmpty()) {
        beginImageRequest(ArtStage::ScryfallEnglish);
    } else {
        beginScryfallEnglishRequest();
    }
}

} // namespace hexproof::client
