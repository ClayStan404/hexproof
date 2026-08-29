// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "DeckLibraryModel.h"

#include "deck/DeckFormat.h"

#include <QMetaMethod>

namespace hexproof::client {

void DeckLibraryModel::scheduleDeckValidation(const QString &deckId)
{
    if (!isSignalConnected(QMetaMethod::fromSignal(&DeckLibraryModel::decksNeedValidation)))
        return;
    const Deck *deck = deckById(deckId);
    if (!deck || !isNamedConstructedFormat(deck->deckFormat))
        return;

    ++m_validationRevisions[deckId];
    m_pendingValidationDeckIds.insert(deckId);
    QVariantMap validation = m_deckValidations.value(deckId);
    validation.insert(QStringLiteral("pending"), true);
    m_deckValidations.insert(deckId, validation);
    m_validationTimer.start();
}

QVariantMap DeckLibraryModel::validationForDeck(const QString &deckId) const
{
    return m_deckValidations.value(deckId);
}

void DeckLibraryModel::refreshDeckValidation()
{
    if (!isSignalConnected(QMetaMethod::fromSignal(&DeckLibraryModel::decksNeedValidation)))
        return;
    m_validationTimer.stop();
    QSet<QString> validDeckIds;
    QSet<QString> changedDeckIds;
    for (const Deck &deck : m_decks) {
        if (!isNamedConstructedFormat(deck.deckFormat)) {
            if (m_deckValidations.remove(deck.id) > 0) {
                changedDeckIds.insert(deck.id);
            }
            m_validationRevisions.remove(deck.id);
            m_pendingValidationDeckIds.remove(deck.id);
            continue;
        }
        validDeckIds.insert(deck.id);
        ++m_validationRevisions[deck.id];
        m_pendingValidationDeckIds.insert(deck.id);
        QVariantMap pending = m_deckValidations.value(deck.id);
        pending.insert(QStringLiteral("pending"), true);
        m_deckValidations.insert(deck.id, pending);
        changedDeckIds.insert(deck.id);
    }
    for (auto it = m_deckValidations.begin(); it != m_deckValidations.end();) {
        if (validDeckIds.contains(it.key())) {
            ++it;
            continue;
        }
        m_validationRevisions.remove(it.key());
        m_pendingValidationDeckIds.remove(it.key());
        it = m_deckValidations.erase(it);
    }
    if (!changedDeckIds.isEmpty())
        notifyDecksChanged(changedDeckIds);
    validatePendingDecks();
}

void DeckLibraryModel::validatePendingDecks()
{
    if (!isSignalConnected(QMetaMethod::fromSignal(&DeckLibraryModel::decksNeedValidation)) ||
        m_pendingValidationDeckIds.isEmpty()) {
        return;
    }

    QVariantList requests;
    for (const Deck &deck : m_decks) {
        if (!m_pendingValidationDeckIds.contains(deck.id) ||
            !isNamedConstructedFormat(deck.deckFormat)) {
            continue;
        }
        const auto cardList = [](const QVector<DeckCard> &cards) {
            QVariantList result;
            result.reserve(cards.size());
            for (const DeckCard &card : cards) {
                result.append(QVariantMap{
                    {QStringLiteral("name"), card.name},
                    {QStringLiteral("setCode"), card.setCode},
                    {QStringLiteral("collectorNumber"), card.collectorNumber},
                    {QStringLiteral("count"), card.count},
                });
            }
            return result;
        };
        requests.append(QVariantMap{
            {QStringLiteral("deckId"), deck.id},
            {QStringLiteral("validationRevision"), m_validationRevisions.value(deck.id)},
            {QStringLiteral("tableMode"), deck.format},
            {QStringLiteral("deckFormat"), deck.deckFormat},
            {QStringLiteral("commanders"), deck.commanders},
            {QStringLiteral("mainboard"), cardList(deck.mainboard)},
            {QStringLiteral("sideboard"), cardList(deck.sideboard)},
        });
    }
    if (!requests.isEmpty())
        emit decksNeedValidation(requests);
}

void DeckLibraryModel::applyDeckValidation(const QVariantList &results)
{
    QSet<QString> currentIds;
    for (const Deck &deck : m_decks)
        currentIds.insert(deck.id);
    QSet<QString> changedDeckIds;
    for (const QVariant &entry : results) {
        QVariantMap result = entry.toMap();
        const QString deckId = result.value(QStringLiteral("deckId")).toString();
        if (deckId.isEmpty() || !currentIds.contains(deckId))
            continue;
        const quint64 revision = result.value(QStringLiteral("validationRevision")).toULongLong();
        if (revision != m_validationRevisions.value(deckId))
            continue;
        result.remove(QStringLiteral("deckId"));
        result.remove(QStringLiteral("validationRevision"));
        result.insert(QStringLiteral("pending"), false);
        m_deckValidations.insert(deckId, result);
        m_pendingValidationDeckIds.remove(deckId);
        changedDeckIds.insert(deckId);
    }
    if (!changedDeckIds.isEmpty())
        notifyDecksChanged(changedDeckIds);
}

} // namespace hexproof::client
