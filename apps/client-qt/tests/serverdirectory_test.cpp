// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/ServerDirectory.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QFile>
#include <QHostAddress>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QTest>
#include <QUrl>

using namespace Qt::StringLiterals;
using hexproof::client::ServerDirectory;

namespace {

void clearServerOverrides()
{
    qunsetenv("HEXPROOF_SERVER_1_URL");
    qunsetenv("HEXPROOF_SERVER_2_URL");
    qunsetenv("HEXPROOF_SERVER_3_URL");
    qunsetenv("HEXPROOF_SERVER_DIRECTORY_FILE");
}

} // namespace

class TestServerDirectory : public QObject
{
    Q_OBJECT

  private slots:
    void init();
    void cleanup();
    void exposesDefaultEndpoints() const;
    void loadsExternalDirectory() const;
    void appliesEnvironmentOverrides() const;
    void mapsConfiguredAndCustomUrls() const;
    void exposesInitialLatencyState() const;
    void probesConfiguredHealthEndpoints() const;
};

void TestServerDirectory::init()
{
    clearServerOverrides();
}

void TestServerDirectory::cleanup()
{
    clearServerOverrides();
}

void TestServerDirectory::exposesDefaultEndpoints() const
{
    ServerDirectory directory;
    for (int index = 0; index < ServerDirectory::ConfiguredServerCount; ++index) {
        const QUrl url(directory.serverUrl(index));
        QVERIFY(url.isValid());
        QVERIFY(!url.host().isEmpty());
        QVERIFY(url.scheme() == u"ws"_s || url.scheme() == u"wss"_s);
    }
    QVERIFY(directory.serverUrl(0) != directory.serverUrl(1));
    QVERIFY(directory.serverUrl(0) != directory.serverUrl(2));
    QVERIFY(directory.serverUrl(1) != directory.serverUrl(2));
}

void TestServerDirectory::loadsExternalDirectory() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString path = directory.filePath(u"servers.json"_s);
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    const QByteArray payload = R"({
  "schemaVersion": 1,
  "servers": [
    {
      "url": "ws://127.0.0.1:10001",
      "legacyUrls": ["ws://retired-primary.example:10001/ws"]
    },
    {"url": "wss://secondary.example/ws"},
    {"url": "wss://tertiary.example/ws"}
  ]
})";
    QCOMPARE(file.write(payload), payload.size());
    file.close();
    qputenv("HEXPROOF_SERVER_DIRECTORY_FILE", path.toUtf8());

    ServerDirectory serverDirectory;
    QCOMPARE(serverDirectory.serverUrl(0), u"ws://127.0.0.1:10001/ws"_s);
    QCOMPARE(serverDirectory.serverUrl(1), u"wss://secondary.example/ws"_s);
    QCOMPARE(serverDirectory.serverUrl(2), u"wss://tertiary.example/ws"_s);
    QCOMPARE(serverDirectory.normalizePersistedUrl(u"ws://retired-primary.example:10001/ws"_s),
             serverDirectory.serverUrl(0));
}

void TestServerDirectory::appliesEnvironmentOverrides() const
{
    qputenv("HEXPROOF_SERVER_1_URL", " ws://127.0.0.1:10001/ws ");
    qputenv("HEXPROOF_SERVER_2_URL", "wss://secondary.example/ws");
    qputenv("HEXPROOF_SERVER_3_URL", "wss://tertiary.example/ws");

    ServerDirectory directory;
    QCOMPARE(directory.serverUrl(0), u"ws://127.0.0.1:10001/ws"_s);
    QCOMPARE(directory.serverUrl(1), u"wss://secondary.example/ws"_s);
    QCOMPARE(directory.serverUrl(2), u"wss://tertiary.example/ws"_s);
}

void TestServerDirectory::mapsConfiguredAndCustomUrls() const
{
    ServerDirectory directory;
    QCOMPARE(directory.indexForUrl(directory.serverUrl(0)), 0);
    QCOMPARE(directory.indexForUrl(directory.serverUrl(1)), 1);
    QCOMPARE(directory.indexForUrl(directory.serverUrl(2)), 2);
    QVERIFY(directory.setCustomServerUrl(u" ws://127.0.0.1:57320 "_s));
    QCOMPARE(directory.customServerUrl(), u"ws://127.0.0.1:57320/ws"_s);
    QCOMPARE(directory.serverUrl(ServerDirectory::CustomServerIndex), directory.customServerUrl());
    QCOMPARE(directory.indexForUrl(directory.customServerUrl()),
             ServerDirectory::CustomServerIndex);
    QCOMPARE(directory.indexForUrl(u"wss://another.example/ws"_s),
             ServerDirectory::CustomServerIndex);
    QVERIFY(!directory.setCustomServerUrl(u"https://invalid.example/ws"_s));
    QCOMPARE(directory.customServerUrl(), u"ws://127.0.0.1:57320/ws"_s);
}

void TestServerDirectory::exposesInitialLatencyState() const
{
    ServerDirectory directory;
    const QVariantList latencies = directory.latencies();
    QCOMPARE(latencies.size(), ServerDirectory::ServerCount);
    QCOMPARE(latencies[0].toInt(), -2);
    QCOMPARE(latencies[1].toInt(), -2);
    QCOMPARE(latencies[2].toInt(), -2);
    QCOMPARE(latencies[3].toInt(), -2);
}

void TestServerDirectory::probesConfiguredHealthEndpoints() const
{
    QTcpServer server;
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));
    connect(&server, &QTcpServer::newConnection, &server, [&server]() {
        while (QTcpSocket *socket = server.nextPendingConnection()) {
            socket->setParent(&server);
            connect(socket, &QTcpSocket::readyRead, socket, [socket]() {
                socket->readAll();
                socket->write("HTTP/1.1 204 No Content\r\n"
                              "Content-Length: 0\r\n"
                              "Connection: close\r\n\r\n");
                socket->disconnectFromHost();
            });
        }
    });

    const QByteArray endpoint = "ws://127.0.0.1:" + QByteArray::number(server.serverPort()) + "/ws";
    qputenv("HEXPROOF_SERVER_1_URL", endpoint);
    qputenv("HEXPROOF_SERVER_2_URL", endpoint);
    qputenv("HEXPROOF_SERVER_3_URL", endpoint);

    ServerDirectory directory;
    QVERIFY(directory.setCustomServerUrl(QString::fromUtf8(endpoint)));
    QSignalSpy changed(&directory, &ServerDirectory::latenciesChanged);
    directory.refreshLatencies();

    QElapsedTimer deadline;
    deadline.start();
    QVariantList latencies;
    do {
        QCoreApplication::processEvents();
        latencies = directory.latencies();
        if (latencies.size() == ServerDirectory::ServerCount && latencies[0].toInt() >= 0 &&
            latencies[1].toInt() >= 0 && latencies[2].toInt() >= 0 && latencies[3].toInt() >= 0) {
            break;
        }
        QTest::qWait(10);
    } while (deadline.elapsed() < 5000);

    QCOMPARE(latencies.size(), ServerDirectory::ServerCount);
    QVERIFY(latencies[0].toInt() >= 0);
    QVERIFY(latencies[1].toInt() >= 0);
    QVERIFY(latencies[2].toInt() >= 0);
    QVERIFY(latencies[3].toInt() >= 0);
    QCOMPARE(changed.count(), 5);
}

QTEST_MAIN(TestServerDirectory)
#include "serverdirectory_test.moc"
