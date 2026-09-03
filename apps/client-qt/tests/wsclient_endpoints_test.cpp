// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "wsclient_test.h"

void TestWsClient::loadsSavedResumeEndpoint() const
{
    QSettings settings;
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
    settings.setValue(u"network/resumeToken"_s, u"saved-token"_s);
    settings.setValue(u"network/resumeServerUrl"_s, secondaryUrl);
    settings.sync();

    WsClient client;
    QCOMPARE(client.serverUrl(), secondaryUrl);
    QCOMPARE(client.serverIndex(), 1);
}

void TestWsClient::configuresAndPersistsCustomServer() const
{
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
