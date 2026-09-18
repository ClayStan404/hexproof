// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/ForgeHostService.h"

#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
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

void publishState(const QString &state)
{
    const QByteArray line =
        QJsonDocument(QJsonObject{{u"state"_s, state}}).toJson(QJsonDocument::Compact) + '\n';
    std::fwrite(line.constData(), 1, static_cast<size_t>(line.size()), stdout);
    std::fflush(stdout);
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
    bool m_hadRuntime = false;

    QString path(const QString &name) const
    {
        return m_directory->filePath(name);
    }

    QByteArray calls() const
    {
        return readFile(path(u"calls"_s));
    }

  private slots:
    void initTestCase()
    {
        m_hadRuntime = qEnvironmentVariableIsSet("HEXPROOF_FORGE_HOST_RUNTIME_DIR");
        m_previousRuntime = qgetenv("HEXPROOF_FORGE_HOST_RUNTIME_DIR");
    }

    void init()
    {
        m_directory = std::make_unique<QTemporaryDir>();
        QVERIFY(m_directory->isValid());
        qputenv("HEXPROOF_FORGE_HOST_RUNTIME_DIR", m_directory->path().toUtf8());
    }

    void cleanupTestCase()
    {
        if (m_hadRuntime)
            qputenv("HEXPROOF_FORGE_HOST_RUNTIME_DIR", m_previousRuntime);
        else
            qunsetenv("HEXPROOF_FORGE_HOST_RUNTIME_DIR");
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
    }
};

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    if (application.arguments().contains(u"--parent-pipe"_s))
        return runHelper(application.arguments());
    ForgeHostServiceTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "forgehostservice_test.moc"
