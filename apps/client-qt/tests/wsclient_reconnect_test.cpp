// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "wsclient_test.h"

void TestWsClient::resumesRoomAfterUnexpectedDisconnect() const
{
    QWebSocketServer server(u"Hexproof reconnect test server"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));

    QList<QWebSocket *> peers;
    QList<QList<Envelope>> received;
    connect(&server, &QWebSocketServer::newConnection, &server, [&]() {
        QWebSocket *peer = takeServerPeer(server);
        const qsizetype index = peers.size();
        peers.append(peer);
        received.append(QList<Envelope>{});
        connect(peer, &QWebSocket::textMessageReceived, &server, [&, index](const QString &text) {
            bool ok = false;
            const Envelope env = hexproof::protocol::parse(text.toUtf8(), &ok);
            if (ok)
                received[index].append(env);
        });
    });

    WsClient client;
    const QString serverUrl = u"ws://127.0.0.1:"_s + QString::number(server.serverPort());
    client.connectTo(serverUrl, u"Alice"_s);
    QTRY_VERIFY_WITH_TIMEOUT(peers.size() == 1, 1000);
    QTRY_VERIFY_WITH_TIMEOUT(!received[0].isEmpty(), 1000);
    QCOMPARE(received[0].first().type, hexproof::protocol::kTypeSessionHello);
    QVERIFY(!received[0].first().payload.contains(u"resumeToken"_s));

    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.id = received[0].first().id;
    welcome.payload = QJsonObject{
        {u"v"_s, hexproof::protocol::kProtocolVersion},
        {u"connectionId"_s, u"conn-before-drop"_s},
        {u"serverVersion"_s, buildVersion()},
        {u"resumeToken"_s, u"resume-secret"_s},
    };
    sendEnvelope(peers[0], welcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 1000);

    Envelope created;
    created.type = hexproof::protocol::kTypeRoomCreated;
    created.id = u"2"_s;
    created.payload = QJsonObject{{u"roomId"_s, u"ABCDEF"_s}};
    sendEnvelope(peers[0], created);
    Envelope beforeDrop = roomSnapshot(u"Room before drop"_s, true, true);
    beforeDrop.seq = 7;
    sendEnvelope(peers[0], beforeDrop);
    QTRY_VERIFY_WITH_TIMEOUT(client.inRoom(), 1000);

    peers[0]->close();
    QTRY_VERIFY_WITH_TIMEOUT(client.reconnecting(), 1000);
    client.drawCards(1);
    QCOMPARE(client.lastError(),
             u"connection: action not sent while the connection is unavailable"_s);
    QTRY_VERIFY_WITH_TIMEOUT(peers.size() == 2, 4000);
    QTRY_VERIFY_WITH_TIMEOUT(!received[1].isEmpty(), 1000);

    const Envelope resumeHello = received[1].first();
    QCOMPARE(resumeHello.type, hexproof::protocol::kTypeSessionHello);
    QCOMPARE(resumeHello.payload.value(u"resumeToken"_s).toString(), u"resume-secret"_s);
    QCOMPARE(resumeHello.payload.value(u"lastSeq"_s).toInteger(), 7);

    Envelope prematureFreshWelcome;
    prematureFreshWelcome.type = hexproof::protocol::kTypeSessionWelcome;
    prematureFreshWelcome.id = resumeHello.id;
    prematureFreshWelcome.payload = QJsonObject{
        {u"v"_s, hexproof::protocol::kProtocolVersion},
        {u"connectionId"_s, u"conn-premature"_s},
        {u"serverVersion"_s, buildVersion()},
        {u"resumeToken"_s, u"do-not-adopt"_s},
    };
    sendEnvelope(peers[1], prematureFreshWelcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.reconnecting(), 1000);
    QTRY_VERIFY_WITH_TIMEOUT(peers.size() == 3, 5000);
    QTRY_VERIFY_WITH_TIMEOUT(!received[2].isEmpty(), 1000);
    const Envelope retriedResumeHello = received[2].first();
    QCOMPARE(retriedResumeHello.type, hexproof::protocol::kTypeSessionHello);
    QCOMPARE(retriedResumeHello.payload.value(u"resumeToken"_s).toString(), u"resume-secret"_s);

    Envelope resumed;
    resumed.type = hexproof::protocol::kTypeSessionWelcome;
    resumed.id = retriedResumeHello.id;
    resumed.payload = QJsonObject{
        {u"v"_s, hexproof::protocol::kProtocolVersion},
        {u"connectionId"_s, u"conn-after-drop"_s},
        {u"serverVersion"_s, buildVersion()},
        {u"resumeToken"_s, u"resume-secret"_s},
        {u"resumed"_s, true},
        {u"roomId"_s, u"ABCDEF"_s},
        {u"role"_s, hexproof::protocol::kRolePlayer},
        {u"seat"_s, 0},
        {u"host"_s, true},
    };
    sendEnvelope(peers[2], resumed);
    Envelope restoredRoom = roomSnapshot(u"Restored room"_s, true, true);
    restoredRoom.seq = 8;
    restoredRoom.payload.insert(u"phase"_s, hexproof::protocol::kRoomPhaseStarted);
    sendEnvelope(peers[2], restoredRoom);

    Envelope restoredGame;
    restoredGame.type = hexproof::protocol::kTypeGameSnapshot;
    restoredGame.hasSeq = true;
    restoredGame.seq = 9;
    restoredGame.payload = QJsonObject{
        {u"roomId"_s, u"ABCDEF"_s},
        {u"gameNumber"_s, 1},
        {u"startingSeat"_s, 0},
        {u"activeSeat"_s, 0},
        {u"currentPhase"_s, hexproof::protocol::kGamePhaseUntap},
        {u"seats"_s,
         QJsonArray{
             QJsonObject{
                 {u"seat"_s, 0},
                 {u"displayName"_s, u"Alice"_s},
                 {u"life"_s, 20},
                 {u"libraryCount"_s, 52},
                 {u"handCount"_s, 1},
                 {u"hand"_s, QJsonArray{QJsonObject{
                                 {u"id"_s, u"alice-secret"_s},
                                 {u"name"_s, u"Lightning Bolt"_s},
                                 {u"setCode"_s, u"M11"_s},
                                 {u"collectorNumber"_s, u"149"_s},
                             }}},
                 {u"battlefield"_s, QJsonArray{}},
                 {u"graveyard"_s, QJsonArray{}},
                 {u"exile"_s, QJsonArray{}},
             },
             QJsonObject{
                 {u"seat"_s, 1},
                 {u"displayName"_s, u"Bob"_s},
                 {u"life"_s, 20},
                 {u"libraryCount"_s, 53},
                 {u"handCount"_s, 7},
                 {u"battlefield"_s, QJsonArray{}},
                 {u"graveyard"_s, QJsonArray{}},
                 {u"exile"_s, QJsonArray{}},
             },
         }},
        {u"stack"_s, QJsonArray{}},
        {u"revealed"_s, QJsonArray{}},
        {u"score"_s, QJsonArray{0, 0}},
        {u"log"_s, QJsonArray{}},
    };
    sendEnvelope(peers[2], restoredGame);

    QTRY_VERIFY_WITH_TIMEOUT(client.inRoom(), 1000);
    QTRY_COMPARE_WITH_TIMEOUT(client.roomName(), u"Restored room"_s, 1000);
    QTRY_VERIFY_WITH_TIMEOUT(client.gameSeats().size() == 2, 1000);
    QVERIFY(client.youAreHost());
    QCOMPARE(client.roomRole(), hexproof::protocol::kRolePlayer);
    QCOMPARE(client.seatIndex(), 0);
    QCOMPARE(client.gameSeats()
                 .first()
                 .toMap()
                 .value(u"hand"_s)
                 .toList()
                 .first()
                 .toMap()
                 .value(u"id"_s)
                 .toString(),
             u"alice-secret"_s);
    QVERIFY(client.gameSeats().last().toMap().value(u"hand"_s).toList().isEmpty());
}

void TestWsClient::keepsPendingCommandsWhenTransportDropsMidCommand() const
{
    QWebSocketServer server(u"Hexproof mid-command drop server"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));

    QList<QWebSocket *> peers;
    QList<QList<Envelope>> received;
    connect(&server, &QWebSocketServer::newConnection, &server, [&]() {
        QWebSocket *peer = takeServerPeer(server);
        const qsizetype index = peers.size();
        peers.append(peer);
        received.append(QList<Envelope>{});
        connect(peer, &QWebSocket::textMessageReceived, &server, [&, index](const QString &text) {
            bool ok = false;
            const Envelope env = hexproof::protocol::parse(text.toUtf8(), &ok);
            if (ok)
                received[index].append(env);
        });
    });

    WsClient client;
    const QString serverUrl = u"ws://127.0.0.1:"_s + QString::number(server.serverPort());
    client.connectTo(serverUrl, u"Alice"_s);
    QTRY_VERIFY_WITH_TIMEOUT(peers.size() == 1, 1000);

    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.id = u"1"_s;
    welcome.payload = QJsonObject{
        {u"v"_s, hexproof::protocol::kProtocolVersion},
        {u"connectionId"_s, u"conn-mid-drop"_s},
        {u"serverVersion"_s, buildVersion()},
        {u"resumeToken"_s, u"resume-secret"_s},
    };
    sendEnvelope(peers[0], welcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 1000);

    Envelope created;
    created.type = hexproof::protocol::kTypeRoomCreated;
    created.id = u"2"_s;
    created.payload = QJsonObject{{u"roomId"_s, u"ABCDEF"_s}};
    sendEnvelope(peers[0], created);
    Envelope beforeDrop = roomSnapshot(u"Room before drop"_s, true, true);
    beforeDrop.seq = 7;
    sendEnvelope(peers[0], beforeDrop);
    QTRY_VERIFY_WITH_TIMEOUT(client.inRoom(), 1000);

    QSignalSpy outbound(peers[0], &QWebSocket::textMessageReceived);
    QSignalSpy succeeded(&client, &WsClient::commandSucceeded);
    QSignalSpy failed(&client, &WsClient::commandFailed);

    // A game command is in flight when the transport dies without any reply.
    client.setCardTapped(u"card-a"_s, true);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    bool ok = false;
    const Envelope tappedRequest =
        hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);

    peers[0]->close();
    QTRY_VERIFY_WITH_TIMEOUT(client.reconnecting(), 1000);
    QTest::qWait(150);
    // Transport loss is not an authoritative rejection: the pending command
    // must survive so the post-resume snapshot (or replayed reply) reconciles.
    QCOMPARE(failed.count(), 0);

    QTRY_VERIFY_WITH_TIMEOUT(peers.size() == 2, 5000);
    QTRY_VERIFY_WITH_TIMEOUT(!received[1].isEmpty(), 1000);
    const Envelope resumeHello = received[1].first();
    QCOMPARE(resumeHello.type, hexproof::protocol::kTypeSessionHello);
    QCOMPARE(resumeHello.payload.value(u"resumeToken"_s).toString(), u"resume-secret"_s);

    Envelope resumed;
    resumed.type = hexproof::protocol::kTypeSessionWelcome;
    resumed.id = u"1"_s;
    resumed.payload = QJsonObject{
        {u"v"_s, hexproof::protocol::kProtocolVersion},
        {u"connectionId"_s, u"conn-after-mid-drop"_s},
        {u"serverVersion"_s, buildVersion()},
        {u"resumeToken"_s, u"resume-secret"_s},
        {u"resumed"_s, true},
        {u"roomId"_s, u"ABCDEF"_s},
        {u"role"_s, hexproof::protocol::kRolePlayer},
        {u"seat"_s, 0},
        {u"host"_s, true},
    };
    sendEnvelope(peers[1], resumed);
    Envelope restoredRoom = roomSnapshot(u"Restored room"_s, true, true);
    restoredRoom.seq = 8;
    sendEnvelope(peers[1], restoredRoom);
    QTRY_VERIFY_WITH_TIMEOUT(client.inRoom(), 1000);

    // The server had received the command before the drop and replays the
    // missed reply after resume; correlation must still resolve it.
    Envelope tapped;
    tapped.type = hexproof::protocol::kTypeGameTappedSet;
    tapped.id = tappedRequest.id;
    sendEnvelope(peers[1], tapped);
    QTRY_COMPARE_WITH_TIMEOUT(succeeded.count(), 1, 1000);
    QCOMPARE(succeeded.at(0).at(0).toString(), tappedRequest.id);
    QCOMPARE(failed.count(), 0);

    // A real typed server error after resume still rolls back immediately.
    QSignalSpy resumedOutbound(peers[1], &QWebSocket::textMessageReceived);
    client.setCardTapped(u"card-b"_s, true);
    QTRY_COMPARE_WITH_TIMEOUT(resumedOutbound.count(), 1, 1000);
    const Envelope rejectedRequest =
        hexproof::protocol::parse(resumedOutbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    Envelope rejected;
    rejected.type = hexproof::protocol::kTypeError;
    rejected.id = rejectedRequest.id;
    rejected.payload = QJsonObject{
        {u"code"_s, u"not_in_room"_s},
        {u"message"_s, u"no such card"_s},
    };
    sendEnvelope(peers[1], rejected);
    QTRY_COMPARE_WITH_TIMEOUT(failed.count(), 1, 1000);
    QCOMPARE(failed.at(0).at(0).toString(), rejectedRequest.id);
}
