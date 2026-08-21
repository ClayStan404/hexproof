// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "DeckEditor.h"

#include "DeckFormat.h"

#include <QDateTime>
#include <algorithm>
#include <utility>

namespace hexproof::client {

bool DeckEditor::rename(Deck &deck, const QString &name)
{
    const QString normalized = name.simplified();
    if (normalized.isEmpty())
        return false;
    deck.name = normalized;
    touch(deck);
    return true;
}

bool DeckEditor::changeFormat(Deck &deck, const QString &format, QString *error)
{
    const QString normalized = normalizedDeckFormat(format);
    if (!supportedDeckFormat(normalized)) {
        if (error)
            *error = QStringLiteral("Choose a supported deck format.");
        return false;
    }

    const QString targetTableMode = tableModeForDeckFormat(normalized);
    const bool wasCommanderFormat = isCommanderTableMode(deck.format);
    const bool targetCommanderFormat = isCommanderTableMode(targetTableMode);
    if (targetCommanderFormat && !deck.sideboard.isEmpty()) {
        for (const DeckCard &sideboardCard : std::as_const(deck.sideboard)) {
            const QString key = normalizedCardName(sideboardCard.name);
            const auto mainboardCard = std::find_if(
                deck.mainboard.begin(), deck.mainboard.end(),
                [&key, &sideboardCard](const DeckCard &card) {
                    return normalizedCardName(card.name) == key &&
                           card.setCode.compare(sideboardCard.setCode, Qt::CaseInsensitive) == 0 &&
                           card.collectorNumber == sideboardCard.collectorNumber;
                });
            if (mainboardCard == deck.mainboard.end())
                deck.mainboard.append(sideboardCard);
            else
                mainboardCard->count += sideboardCard.count;
        }
        deck.sideboard.clear();
    }
    if (wasCommanderFormat != targetCommanderFormat)
        deck.commanders.clear();

    deck.deckFormat = normalized;
    deck.format = targetTableMode;
    touch(deck);
    return true;
}

bool DeckEditor::toggleCommander(Deck &deck, const QString &cardName, QString *error)
{
    const QString key = normalizedCardName(cardName);
    const auto match =
        std::find_if(deck.mainboard.cbegin(), deck.mainboard.cend(),
                     [&key](const DeckCard &card) { return normalizedCardName(card.name) == key; });
    if (match == deck.mainboard.cend())
        return false;

    if (isCommander(deck, match->name)) {
        removeCommander(deck, match->name);
    } else {
        if (deck.commanders.size() >= 2) {
            if (error)
                *error = QStringLiteral("A Commander deck can designate at most two commanders.");
            return false;
        }
        deck.commanders.append(match->name);
    }
    touch(deck);
    return true;
}

bool DeckEditor::moveCard(Deck &deck, const QString &cardName, bool toSideboard)
{
    QVector<DeckCard> &source = toSideboard ? deck.mainboard : deck.sideboard;
    QVector<DeckCard> &destination = toSideboard ? deck.sideboard : deck.mainboard;
    const QString key = normalizedCardName(cardName);
    for (int index = 0; index < source.size(); ++index) {
        if (normalizedCardName(source.at(index).name) != key)
            continue;
        DeckCard moved = source.at(index);
        moved.count = 1;
        source[index].count--;
        if (source.at(index).count == 0)
            source.removeAt(index);
        const auto destinationCard =
            std::find_if(destination.begin(), destination.end(), [&key](const DeckCard &card) {
                return normalizedCardName(card.name) == key;
            });
        if (destinationCard == destination.end())
            destination.append(moved);
        else
            destinationCard->count++;
        if (toSideboard)
            removeCommander(deck, cardName);
        touch(deck);
        return true;
    }
    return false;
}

bool DeckEditor::changeCardCount(Deck &deck, const QString &cardName, bool sideboard, int delta,
                                 QString *error)
{
    if (delta == 0)
        return false;
    QVector<DeckCard> &cards = sideboard ? deck.sideboard : deck.mainboard;
    const QString key = normalizedCardName(cardName);
    for (int index = 0; index < cards.size(); ++index) {
        if (normalizedCardName(cards.at(index).name) != key)
            continue;
        cards[index].count = qMax(0, cards.at(index).count + delta);
        if (cards.at(index).count == 0) {
            if (!sideboard)
                removeCommander(deck, cardName);
            cards.removeAt(index);
        }
        touch(deck);
        return true;
    }
    if (error)
        *error = QStringLiteral("That card is not in the deck.");
    return false;
}

bool DeckEditor::addCard(Deck &deck, const QString &name, const QString &localizedName,
                         const QString &typeLine, const QString &setCode,
                         const QString &collectorNumber, bool sideboard, QString *error)
{
    if (name.simplified().isEmpty()) {
        if (error)
            *error = QStringLiteral("Card name is required.");
        return false;
    }

    QVector<DeckCard> &cards = sideboard ? deck.sideboard : deck.mainboard;
    const QString key = normalizedCardName(name);
    const auto existing = std::find_if(cards.begin(), cards.end(), [&key](const DeckCard &card) {
        return normalizedCardName(card.name) == key;
    });
    if (existing != cards.end()) {
        existing->count++;
    } else {
        DeckCard card;
        card.name = name.simplified();
        card.localizedName = localizedName.simplified();
        card.typeLine = typeLine;
        card.setCode = setCode.toUpper();
        card.collectorNumber = collectorNumber;
        cards.append(card);
    }
    touch(deck);
    return true;
}

bool DeckEditor::setCardPrinting(Deck &deck, const QString &cardName, bool sideboard,
                                 const QString &localizedName, const QString &typeLine,
                                 const QString &setCode, const QString &collectorNumber,
                                 DeckCard *updatedCard)
{
    if (setCode.isEmpty() || collectorNumber.isEmpty())
        return false;
    QVector<DeckCard> &cards = sideboard ? deck.sideboard : deck.mainboard;
    for (DeckCard &card : cards) {
        if (!cardNamesMatch(card.name, cardName))
            continue;
        card.localizedName = localizedName.simplified();
        card.typeLine = typeLine;
        card.setCode = setCode.toUpper();
        card.collectorNumber = collectorNumber;
        card.imagePath.clear();
        if (updatedCard)
            *updatedCard = card;
        touch(deck);
        return true;
    }
    return false;
}

bool DeckEditor::applyCardMetadata(Deck &deck, const QString &requestedName,
                                   const QString &localizedName, const QString &typeLine,
                                   const QString &imagePath, const QString &setCode,
                                   const QString &collectorNumber)
{
    const QString key = normalizedCardName(requestedName);
    bool changed = false;
    const auto apply = [&](QVector<DeckCard> &cards) {
        for (DeckCard &card : cards) {
            if (normalizedCardName(card.name) != key)
                continue;
            if (!setCode.isEmpty() && !collectorNumber.isEmpty() && !card.setCode.isEmpty() &&
                !card.collectorNumber.isEmpty() &&
                (card.setCode.compare(setCode, Qt::CaseInsensitive) != 0 ||
                 card.collectorNumber != collectorNumber)) {
                continue;
            }
            const bool updateLocalizedName =
                !localizedName.isEmpty() && card.localizedName != localizedName;
            const bool updateTypeLine = !typeLine.isEmpty() && card.typeLine != typeLine;
            const bool updateImagePath = !imagePath.isEmpty() && card.imagePath != imagePath;
            const bool updateSetCode = card.setCode.isEmpty() && !setCode.isEmpty();
            const bool updateCollectorNumber =
                card.collectorNumber.isEmpty() && !collectorNumber.isEmpty();
            if (!updateLocalizedName && !updateTypeLine && !updateImagePath && !updateSetCode &&
                !updateCollectorNumber) {
                continue;
            }
            if (updateLocalizedName)
                card.localizedName = localizedName;
            if (updateTypeLine)
                card.typeLine = typeLine;
            if (updateImagePath)
                card.imagePath = imagePath;
            if (updateSetCode)
                card.setCode = setCode.toUpper();
            if (updateCollectorNumber)
                card.collectorNumber = collectorNumber;
            changed = true;
        }
    };
    apply(deck.mainboard);
    apply(deck.sideboard);
    if (changed)
        touch(deck);
    return changed;
}

bool DeckEditor::addToken(Deck &deck, const DeckToken &token)
{
    DeckToken normalized = token;
    normalized.name = normalized.name.simplified();
    normalized.localizedName = normalized.localizedName.simplified();
    normalized.setCode = normalized.setCode.toUpper();
    if (normalized.name.isEmpty() || normalized.setCode.isEmpty() ||
        normalized.collectorNumber.isEmpty()) {
        return false;
    }
    const QString key = normalizedCardName(normalized.name);
    const auto existing = std::find_if(
        deck.tokens.cbegin(), deck.tokens.cend(), [&normalized, &key](const auto &item) {
            return normalizedCardName(item.name) == key &&
                   item.setCode.compare(normalized.setCode, Qt::CaseInsensitive) == 0 &&
                   item.collectorNumber == normalized.collectorNumber;
        });
    if (existing != deck.tokens.cend())
        return false;
    deck.tokens.append(normalized);
    touch(deck);
    return true;
}

bool DeckEditor::removeToken(Deck &deck, const QString &name, const QString &setCode,
                             const QString &collectorNumber)
{
    const QString key = normalizedCardName(name);
    const auto existing =
        std::find_if(deck.tokens.cbegin(), deck.tokens.cend(),
                     [&key, &setCode, &collectorNumber](const auto &item) {
                         return normalizedCardName(item.name) == key &&
                                item.setCode.compare(setCode, Qt::CaseInsensitive) == 0 &&
                                item.collectorNumber == collectorNumber;
                     });
    if (existing == deck.tokens.cend())
        return false;
    deck.tokens.erase(existing);
    touch(deck);
    return true;
}

int DeckEditor::cardCopies(const Deck &deck, const QString &cardName)
{
    const QString key = normalizedCardName(cardName);
    int count = 0;
    const auto addCopies = [&key, &count](const QVector<DeckCard> &cards) {
        for (const DeckCard &card : cards) {
            if (normalizedCardName(card.name) == key)
                count += card.count;
        }
    };
    addCopies(deck.mainboard);
    addCopies(deck.sideboard);
    return count;
}

bool DeckEditor::canAddCard(const Deck &deck, const QString &cardName, const QString &typeLine)
{
    Q_UNUSED(deck)
    Q_UNUSED(typeLine)
    return !cardName.simplified().isEmpty();
}

bool DeckEditor::isCommander(const Deck &deck, const QString &cardName)
{
    const QString key = normalizedCardName(cardName);
    return std::any_of(
        deck.commanders.cbegin(), deck.commanders.cend(),
        [&key](const QString &commander) { return normalizedCardName(commander) == key; });
}

void DeckEditor::removeCommander(Deck &deck, const QString &cardName)
{
    const QString key = normalizedCardName(cardName);
    deck.commanders.removeIf(
        [&key](const QString &commander) { return normalizedCardName(commander) == key; });
}

void DeckEditor::touch(Deck &deck)
{
    deck.updatedAt = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
}

} // namespace hexproof::client
