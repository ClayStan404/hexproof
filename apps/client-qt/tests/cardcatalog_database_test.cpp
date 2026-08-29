// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "cardcatalog_test.h"

void TestCardCatalog::downloadsVerifiedOfficialDatabase() const
{
    QTemporaryDir files;
    QTemporaryDir storage;
    QVERIFY(files.isValid());
    QVERIFY(storage.isValid());
    const QString chinesePath = files.filePath(u"zhs.tar.gz"_s);
    const QString bulkPath = files.filePath(u"default.jsonl.gz"_s);
    const QString databasePath = files.filePath(u"cards.sqlite"_s);
    const QString compressedPath = files.filePath(u"cards.sqlite.gz"_s);

    const QByteArray aliases = QJsonDocument(QJsonObject{
                                                 {u"oracle_id"_s, u"oracle-bolt"_s},
                                                 {u"name"_s, u"Lightning Bolt"_s},
                                                 {u"translated_name"_s, u"闪电击"_s},
                                                 {u"translated_type"_s, u"瞬间"_s},
                                             })
                                   .toJson(QJsonDocument::Compact) +
                               '\n';
    QVERIFY(writeTestTarGzip(chinesePath, QByteArrayLiteral("./zhs_oracle.json"), aliases));
    const QJsonObject card{
        {u"id"_s, u"bolt-1"_s},
        {u"oracle_id"_s, u"oracle-bolt"_s},
        {u"name"_s, u"Lightning Bolt"_s},
        {u"type_line"_s, u"Instant"_s},
        {u"set"_s, u"M11"_s},
        {u"collector_number"_s, u"149"_s},
        {u"lang"_s, u"en"_s},
        {u"layout"_s, u"normal"_s},
        {u"image_uris"_s,
         QJsonObject{{u"normal"_s, u"https://cards.scryfall.io/normal/bolt.jpg"_s}}},
    };
    QVERIFY(writeTestGzip(bulkPath, QJsonDocument(card).toJson(QJsonDocument::Compact) +
                                        QByteArrayLiteral("\n")));
    const CardCatalog::ImportResult built =
        CardCatalog::importBulkFile(bulkPath, databasePath, u"default_cards"_s, chinesePath);
    QVERIFY2(built.ok, qPrintable(built.error));

    QFile database(databasePath);
    QVERIFY(database.open(QIODevice::ReadOnly));
    const QByteArray databaseBytes = database.readAll();
    database.close();
    QVERIFY(writeTestGzip(compressedPath, databaseBytes));
    QFile compressed(compressedPath);
    QVERIFY(compressed.open(QIODevice::ReadOnly));
    const QByteArray compressedBytes = compressed.readAll();

    CatalogDownloadNetworkAccessManager network;
    network.officialArchive = compressedBytes;
    network.officialManifest =
        QJsonDocument(
            QJsonObject{
                {u"format"_s, u"hexproof-card-database-v1"_s},
                {u"schemaVersion"_s, 10},
                {u"package"_s, u"default_cards"_s},
                {u"asset"_s, u"hexproof-default-cards.sqlite.gz"_s},
                {u"generatedAt"_s, built.generatedAt},
                {u"compressedSize"_s, compressedBytes.size()},
                {u"uncompressedSize"_s, databaseBytes.size()},
                {u"compressedSha256"_s,
                 QString::fromLatin1(
                     QCryptographicHash::hash(compressedBytes, QCryptographicHash::Sha256)
                         .toHex())},
                {u"sha256"_s,
                 QString::fromLatin1(
                     QCryptographicHash::hash(databaseBytes, QCryptographicHash::Sha256).toHex())},
            })
            .toJson(QJsonDocument::Compact);
    CardCatalog catalog(storage.path(), &network);

    catalog.downloadCatalog(u"default_cards"_s);

    QTRY_VERIFY_WITH_TIMEOUT(!catalog.busy(), 5'000);
    QVERIFY2(catalog.installed(), qPrintable(catalog.lastError()));
    QVERIFY(catalog.enhancedIndexInstalled());
    QCOMPARE(catalog.packageName(), u"default_cards"_s);
    QCOMPARE(catalog.installedCatalogVersion(), built.generatedAt);
    QCOMPARE(catalog.installedCatalogSchemaVersion(), 10);
    QCOMPARE(network.requestedUrls.size(), 2);
    QCOMPARE(network.requestedUrls.at(0).path(),
             u"/ClayStan404/hexproof/releases/download/card-data/"
             "card-database-manifest.json"_s);
    QCOMPARE(network.requestedUrls.at(1).path(),
             u"/ClayStan404/hexproof/releases/download/card-data/"
             "hexproof-default-cards.sqlite.gz"_s);
}

void TestCardCatalog::reportsCatalogReleaseVersions() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    CatalogDownloadNetworkAccessManager network;
    network.officialManifest =
        QJsonDocument(QJsonObject{
                          {u"format"_s, u"hexproof-card-database-v1"_s},
                          {u"schemaVersion"_s, 10},
                          {u"package"_s, u"default_cards"_s},
                          {u"asset"_s, u"hexproof-default-cards.sqlite.gz"_s},
                          {u"generatedAt"_s, u"2026-08-17T08:30:00Z"_s},
                          {u"compressedSize"_s, 1234},
                          {u"uncompressedSize"_s, 5678},
                          {u"compressedSha256"_s, QString(64, u'a')},
                          {u"sha256"_s, QString(64, u'b')},
                      })
            .toJson(QJsonDocument::Compact);
    CardCatalog catalog(storage.path(), &network);

    catalog.checkCatalogUpdate();

    QTRY_VERIFY_WITH_TIMEOUT(!catalog.checkingCatalogVersion(), 2'000);
    QVERIFY(catalog.latestCatalogKnown());
    QVERIFY(catalog.latestCatalogCompatible());
    QVERIFY(catalog.catalogUpdateAvailable());
    QCOMPARE(catalog.latestCatalogVersion(), u"2026-08-17T08:30:00Z"_s);
    QCOMPARE(catalog.latestCatalogSchemaVersion(), 10);
    QVERIFY(catalog.catalogVersionError().isEmpty());
    QCOMPARE(network.requestedUrls.size(), 1);
}

void TestCardCatalog::catalogAutomaticCheckRunsAtMostOncePerDay() const
{
    QSettings settings;
    settings.remove(u"updates/catalogLastCheckUtc"_s);
    settings.remove(u"updates/latestCatalogGeneratedAt"_s);
    settings.remove(u"updates/latestCatalogSchemaVersion"_s);
    settings.sync();

    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    CatalogDownloadNetworkAccessManager network;
    network.officialManifest =
        QJsonDocument(QJsonObject{
                          {u"format"_s, u"hexproof-card-database-v1"_s},
                          {u"schemaVersion"_s, 10},
                          {u"package"_s, u"default_cards"_s},
                          {u"asset"_s, u"hexproof-default-cards.sqlite.gz"_s},
                          {u"generatedAt"_s, u"2026-08-26T08:30:00Z"_s},
                          {u"compressedSize"_s, 1234},
                          {u"uncompressedSize"_s, 5678},
                          {u"compressedSha256"_s, QString(64, u'a')},
                          {u"sha256"_s, QString(64, u'b')},
                      })
            .toJson(QJsonDocument::Compact);
    CardCatalog catalog(storage.path(), &network);

    catalog.checkCatalogUpdateIfDue();
    QTRY_VERIFY_WITH_TIMEOUT(!catalog.checkingCatalogVersion(), 2'000);
    QCOMPARE(network.requestedUrls.size(), 1);

    network.requestedUrls.clear();
    CatalogDownloadNetworkAccessManager restartedNetwork;
    CardCatalog restarted(storage.path(), &restartedNetwork);
    restarted.checkCatalogUpdateIfDue();
    QTest::qWait(50);
    QCOMPARE(restartedNetwork.requestedUrls.size(), 0);
    QCOMPARE(restarted.latestCatalogVersion(), u"2026-08-26T08:30:00Z"_s);
    QCOMPARE(restarted.latestCatalogSchemaVersion(), 10);

    settings.remove(u"updates/catalogLastCheckUtc"_s);
    settings.remove(u"updates/latestCatalogGeneratedAt"_s);
    settings.remove(u"updates/latestCatalogSchemaVersion"_s);
}

void TestCardCatalog::doesNotBuildCatalogWhenOfficialPackageIsUnavailable() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    CatalogDownloadNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);

    catalog.downloadCatalog(u"default_cards"_s);

    QTRY_VERIFY_WITH_TIMEOUT(!catalog.busy(), 2'000);
    QVERIFY(!catalog.installed());
    QVERIFY(catalog.lastError().contains(u"official card database is unavailable"_s,
                                         Qt::CaseInsensitive));
    QCOMPARE(network.requestedUrls.size(), 1);
    QCOMPARE(network.requestedUrls.constFirst().path(),
             u"/ClayStan404/hexproof/releases/download/card-data/"
             "card-database-manifest.json"_s);
}

void TestCardCatalog::importsAndSearchesBulkData() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString sourcePath = storage.filePath(u"bulk.json"_s);
    const QString databasePath = storage.filePath(u"cards.sqlite"_s);

    const QJsonArray cards{
        QJsonObject{
            {u"id"_s, u"card-1"_s},
            {u"oracle_id"_s, u"oracle-1"_s},
            {u"name"_s, u"Lightning Bolt"_s},
            {u"printed_name"_s, u"闪电击"_s},
            {u"type_line"_s, u"Instant"_s},
            {u"set"_s, u"M11"_s},
            {u"collector_number"_s, u"149"_s},
            {u"lang"_s, u"en"_s},
            {u"color_identity"_s, QJsonArray{u"R"_s}},
            {u"cmc"_s, 1.0},
            {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://example.test/bolt.jpg"_s}}},
        },
        QJsonObject{
            {u"id"_s, u"card-2"_s},
            {u"oracle_id"_s, u"oracle-2"_s},
            {u"name"_s, u"Sol Ring"_s},
            {u"type_line"_s, u"Artifact"_s},
            {u"set"_s, u"CMM"_s},
            {u"collector_number"_s, u"396"_s},
            {u"lang"_s, u"en"_s},
            {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://example.test/ring.jpg"_s}}},
        },
        QJsonObject{
            {u"id"_s, u"card-3"_s},
            {u"oracle_id"_s, u"oracle-1"_s},
            {u"name"_s, u"Lightning Bolt"_s},
            {u"type_line"_s, u"Instant"_s},
            {u"set"_s, u"2X2"_s},
            {u"collector_number"_s, u"117"_s},
            {u"lang"_s, u"en"_s},
            {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://example.test/bolt-2x2.jpg"_s}}},
        },
        QJsonObject{
            {u"id"_s, u"card-4"_s},
            {u"oracle_id"_s, u"oracle-1"_s},
            {u"name"_s, u"Lightning Bolt"_s},
            {u"printed_name"_s, u"闪电击"_s},
            {u"type_line"_s, u"Instant"_s},
            {u"set"_s, u"M11"_s},
            {u"collector_number"_s, u"149"_s},
            {u"lang"_s, u"zhs"_s},
            {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://example.test/bolt-zhs.jpg"_s}}},
        },
        QJsonObject{
            {u"id"_s, u"token-1"_s},
            {u"oracle_id"_s, u"oracle-token-1"_s},
            {u"name"_s, u"Goblin"_s},
            {u"type_line"_s, u"Token Creature — Goblin"_s},
            {u"layout"_s, u"token"_s},
            {u"set"_s, u"TNEO"_s},
            {u"collector_number"_s, u"12"_s},
            {u"lang"_s, u"en"_s},
            {u"power"_s, u"1"_s},
            {u"toughness"_s, u"1"_s},
            {u"oracle_text"_s, u"Haste"_s},
            {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://example.test/goblin.jpg"_s}}},
        },
        QJsonObject{
            {u"id"_s, u"token-1-zhs"_s},
            {u"oracle_id"_s, u"oracle-token-1"_s},
            {u"name"_s, u"Goblin"_s},
            {u"printed_name"_s, u"地精"_s},
            {u"type_line"_s, u"衍生生物 — 地精"_s},
            {u"layout"_s, u"token"_s},
            {u"set"_s, u"TNEO"_s},
            {u"collector_number"_s, u"12"_s},
            {u"lang"_s, u"zhs"_s},
            {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://example.test/goblin-zhs.jpg"_s}}},
        },
        QJsonObject{
            {u"id"_s, u"card-5"_s},
            {u"oracle_id"_s, u"oracle-rider"_s},
            {u"name"_s, u"Murderous Rider // Swift End"_s},
            {u"type_line"_s, u"Creature — Zombie Knight // Instant — Adventure"_s},
            {u"layout"_s, u"adventure"_s},
            {u"set"_s, u"ELD"_s},
            {u"collector_number"_s, u"97"_s},
            {u"lang"_s, u"en"_s},
            {u"image_uris"_s,
             QJsonObject{{u"normal"_s, u"https://example.test/murderous-rider.jpg"_s}}},
        },
    };
    QFile source(sourcePath);
    QVERIFY(source.open(QIODevice::WriteOnly));
    QCOMPARE(source.write(QJsonDocument(cards).toJson(QJsonDocument::Compact)),
             QJsonDocument(cards).toJson(QJsonDocument::Compact).size());
    source.close();

    const CardCatalog::ImportResult imported =
        CardCatalog::importBulkFile(sourcePath, databasePath, u"default_cards"_s);
    QVERIFY2(imported.ok, qPrintable(imported.error));
    QCOMPARE(imported.cardCount, 7);
    QCOMPARE(imported.tokenCount, 1);
    QCOMPARE(imported.localizedPrintingCount, 2);

    CardCatalog catalog(storage.path());
    QVERIFY(catalog.installed());
    QCOMPARE(catalog.packageName(), u"default_cards"_s);
    QVERIFY(catalog.enhancedIndexInstalled());
    QVERIFY(catalog.tokenCatalogInstalled());
    QVERIFY(QFileInfo::exists(storage.filePath(u"catalog.json"_s)));
    catalog.search(u"light"_s);
    QTRY_COMPARE(catalog.searchResults().size(), 1);
    const QVariantMap result = catalog.searchResults().first().toMap();
    QCOMPARE(result.value(u"name"_s).toString(), u"Lightning Bolt"_s);
    QCOMPARE(result.value(u"typeLine"_s).toString(), u"Instant"_s);
    QCOMPARE(result.value(u"versionCount"_s).toInt(), 2);
    const QVariantList printings = catalog.printings(u"Lightning Bolt"_s);
    QCOMPARE(printings.size(), 2);
    QCOMPARE(printings.first().toMap().value(u"setCode"_s).toString(), u"2X2"_s);
    QCOMPARE(catalog.cardTypeLine(u"Lightning Bolt"_s, u"M11"_s, u"149"_s), u"Instant"_s);
    QCOMPARE(catalog.cardTypeLine(u"Murderous Rider"_s, {}, {}),
             u"Creature — Zombie Knight // Instant — Adventure"_s);
    QCOMPARE(catalog.cardTypeLine(u"Missing Card"_s, {}, {}), QString{});
    const QVariantList limitedCards = catalog.enrichLimitedCards(QVariantList{
        QVariantMap{{u"instanceId"_s, u"limited-1"_s},
                    {u"name"_s, u"Lightning Bolt"_s},
                    {u"setCode"_s, u"M11"_s},
                    {u"collectorNumber"_s, u"149"_s}},
        QVariantMap{{u"instanceId"_s, u"limited-missing"_s},
                    {u"name"_s, u"Missing Card"_s},
                    {u"setCode"_s, u"TST"_s},
                    {u"collectorNumber"_s, u"404"_s}},
    });
    QCOMPARE(limitedCards.size(), 2);
    const QVariantMap limitedBolt = limitedCards.first().toMap();
    QCOMPARE(limitedBolt.value(u"instanceId"_s).toString(), u"limited-1"_s);
    QCOMPARE(limitedBolt.value(u"typeLine"_s).toString(), u"Instant"_s);
    QCOMPARE(limitedBolt.value(u"colors"_s).toString(), u"R"_s);
    QCOMPARE(limitedBolt.value(u"manaValue"_s).toDouble(), 1.0);
    QVERIFY(limitedBolt.value(u"limitedMetadataResolved"_s).toBool());
    QVERIFY(!limitedCards.at(1).toMap().contains(u"limitedMetadataResolved"_s));
    QSignalSpy metadataSpy(&catalog, &CardCatalog::cardMetadataAvailable);
    catalog.enrichCardMetadata(QVariantList{
        QVariantMap{
            {u"name"_s, u"Lightning Bolt"_s},
            {u"setCode"_s, u"M11"_s},
            {u"collectorNumber"_s, u"149"_s},
        },
        QVariantMap{
            {u"name"_s, u"Lightning Bolt"_s},
            {u"setCode"_s, u"M11"_s},
            {u"collectorNumber"_s, u"149"_s},
        },
        QVariantMap{{u"name"_s, u"Missing Card"_s}},
    });
    catalog.enrichCardMetadata(QVariantList{QVariantMap{{u"name"_s, u"Murderous Rider"_s}}});
    QTRY_COMPARE(metadataSpy.count(), 1);
    QHash<QString, QString> typeLines;
    for (const QList<QVariant> &arguments : metadataSpy) {
        for (const QVariant &value : arguments.first().toList()) {
            const QVariantMap metadata = value.toMap();
            typeLines.insert(metadata.value(u"requestedName"_s).toString(),
                             metadata.value(u"typeLine"_s).toString());
        }
    }
    QCOMPARE(typeLines.size(), 2);
    QCOMPARE(typeLines.value(u"Lightning Bolt"_s), u"Instant"_s);
    QCOMPARE(typeLines.value(u"Murderous Rider"_s),
             u"Creature — Zombie Knight // Instant — Adventure"_s);
    QVERIFY(catalog.matchesCardQuery(u"Lightning Bolt"_s, u"M11"_s, u"149"_s, u"闪电击"_s));
    QVERIFY(catalog.matchesCardQuery(u"Lightning Bolt"_s, u"M11"_s, u"149"_s, u"Instant"_s));
    QVERIFY(catalog.matchesCardQuery(u"Lightning Bolt"_s, u"M11"_s, u"149"_s, u"瞬间"_s));
    QVERIFY(!catalog.matchesCardQuery(u"Lightning Bolt"_s, u"M11"_s, u"149"_s, u"生物"_s));

    catalog.importCatalogFile(QUrl::fromLocalFile(sourcePath), u"default_cards"_s);
    QTRY_VERIFY_WITH_TIMEOUT(!catalog.busy(), 10'000);
    QVERIFY2(catalog.installed(), qPrintable(catalog.lastError()));
    QCOMPARE(catalog.printings(u"Lightning Bolt"_s).size(), 2);

    catalog.setLanguage(u"zh"_s);
    catalog.search(u"闪电"_s);
    QTRY_COMPARE(catalog.searchResults().size(), 1);
    QTRY_COMPARE(catalog.searchResults().first().toMap().value(u"displayName"_s).toString(),
                 u"闪电击"_s);

    catalog.search(u"Lghtnng"_s);
    QTRY_COMPARE(catalog.searchResults().size(), 1);
    QCOMPARE(catalog.searchResults().first().toMap().value(u"name"_s).toString(),
             u"Lightning Bolt"_s);

    catalog.search({}, u"Artifact"_s);
    QTRY_COMPARE(catalog.searchResults().size(), 1);
    QCOMPARE(catalog.searchResults().first().toMap().value(u"name"_s).toString(), u"Sol Ring"_s);

    catalog.search(u"Lightning"_s, {}, u"2X2"_s, u"en"_s);
    QTRY_COMPARE(catalog.searchResults().size(), 1);
    QCOMPARE(catalog.searchResults().first().toMap().value(u"setCode"_s).toString(), u"2X2"_s);

    catalog.searchTokens(u"gob"_s);
    QTRY_COMPARE(catalog.tokenSearchResults().size(), 1);
    const QVariantMap token = catalog.tokenSearchResults().first().toMap();
    QCOMPARE(token.value(u"name"_s).toString(), u"Goblin"_s);
    QCOMPARE(token.value(u"setCode"_s).toString(), u"TNEO"_s);
    QCOMPARE(token.value(u"power"_s).toString(), u"1"_s);
    QCOMPARE(token.value(u"toughness"_s).toString(), u"1"_s);
    QCOMPARE(token.value(u"oracleText"_s).toString(), u"Haste"_s);

    QSignalSpy tokenMetadataSpy(&catalog, &CardCatalog::tokenMetadataAvailable);
    catalog.enrichTokens(QVariantList{QVariantMap{
        {u"name"_s, u"Goblin"_s},
        {u"setCode"_s, u"TNEO"_s},
        {u"collectorNumber"_s, u"12"_s},
    }});
    QTRY_COMPARE(tokenMetadataSpy.count(), 1);
    const QVariantList enrichedTokens = tokenMetadataSpy.first().first().toList();
    QCOMPARE(enrichedTokens.size(), 1);
    const QVariantMap enrichedToken = enrichedTokens.first().toMap();
    QCOMPARE(enrichedToken.value(u"requestedName"_s).toString(), u"Goblin"_s);
    QCOMPARE(enrichedToken.value(u"power"_s).toString(), u"1"_s);
    QCOMPARE(enrichedToken.value(u"toughness"_s).toString(), u"1"_s);
    QCOMPARE(enrichedToken.value(u"oracleText"_s).toString(), u"Haste"_s);

    catalog.setLanguage(u"zh"_s);
    catalog.searchTokens(u"地精"_s);
    QTRY_COMPARE(catalog.tokenSearchResults().size(), 1);
    QCOMPARE(catalog.tokenSearchResults().first().toMap().value(u"name"_s).toString(), u"Goblin"_s);
    QCOMPARE(catalog.tokenSearchResults().first().toMap().value(u"displayName"_s).toString(),
             u"地精"_s);
}

void TestCardCatalog::importsChineseNameIndex() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString sourcePath = storage.filePath(u"bulk.json"_s);
    const QString archivePath = storage.filePath(u"zhs.tar.gz"_s);
    const QString databasePath = storage.filePath(u"cards.sqlite"_s);

    const QStringList formats{
        u"alchemy"_s,     u"brawl"_s,     u"commander"_s, u"competitivebrawl"_s, u"duel"_s,
        u"future"_s,      u"gladiator"_s, u"historic"_s,  u"legacy"_s,           u"modern"_s,
        u"oathbreaker"_s, u"oldschool"_s, u"pauper"_s,    u"paupercommander"_s,  u"penny"_s,
        u"pioneer"_s,     u"predh"_s,     u"premodern"_s, u"standard"_s,         u"standardbrawl"_s,
        u"timeless"_s,    u"tlr"_s,       u"vintage"_s,
    };
    QJsonObject legalFormats;
    for (const QString &format : formats)
        legalFormats.insert(format, u"legal"_s);
    legalFormats.insert(u"vintage"_s, u"restricted"_s);
    const QJsonArray cards{
        QJsonObject{
            {u"id"_s, u"bolt-1"_s},
            {u"oracle_id"_s, u"oracle-bolt"_s},
            {u"name"_s, u"Lightning Bolt"_s},
            {u"type_line"_s, u"Instant"_s},
            {u"set"_s, u"M11"_s},
            {u"collector_number"_s, u"149"_s},
            {u"lang"_s, u"en"_s},
            {u"color_identity"_s, QJsonArray{u"R"_s}},
            {u"rarity"_s, u"common"_s},
            {u"legalities"_s, legalFormats},
        },
        QJsonObject{
            {u"id"_s, u"bolt-2"_s},
            {u"oracle_id"_s, u"oracle-bolt"_s},
            {u"name"_s, u"Lightning Bolt"_s},
            {u"type_line"_s, u"Instant"_s},
            {u"set"_s, u"2X2"_s},
            {u"collector_number"_s, u"117"_s},
            {u"lang"_s, u"en"_s},
            {u"color_identity"_s, QJsonArray{u"R"_s}},
            {u"rarity"_s, u"uncommon"_s},
            {u"legalities"_s, legalFormats},
        },
        QJsonObject{
            {u"id"_s, u"ring-1"_s},
            {u"oracle_id"_s, u"oracle-ring"_s},
            {u"name"_s, u"Sol Ring"_s},
            {u"type_line"_s, u"Artifact"_s},
            {u"set"_s, u"CMM"_s},
            {u"collector_number"_s, u"396"_s},
            {u"lang"_s, u"en"_s},
            {u"color_identity"_s, QJsonArray{}},
            {u"rarity"_s, u"uncommon"_s},
            {u"legalities"_s,
             QJsonObject{{u"modern"_s, u"not_legal"_s}, {u"commander"_s, u"legal"_s}}},
        },
        QJsonObject{
            {u"id"_s, u"wear-1"_s},
            {u"oracle_id"_s, u"oracle-wear"_s},
            {u"name"_s, u"Wear // Tear"_s},
            {u"type_line"_s, u"Instant // Instant"_s},
            {u"set"_s, u"DGM"_s},
            {u"collector_number"_s, u"135"_s},
            {u"lang"_s, u"en"_s},
            {u"color_identity"_s, QJsonArray{u"R"_s, u"W"_s}},
            {u"rarity"_s, u"uncommon"_s},
            {u"legalities"_s, legalFormats},
        },
    };
    QFile source(sourcePath);
    QVERIFY(source.open(QIODevice::WriteOnly));
    const QByteArray bulk = QJsonDocument(cards).toJson(QJsonDocument::Compact);
    QCOMPARE(source.write(bulk), bulk.size());
    source.close();

    QByteArray aliases;
    const QList<QJsonObject> aliasRows{
        QJsonObject{{u"oracle_id"_s, u"oracle-bolt"_s},
                    {u"name"_s, u"Lightning Bolt"_s},
                    {u"translated_name"_s, u"闪电击"_s},
                    {u"translated_type"_s, u"瞬间"_s},
                    {u"former_names"_s, QJsonArray{u"闪电箭"_s}}},
        QJsonObject{{u"oracle_id"_s, u"oracle-wear"_s},
                    {u"name"_s, u"Wear"_s},
                    {u"translated_name"_s, u"损耗"_s},
                    {u"translated_type"_s, u"瞬间"_s}},
        QJsonObject{{u"oracle_id"_s, u"oracle-wear"_s},
                    {u"name"_s, u"Tear"_s},
                    {u"translated_name"_s, u"穿破"_s},
                    {u"translated_type"_s, u"瞬间"_s}},
    };
    for (qsizetype index = 0; index < aliasRows.size(); ++index) {
        QJsonObject row = aliasRows.at(index);
        if (index == 0)
            row.insert(u"oracle_text"_s, u"It gains \"A quoted ability.\""_s);
        QByteArray encoded = QJsonDocument(row).toJson(QJsonDocument::Compact);
        if (index == 0) {
            encoded.replace(QByteArrayLiteral("\\\""), QByteArrayLiteral("\\\\\""));
            QVERIFY(encoded.contains(QByteArrayLiteral("\\\\\"A quoted ability")));
        }
        aliases += encoded + '\n';
    }
    QVERIFY(writeTestTarGzip(archivePath, QByteArrayLiteral("./zhs_oracle.json"), aliases));

    const CardCatalog::ImportResult imported =
        CardCatalog::importBulkFile(sourcePath, databasePath, u"default_cards"_s, archivePath);
    QVERIFY2(imported.ok, qPrintable(imported.error));
    QCOMPARE(imported.cardCount, 4);
    QCOMPARE(imported.aliasCount, 4);

    CardCatalog catalog(storage.path());
    catalog.setLanguage(u"zh"_s);
    catalog.search(u"闪电"_s);
    QTRY_COMPARE(catalog.searchResults().size(), 1);
    QCOMPARE(catalog.searchResults().first().toMap().value(u"displayName"_s).toString(),
             u"闪电击"_s);
    QCOMPARE(catalog.searchResults().first().toMap().value(u"typeLine"_s).toString(), u"瞬间"_s);
    QCOMPARE(catalog.cardTypeLine(u"Lightning Bolt"_s, u"M11"_s, u"149"_s), u"瞬间"_s);

    catalog.search(u"闪击"_s);
    QTRY_COMPARE(catalog.searchResults().size(), 1);
    catalog.search(u"闪电箭"_s);
    QTRY_COMPARE(catalog.searchResults().size(), 1);

    catalog.search(u"损耗"_s);
    QTRY_COMPARE(catalog.searchResults().size(), 1);
    QCOMPARE(catalog.searchResults().first().toMap().value(u"name"_s).toString(),
             u"Wear // Tear"_s);
    QCOMPARE(catalog.searchResults().first().toMap().value(u"displayName"_s).toString(),
             u"损耗 // 穿破"_s);

    for (const QString &format : formats) {
        catalog.search({}, {}, {}, {}, u"R"_s, u"common"_s, format);
        QTRY_COMPARE(catalog.searchResults().size(), 1);
        QCOMPARE(catalog.searchResults().first().toMap().value(u"name"_s).toString(),
                 u"Lightning Bolt"_s);
    }

    catalog.search({}, {}, {}, {}, u"M"_s);
    QTRY_COMPARE(catalog.searchResults().size(), 1);
    QCOMPARE(catalog.searchResults().first().toMap().value(u"name"_s).toString(),
             u"Wear // Tear"_s);
}

void TestCardCatalog::doesNotCacheBusyCatalogFilterMisses() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString sourcePath = storage.filePath(u"bulk.json"_s);
    const QString databasePath = storage.filePath(u"cards.sqlite"_s);
    const QString brokenPath = storage.filePath(u"broken.json"_s);

    const QJsonArray cards{
        QJsonObject{
            {u"id"_s, u"card-1"_s},
            {u"oracle_id"_s, u"oracle-1"_s},
            {u"name"_s, u"Lightning Bolt"_s},
            {u"printed_name"_s, u"闪电击"_s},
            {u"type_line"_s, u"Instant"_s},
            {u"set"_s, u"M11"_s},
            {u"collector_number"_s, u"149"_s},
            {u"lang"_s, u"zhs"_s},
            {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://example.test/bolt.jpg"_s}}},
        },
    };
    QFile source(sourcePath);
    QVERIFY(source.open(QIODevice::WriteOnly));
    QCOMPARE(source.write(QJsonDocument(cards).toJson(QJsonDocument::Compact)),
             QJsonDocument(cards).toJson(QJsonDocument::Compact).size());
    source.close();
    QVERIFY2(CardCatalog::importBulkFile(sourcePath, databasePath, u"default_cards"_s).ok,
             "test catalog import failed");

    QFile broken(brokenPath);
    QVERIFY(broken.open(QIODevice::WriteOnly));
    QCOMPARE(broken.write("{"), 1);
    broken.close();

    CardCatalog catalog(storage.path());
    QVERIFY(catalog.installed());
    QCOMPARE(catalog.cardTypeLine(u"Lightning Bolt"_s, u"M11"_s, u"149"_s), u"Instant"_s);

    catalog.importCatalogFile(QUrl::fromLocalFile(brokenPath), u"default_cards"_s);
    QVERIFY(catalog.busy());
    QVERIFY(!catalog.matchesCardQuery(u"Lightning Bolt"_s, u"M11"_s, u"149"_s, u"瞬间"_s));
    QTRY_VERIFY_WITH_TIMEOUT(!catalog.busy(), 10'000);
    QVERIFY(catalog.installed());
    QVERIFY(catalog.matchesCardQuery(u"Lightning Bolt"_s, u"M11"_s, u"149"_s, u"瞬间"_s));
}

void TestCardCatalog::hydratesLookupsWhenCatalogChangedFires() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString sourcePath = storage.filePath(u"bulk.json"_s);
    const QJsonArray cards{
        QJsonObject{
            {u"id"_s, u"card-1"_s},
            {u"oracle_id"_s, u"oracle-1"_s},
            {u"name"_s, u"Lightning Bolt"_s},
            {u"type_line"_s, u"Instant"_s},
            {u"set"_s, u"M11"_s},
            {u"collector_number"_s, u"149"_s},
            {u"lang"_s, u"en"_s},
            {u"layout"_s, u"normal"_s},
            {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://example.test/bolt.jpg"_s}}},
        },
    };
    QFile source(sourcePath);
    QVERIFY(source.open(QIODevice::WriteOnly));
    QCOMPARE(source.write(QJsonDocument(cards).toJson(QJsonDocument::Compact)),
             QJsonDocument(cards).toJson(QJsonDocument::Compact).size());
    source.close();

    CardCatalog catalog(storage.path());
    QVERIFY(!catalog.installed());

    bool sawCatalogChanged = false;
    bool busyDuringCatalogChanged = true;
    QString typeLineDuringCatalogChanged;
    QObject::connect(&catalog, &CardCatalog::catalogChanged, &catalog, [&]() {
        sawCatalogChanged = true;
        busyDuringCatalogChanged = catalog.busy();
        typeLineDuringCatalogChanged =
            catalog.cardTypeLine(u"Lightning Bolt"_s, u"M11"_s, u"149"_s);
    });

    catalog.importCatalogFile(QUrl::fromLocalFile(sourcePath), u"default_cards"_s);
    QTRY_VERIFY_WITH_TIMEOUT(!catalog.busy(), 10'000);
    QVERIFY2(catalog.installed(), qPrintable(catalog.lastError()));
    QVERIFY(sawCatalogChanged);
    QVERIFY(!busyDuringCatalogChanged);
    QCOMPARE(typeLineDuringCatalogChanged, u"Instant"_s);
}

namespace {

QString uniqueSqlName(const char *prefix)
{
    static int serial = 0;
    return QString::fromLatin1(prefix) + QString::number(++serial);
}

bool writeBoltCatalog(const QString &storagePath)
{
    const QString sourcePath = storagePath + QStringLiteral("/bulk.json");
    const QString databasePath = storagePath + QStringLiteral("/cards.sqlite");
    const QJsonArray cards{
        QJsonObject{
            {u"id"_s, u"card-1"_s},
            {u"oracle_id"_s, u"oracle-1"_s},
            {u"name"_s, u"Lightning Bolt"_s},
            {u"type_line"_s, u"Instant"_s},
            {u"set"_s, u"M11"_s},
            {u"collector_number"_s, u"149"_s},
            {u"lang"_s, u"en"_s},
            {u"layout"_s, u"normal"_s},
            {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://example.test/bolt.jpg"_s}}},
        },
    };
    QFile source(sourcePath);
    if (!source.open(QIODevice::WriteOnly))
        return false;
    const QByteArray payload = QJsonDocument(cards).toJson(QJsonDocument::Compact);
    if (source.write(payload) != payload.size())
        return false;
    source.close();
    return CardCatalog::importBulkFile(sourcePath, databasePath, u"default_cards"_s).ok;
}

const auto kCardsTableSql = u"CREATE TABLE cards ("
                            "id TEXT PRIMARY KEY, oracle_id TEXT, name TEXT NOT NULL, "
                            "printed_name TEXT, type_line TEXT, set_code TEXT, "
                            "collector_number TEXT, image_url TEXT, lang TEXT, colors TEXT, "
                            "mana_value REAL, rarity TEXT, layout TEXT, "
                            "legal_formats TEXT NOT NULL DEFAULT '', illustration_id TEXT, "
                            "released_at TEXT, digital INTEGER NOT NULL DEFAULT 0, "
                            "power TEXT, toughness TEXT, oracle_text TEXT, "
                            "legality_statuses TEXT NOT NULL DEFAULT '')"_s;

bool writeBoltAndTokenCatalog(const QString &storagePath)
{
    const QString sourcePath = storagePath + QStringLiteral("/bulk.json");
    const QString databasePath = storagePath + QStringLiteral("/cards.sqlite");
    const QJsonArray cards{
        QJsonObject{
            {u"id"_s, u"card-1"_s},
            {u"oracle_id"_s, u"oracle-1"_s},
            {u"name"_s, u"Lightning Bolt"_s},
            {u"type_line"_s, u"Instant"_s},
            {u"set"_s, u"M11"_s},
            {u"collector_number"_s, u"149"_s},
            {u"lang"_s, u"en"_s},
            {u"layout"_s, u"normal"_s},
            {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://example.test/bolt.jpg"_s}}},
        },
        QJsonObject{
            {u"id"_s, u"token-1"_s},
            {u"oracle_id"_s, u"oracle-token-1"_s},
            {u"name"_s, u"Goblin"_s},
            {u"type_line"_s, u"Token Creature — Goblin"_s},
            {u"layout"_s, u"token"_s},
            {u"set"_s, u"TNEO"_s},
            {u"collector_number"_s, u"12"_s},
            {u"lang"_s, u"en"_s},
            {u"power"_s, u"1"_s},
            {u"toughness"_s, u"1"_s},
            {u"oracle_text"_s, u"Haste"_s},
            {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://example.test/goblin.jpg"_s}}},
        },
    };
    QFile source(sourcePath);
    if (!source.open(QIODevice::WriteOnly))
        return false;
    const QByteArray payload = QJsonDocument(cards).toJson(QJsonDocument::Compact);
    if (source.write(payload) != payload.size())
        return false;
    source.close();
    return CardCatalog::importBulkFile(sourcePath, databasePath, u"default_cards"_s).ok;
}

bool dropCardsTable(const QString &databasePath)
{
    const QString connectionName = uniqueSqlName("drop-cards-");
    bool ok = false;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(databasePath);
        if (database.open()) {
            QSqlQuery query(database);
            ok = query.exec(u"DROP TABLE cards"_s);
            database.close();
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return ok;
}

bool restoreBoltAndTokenCardsTable(const QString &databasePath)
{
    const QString connectionName = uniqueSqlName("restore-bolt-token-");
    bool ok = false;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(databasePath);
        if (database.open()) {
            QSqlQuery query(database);
            ok = query.exec(kCardsTableSql) &&
                 query.exec(u"INSERT INTO cards (id, oracle_id, name, type_line, set_code, "
                            "collector_number, image_url, lang, layout) VALUES ("
                            "'card-1', 'oracle-1', 'Lightning Bolt', 'Instant', 'M11', '149', "
                            "'https://example.test/bolt.jpg', 'en', 'normal')"_s) &&
                 query.exec(u"INSERT INTO cards (id, oracle_id, name, type_line, set_code, "
                            "collector_number, image_url, lang, layout, power, toughness, "
                            "oracle_text) VALUES ("
                            "'token-1', 'oracle-token-1', 'Goblin', "
                            "'Token Creature — Goblin', 'TNEO', '12', "
                            "'https://example.test/goblin.jpg', 'en', 'token', "
                            "'1', '1', 'Haste')"_s);
            database.close();
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return ok;
}

} // namespace

void TestCardCatalog::exactArtUsesCatalogEnglishWhenChinesePrintingIsMissing() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writeBoltCatalog(storage.path()), "test catalog import failed");
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"zh"_s);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);

    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"149"_s},
        {u"exactArt"_s, true},
    }});

    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 2'000);
    QVERIFY(cacheSpy.first().at(3).toBool());
    QCOMPARE(network.requestedUrls, QList<QUrl>{QUrl(u"https://example.test/bolt.jpg"_s)});
    QVERIFY(catalog.printingImageSource(u"Lightning Bolt"_s, u"M11"_s, u"149"_s)
                .startsWith(u"file:"_s));
}

void TestCardCatalog::mtgchPreferenceBypassesCatalogScryfallFastPath() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writeBoltCatalog(storage.path()), "test catalog import failed");
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setCardArtProvider(u"mtgch"_s);
    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);

    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"149"_s},
        {u"exactArt"_s, true},
    }});

    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 2'000);
    QVERIFY(cacheSpy.first().at(3).toBool());
    QCOMPARE(network.requestedUrls.size(), 2);
    QCOMPARE(network.requestedUrls.at(0).host(), u"mtgch.com"_s);
    QCOMPARE(network.requestedUrls.at(1), QUrl(u"https://images.test/bolt-en.png"_s));
    QVERIFY(std::none_of(network.requestedUrls.cbegin(), network.requestedUrls.cend(),
                         [](const QUrl &url) { return url.host() == u"example.test"_s; }));
}

void TestCardCatalog::clearsQueryErrorAfterSuccessfulPrintings() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writeBoltCatalog(storage.path()), "test catalog import failed");

    CardCatalog catalog(storage.path());
    QVERIFY(catalog.installed());
    QCOMPARE(catalog.printings(u"Lightning Bolt"_s).size(), 1);
    QVERIFY(catalog.lastError().isEmpty());

    const QString connectionName = uniqueSqlName("catalog-query-error-");
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(storage.filePath(u"cards.sqlite"_s));
        QVERIFY2(database.open(), qPrintable(database.lastError().text()));
        QSqlQuery query(database);
        QVERIFY(query.exec(u"DROP TABLE cards"_s));
        database.close();
    }
    QSqlDatabase::removeDatabase(connectionName);

    QCOMPARE(catalog.printings(u"Sol Ring"_s).size(), 0);
    QVERIFY(!catalog.lastError().isEmpty());

    const QString restoreName = uniqueSqlName("catalog-query-restore-");
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, restoreName);
        database.setDatabaseName(storage.filePath(u"cards.sqlite"_s));
        QVERIFY2(database.open(), qPrintable(database.lastError().text()));
        QSqlQuery query(database);
        QVERIFY(query.exec(kCardsTableSql));
        QVERIFY(query.exec(u"INSERT INTO cards (id, oracle_id, name, type_line, set_code, "
                           "collector_number, image_url, lang, layout) VALUES ("
                           "'sol-1', 'oracle-sol', 'Sol Ring', 'Artifact', 'CMM', '396', "
                           "'https://example.test/sol.jpg', 'en', 'normal')"_s));
        database.close();
    }
    QSqlDatabase::removeDatabase(restoreName);

    QCOMPARE(catalog.printings(u"Sol Ring"_s).size(), 1);
    QVERIFY(catalog.lastError().isEmpty());
}

void TestCardCatalog::keepsOperationErrorAfterSuccessfulPrintings() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writeBoltCatalog(storage.path()), "test catalog import failed");

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
    QVERIFY(catalog.lastError().contains(u"invalid image data"_s));
    QCOMPARE(catalog.printings(u"Lightning Bolt"_s).size(), 1);
    QVERIFY(catalog.lastError().contains(u"invalid image data"_s));
}

void TestCardCatalog::incrementalCacheDoesNotClearPrintingsError() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writeBoltCatalog(storage.path()), "test catalog import failed");

    CardCatalog catalog(storage.path());
    QVERIFY(catalog.installed());

    const QString connectionName = uniqueSqlName("catalog-incremental-error-");
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(storage.filePath(u"cards.sqlite"_s));
        QVERIFY2(database.open(), qPrintable(database.lastError().text()));
        QSqlQuery query(database);
        QVERIFY(query.exec(u"DROP TABLE cards"_s));
        database.close();
    }
    QSqlDatabase::removeDatabase(connectionName);

    QCOMPARE(catalog.printings(u"Sol Ring"_s).size(), 0);
    QVERIFY(!catalog.lastError().isEmpty());
    const QString printingsError = catalog.lastError();

    catalog.cacheCardsIncrementally({});
    QCOMPARE(catalog.lastError(), printingsError);
}

void TestCardCatalog::successfulPrintingsKeepSearchError() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writeBoltCatalog(storage.path()), "test catalog import failed");

    CardCatalog catalog(storage.path());
    QVERIFY(catalog.installed());

    const QString connectionName = uniqueSqlName("catalog-search-error-");
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(storage.filePath(u"cards.sqlite"_s));
        QVERIFY2(database.open(), qPrintable(database.lastError().text()));
        QSqlQuery query(database);
        QVERIFY(query.exec(u"DROP TABLE cards"_s));
        database.close();
    }
    QSqlDatabase::removeDatabase(connectionName);

    catalog.search(u"Lightning"_s);
    QTRY_VERIFY_WITH_TIMEOUT(!catalog.searching(), 2'000);
    QVERIFY(catalog.lastError().contains(u"Could not search the local card catalog."_s));
    const QString searchError = catalog.lastError();

    const QString restoreName = uniqueSqlName("catalog-search-restore-");
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, restoreName);
        database.setDatabaseName(storage.filePath(u"cards.sqlite"_s));
        QVERIFY2(database.open(), qPrintable(database.lastError().text()));
        QSqlQuery query(database);
        QVERIFY(query.exec(kCardsTableSql));
        QVERIFY(query.exec(u"INSERT INTO cards (id, oracle_id, name, type_line, set_code, "
                           "collector_number, image_url, lang, layout) VALUES ("
                           "'sol-1', 'oracle-sol', 'Sol Ring', 'Artifact', 'CMM', '396', "
                           "'https://example.test/sol.jpg', 'en', 'normal')"_s));
        database.close();
    }
    QSqlDatabase::removeDatabase(restoreName);

    QCOMPARE(catalog.printings(u"Sol Ring"_s).size(), 1);
    QCOMPARE(catalog.lastError(), searchError);
}

void TestCardCatalog::successfulCardSearchKeepsTokenSearchError() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writeBoltAndTokenCatalog(storage.path()), "test catalog import failed");

    CardCatalog catalog(storage.path());
    QVERIFY(catalog.installed());
    QVERIFY(catalog.tokenCatalogInstalled());
    QVERIFY2(dropCardsTable(storage.filePath(u"cards.sqlite"_s)), "drop cards table failed");

    catalog.searchTokens(u"gob"_s);
    QTRY_VERIFY_WITH_TIMEOUT(!catalog.tokenSearching(), 2'000);
    QVERIFY(catalog.lastError().contains(u"Could not search the local token catalog."_s));
    const QString tokenError = catalog.lastError();

    QVERIFY2(restoreBoltAndTokenCardsTable(storage.filePath(u"cards.sqlite"_s)),
             "restore cards table failed");
    catalog.search(u"Lightning"_s);
    QTRY_COMPARE(catalog.searchResults().size(), 1);
    QCOMPARE(catalog.lastError(), tokenError);
    QCOMPARE(catalog.tokenSearchError(), tokenError);
    QVERIFY(catalog.cardSearchError().isEmpty());
}

void TestCardCatalog::successfulTokenSearchKeepsCardSearchError() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writeBoltAndTokenCatalog(storage.path()), "test catalog import failed");

    CardCatalog catalog(storage.path());
    QVERIFY(catalog.installed());
    QVERIFY(catalog.tokenCatalogInstalled());
    QVERIFY2(dropCardsTable(storage.filePath(u"cards.sqlite"_s)), "drop cards table failed");

    catalog.search(u"Lightning"_s);
    QTRY_VERIFY_WITH_TIMEOUT(!catalog.searching(), 2'000);
    QVERIFY(catalog.lastError().contains(u"Could not search the local card catalog."_s));
    const QString cardError = catalog.lastError();

    QVERIFY2(restoreBoltAndTokenCardsTable(storage.filePath(u"cards.sqlite"_s)),
             "restore cards table failed");
    catalog.searchTokens(u"gob"_s);
    QTRY_COMPARE(catalog.tokenSearchResults().size(), 1);
    QCOMPARE(catalog.tokenSearchResults().first().toMap().value(u"name"_s).toString(), u"Goblin"_s);
    QCOMPARE(catalog.lastError(), cardError);
    QCOMPARE(catalog.cardSearchError(), cardError);
    QVERIFY(catalog.tokenSearchError().isEmpty());
}

void TestCardCatalog::exposesIndependentCatalogErrorsWhenMultipleSubsystemsFail() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writeBoltAndTokenCatalog(storage.path()), "test catalog import failed");

    CardCatalog catalog(storage.path());
    QVERIFY(catalog.installed());
    QVERIFY(catalog.tokenCatalogInstalled());
    QVERIFY2(dropCardsTable(storage.filePath(u"cards.sqlite"_s)), "drop cards table failed");

    QCOMPARE(catalog.printings(u"Sol Ring"_s).size(), 0);
    QVERIFY(!catalog.printingsError().isEmpty());
    QCOMPARE(catalog.lastError(), catalog.printingsError());

    catalog.searchTokens(u"gob"_s);
    QTRY_VERIFY_WITH_TIMEOUT(!catalog.tokenSearching(), 2'000);
    QVERIFY(catalog.tokenSearchError().contains(u"Could not search the local token catalog."_s));
    QCOMPARE(catalog.lastError(), catalog.tokenSearchError());
    QVERIFY(!catalog.printingsError().isEmpty());

    catalog.search(u"Lightning"_s);
    QTRY_VERIFY_WITH_TIMEOUT(!catalog.searching(), 2'000);
    QVERIFY(catalog.cardSearchError().contains(u"Could not search the local card catalog."_s));
    QCOMPARE(catalog.lastError(), catalog.cardSearchError());
    QCOMPARE(catalog.operationError(), QString{});
    QVERIFY(!catalog.tokenSearchError().isEmpty());
    QVERIFY(!catalog.printingsError().isEmpty());
    QVERIFY(catalog.lastError() != catalog.tokenSearchError());
    QVERIFY(catalog.lastError() != catalog.printingsError());
}
