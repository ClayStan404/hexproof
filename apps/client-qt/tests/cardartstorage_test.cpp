// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/CardArtCache.h"
#include "services/CardArtStorage.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLockFile>
#include <QSaveFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

#ifdef Q_OS_UNIX
#include <sys/stat.h>
#include <unistd.h>
#endif

using namespace Qt::StringLiterals;
using hexproof::client::CardArtCache;
using hexproof::client::CardArtStorage;
using hexproof::client::CardRecord;

namespace {

bool writeFile(const QString &path, const QByteArray &bytes)
{
    if (!QDir().mkpath(QFileInfo(path).absolutePath()))
        return false;
    QSaveFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size() && file.commit();
}

QByteArray readFile(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray{};
}

QVariantMap finishedResult(QSignalSpy &spy)
{
    return spy.isEmpty() ? QVariantMap{} : spy.last().first().toMap();
}

} // namespace

class CardArtStorageTest final : public QObject
{
    Q_OBJECT

  private slots:
    void defaultLocationRetainsLegacyLayout();
    void copiesBothTreesAndActivatesOnlyAfterRestart();
    void resetsToDefaultWithoutDeletingCustomSource();
    void unavailableConfiguredDiskNeverFallsBack();
    void rejectsUnownedAndNestedDestinations();
    void rejectsSymlinkSourceWithoutChangingConfiguration();
    void failedConfigurationCommitKeepsOriginalLocation();
    void locksManagedLocationsAndSeparatesProfiles();
    void rejectsBusyAndRepeatedMigration();
    void invalidConfigurationIsVisibleAndDoesNotCreateFallback();
    void runtimeDiskDisappearanceStopsNewWrites();
    void readOnlyCacheRebasesWithoutMutatingTheIndex();
    void sourceReplacementAtStartDoesNotFollowOutsideTree();
    void destinationReplacementAtStartDoesNotWriteOutsideTree();
    void rejectsNonRegularConfigurationBeforeReading();
};

void CardArtStorageTest::rejectsNonRegularConfigurationBeforeReading()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString profile = directory.filePath(u"directory-config"_s);
    QVERIFY(QDir().mkpath(QDir(profile).filePath(u"card-art-storage.json"_s)));
    CardArtStorage storage(profile);
    QVERIFY(!storage.available());
    QVERIFY(storage.lastError().contains(u"invalid"_s));
    QVERIFY(!QFileInfo::exists(QDir(profile).filePath(u"images"_s)));
#ifdef Q_OS_UNIX
    for (const QString &kind : {u"fifo"_s, u"broken-link"_s}) {
        const QString otherProfile = directory.filePath(kind);
        QVERIFY(QDir().mkpath(otherProfile));
        const QByteArray config =
            QFile::encodeName(QDir(otherProfile).filePath(u"card-art-storage.json"_s));
        if (kind == u"fifo"_s)
            QCOMPARE(::mkfifo(config.constData(), 0600), 0);
        else
            QCOMPARE(::symlink("missing-config.json", config.constData()), 0);
        CardArtStorage rejected(otherProfile);
        QVERIFY(!rejected.available());
        QVERIFY(rejected.lastError().contains(u"invalid"_s));
        QVERIFY(!QFileInfo::exists(QDir(otherProfile).filePath(u"images"_s)));
    }
#endif
}

void CardArtStorageTest::defaultLocationRetainsLegacyLayout()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString profile = directory.filePath(u"profile"_s);
    CardArtStorage storage(profile);
    QVERIFY2(storage.available(), qPrintable(storage.lastError()));
    QVERIFY(storage.defaultLocation());
    QVERIFY(storage.writesAllowed());
    QCOMPARE(storage.imageRoot(), QDir(profile).filePath(u"images"_s));
    QCOMPARE(storage.customImageRoot(), QDir(profile).filePath(u"custom-art"_s));
    QVERIFY(storage.previousImageRoots().isEmpty());
    QVERIFY(!QFileInfo::exists(QDir(profile).filePath(u"card-art-storage.json"_s)));
    QVERIFY(!storage.previewDefault().value(u"ok"_s).toBool());
}

void CardArtStorageTest::copiesBothTreesAndActivatesOnlyAfterRestart()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString profile = directory.filePath(u"profile"_s);
    const QString base = directory.filePath(u"art destination"_s);
    QVERIFY(QDir().mkpath(base));
    QString oldImage;
    QString newImage;
    QString oldCustom;
    QString newCustom;
    QString key;
    {
        CardArtStorage storage(profile);
        CardArtCache cache(profile);
        CardRecord record;
        record.name = record.requestedName = u"Island"_s;
        record.imagePath = QDir(storage.imageRoot()).filePath(u"nested/card.png"_s);
        record.imageLanguage = u"en"_s;
        oldImage = record.imagePath;
        oldCustom = QDir(storage.customImageRoot()).filePath(u"custom.png"_s);
        QVERIFY(writeFile(oldImage, "downloaded-art"));
        QVERIFY(writeFile(oldCustom, "custom-art"));
        QVERIFY(writeFile(QDir(profile).filePath(u"custom-art.json"_s), "relative-custom-index"));
        key = cache.key(record.name, u"en"_s);
        cache.rememberSuccess(key, record);
        storage.setOperationGuard([&cache]() { return cache.save(); });
        connect(&storage, &CardArtStorage::busyChanged, &storage,
                [&]() { cache.setWritable(storage.writesAllowed()); });
        connect(&storage, &CardArtStorage::restartRequiredChanged, &storage,
                [&]() { cache.setWritable(storage.writesAllowed()); });
        const auto preview = storage.previewDirectory(QUrl::fromLocalFile(base));
        QVERIFY(preview.value(u"ok"_s).toBool());
        QVERIFY(preview.value(u"managedDirectory"_s).toString() != base);
        newImage = QDir(preview.value(u"imageRoot"_s).toString()).filePath(u"nested/card.png"_s);
        newCustom = QDir(preview.value(u"customImageRoot"_s).toString()).filePath(u"custom.png"_s);
        QSignalSpy completed(&storage, &CardArtStorage::migrationFinished);
        storage.migrateTo(QUrl::fromLocalFile(base));
        QVERIFY(storage.busy());
        QVERIFY(!storage.writesAllowed());
        QVERIFY(!cache.writable());
        QTRY_COMPARE_WITH_TIMEOUT(completed.count(), 1, 10000);
        QVERIFY2(finishedResult(completed).value(u"ok"_s).toBool(),
                 qPrintable(storage.lastError()));
        QCOMPARE(finishedResult(completed).value(u"fileCount"_s).toInt(), 2);
        QVERIFY(storage.restartRequired());
        QVERIFY(!storage.writesAllowed());
        QCOMPARE(storage.progress(), 1.0);
        QCOMPARE(storage.imageRoot(), QDir(profile).filePath(u"images"_s));
        QCOMPARE(cache.exactRecord(key).imagePath, oldImage);
        QCOMPARE(readFile(oldImage), readFile(newImage));
        QCOMPARE(readFile(oldCustom), readFile(newCustom));
        QCOMPARE(readFile(QDir(profile).filePath(u"custom-art.json"_s)),
                 QByteArray("relative-custom-index"));
        QVERIFY(storage.lastResult().contains(profile));
    }
    {
        CardArtStorage restarted(profile);
        QVERIFY2(restarted.available(), qPrintable(restarted.lastError()));
        QVERIFY(!restarted.defaultLocation());
        QCOMPARE(restarted.configuredBaseDirectory(), base);
        CardArtCache loaded(profile, restarted.imageRoot(), restarted.previousImageRoots(),
                            restarted.available());
        loaded.load();
        QCOMPARE(loaded.exactRecord(key).imagePath, newImage);
        QVERIFY(loaded.dirty());
        QVERIFY(loaded.save());
        QVERIFY(readFile(QDir(profile).filePath(u"card-cache.json"_s)).contains(newImage.toUtf8()));
        QVERIFY(QFileInfo::exists(oldImage));
        QVERIFY(QFileInfo::exists(oldCustom));
    }
}

void CardArtStorageTest::resetsToDefaultWithoutDeletingCustomSource()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString profile = directory.filePath(u"profile"_s);
    const QString base = directory.filePath(u"external"_s);
    QVERIFY(QDir().mkpath(base));
    QString externalImage;
    {
        CardArtStorage storage(profile);
        QVERIFY(writeFile(QDir(storage.imageRoot()).filePath(u"card.png"_s), "original"));
        QSignalSpy finished(&storage, &CardArtStorage::migrationFinished);
        storage.migrateTo(QUrl::fromLocalFile(base));
        QTRY_COMPARE(finished.count(), 1);
        QVERIFY2(storage.restartRequired(), qPrintable(storage.lastError()));
    }
    {
        CardArtStorage storage(profile);
        externalImage = QDir(storage.imageRoot()).filePath(u"card.png"_s);
        QVERIFY(writeFile(externalImage, "updated external image"));
        QVERIFY(
            writeFile(QDir(storage.customImageRoot()).filePath(u"new.png"_s), "new custom image"));
        QSignalSpy finished(&storage, &CardArtStorage::migrationFinished);
        QVERIFY(storage.previewDefault().value(u"ok"_s).toBool());
        storage.resetToDefault();
        QTRY_COMPARE(finished.count(), 1);
        QVERIFY2(storage.restartRequired(), qPrintable(storage.lastError()));
    }
    CardArtStorage storage(profile);
    QVERIFY(storage.available());
    QVERIFY(storage.defaultLocation());
    QCOMPARE(readFile(QDir(storage.imageRoot()).filePath(u"card.png"_s)),
             QByteArray("updated external image"));
    QCOMPARE(readFile(QDir(storage.customImageRoot()).filePath(u"new.png"_s)),
             QByteArray("new custom image"));
    QCOMPARE(readFile(externalImage), QByteArray("updated external image"));
}

void CardArtStorageTest::unavailableConfiguredDiskNeverFallsBack()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString profile = directory.filePath(u"profile"_s);
    const QString base = directory.filePath(u"external"_s);
    QVERIFY(QDir().mkpath(base));
    QString managed;
    QString oldImage;
    {
        CardArtStorage storage(profile);
        oldImage = QDir(storage.imageRoot()).filePath(u"card.png"_s);
        QVERIFY(writeFile(oldImage, "old source stays available"));
        managed = storage.previewDirectory(QUrl::fromLocalFile(base))
                      .value(u"managedDirectory"_s)
                      .toString();
        QSignalSpy finished(&storage, &CardArtStorage::migrationFinished);
        storage.migrateTo(QUrl::fromLocalFile(base));
        QTRY_COMPARE(finished.count(), 1);
        QVERIFY(storage.restartRequired());
    }
    QVERIFY(QDir().rename(managed, managed + u"-offline"_s));
    const QByteArray config = readFile(QDir(profile).filePath(u"card-art-storage.json"_s));
    CardArtStorage storage(profile);
    QVERIFY(!storage.available());
    QVERIFY(!storage.defaultLocation());
    QVERIFY(!storage.writesAllowed());
    QVERIFY(!storage.lastError().isEmpty());
    QCOMPARE(storage.imageRoot(), QDir(managed).filePath(u"images"_s));
    QVERIFY(storage.previousImageRoots().contains(QDir(profile).filePath(u"images"_s)));
    QVERIFY(QFileInfo::exists(oldImage));
    QVERIFY(!QFileInfo::exists(managed));
    storage.resetToDefault();
    QVERIFY(!storage.restartRequired());
    QCOMPARE(readFile(QDir(profile).filePath(u"card-art-storage.json"_s)), config);
    QVERIFY(!QFileInfo::exists(managed));
}

void CardArtStorageTest::rejectsUnownedAndNestedDestinations()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtStorage storage(directory.filePath(u"profile"_s));
    QVERIFY(
        !storage.previewDirectory(QUrl(u"https://example.test/cards"_s)).value(u"ok"_s).toBool());
    QVERIFY(!storage.previewDirectory(QUrl::fromLocalFile(storage.imageRoot()))
                 .value(u"ok"_s)
                 .toBool());
    const QString base = directory.filePath(u"external"_s);
    QVERIFY(QDir().mkpath(base));
    const QString managed =
        storage.previewDirectory(QUrl::fromLocalFile(base)).value(u"managedDirectory"_s).toString();
    const QString unrelated = QDir(managed).filePath(u"unrelated.txt"_s);
    QVERIFY(writeFile(unrelated, "do not overwrite"));
    storage.migrateTo(QUrl::fromLocalFile(base));
    QVERIFY(!storage.busy());
    QVERIFY(!storage.lastError().isEmpty());
    QCOMPARE(readFile(unrelated), QByteArray("do not overwrite"));
    QVERIFY(!QFileInfo::exists(QDir(managed).filePath(u"images"_s)));
}

void CardArtStorageTest::rejectsSymlinkSourceWithoutChangingConfiguration()
{
#ifdef Q_OS_WIN
    QSKIP("QFile::link creates Windows shortcuts instead of filesystem symlinks.");
#else
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtStorage storage(directory.filePath(u"profile"_s));
    const QString outside = directory.filePath(u"outside.png"_s);
    QVERIFY(writeFile(outside, "not an owned image"));
    QVERIFY(QFile::link(outside, QDir(storage.imageRoot()).filePath(u"linked.png"_s)));
    const QString base = directory.filePath(u"external"_s);
    QVERIFY(QDir().mkpath(base));
    QSignalSpy finished(&storage, &CardArtStorage::migrationFinished);
    storage.migrateTo(QUrl::fromLocalFile(base));
    QTRY_COMPARE(finished.count(), 1);
    QVERIFY(!finishedResult(finished).value(u"ok"_s).toBool());
    QVERIFY(!storage.restartRequired());
    QVERIFY(storage.writesAllowed());
    QVERIFY(
        !QFileInfo::exists(QDir(storage.currentDirectory()).filePath(u"card-art-storage.json"_s)));
    QCOMPARE(readFile(outside), QByteArray("not an owned image"));
#endif
}

void CardArtStorageTest::failedConfigurationCommitKeepsOriginalLocation()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString profile = directory.filePath(u"profile"_s);
    CardArtStorage storage(profile);
    const QString source = QDir(storage.imageRoot()).filePath(u"card.png"_s);
    QVERIFY(writeFile(source, "image"));
    // Force the final QSaveFile commit to fail after copying has completed.
    QVERIFY(QDir().mkpath(QDir(profile).filePath(u"card-art-storage.json"_s)));
    const QString base = directory.filePath(u"external"_s);
    QVERIFY(QDir().mkpath(base));
    QSignalSpy finished(&storage, &CardArtStorage::migrationFinished);
    storage.migrateTo(QUrl::fromLocalFile(base));
    QTRY_COMPARE(finished.count(), 1);
    QVERIFY(!finishedResult(finished).value(u"ok"_s).toBool());
    QVERIFY(!storage.restartRequired());
    QVERIFY(storage.writesAllowed());
    QCOMPARE(storage.imageRoot(), QDir(profile).filePath(u"images"_s));
    QCOMPARE(readFile(source), QByteArray("image"));
    QVERIFY(storage.lastError().contains(u"original location remains active"_s));
    QVERIFY(QDir().rmdir(QDir(profile).filePath(u"card-art-storage.json"_s)));
    storage.migrateTo(QUrl::fromLocalFile(base));
    QTRY_COMPARE(finished.count(), 2);
    QVERIFY2(storage.restartRequired(), qPrintable(storage.lastError()));
    QCOMPARE(readFile(source), QByteArray("image"));
}

void CardArtStorageTest::locksManagedLocationsAndSeparatesProfiles()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtStorage first(directory.filePath(u"profile"_s));
    CardArtStorage duplicate(directory.filePath(u"profile"_s));
    QVERIFY(first.available());
    QVERIFY(!duplicate.available());
    QVERIFY(duplicate.lastError().contains(u"another Hexproof process"_s));
    CardArtStorage independent(directory.filePath(u"other-profile"_s));
    QVERIFY(independent.available());
    const QString base = directory.filePath(u"external"_s);
    QVERIFY(QDir().mkpath(base));
    const QString one =
        first.previewDirectory(QUrl::fromLocalFile(base)).value(u"managedDirectory"_s).toString();
    const QString two = independent.previewDirectory(QUrl::fromLocalFile(base))
                            .value(u"managedDirectory"_s)
                            .toString();
    QVERIFY(one != two);
    QSignalSpy firstFinished(&first, &CardArtStorage::migrationFinished);
    first.migrateTo(QUrl::fromLocalFile(base));
    QTRY_COMPARE(firstFinished.count(), 1);
    QVERIFY(first.restartRequired());
    QLockFile competing(QDir(one).filePath(u".hexproof-art.lock"_s));
    competing.setStaleLockTime(0);
    QVERIFY(!competing.tryLock(0));
    QSignalSpy otherFinished(&independent, &CardArtStorage::migrationFinished);
    independent.migrateTo(QUrl::fromLocalFile(base));
    QTRY_COMPARE(otherFinished.count(), 1);
    QVERIFY(independent.restartRequired());
}

void CardArtStorageTest::rejectsBusyAndRepeatedMigration()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtStorage storage(directory.filePath(u"profile"_s));
    const QString base = directory.filePath(u"external"_s);
    QVERIFY(QDir().mkpath(base));
    storage.setOperationGuard([]() { return false; });
    storage.migrateTo(QUrl::fromLocalFile(base));
    QVERIFY(!storage.busy());
    QVERIFY(!storage.lastError().isEmpty());
    storage.setOperationGuard([]() { return true; });
    QSignalSpy finished(&storage, &CardArtStorage::migrationFinished);
    storage.migrateTo(QUrl::fromLocalFile(base));
    storage.migrateTo(QUrl::fromLocalFile(base));
    QTRY_COMPARE(finished.count(), 1);
    QVERIFY(storage.restartRequired());
    storage.resetToDefault();
    QVERIFY(!storage.busy());
    QVERIFY(storage.lastError().contains(u"restart Hexproof"_s));
    QCOMPARE(finished.count(), 1);
}

void CardArtStorageTest::invalidConfigurationIsVisibleAndDoesNotCreateFallback()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString profile = directory.filePath(u"profile"_s);
    const QString config = QDir(profile).filePath(u"card-art-storage.json"_s);
    QVERIFY(writeFile(config, "{ invalid JSON"));
    CardArtStorage storage(profile);
    QVERIFY(!storage.available());
    QVERIFY(!storage.lastError().isEmpty());
    QVERIFY(!QFileInfo::exists(storage.imageRoot()));
    storage.clearMessages();
    QVERIFY(!storage.lastError().isEmpty());
    QCOMPARE(readFile(config), QByteArray("{ invalid JSON"));
}

void CardArtStorageTest::runtimeDiskDisappearanceStopsNewWrites()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString profile = directory.filePath(u"profile"_s);
    const QString base = directory.filePath(u"external"_s);
    QVERIFY(QDir().mkpath(base));
    {
        CardArtStorage storage(profile);
        QSignalSpy finished(&storage, &CardArtStorage::migrationFinished);
        storage.migrateTo(QUrl::fromLocalFile(base));
        QTRY_COMPARE(finished.count(), 1);
        QVERIFY(storage.restartRequired());
    }
    CardArtStorage storage(profile);
    QVERIFY(storage.writesAllowed());
    const QString images = storage.imageRoot();
    QVERIFY(QDir().rename(images, images + u"-disconnected"_s));
    QVERIFY(!storage.writesAllowed());
    QVERIFY(!QFileInfo::exists(images));
    QVERIFY(QDir().rename(images + u"-disconnected"_s, images));
    QVERIFY(storage.writesAllowed());
}

void CardArtStorageTest::readOnlyCacheRebasesWithoutMutatingTheIndex()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString profile = directory.filePath(u"profile"_s);
    QString key;
    QString original;
    {
        CardArtCache cache(profile);
        CardRecord record;
        record.name = record.requestedName = u"Island"_s;
        original = record.imagePath = QDir(cache.imageRoot()).filePath(u"card.png"_s);
        QVERIFY(writeFile(original, "original image"));
        key = cache.key(record.name, u"en"_s);
        cache.rememberSuccess(key, record);
        QVERIFY(cache.save());
    }
    const QString index = QDir(profile).filePath(u"card-cache.json"_s);
    const QByteArray before = readFile(index);
    const QString unavailable = directory.filePath(u"unavailable/images"_s);
    {
        CardArtCache cache(profile, unavailable, {QDir(profile).filePath(u"images"_s)}, false);
        cache.load();
        QVERIFY(!cache.writable());
        QCOMPARE(cache.exactRecord(key).imagePath, QDir(unavailable).filePath(u"card.png"_s));
        QVERIFY(!cache.dirty());
        cache.rememberSuccess(key, {});
        cache.rememberFailure(key);
        cache.setFaceAuditState(999, true);
        cache.replaceEntries({});
        QVERIFY(cache.removeEntries(false).isEmpty());
        QVERIFY(!cache.failedRecently(key));
        QVERIFY(!cache.save());
        QCOMPARE(cache.exactRecord(key).name, u"Island"_s);
        QVERIFY(!cache.dirty());
        cache.saveAsync();
    }
    QCOMPARE(readFile(index), before);
    QVERIFY(!QFileInfo::exists(unavailable));
    QVERIFY(QFileInfo::exists(original));
}

void CardArtStorageTest::sourceReplacementAtStartDoesNotFollowOutsideTree()
{
#ifdef Q_OS_WIN
    QSKIP("QFile::link creates Windows shortcuts instead of filesystem symlinks.");
#else
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtStorage storage(directory.filePath(u"profile"_s));
    const QString images = storage.imageRoot();
    QVERIFY(writeFile(QDir(images).filePath(u"card.png"_s), "owned image"));
    const QString outside = directory.filePath(u"outside"_s);
    QVERIFY(writeFile(QDir(outside).filePath(u"private.png"_s), "outside data"));
    const QString base = directory.filePath(u"external"_s);
    QVERIFY(QDir().mkpath(base));
    const QString targetImages =
        storage.previewDirectory(QUrl::fromLocalFile(base)).value(u"imageRoot"_s).toString();
    bool swapped = false;
    connect(&storage, &CardArtStorage::busyChanged, &storage, [&]() {
        if (storage.busy())
            swapped =
                QDir().rename(images, images + u"-original"_s) && QFile::link(outside, images);
    });
    QSignalSpy finished(&storage, &CardArtStorage::migrationFinished);
    storage.migrateTo(QUrl::fromLocalFile(base));
    QTRY_COMPARE(finished.count(), 1);
    QVERIFY(swapped);
    QVERIFY(!finishedResult(finished).value(u"ok"_s).toBool());
    QVERIFY(!storage.restartRequired());
    QVERIFY(!QFileInfo::exists(QDir(targetImages).filePath(u"private.png"_s)));
    QCOMPARE(readFile(QDir(images + u"-original"_s).filePath(u"card.png"_s)),
             QByteArray("owned image"));
    QVERIFY(QFile::remove(images));
    QVERIFY(QDir().rename(images + u"-original"_s, images));
#endif
}

void CardArtStorageTest::destinationReplacementAtStartDoesNotWriteOutsideTree()
{
#ifdef Q_OS_WIN
    QSKIP("QFile::link creates Windows shortcuts instead of filesystem symlinks.");
#else
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtStorage storage(directory.filePath(u"profile"_s));
    QVERIFY(writeFile(QDir(storage.imageRoot()).filePath(u"card.png"_s), "owned image"));
    const QString outside = directory.filePath(u"outside"_s);
    QVERIFY(writeFile(QDir(outside).filePath(u"card.png"_s), "outside data"));
    const QString base = directory.filePath(u"external"_s);
    QVERIFY(QDir().mkpath(base));
    const QString targetImages =
        storage.previewDirectory(QUrl::fromLocalFile(base)).value(u"imageRoot"_s).toString();
    bool swapped = false;
    connect(&storage, &CardArtStorage::busyChanged, &storage, [&]() {
        if (storage.busy())
            swapped = QFile::link(outside, targetImages);
    });
    QSignalSpy finished(&storage, &CardArtStorage::migrationFinished);
    storage.migrateTo(QUrl::fromLocalFile(base));
    QTRY_COMPARE(finished.count(), 1);
    QVERIFY(swapped);
    QVERIFY(!finishedResult(finished).value(u"ok"_s).toBool());
    QVERIFY(!storage.restartRequired());
    QCOMPARE(readFile(QDir(outside).filePath(u"card.png"_s)), QByteArray("outside data"));
#endif
}

QTEST_GUILESS_MAIN(CardArtStorageTest)
#include "cardartstorage_test.moc"
