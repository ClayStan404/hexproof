// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/DeckLegalityService.h"

#include <QSqlDatabase>
#include <QSqlQuery>
#include <QTemporaryDir>
#include <QtTest>

using hexproof::client::DeckLegalityService;

namespace {

QVariantMap card(const QString &name, int count)
{
    return {{QStringLiteral("name"), name}, {QStringLiteral("count"), count}};
}

QVariantMap deck(const QString &format, const QVariantList &mainboard,
                 const QVariantList &sideboard = {}, const QStringList &commanders = {})
{
    return {{QStringLiteral("deckId"), QStringLiteral("deck-1")},
            {QStringLiteral("tableMode"), QStringLiteral("modern")},
            {QStringLiteral("deckFormat"), format},
            {QStringLiteral("commanders"), commanders},
            {QStringLiteral("mainboard"), mainboard},
            {QStringLiteral("sideboard"), sideboard}};
}

void createCatalog(const QString &path)
{
    const QString connection = QStringLiteral("deck-legality-setup");
    {
        QSqlDatabase database = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connection);
        database.setDatabaseName(path);
        QVERIFY(database.open());
        QSqlQuery query(database);
        QVERIFY(query.exec(
            QStringLiteral("CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")));
        QVERIFY(query.exec(
            QStringLiteral("INSERT INTO metadata (key, value) VALUES ('schema_version', '10')")));
        QVERIFY(query.exec(QStringLiteral(
            "CREATE TABLE cards (oracle_id TEXT, name TEXT NOT NULL, type_line TEXT, set_code "
            "TEXT, "
            "collector_number TEXT, colors TEXT, oracle_text TEXT, legality_statuses TEXT, "
            "digital INTEGER DEFAULT 0, lang TEXT DEFAULT 'en', layout TEXT DEFAULT 'normal')")));
        QVERIFY(query.exec(QStringLiteral("CREATE INDEX cards_name_idx "
                                          "ON cards(name COLLATE NOCASE)")));
        QVERIFY(query.exec(QStringLiteral("CREATE INDEX cards_printing_idx ON "
                                          "cards(set_code COLLATE NOCASE, "
                                          "collector_number COLLATE NOCASE)")));
        query.prepare(QStringLiteral("INSERT INTO cards (oracle_id, name, type_line, colors, "
                                     "oracle_text, legality_statuses, layout) "
                                     "VALUES (?, ?, ?, ?, ?, ?, ?)"));
        const auto insert = [&query](const QString &name, const QString &typeLine,
                                     const QString &colors, const QString &statuses,
                                     const QString &layout = QStringLiteral("normal"),
                                     const QString &oracleId = {}) {
            query.bindValue(0, oracleId.isEmpty() ? name.toCaseFolded() : oracleId);
            query.bindValue(1, name);
            query.bindValue(2, typeLine);
            query.bindValue(3, colors);
            query.bindValue(4, QString{});
            query.bindValue(5, statuses);
            query.bindValue(6, layout);
            QVERIFY(query.exec());
        };
        insert(QStringLiteral("Plains"), QStringLiteral("Basic Land — Plains"), {},
               QStringLiteral("|commander:legal|modern:legal|vintage:legal|"));
        insert(QStringLiteral("Snow-Covered Plains"), QStringLiteral("Basic Snow Land — Plains"),
               QStringLiteral("W"), QStringLiteral("|modern:legal|"));
        insert(QStringLiteral("Lightning Bolt"), QStringLiteral("Instant"), QStringLiteral("R"),
               QStringLiteral("|commander:legal|modern:legal|vintage:legal|"));
        insert(QStringLiteral("Counterspell"), QStringLiteral("Instant"), QStringLiteral("U"),
               QStringLiteral("|commander:legal|legacy:legal|vintage:legal|"));
        insert(QStringLiteral("Banned Card"), QStringLiteral("Sorcery"), {},
               QStringLiteral("|modern:banned|"));
        insert(QStringLiteral("Black Lotus"), QStringLiteral("Artifact"), {},
               QStringLiteral("|vintage:restricted|"));
        insert(QStringLiteral("White Commander"), QStringLiteral("Legendary Creature — Human"),
               QStringLiteral("W"), QStringLiteral("|commander:legal|"));
        insert(QStringLiteral("Esika, God of the Tree // Esika, God of the Tree"),
               QStringLiteral("Card"), {}, QStringLiteral("|commander:not_legal|"),
               QStringLiteral("art_series"), QStringLiteral("esika-art"));
        insert(QStringLiteral("Esika, God of the Tree // The Prismatic Bridge"),
               QStringLiteral("Legendary Creature — God // Legendary Enchantment"),
               QStringLiteral("WUBRG"), QStringLiteral("|commander:legal|"),
               QStringLiteral("modal_dfc"), QStringLiteral("esika"));
        insert(QStringLiteral("The Legend of Roku // Avatar Roku"),
               QStringLiteral("Legendary Enchantment — Saga // Legendary Creature — Avatar"),
               QStringLiteral("R"), QStringLiteral("|commander:legal|"),
               QStringLiteral("transform"), QStringLiteral("roku"));
        database.close();
    }
    QSqlDatabase::removeDatabase(connection);
}

} // namespace

class TestDeckLegality : public QObject
{
    Q_OBJECT

  private slots:
    void acceptsLegalModernDeck() const;
    void rejectsBannedAndRestrictedCards() const;
    void warnsAboutCommanderColorIdentity() const;
    void resolvesDoubleFacedFrontFaceNames() const;
    void degradesWhenCatalogIsMissing() const;
};

void TestDeckLegality::acceptsLegalModernDeck() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString databasePath = storage.filePath(QStringLiteral("cards.sqlite"));
    createCatalog(databasePath);
    QVariantMap request =
        deck(QStringLiteral("modern"), {card(QStringLiteral("Snow-Covered Plains"), 56),
                                        card(QStringLiteral("Lightning Bolt"), 4)});
    request.insert(QStringLiteral("validationRevision"), quint64{42});
    const QVariantList results = DeckLegalityService::validate(databasePath, {request});
    QCOMPARE(results.size(), 1);
    QVERIFY(results.first().toMap().value(QStringLiteral("valid")).toBool());
    QVERIFY(results.first().toMap().value(QStringLiteral("verified")).toBool());
    QCOMPARE(results.first().toMap().value(QStringLiteral("validationRevision")).toULongLong(),
             quint64{42});
}

void TestDeckLegality::rejectsBannedAndRestrictedCards() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString databasePath = storage.filePath(QStringLiteral("cards.sqlite"));
    createCatalog(databasePath);
    QVariantList results = DeckLegalityService::validate(
        databasePath, {deck(QStringLiteral("modern"), {card(QStringLiteral("Plains"), 59),
                                                       card(QStringLiteral("Banned Card"), 1)})});
    QVERIFY(!results.first().toMap().value(QStringLiteral("valid")).toBool());
    QVERIFY(results.first()
                .toMap()
                .value(QStringLiteral("status"))
                .toString()
                .contains(QStringLiteral("not legal")));

    results = DeckLegalityService::validate(
        databasePath, {deck(QStringLiteral("vintage"), {card(QStringLiteral("Plains"), 58),
                                                        card(QStringLiteral("Black Lotus"), 2)})});
    QVERIFY(!results.first().toMap().value(QStringLiteral("valid")).toBool());
    QVERIFY(results.first()
                .toMap()
                .value(QStringLiteral("issues"))
                .toStringList()
                .join(QLatin1Char(' '))
                .contains(QStringLiteral("restricted")));
}

void TestDeckLegality::warnsAboutCommanderColorIdentity() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString databasePath = storage.filePath(QStringLiteral("cards.sqlite"));
    createCatalog(databasePath);
    const QVariantList results = DeckLegalityService::validate(
        databasePath,
        {deck(QStringLiteral("commander"),
              {card(QStringLiteral("White Commander"), 1), card(QStringLiteral("Plains"), 97),
               card(QStringLiteral("Lightning Bolt"), 1), card(QStringLiteral("Counterspell"), 1)},
              {}, {QStringLiteral("White Commander")})});
    const QVariantMap result = results.first().toMap();
    QVERIFY(result.value(QStringLiteral("valid")).toBool());
    QVERIFY(result.value(QStringLiteral("verified")).toBool());
    QCOMPARE(result.value(QStringLiteral("status")).toString(),
             QStringLiteral("2 cards may be outside the commanders' color identity."));
    QCOMPARE(result.value(QStringLiteral("warnings")).toStringList(),
             QStringList{QStringLiteral("2 cards may be outside the commanders' color identity.")});
    const QStringList issues = result.value(QStringLiteral("issues")).toStringList();
    QCOMPARE(issues.size(), 3);
    QVERIFY(
        issues.contains(QStringLiteral("Counterspell is outside the commanders' color identity.")));
    QVERIFY(issues.contains(
        QStringLiteral("Lightning Bolt is outside the commanders' color identity.")));
}

void TestDeckLegality::resolvesDoubleFacedFrontFaceNames() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString databasePath = storage.filePath(QStringLiteral("cards.sqlite"));
    createCatalog(databasePath);
    const QVariantList results = DeckLegalityService::validate(
        databasePath,
        {deck(QStringLiteral("commander"),
              {card(QStringLiteral("Esika, God of the Tree"), 1),
               card(QStringLiteral("The Legend of Roku"), 1), card(QStringLiteral("Plains"), 98)},
              {}, {QStringLiteral("Esika, God of the Tree")})});
    QCOMPARE(results.size(), 1);
    QVERIFY2(results.first().toMap().value(QStringLiteral("valid")).toBool(),
             qPrintable(results.first()
                            .toMap()
                            .value(QStringLiteral("issues"))
                            .toStringList()
                            .join(QLatin1Char('\n'))));
}

void TestDeckLegality::degradesWhenCatalogIsMissing() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QVariantList results = DeckLegalityService::validate(
        storage.filePath(QStringLiteral("missing.sqlite")),
        {deck(QStringLiteral("modern"), {card(QStringLiteral("Plains"), 60)})});
    QVERIFY(results.first().toMap().value(QStringLiteral("valid")).toBool());
    QVERIFY(!results.first().toMap().value(QStringLiteral("verified")).toBool());
}

QTEST_MAIN(TestDeckLegality)

#include "decklegality_test.moc"
