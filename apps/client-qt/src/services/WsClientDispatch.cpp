// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "WsClient.h"

#include "LimitedSessionState.h"
#include "ProtocolSession.h"
#include "ReconnectController.h"
#include "ServerDirectory.h"
#include "TournamentSessionState.h"

#include <QJsonArray>
#include <QJsonObject>
#include <algorithm>

namespace hexproof::client {

namespace {
using namespace hexproof::protocol;
using namespace Qt::StringLiterals;

QVariantMap normalizedRulesStartFailure(const QJsonObject &value, bool player, bool host)
{
    const QString reason = value.value(u"reason"_s).toString();
    if (!QStringList{u"deck_rejected"_s, u"capacity"_s, u"runtime_unavailable"_s,
                     u"runtime_timeout"_s, u"runtime_failed"_s, u"start_rejected"_s}
             .contains(reason))
        return {};
    QVariantMap result{{u"reason"_s, reason}};
    QVariantList issues;
    bool truncated = value.value(u"truncated"_s).toBool();
    // The hub supplies recipient-scoped diagnostics, never raw runtime text.
    // Project only known fields, and retain no deck details for spectators.
    if (player && reason == u"deck_rejected"_s) {
        const auto entries = value.value(u"issues"_s).toArray();
        for (const auto &entry : entries) {
            if (issues.size() >= 32) {
                truncated = true;
                break;
            }
            const auto issue = entry.toObject();
            const QString deck = issue.value(u"deck"_s).toString();
            const QString section = issue.value(u"section"_s).toString();
            const QString code = issue.value(u"code"_s).toString();
            if ((deck != u"player"_s && deck != u"ai"_s) || (deck == u"ai"_s && !host) ||
                !QStringList{u"mainboard"_s, u"sideboard"_s, u"commanders"_s}.contains(section) ||
                !QStringList{u"card_unavailable"_s, u"printing_unavailable"_s,
                             u"commander_missing"_s, u"invalid_deck_size"_s,
                             u"invalid_sideboard_size"_s}
                     .contains(code))
                continue;
            QVariantMap detail{{u"deck"_s, deck}, {u"section"_s, section}, {u"code"_s, code}};
            for (const auto &field : {u"cardName"_s, u"setCode"_s, u"collectorNumber"_s}) {
                const QString text = issue.value(field).toString().trimmed();
                const qsizetype limit = field == u"cardName"_s ? 256 : 64;
                if (text.isEmpty())
                    continue;
                const bool control = std::any_of(text.cbegin(), text.cend(), [](QChar ch) {
                    return ch.category() == QChar::Other_Control ||
                           ch.category() == QChar::Other_Format || ch == QChar::LineSeparator ||
                           ch == QChar::ParagraphSeparator;
                });
                if (text.size() <= limit && !control)
                    detail.insert(field, text);
                else
                    truncated = true;
            }
            issues.append(detail);
        }
    }
    result.insert(u"issues"_s, issues);
    result.insert(u"truncated"_s, truncated);
    return result;
}
} // namespace

void WsClient::dispatch(const Envelope &env, const QVariantMap &gameSnapshot)
{
    if (env.hasSeq)
        m_reconnectController->observeSequence(env.seq);
    if (env.type != kTypeError && !env.id.isEmpty())
        m_protocolSession->resolveSuccess(env.id);
    if (env.type == kTypeRulesSnapshot && env.hasSeq) {
        if (env.seq <= m_lastRulesSnapshotSeq)
            return;
        m_lastRulesSnapshotSeq = env.seq;
    }
    if (env.type == kTypeRoomAIWorker) {
        if (m_aiModelsAvailable && m_roomSession->host() &&
            env.payload.value(u"roomId"_s).toString() == roomId() &&
            env.payload.value(u"source"_s).toString() == m_roomSession->aiSource())
            m_modelOpponent->start(m_serverUrl, env.payload);
    } else if (env.type == kTypeRoomAIStatus) {
        m_roomSession->applyAIStatus(env.payload);
        reconcileModelOpponentStatus();
    } else if (env.type == kTypeForgePeerGrant || env.type == kTypeForgePeerSignaled ||
               env.type == kTypeForgePeerStatus) {
        handlePeerEnvelope(env);
    } else if (env.type == kTypeForgeHostGrant) {
        const bool standby = env.payload.value(u"standby"_s).toBool();
        const bool consent = standby ? m_backupHostingConsent : m_playerHostingConsent;
        if (consent && m_playerHostingAvailable &&
            m_roomSession->hostingMode() == kHostingModePlayer &&
            env.payload.value(u"roomId"_s).toString() == roomId() &&
            m_roomSession->seatIndex() >= 0)
            m_forgeHost->startHosting(m_serverUrl, env.payload);
    } else if (env.type == kTypeForgeHostStatus) {
        m_roomSession->applyHostStatus(env.payload);
        if (env.payload.value(u"roomId"_s).toString() == roomId() && m_forgeHost->hosting()) {
            const int local = m_roomSession->seatIndex();
            const int host = env.payload.value(u"hostSeat"_s).toInt();
            const int backup = env.payload.value(u"backupSeat"_s).toInt(-1);
            if (local != host && local != backup)
                m_forgeHost->stop();
        }
    } else if (env.type == kTypeSessionWelcome)
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
    else if (env.type == kTypeTournamentChatMessage)
        m_tournamentSession->applyChatMessage(env.payload);
    else if (env.type == kTypeTournamentChatHistory)
        m_tournamentSession->applyChatHistory(env.payload);
    else if (env.type == kTypeLimitedSnapshot)
        handleLimitedSnapshot(env);
    else if (env.type == kTypeLimitedProgress) {
        if (env.payload.value(u"tournamentId"_s).toString() == m_tournamentSession->tournamentId())
            m_limitedSession->applyProgress(env.payload);
    } else if (env.type == kTypeTournamentLeft)
        handleTournamentLeft(env);
    else if (env.type == kTypeDeckSelected)
        handleDeckSelected(env);
    else if (env.type == kTypeMatchLoadRequired)
        handleLoadRequired(env);
    else if (env.type == kTypeMatchStarted)
        handleMatchStarted(env);
    else if (env.type == kTypeGameSnapshot)
        handleGameSnapshot(gameSnapshot);
    else if (env.type == kTypeGameRestarted && env.id.isEmpty() &&
             env.payload.value(u"roomId"_s).toString() == roomId())
        emit gameRestarted();
    else if (env.type == kTypeRulesSnapshot)
        handleRulesSnapshot(env.payload);
    else if (env.type == kTypeRulesPrompt)
        handleRulesPrompt(env.payload);
    else if (env.type == kTypeForgeReplayGrant)
        m_replays->acceptGrant(m_serverUrl, env.payload);
    else if (env.type == kTypeForgeReplayPage)
        m_replays->acceptPage(m_serverUrl, env.payload);
    else if (env.type == kTypeGameZoneDumpRequested)
        handleZoneDumpRequested(env);
    else if (env.type == kTypeGamePublicZoneMoveRequested)
        handlePublicZoneMoveRequested(env);
    else if (env.type == kTypeGameZoneDumped)
        handleZoneDumped(env);
    else if (env.type == kTypeSideboardCompleted)
        handleSideboardCompleted(env);
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
    m_limitedSession->clear();
    storeTournamentCredential(tournamentId, env.payload.value(u"organizerToken"_s).toString());
    m_tournamentSession->enter(tournamentId, u"organizer"_s);
}

void WsClient::handleTournamentEntered(const Envelope &env)
{
    m_limitedSession->clear();
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
    if (!m_tournamentSession->inTournament() ||
        env.payload.value(u"tournamentId"_s).toString() != m_tournamentSession->tournamentId())
        return;
    const bool lostParticipantRegistration =
        !m_tournamentSession->participantId().isEmpty() &&
        env.payload.value(u"participantId"_s).toString().isEmpty();
    const bool keepOrganizerCredential = m_tournamentSession->role() == u"organizer"_s;
    const QString tournamentId = m_tournamentSession->tournamentId();
    m_tournamentSession->applySnapshot(env.payload);
    if (lostParticipantRegistration && !keepOrganizerCredential)
        removeTournamentCredential(tournamentId);
}

void WsClient::handleLimitedSnapshot(const Envelope &env)
{
    if (!m_tournamentSession->inTournament() ||
        env.payload.value(u"tournamentId"_s).toString() != m_tournamentSession->tournamentId())
        return;
    m_limitedSession->applySnapshot(env.payload);
}

void WsClient::handleTournamentLeft(const Envelope &env)
{
    if (env.payload.value(u"tournamentId"_s).toString() != m_tournamentSession->tournamentId())
        return;
    if (m_tournamentSession->cubeRoom() && (m_tournamentSession->stage() == u"registration"_s ||
                                            m_tournamentSession->role() == u"organizer"_s ||
                                            m_tournamentSession->status() == u"cancelled"_s)) {
        removeTournamentCredential(m_tournamentSession->tournamentId());
    }
    m_tournamentSession->clear();
    m_limitedSession->clear();
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
    m_peerTransportAvailable = env.payload.value(u"peerTransportAvailable"_s).toBool();
    m_playerHostingAvailable = env.payload.value(u"playerHostingAvailable"_s).toBool();
    m_forgeAIAvailable = env.payload.value(u"forgeAIAvailable"_s).toBool();
    m_aiModelsAvailable = env.payload.value(u"aiModelsAvailable"_s).toBool();
    setForgeRulesAvailable(env.payload.value(u"forgeRulesAvailable"_s).toBool());
    emit capabilitiesChanged();
    m_serverDirectory->recordCapabilities(
        m_serverUrl,
        {{u"forge"_s, forgeRulesAvailable()},
         {u"playerHosting"_s, m_playerHostingAvailable},
         {u"directPeer"_s, m_peerTransportAvailable},
         {u"hostMigration"_s, env.payload.value(u"hostMigrationAvailable"_s).toBool()}});
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
    const QString resumedRole = env.payload.value(u"role"_s).toString();
    m_reconnectController->updateSession(token, m_serverUrl, m_displayName);
    m_reconnectController->setCrossLaunchResumeAllowed(resumed && resumedRole == kRolePlayer);
    m_reconnectController->flush();

    if (resumed) {
        m_reconnectController->stopRetry();
        m_roomSession->enter(env.payload.value(u"roomId"_s).toString(), resumedRole,
                             env.payload.contains(u"seat"_s) ? env.payload.value(u"seat"_s).toInt()
                                                             : -1,
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
    m_reconnectController->setCrossLaunchResumeAllowed(true);
}

void WsClient::handleJoined(const Envelope &env)
{
    m_playerHostingConsent = false;
    // Joiner is not host (regardless of role). Defer InRoom until first
    // snapshot so WaitingRoom renders with seats filled.
    const QString role = env.payload.value(u"role"_s).toString();
    m_roomSession->enter(
        env.payload.value(u"roomId"_s).toString(), role,
        env.payload.contains(u"seat"_s) ? env.payload.value(u"seat"_s).toInt() : -1, false);
    m_reconnectController->resetSequence();
    m_reconnectController->setCrossLaunchResumeAllowed(role == kRolePlayer);
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
        if (m_directPeerPreferred || m_peerResumeNeeded) {
            m_peerResumeNeeded = false;
            setDirectPeerEnabled(true);
        }
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
    clearRulesStartFailure();
    QVariantList cards;
    for (const QJsonValue &value : env.payload.value(u"cardKeys"_s).toArray())
        cards.append(value.toObject().toVariantMap());
    emit loadRequired(loadID, cards);
}

void WsClient::handleMatchStarted(const Envelope &env)
{
    clearRulesStartFailure();
    m_roomSession->applyMatchStarted(env.payload.value(u"loadId"_s).toInteger());
    emit matchStarted();
}

void WsClient::handleGameSnapshot(const QVariantMap &snapshot)
{
    m_gameSession->applySnapshot(snapshot);
}

void WsClient::handleRulesSnapshot(const QJsonObject &snapshot)
{
    if (!m_rulesSession->applySnapshot(snapshot))
        setLastError(u"invalid_rules_snapshot"_s, u"invalid rules snapshot"_s);
}

void WsClient::handleRulesPrompt(const QJsonObject &prompt)
{
    if (!m_rulesSession->applyPrompt(prompt))
        setLastError(u"protocol"_s, u"invalid rules prompt"_s);
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

void WsClient::handleSideboardCompleted(const Envelope &env)
{
    // Explicit sideboard.completed handling: the sideboard view must close on
    // this push alone instead of relying on the server also projecting a
    // game.snapshot, and the reason (ready/timeout) becomes observable.
    m_gameSession->clearSideboard();
    emit sideboardCompleted(env.payload.value(u"reason"_s).toString());
}

void WsClient::handleError(const Envelope &env)
{
    if (!env.id.isEmpty() && env.id == m_rulesResponseRequestId)
        clearRulesResponse();
    m_roomSession->discardPendingDeck(env.id);
    const QString code = env.payload.value(u"code"_s).toString();
    QString msg = env.payload.value(u"message"_s).toString();
    if ((code == u"rules_unavailable"_s || code == u"server_limit"_s) && !roomId().isEmpty() &&
        m_roomSession->rulesMode() == kRulesModeForge) {
        const auto failure = normalizedRulesStartFailure(
            env.payload.value(u"rulesStartFailure"_s).toObject(),
            m_roomSession->role() == kRolePlayer, m_roomSession->host());
        if (!failure.isEmpty()) {
            m_rulesStartFailure = failure;
            emit rulesStartFailureChanged();
        }
    }
    if (code == kErrClientVersionMismatch) {
        setVersionMismatch(env.payload.value(u"requiredVersion"_s).toString().trimmed());
        m_intentionalDisconnect = true;
        m_reconnectController->stopRetry();
    }
    // Rebuild the not-ready message from the structured count so client-side
    // localization matches this client's template, not the server's wording.
    const int minimumPlayers = env.payload.value(u"minimumPlayers"_s).toInt(0);
    if (code == kErrTournamentNotReady && minimumPlayers > 0)
        msg = u"at least %1 checked-in players are required"_s.arg(minimumPlayers);
    setLastError(code, msg);
    m_protocolSession->resolveFailure(env.id, m_lastError);
    if (m_state == Connecting || m_state == Reconnecting) {
        m_helloTimer.stop();
        m_ws.close();
    }
}

} // namespace hexproof::client
