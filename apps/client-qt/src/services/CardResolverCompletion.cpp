// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardResolver.h"

namespace hexproof::client {

void CardResolver::finishCurrentCard(bool success, bool cacheFailure)
{
    const CardRequest request = m_currentRequest;
    CardRecord record = m_currentRecord;
    const QString failureDetail = m_currentFailureDetail;
    cacheFailure = cacheFailure || m_currentConfirmedMissing;
    m_currentRequest = {};
    m_catalogRecord = {};
    m_currentRecord = {};
    m_mtgchEnglishRecord = {};
    m_currentFailureDetail.clear();
    m_currentArtStage = ArtStage::None;
    m_currentPhase = Phase::None;
    m_currentPhaseRetries = 0;
    m_currentMtgchTried = false;
    m_currentConfirmedMissing = false;
    m_active = false;
    if (m_callbacks.completed) {
        m_callbacks.completed(request, std::move(record), success, cacheFailure, failureDetail);
    }
    if (m_callbacks.queueMoreWork)
        m_callbacks.queueMoreWork();
}

} // namespace hexproof::client
