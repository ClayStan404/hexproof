// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtCache.h"
#include "CardCatalog.h"
#include "CardCatalogCommon.h"

namespace hexproof::client {
using namespace catalog_internal;

void CardCatalog::completeCardRequest(const CardRequest &request, CardRecord record, bool success,
                                      bool cacheFailure, const QString &failureDetail)
{
    const QString key =
        cacheKey(request.name, request.language, request.setCode, request.collectorNumber);
    m_queuedKeys.remove(queuedRequestKey(request));
    if (success) {
        const CardRecord cached = m_artCache->exactRecord(key);
        if (!request.exactArt && record.usesSubstituteArt && cached.valid() &&
            cached.resolutionVersion >= kCardResolutionVersion && !cached.usesSubstituteArt &&
            QFileInfo::exists(cached.imagePath)) {
            record = cached;
        }
        record.requestedName = request.name;
        record.resolutionVersion = kCardResolutionVersion;
        m_artCache->rememberSuccess(key, record);
        emitRecord(record);
        ++m_imageRevision;
        emit imageRevisionChanged();
    } else if (cacheFailure) {
        m_artCache->rememberFailure(key);
    }
    if (!success) {
        setLastError(
            failureDetail.isEmpty()
                ? QStringLiteral("Could not cache %1.").arg(request.name)
                : QStringLiteral("Could not cache %1: %2").arg(request.name, failureDetail));
    }
    ++m_completedRequests;
    if (m_totalRequests > 0)
        setProgress(static_cast<qreal>(m_completedRequests) / m_totalRequests);
    emit cardCacheFinished(request.name, request.setCode, request.collectorNumber, success);
}

void CardCatalog::emitRecord(const CardRecord &record)
{
    emit cardAvailable(record.requestedName, record.localizedName, record.typeLine,
                       record.imagePath, record.setCode, record.collectorNumber);
}

} // namespace hexproof::client
