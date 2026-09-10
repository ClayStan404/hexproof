// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/BackgroundTaskPools.h"
#include "services/CardArtArchive.h"
#include "services/CardCatalogCommon.h"
#include "services/CustomCardArtInternal.h"
#include "services/CustomCardArtStore.h"

#include <QDataStream>
#include <QDir>
#include <QFile>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSemaphore>
#include <QSignalSpy>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QTemporaryDir>
#include <QTest>
#include <QUuid>
#include <QtConcurrent>

#include <functional>
#ifdef Q_OS_UNIX
#include <sys/stat.h>
#endif

using namespace Qt::StringLiterals;
using namespace hexproof::client;

namespace {

QVariantMap binding(QString name = u"Island"_s, QString collector = u"1"_s, QString face = {},
                    QString scope = u"printing"_s)
{
    return {{u"name"_s, name},
            {u"setCode"_s, u"TST"_s},
            {u"collectorNumber"_s, collector},
            {u"faceName"_s, face},
            {u"scope"_s, scope},
            {u"oracleId"_s, u"oracle-"_s + name.toLower()}};
}

QUrl makeImage(const QString &path, QColor color = Qt::red, const char *format = "PNG")
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QImage image(24, 32, QImage::Format_ARGB32);
    image.fill(color);
    return image.save(path, format) ? QUrl::fromLocalFile(path) : QUrl{};
}

QByteArray readFile(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray{};
}

bool writeFile(const QString &path, const QByteArray &bytes)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size();
}

QVariantMap runOperation(CustomCardArtStore *store, const std::function<void()> &operation)
{
    QSignalSpy finished(store, &CustomCardArtStore::operationFinished);
    operation();
    if (finished.isEmpty())
        finished.wait(10'000);
    return finished.isEmpty() ? QVariantMap{} : finished.first().first().toMap();
}

bool createCatalog(const QString &path)
{
    const QString connection = u"custom-art-test-"_s + QUuid::createUuid().toString();
    bool ok = false;
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(u"QSQLITE"_s, connection);
        db.setDatabaseName(path);
        if (db.open()) {
            QSqlQuery query(db);
            ok = query.exec(u"CREATE TABLE cards (name TEXT, oracle_id TEXT, printed_name TEXT, "
                            "type_line TEXT, set_code TEXT, collector_number TEXT, image_url TEXT, "
                            "lang TEXT, illustration_id TEXT, layout TEXT)"_s);
            for (const auto &row : QList<QStringList>{
                     {u"Island"_s, u"1"_s, u"normal"_s},
                     {u"Front // Back"_s, u"2"_s, u"transform"_s},
                     {u"Emeritus // Swords"_s, u"3"_s, u"prepare"_s},
                     {u"Angel // Angel"_s, u"4"_s, u"double_faced_token"_s},
                     {u"Dagger"_s, u"7†"_s, u"normal"_s},
                 }) {
                query.prepare(u"INSERT INTO cards VALUES (?, ?, ?, 'Creature', 'TST', ?, "
                              "'', 'en', '', ?)"_s);
                query.addBindValue(row.at(0));
                query.addBindValue(u"oracle-"_s + row.at(0).toLower());
                query.addBindValue(row.at(0));
                query.addBindValue(row.at(1));
                query.addBindValue(row.at(2));
                ok = ok && query.exec();
            }
            db.close();
        }
    }
    QSqlDatabase::removeDatabase(connection);
    return ok;
}

bool writeManifest(const QString &directory, const QVariantList &entries)
{
    const QJsonObject manifest{{u"format"_s, u"hexproof.custom-art-directory"_s},
                               {u"formatVersion"_s, 1},
                               {u"entries"_s, QJsonArray::fromVariantList(entries)}};
    return writeFile(QDir(directory).filePath(u"custom-art-map.json"_s),
                     QJsonDocument(manifest).toJson());
}

} // namespace

class TestCustomCardArtStore final : public QObject
{
    Q_OBJECT

  private slots:
    void copiesPersistsRestoresAndDoesNotTouchNormalCache();
    void separatesExactCardWideAndDoubleFacedOverrides();
    void validatesImagesBeforePreviewAndUsesImmutableSnapshot();
    void directoryFilenamesResolveFacesWithoutGuessing();
    void directoryManifestRejectsTraversalAndAmbiguousMappings();
    void customPackRequiresInspectionAndExplicitImport();
    void customPackConflictPolicyPreservesUnlessConfirmed();
    void tamperedPackAndChangedPreviewDoNotUpdateIndex();
    void removingSharedImagesPreservesRemainingBindings();
    void operationGuardAndOfflineImageRootStayReadOnly();
    void rejectsBadInputsAndPreservesDamagedIndex();
    void bulkDirectoryHandlesManyBindingsWithOneImage();
    void stripsUnknownMetadataBeforePersistenceAndExport();
    void refusesCardWideBindingsWithoutVerifiedIdentity();
    void acceptsSupportedFormatsAndRejectsOversizedDimensions();
    void indexFailureRollsBackOnlyNewImages();
    void invalidPreviewDirectoryAndSymlinksAreRejected();
    void exportSkipsInconsistentSharedImageMetadata();
    void sameNamedTokenFacesRemainIndependent();
    void specialFilesNeverEnterBlockingReaders();
    void ordinaryCacheSeparatesSameNamedTokenFaceRequests();
    void restoreDoesNotQueueBehindCatalogMaintenance();
    void changedBindingsContainOnlyAffectedIdentitiesAfterBusyClears();
    void repairingSharedImageNotifiesEveryBinding_data();
    void repairingSharedImageNotifiesEveryBinding();
};

void TestCustomCardArtStore::repairingSharedImageNotifiesEveryBinding_data()
{
    QTest::addColumn<bool>("missing");
    QTest::newRow("deleted-file") << true;
    QTest::newRow("damaged-file") << false;
}

void TestCustomCardArtStore::repairingSharedImageNotifiesEveryBinding()
{
    QFETCH(bool, missing);
    QTemporaryDir directory;
    CustomCardArtStore store(directory.filePath(u"profile"_s));
    const auto image = makeImage(directory.filePath(u"image.png"_s));
    const auto island = binding();
    const auto forest = binding(u"Forest"_s, u"2"_s);
    QVERIFY(runOperation(&store, [&] { store.setImage(image, island); }).value(u"ok"_s).toBool());
    QVERIFY(runOperation(&store, [&] { store.setImage(image, forest); }).value(u"ok"_s).toBool());
    const QString sharedPath = store.imagePathForBinding(island);
    QCOMPARE(store.imagePathForBinding(forest), sharedPath);
    QVERIFY(!sharedPath.isEmpty());
    if (missing)
        QVERIFY(QFile::remove(sharedPath));
    else
        QVERIFY(writeFile(sharedPath, QByteArrayLiteral("not the original image")));
    QSignalSpy changes(&store, &CustomCardArtStore::bindingsChanged);
    QVERIFY(runOperation(&store, [&] { store.setImage(image, island); }).value(u"ok"_s).toBool());
    QCOMPARE(changes.count(), 1);
    const QVariantList affected = changes.first().first().toList();
    QCOMPARE(affected.size(), 2);
    QVERIFY(affected.contains(island));
    QVERIFY(affected.contains(forest));
    QCOMPARE(readFile(sharedPath), readFile(image.toLocalFile()));
}

void TestCustomCardArtStore::restoreDoesNotQueueBehindCatalogMaintenance()
{
    QTemporaryDir directory;
    CustomCardArtStore store(directory.filePath(u"profile"_s));
    const auto image = makeImage(directory.filePath(u"image.png"_s));
    QVERIFY(
        runOperation(&store, [&] { store.setImage(image, binding()); }).value(u"ok"_s).toBool());

    // Occupy every general maintenance worker deterministically. A custom
    // restore has no dependency on these unrelated jobs and must still finish.
    struct BlockedMaintenance
    {
        QSemaphore started;
        QSemaphore release;
        QList<QFuture<void>> workers;
        BlockedMaintenance()
        {
            const int count = BackgroundTaskPools::catalogMaintenance()->maxThreadCount();
            for (int index = 0; index < count; ++index) {
                workers.append(QtConcurrent::run(BackgroundTaskPools::catalogMaintenance(), [this] {
                    started.release();
                    release.acquire();
                }));
            }
        }
        ~BlockedMaintenance()
        {
            release.release(workers.size());
            for (auto &worker : workers)
                worker.waitForFinished();
        }
    } blocked;
    QVERIFY(blocked.started.tryAcquire(blocked.workers.size(), 5000));
    QSignalSpy finished(&store, &CustomCardArtStore::operationFinished);
    store.removeBindings(binding());
    QVERIFY(store.busy());
    QVERIFY2(finished.wait(3000), "Restore must not wait for the catalog maintenance queue");
    QVERIFY(finished.first().first().toMap().value(u"ok"_s).toBool());
    QVERIFY(store.entries().isEmpty());
    QVERIFY(!store.busy());
}

void TestCustomCardArtStore::changedBindingsContainOnlyAffectedIdentitiesAfterBusyClears()
{
    QTemporaryDir directory;
    CustomCardArtStore store(directory.filePath(u"profile"_s));
    const auto firstImage = makeImage(directory.filePath(u"first.png"_s), Qt::red);
    const auto secondImage = makeImage(directory.filePath(u"second.png"_s), Qt::blue);
    const QVariantMap island = binding();
    const QVariantMap forest = binding(u"Forest"_s, u"2"_s);
    QSignalSpy changes(&store, &CustomCardArtStore::bindingsChanged);
    bool notifiedWhileBusy = false;
    connect(&store, &CustomCardArtStore::changed, &store,
            [&] { notifiedWhileBusy = notifiedWhileBusy || store.busy(); });
    connect(&store, &CustomCardArtStore::bindingsChanged, &store,
            [&] { notifiedWhileBusy = notifiedWhileBusy || store.busy(); });
    QVERIFY(
        runOperation(&store, [&] { store.setImage(firstImage, island); }).value(u"ok"_s).toBool());
    QCOMPARE(changes.count(), 1);
    QCOMPARE(changes.last().first().toList(), QVariantList{island});
    QVERIFY(
        runOperation(&store, [&] { store.setImage(firstImage, forest); }).value(u"ok"_s).toBool());
    QCOMPARE(changes.last().first().toList(), QVariantList{forest});
    QVERIFY(
        runOperation(&store, [&] { store.setImage(secondImage, island); }).value(u"ok"_s).toBool());
    QCOMPARE(changes.count(), 3);
    QCOMPARE(changes.last().first().toList(), QVariantList{island});
    QVERIFY(
        runOperation(&store, [&] { store.setImage(secondImage, island); }).value(u"ok"_s).toBool());
    QCOMPARE(changes.count(), 3); // Reinstalling the same image is not a visual change.
    QVERIFY(runOperation(&store, [&] { store.removeBindings(island); }).value(u"ok"_s).toBool());
    QCOMPARE(changes.count(), 4);
    QCOMPARE(changes.last().first().toList(), QVariantList{island});
    QVERIFY(runOperation(&store, [&] { store.clear(); }).value(u"ok"_s).toBool());
    QCOMPARE(changes.last().first().toList(), QVariantList{forest});
    QVERIFY(!notifiedWhileBusy);
    for (const auto &signal : changes) {
        for (const QVariant &value : signal.first().toList()) {
            QCOMPARE(value.toMap().size(), 6);
            QVERIFY(!value.toMap().contains(u"fileName"_s));
            QVERIFY(!value.toMap().contains(u"imageSource"_s));
        }
    }
    store.load();
    QVERIFY(changes.last().first().toList().isEmpty());
    QVERIFY(store.setImageRoot(directory.filePath(u"new-root"_s)));
    QVERIFY(changes.last().first().toList().isEmpty());
}

void TestCustomCardArtStore::copiesPersistsRestoresAndDoesNotTouchNormalCache()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString profile = directory.filePath(u"profile"_s);
    const QString normalIndex = QDir(profile).filePath(u"card-cache.json"_s);
    QVERIFY(writeFile(normalIndex, QByteArrayLiteral("ordinary cache sentinel")));
    const QUrl image = makeImage(directory.filePath(u"original.png"_s));
    QVERIFY(!image.isEmpty());
    QString stored;
    {
        CustomCardArtStore store(profile);
        QVERIFY(!store.hasEntries());
        const auto result = runOperation(&store, [&] { store.setImage(image, binding()); });
        QVERIFY2(result.value(u"ok"_s).toBool(), qPrintable(result.value(u"error"_s).toString()));
        QCOMPARE(result.value(u"operation"_s).toString(), u"setImage"_s);
        QCOMPARE(result.value(u"fileUrl"_s).toString(), image.toString());
        stored = store.imagePath(u"Island"_s, u"tst"_s, u"1"_s);
        QVERIFY(!stored.isEmpty());
        QVERIFY(stored != image.toLocalFile());
        QCOMPARE(readFile(stored), readFile(image.toLocalFile()));
        QVERIFY(store.hasEntries());
        QCOMPARE(store.entries().size(), 1);
        QVERIFY(store.imagePath(u"Island"_s, u"TST"_s, u"2"_s).isEmpty());
        QVERIFY(QFile::remove(image.toLocalFile()));
        QVERIFY(QFileInfo::exists(stored));
        const QByteArray index = readFile(QDir(profile).filePath(u"custom-art.json"_s));
        QVERIFY(!index.contains(directory.path().toUtf8()));
    }
    CustomCardArtStore reopened(profile);
    QCOMPARE(reopened.imagePath(u"Island"_s, u"TST"_s, u"1"_s), stored);
    const auto removed = runOperation(&reopened, [&] { reopened.removeBindings(binding()); });
    QVERIFY(removed.value(u"ok"_s).toBool());
    QVERIFY(!reopened.hasEntries());
    QVERIFY(!QFileInfo::exists(stored));
    QCOMPARE(readFile(normalIndex), QByteArrayLiteral("ordinary cache sentinel"));
}

void TestCustomCardArtStore::separatesExactCardWideAndDoubleFacedOverrides()
{
    QTemporaryDir directory;
    QVERIFY(createCatalog(directory.filePath(u"cards.sqlite"_s)));
    CustomCardArtStore store(directory.path());
    const QUrl red = makeImage(directory.filePath(u"red.png"_s), Qt::red);
    const QUrl blue = makeImage(directory.filePath(u"blue.png"_s), Qt::blue);
    QVariantMap global = binding(u"Front // Back"_s, u"2"_s, {}, u"card"_s);
    QVERIFY(runOperation(&store, [&] { store.setImage(red, global); }).value(u"ok"_s).toBool());
    const QString fallback =
        store.imagePath(u"Front"_s, u"OTHER"_s, u"9"_s, global.value(u"oracleId"_s).toString());
    QVERIFY(!fallback.isEmpty());
    QVERIFY(store.imagePath(u"Front"_s, u"OTHER"_s, u"9"_s, u"different-oracle"_s).isEmpty());
    const QVariantMap exact = binding(u"Front // Back"_s, u"2"_s);
    QVERIFY(runOperation(&store, [&] { store.setImage(blue, exact); }).value(u"ok"_s).toBool());
    const QString front =
        store.imagePath(u"Front"_s, u"TST"_s, u"2"_s, global.value(u"oracleId"_s).toString());
    QVERIFY(front != fallback);
    QCOMPARE(store.imagePath(u"Front // Back"_s, u"TST"_s, u"2"_s), front);
    QVERIFY(store.imagePath(u"Back"_s, u"TST"_s, u"2"_s, global.value(u"oracleId"_s).toString())
                .isEmpty());
    const auto reverse = binding(u"Front // Back"_s, u"2"_s, u"Back"_s);
    QVERIFY(runOperation(&store, [&] { store.setImage(red, reverse); }).value(u"ok"_s).toBool());
    QVERIFY(!store.imagePath(u"Back"_s, u"TST"_s, u"2"_s).isEmpty());
    const auto prepare = binding(u"Emeritus // Swords"_s, u"3"_s);
    QVERIFY(runOperation(&store, [&] { store.setImage(red, prepare); }).value(u"ok"_s).toBool());
    QVERIFY(!store.imagePath(u"Emeritus"_s, u"TST"_s, u"3"_s).isEmpty());
    QVERIFY(store.imagePath(u"Swords"_s, u"TST"_s, u"3"_s).isEmpty());
    QVERIFY(
        runOperation(&store, [&] { store.removeBindings(exact, true); }).value(u"ok"_s).toBool());
    QCOMPARE(store.imagePath(u"Front"_s, u"TST"_s, u"2"_s, global.value(u"oracleId"_s).toString()),
             fallback);
    QVERIFY(store.entryFor(exact).isEmpty());
    QVERIFY(store.entryFor(reverse).isEmpty());
    QVERIFY(!store.entryFor(global).isEmpty());
}

void TestCustomCardArtStore::validatesImagesBeforePreviewAndUsesImmutableSnapshot()
{
    QTemporaryDir directory;
    CustomCardArtStore store(directory.filePath(u"profile"_s));
    const QUrl source = makeImage(directory.filePath(u"source.png"_s), Qt::green);
    QVERIFY(runOperation(&store, [&] { store.inspectImage(source); }).value(u"ok"_s).toBool());
    const auto preview = store.preview();
    QCOMPARE(preview.value(u"kind"_s).toString(), u"image"_s);
    QCOMPARE(preview.value(u"fileUrl"_s).toString(), source.toString());
    QCOMPARE(preview.value(u"width"_s).toInt(), 24);
    QCOMPARE(preview.value(u"height"_s).toInt(), 32);
    const QUrl staged(preview.value(u"imageSource"_s).toString());
    QVERIFY(staged.isLocalFile());
    QVERIFY(staged != source);
    const QByteArray reviewed = readFile(staged.toLocalFile());
    QVERIFY(!makeImage(source.toLocalFile(), Qt::red).isEmpty());
    QVERIFY(
        runOperation(&store, [&] { store.setImage(staged, binding()); }).value(u"ok"_s).toBool());
    QCOMPARE(readFile(store.imagePath(u"Island"_s, u"TST"_s, u"1"_s)), reviewed);
    const QUrl bad = QUrl::fromLocalFile(directory.filePath(u"not-an-image.png"_s));
    QVERIFY(writeFile(bad.toLocalFile(), QByteArrayLiteral("not an image")));
    QVERIFY(!runOperation(&store, [&] { store.inspectImage(bad); }).value(u"ok"_s).toBool());
    QVERIFY(!store.preview().value(u"ok"_s).toBool());
    QVERIFY(store.preview().value(u"imageSource"_s).toString().isEmpty());
    QCOMPARE(store.preview().value(u"fileUrl"_s).toString(), bad.toString());
}

void TestCustomCardArtStore::directoryFilenamesResolveFacesWithoutGuessing()
{
    QTemporaryDir directory;
    const QString profile = directory.filePath(u"profile"_s);
    QVERIFY(QDir().mkpath(profile));
    QVERIFY(createCatalog(QDir(profile).filePath(u"cards.sqlite"_s)));
    const QString source = directory.filePath(u"source"_s);
    for (const QString &relative :
         {u"TST/1.front.png"_s, u"TST/2.front.png"_s, u"TST/2.back.png"_s, u"TST/3.back.png"_s,
          u"TST/7%E2%80%A0.front.png"_s, u"Island.png"_s})
        QVERIFY(!makeImage(QDir(source).filePath(relative)).isEmpty());
    CustomCardArtStore store(profile);
    QVERIFY(runOperation(&store, [&] { store.inspectDirectory(QUrl::fromLocalFile(source)); })
                .value(u"ok"_s)
                .toBool());
    QCOMPARE(store.preview().value(u"validCount"_s).toInt(), 4);
    QCOMPARE(store.preview().value(u"errorCount"_s).toInt(), 2);
    QVERIFY(!store.hasEntries());
    QVERIFY(!QFileInfo::exists(QDir(profile).filePath(u"custom-art.json"_s)));
    QVERIFY(runOperation(&store, [&] { store.importPreview(); }).value(u"ok"_s).toBool());
    QCOMPARE(store.entries().size(), 4);
    QVERIFY(!store.imagePath(u"Front"_s, u"TST"_s, u"2"_s).isEmpty());
    QVERIFY(!store.imagePath(u"Back"_s, u"TST"_s, u"2"_s).isEmpty());
    QVERIFY(!store.imagePath(u"Dagger"_s, u"TST"_s, u"7†"_s).isEmpty());
    QVERIFY(store.imagePath(u"Swords"_s, u"TST"_s, u"3"_s).isEmpty());
}

void TestCustomCardArtStore::directoryManifestRejectsTraversalAndAmbiguousMappings()
{
    QTemporaryDir directory;
    const QString source = directory.filePath(u"source"_s);
    QVERIFY(!makeImage(QDir(source).filePath(u"one.png"_s)).isEmpty());
    QVERIFY(!makeImage(QDir(source).filePath(u"two.png"_s), Qt::blue).isEmpty());
    QVERIFY(!makeImage(directory.filePath(u"outside.png"_s)).isEmpty());
    auto one = binding();
    one.insert(u"file"_s, u"one.png"_s);
    auto duplicate = binding();
    duplicate.insert(u"file"_s, u"two.png"_s);
    auto traversal = binding(u"Outside"_s, u"9"_s);
    traversal.insert(u"file"_s, u"../outside.png"_s);
    auto valid = binding(u"Mountain"_s, u"5"_s);
    valid.insert(u"file"_s, u"one.png"_s);
    QVERIFY(writeManifest(source, {one, duplicate, traversal, valid}));
    CustomCardArtStore store(directory.filePath(u"profile"_s));
    QVERIFY(runOperation(&store, [&] { store.inspectDirectory(QUrl::fromLocalFile(source)); })
                .value(u"ok"_s)
                .toBool());
    QCOMPARE(store.preview().value(u"validCount"_s).toInt(), 1);
    QCOMPARE(store.preview().value(u"errorCount"_s).toInt(), 3);
    QVERIFY(runOperation(&store, [&] { store.importPreview(); }).value(u"ok"_s).toBool());
    QCOMPARE(store.entries().size(), 1);
    QVERIFY(!store.imagePath(u"Mountain"_s, u"TST"_s, u"5"_s).isEmpty());
}

void TestCustomCardArtStore::customPackRequiresInspectionAndExplicitImport()
{
    QTemporaryDir directory;
    CustomCardArtStore source(directory.filePath(u"source"_s));
    const QUrl image = makeImage(directory.filePath(u"original.png"_s));
    QVERIFY(
        runOperation(&source, [&] { source.setImage(image, binding()); }).value(u"ok"_s).toBool());
    QVERIFY(runOperation(&source, [&] { source.setImage(image, binding(u"Mountain"_s, u"2"_s)); })
                .value(u"ok"_s)
                .toBool());
    const QUrl pack = QUrl::fromLocalFile(directory.filePath(u"shared.hexproof-custom-artpack"_s));
    const auto exported = runOperation(&source, [&] { source.exportPack(pack); });
    QVERIFY(exported.value(u"ok"_s).toBool());
    QCOMPARE(exported.value(u"entryCount"_s).toInt(), 2);
    QCOMPARE(exported.value(u"imageCount"_s).toInt(), 1);
    QVERIFY(!cardart::inspectPack(pack.toLocalFile()).value(u"ok"_s).toBool());
    CardArtCache ordinary(directory.filePath(u"ordinary"_s));
    const auto normalImage = makeImage(QDir(ordinary.imageRoot()).filePath(u"normal.png"_s));
    CardRecord normalRecord;
    normalRecord.name = normalRecord.requestedName = u"Island"_s;
    normalRecord.setCode = u"TST"_s;
    normalRecord.collectorNumber = u"1"_s;
    normalRecord.imagePath = normalImage.toLocalFile();
    normalRecord.imageLanguage = u"en"_s;
    const QString normalPack = directory.filePath(u"normal.hexproof-artpack"_s);
    const auto normalExport = cardart::exportPack(
        normalPack, ordinary.imageRoot(),
        {{ordinary.key(u"Island"_s, u"en"_s, u"TST"_s, u"1"_s), normalRecord}}, false, {}, {});
    QVERIFY2(normalExport.ok, qPrintable(normalExport.error));
    CustomCardArtStore target(directory.filePath(u"target"_s));
    QVERIFY(!runOperation(&target, [&] { target.inspectPack(QUrl::fromLocalFile(normalPack)); })
                 .value(u"ok"_s)
                 .toBool());
    QVERIFY(!runOperation(&target, [&] { target.importPreview(); }).value(u"ok"_s).toBool());
    QVERIFY(runOperation(&target, [&] { target.inspectPack(pack); }).value(u"ok"_s).toBool());
    QCOMPARE(target.preview().value(u"kind"_s).toString(), u"pack"_s);
    QCOMPARE(target.preview().value(u"validCount"_s).toInt(), 2);
    QVERIFY(!target.hasEntries());
    QVERIFY(!QFileInfo::exists(target.imageRoot()));
    QVERIFY(runOperation(&target, [&] { target.importPreview(); }).value(u"ok"_s).toBool());
    QCOMPARE(target.entries().size(), 2);
    const QByteArray index = readFile(directory.filePath(u"target/custom-art.json"_s));
    QVERIFY(!index.contains(directory.path().toUtf8()));
    QCOMPARE(readFile(target.imagePath(u"Island"_s, u"TST"_s, u"1"_s)),
             readFile(image.toLocalFile()));
}

void TestCustomCardArtStore::customPackConflictPolicyPreservesUnlessConfirmed()
{
    QTemporaryDir directory;
    CustomCardArtStore source(directory.filePath(u"source"_s));
    CustomCardArtStore target(directory.filePath(u"target"_s));
    const auto red = makeImage(directory.filePath(u"red.png"_s), Qt::red);
    const auto blue = makeImage(directory.filePath(u"blue.png"_s), Qt::blue);
    QVERIFY(
        runOperation(&source, [&] { source.setImage(red, binding()); }).value(u"ok"_s).toBool());
    QVERIFY(
        runOperation(&target, [&] { target.setImage(blue, binding()); }).value(u"ok"_s).toBool());
    const QString previous = target.imagePath(u"Island"_s, u"TST"_s, u"1"_s);
    const QUrl pack =
        QUrl::fromLocalFile(directory.filePath(u"conflict.hexproof-custom-artpack"_s));
    QVERIFY(runOperation(&source, [&] { source.exportPack(pack); }).value(u"ok"_s).toBool());
    QVERIFY(runOperation(&target, [&] { target.inspectPack(pack); }).value(u"ok"_s).toBool());
    QCOMPARE(target.preview().value(u"conflictCount"_s).toInt(), 1);
    const auto kept = runOperation(&target, [&] { target.importPreview(); });
    QVERIFY(kept.value(u"ok"_s).toBool());
    QCOMPARE(kept.value(u"preservedCount"_s).toInt(), 1);
    QCOMPARE(target.imagePath(u"Island"_s, u"TST"_s, u"1"_s), previous);
    QVERIFY(runOperation(&target, [&] { target.importPreview(true); }).value(u"ok"_s).toBool());
    QVERIFY(target.imagePath(u"Island"_s, u"TST"_s, u"1"_s) != previous);
}

void TestCustomCardArtStore::tamperedPackAndChangedPreviewDoNotUpdateIndex()
{
    QTemporaryDir directory;
    CustomCardArtStore source(directory.filePath(u"source"_s));
    const auto image = makeImage(directory.filePath(u"image.png"_s));
    QVERIFY(
        runOperation(&source, [&] { source.setImage(image, binding()); }).value(u"ok"_s).toBool());
    const QUrl pack = QUrl::fromLocalFile(directory.filePath(u"share.hexproof-custom-artpack"_s));
    QVERIFY(runOperation(&source, [&] { source.exportPack(pack); }).value(u"ok"_s).toBool());
    CustomCardArtStore target(directory.filePath(u"target"_s));
    QVERIFY(runOperation(&target, [&] { target.inspectPack(pack); }).value(u"ok"_s).toBool());
    const QString staged = QUrl(target.preview()
                                    .value(u"rows"_s)
                                    .toList()
                                    .first()
                                    .toMap()
                                    .value(u"imageSource"_s)
                                    .toString())
                               .toLocalFile();
    QVERIFY(writeFile(staged, QByteArrayLiteral("tampered")));
    QVERIFY(!runOperation(&target, [&] { target.importPreview(); }).value(u"ok"_s).toBool());
    QVERIFY(!target.hasEntries());
    QByteArray damaged = readFile(pack.toLocalFile());
    damaged[damaged.size() - 1] = damaged.at(damaged.size() - 1) ^ 0x7f;
    QVERIFY(writeFile(pack.toLocalFile(), damaged));
    QVERIFY(!runOperation(&target, [&] { target.inspectPack(pack); }).value(u"ok"_s).toBool());
    QVERIFY(!QFileInfo::exists(directory.filePath(u"target/custom-art.json"_s)));
}

void TestCustomCardArtStore::removingSharedImagesPreservesRemainingBindings()
{
    QTemporaryDir directory;
    CustomCardArtStore store(directory.filePath(u"profile"_s));
    const auto image = makeImage(directory.filePath(u"image.png"_s));
    QVERIFY(
        runOperation(&store, [&] { store.setImage(image, binding()); }).value(u"ok"_s).toBool());
    const auto second = binding(u"Mountain"_s, u"2"_s);
    QVERIFY(runOperation(&store, [&] { store.setImage(image, second); }).value(u"ok"_s).toBool());
    const QString path = store.imagePath(u"Island"_s, u"TST"_s, u"1"_s);
    QCOMPARE(path, store.imagePath(u"Mountain"_s, u"TST"_s, u"2"_s));
    QVERIFY(
        runOperation(
            &store, [&] { store.removeEntry(store.entryFor(binding()).value(u"id"_s).toString()); })
            .value(u"ok"_s)
            .toBool());
    QVERIFY(QFileInfo::exists(path));
    QVERIFY(runOperation(&store, [&] { store.clear(); }).value(u"ok"_s).toBool());
    QVERIFY(!QFileInfo::exists(path));
}

void TestCustomCardArtStore::operationGuardAndOfflineImageRootStayReadOnly()
{
    QTemporaryDir directory;
    const QString root = directory.filePath(u"not-mounted/custom-art"_s);
    CustomCardArtStore store(directory.filePath(u"profile"_s), root);
    QVERIFY(!QFileInfo::exists(root));
    store.load();
    QVERIFY(!QFileInfo::exists(root));
    store.setOperationGuard([] { return false; });
    const auto image = makeImage(directory.filePath(u"image.png"_s));
    QVERIFY(
        !runOperation(&store, [&] { store.setImage(image, binding()); }).value(u"ok"_s).toBool());
    QVERIFY(!QFileInfo::exists(root));
    QVERIFY(!store.busy());
    const QString alternative = directory.filePath(u"new-mount/custom-art"_s);
    QVERIFY(store.setImageRoot(alternative));
    QVERIFY(!QFileInfo::exists(alternative));
}

void TestCustomCardArtStore::rejectsBadInputsAndPreservesDamagedIndex()
{
    QTemporaryDir directory;
    CustomCardArtStore store(directory.filePath(u"profile"_s));
    const auto image = makeImage(directory.filePath(u"image.png"_s));
    auto bad = binding();
    bad.insert(u"setCode"_s, u"../bad"_s);
    QVERIFY(!runOperation(&store, [&] { store.setImage(image, bad); }).value(u"ok"_s).toBool());
    QVERIFY(!runOperation(&store,
                          [&] { store.inspectImage(QUrl(u"https://example.test/image.png"_s)); })
                 .value(u"ok"_s)
                 .toBool());
    QCOMPARE(store.preview().value(u"kind"_s).toString(), u"image"_s);
    const QString indexPath = directory.filePath(u"profile/custom-art.json"_s);
    QVERIFY(writeFile(indexPath, QByteArrayLiteral("broken user index")));
    store.load();
    QVERIFY(!store.lastError().isEmpty());
    QVERIFY(
        !runOperation(&store, [&] { store.setImage(image, binding()); }).value(u"ok"_s).toBool());
    QCOMPARE(readFile(indexPath), QByteArrayLiteral("broken user index"));
}

void TestCustomCardArtStore::bulkDirectoryHandlesManyBindingsWithOneImage()
{
    QTemporaryDir directory;
    const QString source = directory.filePath(u"images"_s);
    QVERIFY(!makeImage(QDir(source).filePath(u"shared.png"_s)).isEmpty());
    QVariantList mappings;
    constexpr int count = 1'200;
    for (int i = 0; i < count; ++i) {
        auto mapping = binding(u"Cube %1"_s.arg(i), QString::number(i));
        mapping.insert(u"file"_s, u"shared.png"_s);
        mappings.append(mapping);
    }
    QVERIFY(writeManifest(source, mappings));
    CustomCardArtStore store(directory.filePath(u"profile"_s));
    QVERIFY(runOperation(&store, [&] { store.inspectDirectory(QUrl::fromLocalFile(source)); })
                .value(u"ok"_s)
                .toBool());
    QCOMPARE(store.preview().value(u"validCount"_s).toInt(), count);
    const auto imported = runOperation(&store, [&] { store.importPreview(); });
    QVERIFY2(imported.value(u"ok"_s).toBool(), qPrintable(imported.value(u"error"_s).toString()));
    QCOMPARE(imported.value(u"importedCount"_s).toInt(), count);
    QCOMPARE(imported.value(u"imageCount"_s).toInt(), 1);
    QCOMPARE(store.entries().size(), count);
}

void TestCustomCardArtStore::stripsUnknownMetadataBeforePersistenceAndExport()
{
    QTemporaryDir directory;
    const QString profile = directory.filePath(u"profile"_s);
    CustomCardArtStore store(profile);
    const auto image = makeImage(directory.filePath(u"source.png"_s));
    auto inputBinding = binding();
    inputBinding.insert(u"privateDevicePath"_s, u"/do/not/export/private-name"_s);
    QVERIFY(
        runOperation(&store, [&] { store.setImage(image, inputBinding); }).value(u"ok"_s).toBool());
    const QString index = QDir(profile).filePath(u"custom-art.json"_s);
    QVERIFY(!readFile(index).contains("privateDevicePath"));
    auto object = QJsonDocument::fromJson(readFile(index)).object();
    auto array = object.value(u"entries"_s).toArray();
    auto entry = array.first().toObject();
    entry.insert(u"privateDevicePath"_s, u"/do/not/export/private-name"_s);
    array[0] = entry;
    object.insert(u"entries"_s, array);
    QVERIFY(writeFile(index, QJsonDocument(object).toJson()));
    store.load();
    QVERIFY(store.lastError().isEmpty());
    QVERIFY(!store.entries().first().toMap().contains(u"privateDevicePath"_s));
    const QUrl pack = QUrl::fromLocalFile(directory.filePath(u"clean.hexproof-custom-artpack"_s));
    QVERIFY(runOperation(&store, [&] { store.exportPack(pack); }).value(u"ok"_s).toBool());
    QVERIFY(!readFile(pack.toLocalFile()).contains("privateDevicePath"));
    QVERIFY(!readFile(pack.toLocalFile()).contains("/do/not/export"));
}

void TestCustomCardArtStore::refusesCardWideBindingsWithoutVerifiedIdentity()
{
    QTemporaryDir directory;
    CustomCardArtStore store(directory.filePath(u"profile"_s));
    const auto image = makeImage(directory.filePath(u"source.png"_s));
    auto global = binding(u"Goblin"_s, u"1"_s, {}, u"card"_s);
    global.insert(u"oracleId"_s, QString{});
    QVERIFY(!runOperation(&store, [&] { store.setImage(image, global); }).value(u"ok"_s).toBool());
    global.insert(u"oracleId"_s, u"unverified-oracle"_s);
    QVERIFY(!runOperation(&store, [&] { store.setImage(image, global); }).value(u"ok"_s).toBool());
    QVERIFY(!store.hasEntries());
    QVERIFY(QDir().mkpath(directory.filePath(u"profile"_s)));
    QVERIFY(createCatalog(directory.filePath(u"profile/cards.sqlite"_s)));
    global = binding(u"Island"_s, u"1"_s, {}, u"card"_s);
    global.insert(u"oracleId"_s, u"another-cards-oracle"_s);
    QVERIFY(!runOperation(&store, [&] { store.setImage(image, global); }).value(u"ok"_s).toBool());
    QVERIFY(!store.hasEntries());
}

void TestCustomCardArtStore::acceptsSupportedFormatsAndRejectsOversizedDimensions()
{
    QTemporaryDir directory;
    CustomCardArtStore store(directory.filePath(u"profile"_s));
    for (const auto &format :
         {QByteArrayLiteral("JPEG"), QByteArrayLiteral("PNG"), QByteArrayLiteral("WEBP")}) {
        const auto image = makeImage(directory.filePath(u"image-"_s + QString::fromLatin1(format)),
                                     Qt::red, format.constData());
        QVERIFY(!image.isEmpty());
        const auto result = runOperation(&store, [&] { store.inspectImage(image); });
        QVERIFY2(result.value(u"ok"_s).toBool(), qPrintable(result.value(u"error"_s).toString()));
    }
    QImage wide(12'001, 1, QImage::Format_ARGB32);
    wide.fill(Qt::blue);
    const QString path = directory.filePath(u"too-wide.png"_s);
    QVERIFY(wide.save(path, "PNG"));
    QVERIFY(!runOperation(&store, [&] { store.inspectImage(QUrl::fromLocalFile(path)); })
                 .value(u"ok"_s)
                 .toBool());
    QVERIFY(!store.preview().value(u"ok"_s).toBool());
}

void TestCustomCardArtStore::indexFailureRollsBackOnlyNewImages()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString profile = directory.filePath(u"profile"_s);
    CustomCardArtStore store(profile);
    const auto red = makeImage(directory.filePath(u"red.png"_s), Qt::red);
    const auto blue = makeImage(directory.filePath(u"blue.png"_s), Qt::blue);
    QVERIFY(runOperation(&store, [&] { store.setImage(red, binding()); }).value(u"ok"_s).toBool());
    const QString originalImage = store.imagePath(u"Island"_s, u"TST"_s, u"1"_s);
    const QString index = QDir(profile).filePath(u"custom-art.json"_s);
    const QString preservedIndex = directory.filePath(u"preserved-index.json"_s);
    const QByteArray originalIndex = readFile(index);
    const QStringList originalFiles = QDir(store.imageRoot()).entryList(QDir::Files);
    QVERIFY(QFile::rename(index, preservedIndex));
    QVERIFY(QDir().mkpath(index));
    const auto failed = runOperation(&store, [&] { store.setImage(blue, binding()); });
    QVERIFY(!failed.value(u"ok"_s).toBool());
    QVERIFY(!failed.value(u"error"_s).toString().isEmpty());
    QCOMPARE(store.imagePath(u"Island"_s, u"TST"_s, u"1"_s), originalImage);
    QCOMPARE(readFile(originalImage), readFile(red.toLocalFile()));
    QCOMPARE(QDir(store.imageRoot()).entryList(QDir::Files), originalFiles);
    QCOMPARE(readFile(preservedIndex), originalIndex);
    QVERIFY(QDir().rmdir(index));
    QVERIFY(QFile::rename(preservedIndex, index));
    CustomCardArtStore reopened(profile);
    QCOMPARE(reopened.imagePath(u"Island"_s, u"TST"_s, u"1"_s), originalImage);
}

void TestCustomCardArtStore::invalidPreviewDirectoryAndSymlinksAreRejected()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto image = makeImage(directory.filePath(u"source.png"_s));
    QVERIFY(!customart::stageImage(image.toLocalFile(), {}).ok);
    const QString missing = directory.filePath(u"missing-preview"_s);
    QVERIFY(!customart::stageImage(image.toLocalFile(), missing).ok);
    QVERIFY(!QFileInfo::exists(missing));
#ifdef Q_OS_UNIX
    const QString linkedSource = directory.filePath(u"linked.png"_s);
    QVERIFY(QFile::link(image.toLocalFile(), linkedSource));
    CustomCardArtStore store(directory.filePath(u"profile"_s));
    QVERIFY(!runOperation(&store, [&] { store.inspectImage(QUrl::fromLocalFile(linkedSource)); })
                 .value(u"ok"_s)
                 .toBool());
    const QString outside = directory.filePath(u"outside"_s);
    const QString root = directory.filePath(u"folder"_s);
    QVERIFY(QDir().mkpath(root));
    QVERIFY(!makeImage(QDir(outside).filePath(u"source.png"_s)).isEmpty());
    QVERIFY(QFile::link(outside, QDir(root).filePath(u"linked-directory"_s)));
    auto entry = binding();
    entry.insert(u"file"_s, u"linked-directory/source.png"_s);
    QVERIFY(writeManifest(root, {entry}));
    QVERIFY(runOperation(&store, [&] { store.inspectDirectory(QUrl::fromLocalFile(root)); })
                .value(u"ok"_s)
                .toBool());
    QCOMPARE(store.preview().value(u"validCount"_s).toInt(), 0);
    QCOMPARE(store.preview().value(u"errorCount"_s).toInt(), 1);
    QVERIFY(!store.hasEntries());
#endif
}

void TestCustomCardArtStore::exportSkipsInconsistentSharedImageMetadata()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString profile = directory.filePath(u"source-profile"_s);
    CustomCardArtStore store(profile);
    const auto image = makeImage(directory.filePath(u"source.png"_s));
    QVERIFY(
        runOperation(&store, [&] { store.setImage(image, binding()); }).value(u"ok"_s).toBool());
    QVERIFY(runOperation(&store, [&] { store.setImage(image, binding(u"Swamp"_s, u"2"_s)); })
                .value(u"ok"_s)
                .toBool());
    const QString index = QDir(profile).filePath(u"custom-art.json"_s);
    auto object = QJsonDocument::fromJson(readFile(index)).object();
    auto entries = object.value(u"entries"_s).toArray();
    auto inconsistent = entries.last().toObject();
    inconsistent.insert(u"bytes"_s, inconsistent.value(u"bytes"_s).toInt() + 1);
    entries[entries.size() - 1] = inconsistent;
    object.insert(u"entries"_s, entries);
    QVERIFY(writeFile(index, QJsonDocument(object).toJson()));
    store.load();
    QVERIFY(store.lastError().isEmpty());
    const QUrl pack = QUrl::fromLocalFile(directory.filePath(u"partial.hexproof-custom-artpack"_s));
    const auto exported = runOperation(&store, [&] { store.exportPack(pack); });
    QVERIFY2(exported.value(u"ok"_s).toBool(), qPrintable(exported.value(u"error"_s).toString()));
    QCOMPARE(exported.value(u"entryCount"_s).toInt(), 1);
    QCOMPARE(exported.value(u"skippedCount"_s).toInt(), 1);
    CustomCardArtStore receiver(directory.filePath(u"receiver-profile"_s));
    QVERIFY(runOperation(&receiver, [&] { receiver.inspectPack(pack); }).value(u"ok"_s).toBool());
    QVERIFY(runOperation(&receiver, [&] { receiver.importPreview(); }).value(u"ok"_s).toBool());
    QCOMPARE(receiver.entries().size(), 1);
    const QString imported =
        QUrl(receiver.entries().first().toMap().value(u"imageSource"_s).toString()).toLocalFile();
    QCOMPARE(readFile(imported), readFile(image.toLocalFile()));
}

void TestCustomCardArtStore::sameNamedTokenFacesRemainIndependent()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString sourceProfile = directory.filePath(u"source-profile"_s);
    QVERIFY(QDir().mkpath(sourceProfile));
    QVERIFY(createCatalog(QDir(sourceProfile).filePath(u"cards.sqlite"_s)));
    const auto red = makeImage(directory.filePath(u"front.png"_s), Qt::red);
    const auto blue = makeImage(directory.filePath(u"back.png"_s), Qt::blue);
    CustomCardArtStore source(sourceProfile);
    for (const QString &scope : {u"printing"_s, u"card"_s}) {
        const auto front = binding(u"Angel // Angel"_s, u"4"_s, {}, scope);
        const auto back = binding(u"Angel // Angel"_s, u"4"_s, u"Angel"_s, scope);
        const QString oracle = front.value(u"oracleId"_s).toString();
        const QString requestedSet = scope == u"printing"_s ? u"TST"_s : u"OTHER"_s;
        QVERIFY(
            runOperation(&source, [&] { source.setImage(red, front); }).value(u"ok"_s).toBool());
        QVERIFY(source.imagePath(u"Angel"_s, requestedSet, u"4"_s, oracle).isEmpty());
        QVERIFY(
            runOperation(&source, [&] { source.setImage(blue, back); }).value(u"ok"_s).toBool());
        const QString frontPath = source.imagePathForBinding(front);
        const QString backPath = source.imagePathForBinding(back);
        QVERIFY(!frontPath.isEmpty());
        QVERIFY(!backPath.isEmpty());
        QVERIFY(frontPath != backPath);
        QCOMPARE(source.imagePath(u"Angel // Angel"_s, requestedSet, u"4"_s, oracle), frontPath);
        QCOMPARE(source.imagePath(u"Angel"_s, requestedSet, u"4"_s, oracle), backPath);
    }
    const auto pack = QUrl::fromLocalFile(directory.filePath(u"faces.hexproof-custom-artpack"_s));
    QVERIFY(runOperation(&source, [&] { source.exportPack(pack); }).value(u"ok"_s).toBool());
    const QString receiverProfile = directory.filePath(u"receiver-profile"_s);
    QVERIFY(QDir().mkpath(receiverProfile));
    QVERIFY(createCatalog(QDir(receiverProfile).filePath(u"cards.sqlite"_s)));
    CustomCardArtStore receiver(receiverProfile);
    QVERIFY(runOperation(&receiver, [&] { receiver.inspectPack(pack); }).value(u"ok"_s).toBool());
    QVERIFY(runOperation(&receiver, [&] { receiver.importPreview(); }).value(u"ok"_s).toBool());
    QCOMPARE(readFile(receiver.imagePath(u"Angel // Angel"_s, u"TST"_s, u"4"_s)),
             readFile(red.toLocalFile()));
    QCOMPARE(readFile(receiver.imagePath(u"Angel"_s, u"TST"_s, u"4"_s)),
             readFile(blue.toLocalFile()));
}

void TestCustomCardArtStore::specialFilesNeverEnterBlockingReaders()
{
#ifdef Q_OS_UNIX
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString pack = directory.filePath(u"pipe.hexproof-custom-artpack"_s);
    QVERIFY(::mkfifo(QFile::encodeName(pack).constData(), 0600) == 0);
    CustomCardArtStore store(directory.filePath(u"profile"_s));
    QVERIFY(!runOperation(&store, [&] { store.inspectPack(QUrl::fromLocalFile(pack)); })
                 .value(u"ok"_s)
                 .toBool());
    const QString folder = directory.filePath(u"folder"_s);
    QVERIFY(QDir().mkpath(folder));
    const QString manifest = QDir(folder).filePath(u"custom-art-map.json"_s);
    QVERIFY(::mkfifo(QFile::encodeName(manifest).constData(), 0600) == 0);
    QVERIFY(!runOperation(&store, [&] { store.inspectDirectory(QUrl::fromLocalFile(folder)); })
                 .value(u"ok"_s)
                 .toBool());
    const QString profile = directory.filePath(u"pipe-profile"_s);
    QVERIFY(QDir().mkpath(profile));
    const QString index = QDir(profile).filePath(u"custom-art.json"_s);
    QVERIFY(::mkfifo(QFile::encodeName(index).constData(), 0600) == 0);
    CustomCardArtStore damaged(profile);
    QVERIFY(!damaged.lastError().isEmpty());
    QVERIFY(!damaged.hasEntries());
#endif
}

void TestCustomCardArtStore::ordinaryCacheSeparatesSameNamedTokenFaceRequests()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.path());
    const QString canonical = u"Angel // Angel"_s;
    const CardRequest front{canonical, u"TST"_s, u"4"_s, u"en"_s};
    const CardRequest back{u"Angel"_s, u"TST"_s, u"4"_s, u"en"_s};
    CardRecord frontRecord;
    frontRecord.name = frontRecord.requestedName = canonical;
    frontRecord.faceName = u"Angel"_s;
    frontRecord.setCode = u"TST"_s;
    frontRecord.collectorNumber = u"4"_s;
    frontRecord.oracleId = u"same-token-oracle"_s;
    frontRecord.imageLanguage = u"en"_s;
    frontRecord.resolutionVersion = catalog_internal::kCardResolutionVersion;
    frontRecord.imagePath =
        makeImage(QDir(cache.imageRoot()).filePath(u"front.png"_s), Qt::red).toLocalFile();
    QVERIFY(!frontRecord.imagePath.isEmpty());
    cache.rememberSuccess(
        cache.key(front.name, front.language, front.setCode, front.collectorNumber), frontRecord);
    QVERIFY(cache.matchesRequestedFace(front, frontRecord));
    QVERIFY(!cache.matchesRequestedFace(back, frontRecord));
    QCOMPARE(cache.resolvedPrinting(front).imagePath, frontRecord.imagePath);
    QVERIFY(!cache.resolvedPrinting(back).valid());
    QVERIFY(!cache.resolvedPrintingMetadata(back).valid());
    CardRequest otherBack = back;
    otherBack.setCode = u"OTHER"_s;
    QVERIFY(!cache.reusableArt(otherBack, frontRecord).valid());
    CardRequest otherFront = front;
    otherFront.setCode = u"OTHER"_s;
    QCOMPARE(cache.reusableArt(otherFront, frontRecord).imagePath, frontRecord.imagePath);

    CardRecord backRecord = frontRecord;
    backRecord.requestedName = back.name;
    backRecord.imagePath =
        makeImage(QDir(cache.imageRoot()).filePath(u"back.png"_s), Qt::blue).toLocalFile();
    QVERIFY(!backRecord.imagePath.isEmpty());
    cache.replaceEntries(
        {{cache.key(back.name, back.language, back.setCode, back.collectorNumber), backRecord}});
    QVERIFY(!cache.matchesRequestedFace(front, backRecord));
    QVERIFY(cache.matchesRequestedFace(back, backRecord));
    QVERIFY(!cache.resolvedPrinting(front).valid());
    QVERIFY(!cache.resolvedPrintingMetadata(front).valid());
    QCOMPARE(cache.resolvedPrinting(back).imagePath, backRecord.imagePath);
    QVERIFY(!cache.reusableArt(otherFront, frontRecord).valid());
    QCOMPARE(cache.reusableArt(otherBack, frontRecord).imagePath, backRecord.imagePath);

    cache.rememberSuccess(
        cache.key(front.name, front.language, front.setCode, front.collectorNumber), frontRecord);
    QVERIFY(cache.save());
    CardArtCache reopened(directory.path());
    reopened.load();
    QCOMPARE(reopened.resolvedPrinting(front).imagePath, frontRecord.imagePath);
    QCOMPARE(reopened.resolvedPrinting(back).imagePath, backRecord.imagePath);
    QCOMPARE(reopened
                 .exactRecord(
                     cache.key(front.name, front.language, front.setCode, front.collectorNumber))
                 .imagePath,
             frontRecord.imagePath);
    QCOMPARE(
        reopened
            .exactRecord(cache.key(back.name, back.language, back.setCode, back.collectorNumber))
            .imagePath,
        backRecord.imagePath);
}

QTEST_GUILESS_MAIN(TestCustomCardArtStore)
#include "customcardartstore_test.moc"
