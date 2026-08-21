// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "RoomSessionState.h"

#include "protocol/Message.h"

#include <QJsonArray>

namespace hexproof::client {

namespace {
using namespace hexproof::protocol;
using namespace Qt::StringLiterals;
} // namespace

RoomSessionState::RoomSessionState(QObject *parent)
    : QObject(parent),
      m_cardLoadMode(kCardLoadPreload)
{
}

void RoomSessionState::enter(const QString &roomId, const QString &role, int seatIndex, bool host)
{
    m_roomId = roomId;
    m_role = role;
    m_seatIndex = seatIndex;
    m_host = host;
    m_pendingEntry = true;
    emit roomIdChanged();
    emit roleChanged();
    emit hostChanged();
}

RoomSessionState::SnapshotTransition
RoomSessionState::applySnapshot(const QJsonObject &snapshot)
{
    const QString previousPhase = m_phase;
    m_roomName = snapshot.value(u"name"_s).toString();
    m_format = snapshot.value(u"format"_s).toString();
    m_deckFormat = snapshot.value(u"deckFormat"_s).toString();
    m_playtest = snapshot.value(u"playtest"_s).toBool();
    m_matchMode = snapshot.value(u"matchMode"_s).toString(kMatchBO1);
    m_cardLoadMode = snapshot.value(u"cardLoadMode"_s).toString(kCardLoadPreload);
    m_maxSeats = snapshot.value(u"maxSeats"_s).toInt();
    m_phase = snapshot.value(u"phase"_s).toString(kRoomPhaseWaiting);
    m_loadId =
        m_phase == kRoomPhaseWaiting ? 0 : snapshot.value(u"loadId"_s).toInteger();

    QVariantList seats;
    const QJsonArray seatArray = snapshot.value(u"seats"_s).toArray();
    for (const QJsonValue &value : seatArray) {
        const QJsonObject seat = value.toObject();
        seats.append(QVariantMap{
            {u"occupied"_s, seat.value(u"occupied"_s).toBool()},
            {u"displayName"_s, seat.value(u"displayName"_s).toString()},
            {u"host"_s, seat.value(u"host"_s).toBool()},
            {u"deckSelected"_s, seat.value(u"deckSelected"_s).toBool()},
            {u"ready"_s, seat.value(u"ready"_s).toBool()},
            {u"loaded"_s, seat.value(u"loaded"_s).toBool()},
        });
    }
    m_seats = seats;

    const bool snapshotHost =
        m_role == kRolePlayer && m_seatIndex >= 0 && m_seatIndex < seatArray.size() &&
        seatArray.at(m_seatIndex).toObject().value(u"host"_s).toBool();
    if (m_host != snapshotHost) {
        m_host = snapshotHost;
        emit hostChanged();
    }

    QVariantList spectators;
    for (const QJsonValue &value : snapshot.value(u"spectators"_s).toArray()) {
        spectators.append(
            QVariantMap{{u"displayName"_s, value.toObject().value(u"displayName"_s).toString()}});
    }
    m_spectators = spectators;

    SnapshotTransition transition;
    transition.loadCancelled =
        (previousPhase == kRoomPhaseLoading ||
         (previousPhase == kRoomPhaseStarted && m_cardLoadMode == kCardLoadBackground)) &&
        m_phase == kRoomPhaseWaiting;
    transition.returnedToRoom =
        previousPhase == kRoomPhaseStarted && m_phase == kRoomPhaseWaiting;
    if (transition.loadCancelled)
        m_announcedLoadId = 0;
    emit snapshotChanged();
    return transition;
}

bool RoomSessionState::applyLoadRequired(qint64 loadId)
{
    if (loadId <= 0 || loadId == m_announcedLoadId)
        return false;
    m_announcedLoadId = loadId;
    m_loadId = loadId;
    if (m_cardLoadMode == kCardLoadPreload)
        m_phase = kRoomPhaseLoading;
    emit snapshotChanged();
    return true;
}

void RoomSessionState::applyMatchStarted(qint64 loadId)
{
    m_loadId = loadId;
    m_phase = kRoomPhaseStarted;
    m_announcedLoadId = loadId;
    emit snapshotChanged();
}

bool RoomSessionState::completePendingEntry()
{
    if (!m_pendingEntry)
        return false;
    m_pendingEntry = false;
    return true;
}

void RoomSessionState::rememberPendingDeck(const QString &requestId, const QString &deckName)
{
    m_pendingDeckNames.insert(requestId, deckName);
}

QString RoomSessionState::takePendingDeck(const QString &requestId)
{
    const auto pending = m_pendingDeckNames.constFind(requestId);
    if (pending == m_pendingDeckNames.cend())
        return {};
    const QString deckName = *pending;
    m_pendingDeckNames.erase(pending);
    if (m_selectedDeckName == deckName)
        return {};
    m_selectedDeckName = deckName;
    emit selectedDeckNameChanged();
    return deckName;
}

void RoomSessionState::discardPendingDeck(const QString &requestId)
{
    m_pendingDeckNames.remove(requestId);
}

void RoomSessionState::clear()
{
    m_roomId.clear();
    m_roomName.clear();
    m_format.clear();
    m_deckFormat.clear();
    m_playtest = false;
    m_matchMode.clear();
    m_cardLoadMode = kCardLoadPreload;
    m_maxSeats = 0;
    m_phase.clear();
    m_loadId = 0;
    m_announcedLoadId = 0;
    m_host = false;
    m_role.clear();
    m_seatIndex = -1;
    m_pendingDeckNames.clear();
    if (!m_selectedDeckName.isEmpty()) {
        m_selectedDeckName.clear();
        emit selectedDeckNameChanged();
    }
    m_pendingEntry = false;
    m_seats.clear();
    m_spectators.clear();
    emit roomIdChanged();
    emit hostChanged();
    emit roleChanged();
    emit snapshotChanged();
}

} // namespace hexproof::client
