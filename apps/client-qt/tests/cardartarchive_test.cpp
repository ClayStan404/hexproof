// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/CardArtArchive.h"
#include "services/CardArtAudit.h"
#include "services/CardArtCache.h"
#include "services/CardCatalogCommon.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QTemporaryDir>
#include <QTest>
#include <QUuid>

using namespace Qt::StringLiterals;
using namespace hexproof::client;

namespace {

const QByteArray kPng = QByteArray::fromBase64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=");

bool writeFile(const QString &path, const QByteArray &bytes)
{
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size();
}

CardArtCacheEntry cacheEntry(CardArtCache *cache, const QString &name, const QString &setCode,
                             const QString &language, const QString &imagePath)
{
    CardRecord record;
    record.requestedName = name;
    record.name = name;
    record.oracleId = u"oracle-"_s + name.toCaseFolded();
    record.setCode = setCode;
    record.collectorNumber = u"1"_s;
    record.imageUrl = u"https://cards.scryfall.io/normal/front/test.png"_s;
    record.imagePath = imagePath;
    record.imageLanguage = language;
    record.resolutionVersion = catalog_internal::kCardResolutionVersion;
    return {cache->key(name, language, setCode, record.collectorNumber), record};
}

bool writeFaceCatalog(const QString &databasePath, const QVariantList &cards)
{
    const QString connectionName = u"card-art-audit-test-"_s + QUuid::createUuid().toString();
    bool ok = false;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(databasePath);
        if (database.open()) {
            QSqlQuery query(database);
            ok = query.exec(u"CREATE TABLE cards (name TEXT NOT NULL, layout TEXT NOT NULL, "
                            "type_line TEXT NOT NULL, set_code TEXT NOT NULL, "
                            "collector_number TEXT NOT NULL, lang TEXT NOT NULL)"_s);
            for (const QVariant &value : cards) {
                if (!ok)
                    break;
                const QVariantMap card = value.toMap();
                query.prepare(u"INSERT INTO cards (name, layout, type_line, set_code, "
                              "collector_number, lang) VALUES (?, ?, ?, ?, ?, 'en')"_s);
                query.addBindValue(card.value(u"name"_s));
                query.addBindValue(card.value(u"layout"_s));
                query.addBindValue(card.value(u"typeLine"_s));
                query.addBindValue(card.value(u"setCode"_s));
                query.addBindValue(card.value(u"collectorNumber"_s));
                ok = query.exec();
            }
            database.close();
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return ok;
}

QVariantMap deckPrinting(const QString &name, const QString &setCode,
                         const QString &collectorNumber)
{
    return {
        {u"name"_s, name},
        {u"setCode"_s, setCode},
        {u"collectorNumber"_s, collectorNumber},
    };
}

} // namespace

class TestCardArtArchive final : public QObject
{
    Q_OBJECT

  private slots:
    void inventoryGroupsIndexedAndUnusedFiles() const;
    void packRoundTripDeduplicatesImageBytes() const;
    void selectedExportContainsOnlyRequestedGroup() const;
    void importRejectsTamperedImagePayload() const;
    void orphanCleanupDeletesOnlyUnreferencedFiles() const;
    void selectedCleanupPreservesSharedImage() const;
    void auditRepairsCachedFrontAndFindsMissingBack() const;
    void auditIgnoresPrintingsThatWereNeverCached() const;
    void auditRepairsLegacyPrepareMappingWithoutDownload() const;
    void persistsFaceAuditState() const;
};

void TestCardArtArchive::inventoryGroupsIndexedAndUnusedFiles() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.path());
    const QString indexed = cache.imagePath(u"Alpha"_s, u"https://example.test/a.png"_s, u"en"_s);
    const QString orphan = QDir(cache.imageRoot()).filePath(u"orphan.png"_s);
    QVERIFY(writeFile(indexed, kPng));
    QVERIFY(writeFile(orphan, kPng));
    const CardArtCacheEntry entry = cacheEntry(&cache, u"Alpha"_s, u"TST"_s, u"en"_s, indexed);
    const CardArtCacheEntry missing = cacheEntry(
        &cache, u"Beta"_s, u"TST"_s, u"en"_s, QDir(cache.imageRoot()).filePath(u"missing.png"_s));
    cache.rememberSuccess(entry.cacheKey, entry.record);
    cache.rememberSuccess(missing.cacheKey, missing.record);

    const QVariantMap inventory = cardart::inventory(cache.imageRoot(), cache.entries());
    QCOMPARE(inventory.value(u"imageCount"_s).toInt(), 2);
    QCOMPARE(inventory.value(u"indexedImageCount"_s).toInt(), 1);
    QCOMPARE(inventory.value(u"indexedEntryCount"_s).toInt(), 2);
    QCOMPARE(inventory.value(u"cachedEntryCount"_s).toInt(), 1);
    QCOMPARE(inventory.value(u"missingEntryCount"_s).toInt(), 1);
    QCOMPARE(inventory.value(u"orphanCount"_s).toInt(), 1);
    const QVariantList groups = inventory.value(u"groups"_s).toList();
    QCOMPARE(groups.size(), 1);
    QCOMPARE(groups.first().toMap().value(u"setCode"_s).toString(), u"TST"_s);
    QCOMPARE(groups.first().toMap().value(u"language"_s).toString(), u"en"_s);
    QCOMPARE(groups.first().toMap().value(u"entryCount"_s).toInt(), 2);
    QCOMPARE(groups.first().toMap().value(u"missingEntryCount"_s).toInt(), 1);
}

void TestCardArtArchive::packRoundTripDeduplicatesImageBytes() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString sourceRoot = directory.filePath(u"source"_s);
    CardArtCache source(sourceRoot);
    const QString imagePath =
        source.imagePath(u"Alpha"_s, u"https://cards.scryfall.io/normal/front/test.png"_s, u"en"_s);
    QVERIFY(writeFile(imagePath, kPng));
    const CardArtCacheEntry alpha = cacheEntry(&source, u"Alpha"_s, u"ONE"_s, u"en"_s, imagePath);
    const CardArtCacheEntry beta = cacheEntry(&source, u"Beta"_s, u"TWO"_s, u"en"_s, imagePath);
    source.rememberSuccess(alpha.cacheKey, alpha.record);
    source.rememberSuccess(beta.cacheKey, beta.record);

    const QString packPath = directory.filePath(u"shared.hexproof-artpack"_s);
    const cardart::OperationResult exported =
        cardart::exportPack(packPath, source.imageRoot(), source.entries(), false, {}, {});
    QVERIFY2(exported.ok, qPrintable(exported.error));
    QCOMPARE(exported.entryCount, 2);
    QCOMPARE(exported.imageCount, 1);

    const QVariantMap summary = cardart::inspectPack(packPath);
    QVERIFY(summary.value(u"ok"_s).toBool());
    QCOMPARE(summary.value(u"entryCount"_s).toInt(), 2);
    QCOMPARE(summary.value(u"imageCount"_s).toInt(), 1);
    QCOMPARE(summary.value(u"newEntryCount"_s).toInt(), 2);
    QCOMPARE(summary.value(u"existingEntryCount"_s).toInt(), 0);

    CardArtCache target(directory.filePath(u"target"_s));
    const cardart::OperationResult imported = cardart::importPack(packPath, target.imageRoot());
    QVERIFY2(imported.ok, qPrintable(imported.error));
    QCOMPARE(imported.importedEntries.size(), 2);
    QCOMPARE(imported.importedEntries.at(0).record.imagePath,
             imported.importedEntries.at(1).record.imagePath);
    QVERIFY(QFileInfo::exists(imported.importedEntries.first().record.imagePath));
    for (const CardArtCacheEntry &entry : imported.importedEntries)
        target.rememberSuccess(entry.cacheKey, entry.record);
    QVERIFY(target.save());
    const QVariantMap duplicateSummary = cardart::inspectPack(packPath, target.entries());
    QCOMPARE(duplicateSummary.value(u"newEntryCount"_s).toInt(), 0);
    QCOMPARE(duplicateSummary.value(u"existingEntryCount"_s).toInt(), 2);

    CardArtCache restored(directory.filePath(u"target"_s));
    restored.load();
    QVERIFY(restored.exactRecord(alpha.cacheKey).valid());
    QVERIFY(restored.exactRecord(beta.cacheKey).valid());
}

void TestCardArtArchive::importRejectsTamperedImagePayload() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache source(directory.filePath(u"source"_s));
    const QString imagePath =
        source.imagePath(u"Alpha"_s, u"https://example.test/a.png"_s, u"en"_s);
    QVERIFY(writeFile(imagePath, kPng));
    const CardArtCacheEntry entry = cacheEntry(&source, u"Alpha"_s, u"TST"_s, u"en"_s, imagePath);
    source.rememberSuccess(entry.cacheKey, entry.record);
    const QString packPath = directory.filePath(u"tampered.hexproof-artpack"_s);
    QVERIFY(cardart::exportPack(packPath, source.imageRoot(), source.entries(), false, {}, {}).ok);

    QFile pack(packPath);
    QVERIFY(pack.open(QIODevice::ReadWrite));
    QVERIFY(pack.seek(pack.size() - 1));
    char last = 0;
    QCOMPARE(pack.read(&last, 1), 1);
    QVERIFY(pack.seek(pack.size() - 1));
    last ^= 0x01;
    QCOMPARE(pack.write(&last, 1), 1);
    pack.close();

    const cardart::OperationResult imported =
        cardart::importPack(packPath, directory.filePath(u"target-images"_s));
    QVERIFY(!imported.ok);
    QVERIFY(!imported.error.isEmpty());
}

void TestCardArtArchive::selectedExportContainsOnlyRequestedGroup() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache source(directory.filePath(u"source"_s));
    const QString firstImage =
        source.imagePath(u"Alpha"_s, u"https://example.test/a.png"_s, u"en"_s);
    const QString secondImage =
        source.imagePath(u"Beta"_s, u"https://example.test/b.png"_s, u"zh"_s);
    QVERIFY(writeFile(firstImage, kPng));
    QVERIFY(writeFile(secondImage, kPng));
    const CardArtCacheEntry first = cacheEntry(&source, u"Alpha"_s, u"ONE"_s, u"en"_s, firstImage);
    const CardArtCacheEntry second = cacheEntry(&source, u"Beta"_s, u"TWO"_s, u"zh"_s, secondImage);
    source.rememberSuccess(first.cacheKey, first.record);
    source.rememberSuccess(second.cacheKey, second.record);

    const QString packPath = directory.filePath(u"selected.hexproof-artpack"_s);
    const cardart::OperationResult exported = cardart::exportPack(
        packPath, source.imageRoot(), source.entries(), true, u"two"_s, u"zh"_s);
    QVERIFY2(exported.ok, qPrintable(exported.error));
    QCOMPARE(exported.entryCount, 1);
    QCOMPARE(exported.imageCount, 1);

    const cardart::OperationResult imported =
        cardart::importPack(packPath, directory.filePath(u"target-images"_s));
    QVERIFY2(imported.ok, qPrintable(imported.error));
    QCOMPARE(imported.importedEntries.size(), 1);
    QCOMPARE(imported.importedEntries.first().cacheKey, second.cacheKey);
}

void TestCardArtArchive::orphanCleanupDeletesOnlyUnreferencedFiles() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.path());
    const QString indexed = cache.imagePath(u"Alpha"_s, u"https://example.test/a.png"_s, u"en"_s);
    const QString orphan = QDir(cache.imageRoot()).filePath(u"orphan.png"_s);
    QVERIFY(writeFile(indexed, kPng));
    QVERIFY(writeFile(orphan, kPng));
    const CardArtCacheEntry entry = cacheEntry(&cache, u"Alpha"_s, u"TST"_s, u"en"_s, indexed);
    cache.rememberSuccess(entry.cacheKey, entry.record);

    const cardart::OperationResult cleanup =
        cardart::removeUnreferencedFiles(cache.imageRoot(), cache.referencedImagePaths(), {}, true);
    QVERIFY2(cleanup.ok, qPrintable(cleanup.error));
    QCOMPARE(cleanup.imageCount, 1);
    QVERIFY(QFileInfo::exists(indexed));
    QVERIFY(!QFileInfo::exists(orphan));
}

void TestCardArtArchive::selectedCleanupPreservesSharedImage() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.path());
    const QString imagePath = cache.imagePath(u"Alpha"_s, u"https://example.test/a.png"_s, u"en"_s);
    QVERIFY(writeFile(imagePath, kPng));
    const CardArtCacheEntry one = cacheEntry(&cache, u"Alpha"_s, u"ONE"_s, u"en"_s, imagePath);
    const CardArtCacheEntry two = cacheEntry(&cache, u"Beta"_s, u"TWO"_s, u"en"_s, imagePath);
    cache.rememberSuccess(one.cacheKey, one.record);
    cache.rememberSuccess(two.cacheKey, two.record);

    const QList<CardArtCacheEntry> removed = cache.removeEntries(true, u"ONE"_s, u"en"_s);
    QCOMPARE(removed.size(), 1);
    const cardart::OperationResult cleanup = cardart::removeUnreferencedFiles(
        cache.imageRoot(), cache.referencedImagePaths(), {imagePath}, false);
    QVERIFY(cleanup.ok);
    QCOMPARE(cleanup.imageCount, 0);
    QVERIFY(QFileInfo::exists(imagePath));
}

void TestCardArtArchive::auditRepairsCachedFrontAndFindsMissingBack() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString databasePath = directory.filePath(u"cards.sqlite"_s);
    QVERIFY(writeFaceCatalog(
        databasePath,
        {QVariantMap{{u"name"_s, u"Delver of Secrets // Insectile Aberration"_s},
                     {u"layout"_s, u"transform"_s},
                     {u"typeLine"_s, u"Creature — Human Wizard // Creature — Human Insect"_s},
                     {u"setCode"_s, u"MID"_s},
                     {u"collectorNumber"_s, u"47"_s}}}));

    CardArtCache cache(directory.path());
    const QString imagePath =
        cache.imagePath(u"Delver of Secrets"_s, u"https://example.test/front.png"_s, u"en"_s);
    QVERIFY(writeFile(imagePath, kPng));
    CardRecord oldFront;
    oldFront.requestedName = u"Delver of Secrets // Insectile Aberration"_s;
    oldFront.name = oldFront.requestedName;
    oldFront.setCode = u"MID"_s;
    oldFront.collectorNumber = u"47"_s;
    oldFront.imageUrl = u"https://example.test/front.png"_s;
    oldFront.imagePath = imagePath;
    oldFront.imageLanguage = u"en"_s;
    oldFront.resolutionVersion = catalog_internal::kCardResolutionVersion;
    cache.rememberSuccess(
        cache.key(oldFront.requestedName, u"en"_s, oldFront.setCode, oldFront.collectorNumber),
        oldFront);

    const cardart::AuditResult result = cardart::auditDeckArt(
        databasePath, cache.imageRoot(), u"en"_s, true,
        {deckPrinting(oldFront.name, oldFront.setCode, oldFront.collectorNumber)}, cache.entries());
    QVERIFY2(result.ok, qPrintable(result.error));
    QCOMPARE(result.printingCount, 1);
    QCOMPARE(result.faceCount, 2);
    QCOMPARE(result.repairableEntryCount, 1);
    QCOMPARE(result.missingFaceCount, 1);
    QCOMPARE(result.repairedEntries.first().record.faceName, u"Delver of Secrets"_s);
    QCOMPARE(result.repairedEntries.first().record.imagePath, imagePath);
    QCOMPARE(result.missingRequests.first().toMap().value(u"name"_s).toString(),
             u"Insectile Aberration"_s);

    for (const CardArtCacheEntry &entry : result.repairedEntries)
        cache.rememberSuccess(entry.cacheKey, entry.record);
    const QString backImagePath =
        cache.imagePath(u"Insectile Aberration"_s, u"https://example.test/back.png"_s, u"en"_s);
    QVERIFY(writeFile(backImagePath, kPng));
    CardRecord back = oldFront;
    back.requestedName = u"Insectile Aberration"_s;
    back.faceName = back.requestedName;
    back.imageUrl = u"https://example.test/back.png"_s;
    back.imagePath = backImagePath;
    cache.rememberSuccess(cache.key(back.requestedName, u"en"_s, u"MID"_s, u"47"_s), back);
    const cardart::AuditResult repaired = cardart::auditDeckArt(
        databasePath, cache.imageRoot(), u"en"_s, true,
        {deckPrinting(oldFront.name, oldFront.setCode, oldFront.collectorNumber)}, cache.entries());
    QVERIFY2(repaired.ok, qPrintable(repaired.error));
    QVERIFY(!repaired.repairNeeded());
}

void TestCardArtArchive::auditIgnoresPrintingsThatWereNeverCached() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString databasePath = directory.filePath(u"cards.sqlite"_s);
    QVERIFY(writeFaceCatalog(
        databasePath, {QVariantMap{{u"name"_s, u"Delver of Secrets // Insectile Aberration"_s},
                                   {u"layout"_s, u"transform"_s},
                                   {u"typeLine"_s, u"Creature // Creature"_s},
                                   {u"setCode"_s, u"MID"_s},
                                   {u"collectorNumber"_s, u"47"_s}}}));
    CardArtCache cache(directory.path());

    const cardart::AuditResult result = cardart::auditDeckArt(
        databasePath, cache.imageRoot(), u"en"_s, true,
        {deckPrinting(u"Delver of Secrets"_s, u"MID"_s, u"47"_s)}, cache.entries());
    QVERIFY2(result.ok, qPrintable(result.error));
    QCOMPARE(result.printingCount, 0);
    QCOMPARE(result.faceCount, 0);
    QVERIFY(!result.repairNeeded());
}

void TestCardArtArchive::auditRepairsLegacyPrepareMappingWithoutDownload() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString databasePath = directory.filePath(u"cards.sqlite"_s);
    const QString cardName = u"Emeritus of Truce // Swords to Plowshares"_s;
    QVERIFY(
        writeFaceCatalog(databasePath, {QVariantMap{{u"name"_s, cardName},
                                                    {u"layout"_s, u"prepare"_s},
                                                    {u"typeLine"_s, u"Creature — Human Advisor"_s},
                                                    {u"setCode"_s, u"SOS"_s},
                                                    {u"collectorNumber"_s, u"13"_s}}}));

    CardArtCache cache(directory.path());
    const QString imagePath =
        cache.imagePath(cardName, u"https://example.test/prepare.jpg"_s, u"en"_s);
    QVERIFY(writeFile(imagePath, kPng));
    CardRecord prepare;
    prepare.requestedName = cardName;
    prepare.name = cardName;
    prepare.faceName = u"Swords to Plowshares"_s;
    prepare.setCode = u"SOS"_s;
    prepare.collectorNumber = u"13"_s;
    prepare.imageUrl = u"https://example.test/prepare.jpg"_s;
    prepare.imagePath = imagePath;
    prepare.imageLanguage = u"en"_s;
    prepare.resolutionVersion = catalog_internal::kCardResolutionVersion;
    cache.rememberSuccess(cache.key(cardName, u"en"_s, u"SOS"_s, u"13"_s), prepare);

    const cardart::AuditResult result =
        cardart::auditDeckArt(databasePath, cache.imageRoot(), u"en"_s, true,
                              {deckPrinting(cardName, u"SOS"_s, u"13"_s)}, cache.entries());
    QVERIFY2(result.ok, qPrintable(result.error));
    QCOMPARE(result.repairableEntryCount, 1);
    QCOMPARE(result.missingFaceCount, 0);
    QVERIFY(result.repairedEntries.first().record.faceName.isEmpty());
    QCOMPARE(result.repairedEntries.first().record.imagePath, imagePath);
}

void TestCardArtArchive::persistsFaceAuditState() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.path());
    QCOMPARE(cache.faceAuditVersion(), 0);
    QVERIFY(!cache.faceRepairNeeded());
    cache.setFaceAuditState(catalog_internal::kCardFaceAuditVersion, true);
    QVERIFY(cache.save());

    CardArtCache restored(directory.path());
    restored.load();
    QCOMPARE(restored.faceAuditVersion(), catalog_internal::kCardFaceAuditVersion);
    QVERIFY(restored.faceRepairNeeded());
}

QTEST_GUILESS_MAIN(TestCardArtArchive)
#include "cardartarchive_test.moc"
