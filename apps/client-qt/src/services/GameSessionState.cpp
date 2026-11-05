// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "GameSessionState.h"

#include "protocol/Message.h"

#include <QScopedValueRollback>

namespace hexproof::client {

namespace {
using namespace hexproof::protocol;
using namespace Qt::StringLiterals;
} // namespace

GameSessionState::GameSessionState(QObject *parent)
    : QObject(parent)
{
}

void GameSessionState::applySnapshot(const QVariantMap &snapshot)
{
    publishUpdate(UpdateKind::Snapshot, snapshot);
}

void GameSessionState::clearSideboard()
{
    publishUpdate(UpdateKind::ClearSideboard);
}

void GameSessionState::clear()
{
    publishUpdate(UpdateKind::Clear);
}

void GameSessionState::publishUpdate(UpdateKind kind, const QVariantMap &snapshot)
{
    m_pendingUpdates.enqueue({kind, snapshot});
    if (m_publishing)
        return;
    QScopedValueRollback<bool> publishing(m_publishing, true);
    while (!m_pendingUpdates.isEmpty()) {
        const PendingUpdate update = m_pendingUpdates.dequeue();
        const QVariantMap &data = update.snapshot;
        if (update.kind == UpdateKind::ClearSideboard) {
            if (m_sideboard.isEmpty())
                continue;
            m_sideboard.clear();
        } else {
            m_gameNumber = data.value(u"gameNumber"_s).toInt();
            m_startingSeat = data.value(u"startingSeat"_s, -1).toInt();
            m_turnOrder = data.value(u"turnOrder"_s).toList();
            m_activeSeat = data.value(u"activeSeat"_s, -1).toInt();
            m_currentPhase = update.kind == UpdateKind::Clear
                                 ? QString{}
                                 : data.value(u"currentPhase"_s, kGamePhaseUntap).toString();
            m_seats = data.value(u"seats"_s).toList();
            m_stack = data.value(u"stack"_s).toList();
            m_revealed = data.value(u"revealed"_s).toList();
            m_arrows = data.value(u"arrows"_s).toList();
            m_attachments = data.value(u"attachments"_s).toList();
            m_log = data.value(u"log"_s).toList();
            m_score = data.value(u"score"_s).toList();
            m_drawnGames = data.value(u"drawnGames"_s).toInt();
            m_result = data.value(u"result"_s).toMap();
            m_sideboard = data.value(u"sideboard"_s).toMap();
            emit snapshotDataChanged(data);
        }
        emit snapshotChanged();
        emit snapshotCommitted();
    }
}

} // namespace hexproof::client
