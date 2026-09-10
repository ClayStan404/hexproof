// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "LimitedSessionState.h"
#include "TournamentSessionState.h"
#include "WsClient.h"

#include <QJsonArray>
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

QString WsClient::sendTournamentChat(const QString &text)
{
    if (!connected() || !m_tournamentSession->inTournament() || text.trimmed().isEmpty())
        return {};
    return send(kTypeTournamentChatSend,
                QJsonObject{{u"tournamentId"_s, m_tournamentSession->tournamentId()},
                            {u"text"_s, text.trimmed()}});
}

void WsClient::createTournament(const QString &name, const QString &format,
                                const QString &matchMode, int roundMinutes, int maxPlayers)
{
    QJsonObject payload{
        {u"name"_s, name},
        {u"format"_s, format},
        {u"matchMode"_s, matchMode},
        {u"roundMinutes"_s, roundMinutes},
        {u"maxPlayers"_s, maxPlayers},
    };
    send(kTypeTournamentCreate, payload);
}

void WsClient::createLimitedTournament(const QString &name, const QString &eventType,
                                       const QString &matchMode, int roundMinutes, int maxPlayers,
                                       const QVariantMap &product)
{
    QJsonObject payload{
        {u"name"_s, name},
        {u"format"_s, eventType == kLimitedEventCubeDraft ? u"Cube"_s : u"Limited"_s},
        {u"eventType"_s, eventType},
        {u"matchMode"_s, matchMode},
        {u"roundMinutes"_s, roundMinutes},
        {u"maxPlayers"_s, maxPlayers},
        {u"product"_s, QJsonObject::fromVariantMap(product)},
    };
    send(kTypeTournamentCreate, payload);
}

void WsClient::createCasualLimitedEvent(const QString &name, const QString &eventType,
                                        const QString &matchMode, int maxPlayers,
                                        const QVariantMap &product)
{
    QJsonObject payload{
        {u"name"_s, name},
        {u"format"_s, eventType == kLimitedEventCubeDraft ? u"Cube"_s : u"Limited"_s},
        {u"eventType"_s, eventType},
        {u"coordinator"_s, kLimitedCoordinatorCasual},
        {u"matchMode"_s, matchMode},
        {u"roundMinutes"_s, 50},
        {u"maxPlayers"_s, maxPlayers},
        {u"product"_s, QJsonObject::fromVariantMap(product)},
    };
    send(kTypeTournamentCreate, payload);
}

void WsClient::createLimitedCasualMatch(const QString &playerAId, const QString &playerBId)
{
    if (playerAId.isEmpty() || playerBId.isEmpty() || playerAId == playerBId)
        return;
    send(kTypeLimitedCreateCasualMatch,
         QJsonObject{{u"playerAId"_s, playerAId}, {u"playerBId"_s, playerBId}});
}

void WsClient::cancelLimitedCasualMatch(const QString &playerAId, const QString &playerBId)
{
    if (playerAId.isEmpty() || playerBId.isEmpty() || playerAId == playerBId)
        return;
    send(kTypeLimitedCreateCasualMatch, QJsonObject{{u"playerAId"_s, playerAId},
                                                    {u"playerBId"_s, playerBId},
                                                    {u"action"_s, u"cancel"_s}});
}

void WsClient::pickLimitedCard(const QString &instanceId)
{
    if (!instanceId.isEmpty())
        send(kTypeLimitedPick, QJsonObject{{u"instanceId"_s, instanceId}});
}

void WsClient::pickLimitedCards(const QVariantList &instanceIds)
{
    if (!instanceIds.isEmpty() && instanceIds.size() <= 2)
        send(kTypeLimitedPick,
             QJsonObject{{u"instanceIds"_s, QJsonArray::fromVariantList(instanceIds)}});
}

void WsClient::setLimitedDraftControl(const QString &participantId, bool automatic)
{
    if (!participantId.isEmpty())
        send(kTypeLimitedSetDraftControl,
             QJsonObject{{u"participantId"_s, participantId}, {u"automatic"_s, automatic}});
}

void WsClient::setLimitedParticipation(bool participating)
{
    send(kTypeLimitedSetParticipation, QJsonObject{{u"participating"_s, participating}});
}

void WsClient::inviteCommanderCubePlayers(const QVariantList &playerIds)
{
    if (playerIds.size() >= 2 && playerIds.size() <= 4)
        send(kTypeLimitedCreateCasualMatch,
             QJsonObject{{u"action"_s, u"invite"_s},
                         {u"playerIds"_s, QJsonArray::fromVariantList(playerIds)}});
}

void WsClient::respondCommanderCubeInvitation(const QString &pairingId, bool accept)
{
    if (!pairingId.isEmpty())
        send(kTypeLimitedCreateCasualMatch,
             QJsonObject{{u"pairingId"_s, pairingId},
                         {u"action"_s, accept ? u"accept"_s : u"cancel"_s}});
}

void WsClient::submitLimitedCommanderDeck(const QString &name,
                                          const QVariantList &mainboardInstanceIds,
                                          const QVariantList &basicLands,
                                          const QVariantList &commanderInstanceIds,
                                          const QVariantList &commanderColors)
{
    send(kTypeLimitedSubmitDeck,
         QJsonObject{{u"name"_s, name},
                     {u"mainboardInstanceIds"_s, QJsonArray::fromVariantList(mainboardInstanceIds)},
                     {u"basicLands"_s, QJsonArray::fromVariantList(basicLands)},
                     {u"commanderInstanceIds"_s, QJsonArray::fromVariantList(commanderInstanceIds)},
                     {u"commanderColors"_s, QJsonArray::fromVariantList(commanderColors)}});
}

void WsClient::submitLimitedDeck(const QString &name, const QVariantList &mainboardInstanceIds,
                                 const QVariantList &basicLands)
{
    send(kTypeLimitedSubmitDeck,
         QJsonObject{{u"name"_s, name},
                     {u"mainboardInstanceIds"_s, QJsonArray::fromVariantList(mainboardInstanceIds)},
                     {u"basicLands"_s, QJsonArray::fromVariantList(basicLands)}});
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
        m_limitedSession->clear();
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
