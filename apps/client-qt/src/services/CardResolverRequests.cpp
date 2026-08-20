// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalogCommon.h"
#include "CardResolver.h"

namespace hexproof::client {
using namespace catalog_internal;

void CardResolver::beginChineseExactRequest()
{
    if (m_currentRequest.setCode.isEmpty() || m_currentRequest.collectorNumber.isEmpty()) {
        beginChineseAlternate();
        return;
    }
    beginJsonRequest(chineseExactUrl(m_currentRequest.setCode, m_currentRequest.collectorNumber),
                     Phase::ScryfallChineseExact);
}

void CardResolver::beginChineseAlternate()
{
    if (m_currentRequest.exactArt && !m_currentRequest.setCode.isEmpty() &&
        !m_currentRequest.collectorNumber.isEmpty()) {
        const bool catalogHasRequestedEnglishArt =
            m_catalogRecord.valid() && m_catalogRecord.imageLanguage == QStringLiteral("en") &&
            !m_catalogRecord.imageUrl.isEmpty() &&
            m_catalogRecord.setCode.compare(m_currentRequest.setCode, Qt::CaseInsensitive) == 0 &&
            m_catalogRecord.collectorNumber == m_currentRequest.collectorNumber;
        if (catalogHasRequestedEnglishArt) {
            m_currentRecord = m_catalogRecord;
            beginImageRequest(ArtStage::ScryfallEnglish);
        } else {
            beginScryfallEnglishRequest();
        }
        return;
    }

    const CardRecord localized =
        m_callbacks.lookupLocalizedPrinting
            ? m_callbacks.lookupLocalizedPrinting(m_currentRequest, m_catalogRecord)
            : CardRecord{};
    if (localized.valid() && !localized.imageUrl.isEmpty()) {
        m_currentRecord = localized;
        const bool substitute = m_currentRecord.usesSubstituteArt;
        if (!m_currentRequest.setCode.isEmpty() && !m_currentRequest.collectorNumber.isEmpty()) {
            m_currentRecord.setCode = m_currentRequest.setCode;
            m_currentRecord.collectorNumber = m_currentRequest.collectorNumber;
        }
        m_currentRecord.usesSubstituteArt = substitute;
        beginImageRequest(ArtStage::ScryfallChineseAlternate);
        return;
    }
    beginScryfallChineseSearch();
}

void CardResolver::beginScryfallChineseSearch()
{
    beginJsonRequest(chineseSearchUrl(m_catalogRecord.oracleId, m_currentRequest.name),
                     Phase::ScryfallChineseSearch);
}

void CardResolver::beginScryfallEnglishRequest()
{
    beginJsonRequest(englishUrl(m_currentRequest.name, m_currentRequest.setCode,
                                m_currentRequest.collectorNumber),
                     Phase::ScryfallEnglish);
}

void CardResolver::beginMtgchRequest()
{
    m_currentMtgchTried = true;
    const QString set =
        !m_currentRequest.setCode.isEmpty() ? m_currentRequest.setCode : m_catalogRecord.setCode;
    const QString collector = !m_currentRequest.collectorNumber.isEmpty()
                                  ? m_currentRequest.collectorNumber
                                  : m_catalogRecord.collectorNumber;
    if (set.isEmpty() || collector.isEmpty()) {
        if (m_currentRequest.language == QStringLiteral("zh"))
            beginScryfallEnglishRequest();
        else
            finishCurrentCard(false);
        return;
    }
    beginJsonRequest(mtgchUrl(set, collector), Phase::Mtgch);
}

void CardResolver::beginImageRequest(ArtStage stage)
{
    if (QCoreApplication::closingDown())
        return;
    m_currentArtStage = stage;
    if (m_currentPhase != Phase::Image) {
        m_currentPhase = Phase::Image;
        m_currentPhaseRetries = 0;
    }
    const QUrl imageUrl(m_currentRecord.imageUrl);
    if (!imageUrl.isValid() || imageUrl.scheme() != QStringLiteral("https")) {
        setCurrentFailure(imageUrl, Phase::Image, 0, QNetworkReply::ProtocolInvalidOperationError,
                          QStringLiteral("Invalid image URL"));
        continueAfterImageFailure(true);
        return;
    }
    const QString path = m_callbacks.imagePathFor
                             ? m_callbacks.imagePathFor(m_currentRequest, m_currentRecord)
                             : QString{};
    if (QFileInfo::exists(path)) {
        m_currentRecord.imagePath = path;
        finishCurrentCard(true);
        return;
    }
    if (hostInCooldown(imageUrl)) {
        setCurrentFailure(imageUrl, Phase::Image, 0, QNetworkReply::TemporaryNetworkFailureError,
                          QStringLiteral("Provider cooldown"),
                          QStringLiteral("provider is temporarily unavailable"));
        continueAfterImageFailure(false);
        return;
    }
    qCDebug(cardCatalogLog).noquote()
        << "Card image request"
        << "card=" + m_currentRequest.name
        << "printing=" +
               (m_currentRecord.setCode.isEmpty()
                    ? QStringLiteral("<none>")
                    : m_currentRecord.setCode + QLatin1Char('/') + m_currentRecord.collectorNumber)
        << "imageLanguage=" + (m_currentRecord.imageLanguage.isEmpty()
                                   ? QStringLiteral("<none>")
                                   : m_currentRecord.imageLanguage)
        << QStringLiteral("attempt=%1").arg(m_currentPhaseRetries + 1)
        << "url=" + imageUrl.toString(QUrl::FullyEncoded);
    QNetworkReply *reply = requestImage(imageUrl);
    if (!reply) {
        setCurrentFailure(imageUrl, Phase::Image, 0, QNetworkReply::UnknownNetworkError,
                          QStringLiteral("Could not start image request"));
        continueAfterImageFailure(false);
        return;
    }
    connect(reply, &QNetworkReply::finished, this, [this, reply]() { handleImageReply(reply); });
}

void CardResolver::beginJsonRequest(const QUrl &url, Phase phase)
{
    if (QCoreApplication::closingDown())
        return;
    if (m_currentPhase != phase) {
        m_currentPhase = phase;
        m_currentPhaseRetries = 0;
    }
    if (hostInCooldown(url)) {
        setCurrentFailure(url, phase, 0, QNetworkReply::TemporaryNetworkFailureError,
                          QStringLiteral("Provider cooldown"),
                          QStringLiteral("provider is temporarily unavailable"));
        continueAfterJsonFailure(phase, false);
        return;
    }
    requestJson(url, [this, url, phase](QNetworkReply *reply) {
        if (!reply) {
            setCurrentFailure(url, phase, 0, QNetworkReply::UnknownNetworkError,
                              QStringLiteral("Could not start metadata request"));
            continueAfterJsonFailure(phase, false);
            return;
        }
        handleJsonReply(reply, phase);
    });
}

} // namespace hexproof::client
