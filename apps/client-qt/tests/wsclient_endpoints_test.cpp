// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "wsclient_test.h"

#include <QRegularExpression>

void TestWsClient::prefillsInitialConnection_data()
{
    QTest::addColumn<QString>("scenario");
    for (const QString &scenario : {u"fresh"_s, u"legacy"_s, u"same-player"_s,
                                    u"different-server"_s, u"different-name"_s, u"spectator"_s})
        QTest::newRow(qPrintable(scenario)) << scenario;
}

void TestWsClient::prefillsInitialConnection() const
{
    QFETCH(QString, scenario);
    QWebSocketServer server(u"Launch defaults test"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));
    const QString baseUrl = u"ws://127.0.0.1:"_s + QString::number(server.serverPort());
    const QString url = baseUrl + u"/ws"_s;
    const QString name = u"Draft Seat 1"_s;
    QSettings settings;
    settings.setValue(u"preferences/retained"_s, u"unrelated setting"_s);
    if (scenario != u"fresh"_s) {
        settings.setValue(u"network/customServerUrl"_s, url);
        settings.setValue(u"network/resumeServerUrl"_s,
                          scenario == u"different-server"_s ? u"ws://127.0.0.1:1/ws"_s : url);
        settings.setValue(u"network/resumeDisplayName"_s,
                          scenario == u"different-name"_s ? u"Old Seat 1"_s : name);
        if (scenario != u"legacy"_s) {
            settings.setValue(u"network/resumeRoomRole"_s,
                              scenario == u"spectator"_s ? u"spectator"_s : u"player"_s);
            settings.setValue(u"network/resumeToken"_s, u"saved-token"_s);
            settings.setValue(u"network/resumeLastSeq"_s, 42);
        }
    }
    settings.sync();

    QList<Envelope> received;
    connect(&server, &QWebSocketServer::newConnection, &server, [&]() {
        QWebSocket *peer = takeServerPeer(server);
        connect(peer, &QWebSocket::textMessageReceived, &server, [&](const QString &text) {
            bool ok = false;
            const Envelope env = hexproof::protocol::parse(text.toUtf8(), &ok);
            if (ok)
                received.append(env);
        });
    });

    WsClient client;
    QVERIFY(client.setInitialConnection(u" "_s + baseUrl + u" "_s, u" "_s + name + u" "_s));
    QCOMPARE(client.serverUrl(), url);
    QCOMPARE(client.customServerUrl(), url);
    QCOMPARE(client.serverIndex(), ServerDirectory::CustomServerIndex);
    QCOMPARE(client.displayName(), name);
    QCOMPARE(client.connectionState(), WsClient::Disconnected);
    QVERIFY(!server.hasPendingConnections());
    QCOMPARE(settings.value(u"network/customServerUrl"_s).toString(), url);
    QCOMPARE(settings.value(u"preferences/retained"_s).toString(), u"unrelated setting"_s);
    const bool keepsResume = scenario == u"same-player"_s;
    for (const QString &key : {u"resumeToken"_s, u"resumeLastSeq"_s, u"resumeRoomRole"_s,
                               u"resumeServerUrl"_s, u"resumeDisplayName"_s})
        QCOMPARE(settings.contains(u"network/"_s + key), keepsResume);

    client.connectToCustomServer(client.customServerUrl(), client.displayName());
    QTRY_VERIFY_WITH_TIMEOUT(!received.isEmpty(), 1000);
    const Envelope hello = received.first();
    QCOMPARE(hello.type, hexproof::protocol::kTypeSessionHello);
    QCOMPARE(hello.payload.value(u"displayName"_s).toString(), name);
    QCOMPARE(hello.payload.contains(u"resumeToken"_s), keepsResume);
    if (keepsResume) {
        QCOMPARE(hello.payload.value(u"resumeToken"_s).toString(), u"saved-token"_s);
        QCOMPARE(hello.payload.value(u"lastSeq"_s).toInteger(), 42);
    }
    QVERIFY(!client.setInitialConnection(u"ws://127.0.0.1:1/ws"_s, u"New name"_s));
    QCOMPARE(client.serverUrl(), url);
    QCOMPARE(client.displayName(), name);
    client.disconnectFromHub();
}

void TestWsClient::rejectsInvalidInitialConnection() const
{
    WsClient client;
    QVERIFY(client.setInitialConnection(u"ws://127.0.0.1:57320/ws"_s, u"Test Player 1"_s));
    for (const QString &url : {QString{}, u" "_s, u"https://invalid.example/ws"_s, u"ws://"_s}) {
        QVERIFY(!client.setInitialConnection(url, u"New name"_s));
    }
    QVERIFY(!client.setInitialConnection(u"ws://127.0.0.1:1/ws"_s, u" "_s));
    QCOMPARE(client.connectionState(), WsClient::Disconnected);
    QCOMPARE(client.serverUrl(), u"ws://127.0.0.1:57320/ws"_s);
    QCOMPARE(client.customServerUrl(), client.serverUrl());
    QCOMPARE(client.displayName(), u"Test Player 1"_s);
    QSettings settings;
    QCOMPARE(settings.value(u"network/customServerUrl"_s).toString(), client.serverUrl());
}

void TestWsClient::loadsSavedResumeEndpoint() const
{
    QSettings settings;
    settings.setValue(u"network/resumeRoomRole"_s, u"player"_s);
    settings.setValue(u"network/resumeToken"_s, u"saved-token"_s);
    settings.setValue(u"network/resumeServerUrl"_s, u"ws://127.0.0.1:57320/ws"_s);
    settings.setValue(u"network/resumeDisplayName"_s, u"Saved player"_s);
    settings.setValue(u"network/resumeLastSeq"_s, 42);
    settings.sync();

    WsClient client;
    QCOMPARE(client.serverUrl(), u"ws://127.0.0.1:57320/ws"_s);
    QCOMPARE(client.serverIndex(), ServerDirectory::CustomServerIndex);
    QCOMPARE(client.customServerUrl(), u"ws://127.0.0.1:57320/ws"_s);
    QCOMPARE(client.displayName(), u"Saved player"_s);
}

void TestWsClient::loadsSecondaryPublicHubSelection() const
{
    const ServerDirectory directory;
    const QString secondaryUrl = directory.serverUrl(1);
    QSettings settings;
    settings.setValue(u"network/resumeRoomRole"_s, u"player"_s);
    settings.setValue(u"network/resumeToken"_s, u"saved-token"_s);
    settings.setValue(u"network/resumeServerUrl"_s, secondaryUrl);
    settings.sync();

    WsClient client;
    QCOMPARE(client.serverUrl(), secondaryUrl);
    QCOMPARE(client.serverIndex(), 1);
}

void TestWsClient::configuresAndPersistsCustomServer() const
{
    QTest::failOnWarning(QRegularExpression(u".*"_s));
    WsClient client;
    client.connectToCustomServer(u"https://invalid.example/ws"_s, u"Alice"_s);
    QVERIFY(client.lastError().startsWith(u"invalid_server_url:"_s));
    QCOMPARE(client.connectionState(), WsClient::Disconnected);

    client.connectToCustomServer(u" ws://127.0.0.1:9 "_s, u"Alice"_s);
    QCOMPARE(client.customServerUrl(), u"ws://127.0.0.1:9/ws"_s);
    QCOMPARE(client.serverUrl(), client.customServerUrl());
    QCOMPARE(client.serverIndex(), ServerDirectory::CustomServerIndex);

    QSettings settings;
    QCOMPARE(settings.value(u"network/customServerUrl"_s).toString(), client.customServerUrl());
    client.disconnectFromHub();
    QTRY_COMPARE_WITH_TIMEOUT(client.connectionState(), WsClient::Disconnected, 1000);
    QVERIFY(client.lastError().isEmpty());
}

void TestWsClient::migratesLegacyPrimaryPublicHubEndpoint() const
{
    const QString directoryPath = m_settingsDir.filePath(u"legacy-servers.json"_s);
    QFile directoryFile(directoryPath);
    QVERIFY(directoryFile.open(QIODevice::WriteOnly));
    const QByteArray directoryPayload = R"({
  "schemaVersion": 1,
  "servers": [
    {"url": "wss://primary.example/ws",
     "legacyUrls": ["ws://retired-primary.example:57320/ws"]},
    {"url": "wss://secondary.example/ws"},
    {"url": "wss://tertiary.example/ws"},
    {"url": "wss://quaternary.example/ws"},
    {"url": "wss://test.example/test/ws"}
  ]
})";
    QCOMPARE(directoryFile.write(directoryPayload), directoryPayload.size());
    directoryFile.close();
    qputenv("HEXPROOF_SERVER_DIRECTORY_FILE", directoryPath.toUtf8());

    QSettings settings;
    settings.setValue(u"network/resumeRoomRole"_s, u"player"_s);
    settings.setValue(u"network/resumeToken"_s, u"saved-token"_s);
    settings.setValue(u"network/resumeServerUrl"_s, u"ws://retired-primary.example:57320/ws"_s);
    settings.sync();

    WsClient client;
    QCOMPARE(client.serverUrl(), u"wss://primary.example/ws"_s);
    QCOMPARE(client.serverIndex(), 0);
}

void TestWsClient::exposesInitialServerLatencyState() const
{
    WsClient client;
    const QVariantList latencies = client.serverLatencies();
    QCOMPARE(latencies.size(), ServerDirectory::ServerCount);
    QCOMPARE(latencies[0].toInt(), -2);
    QCOMPARE(latencies[1].toInt(), -2);
    QCOMPARE(latencies[2].toInt(), -2);
    QCOMPARE(latencies[3].toInt(), -2);
    QCOMPARE(latencies[4].toInt(), -2);
    QCOMPARE(latencies[5].toInt(), -2);
}
