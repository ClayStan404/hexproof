// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "WsClient.h"

#include "LimitedSessionState.h"
#include "NetworkLimits.h"
#include "ProtocolSession.h"
#include "ReconnectController.h"
#include "ServerDirectory.h"
#include "TournamentSessionState.h"
#include "WsMessageParser.h"

#include <QClipboard>
#include <QCryptographicHash>
#include <QGuiApplication>
#include <QJsonObject>
#include <QSettings>
#include <QUrl>

namespace hexproof::client {

namespace {
using namespace hexproof::protocol;
using namespace Qt::StringLiterals;
} // namespace

WsClient::WsClient(QObject *parent)
    : QObject(parent)
{
    m_ws.setMaxAllowedIncomingFrameSize(network_limits::kMaximumIncomingWebSocketBytes);
    m_ws.setMaxAllowedIncomingMessageSize(network_limits::kMaximumIncomingWebSocketBytes);

    m_forgeHost = new ForgeHostService(this);
    m_roomSession = new RoomSessionState(this);
    connect(m_roomSession, &RoomSessionState::roomIdChanged, this, &WsClient::roomIdChanged);
    connect(m_roomSession, &RoomSessionState::hostChanged, this, &WsClient::youAreHostChanged);
    connect(m_roomSession, &RoomSessionState::roleChanged, this, &WsClient::roomRoleChanged);
    connect(m_roomSession, &RoomSessionState::selectedDeckNameChanged, this,
            &WsClient::selectedDeckNameChanged);
    connect(m_roomSession, &RoomSessionState::snapshotChanged, this, &WsClient::snapshotChanged);

    m_gameSession = new GameSessionState(this);
    connect(m_gameSession, &GameSessionState::snapshotChanged, this,
            &WsClient::gameSnapshotChanged);
    connect(m_gameSession, &GameSessionState::snapshotDataChanged, this,
            &WsClient::gameSnapshotDataChanged);

    m_rulesSession = new RulesSessionState(this);
    connect(m_rulesSession, &RulesSessionState::promptChanged, this,
            &WsClient::reconcileRulesResponse);
    connect(m_rulesSession, &RulesSessionState::snapshotChanged, this,
            &WsClient::reconcileRulesResponse);

    m_rulesResponseTimer.setParent(this);
    m_rulesResponseTimer.setObjectName(u"rulesResponseTimer"_s);
    m_rulesResponseTimer.setSingleShot(true);
    m_rulesResponseTimer.setInterval(30000);
    connect(&m_rulesResponseTimer, &QTimer::timeout, this, [this]() {
        const QString requestId = m_rulesResponseRequestId;
        if (requestId.isEmpty())
            return;
        clearRulesResponse();
        setLastError(u"timeout"_s, u"rules response timed out; retry the decision"_s);
        m_protocolSession->resolveFailure(requestId, m_lastError);
    });

    m_serverDirectory = new ServerDirectory(this);
    connect(m_serverDirectory, &ServerDirectory::latenciesChanged, this,
            &WsClient::serverLatenciesChanged);
    connect(m_serverDirectory, &ServerDirectory::customServerUrlChanged, this,
            &WsClient::customServerUrlChanged);
    connect(m_serverDirectory, &ServerDirectory::directoryChanged, this, [this]() {
        emit serverDirectoryChanged();
        emit serverUrlChanged();
    });
    connect(m_serverDirectory, &ServerDirectory::statusChanged, this,
            &WsClient::serverDirectoryStatusChanged);

    m_tournamentSession = new TournamentSessionState(this);
    m_limitedSession = new LimitedSessionState(this);

    QSettings settings;
    const QString savedCustomServerUrl = settings.value(u"network/customServerUrl"_s).toString();
    if (!m_serverDirectory->setCustomServerUrl(savedCustomServerUrl) &&
        !savedCustomServerUrl.isEmpty()) {
        settings.remove(u"network/customServerUrl"_s);
    }
    m_protocolSession = new ProtocolSession(this);
    initializePeerTransport();
    connect(m_protocolSession, &ProtocolSession::commandQueued, this, &WsClient::commandQueued);
    connect(m_protocolSession, &ProtocolSession::commandSucceeded, this,
            &WsClient::commandSucceeded);
    connect(m_protocolSession, &ProtocolSession::commandFailed, this, &WsClient::commandFailed);
    m_reconnectController = new ReconnectController(m_serverDirectory, this);
    connect(m_reconnectController, &ReconnectController::remainingSecondsChanged, this,
            &WsClient::reconnectSecondsRemainingChanged);
    m_serverUrl = m_reconnectController->serverUrl();
    m_displayName = m_reconnectController->displayName();
    if (!m_serverUrl.isEmpty() &&
        m_serverDirectory->indexForUrl(m_serverUrl) == m_serverDirectory->customServerIndex() &&
        m_serverDirectory->customServerUrl() != m_serverUrl &&
        m_serverDirectory->setCustomServerUrl(m_serverUrl)) {
        settings.setValue(u"network/customServerUrl"_s, m_serverDirectory->customServerUrl());
    }
    connect(m_reconnectController, &ReconnectController::retryDue, this, [this]() {
        if (m_state != Reconnecting)
            return;
        openTransport();
    });
    connect(m_reconnectController, &ReconnectController::reconnectExpired, this, [this]() {
        if (m_state != Reconnecting)
            return;
        m_reconnectController->clear();
        clearRoomState();
        m_tournamentSession->clear();
        m_limitedSession->clear();
        setState(Disconnected);
        emit inRoomChanged();
        emit reconnectExpired();
    });
    m_messageParser = new WsMessageParser;
    m_messageParser->moveToThread(&m_parserThread);
    connect(m_messageParser, &WsMessageParser::messageParsed, this, &WsClient::onMessageParsed);
    connect(m_messageParser, &WsMessageParser::messageRejected, this, &WsClient::onMessageRejected);
    connect(m_messageParser, &WsMessageParser::transportFinished, this, &WsClient::onDisconnected);
    m_parserThread.start();

    connect(&m_ws, &QWebSocket::connected, this, &WsClient::onConnected);
    connect(&m_ws, &QWebSocket::textMessageReceived, this, [this](const QString &text) {
        QMetaObject::invokeMethod(
            m_messageParser,
            [parser = m_messageParser, generation = m_transportGeneration, text]() {
                parser->parseMessage(generation, text);
            },
            Qt::QueuedConnection);
    });
    connect(&m_ws, &QWebSocket::disconnected, this, [this]() {
        QMetaObject::invokeMethod(
            m_messageParser,
            [parser = m_messageParser, generation = m_transportGeneration]() {
                parser->finishTransport(generation);
            },
            Qt::QueuedConnection);
    });
    connect(&m_ws, &QWebSocket::errorOccurred, this, [this]() { onErrorOccurred(); });

    m_helloTimer.setSingleShot(true);
    m_helloTimer.setInterval(10000); // 10s handshake timeout
    connect(&m_helloTimer, &QTimer::timeout, this, [this]() {
        if (m_state == Connecting || m_state == Reconnecting) {
            setLastError(u"timeout"_s, u"handshake (session.welcome) timed out"_s);
            m_ws.close();
        }
    });

    m_keepAliveTimer.setInterval(20000);
    connect(&m_keepAliveTimer, &QTimer::timeout, this, [this]() {
        if (m_ws.state() == QAbstractSocket::ConnectedState)
            m_ws.ping("hexproof");
    });
    m_keepAliveTimer.start();
}

WsClient::~WsClient()
{
    m_reconnectController->flush();
    disconnect(&m_ws, nullptr, this, nullptr);
    disconnect(m_messageParser, nullptr, this, nullptr);

    // The parser must be destroyed in its affinity thread. Move it back only
    // after all already-queued parse work has drained, then delete it here
    // before the thread object and socket members begin destruction.
    QThread *ownerThread = QThread::currentThread();
    QMetaObject::invokeMethod(
        m_messageParser,
        [parser = m_messageParser, ownerThread]() { parser->moveToThread(ownerThread); },
        Qt::BlockingQueuedConnection);
    delete m_messageParser;
    m_messageParser = nullptr;

    m_parserThread.quit();
    m_parserThread.wait();
}

int WsClient::reconnectSecondsRemaining() const
{
    return m_reconnectController->remainingSeconds();
}

bool WsClient::setInitialConnection(const QString &url, const QString &displayName)
{
    const QString name = displayName.trimmed();
    if (m_state != Disconnected || name.isEmpty() || url.trimmed().isEmpty() ||
        !m_serverDirectory->setCustomServerUrl(url))
        return false;

    const QString serverUrl = m_serverDirectory->customServerUrl();
    // Launch defaults are not resume credentials. Keep an existing player
    // identity only when both its endpoint and display name still match.
    if (!m_reconnectController->matches(serverUrl, name))
        m_reconnectController->clear();
    m_serverUrl = serverUrl;
    m_displayName = name;
    QSettings settings;
    settings.setValue(u"network/customServerUrl"_s, serverUrl);
    settings.sync();
    emit serverUrlChanged();
    emit displayNameChanged();
    return true;
}

void WsClient::connectTo(const QString &url, const QString &displayName)
{
    const bool hadRoom = !roomId().isEmpty() || m_state == InRoom;
    m_reconnectController->stopRetry();
    m_protocolSession->failAll(u"connection replaced before the server replied"_s);
    if (hadRoom)
        clearRoomState();
    m_tournamentSession->clear();
    m_limitedSession->clear();
    clearLastError();
    clearVersionMismatch();
    m_peerTransportAvailable = false;
    m_playerHostingAvailable = false;
    setForgeRulesAvailable(false);
    emit capabilitiesChanged();
    const QString nextServerUrl = url.trimmed();
    if (m_serverUrl != nextServerUrl) {
        m_serverUrl = nextServerUrl;
        emit serverUrlChanged();
    }
    m_displayName = displayName.trimmed();
    if (!m_reconnectController->matches(m_serverUrl, m_displayName))
        m_reconnectController->clear();
    m_intentionalDisconnect = false;
    emit displayNameChanged();
    setState(Connecting);
    if (hadRoom)
        emit inRoomChanged();
    openTransport();
}

void WsClient::openTransport()
{
    // Abort before advancing the generation, so even the old socket's final
    // disconnect is tagged with its old identity. Parser deliveries retain
    // their original order within one transport, including its final message.
    m_ws.abort();
    ++m_transportGeneration;
    m_helloTimer.start();
    m_ws.open(QUrl(m_serverUrl));
}

void WsClient::connectToServer(int serverIndex, const QString &displayName)
{
    const QString url = m_serverDirectory->serverUrl(serverIndex);
    if (serverIndex < 0 || serverIndex >= m_serverDirectory->configuredServerCount() ||
        url.isEmpty()) {
        setLastError(u"invalid_server_url"_s, u"enter a ws:// or wss:// server address"_s);
        return;
    }
    connectTo(url, displayName);
}

void WsClient::connectToCustomServer(const QString &url, const QString &displayName)
{
    clearLastError();
    clearVersionMismatch();
    if (url.trimmed().isEmpty() || !m_serverDirectory->setCustomServerUrl(url)) {
        setLastError(u"invalid_server_url"_s, u"enter a ws:// or wss:// server address"_s);
        return;
    }

    QSettings settings;
    settings.setValue(u"network/customServerUrl"_s, m_serverDirectory->customServerUrl());
    settings.sync();
    m_serverDirectory->refreshLatencies();
    connectTo(m_serverDirectory->customServerUrl(), displayName);
}

int WsClient::serverIndex() const
{
    return m_serverDirectory->indexForUrl(m_serverUrl);
}

int WsClient::customServerIndex() const
{
    return m_serverDirectory->customServerIndex();
}

QVariantList WsClient::serverEntries() const
{
    return m_serverDirectory->entries();
}
QString WsClient::serverDirectorySource() const
{
    return m_serverDirectory->source();
}
bool WsClient::serverDirectoryRefreshing() const
{
    return m_serverDirectory->refreshing();
}
bool WsClient::serverDirectoryRefreshFailed() const
{
    return m_serverDirectory->refreshFailed();
}

QString WsClient::customServerUrl() const
{
    return m_serverDirectory->customServerUrl();
}

QVariantList WsClient::serverLatencies() const
{
    return m_serverDirectory->latencies();
}

QString WsClient::clientVersion() const
{
    return QStringLiteral(HEXPROOF_VERSION);
}

QString WsClient::releaseDownloadUrl() const
{
    return u"https://github.com/ClayStan404/hexproof/releases"_s;
}

void WsClient::refreshServerLatencies()
{
    m_serverDirectory->refreshLatencies();
}

void WsClient::refreshServerDirectory(bool force)
{
    m_serverDirectory->refreshDirectory(force);
}

void WsClient::disconnectFromHub()
{
    m_intentionalDisconnect = true;
    m_reconnectController->stopRetry();
    m_reconnectController->clear();
    if (m_ws.state() == QAbstractSocket::UnconnectedState) {
        // The socket can finish before its parser queue drains. Explicit
        // cancellation invalidates those queued messages as well.
        ++m_transportGeneration;
        m_helloTimer.stop();
        m_protocolSession->failAll(u"connection closed before the server replied"_s);
        const bool hadRoom = !roomId().isEmpty() || m_state == InRoom || m_state == Reconnecting;
        setState(Disconnected);
        if (hadRoom) {
            clearRoomState();
            emit inRoomChanged();
        }
        m_tournamentSession->clear();
        m_limitedSession->clear();
        m_intentionalDisconnect = false;
        return;
    }
    if (m_ws.state() == QAbstractSocket::ConnectedState)
        m_ws.close();
    else
        m_ws.abort();
}

void WsClient::copyToClipboard(const QString &text)
{
    if (QGuiApplication *app = qApp)
        app->clipboard()->setText(text);
}

QString WsClient::tournamentCredential(const QString &tournamentId) const
{
    const QByteArray serverKey =
        QCryptographicHash::hash(m_serverUrl.toUtf8(), QCryptographicHash::Sha256).toHex();
    QSettings settings;
    return settings
        .value(u"tournaments/"_s + QString::fromLatin1(serverKey) + u"/"_s + tournamentId.toUpper())
        .toString();
}

void WsClient::storeTournamentCredential(const QString &tournamentId, const QString &credential)
{
    if (tournamentId.isEmpty() || credential.isEmpty())
        return;
    const QByteArray serverKey =
        QCryptographicHash::hash(m_serverUrl.toUtf8(), QCryptographicHash::Sha256).toHex();
    QSettings settings;
    settings.setValue(u"tournaments/"_s + QString::fromLatin1(serverKey) + u"/"_s +
                          tournamentId.toUpper(),
                      credential);
}

void WsClient::removeTournamentCredential(const QString &tournamentId)
{
    if (tournamentId.isEmpty())
        return;
    const QByteArray serverKey =
        QCryptographicHash::hash(m_serverUrl.toUtf8(), QCryptographicHash::Sha256).toHex();
    QSettings settings;
    settings.remove(u"tournaments/"_s + QString::fromLatin1(serverKey) + u"/"_s +
                    tournamentId.toUpper());
}

void WsClient::resumeTournamentView()
{
    if (!m_tournamentSession->inTournament() || (!connected() && !inRoom()))
        return;
    const QString id = m_tournamentSession->tournamentId();
    QJsonObject payload{{u"tournamentId"_s, id}};
    // Reconnecting an explicitly public view must not silently reclaim a
    // previously saved player identity. A seated player watching another
    // table still has participant/organizer membership and can restore it.
    const QString credential =
        m_tournamentSession->role() == u"viewer"_s ? QString{} : tournamentCredential(id);
    if (!credential.isEmpty())
        payload.insert(u"credential"_s, credential);
    send(kTypeTournamentEnter, payload);
}

QString WsClient::send(const QString &type, const QJsonObject &payload)
{
    // Every typed rules response passes here, including hand-card drag actions.
    // A queued write is not a completed decision: retain the lock until the
    // authoritative prompt changes, a correlated error arrives, or it times out.
    if (type == kTypeRulesRespond && m_roomSession->hostingMode() == u"player"_s &&
        (!m_roomSession->hostConnected() ||
         m_roomSession->hostStatus().value(u"migrating"_s).toBool()))
        return {};
    if (type == kTypeRulesRespond &&
        (rulesResponsePending() || !m_rulesSession->active() || !m_rulesSession->promptPending() ||
         !m_rulesSession->promptSupported() || m_rulesSession->gameOver() ||
         payload.value(u"promptId"_s).toInteger() != m_rulesSession->promptId()))
        return {};
    const bool socketConnected = m_ws.state() == QAbstractSocket::ConnectedState;
    const bool sendingHello =
        type == kTypeSessionHello && (m_state == Connecting || m_state == Reconnecting);
    const bool sessionReady = m_state == Connected || m_state == InRoom;
    if (!socketConnected || (!sendingHello && !sessionReady)) {
        if (type != kTypeSessionHello) {
            setLastError(u"connection"_s, u"action not sent while the connection is unavailable"_s);
            m_protocolSession->reportUnqueuedFailure(type, payload, m_lastError);
        }
        return {};
    }
    clearLastError();
    QJsonObject outbound = payload;
    const bool direct = type == kTypeRulesRespond && m_peerConsent && m_peerTransport->ready() &&
                        m_peerTransport->gameId() == m_rulesSession->gameId() &&
                        m_roomSession->seatIndex() != m_peerTransport->hostSeat();
    if (direct)
        outbound.insert(u"peerBinding"_s, m_peerTransport->bindingId());
    const ProtocolSession::OutboundCommand command = m_protocolSession->prepare(type, outbound);
    bool directQueued = false;
    if (direct) {
        directQueued = m_peerTransport->send({{u"bindingId"_s, m_peerTransport->bindingId()},
                                              {u"operationId"_s, command.id},
                                              {u"request"_s, outbound}});
    }
    if (!directQueued && m_ws.sendTextMessage(QString::fromUtf8(command.wire)) <= 0) {
        setLastError(u"connection"_s, u"action could not be queued for sending"_s);
        m_protocolSession->reportUnqueuedFailure(type, payload, m_lastError);
        return {};
    }
    if (type == kTypeRulesRespond) {
        m_rulesResponseRequestId = command.id;
        m_rulesResponseGameId = m_rulesSession->gameId();
        m_rulesResponsePromptId = m_rulesSession->promptId();
        // Cover the maximum ten-minute host grace and 45-second operation deadline.
        m_rulesResponseTimer.start(m_roomSession->hostingMode() == u"player"_s ? 660000 : 30000);
        emit rulesResponsePendingChanged();
    }
    m_protocolSession->markQueued(command);
    if (directQueued) {
        m_peerDecisionClock.start();
        m_peerRequestId = command.id;
        m_peerFallbackWire = command.wire;
        m_peerFallbackTimer.start();
    }
    return command.id;
}

void WsClient::onConnected()
{
    // Send session.hello immediately; state advances to Connected on welcome.
    QJsonObject p;
    p.insert(u"displayName"_s, m_displayName);
    p.insert(u"clientVersion"_s, QStringLiteral(HEXPROOF_VERSION));
    p.insert(u"protocol"_s, kProtocolVersion);
    m_resumeAttempted = m_reconnectController->hasCredentials() &&
                        m_reconnectController->matches(m_serverUrl, m_displayName);
    if (m_resumeAttempted) {
        p.insert(u"resumeToken"_s, m_reconnectController->token());
        if (m_reconnectController->lastSeq() > 0)
            p.insert(u"lastSeq"_s, m_reconnectController->lastSeq());
    }
    send(kTypeSessionHello, p);
}

void WsClient::onDisconnected(quint64 transportGeneration)
{
    if (transportGeneration != m_transportGeneration)
        return;
    clearRulesResponse();
    m_peerResumeNeeded = m_peerConsent;
    m_peerTransport->stop();
    m_helloTimer.stop();
    m_reconnectController->flush();
    const bool hadRoom = m_state == InRoom || m_state == Reconnecting ||
                         m_roomSession->pendingEntry() || !roomId().isEmpty();
    const bool hadTournament = m_tournamentSession->inTournament();
    if (!m_intentionalDisconnect && (hadRoom || hadTournament) &&
        m_reconnectController->hasCredentials()) {
        // Transport loss is not an authoritative rejection: keep pending
        // command correlation so optimistic overlays survive until the
        // post-resume snapshot (or replayed reply) reconciles them. A
        // room-ending failure still rolls back via clearRoomState().
        if (m_state != Reconnecting)
            m_reconnectController->beginReconnectWindow();
        setState(Reconnecting);
        emit inRoomChanged();
        m_reconnectController->scheduleRetry();
        return;
    }
    m_protocolSession->failAll(u"connection closed before the server replied"_s);
    setState(Disconnected);
    m_playerHostingAvailable = false;
    setForgeRulesAvailable(false);
    emit capabilitiesChanged();
    if (hadRoom) {
        clearRoomState();
        emit inRoomChanged();
    }
    if (hadTournament) {
        m_tournamentSession->clear();
        m_limitedSession->clear();
    }
    m_intentionalDisconnect = false;
}

void WsClient::onErrorOccurred()
{
    // Only surface socket errors during the connecting phase; once connected,
    // a socket error is followed by onDisconnected which handles the transition.
    // Writing lastError in Connected/InRoom would clobber more meaningful
    // business errors.
    if ((m_state == Connecting || m_state == Reconnecting) && !m_versionMismatch)
        setLastError(u"socket"_s, m_ws.errorString());
}

void WsClient::onMessageParsed(quint64 transportGeneration, const QString &type, const QString &id,
                               qint64 seq, bool hasSeq, const QJsonObject &payload,
                               const QVariantMap &gameSnapshot)
{
    if (transportGeneration != m_transportGeneration || m_intentionalDisconnect)
        return;
    Envelope envelope;
    envelope.type = type;
    envelope.id = id;
    envelope.seq = seq;
    envelope.hasSeq = hasSeq;
    envelope.payload = payload;
    dispatch(envelope, gameSnapshot);
}

void WsClient::onMessageRejected(quint64 transportGeneration)
{
    if (transportGeneration != m_transportGeneration || m_intentionalDisconnect)
        return;
    setLastError(u"parse"_s, u"invalid message from server"_s);
}

void WsClient::setLastError(const QString &code, const QString &message)
{
    m_lastError = code + u": "_s + message;
    emit lastErrorChanged();
}

void WsClient::clearLastError()
{
    if (m_lastError.isEmpty())
        return;
    m_lastError.clear();
    emit lastErrorChanged();
}

void WsClient::setVersionMismatch(const QString &requiredVersion)
{
    const QString normalizedVersion = requiredVersion.trimmed();
    if (m_versionMismatch && m_requiredVersion == normalizedVersion)
        return;
    m_versionMismatch = true;
    m_requiredVersion = normalizedVersion;
    emit versionMismatchChanged();
}

void WsClient::clearVersionMismatch()
{
    if (!m_versionMismatch && m_requiredVersion.isEmpty())
        return;
    m_versionMismatch = false;
    m_requiredVersion.clear();
    emit versionMismatchChanged();
}

void WsClient::setForgeRulesAvailable(bool available)
{
    if (m_forgeRulesAvailable == available)
        return;
    m_forgeRulesAvailable = available;
    emit capabilitiesChanged();
}

void WsClient::clearGameState()
{
    clearRulesResponse();
    m_gameSession->clear();
    m_rulesSession->clear();
}

void WsClient::clearRulesResponse()
{
    m_rulesResponseTimer.stop();
    m_peerFallbackTimer.stop();
    m_peerFallbackWire.clear();
    if (!rulesResponsePending())
        return;
    m_rulesResponseRequestId.clear();
    m_rulesResponseGameId.clear();
    m_rulesResponsePromptId = 0;
    emit rulesResponsePendingChanged();
}

void WsClient::reconcileRulesResponse()
{
    if (rulesResponsePending() &&
        (!m_rulesSession->active() || m_rulesSession->gameOver() ||
         m_rulesSession->gameId() != m_rulesResponseGameId || !m_rulesSession->promptPending() ||
         m_rulesSession->promptId() != m_rulesResponsePromptId)) {
        // Authoritative progress can overtake a lost direct acknowledgement.
        // Release its correlation as well as the UI lock; do not retain a
        // permanently pending command after stopping the fallback timer.
        if (m_peerRequestId == m_rulesResponseRequestId && !m_peerRequestId.isEmpty())
            m_protocolSession->resolveSuccess(m_peerRequestId);
        clearRulesResponse();
    }
}

void WsClient::clearRoomState()
{
    // Pending observers still need the current room role and seat to address
    // optimistic life, counter, and commander-tax entries during rollback.
    m_protocolSession->discardAll();
    m_forgeHost->stop();
    m_peerTransport->stop();
    m_peerConsent = m_peerOtherEnabled = m_peerResumeNeeded = false;
    m_peerRequestId.clear();
    m_directPeerDecisions = m_peerFallbacks = 0;
    m_peerLatencies.clear();
    m_lastRulesSnapshotSeq = 0;
    emit peerTransportChanged();
    m_playerHostingConsent = false;
    m_backupHostingConsent = false;
    m_roomSession->clear();
    clearGameState();
    m_reconnectController->setCrossLaunchResumeAllowed(false);
    m_reconnectController->resetSequence();
    m_reconnectController->flush();
}

void WsClient::setState(ConnectionState s)
{
    if (m_state == s)
        return;
    m_state = s;
    emit connectionStateChanged();
}

} // namespace hexproof::client
