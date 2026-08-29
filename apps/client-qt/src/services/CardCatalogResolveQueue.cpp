// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtCache.h"
#include "CardCatalog.h"
#include "CardCatalogCommon.h"
#include "CardImageProvider.h"
#include "CardResolver.h"
#include "CatalogStorage.h"

namespace hexproof::client {
using namespace catalog_internal;

void CardCatalog::scheduleResolutionWork()
{
    if (m_shuttingDown || QCoreApplication::closingDown() || m_catalogBusy)
        return;

    const bool resolverActive = m_cardResolver && m_cardResolver->active();
    const bool hasWork = !m_cardQueue.isEmpty() || !m_fallbackQueue.isEmpty() ||
                         !m_directImageJobs.isEmpty() || resolverActive;
    if (!hasWork) {
        finishResolutionIfIdle();
        return;
    }
    if (!m_resolving)
        setResolving(true);

    while (m_directImageJobs.size() < kMaximumConcurrentImageDownloads && !m_cardQueue.isEmpty()) {
        CardRequest request = m_cardQueue.dequeue();
        request.catalogHint =
            request.catalogHint.valid() ? request.catalogHint : lookupCatalog(request);

        if (request.allowsSubstituteArt(m_artCache->reuseLocalArt())) {
            const CardRecord localArt = reusableLocalArt(request, request.catalogHint);
            if (localArt.valid()) {
                completeCardRequest(
                    request, substituteArtRecord(request, request.catalogHint, localArt), true);
                continue;
            }
        }

        const QString canonicalName = request.catalogHint.name;
        const bool requestedFace = canonicalName.contains(QStringLiteral(" // ")) &&
                                   canonicalName.compare(request.name, Qt::CaseInsensitive) != 0 &&
                                   canonicalName.split(QStringLiteral(" // "), Qt::SkipEmptyParts)
                                       .contains(request.name, Qt::CaseInsensitive);

        CardRecord directRecord;
        if (!requestedFace && request.language == QStringLiteral("zh")) {
            if (request.catalogHint.imageLanguage == QStringLiteral("zh") &&
                !request.catalogHint.imageUrl.isEmpty()) {
                directRecord = request.catalogHint;
            } else {
                directRecord = lookupLocalizedPrinting(request, request.catalogHint);
                if (request.exactArt && (!directRecord.valid() || directRecord.usesSubstituteArt) &&
                    request.catalogHint.imageLanguage == QStringLiteral("en") &&
                    !request.catalogHint.imageUrl.isEmpty()) {
                    directRecord = request.catalogHint;
                }
                if (directRecord.valid() && !directRecord.imageUrl.isEmpty()) {
                    const bool substitute = directRecord.usesSubstituteArt;
                    if (!request.setCode.isEmpty() && !request.collectorNumber.isEmpty()) {
                        directRecord.setCode = request.setCode;
                        directRecord.collectorNumber = request.collectorNumber;
                    }
                    directRecord.usesSubstituteArt = substitute;
                }
            }
        } else if (!requestedFace && request.language == QStringLiteral("en") &&
                   request.catalogHint.imageLanguage == QStringLiteral("en") &&
                   !request.catalogHint.imageUrl.isEmpty()) {
            directRecord = request.catalogHint;
        }

        directRecord.requestedName = request.name;
        // Catalog image records are sourced from Scryfall. MTGCH-first requests
        // must enter the resolver instead of taking this concurrent fast path.
        const bool directRecordUsesPreferredProvider = m_cardArtProvider != QStringLiteral("mtgch");
        if (directRecordUsesPreferredProvider && directRecord.valid() &&
            !directRecord.imageUrl.isEmpty() && startDirectImageDownload({request, directRecord})) {
            continue;
        }
        m_fallbackQueue.enqueue(request);
    }

    if (m_cardResolver && !m_cardResolver->active() && !m_fallbackQueue.isEmpty())
        m_cardResolver->resolve(m_fallbackQueue.dequeue());
    finishResolutionIfIdle();
}

void CardCatalog::finishResolutionIfIdle()
{
    if (m_catalogBusy || (m_cardResolver && m_cardResolver->active()) || !m_cardQueue.isEmpty() ||
        !m_fallbackQueue.isEmpty() || !m_directImageJobs.isEmpty() ||
        !m_cachedHydrationQueue.isEmpty() || m_cachedHydrationScheduled ||
        !m_incrementalCacheQueue.isEmpty() || m_incrementalCacheScheduled) {
        return;
    }
    if (m_artCache->dirty() && !saveResolutionCache())
        setLastError(QStringLiteral("Could not save the card image cache."));
    if (!m_resolving)
        return;
    setResolving(false);
    setStatus(QStringLiteral("Card images are up to date."));
    m_totalRequests = 0;
    m_completedRequests = 0;
    setProgress(0.0);
}

bool CardCatalog::startDirectImageDownload(const DirectImageJob &job)
{
    if (m_shuttingDown || QCoreApplication::closingDown() || !m_cardResolver)
        return false;
    const QUrl imageUrl(job.record.imageUrl);
    if (!imageUrl.isValid() || imageUrl.scheme() != QStringLiteral("https") ||
        m_cardResolver->hostInCooldown(imageUrl)) {
        return false;
    }

    const QString path = imagePathFor(job.request.name, job.record.imageUrl, job.request.language);
    if (QFileInfo::exists(path)) {
        CardRecord record = job.record;
        record.imagePath = path;
        completeCardRequest(job.request, record, true);
        return true;
    }

    setStatus(QStringLiteral("Caching card images…"));
    QNetworkReply *reply = m_cardResolver->requestImage(imageUrl);
    if (!reply)
        return false;
    m_directImageJobs.insert(reply, job);
    connect(reply, &QNetworkReply::finished, this,
            [this, reply]() { handleDirectImageReply(reply); });
    return true;
}

void CardCatalog::handleDirectImageReply(QNetworkReply *reply)
{
    const DirectImageJob job = m_directImageJobs.take(reply);
    const QByteArray bytes = takeAvailableData(reply);
    const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QNetworkReply::NetworkError networkError = reply->error();
    const QString networkErrorString = reply->errorString();
    const QByteArray retryAfter = reply->rawHeader(QByteArrayLiteral("Retry-After"));
    const QUrl requestUrl = reply->url();

    const bool decoderCanRead = inspectImagePayload(bytes).canRead;
    const bool networkOk = networkError == QNetworkReply::NoError &&
                           (httpStatus == 0 || (httpStatus >= 200 && httpStatus < 300));
    const bool ok = networkOk && !bytes.isEmpty() && decoderCanRead;
    reply->deleteLater();

    if (ok) {
        if (m_cardResolver)
            m_cardResolver->markHostSuccess(requestUrl);
        CardRecord record = job.record;
        const QString path = imagePathFor(job.request.name, record.imageUrl, job.request.language);
        if (writeBytesAtomically(path, bytes)) {
            record.imagePath = path;
            completeCardRequest(job.request, record, true);
        } else {
            completeCardRequest(job.request, record, false, false,
                                QStringLiteral("could not write the image cache"));
        }
    } else {
        DirectImageJob retryJob = job;
        const int delayMs =
            m_cardResolver ? m_cardResolver->retryDelayMs(httpStatus, retryAfter) : -1;
        if (retryJob.retries < 1 && delayMs >= 0) {
            ++retryJob.retries;
            qCDebug(cardCatalogLog).noquote()
                << "Concurrent card image download interrupted; retrying"
                << "card=" + job.request.name << QStringLiteral("http=%1").arg(httpStatus)
                << "networkError=" + networkErrorString
                << "url=" + requestUrl.toString(QUrl::FullyEncoded);
            QTimer::singleShot(delayMs, this, [this, retryJob]() {
                if (QCoreApplication::closingDown())
                    return;
                if (!startDirectImageDownload(retryJob)) {
                    m_fallbackQueue.enqueue(retryJob.request);
                    QTimer::singleShot(0, this, &CardCatalog::scheduleResolutionWork);
                }
            });
            if (!QCoreApplication::closingDown())
                QTimer::singleShot(0, this, &CardCatalog::scheduleResolutionWork);
            return;
        }
        if (m_cardResolver)
            m_cardResolver->markHostFailure(requestUrl, httpStatus, retryAfter, networkError);
        CardRequest fallback = job.request;
        if (fallback.catalogHint.imageUrl == job.record.imageUrl)
            fallback.catalogHint.imageUrl.clear();
        m_fallbackQueue.enqueue(fallback);
        qCDebug(cardCatalogLog).noquote()
            << "Concurrent card image download interrupted; continuing with fallback providers"
            << "card=" + job.request.name << QStringLiteral("http=%1").arg(httpStatus)
            << "networkError=" + networkErrorString
            << "url=" + requestUrl.toString(QUrl::FullyEncoded);
    }

    if (!QCoreApplication::closingDown())
        QTimer::singleShot(0, this, &CardCatalog::scheduleResolutionWork);
}

} // namespace hexproof::client
