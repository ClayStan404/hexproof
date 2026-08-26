// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalogCommon.h"
#include "CardResolver.h"

namespace hexproof::client {
using namespace catalog_internal;

void CardResolver::continueAfterImageFailure(bool confirmedMissing)
{
    switch (m_currentArtStage) {
    case ArtStage::ScryfallChineseExact:
        beginChineseAlternate();
        return;
    case ArtStage::ScryfallChineseAlternate:
        continueAfterScryfallChinese();
        return;
    case ArtStage::MtgchChinese:
        continueAfterMtgchChinese();
        return;
    case ArtStage::ScryfallEnglish:
        m_currentConfirmedMissing = m_currentConfirmedMissing || confirmedMissing;
        beginNextEnglishCandidate();
        return;
    case ArtStage::MtgchEnglish:
        m_currentConfirmedMissing = m_currentConfirmedMissing || confirmedMissing;
        beginNextEnglishCandidate();
        return;
    case ArtStage::None:
        finishCurrentCard(false, confirmedMissing);
        return;
    }
}

void CardResolver::continueAfterJsonFailure(Phase phase, bool confirmedMissing)
{
    if (phase == Phase::ScryfallEnglish && confirmedMissing)
        m_currentConfirmedMissing = true;
    switch (phase) {
    case Phase::ScryfallChineseExact:
        beginChineseAlternate();
        return;
    case Phase::ScryfallChineseSearch:
        continueAfterScryfallChinese();
        return;
    case Phase::Mtgch:
        if (m_currentRequest.language == QStringLiteral("zh")) {
            continueAfterMtgchChinese();
        } else {
            beginNextEnglishCandidate();
        }
        return;
    case Phase::ScryfallEnglish:
        m_currentConfirmedMissing = m_currentConfirmedMissing || confirmedMissing;
        beginNextEnglishCandidate();
        return;
    case Phase::Image:
    case Phase::None:
        finishCurrentCard(false, confirmedMissing);
        return;
    }
}

bool CardResolver::retryCurrentPhase(const QUrl &url, Phase phase, int httpStatus,
                                     const QByteArray &retryAfter)
{
    if (QCoreApplication::closingDown())
        return false;
    constexpr int maximumRetries = 1;
    if (m_currentPhase != phase || m_currentPhaseRetries >= maximumRetries)
        return false;

    const int delayMs = retryDelayMs(httpStatus, retryAfter);
    if (delayMs < 0)
        return false;

    ++m_currentPhaseRetries;
    QTimer::singleShot(delayMs, this, [this, url, phase]() {
        if (phase == Phase::Image)
            beginImageRequest(m_currentArtStage);
        else
            beginJsonRequest(url, phase);
    });
    return true;
}

void CardResolver::setCurrentFailure(const QUrl &url, Phase phase, int httpStatus,
                                     int networkErrorCode, const QString &networkErrorString,
                                     const QString &validationError)
{
    QString reason = validationError;
    if (reason.isEmpty() && httpStatus > 0)
        reason = QStringLiteral("HTTP %1").arg(httpStatus);
    if (reason.isEmpty() && networkErrorCode != QNetworkReply::NoError)
        reason = networkErrorString;
    if (reason.isEmpty())
        reason = QStringLiteral("request failed");

    const QString host = url.host().isEmpty() ? QStringLiteral("unknown host") : url.host();
    m_currentFailureDetail = QStringLiteral("%1 via %2: %3").arg(phaseName(phase), host, reason);
}

} // namespace hexproof::client
