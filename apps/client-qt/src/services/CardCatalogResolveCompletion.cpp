// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtCache.h"
#include "CardCatalog.h"
#include "CardCatalogCommon.h"
#include "CardImageProvider.h"

namespace hexproof::client {
using namespace catalog_internal;

namespace {

void retainLocalizedMetadata(const CardRequest &request, const CardRecord &cached,
                             CardRecord *updated)
{
    if (request.language != QStringLiteral("zh") || !cached.valid())
        return;
    if (!looksLikeChinese(updated->localizedName) && looksLikeChinese(cached.localizedName))
        updated->localizedName = cached.localizedName;
    if (!looksLikeChinese(updated->typeLine) && looksLikeChinese(cached.typeLine))
        updated->typeLine = cached.typeLine;
    if (updated->oracleTextLanguage != QStringLiteral("zh") &&
        cached.oracleTextLanguage == QStringLiteral("zh")) {
        updated->oracleText = cached.oracleText;
        updated->oracleTextLanguage = cached.oracleTextLanguage;
    }
    updated->localizedRulesChecked = updated->localizedRulesChecked || cached.localizedRulesChecked;
}

} // namespace

void CardCatalog::scheduleImageRevisionChanged()
{
    ++m_imageRevision;
    if (m_imageRevisionNotificationPending)
        return;
    m_imageRevisionNotificationPending = true;
    // Every visible image observes this property. Coalesce metadata and art
    // arrivals within one frame without delaying per-card completion signals.
    QTimer::singleShot(16, this, [this]() {
        m_imageRevisionNotificationPending = false;
        emit imageRevisionChanged();
    });
}

void CardCatalog::cacheResolvedMetadata(const CardRequest &request, const CardRecord &record)
{
    if (!record.valid() || record.oracleTextLanguage.isEmpty())
        return;
    const QString key =
        cacheKey(request.name, request.language, request.setCode, request.collectorNumber);
    const CardRecord cached = m_artCache->exactRecord(key);
    CardRecord updated = record;
    if (cached.valid()) {
        updated.imagePath = cached.imagePath;
        updated.imageUrl = cached.imageUrl;
        updated.imageLanguage = cached.imageLanguage;
        updated.illustrationId = cached.illustrationId;
        updated.usesSubstituteArt = cached.usesSubstituteArt;
        updated.reusesLocalArt = cached.reusesLocalArt;
        updated.resolutionVersion = cached.resolutionVersion;
        retainLocalizedMetadata(request, cached, &updated);
    }
    updated.requestedName = request.name;
    if (request.specifiesPrinting()) {
        updated.setCode = request.setCode;
        updated.collectorNumber = request.collectorNumber;
    }
    if (recordToJson(updated) == recordToJson(cached))
        return;
    m_artCache->rememberSuccess(key, updated);
    m_artCache->saveAsync();
    scheduleImageRevisionChanged();
}

void CardCatalog::completeCardRequest(const CardRequest &request, CardRecord record, bool success,
                                      bool cacheFailure, const QString &failureDetail)
{
    if (request.artProvider != CardArtProvider::Auto)
        --m_parallelProviderRequests[static_cast<size_t>(request.artProvider)];
    const bool previewOnly =
        queuedRequestKey(request) == m_searchPreviewIdentity && !m_searchPreviewAdopted;
    const QString key =
        cacheKey(request.name, request.language, request.setCode, request.collectorNumber);
    m_queuedKeys.remove(queuedRequestKey(request));
    if (success) {
        const CardRecord cached = m_artCache->exactRecord(key);
        // A later art-only retry must not erase translated metadata already
        // obtained when an earlier image download failed.
        retainLocalizedMetadata(request, cached, &record);
        if (!request.exactArt && record.usesSubstituteArt && cached.valid() &&
            cached.resolutionVersion >= kCardResolutionVersion && !cached.usesSubstituteArt &&
            m_artCache->matchesRequestedFace(request, cached) &&
            QFileInfo::exists(cached.imagePath)) {
            record = cached;
        }
        record.requestedName = request.name;
        record.resolutionVersion = kCardResolutionVersion;
        m_artCache->rememberSuccess(key, record);
        if (m_cardImageProvider)
            m_cardImageProvider->invalidatePath(record.imagePath);
        emitRecord(record);
        scheduleImageRevisionChanged();
    } else if (cacheFailure) {
        m_artCache->rememberFailure(key);
    }
    if (!success && !previewOnly) {
        setLastError(
            failureDetail.isEmpty()
                ? QStringLiteral("Could not cache %1.").arg(request.name)
                : QStringLiteral("Could not cache %1: %2").arg(request.name, failureDetail));
    }
    if (!previewOnly)
        ++m_completedRequests;
    if (m_totalRequests > 0)
        setProgress(static_cast<qreal>(m_completedRequests) / m_totalRequests);
    emitCardCacheCompletion(request, success);
    emit busyChanged();
}

void CardCatalog::emitCardCacheCompletion(const CardRequest &request, bool success)
{
    finishSearchPreview(request);
    const QString identity = queuedRequestKey(request);
    const QList<MatchCacheSubscription> subscriptions = m_matchCacheSubscriptions.take(identity);
    for (const MatchCacheSubscription &subscription : subscriptions) {
        emit matchCardCacheFinished(subscription.loadId, subscription.generation, identity,
                                    request.name, request.setCode, request.collectorNumber,
                                    request.exactArt, success);
    }
    emit cardCacheFinished(request.name, request.setCode, request.collectorNumber, success);
}

void CardCatalog::emitRecord(const CardRecord &record)
{
    emit cardAvailable(record.requestedName, record.localizedName, record.typeLine,
                       record.imagePath, record.setCode, record.collectorNumber);

    // Face expansion queues independent images under their face names. A deck
    // imported with the whole canonical name must invalidate its missing-art
    // projection when the front arrives, while a reverse must never replace it.
    const QStringList faces = record.name.split(QStringLiteral(" // "), Qt::SkipEmptyParts);
    if (faces.size() != 2 || record.setCode.isEmpty() || record.collectorNumber.isEmpty() ||
        record.imagePath.isEmpty()) {
        return;
    }
    const QString frontName = normalizedCardName(faces.first());
    const QString requestedName = normalizedCardName(record.requestedName);
    if (frontName == normalizedCardName(faces.last()) || requestedName != frontName ||
        normalizedCardName(record.faceName) != frontName ||
        requestedName == normalizedCardName(record.name)) {
        return;
    }
    emit cardAvailable(record.name, record.localizedName, record.typeLine, record.imagePath,
                       record.setCode, record.collectorNumber);
}

} // namespace hexproof::client
