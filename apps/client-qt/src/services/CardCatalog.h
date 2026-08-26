// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "CatalogTypes.h"

#include <QCache>
#include <QHash>
#include <QJsonArray>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QObject>
#include <QQueue>
#include <QSet>
#include <QUrl>
#include <QVariantList>

#include <memory>

class QNetworkReply;

namespace hexproof::client {

class CardArtCache;
class CardImageProvider;
class CardResolver;
class CatalogInstaller;
class CatalogRepository;

class CardCatalog : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool installed READ installed NOTIFY catalogChanged)
    Q_PROPERTY(bool enhancedIndexInstalled READ enhancedIndexInstalled NOTIFY catalogChanged)
    Q_PROPERTY(bool chineseIndexInstalled READ chineseIndexInstalled NOTIFY catalogChanged)
    Q_PROPERTY(bool tokenCatalogInstalled READ tokenCatalogInstalled NOTIFY catalogChanged)
    Q_PROPERTY(QString packageName READ packageName NOTIFY catalogChanged)
    Q_PROPERTY(
        QString installedCatalogVersion READ installedCatalogVersion NOTIFY catalogVersionChanged)
    Q_PROPERTY(int installedCatalogSchemaVersion READ installedCatalogSchemaVersion NOTIFY
                   catalogVersionChanged)
    Q_PROPERTY(QString latestCatalogVersion READ latestCatalogVersion NOTIFY catalogVersionChanged)
    Q_PROPERTY(
        int latestCatalogSchemaVersion READ latestCatalogSchemaVersion NOTIFY catalogVersionChanged)
    Q_PROPERTY(bool latestCatalogKnown READ latestCatalogKnown NOTIFY catalogVersionChanged)
    Q_PROPERTY(
        bool latestCatalogCompatible READ latestCatalogCompatible NOTIFY catalogVersionChanged)
    Q_PROPERTY(bool catalogUpdateAvailable READ catalogUpdateAvailable NOTIFY catalogVersionChanged)
    Q_PROPERTY(bool checkingCatalogVersion READ checkingCatalogVersion NOTIFY catalogVersionChanged)
    Q_PROPERTY(QString catalogVersionError READ catalogVersionError NOTIFY catalogVersionChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(qreal progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QString operationError READ operationError NOTIFY operationErrorChanged)
    Q_PROPERTY(QString cardSearchError READ cardSearchError NOTIFY cardSearchErrorChanged)
    Q_PROPERTY(QString tokenSearchError READ tokenSearchError NOTIFY tokenSearchErrorChanged)
    Q_PROPERTY(QString printingsError READ printingsError NOTIFY printingsErrorChanged)
    Q_PROPERTY(QVariantList searchResults READ searchResults NOTIFY searchResultsChanged)
    Q_PROPERTY(bool searching READ searching NOTIFY searchingChanged)
    Q_PROPERTY(
        QVariantList tokenSearchResults READ tokenSearchResults NOTIFY tokenSearchResultsChanged)
    Q_PROPERTY(bool tokenSearching READ tokenSearching NOTIFY tokenSearchingChanged)
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)
    Q_PROPERTY(QString cardArtProvider READ cardArtProvider WRITE setCardArtProvider NOTIFY
                   cardArtProviderChanged)
    Q_PROPERTY(bool reuseLocalCardArt READ reuseLocalCardArt WRITE setReuseLocalCardArt NOTIFY
                   reuseLocalCardArtChanged)
    Q_PROPERTY(int imageRevision READ imageRevision NOTIFY imageRevisionChanged)

  public:
    using CardRecord = hexproof::client::CardRecord;
    using ImportResult = CatalogImportResult;

    explicit CardCatalog(QObject *parent = nullptr);
    explicit CardCatalog(const QString &storageRoot, QObject *parent = nullptr);
    CardCatalog(const QString &storageRoot, QNetworkAccessManager *network,
                QObject *parent = nullptr);
    ~CardCatalog() override;

    bool installed() const;
    bool enhancedIndexInstalled() const
    {
        return installed() && m_indexVersion >= 6 &&
               m_packageName == QStringLiteral("default_cards");
    }
    bool chineseIndexInstalled() const
    {
        return installed() && m_aliasCount > 0;
    }
    bool tokenCatalogInstalled() const
    {
        return installed() && m_indexVersion >= 3 && m_tokenCount > 0;
    }
    QString packageName() const
    {
        return m_packageName;
    }
    QString installedCatalogVersion() const
    {
        return m_catalogGeneratedAt;
    }
    int installedCatalogSchemaVersion() const
    {
        return m_indexVersion;
    }
    QString latestCatalogVersion() const
    {
        return m_latestCatalogGeneratedAt;
    }
    int latestCatalogSchemaVersion() const
    {
        return m_latestCatalogSchemaVersion;
    }
    bool latestCatalogKnown() const
    {
        return !m_latestCatalogGeneratedAt.isEmpty() && m_latestCatalogSchemaVersion > 0;
    }
    bool latestCatalogCompatible() const;
    bool catalogUpdateAvailable() const;
    bool checkingCatalogVersion() const
    {
        return m_checkingCatalogVersion;
    }
    QString catalogVersionError() const
    {
        return m_catalogVersionError;
    }
    bool busy() const
    {
        return m_catalogBusy || m_resolving || m_searching || m_tokenSearching;
    }
    qreal progress() const
    {
        return m_progress;
    }
    QString status() const
    {
        return m_status;
    }
    QString lastError() const
    {
        if (!m_lastError.isEmpty())
            return m_lastError;
        if (!m_cardSearchError.isEmpty())
            return m_cardSearchError;
        if (!m_tokenSearchError.isEmpty())
            return m_tokenSearchError;
        return m_printingsError;
    }
    QString operationError() const
    {
        return m_lastError;
    }
    QString cardSearchError() const
    {
        return m_cardSearchError;
    }
    QString tokenSearchError() const
    {
        return m_tokenSearchError;
    }
    QString printingsError() const
    {
        return m_printingsError;
    }
    QVariantList searchResults() const
    {
        return m_searchResults;
    }
    bool searching() const
    {
        return m_searching;
    }
    QVariantList tokenSearchResults() const
    {
        return m_tokenSearchResults;
    }
    bool tokenSearching() const
    {
        return m_tokenSearching;
    }
    QString language() const
    {
        return m_language;
    }
    QString cardArtProvider() const
    {
        return m_cardArtProvider;
    }
    bool reuseLocalCardArt() const;
    int imageRevision() const
    {
        return m_imageRevision;
    }

    void setLanguage(const QString &language);
    void setCardArtProvider(const QString &provider);
    void setReuseLocalCardArt(bool reuse);

    Q_INVOKABLE void downloadCatalog(const QString &packageType);
    Q_INVOKABLE void checkCatalogUpdate();
    Q_INVOKABLE void checkCatalogUpdateIfDue();
    Q_INVOKABLE void importCatalogFile(const QUrl &fileUrl, const QString &packageType);
    Q_INVOKABLE void search(const QString &query, const QString &typeFilter = {},
                            const QString &setFilter = {}, const QString &languageFilter = {},
                            const QString &colorFilter = {}, const QString &rarityFilter = {},
                            const QString &legalityFilter = {});
    Q_INVOKABLE QVariantList printings(const QString &name);
    Q_INVOKABLE QVariantList cardFaces(const QString &name, const QString &setCode,
                                       const QString &collectorNumber);
    Q_INVOKABLE QString imageSource(const QString &name, const QString &setCode,
                                    const QString &collectorNumber) const;
    Q_INVOKABLE QString printingImageSource(const QString &name, const QString &setCode,
                                            const QString &collectorNumber) const;
    Q_INVOKABLE QString tableImageSource(const QString &name, const QString &setCode,
                                         const QString &collectorNumber) const;
    Q_INVOKABLE QString cardTypeLine(const QString &name, const QString &setCode,
                                     const QString &collectorNumber) const;
    Q_INVOKABLE bool matchesCardQuery(const QString &name, const QString &setCode,
                                      const QString &collectorNumber, const QString &query) const;
    Q_INVOKABLE void clearLastError();
    Q_INVOKABLE void downloadTokenCatalog();
    Q_INVOKABLE void searchTokens(const QString &query);
    Q_INVOKABLE QString tokenImageSource(const QString &name, const QString &setCode,
                                         const QString &collectorNumber) const;
    Q_INVOKABLE void cacheToken(const QVariantMap &token);
    Q_INVOKABLE void prioritizeCards(const QVariantList &cards);
    Q_INVOKABLE QVariantList limitedProducts() const;
    Q_INVOKABLE QVariantList limitedSets() const;
    Q_INVOKABLE QVariantMap limitedProduct(const QString &productId) const;
    Q_INVOKABLE QVariantList simulateLimitedPacks(const QVariantMap &product, int packCount) const;

    static CardRecord parseCardObject(const QJsonObject &object, const QString &language,
                                      const QString &requestedName = {});
    static ImportResult importBulkFile(const QString &jsonPath, const QString &databasePath,
                                       const QString &packageType,
                                       const QString &chineseArchivePath = {},
                                       const QString &localizedPrintingsPath = {});
    static ImportResult importDatabaseFile(const QString &sourcePath, const QString &databasePath);
    void setCardImageProvider(CardImageProvider *provider);

  public slots:
    Q_INVOKABLE void cacheCards(const QVariantList &cards);
    Q_INVOKABLE void cacheCardsIncrementally(const QVariantList &cards);
    void hydrateCachedCards(const QVariantList &cards);
    Q_INVOKABLE void retryCards(const QVariantList &cards);
    void enrichCardMetadata(const QVariantList &cards);
    Q_INVOKABLE void enrichTokens(const QVariantList &tokens);

  signals:
    void catalogChanged();
    void catalogVersionChanged();
    void busyChanged();
    void progressChanged();
    void statusChanged();
    void lastErrorChanged();
    void operationErrorChanged();
    void cardSearchErrorChanged();
    void tokenSearchErrorChanged();
    void printingsErrorChanged();
    void searchResultsChanged();
    void searchingChanged();
    void tokenSearchResultsChanged();
    void tokenSearchingChanged();
    void languageChanged();
    void cardArtProviderChanged();
    void reuseLocalCardArtChanged();
    void imageRevisionChanged();
    void cardAvailable(const QString &requestedName, const QString &localizedName,
                       const QString &typeLine, const QString &imagePath, const QString &setCode,
                       const QString &collectorNumber);
    void cardCacheFinished(const QString &requestedName, const QString &setCode,
                           const QString &collectorNumber, bool success);
    void cardMetadataAvailable(const QVariantList &cards);
    void tokenMetadataAvailable(const QVariantList &tokens);

  private:
    using CardRequest = hexproof::client::CardRequest;

    struct SearchResult
    {
        QVariantList cards;
        QString error;
    };

    struct DirectImageJob
    {
        CardRequest request;
        CardRecord record;
        int retries = 0;
    };

    struct IncrementalCacheItem
    {
        QVariant card;
        QString language;
        QString key;
    };

    void loadCatalogMetadata();
    void loadCachedCatalogRelease();
    bool saveCatalogMetadata();
    void loadResolutionCache();
    bool saveResolutionCache();
    QString cacheKey(const QString &name, const QString &language, const QString &setCode = {},
                     const QString &collectorNumber = {}) const;
    QString queuedRequestKey(const CardRequest &request) const;
    CardRecord cachedResolvedPrinting(const CardRequest &request) const;
    CardRecord localCachedRecord(const CardRequest &request, const QString &key,
                                 bool *createdMapping);
    CardRecord reusableLocalArt(const CardRequest &request,
                                const CardRecord &catalogIdentity) const;
    CardRecord substituteArtRecord(const CardRequest &request, const CardRecord &catalogIdentity,
                                   const CardRecord &cachedArt) const;
    QString resolvedImagePath(const CardRequest &request) const;
    QString imagePathFor(const QString &name, const QString &imageUrl,
                         const QString &language) const;
    CardRecord lookupCatalog(const CardRequest &request) const;
    CardRecord lookupLocalizedPrinting(const CardRequest &request,
                                       const CardRecord &catalogIdentity) const;
    CardRecord migrateLegacyCacheRecord(const CardRequest &request, const CardRecord &record) const;
    CatalogRepository &guiCatalog() const;
    void persistLocalizedPrintings(const QJsonArray &printings);
    void clearGuiQueryCaches();
    void scheduleResolutionWork();
    void finishResolutionIfIdle();
    bool startDirectImageDownload(const DirectImageJob &job);
    void handleDirectImageReply(QNetworkReply *reply);
    void completeCardRequest(const CardRequest &request, CardRecord record, bool success,
                             bool cacheFailure = false, const QString &failureDetail = {});
    void emitRecord(const CardRecord &record);
    void setResolving(bool resolving);
    void setProgress(qreal progress);
    void setStatus(const QString &status);
    void setLastError(const QString &error);
    void clearOperationError();
    void setCardSearchError(const QString &error);
    void clearCardSearchError();
    void setTokenSearchError(const QString &error);
    void clearTokenSearchError();
    void setPrintingsError(const QString &error);
    void clearPrintingsError();
    static SearchResult searchDatabase(const QString &databasePath, const QString &query,
                                       const QString &language, const QString &typeFilter,
                                       const QString &setFilter, const QString &languageFilter,
                                       const QString &colorFilter, const QString &rarityFilter,
                                       const QString &legalityFilter);
    static SearchResult searchTokenDatabase(const QString &databasePath, const QString &query);
    void enqueueCards(const QVariantList &cards, const QString &language);
    void processCachedHydrationBatch();
    void processIncrementalCacheBatch();
    void processCardMetadataBatch();
    void startLatestCardSearch();
    void startLatestTokenSearch();
    void finishCatalogOperation(const ImportResult &result);
    QString m_storageRoot;
    QString m_databasePath;
    QString m_catalogMetadataPath;
    QString m_packageName;
    QString m_catalogGeneratedAt;
    QString m_latestCatalogGeneratedAt;
    QString m_catalogVersionError;
    QString m_language = QStringLiteral("en");
    QString m_cardArtProvider = QStringLiteral("scryfall");
    QString m_status;
    QString m_lastError;
    QString m_cardSearchError;
    QString m_tokenSearchError;
    QString m_printingsError;
    QString m_lastSearchQuery;
    QString m_lastTokenSearchQuery;
    QString m_lastTypeFilter;
    QString m_lastSetFilter;
    QString m_lastLanguageFilter;
    QString m_lastColorFilter;
    QString m_lastRarityFilter;
    QString m_lastLegalityFilter;
    QVariantList m_searchResults;
    QVariantList m_tokenSearchResults;
    qreal m_progress = 0.0;
    bool m_catalogBusy = false;
    bool m_shuttingDown = false;
    bool m_resolving = false;
    bool m_searching = false;
    bool m_tokenSearching = false;
    bool m_cardSearchWorkerRunning = false;
    bool m_tokenSearchWorkerRunning = false;
    int m_totalRequests = 0;
    int m_completedRequests = 0;
    int m_searchGeneration = 0;
    int m_tokenSearchGeneration = 0;
    int m_tokenEnrichGeneration = 0;
    int m_indexVersion = 0;
    int m_latestCatalogSchemaVersion = 0;
    int m_aliasCount = 0;
    int m_tokenCount = 0;
    int m_localizedPrintingCount = 0;
    int m_imageRevision = 0;

    std::unique_ptr<QNetworkAccessManager> m_ownedNetwork;
    QNetworkAccessManager *m_network = nullptr;
    std::unique_ptr<CardArtCache> m_artCache;
    std::unique_ptr<CatalogInstaller> m_catalogInstaller;
    std::unique_ptr<CardResolver> m_cardResolver;
    mutable std::unique_ptr<CatalogRepository> m_guiCatalog;
    mutable QHash<QString, QVariantList> m_printingsCache;
    mutable QHash<QString, QVariantList> m_cardFacesCache;
    mutable QHash<QString, CardRecord> m_lookupCache;
    CardImageProvider *m_cardImageProvider = nullptr;
    QQueue<CardRequest> m_cardQueue;
    QQueue<CardRequest> m_fallbackQueue;
    QQueue<IncrementalCacheItem> m_cachedHydrationQueue;
    QSet<QString> m_cachedHydrationQueuedKeys;
    QQueue<IncrementalCacheItem> m_incrementalCacheQueue;
    QSet<QString> m_incrementalQueuedKeys;
    QQueue<IncrementalCacheItem> m_metadataEnrichmentQueue;
    QSet<QString> m_metadataEnrichmentQueuedKeys;
    QHash<QNetworkReply *, DirectImageJob> m_directImageJobs;
    QHash<QString, bool> m_queuedKeys;
    mutable QCache<QString, QString> m_cardQueryTextCache{4096};
    bool m_cachedHydrationCreatedMapping = false;
    bool m_cachedHydrationScheduled = false;
    bool m_incrementalCacheScheduled = false;
    bool m_metadataEnrichmentRunning = false;
    bool m_checkingCatalogVersion = false;
};

} // namespace hexproof::client
