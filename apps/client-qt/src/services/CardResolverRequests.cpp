// SPDX-License-Identifier: GPL-3.0-or-later
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
        if (!m_currentMtgchTried)
            beginMtgchRequest();
        else
            beginNextEnglishCandidate();
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
    m_currentScryfallEnglishTried = true;
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
        if (m_currentRequest.language == QStringLiteral("zh") &&
            m_currentProvider == ArtProvider::Mtgch) {
            beginChineseExactRequest();
        } else {
            beginNextEnglishCandidate();
        }
        return;
    }
    beginJsonRequest(mtgchUrl(set, collector), Phase::Mtgch);
}

void CardResolver::continueAfterScryfallChinese()
{
    if (!m_currentMtgchTried) {
        beginMtgchRequest();
        return;
    }
    beginNextEnglishCandidate();
}

void CardResolver::continueAfterMtgchChinese()
{
    if (m_currentProvider == ArtProvider::Mtgch) {
        beginChineseExactRequest();
        return;
    }
    beginNextEnglishCandidate();
}

void CardResolver::beginNextEnglishCandidate()
{
    const auto beginScryfall = [this]() {
        m_currentScryfallEnglishTried = true;
        const bool requestsFace =
            m_catalogRecord.name.contains(QStringLiteral(" // ")) &&
            m_catalogRecord.name.compare(m_currentRequest.name, Qt::CaseInsensitive) != 0 &&
            m_catalogRecord.name.split(QStringLiteral(" // "), Qt::SkipEmptyParts)
                .contains(m_currentRequest.name, Qt::CaseInsensitive);
        const bool requestedPrintingMatches =
            m_currentRequest.setCode.isEmpty() || m_currentRequest.collectorNumber.isEmpty() ||
            (m_catalogRecord.setCode.compare(m_currentRequest.setCode, Qt::CaseInsensitive) == 0 &&
             m_catalogRecord.collectorNumber == m_currentRequest.collectorNumber);
        const bool catalogHasEnglishArt = !requestsFace && requestedPrintingMatches &&
                                          m_catalogRecord.valid() &&
                                          m_catalogRecord.imageLanguage == QStringLiteral("en") &&
                                          !m_catalogRecord.imageUrl.isEmpty();
        if (catalogHasEnglishArt) {
            m_currentRecord = m_catalogRecord;
            beginImageRequest(ArtStage::ScryfallEnglish);
        } else {
            beginJsonRequest(englishUrl(m_currentRequest.name, m_currentRequest.setCode,
                                        m_currentRequest.collectorNumber),
                             Phase::ScryfallEnglish);
        }
    };
    const auto beginMtgchEnglish = [this]() {
        m_currentMtgchEnglishImageTried = true;
        m_currentConfirmedMissing = false;
        m_currentRecord = m_mtgchEnglishRecord;
        beginImageRequest(ArtStage::MtgchEnglish);
    };

    if (m_currentProvider == ArtProvider::Mtgch) {
        if (!m_currentMtgchTried) {
            beginMtgchRequest();
        } else if (!m_currentMtgchEnglishImageTried && !m_mtgchEnglishRecord.imageUrl.isEmpty()) {
            beginMtgchEnglish();
        } else if (!m_currentScryfallEnglishTried) {
            beginScryfall();
        } else {
            finishCurrentCard(false, m_currentConfirmedMissing);
        }
        return;
    }

    if (!m_currentScryfallEnglishTried) {
        beginScryfall();
    } else if (!m_currentMtgchTried) {
        beginMtgchRequest();
    } else if (!m_currentMtgchEnglishImageTried && !m_mtgchEnglishRecord.imageUrl.isEmpty()) {
        beginMtgchEnglish();
    } else {
        finishCurrentCard(false, m_currentConfirmedMissing);
    }
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
