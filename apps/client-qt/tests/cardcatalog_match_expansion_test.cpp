// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "cardcatalog_test.h"

#include "services/CardArtCache.h"
#include "services/CatalogStorage.h"

#include <QEventLoop>

namespace {

QVariantMap printingRequest(int index)
{
    return {
        {u"name"_s, QStringLiteral("Front %1").arg(index)},
        {u"setCode"_s, u"TST"_s},
        {u"collectorNumber"_s, QString::number(index + 1)},
    };
}

bool writeExpansionCatalog(const QString &storagePath, int count)
{
    QJsonArray cards;
    for (int index = 0; index < count; ++index) {
        const QString front = QStringLiteral("Front %1").arg(index);
        const QString back = QStringLiteral("Back %1").arg(index);
        cards.append(QJsonObject{
            {u"id"_s, QStringLiteral("printing-%1").arg(index)},
            {u"oracle_id"_s, QStringLiteral("oracle-%1").arg(index)},
            {u"name"_s, front + u" // "_s + back},
            {u"type_line"_s, u"Creature // Creature"_s},
            {u"set"_s, u"TST"_s},
            {u"collector_number"_s, QString::number(index + 1)},
            {u"lang"_s, u"en"_s},
            {u"layout"_s, u"transform"_s},
            {u"card_faces"_s,
             QJsonArray{
                 QJsonObject{
                     {u"name"_s, front},
                     {u"type_line"_s, u"Creature — Human"_s},
                     {u"image_uris"_s,
                      QJsonObject{{u"normal"_s,
                                   QStringLiteral("https://images.test/front-%1.png").arg(index)}}},
                 },
                 QJsonObject{
                     {u"name"_s, back},
                     {u"type_line"_s, u"Creature — Beast"_s},
                     {u"image_uris"_s,
                      QJsonObject{{u"normal"_s,
                                   QStringLiteral("https://images.test/back-%1.png").arg(index)}}},
                 },
             }},
        });
    }

    const QString sourcePath = QDir(storagePath).filePath(u"expansion-bulk.json"_s);
    QFile source(sourcePath);
    if (!source.open(QIODevice::WriteOnly))
        return false;
    const QByteArray payload = QJsonDocument(cards).toJson(QJsonDocument::Compact);
    const bool written = source.write(payload) == payload.size();
    source.close();
    return written &&
           CardCatalog::importBulkFile(sourcePath, QDir(storagePath).filePath(u"cards.sqlite"_s),
                                       u"default_cards"_s)
               .ok;
}

bool writeSingleFaceExpansionCatalog(const QString &storagePath)
{
    const QJsonArray cards{QJsonObject{
        {u"id"_s, u"single-printing"_s},
        {u"oracle_id"_s, u"single-oracle"_s},
        {u"name"_s, u"Solo Card"_s},
        {u"type_line"_s, u"Creature — Human"_s},
        {u"set"_s, u"TST"_s},
        {u"collector_number"_s, u"99"_s},
        {u"lang"_s, u"en"_s},
        {u"layout"_s, u"normal"_s},
        {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://images.test/solo.png"_s}}},
    }};
    const QString sourcePath = QDir(storagePath).filePath(u"single-expansion-bulk.json"_s);
    QFile source(sourcePath);
    if (!source.open(QIODevice::WriteOnly))
        return false;
    const QByteArray payload = QJsonDocument(cards).toJson(QJsonDocument::Compact);
    const bool written = source.write(payload) == payload.size();
    source.close();
    return written &&
           CardCatalog::importBulkFile(sourcePath, QDir(storagePath).filePath(u"cards.sqlite"_s),
                                       u"default_cards"_s)
               .ok;
}

bool dropExpansionCardsTable(const QString &databasePath)
{
    const QString connectionName =
        QStringLiteral("expansion-drop-%1").arg(QDateTime::currentMSecsSinceEpoch());
    bool dropped = false;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(databasePath);
        if (database.open()) {
            QSqlQuery query(database);
            dropped = query.exec(u"DROP TABLE cards"_s);
            database.close();
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return dropped;
}

void runOneEventLoopTurn()
{
    QEventLoop loop;
    QTimer::singleShot(0, &loop, &QEventLoop::quit);
    loop.exec();
}

} // namespace

void TestCardCatalog::boundedExpansionPreservesFacesIdentityAndDeduplication() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const int requestCount = CardCatalog::cardFaceExpansionBatchSize() + 1;
    QVERIFY2(writeExpansionCatalog(storage.path(), requestCount), "test catalog import failed");
    CardCatalog catalog(storage.path());
    QSignalSpy progress(&catalog, &CardCatalog::cardFaceExpansionProgress);
    QSignalSpy completed(&catalog, &CardCatalog::cardFaceRequestsExpanded);

    QVariantList requests;
    QVariantMap exact = printingRequest(0);
    exact.insert(u"exactArt"_s, true);
    requests.append(exact);
    requests.append(exact);
    for (int index = 1; index < requestCount; ++index)
        requests.append(printingRequest(index));

    catalog.expandCardFaceRequestsIncrementally(21, 5, requests);
    QCOMPARE(completed.count(), 0);
    runOneEventLoopTurn();
    QCOMPARE(progress.count(), 1);
    QVERIFY(progress.first().at(3).toInt() <= CardCatalog::cardFaceExpansionBatchSize());
    QCOMPARE(completed.count(), 0);
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), 1, 2'000);

    QCOMPARE(completed.first().at(0).toLongLong(), 21);
    QCOMPARE(completed.first().at(1).toULongLong(), quint64(5));
    const QVariantList expanded = completed.first().at(2).toList();
    QCOMPARE(expanded.size(), requestCount * 2);
    const QVariantMap front = expanded.at(0).toMap();
    const QVariantMap back = expanded.at(1).toMap();
    QCOMPARE(front.value(u"name"_s).toString(), u"Front 0"_s);
    QCOMPARE(back.value(u"name"_s).toString(), u"Back 0"_s);
    QCOMPARE(front.value(u"priorityName"_s).toString(), u"Front 0"_s);
    QCOMPARE(back.value(u"priorityName"_s).toString(), u"Front 0"_s);
    QVERIFY(front.value(u"exactArt"_s).toBool());
    QVERIFY(back.value(u"exactArt"_s).toBool());
    QVERIFY(front.value(u"_hexproofCardFacesExpanded"_s).toBool());
    QVERIFY(back.value(u"_hexproofCardFacesExpanded"_s).toBool());
    QVERIFY(front.value(u"faceName"_s).toString().isEmpty());
    QCOMPARE(back.value(u"faceName"_s).toString(), u"Back 0"_s);
    QCOMPARE(back.value(u"setCode"_s).toString(), u"TST"_s);
    QCOMPARE(back.value(u"collectorNumber"_s).toString(), u"1"_s);
}

void TestCardCatalog::boundedExpansionWaitsForCatalogReplacement() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY(writeExpansionCatalog(storage.path(), 1));
    CardCatalog catalog(storage.path());
    QSignalSpy completed(&catalog, &CardCatalog::cardFaceRequestsExpanded);
    // Hold installation at the live-file swap while the GUI processes expansion.
    QReadLocker catalogReader(&hexproof::client::catalogstorage::databaseLock());
    catalog.importCatalogFile(QUrl::fromLocalFile(storage.filePath(u"expansion-bulk.json"_s)),
                              u"default_cards"_s);
    QVERIFY(catalog.busy());
    catalog.expandCardFaceRequestsIncrementally(24, 8, {printingRequest(0)});
    runOneEventLoopTurn();
    const int completedWhileInstalling = completed.count();
    catalogReader.unlock();
    QTRY_VERIFY(!catalog.busy());
    QVERIFY2(catalog.lastError().isEmpty(), qPrintable(catalog.lastError()));
    QCOMPARE(completedWhileInstalling, 0);
    QTRY_COMPARE(completed.count(), 1);
    const QVariantList expanded = completed.first().at(2).toList();
    QCOMPARE(expanded.size(), 2);
    QCOMPARE(expanded.at(1).toMap().value(u"name"_s).toString(), u"Back 0"_s);
}

void TestCardCatalog::languageChangeRestartsBoundedExpansion() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const int requestCount = CardCatalog::cardFaceExpansionBatchSize() + 1;
    QVERIFY2(writeExpansionCatalog(storage.path(), requestCount), "test catalog import failed");
    CardCatalog catalog(storage.path());
    QSignalSpy progress(&catalog, &CardCatalog::cardFaceExpansionProgress);
    QSignalSpy completed(&catalog, &CardCatalog::cardFaceRequestsExpanded);
    QVariantList requests;
    for (int index = 0; index < requestCount; ++index)
        requests.append(printingRequest(index));

    catalog.expandCardFaceRequestsIncrementally(22, 6, requests);
    runOneEventLoopTurn();
    QCOMPARE(progress.count(), 1);
    QCOMPARE(progress.first().at(2).toString(), u"en"_s);

    catalog.setLanguage(u"zh"_s);
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), 1, 2'000);
    QVERIFY(progress.count() >= 3);
    QCOMPARE(progress.at(1).at(2).toString(), u"zh"_s);
    QCOMPARE(completed.first().at(0).toLongLong(), 22);
    QCOMPARE(completed.first().at(1).toULongLong(), quint64(6));
}

void TestCardCatalog::supersededBoundedExpansionDoesNotComplete() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const int requestCount = CardCatalog::cardFaceExpansionBatchSize() + 1;
    QVERIFY2(writeExpansionCatalog(storage.path(), requestCount), "test catalog import failed");
    CardCatalog catalog(storage.path());
    QSignalSpy completed(&catalog, &CardCatalog::cardFaceRequestsExpanded);
    QVariantList requests;
    for (int index = 0; index < requestCount; ++index)
        requests.append(printingRequest(index));

    catalog.expandCardFaceRequestsIncrementally(23, 7, requests);
    runOneEventLoopTurn();
    catalog.expandCardFaceRequestsIncrementally(23, 8, {printingRequest(0)});

    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), 1, 2'000);
    QCOMPARE(completed.first().at(1).toULongLong(), quint64(8));
    QTest::qWait(20);
    QCOMPARE(completed.count(), 1);
}

void TestCardCatalog::incrementalCachingDoesNotReexpandAdoptedFaces() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writeExpansionCatalog(storage.path(), 1), "test catalog import failed");
    QVariantMap exact = printingRequest(0);
    exact.insert(u"exactArt"_s, true);
    QVariantList expanded;
    {
        CardCatalog catalog(storage.path());
        QSignalSpy completed(&catalog, &CardCatalog::cardFaceRequestsExpanded);
        catalog.expandCardFaceRequestsIncrementally(24, 9, {exact});
        QTRY_COMPARE_WITH_TIMEOUT(completed.count(), 1, 1'000);
        expanded = completed.first().at(2).toList();
    }
    QCOMPARE(expanded.size(), 2);
    for (const QVariant &value : std::as_const(expanded)) {
        const QVariantMap face = value.toMap();
        QVERIFY(face.value(u"_hexproofCardFacesExpanded"_s).toBool());
        QVERIFY(face.value(u"exactArt"_s).toBool());
    }
    QVERIFY(expanded.at(0).toMap().value(u"faceName"_s).toString().isEmpty());
    QCOMPARE(expanded.at(1).toMap().value(u"faceName"_s).toString(), u"Back 0"_s);

    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy errors(&catalog, &CardCatalog::printingsErrorChanged);
    catalog.cacheCardsIncrementally(expanded);
    QVERIFY(dropExpansionCardsTable(storage.filePath(u"cards.sqlite"_s)));
    QTest::qWait(50);
    QCOMPARE(errors.count(), 0);
}

void TestCardCatalog::incrementalCachingDoesNotReexpandSingleFace() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writeSingleFaceExpansionCatalog(storage.path()), "test catalog import failed");
    const QVariantMap request{
        {u"name"_s, u"Solo Card"_s},
        {u"setCode"_s, u"TST"_s},
        {u"collectorNumber"_s, u"99"_s},
    };
    QVariantList expanded;
    {
        CardCatalog catalog(storage.path());
        QSignalSpy completed(&catalog, &CardCatalog::cardFaceRequestsExpanded);
        catalog.expandCardFaceRequestsIncrementally(25, 10, {request});
        QTRY_COMPARE_WITH_TIMEOUT(completed.count(), 1, 1'000);
        expanded = completed.first().at(2).toList();
    }
    QCOMPARE(expanded.size(), 1);
    const QVariantMap card = expanded.first().toMap();
    QVERIFY(card.value(u"_hexproofCardFacesExpanded"_s).toBool());
    QVERIFY(!card.contains(u"faceName"_s));

    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy errors(&catalog, &CardCatalog::printingsErrorChanged);
    catalog.cacheCardsIncrementally(expanded);
    QVERIFY(dropExpansionCardsTable(storage.filePath(u"cards.sqlite"_s)));
    QTest::qWait(50);
    QCOMPARE(errors.count(), 0);
}

void TestCardCatalog::matchSubscriptionCoalescesWithQueuedWork() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy global(&catalog, &CardCatalog::cardCacheFinished);
    QSignalSpy scoped(&catalog, &CardCatalog::matchCardCacheFinished);
    const QVariantMap card{
        {u"name"_s, u"Wear // Tear"_s},
        {u"setCode"_s, u"MOC"_s},
        {u"collectorNumber"_s, u"343"_s},
        {u"faceName"_s, QString{}},
    };

    catalog.cacheCardsIncrementally({card});
    catalog.cacheMatchCardsIncrementally(31, 4, {card});

    QTRY_COMPARE_WITH_TIMEOUT(global.count(), 1, 2'000);
    QTRY_COMPARE_WITH_TIMEOUT(scoped.count(), 1, 2'000);
    const QList<QVariant> completion = scoped.first();
    QCOMPARE(completion.at(0).toLongLong(), 31);
    QCOMPARE(completion.at(1).toULongLong(), quint64(4));
    QVERIFY(completion.at(2).toString().startsWith(u"en|wear // tear|MOC|343"_s));
    QVERIFY(!completion.at(6).toBool());
    QVERIFY(completion.at(7).toBool());
}

void TestCardCatalog::matchSubscriptionsSeparateExactArtModes() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy scoped(&catalog, &CardCatalog::matchCardCacheFinished);
    const QVariantMap normal{
        {u"name"_s, u"Wear // Tear"_s},
        {u"setCode"_s, u"CMM"_s},
        {u"collectorNumber"_s, u"1"_s},
        {u"faceName"_s, QString{}},
    };
    QVariantMap exact = normal;
    exact.insert(u"exactArt"_s, true);

    catalog.cacheMatchCardsIncrementally(32, 5, {normal, exact});

    QTRY_COMPARE_WITH_TIMEOUT(scoped.count(), 2, 3'000);
    const QList<QVariant> first = scoped.at(0);
    const QList<QVariant> second = scoped.at(1);
    QVERIFY(first.at(6).toBool() != second.at(6).toBool());
    const QList<QVariant> exactCompletion = first.at(6).toBool() ? first : second;
    const QList<QVariant> normalCompletion = first.at(6).toBool() ? second : first;
    QVERIFY(exactCompletion.at(2).toString().endsWith(u"|exact-art"_s));
    QVERIFY(!normalCompletion.at(2).toString().endsWith(u"|exact-art"_s));
    QVERIFY(exactCompletion.at(7).toBool());
    QVERIFY(normalCompletion.at(7).toBool());
}

void TestCardCatalog::cancelledMatchSubscriptionCannotAffectReplacement() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy scoped(&catalog, &CardCatalog::matchCardCacheFinished);
    const QVariantMap card{
        {u"name"_s, u"Wear // Tear"_s},
        {u"setCode"_s, u"MOC"_s},
        {u"collectorNumber"_s, u"343"_s},
        {u"faceName"_s, QString{}},
    };

    catalog.cacheMatchCardsIncrementally(32, 5, {card});
    catalog.cancelMatchCardSubscriptions(32, 5);
    catalog.cacheMatchCardsIncrementally(33, 6, {card});

    QTRY_COMPARE_WITH_TIMEOUT(scoped.count(), 1, 2'000);
    QCOMPARE(scoped.first().at(0).toLongLong(), 33);
    QCOMPARE(scoped.first().at(1).toULongLong(), quint64(6));
    QTest::qWait(20);
    QCOMPARE(scoped.count(), 1);
}

void TestCardCatalog::cacheAndRetryDeferFaceExpansion() const
{
    for (const bool retry : {false, true}) {
        QTemporaryDir storage;
        QVERIFY(storage.isValid());
        QVERIFY2(writeExpansionCatalog(storage.path(), 1), "test catalog import failed");
        CardCatalog catalog(storage.path());
        QSignalSpy errors(&catalog, &CardCatalog::printingsErrorChanged);

        if (retry)
            catalog.retryCards({printingRequest(0)});
        else
            catalog.cacheCards({printingRequest(0)});
        QCOMPARE(errors.count(), 0);
        QVERIFY(dropExpansionCardsTable(storage.filePath(u"cards.sqlite"_s)));
        QTRY_VERIFY_WITH_TIMEOUT(errors.count() > 0, 1'000);
    }
}

void TestCardCatalog::retryClearsFailureForEveryExpandedFace() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writeExpansionCatalog(storage.path(), 1), "test catalog import failed");
    hexproof::client::CardArtCache cache(storage.path());
    for (const QString &name : {u"Front 0"_s, u"Back 0"_s})
        cache.rememberFailure(cache.key(name, u"en"_s, u"TST"_s, u"1"_s));
    QVERIFY(cache.save());

    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy finished(&catalog, &CardCatalog::cardCacheFinished);
    catalog.retryCards({printingRequest(0)});

    QTRY_COMPARE_WITH_TIMEOUT(finished.count(), 2, 3'000);
    QVERIFY(finished.at(0).at(3).toBool());
    QVERIFY(finished.at(1).at(3).toBool());
}

void TestCardCatalog::cachedTypeLineNeverQueriesBrokenCatalog() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writeExpansionCatalog(storage.path(), 1), "test catalog import failed");
    const QString imagePath = storage.filePath(u"cached.jpg"_s);
    QFile image(imagePath);
    QVERIFY(image.open(QIODevice::WriteOnly));
    QCOMPARE(image.write("cached image"), 12);
    image.close();

    hexproof::client::CardArtCache cache(storage.path());
    CardCatalog::CardRecord record;
    record.requestedName = u"Front 0"_s;
    record.name = u"Front 0"_s;
    record.typeLine = u"Creature — Human"_s;
    record.setCode = u"TST"_s;
    record.collectorNumber = u"1"_s;
    record.imagePath = imagePath;
    record.imageLanguage = u"en"_s;
    record.resolutionVersion = kCardResolutionVersion;
    cache.rememberSuccess(cache.key(record.name, u"en"_s, record.setCode, record.collectorNumber),
                          record);
    QVERIFY(cache.save());

    CardCatalog catalog(storage.path());
    QVERIFY(dropExpansionCardsTable(storage.filePath(u"cards.sqlite"_s)));
    QCOMPARE(catalog.printings(u"Missing"_s), QVariantList{});
    QVERIFY(!catalog.printingsError().isEmpty());
    const QString catalogError = catalog.printingsError();

    QCOMPARE(catalog.cachedCardTypeLine(u"Front 0"_s, u"TST"_s, u"1"_s), u"Creature — Human"_s);
    QCOMPARE(catalog.cachedCardTypeLine(u"Missing"_s, u"TST"_s, u"99"_s), QString{});
    QCOMPARE(catalog.printingsError(), catalogError);
}
