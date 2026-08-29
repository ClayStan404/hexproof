// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardArtCache.h"
#include "CardCatalog.h"
#include "CardCatalogCommon.h"
#include "CardImageProvider.h"
#include "CardResolver.h"
#include "CatalogStorage.h"
#include "deck/Deck.h"
#include <QTimer>

namespace hexproof::client {
using namespace catalog_internal;

namespace {
constexpr int kCachedHydrationIntervalMs = 16;
}

void CardCatalog::cacheCards(const QVariantList &cards)
{
    clearOperationError();
    enqueueCards(cards, m_language);
}

void CardCatalog::cacheCardsIncrementally(const QVariantList &cards)
{
    clearOperationError();
    for (const QVariant &card : cards) {
        const QVariantMap map = card.toMap();
        const QString name = map.value(QStringLiteral("name")).toString().simplified();
        if (name.isEmpty())
            continue;
        QString key =
            cacheKey(name, m_language, map.value(QStringLiteral("setCode")).toString().toUpper(),
                     map.value(QStringLiteral("collectorNumber")).toString());
        if (map.value(QStringLiteral("exactArt")).toBool())
            key += QStringLiteral("|exact");
        if (m_incrementalQueuedKeys.contains(key))
            continue;
        m_incrementalQueuedKeys.insert(key);
        m_incrementalCacheQueue.enqueue({card, m_language, key});
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
        const QString key =
            cacheKey(name, m_language, map.value(QStringLiteral("setCode")).toString().toUpper(),
                     map.value(QStringLiteral("collectorNumber")).toString());
        if (m_cachedHydrationQueuedKeys.contains(key))
            continue;
        m_cachedHydrationQueuedKeys.insert(key);
        m_cachedHydrationQueue.enqueue({card, m_language, key});
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

    bool createdAnyMapping = false;
    const IncrementalCacheItem item = m_cachedHydrationQueue.dequeue();
    m_cachedHydrationQueuedKeys.remove(item.key);
    if (item.language == m_language) {
        const QVariantMap map = item.card.toMap();
        CardRequest request{
            map.value(QStringLiteral("name")).toString().simplified(),
            map.value(QStringLiteral("setCode")).toString().toUpper(),
            map.value(QStringLiteral("collectorNumber")).toString(),
            item.language,
        };

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

    constexpr int kIncrementalCacheBatchSize = 4;
    const QString language = m_incrementalCacheQueue.head().language;
    QVariantList batch;
    while (batch.size() < kIncrementalCacheBatchSize && !m_incrementalCacheQueue.isEmpty() &&
           m_incrementalCacheQueue.head().language == language) {
        const IncrementalCacheItem item = m_incrementalCacheQueue.dequeue();
        m_incrementalQueuedKeys.remove(item.key);
        batch.append(item.card);
    }
    enqueueCards(batch, language);

    if (m_incrementalCacheQueue.isEmpty())
        return;
    m_incrementalCacheScheduled = true;
    QTimer::singleShot(8, this, &CardCatalog::processIncrementalCacheBatch);
}

void CardCatalog::retryCards(const QVariantList &cards)
{
    for (const QVariant &value : cards) {
        const QVariantMap map = value.toMap();
        const QString name = map.value(QStringLiteral("name")).toString().simplified();
        if (name.isEmpty())
            continue;
        const QString key =
            cacheKey(name, m_language, map.value(QStringLiteral("setCode")).toString().toUpper(),
                     map.value(QStringLiteral("collectorNumber")).toString());
        m_artCache->forgetFailure(key);
    }
    if (m_cardResolver)
        m_cardResolver->clearCooldowns();
    clearOperationError();
    enqueueCards(cards, m_language);
}

void CardCatalog::prioritizeCards(const QVariantList &cards)
{
    enqueueCards(cards, m_language);

    QList<CardRequest> prioritized;
    for (const QVariant &value : cards) {
        const QVariantMap map = value.toMap();
        const QString key =
            cacheKey(map.value(QStringLiteral("name")).toString().simplified(), m_language,
                     map.value(QStringLiteral("setCode")).toString().toUpper(),
                     map.value(QStringLiteral("collectorNumber")).toString());
        const auto takeMatchingRequest = [&key, this](QQueue<CardRequest> &queue,
                                                      QList<CardRequest> *matches) {
            for (auto it = queue.begin(); it != queue.end(); ++it) {
                if (cacheKey(it->name, it->language, it->setCode, it->collectorNumber) != key)
                    continue;
                matches->append(*it);
                queue.erase(it);
                return true;
            }
            return false;
        };
        if (!takeMatchingRequest(m_cardQueue, &prioritized))
            takeMatchingRequest(m_fallbackQueue, &prioritized);
    }
    for (auto it = prioritized.crbegin(); it != prioritized.crend(); ++it)
        m_cardQueue.prepend(*it);
    scheduleResolutionWork();
}

void CardCatalog::cacheToken(const QVariantMap &token)
{
    enqueueCards(QVariantList{token}, QStringLiteral("en"));
}

void CardCatalog::enqueueCards(const QVariantList &cards, const QString &language)
{
    for (const QVariant &value : cards) {
        const QVariantMap map = value.toMap();
        CardRequest request{
            map.value(QStringLiteral("name")).toString().simplified(),
            map.value(QStringLiteral("setCode")).toString().toUpper(),
            map.value(QStringLiteral("collectorNumber")).toString(),
            language,
        };
        request.exactArt = map.value(QStringLiteral("exactArt")).toBool();
        if (request.name.isEmpty())
            continue;
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
            emit cardCacheFinished(request.name, request.setCode, request.collectorNumber, true);
            continue;
        }
        if (m_artCache->failedRecently(key)) {
            emit cardCacheFinished(request.name, request.setCode, request.collectorNumber, false);
            continue;
        }
        m_queuedKeys.insert(pendingKey, true);
        m_cardQueue.enqueue(request);
        ++m_totalRequests;
    }
    scheduleResolutionWork();
}

CardCatalog::CardRecord CardCatalog::localCachedRecord(const CardRequest &request,
                                                       const QString &key, bool *createdMapping)
{
    *createdMapping = false;
    const CardRecord positive = m_artCache->exactRecord(key);
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
