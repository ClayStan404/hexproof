// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtCache.h"
#include "CardArtManager.h"
#include "CardCatalog.h"
#include "CardCatalogCommon.h"
#include "CardImageProvider.h"
#include "CardImageValidation.h"
#include "CardResolver.h"
#include "CatalogStorage.h"

#include <QTimer>

#include <algorithm>

namespace hexproof::client {
using namespace catalog_internal;

void CardCatalog::enqueueFallbackRequest(const CardRequest &request)
{
    if (request.highPriority) {
        // Preserve explicit demand when metadata discovery changes the queue
        // lane; background prefetch must not move back ahead of a hovered card.
        const auto position =
            std::find_if(m_fallbackQueue.cbegin(), m_fallbackQueue.cend(),
                         [](const CardRequest &queued) { return !queued.highPriority; });
        m_fallbackQueue.insert(position, request);
    } else {
        m_fallbackQueue.enqueue(request);
    }
}

int CardCatalog::activeCardResolutions() const
{
    int active = m_cardResolver && m_cardResolver->active() ? 1 : 0;
    for (const auto &resolver : m_parallelResolvers)
        active += resolver && resolver->active() ? 1 : 0;
    return active;
}

void CardCatalog::startFallbackResolutions()
{
    const auto start = [this](CardResolver *resolver) {
        if (resolver && !resolver->active() && !m_fallbackQueue.isEmpty() &&
            activeCardResolutions() + m_directImageJobs.size() + m_pendingDirectImageRetries <
                kMaximumConcurrentImageDownloads) {
            resolver->resolve(m_fallbackQueue.dequeue());
        }
    };
    start(m_cardResolver.get());
    if (m_cardArtProvider == QStringLiteral("parallel")) {
        for (const auto &resolver : m_parallelResolvers)
            start(resolver.get());
    }
}

void CardCatalog::scheduleResolutionWork()
{
    if (m_shuttingDown || QCoreApplication::closingDown() || m_catalogBusy || m_artCacheBusy ||
        !artWritesAllowed())
        return;

    const bool resolverActive = activeCardResolutions() > 0;
    const bool hasWork = !m_cardQueue.isEmpty() || !m_fallbackQueue.isEmpty() ||
                         !m_directImageJobs.isEmpty() || m_pendingDirectImageRetries > 0 ||
                         resolverActive;
    if (!hasWork) {
        finishResolutionIfIdle();
        return;
    }
    if (!m_resolving)
        setResolving(true);

    const bool parallel = m_cardArtProvider == QStringLiteral("parallel");
    constexpr int providerSlots = kMaximumConcurrentImageDownloads / 2;
    const auto providerCount = [this](CardArtProvider provider) -> int & {
        return m_parallelProviderRequests[static_cast<size_t>(provider)];
    };
    if (m_cardQueue.isEmpty() || !m_cardQueue.head().highPriority ||
        (!m_fallbackQueue.isEmpty() && m_fallbackQueue.head().highPriority)) {
        startFallbackResolutions();
    }
    while (activeCardResolutions() + m_directImageJobs.size() + m_pendingDirectImageRetries <
               kMaximumConcurrentImageDownloads &&
           !m_cardQueue.isEmpty()) {
        auto position = m_cardQueue.cbegin();
        if (parallel && providerCount(CardArtProvider::Scryfall) >= providerSlots &&
            providerCount(CardArtProvider::Mtgch) >= providerSlots) {
            // An interactive promotion may have moved an already assigned
            // fallback back to this queue. It still owns its original slot.
            position = std::find_if(position, m_cardQueue.cend(), [](const CardRequest &request) {
                return request.artProvider != CardArtProvider::Auto;
            });
            if (position == m_cardQueue.cend())
                break;
        }
        CardRequest request = m_cardQueue.takeAt(std::distance(m_cardQueue.cbegin(), position));
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

        if (parallel && request.artProvider == CardArtProvider::Auto) {
            const bool chinese = request.language == QStringLiteral("zh");
            CardArtProvider provider = chinese != m_parallelUseAlternateProvider
                                           ? CardArtProvider::Mtgch
                                           : CardArtProvider::Scryfall;
            if (providerCount(provider) >= providerSlots)
                provider = provider == CardArtProvider::Mtgch ? CardArtProvider::Scryfall
                                                              : CardArtProvider::Mtgch;
            request.artProvider = provider;
            ++providerCount(provider);
            m_parallelUseAlternateProvider = !m_parallelUseAlternateProvider;
        }

        const QString canonicalName = request.catalogHint.name;
        const bool requestedFace = canonicalName.contains(QStringLiteral(" // ")) &&
                                   canonicalName.compare(request.name, Qt::CaseInsensitive) != 0 &&
                                   canonicalName.split(QStringLiteral(" // "), Qt::SkipEmptyParts)
                                       .contains(request.name, Qt::CaseInsensitive);
        const QString hintHost = QUrl(request.catalogHint.imageUrl).host().toLower();
        const bool mtgchFaceHint =
            requestedFace &&
            request.catalogHint.faceName.compare(request.name, Qt::CaseInsensitive) == 0 &&
            (hintHost == QStringLiteral("images.mtgch.com") ||
             hintHost.endsWith(QStringLiteral(".mtgch.com")));

        CardRecord directRecord;
        if ((!requestedFace || mtgchFaceHint) && request.language == QStringLiteral("zh")) {
            if (request.catalogHint.imageLanguage == QStringLiteral("zh") &&
                !request.catalogHint.imageUrl.isEmpty()) {
                directRecord = request.catalogHint;
            } else {
                directRecord = lookupLocalizedPrinting(request, request.catalogHint);
                if (request.artProvider == CardArtProvider::Auto &&
                    m_cardArtProvider == QStringLiteral("scryfall") && request.exactArt &&
                    (!directRecord.valid() || directRecord.usesSubstituteArt) &&
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
        const bool prefersMtgch = request.artProvider == CardArtProvider::Mtgch ||
                                  (request.artProvider == CardArtProvider::Auto &&
                                   (m_cardArtProvider == QStringLiteral("mtgch") ||
                                    (m_cardArtProvider == QStringLiteral("auto") &&
                                     request.language == QStringLiteral("zh"))));
        const QString imageHost = QUrl(directRecord.imageUrl).host().toLower();
        const bool recordUsesMtgch = imageHost == QStringLiteral("images.mtgch.com") ||
                                     imageHost.endsWith(QStringLiteral(".mtgch.com"));
        const bool directRecordUsesPreferredProvider = prefersMtgch == recordUsesMtgch;
        const bool needsLocalizedRules = request.supportCard &&
                                         request.language == QStringLiteral("zh") &&
                                         !directRecord.localizedRulesChecked;
        if (!needsLocalizedRules && directRecordUsesPreferredProvider && directRecord.valid() &&
            !directRecord.imageUrl.isEmpty() && startDirectImageDownload({request, directRecord})) {
            continue;
        }
        enqueueFallbackRequest(request);
        if (parallel)
            startFallbackResolutions();
    }

    startFallbackResolutions();
    finishResolutionIfIdle();
}

void CardCatalog::finishResolutionIfIdle()
{
    // A delayed direct-download retry still owns its queued identity even
    // though no network reply is active during the backoff interval.
    if (m_catalogBusy || m_artCacheBusy || activeCardResolutions() > 0 ||
        m_pendingDirectImageRetries > 0 || !m_cardQueue.isEmpty() || !m_fallbackQueue.isEmpty() ||
        !m_directImageJobs.isEmpty() || !m_queuedKeys.isEmpty() ||
        !m_cachedHydrationQueue.isEmpty() || m_cachedHydrationScheduled ||
        !m_incrementalCacheQueue.isEmpty() || m_incrementalCacheScheduled) {
        return;
    }
    m_artCache->saveAsync();
    if (m_resolving) {
        setResolving(false);
        setStatus(QStringLiteral("Card images are up to date."));
        m_totalRequests = 0;
        m_completedRequests = 0;
        setProgress(0.0);
    }
    if (m_cardArtRepairAuditPending) {
        m_cardArtRepairAuditPending = false;
        QTimer::singleShot(0, m_artManager.get(), &CardArtManager::repeatAuditAfterRepair);
    }
    scheduleSearchPreview();
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
    const QByteArray bytes = takeAvailableData(reply);
    const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QNetworkReply::NetworkError networkError = reply->error();
    const QString networkErrorString = reply->errorString();
    const QByteArray retryAfter = reply->rawHeader(QByteArrayLiteral("Retry-After"));
    const QUrl requestUrl = reply->url();

    const bool networkOk = networkError == QNetworkReply::NoError &&
                           (httpStatus == 0 || (httpStatus >= 200 && httpStatus < 300));
    // Keep the job/reply alive while validation is pending: it still owns a
    // download slot and excludes destructive cache maintenance.
    const auto complete = [this, reply, bytes, httpStatus, networkError, networkErrorString,
                           retryAfter, requestUrl, networkOk](const ImagePayloadInspection &image) {
        const DirectImageJob job = m_directImageJobs.take(reply);
        const bool ok = networkOk && image.decoded;
        reply->deleteLater();

        if (ok) {
            if (m_cardResolver)
                m_cardResolver->markHostSuccess(requestUrl);
            CardRecord record = job.record;
            const QString path =
                imagePathFor(job.request.name, record.imageUrl, job.request.language);
            if (writeBytesAtomically(path, bytes)) {
                record.imagePath = path;
                completeCardRequest(job.request, record, true);
            } else {
                completeCardRequest(job.request, record, false, false,
                                    QStringLiteral("could not write the image cache"));
            }
        } else {
            DirectImageJob retryJob = job;
            if (m_cardResolver && httpStatus == 429)
                m_cardResolver->markHostFailure(requestUrl, httpStatus, retryAfter, networkError);
            const int delayMs =
                m_cardResolver ? m_cardResolver->retryDelayMs(httpStatus, retryAfter) : -1;
            if (retryJob.retries < 1 && delayMs >= 0) {
                ++retryJob.retries;
                ++m_pendingDirectImageRetries;
                qCDebug(cardCatalogLog).noquote()
                    << "Concurrent card image download interrupted; retrying"
                    << "card=" + job.request.name << QStringLiteral("http=%1").arg(httpStatus)
                    << "networkError=" + networkErrorString
                    << "url=" + requestUrl.toString(QUrl::FullyEncoded);
                QTimer::singleShot(delayMs, this, [this, retryJob]() {
                    --m_pendingDirectImageRetries;
                    if (QCoreApplication::closingDown())
                        return;
                    if (!startDirectImageDownload(retryJob)) {
                        enqueueFallbackRequest(retryJob.request);
                    }
                    QTimer::singleShot(0, this, &CardCatalog::scheduleResolutionWork);
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
            enqueueFallbackRequest(fallback);
            qCDebug(cardCatalogLog).noquote()
                << "Concurrent card image download interrupted; continuing with fallback providers"
                << "card=" + job.request.name << QStringLiteral("http=%1").arg(httpStatus)
                << "networkError=" + networkErrorString
                << "url=" + requestUrl.toString(QUrl::FullyEncoded);
        }

        if (!QCoreApplication::closingDown())
            QTimer::singleShot(0, this, &CardCatalog::scheduleResolutionWork);
    };
    if (networkOk)
        inspectImagePayloadAsync(this, bytes, complete);
    else
        complete({});
}

} // namespace hexproof::client
