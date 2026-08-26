// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/CatalogRepository.h"
#include "services/CatalogStorage.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QTemporaryDir>
#include <QTest>

#include <chrono>
#include <future>

using namespace Qt::StringLiterals;
using hexproof::client::CardRecord;
using hexproof::client::CatalogCardQuery;
using hexproof::client::CatalogRepository;

class TestCatalogRepository : public QObject
{
    Q_OBJECT

  private slots:
    void queriesCatalog() const;
    void readsInstalledLimitedProduct() const;
    void prefersUsableEnglishOverLocalizedPlaceholder() const;
    void validatesPreviousPolicyScryfallArt() const;
    void reportsPrintingsQueryErrors() const;
    void distinguishesTokenIdentities() const;
    void replacementWaitsForActiveRepository() const;
    void failedLocalizedPersistLeavesLookupsWorking() const;
};

void TestCatalogRepository::readsInstalledLimitedProduct() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString databasePath = storage.filePath(u"limited.sqlite"_s);
    const QString connectionName = u"catalog-limited-fixture"_s;
    const QJsonObject definition{
        {u"id"_s, u"mtgjson-tst-play"_s}, {u"name"_s, u"Test Play Booster"_s},
        {u"setCode"_s, u"TST"_s},         {u"productType"_s, u"official"_s},
        {u"authentic"_s, true},           {u"cardsPerPack"_s, 1},
        {u"sheets"_s, QJsonArray{}},      {u"variants"_s, QJsonArray{}},
    };
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(databasePath);
        QVERIFY2(database.open(), qPrintable(database.lastError().text()));
        QSqlQuery query(database);
        QVERIFY(query.exec(u"CREATE TABLE cards (name TEXT)"_s));
        QVERIFY(query.exec(u"CREATE TABLE limited_products ("
                           "id TEXT PRIMARY KEY, name TEXT, set_code TEXT, product_type TEXT, "
                           "authentic INTEGER, definition_json TEXT)"_s));
        query.prepare(u"INSERT INTO limited_products VALUES (?, ?, ?, ?, ?, ?)"_s);
        query.addBindValue(u"mtgjson-tst-play"_s);
        query.addBindValue(u"Test Play Booster"_s);
        query.addBindValue(u"TST"_s);
        query.addBindValue(u"official"_s);
        query.addBindValue(1);
        query.addBindValue(QJsonDocument(definition).toJson(QJsonDocument::Compact));
        QVERIFY2(query.exec(), qPrintable(query.lastError().text()));
        database.close();
    }
    QSqlDatabase::removeDatabase(connectionName);

    CatalogRepository repository(databasePath);
    const QVariantList products = repository.limitedProducts();
    QCOMPARE(products.size(), 1);
    QCOMPARE(products.first().toMap().value(u"setCode"_s).toString(), u"TST"_s);
    QCOMPARE(repository.limitedProduct(u"mtgjson-tst-play"_s).value(u"name"_s).toString(),
             u"Test Play Booster"_s);
}

void TestCatalogRepository::queriesCatalog() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString databasePath = storage.filePath(u"cards.sqlite"_s);
    const QString connectionName = u"catalog-repository-fixture"_s;

    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(databasePath);
        QVERIFY2(database.open(), qPrintable(database.lastError().text()));
        QSqlQuery query(database);
        QVERIFY(query.exec(u"CREATE TABLE cards ("
                           "oracle_id TEXT, name TEXT, printed_name TEXT, type_line TEXT, "
                           "set_code TEXT, collector_number TEXT, image_url TEXT, lang TEXT, "
                           "illustration_id TEXT, layout TEXT, colors TEXT, rarity TEXT, "
                           "legal_formats TEXT)"_s));
        QVERIFY(query.exec(u"CREATE TABLE card_aliases ("
                           "oracle_id TEXT, localized_name TEXT, localized_type TEXT, "
                           "face_name TEXT, preferred INTEGER, face_order INTEGER)"_s));

        query.prepare(u"INSERT INTO cards VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"_s);
        const auto insertCard = [&query](const QString &oracleId, const QString &name,
                                         const QString &printedName, const QString &typeLine,
                                         const QString &setCode, const QString &collectorNumber,
                                         const QString &language, const QString &layout) {
            query.bindValue(0, oracleId);
            query.bindValue(1, name);
            query.bindValue(2, printedName);
            query.bindValue(3, typeLine);
            query.bindValue(4, setCode);
            query.bindValue(5, collectorNumber);
            query.bindValue(6, u"https://example.test/card.jpg"_s);
            query.bindValue(7, language);
            query.bindValue(8, oracleId + u"-art"_s);
            query.bindValue(9, layout);
            query.bindValue(10, QString{});
            query.bindValue(11, u"common"_s);
            query.bindValue(12, u"|modern|commander|"_s);
            QVERIFY(query.exec());
        };
        insertCard(u"bolt"_s, u"Lightning Bolt"_s, u"Lightning Bolt"_s, u"Instant"_s, u"M11"_s,
                   u"149"_s, u"en"_s, u"normal"_s);
        insertCard(u"bolt"_s, u"Lightning Bolt"_s, u"Lightning Bolt"_s, u"Instant"_s, u"2X2"_s,
                   u"117"_s, u"en"_s, u"normal"_s);
        insertCard(u"bolt"_s, u"Lightning Bolt"_s, u"闪电击"_s, u"Instant"_s, u"M11"_s, u"149"_s,
                   u"zhs"_s, u"normal"_s);
        insertCard(u"goblin-token"_s, u"Goblin"_s, u"Goblin"_s, u"Token Creature — Goblin"_s,
                   u"TNEO"_s, u"12"_s, u"en"_s, u"token"_s);
        insertCard(u"delver"_s, u"Delver of Secrets // Insectile Aberration"_s,
                   u"Delver of Secrets // Insectile Aberration"_s,
                   u"Creature — Human Wizard // Creature — Human Insect"_s, u"MID"_s, u"47"_s,
                   u"en"_s, u"transform"_s);
        insertCard(u"esika-art"_s, u"Esika, God of the Tree // Esika, God of the Tree"_s,
                   u"Esika, God of the Tree // Esika, God of the Tree"_s, u"Card"_s, u"AKHM"_s,
                   u"43"_s, u"en"_s, u"art_series"_s);
        insertCard(u"esika"_s, u"Esika, God of the Tree // The Prismatic Bridge"_s,
                   u"Esika, God of the Tree // The Prismatic Bridge"_s,
                   u"Legendary Creature — God // Legendary Enchantment"_s, u"KHM"_s, u"168"_s,
                   u"en"_s, u"modal_dfc"_s);
        insertCard(u"esika"_s, u"Esika, God of the Tree // The Prismatic Bridge"_s,
                   u"Esika, God of the Tree // The Prismatic Bridge"_s,
                   u"Legendary Creature — God // Legendary Enchantment"_s, u"SLD"_s, u"1155"_s,
                   u"en"_s, u"modal_dfc"_s);
        insertCard(u"mountain"_s, u"Mountain"_s, u"Mountain"_s, u"Basic Land — Mountain"_s,
                   u"M21"_s, u"273"_s, u"en"_s, QString{});

        query.prepare(u"INSERT INTO card_aliases VALUES (?, ?, ?, ?, ?, ?)"_s);
        query.addBindValue(u"bolt"_s);
        query.addBindValue(u"闪电击"_s);
        query.addBindValue(u"瞬间"_s);
        query.addBindValue(QString{});
        query.addBindValue(1);
        query.addBindValue(0);
        QVERIFY(query.exec());
        query.prepare(u"INSERT INTO card_aliases VALUES (?, ?, ?, ?, ?, ?)"_s);
        query.addBindValue(u"goblin-token"_s);
        query.addBindValue(u"地精"_s);
        query.addBindValue(u"衍生生物 — 地精"_s);
        query.addBindValue(QString{});
        query.addBindValue(1);
        query.addBindValue(0);
        QVERIFY(query.exec());
        database.close();
    }
    QSqlDatabase::removeDatabase(connectionName);

    CatalogRepository repository(databasePath);
    QVERIFY(repository.installed());

    const auto english = repository.search(u"light"_s, u"en"_s, {}, {}, {}, {}, {}, {});
    QVERIFY2(english.error.isEmpty(), qPrintable(english.error));
    QCOMPARE(english.cards.size(), 1);
    QCOMPARE(english.cards.first().toMap().value(u"name"_s).toString(), u"Lightning Bolt"_s);
    QCOMPARE(english.cards.first().toMap().value(u"versionCount"_s).toInt(), 2);

    const auto chinese = repository.search(u"闪电"_s, u"zh"_s, {}, {}, {}, {}, {}, {});
    QVERIFY2(chinese.error.isEmpty(), qPrintable(chinese.error));
    QCOMPARE(chinese.cards.size(), 1);
    QCOMPARE(chinese.cards.first().toMap().value(u"displayName"_s).toString(), u"闪电击"_s);
    QCOMPARE(chinese.cards.first().toMap().value(u"typeLine"_s).toString(), u"瞬间"_s);

    const auto tokens = repository.searchTokens(u"gob"_s, u"en"_s);
    QVERIFY2(tokens.error.isEmpty(), qPrintable(tokens.error));
    QCOMPARE(tokens.cards.size(), 1);
    QCOMPARE(tokens.cards.first().toMap().value(u"name"_s).toString(), u"Goblin"_s);

    const auto chineseTokens = repository.searchTokens(u"地精"_s, u"zh"_s);
    QVERIFY2(chineseTokens.error.isEmpty(), qPrintable(chineseTokens.error));
    QCOMPARE(chineseTokens.cards.size(), 1);
    QCOMPARE(chineseTokens.cards.first().toMap().value(u"name"_s).toString(), u"Goblin"_s);
    QCOMPARE(chineseTokens.cards.first().toMap().value(u"displayName"_s).toString(), u"地精"_s);
    QCOMPARE(chineseTokens.cards.first().toMap().value(u"typeLine"_s).toString(),
             u"衍生生物 — 地精"_s);

    QCOMPARE(repository.printings(u"Lightning Bolt"_s, u"en"_s).size(), 2);
    QCOMPARE(repository.printings(u"Mountain"_s, u"en"_s).size(), 1);
    QCOMPARE(repository.printings(u"Goblin"_s, u"en"_s).size(), 0);
    const QVariantList delverFaces =
        repository.cardFaces(u"Delver of Secrets"_s, u"MID"_s, u"47"_s);
    QCOMPARE(delverFaces.size(), 2);
    QCOMPARE(delverFaces.at(0).toMap().value(u"typeLine"_s).toString(),
             u"Creature — Human Wizard"_s);
    QCOMPARE(delverFaces.at(1).toMap().value(u"typeLine"_s).toString(),
             u"Creature — Human Insect"_s);

    const QVariantList delverPrintings = repository.printings(u"Delver of Secrets"_s, u"en"_s);
    QCOMPARE(delverPrintings.size(), 1);
    QCOMPARE(delverPrintings.first().toMap().value(u"setCode"_s).toString(), u"MID"_s);
    QVERIFY(!delverPrintings.first().toMap().value(u"imageUrl"_s).toString().isEmpty());
    QCOMPARE(repository.printings(u"Insectile Aberration"_s, u"en"_s).size(), 1);

    const QVariantList esikaPrintings = repository.printings(u"Esika, God of the Tree"_s, u"en"_s);
    QCOMPARE(esikaPrintings.size(), 2);
    QCOMPARE(esikaPrintings.at(0).toMap().value(u"setCode"_s).toString(), u"KHM"_s);
    QCOMPARE(esikaPrintings.at(1).toMap().value(u"setCode"_s).toString(), u"SLD"_s);
    QVERIFY(!esikaPrintings.at(0).toMap().value(u"imageUrl"_s).toString().isEmpty());

    const auto record = repository.lookup(CatalogCardQuery{
        u"Lightning Bolt"_s,
        u"M11"_s,
        u"149"_s,
        u"zh"_s,
    });
    QCOMPARE(record.name, u"Lightning Bolt"_s);
    QCOMPARE(record.localizedName, u"闪电击"_s);
    QCOMPARE(record.typeLine, u"瞬间"_s);
    QVERIFY(record.imageUrl.isEmpty());

    const auto recordAgain = repository.lookup(CatalogCardQuery{
        u"Lightning Bolt"_s,
        u"M11"_s,
        u"149"_s,
        u"zh"_s,
    });
    QCOMPARE(recordAgain.typeLine, u"瞬间"_s);
    QCOMPARE(repository.printings(u"Lightning Bolt"_s, u"en"_s).size(), 2);
}

void TestCatalogRepository::prefersUsableEnglishOverLocalizedPlaceholder() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString databasePath = storage.filePath(u"cards.sqlite"_s);
    const QString connectionName = u"catalog-placeholder-fixture"_s;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(databasePath);
        QVERIFY2(database.open(), qPrintable(database.lastError().text()));
        QSqlQuery query(database);
        QVERIFY(query.exec(u"CREATE TABLE cards ("
                           "oracle_id TEXT, name TEXT, printed_name TEXT, type_line TEXT, "
                           "set_code TEXT, collector_number TEXT, image_url TEXT, "
                           "image_status TEXT, lang TEXT, illustration_id TEXT)"_s));
        QVERIFY(
            query.exec(u"INSERT INTO cards VALUES ("
                       "'goryo', 'Goryo''s Vengeance', 'Goryo''s Vengeance', "
                       "'Instant — Arcane', 'BOK', '67', "
                       "'https://example.test/english.jpg', 'highres_scan', 'en', 'art-en')"_s));
        QVERIFY(query.exec(u"INSERT INTO cards VALUES ("
                           "'goryo', 'Goryo''s Vengeance', '怨灵复仇', "
                           "'Instant — Arcane', 'BOK', '67', "
                           "'https://example.test/placeholder.jpg', 'placeholder', 'zhs', "
                           "'art-zh')"_s));
        database.close();
    }
    QSqlDatabase::removeDatabase(connectionName);

    CatalogRepository repository(databasePath);
    const auto record = repository.lookup(CatalogCardQuery{
        u"Goryo's Vengeance"_s,
        u"BOK"_s,
        u"67"_s,
        u"zh"_s,
    });
    QCOMPARE(record.imageUrl, u"https://example.test/english.jpg"_s);
    QCOMPARE(record.imageLanguage, u"en"_s);
}

void TestCatalogRepository::validatesPreviousPolicyScryfallArt() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString databasePath = storage.filePath(u"cards.sqlite"_s);
    const QString connectionName = u"catalog-cache-migration-fixture"_s;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(databasePath);
        QVERIFY2(database.open(), qPrintable(database.lastError().text()));
        QSqlQuery query(database);
        QVERIFY(
            query.exec(u"CREATE TABLE cards ("
                       "oracle_id TEXT, set_code TEXT, collector_number TEXT, "
                       "illustration_id TEXT, image_url TEXT, image_status TEXT, lang TEXT)"_s));
        QVERIFY(query.exec(u"CREATE TABLE localized_printings ("
                           "oracle_id TEXT, set_code TEXT, collector_number TEXT, "
                           "illustration_id TEXT, image_url TEXT, image_status TEXT)"_s));
        QVERIFY(query.exec(u"INSERT INTO cards VALUES ("
                           "'goryo', 'BOK', '67', 'art-en', "
                           "'https://cards.scryfall.io/english.jpg', 'highres_scan', 'en')"_s));
        QVERIFY(query.exec(u"INSERT INTO localized_printings VALUES ("
                           "'bolt', 'M11', '146', 'art-zh', "
                           "'https://cards.scryfall.io/bolt-zh.jpg', 'lowres')"_s));
        QVERIFY(query.exec(u"INSERT INTO localized_printings VALUES ("
                           "'goryo', 'BOK', '67', 'art-zh-current', "
                           "'https://cards.scryfall.io/goryo-zh-current.jpg', 'highres_scan')"_s));
        database.close();
    }
    QSqlDatabase::removeDatabase(connectionName);

    CatalogRepository repository(databasePath);
    CardRecord english;
    english.oracleId = u"goryo"_s;
    english.setCode = u"BOK"_s;
    english.collectorNumber = u"67"_s;
    english.illustrationId = u"art-en"_s;
    english.imageUrl = u"https://cards.scryfall.io/english.jpg"_s;
    english.imageLanguage = u"en"_s;
    QVERIFY(repository.cachedScryfallArtIsUsable(english));

    CardRecord chinesePlaceholder = english;
    chinesePlaceholder.illustrationId = u"art-zh-placeholder"_s;
    chinesePlaceholder.imageUrl = u"https://cards.scryfall.io/placeholder.jpg"_s;
    chinesePlaceholder.imageLanguage = u"zh"_s;
    QVERIFY(!repository.cachedScryfallArtIsUsable(chinesePlaceholder));

    CardRecord localized;
    localized.oracleId = u"bolt"_s;
    localized.setCode = u"M11"_s;
    localized.collectorNumber = u"146"_s;
    localized.illustrationId = u"art-zh"_s;
    localized.imageUrl = u"https://cards.scryfall.io/bolt-zh.jpg"_s;
    localized.imageLanguage = u"zh"_s;
    QVERIFY(repository.cachedScryfallArtIsUsable(localized));
}

void TestCatalogRepository::reportsPrintingsQueryErrors() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString databasePath = storage.filePath(u"cards.sqlite"_s);
    const QString connectionName = u"catalog-printings-error-fixture"_s;

    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(databasePath);
        QVERIFY2(database.open(), qPrintable(database.lastError().text()));
        QSqlQuery query(database);
        QVERIFY(query.exec(u"CREATE TABLE dummy (id INTEGER)"_s));
        database.close();
    }
    QSqlDatabase::removeDatabase(connectionName);

    CatalogRepository repository(databasePath);
    QString error;
    QCOMPARE(repository.printings(u"Lightning Bolt"_s, u"en"_s, &error).size(), 0);
    QVERIFY2(!error.isEmpty(), "printings() must surface a catalog query failure");
    error.clear();
    QCOMPARE(repository.cardFaces(u"Delver of Secrets"_s, u"MID"_s, u"47"_s, &error).size(), 0);
    QVERIFY2(!error.isEmpty(), "cardFaces() must surface a catalog query failure");
}

void TestCatalogRepository::distinguishesTokenIdentities() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString databasePath = storage.filePath(u"cards.sqlite"_s);
    const QString connectionName = u"catalog-token-identity-fixture"_s;

    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(databasePath);
        QVERIFY2(database.open(), qPrintable(database.lastError().text()));
        QSqlQuery query(database);
        QVERIFY(query.exec(u"CREATE TABLE cards ("
                           "oracle_id TEXT, name TEXT, type_line TEXT, set_code TEXT, "
                           "collector_number TEXT, image_url TEXT, lang TEXT, layout TEXT, "
                           "power TEXT, toughness TEXT, oracle_text TEXT)"_s));
        query.prepare(u"INSERT INTO cards VALUES (?, 'Cat', 'Token Creature — Cat', ?, ?, "
                      "'https://example.test/cat.jpg', 'en', 'token', ?, ?, ?)"_s);
        const auto insertCat = [&query](const QString &oracleId, const QString &setCode,
                                        const QString &collectorNumber, const QString &power,
                                        const QString &toughness, const QString &oracleText) {
            query.bindValue(0, oracleId);
            query.bindValue(1, setCode);
            query.bindValue(2, collectorNumber);
            query.bindValue(3, power);
            query.bindValue(4, toughness);
            query.bindValue(5, oracleText);
            QVERIFY(query.exec());
        };
        insertCat(u"cat-one-one"_s, u"TABC"_s, u"2"_s, u"1"_s, u"1"_s, QString{});
        insertCat(u"cat-one-one"_s, u"TDEF"_s, u"4"_s, u"1"_s, u"1"_s, QString{});
        insertCat(u"cat-two-two-flying"_s, u"TUNF"_s, u"1"_s, u"2"_s, u"2"_s, u"Flying"_s);
        database.close();
    }
    QSqlDatabase::removeDatabase(connectionName);

    const CatalogRepository repository(databasePath);
    const auto cats = repository.searchTokens(u"cat"_s, u"en"_s);
    QVERIFY2(cats.error.isEmpty(), qPrintable(cats.error));
    QCOMPARE(cats.cards.size(), 2);

    const auto exact = repository.searchTokens(u"UNF 001"_s, u"en"_s);
    QVERIFY2(exact.error.isEmpty(), qPrintable(exact.error));
    QCOMPARE(exact.cards.size(), 1);
    const QVariantMap cat = exact.cards.first().toMap();
    QCOMPARE(cat.value(u"oracleId"_s).toString(), u"cat-two-two-flying"_s);
    QCOMPARE(cat.value(u"setCode"_s).toString(), u"TUNF"_s);
    QCOMPARE(cat.value(u"collectorNumber"_s).toString(), u"1"_s);
    QCOMPARE(cat.value(u"power"_s).toString(), u"2"_s);
    QCOMPARE(cat.value(u"toughness"_s).toString(), u"2"_s);
    QCOMPARE(cat.value(u"oracleText"_s).toString(), u"Flying"_s);

    const auto tokenSetExact = repository.searchTokens(u"TUNF #1"_s, u"en"_s);
    QCOMPARE(tokenSetExact.cards.size(), 1);
    QCOMPARE(tokenSetExact.cards.first().toMap().value(u"oracleId"_s).toString(),
             u"cat-two-two-flying"_s);
}

void TestCatalogRepository::replacementWaitsForActiveRepository() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString databasePath = storage.filePath(u"cards.sqlite"_s);
    const QString newPath = storage.filePath(u"cards.sqlite.new"_s);
    const QString connectionName = u"catalog-lock-fixture"_s;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(databasePath);
        QVERIFY2(database.open(), qPrintable(database.lastError().text()));
        QSqlQuery query(database);
        QVERIFY(query.exec(u"CREATE TABLE cards (name TEXT)"_s));
        database.close();
    }
    QSqlDatabase::removeDatabase(connectionName);
    {
        QFile replacement(newPath);
        QVERIFY(replacement.open(QIODevice::WriteOnly));
        QCOMPARE(replacement.write("new"), 3);
    }

    std::future<bool> install;
    {
        CatalogRepository activeRepository(databasePath);
        // Opening the connection takes the file lock that installDatabase needs.
        QCOMPARE(activeRepository.lookup(CatalogCardQuery{u"x"_s, {}, {}, u"en"_s}).name,
                 QString{});
        install = std::async(std::launch::async, [newPath, databasePath]() {
            return hexproof::client::catalogstorage::installDatabase(newPath, databasePath);
        });
        QCOMPARE(install.wait_for(std::chrono::milliseconds(50)), std::future_status::timeout);
        QVERIFY(activeRepository.installed());
    }

    QCOMPARE(install.wait_for(std::chrono::seconds(1)), std::future_status::ready);
    QVERIFY(install.get());
    QFile installed(databasePath);
    QVERIFY(installed.open(QIODevice::ReadOnly));
    QCOMPARE(installed.readAll(), QByteArray("new"));
}

void TestCatalogRepository::failedLocalizedPersistLeavesLookupsWorking() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString databasePath = storage.filePath(u"cards.sqlite"_s);
    const QString connectionName = u"catalog-persist-fixture"_s;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(databasePath);
        QVERIFY2(database.open(), qPrintable(database.lastError().text()));
        QSqlQuery query(database);
        QVERIFY(query.exec(u"CREATE TABLE cards ("
                           "oracle_id TEXT, name TEXT, printed_name TEXT, type_line TEXT, "
                           "set_code TEXT, collector_number TEXT, image_url TEXT, lang TEXT, "
                           "illustration_id TEXT, layout TEXT, colors TEXT, rarity TEXT, "
                           "legal_formats TEXT)"_s));
        QVERIFY(query.exec(u"INSERT INTO cards VALUES ("
                           "'bolt', 'Lightning Bolt', 'Lightning Bolt', 'Instant', "
                           "'M11', '149', 'https://example.test/card.jpg', 'en', "
                           "'bolt-art', 'normal', '', 'common', '|modern|')"_s));
        database.close();
    }
    QSqlDatabase::removeDatabase(connectionName);

    CatalogRepository repository(databasePath);
    QCOMPARE(
        repository.lookup(CatalogCardQuery{u"Lightning Bolt"_s, u"M11"_s, u"149"_s, u"en"_s}).name,
        u"Lightning Bolt"_s);

    const QJsonArray printings{QJsonObject{
        {u"id"_s, u"zh-1"_s},
        {u"oracle_id"_s, u"bolt"_s},
        {u"name"_s, u"Lightning Bolt"_s},
        {u"lang"_s, u"zhs"_s},
        {u"set"_s, u"M11"_s},
        {u"collector_number"_s, u"149"_s},
        {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://example.test/bolt.jpg"_s}}},
    }};
    const auto persisted = repository.persistLocalizedPrintings(printings, 10);
    QVERIFY(!persisted.error.isEmpty());
    QCOMPARE(
        repository.lookup(CatalogCardQuery{u"Lightning Bolt"_s, u"M11"_s, u"149"_s, u"en"_s}).name,
        u"Lightning Bolt"_s);
}

QTEST_GUILESS_MAIN(TestCatalogRepository)
#include "catalogrepository_test.moc"
