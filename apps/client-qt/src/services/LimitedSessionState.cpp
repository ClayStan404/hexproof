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
    m_tournamentId = payload.value(u"tournamentId"_s).toString();
    m_eventType = payload.value(u"eventType"_s).toString();
    m_stage = payload.value(u"stage"_s).toString();
    m_product = payload.value(u"product"_s).toObject().toVariantMap();
    m_packRound = payload.value(u"packRound"_s).toInt();
    m_direction = payload.value(u"direction"_s).toInt(1);
    m_currentPack = objectArray(payload.value(u"currentPack"_s));
    m_pool = objectArray(payload.value(u"pool"_s));
    m_mainboardInstanceIds = stringArray(payload.value(u"mainboardInstanceIds"_s));
    m_basicLands = objectArray(payload.value(u"basicLands"_s));
    m_participants = objectArray(payload.value(u"participants"_s));
    m_deckSubmitted = payload.value(u"deckSubmitted"_s).toBool();
    m_allDecksSubmitted = payload.value(u"allDecksSubmitted"_s).toBool();
    emit snapshotChanged();
}

void LimitedSessionState::clear()
{
    if (!active())
        return;
    m_tournamentId.clear();
    m_eventType.clear();
    m_stage.clear();
    m_product.clear();
    m_packRound = 0;
    m_direction = 1;
    m_currentPack.clear();
    m_pool.clear();
    m_mainboardInstanceIds.clear();
    m_basicLands.clear();
    m_participants.clear();
    m_deckSubmitted = false;
    m_allDecksSubmitted = false;
    emit snapshotChanged();
}

} // namespace hexproof::client
