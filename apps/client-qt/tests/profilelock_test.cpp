// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/ProfileLock.h"

#include <QCoreApplication>
#include <QFile>
#include <QProcess>
#include <QTemporaryDir>
#include <QTest>
#include <QTextStream>

using namespace Qt::StringLiterals;
using hexproof::client::ProfileLock;

class TestProfileLock final : public QObject
{
    Q_OBJECT
  private slots:
    void excludesStaleWritersAndAllowsIndependentProfiles() const
    {
        QTemporaryDir profile;
        QVERIFY(profile.isValid());
        {
            ProfileLock first(profile.path());
            QVERIFY(first.tryLock());
            ProfileLock second(profile.path() + u"/../"_s + QDir(profile.path()).dirName());
            QVERIFY(!second.tryLock());
            QVERIFY(second.occupied());
            ProfileLock independent(profile.filePath(u"other"_s));
            QVERIFY(independent.tryLock());
        }
        ProfileLock reopened(profile.path());
        QVERIFY(reopened.tryLock());
    }

    void detectsASecondProcessAndRecoversAfterCrash() const
    {
        QTemporaryDir profile;
        QVERIFY(profile.isValid());
        QProcess holder;
        holder.start(QCoreApplication::applicationFilePath(),
                     {u"--hold-profile"_s, profile.path()});
        QVERIFY(holder.waitForStarted());
        QVERIFY(holder.waitForReadyRead());
        QCOMPARE(holder.readAllStandardOutput().trimmed(), QByteArray("locked"));
        ProfileLock blocked(profile.path());
        const bool acquired = blocked.tryLock();
        const bool occupied = blocked.occupied();
        holder.kill();
        QVERIFY(holder.waitForFinished());
        QVERIFY(!acquired);
        QVERIFY(occupied);
        ProfileLock afterCrash(profile.path());
        QVERIFY(afterCrash.tryLock());
    }

    void invalidStorageFailsClosed() const
    {
        QTemporaryDir profile;
        QFile obstruction(profile.filePath(u"not-a-directory"_s));
        QVERIFY(obstruction.open(QIODevice::WriteOnly));
        obstruction.close();
        ProfileLock lock(obstruction.fileName());
        QVERIFY(!lock.tryLock());
        QVERIFY(!lock.occupied());
    }
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (app.arguments().size() == 3 && app.arguments().at(1) == u"--hold-profile"_s) {
        ProfileLock lock(app.arguments().at(2));
        if (!lock.tryLock())
            return 2;
        QTextStream(stdout) << "locked" << Qt::endl;
        return app.exec();
    }
    TestProfileLock test;
    return QTest::qExec(&test, argc, argv);
}

#include "profilelock_test.moc"
