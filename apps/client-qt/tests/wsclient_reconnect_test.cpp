// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "wsclient_test.h"

#include <QJsonDocument>
#include <QScopeGuard>

namespace hexproof::client {
// Exercise the dispatcher used after peer receipt authentication while the hub
// side still uses the real socket and background parser.
class NativeAudit
{
  public:
    static void applyPeerPublication(WsClient &client, const Envelope &snapshot,
                                     const Envelope &prompt)
    {
        client.dispatch(snapshot);
        client.dispatch(prompt);
    }
};
} // namespace hexproof::client

void TestWsClient::staleHubPromptsDoNotReplacePeerDecisions_data() const
{
    QTest::addColumn<bool>("snapshotBeforePeer");
    QTest::addColumn<bool>("clearedPrompt");
    QTest::newRow("old-publication") << false << false;
    QTest::newRow("split-publication") << true << false;
    QTest::newRow("old-cleared-prompt") << false << true;
    QTest::newRow("split-cleared-prompt") << true << true;
}

void TestWsClient::staleHubPromptsDoNotReplacePeerDecisions() const
{
    QFETCH(bool, snapshotBeforePeer);
    QFETCH(bool, clearedPrompt);
    QWebSocketServer server(u"Hub and peer publication ordering"_s,
                            QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));
    QWebSocket *peer = nullptr;
    connect(&server, &QWebSocketServer::newConnection, &server,
            [&] { peer = takeServerPeer(server); });
    WsClient client;
    client.connectTo(u"ws://127.0.0.1:%1"_s.arg(server.serverPort()), u"Alice"_s);
    QTRY_VERIFY(peer);
    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.payload = {{u"v"_s, hexproof::protocol::kProtocolVersion},
                       {u"serverVersion"_s, buildVersion()}};
    sendEnvelope(peer, welcome);
    QTRY_VERIFY(client.connected());
    Envelope created;
    created.type = hexproof::protocol::kTypeRoomCreated;
    created.payload = {{u"roomId"_s, u"ABCDEF"_s}};
    sendEnvelope(peer, created);
    auto room = roomSnapshot(u"Rules room"_s);
    room.payload.insert(u"phase"_s, hexproof::protocol::kRoomPhaseStarted);
    sendEnvelope(peer, room);
    QTRY_VERIFY(client.inRoom());
    bool ok = false;
    auto oldSnapshot = sharedFixture(u"rules-snapshot-owner.json"_s, &ok);
    QVERIFY(ok);
    oldSnapshot.seq = 10;
    auto oldPrompt = sharedFixture(u"rules-prompt.json"_s, &ok);
    QVERIFY(ok);
    oldPrompt.hasSeq = true;
    oldPrompt.seq = oldSnapshot.seq;
    oldPrompt.payload.insert(u"promptId"_s, clearedPrompt ? 0 : 10);
    oldPrompt.payload.insert(u"pending"_s, !clearedPrompt);
    Envelope boundary;
    boundary.type = hexproof::protocol::kTypeRoomListed;
    boundary.payload = {{u"rooms"_s, QJsonArray{}}};
    QSignalSpy boundaries(&client, &WsClient::roomListChanged);
    if (snapshotBeforePeer) {
        sendEnvelope(peer, oldSnapshot);
        sendEnvelope(peer, boundary);
        QTRY_COMPARE(boundaries.count(), 1);
    }
    auto currentSnapshot = oldSnapshot;
    currentSnapshot.seq = 20;
    currentSnapshot.payload.insert(u"turn"_s, 2);
    auto currentPrompt = oldPrompt;
    currentPrompt.seq = currentSnapshot.seq;
    currentPrompt.payload.insert(u"pending"_s, true);
    currentPrompt.payload.insert(u"promptId"_s, 20);
    hexproof::client::NativeAudit::applyPeerPublication(client, currentSnapshot, currentPrompt);
    QCOMPARE(client.rulesSession()->promptId(), 20);
    client.respondRulesPrompt(20, u"$pass"_s);
    QVERIFY(client.rulesResponsePending());
    if (!snapshotBeforePeer)
        sendEnvelope(peer, oldSnapshot);
    sendEnvelope(peer, oldPrompt);
    sendEnvelope(peer, boundary);
    QTRY_COMPARE(boundaries.count(), snapshotBeforePeer ? 2 : 1);
    QCOMPARE(client.rulesSession()->turn(), 2);
    QCOMPARE(client.rulesSession()->promptId(), 20);
    QVERIFY(client.rulesResponsePending());

    // A duplicate publication's equal sequence still carries a valid prompt.
    sendEnvelope(peer, currentSnapshot);
    sendEnvelope(peer, currentPrompt);
    sendEnvelope(peer, boundary);
    QTRY_COMPARE(boundaries.count(), snapshotBeforePeer ? 3 : 2);
    QCOMPARE(client.rulesSession()->promptId(), 20);
    QVERIFY(client.rulesResponsePending());

    // A snapshot without a prompt must not fence a later standalone refresh.
    currentSnapshot.seq = 21;
    currentSnapshot.payload.insert(u"turn"_s, 3);
    sendEnvelope(peer, currentSnapshot);
    currentPrompt.hasSeq = false;
    currentPrompt.payload.insert(u"promptId"_s, 21);
    sendEnvelope(peer, currentPrompt);
    QTRY_COMPARE(client.rulesSession()->promptId(), 21);
    QVERIFY(!client.rulesResponsePending());
    // Sequence-free compatibility projections must not inherit the old fence.
    currentSnapshot.hasSeq = false;
    currentSnapshot.payload.insert(u"turn"_s, 3);
    currentPrompt.payload.insert(u"promptId"_s, 22);
    sendEnvelope(peer, currentSnapshot);
    sendEnvelope(peer, currentPrompt);
    QTRY_COMPARE(client.rulesSession()->promptId(), 22);
    QCOMPARE(client.rulesSession()->turn(), 3);

    // A replacement game's newer publication still clears the old decision.
    currentSnapshot.hasSeq = true;
    currentSnapshot.seq = 22;
    currentPrompt.hasSeq = true;
    currentPrompt.seq = currentSnapshot.seq;
    currentSnapshot.payload.insert(u"gameId"_s, u"ABCDEF-2"_s);
    currentSnapshot.payload.insert(u"promptFollows"_s, true);
    currentPrompt.payload.insert(u"gameId"_s, u"ABCDEF-2"_s);
    currentPrompt.payload.insert(u"promptId"_s, 23);
    sendEnvelope(peer, currentSnapshot);
    sendEnvelope(peer, currentPrompt);
    QTRY_COMPARE(client.rulesSession()->promptId(), 23);
    QCOMPARE(client.rulesSession()->gameId(), u"ABCDEF-2"_s);

    // Ending membership resets the room-scoped sequence for the next table.
    Envelope left;
    left.type = hexproof::protocol::kTypeRoomLeft;
    left.payload = {{u"roomId"_s, u"ABCDEF"_s}};
    sendEnvelope(peer, left);
    QTRY_VERIFY(client.roomId().isEmpty());
    created.payload.insert(u"roomId"_s, u"NEW123"_s);
    room.payload.insert(u"roomId"_s, u"NEW123"_s);
    sendEnvelope(peer, created);
    sendEnvelope(peer, room);
    currentSnapshot.seq = 1;
    currentSnapshot.payload.insert(u"roomId"_s, u"NEW123"_s);
    currentSnapshot.payload.insert(u"gameId"_s, u"NEW123-1"_s);
    currentPrompt.seq = 1;
    currentPrompt.payload.insert(u"roomId"_s, u"NEW123"_s);
    currentPrompt.payload.insert(u"gameId"_s, u"NEW123-1"_s);
    currentPrompt.payload.insert(u"promptId"_s, 24);
    sendEnvelope(peer, currentSnapshot);
    sendEnvelope(peer, currentPrompt);
    QTRY_COMPARE(client.rulesSession()->promptId(), 24);
    QCOMPARE(client.rulesSession()->gameId(), u"NEW123-1"_s);

    // A new connection can revisit the same room identifier with a fresh
    // sequence; the previous transport's watermark must not reject its prompt.
    QWebSocket *previousPeer = peer;
    client.connectTo(u"ws://127.0.0.1:%1"_s.arg(server.serverPort()), u"Alice"_s);
    QTRY_VERIFY(peer != previousPeer);
    sendEnvelope(peer, welcome);
    QTRY_VERIFY(client.connected());
    sendEnvelope(peer, created);
    sendEnvelope(peer, room);
    currentPrompt.payload.insert(u"promptId"_s, 25);
    sendEnvelope(peer, currentSnapshot);
    sendEnvelope(peer, currentPrompt);
    QTRY_COMPARE(client.rulesSession()->promptId(), 25);
    QVERIFY(client.lastError().isEmpty());
}

void TestWsClient::replayRetryIgnoresRepliesFromTimedOutDownload() const
{
    const QByteArray previousDataHome = qgetenv("XDG_DATA_HOME");
    qputenv("XDG_DATA_HOME", m_settingsDir.path().toUtf8());
    const auto restoreDataHome = qScopeGuard([&] {
        if (previousDataHome.isNull())
            qunsetenv("XDG_DATA_HOME");
        else
            qputenv("XDG_DATA_HOME", previousDataHome);
    });
    QWebSocketServer server(u"Replay retry correlation"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));
    QWebSocket *peer = nullptr;
    QList<Envelope> requests;
    connect(&server, &QWebSocketServer::newConnection, &server, [&] {
        peer = takeServerPeer(server);
        connect(peer, &QWebSocket::textMessageReceived, &server, [&](const QString &text) {
            bool ok = false;
            const auto request = hexproof::protocol::parse(text.toUtf8(), &ok);
            if (ok && request.type == hexproof::protocol::kTypeForgeReplayGet)
                requests.append(request);
        });
    });
    WsClient client;
    client.connectTo(u"ws://127.0.0.1:%1"_s.arg(server.serverPort()), u"Alice"_s);
    QTRY_VERIFY(peer);
    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.payload = {{u"v"_s, hexproof::protocol::kProtocolVersion},
                       {u"serverVersion"_s, buildVersion()}};
    sendEnvelope(peer, welcome);
    QTRY_VERIFY(client.connected());
    const QString replayId(64, u'c');
    client.replays()->acceptGrant(
        client.serverUrl(),
        {{u"replayId"_s, replayId}, {u"token"_s, QString(64, u'd')}, {u"finished"_s, true}});
    QSignalSpy failed(&client, &WsClient::commandFailed);
    QSignalSpy succeeded(&client, &WsClient::commandSucceeded);
    client.replays()->download(replayId);
    QTRY_COMPARE(requests.size(), 1);
    // Retry synchronously from the production timeout's failure notification.
    // Clearing the old correlation must not clear the newly queued request.
    bool retried = false;
    bool wasIdleAtTimeout = false;
    QString timeoutError;
    connect(&client, &WsClient::commandFailed, &client,
            [&](const QString &requestId, const QString &, const QVariantMap &, const QString &) {
                if (retried || requestId != requests.first().id)
                    return;
                retried = true;
                wasIdleAtTimeout = !client.replays()->busy();
                timeoutError = client.replays()->error();
                client.replays()->download(replayId);
            });
    QTRY_COMPARE_WITH_TIMEOUT(requests.size(), 2, 17000);
    QVERIFY(retried);
    QVERIFY(wasIdleAtTimeout);
    QVERIFY(!timeoutError.isEmpty());
    QCOMPARE(failed.count(), 1);
    QCOMPARE(failed.first().first().toString(), requests.first().id);
    bool ok = false;
    const auto snapshot = sharedFixture(u"rules-snapshot-owner.json"_s, &ok);
    QVERIFY(ok);
    Envelope page;
    page.type = hexproof::protocol::kTypeForgeReplayPage;
    page.id = requests.first().id;
    page.payload = {{u"replayId"_s, replayId},
                    {u"schemaVersion"_s, 1},
                    {u"offset"_s, 0},
                    {u"total"_s, 2},
                    {u"complete"_s, true},
                    {u"frames"_s, QJsonArray{QJsonObject{{u"sequence"_s, 1},
                                                         {u"snapshot"_s, snapshot.payload}}}}};
    sendEnvelope(peer, page);
    Envelope error;
    error.type = hexproof::protocol::kTypeError;
    error.id = requests.first().id;
    error.payload = {{u"code"_s, u"replay_unavailable"_s}, {u"message"_s, u"late failure"_s}};
    sendEnvelope(peer, error);
    Envelope boundary;
    boundary.type = hexproof::protocol::kTypeRoomListed;
    boundary.payload = {{u"rooms"_s, QJsonArray{}}};
    QSignalSpy boundaries(&client, &WsClient::roomListChanged);
    sendEnvelope(peer, boundary);
    QTRY_COMPARE(boundaries.count(), 1);
    QVERIFY(client.replays()->busy());
    QVERIFY(client.replays()->error().isEmpty());
    QCOMPARE(failed.count(), 1);
    QCOMPARE(client.replays()->count(), 0);
    QCOMPARE(requests.size(), 2);
    page.id = requests.at(1).id;
    sendEnvelope(peer, page);
    QTRY_COMPARE(requests.size(), 3);
    QCOMPARE(requests.last().payload.value(u"offset"_s).toInt(), 1);
    // A duplicate first page must not abort the subsequent page request.
    sendEnvelope(peer, page);
    page.id = requests.last().id;
    page.payload.insert(u"offset"_s, 1);
    page.payload.insert(u"frames"_s, QJsonArray{QJsonObject{{u"sequence"_s, 2},
                                                            {u"snapshot"_s, snapshot.payload}}});
    sendEnvelope(peer, page);
    QTRY_VERIFY(!client.replays()->busy());
    QCOMPARE(client.replays()->count(), 2);
    QCOMPARE(client.replays()->position(), 0);
    QVERIFY(client.replays()->error().isEmpty());
    QCOMPARE(failed.count(), 1);
    QCOMPARE(succeeded.count(), 2);
    client.replays()->download(replayId);
    QTRY_COMPARE(requests.size(), 4);
    error.id = requests.last().id;
    sendEnvelope(peer, error);
    QTRY_VERIFY(!client.replays()->busy());
    QVERIFY(client.replays()->error().contains(u"replay_unavailable"_s));
    QCOMPARE(failed.count(), 2);
}

void TestWsClient::deferredRulesSnapshotsCoalesceOnlyWithMatchingPrompt() const
{
    QWebSocketServer server(u"Rules snapshot batching"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));
    QWebSocket *peer = nullptr;
    connect(&server, &QWebSocketServer::newConnection, &server,
            [&]() { peer = takeServerPeer(server); });
    WsClient client;
    client.connectTo(u"ws://127.0.0.1:%1"_s.arg(server.serverPort()), u"Alice"_s);
    QTRY_VERIFY(peer);
    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.payload = {{u"v"_s, hexproof::protocol::kProtocolVersion},
                       {u"serverVersion"_s, buildVersion()}};
    sendEnvelope(peer, welcome);
    QTRY_VERIFY(client.connected());
    Envelope created;
    created.type = hexproof::protocol::kTypeRoomCreated;
    created.payload = {{u"roomId"_s, u"ABCDEF"_s}};
    sendEnvelope(peer, created);
    sendEnvelope(peer, roomSnapshot(u"Rules room"_s));
    QTRY_VERIFY(client.inRoom());

    bool ok = false;
    Envelope snapshot = sharedFixture(u"rules-snapshot-owner.json"_s, &ok);
    QVERIFY(ok);
    sendEnvelope(peer, snapshot);
    QTRY_COMPARE(client.rulesSession()->turn(), 1);
    Envelope prompt = sharedFixture(u"rules-prompt.json"_s, &ok);
    QVERIFY(ok);
    sendEnvelope(peer, prompt);
    QTRY_VERIFY(client.rulesSession()->promptPending());
    QSignalSpy snapshots(client.rulesSession(), &RulesSessionState::snapshotChanged);
    QSignalSpy boundaries(&client, &WsClient::roomListChanged);
    Envelope boundary;
    boundary.type = hexproof::protocol::kTypeRoomListed;
    boundary.payload = {{u"rooms"_s, QJsonArray{}}};

    // An obsolete prompt must not flush the replacement game's held snapshot.
    snapshot.seq += 1;
    snapshot.payload.insert(u"gameId"_s, u"ABCDEF-2"_s);
    snapshot.payload.insert(u"turn"_s, 2);
    snapshot.payload.insert(u"promptFollows"_s, true);
    sendEnvelope(peer, snapshot);
    sendEnvelope(peer, prompt);
    sendEnvelope(peer, boundary);
    QTRY_COMPARE_WITH_TIMEOUT(boundaries.count(), 1, 1000);
    QCOMPARE(snapshots.count(), 0);
    QCOMPARE(client.rulesSession()->gameId(), u"ABCDEF-1"_s);
    QVERIFY(client.lastError().isEmpty());
    prompt.payload.insert(u"gameId"_s, u"ABCDEF-2"_s);
    prompt.payload.insert(u"promptId"_s, 8);
    sendEnvelope(peer, prompt);
    QTRY_COMPARE(client.rulesSession()->gameId(), u"ABCDEF-2"_s);
    QCOMPARE(client.rulesSession()->turn(), 2);
    QCOMPARE(client.rulesSession()->promptId(), 8);
    const int coalescedChanges = snapshots.count();
    QVERIFY(coalescedChanges > 0);
    QTest::qWait(130);
    QCOMPARE(snapshots.count(), coalescedChanges);

    // A newer immediate snapshot supersedes the held update without painting it.
    snapshot.seq += 1;
    snapshot.payload.insert(u"turn"_s, 3);
    sendEnvelope(peer, snapshot);
    snapshot.seq += 1;
    snapshot.payload.insert(u"turn"_s, 4);
    snapshot.payload.remove(u"promptFollows"_s);
    sendEnvelope(peer, snapshot);
    QTRY_COMPARE(client.rulesSession()->turn(), 4);
    QCOMPARE(snapshots.count(), coalescedChanges + 1);
    QTest::qWait(130);
    QCOMPARE(snapshots.count(), coalescedChanges + 1);

    // A missing prompt still releases the current room's snapshot within the bound.
    snapshot.seq += 1;
    snapshot.payload.insert(u"turn"_s, 5);
    snapshot.payload.insert(u"promptFollows"_s, true);
    sendEnvelope(peer, snapshot);
    QTRY_COMPARE_WITH_TIMEOUT(client.rulesSession()->turn(), 5, 1000);
    QCOMPARE(snapshots.count(), coalescedChanges + 2);
}

void TestWsClient::deferredRulesSnapshotsDoNotSurviveLifecycleChanges_data() const
{
    QTest::addColumn<QString>("transition");
    for (const auto &transition :
         {u"kicked"_s, u"left"_s, u"disbanded"_s, u"waiting"_s, u"disconnect"_s, u"reconnect"_s,
          u"replaceTransport"_s, u"replaceRoom"_s})
        QTest::newRow(qPrintable(transition)) << transition;
}

void TestWsClient::deferredRulesSnapshotsDoNotSurviveLifecycleChanges() const
{
    QFETCH(QString, transition);
    QWebSocketServer server(u"Rules snapshot lifecycle"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));
    QList<QWebSocket *> peers;
    connect(&server, &QWebSocketServer::newConnection, &server, [&]() {
        QWebSocket *peer = takeServerPeer(server);
        peers.append(peer);
        connect(peer, &QWebSocket::textMessageReceived, &server, [peer](const QString &text) {
            bool ok = false;
            const auto hello = hexproof::protocol::parse(text.toUtf8(), &ok);
            if (!ok || hello.type != hexproof::protocol::kTypeSessionHello)
                return;
            Envelope welcome;
            welcome.type = hexproof::protocol::kTypeSessionWelcome;
            welcome.id = hello.id;
            welcome.payload = {{u"v"_s, hexproof::protocol::kProtocolVersion},
                               {u"serverVersion"_s, buildVersion()},
                               {u"resumeToken"_s, u"rules-resume-token"_s}};
            sendEnvelope(peer, welcome);
        });
    });
    WsClient client;
    const QString url = u"ws://127.0.0.1:%1"_s.arg(server.serverPort());
    client.connectTo(url, u"Alice"_s);
    QTRY_VERIFY(client.connected());
    QVERIFY(!peers.isEmpty());
    Envelope created;
    created.type = hexproof::protocol::kTypeRoomCreated;
    created.payload = {{u"roomId"_s, u"ABCDEF"_s}};
    sendEnvelope(peers.first(), created);
    Envelope room = roomSnapshot(u"Rules room"_s);
    room.payload.insert(u"phase"_s, hexproof::protocol::kRoomPhaseStarted);
    sendEnvelope(peers.first(), room);
    QTRY_VERIFY(client.inRoom());
    bool ok = false;
    Envelope snapshot = sharedFixture(u"rules-snapshot-owner.json"_s, &ok);
    QVERIFY(ok);
    sendEnvelope(peers.first(), snapshot);
    QTRY_COMPARE(client.rulesSession()->turn(), 1);
    snapshot.seq += 1;
    snapshot.payload.insert(u"turn"_s, 2);
    snapshot.payload.insert(u"promptFollows"_s, true);
    sendEnvelope(peers.first(), snapshot);

    Envelope boundary;
    boundary.type = hexproof::protocol::kTypeRoomListed;
    boundary.payload = {{u"rooms"_s, QJsonArray{}}};
    QSignalSpy boundaries(&client, &WsClient::roomListChanged);
    if (transition == u"disconnect"_s || transition == u"replaceTransport"_s) {
        connect(&client, &WsClient::roomListChanged, &client, [&]() {
            if (transition == u"disconnect"_s)
                client.disconnectFromHub();
            else
                client.connectTo(url, u"Alice"_s);
        });
        sendEnvelope(peers.first(), boundary);
    } else if (transition == u"reconnect"_s) {
        peers.first()->close();
    } else if (transition == u"waiting"_s) {
        room.seq += 1;
        room.payload.insert(u"phase"_s, hexproof::protocol::kRoomPhaseWaiting);
        sendEnvelope(peers.first(), room);
        sendEnvelope(peers.first(), boundary);
    } else if (transition == u"replaceRoom"_s) {
        created.payload.insert(u"roomId"_s, u"NEW123"_s);
        sendEnvelope(peers.first(), created);
        room.seq += 1;
        room.payload.insert(u"roomId"_s, u"NEW123"_s);
        sendEnvelope(peers.first(), room);
        sendEnvelope(peers.first(), boundary);
    } else {
        Envelope ended;
        ended.type = transition == u"kicked"_s ? hexproof::protocol::kTypeRoomKicked
                     : transition == u"left"_s ? hexproof::protocol::kTypeRoomLeft
                                               : hexproof::protocol::kTypeRoomDisbanded;
        ended.payload = {{u"roomId"_s, u"ABCDEF"_s}};
        sendEnvelope(peers.first(), ended);
        sendEnvelope(peers.first(), boundary);
    }
    if (transition == u"reconnect"_s)
        QTRY_VERIFY(client.reconnecting());
    else
        QTRY_COMPARE_WITH_TIMEOUT(boundaries.count(), 1, 1000);
    if (transition == u"replaceTransport"_s) {
        QTRY_COMPARE(peers.size(), 2);
        QTRY_VERIFY(client.connected());
    }
    if (transition != u"reconnect"_s && transition != u"replaceRoom"_s)
        QVERIFY(!client.rulesSession()->active());
    QSignalSpy snapshots(client.rulesSession(), &RulesSessionState::snapshotChanged);
    QTest::qWait(150);
    QCOMPARE(snapshots.count(), 0);
    if (transition == u"reconnect"_s || transition == u"replaceRoom"_s)
        QCOMPARE(client.rulesSession()->turn(), 1);
    else
        QVERIFY(!client.rulesSession()->active());
    QVERIFY(client.lastError().isEmpty());
    client.disconnectFromHub();
}

void TestWsClient::switchingServersIgnoresOldTransportCompletion() const
{
    QWebSocketServer first(u"First hub"_s, QWebSocketServer::NonSecureMode);
    QWebSocketServer second(u"Second hub"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(first.listen(QHostAddress::LocalHost, 0));
    QVERIFY(second.listen(QHostAddress::LocalHost, 0));
    QWebSocket *firstPeer = nullptr;
    bool secondHello = false;
    const auto welcome = [](QWebSocket *peer, const QString &id) {
        Envelope env;
        env.type = hexproof::protocol::kTypeSessionWelcome;
        env.id = id;
        env.payload = {{u"v"_s, hexproof::protocol::kProtocolVersion},
                       {u"serverVersion"_s, buildVersion()}};
        sendEnvelope(peer, env);
    };
    connect(&first, &QWebSocketServer::newConnection, &first, [&]() {
        firstPeer = takeServerPeer(first);
        connect(firstPeer, &QWebSocket::textMessageReceived, &first, [&](const QString &text) {
            bool ok = false;
            const auto env = hexproof::protocol::parse(text.toUtf8(), &ok);
            if (ok && env.type == hexproof::protocol::kTypeSessionHello)
                welcome(firstPeer, env.id);
        });
    });
    connect(&second, &QWebSocketServer::newConnection, &second, [&]() {
        QWebSocket *peer = takeServerPeer(second);
        connect(peer, &QWebSocket::textMessageReceived, &second, [&, peer](const QString &text) {
            bool ok = false;
            const auto env = hexproof::protocol::parse(text.toUtf8(), &ok);
            if (ok && env.type == hexproof::protocol::kTypeSessionHello) {
                secondHello = true;
                welcome(peer, env.id);
            }
        });
    });
    WsClient client;
    client.connectTo(u"ws://127.0.0.1:%1"_s.arg(first.serverPort()), u"Alice"_s);
    QTRY_VERIFY(client.connected());
    const QString secondUrl = u"ws://127.0.0.1:%1"_s.arg(second.serverPort());
    // Switch while the parser is delivering the first transport's final
    // message, before its queued disconnect notification reaches the GUI.
    connect(&client, &WsClient::roomListChanged, &client,
            [&]() { client.connectTo(secondUrl, u"Bob"_s); });
    Envelope finalMessage;
    finalMessage.type = hexproof::protocol::kTypeRoomListed;
    finalMessage.payload = {{u"rooms"_s, QJsonArray{}}};
    sendEnvelope(firstPeer, finalMessage);
    Envelope staleRoom;
    staleRoom.type = hexproof::protocol::kTypeRoomCreated;
    staleRoom.payload = {{u"roomId"_s, u"OLD123"_s}};
    sendEnvelope(firstPeer, staleRoom);
    firstPeer->sendTextMessage(u"invalid old message"_s);
    firstPeer->close();
    QTRY_VERIFY_WITH_TIMEOUT(secondHello, 2'000);
    QTRY_VERIFY(client.connected());
    QCOMPARE(client.serverUrl(), secondUrl);
    QCOMPARE(client.displayName(), u"Bob"_s);
    QVERIFY(client.roomId().isEmpty());
    QVERIFY(client.lastError().isEmpty());
}

void TestWsClient::cancelledConnectionIgnoresQueuedWelcome() const
{
    QWebSocketServer server(u"Cancelled hub"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));
    QWebSocket *peer = nullptr;
    connect(&server, &QWebSocketServer::newConnection, &server,
            [&]() { peer = takeServerPeer(server); });
    WsClient client;
    client.connectTo(u"ws://127.0.0.1:%1"_s.arg(server.serverPort()), u"Alice"_s);
    QTRY_VERIFY(peer);
    QSignalSpy welcomes(&client, &WsClient::welcomeReceived);
    connect(&client, &WsClient::roomListChanged, &client, &WsClient::disconnectFromHub);
    Envelope boundary;
    boundary.type = hexproof::protocol::kTypeRoomListed;
    boundary.payload = {{u"rooms"_s, QJsonArray{}}};
    sendEnvelope(peer, boundary);
    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.payload = {{u"v"_s, hexproof::protocol::kProtocolVersion},
                       {u"serverVersion"_s, buildVersion()},
                       {u"resumeToken"_s, u"cancelled-credential"_s}};
    sendEnvelope(peer, welcome);
    peer->close();
    QTRY_COMPARE(client.connectionState(), WsClient::Disconnected);
    QTest::qWait(50);
    QVERIFY(welcomes.isEmpty());
    QVERIFY(client.roomId().isEmpty());
    QVERIFY(QSettings().value(u"network/resumeToken"_s).toString().isEmpty());
}

void TestWsClient::resumesRoomAfterUnexpectedDisconnect_data() const
{
    QTest::addColumn<bool>("officialGuest");
    QTest::newRow("self-hosted") << false;
    QTest::newRow("official-guest") << true;
}

void TestWsClient::resumesRoomAfterUnexpectedDisconnect() const
{
    QFETCH(bool, officialGuest);
    QWebSocketServer server(u"Hexproof reconnect test server"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));
    const QString serverUrl = u"ws://127.0.0.1:"_s + QString::number(server.serverPort());
    QTemporaryDir directory;
    QFile config(directory.filePath(u"servers.json"_s));
    if (officialGuest) {
        QVERIFY(config.open(QIODevice::WriteOnly));
        config.write(
            QJsonDocument(
                QJsonObject{{u"schemaVersion"_s, 2},
                            {u"revision"_s, 1},
                            {u"servers"_s,
                             QJsonArray{QJsonObject{{u"id"_s, u"local"_s},
                                                    {u"name"_s, u"Local"_s},
                                                    {u"url"_s, serverUrl},
                                                    {u"forge"_s, false},
                                                    {u"accountRealm"_s, u"reconnect-test"_s}}}}})
                .toJson());
        config.close();
        qputenv("HEXPROOF_SERVER_DIRECTORY_FILE", config.fileName().toUtf8());
    }
    auto cleanup = qScopeGuard([] { qunsetenv("HEXPROOF_SERVER_DIRECTORY_FILE"); });

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
    if (officialGuest)
        client.connectAccountToServer(0, u"guest"_s, u"Alice"_s);
    else
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
    if (officialGuest)
        welcome.payload.insert(u"accountRealm"_s, u"reconnect-test"_s);
    sendEnvelope(peers[0], welcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 1000);
    QCOMPARE(client.account()->supported(), officialGuest);

    Envelope created;
    created.type = hexproof::protocol::kTypeRoomCreated;
    created.id = u"2"_s;
    created.payload = QJsonObject{{u"roomId"_s, u"ABCDEF"_s}};
    sendEnvelope(peers[0], created);
    Envelope beforeDrop = roomSnapshot(u"Room before drop"_s, true, true);
    beforeDrop.seq = 7;
    sendEnvelope(peers[0], beforeDrop);
    QTRY_VERIFY_WITH_TIMEOUT(client.inRoom(), 1000);

    QSettings settings;
    QCOMPARE(settings.value(u"network/resumeRoomRole"_s).toString(), u"player"_s);
    QCOMPARE(settings.value(u"network/resumeToken"_s).toString(), u"resume-secret"_s);

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
    if (officialGuest)
        prematureFreshWelcome.payload.insert(u"accountRealm"_s, u"reconnect-test"_s);
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
    if (officialGuest)
        resumed.payload.insert(u"accountRealm"_s, u"reconnect-test"_s);
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
