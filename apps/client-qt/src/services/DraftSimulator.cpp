// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "DraftSimulator.h"

#include <QHash>
#include <QJsonObject>
#include <QRandomGenerator>
#include <QSet>
#include <QUuid>
#include <algorithm>
#include <limits>
#include <utility>

namespace hexproof::client {

using namespace Qt::StringLiterals;

DraftSimulator::DraftSimulator(QObject *parent)
    : QObject(parent)
{
}

void DraftSimulator::setPackGenerator(PackGenerator generator)
{
    m_generatePacks = std::move(generator);
}

void DraftSimulator::setDeckSaver(DeckSaver saver)
{
    m_saveDeck = std::move(saver);
}

bool DraftSimulator::fail(const QString &message)
{
    m_lastError = message;
    emit lastErrorChanged();
    return false;
}

void DraftSimulator::clearError()
{
    if (m_lastError.isEmpty())
        return;
    m_lastError.clear();
    emit lastErrorChanged();
}

bool DraftSimulator::start(const QVariantMap &product, int seats)
{
    if (seats < 2 || seats > 8 || !m_generatePacks)
        return fail(tr("Choose two to eight seats and an installed draft product."));
    QVariantMap definition = product;
    const bool cube = definition.value(u"productType"_s).toString() == u"cube";
    if (cube)
        definition.insert(u"cardsPerPack"_s, 15);
    const int cardsPerPack = definition.value(u"cardsPerPack"_s).toInt();
    if (definition.value(u"name"_s).toString().isEmpty() || cardsPerPack < 1 || cardsPerPack > 30)
        return fail(tr("This product cannot be used for draft practice."));

    // Generate the entire pod together so Cube quantities remain physical stock.
    QVariantList packs = m_generatePacks(definition, seats * 3);
    if (packs.size() != seats * 3)
        return fail(
            tr("Could not generate all boosters. Check the installed product or Cube size."));
    const QString sessionId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    int serial = 0;
    for (QVariant &packValue : packs) {
        QVariantMap pack = packValue.toMap();
        QVariantList cards = pack.value(u"cards"_s).toList();
        if (cards.size() != cardsPerPack)
            return fail(tr("The product generated an incomplete booster."));
        for (QVariant &value : cards) {
            QVariantMap card = value.toMap();
            if (card.value(u"name"_s).toString().trimmed().isEmpty())
                return fail(tr("The product generated a card without a name."));
            card.insert(u"instanceId"_s, sessionId + u'/' + QString::number(++serial));
            value = card;
        }
        pack.insert(u"cards"_s, cards);
        packValue = pack;
    }

    // A failed start above leaves the previous practice session intact.
    m_sessionId = sessionId;
    m_product = {{u"name"_s, definition.value(u"name"_s)},
                 {u"setCode"_s, definition.value(u"setCode"_s)},
                 {u"productType"_s, definition.value(u"productType"_s)},
                 {u"authentic"_s, definition.value(u"authentic"_s)},
                 {u"cardsPerPack"_s, cardsPerPack}};
    m_unopenedPacks = packs;
    m_pools = QList<QVariantList>(seats);
    m_packs = QList<QVariantList>(seats);
    m_round = 1;
    m_finished = false;
    m_saved = false;
    m_savedIds.clear();
    m_savedBasics.clear();
    m_constructionDraft.clear();
    clearError();
    openRound();
    publish();
    return true;
}

void DraftSimulator::openRound()
{
    for (int seat = 0; seat < m_packs.size(); ++seat)
        m_packs[seat] = m_unopenedPacks.at((m_round - 1) * m_packs.size() + seat)
                            .toMap()
                            .value(u"cards"_s)
                            .toList();
}

int DraftSimulator::botChoice(int seat) const
{
    // Deliberately modest heuristics: rarity, drafted colors, and a playable curve.
    // No future pack or another seat's pool participates in this decision.
    QHash<QChar, int> colors;
    int expensive = 0;
    for (const QVariant &value : m_pools.at(seat)) {
        const QVariantMap card = value.toMap();
        for (QChar color : card.value(u"cardColors"_s).toString())
            ++colors[color];
        if (card.value(u"manaValue"_s).toDouble() >= 5)
            ++expensive;
    }
    const QVariantList &pack = m_packs.at(seat);
    double best = -std::numeric_limits<double>::infinity();
    int choice = 0;
    for (int index = 0; index < pack.size(); ++index) {
        const QVariantMap card = pack.at(index).toMap();
        const QString rarity = card.value(u"rarity"_s).toString();
        double score = rarity == u"mythic"     ? 3.5
                       : rarity == u"rare"     ? 3.0
                       : rarity == u"uncommon" ? 2.0
                                               : 1.0;
        const QString cardColors = card.value(u"cardColors"_s).toString();
        for (QChar color : cardColors)
            score += qMin(2.5, colors.value(color) * 0.35);
        if (cardColors.size() > 1)
            score -= (cardColors.size() - 1) * 1.0;
        const QString type = card.value(u"typeLine"_s).toString();
        if (type.contains(u"Basic"_s) && type.contains(u"Land"_s))
            score -= 5;
        if (card.value(u"manaValue"_s).toDouble() >= 5)
            score -= qMin(2.0, expensive * 0.25);
        score += QRandomGenerator::global()->generateDouble() * 0.6;
        if (score > best) {
            best = score;
            choice = index;
        }
    }
    return choice;
}

bool DraftSimulator::pick(const QString &instanceId)
{
    if (m_round == 0 || m_finished)
        return fail(tr("No draft pick is available."));
    const auto &pack = m_packs.first();
    const auto selected = std::find_if(pack.cbegin(), pack.cend(), [&](const QVariant &card) {
        return card.toMap().value(u"instanceId"_s).toString() == instanceId;
    });
    if (selected == pack.cend())
        return fail(tr("That card is no longer in the current booster."));
    const int humanChoice = static_cast<int>(selected - pack.cbegin());
    for (int seat = 0; seat < m_packs.size(); ++seat) {
        const int choice = seat == 0 ? humanChoice : botChoice(seat);
        m_pools[seat].append(m_packs[seat].takeAt(choice));
    }
    if (m_packs.first().isEmpty()) {
        if (m_round == 3)
            m_finished = true;
        else {
            ++m_round;
            openRound();
        }
    } else {
        const int direction = m_round == 2 ? -1 : 1;
        QList<QVariantList> passed(m_packs.size());
        for (int seat = 0; seat < m_packs.size(); ++seat)
            passed[(seat + direction + m_packs.size()) % m_packs.size()] = m_packs[seat];
        m_packs = passed;
    }
    clearError();
    publish();
    return true;
}

bool DraftSimulator::saveDeck(const QString &name, const QVariantList &instanceIds,
                              const QVariantList &basicLands)
{
    if (!m_finished || !m_saveDeck)
        return fail(tr("Finish drafting before saving a deck."));
    QSet<QString> selected;
    for (const QVariant &value : instanceIds) {
        const QString id = value.toString();
        if (selected.contains(id))
            return fail(tr("A drafted card can only be used once."));
        selected.insert(id);
    }
    QVariantList mainboard;
    QVariantList sideboard;
    for (const QVariant &value : m_pools.first()) {
        QVariantMap card = value.toMap();
        const bool inMain = selected.remove(card.value(u"instanceId"_s).toString());
        card.insert(u"count"_s, 1);
        (inMain ? mainboard : sideboard).append(card);
    }
    if (!selected.isEmpty())
        return fail(tr("The deck contains a card outside your drafted pool."));
    const QSet<QString> basicNames{u"Plains"_s, u"Island"_s, u"Swamp"_s, u"Mountain"_s,
                                   u"Forest"_s};
    QSet<QString> addedBasics;
    int count = mainboard.size();
    for (const QVariant &value : basicLands) {
        const QVariantMap land = value.toMap();
        const QString landName = land.value(u"name"_s).toString();
        const int quantity = land.value(u"count"_s).toInt();
        if (!basicNames.contains(landName) || addedBasics.contains(landName) || quantity < 1 ||
            quantity > 1000 || land.value(u"count"_s).toDouble() != quantity)
            return fail(tr("Choose valid quantities of ordinary basic lands."));
        addedBasics.insert(landName);
        mainboard.append(land);
        count += quantity;
    }
    if (count < 40)
        return fail(tr("A practice deck needs at least 40 cards."));
    const QString error =
        m_saveDeck(name, {{u"mainboard"_s, mainboard}, {u"sideboard"_s, sideboard}});
    if (!error.isEmpty())
        return fail(error);
    m_saved = true;
    m_savedIds = instanceIds;
    m_savedBasics = basicLands;
    m_constructionDraft.clear();
    clearError();
    publish();
    return true;
}

void DraftSimulator::publish()
{
    QVariantList participants;
    for (int seat = 0; seat < m_pools.size(); ++seat) {
        participants.append(
            QVariantMap{{u"participantId"_s, QString::number(seat)},
                        {u"displayName"_s, seat == 0 ? tr("You") : tr("Bot %1").arg(seat)},
                        {u"poolCount"_s, m_pools.at(seat).size()},
                        {u"queuedPacks"_s, m_finished ? 0 : 1},
                        {u"autoDraft"_s, seat != 0},
                        {u"deckSubmitted"_s, seat == 0 && m_saved}});
    }
    m_state.applySnapshot(QJsonObject::fromVariantMap(
        {{u"tournamentId"_s, m_sessionId},
         {u"eventType"_s, m_product.value(u"productType"_s).toString() == u"cube" ? u"cube_draft"_s
                                                                                  : u"set_draft"_s},
         {u"stage"_s, m_finished ? u"deck_building"_s : u"draft"_s},
         {u"product"_s, m_product},
         {u"packRound"_s, m_round},
         {u"direction"_s, m_round == 2 ? -1 : 1},
         {u"participants"_s, participants},
         {u"currentPack"_s, m_packs.first()},
         {u"pool"_s, m_pools.first()},
         {u"deckSubmitted"_s, m_saved},
         {u"mainboardInstanceIds"_s, m_savedIds},
         {u"basicLands"_s, m_savedBasics}}));
}

void DraftSimulator::reset()
{
    m_unopenedPacks.clear();
    m_packs.clear();
    m_pools.clear();
    m_constructionDraft.clear();
    m_savedIds.clear();
    m_savedBasics.clear();
    m_product.clear();
    m_sessionId.clear();
    m_round = 0;
    m_finished = false;
    m_saved = false;
    clearError();
    m_state.clear();
}

} // namespace hexproof::client
