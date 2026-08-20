// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "WsClient.h"

#include "ProtocolSession.h"
#include "ReconnectController.h"
#include "TournamentSessionState.h"

#include <QJsonArray>
#include <QJsonObject>

namespace hexproof::client {

namespace {
using namespace hexproof::protocol;
using namespace Qt::StringLiterals;
} // namespace

void WsClient::dispatch(const Envelope &env, const QVariantMap &gameSnapshot)
{
    if (env.hasSeq)
        m_reconnectController->observeSequence(env.seq);
    if (env.type != kTypeError && !env.id.isEmpty())
        m_protocolSession->resolveSuccess(env.id);
    if (env.type == kTypeSessionWelcome)
        handleWelcome(env);
    else if (env.type == kTypeRoomCreated)
        handleCreated(env);
    else if (env.type == kTypeRoomJoined)
        handleJoined(env);
    else if (env.type == kTypeRoomSnapshot)
        handleSnapshot(env);
    else if (env.type == kTypeRoomListed)
        handleRoomListed(env);
    else if (env.type == kTypeTournamentListed)
        handleTournamentListed(env);
    else if (env.type == kTypeTournamentCreated)
        handleTournamentCreated(env);
    else if (env.type == kTypeTournamentEntered)
        handleTournamentEntered(env);
    else if (env.type == kTypeTournamentRegistered)
        handleTournamentRegistered(env);
    else if (env.type == kTypeTournamentSnapshot)
        handleTournamentSnapshot(env);
    else if (env.type == kTypeTournamentLeft)
        handleTournamentLeft(env);
    else if (env.type == kTypeDeckSelected)
        handleDeckSelected(env);
    else if (env.type == kTypeMatchLoadRequired)
        handleLoadRequired(env);
    else if (env.type == kTypeMatchStarted)
        handleMatchStarted(env);
    else if (env.type == kTypeGameSnapshot)
        handleGameSnapshot(gameSnapshot);
    else if (env.type == kTypeGameZoneDumpRequested)
        handleZoneDumpRequested(env);
    else if (env.type == kTypeGamePublicZoneMoveRequested)
        handlePublicZoneMoveRequested(env);
    else if (env.type == kTypeGameZoneDumped)
        handleZoneDumped(env);
    else if (env.type == kTypeReplayListed)
        handleReplayListed(env);
    else if (env.type == kTypeReplayLoaded)
        handleReplayLoaded(env);
    else if (env.type == kTypeRoomLeft)
        handleLeft(env);
    else if (env.type == kTypeRoomKicked) {
        // The host receives a correlated room.kicked success reply and stays
        // in the room. Only the kicked member receives an uncorrelated push.
        if (env.id.isEmpty())
            handleKicked(env);
    } else if (env.type == kTypeRoomDisbanded)
        handleDisbanded(env);
    else if (env.type == kTypeError)
        handleError(env);
    // Pong / unknown: ignore.
}

void WsClient::handleRoomListed(const Envelope &env)
{
    m_roomList.clear();
    for (const QJsonValue &value : env.payload.value(u"rooms"_s).toArray())
        m_roomList.append(value.toObject().toVariantMap());
    emit roomListChanged();
}

void WsClient::handleTournamentListed(const Envelope &env)
{
    m_tournamentSession->applyList(env.payload);
}

void WsClient::handleTournamentCreated(const Envelope &env)
{
    const QString tournamentId = env.payload.value(u"tournamentId"_s).toString();
    storeTournamentCredential(tournamentId, env.payload.value(u"organizerToken"_s).toString());
    m_tournamentSession->enter(tournamentId, u"organizer"_s);
}

void WsClient::handleTournamentEntered(const Envelope &env)
{
    m_tournamentSession->enter(env.payload.value(u"tournamentId"_s).toString(),
                               env.payload.value(u"role"_s).toString(),
                               env.payload.value(u"participantId"_s).toString());
}

void WsClient::handleTournamentRegistered(const Envelope &env)
{
    const QString tournamentId = env.payload.value(u"tournamentId"_s).toString();
    // An organizer may also play. Keep the organizer credential as the
    // canonical re-entry token; the server binds that identity back to its
    // participant seat as well.
    if (m_tournamentSession->role() != u"organizer"_s) {
        storeTournamentCredential(tournamentId,
                                  env.payload.value(u"participantToken"_s).toString());
    }
    m_tournamentSession->applyRegistration(env.payload.value(u"participantId"_s).toString());
}

void WsClient::handleTournamentSnapshot(const Envelope &env)
{
    const bool lostParticipantRegistration =
        !m_tournamentSession->participantId().isEmpty() &&
        env.payload.value(u"participantId"_s).toString().isEmpty();
    const bool keepOrganizerCredential = m_tournamentSession->role() == u"organizer"_s;
    const QString tournamentId = m_tournamentSession->tournamentId();
    m_tournamentSession->applySnapshot(env.payload);
    if (lostParticipantRegistration && !keepOrganizerCredential)
        removeTournamentCredential(tournamentId);
}

void WsClient::handleTournamentLeft(const Envelope &env)
{
    m_tournamentSession->clear();
    (void)env;
}

void WsClient::handleWelcome(const Envelope &env)
{
    m_helloTimer.stop();
    const QString v = env.payload.value(u"v"_s).toString();
    if (v != kProtocolVersion) {
        setLastError(u"protocol"_s, u"server protocol version mismatch (got \""_s + v + u"\")"_s);
        m_ws.close();
        // State stays Disconnected via onDisconnected; do not enter Connected.
        return;
    }
    const QString serverVersion = env.payload.value(u"serverVersion"_s).toString().trimmed();
    if (serverVersion != clientVersion()) {
        setVersionMismatch(serverVersion);
        setLastError(kErrClientVersionMismatch, u"server requires version \""_s + serverVersion +
                                                    u"\"; client version is \""_s +
                                                    clientVersion() + u"\""_s);
        m_intentionalDisconnect = true;
        m_reconnectController->stopRetry();
        m_ws.close();
        return;
    }
    const bool resumed = env.payload.value(u"resumed"_s).toBool();
    const bool tournamentOnlyReconnect = m_resumeAttempted && m_state == Reconnecting &&
                                         roomId().isEmpty() && m_tournamentSession->inTournament();
    const bool resumePending =
        m_resumeAttempted && m_state == Reconnecting && !resumed && !roomId().isEmpty();
    if (resumePending) {
        // The replacement connection can beat the server's observation of
        // the stale transport. Keep the original credential and retry until
        // the bounded reconnect window makes that seat resumable.
        m_ws.close();
        return;
    }
    const QString token = env.payload.value(u"resumeToken"_s).toString();
    m_reconnectController->updateSession(token, m_serverUrl, m_displayName);
    m_reconnectController->flush();

    if (resumed) {
        m_reconnectController->stopRetry();
        m_roomSession->enter(
            env.payload.value(u"roomId"_s).toString(), env.payload.value(u"role"_s).toString(),
            env.payload.contains(u"seat"_s) ? env.payload.value(u"seat"_s).toInt() : -1,
            env.payload.value(u"host"_s).toBool());
        return;
    }

    const bool resumeRejected =
        m_resumeAttempted &&
        (!roomId().isEmpty() || (m_state == Reconnecting && !tournamentOnlyReconnect));
    if (resumeRejected) {
        clearRoomState();
        setState(Connected);
        emit inRoomChanged();
        emit reconnectExpired();
    } else if (tournamentOnlyReconnect) {
        m_reconnectController->stopRetry();
        setState(Connected);
        resumeTournamentView();
    } else {
        setState(Connected);
        emit welcomeReceived();
        resumeTournamentView();
    }
}

void WsClient::handleCreated(const Envelope &env)
{
    // Creator is host; room id from payload. Defer the InRoom transition until
    // the first room.snapshot arrives so WaitingRoom renders with seats filled
    // (no empty-flash).
    m_roomSession->enter(env.payload.value(u"roomId"_s).toString(), kRolePlayer, 0, true);
    m_reconnectController->resetSequence();
}

void WsClient::handleJoined(const Envelope &env)
{
    // Joiner is not host (regardless of role). Defer InRoom until first
    // snapshot so WaitingRoom renders with seats filled.
    m_roomSession->enter(
        env.payload.value(u"roomId"_s).toString(), env.payload.value(u"role"_s).toString(),
        env.payload.contains(u"seat"_s) ? env.payload.value(u"seat"_s).toInt() : -1, false);
    m_reconnectController->resetSequence();
}

void WsClient::handleSnapshot(const Envelope &env)
{
    const RoomSessionState::SnapshotTransition transition =
        m_roomSession->applySnapshot(env.payload);
    if (transition.loadCancelled)
        emit loadCancelled();
    if (transition.returnedToRoom) {
        clearGameState();
        emit matchReturnedToRoom();
    }

    // First snapshot after create/join completes the InRoom transition (seats
    // are now populated, so WaitingRoom does not flash empty).
    if (m_roomSession->completePendingEntry()) {
        setState(InRoom);
        emit inRoomChanged();
        resumeTournamentView();
    }
}

void WsClient::handleDeckSelected(const Envelope &env)
{
    m_roomSession->takePendingDeck(env.id);
}

void WsClient::handleLoadRequired(const Envelope &env)
{
    const qint64 loadID = env.payload.value(u"loadId"_s).toInteger();
    if (!m_roomSession->applyLoadRequired(loadID))
        return;
    QVariantList cards;
    for (const QJsonValue &value : env.payload.value(u"cardKeys"_s).toArray())
        cards.append(value.toObject().toVariantMap());
    emit loadRequired(loadID, cards);
}

void WsClient::handleMatchStarted(const Envelope &env)
{
    m_roomSession->applyMatchStarted(env.payload.value(u"loadId"_s).toInteger());
    emit matchStarted();
}

void WsClient::handleGameSnapshot(const QVariantMap &snapshot)
{
    m_gameSession->applySnapshot(snapshot);
}

void WsClient::handleReplayListed(const Envelope &env)
{
    m_replayList.clear();
    for (const QJsonValue &value : env.payload.value(u"replays"_s).toArray())
        m_replayList.append(value.toObject().toVariantMap());
    m_replayOffset = env.payload.value(u"offset"_s).toInt();
    m_replayLimit = qMax(1, env.payload.value(u"limit"_s).toInt(50));
    m_replayTotal = env.payload.value(u"total"_s).toInt(m_replayList.size());
    m_replayHasMore = env.payload.value(u"hasMore"_s).toBool();
    emit replayListChanged();
}

void WsClient::handleReplayLoaded(const Envelope &env)
{
    m_loadedReplay = env.payload.toVariantMap();
    emit replayLoaded();
}

void WsClient::handleZoneDumped(const Envelope &env)
{
    if (env.payload.value(u"zone"_s).toString() != kZoneLibrary)
        return;
    QVariantList cards;
    for (const QJsonValue &value : env.payload.value(u"cards"_s).toArray())
        cards.append(value.toObject().toVariantMap());
    emit libraryDumped(cards, env.payload.value(u"sourceSeat"_s).toInt(seatIndex()),
                       env.payload.value(u"approvalId"_s).toString(),
                       env.payload.value(u"topCount"_s).toInt());
}

void WsClient::handleZoneDumpRequested(const Envelope &env)
{
    if (env.payload.value(u"zone"_s).toString() != kZoneLibrary)
        return;
    const QString approvalId = env.payload.value(u"approvalId"_s).toString();
    const QString requesterName = env.payload.value(u"requesterName"_s).toString();
    if (approvalId.isEmpty() || requesterName.isEmpty())
        return;
    emit libraryAccessRequested(approvalId, requesterName,
                                env.payload.value(u"requesterSeat"_s).toInt(-1),
                                env.payload.value(u"topCount"_s).toInt());
}

void WsClient::handlePublicZoneMoveRequested(const Envelope &env)
{
    const QString approvalId = env.payload.value(u"approvalId"_s).toString();
    const QString requesterName = env.payload.value(u"requesterName"_s).toString();
    const QString sourceZone = env.payload.value(u"sourceZone"_s).toString();
    const QString toZone = env.payload.value(u"toZone"_s).toString();
    const int cardCount = env.payload.value(u"cardCount"_s).toInt();
    if (approvalId.isEmpty() || requesterName.isEmpty() ||
        (sourceZone != kZoneGraveyard && sourceZone != kZoneExile) || toZone.isEmpty() ||
        cardCount < 1) {
        return;
    }
    emit publicZoneMoveRequested(approvalId, requesterName,
                                 env.payload.value(u"requesterSeat"_s).toInt(-1), sourceZone,
                                 cardCount, toZone);
}

void WsClient::handleLeft(const Envelope &env)
{
    // Non-host leave ack: we left the room but stay on the hub.
    clearRoomState();
    setState(Connected);
    emit inRoomChanged();
    emit leftRoom();
    (void)env;
}

void WsClient::handleKicked(const Envelope &env)
{
    // Server-push room.kicked (no echo id): leave waiting UI, stay on hub.
    clearRoomState();
    setState(Connected);
    emit inRoomChanged();
    emit kicked();
    (void)env;
}

void WsClient::handleDisbanded(const Envelope &env)
{
    // Room gone (we were host or another member). Back to hub connected state.
    clearRoomState();
    setState(Connected);
    emit inRoomChanged();
    emit roomDisbanded();
    (void)env;
}

void WsClient::handleError(const Envelope &env)
{
    m_roomSession->discardPendingDeck(env.id);
    const QString code = env.payload.value(u"code"_s).toString();
    const QString msg = env.payload.value(u"message"_s).toString();
    if (code == kErrClientVersionMismatch) {
        setVersionMismatch(env.payload.value(u"requiredVersion"_s).toString().trimmed());
        m_intentionalDisconnect = true;
        m_reconnectController->stopRetry();
    }
    setLastError(code, msg);
    m_protocolSession->resolveFailure(env.id, m_lastError);
    if (m_state == Connecting || m_state == Reconnecting) {
        m_helloTimer.stop();
        m_ws.close();
    }
}

} // namespace hexproof::client
