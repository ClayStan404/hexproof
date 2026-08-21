// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "protocol/Message.h"
#include "services/WsClient.h"

#include <QElapsedTimer>
#include <QFileInfo>
#include <QProcess>
#include <QRegularExpression>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QVariantList>
#include <QVariantMap>

#include <algorithm>

using namespace Qt::StringLiterals;
using namespace hexproof::client;

namespace {

QVariantMap modernDeck(const QString &name)
{
    return {
        {u"name"_s, name},
        {u"format"_s, hexproof::protocol::kFormatModern},
        {u"commander"_s, QString{}},
        {u"mainboard"_s, QVariantList{QVariantMap{
                             {u"name"_s, u"Lightning Bolt"_s},
                             {u"count"_s, 10},
                             {u"setCode"_s, u"M11"_s},
                             {u"collectorNumber"_s, u"149"_s},
                             {u"typeLine"_s, u"Instant"_s},
                         }}},
        {u"sideboard"_s, QVariantList{}},
    };
}

QVariantList zoneForSeat(const WsClient &client, int seat, const QString &zone)
{
    const QVariantList seats = client.gameSeats();
    if (seat < 0 || seat >= seats.size())
        return {};
    return seats.at(seat).toMap().value(zone).toList();
}

bool zoneContains(const WsClient &client, int seat, const QString &zone, const QString &cardId)
{
    const QVariantList cards = zoneForSeat(client, seat, zone);
    return std::ranges::any_of(cards, [&cardId](const QVariant &value) {
        return value.toMap().value(u"id"_s).toString() == cardId;
    });
}

class TestServerProcess final
{
  public:
    ~TestServerProcess()
    {
        stop();
    }

    bool start(const QString &binary, const QString &retentionDirectory, QString *webSocketUrl,
               QString *error)
    {
        m_process.setProgram(binary);
        m_process.setArguments({
            u"-bind"_s,
            u"127.0.0.1"_s,
            u"-port"_s,
            u"0"_s,
            u"-retention-dir"_s,
            retentionDirectory,
            u"-hello-timeout"_s,
            u"2s"_s,
        });
        m_process.setProcessChannelMode(QProcess::SeparateChannels);
        m_process.start();
        if (!m_process.waitForStarted(5000)) {
            *error = m_process.errorString();
            return false;
        }

        QElapsedTimer timer;
        timer.start();
        QByteArray output;
        const QRegularExpression readyPattern(
            u"listening on 127\\.0\\.0\\.1:(\\d+) \\(ws path /ws"_s);
        while (timer.elapsed() < 5000) {
            m_process.waitForReadyRead(100);
            output += m_process.readAllStandardOutput();
            const QRegularExpressionMatch match = readyPattern.match(QString::fromUtf8(output));
            if (match.hasMatch()) {
                *webSocketUrl = u"ws://127.0.0.1:"_s + match.captured(1) + u"/ws"_s;
                return true;
            }
            if (m_process.state() == QProcess::NotRunning) {
                *error = QStringLiteral("server exited before readiness: %1")
                             .arg(QString::fromUtf8(m_process.readAllStandardError()));
                return false;
            }
        }
        *error = QStringLiteral("server readiness timed out; stdout=%1 stderr=%2")
                     .arg(QString::fromUtf8(output),
                          QString::fromUtf8(m_process.readAllStandardError()));
        return false;
    }

    void stop()
    {
        if (m_process.state() == QProcess::NotRunning)
            return;
        m_process.terminate();
        if (!m_process.waitForFinished(5000)) {
            m_process.kill();
            m_process.waitForFinished(2000);
        }
    }

  private:
    QProcess m_process;
};

} // namespace

class TestServerIntegration final : public QObject
{
    Q_OBJECT

  private slots:
    void realServerSupportsRoomAndGameFlow() const;
};

void TestServerIntegration::realServerSupportsRoomAndGameFlow() const
{
    QString serverBinary = qEnvironmentVariable("HEXPROOF_SERVER_BINARY");
    if (serverBinary.isEmpty())
        serverBinary = QStringLiteral(HEXPROOF_DEFAULT_SERVER_BINARY);
    const QString missingBinary =
        u"Build the Go server at "_s + serverBinary +
        u" or set HEXPROOF_SERVER_BINARY; the integration test cannot be skipped."_s;
    QVERIFY2(QFileInfo(serverBinary).isExecutable(), qPrintable(missingBinary));

    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    TestServerProcess server;
    QString webSocketUrl;
    QString serverError;
    QVERIFY2(
        server.start(serverBinary, directory.filePath(u"retained"_s), &webSocketUrl, &serverError),
        qPrintable(serverError));

    WsClient host;
    WsClient guest;
    host.connectTo(webSocketUrl, u"Alice"_s);
    guest.connectTo(webSocketUrl, u"Bob"_s);
    QTRY_VERIFY_WITH_TIMEOUT(host.connected(), 5000);
    QTRY_VERIFY_WITH_TIMEOUT(guest.connected(), 5000);

    host.createRoom(u"Qt-Go integration"_s, hexproof::protocol::kFormatModern,
                    hexproof::protocol::kDeckFormatCustom, true, hexproof::protocol::kMatchBO1,
                    hexproof::protocol::kCardLoadPreload, {});
    QTRY_VERIFY_WITH_TIMEOUT(host.inRoom(), 5000);
    QTRY_VERIFY_WITH_TIMEOUT(!host.roomId().isEmpty(), 5000);
    const QString roomId = host.roomId();
    QCOMPARE(host.seatIndex(), 0);
    QVERIFY(host.youAreHost());

    guest.joinRoom(roomId, false, {});
    QTRY_VERIFY_WITH_TIMEOUT(guest.inRoom(), 5000);
    QCOMPARE(guest.seatIndex(), 1);
    QTRY_VERIFY_WITH_TIMEOUT(host.seats().size() == 2, 5000);
    QTRY_VERIFY_WITH_TIMEOUT(
        host.seats().at(1).toMap().value(u"displayName"_s).toString() == u"Bob"_s, 5000);

    host.selectDeck(modernDeck(u"Host Burn"_s));
    guest.selectDeck(modernDeck(u"Guest Burn"_s));
    QTRY_COMPARE_WITH_TIMEOUT(host.selectedDeckName(), u"Host Burn"_s, 5000);
    QTRY_COMPARE_WITH_TIMEOUT(guest.selectedDeckName(), u"Guest Burn"_s, 5000);

    QSignalSpy hostLoadRequired(&host, &WsClient::loadRequired);
    QSignalSpy guestLoadRequired(&guest, &WsClient::loadRequired);
    host.setReady(true);
    guest.setReady(true);
    QTRY_COMPARE_WITH_TIMEOUT(hostLoadRequired.count(), 1, 5000);
    QTRY_COMPARE_WITH_TIMEOUT(guestLoadRequired.count(), 1, 5000);
    const qint64 hostLoadId = hostLoadRequired.at(0).at(0).toLongLong();
    const qint64 guestLoadId = guestLoadRequired.at(0).at(0).toLongLong();
    QVERIFY(hostLoadId > 0);
    QCOMPARE(guestLoadId, hostLoadId);

    QSignalSpy hostStarted(&host, &WsClient::matchStarted);
    QSignalSpy guestStarted(&guest, &WsClient::matchStarted);
    host.completeLoad(hostLoadId);
    guest.completeLoad(guestLoadId);
    QTRY_COMPARE_WITH_TIMEOUT(hostStarted.count(), 1, 5000);
    QTRY_COMPARE_WITH_TIMEOUT(guestStarted.count(), 1, 5000);
    QTRY_COMPARE_WITH_TIMEOUT(host.gameNumber(), 1, 5000);
    QTRY_COMPARE_WITH_TIMEOUT(guest.gameNumber(), 1, 5000);

    QTRY_COMPARE_WITH_TIMEOUT(zoneForSeat(host, 0, hexproof::protocol::kZoneHand).size(), 7, 5000);
    QTRY_COMPARE_WITH_TIMEOUT(zoneForSeat(guest, 1, hexproof::protocol::kZoneHand).size(), 7, 5000);
    QCOMPARE(zoneForSeat(guest, 0, hexproof::protocol::kZoneHand).size(), 0);

    const QString cardId = zoneForSeat(host, 0, hexproof::protocol::kZoneHand)
                               .first()
                               .toMap()
                               .value(u"id"_s)
                               .toString();
    QVERIFY(!cardId.isEmpty());
    host.moveCard(cardId, hexproof::protocol::kZoneHand, hexproof::protocol::kZoneBattlefield,
                  QVariantMap{{u"x"_s, 0.25}, {u"y"_s, 0.5}});
    QTRY_VERIFY_WITH_TIMEOUT(zoneContains(host, 0, hexproof::protocol::kZoneBattlefield, cardId),
                             5000);
    QTRY_VERIFY_WITH_TIMEOUT(zoneContains(guest, 0, hexproof::protocol::kZoneBattlefield, cardId),
                             5000);
    QCOMPARE(zoneForSeat(host, 0, hexproof::protocol::kZoneHand).size(), 6);
    QCOMPARE(zoneForSeat(guest, 0, hexproof::protocol::kZoneHand).size(), 0);

    host.disconnectFromHub();
    guest.disconnectFromHub();
    QTRY_VERIFY_WITH_TIMEOUT(!host.connected(), 5000);
    QTRY_VERIFY_WITH_TIMEOUT(!guest.connected(), 5000);
}

QTEST_GUILESS_MAIN(TestServerIntegration)
#include "server_integration_test.moc"
