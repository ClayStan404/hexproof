// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#include "forgecrashreport_fixture.h"
#include "wsclient_test.h"
#include <QUuid>

void TestWsClient::crashReportsBypassUnrelatedCommandErrors() const
{
    QWebSocketServer server(u"Crash report delivery"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));
    QWebSocket *peer = nullptr;
    QList<Envelope> received;
    connect(&server, &QWebSocketServer::newConnection, &server, [&] {
        peer = takeServerPeer(server);
        connect(peer, &QWebSocket::textMessageReceived, &server, [&](const QString &text) {
            bool ok = false;
            const auto envelope = hexproof::protocol::parse(text.toUtf8(), &ok);
            if (ok)
                received.append(envelope);
        });
    });
    WsClient client;
    client.connectTo(u"ws://127.0.0.1:"_s + QString::number(server.serverPort()), u"Alice"_s);
    QTRY_VERIFY_WITH_TIMEOUT(!received.isEmpty(), 1000);
    QCOMPARE(received.first().payload.value(u"rulesCrashReportSchema"_s).toInt(), 1);
    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.payload = {{u"v"_s, hexproof::protocol::kProtocolVersion},
                       {u"connectionId"_s, u"crash-report-test"_s},
                       {u"serverVersion"_s, buildVersion()}};
    sendEnvelope(peer, welcome);
    QTRY_VERIFY(client.connected());
    QSignalSpy failed(&client, &WsClient::commandFailed);
    QSignalSpy queued(&client, &WsClient::commandQueued);
    client.setCardTapped(u"card-a"_s, true);
    QTRY_COMPARE(queued.size(), 1);
    const auto pendingId = queued.first().at(0).toString();
    const auto id = QUuid::createUuid().toString(QUuid::Id128);
    const auto now = QDateTime::currentDateTimeUtc();
    Envelope error;
    error.type = hexproof::protocol::kTypeError;
    error.payload = {{u"code"_s, u"rules_unavailable"_s},
                     {u"message"_s, u"engine failure"_s},
                     {u"rulesCrashReport"_s, crashReportFixture(now, id)}};
    sendEnvelope(peer, error);
    QTRY_COMPARE(client.crashReports()->noticeId(), id);
    QCOMPARE(failed.size(), 0);
    QVERIFY(client.lastError().isEmpty());
    client.crashReports()->dismiss(id);
    error.payload.insert(u"rulesCrashReport"_s, crashReportFixture(now, id, 2));
    sendEnvelope(peer, error);
    QTRY_COMPARE(client.crashReports()->report(id).value(u"revision"_s).toInt(), 2);
    QVERIFY(client.crashReports()->noticeId().isEmpty());
    QCOMPARE(failed.size(), 0);
    error.id = pendingId;
    sendEnvelope(peer, error);
    QTRY_COMPARE(failed.size(), 1);
    QCOMPARE(failed.first().at(0).toString(), pendingId);
    QVERIFY(client.lastError().isEmpty());
    client.disconnectFromHub();
    QVERIFY(!client.crashReports()->report(id).isEmpty());
}
