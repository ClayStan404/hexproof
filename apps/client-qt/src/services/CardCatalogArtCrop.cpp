// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtCache.h"
#include "CardArtCrop.h"
#include "CardCatalog.h"
#include "CardCatalogCommon.h"
#include "CardImageProvider.h"
#include "CardImageValidation.h"
#include "CardResolver.h"

#include <QNetworkReply>
#include <QTimer>

#include <utility>

namespace hexproof::client {
using namespace catalog_internal;

namespace {

QString cropFileFingerprint(const QString &path)
{
    const QFileInfo file(path);
    if (!file.isFile())
        return {};
    return file.absoluteFilePath() + QChar(0x1f) + QString::number(file.size()) + QChar(0x1f) +
           QString::number(file.lastModified().toMSecsSinceEpoch());
}

} // namespace

bool CardCatalog::verifiedArtCrop(const QString &path, const QString &name) const
{
    if (m_shuttingDown || QCoreApplication::closingDown())
        return false;
    const QString fingerprint = cropFileFingerprint(path);
    if (fingerprint.isEmpty())
        return false;
    if (const bool *verified = m_artCropValidationResults.object(fingerprint))
        return *verified;
    auto waiting = m_artCropValidationWaiters.find(fingerprint);
    if (waiting != m_artCropValidationWaiters.end()) {
        waiting->names.insert(name);
        return false;
    }
    const quint64 serial = ++m_artCropValidationSerial;
    m_artCropValidationWaiters.insert(fingerprint, {serial, {name}});
    // The const getter schedules local inspection only. It never starts a
    // download, writes the index, or claims the cache-maintenance lock.
    auto *self = const_cast<CardCatalog *>(this);
    inspectImageFileAsync(
        self, path, [self, path, fingerprint, serial](const ImagePayloadInspection &image) {
            auto waiting = self->m_artCropValidationWaiters.find(fingerprint);
            if (self->m_shuttingDown || waiting == self->m_artCropValidationWaiters.end() ||
                waiting->serial != serial)
                return;
            const QSet<QString> names = waiting->names;
            self->m_artCropValidationWaiters.erase(waiting);
            const bool current = cropFileFingerprint(path) == fingerprint;
            if (current)
                self->m_artCropValidationResults.insert(fingerprint, new bool(image.decoded));
            if (current && !image.decoded)
                return;
            if (current && self->m_cardImageProvider)
                self->m_cardImageProvider->invalidatePath(path);
            for (const QString &arrived : names)
                emit self->cardArtCropAvailable(arrived);
        });
    return false;
}

int CardCatalog::activeImageDownloads() const
{
    return activeCardResolutions() + m_directImageJobs.size() + m_pendingDirectImageRetries +
           m_artCropJobs.size();
}

void CardCatalog::prepareTableArtCrops(const QVariantList &cards)
{
    if (m_shuttingDown || QCoreApplication::closingDown() || m_catalogBusy || m_artCacheBusy ||
        !artWritesAllowed())
        return;
    for (const QVariant &value : cards) {
        const QVariantMap card = value.toMap();
        CardRequest request{card.value(QStringLiteral("name")).toString().simplified(),
                            card.value(QStringLiteral("setCode")).toString().toUpper(),
                            card.value(QStringLiteral("collectorNumber")).toString(), m_language};
        request.exactArt = card.value(QStringLiteral("exactArt")).toBool();
        request.supportCard = isSupportCardRequest(card);
        if (request.name.isEmpty() || !customImagePath(request).isEmpty())
            continue;
        const QString key =
            cacheKey(request.name, request.language, request.setCode, request.collectorNumber);
        CardRecord record = m_artCache->exactRecord(key);
        if (!record.valid() || record.resolutionVersion < kCardResolutionVersion ||
            !m_artCache->matchesRequestedFace(request, record) ||
            (record.reusesLocalArt && !request.allowsSubstituteArt(m_artCache->reuseLocalArt())) ||
            !QFileInfo::exists(record.imagePath)) {
            record = cachedResolvedPrinting(request);
            if (!record.valid() || !QFileInfo::exists(record.imagePath))
                continue;
            // Alias an existing local image without metadata discovery or a
            // full-image request. Match readiness remains a separate concern.
            record.requestedName = request.name;
            m_artCache->rememberSuccess(key, record);
        }
        queueOptionalArtCrop(request, record);
    }
    scheduleResolutionWork();
}

void CardCatalog::queueOptionalArtCrop(const CardRequest &request, const CardRecord &record)
{
    if (m_shuttingDown || !artWritesAllowed() || !record.valid() ||
        !customImagePath(request).isEmpty())
        return;
    const QString url = artCropUrlForImage(record.imageUrl);
    if (url.isEmpty())
        return;
    const QString key =
        cacheKey(request.name, request.language, request.setCode, request.collectorNumber);
    const bool refresh = m_artCropRefreshKeys.remove(key);
    if (!refresh && record.artCropUrl == url && !record.artCropPath.isEmpty() &&
        QFileInfo::exists(record.artCropPath))
        return;
    const QString path = imagePathFor(request.name, url, request.language);
    const QDateTime now = QDateTime::currentDateTimeUtc();
    if (m_artCropFailures.value(path) > now)
        return;
    m_artCropFailures.remove(path);

    // Multiple printing aliases may share one downloaded image. Retain each
    // index destination, while fetching and validating the bytes only once.
    auto target = m_artCropTargets.find(path);
    if (target != m_artCropTargets.end()) {
        if (refresh) {
            for (ArtCropJob &queued : m_artCropQueue) {
                if (queued.cropPath == path)
                    queued.refresh = true;
            }
        }
        for (const CardRequest &existing : std::as_const(target.value())) {
            if (cacheKey(existing.name, existing.language, existing.setCode,
                         existing.collectorNumber) == key)
                return;
        }
        target->append(request);
        return;
    }
    m_artCropTargets.insert(path, {request});
    m_artCropQueue.enqueue({request, record.imageUrl, url, path, refresh});
    // Reserve maintenance exclusion before any full-image completion signal
    // can let a caller start cache deletion or storage migration.
    setResolving(true);
}

void CardCatalog::startOptionalArtCrop()
{
    // A crop is optional presentation data. Leave all queued full images and
    // interactive work ahead of it, and occupy at most one of the shared slots.
    if (m_shuttingDown || QCoreApplication::closingDown() || !artWritesAllowed() ||
        !m_cardResolver || !m_artCropJobs.isEmpty() || !m_cardQueue.isEmpty() ||
        !m_fallbackQueue.isEmpty() || !m_incrementalCacheQueue.isEmpty() ||
        activeImageDownloads() >= kMaximumConcurrentImageDownloads)
        return;

    while (!m_artCropQueue.isEmpty()) {
        const ArtCropJob job = m_artCropQueue.dequeue();
        if (!job.refresh && QFileInfo::exists(job.cropPath)) {
            finishArtCrop(job, true);
            continue;
        }
        const QUrl url(job.cropUrl);
        if (m_cardResolver->hostInCooldown(url)) {
            finishArtCrop(job, false);
            continue;
        }
        QNetworkReply *reply = m_cardResolver->requestImage(url);
        if (!reply) {
            finishArtCrop(job, false);
            continue;
        }
        m_artCropJobs.insert(reply, job);
        connect(reply, &QNetworkReply::finished, this,
                [this, reply]() { handleArtCropReply(reply); });
        return;
    }
}

void CardCatalog::handleArtCropReply(QNetworkReply *reply)
{
    const QByteArray bytes = takeAvailableData(reply);
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const auto error = reply->error();
    const QByteArray retryAfter = reply->rawHeader(QByteArrayLiteral("Retry-After"));
    const QUrl url = reply->url();
    const bool networkOk =
        error == QNetworkReply::NoError && (status == 0 || (status >= 200 && status < 300));
    // Keep the job in the shared pool during asynchronous decoding. The
    // context also drops this callback if the catalog/profile is destroyed.
    const auto complete = [this, reply, bytes, status, error, retryAfter, url,
                           networkOk](const ImagePayloadInspection &image) {
        const ArtCropJob job = m_artCropJobs.take(reply);
        reply->deleteLater();
        bool stillReferenced = false;
        for (const CardRequest &target : m_artCropTargets.value(job.cropPath)) {
            const CardRecord latest = m_artCache->exactRecord(
                cacheKey(target.name, target.language, target.setCode, target.collectorNumber));
            stillReferenced |= latest.valid() && latest.imageUrl == job.imageUrl;
        }
        const bool decoded = networkOk && image.decoded;
        const bool success = decoded && stillReferenced && artWritesAllowed() &&
                             writeBytesAtomically(job.cropPath, bytes);
        QSet<QString> validatedNames;
        if (success) {
            const QString fingerprint = cropFileFingerprint(job.cropPath);
            if (!fingerprint.isEmpty())
                m_artCropValidationResults.insert(fingerprint, new bool(true));
            // A same-path Retry can replace a file without changing its stat
            // fingerprint. Its verified bytes supersede any older local read.
            validatedNames = m_artCropValidationWaiters.take(fingerprint).names;
        }
        if (decoded)
            m_cardResolver->markHostSuccess(url);
        else if (status == 429)
            m_cardResolver->markHostFailure(url, status, retryAfter, error);
        finishArtCrop(job, success, std::move(validatedNames));
        QTimer::singleShot(0, this, &CardCatalog::scheduleResolutionWork);
    };
    if (networkOk)
        inspectImagePayloadAsync(this, bytes, complete);
    else
        complete({});
}

void CardCatalog::finishArtCrop(const ArtCropJob &job, bool success, QSet<QString> arrivedNames)
{
    const QList<CardRequest> targets = m_artCropTargets.take(job.cropPath);
    if (!success) {
        // A missing crop never changes full-image readiness or its negative
        // cache. Suppress repeated background attempts; explicit Retry clears it.
        m_artCropFailures.insert(job.cropPath, QDateTime::currentDateTimeUtc().addSecs(5 * 60));
        return;
    }
    bool changed = false;
    for (const CardRequest &target : targets) {
        const QString key =
            cacheKey(target.name, target.language, target.setCode, target.collectorNumber);
        CardRecord latest = m_artCache->exactRecord(key);
        if (!latest.valid() || latest.imageUrl != job.imageUrl)
            continue;
        // Merge into current metadata: translated rules or the chosen source
        // may have changed while this optional download was in flight.
        if (latest.artCropUrl != job.cropUrl || latest.artCropPath != job.cropPath) {
            latest.artCropUrl = job.cropUrl;
            latest.artCropPath = job.cropPath;
            m_artCache->rememberSuccess(key, latest);
            changed = true;
        }
        arrivedNames.insert(target.name);
        const QStringList faces = latest.name.split(QStringLiteral(" // "), Qt::SkipEmptyParts);
        if (faces.size() == 2 &&
            normalizedCardName(target.name) == normalizedCardName(faces.first()) &&
            normalizedCardName(latest.faceName) == normalizedCardName(faces.first()) &&
            normalizedCardName(faces.first()) != normalizedCardName(faces.last()) &&
            normalizedCardName(target.name) != normalizedCardName(latest.name))
            arrivedNames.insert(latest.name);
    }
    if (changed)
        m_artCache->saveAsync();
    if (!arrivedNames.isEmpty()) {
        if (m_cardImageProvider)
            m_cardImageProvider->invalidatePath(job.cropPath);
        // Full-card consumers have not changed; refresh only this card's
        // battlefield illustration, including a restored file whose index
        // mapping was already present, instead of invalidating the library.
        for (const QString &name : arrivedNames)
            emit cardArtCropAvailable(name);
    }
}

} // namespace hexproof::client
