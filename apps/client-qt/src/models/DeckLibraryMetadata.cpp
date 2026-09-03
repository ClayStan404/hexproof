// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "DeckLibraryModel.h"

#include "services/BackgroundTaskPools.h"

#include "deck/DeckEditor.h"
#include "models/DeckLibraryQueries.h"

#include <QDateTime>
#include <QtConcurrent>

#include <algorithm>
#include <utility>

namespace hexproof::client {

namespace {

constexpr int kMaxBackgroundSaveAttempts = 3;
constexpr int kBackgroundSaveRetryDelayMs = 100;

QString metadataIdentity(const QString &name, const QString &setCode,
                         const QString &collectorNumber)
{
    return normalizedCardName(name) + QChar(0x1f) + setCode.toUpper() + QChar(0x1f) +
           collectorNumber;
}

void appendCatalogMetadataRequests(const Deck &deck, bool refreshExisting, QVariantList *requests,
                                   QSet<QString> *seen)
{
    const QVector<DeckCard> *const zones[] = {&deck.mainboard, &deck.sideboard, &deck.consider};
    for (const QVector<DeckCard> *zone : zones) {
        for (const DeckCard &card : *zone) {
            if (!refreshExisting && !card.typeLine.isEmpty() && card.manaValue >= 0.0)
                continue;
            const QString key = metadataIdentity(card.name, card.setCode, card.collectorNumber);
            if (normalizedCardName(card.name).isEmpty() || seen->contains(key))
                continue;
            seen->insert(key);
            requests->append(QVariantMap{
                {QStringLiteral("name"), card.name},
                {QStringLiteral("setCode"), card.setCode},
                {QStringLiteral("collectorNumber"), card.collectorNumber},
            });
        }
    }
}

} // namespace

void DeckLibraryModel::requestCatalogMetadata(const Deck &deck, bool refreshExisting)
{
    QVariantList requests;
    QSet<QString> seen;
    appendCatalogMetadataRequests(deck, refreshExisting, &requests, &seen);
    if (!requests.isEmpty())
        emit cardsNeedMetadata(requests);
}

void DeckLibraryModel::hydrateCatalogMetadata(bool refreshExisting)
{
    const QVariantList missingArt = DeckLibraryQueries::cacheRequestsForLibrary(m_decks);
    if (!missingArt.isEmpty())
        emit cardsNeedCachedArtLookup(missingArt);

    QVariantList requests;
    QSet<QString> seen;
    for (const Deck &deck : std::as_const(m_decks))
        appendCatalogMetadataRequests(deck, refreshExisting, &requests, &seen);
    if (!requests.isEmpty())
        emit cardsNeedMetadata(requests);
}

void DeckLibraryModel::refreshMissingArt()
{
    emit cardsNeedCaching(DeckLibraryQueries::cacheRequestsForLibrary(m_decks, true));
}

void DeckLibraryModel::cacheCurrentDeckArt()
{
    const Deck *deck = currentDeck();
    if (!deck)
        return;
    emit cardsNeedCaching(DeckLibraryQueries::cacheRequestsForDeck(*deck, true));
}

void DeckLibraryModel::refreshTokenMetadata()
{
    QVariantList requests;
    QSet<QString> seen;
    for (const Deck &deck : std::as_const(m_decks)) {
        for (const DeckToken &token : deck.tokens) {
            if (!token.power.isEmpty() || !token.toughness.isEmpty() ||
                !token.oracleText.isEmpty()) {
                continue;
            }
            const QString key = normalizedCardName(token.name) + QChar(0x1f) +
                                token.setCode.toUpper() + QChar(0x1f) + token.collectorNumber;
            if (seen.contains(key))
                continue;
            seen.insert(key);
            requests.append(QVariantMap{
                {QStringLiteral("name"), token.name},
                {QStringLiteral("setCode"), token.setCode},
                {QStringLiteral("collectorNumber"), token.collectorNumber},
            });
        }
    }
    if (!requests.isEmpty())
        emit tokensNeedMetadata(requests);
}

void DeckLibraryModel::refreshCardArt()
{
    emit cardsNeedCaching(DeckLibraryQueries::cacheRequestsForLibrary(m_decks, true));
}

void DeckLibraryModel::refreshCachedCardArt()
{
    emit cardsNeedCachedArtLookup(DeckLibraryQueries::cacheRequestsForLibrary(m_decks, true));
}

QVariantList DeckLibraryModel::cardArtAuditRequests() const
{
    return DeckLibraryQueries::cacheRequestsForLibrary(m_decks, true);
}

void DeckLibraryModel::retryMissingArt()
{
    emit cardsNeedRetry(DeckLibraryQueries::cacheRequestsForLibrary(m_decks));
}

void DeckLibraryModel::applyCardMetadata(const QString &requestedName, const QString &localizedName,
                                         const QString &typeLine, const QString &imagePath,
                                         const QString &setCode, const QString &collectorNumber)
{
    const QString normalizedName = normalizedCardName(requestedName);
    if (normalizedName.isEmpty())
        return;
    QSet<QString> changedDeckIds;
    const QSet<int> deckIndexes = m_cardDeckIndex.value(normalizedName);
    for (const int deckIndex : deckIndexes) {
        if (deckIndex < 0 || deckIndex >= m_decks.size())
            continue;
        Deck &deck = m_decks[deckIndex];
        if (DeckEditor::applyCardMetadata(deck, requestedName, localizedName, typeLine, imagePath,
                                          setCode, collectorNumber)) {
            changedDeckIds.insert(deck.id);
        }
    }
    if (changedDeckIds.isEmpty())
        return;
    m_metadataChangedDeckIds.unite(changedDeckIds);
    scheduleMetadataCommit();
}

void DeckLibraryModel::applyCatalogMetadata(const QVariantList &cards)
{
    QHash<QString, QVariantMap> metadataByIdentity;
    for (const QVariant &value : cards) {
        const QVariantMap metadata = value.toMap();
        const QString name = metadata.value(QStringLiteral("requestedName")).toString();
        if (normalizedCardName(name).isEmpty())
            continue;
        metadataByIdentity.insert(
            metadataIdentity(name, metadata.value(QStringLiteral("requestedSetCode")).toString(),
                             metadata.value(QStringLiteral("requestedCollectorNumber")).toString()),
            metadata);
    }
    if (metadataByIdentity.isEmpty())
        return;

    QSet<QString> changedDeckIds;
    for (Deck &deck : m_decks) {
        bool deckChanged = false;
        QVector<DeckCard> *const zones[] = {&deck.mainboard, &deck.sideboard, &deck.consider};
        for (QVector<DeckCard> *zone : zones) {
            for (DeckCard &card : *zone) {
                const auto metadata = metadataByIdentity.constFind(
                    metadataIdentity(card.name, card.setCode, card.collectorNumber));
                if (metadata == metadataByIdentity.cend())
                    continue;
                const QString localizedName =
                    metadata->value(QStringLiteral("localizedName")).toString();
                const QString typeLine = metadata->value(QStringLiteral("typeLine")).toString();
                const QString colors = metadata->value(QStringLiteral("colors")).toString();
                const double manaValue =
                    metadata->value(QStringLiteral("manaValue"), -1.0).toDouble();
                if (!localizedName.isEmpty() && card.localizedName != localizedName) {
                    card.localizedName = localizedName;
                    deckChanged = true;
                }
                if (!typeLine.isEmpty() && card.typeLine != typeLine) {
                    card.typeLine = typeLine;
                    deckChanged = true;
                }
                if (metadata->contains(QStringLiteral("colors")) && card.colors != colors) {
                    card.colors = colors;
                    deckChanged = true;
                }
                if (manaValue >= 0.0 && card.manaValue != manaValue) {
                    card.manaValue = manaValue;
                    deckChanged = true;
                }
            }
        }
        if (!deckChanged)
            continue;
        deck.updatedAt = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
        changedDeckIds.insert(deck.id);
    }
    if (changedDeckIds.isEmpty())
        return;
    m_metadataChangedDeckIds.unite(changedDeckIds);
    scheduleMetadataCommit();
    notifyDecksChanged(changedDeckIds, true);
}

void DeckLibraryModel::applyTokenMetadata(const QVariantList &tokens)
{
    QHash<QString, QVariantMap> metadataByIdentity;
    for (const QVariant &value : tokens) {
        const QVariantMap metadata = value.toMap();
        const QString name =
            metadata.value(QStringLiteral("requestedName")).toString().simplified();
        const QString setCode =
            metadata.value(QStringLiteral("requestedSetCode")).toString().toUpper();
        const QString collectorNumber =
            metadata.value(QStringLiteral("requestedCollectorNumber")).toString();
        if (name.isEmpty() || setCode.isEmpty() || collectorNumber.isEmpty())
            continue;
        metadataByIdentity.insert(normalizedCardName(name) + QChar(0x1f) + setCode + QChar(0x1f) +
                                      collectorNumber,
                                  metadata);
    }
    if (metadataByIdentity.isEmpty())
        return;

    QSet<QString> changedDeckIds;
    for (Deck &deck : m_decks) {
        bool deckChanged = false;
        for (DeckToken &token : deck.tokens) {
            const QString identity = normalizedCardName(token.name) + QChar(0x1f) +
                                     token.setCode.toUpper() + QChar(0x1f) + token.collectorNumber;
            const auto metadata = metadataByIdentity.constFind(identity);
            if (metadata == metadataByIdentity.cend())
                continue;
            const auto fill = [&deckChanged](QString *target, const QString &source) {
                if (source.isEmpty() || *target == source)
                    return;
                *target = source;
                deckChanged = true;
            };
            fill(&token.power, metadata->value(QStringLiteral("power")).toString());
            fill(&token.toughness, metadata->value(QStringLiteral("toughness")).toString());
            fill(&token.oracleText, metadata->value(QStringLiteral("oracleText")).toString());
            if (token.typeLine.isEmpty())
                fill(&token.typeLine, metadata->value(QStringLiteral("typeLine")).toString());
            if (token.localizedName.isEmpty()) {
                const QString displayName =
                    metadata->value(QStringLiteral("displayName")).toString();
                if (displayName != token.name)
                    fill(&token.localizedName, displayName);
            }
        }
        if (deckChanged)
            changedDeckIds.insert(deck.id);
    }
    if (changedDeckIds.isEmpty())
        return;
    m_metadataChangedDeckIds.unite(changedDeckIds);
    scheduleMetadataCommit();
}

void DeckLibraryModel::scheduleMetadataCommit()
{
    ++m_persistenceGeneration;
    m_backgroundSaveAttempts = 0;
    m_metadataCommitPending = true;
    m_metadataCommitTimer.setInterval(kMetadataCommitDelayMs);
    m_metadataCommitTimer.start();
}

void DeckLibraryModel::flushMetadataCommit()
{
    if (!m_metadataCommitPending)
        return;
    startBackgroundSave();
}

void DeckLibraryModel::startBackgroundSave()
{
    if (m_backgroundSaveRunning || m_persistedGeneration >= m_persistenceGeneration)
        return;
    const quint64 generation = m_persistenceGeneration;
    const QVector<Deck> snapshot = m_decks;
    const SaveDecksFunction saveDecks = m_saveDecks;
    m_backgroundSaveDeckIds = std::exchange(m_metadataChangedDeckIds, {});
    m_backgroundSaveRunning = true;
    ++m_backgroundSaveAttempts;
    m_backgroundSaveWatcher.setFuture(QtConcurrent::run(
        BackgroundTaskPools::deckPersistence(), [saveDecks, snapshot, generation]() {
            BackgroundSaveResult result;
            result.generation = generation;
            result.success = saveDecks(snapshot, generation, &result.error);
            return result;
        }));
}

void DeckLibraryModel::finishBackgroundSave()
{
    const BackgroundSaveResult result = m_backgroundSaveWatcher.result();
    m_backgroundSaveRunning = false;
    if (result.generation <= m_persistedGeneration) {
        m_backgroundSaveDeckIds.clear();
        m_metadataCommitPending = m_persistedGeneration < m_persistenceGeneration;
        if (m_metadataCommitPending)
            startBackgroundSave();
        return;
    }
    if (!result.success) {
        m_metadataChangedDeckIds.unite(m_backgroundSaveDeckIds);
        m_backgroundSaveDeckIds.clear();
        m_metadataCommitPending = true;
        if (m_backgroundSaveAttempts < kMaxBackgroundSaveAttempts) {
            setLastError(result.error);
            m_metadataCommitTimer.setInterval(kBackgroundSaveRetryDelayMs *
                                              m_backgroundSaveAttempts);
            m_metadataCommitTimer.start();
        } else {
            const QString pending =
                QStringLiteral(" Deck changes remain pending until the next edit or exit.");
            setLastError(result.error.isEmpty() ? pending.trimmed() : result.error + pending);
        }
        return;
    }
    m_backgroundSaveAttempts = 0;
    notifyDecksChanged(std::exchange(m_backgroundSaveDeckIds, {}), true);
    m_persistedGeneration = std::max(m_persistedGeneration, result.generation);
    m_metadataCommitPending = m_persistedGeneration < m_persistenceGeneration;
    if (m_metadataCommitPending)
        startBackgroundSave();
}

} // namespace hexproof::client
