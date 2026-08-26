// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "protocol/Message.h"
#include "services/LimitedSessionState.h"
#include "services/NetworkLimits.h"
#include "services/ServerDirectory.h"
#include "services/TournamentSessionState.h"
#include "services/WsClient.h"

#include <QDir>
#include <QFile>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonObject>
#include <QSettings>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QtWebSockets/QWebSocket>
#include <QtWebSockets/QWebSocketServer>

using namespace Qt::StringLiterals;
using hexproof::client::GameSessionState;
using hexproof::client::LimitedSessionState;
using hexproof::client::RoomSessionState;
using hexproof::client::ServerDirectory;
using hexproof::client::WsClient;
namespace network_limits = hexproof::client::network_limits;
using hexproof::protocol::Envelope;

namespace {

[[maybe_unused]] inline void sendEnvelope(QWebSocket *socket, const Envelope &env)
{
    socket->sendTextMessage(QString::fromUtf8(hexproof::protocol::serialize(env)));
}

[[maybe_unused]] inline QWebSocket *takeServerPeer(QWebSocketServer &server)
{
    QWebSocket *peer = server.nextPendingConnection();
    if (peer != nullptr)
        peer->setParent(&server);
    return peer;
}

[[maybe_unused]] inline QString buildVersion()
{
    return QStringLiteral(HEXPROOF_VERSION);
}

[[maybe_unused]] inline Envelope sharedFixture(const QString &name, bool *ok)
{
    QFile file(QDir(QStringLiteral(HEXPROOF_PROTOCOL_FIXTURE_DIR)).filePath(name));
    if (!file.open(QIODevice::ReadOnly)) {
        *ok = false;
        return {};
    }
    return hexproof::protocol::parse(file.readAll(), ok);
}

[[maybe_unused]] inline Envelope roomSnapshot(const QString &name, bool deckSelected = false,
                                              bool ready = false)
{
    Envelope env;
    env.type = hexproof::protocol::kTypeRoomSnapshot;
    env.hasSeq = true;
    env.seq = 1;
    env.payload = QJsonObject{
        {u"roomId"_s, u"ABCDEF"_s},
        {u"name"_s, name},
        {u"format"_s, u"modern"_s},
        {u"matchMode"_s, u"bo3"_s},
        {u"cardLoadMode"_s, u"preload"_s},
        {u"maxSeats"_s, 2},
        {u"seats"_s,
         QJsonArray{
             QJsonObject{
                 {u"occupied"_s, true},
                 {u"displayName"_s, u"Alice"_s},
                 {u"host"_s, true},
                 {u"deckSelected"_s, deckSelected},
                 {u"ready"_s, ready},
             },
             QJsonObject{
                 {u"occupied"_s, false},
             },
         }},
        {u"spectators"_s, QJsonArray{}},
    };
    return env;
}

} // namespace

class TestWsClient : public QObject
{
    Q_OBJECT

  private slots:
    void initTestCase();
    void cleanup();
    void correlatesCommandOutcomes() const;
    void rollsBackPendingCommandsBeforeRoomIdentityClears() const;
    void destroysParserWorkersDeterministically() const;
    void distinguishesHostKickReplyFromKickedPush() const;
    void exposesJoinedRoomRole() const;
    void roomSessionStateExposesQmlBindableIdentity() const;
    void roomSessionStateExposesQmlBindableSnapshot() const;
    void gameSessionStateExposesQmlBindableSnapshot() const;
    void limitedSessionRestoresPrivateDeckSelection() const;
    void dispatchesSharedSessionRoomAndGameFixtures() const;
    void exposesRoomAndGameSessionsToQml() const;
    void hidesMirroredSessionPropertiesFromQml() const;
    void updatesHostAuthorityFromRoomSnapshots() const;
    void handshakeErrorDisconnects() const;
    void rejectsOversizeIncomingMessages() const;
    void welcomeVersionMismatchDisconnects() const;
    void handlesP7DiscoveryReplayAndTableCommands() const;
    void handlesTournamentCommandsAndSnapshots() const;
    void loadsSavedResumeEndpoint() const;
    void loadsSecondaryPublicHubSelection() const;
    void configuresAndPersistsCustomServer() const;
    void migratesLegacyPrimaryPublicHubEndpoint() const;
    void exposesInitialServerLatencyState() const;
    void processesFinalMessageBeforeDisconnect() const;
    void resumesRoomAfterUnexpectedDisconnect() const;
    void sendsDeckAndReadyCommands() const;

  private:
    QTemporaryDir m_settingsDir;
};
