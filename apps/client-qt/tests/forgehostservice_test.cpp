// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/ForgeHostService.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QScopeGuard>
#include <QTemporaryDir>
#include <QTest>
#include <QThread>
#include <cstdio>
#include <memory>

using namespace hexproof::client;
using namespace Qt::StringLiterals;

namespace {
bool writeFile(const QString &path, const QByteArray &data = {})
{
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(data) == data.size();
}

QByteArray readFile(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray{};
}

void publish(const QJsonObject &event)
{
    const QByteArray line = QJsonDocument(event).toJson(QJsonDocument::Compact) + '\n';
    std::fwrite(line.constData(), 1, static_cast<size_t>(line.size()), stdout);
    std::fflush(stdout);
}

void publishState(const QString &state)
{
    publish({{u"state"_s, state},
             {u"version"_s, u"2.0.5"_s},
             {u"runtimeId"_s, QString(40, u'a') + u"-adapter15-"_s + QString(64, u'b')}});
}

// CMake copies this test executable into an isolated directory under the
// helper's name. Exercise the production QProcess path without Java, downloads,
// shell scripts, or replacing the helper beside the real client.
int runHelper(const QStringList &arguments)
{
    const int baseIndex = arguments.indexOf(u"--runtime-dir"_s);
    if (baseIndex < 0 || baseIndex + 1 >= arguments.size())
        return 2;
    const QDir base(arguments[baseIndex + 1]);
    const bool check = arguments.contains(u"--check"_s);
    const int packIndex = arguments.indexOf(u"--import-pack"_s);
    QFile calls(base.filePath(u"calls"_s));
    if (!calls.open(QIODevice::WriteOnly | QIODevice::Append))
        return 2;
    calls.write(check ? "check\n" : "import\n");
    calls.close();
    const auto extraEvents =
        QJsonDocument::fromJson(readFile(base.filePath(u"helper-events"_s))).array();
    for (const auto &event : extraEvents)
        publish(event.toObject());
    if (check) {
        publishState(u"verifying"_s);
        QElapsedTimer timeout;
        timeout.start();
        while (base.exists(u"hold-check"_s)) {
            if (timeout.elapsed() > 8000)
                return 2;
            QThread::msleep(10);
        }
        const bool installed = base.exists(u"installed"_s);
        publishState(installed ? u"ready"_s : u"not_ready"_s);
        if (base.exists(u"check-await-eof"_s)) {
            // Even a ready event must not win over cancellation or failed exit.
            writeFile(base.filePath(u"check-published"_s));
            while (std::getchar() != EOF) {
            }
        }
        return installed && !base.exists(u"check-exit-failure"_s) ? 0 : 1;
    }
    if (packIndex < 0 || packIndex + 1 >= arguments.size())
        return 2;
    const QString result = QString::fromUtf8(readFile(arguments[packIndex + 1]));
    if (base.exists(u"invalidate-installation"_s))
        QFile::remove(base.filePath(u"installed"_s));
    if (result == u"cancel"_s) {
        publishState(u"importing"_s);
        while (std::getchar() != EOF) {
        }
        // Simulate completion racing with the parent's cancellation.
        publishState(u"ready"_s);
        return 0;
    }
    if (result == u"import_failed"_s)
        publish({{u"diagnostic"_s, QJsonObject{{u"stage"_s, u"import"_s},
                                               {u"component"_s, u"pack"_s},
                                               {u"code"_s, u"checksum_mismatch"_s}}}});
    if (result == u"ready"_s && !writeFile(base.filePath(u"installed"_s)))
        return 2;
    publishState(result);
    return result == u"ready"_s ? 0 : 1;
}
} // namespace

class ForgeHostServiceTest : public QObject
{
    Q_OBJECT

  private:
    std::unique_ptr<QTemporaryDir> m_directory;
    QByteArray m_previousRuntime;
    QByteArray m_previousDiagnostics;
    bool m_hadRuntime = false;
    bool m_hadDiagnostics = false;

    QString path(const QString &name) const
    {
        return m_directory->filePath(name);
    }

    QByteArray calls() const
    {
        return readFile(path(u"calls"_s));
    }

    QJsonObject report(ForgeHostService &service) const
    {
        const auto destination = path(u"diagnostics.json"_s);
        if (!service.exportDiagnostics(QUrl::fromLocalFile(destination)))
            return {};
        return QJsonDocument::fromJson(readFile(destination)).object();
    }

  private slots:
    void initTestCase()
    {
        m_hadRuntime = qEnvironmentVariableIsSet("HEXPROOF_FORGE_HOST_RUNTIME_DIR");
        m_previousRuntime = qgetenv("HEXPROOF_FORGE_HOST_RUNTIME_DIR");
        m_hadDiagnostics = qEnvironmentVariableIsSet("HEXPROOF_FORGE_DIAGNOSTICS_DIR");
        m_previousDiagnostics = qgetenv("HEXPROOF_FORGE_DIAGNOSTICS_DIR");
    }

    void init()
    {
        m_directory = std::make_unique<QTemporaryDir>();
        QVERIFY(m_directory->isValid());
        qputenv("HEXPROOF_FORGE_HOST_RUNTIME_DIR", m_directory->path().toUtf8());
        qputenv("HEXPROOF_FORGE_DIAGNOSTICS_DIR", m_directory->path().toUtf8());
    }

    void cleanupTestCase()
    {
        if (m_hadRuntime)
            qputenv("HEXPROOF_FORGE_HOST_RUNTIME_DIR", m_previousRuntime);
        else
            qunsetenv("HEXPROOF_FORGE_HOST_RUNTIME_DIR");
        if (m_hadDiagnostics)
            qputenv("HEXPROOF_FORGE_DIAGNOSTICS_DIR", m_previousDiagnostics);
        else
            qunsetenv("HEXPROOF_FORGE_DIAGNOSTICS_DIR");
    }

    void rejectedImportRechecksInstallation_data()
    {
        QTest::addColumn<QString>("errorState");
        QTest::addColumn<QString>("message");
        QTest::addColumn<bool>("initiallyInstalled");
        QTest::addColumn<bool>("invalidate");
        const QList<QPair<QString, QString>> errors{
            {u"pack_platform_failed"_s, u"another operating system"_s},
            {u"pack_version_failed"_s, u"does not match this version"_s},
            {u"import_failed"_s, u"Could not import"_s}};
        for (const auto &error : errors) {
            for (int installation = 0; installation < 3; ++installation) {
                const QByteArray name =
                    error.first.toUtf8() + '-' + QByteArray::number(installation);
                QTest::newRow(name.constData())
                    << error.first << error.second << (installation != 0) << (installation == 2);
            }
        }
    }

    void rejectedImportRechecksInstallation()
    {
        QFETCH(QString, errorState);
        QFETCH(QString, message);
        QFETCH(bool, initiallyInstalled);
        QFETCH(bool, invalidate);
        if (initiallyInstalled)
            QVERIFY(writeFile(path(u"installed"_s)));
        ForgeHostService service;
        service.check();
        QTRY_VERIFY(!service.busy());
        QCOMPARE(service.ready(), initiallyInstalled);
        if (invalidate)
            QVERIFY(writeFile(path(u"invalidate-installation"_s)));
        QVERIFY(writeFile(path(u"hold-check"_s)));
        QVERIFY(writeFile(path(u"test.hexproof-forgepack"_s), errorState.toUtf8()));
        const QUrl pack = QUrl::fromLocalFile(path(u"test.hexproof-forgepack"_s));
        service.importPack(pack);
        QTRY_COMPARE(calls(), QByteArray("check\nimport\ncheck\n"));
        QVERIFY(service.busy());
        QVERIFY(!service.ready());
        QVERIFY(service.status().contains(message));
        const QString importError = service.status();
        service.check();
        service.prepare();
        service.importPack(pack);
        service.clearCache();
        service.startHosting(u"ws://127.0.0.1/ws"_s, {});
        QVERIFY(!service.hosting());
        QVERIFY(QFile::remove(path(u"hold-check"_s)));
        QTRY_VERIFY(!service.busy());
        QCOMPARE(service.ready(), initiallyInstalled && !invalidate);
        QCOMPARE(service.status(), importError);
        QCOMPARE(calls(), QByteArray("check\nimport\ncheck\n"));
        QCOMPARE(QFile::exists(path(u"installed"_s)), initiallyInstalled && !invalidate);
        QVERIFY(service.exportDiagnostics(QUrl::fromLocalFile(path(u"diagnostics.json"_s))));
        const auto report = QJsonDocument::fromJson(readFile(path(u"diagnostics.json"_s))).object();
        QCOMPARE(report.value(u"state"_s).toString(), errorState);
        QCOMPARE(report.value(u"ready"_s).toBool(), service.ready());
        const auto events = report.value(u"events"_s).toArray();
        QString importId;
        QString checkId;
        bool importFinished = false;
        bool specificFailure = false;
        bool exitRecorded = false;
        for (const auto &value : events) {
            const auto event = value.toObject();
            QVERIFY(!event.value(u"timestamp"_s).toString().isEmpty());
            QVERIFY(event.value(u"elapsedMs"_s).toInteger(-1) >= 0);
            if (event.value(u"operation"_s) == u"import"_s) {
                importId = event.value(u"operationId"_s).toString();
                if (event.value(u"kind"_s) == u"finished"_s) {
                    QCOMPARE(event.value(u"outcome"_s).toString(), u"failed"_s);
                    QCOMPARE(event.value(u"state"_s).toString(), errorState);
                    importFinished = true;
                }
                specificFailure |= event.value(u"code"_s) == u"checksum_mismatch"_s;
                exitRecorded |= event.value(u"code"_s) == u"process_exited"_s &&
                                event.value(u"exitCode"_s).toInt() == 1;
            } else if (event.value(u"operation"_s) == u"import_check"_s) {
                checkId = event.value(u"operationId"_s).toString();
                QCOMPARE(event.value(u"parentOperationId"_s).toString(), importId);
            }
        }
        QVERIFY(importFinished);
        QVERIFY(exitRecorded);
        QVERIFY(!importId.isEmpty());
        QVERIFY(!checkId.isEmpty());
        QVERIFY(importId != checkId);
        if (errorState == u"import_failed"_s)
            QVERIFY(specificFailure);
    }

    void cancelledImportRechecksInstallation_data()
    {
        QTest::addColumn<bool>("installed");
        QTest::newRow("installed") << true;
        QTest::newRow("not-installed") << false;
    }

    void cancelledImportRechecksInstallation()
    {
        QFETCH(bool, installed);
        if (installed)
            QVERIFY(writeFile(path(u"installed"_s)));
        ForgeHostService service;
        service.check();
        QTRY_VERIFY(!service.busy());
        QVERIFY(writeFile(path(u"test.hexproof-forgepack"_s), "cancel"));
        service.importPack(QUrl::fromLocalFile(path(u"test.hexproof-forgepack"_s)));
        QTRY_VERIFY(service.status().contains(u"Importing"_s));
        service.cancel();
        QTRY_VERIFY(!service.busy());
        QCOMPARE(calls(), QByteArray("check\nimport\ncheck\n"));
        QCOMPARE(service.ready(), installed);
        QVERIFY(service.status().contains(u"Stopped"_s));
        bool recorded = false;
        for (const auto &value : report(service).value(u"events"_s).toArray()) {
            const auto event = value.toObject();
            recorded |= event.value(u"operation"_s) == u"import"_s &&
                        event.value(u"kind"_s) == u"finished"_s &&
                        event.value(u"outcome"_s) == u"cancelled"_s;
        }
        QVERIFY(recorded);
    }

    void failedRecheckDoesNotRestoreRememberedReadiness()
    {
        QVERIFY(writeFile(path(u"installed"_s)));
        ForgeHostService service;
        service.check();
        QTRY_VERIFY(!service.busy());
        QVERIFY(service.ready());
        QVERIFY(writeFile(path(u"check-exit-failure"_s)));
        QVERIFY(writeFile(path(u"test.hexproof-forgepack"_s), "pack_platform_failed"));
        service.importPack(QUrl::fromLocalFile(path(u"test.hexproof-forgepack"_s)));
        QTRY_VERIFY(!service.busy());
        QVERIFY(!service.ready());
        QVERIFY(service.status().contains(u"another operating system"_s));
        QCOMPARE(calls(), QByteArray("check\nimport\ncheck\n"));
    }

    void recheckCanBeCancelledWithoutLosingImportError()
    {
        QVERIFY(writeFile(path(u"installed"_s)));
        QVERIFY(writeFile(path(u"check-await-eof"_s)));
        QVERIFY(writeFile(path(u"test.hexproof-forgepack"_s), "pack_version_failed"));
        ForgeHostService service;
        service.importPack(QUrl::fromLocalFile(path(u"test.hexproof-forgepack"_s)));
        QTRY_VERIFY(QFile::exists(path(u"check-published"_s)));
        QVERIFY(service.busy());
        QVERIFY(!service.ready());
        const QString importError = service.status();
        QVERIFY(importError.contains(u"does not match this version"_s));
        service.cancel();
        QTRY_VERIFY(!service.busy());
        QVERIFY(!service.ready());
        QCOMPARE(service.status(), importError);
        QCOMPARE(calls(), QByteArray("import\ncheck\n"));
    }

    void successfulRetryClearsTheImportError()
    {
        ForgeHostService service;
        const QString file = path(u"test.hexproof-forgepack"_s);
        QVERIFY(writeFile(file, "pack_platform_failed"));
        service.importPack(QUrl::fromLocalFile(file));
        QTRY_VERIFY(!service.busy());
        QVERIFY(!service.ready());
        QVERIFY(service.status().contains(u"another operating system"_s));
        QVERIFY(writeFile(file, "ready"));
        service.importPack(QUrl::fromLocalFile(file));
        QTRY_VERIFY(!service.busy());
        QVERIFY(service.ready());
        QCOMPARE(service.status(), u"The local rules engine is ready."_s);
        QCOMPARE(calls(), QByteArray("import\ncheck\nimport\n"));
    }

    void historySurvivesRestartWithoutRestoringReadiness()
    {
        QVERIFY(writeFile(path(u"installed"_s)));
        QJsonArray before;
        {
            ForgeHostService service;
            service.check();
            QTRY_VERIFY(!service.busy());
            QVERIFY(service.ready());
            const auto first = report(service);
            QCOMPARE(first.value(u"schemaVersion"_s).toInt(), 2);
            QCOMPARE(first.value(u"historyPersistence"_s).toString(), u"available"_s);
            QVERIFY(first.value(u"availableBytes"_s).toInteger(-1) >= 0);
            QVERIFY(!first.value(u"qtVersion"_s).toString().isEmpty());
            before = first.value(u"events"_s).toArray();
            QVERIFY(before.size() >= 4);
            QCOMPARE(before.last().toObject().value(u"helperVersion"_s).toString(), u"2.0.5"_s);
            QCOMPARE(before.last().toObject().value(u"applicationVersion"_s).toString(),
                     u"2.0.5"_s);
        }
        QCoreApplication::setApplicationVersion(u"2.0.6"_s);
        const auto restoreVersion =
            qScopeGuard([] { QCoreApplication::setApplicationVersion(u"2.0.5"_s); });
        ForgeHostService restarted;
        QVERIFY(!restarted.ready());
        QVERIFY(!restarted.hosting());
        const auto second = report(restarted);
        QCOMPARE(second.value(u"applicationVersion"_s).toString(), u"2.0.6"_s);
        QCOMPARE(second.value(u"events"_s).toArray(), before);
    }

    void helperAndStoredHistoryAreStrictlyFiltered()
    {
        const QJsonObject hostile{{u"state"_s, u"secret-card-name"_s},
                                  {u"version"_s, u"secret-version"_s},
                                  {u"runtimeId"_s, u"secret-runtime"_s},
                                  {u"token"_s, u"private-token"_s}};
        const QJsonObject diagnostic{{u"stage"_s, u"import"_s},
                                     {u"component"_s, u"pack"_s},
                                     {u"code"_s, u"checksum_mismatch"_s},
                                     {u"source"_s, u"offline"_s},
                                     {u"actualPlatform"_s, u"secret-platform"_s},
                                     {u"actualPackageId"_s, u"private-package"_s},
                                     {u"expectedPackageId"_s, QString(20, u'a')},
                                     {u"path"_s, u"/private/player/cards"_s},
                                     {u"url"_s, u"https://secret-mirror/token"_s},
                                     {u"exitCode"_s, 3221225781LL},
                                     {u"httpStatus"_s, 404},
                                     {u"attempt"_s, -1},
                                     {u"received"_s, 1.5},
                                     {u"availableBytes"_s, 123456}};
        QVERIFY(
            writeFile(path(u"helper-events"_s),
                      QJsonDocument(QJsonArray{hostile, QJsonObject{{u"diagnostic"_s, diagnostic}}})
                          .toJson()));
        {
            ForgeHostService service;
            service.check();
            QTRY_VERIFY(!service.busy());
            const auto first = report(service);
            const auto events = first.value(u"events"_s).toArray();
            bool found = false;
            for (const auto &value : events) {
                const auto event = value.toObject();
                if (event.value(u"code"_s) != u"checksum_mismatch"_s)
                    continue;
                found = true;
                QCOMPARE(event.value(u"exitCode"_s).toInteger(), 3221225781LL);
                QCOMPARE(event.value(u"httpStatus"_s).toInt(), 404);
                QCOMPARE(event.value(u"availableBytes"_s).toInt(), 123456);
                QVERIFY(!event.contains(u"received"_s));
                QVERIFY(!event.contains(u"attempt"_s));
                QVERIFY(!event.contains(u"actualPlatform"_s));
                QVERIFY(!event.contains(u"actualPackageId"_s));
            }
            QVERIFY(found);
            const auto bytes = QJsonDocument(first).toJson();
            QVERIFY(!bytes.contains("secret-"));
            QVERIFY(!bytes.contains("private-"));
            QVERIFY(!bytes.contains("/private/"));
        }
        const auto historyPath = path(u"diagnostics-v2.json"_s);
        auto root = QJsonDocument::fromJson(readFile(historyPath)).object();
        auto events = root.value(u"events"_s).toArray();
        auto last = events.last().toObject();
        last.insert(u"version"_s, u"private-version"_s);
        last.insert(u"runtimeId"_s, u"private-runtime"_s);
        last.insert(u"helperVersion"_s, u"private-helper"_s);
        last.insert(u"source"_s, u"private-source"_s);
        last.insert(u"unknown"_s, hostile);
        events.replace(events.size() - 1, last);
        root.insert(u"events"_s, events);
        root.insert(u"secret"_s, hostile);
        QVERIFY(writeFile(historyPath, QJsonDocument(root).toJson()));
        ForgeHostService restarted;
        const auto bytes = QJsonDocument(report(restarted)).toJson();
        QVERIFY(!bytes.contains("private-"));
        QVERIFY(!bytes.contains("secret-"));
        QVERIFY(!readFile(historyPath).contains("private-"));
        QVERIFY(bytes.contains("3221225781"));
    }

    void progressIsSampledAndHistoryIsBounded()
    {
        QJsonArray events;
        for (int index = 0; index < 3000; ++index)
            events.append(
                QJsonObject{{u"state"_s, u"forge"_s}, {u"received"_s, index}, {u"total"_s, 3000}});
        QVERIFY(writeFile(path(u"helper-events"_s), QJsonDocument(events).toJson()));
        ForgeHostService service;
        service.check();
        QTRY_VERIFY(!service.busy());
        const auto sampled = report(service).value(u"events"_s).toArray();
        QVERIFY(sampled.size() < 20);
        events = {};
        for (int index = 0; index < 300; ++index)
            events.append(QJsonObject{{u"diagnostic"_s, QJsonObject{{u"stage"_s, u"download"_s},
                                                                    {u"component"_s, u"java"_s},
                                                                    {u"code"_s, u"http_status"_s},
                                                                    {u"httpStatus"_s, 503}}}});
        QVERIFY(writeFile(path(u"helper-events"_s), QJsonDocument(events).toJson()));
        service.check();
        QTRY_VERIFY(!service.busy());
        const auto bounded = report(service).value(u"events"_s).toArray();
        QCOMPARE(bounded.size(), 256);
        QCOMPARE(bounded.last().toObject().value(u"kind"_s).toString(), u"finished"_s);
        QVERIFY(readFile(path(u"diagnostics-v2.json"_s)).size() <= 256 * 1024);
    }

    void expiredAndUnfinishedHistoryIsHandled()
    {
        QJsonObject record{
            {u"operationId"_s, u"00000000-0000-4000-8000-000000000001"_s},
            {u"operation"_s, u"prepare"_s},
            {u"kind"_s, u"started"_s},
            {u"elapsedMs"_s, 10},
            {u"applicationVersion"_s, u"2.0.4"_s},
            {u"timestamp"_s, QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)}};
        auto expired = record;
        expired.insert(u"timestamp"_s,
                       QDateTime::currentDateTimeUtc().addDays(-8).toString(Qt::ISODateWithMs));
        QVERIFY(writeFile(path(u"diagnostics-v2.json"_s),
                          QJsonDocument(QJsonObject{{u"schemaVersion"_s, 2},
                                                    {u"events"_s, QJsonArray{expired, record}}})
                              .toJson()));
        ForgeHostService service;
        const auto events = report(service).value(u"events"_s).toArray();
        QCOMPARE(events.size(), 2);
        const auto interrupted = events.last().toObject();
        QCOMPARE(interrupted.value(u"kind"_s).toString(), u"finished"_s);
        QCOMPARE(interrupted.value(u"outcome"_s).toString(), u"interrupted"_s);
        QCOMPARE(interrupted.value(u"operationId"_s), record.value(u"operationId"_s));
        QCOMPARE(interrupted.value(u"applicationVersion"_s).toString(), u"2.0.4"_s);
        QVERIFY(!service.ready());
        QVERIFY(!service.busy());
    }

    void sharedRuntimeKeepsEachProfilesHistorySeparate()
    {
        QVERIFY(writeFile(path(u"hold-check"_s)));
        ForgeHostService first;
        first.check();
        QTRY_COMPARE(calls(), QByteArray("check\n"));
        QVERIFY(first.busy());
        const auto firstHistory = readFile(path(u"diagnostics-v2.json"_s));
        const auto otherProfile = path(u"other-profile"_s);
        qputenv("HEXPROOF_FORGE_DIAGNOSTICS_DIR", otherProfile.toUtf8());
        ForgeHostService second;
        QVERIFY(report(second).value(u"events"_s).toArray().isEmpty());
        QCOMPARE(readFile(path(u"diagnostics-v2.json"_s)), firstHistory);
        QVERIFY(QFile::remove(path(u"hold-check"_s)));
        QTRY_VERIFY(!first.busy());
        const auto firstEvents = report(first).value(u"events"_s).toArray();
        second.check();
        QTRY_VERIFY(!second.busy());
        const auto secondEvents = report(second).value(u"events"_s).toArray();
        QVERIFY(!firstEvents.isEmpty());
        QVERIFY(!secondEvents.isEmpty());
        QVERIFY(firstEvents.first().toObject().value(u"operationId"_s) !=
                secondEvents.first().toObject().value(u"operationId"_s));
        QCOMPARE(report(first).value(u"events"_s).toArray(), firstEvents);
        QVERIFY(QFile::exists(QDir(otherProfile).filePath(u"diagnostics-v2.json"_s)));
    }

    void oversizedHistoryAndPersistenceFailureDoNotBlockUse()
    {
        QVERIFY(writeFile(path(u"diagnostics-v2.json"_s), QByteArray(256 * 1024 + 1, 'x')));
        {
            ForgeHostService service;
            const auto invalid = report(service);
            QVERIFY(invalid.value(u"events"_s).toArray().isEmpty());
            QCOMPARE(invalid.value(u"historyPersistence"_s).toString(), u"read_failed"_s);
            service.check();
            QTRY_VERIFY(!service.busy());
            QCOMPARE(report(service).value(u"historyPersistence"_s).toString(), u"available"_s);
        }
        const auto blocked = path(u"blocked"_s);
        QVERIFY(writeFile(blocked));
        qputenv("HEXPROOF_FORGE_DIAGNOSTICS_DIR", blocked.toUtf8());
        ForgeHostService service;
        service.importPack(QUrl(u"https://private-source/test"_s));
        QVERIFY(!service.busy());
        const auto failed = report(service);
        QCOMPARE(failed.value(u"historyPersistence"_s).toString(), u"write_failed"_s);
        QVERIFY(!failed.value(u"events"_s).toArray().isEmpty());
    }

    void unavailableHelperDoesNotLeaveRecheckBusy_data()
    {
        QTest::addColumn<bool>("badExecutable");
        QTest::newRow("missing") << false;
        QTest::newRow("failed-to-start") << true;
    }

    void unavailableHelperDoesNotLeaveRecheckBusy()
    {
        QFETCH(bool, badExecutable);
        QString helper =
            QDir(QCoreApplication::applicationDirPath()).filePath(u"hexproof-forge-host"_s);
#ifdef Q_OS_WIN
        helper += u".exe"_s;
#endif
        const QString saved = helper + u".saved"_s;
        QVERIFY(QFile::rename(helper, saved));
        const auto restoreHelper = qScopeGuard([&]() {
            QFile::remove(helper);
            QFile::rename(saved, helper);
        });
        if (badExecutable) {
            QVERIFY(writeFile(helper, "not an executable\n"));
            QVERIFY(QFile::setPermissions(helper,
                                          QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
        }
        QVERIFY(writeFile(path(u"test.hexproof-forgepack"_s), "pack_platform_failed"));
        ForgeHostService service;
        service.importPack(QUrl::fromLocalFile(path(u"test.hexproof-forgepack"_s)));
        QTRY_VERIFY(!service.busy());
        QVERIFY(!service.ready());
        QVERIFY(service.status().contains(badExecutable ? u"could not start"_s
                                                        : u"helper is missing"_s));
        QVERIFY(calls().isEmpty());
        const auto events = report(service).value(u"events"_s).toArray();
        bool recorded = false;
        for (const auto &event : events)
            recorded |= event.toObject().value(u"code"_s) ==
                        (badExecutable ? u"helper_start_failed"_s : u"helper_missing"_s);
        QVERIFY(recorded);
    }
};

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    if (application.arguments().contains(u"--parent-pipe"_s))
        return runHelper(application.arguments());
    QCoreApplication::setApplicationVersion(u"2.0.5"_s);
    ForgeHostServiceTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "forgehostservice_test.moc"
