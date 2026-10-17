// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "TournamentSessionState.h"

#include <QJsonArray>
#include <QSignalBlocker>
#include <QVariantMap>

#include <utility>

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
    if (roomId.isEmpty() || !inTournament() || m_participantId.isEmpty())
        return;
    for (const QVariant &value : std::as_const(m_pairings)) {
        const QVariantMap pairing = value.toMap();
        const QString pairingId = pairing.value(u"pairingId"_s).toString();
        const QString playerA = pairing.value(u"playerAId"_s).toString();
        const QString playerB = pairing.value(u"playerBId"_s).toString();
        if (pairingId.isEmpty() || playerA.isEmpty() || playerB.isEmpty() ||
            (m_participantId != playerA && m_participantId != playerB) ||
            pairing.value(u"roomId"_s).toString() != roomId) {
            continue;
        }
        m_tabletopScores.insert(pairingId, {{u"tournamentId"_s, m_tournamentId},
                                            {u"pairingId"_s, pairingId},
                                            {u"participantId"_s, m_participantId},
                                            {u"currentRound"_s, m_currentRound},
                                            {u"playerAId"_s, playerA},
                                            {u"playerBId"_s, playerB},
                                            {u"roomId"_s, roomId},
                                            {u"seats"_s, seats},
                                            {u"drawnGames"_s, drawnGames}});
        return;
    }
}

bool TournamentSessionState::tabletopScoreMatchesPairing(const QVariantMap &score,
                                                         const QVariantMap &pairing) const
{
    if (score.isEmpty() || m_participantId.isEmpty() ||
        score.value(u"tournamentId"_s).toString() != m_tournamentId ||
        score.value(u"participantId"_s).toString() != m_participantId ||
        score.value(u"currentRound"_s).toInt() != m_currentRound ||
        score.value(u"playerAId"_s) != pairing.value(u"playerAId"_s) ||
        score.value(u"playerBId"_s) != pairing.value(u"playerBId"_s)) {
        return false;
    }
    const QString roomId = pairing.value(u"roomId"_s).toString();
    return roomId.isEmpty() || roomId == score.value(u"roomId"_s).toString();
}

QVariantMap TournamentSessionState::tabletopScoreForPairing(const QString &pairingId) const
{
    const QVariantMap score = m_tabletopScores.value(pairingId);
    for (const QVariant &value : m_pairings) {
        const QVariantMap pairing = value.toMap();
        if (pairing.value(u"pairingId"_s).toString() == pairingId)
            return tabletopScoreMatchesPairing(score, pairing) ? score : QVariantMap{};
    }
    return {};
}

void TournamentSessionState::applyList(const QJsonObject &payload)
{
    m_tournamentList = arrayToVariantList(payload.value(u"tournaments"_s));
    m_activeTournamentList.clear();
    m_historicalTournamentList.clear();
    for (const QVariant &entry : std::as_const(m_tournamentList)) {
        const QString status = entry.toMap().value(u"status"_s).toString();
        if (status == u"completed"_s || status == u"cancelled"_s)
            m_historicalTournamentList.append(entry);
        else
            m_activeTournamentList.append(entry);
    }
    emit tournamentListChanged();
}

void TournamentSessionState::enter(const QString &tournamentId, const QString &role,
                                   const QString &participantId)
{
    const bool wasInTournament = inTournament();
    if (tournamentId != m_tournamentId) {
        // Do not route a new session using the previous lobby's kind or stage.
        {
            const QSignalBlocker blocker(this);
            clear();
        }
        emit chatChanged();
    }
    m_tournamentId = tournamentId;
    m_role = role;
    if (m_participantId != participantId)
        m_tabletopScores.clear();
    m_participantId = participantId;
    if (!wasInTournament)
        emit inTournamentChanged();
    emit snapshotChanged();
}

void TournamentSessionState::applyRegistration(const QString &participantId)
{
    if (m_participantId != participantId)
        m_tabletopScores.clear();
    m_participantId = participantId;
    if (m_role != u"organizer"_s)
        m_role = u"participant"_s;
    emit snapshotChanged();
}

void TournamentSessionState::applySnapshot(const QJsonObject &payload)
{
    const bool wasInTournament = inTournament();
    if (payload.value(u"tournamentId"_s).toString(m_tournamentId) != m_tournamentId ||
        payload.value(u"participantId"_s).toString() != m_participantId ||
        payload.value(u"currentRound"_s).toInt() != m_currentRound) {
        m_tabletopScores.clear();
    }
    m_tournamentId = payload.value(u"tournamentId"_s).toString(m_tournamentId);
    m_name = payload.value(u"name"_s).toString();
    m_format = payload.value(u"format"_s).toString();
    m_eventType = payload.value(u"eventType"_s).toString();
    m_coordinator = payload.value(u"coordinator"_s).toString(u"swiss"_s);
    m_stage = payload.value(u"stage"_s).toString();
    m_matchMode = payload.value(u"matchMode"_s).toString();
    m_rulesMode = payload.value(u"rulesMode"_s).toString(u"manual"_s);
    m_actionClockEnabled = payload.value(u"actionClockEnabled"_s)
                               .toBool(m_rulesMode == u"forge"_s &&
                                       (m_eventType.isEmpty() || m_eventType == u"constructed"_s));
    m_status = payload.value(u"status"_s).toString();
    m_role = payload.value(u"role"_s).toString();
    m_participantId = payload.value(u"participantId"_s).toString();
    m_organizerName = payload.value(u"organizerName"_s).toString();
    m_roundMinutes = payload.value(u"roundMinutes"_s).toInt();
    m_roundStartedAt = payload.value(u"roundStartedAt"_s).toString();
    m_maxPlayers = payload.value(u"maxPlayers"_s).toInt();
    m_minimumPlayers = payload.value(u"minimumPlayers"_s).toInt();
    m_plannedRounds = payload.value(u"plannedRounds"_s).toInt();
    m_currentRound = payload.value(u"currentRound"_s).toInt();
    m_registered = payload.value(u"registered"_s).toInt();
    m_checkedIn = payload.value(u"checkedIn"_s).toInt();
    m_roundComplete = payload.value(u"roundComplete"_s).toBool();
    m_canRegister = payload.value(u"canRegister"_s).toBool();
    m_product = payload.value(u"product"_s).toObject().toVariantMap();
    m_draftSettings = payload.value(u"draftSettings"_s).toObject().toVariantMap();
    m_participants = arrayToVariantList(payload.value(u"participants"_s));
    m_pairings = arrayToVariantList(payload.value(u"pairings"_s));
    // Closed room IDs disappear from event snapshots. Keep their completed
    // suggestion only while the same pairing and participant scope survives.
    for (auto entry = m_tabletopScores.begin(); entry != m_tabletopScores.end();) {
        if (tabletopScoreForPairing(entry.key()).isEmpty())
            entry = m_tabletopScores.erase(entry);
        else
            ++entry;
    }
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
    m_rulesMode = u"manual"_s;
    m_actionClockEnabled = false;
    m_status.clear();
    m_role.clear();
    m_participantId.clear();
    m_organizerName.clear();
    m_roundMinutes = 0;
    m_roundStartedAt.clear();
    m_maxPlayers = 0;
    m_minimumPlayers = 0;
    m_plannedRounds = 0;
    m_currentRound = 0;
    m_registered = 0;
    m_checkedIn = 0;
    m_roundComplete = false;
    m_canRegister = false;
    m_product.clear();
    m_draftSettings.clear();
    m_participants.clear();
    m_pairings.clear();
    m_standings.clear();
    m_chatMessages.clear();
    emit chatChanged();
    m_tabletopScores.clear();
    if (wasInTournament)
        emit inTournamentChanged();
    emit snapshotChanged();
}

void TournamentSessionState::applyChatMessage(const QJsonObject &payload)
{
    if (!inTournament() || payload.value(u"tournamentId"_s).toString() != m_tournamentId)
        return;
    const int sequence = payload.value(u"sequence"_s).toInt();
    if (sequence <= 0)
        return;
    qsizetype position = 0;
    while (position < m_chatMessages.size()) {
        const int existing = m_chatMessages.at(position).toMap().value(u"sequence"_s).toInt();
        if (existing == sequence)
            return;
        if (existing > sequence)
            break;
        ++position;
    }
    m_chatMessages.insert(position, payload.toVariantMap());
    while (m_chatMessages.size() > 100)
        m_chatMessages.removeFirst();
    emit chatChanged();
}

void TournamentSessionState::applyChatHistory(const QJsonObject &payload)
{
    if (payload.value(u"tournamentId"_s).toString() != m_tournamentId)
        return;
    const QVariantList previous = m_chatMessages;
    {
        const QSignalBlocker blocker(this);
        for (const QJsonValue &value : payload.value(u"messages"_s).toArray())
            applyChatMessage(value.toObject());
    }
    if (previous != m_chatMessages)
        emit chatChanged();
}

} // namespace hexproof::client
