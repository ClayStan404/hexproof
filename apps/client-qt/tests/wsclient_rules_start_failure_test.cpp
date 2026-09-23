// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "wsclient_test.h"

namespace {
class StartFailureConnection
{
  public:
    QWebSocketServer server{u"Forge start failure test"_s, QWebSocketServer::NonSecureMode};
    QWebSocket *peer = nullptr;
    WsClient client;

    bool start(const QString &role = u"player"_s, bool host = true)
    {
        if (!server.listen(QHostAddress::LocalHost, 0))
            return false;
        QObject::connect(&server, &QWebSocketServer::newConnection, &server,
                         [&]() { peer = takeServerPeer(server); });
        client.connectTo(u"ws://127.0.0.1:"_s + QString::number(server.serverPort()), u"Alice"_s);
        if (!QTest::qWaitFor([&]() { return peer != nullptr; }, 1000))
            return false;
        Envelope welcome;
        welcome.type = hexproof::protocol::kTypeSessionWelcome;
        welcome.payload = {{u"v"_s, hexproof::protocol::kProtocolVersion},
                           {u"serverVersion"_s, buildVersion()}};
        sendEnvelope(peer, welcome);
        if (!QTest::qWaitFor([&]() { return client.connected(); }, 1000))
            return false;
        Envelope joined;
        joined.type = hexproof::protocol::kTypeRoomJoined;
        joined.payload = {{u"roomId"_s, u"ABCDEF"_s}, {u"role"_s, role}, {u"seat"_s, 0}};
        sendEnvelope(peer, joined);
        auto snapshot = waiting();
        auto seats = snapshot.payload.value(u"seats"_s).toArray();
        auto owner = seats.first().toObject();
        owner.insert(u"host"_s, host);
        seats[0] = owner;
        snapshot.payload.insert(u"seats"_s, seats);
        sendEnvelope(peer, snapshot);
        return QTest::qWaitFor([&]() { return client.inRoom(); }, 1000);
    }

    static Envelope waiting()
    {
        auto snapshot = roomSnapshot(u"Failure room"_s, true);
        snapshot.payload.insert(u"rulesMode"_s, u"forge"_s);
        snapshot.payload.insert(u"phase"_s, u"waiting"_s);
        return snapshot;
    }
};
} // namespace

void TestWsClient::rulesStartFailureSurvivesWaiting_data() const
{
    QTest::addColumn<bool>("errorFirst");
    QTest::addColumn<bool>("background");
    QTest::newRow("preload-error-first") << true << false;
    QTest::newRow("preload-room-first") << false << false;
    QTest::newRow("background-error-first") << true << true;
    QTest::newRow("background-room-first") << false << true;
}

void TestWsClient::rulesStartFailureSurvivesWaiting() const
{
    QFETCH(bool, errorFirst);
    QFETCH(bool, background);
    StartFailureConnection connection;
    QVERIFY(connection.start());
    auto &client = connection.client;
    auto active = StartFailureConnection::waiting();
    active.payload.insert(u"cardLoadMode"_s, background ? u"background"_s : u"preload"_s);
    active.payload.insert(u"phase"_s, background ? u"started"_s : u"loading"_s);
    active.payload.insert(u"loadId"_s, 1);
    sendEnvelope(connection.peer, active);
    QTRY_COMPARE(client.roomPhase(), background ? u"started"_s : u"loading"_s);

    bool ok = false;
    const Envelope failure = sharedFixture(u"rules-start-failure-owner.json"_s, &ok);
    QVERIFY(ok);
    auto waiting = StartFailureConnection::waiting();
    waiting.payload.insert(u"cardLoadMode"_s, background ? u"background"_s : u"preload"_s);
    QSignalSpy cancelled(&client, &WsClient::loadCancelled);
    sendEnvelope(connection.peer, errorFirst ? failure : waiting);
    sendEnvelope(connection.peer, errorFirst ? waiting : failure);
    QTRY_COMPARE(client.roomPhase(), u"waiting"_s);
    QTRY_COMPARE(client.rulesStartFailure().value(u"reason"_s).toString(), u"deck_rejected"_s);
    QCOMPARE(cancelled.size(), 1);
    const auto details = client.rulesStartFailure();
    QCOMPARE(details.value(u"issues"_s).toList().size(), 2);
    QVERIFY(client.lastError().startsWith(u"rules_unavailable:"_s));
    QVERIFY(client.seats().first().toMap().value(u"deckSelected"_s).toBool());

    // Sending a normal command clears the legacy string, but cannot erase the
    // actionable startup failure while the user reviews or changes their deck.
    client.requestRoomList();
    QVERIFY(client.lastError().isEmpty());
    QCOMPARE(client.rulesStartFailure(), details);
    sendEnvelope(connection.peer, waiting);
    QTest::qWait(10);
    QCOMPARE(client.rulesStartFailure(), details);

    Envelope load;
    load.type = hexproof::protocol::kTypeMatchLoadRequired;
    load.payload = {{u"loadId"_s, 2}, {u"cardKeys"_s, QJsonArray{}}};
    sendEnvelope(connection.peer, load);
    QTRY_VERIFY(client.rulesStartFailure().isEmpty());

    sendEnvelope(connection.peer, failure);
    QTRY_VERIFY(!client.rulesStartFailure().isEmpty());
    client.dismissRulesStartFailure();
    QVERIFY(client.rulesStartFailure().isEmpty());
    QVERIFY(client.lastError().isEmpty());

    sendEnvelope(connection.peer, failure);
    QTRY_VERIFY(!client.rulesStartFailure().isEmpty());
    Envelope started;
    started.type = hexproof::protocol::kTypeMatchStarted;
    started.payload = {{u"roomId"_s, u"ABCDEF"_s}, {u"loadId"_s, 2}};
    sendEnvelope(connection.peer, started);
    QTRY_VERIFY(client.rulesStartFailure().isEmpty());

    sendEnvelope(connection.peer, failure);
    QTRY_VERIFY(!client.rulesStartFailure().isEmpty());
    Envelope left;
    left.type = hexproof::protocol::kTypeRoomLeft;
    left.payload = {{u"roomId"_s, u"ABCDEF"_s}};
    sendEnvelope(connection.peer, left);
    QTRY_VERIFY(!client.inRoom());
    QVERIFY(client.rulesStartFailure().isEmpty());
    sendEnvelope(connection.peer, failure);
    QTest::qWait(10);
    QVERIFY(client.rulesStartFailure().isEmpty());
}

void TestWsClient::rulesStartFailureProjectsKnownRecipientDetails() const
{
    StartFailureConnection owner;
    StartFailureConnection spectator;
    StartFailureConnection otherPlayer;
    QVERIFY(owner.start());
    QVERIFY(spectator.start(u"spectator"_s, false));
    QVERIFY(otherPlayer.start(u"player"_s, false));
    bool ok = false;
    Envelope failure = sharedFixture(u"rules-start-failure-ai-host.json"_s, &ok);
    QVERIFY(ok);
    sendEnvelope(owner.peer, failure);
    sendEnvelope(spectator.peer, failure);
    sendEnvelope(otherPlayer.peer, failure);
    QTRY_VERIFY(!owner.client.rulesStartFailure().isEmpty());
    QTRY_VERIFY(!spectator.client.rulesStartFailure().isEmpty());
    QTRY_VERIFY(!otherPlayer.client.rulesStartFailure().isEmpty());
    QVERIFY(!owner.client.rulesStartFailure().value(u"issues"_s).toList().isEmpty());
    QVERIFY(spectator.client.rulesStartFailure().value(u"issues"_s).toList().isEmpty());
    QVERIFY(otherPlayer.client.rulesStartFailure().value(u"issues"_s).toList().isEmpty());

    auto detail = failure.payload.value(u"rulesStartFailure"_s).toObject();
    const QJsonObject safeIssue{{u"deck"_s, u"player"_s},
                                {u"section"_s, u"mainboard"_s},
                                {u"code"_s, u"printing_unavailable"_s},
                                {u"cardName"_s, u"Forest <literal> %2"_s},
                                {u"setCode"_s, u"M21"_s},
                                {u"collectorNumber"_s, u"999"_s},
                                {u"exception"_s, u"secret-stack-and-deck"_s}};
    QJsonArray issues;
    for (int index = 0; index < 33; ++index)
        issues.append(safeIssue);
    detail.insert(u"issues"_s, issues);
    detail.insert(u"exception"_s, u"secret-java-trace"_s);
    failure.payload.insert(u"rulesStartFailure"_s, detail);
    sendEnvelope(owner.peer, failure);
    QTRY_COMPARE(owner.client.rulesStartFailure().value(u"issues"_s).toList().size(), 32);
    const auto projected = owner.client.rulesStartFailure();
    QVERIFY(projected.value(u"truncated"_s).toBool());
    QVERIFY(!projected.contains(u"exception"_s));
    const auto issue = projected.value(u"issues"_s).toList().first().toMap();
    QVERIFY(!issue.contains(u"exception"_s));
    QCOMPARE(issue.value(u"cardName"_s).toString(), u"Forest <literal> %2"_s);

    auto invalidIssue = safeIssue;
    invalidIssue.insert(u"cardName"_s, u"private\nlog injection"_s);
    invalidIssue.insert(u"setCode"_s, QString(65, u'x'));
    auto unknownIssue = safeIssue;
    unknownIssue.insert(u"code"_s, u"java_exception"_s);
    detail.insert(u"issues"_s, QJsonArray{invalidIssue, unknownIssue});
    failure.payload.insert(u"rulesStartFailure"_s, detail);
    sendEnvelope(owner.peer, failure);
    QTRY_COMPARE(owner.client.rulesStartFailure().value(u"issues"_s).toList().size(), 1);
    const auto bounded =
        owner.client.rulesStartFailure().value(u"issues"_s).toList().first().toMap();
    QVERIFY(!bounded.contains(u"cardName"_s));
    QVERIFY(!bounded.contains(u"setCode"_s));

    owner.client.dismissRulesStartFailure();
    detail.insert(u"reason"_s, u"raw_exception"_s);
    failure.payload.insert(u"rulesStartFailure"_s, detail);
    sendEnvelope(owner.peer, failure);
    QTest::qWait(10);
    QVERIFY(owner.client.rulesStartFailure().isEmpty());

    const auto timeout = sharedFixture(u"rules-start-failure-timeout.json"_s, &ok);
    QVERIFY(ok);
    sendEnvelope(owner.peer, timeout);
    QTRY_COMPARE(owner.client.rulesStartFailure().value(u"reason"_s).toString(),
                 u"runtime_timeout"_s);
    QVERIFY(owner.client.rulesStartFailure().value(u"issues"_s).toList().isEmpty());
}
