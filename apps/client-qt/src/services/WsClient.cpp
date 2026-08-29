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

    m_serverDirectory = new ServerDirectory(this);
    connect(m_serverDirectory, &ServerDirectory::latenciesChanged, this,
            &WsClient::serverLatenciesChanged);
    connect(m_serverDirectory, &ServerDirectory::customServerUrlChanged, this,
            &WsClient::customServerUrlChanged);

    m_tournamentSession = new TournamentSessionState(this);
    m_limitedSession = new LimitedSessionState(this);

    QSettings settings;
    const QString savedCustomServerUrl = settings.value(u"network/customServerUrl"_s).toString();
    if (!m_serverDirectory->setCustomServerUrl(savedCustomServerUrl) &&
        !savedCustomServerUrl.isEmpty()) {
        settings.remove(u"network/customServerUrl"_s);
    }
    m_protocolSession = new ProtocolSession(this);
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
        m_serverDirectory->indexForUrl(m_serverUrl) == ServerDirectory::CustomServerIndex &&
        m_serverDirectory->customServerUrl() != m_serverUrl &&
        m_serverDirectory->setCustomServerUrl(m_serverUrl)) {
        settings.setValue(u"network/customServerUrl"_s, m_serverDirectory->customServerUrl());
    }
    connect(m_reconnectController, &ReconnectController::retryDue, this, [this]() {
        if (m_state != Reconnecting)
            return;
        m_helloTimer.start();
        m_ws.open(QUrl(m_serverUrl));
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
    connect(&m_ws, &QWebSocket::textMessageReceived, m_messageParser,
            &WsMessageParser::parseMessage);
    connect(&m_ws, &QWebSocket::disconnected, m_messageParser, &WsMessageParser::finishTransport);
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
    disconnect(&m_ws, nullptr, m_messageParser, nullptr);
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

void WsClient::connectTo(const QString &url, const QString &displayName)
{
    clearLastError();
    clearVersionMismatch();
    setForgeRulesAvailable(false);
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
    m_helloTimer.start();
    m_ws.open(QUrl(m_serverUrl));
}

void WsClient::connectToServer(int serverIndex, const QString &displayName)
{
    const QString url = m_serverDirectory->serverUrl(serverIndex);
    if (serverIndex < 0 || serverIndex >= ServerDirectory::ConfiguredServerCount || url.isEmpty()) {
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
    return ServerDirectory::CustomServerIndex;
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

void WsClient::disconnectFromHub()
{
    m_intentionalDisconnect = true;
    m_reconnectController->stopRetry();
    m_reconnectController->clear();
    if (m_ws.state() == QAbstractSocket::UnconnectedState) {
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
    m_ws.close();
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
    const QString credential = tournamentCredential(id);
    if (!credential.isEmpty())
        payload.insert(u"credential"_s, credential);
    send(kTypeTournamentEnter, payload);
}

QString WsClient::send(const QString &type, const QJsonObject &payload)
{
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
    const ProtocolSession::OutboundCommand command = m_protocolSession->prepare(type, payload);
    if (m_ws.sendTextMessage(QString::fromUtf8(command.wire)) <= 0) {
        setLastError(u"connection"_s, u"action could not be queued for sending"_s);
        m_protocolSession->reportUnqueuedFailure(type, payload, m_lastError);
        return {};
    }
    m_protocolSession->markQueued(command);
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

void WsClient::onDisconnected()
{
    m_helloTimer.stop();
    m_reconnectController->flush();
    m_protocolSession->failAll(u"connection closed before the server replied"_s);
    const bool hadRoom = m_state == InRoom || m_state == Reconnecting ||
                         m_roomSession->pendingEntry() || !roomId().isEmpty();
    const bool hadTournament = m_tournamentSession->inTournament();
    if (!m_intentionalDisconnect && (hadRoom || hadTournament) &&
        m_reconnectController->hasCredentials()) {
        if (m_state != Reconnecting)
            m_reconnectController->beginReconnectWindow();
        setState(Reconnecting);
        emit inRoomChanged();
        m_reconnectController->scheduleRetry();
        return;
    }
    setState(Disconnected);
    setForgeRulesAvailable(false);
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

void WsClient::onMessageParsed(const QString &type, const QString &id, qint64 seq, bool hasSeq,
                               const QJsonObject &payload, const QVariantMap &gameSnapshot)
{
    Envelope envelope;
    envelope.type = type;
    envelope.id = id;
    envelope.seq = seq;
    envelope.hasSeq = hasSeq;
    envelope.payload = payload;
    dispatch(envelope, gameSnapshot);
}

void WsClient::onMessageRejected()
{
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
    m_gameSession->clear();
    m_rulesSession->clear();
}

void WsClient::clearRoomState()
{
    // Pending observers still need the current room role and seat to address
    // optimistic life, counter, and commander-tax entries during rollback.
    m_protocolSession->discardAll();
    m_roomSession->clear();
    clearGameState();
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
