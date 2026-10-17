// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#include "forgecrashreport_fixture.h"
#include "services/ForgeCrashReportService.h"
#include <QClipboard>
#include <QFile>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using namespace Qt::StringLiterals;
using namespace hexproof::client;
class TestForgeCrashReport : public QObject
{
    Q_OBJECT
  private slots:
    void sharedProtocolFixturesRemainIntact()
    {
        for (const auto &name :
             {u"error-forge-crash-edh.json"_s, u"error-forge-crash-partial.json"_s}) {
            const auto path = QFINDTESTDATA(qPrintable(u"../../../testdata/protocol/v1/"_s + name));
            QVERIFY(!path.isEmpty());
            QFile file(path);
            QVERIFY(file.open(QIODevice::ReadOnly));
            const auto value = QJsonDocument::fromJson(file.readAll())
                                   .object()
                                   .value(u"payload"_s)
                                   .toObject()
                                   .value(u"rulesCrashReport"_s)
                                   .toObject();
            QVERIFY(!value.isEmpty());
            QCOMPARE(normalizedForgeCrashReport(value), value);
        }
    }
    void acceptsGoNanosecondTimestampWithoutLosingPrecision()
    {
        QTemporaryDir directory;
        const auto now = QDateTime::fromString(u"2026-10-08T10:30:01Z"_s, Qt::ISODate);
        const auto timestamp = u"2026-10-08T10:30:00.123456789Z"_s;
        ForgeCrashReportService service(nullptr, directory.path(), [now] { return now; });
        auto value = crashReportFixture(now);
        value.insert(u"occurredAt"_s, timestamp);
        QVERIFY(service.accept(value));
        const auto id = value.value(u"reportId"_s).toString();
        QCOMPARE(service.noticeId(), id);
        QCOMPARE(service.report(id).value(u"occurredAt"_s).toString(), timestamp);
        QVERIFY(service.reportText(id).contains(timestamp));
        ForgeCrashReportService restored(nullptr, directory.path(), [now] { return now; });
        QCOMPARE(restored.report(id).value(u"occurredAt"_s).toString(), timestamp);
    }
    void projectsOnlySafeFields()
    {
        const auto now = QDateTime::currentDateTimeUtc();
        auto input = crashReportFixture(now);
        input.insert(u"resumeToken"_s, u"PRIVATE_TOKEN"_s);
        auto failure = input.value(u"failure"_s).toObject();
        failure.insert(u"message"_s, u"PRIVATE_CARD_AND_PATH"_s);
        input.insert(u"failure"_s, failure);
        const auto safe = normalizedForgeCrashReport(input);
        QVERIFY(!safe.isEmpty());
        const auto bytes = QJsonDocument(safe).toJson();
        QVERIFY(!bytes.contains("PRIVATE"));
        QVERIFY(bytes.contains("DrawEffect"));
        QVERIFY(bytes.contains("Divination"));
        QCOMPARE(safe.value(u"environment"_s).toObject().value(u"participants"_s).toInt(), 4);
        input.insert(u"occurredAt"_s, u"2026-10-08T12:00:00.123456789Z"_s);
        QVERIFY(!normalizedForgeCrashReport(input).isEmpty());
        input.insert(u"revision"_s, 3);
        QVERIFY(normalizedForgeCrashReport(input).isEmpty());
    }
    void rejectsPrivateSourcesAndMalformedSymbols()
    {
        auto input = crashReportFixture(QDateTime::currentDateTimeUtc());
        auto context = input.value(u"context"_s).toObject();
        auto source = context.value(u"sources"_s).toArray().first().toObject();
        source.insert(u"zone"_s, u"hand"_s);
        context.insert(u"sources"_s, QJsonArray{source});
        input.insert(u"context"_s, context);
        QVERIFY(normalizedForgeCrashReport(input).isEmpty());
        input = crashReportFixture(QDateTime::currentDateTimeUtc());
        auto failure = input.value(u"failure"_s).toObject();
        failure.insert(u"causes"_s,
                       QJsonArray{QJsonObject{{u"className"_s, u"/home/secret/card"_s}}});
        input.insert(u"failure"_s, failure);
        QVERIFY(normalizedForgeCrashReport(input).isEmpty());
        input = crashReportFixture(QDateTime::currentDateTimeUtc());
        input.insert(u"oversized"_s, QString(65536, u'x'));
        QVERIFY(normalizedForgeCrashReport(input).isEmpty());
    }
    void revisionsDismissalAndRestart()
    {
        QTemporaryDir directory;
        const auto now = QDateTime::currentDateTimeUtc();
        const auto input = crashReportFixture(now);
        const auto id = input.value(u"reportId"_s).toString();
        {
            ForgeCrashReportService service(nullptr, directory.path());
            QVERIFY(service.accept(input));
            QCOMPARE(service.noticeId(), id);
            service.dismiss(id);
            QVERIFY(service.noticeId().isEmpty());
            QVERIFY(service.accept(crashReportFixture(now, id, 2)));
            QVERIFY(service.noticeId().isEmpty());
            QCOMPARE(service.entries().size(), 1);
            QCOMPARE(service.report(id).value(u"revision"_s).toInt(), 2);
            QVERIFY(service.accept(input));
            QCOMPARE(service.report(id).value(u"revision"_s).toInt(), 2);
            QVERIFY(service.storageError().isEmpty());
        }
        ForgeCrashReportService restored(nullptr, directory.path());
        QCOMPARE(restored.entries().size(), 1);
        QVERIFY(restored.noticeId().isEmpty());
        QVERIFY(restored.accept(input));
        QVERIFY(restored.noticeId().isEmpty());
        QVERIFY(restored.copyReport(id));
        QCOMPARE(restored.operationReportId(), id);
        QVERIFY(QGuiApplication::clipboard()->text().contains(u"DrawEffect"_s));
        const auto url = QUrl::fromLocalFile(directory.filePath(u"export.json"_s));
        QVERIFY(restored.saveReport(id, url));
        QCOMPARE(restored.operationReportId(), id);
        QFile saved(url.toLocalFile());
        QVERIFY(saved.open(QIODevice::ReadOnly));
        QCOMPARE(QJsonDocument::fromJson(saved.readAll()).object().value(u"reportId"_s).toString(),
                 id);
    }
    void duplicateAndRevisionNeverRenewExpiry()
    {
        QTemporaryDir directory;
        auto now = QDateTime::currentDateTimeUtc();
        const auto occurred = now;
        const auto id = QString(32, u'a');
        ForgeCrashReportService service(nullptr, directory.path(), [&] { return now; });
        QVERIFY(service.accept(crashReportFixture(occurred)));
        const auto firstReceipt = service.entries().first().toMap().value(u"firstReceived"_s);
        now = now.addDays(6);
        QVERIFY(service.accept(crashReportFixture(occurred, id, 2)));
        QCOMPARE(service.entries().first().toMap().value(u"firstReceived"_s), firstReceipt);
        now = now.addDays(1);
        QVERIFY(service.report(id).isEmpty());
        QVERIFY(!service.copyReport(id));
        QVERIFY(
            !service.saveReport(id, QUrl::fromLocalFile(directory.filePath(u"expired.json"_s))));
        QVERIFY(service.accept(crashReportFixture(occurred, id, 2)));
        QVERIFY(service.entries().isEmpty());
        QVERIFY(service.noticeId().isEmpty());
        QVERIFY(!QFile::exists(directory.filePath(u"expired.json"_s)));
    }
    void boundsHistoryAndSurvivesDiskFailure()
    {
        QTemporaryDir directory;
        const auto now = QDateTime::currentDateTimeUtc();
        ForgeCrashReportService service(nullptr, directory.path());
        for (int i = 0; i < 70; ++i)
            QVERIFY(service.accept(
                crashReportFixture(now, QString::number(i, 16).rightJustified(32, u'0'))));
        QCOMPARE(service.entries().size(), 64);
        QFile history(directory.filePath(u"history.json"_s));
        QVERIFY(history.size() <= 4 * 1024 * 1024);
        QFile blocked(directory.filePath(u"not-a-directory"_s));
        QVERIFY(blocked.open(QIODevice::WriteOnly));
        blocked.close();
        ForgeCrashReportService memoryOnly(nullptr, blocked.fileName());
        QVERIFY(memoryOnly.accept(crashReportFixture(now)));
        QVERIFY(!memoryOnly.noticeId().isEmpty());
        QVERIFY(!memoryOnly.storageError().isEmpty());
        QVERIFY(memoryOnly.copyReport(QString(32, u'a')));
        QVERIFY(memoryOnly.saveReport(QString(32, u'a'),
                                      QUrl::fromLocalFile(directory.filePath(u"rescue.json"_s))));
    }
};
QTEST_MAIN(TestForgeCrashReport)
#include "forgecrashreport_test.moc"
