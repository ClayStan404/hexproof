// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "DeckLibraryQueries.h"

#include "deck/DeckEditor.h"
#include "deck/DeckFormat.h"

#include <QFileInfo>
#include <QSet>
#include <QUrl>

#include <algorithm>

namespace hexproof::client {

namespace {

qsizetype categoryOrder(const QString &category)
{
    static const QStringList order{
        QStringLiteral("Creatures"), QStringLiteral("Planeswalkers"),
        QStringLiteral("Artifacts"), QStringLiteral("Enchantments"),
        QStringLiteral("Spells"),    QStringLiteral("Lands"),
        QStringLiteral("Other"),
    };
    const qsizetype index = order.indexOf(category);
    return index < 0 ? order.size() : index;
}

QString cardRequestKey(const QString &name, const QString &setCode, const QString &collectorNumber)
{
    return normalizedCardName(name) + QChar(0x1f) + setCode.toUpper() + QChar(0x1f) +
           collectorNumber;
}

} // namespace

QString DeckLibraryQueries::commanderDisplayName(const Deck &deck)
{
    return deck.commanders.join(QStringLiteral(" / "));
}

bool DeckLibraryQueries::deckReady(const Deck &deck, const QVariantMap &validation)
{
    return deckSelectable(deck, false, validation);
}

bool DeckLibraryQueries::deckSelectable(const Deck &deck, bool allowMissingArt,
                                        const QVariantMap &validation)
{
    if (isCubeDeckFormat(deck.deckFormat)) {
        return cardCount(deck.mainboard) >= 360 && deck.sideboard.isEmpty() &&
               hasExactPrintings(deck) && (allowMissingArt || missingImageCount(deck) == 0);
    }
    constexpr int minimumOpeningHandCards = 7;
    if (cardCount(deck.mainboard) < minimumOpeningHandCards)
        return false;
    if (isCommanderTableMode(deck.format) && deck.commanders.isEmpty())
        return false;
    if (validation.value(QStringLiteral("pending")).toBool())
        return false;
    if (validation.contains(QStringLiteral("valid")) &&
        !validation.value(QStringLiteral("valid")).toBool())
        return false;
    return allowMissingArt || missingImageCount(deck) == 0;
}

QString DeckLibraryQueries::deckStatus(const Deck &deck, const QVariantMap &validation)
{
    if (cardCount(deck.mainboard) == 0)
        return QStringLiteral("Empty deck");
    if (isCubeDeckFormat(deck.deckFormat)) {
        if (!deck.sideboard.isEmpty())
            return QStringLiteral("Cube cards must stay in the main pool.");
        if (!hasExactPrintings(deck))
            return QStringLiteral("Every Cube card needs an exact printing.");
        if (cardCount(deck.mainboard) < 360) {
            return QStringLiteral(
                "The Cube needs at least 360 physical cards for an eight-player draft.");
        }
        const int missing = missingImageCount(deck);
        if (missing > 0) {
            return QStringLiteral("%1 image%2 missing")
                .arg(missing)
                .arg(missing == 1 ? QString{} : QStringLiteral("s"));
        }
        return QStringLiteral("Playable");
    }
    if (isCommanderTableMode(deck.format) && deck.commanders.isEmpty())
        return QStringLiteral("Commander required");
    if (validation.value(QStringLiteral("pending")).toBool())
        return QStringLiteral("Checking deck legality…");
    if (validation.contains(QStringLiteral("valid")) &&
        !validation.value(QStringLiteral("valid")).toBool())
        return validation.value(QStringLiteral("status")).toString();
    if (validation.contains(QStringLiteral("verified")) &&
        !validation.value(QStringLiteral("verified")).toBool())
        return validation.value(QStringLiteral("status")).toString();
    constexpr int minimumOpeningHandCards = 7;
    if (cardCount(deck.mainboard) < minimumOpeningHandCards)
        return QStringLiteral("At least 7 main-deck cards required");
    const int missing = missingImageCount(deck);
    if (missing > 0)
        return QStringLiteral("%1 image%2 missing")
            .arg(missing)
            .arg(missing == 1 ? QString{} : QStringLiteral("s"));
    if (!validation.value(QStringLiteral("warnings")).toStringList().isEmpty())
        return validation.value(QStringLiteral("status")).toString();
    return QStringLiteral("Playable");
}

int DeckLibraryQueries::missingImageCount(const Deck &deck)
{
    int count = 0;
    const auto inspect = [&count](const QVector<DeckCard> &cards) {
        for (const DeckCard &card : cards) {
            if (card.imagePath.isEmpty() || !QFileInfo::exists(card.imagePath))
                ++count;
        }
    };
    inspect(deck.mainboard);
    inspect(deck.sideboard);
    return count;
}

bool DeckLibraryQueries::hasMissingArt(const QVector<Deck> &decks)
{
    return std::any_of(decks.cbegin(), decks.cend(),
                       [](const Deck &deck) { return missingImageCount(deck) > 0; });
}

bool DeckLibraryQueries::hasExactPrintings(const Deck &deck)
{
    if (deck.mainboard.isEmpty())
        return false;
    for (const DeckCard &card : deck.mainboard) {
        if (card.setCode.trimmed().isEmpty() ||
            card.setCode.compare(QStringLiteral("CUBE"), Qt::CaseInsensitive) == 0 ||
            card.collectorNumber.trimmed().isEmpty()) {
            return false;
        }
    }
    return true;
}

QVariantMap DeckLibraryQueries::cubeProduct(const Deck &deck)
{
    if (!isCubeDeckFormat(deck.deckFormat) || cardCount(deck.mainboard) < 360 ||
        !deck.sideboard.isEmpty() || !hasExactPrintings(deck)) {
        return {};
    }

    QVariantList cards;
    cards.reserve(deck.mainboard.size());
    for (const DeckCard &card : deck.mainboard) {
        cards.append(QVariantMap{
            {QStringLiteral("name"), card.name},
            {QStringLiteral("setCode"), card.setCode.toUpper()},
            {QStringLiteral("collectorNumber"), card.collectorNumber},
            {QStringLiteral("typeLine"), card.typeLine},
            {QStringLiteral("rarity"), QStringLiteral("special")},
            {QStringLiteral("finish"), QStringLiteral("nonfoil")},
            {QStringLiteral("weight"), card.count},
        });
    }
    return QVariantMap{
        {QStringLiteral("id"), QStringLiteral("cube-") + deck.id},
        {QStringLiteral("name"), deck.name},
        {QStringLiteral("productType"), QStringLiteral("cube")},
        {QStringLiteral("authentic"), false},
        {QStringLiteral("cardsPerPack"), 0},
        {QStringLiteral("sheets"), QVariantList{QVariantMap{
                                       {QStringLiteral("name"), QStringLiteral("cube")},
                                       {QStringLiteral("withReplacement"), false},
                                       {QStringLiteral("cards"), cards},
                                   }}},
        {QStringLiteral("variants"), QVariantList{}},
    };
}

QVariantList DeckLibraryQueries::cardVariants(const QVector<DeckCard> &cards, const Deck &deck,
                                              bool grouped)
{
    QVector<DeckCard> sorted = cards;
    if (grouped) {
        std::sort(sorted.begin(), sorted.end(), [](const DeckCard &left, const DeckCard &right) {
            const QString leftCategory = cardCategory(left.typeLine);
            const QString rightCategory = cardCategory(right.typeLine);
            if (categoryOrder(leftCategory) != categoryOrder(rightCategory))
                return categoryOrder(leftCategory) < categoryOrder(rightCategory);
            return left.name.localeAwareCompare(right.name) < 0;
        });
    } else {
        std::sort(sorted.begin(), sorted.end(), [](const DeckCard &left, const DeckCard &right) {
            return left.name.localeAwareCompare(right.name) < 0;
        });
    }

    QVariantList result;
    for (const DeckCard &card : sorted) {
        const QString displayName = card.localizedName.isEmpty() ? card.name : card.localizedName;
        result.append(QVariantMap{
            {QStringLiteral("name"), card.name},
            {QStringLiteral("displayName"), displayName},
            {QStringLiteral("count"), card.count},
            {QStringLiteral("totalCount"), DeckEditor::cardCopies(deck, card.name)},
            {QStringLiteral("setCode"), card.setCode},
            {QStringLiteral("collectorNumber"), card.collectorNumber},
            {QStringLiteral("typeLine"), card.typeLine},
            {QStringLiteral("category"), cardCategory(card.typeLine)},
            {QStringLiteral("commander"), DeckEditor::isCommander(deck, card.name)},
            {QStringLiteral("imageSource"),
             card.imagePath.isEmpty() ? QString{} : QUrl::fromLocalFile(card.imagePath).toString()},
        });
    }
    return result;
}

QVariantList DeckLibraryQueries::tokenVariants(const QVector<DeckToken> &tokens)
{
    QVariantList result;
    result.reserve(tokens.size());
    for (const DeckToken &token : tokens) {
        result.append(QVariantMap{
            {QStringLiteral("name"), token.name},
            {QStringLiteral("displayName"),
             token.localizedName.isEmpty() ? token.name : token.localizedName},
            {QStringLiteral("typeLine"), token.typeLine},
            {QStringLiteral("setCode"), token.setCode},
            {QStringLiteral("collectorNumber"), token.collectorNumber},
            {QStringLiteral("power"), token.power},
            {QStringLiteral("toughness"), token.toughness},
            {QStringLiteral("oracleText"), token.oracleText},
        });
    }
    return result;
}

QVariantList DeckLibraryQueries::matchingDecks(const QVector<Deck> &decks, const QString &format,
                                               bool allowMissingArt,
                                               const QHash<QString, QVariantMap> &validations)
{
    QVariantList result;
    for (const Deck &deck : decks) {
        if (deck.deckFormat != normalizedDeckFormat(format))
            continue;
        const bool artReady = missingImageCount(deck) == 0;
        const QVariantMap validation = validations.value(deck.id);
        result.append(QVariantMap{
            {QStringLiteral("deckId"), deck.id},
            {QStringLiteral("deckName"), deck.name},
            {QStringLiteral("deckFormat"), deck.deckFormat},
            {QStringLiteral("tableMode"), deck.format},
            {QStringLiteral("mainCount"), cardCount(deck.mainboard)},
            {QStringLiteral("sideboardCount"), cardCount(deck.sideboard)},
            {QStringLiteral("exactPrintings"), hasExactPrintings(deck)},
            {QStringLiteral("commander"), commanderDisplayName(deck)},
            {QStringLiteral("ready"), deckSelectable(deck, allowMissingArt, validation)},
            {QStringLiteral("artReady"), artReady},
            {QStringLiteral("status"), deckStatus(deck, validation)},
            {QStringLiteral("legalityVerified"),
             validation.value(QStringLiteral("verified"), true)},
            {QStringLiteral("legalityIssues"),
             validation.value(QStringLiteral("issues")).toStringList()},
            {QStringLiteral("legalityWarnings"),
             validation.value(QStringLiteral("warnings")).toStringList()},
        });
    }
    return result;
}

QVariantMap DeckLibraryQueries::matchPayload(const QVector<Deck> &decks, const QString &id,
                                             bool allowMissingArt,
                                             const QHash<QString, QVariantMap> &validations)
{
    const auto cardList = [](const QVector<DeckCard> &cards) {
        QVariantList result;
        for (const DeckCard &card : cards) {
            result.append(QVariantMap{
                {QStringLiteral("name"), card.name},
                {QStringLiteral("count"), card.count},
                {QStringLiteral("setCode"), card.setCode},
                {QStringLiteral("collectorNumber"), card.collectorNumber},
                {QStringLiteral("typeLine"), card.typeLine},
            });
        }
        return result;
    };

    for (const Deck &deck : decks) {
        if (deck.id != id || !deckSelectable(deck, allowMissingArt, validations.value(deck.id)))
            continue;
        QVariantList commanders;
        for (const QString &commander : deck.commanders)
            commanders.append(commander);
        return QVariantMap{
            {QStringLiteral("name"), deck.name},
            {QStringLiteral("format"), deck.format},
            {QStringLiteral("deckFormat"), deck.deckFormat},
            {QStringLiteral("commander"),
             deck.commanders.isEmpty() ? QString{} : deck.commanders.first()},
            {QStringLiteral("commanders"), commanders},
            {QStringLiteral("mainboard"), cardList(deck.mainboard)},
            {QStringLiteral("sideboard"), cardList(deck.sideboard)},
        };
    }
    return {};
}

QVariantList DeckLibraryQueries::cacheRequestsForDeck(const Deck &deck, bool includeCached)
{
    QVariantList requests;
    QSet<QString> requestedKeys;
    const auto append = [&](const QVector<DeckCard> &cards) {
        for (const DeckCard &card : cards) {
            if (!includeCached && !card.imagePath.isEmpty() && QFileInfo::exists(card.imagePath))
                continue;
            const QString key = cardRequestKey(card.name, card.setCode, card.collectorNumber);
            if (requestedKeys.contains(key))
                continue;
            requestedKeys.insert(key);
            requests.append(QVariantMap{
                {QStringLiteral("name"), card.name},
                {QStringLiteral("setCode"), card.setCode},
                {QStringLiteral("collectorNumber"), card.collectorNumber},
            });
        }
    };
    append(deck.mainboard);
    append(deck.sideboard);
    return requests;
}

QVariantList DeckLibraryQueries::cacheRequestsForLibrary(const QVector<Deck> &decks,
                                                         bool includeCached)
{
    QVariantList requests;
    QSet<QString> requestedKeys;
    for (const Deck &deck : decks) {
        const QVariantList deckRequests = cacheRequestsForDeck(deck, includeCached);
        for (const QVariant &candidate : deckRequests) {
            const QVariantMap candidateMap = candidate.toMap();
            const QString key =
                cardRequestKey(candidateMap.value(QStringLiteral("name")).toString(),
                               candidateMap.value(QStringLiteral("setCode")).toString(),
                               candidateMap.value(QStringLiteral("collectorNumber")).toString());
            if (requestedKeys.contains(key))
                continue;
            requestedKeys.insert(key);
            requests.append(candidate);
        }
    }
    return requests;
}

} // namespace hexproof::client
