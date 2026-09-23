// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/ForgeReplayService.h"
#include <QFile>
#include <QJsonDocument>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QtEndian>

using namespace Qt::StringLiterals;
using hexproof::client::ForgeReplayService;
namespace {
const QString id(64, u'a');
const QString token(64, u'b');
const QString server = u"ws://localhost:57320"_s;
QJsonObject grant()
{
    return {{u"replayId"_s, id},         {u"token"_s, token},
            {u"roomName"_s, u"Study"_s}, {u"players"_s, QJsonArray{u"Alice"_s, u"Bob"_s}},
            {u"finished"_s, true},       {u"complete"_s, true}};
}
QJsonObject frame(int seq, int turn = 1, int game = 1)
{
    const QJsonObject card{{u"id"_s, u"hand-b"_s},
                           {u"visible"_s, true},
                           {u"identity"_s, QJsonObject{{u"name"_s, u"Lightning Bolt"_s}}}};
    const QJsonArray players{
        QJsonObject{{u"seat"_s, 0}, {u"name"_s, u"Alice"_s}, {u"life"_s, 20}},
        QJsonObject{{u"seat"_s, 1}, {u"name"_s, u"Bob"_s}, {u"life"_s, 20 - seq}}};
    const QJsonObject snapshot{
        {u"roomId"_s, u"study"_s},
        {u"gameId"_s, QString::number(game)},
        {u"turn"_s, turn},
        {u"activeSeat"_s, 0},
        {u"prioritySeat"_s, 1},
        {u"players"_s, players},
        {u"zones"_s, QJsonArray{QJsonObject{{u"zone"_s, u"hand"_s},
                                            {u"ownerSeat"_s, 1},
                                            {u"count"_s, 1},
                                            {u"cards"_s, QJsonArray{card}}}}},
        {u"stack"_s, QJsonArray{}}};
    return {{u"sequence"_s, seq},
            {u"gameNumber"_s, game},
            {u"kind"_s, u"SpellResolved"_s},
            {u"text"_s, u"Bob casts a spell during Alice's turn"_s},
            {u"actorSeat"_s, 1},
            {u"snapshot"_s, snapshot}};
}
QJsonObject page(int offset, const QJsonArray &frames, int total = 5)
{
    return {{u"replayId"_s, id}, {u"schemaVersion"_s, 1}, {u"offset"_s, offset},
            {u"total"_s, total}, {u"complete"_s, true},   {u"frames"_s, frames}};
}
} // namespace
class TestForgeReplay : public QObject
{
    Q_OBJECT
  private slots:
    void pagedDownloadSeekAndOfflineExport()
    {
        QTemporaryDir directory;
        ForgeReplayService service(nullptr, directory.path());
        QSignalSpy requests(&service, &ForgeReplayService::requestPage);
        service.acceptGrant(server, grant());
        QVERIFY(!service.entries().first().toMap().contains(u"token"_s));
        service.download(id);
        QVERIFY(service.busy());
        QCOMPARE(requests.size(), 1);
        QCOMPARE(requests.last().at(1).toJsonObject().value(u"token"_s).toString(), token);
        service.acceptPage(u"ws://wrong-server"_s, page(0, {frame(1), frame(2)}));
        QCOMPARE(requests.size(), 1);
        service.acceptPage(server, page(0, {frame(1), frame(2)}));
        QTRY_COMPARE(requests.last().at(1).toJsonObject().value(u"offset"_s).toInt(), 2);
        service.acceptPage(server, page(2, {frame(3, 2), frame(4, 2), frame(5, 1, 2)}));
        QVERIFY(!service.busy());
        QVERIFY2(service.error().isEmpty(), qPrintable(service.error()));
        QCOMPARE(service.count(), 5);
        QCOMPARE(service.position(), 0);
        QCOMPARE(service.session()->cardForInspection(u"hand-b"_s).value(u"name"_s).toString(),
                 u"Lightning Bolt"_s);
        service.nextTurn(1);
        QCOMPARE(service.position(), 2);
        service.nextTurn(1);
        QCOMPARE(service.position(), 4);
        service.nextTurn(-1);
        QCOMPARE(service.position(), 2);
        service.seek(1);
        const auto expected = service.frame();
        service.seek(4);
        service.seek(1);
        QCOMPARE(service.frame(), expected);
        service.step(-100);
        QCOMPARE(service.position(), 0);
        service.setSpeed(8);
        service.togglePlaying();
        QTRY_VERIFY_WITH_TIMEOUT(!service.playing(), 2000);
        QCOMPARE(service.position(), 4);

        const QString path = directory.filePath(u"export.hpr"_s);
        QVERIFY(service.exportFile(QUrl::fromLocalFile(path)));
        QFile file(path);
        QVERIFY(file.open(QIODevice::ReadOnly));
        const QByteArray raw =
            qUncompress(file.readAll().mid(QByteArray("HEXPROOF-REPLAY-1\n").size()));
        QVERIFY(!raw.contains(token.toUtf8()));
        QVERIFY(!raw.contains(server.toUtf8()));
        QTemporaryDir offlineDirectory;
        ForgeReplayService offline(nullptr, offlineDirectory.path());
        QVERIFY(offline.importFile(QUrl::fromLocalFile(path)));
        offline.seek(1);
        QCOMPARE(offline.frame(), expected);
        ForgeReplayService restarted(nullptr, offlineDirectory.path());
        QVERIFY(restarted.open(id));
        QCOMPARE(restarted.count(), 5);
    }
    void rejectsBrokenPagesAndFiles()
    {
        QTemporaryDir directory;
        ForgeReplayService service(nullptr, directory.path());
        service.acceptGrant(server, grant());
        service.download(id);
        service.acceptPage(server, page(1, {frame(1)}, 1));
        QVERIFY(!service.busy());
        QVERIFY(!service.error().isEmpty());
        QCOMPARE(service.count(), 0);
        service.download(id);
        auto invalid = frame(1);
        auto snapshot = invalid.value(u"snapshot"_s).toObject();
        snapshot.remove(u"roomId"_s);
        invalid.insert(u"snapshot"_s, snapshot);
        service.acceptPage(server, page(0, {invalid}, 1));
        QCOMPARE(service.count(), 0);
        QVERIFY(!service.error().isEmpty());
        service.download(id);
        service.fail(u"Disconnected"_s);
        QVERIFY(!service.busy());

        // A forged small prefix must not let zlib grow an unbounded buffer.
        QByteArray compressed = qCompress(QByteArray(1024 * 1024, 'x'));
        qToBigEndian<quint32>(16, compressed.data());
        QFile bomb(directory.filePath(u"bomb.hpr"_s));
        QVERIFY(bomb.open(QIODevice::WriteOnly));
        bomb.write("HEXPROOF-REPLAY-1\n");
        bomb.write(compressed);
        bomb.close();
        QVERIFY(!service.importFile(QUrl::fromLocalFile(bomb.fileName())));
        QCOMPARE(service.count(), 0);
    }
};
QTEST_GUILESS_MAIN(TestForgeReplay)
#include "forgereplay_test.moc"
