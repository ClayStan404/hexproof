// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtCache.h"
#include "CardArtStorage.h"
#include "CardCatalog.h"
#include "CardCatalogCommon.h"
#include "CardImageProvider.h"
#include "CardResolver.h"
#include "CatalogStorage.h"
#include "deck/Deck.h"
#include <QTimer>

#include <algorithm>

namespace hexproof::client {
using namespace catalog_internal;

namespace {
constexpr int kCachedHydrationIntervalMs = 16;
}

void CardCatalog::cacheCards(const QVariantList &cards)
{
    clearOperationError();
    queueCardsIncrementally(cards, false);
}

void CardCatalog::cacheCardsIncrementally(const QVariantList &cards)
{
    clearOperationError();
    queueCardsIncrementally(cards, false);
}

void CardCatalog::queueCardsIncrementally(const QVariantList &cards, bool highPriority, bool retry)
{
    if (cards.isEmpty())
        return;
    if (!m_artStorage->writesAllowed()) {
        setLastError(
            m_artStorage->restartRequired()
                ? QStringLiteral("Restart Hexproof to use the new card-art directory.")
                : QStringLiteral("The card-art directory is unavailable or being migrated."));
        for (const QVariant &value : expandCardFaceRequests(cards)) {
            const QVariantMap map = value.toMap();
            CardRequest request{map.value(QStringLiteral("name")).toString(),
                                map.value(QStringLiteral("setCode")).toString().toUpper(),
                                map.value(QStringLiteral("collectorNumber")).toString(),
                                m_language};
            request.exactArt = map.value(QStringLiteral("exactArt")).toBool();
            emitCardCacheCompletion(request, false);
        }
        return;
    }
    const auto queueCard = [this, highPriority, retry](const QVariant &card) {
        const QVariantMap map = card.toMap();
        const QString name = map.value(QStringLiteral("name")).toString().simplified();
        if (name.isEmpty())
            return;
        const QString language = m_language;
        QString key =
            cacheKey(name, language, map.value(QStringLiteral("setCode")).toString().toUpper(),
                     map.value(QStringLiteral("collectorNumber")).toString());
        if (map.value(QStringLiteral("exactArt")).toBool())
            key += QStringLiteral("|exact");
        const bool alreadyQueued = m_incrementalQueuedKeys.contains(key);
        if (alreadyQueued && retry) {
            for (auto it = m_incrementalCacheQueue.begin(); it != m_incrementalCacheQueue.end();) {
                if (it->key == key)
                    it = m_incrementalCacheQueue.erase(it);
                else
                    ++it;
            }
        } else if (alreadyQueued && !highPriority) {
            return;
        }
        if (!alreadyQueued)
            m_incrementalQueuedKeys.insert(key);
        const IncrementalCacheItem item{card, language, key, retry, highPriority};
        if (highPriority)
            m_incrementalCacheQueue.prepend(item);
        else
            m_incrementalCacheQueue.enqueue(item);
    };
    if (highPriority) {
        for (auto it = cards.crbegin(); it != cards.crend(); ++it)
            queueCard(*it);
    } else {
        for (const QVariant &card : cards)
            queueCard(card);
    }
    if (m_incrementalCacheQueue.isEmpty() || m_incrementalCacheScheduled)
        return;

    m_incrementalCacheScheduled = true;
    QTimer::singleShot(0, this, &CardCatalog::processIncrementalCacheBatch);
}

void CardCatalog::hydrateCachedCards(const QVariantList &cards)
{
    for (const QVariant &card : cards) {
        const QVariantMap map = card.toMap();
        const QString name = map.value(QStringLiteral("name")).toString().simplified();
        if (name.isEmpty())
            continue;
        const QString language = m_language;
        const QString key =
            cacheKey(name, language, map.value(QStringLiteral("setCode")).toString().toUpper(),
                     map.value(QStringLiteral("collectorNumber")).toString());
        if (m_cachedHydrationQueuedKeys.contains(key))
            continue;
        m_cachedHydrationQueuedKeys.insert(key);
        m_cachedHydrationQueue.enqueue({card, language, key});
    }
    if (m_cachedHydrationQueue.isEmpty() || m_cachedHydrationScheduled)
        return;

    m_cachedHydrationScheduled = true;
    QTimer::singleShot(kCachedHydrationIntervalMs, this, &CardCatalog::processCachedHydrationBatch);
}

void CardCatalog::processCachedHydrationBatch()
{
    m_cachedHydrationScheduled = false;
    if (m_shuttingDown || QCoreApplication::closingDown()) {
        m_cachedHydrationQueue.clear();
        m_cachedHydrationQueuedKeys.clear();
        m_cachedHydrationCreatedMapping = false;
        return;
    }
    if (m_cachedHydrationQueue.isEmpty())
        return;
    if (!m_artStorage->writesAllowed()) {
        m_cachedHydrationQueue.clear();
        m_cachedHydrationQueuedKeys.clear();
        return;
    }
    if (m_customArtBusy || m_artCacheBusy) {
        m_cachedHydrationScheduled = true;
        QTimer::singleShot(50, this, &CardCatalog::processCachedHydrationBatch);
        return;
    }

    bool createdAnyMapping = false;
    const IncrementalCacheItem item = m_cachedHydrationQueue.dequeue();
    m_cachedHydrationQueuedKeys.remove(item.key);
    const QVariantMap map = item.card.toMap();
    if (item.language == m_language) {
        CardRequest request{
            map.value(QStringLiteral("name")).toString().simplified(),
            map.value(QStringLiteral("setCode")).toString().toUpper(),
            map.value(QStringLiteral("collectorNumber")).toString(),
            item.language,
        };
        request.supportCard = isSupportCardRequest(map);

        bool createdMapping = false;
        const CardRecord record = localCachedRecord(request, item.key, &createdMapping);
        if (!record.valid())
            createdMapping = false;
        else
            emitRecord(record);
        createdAnyMapping = createdMapping;
    }

    m_cachedHydrationCreatedMapping = m_cachedHydrationCreatedMapping || createdAnyMapping;
    if (m_cachedHydrationQueue.isEmpty()) {
        if (m_cachedHydrationCreatedMapping) {
            m_cachedHydrationCreatedMapping = false;
            ++m_imageRevision;
            emit imageRevisionChanged();
        }
        scheduleResolutionWork();
        return;
    }
    m_cachedHydrationScheduled = true;
    QTimer::singleShot(kCachedHydrationIntervalMs, this, &CardCatalog::processCachedHydrationBatch);
}

void CardCatalog::processIncrementalCacheBatch()
{
    m_incrementalCacheScheduled = false;
    if (m_shuttingDown || QCoreApplication::closingDown()) {
        m_incrementalCacheQueue.clear();
        m_incrementalQueuedKeys.clear();
        return;
    }
    if (m_incrementalCacheQueue.isEmpty())
        return;
    if (m_customArtBusy || m_artCacheBusy) {
        m_incrementalCacheScheduled = true;
        QTimer::singleShot(50, this, &CardCatalog::processIncrementalCacheBatch);
        return;
    }

    constexpr int kIncrementalCacheBatchSize = 4;
    QString language;
    bool highPriority = false;
    QList<IncrementalCacheItem> items;
    while (items.size() < kIncrementalCacheBatchSize && !m_incrementalCacheQueue.isEmpty()) {
        if (!m_incrementalQueuedKeys.contains(m_incrementalCacheQueue.head().key)) {
            m_incrementalCacheQueue.dequeue();
            continue;
        }
        if (language.isEmpty()) {
            language = m_incrementalCacheQueue.head().language;
            highPriority = m_incrementalCacheQueue.head().highPriority;
        }
        if (m_incrementalCacheQueue.head().language != language ||
            m_incrementalCacheQueue.head().highPriority != highPriority)
            break;
        const IncrementalCacheItem item = m_incrementalCacheQueue.dequeue();
        m_incrementalQueuedKeys.remove(item.key);
        items.append(item);
    }
    QVariantList batch;
    for (const IncrementalCacheItem &item : std::as_const(items)) {
        const QVariantList expanded = item.card.toMap().value(kCardFacesExpandedKey).toBool()
                                          ? QVariantList{item.card}
                                          : expandCardFaceRequests({item.card});
        if (item.retry) {
            for (const QVariant &value : expanded) {
                const QVariantMap map = value.toMap();
                const QString name = map.value(QStringLiteral("name")).toString().simplified();
                if (name.isEmpty())
                    continue;
                const QString key = cacheKey(
                    name, item.language, map.value(QStringLiteral("setCode")).toString().toUpper(),
                    map.value(QStringLiteral("collectorNumber")).toString());
                m_artCache->forgetFailure(key);
            }
        }
        for (const QVariant &value : expanded) {
            QVariantMap request = value.toMap();
            request.insert(QStringLiteral("_presentationArtOnly"),
                           item.highPriority && !item.retry);
            batch.append(request);
        }
    }
    enqueueCards(batch, language, highPriority);

    if (m_incrementalCacheQueue.isEmpty())
        return;
    m_incrementalCacheScheduled = true;
    QTimer::singleShot(8, this, &CardCatalog::processIncrementalCacheBatch);
}

void CardCatalog::retryCards(const QVariantList &cards)
{
    if (m_cardResolver)
        m_cardResolver->clearCooldowns();
    clearOperationError();
    queueCardsIncrementally(cards, true, true);
}

void CardCatalog::prioritizeCards(const QVariantList &cards)
{
    QList<CardRequest> prioritized;
    for (const QVariant &value : cards) {
        const QVariantMap map = value.toMap();
        CardRequest requested{
            map.value(QStringLiteral("name")).toString().simplified(),
            map.value(QStringLiteral("setCode")).toString().toUpper(),
            map.value(QStringLiteral("collectorNumber")).toString(),
            m_language,
        };
        requested.exactArt = map.value(QStringLiteral("exactArt")).toBool();
        requested.supportCard = isSupportCardRequest(map);
        requested.priorityName =
            map.value(QStringLiteral("priorityName"), requested.name).toString().simplified();
        const QString pendingKey = queuedRequestKey(requested);
        const bool explicitFace =
            !map.value(QStringLiteral("faceName")).toString().simplified().isEmpty();
        const auto matchesRequest = [&pendingKey, &requested, explicitFace,
                                     this](const CardRequest &candidate) {
            if (explicitFace)
                return queuedRequestKey(candidate) == pendingKey;
            return normalizedCardName(candidate.priorityName) ==
                       normalizedCardName(requested.priorityName) &&
                   candidate.setCode == requested.setCode &&
                   candidate.collectorNumber == requested.collectorNumber &&
                   candidate.language == requested.language &&
                   candidate.exactArt == requested.exactArt;
        };
        const auto takeMatchingRequests = [&matchesRequest](QQueue<CardRequest> &queue,
                                                            QList<CardRequest> *matches) {
            for (auto it = queue.begin(); it != queue.end();) {
                if (!matchesRequest(*it)) {
                    ++it;
                    continue;
                }
                it->highPriority = true;
                matches->append(*it);
                it = queue.erase(it);
            }
        };
        takeMatchingRequests(m_cardQueue, &prioritized);
        takeMatchingRequests(m_fallbackQueue, &prioritized);
    }
    for (auto it = prioritized.crbegin(); it != prioritized.crend(); ++it)
        m_cardQueue.prepend(*it);
    queueCardsIncrementally(cards, true);
}

void CardCatalog::cacheToken(const QVariantMap &token)
{
    QVariantMap request = token;
    request.insert(QStringLiteral("kind"),
                   normalizedDeckTokenKind(token.value(QStringLiteral("kind")).toString(),
                                           token.value(QStringLiteral("typeLine")).toString(),
                                           token.value(QStringLiteral("layout")).toString()));
    cacheCardsIncrementally({request});
}

void CardCatalog::enqueueCards(const QVariantList &cards, const QString &language,
                               bool highPriority)
{
    QList<CardRequest> requests;
    requests.reserve(cards.size());
    for (const QVariant &value : cards) {
        const QVariantMap map = value.toMap();
        CardRequest request{
            map.value(QStringLiteral("name")).toString().simplified(),
            map.value(QStringLiteral("setCode")).toString().toUpper(),
            map.value(QStringLiteral("collectorNumber")).toString(),
            language,
        };
        request.exactArt = map.value(QStringLiteral("exactArt")).toBool();
        request.supportCard = isSupportCardRequest(map);
        request.highPriority = highPriority;
        request.priorityName =
            map.value(QStringLiteral("priorityName"), request.name).toString().simplified();
        if (request.name.isEmpty())
            continue;
        if (map.value(QStringLiteral("_presentationArtOnly")).toBool() && !request.exactArt &&
            !customImagePath(request).isEmpty()) {
            emitCardCacheCompletion(request, true);
            continue;
        }
        requests.append(request);
    }
    enqueueRequests(requests);
}

void CardCatalog::enqueueRequests(const QList<CardRequest> &requests)
{
    for (const CardRequest &request : requests) {
        const QString key =
            cacheKey(request.name, request.language, request.setCode, request.collectorNumber);
        const QString pendingKey = queuedRequestKey(request);
        if (m_queuedKeys.contains(pendingKey))
            continue;
        bool createdMapping = false;
        const CardRecord local = localCachedRecord(request, key, &createdMapping);
        if (local.valid()) {
            emitRecord(local);
            if (createdMapping) {
                ++m_imageRevision;
                emit imageRevisionChanged();
            }
            emitCardCacheCompletion(request, true);
            continue;
        }
        if (m_artCache->failedRecently(key)) {
            emitCardCacheCompletion(request, false);
            continue;
        }
        m_queuedKeys.insert(pendingKey, true);
        if (request.highPriority) {
            const auto position =
                std::find_if(m_cardQueue.cbegin(), m_cardQueue.cend(),
                             [](const CardRequest &queued) { return !queued.highPriority; });
            m_cardQueue.insert(position, request);
        } else {
            m_cardQueue.enqueue(request);
        }
        ++m_totalRequests;
    }
    scheduleResolutionWork();
}

CardCatalog::CardRecord CardCatalog::localCachedRecord(const CardRequest &request,
                                                       const QString &key, bool *createdMapping)
{
    *createdMapping = false;
    const CardRecord positive = m_artCache->exactRecord(key);
    if (request.supportCard && request.language == QStringLiteral("zh") && positive.valid() &&
        !positive.localizedRulesChecked) {
        // Legacy token cache entries predate localized rules text. Keep the
        // image as a display fallback, but let the resolver refresh metadata.
        return {};
    }
    const bool positiveMatchesPolicy =
        positive.valid() && positive.resolutionVersion >= kCardResolutionVersion &&
        m_artCache->matchesRequestedFace(request, positive) &&
        (!positive.reusesLocalArt || request.allowsSubstituteArt(m_artCache->reuseLocalArt()));
    if (positiveMatchesPolicy && QFileInfo::exists(positive.imagePath))
        return positive;

    const CardRecord migrated = migrateLegacyCacheRecord(request, positive);
    if (migrated.valid()) {
        m_artCache->rememberSuccess(key, migrated);
        return migrated;
    }

    CardRecord resolved = cachedResolvedPrinting(request);
    if (resolved.valid()) {
        resolved.requestedName = request.name;
        m_artCache->rememberSuccess(key, resolved);
        *createdMapping = true;
        return resolved;
    }

    if (request.allowsSubstituteArt(m_artCache->reuseLocalArt())) {
        const CardRecord catalogIdentity = lookupCatalog(request);
        const CardRecord cachedArt = reusableLocalArt(request, catalogIdentity);
        if (cachedArt.valid()) {
            resolved = substituteArtRecord(request, catalogIdentity, cachedArt);
            m_artCache->rememberSuccess(key, resolved);
            *createdMapping = true;
            return resolved;
        }
    }
    return {};
}

void CardCatalog::loadCatalogMetadata()
{
    bool aliasCountStored = false;
    QFile file(m_catalogMetadataPath);
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonObject object = QJsonDocument::fromJson(file.readAll()).object();
        m_packageName = object.value(QStringLiteral("package")).toString();
        m_catalogGeneratedAt = object.value(QStringLiteral("generatedAt")).toString();
        m_indexVersion = object.value(QStringLiteral("indexVersion")).toInt();
        aliasCountStored = object.contains(QStringLiteral("aliasCount"));
        m_aliasCount = object.value(QStringLiteral("aliasCount")).toInt();
        m_tokenCount = object.value(QStringLiteral("tokenCount")).toInt();
        m_localizedPrintingCount = object.value(QStringLiteral("localizedPrintingCount")).toInt();
    }
    if (!installed() ||
        (!m_packageName.isEmpty() && !m_catalogGeneratedAt.isEmpty() &&
         m_indexVersion >= kCatalogIndexVersion && m_tokenCount > 0 && aliasCountStored))
        return;

    // A process can stop after the SQLite rename but before catalog.json is
    // committed. Recover the descriptive metadata from the indexed database.
    const QString connectionName = sqlConnectionName(QStringLiteral("hexproof-metadata-"));
    bool recovered = false;
    {
        QSqlDatabase database =
            QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        database.setDatabaseName(m_databasePath);
        if (database.open()) {
            QSqlQuery query(database);
            if (m_packageName.isEmpty() &&
                query.exec(
                    QStringLiteral("SELECT value FROM metadata WHERE key = 'package' LIMIT 1")) &&
                query.next()) {
                m_packageName = query.value(0).toString();
                recovered = !m_packageName.isEmpty();
            }
            if (m_catalogGeneratedAt.isEmpty() &&
                query.exec(QStringLiteral(
                    "SELECT value FROM metadata WHERE key = 'generated_at' LIMIT 1")) &&
                query.next()) {
                m_catalogGeneratedAt = query.value(0).toString();
                recovered = !m_catalogGeneratedAt.isEmpty();
            }
            if (m_indexVersion < kCatalogIndexVersion) {
                bool hasLayout = false;
                bool hasFullLegalityIndex = false;
                bool hasTokenPower = false;
                bool hasTokenToughness = false;
                bool hasTokenOracleText = false;
                bool hasLegalityStatuses = false;
                bool hasCardImageStatus = false;
                if (query.exec(QStringLiteral("PRAGMA table_info(cards)"))) {
                    while (query.next()) {
                        const QString column = query.value(1).toString();
                        if (column == QStringLiteral("layout"))
                            hasLayout = true;
                        else if (column == QStringLiteral("legal_formats"))
                            hasFullLegalityIndex = true;
                        else if (column == QStringLiteral("power"))
                            hasTokenPower = true;
                        else if (column == QStringLiteral("toughness"))
                            hasTokenToughness = true;
                        else if (column == QStringLiteral("oracle_text"))
                            hasTokenOracleText = true;
                        else if (column == QStringLiteral("legality_statuses"))
                            hasLegalityStatuses = true;
                        else if (column == QStringLiteral("image_status"))
                            hasCardImageStatus = true;
                    }
                }
                if (hasFullLegalityIndex) {
                    if (query.exec(
                            QStringLiteral("SELECT 1 FROM sqlite_master WHERE type = 'table' "
                                           "AND name = 'localized_printings' LIMIT 1")) &&
                        query.next()) {
                        bool hasLocalizedLayout = false;
                        bool hasLocalizedImageStatus = false;
                        if (query.exec(QStringLiteral(
                                "SELECT name FROM pragma_table_info('localized_printings') "
                                "WHERE name IN ('layout', 'image_status')"))) {
                            while (query.next()) {
                                const QString column = query.value(0).toString();
                                if (column == QStringLiteral("layout"))
                                    hasLocalizedLayout = true;
                                else if (column == QStringLiteral("image_status"))
                                    hasLocalizedImageStatus = true;
                            }
                        }
                        if (hasLocalizedLayout) {
                            if (hasTokenPower && hasTokenToughness && hasTokenOracleText) {
                                if (hasLegalityStatuses) {
                                    m_indexVersion = hasCardImageStatus && hasLocalizedImageStatus
                                                         ? kCatalogIndexVersion
                                                         : kLegalityCatalogIndexVersion;
                                } else {
                                    m_indexVersion = 7;
                                }
                            } else {
                                m_indexVersion = kEnhancedCatalogIndexVersion;
                            }
                        } else {
                            m_indexVersion = 5;
                        }
                    } else {
                        m_indexVersion = 4;
                    }
                    recovered = true;
                } else if (hasLayout) {
                    m_indexVersion = 3;
                    recovered = true;
                } else if (query.exec(
                               QStringLiteral("SELECT 1 FROM sqlite_master WHERE type = 'table' "
                                              "AND name = 'card_aliases' LIMIT 1")) &&
                           query.next()) {
                    m_indexVersion = 2;
                    recovered = true;
                }
            }
            if (m_indexVersion >= 3 &&
                query.exec(QStringLiteral(
                    "SELECT value FROM metadata WHERE key = 'token_count' LIMIT 1")) &&
                query.next()) {
                m_tokenCount = query.value(0).toInt();
                recovered = true;
            }
            if (m_indexVersion >= 3 && m_tokenCount == 0 &&
                query.exec(QStringLiteral("SELECT count(*) FROM cards WHERE lang = 'en' AND "
                                          "layout IN ('token', 'double_faced_token', 'emblem')")) &&
                query.next()) {
                // Older catalogs counted only single-faced tokens. An emblem-only
                // database is usable without rebuilding or rewriting its SQLite file.
                m_tokenCount = query.value(0).toInt();
                recovered = true;
            }
            if (!aliasCountStored &&
                query.exec(QStringLiteral(
                    "SELECT value FROM metadata WHERE key = 'alias_count' LIMIT 1")) &&
                query.next()) {
                m_aliasCount = query.value(0).toInt();
                recovered = true;
            }
            if (m_indexVersion >= 5 &&
                query.exec(QStringLiteral("SELECT value FROM metadata WHERE key = "
                                          "'localized_printing_count' LIMIT 1")) &&
                query.next()) {
                m_localizedPrintingCount = query.value(0).toInt();
                recovered = true;
            }
            database.close();
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    if (m_catalogGeneratedAt.isEmpty()) {
        m_catalogGeneratedAt =
            QFileInfo(m_databasePath).lastModified().toUTC().toString(Qt::ISODate);
        recovered = !m_catalogGeneratedAt.isEmpty();
    }
    if (recovered && !saveCatalogMetadata())
        setLastError(QStringLiteral("Catalog metadata was recovered, but could not be saved."));
}

bool CardCatalog::saveCatalogMetadata()
{
    const QJsonObject object{
        {QStringLiteral("package"), m_packageName},
        {QStringLiteral("generatedAt"), m_catalogGeneratedAt},
        {QStringLiteral("indexVersion"), m_indexVersion},
        {QStringLiteral("aliasCount"), m_aliasCount},
        {QStringLiteral("tokenCount"), m_tokenCount},
        {QStringLiteral("localizedPrintingCount"), m_localizedPrintingCount},
        {QStringLiteral("updatedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)},
    };
    return catalogstorage::writeJson(m_catalogMetadataPath, object);
}

void CardCatalog::loadResolutionCache()
{
    m_artCache->load();
}

bool CardCatalog::saveResolutionCache()
{
    return m_artCache->save();
}

QString CardCatalog::cacheKey(const QString &name, const QString &language, const QString &setCode,
                              const QString &collectorNumber) const
{
    return m_artCache->key(name, language, setCode, collectorNumber);
}

QString CardCatalog::queuedRequestKey(const CardRequest &request) const
{
    QString key =
        cacheKey(request.name, request.language, request.setCode, request.collectorNumber);
    if (request.exactArt)
        key += QStringLiteral("|exact-art");
    return key;
}

CardCatalog::CardRecord CardCatalog::cachedResolvedPrinting(const CardRequest &request) const
{
    return m_artCache->resolvedPrinting(request);
}

CardCatalog::CardRecord CardCatalog::reusableLocalArt(const CardRequest &request,
                                                      const CardRecord &catalogIdentity) const
{
    return m_artCache->reusableArt(request, catalogIdentity);
}

CardCatalog::CardRecord CardCatalog::substituteArtRecord(const CardRequest &request,
                                                         const CardRecord &catalogIdentity,
                                                         const CardRecord &cachedArt) const
{
    return m_artCache->substituteRecord(request, catalogIdentity, cachedArt);
}

QString CardCatalog::imagePathFor(const QString &name, const QString &imageUrl,
                                  const QString &language) const
{
    return m_artCache->imagePath(name, imageUrl, language);
}

} // namespace hexproof::client
