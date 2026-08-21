// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "TournamentSessionState.h"
#include "WsClient.h"

#include <QJsonObject>

namespace hexproof::client {

namespace {
using namespace hexproof::protocol;
using namespace Qt::StringLiterals;
} // namespace

void WsClient::requestTournamentList()
{
    send(kTypeTournamentList);
}

void WsClient::createTournament(const QString &name, const QString &format,
                                const QString &matchMode, int roundMinutes, int maxPlayers,
                                int plannedRounds)
{
    QJsonObject payload{
        {u"name"_s, name},
        {u"format"_s, format},
        {u"matchMode"_s, matchMode},
        {u"roundMinutes"_s, roundMinutes},
        {u"maxPlayers"_s, maxPlayers},
    };
    if (plannedRounds > 0)
        payload.insert(u"plannedRounds"_s, plannedRounds);
    send(kTypeTournamentCreate, payload);
}

void WsClient::enterTournament(const QString &tournamentId)
{
    const QString normalizedId = tournamentId.trimmed().toUpper();
    QJsonObject payload{{u"tournamentId"_s, normalizedId}};
    const QString credential = tournamentCredential(normalizedId);
    if (!credential.isEmpty())
        payload.insert(u"credential"_s, credential);
    send(kTypeTournamentEnter, payload);
}

void WsClient::leaveTournament()
{
    if (!connected()) {
        m_tournamentSession->clear();
        return;
    }
    send(kTypeTournamentLeave);
}

void WsClient::registerTournament()
{
    if (!m_tournamentSession->inTournament())
        return;
    send(kTypeTournamentRegister,
         QJsonObject{{u"tournamentId"_s, m_tournamentSession->tournamentId()}});
}

void WsClient::unregisterTournament(const QString &participantId)
{
    QJsonObject payload;
    if (!participantId.isEmpty())
        payload.insert(u"participantId"_s, participantId);
    send(kTypeTournamentUnregister, payload);
}

void WsClient::setTournamentCheckedIn(bool checkedIn, const QString &participantId)
{
    QJsonObject payload{{u"checkedIn"_s, checkedIn}};
    if (!participantId.isEmpty())
        payload.insert(u"participantId"_s, participantId);
    send(kTypeTournamentCheckIn, payload);
}

void WsClient::startTournament()
{
    send(kTypeTournamentStart);
}

void WsClient::dropTournament(const QString &participantId)
{
    QJsonObject payload;
    if (!participantId.isEmpty())
        payload.insert(u"participantId"_s, participantId);
    send(kTypeTournamentDrop, payload);
}

void WsClient::reportTournamentResult(const QString &pairingId, int playerAWins, int playerBWins,
                                      int drawnGames)
{
    send(kTypeTournamentReportResult, QJsonObject{
                                          {u"pairingId"_s, pairingId},
                                          {u"playerAWins"_s, playerAWins},
                                          {u"playerBWins"_s, playerBWins},
                                          {u"drawnGames"_s, drawnGames},
                                      });
}

void WsClient::confirmTournamentResult(const QString &pairingId)
{
    send(kTypeTournamentConfirmResult, QJsonObject{{u"pairingId"_s, pairingId}});
}

void WsClient::rejectTournamentResult(const QString &pairingId)
{
    send(kTypeTournamentRejectResult, QJsonObject{{u"pairingId"_s, pairingId}});
}

void WsClient::correctTournamentResult(const QString &pairingId, int playerAWins, int playerBWins,
                                       int drawnGames)
{
    send(kTypeTournamentCorrectResult, QJsonObject{
                                           {u"pairingId"_s, pairingId},
                                           {u"playerAWins"_s, playerAWins},
                                           {u"playerBWins"_s, playerBWins},
                                           {u"drawnGames"_s, drawnGames},
                                       });
}

void WsClient::startNextTournamentRound()
{
    send(kTypeTournamentNextRound);
}

void WsClient::openTournamentMatch(const QString &pairingId)
{
    send(kTypeTournamentOpenMatch, QJsonObject{{u"pairingId"_s, pairingId}});
}

void WsClient::cancelTournament()
{
    send(kTypeTournamentCancel);
}

} // namespace hexproof::client
