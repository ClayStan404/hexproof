// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/CardCatalogQueryInternal.h"
#include "services/CatalogImport.h"
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
    void cardFacesUseIndexedCaseInsensitivePrinting() const;
    void meldFacesPreferRelatedPrintingAndConstrainFallback() const;
    void filtersSelectionsBeforeResultLimit() const;
    void enrichesLocalizedCardPresentation() const;
    void resolvesRarityFromExactPrintingInsteadOfCubePlaceholder() const;
    void oldLimitedMetadataDoesNotInventColorsOrCosts() const;
    void readsInstalledLimitedProduct() const;
    void approximatesWhenSetHasOnlyLeftoverOfficialProducts() const;
    void prefersUsableEnglishOverLocalizedPlaceholder() const;
    void validatesPreviousPolicyScryfallArt() const;
    void reportsPrintingsQueryErrors() const;
    void distinguishesTokenIdentities() const;
    void replacementWaitsForActiveRepository() const;
    void failedLocalizedPersistLeavesLookupsWorking() const;
};

void TestCatalogRepository::cardFacesUseIndexedCaseInsensitivePrinting() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString databasePath = storage.filePath(u"cards.sqlite"_s);
    const auto card = [](const QString &id, const QString &number, const QString &language,
                         const QString &typeLine) {
        return QJsonObject{{u"id"_s, id},
                           {u"name"_s, u"Front // Back"_s},
                           {u"set"_s, u"TsT"_s},
                           {u"collector_number"_s, number},
                           {u"lang"_s, language},
                           {u"layout"_s, u"transform"_s},
                           {u"type_line"_s, typeLine}};
    };
    QFile source(storage.filePath(u"source.json"_s));
    QVERIFY(source.open(QIODevice::WriteOnly));
    source.write(QJsonDocument(QJsonArray{
                                   card(u"localized"_s, u"7A"_s, u"zhs"_s,
                                        u"Localized front // Localized back"_s),
                                   card(u"english"_s, u"7A"_s, u"en"_s, u"Creature // Land"_s),
                                   card(u"unicode"_s, u"7†"_s, u"en"_s, u"Creature // Artifact"_s),
                               })
                     .toJson());
    source.close();
    const auto imported = hexproof::client::catalogimport::importBulkFile(
        source.fileName(), databasePath, u"default_cards"_s);
    QVERIFY2(imported.ok, qPrintable(imported.error));

    // Use the production predicate and imported indexes, not a timing threshold
    // or a second copy of the SQL that could silently diverge from cardFaces().
    const QString connection = u"card-faces-index-plan"_s;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connection);
        database.setDatabaseName(databasePath);
        QVERIFY2(database.open(), qPrintable(database.lastError().text()));
        QSqlQuery query(database);
        query.prepare(
            u"EXPLAIN QUERY PLAN SELECT name, layout, type_line, set_code, collector_number, "
            "related_cards FROM cards WHERE "_s +
            hexproof::client::catalog_internal::catalogExactPrintingSql(QString{}) +
            u" ORDER BY CASE WHEN lang = 'en' THEN 0 ELSE 1 END LIMIT 1"_s);
        query.addBindValue(u"tst"_s);
        query.addBindValue(u"7a"_s);
        QVERIFY2(query.exec(), qPrintable(query.lastError().text()));
        QStringList plan;
        while (query.next())
            plan.append(query.value(3).toString());
        const QString details = plan.join(QLatin1Char('\n'));
        QVERIFY2(details.contains(u"SEARCH cards USING INDEX cards_printing_idx"_s),
                 qPrintable(details));
        QVERIFY2(details.contains(u"set_code=? AND collector_number=?"_s), qPrintable(details));
        QVERIFY2(!details.contains(u"SCAN cards"_s), qPrintable(details));
        database.close();
    }
    QSqlDatabase::removeDatabase(connection);

    CatalogRepository repository(databasePath);
    QString error;
    QString layout;
    QString canonicalName;
    const QVariantList faces =
        repository.cardFaces(u"Front"_s, u"tst"_s, u"7a"_s, &error, &layout, &canonicalName);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QCOMPARE(layout, u"transform"_s);
    QCOMPARE(canonicalName, u"Front // Back"_s);
    QCOMPARE(faces.size(), 2);
    QCOMPARE(faces.at(0).toMap().value(u"typeLine"_s).toString(), u"Creature"_s);
    QCOMPARE(faces.at(1).toMap().value(u"typeLine"_s).toString(), u"Land"_s);
    const QVariantList unicode = repository.cardFaces(u"Front"_s, u"tst"_s, u"7†"_s, &error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QCOMPARE(unicode.size(), 2);
    QCOMPARE(unicode.at(1).toMap().value(u"typeLine"_s).toString(), u"Artifact"_s);
    QCOMPARE(repository.cardFaces(u"Front"_s, u"OTHER"_s, u"7a"_s).size(), 0);
}

void TestCatalogRepository::meldFacesPreferRelatedPrintingAndConstrainFallback() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString databasePath = storage.filePath(u"cards.sqlite"_s);
    const auto card = [](const QString &id, const QString &name, const QString &setCode,
                         const QString &number, const QString &language) {
        return QJsonObject{{u"id"_s, id},
                           {u"name"_s, name},
                           {u"set"_s, setCode},
                           {u"collector_number"_s, number},
                           {u"lang"_s, language},
                           {u"layout"_s, u"meld"_s},
                           {u"type_line"_s, u"Creature"_s}};
    };
    const auto component = [&card](const QString &number, const QString &relatedId,
                                   const QString &relatedName) {
        QJsonObject object = card(number, u"Component "_s + number, u"tst"_s, number, u"en"_s);
        object.insert(u"all_parts"_s, QJsonArray{QJsonObject{{u"id"_s, relatedId},
                                                             {u"name"_s, relatedName},
                                                             {u"component"_s, u"meld_result"_s}}});
        return object;
    };
    QFile source(storage.filePath(u"source.json"_s));
    QVERIFY(source.open(QIODevice::WriteOnly));
    source.write(QJsonDocument(
                     QJsonArray{
                         component(u"1"_s, u"related-printing"_s, u"Meld Result"_s),
                         component(u"2"_s, u"missing-id"_s, u"mELD rESULT"_s),
                         component(u"3"_s, QString{}, u"mELD rESULT"_s),
                         component(u"4"_s, QString{}, u"Other Result"_s),
                         card(u"related-printing"_s, u"Meld Result"_s, u"ALT"_s, u"99"_s, u"zhs"_s),
                         card(u"local-result"_s, u"Meld Result"_s, u"TST"_s, u"88"_s, u"zhs"_s),
                         card(u"english-result"_s, u"Meld Result"_s, u"TST"_s, u"88"_s, u"en"_s),
                         card(u"other-result"_s, u"Other Result"_s, u"ALT"_s, u"77"_s, u"en"_s),
                     })
                     .toJson());
    source.close();
    const auto imported = hexproof::client::catalogimport::importBulkFile(
        source.fileName(), databasePath, u"default_cards"_s);
    QVERIFY2(imported.ok, qPrintable(imported.error));

    // Make the language winner observable without changing its canonical name.
    const QString connection = u"meld-result-language"_s;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connection);
        database.setDatabaseName(databasePath);
        QVERIFY(database.open());
        QSqlQuery query(database);
        QVERIFY(query.exec(u"UPDATE cards SET type_line = 'Artifact Creature' "
                           "WHERE id = 'english-result'"_s));
        database.close();
    }
    QSqlDatabase::removeDatabase(connection);

    CatalogRepository repository(databasePath);
    QString error;
    const QVariantList exact = repository.cardFaces(u"Component 1"_s, u"tst"_s, u"1"_s, &error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QCOMPARE(exact.size(), 2);
    const QVariantMap front = exact.at(0).toMap();
    const QVariantMap back = exact.at(1).toMap();
    QCOMPARE(front.value(u"setCode"_s).toString(), u"TST"_s);
    QCOMPARE(front.value(u"collectorNumber"_s).toString(), u"1"_s);
    QCOMPARE(back.value(u"setCode"_s).toString(), u"ALT"_s);
    QCOMPARE(back.value(u"collectorNumber"_s).toString(), u"99"_s);
    QVERIFY(back.value(u"relatedCard"_s).toBool());
    for (const QString &number : {u"2"_s, u"3"_s}) {
        const QVariantList fallback =
            repository.cardFaces(u"Component "_s + number, u"tst"_s, number, &error);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QCOMPARE(fallback.size(), 2);
        const QVariantMap result = fallback.at(1).toMap();
        QCOMPARE(result.value(u"name"_s).toString(), u"Meld Result"_s);
        QCOMPARE(result.value(u"setCode"_s).toString(), u"TST"_s);
        QCOMPARE(result.value(u"collectorNumber"_s).toString(), u"88"_s);
        QCOMPARE(result.value(u"typeLine"_s).toString(), u"Artifact Creature"_s);
    }
    QCOMPARE(repository.cardFaces(u"Component 4"_s, u"tst"_s, u"4"_s).size(), 0);
}

void TestCatalogRepository::enrichesLocalizedCardPresentation() const
{
    QTemporaryDir storage;
    const QString databasePath = storage.filePath(u"cards.sqlite"_s);
    QJsonArray sourceCards;
    const auto makeCard = [](QString name, QString number) {
        return QJsonObject{{u"id"_s, number},
                           {u"oracle_id"_s, number},
                           {u"name"_s, name},
                           {u"set"_s, u"TST"_s},
                           {u"collector_number"_s, number},
                           {u"lang"_s, u"en"_s},
                           {u"type_line"_s, u"Artifact"_s}};
    };
    QJsonObject rock = makeCard(u"Mana rock"_s, u"1"_s);
    rock.insert(u"printed_name"_s, u"法力石"_s);
    rock.insert(u"colors"_s, QJsonArray{});
    rock.insert(u"color_identity"_s, QJsonArray{u"U"_s, u"W"_s});
    rock.insert(u"mana_cost"_s, u"{2}"_s);
    rock.insert(u"oracle_text"_s, u"{T}: Add {W} or {U}."_s);
    sourceCards.append(rock);
    QJsonObject transform = makeCard(u"Front // Back"_s, u"2"_s);
    transform.insert(
        u"card_faces"_s,
        QJsonArray{QJsonObject{{u"colors"_s, QJsonArray{u"W"_s}}, {u"mana_cost"_s, u"{1}{W}"_s}},
                   QJsonObject{{u"colors"_s, QJsonArray{u"R"_s}}, {u"mana_cost"_s, u""_s}}});
    sourceCards.append(transform);
    QJsonObject split = makeCard(u"Split"_s, u"3"_s);
    split.insert(u"colors"_s, QJsonArray{u"R"_s, u"U"_s});
    split.insert(u"mana_cost"_s, u"{1}{U} // {1}{R}"_s);
    split.insert(u"card_faces"_s, transform.value(u"card_faces"_s));
    sourceCards.append(split);
    QJsonObject land = makeCard(u"Land"_s, u"4"_s);
    land.insert(u"colors"_s, QJsonArray{});
    land.insert(u"mana_cost"_s, u""_s);
    sourceCards.append(land);
    QFile source(storage.filePath(u"source.json"_s));
    QVERIFY(source.open(QIODevice::WriteOnly));
    source.write(QJsonDocument(sourceCards).toJson());
    source.close();
    const auto imported = hexproof::client::catalogimport::importBulkFile(
        source.fileName(), databasePath, u"default_cards"_s);
    QVERIFY2(imported.ok, qPrintable(imported.error));

    // A preferred Chinese alias works without a Chinese printing of this set.
    const QString connection = u"presentation-alias"_s;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connection);
        database.setDatabaseName(databasePath);
        QVERIFY(database.open());
        QSqlQuery query(database);
        QVERIFY(query.exec(u"INSERT INTO card_aliases VALUES ('2', 'Front', '正面', '', 1, 0)"_s));
        QVERIFY(query.exec(u"INSERT INTO card_aliases VALUES ('2', 'Back', '背面', '', 1, 1)"_s));
        database.close();
    }
    QSqlDatabase::removeDatabase(connection);

    QVariantList pool;
    for (int i = 0; i < sourceCards.size(); ++i) {
        pool.append(QVariantMap{{u"instanceId"_s, QString::number(i)},
                                {u"name"_s, sourceCards[i].toObject().value(u"name"_s).toString()},
                                {u"setCode"_s, u"tst"_s},
                                {u"collectorNumber"_s, QString::number(i + 1)}});
    }
    CatalogRepository repository(databasePath);
    QString error;
    const QVariantList zh = repository.enrichLimitedCards(pool, &error, u"zh"_s);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    const QVariantMap first = zh.first().toMap();
    QCOMPARE(first.value(u"displayName"_s).toString(), u"法力石"_s);
    QCOMPARE(first.value(u"name"_s).toString(), u"Mana rock"_s);
    QCOMPARE(first.value(u"instanceId"_s).toString(), u"0"_s);
    QCOMPARE(first.value(u"colors"_s).toString(), u"WU"_s);
    QVERIFY(first.contains(u"cardColors"_s));
    QCOMPARE(first.value(u"cardColors"_s).toString(), u""_s);
    QCOMPARE(first.value(u"manaCost"_s).toString(), u"{2}"_s);
    QCOMPARE(first.value(u"oracleText"_s).toString(), u"{T}: Add {W} or {U}."_s);
    QCOMPARE(zh[1].toMap().value(u"cardColors"_s).toString(), u"W"_s);
    QCOMPARE(zh[1].toMap().value(u"manaCost"_s).toString(), u"{1}{W}"_s);
    QCOMPARE(zh[1].toMap().value(u"displayName"_s).toString(), u"正面 // 背面"_s);
    QCOMPARE(zh[2].toMap().value(u"cardColors"_s).toString(), u"UR"_s);
    QCOMPARE(zh[2].toMap().value(u"manaCost"_s).toString(), u"{1}{U} // {1}{R}"_s);
    QCOMPARE(zh[2].toMap().value(u"displayName"_s).toString(), u"Split"_s);
    QVERIFY(zh[3].toMap().contains(u"manaCost"_s));
    QCOMPARE(zh[3].toMap().value(u"manaCost"_s).toString(), u""_s);
    QCOMPARE(repository.enrichLimitedCards(zh).first().toMap().value(u"displayName"_s).toString(),
             u"Mana rock"_s);
}

void TestCatalogRepository::resolvesRarityFromExactPrintingInsteadOfCubePlaceholder() const
{
    QTemporaryDir storage;
    const QString path = storage.filePath(u"rarity.sqlite"_s);
    const QString connection = u"cube-printing-rarity"_s;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connection);
        database.setDatabaseName(path);
        QVERIFY(database.open());
        QSqlQuery query(database);
        QVERIFY(query.exec(u"CREATE TABLE cards (name TEXT, type_line TEXT, set_code TEXT, "
                           "collector_number TEXT, rarity TEXT)"_s));
        QVERIFY(query.exec(u"INSERT INTO cards VALUES "
                           "('Shared name','Creature','TST','1','mythic'),"
                           "('Shared name','Creature','TST','2','rare'),"
                           "('Shared name','Creature','TST','3','special'),"
                           "('Shared name','Creature','TST','4','bonus'),"
                           "('Shared name','Creature','TST','5',''),"
                           "('Shared name','Creature','TST','6',NULL)"_s));
        database.close();
    }
    QSqlDatabase::removeDatabase(connection);
    CatalogRepository repository(path);
    const QVariantMap original{{u"instanceId"_s, u"physical-1"_s}, {u"name"_s, u"Shared name"_s},
                               {u"setCode"_s, u"tst"_s},           {u"collectorNumber"_s, u"1"_s},
                               {u"rarity"_s, u"special"_s},        {u"finish"_s, u"foil"_s}};
    QString error;
    const QVariantMap enriched = repository.enrichLimitedCards({original}, &error).first().toMap();
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QCOMPARE(enriched.value(u"rarity"_s).toString(), u"mythic"_s);
    QCOMPARE(original.value(u"rarity"_s).toString(), u"special"_s);
    for (const QString &field :
         {u"instanceId"_s, u"name"_s, u"setCode"_s, u"collectorNumber"_s, u"finish"_s})
        QCOMPARE(enriched.value(field), original.value(field));

    const QStringList expected{u"mythic"_s, u"rare"_s,   u"special"_s, u"bonus"_s,
                               u"common"_s, u"common"_s, u"common"_s};
    for (int i = 0; i < expected.size(); ++i) {
        QVariantMap card = original;
        card.insert(u"collectorNumber"_s, QString::number(i + 1));
        card.insert(u"rarity"_s, u"common"_s);
        QCOMPARE(
            repository.enrichLimitedCards({card}).first().toMap().value(u"rarity"_s).toString(),
            expected[i]);
    }
    QVariantMap otherSet = original;
    otherSet.insert(u"setCode"_s, u"OTHER"_s);
    QCOMPARE(
        repository.enrichLimitedCards({otherSet}).first().toMap().value(u"rarity"_s).toString(),
        u"special"_s);
}

void TestCatalogRepository::oldLimitedMetadataDoesNotInventColorsOrCosts() const
{
    QTemporaryDir storage;
    const QString path = storage.filePath(u"old.sqlite"_s);
    const QString connection = u"old-presentation"_s;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connection);
        database.setDatabaseName(path);
        QVERIFY(database.open());
        QSqlQuery query(database);
        QVERIFY(
            query.exec(u"CREATE TABLE cards (name TEXT, printed_name TEXT, type_line TEXT, "
                       "set_code TEXT, collector_number TEXT, colors TEXT, mana_value REAL)"_s));
        QVERIFY(query.exec(
            u"INSERT INTO cards VALUES ('Old rock', '旧法力石', 'Artifact', 'TST', '1', 'WU', 2)"_s));
        database.close();
    }
    QSqlDatabase::removeDatabase(connection);
    const QVariantList pool{QVariantMap{{u"name"_s, u"Old rock"_s},
                                        {u"setCode"_s, u"TST"_s},
                                        {u"collectorNumber"_s, u"1"_s},
                                        {u"instanceId"_s, u"old-1"_s}}};
    CatalogRepository repository(path);
    const QVariantMap card = repository.enrichLimitedCards(pool, nullptr, u"zh"_s).first().toMap();
    QCOMPARE(card.value(u"displayName"_s).toString(), u"旧法力石"_s);
    QCOMPARE(card.value(u"instanceId"_s).toString(), u"old-1"_s);
    QCOMPARE(card.value(u"colors"_s).toString(), u"WU"_s);
    QVERIFY(!card.contains(u"cardColors"_s));
    QVERIFY(!card.contains(u"manaCost"_s));
}

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

void TestCatalogRepository::approximatesWhenSetHasOnlyLeftoverOfficialProducts() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString databasePath = storage.filePath(u"limited-approx.sqlite"_s);
    const QString connectionName = u"catalog-limited-approx-fixture"_s;
    const QJsonObject promo{
        {u"id"_s, u"mtgjson-fin-bundle-promo"_s},
        {u"name"_s, u"Final Fantasy — Bundle Promo"_s},
        {u"setCode"_s, u"FIN"_s},
        {u"productType"_s, u"official"_s},
        {u"authentic"_s, true},
        {u"cardsPerPack"_s, 2},
        {u"sheets"_s, QJsonArray{}},
        {u"variants"_s, QJsonArray{}},
    };
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(databasePath);
        QVERIFY2(database.open(), qPrintable(database.lastError().text()));
        QSqlQuery query(database);
        QVERIFY(query.exec(u"CREATE TABLE cards ("
                           "name TEXT, set_code TEXT, collector_number TEXT, type_line TEXT, "
                           "rarity TEXT, digital INTEGER, lang TEXT, booster INTEGER)"_s));
        QVERIFY(query.exec(u"CREATE TABLE limited_products ("
                           "id TEXT PRIMARY KEY, name TEXT, set_code TEXT, product_type TEXT, "
                           "authentic INTEGER, definition_json TEXT)"_s));
        query.prepare(u"INSERT INTO limited_products VALUES (?, ?, ?, ?, ?, ?)"_s);
        query.addBindValue(u"mtgjson-fin-bundle-promo"_s);
        query.addBindValue(u"Final Fantasy — Bundle Promo"_s);
        query.addBindValue(u"FIN"_s);
        query.addBindValue(u"official"_s);
        query.addBindValue(1);
        query.addBindValue(QJsonDocument(promo).toJson(QJsonDocument::Compact));
        QVERIFY2(query.exec(), qPrintable(query.lastError().text()));
        query.prepare(u"INSERT INTO cards VALUES (?, 'FIN', ?, 'Creature', ?, 0, 'en', 1)"_s);
        for (int index = 1; index <= 30; ++index) {
            const QString rarity = index <= 20   ? u"common"_s
                                   : index <= 28 ? u"uncommon"_s
                                                 : u"rare"_s;
            query.addBindValue(u"Card %1"_s.arg(index));
            query.addBindValue(QString::number(index));
            query.addBindValue(rarity);
            QVERIFY2(query.exec(), qPrintable(query.lastError().text()));
        }
        database.close();
    }
    QSqlDatabase::removeDatabase(connectionName);

    CatalogRepository repository(databasePath);
    const QVariantList products = repository.limitedProducts();
    QStringList ids;
    for (const QVariant &value : products)
        ids.append(value.toMap().value(u"id"_s).toString());
    QVERIFY(ids.contains(u"mtgjson-fin-bundle-promo"_s));
    QVERIFY(ids.contains(u"approx-fin"_s));
    QCOMPARE(repository.limitedProduct(u"approx-fin"_s).value(u"cardsPerPack"_s).toInt(), 14);
}

void TestCatalogRepository::filtersSelectionsBeforeResultLimit() const
{
    QTemporaryDir storage;
    const QString path = storage.filePath(u"filters.sqlite"_s);
    const QString connection = u"catalog-multiple-filters"_s;
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connection);
        database.setDatabaseName(path);
        QVERIFY(database.open());
        QSqlQuery query(database);
        QVERIFY(query.exec(
            u"CREATE TABLE cards (oracle_id TEXT, name TEXT, printed_name TEXT, "
            "type_line TEXT, set_code TEXT, collector_number TEXT, image_url TEXT, "
            "lang TEXT, colors TEXT, mana_value REAL, rarity TEXT, legal_formats TEXT)"_s));
        query.prepare(
            u"INSERT INTO cards VALUES ('id', ?, '', ?, 'TST', ?, '', 'en', ?, ?, ?, '|modern|')"_s);
        for (int index = 0; index < 55; ++index) {
            query.bindValue(0,
                            index < 50 ? u"A filler %1"_s.arg(index) : u"Z target %1"_s.arg(index));
            const bool instant = index == 51 || index == 53;
            query.bindValue(1, instant ? u"Instant"_s : u"Creature"_s);
            query.bindValue(2, QString::number(index));
            query.bindValue(3, index < 50    ? u"W"_s
                               : index == 50 ? u"W"_s
                               : index == 51 ? u"U"_s
                               : index == 52 ? u"WU"_s
                               : index == 53 ? u"WUG"_s
                                             : u""_s);
            query.bindValue(4, index < 50 ? 1 : instant ? 8 : 5);
            query.bindValue(5, index < 50 ? u"common"_s : instant ? u"mythic"_s : u"rare"_s);
            QVERIFY2(query.exec(), qPrintable(query.lastError().text()));
        }
        database.close();
    }
    QSqlDatabase::removeDatabase(connection);
    CatalogRepository repository(path);
    const auto unfiltered = repository.search({}, u"en"_s, {}, {}, {}, {}, {}, {});
    QVERIFY2(unfiltered.error.isEmpty(), qPrintable(unfiltered.error));
    QCOMPARE(unfiltered.cards.size(), 40);
    const auto filtered = repository.search({}, u"en"_s, u"Creature,Instant"_s, {}, {}, u"W,U"_s,
                                            u"rare,mythic"_s, u"modern"_s, u"5,7+"_s);
    QVERIFY2(filtered.error.isEmpty(), qPrintable(filtered.error));
    QCOMPARE(filtered.cards.size(), 2);
    for (const QVariant &value : filtered.cards) {
        const QVariantMap card = value.toMap();
        QVERIFY(card.value(u"name"_s).toString().startsWith(u"Z target"_s));
        QVERIFY(!card.value(u"rarity"_s).toString().isEmpty());
        QVERIFY(card.value(u"manaValue"_s).toInt() >= 5);
        QVERIFY(card.value(u"colors"_s).toString().contains(QLatin1Char('W')));
        QVERIFY(card.value(u"colors"_s).toString().contains(QLatin1Char('U')));
    }
    const auto reversed = repository.search({}, u"en"_s, {}, {}, {}, u"U,W"_s, {}, {});
    QCOMPARE(reversed.cards, filtered.cards);
    const auto threeColors = repository.search({}, u"en"_s, {}, {}, {}, u"W,U,G"_s, {}, {});
    QCOMPARE(threeColors.cards.size(), 1);
    QCOMPARE(threeColors.cards.first().toMap().value(u"colors"_s).toString(), u"WUG"_s);
    const auto whiteMulticolor = repository.search({}, u"en"_s, {}, {}, {}, u"W,M"_s, {}, {});
    QCOMPARE(whiteMulticolor.cards, filtered.cards);
    const auto blueHighCost = repository.search({}, u"en"_s, {}, {}, {}, u"U"_s, {}, {}, u"7+"_s);
    QCOMPARE(blueHighCost.cards.size(), 2);
    const auto colorless = repository.search({}, u"en"_s, {}, {}, {}, u"C"_s, {}, {});
    QCOMPARE(colorless.cards.size(), 1);
    const auto incompatible = repository.search({}, u"en"_s, {}, {}, {}, u"W,C"_s, {}, {});
    QVERIFY2(incompatible.error.isEmpty(), qPrintable(incompatible.error));
    QVERIFY(incompatible.cards.isEmpty());
    const auto unknown =
        repository.search({}, u"en"_s, {}, {}, {}, {}, {}, {}, u"not a mana value"_s);
    QVERIFY(unknown.error.isEmpty());
    QVERIFY(unknown.cards.isEmpty());
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
    QCOMPARE(delverFaces.at(0).toMap().value(u"name"_s).toString(), u"Delver of Secrets"_s);
    QCOMPARE(delverFaces.at(1).toMap().value(u"name"_s).toString(), u"Insectile Aberration"_s);
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
