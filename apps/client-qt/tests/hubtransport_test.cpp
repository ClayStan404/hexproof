// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/HubTransport.h"
#include "services/WsClient.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QUrlQuery>
#include <QtWebSockets/QWebSocketServer>
#include <cstdio>
#include <iostream>

using namespace Qt::StringLiterals;
using namespace hexproof::client;

namespace {
void publish(const QJsonObject &object)
{
    const QByteArray wire = QJsonDocument(object).toJson(QJsonDocument::Compact) + '\n';
    std::fwrite(wire.constData(), 1, size_t(wire.size()), stdout);
    std::fflush(stdout);
}

void record(const QJsonObject &object)
{
    QFile file(qEnvironmentVariable("HEXPROOF_HOME_TEST_TRACE"));
    if (file.open(QIODevice::WriteOnly | QIODevice::Append))
        file.write(QJsonDocument(object).toJson(QJsonDocument::Compact) + '\n');
}

// This executable is copied next to the isolated test under the bundled helper
// name. Exercise actual pipes, EOF and process exits without modifying the app.
int runHelper()
{
    std::string line;
    if (!std::getline(std::cin, line))
        return 2;
    const QJsonObject config = QJsonDocument::fromJson(QByteArray::fromStdString(line)).object();
    record(config);
    const QUrl url(config.value(u"url"_s).toString());
    const QString mode = QUrlQuery(url).queryItemValue(u"mode"_s);
    if (mode == u"exit-before"_s)
        return 1;
    publish({{u"state"_s, u"connected"_s},
             {u"transport"_s, config.value(u"forceRelay"_s).toBool() ? u"relay"_s : u"direct"_s}});
    while (std::getline(std::cin, line)) {
        const QJsonObject command =
            QJsonDocument::fromJson(QByteArray::fromStdString(line)).object();
        record(command);
        if (mode == u"oversize"_s) {
            publish({{u"message"_s, QJsonObject{{u"text"_s, QString(4096, u'x')}}}});
        } else if (mode == u"session"_s) {
            const QJsonObject request = command.value(u"message"_s).toObject();
            publish({{u"message"_s,
                      QJsonObject{{u"v"_s, u"hexproof.v1"_s},
                                  {u"type"_s, u"session.welcome"_s},
                                  {u"id"_s, request.value(u"id"_s)},
                                  {u"payload"_s, QJsonObject{{u"v"_s, u"hexproof.v1"_s},
                                                             {u"serverVersion"_s,
                                                              QStringLiteral(HEXPROOF_VERSION)},
                                                             {u"connectionId"_s, u"home-test"_s},
                                                             {u"resumeToken"_s, u"new-token"_s},
                                                             {u"resumed"_s, true},
                                                             {u"roomId"_s, u"ABCDEF"_s},
                                                             {u"role"_s, u"player"_s},
                                                             {u"seat"_s, 0},
                                                             {u"host"_s, true}}}}}});
        } else {
            publish(command);
        }
        if (mode == u"exit-after"_s || mode == u"exit-without-close"_s) {
            if (mode == u"exit-after"_s)
                publish({{u"state"_s, u"closed"_s}});
            return 1;
        }
    }
    record({{u"eof"_s, true}});
    // A cancelled helper may race with its parent opening a new connection.
    publish({{u"message"_s, QJsonObject{{u"stale"_s, true}}}});
    publish({{u"state"_s, u"connected"_s}, {u"transport"_s, u"direct"_s}});
    return 0;
}

QString bundledHelper()
{
    QString path = QDir(QCoreApplication::applicationDirPath()).filePath(u"hexproof-forge-host"_s);
#ifdef Q_OS_WIN
    path += u".exe"_s;
#endif
    return path;
}
} // namespace

class HubTransportTest : public QObject
{
    Q_OBJECT

  private:
    QTemporaryDir m_directory;
    QByteArray m_oldTrace;
    QByteArray m_oldRelay;
    QByteArray m_oldTurn;

    QList<QJsonObject> records() const
    {
        QFile file(m_directory.filePath(u"trace"_s));
        QList<QJsonObject> values;
        if (!file.open(QIODevice::ReadOnly))
            return values;
        for (const QByteArray &line : file.readAll().split('\n')) {
            if (!line.isEmpty())
                values.append(QJsonDocument::fromJson(line).object());
        }
        return values;
    }

    bool sawEof() const
    {
        for (const auto &record : records()) {
            if (record.value(u"eof"_s).toBool())
                return true;
        }
        return false;
    }

  private slots:
    void initTestCase()
    {
        QVERIFY(m_directory.isValid());
        m_oldTrace = qgetenv("HEXPROOF_HOME_TEST_TRACE");
        m_oldRelay = qgetenv("HEXPROOF_HOME_FORCE_RELAY");
        m_oldTurn = qgetenv("HEXPROOF_HOME_FORCE_TURN");
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_directory.path());
        QCoreApplication::setOrganizationName(u"HexproofHubTransportTest"_s);
        QCoreApplication::setApplicationName(u"HexproofHubTransportTest"_s);
        qputenv("HEXPROOF_HOME_TEST_TRACE", m_directory.filePath(u"trace"_s).toUtf8());
    }

    void init()
    {
        QFile::remove(m_directory.filePath(u"trace"_s));
        qunsetenv("HEXPROOF_HOME_FORCE_RELAY");
        qunsetenv("HEXPROOF_HOME_FORCE_TURN");
        QSettings().clear();
    }

    void cleanupTestCase()
    {
        qputenv("HEXPROOF_HOME_TEST_TRACE", m_oldTrace);
        qputenv("HEXPROOF_HOME_FORCE_RELAY", m_oldRelay);
        qputenv("HEXPROOF_HOME_FORCE_TURN", m_oldTurn);
    }

    void recognizesOnlyHomeEndpoints_data()
    {
        QTest::addColumn<QString>("url");
        QTest::addColumn<bool>("home");
        QTest::newRow("secure") << u"wss://hub.example/home/debian/ws"_s << true;
        QTest::newRow("loopback") << u"ws://127.0.0.1:1234/home/radxa-32g/ws"_s << true;
        QTest::newRow("ipv6-loopback") << u"ws://[::1]/home/radxa/ws"_s << true;
        QTest::newRow("plain") << u"wss://hub.example/ws"_s << false;
        QTest::newRow("insecure-wan") << u"ws://hub.example/home/debian/ws"_s << false;
        QTest::newRow("credentials") << u"wss://user:secret@hub.example/home/debian/ws"_s << false;
        QTest::newRow("missing-node") << u"wss://hub.example/home//ws"_s << false;
        QTest::newRow("invalid-node") << u"wss://hub.example/home/Debian_1/ws"_s << false;
        QTest::newRow("other-path") << u"wss://hub.example/home/debian/ws/other"_s << false;
    }

    void recognizesOnlyHomeEndpoints()
    {
        QFETCH(QString, url);
        QFETCH(bool, home);
        QCOMPARE(HubTransport::isHomeUrl(QUrl(url)), home);
    }

    void normalWebSocketAndMissingHelper_data()
    {
        QTest::addColumn<bool>("home");
        QTest::newRow("ordinary-websocket") << false;
        QTest::newRow("missing-home-helper") << true;
    }

    void normalWebSocketAndMissingHelper()
    {
        QFETCH(bool, home);
        QWebSocketServer server(u"transport"_s, QWebSocketServer::NonSecureMode);
        QVERIFY(server.listen(QHostAddress::LocalHost, 0));
        connect(&server, &QWebSocketServer::newConnection, &server, [&]() {
            QWebSocket *peer = server.nextPendingConnection();
            peer->setParent(&server);
            connect(peer, &QWebSocket::textMessageReceived, peer, &QWebSocket::sendTextMessage);
        });
        HubTransport transport(home ? m_directory.filePath(u"missing"_s) : bundledHelper());
        QSignalSpy connected(&transport, &HubTransport::connected);
        QSignalSpy received(&transport, &HubTransport::textMessageReceived);
        QSignalSpy disconnected(&transport, &HubTransport::disconnected);
        const QUrl url(u"ws://127.0.0.1:%1%2"_s.arg(server.serverPort())
                           .arg(home ? u"/home/test/ws"_s : u"/ws"_s));
        transport.open(url);
        QTRY_COMPARE(connected.size(), 1);
        QCOMPARE(transport.transportState(), home ? u"relay"_s : QString{});
        QCOMPARE(transport.url(), url);
        QVERIFY(transport.sendTextMessage(u"ordinary text"_s) > 0);
        QTRY_COMPARE(received.size(), 1);
        QCOMPARE(received.first().first().toString(), u"ordinary text"_s);
        transport.ping("test");
        transport.close();
        QTRY_COMPARE(disconnected.size(), 1);
        QVERIFY(records().isEmpty());
    }

    void homeHelperKeepsUrlAndStopsAtEof_data()
    {
        QTest::addColumn<bool>("forceRelay");
        QTest::newRow("direct") << false;
        QTest::newRow("relay") << true;
    }

    void homeHelperKeepsUrlAndStopsAtEof()
    {
        QFETCH(bool, forceRelay);
        if (forceRelay)
            qputenv("HEXPROOF_HOME_FORCE_RELAY", "1");
        HubTransport transport;
        QSignalSpy connected(&transport, &HubTransport::connected);
        QSignalSpy received(&transport, &HubTransport::textMessageReceived);
        QSignalSpy disconnected(&transport, &HubTransport::disconnected);
        const QUrl url(u"ws://127.0.0.1:7/home/debian/ws?mode=echo"_s);
        transport.open(url);
        QTRY_COMPARE(connected.size(), 1);
        QCOMPARE(transport.transportState(), forceRelay ? u"relay"_s : u"direct"_s);
        QCOMPARE(records().first().value(u"url"_s).toString(), url.toString());
        QCOMPARE(transport.url(), url);
        QVERIFY(transport.sendTextMessage(u"{\"type\":\"session.ping\",\"id\":\"1\"}"_s) > 0);
        QTRY_COMPARE(received.size(), 1);
        QCOMPARE(QJsonDocument::fromJson(received.first().first().toString().toUtf8())
                     .object()
                     .value(u"id"_s),
                 u"1"_s);
        transport.close();
        QTRY_VERIFY(sawEof());
        QCOMPARE(disconnected.size(), 1);
        QCOMPARE(connected.size(), 1);
        QCOMPARE(received.size(), 1);
    }

    void failureBeforeFirstMessageUsesOriginalRelayUrl()
    {
        QWebSocketServer server(u"relay"_s, QWebSocketServer::NonSecureMode);
        QVERIFY(server.listen(QHostAddress::LocalHost, 0));
        QSignalSpy accepted(&server, &QWebSocketServer::newConnection);
        HubTransport transport;
        QSignalSpy connected(&transport, &HubTransport::connected);
        const QUrl url(
            u"ws://127.0.0.1:%1/home/test/ws?mode=exit-before"_s.arg(server.serverPort()));
        transport.open(url);
        QTRY_COMPARE(connected.size(), 1);
        QCOMPARE(accepted.size(), 1);
        QCOMPARE(transport.transportState(), u"relay"_s);
        QWebSocket *peer = server.nextPendingConnection();
        peer->setParent(&server);
        QCOMPARE(peer->requestUrl().path(), url.path());
        QCOMPARE(peer->requestUrl().query(), url.query());
        transport.abort();
    }

    void failureAfterMessageNeverReplaysOnRelay_data()
    {
        QTest::addColumn<QString>("mode");
        QTest::newRow("closed-event") << u"exit-after"_s;
        QTest::newRow("process-exit") << u"exit-without-close"_s;
    }

    void forceTurnNeverFallsBackToWebSocket_data()
    {
        QTest::addColumn<bool>("missingHelper");
        QTest::newRow("helper-missing") << true;
        QTest::newRow("connection-failed") << false;
    }

    void forceTurnNeverFallsBackToWebSocket()
    {
        QFETCH(bool, missingHelper);
        qputenv("HEXPROOF_HOME_FORCE_TURN", "1");
        QWebSocketServer server(u"must require TURN"_s, QWebSocketServer::NonSecureMode);
        QVERIFY(server.listen(QHostAddress::LocalHost, 0));
        QSignalSpy accepted(&server, &QWebSocketServer::newConnection);
        HubTransport transport(missingHelper ? m_directory.filePath(u"missing"_s)
                                             : bundledHelper());
        QSignalSpy connected(&transport, &HubTransport::connected);
        QSignalSpy disconnected(&transport, &HubTransport::disconnected);
        transport.open(
            QUrl(u"ws://127.0.0.1:%1/home/test/ws?mode=exit-before"_s.arg(server.serverPort())));
        QTRY_COMPARE(disconnected.size(), 1);
        QCOMPARE(transport.state(), QAbstractSocket::UnconnectedState);
        QVERIFY(!transport.errorString().isEmpty());
        QVERIFY(connected.isEmpty());
        QVERIFY(accepted.isEmpty());
        if (!missingHelper) {
            QVERIFY(!records().isEmpty());
            QVERIFY(records().first().value(u"forceTURN"_s).toBool());
        }
    }

    void failureAfterMessageNeverReplaysOnRelay()
    {
        QFETCH(QString, mode);
        QWebSocketServer server(u"must not replay"_s, QWebSocketServer::NonSecureMode);
        QVERIFY(server.listen(QHostAddress::LocalHost, 0));
        QSignalSpy accepted(&server, &QWebSocketServer::newConnection);
        HubTransport transport;
        QStringList events;
        connect(&transport, &HubTransport::textMessageReceived, &transport,
                [&]() { events.append(u"message"_s); });
        connect(&transport, &HubTransport::disconnected, &transport,
                [&]() { events.append(u"closed"_s); });
        transport.open(
            QUrl(u"ws://127.0.0.1:%1/home/test/ws?mode=%2"_s.arg(server.serverPort()).arg(mode)));
        QTRY_COMPARE(transport.state(), QAbstractSocket::ConnectedState);
        QVERIFY(transport.sendTextMessage(u"{\"type\":\"game.draw\",\"id\":\"draw-once\"}"_s) > 0);
        QTRY_COMPARE(transport.state(), QAbstractSocket::UnconnectedState);
        QCOMPARE(events, QStringList({u"message"_s, u"closed"_s}));
        QCOMPARE(accepted.size(), 0);
        QCOMPARE(records().size(), 2);
    }

    void replacedHelperCannotDeliverOldMessagesOrDisconnect()
    {
        HubTransport transport;
        QSignalSpy connected(&transport, &HubTransport::connected);
        QSignalSpy received(&transport, &HubTransport::textMessageReceived);
        QSignalSpy disconnected(&transport, &HubTransport::disconnected);
        transport.open(QUrl(u"ws://127.0.0.1:7/home/old/ws"_s));
        QTRY_COMPARE(connected.size(), 1);
        transport.open(QUrl(u"ws://127.0.0.1:7/home/new/ws"_s));
        QTRY_COMPARE(connected.size(), 2);
        QTRY_VERIFY(sawEof());
        QVERIFY(transport.sendTextMessage(u"{\"current\":true}"_s) > 0);
        QTRY_COMPARE(received.size(), 1);
        QCOMPARE(QJsonDocument::fromJson(received.first().first().toString().toUtf8()).object(),
                 QJsonObject({{u"current"_s, true}}));
        QCOMPARE(disconnected.size(), 1);
        QCOMPARE(transport.state(), QAbstractSocket::ConnectedState);
    }

    void oversizedHelperMessageClosesTheSession()
    {
        HubTransport transport;
        transport.setMaxAllowedIncomingMessageSize(1024);
        QSignalSpy received(&transport, &HubTransport::textMessageReceived);
        transport.open(QUrl(u"ws://127.0.0.1:7/home/test/ws?mode=oversize"_s));
        QTRY_COMPARE(transport.state(), QAbstractSocket::ConnectedState);
        QVERIFY(transport.sendTextMessage(u"{\"request\":true}"_s) > 0);
        QTRY_COMPARE(transport.state(), QAbstractSocket::UnconnectedState);
        QVERIFY(received.isEmpty());
    }

    void clientResumeUsesLogicalHomeUrl()
    {
        const QString url = u"ws://127.0.0.1:7/home/debian/ws?mode=session"_s;
        QSettings settings;
        settings.setValue(u"network/resumeRoomRole"_s, u"player"_s);
        settings.setValue(u"network/resumeToken"_s, u"saved-token"_s);
        settings.setValue(u"network/resumeServerUrl"_s, url);
        settings.setValue(u"network/resumeDisplayName"_s, u"Home player"_s);
        settings.setValue(u"network/resumeLastSeq"_s, 42);
        settings.sync();
        WsClient client;
        client.connectTo(url, u"Home player"_s);
        QTRY_VERIFY(records().size() >= 2);
        QTRY_COMPARE(settings.value(u"network/resumeToken"_s).toString(), u"new-token"_s);
        QCOMPARE(client.serverUrl(), url);
        QCOMPARE(client.serverTransportState(), u"direct"_s);
        QCOMPARE(settings.value(u"network/resumeServerUrl"_s).toString(), url);
        const QJsonObject hello = records()[1].value(u"message"_s).toObject();
        QCOMPARE(hello.value(u"type"_s), u"session.hello"_s);
        QCOMPARE(hello.value(u"payload"_s).toObject().value(u"resumeToken"_s), u"saved-token"_s);
        QCOMPARE(hello.value(u"payload"_s).toObject().value(u"lastSeq"_s).toInt(), 42);
        client.disconnectFromHub();
    }
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (app.arguments().contains(u"--home-connect"_s))
        return runHelper();
    HubTransportTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "hubtransport_test.moc"
