// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "GameSessionState.h"

#include "protocol/Message.h"

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
    m_gameNumber = snapshot.value(u"gameNumber"_s).toInt();
    m_startingSeat = snapshot.value(u"startingSeat"_s, -1).toInt();
    m_turnOrder = snapshot.value(u"turnOrder"_s).toList();
    m_activeSeat = snapshot.value(u"activeSeat"_s, -1).toInt();
    m_currentPhase = snapshot.value(u"currentPhase"_s, kGamePhaseUntap).toString();
    m_seats = snapshot.value(u"seats"_s).toList();
    m_stack = snapshot.value(u"stack"_s).toList();
    m_revealed = snapshot.value(u"revealed"_s).toList();
    m_arrows = snapshot.value(u"arrows"_s).toList();
    m_attachments = snapshot.value(u"attachments"_s).toList();
    m_log = snapshot.value(u"log"_s).toList();
    m_score = snapshot.value(u"score"_s).toList();
    m_drawnGames = snapshot.value(u"drawnGames"_s).toInt();
    m_result = snapshot.value(u"result"_s).toMap();
    m_sideboard = snapshot.value(u"sideboard"_s).toMap();
    emit snapshotDataChanged(snapshot);
    emit snapshotChanged();
}

void GameSessionState::clear()
{
    m_gameNumber = 0;
    m_startingSeat = -1;
    m_turnOrder.clear();
    m_activeSeat = -1;
    m_currentPhase.clear();
    m_seats.clear();
    m_stack.clear();
    m_revealed.clear();
    m_arrows.clear();
    m_attachments.clear();
    m_log.clear();
    m_score.clear();
    m_drawnGames = 0;
    m_result.clear();
    m_sideboard.clear();
    emit snapshotDataChanged({});
    emit snapshotChanged();
}

} // namespace hexproof::client
