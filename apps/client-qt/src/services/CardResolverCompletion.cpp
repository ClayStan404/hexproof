// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalogCommon.h"
#include "CardResolver.h"

namespace hexproof::client {

void CardResolver::retainMetadata(CardRecord *record, bool publish)
{
    if (!record->valid())
        return;
    const bool chinese = m_currentRequest.language == QStringLiteral("zh");
    if (chinese && record->oracleTextLanguage == QStringLiteral("zh"))
        record->localizedRulesChecked = true;
    if (!m_metadataRecord.valid()) {
        m_metadataRecord = *record;
    } else {
        if (!record->oracleTextLanguage.isEmpty() &&
            (m_metadataRecord.oracleTextLanguage.isEmpty() ||
             (record->oracleTextLanguage == m_currentRequest.language &&
              m_metadataRecord.oracleTextLanguage != m_currentRequest.language) ||
             (record->oracleTextLanguage == m_metadataRecord.oracleTextLanguage &&
              m_metadataRecord.oracleText.isEmpty()))) {
            m_metadataRecord.oracleText = record->oracleText;
            m_metadataRecord.oracleTextLanguage = record->oracleTextLanguage;
        }
        if (m_metadataRecord.localizedName.isEmpty() ||
            (chinese && catalog_internal::looksLikeChinese(record->localizedName) &&
             !catalog_internal::looksLikeChinese(m_metadataRecord.localizedName))) {
            m_metadataRecord.localizedName = record->localizedName;
        }
        if (m_metadataRecord.typeLine.isEmpty() ||
            (chinese && catalog_internal::looksLikeChinese(record->typeLine) &&
             !catalog_internal::looksLikeChinese(m_metadataRecord.typeLine))) {
            m_metadataRecord.typeLine = record->typeLine;
        }
    }
    m_metadataRecord.localizedRulesChecked =
        m_metadataRecord.localizedRulesChecked || record->localizedRulesChecked;
    record->localizedRulesChecked = m_metadataRecord.localizedRulesChecked;
    record->oracleText = m_metadataRecord.oracleText;
    record->oracleTextLanguage = m_metadataRecord.oracleTextLanguage;
    if (!m_metadataRecord.localizedName.isEmpty())
        record->localizedName = m_metadataRecord.localizedName;
    if (!m_metadataRecord.typeLine.isEmpty())
        record->typeLine = m_metadataRecord.typeLine;
    if (publish && m_callbacks.metadataAvailable &&
        !m_metadataRecord.oracleTextLanguage.isEmpty()) {
        CardRecord metadata = *record;
        // Metadata-only publication must not replace a previously cached image
        // with an unverified URL from a failed download candidate.
        metadata.imagePath.clear();
        metadata.imageUrl.clear();
        metadata.imageLanguage.clear();
        m_callbacks.metadataAvailable(m_currentRequest, metadata);
    }
}

void CardResolver::finishCurrentCard(bool success, bool cacheFailure)
{
    if (!m_currentRecord.valid() && m_metadataRecord.valid())
        m_currentRecord = m_metadataRecord;
    if (m_currentRequest.supportCard && m_currentRequest.language == QStringLiteral("zh")) {
        const bool checked = m_metadataRecord.oracleTextLanguage == QStringLiteral("zh") ||
                             (m_localizedRulesAttempted && !m_localizedRulesTransientFailure);
        m_currentRecord.localizedRulesChecked = checked;
        m_metadataRecord.localizedRulesChecked = checked;
    }
    retainMetadata(&m_currentRecord, true);
    const CardRequest request = m_currentRequest;
    CardRecord record = m_currentRecord;
    const QString failureDetail = m_currentFailureDetail;
    cacheFailure = cacheFailure || m_currentConfirmedMissing;
    m_currentRequest = {};
    m_catalogRecord = {};
    m_currentRecord = {};
    m_mtgchEnglishRecord = {};
    m_metadataRecord = {};
    m_pendingImageRecord = {};
    m_pendingImageStage = ArtStage::None;
    m_rulesProbeAttempted = false;
    m_localizedRulesAttempted = false;
    m_localizedRulesTransientFailure = false;
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
