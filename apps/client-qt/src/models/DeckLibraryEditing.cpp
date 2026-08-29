// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "DeckLibraryModel.h"

#include "deck/DeckEditor.h"
#include "deck/DeckFormat.h"
#include "models/DeckLibraryQueries.h"

#include <algorithm>

namespace hexproof::client {

bool DeckLibraryModel::deleteDeck(const QString &id)
{
    for (int i = 0; i < m_decks.size(); ++i) {
        if (m_decks.at(i).id != id)
            continue;
        const QVector<Deck> previousDecks = m_decks;
        const QString previousCurrentDeckId = m_currentDeckId;
        const QString previousActiveMatchDeckId = m_activeMatchDeckId;
        m_decks.removeAt(i);
        if (m_currentDeckId == id)
            m_currentDeckId.clear();
        const bool activeMatchDeckRemoved = m_activeMatchDeckId == id;
        if (activeMatchDeckRemoved)
            m_activeMatchDeckId.clear();
        if (!save()) {
            m_decks = previousDecks;
            m_currentDeckId = previousCurrentDeckId;
            m_activeMatchDeckId = previousActiveMatchDeckId;
            return false;
        }
        m_deckValidations.remove(id);
        m_validationRevisions.remove(id);
        m_pendingValidationDeckIds.remove(id);
        beginResetModel();
        rebuildVisibleRows();
        rebuildCardDeckIndex();
        endResetModel();
        emit countChanged();
        emit currentDeckCardsChanged();
        emit currentDeckChanged();
        if (activeMatchDeckRemoved)
            emit activeMatchTokensChanged();
        return true;
    }
    setLastError(QStringLiteral("Deck not found."));
    return false;
}

bool DeckLibraryModel::openDeck(const QString &id)
{
    for (const Deck &deck : m_decks) {
        if (deck.id == id) {
            m_currentDeckId = id;
            emit currentDeckCardsChanged();
            emit currentDeckChanged();
            return true;
        }
    }
    setLastError(QStringLiteral("Deck not found."));
    return false;
}

void DeckLibraryModel::closeDeck()
{
    if (m_currentDeckId.isEmpty())
        return;
    m_currentDeckId.clear();
    emit currentDeckCardsChanged();
    emit currentDeckChanged();
}

bool DeckLibraryModel::renameCurrentDeck(const QString &name)
{
    Deck *deck = currentDeck();
    if (!deck)
        return false;
    const Deck previous = *deck;
    if (!DeckEditor::rename(*deck, name))
        return false;
    if (!save()) {
        *deck = previous;
        return false;
    }
    notifyAllChanged();
    return true;
}

bool DeckLibraryModel::changeCurrentDeckFormat(const QString &format)
{
    clearLastError();
    Deck *deck = currentDeck();
    if (!deck)
        return false;
    const QString normalized = normalizedDeckFormat(format);
    if (deck->deckFormat == normalized)
        return true;

    const Deck previous = *deck;
    QString error;
    if (!DeckEditor::changeFormat(*deck, normalized, &error)) {
        if (!error.isEmpty())
            setLastError(error);
        return false;
    }
    if (!save()) {
        *deck = previous;
        return false;
    }

    const QString deckId = deck->id;
    if (isNamedConstructedFormat(deck->deckFormat)) {
        scheduleDeckValidation(deckId);
    } else {
        m_deckValidations.remove(deckId);
        m_validationRevisions.remove(deckId);
        m_pendingValidationDeckIds.remove(deckId);
    }
    notifyAllChanged();
    return true;
}

bool DeckLibraryModel::setCommander(const QString &cardName)
{
    clearLastError();
    Deck *deck = currentDeck();
    if (!deck || !isCommanderTableMode(deck->format))
        return false;
    const Deck previous = *deck;
    QString error;
    if (!DeckEditor::toggleCommander(*deck, cardName, &error)) {
        if (!error.isEmpty())
            setLastError(error);
        return false;
    }
    if (!save()) {
        *deck = previous;
        return false;
    }
    scheduleDeckValidation(deck->id);
    notifyAllChanged();
    return true;
}

bool DeckLibraryModel::moveCard(const QString &cardName, bool toSideboard)
{
    Deck *deck = currentDeck();
    if (!deck || (isCubeDeckFormat(deck->deckFormat) && toSideboard))
        return false;
    const Deck previous = *deck;
    if (!DeckEditor::moveCard(*deck, cardName, toSideboard))
        return false;
    if (!save()) {
        *deck = previous;
        return false;
    }
    scheduleDeckValidation(deck->id);
    notifyAllChanged();
    return true;
}

bool DeckLibraryModel::changeCardCount(const QString &cardName, bool sideboard, int delta)
{
    Deck *deck = currentDeck();
    if (!deck || (isCubeDeckFormat(deck->deckFormat) && sideboard))
        return false;
    const Deck previous = *deck;
    QString error;
    if (!DeckEditor::changeCardCount(*deck, cardName, sideboard, delta, &error)) {
        if (!error.isEmpty())
            setLastError(error);
        return false;
    }
    if (!save()) {
        *deck = previous;
        return false;
    }
    scheduleDeckValidation(deck->id);
    rebuildCardDeckIndex();
    notifyAllChanged();
    return true;
}

bool DeckLibraryModel::addCard(const QString &name, const QString &localizedName,
                               const QString &typeLine, const QString &setCode,
                               const QString &collectorNumber, bool sideboard)
{
    Deck *deck = currentDeck();
    if (!deck || (isCubeDeckFormat(deck->deckFormat) && sideboard))
        return false;
    const Deck previous = *deck;
    QString error;
    if (!DeckEditor::addCard(*deck, name, localizedName, typeLine, setCode, collectorNumber,
                             sideboard, &error)) {
        if (!error.isEmpty())
            setLastError(error);
        return false;
    }
    if (!save()) {
        *deck = previous;
        return false;
    }
    scheduleDeckValidation(deck->id);
    rebuildCardDeckIndex();
    notifyAllChanged();
    emit cardsNeedCaching(QVariantList{QVariantMap{
        {QStringLiteral("name"), name},
        {QStringLiteral("setCode"), setCode},
        {QStringLiteral("collectorNumber"), collectorNumber},
        {QStringLiteral("exactArt"), true},
    }});
    return true;
}

bool DeckLibraryModel::setCardPrinting(const QString &cardName, bool sideboard,
                                       const QString &localizedName, const QString &typeLine,
                                       const QString &setCode, const QString &collectorNumber)
{
    Deck *deck = currentDeck();
    if (!deck)
        return false;
    const Deck previous = *deck;
    DeckCard updatedCard;
    if (!DeckEditor::setCardPrinting(*deck, cardName, sideboard, localizedName, typeLine, setCode,
                                     collectorNumber, &updatedCard)) {
        return false;
    }
    if (!save()) {
        *deck = previous;
        return false;
    }
    scheduleDeckValidation(deck->id);
    notifyAllChanged();
    emit cardsNeedCaching(QVariantList{QVariantMap{
        {QStringLiteral("name"), updatedCard.name},
        {QStringLiteral("setCode"), updatedCard.setCode},
        {QStringLiteral("collectorNumber"), updatedCard.collectorNumber},
        {QStringLiteral("exactArt"), true},
    }});
    return true;
}

bool DeckLibraryModel::addToken(const QVariantMap &token)
{
    Deck *deck = currentDeck();
    if (!deck)
        return false;
    const Deck previous = *deck;
    const DeckToken deckToken{
        token.value(QStringLiteral("name")).toString(),
        token.value(QStringLiteral("displayName")).toString(),
        token.value(QStringLiteral("setCode")).toString(),
        token.value(QStringLiteral("collectorNumber")).toString(),
        token.value(QStringLiteral("typeLine")).toString(),
        token.value(QStringLiteral("power")).toString(),
        token.value(QStringLiteral("toughness")).toString(),
        token.value(QStringLiteral("oracleText")).toString(),
    };
    if (!DeckEditor::addToken(*deck, deckToken))
        return false;
    if (!save()) {
        *deck = previous;
        return false;
    }
    notifyAllChanged();
    if (deck->id == m_activeMatchDeckId)
        emit activeMatchTokensChanged();
    return true;
}

bool DeckLibraryModel::removeToken(const QString &name, const QString &setCode,
                                   const QString &collectorNumber)
{
    Deck *deck = currentDeck();
    if (!deck)
        return false;
    const Deck previous = *deck;
    if (!DeckEditor::removeToken(*deck, name, setCode, collectorNumber))
        return false;
    if (!save()) {
        *deck = previous;
        return false;
    }
    notifyAllChanged();
    if (deck->id == m_activeMatchDeckId)
        emit activeMatchTokensChanged();
    return true;
}

bool DeckLibraryModel::setActiveMatchDeck(const QString &id)
{
    if (m_activeMatchDeckId == id)
        return activeMatchDeck() != nullptr;
    const auto deck = std::find_if(m_decks.cbegin(), m_decks.cend(),
                                   [&id](const Deck &candidate) { return candidate.id == id; });
    if (deck == m_decks.cend())
        return false;
    m_activeMatchDeckId = id;
    emit activeMatchTokensChanged();
    return true;
}

int DeckLibraryModel::currentCardCopies(const QString &cardName) const
{
    const Deck *deck = currentDeck();
    return deck ? DeckEditor::cardCopies(*deck, cardName) : 0;
}

bool DeckLibraryModel::canAddCard(const QString &cardName, const QString &typeLine) const
{
    const Deck *deck = currentDeck();
    return deck && DeckEditor::canAddCard(*deck, cardName, typeLine);
}

QVariantList DeckLibraryModel::matchDecks(const QString &format, bool allowMissingArt) const
{
    return DeckLibraryQueries::matchingDecks(m_decks, format, allowMissingArt, m_deckValidations);
}

QVariantMap DeckLibraryModel::deckForMatch(const QString &id, bool allowMissingArt) const
{
    return DeckLibraryQueries::matchPayload(m_decks, id, allowMissingArt, m_deckValidations);
}

QVariantMap DeckLibraryModel::cubeProduct(const QString &id) const
{
    const Deck *deck = deckById(id);
    return deck ? DeckLibraryQueries::cubeProduct(*deck) : QVariantMap{};
}

} // namespace hexproof::client
