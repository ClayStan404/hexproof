// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "BackgroundTaskPools.h"
#include "CardCatalog.h"
#include "CardImageProvider.h"
#include "CatalogRepository.h"
#include "CatalogStorage.h"
#include <QFuture>
#include <QTimer>
#include <QtConcurrent>

namespace hexproof::client {

namespace {

QVariantList enrichCardMetadataBatch(const QString &databasePath, const QString &language,
                                     const QVariantList &cards)
{
    QVariantList enriched;
    const CatalogRepository repository(databasePath);
    const QVariantList cardsWithDeckMetadata = repository.enrichLimitedCards(cards);
    for (const QVariant &value : cardsWithDeckMetadata) {
        const QVariantMap requested = value.toMap();
        const QString name = requested.value(QStringLiteral("name")).toString().simplified();
        const QString setCode = requested.value(QStringLiteral("setCode")).toString().toUpper();
        const QString collectorNumber =
            requested.value(QStringLiteral("collectorNumber")).toString();
        if (name.isEmpty())
            continue;

        CardRecord record = repository.lookup(CatalogCardQuery{
            name,
            setCode,
            collectorNumber,
            language,
        });
        if (record.typeLine.isEmpty() && language != QStringLiteral("en")) {
            const CardRecord english = repository.lookup(CatalogCardQuery{
                name,
                setCode,
                collectorNumber,
                QStringLiteral("en"),
            });
            if (record.localizedName.isEmpty())
                record.localizedName = english.localizedName;
            record.typeLine = english.typeLine;
        }
        if (record.localizedName.isEmpty() && record.typeLine.isEmpty())
            continue;
        QVariantMap metadata{
            {QStringLiteral("requestedName"), name},
            {QStringLiteral("requestedSetCode"), setCode},
            {QStringLiteral("requestedCollectorNumber"), collectorNumber},
            {QStringLiteral("localizedName"), record.localizedName},
            {QStringLiteral("typeLine"), record.typeLine},
        };
        if (requested.contains(QStringLiteral("colors")))
            metadata.insert(QStringLiteral("colors"), requested.value(QStringLiteral("colors")));
        if (requested.contains(QStringLiteral("manaValue")))
            metadata.insert(QStringLiteral("manaValue"),
                            requested.value(QStringLiteral("manaValue")));
        enriched.append(metadata);
    }
    return enriched;
}

} // namespace

void CardCatalog::searchTokens(const QString &queryText)
{
    const QString text = queryText.simplified();
    m_lastTokenSearchQuery = text;
    ++m_tokenSearchGeneration;
    if (!tokenCatalogInstalled() || m_catalogBusy) {
        if (m_tokenSearching) {
            m_tokenSearching = false;
            emit tokenSearchingChanged();
            emit busyChanged();
        }
        if (!m_tokenSearchResults.isEmpty()) {
            m_tokenSearchResults.clear();
            emit tokenSearchResultsChanged();
        }
        return;
    }
    if (!m_tokenSearchResults.isEmpty()) {
        m_tokenSearchResults.clear();
        emit tokenSearchResultsChanged();
    }
    if (!m_tokenSearching) {
        m_tokenSearching = true;
        emit tokenSearchingChanged();
        emit busyChanged();
    }
    startLatestTokenSearch();
}

void CardCatalog::startLatestTokenSearch()
{
    if (m_tokenSearchWorkerRunning || !m_tokenSearching)
        return;

    m_tokenSearchWorkerRunning = true;
    const int generation = m_tokenSearchGeneration;
    auto *watcher = new QFutureWatcher<CatalogSearchResult>(this);
    connect(watcher, &QFutureWatcher<CatalogSearchResult>::finished, this,
            [this, watcher, generation]() {
                const CatalogSearchResult result = watcher->result();
                watcher->deleteLater();
                m_tokenSearchWorkerRunning = false;
                if (generation != m_tokenSearchGeneration) {
                    startLatestTokenSearch();
                    return;
                }
                m_tokenSearching = false;
                emit tokenSearchingChanged();
                emit busyChanged();
                if (!result.error.isEmpty())
                    setTokenSearchError(result.error);
                else
                    clearTokenSearchError();
                if (m_tokenSearchResults != result.cards) {
                    m_tokenSearchResults = result.cards;
                    emit tokenSearchResultsChanged();
                }
            });
    const QString databasePath = m_databasePath;
    const QString language = m_language;
    const QString text = m_lastTokenSearchQuery;
    watcher->setFuture(
        QtConcurrent::run(BackgroundTaskPools::catalogSearch(), [databasePath, text, language]() {
            return CatalogRepository(databasePath).searchTokens(text, language);
        }));
}

void CardCatalog::enrichCardMetadata(const QVariantList &cards)
{
    if (!installed() || m_catalogBusy || cards.isEmpty())
        return;

    for (const QVariant &card : cards) {
        const QVariantMap requested = card.toMap();
        const QString name = requested.value(QStringLiteral("name")).toString().simplified();
        if (name.isEmpty())
            continue;
        const QString key = m_language + QChar(0x1f) + name.toCaseFolded() + QChar(0x1f) +
                            requested.value(QStringLiteral("setCode")).toString().toUpper() +
                            QChar(0x1f) +
                            requested.value(QStringLiteral("collectorNumber")).toString();
        if (m_metadataEnrichmentQueuedKeys.contains(key))
            continue;
        m_metadataEnrichmentQueuedKeys.insert(key);
        m_metadataEnrichmentQueue.enqueue({card, m_language, key});
    }
    if (m_metadataEnrichmentQueue.isEmpty() || m_metadataEnrichmentRunning)
        return;

    QTimer::singleShot(0, this, &CardCatalog::processCardMetadataBatch);
}

void CardCatalog::processCardMetadataBatch()
{
    if (m_metadataEnrichmentRunning)
        return;
    if (!installed() || m_catalogBusy) {
        m_metadataEnrichmentQueue.clear();
        m_metadataEnrichmentQueuedKeys.clear();
        return;
    }
    while (!m_metadataEnrichmentQueue.isEmpty() &&
           m_metadataEnrichmentQueue.head().language != m_language) {
        m_metadataEnrichmentQueuedKeys.remove(m_metadataEnrichmentQueue.dequeue().key);
    }
    if (m_metadataEnrichmentQueue.isEmpty())
        return;

    constexpr int kMetadataBatchSize = 128;
    const QString language = m_metadataEnrichmentQueue.head().language;
    QVariantList batch;
    QStringList batchKeys;
    while (batch.size() < kMetadataBatchSize && !m_metadataEnrichmentQueue.isEmpty() &&
           m_metadataEnrichmentQueue.head().language == language) {
        const IncrementalCacheItem item = m_metadataEnrichmentQueue.dequeue();
        batch.append(item.card);
        batchKeys.append(item.key);
    }

    m_metadataEnrichmentRunning = true;
    const QString catalogVersion = m_catalogGeneratedAt;
    auto *watcher = new QFutureWatcher<QVariantList>(this);
    connect(watcher, &QFutureWatcher<QVariantList>::finished, this,
            [this, watcher, language, catalogVersion, batchKeys]() {
                const QVariantList enriched = watcher->result();
                watcher->deleteLater();
                for (const QString &key : batchKeys)
                    m_metadataEnrichmentQueuedKeys.remove(key);
                m_metadataEnrichmentRunning = false;
                if (language != m_language || catalogVersion != m_catalogGeneratedAt ||
                    m_catalogBusy) {
                    QTimer::singleShot(0, this, &CardCatalog::processCardMetadataBatch);
                    return;
                }
                if (!enriched.isEmpty())
                    emit cardMetadataAvailable(enriched);
                QTimer::singleShot(0, this, &CardCatalog::processCardMetadataBatch);
            });
    const QString databasePath = m_databasePath;
    watcher->setFuture(QtConcurrent::run(
        BackgroundTaskPools::catalogMaintenance(), [databasePath, language, batch]() {
            return enrichCardMetadataBatch(databasePath, language, batch);
        }));
}

void CardCatalog::enrichTokens(const QVariantList &tokens)
{
    if (!tokenCatalogInstalled() || tokens.isEmpty())
        return;
    // Discard superseded results the same way search() does. Without this a
    // late reply from an earlier deck or language can overwrite token metadata
    // with values that no longer match the request.
    const int generation = ++m_tokenEnrichGeneration;
    auto *watcher = new QFutureWatcher<QVariantList>(this);
    connect(watcher, &QFutureWatcher<QVariantList>::finished, this, [this, watcher, generation]() {
        const QVariantList enriched = watcher->result();
        watcher->deleteLater();
        if (generation != m_tokenEnrichGeneration)
            return;
        if (!enriched.isEmpty())
            emit tokenMetadataAvailable(enriched);
    });
    const QString databasePath = m_databasePath;
    const QString language = m_language;
    watcher->setFuture(QtConcurrent::run(BackgroundTaskPools::catalogMaintenance(), [databasePath,
                                                                                     language,
                                                                                     tokens]() {
        QVariantList enriched;
        QSet<QString> seen;
        const auto normalizedCollectorNumber = [](QString value) {
            while (value.size() > 1 && value.startsWith(QLatin1Char('0')))
                value.remove(0, 1);
            return value.toLower();
        };
        const CatalogRepository repository(databasePath);
        for (const QVariant &value : tokens) {
            const QVariantMap requested = value.toMap();
            const QString name = requested.value(QStringLiteral("name")).toString().simplified();
            const QString setCode = requested.value(QStringLiteral("setCode")).toString().toUpper();
            const QString collectorNumber =
                requested.value(QStringLiteral("collectorNumber")).toString();
            if (name.isEmpty() || setCode.isEmpty() || collectorNumber.isEmpty())
                continue;
            const QString key = name.toCaseFolded() + QChar(0x1f) + setCode + QChar(0x1f) +
                                normalizedCollectorNumber(collectorNumber);
            if (seen.contains(key))
                continue;
            seen.insert(key);
            const CatalogSearchResult result =
                repository.searchTokens(setCode + QStringLiteral(" #") + collectorNumber, language);
            QVariantMap selected;
            for (const QVariant &candidateValue : result.cards) {
                const QVariantMap candidate = candidateValue.toMap();
                if (candidate.value(QStringLiteral("setCode"))
                            .toString()
                            .compare(setCode, Qt::CaseInsensitive) == 0 &&
                    normalizedCollectorNumber(
                        candidate.value(QStringLiteral("collectorNumber")).toString()) ==
                        normalizedCollectorNumber(collectorNumber)) {
                    selected = candidate;
                    break;
                }
            }
            if (selected.isEmpty())
                continue;
            selected.insert(QStringLiteral("requestedName"), name);
            selected.insert(QStringLiteral("requestedSetCode"), setCode);
            selected.insert(QStringLiteral("requestedCollectorNumber"), collectorNumber);
            enriched.append(selected);
        }
        return enriched;
    }));
}

void CardCatalog::search(const QString &queryText, const QString &typeFilter,
                         const QString &setFilter, const QString &languageFilter,
                         const QString &colorFilter, const QString &rarityFilter,
                         const QString &legalityFilter)
{
    const QString text = queryText.simplified();
    m_lastSearchQuery = text;
    m_lastTypeFilter = typeFilter.simplified();
    m_lastSetFilter = setFilter.simplified().toUpper();
    m_lastLanguageFilter = languageFilter.toLower();
    m_lastColorFilter = colorFilter.simplified().toUpper();
    m_lastRarityFilter = rarityFilter.simplified().toLower();
    m_lastLegalityFilter = legalityFilter.simplified().toLower();
    if (m_catalogBusy)
        return;
    const bool hasFilter = !m_lastTypeFilter.isEmpty() || !m_lastSetFilter.isEmpty() ||
                           !m_lastLanguageFilter.isEmpty() || !m_lastColorFilter.isEmpty() ||
                           !m_lastRarityFilter.isEmpty() || !m_lastLegalityFilter.isEmpty();
    if (!installed() || (text.isEmpty() && !hasFilter)) {
        ++m_searchGeneration;
        if (m_searching) {
            m_searching = false;
            emit searchingChanged();
            emit busyChanged();
        }
        const QVariantList results;
        if (m_searchResults != results) {
            m_searchResults = results;
            emit searchResultsChanged();
        }
        return;
    }

    ++m_searchGeneration;
    if (!m_searchResults.isEmpty()) {
        m_searchResults.clear();
        emit searchResultsChanged();
    }
    if (!m_searching) {
        m_searching = true;
        emit searchingChanged();
        emit busyChanged();
    }
    startLatestCardSearch();
}

void CardCatalog::startLatestCardSearch()
{
    if (m_cardSearchWorkerRunning || !m_searching)
        return;

    m_cardSearchWorkerRunning = true;
    const int generation = m_searchGeneration;
    auto *watcher = new QFutureWatcher<CatalogSearchResult>(this);
    connect(watcher, &QFutureWatcher<CatalogSearchResult>::finished, this,
            [this, watcher, generation]() {
                const CatalogSearchResult result = watcher->result();
                watcher->deleteLater();
                m_cardSearchWorkerRunning = false;
                if (generation != m_searchGeneration) {
                    startLatestCardSearch();
                    return;
                }
                m_searching = false;
                emit searchingChanged();
                emit busyChanged();
                if (!result.error.isEmpty())
                    setCardSearchError(result.error);
                else
                    clearCardSearchError();
                if (m_searchResults != result.cards) {
                    m_searchResults = result.cards;
                    emit searchResultsChanged();
                }
            });
    const QString databasePath = m_databasePath;
    const QString language = m_language;
    const QString normalizedType = m_lastTypeFilter;
    const QString normalizedSet = m_lastSetFilter;
    const QString normalizedLanguage = m_lastLanguageFilter;
    const QString normalizedColor = m_lastColorFilter;
    const QString normalizedRarity = m_lastRarityFilter;
    const QString normalizedLegality = m_lastLegalityFilter;
    const QString text = m_lastSearchQuery;
    watcher->setFuture(QtConcurrent::run(
        BackgroundTaskPools::catalogSearch(),
        [databasePath, text, language, normalizedType, normalizedSet, normalizedLanguage,
         normalizedColor, normalizedRarity, normalizedLegality]() {
            return CatalogRepository(databasePath)
                .search(text, language, normalizedType, normalizedSet, normalizedLanguage,
                        normalizedColor, normalizedRarity, normalizedLegality);
        }));
}

} // namespace hexproof::client
