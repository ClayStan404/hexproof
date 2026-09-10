// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/CardArtArchive.h"
#include "services/CardArtAudit.h"
#include "services/CardArtCache.h"
#include "services/CardCatalogCommon.h"

#include <QDataStream>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
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
    void importReusesDownloadedBytesForNewAliasesAndMetadata() const;
    void importReplacesCorruptExistingImage() const;
    void importPrefersRequestedLanguageAndMergesRules() const;
    void importAcceptsLegacyRulesAndRejectsInvalidMetadata() const;
    void selectedExportContainsOnlyRequestedGroup() const;
    void deckExportIncludesExactPrintingsLanguagesFacesAndSupportCards() const;
    void deckExportReportsUncachedAndCorruptFaces() const;
    void deckExportNeverBroadensAnEmptySelection() const;
    void deckExportWithoutCatalogIncludesKnownFaces() const;
    void deckExportPreservesRequestedFallbackIdentity() const;
    void deckExportNormalizesLegacySingleImageFaceMetadata() const;
    void deckExportDoesNotConfusePrepareCharacteristicsWithCards() const;
    void deckExportNameOnlyFindsStandaloneDoubleFaces() const;
    void exportSkipsInvalidAndDuplicateMappingMetadata() const;
    void deckExportLargeCubeDeduplicatesImages() const;
    void importRejectsTamperedImagePayload() const;
    void orphanCleanupDeletesOnlyUnreferencedFiles() const;
    void selectedCleanupPreservesSharedImage() const;
    void auditRepairsCachedFrontAndFindsMissingBack() const;
    void auditIgnoresPrintingsThatWereNeverCached() const;
    void auditRepairsLegacyPrepareMappingWithoutDownload() const;
    void supportArtAuditAndPackRoundTripUsePreferredLanguage() const;
    void persistsFaceAuditState() const;
};

void TestCardArtArchive::deckExportIncludesExactPrintingsLanguagesFacesAndSupportCards() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.filePath(u"source"_s));
    const QString imagePath =
        cache.imagePath(u"shared"_s, u"https://example.test/a.png"_s, u"en"_s);
    QVERIFY(writeFile(imagePath, kPng));
    const QString database = directory.filePath(u"cards.sqlite"_s);
    const QVariantList catalog{
        QVariantMap{{u"name"_s, u"Front // Reverse"_s},
                    {u"layout"_s, u"transform"_s},
                    {u"typeLine"_s, u"Creature // Creature"_s},
                    {u"setCode"_s, u"DFC"_s},
                    {u"collectorNumber"_s, u"1"_s}},
        QVariantMap{{u"name"_s, u"Angel"_s},
                    {u"layout"_s, u"token"_s},
                    {u"typeLine"_s, u"Token Creature — Angel"_s},
                    {u"setCode"_s, u"TOK"_s},
                    {u"collectorNumber"_s, u"1"_s}},
        QVariantMap{{u"name"_s, u"Teferi Emblem"_s},
                    {u"layout"_s, u"emblem"_s},
                    {u"typeLine"_s, u"Emblem — Teferi"_s},
                    {u"setCode"_s, u"EMB"_s},
                    {u"collectorNumber"_s, u"1"_s}},
    };
    QVERIFY(writeFaceCatalog(database, catalog));
    QSet<QString> expected;
    for (const QString &language : {u"en"_s, u"zh"_s}) {
        for (const QString &face : {u"Front"_s, u"Reverse"_s}) {
            CardArtCacheEntry entry = cacheEntry(&cache, face, u"DFC"_s, language, imagePath);
            entry.record.name = u"Front // Reverse"_s;
            entry.record.faceName = face;
            cache.rememberSuccess(entry.cacheKey, entry.record);
            expected.insert(entry.cacheKey);
        }
    }
    CardArtCacheEntry angel = cacheEntry(&cache, u"Angel"_s, u"TOK"_s, u"zh"_s, imagePath);
    angel.record.localizedName = QString::fromUtf8("天使");
    angel.record.oracleText = QString::fromUtf8("飞行");
    angel.record.oracleTextLanguage = u"zh"_s;
    angel.record.localizedRulesChecked = true;
    cache.rememberSuccess(angel.cacheKey, angel.record);
    expected.insert(angel.cacheKey);
    const CardArtCacheEntry emblem =
        cacheEntry(&cache, u"Teferi Emblem"_s, u"EMB"_s, u"en"_s, imagePath);
    cache.rememberSuccess(emblem.cacheKey, emblem.record);
    expected.insert(emblem.cacheKey);
    for (const auto &entry : {
             cacheEntry(&cache, u"Front"_s, u"OTHER"_s, u"en"_s, imagePath),
             cacheEntry(&cache, u"Unrelated"_s, u"EMB"_s, u"en"_s, imagePath),
         }) {
        CardArtCacheEntry unrelated = entry;
        if (unrelated.record.name == u"Unrelated"_s) {
            unrelated.record.collectorNumber = u"2"_s;
            unrelated.cacheKey = cache.key(unrelated.record.name, u"en"_s, u"EMB"_s, u"2"_s);
        }
        cache.rememberSuccess(unrelated.cacheKey, unrelated.record);
    }
    QVariantMap token = deckPrinting(u"Angel"_s, u"TOK"_s, u"1"_s);
    token.insert(u"kind"_s, u"token"_s);
    QVariantMap savedEmblem = deckPrinting(u"Teferi Emblem"_s, u"EMB"_s, u"1"_s);
    savedEmblem.insert(u"kind"_s, u"emblem"_s);
    const QVariantList requests{deckPrinting(u"Front // Reverse"_s, u"dfc"_s, u"1"_s),
                                deckPrinting(u"Front"_s, u"DFC"_s, u"1"_s), token, savedEmblem};
    const QString archive = directory.filePath(u"deck.hexproof-artpack"_s);
    const auto result =
        cardart::exportDeckPack(archive, cache.imageRoot(), database, requests, cache.entries());
    QVERIFY2(result.operation.ok, qPrintable(result.operation.error));
    QCOMPARE(result.requestedPrintingCount, 3);
    QCOMPARE(result.requestedFaceCount, 4);
    QCOMPARE(result.missingFaceCount, 0);
    QCOMPARE(result.missingPrintingCount, 0);
    QVERIFY(result.faceCoverageVerified);
    QCOMPARE(result.operation.exportedEntryKeys, expected);
    QCOMPARE(result.operation.entryCount, 6);
    QCOMPARE(result.operation.imageCount, 1);
    CardArtCache destination(directory.filePath(u"destination"_s));
    const auto imported = cardart::importPack(archive, destination.imageRoot());
    QVERIFY2(imported.ok, qPrintable(imported.error));
    QSet<QString> actual;
    for (const CardArtCacheEntry &entry : imported.importedEntries) {
        actual.insert(entry.cacheKey);
        if (entry.cacheKey == angel.cacheKey)
            QCOMPARE(entry.record.oracleText, angel.record.oracleText);
    }
    QCOMPARE(actual, expected);
}

void TestCardArtArchive::deckExportReportsUncachedAndCorruptFaces() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.filePath(u"source"_s));
    const QString imagePath = cache.imagePath(u"front"_s, u"https://example.test/a.png"_s, u"en"_s);
    const QString corruptPath =
        cache.imagePath(u"corrupt"_s, u"https://example.test/b.png"_s, u"en"_s);
    QVERIFY(writeFile(imagePath, kPng));
    QVERIFY(writeFile(corruptPath, QByteArrayLiteral("not an image")));
    const QString database = directory.filePath(u"cards.sqlite"_s);
    QVariantList catalog;
    QVariantList requests;
    for (const QString &name : {u"Front // Reverse"_s, u"Uncached"_s, u"Corrupt"_s, u"Healthy"_s}) {
        const QString setCode = name.left(3).toUpper();
        catalog.append(
            QVariantMap{{u"name"_s, name},
                        {u"layout"_s, name.contains(u" // "_s) ? u"transform"_s : u"normal"_s},
                        {u"typeLine"_s, u"Creature"_s},
                        {u"setCode"_s, setCode},
                        {u"collectorNumber"_s, u"1"_s}});
        requests.append(deckPrinting(name, setCode, u"1"_s));
    }
    QVERIFY(writeFaceCatalog(database, catalog));
    auto front = cacheEntry(&cache, u"Front // Reverse"_s, u"FRO"_s, u"en"_s, imagePath);
    cache.rememberSuccess(front.cacheKey, front.record);
    // An obsolete reverse alias still points at the unmarked front image.
    auto falseReverse = front;
    falseReverse.record.requestedName = u"Reverse"_s;
    falseReverse.cacheKey = cache.key(u"Reverse"_s, u"en"_s, u"FRO"_s, u"1"_s);
    cache.rememberSuccess(falseReverse.cacheKey, falseReverse.record);
    for (const auto &entry : {
             cacheEntry(&cache, u"Corrupt"_s, u"COR"_s, u"en"_s, corruptPath),
             cacheEntry(&cache, u"Healthy"_s, u"HEA"_s, u"en"_s, imagePath),
         })
        cache.rememberSuccess(entry.cacheKey, entry.record);
    const auto result =
        cardart::exportDeckPack(directory.filePath(u"partial.hexproof-artpack"_s),
                                cache.imageRoot(), database, requests, cache.entries());
    QVERIFY2(result.operation.ok, qPrintable(result.operation.error));
    QCOMPARE(result.requestedPrintingCount, 4);
    QCOMPARE(result.requestedFaceCount, 5);
    QCOMPARE(result.missingPrintingCount, 2);
    QCOMPARE(result.missingFaceCount, 3);
    QCOMPARE(result.operation.skippedCount, 2);
    QCOMPARE(result.operation.entryCount, 2);
    QVERIFY(!result.operation.exportedEntryKeys.contains(falseReverse.cacheKey));
    QVERIFY(result.faceCoverageVerified);
}

void TestCardArtArchive::deckExportNeverBroadensAnEmptySelection() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.filePath(u"source"_s));
    const QString imagePath =
        cache.imagePath(u"Healthy"_s, u"https://example.test/a.png"_s, u"en"_s);
    QVERIFY(writeFile(imagePath, kPng));
    const auto entry = cacheEntry(&cache, u"Healthy"_s, u"SET"_s, u"en"_s, imagePath);
    cache.rememberSuccess(entry.cacheKey, entry.record);
    const QString destination = directory.filePath(u"existing.hexproof-artpack"_s);
    const QByteArray original("preserve existing destination");
    QVERIFY(writeFile(destination, original));
    for (const QVariantList &cards : {
             QVariantList{},
             QVariantList{QVariantMap{}},
             QVariantList{deckPrinting(u"Unknown"_s, u"SET"_s, u"2"_s)},
             QVariantList{deckPrinting(u"Healthy"_s, u"OTHER"_s, u"1"_s)},
         }) {
        const auto result =
            cardart::exportDeckPack(destination, cache.imageRoot(), {}, cards, cache.entries());
        QVERIFY(!result.operation.ok);
        QCOMPARE(result.operation.entryCount, 0);
        QFile file(destination);
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(), original);
    }
}

void TestCardArtArchive::deckExportWithoutCatalogIncludesKnownFaces() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.filePath(u"source"_s));
    const QString imagePath = cache.imagePath(u"front"_s, u"https://example.test/a.png"_s, u"en"_s);
    QVERIFY(writeFile(imagePath, kPng));
    for (const QString &face : {u"Front"_s, u"Reverse"_s}) {
        auto entry = cacheEntry(&cache, face, u"DFC"_s, u"en"_s, imagePath);
        entry.record.name = u"Front // Reverse"_s;
        entry.record.faceName = face;
        cache.rememberSuccess(entry.cacheKey, entry.record);
    }
    const auto result = cardart::exportDeckPack(
        directory.filePath(u"without-database.hexproof-artpack"_s), cache.imageRoot(), {},
        {deckPrinting(u"Front // Reverse"_s, {}, {})}, cache.entries());
    QVERIFY2(result.operation.ok, qPrintable(result.operation.error));
    QCOMPARE(result.operation.entryCount, 2);
    QCOMPARE(result.requestedFaceCount, 2);
    QCOMPARE(result.missingFaceCount, 0);
    QVERIFY(!result.faceCoverageVerified);
    QVERIFY(!result.summary().value(u"faceCoverageVerified"_s).toBool());
}

void TestCardArtArchive::deckExportLargeCubeDeduplicatesImages() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.filePath(u"source"_s));
    const QString imagePath =
        cache.imagePath(u"shared"_s, u"https://example.test/a.png"_s, u"en"_s);
    QVERIFY(writeFile(imagePath, kPng));
    QVariantList requests;
    constexpr int cubeSize = 3'000;
    for (int i = 0; i < cubeSize; ++i) {
        const QString name = u"Cube card %1"_s.arg(i);
        const QString number = QString::number(i) + QChar(0x2020);
        auto entry = cacheEntry(&cache, name, u"CUBE"_s, u"en"_s, imagePath);
        entry.record.collectorNumber = number;
        entry.cacheKey = cache.key(name, u"en"_s, u"CUBE"_s, number);
        cache.rememberSuccess(entry.cacheKey, entry.record);
        requests.append(deckPrinting(name, u"CUBE"_s, number));
        requests.append(deckPrinting(name, u"cube"_s, number));
    }
    const QString archive = directory.filePath(u"cube.hexproof-artpack"_s);
    const auto result =
        cardart::exportDeckPack(archive, cache.imageRoot(), {}, requests, cache.entries());
    QVERIFY2(result.operation.ok, qPrintable(result.operation.error));
    QCOMPARE(result.requestedPrintingCount, cubeSize);
    QCOMPARE(result.operation.entryCount, cubeSize);
    QCOMPARE(result.operation.imageCount, 1);
    QCOMPARE(result.operation.bytes, kPng.size());
    QCOMPARE(result.missingFaceCount, 0);
    const auto preview = cardart::inspectPack(archive);
    QVERIFY(preview.value(u"ok"_s).toBool());
    QCOMPARE(preview.value(u"entryCount"_s).toInt(), cubeSize);
}

void TestCardArtArchive::deckExportPreservesRequestedFallbackIdentity() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.filePath(u"source"_s));
    const QString imagePath =
        cache.imagePath(u"Island"_s, u"https://example.test/a.png"_s, u"en"_s);
    QVERIFY(writeFile(imagePath, kPng));
    auto entry = cacheEntry(&cache, u"Island"_s, u"REQUEST"_s, u"zh"_s, imagePath);
    entry.record.setCode = u"FALLBACK"_s;
    entry.record.collectorNumber = u"7"_s;
    entry.record.imageLanguage = u"en"_s;
    entry.record.usesSubstituteArt = true;
    cache.rememberSuccess(entry.cacheKey, entry.record);
    const QString archive = directory.filePath(u"fallback.hexproof-artpack"_s);
    const auto exported =
        cardart::exportDeckPack(archive, cache.imageRoot(), {},
                                {deckPrinting(u"Island"_s, u"REQUEST"_s, u"1"_s)}, cache.entries());
    QVERIFY2(exported.operation.ok, qPrintable(exported.operation.error));
    QCOMPARE(exported.operation.entryCount, 1);
    CardArtCache destination(directory.filePath(u"destination"_s));
    const auto imported = cardart::importPack(archive, destination.imageRoot());
    QVERIFY2(imported.ok, qPrintable(imported.error));
    QCOMPARE(imported.importedEntries.first().cacheKey, entry.cacheKey);
    QCOMPARE(imported.importedEntries.first().record.imageLanguage, u"en"_s);
    QCOMPARE(imported.importedEntries.first().record.setCode, u"REQUEST"_s);
    const auto unrelated = cardart::exportDeckPack(
        directory.filePath(u"unrelated.hexproof-artpack"_s), cache.imageRoot(), {},
        {deckPrinting(u"Island"_s, u"FALLBACK"_s, u"7"_s)}, cache.entries());
    QVERIFY(!unrelated.operation.ok);
}

void TestCardArtArchive::deckExportNormalizesLegacySingleImageFaceMetadata() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.filePath(u"source"_s));
    const QString name = u"Emeritus of Truce // Swords to Plowshares"_s;
    const QString imagePath = cache.imagePath(name, u"https://example.test/prepare.png"_s, u"en"_s);
    QVERIFY(writeFile(imagePath, kPng));
    const QString database = directory.filePath(u"cards.sqlite"_s);
    QVERIFY(writeFaceCatalog(database, {
                                           QVariantMap{{u"name"_s, name},
                                                       {u"layout"_s, u"prepare"_s},
                                                       {u"typeLine"_s, u"Creature // Instant"_s},
                                                       {u"setCode"_s, u"SOS"_s},
                                                       {u"collectorNumber"_s, u"1"_s}},
                                       }));
    auto entry = cacheEntry(&cache, name, u"SOS"_s, u"en"_s, imagePath);
    entry.record.faceName = u"Swords to Plowshares"_s;
    cache.rememberSuccess(entry.cacheKey, entry.record);
    const CardRequest request{name, u"SOS"_s, u"1"_s, u"en"_s};
    QVERIFY(!cache.resolvedPrinting(request).valid());
    const QString archive = directory.filePath(u"prepare.hexproof-artpack"_s);
    const auto exported =
        cardart::exportDeckPack(archive, cache.imageRoot(), database,
                                {deckPrinting(name, u"SOS"_s, u"1"_s)}, cache.entries());
    QVERIFY2(exported.operation.ok, qPrintable(exported.operation.error));
    QCOMPARE(exported.requestedFaceCount, 1);
    QCOMPARE(exported.missingFaceCount, 0);
    QVERIFY(exported.faceCoverageVerified);
    CardArtCache destination(directory.filePath(u"destination"_s));
    const auto imported = cardart::importPack(archive, destination.imageRoot());
    QVERIFY2(imported.ok, qPrintable(imported.error));
    for (const auto &incoming : imported.importedEntries)
        destination.rememberSuccess(incoming.cacheKey, incoming.record);
    QVERIFY(destination.resolvedPrinting(request).valid());
    QVERIFY(destination.resolvedPrinting(request).faceName.isEmpty());
    QCOMPARE(cache.exactRecord(entry.cacheKey).faceName, u"Swords to Plowshares"_s);
}

void TestCardArtArchive::deckExportDoesNotConfusePrepareCharacteristicsWithCards() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.filePath(u"source"_s));
    const QString prepareName = u"Emeritus of Truce // Swords to Plowshares"_s;
    const QString imagePath =
        cache.imagePath(prepareName, u"https://example.test/prepare.png"_s, u"en"_s);
    QVERIFY(writeFile(imagePath, kPng));
    const QString database = directory.filePath(u"cards.sqlite"_s);
    // Deliberately insert the characteristic match first: the repository must
    // prefer the exact playable-card name regardless of database row order.
    QVERIFY(writeFaceCatalog(database, {
                                           QVariantMap{{u"name"_s, prepareName},
                                                       {u"layout"_s, u"prepare"_s},
                                                       {u"typeLine"_s, u"Creature // Instant"_s},
                                                       {u"setCode"_s, u"SOS"_s},
                                                       {u"collectorNumber"_s, u"1"_s}},
                                           QVariantMap{{u"name"_s, u"Swords to Plowshares"_s},
                                                       {u"layout"_s, u"normal"_s},
                                                       {u"typeLine"_s, u"Instant"_s},
                                                       {u"setCode"_s, u"LEA"_s},
                                                       {u"collectorNumber"_s, u"1"_s}},
                                       }));
    auto prepare = cacheEntry(&cache, prepareName, u"SOS"_s, u"en"_s, imagePath);
    prepare.record.faceName = u"Swords to Plowshares"_s;
    cache.rememberSuccess(prepare.cacheKey, prepare.record);
    const QVariantList requests{deckPrinting(u"Swords to Plowshares"_s, {}, {})};
    const QString archive = directory.filePath(u"swords.hexproof-artpack"_s);
    for (const QString &catalog : {database, QString{}}) {
        const auto missing =
            cardart::exportDeckPack(archive, cache.imageRoot(), catalog, requests, cache.entries());
        QVERIFY(!missing.operation.ok);
        QCOMPARE(missing.requestedFaceCount, 1);
        QCOMPARE(missing.missingFaceCount, 1);
        QCOMPARE(missing.missingPrintingCount, 1);
        QVERIFY(!QFileInfo::exists(archive));
    }
    const auto swords = cacheEntry(&cache, u"Swords to Plowshares"_s, u"LEA"_s, u"en"_s, imagePath);
    cache.rememberSuccess(swords.cacheKey, swords.record);
    const auto exported =
        cardart::exportDeckPack(archive, cache.imageRoot(), database, requests, cache.entries());
    QVERIFY2(exported.operation.ok, qPrintable(exported.operation.error));
    QCOMPARE(exported.operation.exportedEntryKeys, QSet<QString>{swords.cacheKey});
    QCOMPARE(exported.missingFaceCount, 0);
    QVERIFY(exported.faceCoverageVerified);
}

void TestCardArtArchive::deckExportNameOnlyFindsStandaloneDoubleFaces() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.filePath(u"source"_s));
    const QString imagePath =
        cache.imagePath(u"Front"_s, u"https://example.test/front.png"_s, u"en"_s);
    QVERIFY(writeFile(imagePath, kPng));
    const QString database = directory.filePath(u"cards.sqlite"_s);
    QVERIFY(writeFaceCatalog(database, {
                                           QVariantMap{{u"name"_s, u"Front // Reverse"_s},
                                                       {u"layout"_s, u"transform"_s},
                                                       {u"typeLine"_s, u"Creature // Creature"_s},
                                                       {u"setCode"_s, u"DFC"_s},
                                                       {u"collectorNumber"_s, u"1"_s}},
                                       }));
    for (const QString &face : {u"Front"_s, u"Reverse"_s}) {
        auto entry = cacheEntry(&cache, face, u"DFC"_s, u"en"_s, imagePath);
        entry.record.faceName = face;
        cache.rememberSuccess(entry.cacheKey, entry.record);
    }
    const QString archive = directory.filePath(u"double-faced.hexproof-artpack"_s);
    const auto exported = cardart::exportDeckPack(
        archive, cache.imageRoot(), database, {deckPrinting(u"Front"_s, {}, {})}, cache.entries());
    QVERIFY2(exported.operation.ok, qPrintable(exported.operation.error));
    QCOMPARE(exported.operation.entryCount, 2);
    QCOMPARE(exported.missingFaceCount, 0);
    QVERIFY(exported.faceCoverageVerified);
    CardArtCache destination(directory.filePath(u"destination"_s));
    const auto imported = cardart::importPack(archive, destination.imageRoot());
    QVERIFY2(imported.ok, qPrintable(imported.error));
    for (const auto &entry : imported.importedEntries)
        destination.rememberSuccess(entry.cacheKey, entry.record);
    for (const QString &face : {u"Front"_s, u"Reverse"_s})
        QVERIFY(destination.resolvedPrinting(CardRequest{face, u"DFC"_s, u"1"_s, u"en"_s}).valid());
}

void TestCardArtArchive::exportSkipsInvalidAndDuplicateMappingMetadata() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.filePath(u"source"_s));
    const QString validPath =
        cache.imagePath(u"Healthy"_s, u"https://example.test/valid.png"_s, u"en"_s);
    const QString invalidMetadataPath =
        cache.imagePath(u"Invalid"_s, u"https://example.test/invalid.png"_s, u"en"_s);
    QVERIFY(writeFile(validPath, kPng));
    QImage other(2, 2, QImage::Format_ARGB32);
    other.fill(Qt::red);
    QVERIFY(other.save(invalidMetadataPath, "PNG"));
    const auto valid = cacheEntry(&cache, u"Healthy"_s, u"ONE"_s, u"en"_s, validPath);
    auto invalid = cacheEntry(&cache, u"Invalid"_s, u"TWO"_s, u"en"_s, invalidMetadataPath);
    invalid.record.imageLanguage.clear();
    auto duplicate = valid;
    duplicate.cacheKey = cache.key(u"Other alias"_s, u"en"_s, u"ONE"_s, u"1"_s);
    auto invalidRules =
        cacheEntry(&cache, u"Invalid rules"_s, u"THREE"_s, u"en"_s, invalidMetadataPath);
    invalidRules.record.oracleText = u"Rules without a resolved language"_s;
    const QString archive = directory.filePath(u"metadata.hexproof-artpack"_s);
    const auto exported = cardart::exportPack(
        archive, cache.imageRoot(), {valid, invalid, duplicate, invalidRules}, false, {}, {});
    QVERIFY2(exported.ok, qPrintable(exported.error));
    QCOMPARE(exported.entryCount, 1);
    QCOMPARE(exported.imageCount, 1);
    QCOMPARE(exported.bytes, kPng.size());
    QCOMPARE(exported.skippedCount, 3);
    CardArtCache destination(directory.filePath(u"destination"_s));
    const auto imported = cardart::importPack(archive, destination.imageRoot());
    QVERIFY2(imported.ok, qPrintable(imported.error));
    QCOMPARE(imported.entryCount, 1);
    QCOMPARE(imported.importedEntries.first().cacheKey, valid.cacheKey);
}

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

void TestCardArtArchive::importReusesDownloadedBytesForNewAliasesAndMetadata() const
{
    QTemporaryDir directory;
    CardArtCache cache(directory.path());
    const QString imagePath = cache.imagePath(u"Alpha"_s, u"https://example.test/a.png"_s, u"en"_s);
    QVERIFY(writeFile(imagePath, kPng));
    const auto alpha = cacheEntry(&cache, u"Alpha"_s, u"ONE"_s, u"en"_s, imagePath);
    const auto beta = cacheEntry(&cache, u"Beta"_s, u"TWO"_s, u"en"_s, imagePath);
    const QString packPath = directory.filePath(u"shared.hexproof-artpack"_s);
    QVERIFY(cardart::exportPack(packPath, cache.imageRoot(), {alpha, beta}, false, {}, {}).ok);
    auto imported = cardart::importPack(packPath, cache.imageRoot(), {alpha});
    QVERIFY2(imported.ok, qPrintable(imported.error));
    QCOMPARE(imported.importedEntries.size(), 2);
    for (const auto &entry : imported.importedEntries)
        QCOMPARE(entry.record.imagePath, imagePath);
    QCOMPARE(cardart::inventory(cache.imageRoot(), {alpha}).value(u"imageCount"_s).toInt(), 1);

    auto oldAlpha = alpha;
    oldAlpha.record.resolutionVersion = 0;
    imported = cardart::importPack(packPath, cache.imageRoot(), {oldAlpha});
    QVERIFY2(imported.ok, qPrintable(imported.error));
    for (const auto &entry : imported.importedEntries) {
        QCOMPARE(entry.record.imagePath, imagePath);
        QCOMPARE(entry.record.resolutionVersion, catalog_internal::kCardResolutionVersion);
    }
    QCOMPARE(cardart::inventory(cache.imageRoot(), {alpha}).value(u"imageCount"_s).toInt(), 1);
}

void TestCardArtArchive::importReplacesCorruptExistingImage() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.path());
    const QString path = cache.imagePath(u"Alpha"_s, u"https://example.test/a.png"_s, u"en"_s);
    QVERIFY(writeFile(path, kPng));
    const CardArtCacheEntry entry = cacheEntry(&cache, u"Alpha"_s, u"ONE"_s, u"en"_s, path);
    const QString packPath = directory.filePath(u"good.hexproof-artpack"_s);
    QVERIFY(cardart::exportPack(packPath, cache.imageRoot(), {entry}, false, {}, {}).ok);
    QVERIFY(writeFile(path, QByteArrayLiteral("not an image")));
    const auto summary = cardart::inspectPack(packPath, {entry}, cache.imageRoot());
    QCOMPARE(summary.value(u"existingEntryCount"_s).toInt(), 0);
    QCOMPARE(summary.value(u"newEntryCount"_s).toInt(), 1);
    const auto imported = cardart::importPack(packPath, cache.imageRoot(), {entry});
    QVERIFY2(imported.ok, qPrintable(imported.error));
    QCOMPARE(imported.importedEntries.size(), 1);
    QFile restored(imported.importedEntries.first().record.imagePath);
    QVERIFY(restored.open(QIODevice::ReadOnly));
    QCOMPARE(restored.readAll(), kPng);
}

void TestCardArtArchive::importPrefersRequestedLanguageAndMergesRules() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.path());
    const QString englishPath =
        cache.imagePath(u"Emblem"_s, u"https://cards.scryfall.io/emblem.png"_s, u"en"_s);
    const QString chinesePath =
        cache.imagePath(u"Emblem"_s, u"https://mtgch.com/emblem.png"_s, u"zh"_s);
    QVERIFY(writeFile(englishPath, kPng));
    QVERIFY(writeFile(chinesePath, kPng));
    CardArtCacheEntry english = cacheEntry(&cache, u"Emblem"_s, u"TST"_s, u"zh"_s, englishPath);
    english.record.imageLanguage = u"en"_s;
    english.record.oracleText = u"由你操控的生物具有飞行。"_s;
    english.record.oracleTextLanguage = u"zh"_s;
    CardArtCacheEntry chinese = english;
    chinese.record.imagePath = chinesePath;
    chinese.record.imageUrl = u"https://mtgch.com/emblem.png"_s;
    chinese.record.imageLanguage = u"zh"_s;
    chinese.record.oracleText.clear();
    chinese.record.oracleTextLanguage.clear();
    const QString chinesePack = directory.filePath(u"chinese.hexproof-artpack"_s);
    QVERIFY(cardart::exportPack(chinesePack, cache.imageRoot(), {chinese}, false, {}, {}).ok);
    const QVariantMap summary = cardart::inspectPack(chinesePack, {english}, cache.imageRoot());
    QCOMPARE(summary.value(u"newEntryCount"_s).toInt(), 1);
    auto imported = cardart::importPack(chinesePack, cache.imageRoot(), {english});
    QVERIFY2(imported.ok, qPrintable(imported.error));
    QCOMPARE(imported.importedEntries.size(), 1);
    const CardRecord upgraded = imported.importedEntries.first().record;
    QCOMPARE(upgraded.imageLanguage, u"zh"_s);
    QCOMPARE(upgraded.imageUrl, chinese.record.imageUrl);
    QCOMPARE(upgraded.oracleText, english.record.oracleText);
    QCOMPARE(upgraded.oracleTextLanguage, u"zh"_s);
    QVERIFY(!imported.retainedEntryKeys.contains(english.cacheKey));

    const QString englishPack = directory.filePath(u"english.hexproof-artpack"_s);
    QVERIFY(cardart::exportPack(englishPack, cache.imageRoot(), {english}, false, {}, {}).ok);
    imported = cardart::importPack(englishPack, cache.imageRoot(), {chinese});
    QVERIFY2(imported.ok, qPrintable(imported.error));
    const CardRecord merged = imported.importedEntries.first().record;
    QCOMPARE(merged.imageLanguage, u"zh"_s);
    QCOMPARE(merged.imagePath, chinesePath);
    QCOMPARE(merged.imageUrl, chinese.record.imageUrl);
    QCOMPARE(merged.oracleText, english.record.oracleText);
    QCOMPARE(merged.oracleTextLanguage, u"zh"_s);
    // The image is retained, but the manager must still persist new rules.
    QVERIFY(!imported.retainedEntryKeys.contains(chinese.cacheKey));
    const CardArtCacheEntry complete{chinese.cacheKey, merged};
    imported = cardart::importPack(englishPack, cache.imageRoot(), {complete});
    QVERIFY(imported.ok);
    QVERIFY(imported.retainedEntryKeys.contains(chinese.cacheKey));
    QCOMPARE(imported.importedEntries.first().record.imageLanguage, u"zh"_s);
}

void TestCardArtArchive::importAcceptsLegacyRulesAndRejectsInvalidMetadata() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    CardArtCache cache(directory.path());
    const QString imagePath =
        cache.imagePath(u"Emblem"_s, u"https://cards.scryfall.io/emblem.png"_s, u"en"_s);
    QVERIFY(writeFile(imagePath, kPng));
    CardArtCacheEntry entry = cacheEntry(&cache, u"Emblem"_s, u"TST"_s, u"zh"_s, imagePath);
    entry.record.imageLanguage = u"en"_s;
    entry.record.oracleText = u"由你操控的生物具有飞行。"_s;
    entry.record.oracleTextLanguage = u"zh"_s;
    entry.record.localizedRulesChecked = true;
    const QString packPath = directory.filePath(u"rules.hexproof-artpack"_s);
    QVERIFY(cardart::exportPack(packPath, cache.imageRoot(), {entry}, false, {}, {}).ok);
    QFile pack(packPath);
    QVERIFY(pack.open(QIODevice::ReadOnly));
    const QByteArray magic = pack.read(8);
    QDataStream input(&pack);
    input.setByteOrder(QDataStream::BigEndian);
    quint32 manifestLength = 0;
    input >> manifestLength;
    const QJsonObject original = QJsonDocument::fromJson(pack.read(manifestLength)).object();
    const QByteArray payload = pack.readAll();
    pack.close();
    const auto rewriteEntry = [&](QJsonObject record) {
        QJsonObject manifest = original;
        manifest.insert(u"entries"_s, QJsonArray{record});
        const QByteArray bytes = QJsonDocument(manifest).toJson(QJsonDocument::Compact);
        if (!pack.open(QIODevice::WriteOnly | QIODevice::Truncate))
            return false;
        if (pack.write(magic) != magic.size())
            return false;
        QDataStream output(&pack);
        output.setByteOrder(QDataStream::BigEndian);
        output << static_cast<quint32>(bytes.size());
        const bool ok = pack.write(bytes) == bytes.size() && pack.write(payload) == payload.size();
        pack.close();
        return ok;
    };
    const QJsonObject originalEntry = original.value(u"entries"_s).toArray().first().toObject();
    QJsonObject legacy = originalEntry;
    legacy.remove(u"oracleText"_s);
    legacy.remove(u"oracleTextLanguage"_s);
    legacy.remove(u"localizedRulesChecked"_s);
    QVERIFY(rewriteEntry(legacy));
    auto imported = cardart::importPack(packPath, cache.imageRoot());
    QVERIFY2(imported.ok, qPrintable(imported.error));
    QCOMPARE(imported.importedEntries.first().record.imageLanguage, u"en"_s);
    QVERIFY(imported.importedEntries.first().record.oracleTextLanguage.isEmpty());

    const QList<QPair<QString, QJsonValue>> invalid{
        {u"oracleText"_s, 42},
        {u"oracleText"_s, QString(16'385, QLatin1Char('x'))},
        {u"oracleText"_s, QString(QChar::Null)},
        {u"oracleTextLanguage"_s, u"fr"_s},
        {u"oracleTextLanguage"_s, true},
        {u"oracleTextLanguage"_s, QString{}},
        {u"localizedRulesChecked"_s, u"true"_s},
    };
    for (const auto &[key, value] : invalid) {
        QJsonObject malformed = originalEntry;
        malformed.insert(key, value);
        QVERIFY(rewriteEntry(malformed));
        QVERIFY(!cardart::inspectPack(packPath).value(u"ok"_s).toBool());
        QVERIFY(!cardart::importPack(packPath, cache.imageRoot()).ok);
    }
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
    // Already-cached entries must not bypass validation of the archive payload.
    QVERIFY(!cardart::importPack(packPath, source.imageRoot(), source.entries()).ok);
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

void TestCardArtArchive::supportArtAuditAndPackRoundTripUsePreferredLanguage() const
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString databasePath = directory.filePath(u"cards.sqlite"_s);
    QVERIFY(writeFaceCatalog(databasePath,
                             {QVariantMap{{u"name"_s, u"Teferi Emblem"_s},
                                          {u"layout"_s, u"emblem"_s},
                                          {u"typeLine"_s, u"Emblem — Teferi"_s},
                                          {u"setCode"_s, u"TDOM"_s},
                                          {u"collectorNumber"_s, u"16"_s}},
                              QVariantMap{{u"name"_s, u"Goblin // Soldier"_s},
                                          {u"layout"_s, u"double_faced_token"_s},
                                          {u"typeLine"_s, u"Token Creature // Token Creature"_s},
                                          {u"setCode"_s, u"TTST"_s},
                                          {u"collectorNumber"_s, u"1"_s}}}));
    QVariantMap emblem = deckPrinting(u"Teferi Emblem"_s, u"TDOM"_s, u"16"_s);
    emblem.insert(u"kind"_s, u"emblem"_s);
    QVariantMap token = deckPrinting(u"Goblin // Soldier"_s, u"TTST"_s, u"1"_s);
    token.insert(u"kind"_s, u"token"_s);
    const QVariantList requests{emblem, token};
    CardArtCache cache(directory.filePath(u"source"_s));
    const auto missing = cardart::auditDeckArt(databasePath, cache.imageRoot(), u"zh"_s, true,
                                               requests, cache.entries());
    QVERIFY2(missing.ok, qPrintable(missing.error));
    QCOMPARE(missing.printingCount, 2);
    QCOMPARE(missing.missingFaceCount, 3);
    QCOMPARE(missing.missingRequests.first().toMap().value(u"kind"_s).toString(), u"emblem"_s);
    QCOMPARE(missing.missingRequests.last().toMap().value(u"kind"_s).toString(), u"token"_s);
    for (const QVariant &request : missing.missingRequests) {
        const QVariantMap map = request.toMap();
        const QString name = map.value(u"name"_s).toString();
        const QString url = u"https://images.test/"_s + name + u".png"_s;
        const QString path = cache.imagePath(name, url, u"zh"_s);
        QVERIFY(writeFile(path, kPng));
        auto entry = cacheEntry(&cache, name, map.value(u"setCode"_s).toString(), u"zh"_s, path);
        entry.record.collectorNumber = map.value(u"collectorNumber"_s).toString();
        entry.record.oracleText = u"测试规则文字。"_s;
        entry.record.oracleTextLanguage = u"zh"_s;
        entry.record.localizedRulesChecked = true;
        entry.record.faceName = map.value(u"kind"_s).toString() == u"token"_s ? name : QString{};
        entry.cacheKey =
            cache.key(name, u"zh"_s, entry.record.setCode, entry.record.collectorNumber);
        cache.rememberSuccess(entry.cacheKey, entry.record);
    }
    const auto healthy = cardart::auditDeckArt(databasePath, cache.imageRoot(), u"zh"_s, true,
                                               requests, cache.entries());
    QVERIFY2(healthy.ok, qPrintable(healthy.error));
    QCOMPARE(healthy.faceCount, 3);
    QVERIFY(!healthy.repairNeeded());
    const QString pack = directory.filePath(u"support.hexproof-artpack"_s);
    const auto exported =
        cardart::exportPack(pack, cache.imageRoot(), cache.entries(), false, {}, {});
    QVERIFY2(exported.ok, qPrintable(exported.error));
    QCOMPARE(exported.entryCount, 3);
    CardArtCache target(directory.filePath(u"target"_s));
    const auto imported = cardart::importPack(pack, target.imageRoot());
    QVERIFY2(imported.ok, qPrintable(imported.error));
    for (const auto &entry : imported.importedEntries) {
        QVERIFY(entry.cacheKey.startsWith(u"zh|"_s));
        QCOMPARE(entry.record.imageLanguage, u"zh"_s);
        QCOMPARE(entry.record.oracleText, u"测试规则文字。"_s);
        QCOMPARE(entry.record.oracleTextLanguage, u"zh"_s);
        target.rememberSuccess(entry.cacheKey, entry.record);
    }
    const auto restored = cardart::auditDeckArt(databasePath, target.imageRoot(), u"zh"_s, true,
                                                requests, target.entries());
    QVERIFY2(restored.ok, qPrintable(restored.error));
    QVERIFY(!restored.repairNeeded());
}

QTEST_GUILESS_MAIN(TestCardArtArchive)
#include "cardartarchive_test.moc"
