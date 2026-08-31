// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/ReconnectController.h"
#include "services/ServerDirectory.h"

#include <QCoreApplication>
#include <QFile>
#include <QSettings>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using namespace Qt::StringLiterals;
using hexproof::client::ReconnectController;
using hexproof::client::ServerDirectory;

class TestReconnectController : public QObject
{
    Q_OBJECT

  private slots:
    void initTestCase();
    void cleanup();
    void loadsPersistedResumeState() const;
    void updatesAndPersistsResumeState() const;
    void ignoresOlderSequences() const;
    void clearsResumeState() const;
    void preservesRetryBackoff() const;
    void schedulesFirstRetry() const;
    void publishesReconnectCountdown() const;

  private:
    QTemporaryDir m_settingsDir;
};

void TestReconnectController::initTestCase()
{
    QVERIFY(m_settingsDir.isValid());
    QCoreApplication::setOrganizationName(u"HexproofTests"_s);
    QCoreApplication::setApplicationName(u"ReconnectControllerTest"_s);
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_settingsDir.path());
}

void TestReconnectController::cleanup()
{
    qunsetenv("HEXPROOF_SERVER_DIRECTORY_FILE");
    QSettings settings;
    settings.clear();
    settings.sync();
}

void TestReconnectController::loadsPersistedResumeState() const
{
    const QString directoryPath = m_settingsDir.filePath(u"legacy-servers.json"_s);
    QFile directoryFile(directoryPath);
    QVERIFY(directoryFile.open(QIODevice::WriteOnly));
    const QByteArray directoryPayload = R"({
  "schemaVersion": 1,
  "servers": [
    {
      "url": "wss://primary.example/ws",
      "legacyUrls": ["ws://retired-primary.example:57320/ws"]
    },
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
    settings.setValue(u"network/resumeDisplayName"_s, u"Saved player"_s);
    settings.setValue(u"network/resumeLastSeq"_s, 42);
    settings.sync();

    ServerDirectory directory;
    ReconnectController controller(&directory);
    QCOMPARE(controller.token(), u"saved-token"_s);
    QCOMPARE(controller.serverUrl(), directory.serverUrl(0));
    QCOMPARE(controller.displayName(), u"Saved player"_s);
    QCOMPARE(controller.lastSeq(), 42);
    QVERIFY(controller.matches(directory.serverUrl(0), u"Saved player"_s));
}

void TestReconnectController::updatesAndPersistsResumeState() const
{
    ServerDirectory directory;
    ReconnectController controller(&directory);
    controller.updateSession(u"resume-secret"_s, u"ws://127.0.0.1:57320/ws"_s, u"Alice"_s);
    controller.observeSequence(7);
    controller.flush();

    QSettings settings;
    QCOMPARE(settings.value(u"network/resumeToken"_s).toString(), u"resume-secret"_s);
    QCOMPARE(settings.value(u"network/resumeServerUrl"_s).toString(), u"ws://127.0.0.1:57320/ws"_s);
    QCOMPARE(settings.value(u"network/resumeDisplayName"_s).toString(), u"Alice"_s);
    QCOMPARE(settings.value(u"network/resumeLastSeq"_s).toLongLong(), 7);
}

void TestReconnectController::ignoresOlderSequences() const
{
    ServerDirectory directory;
    ReconnectController controller(&directory);
    controller.updateSession(u"resume-secret"_s, directory.serverUrl(0), u"Alice"_s);
    controller.observeSequence(9);
    controller.observeSequence(7);
    QCOMPARE(controller.lastSeq(), 9);
    controller.resetSequence();
    QCOMPARE(controller.lastSeq(), 0);
}

void TestReconnectController::clearsResumeState() const
{
    ServerDirectory directory;
    ReconnectController controller(&directory);
    controller.updateSession(u"resume-secret"_s, directory.serverUrl(0), u"Alice"_s);
    controller.observeSequence(3);
    controller.flush();
    controller.clear();

    QVERIFY(!controller.hasCredentials());
    QVERIFY(controller.serverUrl().isEmpty());
    QVERIFY(controller.displayName().isEmpty());
    QCOMPARE(controller.lastSeq(), 0);

    QSettings settings;
    QVERIFY(!settings.contains(u"network/resumeToken"_s));
    QVERIFY(!settings.contains(u"network/resumeServerUrl"_s));
    QVERIFY(!settings.contains(u"network/resumeDisplayName"_s));
    QVERIFY(!settings.contains(u"network/resumeLastSeq"_s));
}

void TestReconnectController::preservesRetryBackoff() const
{
    QCOMPARE(ReconnectController::retryDelayMs(0), 1000);
    QCOMPARE(ReconnectController::retryDelayMs(1), 2000);
    QCOMPARE(ReconnectController::retryDelayMs(2), 4000);
    QCOMPARE(ReconnectController::retryDelayMs(3), 8000);
    QCOMPARE(ReconnectController::retryDelayMs(10), 8000);
}

void TestReconnectController::schedulesFirstRetry() const
{
    ServerDirectory directory;
    ReconnectController controller(&directory);
    QSignalSpy retryDue(&controller, &ReconnectController::retryDue);
    controller.beginReconnectWindow();
    controller.scheduleRetry();
    QTRY_COMPARE_WITH_TIMEOUT(retryDue.count(), 1, 1500);
    controller.stopRetry();
}

void TestReconnectController::publishesReconnectCountdown() const
{
    ServerDirectory directory;
    ReconnectController controller(&directory);
    QSignalSpy changed(&controller, &ReconnectController::remainingSecondsChanged);

    controller.beginReconnectWindow();
    QCOMPARE(controller.remainingSeconds(), 180);
    QTRY_VERIFY_WITH_TIMEOUT(controller.remainingSeconds() < 180, 2500);
    QVERIFY(changed.count() >= 1);

    controller.stopRetry();
    QCOMPARE(controller.remainingSeconds(), 0);
}

QTEST_MAIN(TestReconnectController)
#include "reconnectcontroller_test.moc"
