// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "cardcatalog_test.h"

#include "services/CardArtCache.h"

void TestCardCatalog::prefersMtgchChineseFields() const
{
    const QJsonObject object{
        {u"name"_s, u"Sol Ring"_s},
        {u"zhs_name"_s, u"阳光戒"_s},
        {u"zhs_type_line"_s, u"神器"_s},
        {u"type_line"_s, u"Artifact"_s},
        {u"set"_s, u"CMM"_s},
        {u"collector_number"_s, u"396"_s},
        {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://example.test/en.jpg"_s}}},
        {u"zhs_image_uris"_s, QJsonObject{{u"normal"_s, u"https://example.test/zh.webp"_s}}},
    };

    const CardCatalog::CardRecord chinese =
        CardCatalog::parseCardObject(object, u"zh"_s, u"Sol Ring"_s);
    QCOMPARE(chinese.localizedName, u"阳光戒"_s);
    QCOMPARE(chinese.imageUrl, u"https://example.test/zh.webp"_s);
    QCOMPARE(chinese.imageLanguage, u"zh"_s);
    QCOMPARE(chinese.typeLine, u"神器"_s);

    const CardCatalog::CardRecord english =
        CardCatalog::parseCardObject(object, u"en"_s, u"Sol Ring"_s);
    QCOMPARE(english.localizedName, u"Sol Ring"_s);
    QCOMPARE(english.imageUrl, u"https://example.test/en.jpg"_s);
    QCOMPARE(english.imageLanguage, u"en"_s);

    QJsonObject fallbackObject = object;
    fallbackObject.insert(u"image_uris"_s,
                          QJsonObject{{u"small"_s, u"https://example.test/en-small.jpg"_s},
                                      {u"large"_s, u"https://example.test/en-large.jpg"_s}});
    const CardCatalog::CardRecord fallback =
        CardCatalog::parseCardObject(fallbackObject, u"en"_s, u"Sol Ring"_s);
    QCOMPARE(fallback.imageUrl, u"https://example.test/en-large.jpg"_s);
}

void TestCardCatalog::rejectsUnverifiedChineseFallbacks() const
{
    const QJsonObject object{
        {u"name"_s, u"Sol Ring"_s},
        {u"zhs_name"_s, u"Sol Ring"_s},
        {u"atomic_official_name"_s, u"Sol Ring"_s},
        {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://example.test/en.jpg"_s}}},
    };

    const CardCatalog::CardRecord chinese =
        CardCatalog::parseCardObject(object, u"zh"_s, u"Sol Ring"_s);
    QCOMPARE(chinese.localizedName, u"Sol Ring"_s);
    QVERIFY(chinese.imageUrl.isEmpty());
    QVERIFY(chinese.imageLanguage.isEmpty());
}

void TestCardCatalog::rejectsScryfallPlaceholderImages() const
{
    QJsonObject object{
        {u"name"_s, u"Goryo's Vengeance"_s},
        {u"printed_name"_s, u"怨灵复仇"_s},
        {u"lang"_s, u"zhs"_s},
        {u"image_status"_s, u"placeholder"_s},
        {u"image_uris"_s,
         QJsonObject{{u"normal"_s, u"https://example.test/localized-placeholder.jpg"_s}}},
    };

    const CardCatalog::CardRecord chinese =
        CardCatalog::parseCardObject(object, u"zh"_s, u"Goryo's Vengeance"_s);
    QVERIFY(chinese.imageUrl.isEmpty());
    QVERIFY(chinese.imageLanguage.isEmpty());

    const CardCatalog::CardRecord english =
        CardCatalog::parseCardObject(object, u"en"_s, u"Goryo's Vengeance"_s);
    QVERIFY(english.imageUrl.isEmpty());
    QVERIFY(english.imageLanguage.isEmpty());

    object.insert(u"image_status"_s, u"lowres"_s);
    const CardCatalog::CardRecord lowResolution =
        CardCatalog::parseCardObject(object, u"zh"_s, u"Goryo's Vengeance"_s);
    QCOMPARE(lowResolution.imageUrl, u"https://example.test/localized-placeholder.jpg"_s);
    QCOMPARE(lowResolution.imageLanguage, u"zh"_s);
}

void TestCardCatalog::filtersPlaceholderImagesFromBulkCatalog() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString sourcePath = storage.filePath(u"bulk.json"_s);
    const QString databasePath = storage.filePath(u"cards.sqlite"_s);
    const QJsonArray cards{
        QJsonObject{
            {u"id"_s, u"placeholder-printing"_s},
            {u"oracle_id"_s, u"oracle-1"_s},
            {u"name"_s, u"Goryo's Vengeance"_s},
            {u"printed_name"_s, u"怨灵复仇"_s},
            {u"type_line"_s, u"Instant — Arcane"_s},
            {u"set"_s, u"BOK"_s},
            {u"collector_number"_s, u"67"_s},
            {u"lang"_s, u"zhs"_s},
            {u"image_status"_s, u"placeholder"_s},
            {u"image_uris"_s,
             QJsonObject{{u"normal"_s, u"https://example.test/placeholder.jpg"_s}}},
        },
        QJsonObject{
            {u"id"_s, u"lowres-printing"_s},
            {u"oracle_id"_s, u"oracle-2"_s},
            {u"name"_s, u"Test Card"_s},
            {u"printed_name"_s, u"测试牌"_s},
            {u"type_line"_s, u"Instant"_s},
            {u"set"_s, u"TST"_s},
            {u"collector_number"_s, u"1"_s},
            {u"lang"_s, u"zhs"_s},
            {u"image_status"_s, u"lowres"_s},
            {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://example.test/lowres.jpg"_s}}},
        },
    };
    QFile source(sourcePath);
    QVERIFY(source.open(QIODevice::WriteOnly));
    const QByteArray payload = QJsonDocument(cards).toJson(QJsonDocument::Compact);
    QCOMPARE(source.write(payload), payload.size());
    source.close();

    const CardCatalog::ImportResult imported =
        CardCatalog::importBulkFile(sourcePath, databasePath, u"default_cards"_s);
    QVERIFY2(imported.ok, qPrintable(imported.error));
    QCOMPARE(imported.cardCount, 2);
    QCOMPARE(imported.localizedPrintingCount, 1);

    const QString connectionName = u"placeholder-image-status-test"_s;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(databasePath);
        QVERIFY2(database.open(), qPrintable(database.lastError().text()));
        QSqlQuery query(database);
        QVERIFY(query.exec(u"SELECT image_status, image_url FROM cards "
                           "WHERE id = 'placeholder-printing'"_s));
        QVERIFY(query.next());
        QCOMPARE(query.value(0).toString(), u"placeholder"_s);
        QVERIFY(query.value(1).toString().isEmpty());
        QVERIFY(query.exec(u"SELECT image_status, image_url FROM localized_printings "
                           "WHERE id = 'lowres-printing'"_s));
        QVERIFY(query.next());
        QCOMPARE(query.value(0).toString(), u"lowres"_s);
        QCOMPARE(query.value(1).toString(), u"https://example.test/lowres.jpg"_s);
        QVERIFY(query.exec(u"SELECT 1 FROM sqlite_master WHERE type = 'index' "
                           "AND name = 'cards_printing_idx'"_s));
        QVERIFY(query.next());
        database.close();
    }
    QSqlDatabase::removeDatabase(connectionName);
}

void TestCardCatalog::usesWholeCardImageForAdventureFace() const
{
    const QJsonObject object{
        {u"name"_s, u"Murderous Rider // Swift End"_s},
        {u"oracle_id"_s, u"rider-oracle"_s},
        {u"layout"_s, u"adventure"_s},
        {u"set"_s, u"ELD"_s},
        {u"collector_number"_s, u"97"_s},
        {u"lang"_s, u"en"_s},
        {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://images.test/murderous-rider.png"_s}}},
        {u"card_faces"_s,
         QJsonArray{
             QJsonObject{{u"name"_s, u"Murderous Rider"_s},
                         {u"type_line"_s, u"Creature — Zombie Knight"_s}},
             QJsonObject{{u"name"_s, u"Swift End"_s}, {u"type_line"_s, u"Instant — Adventure"_s}},
         }},
    };

    const CardCatalog::CardRecord record =
        CardCatalog::parseCardObject(object, u"en"_s, u"Murderous Rider"_s);
    QCOMPARE(record.name, u"Murderous Rider // Swift End"_s);
    QCOMPARE(record.faceName, u"Murderous Rider"_s);
    QCOMPARE(record.typeLine, u"Creature — Zombie Knight"_s);
    QCOMPARE(record.imageUrl, u"https://images.test/murderous-rider.png"_s);
}

void TestCardCatalog::usesWholeCardImageForPrepareCard() const
{
    const QJsonObject object{
        {u"name"_s, u"Emeritus of Truce // Swords to Plowshares"_s},
        {u"face_name"_s, u"Emeritus of Truce"_s},
        {u"oracle_id"_s, u"emeritus-oracle"_s},
        {u"layout"_s, u"prepare"_s},
        {u"set"_s, u"SOS"_s},
        {u"collector_number"_s, u"13"_s},
        {u"type_line"_s, u"Creature — Cat Cleric"_s},
        {u"atomic_translated_name"_s, u"止战尊贤"_s},
        {u"zhs_image_uris"_s,
         QJsonObject{{u"normal"_s, u"https://images.test/emeritus-zh.webp"_s}}},
        {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://images.test/emeritus-en.webp"_s}}},
        {u"other_faces"_s,
         QJsonArray{QJsonObject{
             {u"name"_s, u"Emeritus of Truce // Swords to Plowshares"_s},
             {u"face_name"_s, u"Swords to Plowshares"_s},
             {u"type_line"_s, u"Instant"_s},
             {u"atomic_translated_name"_s, u"化剑为犁"_s},
             {u"zhs_image_uris"_s,
              QJsonObject{{u"normal"_s, u"https://images.test/emeritus-zh.webp"_s}}},
             {u"image_uris"_s,
              QJsonObject{{u"normal"_s, u"https://images.test/emeritus-en.webp"_s}}},
         }}},
    };

    const CardCatalog::CardRecord wholeCard = CardCatalog::parseCardObject(
        object, u"zh"_s, u"Emeritus of Truce // Swords to Plowshares"_s);
    QVERIFY(wholeCard.faceName.isEmpty());
    QCOMPARE(wholeCard.typeLine, u"Creature — Cat Cleric"_s);
    QCOMPARE(wholeCard.localizedName, u"止战尊贤"_s);
    QCOMPARE(wholeCard.imageUrl, u"https://images.test/emeritus-zh.webp"_s);
    QTemporaryDir cacheStorage;
    QVERIFY(cacheStorage.isValid());
    hexproof::client::CardArtCache cache(cacheStorage.path());
    QVERIFY(cache.matchesRequestedFace(
        hexproof::client::CardRequest{u"Emeritus of Truce // Swords to Plowshares"_s, u"SOS"_s,
                                      u"13"_s, u"zh"_s},
        wholeCard));

    const CardCatalog::CardRecord prepareSpell =
        CardCatalog::parseCardObject(object, u"zh"_s, u"Swords to Plowshares"_s);
    QCOMPARE(prepareSpell.faceName, u"Swords to Plowshares"_s);
    QCOMPARE(prepareSpell.typeLine, u"Instant"_s);
    QCOMPARE(prepareSpell.localizedName, u"化剑为犁"_s);
    QCOMPARE(prepareSpell.imageUrl, u"https://images.test/emeritus-zh.webp"_s);
}

void TestCardCatalog::usesRequestedMtgchDoubleFace() const
{
    const QJsonObject object{
        {u"name"_s, u"Ajani, Nacatl Pariah // Ajani, Nacatl Avenger"_s},
        {u"oracle_id"_s, u"ajani-oracle"_s},
        {u"layout"_s, u"transform"_s},
        {u"set"_s, u"MH3"_s},
        {u"collector_number"_s, u"237"_s},
        {u"lang"_s, u"en"_s},
        {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://images.test/front-en.webp"_s}}},
        {u"zhs_image_uris"_s, QJsonObject{{u"normal"_s, u"https://images.test/front-zh.webp"_s}}},
        {u"other_faces"_s,
         QJsonArray{QJsonObject{
             {u"name"_s, u"Ajani, Nacatl Pariah // Ajani, Nacatl Avenger"_s},
             {u"face_name"_s, u"Ajani, Nacatl Avenger"_s},
             {u"type_line"_s, u"Legendary Planeswalker — Ajani"_s},
             {u"zhs_face_name"_s, u"拿卡地复仇者阿耶尼"_s},
             {u"zhs_type_line"_s, u"传奇鹏洛客～阿耶尼"_s},
             {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://images.test/back-en.webp"_s}}},
             {u"zhs_image_uris"_s,
              QJsonObject{{u"normal"_s, u"https://images.test/back-zh.webp"_s}}},
         }}},
    };

    const CardCatalog::CardRecord chinese =
        CardCatalog::parseCardObject(object, u"zh"_s, u"Ajani, Nacatl Avenger"_s);
    QCOMPARE(chinese.faceName, u"Ajani, Nacatl Avenger"_s);
    QCOMPARE(chinese.localizedName, u"拿卡地复仇者阿耶尼"_s);
    QCOMPARE(chinese.typeLine, u"传奇鹏洛客～阿耶尼"_s);
    QCOMPARE(chinese.imageUrl, u"https://images.test/back-zh.webp"_s);

    QJsonObject missingLocalizedBack = object;
    QJsonObject englishOnlyBack = object.value(u"other_faces"_s).toArray().first().toObject();
    englishOnlyBack.remove(u"zhs_image_uris"_s);
    missingLocalizedBack.insert(u"other_faces"_s, QJsonArray{englishOnlyBack});
    const CardCatalog::CardRecord missingChinese =
        CardCatalog::parseCardObject(missingLocalizedBack, u"zh"_s, u"Ajani, Nacatl Avenger"_s);
    QVERIFY(missingChinese.imageUrl.isEmpty());

    const CardCatalog::CardRecord english =
        CardCatalog::parseCardObject(object, u"en"_s, u"Ajani, Nacatl Avenger"_s);
    QCOMPARE(english.faceName, u"Ajani, Nacatl Avenger"_s);
    QCOMPARE(english.typeLine, u"Legendary Planeswalker — Ajani"_s);
    QCOMPARE(english.imageUrl, u"https://images.test/back-en.webp"_s);

    QJsonObject missingBack = object;
    missingBack.remove(u"other_faces"_s);
    const CardCatalog::CardRecord unidentifiedBack =
        CardCatalog::parseCardObject(missingBack, u"zh"_s, u"Ajani, Nacatl Avenger"_s);
    QVERIFY(unidentifiedBack.faceName.isEmpty());
    QVERIFY(unidentifiedBack.imageUrl.isEmpty());
}

void TestCardCatalog::preservesScryfallFlavorName() const
{
    const QJsonObject object{
        {u"name"_s, u"Brago, King Eternal"_s},
        {u"flavor_name"_s, u"Miku, Queen Electric"_s},
        {u"oracle_id"_s, u"brago-oracle"_s},
        {u"set"_s, u"SLD"_s},
        {u"collector_number"_s, u"1601"_s},
        {u"lang"_s, u"en"_s},
        {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://images.test/miku.png"_s}}},
    };

    const CardCatalog::CardRecord record =
        CardCatalog::parseCardObject(object, u"en"_s, u"Miku, Queen Electric"_s);
    QCOMPARE(record.name, u"Brago, King Eternal"_s);
    QCOMPARE(record.localizedName, u"Miku, Queen Electric"_s);
    QCOMPARE(record.imageUrl, u"https://images.test/miku.png"_s);
}

void TestCardCatalog::rejectsTruncatedBulkData() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString sourcePath = storage.filePath(u"truncated.json"_s);
    const QString databasePath = storage.filePath(u"cards.sqlite"_s);

    QFile source(sourcePath);
    QVERIFY(source.open(QIODevice::WriteOnly));
    const QByteArray truncated = QByteArrayLiteral(
        "[{\"id\":\"complete\",\"name\":\"Sol Ring\"},{\"id\":\"cut\",\"name\":\"Light");
    QVERIFY(source.write(truncated) > 0);
    source.close();

    const CardCatalog::ImportResult imported =
        CardCatalog::importBulkFile(sourcePath, databasePath, u"default_cards"_s);
    QVERIFY(!imported.ok);
    QVERIFY(imported.error.contains(u"middle of a card"_s));
    QVERIFY(!QFile::exists(databasePath));
}

void TestCardCatalog::recoversInterruptedDatabaseReplacement() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString databasePath = storage.filePath(u"cards.sqlite"_s);
    QFile backup(databasePath + u".backup"_s);
    QVERIFY(backup.open(QIODevice::WriteOnly));
    QCOMPARE(backup.write("previous catalog"), 16);
    backup.close();
    QFile incomplete(databasePath + u".new"_s);
    QVERIFY(incomplete.open(QIODevice::WriteOnly));
    QCOMPARE(incomplete.write("incomplete"), 10);
    incomplete.close();

    CardCatalog catalog(storage.path());
    QVERIFY(catalog.installed());
    QVERIFY(!QFileInfo::exists(databasePath + u".backup"_s));
    QVERIFY(!QFileInfo::exists(databasePath + u".new"_s));
    QFile restored(databasePath);
    QVERIFY(restored.open(QIODevice::ReadOnly));
    QCOMPARE(restored.readAll(), QByteArrayLiteral("previous catalog"));
}

void TestCardCatalog::prefersScryfallBeforeMtgchFallback() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"zh"_s);
    catalog.setCardArtProvider(u"scryfall"_s);
    QSignalSpy availableSpy(&catalog, &CardCatalog::cardAvailable);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);

    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }});

    QTRY_COMPARE_WITH_TIMEOUT(availableSpy.count(), 1, 2'000);
    QCOMPARE(cacheSpy.count(), 1);
    QVERIFY(cacheSpy.first().at(3).toBool());
    QCOMPARE(network.requestedUrls.size(), 2);
    QCOMPARE(network.requestedUrls.at(0).host(), u"api.scryfall.com"_s);
    QCOMPARE(network.requestedUrls.at(1), QUrl(u"https://images.test/bolt.png"_s));
    const QList<QVariant> arguments = availableSpy.takeFirst();
    QCOMPARE(arguments.at(1).toString(), u"闪电击"_s);
    QCOMPARE(arguments.at(2).toString(), u"瞬间"_s);
    QVERIFY(QFileInfo::exists(arguments.at(3).toString()));

    // A match prefetch for an already-cached printing completes immediately
    // without another network request.
    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }});
    QCOMPARE(cacheSpy.count(), 2);
    QCOMPARE(network.requestedUrls.size(), 2);
    QVERIFY(catalog.imageSource(u"Lightning Bolt"_s, u"M11"_s, u"146"_s).startsWith(u"file:"_s));

    catalog.setCardArtProvider(u"mtgch"_s);
    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }});
    QCOMPARE(cacheSpy.count(), 3);
    QCOMPARE(network.requestedUrls.size(), 2);
}

void TestCardCatalog::automaticProviderUsesLanguagePriority() const
{
    QTemporaryDir chineseStorage;
    QVERIFY(chineseStorage.isValid());
    FakeNetworkAccessManager chineseNetwork;
    CardCatalog chineseCatalog(chineseStorage.path(), &chineseNetwork);
    chineseCatalog.setLanguage(u"zh"_s);
    QCOMPARE(chineseCatalog.cardArtProvider(), u"auto"_s);
    QSignalSpy chineseSpy(&chineseCatalog, &CardCatalog::cardCacheFinished);
    chineseCatalog.cacheCards({QVariantMap{{u"name"_s, u"Lightning Bolt"_s},
                                           {u"setCode"_s, u"M11"_s},
                                           {u"collectorNumber"_s, u"146"_s}}});
    QTRY_COMPARE_WITH_TIMEOUT(chineseSpy.count(), 1, 2'000);
    QCOMPARE(chineseNetwork.requestedUrls.constFirst().host(), u"mtgch.com"_s);

    QTemporaryDir englishStorage;
    QVERIFY(englishStorage.isValid());
    FakeNetworkAccessManager englishNetwork;
    CardCatalog englishCatalog(englishStorage.path(), &englishNetwork);
    QSignalSpy englishSpy(&englishCatalog, &CardCatalog::cardCacheFinished);
    englishCatalog.cacheCards({QVariantMap{{u"name"_s, u"Lightning Bolt"_s},
                                           {u"setCode"_s, u"M11"_s},
                                           {u"collectorNumber"_s, u"146"_s}}});
    QTRY_COMPARE_WITH_TIMEOUT(englishSpy.count(), 1, 2'000);
    QCOMPARE(englishNetwork.requestedUrls.constFirst().host(), u"api.scryfall.com"_s);
}

void TestCardCatalog::prefersMtgchBeforeScryfallFallback() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"zh"_s);
    catalog.setCardArtProvider(u"mtgch"_s);
    QCOMPARE(catalog.cardArtProvider(), u"mtgch"_s);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);

    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }});

    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 2'000);
    QVERIFY(cacheSpy.first().at(3).toBool());
    QCOMPARE(network.requestedUrls.size(), 2);
    QCOMPARE(network.requestedUrls.at(0).host(), u"mtgch.com"_s);
    QCOMPARE(network.requestedUrls.at(1), QUrl(u"https://images.test/bolt.png"_s));

    QTemporaryDir fallbackStorage;
    QVERIFY(fallbackStorage.isValid());
    FakeNetworkAccessManager fallbackNetwork;
    fallbackNetwork.missMtgchRequests = true;
    CardCatalog fallbackCatalog(fallbackStorage.path(), &fallbackNetwork);
    fallbackCatalog.setLanguage(u"zh"_s);
    fallbackCatalog.setCardArtProvider(u"mtgch"_s);
    QSignalSpy fallbackSpy(&fallbackCatalog, &CardCatalog::cardCacheFinished);
    fallbackCatalog.cacheCards({QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }});

    QTRY_COMPARE_WITH_TIMEOUT(fallbackSpy.count(), 1, 2'000);
    QVERIFY(fallbackSpy.first().at(3).toBool());
    QVERIFY(fallbackNetwork.requestedUrls.size() >= 3);
    QCOMPARE(fallbackNetwork.requestedUrls.at(0).host(), u"mtgch.com"_s);
    QCOMPARE(fallbackNetwork.requestedUrls.at(1).host(), u"api.scryfall.com"_s);
}

void TestCardCatalog::prefersMtgchForEnglishArt() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setCardArtProvider(u"mtgch"_s);
    QSignalSpy availableSpy(&catalog, &CardCatalog::cardAvailable);

    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }});

    QTRY_COMPARE_WITH_TIMEOUT(availableSpy.count(), 1, 2'000);
    QCOMPARE(network.requestedUrls.size(), 2);
    QCOMPARE(network.requestedUrls.at(0).host(), u"mtgch.com"_s);
    QCOMPARE(network.requestedUrls.at(1), QUrl(u"https://images.test/bolt-en.png"_s));
    QCOMPARE(availableSpy.first().at(1).toString(), u"Lightning Bolt"_s);
}

void TestCardCatalog::positiveCacheHitDoesNotBumpImageRevision() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"zh"_s);
    QSignalSpy availableSpy(&catalog, &CardCatalog::cardAvailable);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);
    QSignalSpy revisionSpy(&catalog, &CardCatalog::imageRevisionChanged);
    const QVariantList request{QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }};

    catalog.cacheCards(request);
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 2'000);
    QVERIFY(cacheSpy.first().at(3).toBool());
    QCOMPARE(availableSpy.count(), 1);
    const int revisionAfterDownload = catalog.imageRevision();
    QVERIFY(revisionAfterDownload > 0);
    const int revisionSignalsAfterDownload = revisionSpy.count();
    QVERIFY(revisionSignalsAfterDownload > 0);

    catalog.cacheCards(request);
    QCOMPARE(cacheSpy.count(), 2);
    QVERIFY(cacheSpy.at(1).at(3).toBool());
    QCOMPARE(cacheSpy.at(1).at(0).toString(), u"Lightning Bolt"_s);
    QCOMPARE(cacheSpy.at(1).at(1).toString(), u"M11"_s);
    QCOMPARE(cacheSpy.at(1).at(2).toString(), u"146"_s);
    QCOMPARE(availableSpy.count(), 2);
    QCOMPARE(catalog.imageRevision(), revisionAfterDownload);
    QCOMPARE(revisionSpy.count(), revisionSignalsAfterDownload);
    QCOMPARE(network.requestedUrls.size(), 2);
}

void TestCardCatalog::setLanguageBumpsImageRevision() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    QCOMPARE(catalog.language(), u"en"_s);
    QSignalSpy revisionSpy(&catalog, &CardCatalog::imageRevisionChanged);
    const int initialRevision = catalog.imageRevision();

    catalog.setLanguage(u"zh"_s);

    QCOMPARE(catalog.language(), u"zh"_s);
    QCOMPARE(catalog.imageRevision(), initialRevision + 1);
    QCOMPARE(revisionSpy.count(), 1);

    catalog.setLanguage(u"zh"_s);
    QCOMPARE(catalog.imageRevision(), initialRevision + 1);
    QCOMPARE(revisionSpy.count(), 1);

    catalog.setLanguage(u"en"_s);
    QCOMPARE(catalog.language(), u"en"_s);
    QCOMPARE(catalog.imageRevision(), initialRevision + 2);
    QCOMPARE(revisionSpy.count(), 2);
}

void TestCardCatalog::providerFallbackSurvivesDisabledLocalReuse() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString imageRoot = storage.filePath(u"images"_s);
    QVERIFY(QDir().mkpath(imageRoot));
    const QString providerPath = QDir(imageRoot).filePath(u"provider.jpg"_s);
    const QString localReusePath = QDir(imageRoot).filePath(u"local-reuse.jpg"_s);
    for (const QString &path : {providerPath, localReusePath}) {
        QFile image(path);
        QVERIFY(image.open(QIODevice::WriteOnly));
        QCOMPARE(image.write("cached image"), 12);
    }

    const auto cachedRecord = [](const QString &name, const QString &path, bool reusesLocalArt) {
        return QJsonObject{
            {u"requestedName"_s, name},
            {u"name"_s, name},
            {u"setCode"_s, u"TST"_s},
            {u"collectorNumber"_s, u"1"_s},
            {u"imagePath"_s, path},
            {u"imageLanguage"_s, u"zh"_s},
            {u"resolutionVersion"_s, kCardResolutionVersion},
            {u"usesSubstituteArt"_s, true},
            {u"reusesLocalArt"_s, reusesLocalArt},
        };
    };
    const QJsonObject cacheRoot{
        {u"version"_s, kCardResolutionVersion},
        {u"negativeVersion"_s, kNegativeCacheVersion},
        {u"positive"_s,
         QJsonObject{
             {u"zh|provider fallback|TST|1"_s,
              cachedRecord(u"Provider Fallback"_s, providerPath, false)},
             {u"zh|local reuse|TST|1"_s, cachedRecord(u"Local Reuse"_s, localReusePath, true)},
         }},
        {u"negative"_s, QJsonObject{}},
    };
    QFile cacheFile(storage.filePath(u"card-cache.json"_s));
    QVERIFY(cacheFile.open(QIODevice::WriteOnly));
    const QByteArray cacheData = QJsonDocument(cacheRoot).toJson(QJsonDocument::Compact);
    QCOMPARE(cacheFile.write(cacheData), cacheData.size());
    cacheFile.close();

    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"zh"_s);
    catalog.setReuseLocalCardArt(false);
    QVERIFY(catalog.imageSource(u"Provider Fallback"_s, u"TST"_s, u"1"_s).startsWith(u"file:"_s));
    QVERIFY(catalog.imageSource(u"Local Reuse"_s, u"TST"_s, u"1"_s).isEmpty());

    catalog.setReuseLocalCardArt(true);
    QVERIFY(catalog.imageSource(u"Local Reuse"_s, u"TST"_s, u"1"_s).startsWith(u"file:"_s));
}

void TestCardCatalog::migratesUsablePreviousPolicyCache() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString imageRoot = storage.filePath(u"images"_s);
    QVERIFY(QDir().mkpath(imageRoot));
    const QString imagePath = QDir(imageRoot).filePath(u"legacy.jpg"_s);
    QFile image(imagePath);
    QVERIFY(image.open(QIODevice::WriteOnly));
    QCOMPARE(image.write("cached image"), 12);
    image.close();

    const QString connectionName = u"card-catalog-cache-migration"_s;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(storage.filePath(u"cards.sqlite"_s));
        QVERIFY2(database.open(), qPrintable(database.lastError().text()));
        QSqlQuery query(database);
        QVERIFY(
            query.exec(u"CREATE TABLE cards ("
                       "oracle_id TEXT, set_code TEXT, collector_number TEXT, "
                       "illustration_id TEXT, image_url TEXT, image_status TEXT, lang TEXT)"_s));
        QVERIFY(query.exec(u"INSERT INTO cards VALUES ("
                           "'bolt-oracle', 'M11', '146', 'bolt-art', "
                           "'https://cards.scryfall.io/normal/bolt.jpg', "
                           "'highres_scan', 'en')"_s));
        database.close();
    }
    QSqlDatabase::removeDatabase(connectionName);

    const QJsonObject record{
        {u"requestedName"_s, u"Lightning Bolt"_s},
        {u"name"_s, u"Lightning Bolt"_s},
        {u"oracleId"_s, u"bolt-oracle"_s},
        {u"localizedName"_s, u"Lightning Bolt"_s},
        {u"typeLine"_s, u"Instant"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
        {u"illustrationId"_s, u"bolt-art"_s},
        {u"imageUrl"_s, u"https://cards.scryfall.io/normal/bolt.jpg"_s},
        {u"imagePath"_s, imagePath},
        {u"imageLanguage"_s, u"en"_s},
        {u"resolutionVersion"_s, 5},
        {u"usesSubstituteArt"_s, true},
    };
    QFile cacheFile(storage.filePath(u"card-cache.json"_s));
    QVERIFY(cacheFile.open(QIODevice::WriteOnly));
    const QJsonObject cacheRoot{
        {u"version"_s, 5},
        {u"negativeVersion"_s, 2},
        {u"positive"_s, QJsonObject{{u"en|lightning bolt"_s, record}}},
        {u"negative"_s, QJsonObject{}},
    };
    const QByteArray cacheData = QJsonDocument(cacheRoot).toJson(QJsonDocument::Compact);
    QCOMPARE(cacheFile.write(cacheData), cacheData.size());
    cacheFile.close();

    FakeNetworkAccessManager network;
    network.forbidScryfallRequests = true;
    CardCatalog catalog(storage.path(), &network);
    catalog.setReuseLocalCardArt(false);
    QSignalSpy availableSpy(&catalog, &CardCatalog::cardAvailable);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);
    bool eventLoopYielded = false;
    QTimer::singleShot(0, &catalog, [&eventLoopYielded]() { eventLoopYielded = true; });
    catalog.hydrateCachedCards({
        QVariantMap{
            {u"name"_s, u"Lightning Bolt"_s},
        },
        QVariantMap{
            {u"name"_s, u"Not Cached"_s},
            {u"setCode"_s, u"TST"_s},
            {u"collectorNumber"_s, u"1"_s},
        },
    });

    QCOMPARE(cacheSpy.count(), 0);
    QCOMPARE(availableSpy.count(), 0);
    QTRY_VERIFY_WITH_TIMEOUT(eventLoopYielded, 1'000);
    QCOMPARE(availableSpy.count(), 0);
    QTRY_COMPARE_WITH_TIMEOUT(availableSpy.count(), 1, 2'000);
    QCOMPARE(network.requestedUrls.size(), 0);

    const auto savedCache = [&storage]() {
        QFile savedFile(storage.filePath(u"card-cache.json"_s));
        if (!savedFile.open(QIODevice::ReadOnly))
            return QJsonObject{};
        return QJsonDocument::fromJson(savedFile.readAll()).object();
    };
    QTRY_COMPARE_WITH_TIMEOUT(savedCache().value(u"version"_s).toInt(), 6, 2'000);
    const QJsonObject saved = savedCache();
    QCOMPARE(saved.value(u"positive"_s)
                 .toObject()
                 .value(u"en|lightning bolt"_s)
                 .toObject()
                 .value(u"resolutionVersion"_s)
                 .toInt(),
             6);
}

void TestCardCatalog::resolvedPrintingAliasBumpsImageRevision() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"zh"_s);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);
    QSignalSpy revisionSpy(&catalog, &CardCatalog::imageRevisionChanged);

    catalog.cacheCards({QVariantMap{{u"name"_s, u"Lightning Bolt"_s}}});
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 2'000);
    QVERIFY(cacheSpy.first().at(3).toBool());
    const int revisionAfterNameOnly = catalog.imageRevision();
    QVERIFY(revisionAfterNameOnly > 0);
    const int revisionSignalsAfterNameOnly = revisionSpy.count();
    const qsizetype initialRequests = network.requestedUrls.size();

    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }});
    QCOMPARE(cacheSpy.count(), 2);
    QVERIFY(cacheSpy.at(1).at(3).toBool());
    QCOMPARE(catalog.imageRevision(), revisionAfterNameOnly + 1);
    QCOMPARE(revisionSpy.count(), revisionSignalsAfterNameOnly + 1);
    QCOMPARE(network.requestedUrls.size(), initialRequests);
}

void TestCardCatalog::incrementalCacheCoalescesDuplicateRequests() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);
    const QVariantList request{QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }};

    catalog.cacheCardsIncrementally(request);
    catalog.cacheCardsIncrementally(request);

    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 2'000);
    QVERIFY(cacheSpy.first().at(3).toBool());
    QCOMPARE(network.requestedUrls.size(), 2);
}

void TestCardCatalog::exactArtRequestDoesNotCoalesceWithNormalRequest() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"zh"_s);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);
    const QVariantMap printing{
        {u"name"_s, u"Wear // Tear"_s},
        {u"setCode"_s, u"CMM"_s},
        {u"collectorNumber"_s, u"1"_s},
    };

    catalog.cacheCards({printing});
    QVariantMap exactPrinting = printing;
    exactPrinting.insert(u"exactArt"_s, true);
    catalog.cacheCards({exactPrinting});

    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 2, 3'000);
    QVERIFY(cacheSpy.at(0).at(3).toBool());
    QVERIFY(cacheSpy.at(1).at(3).toBool());
}

void TestCardCatalog::exactArtUsesSamePrintingProviderFallback() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    network.missFirstScryfallRequest = true;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"zh"_s);
    catalog.setCardArtProvider(u"scryfall"_s);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);

    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Wear // Tear"_s},
        {u"setCode"_s, u"CMM"_s},
        {u"collectorNumber"_s, u"1"_s},
        {u"exactArt"_s, true},
    }});

    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 3'000);
    QVERIFY(cacheSpy.first().at(3).toBool());
    QCOMPARE(network.requestedUrls.size(), 3);
    QCOMPARE(network.requestedUrls.at(0).path(), u"/cards/cmm/1/zhs"_s);
    QCOMPARE(network.requestedUrls.at(1).host(), u"mtgch.com"_s);
    QVERIFY(std::none_of(network.requestedUrls.cbegin(), network.requestedUrls.cend(),
                         [](const QUrl &url) { return url.path() == u"/cards/search"_s; }));
    QVERIFY(
        catalog.printingImageSource(u"Wear // Tear"_s, u"CMM"_s, u"1"_s).startsWith(u"file:"_s));
}

void TestCardCatalog::reusesNameOnlyCacheForResolvedPrinting() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"zh"_s);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);

    // Deck import starts with a name-only identity. Resolution adds the exact
    // printing to the deck while retaining the original name-only cache key.
    catalog.cacheCards({QVariantMap{{u"name"_s, u"Lightning Bolt"_s}}});
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 2'000);
    QVERIFY(cacheSpy.first().at(3).toBool());
    const qsizetype initialRequests = network.requestedUrls.size();
    QVERIFY(initialRequests > 0);

    // Match prefetch sends that resolved printing identity. It must alias the
    // existing record and image without issuing metadata or image requests.
    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }});
    QCOMPARE(cacheSpy.count(), 2);
    QVERIFY(cacheSpy.at(1).at(3).toBool());
    QCOMPARE(network.requestedUrls.size(), initialRequests);

    // The exact alias is persisted, so a fresh client process also hits it.
    FakeNetworkAccessManager restartedNetwork;
    CardCatalog restarted(storage.path(), &restartedNetwork);
    restarted.setLanguage(u"zh"_s);
    QSignalSpy restartedSpy(&restarted, &CardCatalog::cardCacheFinished);
    restarted.cacheCards({QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }});
    QCOMPARE(restartedSpy.count(), 1);
    QVERIFY(restartedSpy.first().at(3).toBool());
    QCOMPARE(restartedNetwork.requestedUrls.size(), 0);
}

void TestCardCatalog::reusesLocalArtAcrossPrintings() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);

    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Wear // Tear"_s},
        {u"setCode"_s, u"MOC"_s},
        {u"collectorNumber"_s, u"343"_s},
    }});
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 2'000);
    QCOMPARE(network.requestedUrls.size(), 2);

    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Wear // Tear"_s},
        {u"setCode"_s, u"CMM"_s},
        {u"collectorNumber"_s, u"1"_s},
    }});
    QCOMPARE(cacheSpy.count(), 2);
    QCOMPARE(network.requestedUrls.size(), 2);
    QVERIFY(catalog.imageSource(u"Wear // Tear"_s, u"CMM"_s, u"1"_s).startsWith(u"file:"_s));
    QVERIFY(catalog.printingImageSource(u"Wear // Tear"_s, u"CMM"_s, u"1"_s).isEmpty());
    catalog.setReuseLocalCardArt(false);
    QVERIFY(catalog.imageSource(u"Wear // Tear"_s, u"CMM"_s, u"1"_s).isEmpty());
    catalog.setReuseLocalCardArt(true);
    QVERIFY(catalog.imageSource(u"Wear // Tear"_s, u"CMM"_s, u"1"_s).startsWith(u"file:"_s));

    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Wear // Tear"_s},
        {u"setCode"_s, u"CMM"_s},
        {u"collectorNumber"_s, u"1"_s},
        {u"exactArt"_s, true},
    }});
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 3, 2'000);
    QCOMPARE(network.requestedUrls.size(), 3);
    QVERIFY(
        catalog.printingImageSource(u"Wear // Tear"_s, u"CMM"_s, u"1"_s).startsWith(u"file:"_s));

    catalog.setReuseLocalCardArt(false);
    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Wear // Tear"_s},
        {u"setCode"_s, u"2X2"_s},
        {u"collectorNumber"_s, u"2"_s},
    }});
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 4, 2'000);
    QCOMPARE(network.requestedUrls.size(), 4);
}

void TestCardCatalog::retriesTransientFailureForSplitCard() const
{
    QTest::failOnWarning(QRegularExpression(QStringLiteral("QIODevice::read.*device not open")));
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    network.failFirstScryfallRequest = true;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy availableSpy(&catalog, &CardCatalog::cardAvailable);

    catalog.cacheCards({QVariantMap{{u"name"_s, u"Wear // Tear"_s}}});

    QTRY_COMPARE_WITH_TIMEOUT(availableSpy.count(), 1, 5'000);
    QCOMPARE(network.scryfallRequestCount, 2);
    QCOMPARE(network.requestedUrls.size(), 3);
    QCOMPARE(QUrlQuery(network.requestedUrls.at(0)).queryItemValue(u"exact"_s), u"Wear // Tear"_s);
    const QList<QVariant> arguments = availableSpy.takeFirst();
    QCOMPARE(arguments.at(0).toString(), u"Wear // Tear"_s);
    QCOMPARE(arguments.at(1).toString(), u"Wear // Tear"_s);
    QVERIFY(QFileInfo::exists(arguments.at(3).toString()));
}

void TestCardCatalog::reportsImageDecoderFailure() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    network.invalidImageResponse = true;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);
    const QRegularExpression diagnostic(
        QStringLiteral("^Card image download failed .*payloadKind=html "
                       ".*payloadPreview=<html>not an image</html>.*$"));
    QTest::ignoreMessage(QtWarningMsg, diagnostic);

    catalog.cacheCards({QVariantMap{{u"name"_s, u"Wear // Tear"_s}}});

    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 3'000);
    QVERIFY(!cacheSpy.first().at(3).toBool());
    QVERIFY(catalog.lastError().contains(u"invalid image data"_s));
    QCOMPARE(std::count_if(network.requestedUrls.cbegin(), network.requestedUrls.cend(),
                           [](const QUrl &url) { return url.host() == u"images.test"_s; }),
             2);
}

void TestCardCatalog::clearsStaleErrorForNewCacheBatch() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    network.invalidImageResponse = true;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);
    const QRegularExpression diagnostic(
        QStringLiteral("^Card image download failed .*payloadKind=html "
                       ".*payloadPreview=<html>not an image</html>.*$"));
    QTest::ignoreMessage(QtWarningMsg, diagnostic);

    catalog.cacheCards({QVariantMap{{u"name"_s, u"Wear // Tear"_s}}});
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 3'000);
    QVERIFY(!catalog.lastError().isEmpty());

    catalog.cacheCards({QVariantMap{{u"name"_s, u"Wistfulness"_s}}});
    QCOMPARE(catalog.lastError(), QString{});
}

void TestCardCatalog::doesNotRetryForbiddenRequests() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    network.forbidScryfallRequests = true;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);

    catalog.cacheCards({QVariantMap{{u"name"_s, u"Wear // Tear"_s}}});

    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 2'000);
    QVERIFY(!cacheSpy.first().at(3).toBool());
    QCOMPARE(network.scryfallRequestCount, 1);
    QVERIFY(catalog.lastError().contains(u"HTTP 403"_s));
}

void TestCardCatalog::circuitBreaksUnavailableProvider() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    network.failAllScryfallRequests = true;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);

    catalog.cacheCards({
        QVariantMap{{u"name"_s, u"Wear // Tear"_s}},
        QVariantMap{{u"name"_s, u"Fire // Ice"_s}},
    });

    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 2, 4'000);
    QCOMPARE(network.scryfallRequestCount, 2);
    QVERIFY(!cacheSpy.at(0).at(3).toBool());
    QVERIFY(!cacheSpy.at(1).at(3).toBool());
    QVERIFY(catalog.lastError().contains(u"temporarily unavailable"_s));

    network.failAllScryfallRequests = false;
    catalog.retryCards({
        QVariantMap{{u"name"_s, u"Wear // Tear"_s}},
        QVariantMap{{u"name"_s, u"Fire // Ice"_s}},
    });

    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 4, 4'000);
    QCOMPARE(network.scryfallRequestCount, 4);
    QVERIFY(cacheSpy.at(2).at(3).toBool());
    QVERIFY(cacheSpy.at(3).at(3).toBool());
    QVERIFY(catalog.lastError().isEmpty());
}

void TestCardCatalog::retriesImageTimeoutThenSucceeds() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    network.serveScryfallCdnImages = true;
    network.scryfallImageTimeoutsRemaining = 1;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);
    catalog.cacheCards({QVariantMap{{u"name"_s, u"Wear // Tear"_s}}});

    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 3'000);
    QVERIFY(cacheSpy.first().at(3).toBool());
    QCOMPARE(network.scryfallImageRequestCount, 2);
}

void TestCardCatalog::imageTimeoutDoesNotCircuitBreakLaterCards() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    network.serveScryfallCdnImages = true;
    network.scryfallImageTimeoutsRemaining = 2;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);
    const QRegularExpression diagnostic(
        QStringLiteral("^Card image download failed .*networkError=4 .*bytes=0.*$"));
    QTest::ignoreMessage(QtWarningMsg, diagnostic);

    catalog.cacheCards({
        QVariantMap{
            {u"name"_s, u"Wear // Tear"_s},
            {u"setCode"_s, u"MOC"_s},
            {u"collectorNumber"_s, u"343"_s},
        },
        QVariantMap{
            {u"name"_s, u"Fire // Ice"_s},
            {u"setCode"_s, u"APC"_s},
            {u"collectorNumber"_s, u"97"_s},
        },
    });

    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 2, 5'000);
    QVERIFY(cacheSpy.at(0).at(3).toBool());
    QVERIFY(cacheSpy.at(1).at(3).toBool());
    QVERIFY(network.scryfallImageRequestCount >= 3);
}

void TestCardCatalog::remoteCloseDoesNotCircuitBreakLaterCards() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    network.serveScryfallCdnImages = true;
    network.scryfallImageRemoteClosesRemaining = 2;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);
    const QRegularExpression diagnostic(
        QStringLiteral("^Card image download failed .*networkError=2 .*bytes=0.*$"));
    QTest::ignoreMessage(QtWarningMsg, diagnostic);

    catalog.cacheCards({
        QVariantMap{
            {u"name"_s, u"Wear // Tear"_s},
            {u"setCode"_s, u"MOC"_s},
            {u"collectorNumber"_s, u"343"_s},
        },
        QVariantMap{
            {u"name"_s, u"Fire // Ice"_s},
            {u"setCode"_s, u"APC"_s},
            {u"collectorNumber"_s, u"97"_s},
        },
    });

    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 2, 5'000);
    QVERIFY(cacheSpy.at(0).at(3).toBool());
    QVERIFY(cacheSpy.at(1).at(3).toBool());
    QVERIFY(network.scryfallImageRequestCount >= 3);
}

void TestCardCatalog::manualRetryBypassesNegativeCache() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    network.missFirstScryfallRequest = true;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);
    const QVariantList cards{QVariantMap{{u"name"_s, u"Wear // Tear"_s}}};

    catalog.cacheCards(cards);
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 2'000);
    QVERIFY(!cacheSpy.at(0).at(3).toBool());
    QCOMPARE(network.scryfallRequestCount, 1);

    catalog.cacheCards(cards);
    QCOMPARE(cacheSpy.count(), 2);
    QCOMPARE(network.scryfallRequestCount, 1);

    catalog.retryCards(cards);
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 3, 2'000);
    QVERIFY(cacheSpy.at(2).at(3).toBool());
    QCOMPARE(network.scryfallRequestCount, 2);
    QVERIFY(catalog.lastError().isEmpty());
}

QTEST_GUILESS_MAIN(TestCardCatalog)
