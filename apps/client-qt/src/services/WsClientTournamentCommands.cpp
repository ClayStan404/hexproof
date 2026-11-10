// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "LimitedSessionState.h"
#include "TournamentSessionState.h"
#include "WsClient.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUuid>

namespace hexproof::client {

namespace {
using namespace hexproof::protocol;
using namespace Qt::StringLiterals;
} // namespace

void WsClient::requestTournamentList()
{
    send(kTypeTournamentList);
}

void WsClient::resetTournamentCreation()
{
    m_tournamentCreatePayload.clear();
    m_tournamentCreateOperation.clear();
}

void WsClient::sendTournamentCreation(QJsonObject payload)
{
    const QByteArray encoded = QJsonDocument(payload).toJson(QJsonDocument::Compact);
    if (m_tournamentCreateOperation.isEmpty() || encoded != m_tournamentCreatePayload) {
        m_tournamentCreatePayload = encoded;
        m_tournamentCreateOperation = QUuid::createUuid().toString(QUuid::WithoutBraces);
    }
    payload.insert(u"operationId"_s, m_tournamentCreateOperation);
    send(kTypeTournamentCreate, payload);
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
                                const QString &matchMode, int roundMinutes, int maxPlayers,
                                const QString &rulesMode, bool actionClockEnabled)
{
    QJsonObject payload{
        {u"name"_s, name},
        {u"format"_s, format},
        {u"matchMode"_s, matchMode},
        {u"rulesMode"_s, rulesMode},
        {u"actionClockEnabled"_s, actionClockEnabled && rulesMode == kRulesModeForge},
        {u"roundMinutes"_s, roundMinutes},
        {u"maxPlayers"_s, maxPlayers},
    };
    sendTournamentCreation(payload);
}

void WsClient::createLimitedTournament(const QString &name, const QString &eventType,
                                       const QString &matchMode, int roundMinutes, int maxPlayers,
                                       const QVariantMap &product, const QString &rulesMode,
                                       bool actionClockEnabled)
{
    QJsonObject payload{
        {u"name"_s, name},
        {u"format"_s, eventType == kLimitedEventCubeDraft ? u"Cube"_s : u"Limited"_s},
        {u"eventType"_s, eventType},
        {u"matchMode"_s, matchMode},
        {u"rulesMode"_s, rulesMode},
        {u"actionClockEnabled"_s, actionClockEnabled && rulesMode == kRulesModeForge &&
                                      eventType != kLimitedEventCommanderCube},
        {u"roundMinutes"_s, roundMinutes},
        {u"maxPlayers"_s, maxPlayers},
        {u"product"_s, QJsonObject::fromVariantMap(product)},
    };
    sendTournamentCreation(payload);
}

void WsClient::createLimitedPlanTournament(const QString &name, const QString &eventType,
                                           const QString &matchMode, int roundMinutes,
                                           int maxPlayers, const QVariantMap &plan,
                                           const QString &rulesMode, bool actionClockEnabled)
{
    if (plan.isEmpty()) {
        setLastError(
            u"invalid_pack_plan"_s,
            u"The selected products are unavailable. Update the card database and select them again."_s);
        return;
    }
    if (QJsonDocument(QJsonObject::fromVariantMap(plan)).toJson(QJsonDocument::Compact).size() >
        800 * 1024) {
        setLastError(u"invalid_pack_plan"_s,
                     u"Combined products are too large. Choose fewer or smaller products."_s);
        return;
    }
    sendTournamentCreation(QJsonObject{
        {u"name"_s, name},
        {u"format"_s, u"Limited"_s},
        {u"eventType"_s, eventType},
        {u"matchMode"_s, matchMode},
        {u"rulesMode"_s, rulesMode},
        {u"actionClockEnabled"_s, actionClockEnabled && rulesMode == kRulesModeForge},
        {u"roundMinutes"_s, roundMinutes},
        {u"maxPlayers"_s, maxPlayers},
        {u"plan"_s, QJsonObject::fromVariantMap(plan)},
    });
}

void WsClient::createCasualLimitedEvent(const QString &name, const QString &eventType,
                                        const QString &matchMode, int maxPlayers,
                                        const QVariantMap &product,
                                        const QVariantMap &draftSettings, const QString &rulesMode,
                                        bool actionClockEnabled)
{
    QJsonObject payload{
        {u"name"_s, name},
        {u"format"_s, eventType == kLimitedEventCubeDraft ? u"Cube"_s : u"Limited"_s},
        {u"eventType"_s, eventType},
        {u"coordinator"_s, kLimitedCoordinatorCasual},
        {u"matchMode"_s, matchMode},
        {u"rulesMode"_s, rulesMode},
        {u"actionClockEnabled"_s, actionClockEnabled && rulesMode == kRulesModeForge &&
                                      eventType != kLimitedEventCommanderCube},
        {u"roundMinutes"_s, 50},
        {u"maxPlayers"_s, maxPlayers},
        {u"product"_s, QJsonObject::fromVariantMap(product)},
    };
    if (!draftSettings.isEmpty())
        payload.insert(u"draftSettings"_s, QJsonObject::fromVariantMap(draftSettings));
    sendTournamentCreation(payload);
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
    if (!instanceIds.isEmpty() && instanceIds.size() <= 4)
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
    if (!m_account->authenticated() && !credential.isEmpty())
        payload.insert(u"credential"_s, credential);
    if (m_account->authenticated())
        payload.insert(u"useAccount"_s, true);
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

QString WsClient::tournamentStartReadiness(const QString &stage) const
{
    if (stage == u"deck_building"_s)
        return m_limitedSession->allDecksSubmitted() ? u"ready"_s : u"waiting"_s;
    QStringList checkedIn;
    bool cubeReady = !m_tournamentSession->participants().isEmpty();
    for (const auto &value : m_tournamentSession->participants()) {
        const auto participant = value.toMap();
        if (participant.value(u"checkedIn"_s).toBool())
            checkedIn.append(participant.value(u"participantId"_s).toString());
        cubeReady &=
            participant.value(u"checkedIn"_s).toBool() && participant.value(u"online"_s).toBool();
    }
    checkedIn.sort();
    QString readiness = checkedIn.join(u'\n');
    if (m_tournamentSession->cubeRoom())
        readiness += cubeReady ? u"\nready"_s : u"\nwaiting"_s;
    return readiness;
}

void WsClient::startTournament()
{
    if (!m_tournamentSession->inTournament())
        return;
    const QString stage = m_tournamentSession->stage().isEmpty() ? m_tournamentSession->status()
                                                                 : m_tournamentSession->stage();
    const QString scope = m_tournamentSession->tournamentId() + u":"_s + stage;
    const QString readiness = tournamentStartReadiness(stage);
    if (m_tournamentStartOperation.isEmpty() || scope != m_tournamentStartScope ||
        (m_tournamentStartNotReady && readiness != m_tournamentStartReadiness)) {
        m_tournamentStartScope = scope;
        m_tournamentStartOperation = QUuid::createUuid().toString(QUuid::WithoutBraces);
        m_tournamentStartReadiness = readiness;
        m_tournamentStartNotReady = false;
    }
    send(kTypeTournamentStart,
         QJsonObject{{u"operationId"_s, m_tournamentStartOperation}, {u"expectedStage"_s, stage}});
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
