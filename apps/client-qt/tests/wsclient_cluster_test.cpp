// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "wsclient_test.h"

#include <QCryptographicHash>
#include <QJsonDocument>

void TestWsClient::clusterTransferConsumesPrivateCommandOnce() const
{
    hexproof::client::ClusterTransfer transfer;
    const QByteArray wire = R"({"private":"command"})";
    transfer.track(u"request"_s, u"room.create"_s, wire);
    hexproof::protocol::Envelope route;
    route.id = u"request"_s;
    route.payload = {{u"url"_s, u"ws://target/ws"_s},
                     {u"realm"_s, u"test"_s},
                     {u"nodeId"_s, u"N2"_s},
                     {u"ticket"_s, QString(64, u'a')}};
    QVERIFY(!transfer.acceptRoute(route, u"ws://origin/ws"_s, u"test"_s, {}, {}, true));
    QVERIFY(transfer.pending());
    QVERIFY(!transfer.routed());
    QVERIFY(
        transfer.acceptRoute(route, u"ws://origin/ws"_s, u"test"_s, u"test"_s, u"owner"_s, true));
    QVERIFY(transfer.routing());
    QVERIFY(!transfer.ticket().isEmpty());
    hexproof::protocol::Envelope welcome;
    welcome.payload = {{u"accountId"_s, u"other"_s}};
    QVERIFY(transfer.takeCommand(welcome, u"N2"_s).isEmpty());
    welcome.payload.insert(u"accountId"_s, u"owner"_s);
    QCOMPARE(transfer.takeCommand(welcome, u"N2"_s), wire);
    QVERIFY(transfer.takeCommand(welcome, u"N2"_s).isEmpty());
    QVERIFY(transfer.ticket().isEmpty());
    QVERIFY(transfer.pending());
    QVERIFY(
        !transfer.acceptRoute(route, u"ws://target/ws"_s, u"test"_s, u"test"_s, u"owner"_s, true));
    transfer.resolve(u"unrelated"_s);
    QVERIFY(transfer.pending());
    transfer.resolve(u"request"_s);
    QVERIFY(!transfer.pending());
    QVERIFY(!transfer.routed());
}

void TestWsClient::routesOfficialCommandOnce_data()
{
    QTest::addColumn<QString>("scenario");
    for (const auto &name :
         {"success", "credential", "wrong-realm", "unlisted", "wrong-id", "wrong-node", "dropped"})
        QTest::newRow(name) << QString::fromLatin1(name);
}

void TestWsClient::routesOfficialCommandOnce() const
{
    QFETCH(QString, scenario);
    using namespace hexproof::protocol;
    QWebSocketServer origin(u"Origin"_s, QWebSocketServer::NonSecureMode);
    QWebSocketServer target(u"Target"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(origin.listen(QHostAddress::LocalHost, 0));
    QVERIFY(target.listen(QHostAddress::LocalHost, 0));
    const QString sourceUrl = u"ws://127.0.0.1:%1/ws"_s.arg(origin.serverPort());
    const QString targetUrl = u"ws://127.0.0.1:%1/ws"_s.arg(target.serverPort());
    QTemporaryDir directory;
    QFile config(directory.filePath(u"servers.json"_s));
    QVERIFY(config.open(QIODevice::WriteOnly));
    QJsonArray nodes;
    for (const auto &url : {sourceUrl, targetUrl}) {
        if (scenario == u"unlisted"_s && url == targetUrl)
            continue;
        nodes.append(QJsonObject{{u"id"_s, url == sourceUrl ? u"source"_s : u"target"_s},
                                 {u"name"_s, u"Local"_s},
                                 {u"url"_s, url},
                                 {u"forge"_s, false},
                                 {u"accountRealm"_s, u"cluster-client-test"_s}});
    }
    config.write(
        QJsonDocument(
            QJsonObject{{u"schemaVersion"_s, 2}, {u"revision"_s, 1}, {u"servers"_s, nodes}})
            .toJson());
    config.close();
    qputenv("HEXPROOF_SERVER_DIRECTORY_FILE", config.fileName().toUtf8());
    if (scenario == u"credential"_s) {
        const auto key =
            QCryptographicHash::hash(targetUrl.toUtf8(), QCryptographicHash::Sha256).toHex();
        QSettings settings;
        settings.setValue(u"officialNodes/cluster-client-test/N2"_s, targetUrl);
        settings.setValue(u"tournaments/"_s + QString::fromLatin1(key) + u"/ABCDEF"_s,
                          u"guest-token"_s);
    }
    QList<Envelope> sourceMessages, targetMessages;
    QWebSocket *sourcePeer = nullptr;
    auto attach = [&](QWebSocketServer &server, QList<Envelope> &messages, bool destination) {
        connect(&server, &QWebSocketServer::newConnection, &server, [&, destination] {
            QWebSocket *peer = takeServerPeer(server);
            if (!destination)
                sourcePeer = peer;
            connect(peer, &QWebSocket::textMessageReceived, &server,
                    [&, peer, destination](const QString &wire) {
                        bool ok = false;
                        const Envelope incoming = parse(wire.toUtf8(), &ok);
                        QVERIFY(ok);
                        messages.append(incoming);
                        if (incoming.type != kTypeSessionHello)
                            return;
                        Envelope welcome;
                        welcome.type = kTypeSessionWelcome;
                        welcome.id = incoming.id;
                        welcome.payload = {
                            {u"v"_s, kProtocolVersion},
                            {u"serverVersion"_s, buildVersion()},
                            {u"connectionId"_s, u"connection"_s},
                            {u"resumeToken"_s, u"resume"_s},
                            {u"accountRealm"_s, u"cluster-client-test"_s},
                            {u"clusterNode"_s,
                             destination && scenario != u"wrong-node"_s ? u"N2"_s : u"N1"_s}};
                        sendEnvelope(peer, welcome);
                    });
        });
    };
    attach(origin, sourceMessages, false);
    attach(target, targetMessages, true);
    WsClient client;
    QSignalSpy queued(&client, &WsClient::commandQueued);
    QSignalSpy succeeded(&client, &WsClient::commandSucceeded);
    QSignalSpy failed(&client, &WsClient::commandFailed);
    QSignalSpy welcomed(&client, &WsClient::welcomeReceived);
    client.connectToOfficial(u"guest"_s, u"Player"_s);
    QTRY_VERIFY(client.connected());
    QVERIFY(client.clusterAvailable());
    QCOMPARE(client.globalCode(u"ABCDEF"_s), u"N1:ABCDEF"_s);
    client.joinRoom(u"N2:ABCDEF"_s, false, u"private-password"_s);
    QTRY_VERIFY(sourceMessages.size() >= 2);
    const auto original = sourceMessages.last();
    QCOMPARE(original.type, kTypeRoomJoin);
    if (scenario == u"credential"_s)
        QCOMPARE(original.payload.value(u"credential"_s).toString(), u"guest-token"_s);
    Envelope route;
    route.type = kTypeSessionRoute;
    route.id = scenario == u"wrong-id"_s ? u"unrelated-request"_s : original.id;
    route.payload = {
        {u"url"_s, targetUrl},
        {u"nodeId"_s, u"N2"_s},
        {u"realm"_s, scenario == u"wrong-realm"_s ? u"untrusted"_s : u"cluster-client-test"_s},
        {u"ticket"_s, QString(64, u'a')}};
    sendEnvelope(sourcePeer, route);
    if (scenario == u"wrong-realm"_s || scenario == u"unlisted"_s || scenario == u"wrong-id"_s) {
        QTRY_VERIFY(!client.connected());
        QCOMPARE(targetMessages.size(), 0);
    } else if (scenario == u"wrong-node"_s) {
        QTRY_VERIFY(!failed.isEmpty());
        QCOMPARE(targetMessages.size(), 1);
    } else {
        QTRY_VERIFY(targetMessages.size() >= 2);
        QCOMPARE(targetMessages[0].payload.value(u"clusterTicket"_s).toString(), QString(64, u'a'));
        QCOMPARE(targetMessages[1].id, original.id);
        QCOMPARE(targetMessages[1].type, original.type);
        QCOMPARE(targetMessages[1].payload, original.payload);
        QCOMPARE(welcomed.count(), 1); // Routing does not bounce back to the main menu.
        QCOMPARE(client.serverUrl(), targetUrl);
        if (scenario == u"success"_s || scenario == u"credential"_s) {
            Envelope reply;
            reply.type = kTypeError;
            reply.id = original.id;
            reply.payload = {{u"code"_s, u"wrong_password"_s}, {u"message"_s, u"Wrong password"_s}};
            const auto peers = target.findChildren<QWebSocket *>();
            QVERIFY(!peers.isEmpty());
            sendEnvelope(peers.last(), reply);
            QTRY_VERIFY(!failed.isEmpty());
            QCOMPARE(client.globalCode(u"ABCDEF"_s), u"N2:ABCDEF"_s);
        } else {
            const auto peers = target.findChildren<QWebSocket *>();
            QVERIFY(!peers.isEmpty());
            peers.last()->abort();
            QTRY_VERIFY(!client.connected());
            QTest::qWait(150);
            QCOMPARE(targetMessages.size(), 2);
        }
    }
    for (const auto &success : succeeded)
        QVERIFY(success[0].toString() != original.id); // A route is not command success.
    int queuedOriginal = 0;
    for (const auto &command : queued) {
        queuedOriginal += command[0].toString() == original.id;
        QVERIFY(!command[2].toMap().contains(u"clusterTicket"_s));
    }
    QCOMPARE(queuedOriginal, 1);
    client.disconnectFromHub();
}
