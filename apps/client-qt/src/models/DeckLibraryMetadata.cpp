// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "DeckLibraryModel.h"

#include "services/BackgroundTaskPools.h"

#include "deck/DeckEditor.h"
#include "models/DeckLibraryQueries.h"

#include <QDateTime>
#include <QElapsedTimer>
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

QString displayPrintingKey(const QString &setCode, const QString &collectorNumber)
{
    return setCode.trimmed().toCaseFolded() + QChar(0x1f) +
           collectorNumber.trimmed().toCaseFolded();
}

bool matchesDisplayAliases(const DeckCard &card, const QSet<QString> &aliases)
{
    const QString name = normalizedCardName(card.name);
    QStringList faces = name.split(QStringLiteral(" // "), Qt::SkipEmptyParts);
    if (card.setCode.isEmpty() || card.collectorNumber.isEmpty()) {
        if (aliases.contains(name))
            return true;
    } else if (!faces.isEmpty()) {
        // Exact front printings must not invalidate all editions of that card.
        // A combined name can nevertheless refer to a separate meld result
        // whose printing differs from the component stored in the deck.
        faces.removeFirst();
    }
    return std::any_of(faces.cbegin(), faces.cend(),
                       [&aliases](const QString &face) { return aliases.contains(face); });
}

void appendCatalogMetadataRequests(const Deck &deck, bool refreshExisting, QVariantList *requests,
                                   QSet<QString> *seen)
{
    const QVector<DeckCard> *const zones[] = {&deck.mainboard, &deck.sideboard, &deck.consider};
    for (const QVector<DeckCard> *zone : zones) {
        for (const DeckCard &card : *zone) {
            if (!refreshExisting && !card.typeLine.isEmpty() && card.manaValue >= 0.0 &&
                !card.rarity.isEmpty() && !card.cardColors.isNull() && !card.manaCost.isNull() &&
                !card.setCode.isEmpty() && !card.collectorNumber.isEmpty())
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

void mergeResolvedPrintings(QVector<DeckCard> &cards)
{
    QVector<DeckCard> merged;
    QHash<QString, qsizetype> rows;
    for (const DeckCard &card : std::as_const(cards)) {
        const QString key = metadataIdentity(card.name, card.setCode, card.collectorNumber);
        const auto found = rows.constFind(key);
        if (found == rows.cend()) {
            rows.insert(key, merged.size());
            merged.append(card);
        } else {
            DeckCard &existing = merged[*found];
            existing.count += card.count;
            if (existing.imagePath.isEmpty())
                existing.imagePath = card.imagePath;
            existing.displayImagePathResolved = false;
        }
    }
    cards = std::move(merged);
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
            if (!token.typeLine.isEmpty() &&
                (!token.power.isEmpty() || !token.toughness.isEmpty() ||
                 !token.oracleText.isEmpty())) {
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
    refreshDisplayedCardArt();
    emit cardsNeedCachedArtLookup(DeckLibraryQueries::cacheRequestsForLibrary(m_decks, true));
}

void DeckLibraryModel::refreshCustomCardArt(const QVariantList &bindings)
{
    if (!m_imagePathResolver)
        return;
    bool refreshAll = bindings.isEmpty();
    QSet<QString> printings;
    QSet<QString> aliases;
    for (const QVariant &value : bindings) {
        const QVariantMap binding = value.toMap();
        const QString set = binding.value(QStringLiteral("setCode")).toString();
        const QString collector = binding.value(QStringLiteral("collectorNumber")).toString();
        if (binding.value(QStringLiteral("scope")).toString() != QStringLiteral("printing") ||
            set.trimmed().isEmpty() || collector.trimmed().isEmpty()) {
            // Deck entries need not carry Oracle IDs or canonical English
            // names, so a card-wide change cannot safely be narrowed by name.
            refreshAll = true;
            break;
        }
        printings.insert(displayPrintingKey(set, collector));
        for (const QString &field : {QStringLiteral("name"), QStringLiteral("faceName")}) {
            const QString name = normalizedCardName(binding.value(field).toString());
            if (!name.isEmpty()) {
                aliases.insert(name);
                const QStringList faces = name.split(QStringLiteral(" // "), Qt::SkipEmptyParts);
                for (const QString &face : faces)
                    aliases.insert(face);
            }
        }
    }
    for (Deck &deck : m_decks) {
        for (QVector<DeckCard> *zone : {&deck.mainboard, &deck.sideboard, &deck.consider}) {
            for (qsizetype cardIndex = 0; cardIndex < zone->size(); ++cardIndex) {
                const DeckCard &card = zone->at(cardIndex);
                if (refreshAll ||
                    printings.contains(displayPrintingKey(card.setCode, card.collectorNumber)) ||
                    matchesDisplayAliases(card, aliases))
                    (*zone)[cardIndex].displayImagePathPending = true;
            }
        }
    }
    // Preserve unresolved startup/previous-refresh rows as well as this change.
    // Neither official metadata, persistence nor the download queue is touched.
    queuePendingDisplayPaths();
}

void DeckLibraryModel::queuePendingDisplayPaths()
{
    const quint64 generation = ++m_displayPathGeneration;
    QSet<QString> names;
    m_pendingDisplayPathNames.clear();
    const auto appendDeck = [this, &names](const Deck &deck) {
        for (const QVector<DeckCard> *zone : {&deck.mainboard, &deck.sideboard, &deck.consider}) {
            for (const DeckCard &card : *zone) {
                if (card.displayImagePathPending) {
                    const QString name = normalizedCardName(card.name);
                    if (!names.contains(name)) {
                        names.insert(name);
                        m_pendingDisplayPathNames.append(name);
                    }
                }
            }
        }
    };
    if (const Deck *deck = currentDeck())
        appendDeck(*deck);
    m_pendingDisplayPathPriorityNameCount = m_pendingDisplayPathNames.size();
    for (const Deck &deck : std::as_const(m_decks)) {
        if (deck.id != m_currentDeckId)
            appendDeck(deck);
    }
    m_pendingDisplayPathNameIndex = 0;
    m_pendingDisplayPathLocationIndex = 0;
    m_pendingDisplayPathLocationRevision = m_cardLocationRevision;
    m_pendingDisplayPathPriorityDeckId = m_currentDeckId;
    m_resolvingPriorityDisplayPaths = !m_pendingDisplayPathPriorityDeckId.isEmpty();
    if (!m_pendingDisplayPathNames.isEmpty())
        QTimer::singleShot(16, this,
                           [this, generation]() { resolveDeferredDisplayPaths(generation); });
}

void DeckLibraryModel::setImagePathResolver(std::function<QString(const DeckCard &)> resolver,
                                            bool deferInitialRefresh)
{
    m_imagePathResolver = std::move(resolver);
    if (!deferInitialRefresh || !m_imagePathResolver) {
        ++m_displayPathGeneration;
        m_pendingDisplayPathNames.clear();
        m_pendingDisplayPathNameIndex = 0;
        m_imageCounts.clear();
        resolveDisplayPaths({}, true);
        QSet<QString> ids;
        for (const Deck &deck : std::as_const(m_decks))
            ids.insert(deck.id);
        notifyDecksChanged(ids, true);
        return;
    }
    QSet<QString> ids;
    for (Deck &deck : m_decks) {
        ids.insert(deck.id);
        for (QVector<DeckCard> *zone : {&deck.mainboard, &deck.sideboard, &deck.consider}) {
            for (DeckCard &card : *zone) {
                // Never expose a persisted path as ready before checking the
                // configured storage and current custom-art bindings.
                card.displayImagePath.clear();
                card.displayImagePathResolved = true;
                card.displayImagePathPending = true;
            }
        }
    }
    queuePendingDisplayPaths();
    notifyDecksChanged(ids, true);
}

void DeckLibraryModel::resolveDeferredDisplayPaths(quint64 generation)
{
    if (generation != m_displayPathGeneration || !m_imagePathResolver)
        return;
    QElapsedTimer budget;
    budget.start();
    int resolved = 0;
    int scanned = 0;
    QSet<QString> changedIds;
    if (m_pendingDisplayPathPriorityDeckId != m_currentDeckId) {
        queuePendingDisplayPaths();
        return;
    }
    if (m_pendingDisplayPathLocationRevision != m_cardLocationRevision) {
        m_pendingDisplayPathLocationRevision = m_cardLocationRevision;
        m_pendingDisplayPathLocationIndex = 0;
    }
    while (true) {
        if (resolved >= 32 || scanned >= 256 || (scanned > 0 && budget.elapsed() >= 8))
            break;
        const qsizetype nameLimit = m_resolvingPriorityDisplayPaths
                                        ? m_pendingDisplayPathPriorityNameCount
                                        : m_pendingDisplayPathNames.size();
        if (m_pendingDisplayPathNameIndex >= nameLimit) {
            if (!m_resolvingPriorityDisplayPaths)
                break;
            m_resolvingPriorityDisplayPaths = false;
            m_pendingDisplayPathNameIndex = 0;
            m_pendingDisplayPathLocationIndex = 0;
            continue;
        }
        const QString name = m_pendingDisplayPathNames.at(m_pendingDisplayPathNameIndex);
        // Resolve live locations again after every yield. Deleting, importing,
        // moving or merging rows may have invalidated every previous index.
        const QVector<CardLocation> locations = m_cardLocationsByName.value(name);
        if (m_pendingDisplayPathLocationIndex >= locations.size()) {
            ++m_pendingDisplayPathNameIndex;
            m_pendingDisplayPathLocationIndex = 0;
            ++scanned;
            continue;
        }
        const CardLocation location = locations.at(m_pendingDisplayPathLocationIndex++);
        ++scanned;
        const DeckCard *pendingCard = std::as_const(*this).cardAt(location);
        if (!pendingCard || !pendingCard->displayImagePathPending ||
            (m_resolvingPriorityDisplayPaths &&
             m_decks.at(location.deckIndex).id != m_pendingDisplayPathPriorityDeckId))
            continue;
        const DeckCard requestedCard = *pendingCard;
        const QString path = m_imagePathResolver(requestedCard);
        ++resolved;
        if (generation != m_displayPathGeneration)
            return;
        if (m_pendingDisplayPathLocationRevision != m_cardLocationRevision) {
            // A resolver callback may change the live deck structure. Do not
            // publish into a row whose index now identifies a different card.
            m_pendingDisplayPathLocationRevision = m_cardLocationRevision;
            m_pendingDisplayPathLocationIndex = 0;
            continue;
        }
        DeckCard *card = cardAt(location);
        if (!card)
            continue;
        const bool changed = !card->displayImagePathResolved || card->displayImagePath != path;
        card->displayImagePath = path;
        card->displayImagePathResolved = true;
        card->displayImagePathPending = false;
        if (changed)
            changedIds.insert(m_decks.at(location.deckIndex).id);
    }
    if (!changedIds.isEmpty())
        notifyDecksChanged(changedIds, true);
    if (generation != m_displayPathGeneration)
        return;
    if (m_resolvingPriorityDisplayPaths ||
        m_pendingDisplayPathNameIndex < m_pendingDisplayPathNames.size()) {
        QTimer::singleShot(16, this,
                           [this, generation]() { resolveDeferredDisplayPaths(generation); });
    } else {
        m_pendingDisplayPathNames.clear();
        m_pendingDisplayPathNameIndex = 0;
        m_pendingDisplayPathLocationIndex = 0;
    }
}

void DeckLibraryModel::resolveDisplayPaths(const QSet<QString> &deckIds, bool force)
{
    if (!m_imagePathResolver && !force)
        return;
    for (Deck &deck : m_decks) {
        if (!deckIds.isEmpty() && !deckIds.contains(deck.id))
            continue;
        for (QVector<DeckCard> *zone : {&deck.mainboard, &deck.sideboard, &deck.consider}) {
            for (qsizetype cardIndex = 0; cardIndex < zone->size(); ++cardIndex) {
                if (!force && zone->at(cardIndex).displayImagePathResolved)
                    continue;
                DeckCard &card = (*zone)[cardIndex];
                card.displayImagePath = m_imagePathResolver ? m_imagePathResolver(card) : QString{};
                card.displayImagePathResolved = bool(m_imagePathResolver);
                card.displayImagePathPending = false;
            }
        }
    }
}

void DeckLibraryModel::refreshDisplayedCardArt()
{
    if (!m_imagePathResolver) {
        setImagePathResolver({});
        return;
    }
    m_imageCounts.clear();
    QSet<QString> ids;
    for (Deck &deck : m_decks) {
        ids.insert(deck.id);
        for (QVector<DeckCard> *zone : {&deck.mainboard, &deck.sideboard, &deck.consider}) {
            for (DeckCard &card : *zone) {
                // Retain the displayed art while rechecking storage. Marking it
                // resolved keeps notification delivery from doing this entire
                // local-cache/catalog scan synchronously.
                card.displayImagePathResolved = true;
                card.displayImagePathPending = true;
            }
        }
    }
    queuePendingDisplayPaths();
    notifyDecksChanged(ids, true);
}

QVariantList DeckLibraryModel::cardArtAuditRequests() const
{
    return DeckLibraryQueries::cacheRequestsForLibrary(m_decks, true);
}

QVariantList DeckLibraryModel::cardArtExportRequests(const QString &id) const
{
    // Use the requested deck, independently of the open editor or library filter.
    // A stale or empty ID must never widen an export to the complete library.
    for (const Deck &deck : m_decks) {
        if (deck.id == id)
            return DeckLibraryQueries::cacheRequestsForDeck(deck, true);
    }
    return {};
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
    QSet<int> changedDeckIndexes;
    QSet<QString> recoveredArtDeckIds;
    const QVector<CardLocation> locations = m_cardLocationsByName.value(normalizedName);
    for (const CardLocation &location : locations) {
        DeckCard *card = cardAt(location);
        if (!card)
            continue;
        const QString previousPath = card->imagePath;
        const QString previousSet = card->setCode;
        const QString previousCollector = card->collectorNumber;
        const bool metadataChanged = DeckEditor::applyCardMetadata(
            *card, requestedName, localizedName, typeLine, imagePath, setCode, collectorNumber);
        const bool printingMatches = setCode.isEmpty() || collectorNumber.isEmpty() ||
                                     (card->setCode.compare(setCode, Qt::CaseInsensitive) == 0 &&
                                      card->collectorNumber == collectorNumber);
        // A file lost between launches can be downloaded back to its saved
        // path. No persisted string changes, but the earlier missing-art
        // resolution must be retried for this printing. Existing valid display
        // paths remain cached during repeated availability notifications.
        const bool recoveredArt = printingMatches && !imagePath.isEmpty() &&
                                  card->imagePath == imagePath && card->displayImagePathResolved &&
                                  card->displayImagePath.isEmpty();
        if (metadataChanged) {
            if (card->imagePath != previousPath || card->setCode != previousSet ||
                card->collectorNumber != previousCollector || recoveredArt) {
                card->displayImagePathResolved = false;
            }
            changedDeckIndexes.insert(location.deckIndex);
        } else if (recoveredArt) {
            card->displayImagePathResolved = false;
            recoveredArtDeckIds.insert(m_decks.at(location.deckIndex).id);
        }
    }
    QSet<QString> changedDeckIds;
    const QString updatedAt = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
    for (const int deckIndex : changedDeckIndexes) {
        Deck &deck = m_decks[deckIndex];
        deck.updatedAt = updatedAt;
        changedDeckIds.insert(deck.id);
    }
    if (!changedDeckIds.isEmpty()) {
        m_metadataChangedDeckIds.unite(changedDeckIds);
        scheduleMetadataCommit();
    }
    // File availability is presentation state; it must not wait for or enqueue
    // another deck-library write when its metadata already matches the disk.
    notifyDecksChanged(recoveredArtDeckIds, true);
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

    QSet<int> changedDeckIndexes;
    QSet<int> printingChangedDeckIndexes;
    QSet<int> validationChangedDeckIndexes;
    for (auto metadata = metadataByIdentity.cbegin(); metadata != metadataByIdentity.cend();
         ++metadata) {
        const QString requestedName = metadata->value(QStringLiteral("requestedName")).toString();
        const QVector<CardLocation> locations =
            m_cardLocationsByName.value(normalizedCardName(requestedName));
        for (const CardLocation &location : locations) {
            DeckCard *card = cardAt(location);
            if (!card || metadataIdentity(card->name, card->setCode, card->collectorNumber) !=
                             metadata.key()) {
                continue;
            }
            bool cardChanged = false;
            const QString resolvedSet = metadata->value(QStringLiteral("setCode")).toString();
            const QString resolvedCollector =
                metadata->value(QStringLiteral("collectorNumber")).toString();
            // Match the original request above before adopting a default printing.
            // A late name-only result must not replace a user's newer selection.
            if ((card->setCode.isEmpty() || card->collectorNumber.isEmpty()) &&
                !resolvedSet.isEmpty() && !resolvedCollector.isEmpty() &&
                (card->setCode.isEmpty() ||
                 card->setCode.compare(resolvedSet, Qt::CaseInsensitive) == 0) &&
                (card->collectorNumber.isEmpty() || card->collectorNumber == resolvedCollector)) {
                card->setCode = resolvedSet.toUpper();
                card->collectorNumber = resolvedCollector;
                card->displayImagePathResolved = false;
                cardChanged = true;
                printingChangedDeckIndexes.insert(location.deckIndex);
                if (location.section != CardSection::Consider)
                    validationChangedDeckIndexes.insert(location.deckIndex);
            }
            if (metadata->contains(QStringLiteral("cardColors")) &&
                (card->cardColors.isNull() ||
                 card->cardColors != metadata->value(QStringLiteral("cardColors")).toString())) {
                card->cardColors = metadata->value(QStringLiteral("cardColors")).toString();
                cardChanged = true;
            }
            if (metadata->contains(QStringLiteral("manaCost")) &&
                (card->manaCost.isNull() ||
                 card->manaCost != metadata->value(QStringLiteral("manaCost")).toString())) {
                card->manaCost = metadata->value(QStringLiteral("manaCost")).toString();
                cardChanged = true;
            }
            const QString localizedName =
                metadata->value(QStringLiteral("localizedName")).toString();
            const QString typeLine = metadata->value(QStringLiteral("typeLine")).toString();
            const QString colors = metadata->value(QStringLiteral("colors")).toString();
            const double manaValue = metadata->value(QStringLiteral("manaValue"), -1.0).toDouble();
            const QString rarity = metadata->value(QStringLiteral("rarity")).toString();
            if (!rarity.isEmpty() && card->rarity != rarity) {
                card->rarity = rarity;
                cardChanged = true;
            }
            if (!localizedName.isEmpty() && card->localizedName != localizedName) {
                card->localizedName = localizedName;
                cardChanged = true;
            }
            if (!typeLine.isEmpty() && card->typeLine != typeLine) {
                card->typeLine = typeLine;
                cardChanged = true;
            }
            if (metadata->contains(QStringLiteral("colors")) && card->colors != colors) {
                card->colors = colors;
                cardChanged = true;
            }
            if (manaValue >= 0.0 && card->manaValue != manaValue) {
                card->manaValue = manaValue;
                cardChanged = true;
            }
            if (cardChanged)
                changedDeckIndexes.insert(location.deckIndex);
        }
    }

    QSet<QString> changedDeckIds;
    const QString updatedAt = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
    for (const int deckIndex : changedDeckIndexes) {
        Deck &deck = m_decks[deckIndex];
        deck.updatedAt = updatedAt;
        changedDeckIds.insert(deck.id);
        if (printingChangedDeckIndexes.contains(deckIndex)) {
            for (QVector<DeckCard> *zone : {&deck.mainboard, &deck.sideboard, &deck.consider})
                mergeResolvedPrintings(*zone);
            rebuildCardDeckIndex(deckIndex);
        }
        if (validationChangedDeckIndexes.contains(deckIndex))
            scheduleDeckValidation(deck.id);
    }
    if (changedDeckIds.isEmpty())
        return;
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
            fill(&token.kind,
                 normalizedDeckTokenKind(
                     metadata->value(QStringLiteral("kind"), token.kind).toString(), token.typeLine,
                     metadata->value(QStringLiteral("layout")).toString()));
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
