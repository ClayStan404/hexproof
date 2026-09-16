// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "LimitedSessionState.h"

#include <QJsonArray>

namespace hexproof::client {

using namespace Qt::StringLiterals;

namespace {
QVariantList objectArray(const QJsonValue &value)
{
    QVariantList result;
    const QJsonArray array = value.toArray();
    result.reserve(array.size());
    for (const QJsonValue &entry : array)
        result.append(entry.toObject().toVariantMap());
    return result;
}

QVariantList stringArray(const QJsonValue &value)
{
    QVariantList result;
    const QJsonArray array = value.toArray();
    result.reserve(array.size());
    for (const QJsonValue &entry : array)
        result.append(entry.toString());
    return result;
}
} // namespace

LimitedSessionState::LimitedSessionState(QObject *parent)
    : QObject(parent)
{
}

void LimitedSessionState::applySnapshot(const QJsonObject &payload)
{
    const auto update = [](auto &current, const auto &next) {
        if (current == next)
            return false;
        current = next;
        return true;
    };
    // Evaluate every update before notifying: listeners must see a coherent snapshot.
    bool header = update(m_tournamentId, payload.value(u"tournamentId"_s).toString());
    header |= update(m_eventType, payload.value(u"eventType"_s).toString());
    header |= update(m_stage, payload.value(u"stage"_s).toString());
    header |= update(m_product, payload.value(u"product"_s).toObject().toVariantMap());
    header |= update(m_packRound, payload.value(u"packRound"_s).toInt());
    header |= update(m_packsThisBatch, payload.value(u"packsThisBatch"_s).toInt(1));
    header |= update(m_direction, payload.value(u"direction"_s).toInt(1));
    header |= update(m_allDecksSubmitted, payload.value(u"allDecksSubmitted"_s).toBool());
    header |= update(m_minimumDeckCards,
                     payload.value(u"minimumDeckCards"_s).toInt(commanderDraft() ? 60 : 40));
    header |= update(m_packsPerPlayer, payload.value(u"packsPerPlayer"_s).toInt(3));
    bool pack = update(m_currentPack, objectArray(payload.value(u"currentPack"_s)));
    pack |= update(m_currentPacks, objectArray(payload.value(u"currentPacks"_s)));
    pack |= update(m_picksRequired,
                   payload.value(u"picksRequired"_s)
                       .toInt(m_currentPack.isEmpty() ? 0 : (commanderDraft() ? 2 : 1)));
    const bool pool = update(m_pool, objectArray(payload.value(u"pool"_s)));
    bool deck =
        update(m_mainboardInstanceIds, stringArray(payload.value(u"mainboardInstanceIds"_s)));
    deck |= update(m_basicLands, objectArray(payload.value(u"basicLands"_s)));
    deck |= update(m_commanderInstanceIds, stringArray(payload.value(u"commanderInstanceIds"_s)));
    deck |= update(m_fallbackCommanders, objectArray(payload.value(u"fallbackCommanders"_s)));
    deck |= update(m_optionalCards, objectArray(payload.value(u"optionalCards"_s)));
    deck |= update(m_commanderColors, objectArray(payload.value(u"commanderColors"_s)));
    deck |= update(m_deckSubmitted, payload.value(u"deckSubmitted"_s).toBool());
    const bool participants = update(m_participants, objectArray(payload.value(u"participants"_s)));
    if (header)
        emit headerChanged();
    if (pack)
        emit packChanged();
    if (pool)
        emit poolChanged();
    if (deck)
        emit deckChanged();
    if (participants)
        emit participantsChanged();
    if (header || pack || pool || deck || participants)
        emit snapshotChanged();
}

void LimitedSessionState::applyProgress(const QJsonObject &payload)
{
    if (!active() || payload.value(u"tournamentId"_s).toString() != m_tournamentId ||
        !payload.value(u"participants"_s).isArray())
        return;
    const QVariantList participants = objectArray(payload.value(u"participants"_s));
    if (participants == m_participants)
        return;
    m_participants = participants;
    emit participantsChanged();
    emit snapshotChanged();
}

void LimitedSessionState::clear()
{
    if (active())
        applySnapshot({});
}

} // namespace hexproof::client
