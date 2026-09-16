// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalog.h"
#include "ApplicationPaths.h"
#include "CardArtCache.h"
#include "CardArtManager.h"
#include "CardArtStorage.h"
#include "CardCatalogCommon.h"
#include "CardCatalogFaceExpansionState.h"
#include "CardImageProvider.h"
#include "CardResolver.h"
#include "CatalogInstaller.h"
#include "CatalogRepository.h"
#include "CatalogStorage.h"
#include "CustomCardArtStore.h"

#include <algorithm>

namespace hexproof::client {
using namespace catalog_internal;

CardCatalog::CardCatalog(QObject *parent)
    : CardCatalog(defaultStorageRoot(), parent)
{
}

CardCatalog::CardCatalog(const QString &storageRoot, QObject *parent)
    : CardCatalog(storageRoot, nullptr, parent)
{
}

CardCatalog::CardCatalog(const QString &storageRoot, QNetworkAccessManager *network,
                         QObject *parent)
    : QObject(parent),
      m_storageRoot(storageRoot),
      m_databasePath(QDir(storageRoot).filePath(QStringLiteral("cards.sqlite"))),
      m_catalogMetadataPath(QDir(storageRoot).filePath(QStringLiteral("catalog.json"))),
      m_artStorage(std::make_unique<CardArtStorage>(storageRoot)),
      m_customArt(
          std::make_unique<CustomCardArtStore>(storageRoot, m_artStorage->customImageRoot())),
      m_artCache(std::make_unique<CardArtCache>(storageRoot, m_artStorage->imageRoot(),
                                                m_artStorage->previousImageRoots(),
                                                m_artStorage->available()))
{
    if (network) {
        m_network = network;
    } else {
        m_ownedNetwork = std::make_unique<QNetworkAccessManager>();
        m_network = m_ownedNetwork.get();
    }
    const QString imageFormats = supportedImageFormatsForLog();
    const QString pluginPaths = QCoreApplication::libraryPaths().join(QLatin1Char(';'));
    qCDebug(cardCatalogLog).noquote() << "Qt image decoders"
                                      << "formats=" + imageFormats << "pluginPaths=" + pluginPaths;
    if (!imageFormatSupported(QByteArrayLiteral("webp"))) {
        qCWarning(cardCatalogLog).noquote()
            << "Qt WebP image decoder is unavailable;"
            << "images.mtgch.com card art cannot be decoded"
            << "formats=" + imageFormats << "pluginPaths=" + pluginPaths;
    }
    QDir().mkpath(m_storageRoot);
    QString recoveryError;
    if (!catalogstorage::recoverDatabase(m_databasePath, &recoveryError))
        setLastError(recoveryError);
    QFile::remove(m_databasePath + QStringLiteral(".download"));
    loadCatalogMetadata();
    loadCachedCatalogRelease();
    loadResolutionCache();

    m_catalogInstaller =
        std::make_unique<CatalogInstaller>(m_storageRoot, m_databasePath, m_network);
    CardResolver::Callbacks resolverCallbacks;
    resolverCallbacks.lookupCatalog = [this](const CardRequest &request) {
        return lookupCatalog(request);
    };
    resolverCallbacks.metadataAvailable = [this](const CardRequest &request,
                                                 const CardRecord &record) {
        cacheResolvedMetadata(request, record);
    };
    resolverCallbacks.lookupLocalizedPrinting = [this](const CardRequest &request,
                                                       const CardRecord &identity) {
        return lookupLocalizedPrinting(request, identity);
    };
    resolverCallbacks.persistLocalizedPrintings = [this](const QJsonArray &printings) {
        persistLocalizedPrintings(printings);
    };
    resolverCallbacks.imagePathFor = [this](const CardRequest &request, const CardRecord &record) {
        return imagePathFor(request.name, record.imageUrl, request.language);
    };
    resolverCallbacks.setStatus = [this](const QString &status) { setStatus(status); };
    resolverCallbacks.completed = [this](const CardRequest &request, CardRecord record,
                                         bool success, bool cacheFailure,
                                         const QString &failureDetail) {
        completeCardRequest(request, std::move(record), success, cacheFailure, failureDetail);
    };
    resolverCallbacks.queueMoreWork = [this]() {
        if (!QCoreApplication::closingDown())
            QTimer::singleShot(0, this, &CardCatalog::scheduleResolutionWork);
    };
    m_cardResolver = std::make_unique<CardResolver>(m_network, resolverCallbacks);
    for (auto &resolver : m_parallelResolvers)
        resolver = std::make_unique<CardResolver>(*m_cardResolver, resolverCallbacks);
    connect(this, &CardCatalog::cardCacheFinished, this, &CardCatalog::handleLimitedArtCacheResult);

    CatalogInstaller *installer = m_catalogInstaller.get();
    installer->onBusyChanged = [this](bool busy) {
        if (m_catalogBusy == busy)
            return;
        if (busy) {
            clearLastError();
            // Drop the GUI connection so installDatabase can take the file lock.
            m_guiCatalog.reset();
            clearGuiQueryCaches();
        }
        m_catalogBusy = busy;
        if (busy) {
            ++m_tokenEnrichGeneration;
            search(m_lastSearchQuery, m_lastTypeFilter, m_lastSetFilter, m_lastLanguageFilter,
                   m_lastColorFilter, m_lastRarityFilter, m_lastLegalityFilter, m_lastManaFilter);
            if (m_tokenSearchRequested)
                searchTokens(m_lastTokenSearchQuery, m_lastTokenSearchKind);
        }
        emit busyChanged();
    };
    installer->onProgressChanged = [this](qreal progress) { setProgress(progress); };
    installer->onStatusChanged = [this](const QString &status) { setStatus(status); };
    installer->onValidationError = [this](const QString &error) { setLastError(error); };
    installer->onFailed = [this](const QString &error) {
        finishCatalogOperation({false, error, 0});
    };
    installer->onImportFinished = [this](const CatalogImportResult &result) {
        finishCatalogOperation(result);
    };

    m_artManager = std::make_unique<CardArtManager>(m_storageRoot, m_artCache.get());
    m_artCache->onSaveFinished = [this](bool success) {
        if (!success)
            setLastError(QStringLiteral("Could not save the card image cache."));
    };
    m_artManager->setOperationGuard([this]() { return artOperationsIdle() && artWritesAllowed(); });
    m_artManager->setInspectionGuard(
        [this]() { return !m_shuttingDown && !m_catalogBusy && artWritesAllowed(); });
    m_customArt->setOperationGuard([this]() {
        // Custom mappings and blobs do not share the ordinary cache's files.
        // Downloads, cache hydration and searches must not prevent a restore.
        // Only identity-database replacement and image-storage migration
        // conflict with a custom operation.
        return !m_shuttingDown && !m_catalogBusy && m_artStorage->writesAllowed();
    });
    m_artStorage->setOperationGuard(
        [this]() { return artOperationsIdle() && !m_customArt->busy() && !m_artManager->busy(); });
    m_artStorage->setIndexFlush([this](std::function<void(bool)> completion) {
        m_artIndexFlushing = true;
        m_artCache->saveAsync([this, completion = std::move(completion)](bool success) {
            m_artIndexFlushing = false;
            m_artCache->setWritable(m_artStorage->writesAllowed());
            completion(success);
        });
    });
    const auto storageStateChanged = [this]() {
        m_artStorageBusy = m_artStorage->busy();
        // The migration guard blocks new resolutions immediately, but a newer
        // index generation queued behind an older save must still reach disk.
        m_artCache->setWritable(m_artIndexFlushing || m_artStorage->writesAllowed());
        emit busyChanged();
        if (m_artStorage->writesAllowed() && !QCoreApplication::closingDown())
            QTimer::singleShot(0, this, &CardCatalog::scheduleResolutionWork);
    };
    connect(m_artStorage.get(), &CardArtStorage::busyChanged, this, storageStateChanged);
    connect(m_artStorage.get(), &CardArtStorage::restartRequiredChanged, this, storageStateChanged);
    connect(m_customArt.get(), &CustomCardArtStore::busyChanged, this, [this]() {
        m_customArtBusy = m_customArt->busy();
        emit busyChanged();
        if (!m_customArt->busy() && !QCoreApplication::closingDown())
            QTimer::singleShot(0, this, &CardCatalog::scheduleResolutionWork);
    });
    connect(m_customArt.get(), &CustomCardArtStore::bindingsChanged, this,
            [this](const QVariantList &bindings) {
                ++m_imageRevision;
                emit imageRevisionChanged();
                emit customArtContentsChanged(bindings);
            });
    connect(m_artManager.get(), &CardArtManager::busyChanged, this, [this]() {
        m_artCacheBusy = m_artManager && m_artManager->busy();
        emit busyChanged();
        if (!m_artCacheBusy && !QCoreApplication::closingDown())
            QTimer::singleShot(0, this, &CardCatalog::scheduleResolutionWork);
    });
    connect(m_artManager.get(), &CardArtManager::contentsChanged, this, [this]() {
        if (m_cardImageProvider)
            m_cardImageProvider->invalidateAll();
        ++m_imageRevision;
        emit imageRevisionChanged();
        emit artCacheContentsChanged();
    });
    connect(m_artManager.get(), &CardArtManager::repairDownloadsRequested, this,
            [this](const QVariantList &cards) {
                m_cardArtRepairAuditPending = true;
                retryCards(cards);
            });
}

CardCatalog::~CardCatalog()
{
    m_shuttingDown = true;
    ++m_faceExpansionSerial;
    m_faceExpansion.reset();
    ++m_limitedArtFaceExpansionSerial;
    m_limitedArtFaceExpansion.reset();
    m_artManager.reset();
    m_guiCatalog.reset();
    const auto directReplies = m_directImageJobs.keys();
    for (QNetworkReply *reply : directReplies)
        disconnect(reply, nullptr, this, nullptr);
    m_directImageJobs.clear();
    for (auto &resolver : m_parallelResolvers)
        resolver.reset();
    m_cardResolver.reset();
    m_catalogInstaller.reset();
    const auto replies =
        m_network ? m_network->findChildren<QNetworkReply *>() : QList<QNetworkReply *>{};
    for (QNetworkReply *reply : replies) {
        disconnect(reply, nullptr, this, nullptr);
        if (m_ownedNetwork)
            reply->abort();
    }
    if (m_artCache->dirty())
        saveResolutionCache();
}

CardArtManager *CardCatalog::artManager() const
{
    return m_artManager.get();
}

bool CardCatalog::installed() const
{
    return QFileInfo(m_databasePath).isFile() && QFileInfo(m_databasePath).size() > 0;
}

bool CardCatalog::reuseLocalCardArt() const
{
    return m_artCache->reuseLocalArt();
}

void CardCatalog::setLanguage(const QString &language)
{
    const QString normalized =
        language.toLower() == QStringLiteral("zh") ? QStringLiteral("zh") : QStringLiteral("en");
    if (normalized == m_language)
        return;
    m_language = normalized;
    setSearchPreviewCards({});
    ++m_tokenEnrichGeneration;
    clearGuiQueryCaches();
    restartCardFaceExpansion();
    restartLimitedArtFaceExpansion();
    ++m_imageRevision;
    emit imageRevisionChanged();
    emit languageChanged();
    if (m_tokenSearchRequested)
        searchTokens(m_lastTokenSearchQuery, m_lastTokenSearchKind);
    if (installed() && (!m_lastSearchQuery.isEmpty() || !m_lastTypeFilter.isEmpty() ||
                        !m_lastSetFilter.isEmpty() || !m_lastLanguageFilter.isEmpty() ||
                        !m_lastColorFilter.isEmpty() || !m_lastRarityFilter.isEmpty() ||
                        !m_lastLegalityFilter.isEmpty() || !m_lastManaFilter.isEmpty())) {
        search(m_lastSearchQuery, m_lastTypeFilter, m_lastSetFilter, m_lastLanguageFilter,
               m_lastColorFilter, m_lastRarityFilter, m_lastLegalityFilter, m_lastManaFilter);
    }
}

void CardCatalog::setCardArtProvider(const QString &provider)
{
    const QString lowered = provider.toLower();
    const QString normalized = lowered == QStringLiteral("mtgch") ||
                                       lowered == QStringLiteral("scryfall") ||
                                       lowered == QStringLiteral("parallel")
                                   ? lowered
                                   : QStringLiteral("auto");
    if (normalized == m_cardArtProvider)
        return;
    m_cardArtProvider = normalized;
    if (normalized == QStringLiteral("parallel")) {
        // Assign providers to work that was waiting in the serial resolver's
        // backlog, retaining explicit demand ahead of background downloads.
        m_cardQueue.append(m_fallbackQueue);
        m_fallbackQueue.clear();
        std::stable_partition(m_cardQueue.begin(), m_cardQueue.end(),
                              [](const CardRequest &request) { return request.highPriority; });
    }
    if (m_cardResolver) {
        const CardResolver::ArtProvider resolverProvider =
            normalized == QStringLiteral("mtgch")
                ? CardResolver::ArtProvider::Mtgch
                : (normalized == QStringLiteral("scryfall") ? CardResolver::ArtProvider::Scryfall
                                                            : CardResolver::ArtProvider::Auto);
        m_cardResolver->setPreferredProvider(resolverProvider);
    }
    emit cardArtProviderChanged();
    if (!QCoreApplication::closingDown())
        QTimer::singleShot(0, this, &CardCatalog::scheduleResolutionWork);
}

void CardCatalog::setReuseLocalCardArt(bool reuse)
{
    if (reuse == m_artCache->reuseLocalArt())
        return;
    m_artCache->setReuseLocalArt(reuse);
    emit reuseLocalCardArtChanged();
    ++m_imageRevision;
    emit imageRevisionChanged();
}

void CardCatalog::clearLastError()
{
    const bool hadOperation = !m_lastError.isEmpty();
    const bool hadCardSearch = !m_cardSearchError.isEmpty();
    const bool hadTokenSearch = !m_tokenSearchError.isEmpty();
    const bool hadPrintings = !m_printingsError.isEmpty();
    if (!hadOperation && !hadCardSearch && !hadTokenSearch && !hadPrintings)
        return;
    m_lastError.clear();
    m_cardSearchError.clear();
    m_tokenSearchError.clear();
    m_printingsError.clear();
    if (hadOperation)
        emit operationErrorChanged();
    if (hadCardSearch)
        emit cardSearchErrorChanged();
    if (hadTokenSearch)
        emit tokenSearchErrorChanged();
    if (hadPrintings)
        emit printingsErrorChanged();
    emit lastErrorChanged();
}

void CardCatalog::setCardImageProvider(CardImageProvider *provider)
{
    m_cardImageProvider = provider;
}

void CardCatalog::setResolving(bool resolving)
{
    if (m_resolving == resolving)
        return;
    m_resolving = resolving;
    emit busyChanged();
}

void CardCatalog::setProgress(qreal progress)
{
    progress = qBound<qreal>(0.0, progress, 1.0);
    if (qFuzzyCompare(m_progress, progress))
        return;
    m_progress = progress;
    emit progressChanged();
}

void CardCatalog::setStatus(const QString &status)
{
    if (m_status == status)
        return;
    m_status = status;
    emit statusChanged();
}

void CardCatalog::setLastError(const QString &error)
{
    if (m_lastError == error)
        return;
    const QString previous = lastError();
    m_lastError = error;
    emit operationErrorChanged();
    if (lastError() != previous)
        emit lastErrorChanged();
}

void CardCatalog::clearOperationError()
{
    setLastError({});
}

void CardCatalog::setCardSearchError(const QString &error)
{
    if (m_cardSearchError == error)
        return;
    const QString previous = lastError();
    m_cardSearchError = error;
    emit cardSearchErrorChanged();
    if (lastError() != previous)
        emit lastErrorChanged();
}

void CardCatalog::clearCardSearchError()
{
    setCardSearchError({});
}

void CardCatalog::setTokenSearchError(const QString &error)
{
    if (m_tokenSearchError == error)
        return;
    const QString previous = lastError();
    m_tokenSearchError = error;
    emit tokenSearchErrorChanged();
    if (lastError() != previous)
        emit lastErrorChanged();
}

void CardCatalog::clearTokenSearchError()
{
    setTokenSearchError({});
}

void CardCatalog::setPrintingsError(const QString &error)
{
    if (m_printingsError == error)
        return;
    const QString previous = lastError();
    m_printingsError = error;
    emit printingsErrorChanged();
    if (lastError() != previous)
        emit lastErrorChanged();
}

void CardCatalog::clearPrintingsError()
{
    setPrintingsError({});
}

} // namespace hexproof::client
