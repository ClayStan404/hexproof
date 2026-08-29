// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "TournamentSessionState.h"

#include <QJsonArray>
#include <QVariantMap>

namespace hexproof::client {

using namespace Qt::StringLiterals;

namespace {

QVariantList arrayToVariantList(const QJsonValue &value)
{
    QVariantList result;
    for (const QJsonValue &entry : value.toArray())
        result.append(entry.toObject().toVariantMap());
    return result;
}
} // namespace

TournamentSessionState::TournamentSessionState(QObject *parent)
    : QObject(parent)
{
}

void TournamentSessionState::rememberTabletopScore(const QString &roomId, const QVariantList &seats,
                                                   int drawnGames)
{
    if (roomId.isEmpty())
        return;
    QVariantMap entry;
    entry.insert(u"roomId"_s, roomId);
    entry.insert(u"seats"_s, seats);
    entry.insert(u"drawnGames"_s, drawnGames);
    m_tabletopScores.insert(roomId, entry);
}

QVariantMap TournamentSessionState::tabletopScoreForRoom(const QString &roomId) const
{
    return m_tabletopScores.value(roomId);
}

void TournamentSessionState::applyList(const QJsonObject &payload)
{
    m_tournamentList = arrayToVariantList(payload.value(u"tournaments"_s));
    emit tournamentListChanged();
}

void TournamentSessionState::enter(const QString &tournamentId, const QString &role,
                                   const QString &participantId)
{
    const bool wasInTournament = inTournament();
    m_tournamentId = tournamentId;
    m_role = role;
    m_participantId = participantId;
    if (!wasInTournament)
        emit inTournamentChanged();
    emit snapshotChanged();
}

void TournamentSessionState::applyRegistration(const QString &participantId)
{
    m_participantId = participantId;
    if (m_role != u"organizer"_s)
        m_role = u"participant"_s;
    emit snapshotChanged();
}

void TournamentSessionState::applySnapshot(const QJsonObject &payload)
{
    const bool wasInTournament = inTournament();
    m_tournamentId = payload.value(u"tournamentId"_s).toString(m_tournamentId);
    m_name = payload.value(u"name"_s).toString();
    m_format = payload.value(u"format"_s).toString();
    m_eventType = payload.value(u"eventType"_s).toString();
    m_coordinator = payload.value(u"coordinator"_s).toString(u"swiss"_s);
    m_stage = payload.value(u"stage"_s).toString();
    m_matchMode = payload.value(u"matchMode"_s).toString();
    m_status = payload.value(u"status"_s).toString();
    m_role = payload.value(u"role"_s).toString();
    m_participantId = payload.value(u"participantId"_s).toString();
    m_organizerName = payload.value(u"organizerName"_s).toString();
    m_roundMinutes = payload.value(u"roundMinutes"_s).toInt();
    m_roundStartedAt = payload.value(u"roundStartedAt"_s).toString();
    m_maxPlayers = payload.value(u"maxPlayers"_s).toInt();
    m_plannedRounds = payload.value(u"plannedRounds"_s).toInt();
    m_currentRound = payload.value(u"currentRound"_s).toInt();
    m_registered = payload.value(u"registered"_s).toInt();
    m_checkedIn = payload.value(u"checkedIn"_s).toInt();
    m_roundComplete = payload.value(u"roundComplete"_s).toBool();
    m_canRegister = payload.value(u"canRegister"_s).toBool();
    m_participants = arrayToVariantList(payload.value(u"participants"_s));
    m_pairings = arrayToVariantList(payload.value(u"pairings"_s));
    m_standings = arrayToVariantList(payload.value(u"standings"_s));
    if (!wasInTournament && inTournament())
        emit inTournamentChanged();
    emit snapshotChanged();
}

void TournamentSessionState::clear()
{
    const bool wasInTournament = inTournament();
    m_tournamentId.clear();
    m_name.clear();
    m_format.clear();
    m_eventType.clear();
    m_coordinator.clear();
    m_stage.clear();
    m_matchMode.clear();
    m_status.clear();
    m_role.clear();
    m_participantId.clear();
    m_organizerName.clear();
    m_roundMinutes = 0;
    m_roundStartedAt.clear();
    m_maxPlayers = 0;
    m_plannedRounds = 0;
    m_currentRound = 0;
    m_registered = 0;
    m_checkedIn = 0;
    m_roundComplete = false;
    m_canRegister = false;
    m_participants.clear();
    m_pairings.clear();
    m_standings.clear();
    m_tabletopScores.clear();
    if (wasInTournament)
        emit inTournamentChanged();
    emit snapshotChanged();
}

} // namespace hexproof::client
