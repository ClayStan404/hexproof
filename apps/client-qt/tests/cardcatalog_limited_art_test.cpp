// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "cardcatalog_test.h"

namespace {

bool writeLimitedArtCatalog(const QString &storagePath)
{
    const QString sourcePath = storagePath + QStringLiteral("/bulk.json");
    const QString databasePath = storagePath + QStringLiteral("/cards.sqlite");
    const QJsonArray cards{QJsonObject{
        {u"id"_s, u"card-1"_s},
        {u"oracle_id"_s, u"oracle-1"_s},
        {u"name"_s, u"Lightning Bolt"_s},
        {u"type_line"_s, u"Instant"_s},
        {u"set"_s, u"M11"_s},
        {u"collector_number"_s, u"149"_s},
        {u"lang"_s, u"en"_s},
        {u"layout"_s, u"normal"_s},
        {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://example.test/bolt.jpg"_s}}},
    }};
    QFile source(sourcePath);
    if (!source.open(QIODevice::WriteOnly))
        return false;
    const QByteArray payload = QJsonDocument(cards).toJson(QJsonDocument::Compact);
    if (source.write(payload) != payload.size())
        return false;
    source.close();
    if (!CardCatalog::importBulkFile(sourcePath, databasePath, u"default_cards"_s).ok)
        return false;

    const QJsonObject card{{u"name"_s, u"Lightning Bolt"_s}, {u"setCode"_s, u"M11"_s},
                           {u"collectorNumber"_s, u"149"_s}, {u"typeLine"_s, u"Instant"_s},
                           {u"rarity"_s, u"common"_s},       {u"weight"_s, 1}};
    const QJsonObject definition{
        {u"id"_s, u"mtgjson-m11-play"_s},
        {u"name"_s, u"M11 Play Booster"_s},
        {u"setCode"_s, u"M11"_s},
        {u"productType"_s, u"official"_s},
        {u"authentic"_s, true},
        {u"cardsPerPack"_s, 1},
        {u"sheets"_s, QJsonArray{QJsonObject{{u"name"_s, u"common"_s},
                                             {u"withReplacement"_s, false},
                                             {u"cards"_s, QJsonArray{card}}},
                                 QJsonObject{{u"name"_s, u"duplicate"_s},
                                             {u"withReplacement"_s, false},
                                             {u"cards"_s, QJsonArray{card}}}}},
        {u"variants"_s,
         QJsonArray{QJsonObject{
             {u"weight"_s, 1},
             {u"slots"_s, QJsonArray{QJsonObject{{u"sheet"_s, u"common"_s}, {u"count"_s, 1}}}}}}},
    };

    static int connectionSerial = 0;
    const QString connectionName = u"limited-art-product-%1"_s.arg(++connectionSerial);
    bool ok = false;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(databasePath);
        if (database.open()) {
            QSqlQuery query(database);
            ok = query.exec(u"CREATE TABLE IF NOT EXISTS limited_products ("
                            "id TEXT PRIMARY KEY, name TEXT, set_code TEXT, product_type TEXT, "
                            "authentic INTEGER, definition_json TEXT)"_s);
            if (ok) {
                query.prepare(u"INSERT INTO limited_products VALUES (?, ?, ?, ?, ?, ?)"_s);
                query.addBindValue(u"mtgjson-m11-play"_s);
                query.addBindValue(u"M11 Play Booster"_s);
                query.addBindValue(u"M11"_s);
                query.addBindValue(u"official"_s);
                query.addBindValue(1);
                query.addBindValue(QJsonDocument(definition).toJson(QJsonDocument::Compact));
                ok = query.exec();
            }
            database.close();
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return ok;
}

} // namespace

void TestCardCatalog::cachesLimitedProductWithMtgchSetIndex() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writeLimitedArtCatalog(storage.path()), "limited catalog setup failed");
    {
        FakeNetworkAccessManager network;
        CardCatalog catalog(storage.path(), &network);
        catalog.setLanguage(u"zh"_s);

        catalog.cacheLimitedProductArt(u"mtgjson-m11-play"_s);

        QTRY_VERIFY_WITH_TIMEOUT(!catalog.limitedArtCaching(), 3'000);
        QCOMPARE(catalog.limitedArtTotal(), 1);
        QCOMPARE(catalog.limitedArtCompleted(), 1);
        QCOMPARE(catalog.limitedArtFailed(), 0);
        QCOMPARE(network.requestedUrls.size(), 2);
        QCOMPARE(network.requestedUrls.at(0).path(), u"/api/v1/set/M11/cards/"_s);
        QCOMPARE(network.requestedUrls.at(1).host(), u"images.mtgch.com"_s);
        QVERIFY(std::none_of(
            network.requestedUrls.cbegin(), network.requestedUrls.cend(),
            [](const QUrl &url) { return url.path().startsWith(u"/api/v1/card/"_s); }));
        QVERIFY(catalog.printingImageSource(u"Lightning Bolt"_s, u"M11"_s, u"149"_s)
                    .startsWith(u"file:"_s));
    }

    QTemporaryDir fallbackStorage;
    QVERIFY(fallbackStorage.isValid());
    QVERIFY2(writeLimitedArtCatalog(fallbackStorage.path()), "fallback catalog setup failed");
    FakeNetworkAccessManager fallbackNetwork;
    fallbackNetwork.missMtgchSetRequests = true;
    CardCatalog fallbackCatalog(fallbackStorage.path(), &fallbackNetwork);
    fallbackCatalog.setLanguage(u"zh"_s);

    fallbackCatalog.cacheLimitedProductArt(u"mtgjson-m11-play"_s);

    QTRY_VERIFY_WITH_TIMEOUT(!fallbackCatalog.limitedArtCaching(), 3'000);
    QCOMPARE(fallbackCatalog.limitedArtFailed(), 0);
    QVERIFY(std::any_of(fallbackNetwork.requestedUrls.cbegin(),
                        fallbackNetwork.requestedUrls.cend(),
                        [](const QUrl &url) { return url.path().startsWith(u"/api/v1/card/"_s); }));
}
