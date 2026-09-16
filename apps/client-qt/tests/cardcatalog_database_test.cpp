// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "cardcatalog_test.h"

#include "models/DeckLibraryModel.h"
#include "services/BackgroundTaskPools.h"
#include "services/CardArtCache.h"
#include "services/CardArtManager.h"
#include "services/CatalogRepository.h"

#include <QScopeGuard>
#include <QSemaphore>

namespace {

class SupportNetworkAccessManager final : public QNetworkAccessManager
{
  public:
    QList<QUrl> requestedUrls;
    bool failImages = false;
    bool failMtgch = false;

  protected:
    QNetworkReply *createRequest(Operation, const QNetworkRequest &request, QIODevice *) override
    {
        requestedUrls.append(request.url());
        if (request.url().host() == u"api.scryfall.com"_s)
            return new StaticNetworkReply(request, "{}", "application/json", this, 404,
                                          QNetworkReply::ContentNotFoundError);
        if (request.url().host() == u"mtgch.com"_s) {
            if (failMtgch)
                return new StaticNetworkReply(request, "{}", "application/json", this, 404,
                                              QNetworkReply::ContentNotFoundError);
            const auto parts = request.url().path().split(u'/', Qt::SkipEmptyParts);
            const QString number = parts.last();
            const QString set = parts.at(parts.size() - 2).toUpper();
            const bool emblem = set == u"TTST"_s && number == u"1"_s;
            const bool goblin = set == u"TTST"_s && number == u"2"_s;
            const QString name = emblem   ? u"Teferi Emblem"_s
                                 : goblin ? u"Goblin"_s
                                          : u"Lightning Bolt"_s;
            const QString slug = emblem ? u"emblem"_s : goblin ? u"goblin"_s : u"bolt"_s;
            const QJsonObject object{
                {u"name"_s, name},
                {u"set"_s, set},
                {u"collector_number"_s, number},
                {u"type_line"_s, emblem   ? u"Emblem — Teferi"_s
                                 : goblin ? u"Token Creature — Goblin"_s
                                          : u"Instant"_s},
                {u"zhs_name"_s, emblem   ? u"泰菲力徽记"_s
                                : goblin ? u"地精"_s
                                         : u"闪电击"_s},
                {u"zhs_type_line"_s, emblem   ? u"徽记 ～ 泰菲力"_s
                                     : goblin ? u"衍生生物 ～ 地精"_s
                                              : u"瞬间"_s},
                {u"text"_s,
                 emblem
                     ? u"Whenever you draw a card, exile target permanent an opponent controls."_s
                     : u"Haste"_s},
                {u"zhs_text"_s,
                 emblem ? u"每当你抓一张牌时，放逐目标由对手操控的永久物。"_s : u"敏捷"_s},
                {u"image_uris"_s,
                 QJsonObject{{u"normal"_s, u"https://images.test/"_s + slug + u"-en.png"_s}}},
                {u"zhs_image_uris"_s,
                 emblem ? QJsonValue(QJsonValue::Null)
                        : QJsonValue(QJsonObject{
                              {u"normal"_s, u"https://images.test/"_s + slug + u"-zh.png"_s}})}};
            return new StaticNetworkReply(request, QJsonDocument(object).toJson(),
                                          "application/json", this);
        }
        if (failImages)
            return new StaticNetworkReply(request, {}, "image/png", this, 404,
                                          QNetworkReply::ContentNotFoundError);
        QImage image(1, 1, QImage::Format_ARGB32);
        image.fill(Qt::green);
        QByteArray png;
        QBuffer buffer(&png);
        buffer.open(QIODevice::WriteOnly);
        image.save(&buffer, "PNG");
        return new StaticNetworkReply(request, png, "image/png", this);
    }
};

QJsonObject supportFixture(const QString &name, const QString &layout, const QString &number)
{
    return {{u"id"_s, u"support-"_s + number},
            {u"oracle_id"_s, u"oracle-support-"_s + number},
            {u"name"_s, name},
            {u"type_line"_s, layout == u"emblem"_s ? u"Emblem — Teferi"_s : u"Token Creature"_s},
            {u"set"_s, u"ttst"_s},
            {u"collector_number"_s, number},
            {u"lang"_s, u"en"_s},
            {u"layout"_s, layout},
            {u"oracle_text"_s, u"Test ability."_s},
            {u"image_uris"_s,
             QJsonObject{{u"normal"_s, u"https://images.test/support-"_s + number + u".png"_s}}}};
}

CardCatalog::ImportResult importSupportFixture(const QString &root, const QJsonArray &cards)
{
    const QString sourcePath = QDir(root).filePath(u"support.json"_s);
    QFile source(sourcePath);
    if (!source.open(QIODevice::WriteOnly))
        return {};
    const QByteArray bytes = QJsonDocument(cards).toJson();
    if (source.write(bytes) != bytes.size())
        return {};
    source.close();
    return CardCatalog::importBulkFile(sourcePath, QDir(root).filePath(u"cards.sqlite"_s),
                                       u"default_cards"_s);
}

bool writeAuditTokenCatalog(const QString &root, const QString &name = u"Goblin"_s)
{
    const QJsonObject token{{u"id"_s, u"audit-goblin"_s},
                            {u"oracle_id"_s, u"audit-oracle-goblin"_s},
                            {u"name"_s, name},
                            {u"type_line"_s, u"Token Creature — Goblin"_s},
                            {u"set"_s, u"tneo"_s},
                            {u"collector_number"_s, u"12"_s},
                            {u"lang"_s, u"en"_s},
                            {u"layout"_s, u"token"_s},
                            {u"power"_s, u"1"_s},
                            {u"toughness"_s, u"1"_s},
                            {u"oracle_text"_s, u"Haste"_s}};
    const QString sourcePath = QDir(root).filePath(u"tokens.json"_s);
    QFile source(sourcePath);
    if (!source.open(QIODevice::WriteOnly))
        return false;
    const QByteArray bytes = QJsonDocument(QJsonArray{token}).toJson();
    if (source.write(bytes) != bytes.size())
        return false;
    source.close();
    const QString aliasesPath = QDir(root).filePath(u"token-aliases.tar.gz"_s);
    const QByteArray aliases = QJsonDocument(QJsonObject{{u"oracle_id"_s, u"audit-oracle-goblin"_s},
                                                         {u"name"_s, name},
                                                         {u"translated_name"_s, u"地精"_s}})
                                   .toJson(QJsonDocument::Compact) +
                               '\n';
    if (!writeTestTarGzip(aliasesPath, QByteArrayLiteral("./zhs_oracle.json"), aliases))
        return false;
    return CardCatalog::importBulkFile(sourcePath, QDir(root).filePath(u"cards.sqlite"_s),
                                       u"default_cards"_s, aliasesPath)
        .ok;
}

} // namespace

void TestCardCatalog::searchesSupportKindsBeforeResultLimit() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QJsonArray cards;
    for (int index = 0; index < 65; ++index)
        cards.append(
            supportFixture(u"A Token %1"_s.arg(index), u"token"_s, QString::number(index)));
    cards.append(supportFixture(u"ZZ Teferi Emblem"_s, u"emblem"_s, u"100"_s));
    cards.append(supportFixture(u"Double // Back"_s, u"double_faced_token"_s, u"101"_s));
    cards.append(supportFixture(u"Normal Spell"_s, u"front_card"_s, u"105"_s));
    cards.append(supportFixture(u"Normal Spell"_s, u"normal"_s, u"102"_s));
    cards.append(supportFixture(u"Normal Front // Normal Back"_s, u"transform"_s, u"103"_s));
    cards.append(supportFixture(u"Normal Spell"_s, u"art_series"_s, u"104"_s));
    const auto imported = importSupportFixture(storage.path(), cards);
    QVERIFY2(imported.ok, qPrintable(imported.error));
    QCOMPARE(imported.tokenCount, 67);

    {
        // Release the repository's read lock before CardCatalog's constructor
        // performs startup recovery under CatalogStorage's write lock.
        hexproof::client::CatalogRepository repository(storage.filePath(u"cards.sqlite"_s));
        const auto all = repository.searchTokens({}, u"en"_s);
        QVERIFY2(all.error.isEmpty(), qPrintable(all.error));
        QCOMPARE(all.cards.size(), 60);
        const auto emblems = repository.searchTokens({}, u"en"_s, u"emblem"_s);
        QCOMPARE(emblems.cards.size(), 1);
        QCOMPARE(emblems.cards.first().toMap().value(u"kind"_s).toString(), u"emblem"_s);
        QCOMPARE(repository.searchTokens(u"TST #100"_s, u"en"_s, u"emblem"_s).cards.size(), 1);
        QVERIFY(repository.searchTokens(u"TST #100"_s, u"en"_s, u"token"_s).cards.isEmpty());
        const auto doubleToken = repository.searchTokens(u"Double"_s, u"en"_s, u"token"_s);
        QCOMPARE(doubleToken.cards.size(), 1);
        QCOMPARE(doubleToken.cards.first().toMap().value(u"kind"_s).toString(), u"token"_s);
        const auto playable = repository.search({}, u"en"_s, {}, {}, {}, {}, {}, {});
        QVERIFY2(playable.error.isEmpty(), qPrintable(playable.error));
        QCOMPARE(playable.cards.size(), 2);
        for (const QVariant &card : playable.cards) {
            QVERIFY(card.toMap().value(u"name"_s).toString().startsWith(u"Normal"_s));
            QCOMPARE(card.toMap().value(u"versionCount"_s).toInt(), 1);
        }
        QVERIFY(repository.printings(u"ZZ Teferi Emblem"_s, u"en"_s).isEmpty());
        QVERIFY(repository.lookup({u"ZZ Teferi Emblem"_s, u"TTST"_s, u"100"_s, u"en"_s}).valid());
        QCOMPARE(repository.printings(u"Normal Spell"_s, u"en"_s).size(), 1);
        QCOMPARE(repository.lookup({u"Normal Spell"_s, {}, {}, u"en"_s}).collectorNumber, u"102"_s);
        QCOMPARE(
            repository.lookup({u"Normal Spell"_s, u"TTST"_s, u"105"_s, u"en"_s}).collectorNumber,
            u"105"_s);
        QString layout;
        repository.cardFaces(u"Normal Spell"_s, {}, {}, nullptr, &layout);
        QCOMPARE(layout, u"normal"_s);
    }

    CardCatalog catalog(storage.path());
    catalog.searchTokens({}, u"token"_s);
    catalog.searchTokens({}, u"emblem"_s);
    QTRY_COMPARE(catalog.tokenSearchResults().size(), 1);
    QCOMPARE(catalog.tokenSearchResults().first().toMap().value(u"kind"_s).toString(), u"emblem"_s);
    catalog.setLanguage(u"zh"_s);
    QTRY_COMPARE(catalog.tokenSearchResults().size(), 1);
    QCOMPARE(catalog.tokenSearchResults().first().toMap().value(u"kind"_s).toString(), u"emblem"_s);
    QSignalSpy metadata(&catalog, &CardCatalog::tokenMetadataAvailable);
    catalog.enrichTokens({QVariantMap{{u"name"_s, u"ZZ Teferi Emblem"_s},
                                      {u"setCode"_s, u"TTST"_s},
                                      {u"collectorNumber"_s, u"100"_s}}});
    QTRY_COMPARE(metadata.count(), 1);
    QCOMPARE(metadata.first().first().toList().first().toMap().value(u"kind"_s).toString(),
             u"emblem"_s);
}

void TestCardCatalog::emblemOnlyCatalogRemainsInstalledAfterLegacyCountRecovery() const
{
    QTemporaryDir source;
    QTemporaryDir destination;
    QVERIFY(source.isValid());
    QVERIFY(destination.isValid());
    const auto imported = importSupportFixture(
        source.path(), {supportFixture(u"Teferi Emblem"_s, u"emblem"_s, u"1"_s)});
    QVERIFY2(imported.ok, qPrintable(imported.error));
    QCOMPARE(imported.tokenCount, 1);
    const QString connectionName = u"legacy-emblem-count"_s;
    {
        auto database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(source.filePath(u"cards.sqlite"_s));
        QVERIFY(database.open());
        QSqlQuery query(database);
        QVERIFY(query.exec(u"UPDATE metadata SET value = '0' WHERE key = 'token_count'"_s));
    }
    QSqlDatabase::removeDatabase(connectionName);
    CardCatalog recovered(source.path());
    QVERIFY(recovered.tokenCatalogInstalled());
    recovered.searchTokens({}, u"emblem"_s);
    QTRY_COMPARE(recovered.tokenSearchResults().size(), 1);
    CardCatalog installed(destination.path());
    installed.searchTokens({}, u"emblem"_s);
    installed.importCatalogFile(QUrl::fromLocalFile(source.filePath(u"cards.sqlite"_s)),
                                u"default_cards"_s);
    QTRY_VERIFY(!installed.busy());
    QVERIFY2(installed.lastError().isEmpty(), qPrintable(installed.lastError()));
    QVERIFY(installed.tokenCatalogInstalled());
    QTRY_COMPARE(installed.tokenSearchResults().size(), 1);
    QCOMPARE(installed.tokenSearchResults().first().toMap().value(u"kind"_s).toString(),
             u"emblem"_s);
}

void TestCardCatalog::tokenDisplayNameUsesLocalLanguageWithoutNetwork() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QJsonObject emblem = supportFixture(u"Teferi Emblem"_s, u"emblem"_s, u"1"_s);
    QJsonObject chinese = emblem;
    chinese.insert(u"id"_s, u"emblem-zh"_s);
    chinese.insert(u"lang"_s, u"zhs"_s);
    chinese.insert(u"printed_name"_s, u"泰菲力徽记"_s);
    chinese.insert(u"printed_type_line"_s, u"徽记 ～ 泰菲力"_s);
    const auto imported = importSupportFixture(storage.path(), {emblem, chinese});
    QVERIFY2(imported.ok, qPrintable(imported.error));
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    QCOMPARE(catalog.tokenDisplayName(u"Teferi Emblem"_s, u"TTST"_s, u"1"_s), u"Teferi Emblem"_s);
    catalog.setLanguage(u"zh"_s);
    QCOMPARE(catalog.tokenDisplayName(u"Teferi Emblem"_s, u"TTST"_s, u"1"_s), u"泰菲力徽记"_s);
    QCOMPARE(catalog.tokenDisplayName(u"Unknown Emblem"_s, u"NONE"_s, u"9"_s), u"Unknown Emblem"_s);
    catalog.setLanguage(u"en"_s);
    QCOMPARE(catalog.tokenDisplayName(u"Teferi Emblem"_s, u"TTST"_s, u"1"_s), u"Teferi Emblem"_s);
    QVERIFY(network.requestedUrls.isEmpty());
}

void TestCardCatalog::cardDisplayNamesResolveCatalogNamesAndFaces() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QJsonObject bolt = supportFixture(u"Lightning Bolt"_s, u"normal"_s, u"1"_s);
    bolt.insert(u"type_line"_s, u"Instant"_s);
    QJsonObject chinese = bolt;
    chinese.insert(u"id"_s, u"bolt-zh"_s);
    chinese.insert(u"lang"_s, u"zhs"_s);
    chinese.insert(u"printed_name"_s, u"闪电击"_s);
    QJsonObject split = supportFixture(u"Fire // Ice"_s, u"split"_s, u"2"_s);
    split.insert(u"type_line"_s, u"Instant // Instant"_s);
    split.insert(u"card_faces"_s,
                 QJsonArray{QJsonObject{{u"name"_s, u"Fire"_s}, {u"type_line"_s, u"Instant"_s}},
                            QJsonObject{{u"name"_s, u"Ice"_s}, {u"type_line"_s, u"Instant"_s}}});
    QJsonObject splitChinese = split;
    splitChinese.insert(u"id"_s, u"split-zh"_s);
    splitChinese.insert(u"lang"_s, u"zhs"_s);
    splitChinese.insert(u"printed_name"_s, u"烈火 // 寒冰"_s);
    splitChinese.insert(u"card_faces"_s, QJsonArray{QJsonObject{{u"name"_s, u"Fire"_s},
                                                                {u"printed_name"_s, u"烈火"_s},
                                                                {u"type_line"_s, u"Instant"_s}},
                                                    QJsonObject{{u"name"_s, u"Ice"_s},
                                                                {u"printed_name"_s, u"寒冰"_s},
                                                                {u"type_line"_s, u"Instant"_s}}});
    const auto imported =
        importSupportFixture(storage.path(), {bolt, chinese, split, splitChinese});
    QVERIFY2(imported.ok, qPrintable(imported.error));
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    QCOMPARE(catalog.cardDisplayName(u"Lightning Bolt"_s), u"Lightning Bolt"_s);
    catalog.setLanguage(u"zh"_s);
    QCOMPARE(catalog.cardDisplayName(u"Lightning Bolt"_s), u"闪电击"_s);
    QCOMPARE(catalog.cardDisplayName(u"Fire // Ice"_s), u"烈火 // 寒冰"_s);
    QCOMPARE(catalog.cardDisplayName(u"Fire"_s), u"烈火"_s);
    QCOMPARE(catalog.cardDisplayName(u"Ice"_s), u"寒冰"_s);
    QCOMPARE(catalog.cardDisplayName(u"Unknown %2"_s), u"Unknown %2"_s);
    QCOMPARE(catalog.cardDisplayName({}), QString{});
    catalog.setLanguage(u"en"_s);
    QCOMPARE(catalog.cardDisplayName(u"Lightning Bolt"_s), u"Lightning Bolt"_s);
    QVERIFY(network.requestedUrls.isEmpty());
}

void TestCardCatalog::cardDisplayNamesUseCachedTextWithoutArtwork() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    {
        hexproof::client::CardArtCache cache(storage.path());
        CardCatalog::CardRecord record;
        record.name = u"Cached Adept"_s;
        record.requestedName = record.name;
        record.localizedName = u"缓存学徒"_s;
        record.setCode = u"TST"_s;
        record.collectorNumber = u"1"_s;
        const QString key = cache.key(record.name, u"zh"_s, record.setCode, record.collectorNumber);
        cache.rememberSuccess(key, record);
        const hexproof::client::CardRequest request{record.name, {}, {}, u"zh"_s};
        QCOMPARE(cache.localizedMetadataForName(request).localizedName, record.localizedName);
        record.name = u"Renamed Adept"_s;
        record.requestedName = record.name;
        record.localizedName = u"新名称学徒"_s;
        record.imageLanguage = u"en"_s;
        cache.rememberSuccess(key, record);
        QVERIFY(!cache.localizedMetadataForName(request).valid());
        QVERIFY(cache.save());
    }
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    QVERIFY(!catalog.installed());
    catalog.setLanguage(u"zh"_s);
    QCOMPARE(catalog.cardDisplayName(u"Renamed Adept"_s), u"新名称学徒"_s);
    QCOMPARE(catalog.cardDisplayName(u"Cached Adept"_s), u"Cached Adept"_s);
    QVERIFY(network.requestedUrls.isEmpty());
}

void TestCardCatalog::cachesSupportCardsAlongsidePreferredLanguage() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const auto imported = importSupportFixture(
        storage.path(), {supportFixture(u"Teferi Emblem"_s, u"emblem"_s, u"1"_s),
                         supportFixture(u"Goblin"_s, u"token"_s, u"2"_s)});
    QVERIFY2(imported.ok, qPrintable(imported.error));
    SupportNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"zh"_s);
    QSignalSpy cached(&catalog, &CardCatalog::cardCacheFinished);
    const QVariantList cards{QVariantMap{{u"name"_s, u"Teferi Emblem"_s},
                                         {u"setCode"_s, u"TTST"_s},
                                         {u"collectorNumber"_s, u"1"_s},
                                         {u"kind"_s, u"emblem"_s}},
                             QVariantMap{{u"name"_s, u"Goblin"_s},
                                         {u"setCode"_s, u"TTST"_s},
                                         {u"collectorNumber"_s, u"2"_s},
                                         {u"kind"_s, u"token"_s}},
                             QVariantMap{{u"name"_s, u"Lightning Bolt"_s},
                                         {u"setCode"_s, u"M11"_s},
                                         {u"collectorNumber"_s, u"146"_s}}};
    catalog.cacheCardsIncrementally(cards);
    QTRY_COMPARE_WITH_TIMEOUT(cached.count(), 3, 5'000);
    for (const auto &signal : cached)
        QVERIFY(signal.at(3).toBool());
    QVERIFY(!catalog.tokenImageSource(u"Teferi Emblem"_s, u"TTST"_s, u"1"_s).isEmpty());
    QVERIFY(!catalog.tokenImageSource(u"Goblin"_s, u"TTST"_s, u"2"_s).isEmpty());
    QVERIFY(!catalog.imageSource(u"Lightning Bolt"_s, u"M11"_s, u"146"_s).isEmpty());
    QVERIFY(network.requestedUrls.contains(QUrl(u"https://images.test/emblem-en.png"_s)));
    QVERIFY(network.requestedUrls.contains(QUrl(u"https://images.test/goblin-zh.png"_s)));
    QVERIFY(network.requestedUrls.contains(QUrl(u"https://images.test/bolt-zh.png"_s)));
    QCOMPARE(catalog.tokenImageSource(u"Goblin"_s, u"TTST"_s, u"2"_s),
             catalog.imageSource(u"Goblin"_s, u"TTST"_s, u"2"_s));
    const auto details = catalog.tokenDetails(u"Teferi Emblem"_s, u"TTST"_s, u"1"_s);
    QCOMPARE(details.value(u"displayName"_s).toString(), u"泰菲力徽记"_s);
    QCOMPARE(details.value(u"oracleText"_s).toString(),
             u"每当你抓一张牌时，放逐目标由对手操控的永久物。"_s);
    const qsizetype requests = network.requestedUrls.size();
    catalog.retryCards(cards);
    QTRY_COMPARE(cached.count(), 6);
    QCOMPARE(network.requestedUrls.size(), requests);
}

void TestCardCatalog::tokenSearchRefreshesOnLanguageChange() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY(writeAuditTokenCatalog(storage.path()));
    CardCatalog catalog(storage.path());
    catalog.searchTokens(u"gob"_s);
    QTRY_COMPARE(catalog.tokenSearchResults().size(), 1);
    QCOMPARE(catalog.tokenSearchResults().first().toMap().value(u"displayName"_s).toString(),
             u"Goblin"_s);
    catalog.setLanguage(u"zh"_s);
    QTRY_COMPARE(catalog.tokenSearchResults().size(), 1);
    QTRY_COMPARE(catalog.tokenSearchResults().first().toMap().value(u"displayName"_s).toString(),
                 u"地精"_s);
    catalog.searchTokens(QString());
    QTRY_COMPARE(catalog.tokenSearchResults().size(), 1);
    catalog.setLanguage(u"en"_s);
    QTRY_COMPARE(catalog.tokenSearchResults().size(), 1);
    QCOMPARE(catalog.tokenSearchResults().first().toMap().value(u"displayName"_s).toString(),
             u"Goblin"_s);
}

void TestCardCatalog::supportDetailsAndArtSurviveLanguageChangesAndRestart() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const auto imported = importSupportFixture(
        storage.path(), {supportFixture(u"Teferi Emblem"_s, u"emblem"_s, u"1"_s),
                         supportFixture(u"Goblin"_s, u"token"_s, u"2"_s)});
    QVERIFY2(imported.ok, qPrintable(imported.error));
    const QVariantMap emblem{{u"name"_s, u"Teferi Emblem"_s},
                             {u"setCode"_s, u"TTST"_s},
                             {u"collectorNumber"_s, u"1"_s},
                             {u"kind"_s, u"emblem"_s}};
    const QVariantMap goblin{{u"name"_s, u"Goblin"_s},
                             {u"setCode"_s, u"TTST"_s},
                             {u"collectorNumber"_s, u"2"_s},
                             {u"kind"_s, u"token"_s}};
    SupportNetworkAccessManager network;
    QString chineseImage;
    QString fallbackImage;
    {
        CardCatalog catalog(storage.path(), &network);
        catalog.setLanguage(u"zh"_s);
        QSignalSpy cached(&catalog, &CardCatalog::cardCacheFinished);
        catalog.cacheToken(emblem);
        catalog.cacheToken(goblin);
        QTRY_COMPARE_WITH_TIMEOUT(cached.count(), 2, 5'000);
        chineseImage = catalog.tokenImageSource(u"Goblin"_s, u"TTST"_s, u"2"_s);
        fallbackImage = catalog.tokenImageSource(u"Teferi Emblem"_s, u"TTST"_s, u"1"_s);
        QVERIFY(!chineseImage.isEmpty());
        QVERIFY(!fallbackImage.isEmpty());
        QCOMPARE(
            catalog.tokenDetails(u"Goblin"_s, u"TTST"_s, u"2"_s).value(u"oracleText"_s).toString(),
            u"敏捷"_s);
        catalog.setLanguage(u"en"_s);
        catalog.cacheToken(emblem);
        catalog.cacheToken(goblin);
        QTRY_COMPARE_WITH_TIMEOUT(cached.count(), 4, 5'000);
        QCOMPARE(catalog.tokenDisplayName(u"Goblin"_s, u"TTST"_s, u"2"_s), u"Goblin"_s);
        QCOMPARE(
            catalog.tokenDetails(u"Goblin"_s, u"TTST"_s, u"2"_s).value(u"oracleText"_s).toString(),
            u"Test ability."_s);
        QVERIFY(catalog.tokenImageSource(u"Goblin"_s, u"TTST"_s, u"2"_s) != chineseImage);
        catalog.setLanguage(u"zh"_s);
        QCOMPARE(catalog.tokenImageSource(u"Goblin"_s, u"TTST"_s, u"2"_s), chineseImage);
    }
    const qsizetype requests = network.requestedUrls.size();
    CardCatalog restored(storage.path(), &network);
    restored.setLanguage(u"zh"_s);
    QCOMPARE(restored.tokenImageSource(u"Goblin"_s, u"TTST"_s, u"2"_s), chineseImage);
    QCOMPARE(restored.tokenImageSource(u"Teferi Emblem"_s, u"TTST"_s, u"1"_s), fallbackImage);
    QCOMPARE(restored.tokenDetails(u"Teferi Emblem"_s, u"TTST"_s, u"1"_s)
                 .value(u"oracleText"_s)
                 .toString(),
             u"每当你抓一张牌时，放逐目标由对手操控的永久物。"_s);
    QCOMPARE(network.requestedUrls.size(), requests);
}

void TestCardCatalog::legacySupportArtDoesNotSuppressChineseMetadata() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const auto imported = importSupportFixture(
        storage.path(), {supportFixture(u"Teferi Emblem"_s, u"emblem"_s, u"1"_s),
                         supportFixture(u"Goblin"_s, u"token"_s, u"2"_s)});
    QVERIFY2(imported.ok, qPrintable(imported.error));
    QString oldEnglishPath;
    {
        hexproof::client::CardArtCache cache(storage.path());
        for (const QString &number : {u"1"_s, u"2"_s}) {
            hexproof::client::CardRecord record;
            record.name = record.requestedName =
                number == u"1"_s ? u"Teferi Emblem"_s : u"Goblin"_s;
            record.setCode = u"TTST"_s;
            record.collectorNumber = number;
            record.imageLanguage = u"en"_s;
            record.imageUrl = u"https://images.test/old-"_s + number + u".png"_s;
            record.imagePath = cache.imagePath(record.name, record.imageUrl, u"en"_s);
            record.resolutionVersion = kCardResolutionVersion;
            QImage image(1, 1, QImage::Format_ARGB32);
            image.fill(Qt::blue);
            QVERIFY(image.save(record.imagePath, "PNG"));
            cache.rememberSuccess(
                cache.key(record.name, number == u"1"_s ? u"zh"_s : u"en"_s, u"TTST"_s, number),
                record);
            if (number == u"2"_s)
                oldEnglishPath = record.imagePath;
        }
        QVERIFY(cache.save());
    }
    SupportNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"zh"_s);
    QCOMPARE(catalog.tokenImageSource(u"Goblin"_s, u"TTST"_s, u"2"_s),
             QUrl::fromLocalFile(oldEnglishPath).toString());
    QVERIFY(catalog.imageSource(u"Goblin"_s, u"TTST"_s, u"2"_s).isEmpty());
    QSignalSpy cached(&catalog, &CardCatalog::cardCacheFinished);
    catalog.cacheToken(
        {{u"name"_s, u"Goblin"_s}, {u"setCode"_s, u"TTST"_s}, {u"collectorNumber"_s, u"2"_s}});
    catalog.cacheToken({{u"name"_s, u"Teferi Emblem"_s},
                        {u"setCode"_s, u"TTST"_s},
                        {u"collectorNumber"_s, u"1"_s},
                        {u"kind"_s, u"emblem"_s}});
    QTRY_COMPARE_WITH_TIMEOUT(cached.count(), 2, 5'000);
    QVERIFY(network.requestedUrls.contains(QUrl(u"https://images.test/goblin-zh.png"_s)));
    QVERIFY(QFileInfo::exists(oldEnglishPath));
    QVERIFY(catalog.tokenImageSource(u"Goblin"_s, u"TTST"_s, u"2"_s) !=
            QUrl::fromLocalFile(oldEnglishPath).toString());
    QCOMPARE(catalog.tokenDetails(u"Goblin"_s, u"TTST"_s, u"2"_s).value(u"oracleText"_s).toString(),
             u"敏捷"_s);
    QCOMPARE(catalog.tokenDetails(u"Teferi Emblem"_s, u"TTST"_s, u"1"_s)
                 .value(u"oracleText"_s)
                 .toString(),
             u"每当你抓一张牌时，放逐目标由对手操控的永久物。"_s);
}

void TestCardCatalog::battlefieldTokensRefreshLegacyChineseMetadata() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const auto imported =
        importSupportFixture(storage.path(), {supportFixture(u"Goblin"_s, u"token"_s, u"2"_s)});
    QVERIFY2(imported.ok, qPrintable(imported.error));
    {
        hexproof::client::CardArtCache cache(storage.path());
        hexproof::client::CardRecord record;
        record.name = record.requestedName = u"Goblin"_s;
        record.setCode = u"TTST"_s;
        record.collectorNumber = u"2"_s;
        record.imageLanguage = u"en"_s;
        record.imageUrl = u"https://images.test/legacy-goblin.png"_s;
        record.imagePath = cache.imagePath(record.name, record.imageUrl, u"zh"_s);
        record.oracleText = u"Haste"_s;
        record.oracleTextLanguage = u"en"_s;
        record.resolutionVersion = kCardResolutionVersion;
        QImage image(1, 1, QImage::Format_ARGB32);
        image.fill(Qt::blue);
        QVERIFY(image.save(record.imagePath, "PNG"));
        cache.rememberSuccess(cache.key(record.name, u"zh"_s, u"TTST"_s, u"2"_s), record);
        QVERIFY(cache.save());
    }
    SupportNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"zh"_s);
    QSignalSpy cached(&catalog, &CardCatalog::cardCacheFinished);
    // Public battlefield snapshots use token:true rather than saved-deck kind.
    catalog.prioritizeCards({QVariantMap{{u"name"_s, u"Goblin"_s},
                                         {u"setCode"_s, u"TTST"_s},
                                         {u"collectorNumber"_s, u"2"_s},
                                         {u"token"_s, true}}});
    QTRY_COMPARE_WITH_TIMEOUT(cached.count(), 1, 5'000);
    QVERIFY(cached.first().last().toBool());
    QVERIFY(network.requestedUrls.contains(QUrl(u"https://images.test/goblin-zh.png"_s)));
    QCOMPARE(catalog.tokenDetails(u"Goblin"_s, u"TTST"_s, u"2"_s).value(u"oracleText"_s).toString(),
             u"敏捷"_s);
}

void TestCardCatalog::supportRulesSurviveImageFailures() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const auto imported = importSupportFixture(
        storage.path(), {supportFixture(u"Teferi Emblem"_s, u"emblem"_s, u"1"_s)});
    QVERIFY2(imported.ok, qPrintable(imported.error));
    SupportNetworkAccessManager network;
    network.failImages = true;
    {
        CardCatalog catalog(storage.path(), &network);
        catalog.setLanguage(u"zh"_s);
        QSignalSpy cached(&catalog, &CardCatalog::cardCacheFinished);
        const QRegularExpression failure(u"^Card image download failed .+$"_s);
        QTest::ignoreMessage(QtWarningMsg, failure);
        QTest::ignoreMessage(QtWarningMsg, failure);
        catalog.cacheToken({{u"name"_s, u"Teferi Emblem"_s},
                            {u"setCode"_s, u"TTST"_s},
                            {u"collectorNumber"_s, u"1"_s},
                            {u"kind"_s, u"emblem"_s}});
        QTRY_COMPARE_WITH_TIMEOUT(cached.count(), 1, 5'000);
        QVERIFY(!cached.first().at(3).toBool());
        QVERIFY(catalog.tokenImageSource(u"Teferi Emblem"_s, u"TTST"_s, u"1"_s).isEmpty());
        QCOMPARE(catalog.tokenDetails(u"Teferi Emblem"_s, u"TTST"_s, u"1"_s)
                     .value(u"oracleText"_s)
                     .toString(),
                 u"每当你抓一张牌时，放逐目标由对手操控的永久物。"_s);
    }
    CardCatalog restored(storage.path(), &network);
    restored.setLanguage(u"zh"_s);
    QCOMPARE(restored.tokenDetails(u"Teferi Emblem"_s, u"TTST"_s, u"1"_s)
                 .value(u"oracleText"_s)
                 .toString(),
             u"每当你抓一张牌时，放逐目标由对手操控的永久物。"_s);
    network.failImages = false;
    network.failMtgch = true;
    QSignalSpy retried(&restored, &CardCatalog::cardCacheFinished);
    restored.retryCards({QVariantMap{{u"name"_s, u"Teferi Emblem"_s},
                                     {u"setCode"_s, u"TTST"_s},
                                     {u"collectorNumber"_s, u"1"_s},
                                     {u"kind"_s, u"emblem"_s}}});
    QTRY_COMPARE_WITH_TIMEOUT(retried.count(), 1, 5'000);
    QVERIFY(retried.first().last().toBool());
    QVERIFY(!restored.tokenImageSource(u"Teferi Emblem"_s, u"TTST"_s, u"1"_s).isEmpty());
    const QVariantMap details = restored.tokenDetails(u"Teferi Emblem"_s, u"TTST"_s, u"1"_s);
    QCOMPARE(details.value(u"displayName"_s).toString(), u"泰菲力徽记"_s);
    QCOMPARE(details.value(u"typeLine"_s).toString(), u"徽记 ～ 泰菲力"_s);
    QCOMPARE(details.value(u"oracleText"_s).toString(),
             u"每当你抓一张牌时，放逐目标由对手操控的永久物。"_s);
}

void TestCardCatalog::tokenEnrichmentDiscardsEarlierLanguage() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY(writeAuditTokenCatalog(storage.path()));
    CardCatalog catalog(storage.path());
    QSignalSpy metadata(&catalog, &CardCatalog::tokenMetadataAvailable);
    catalog.enrichTokens({QVariantMap{
        {u"name"_s, u"Goblin"_s}, {u"setCode"_s, u"TNEO"_s}, {u"collectorNumber"_s, u"12"_s}}});
    catalog.setLanguage(u"zh"_s);
    QVERIFY(hexproof::client::BackgroundTaskPools::catalogMaintenance()->waitForDone(5'000));
    QTest::qWait(50);
    QCOMPARE(metadata.count(), 0);
    catalog.enrichTokens({QVariantMap{
        {u"name"_s, u"Goblin"_s}, {u"setCode"_s, u"TNEO"_s}, {u"collectorNumber"_s, u"12"_s}}});
    QTRY_COMPARE(metadata.count(), 1);
    QCOMPARE(metadata.first().first().toList().first().toMap().value(u"displayName"_s).toString(),
             u"地精"_s);
}

void TestCardCatalog::tokenSearchRefreshesAfterCatalogReplacement() const
{
    QTemporaryDir storage;
    QTemporaryDir replacement;
    QVERIFY(storage.isValid());
    QVERIFY(replacement.isValid());
    QVERIFY(writeAuditTokenCatalog(storage.path()));
    QVERIFY(writeAuditTokenCatalog(replacement.path(), u"Zombie"_s));
    CardCatalog catalog(storage.path());
    catalog.searchTokens(QString());
    QTRY_COMPARE(catalog.tokenSearchResults().size(), 1);
    QCOMPARE(catalog.tokenSearchResults().first().toMap().value(u"name"_s).toString(), u"Goblin"_s);
    catalog.importCatalogFile(QUrl::fromLocalFile(replacement.filePath(u"cards.sqlite"_s)),
                              u"default_cards"_s);
    QTRY_VERIFY(!catalog.busy());
    QVERIFY2(catalog.lastError().isEmpty(), qPrintable(catalog.lastError()));
    QTRY_COMPARE(catalog.tokenSearchResults().size(), 1);
    QCOMPARE(catalog.tokenSearchResults().first().toMap().value(u"name"_s).toString(), u"Zombie"_s);
}

void TestCardCatalog::emptyTokenRequestInvalidatesEnrichment() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY(writeAuditTokenCatalog(storage.path()));
    CardCatalog catalog(storage.path());
    QSignalSpy metadata(&catalog, &CardCatalog::tokenMetadataAvailable);
    catalog.enrichTokens({QVariantMap{
        {u"name"_s, u"Goblin"_s}, {u"setCode"_s, u"TNEO"_s}, {u"collectorNumber"_s, u"12"_s}}});
    catalog.enrichTokens({});
    QVERIFY(hexproof::client::BackgroundTaskPools::catalogMaintenance()->waitForDone(5'000));
    QTest::qWait(50);
    QCOMPARE(metadata.count(), 0);
}

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

    QTest::ignoreMessage(
        QtWarningMsg,
        QRegularExpression(u"^Official card database manifest request failed: .+$"_s));
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
            {u"rarity"_s, u"common"_s},
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
    QCOMPARE(limitedBolt.value(u"rarity"_s).toString(), u"common"_s);
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
            const bool rider = metadata.value(u"requestedName"_s).toString() == u"Murderous Rider";
            QCOMPARE(metadata.value(u"requestedSetCode"_s).toString(),
                     rider ? QString{} : u"M11"_s);
            QCOMPARE(metadata.value(u"setCode"_s).toString(), rider ? u"ELD"_s : u"M11"_s);
            QCOMPARE(metadata.value(u"collectorNumber"_s).toString(), rider ? u"97"_s : u"149"_s);
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

    {
        QTemporaryDir libraryStorage;
        QVERIFY(libraryStorage.isValid());
        hexproof::client::DeckLibraryModel library(libraryStorage.path());
        connect(&library, &hexproof::client::DeckLibraryModel::cardsNeedMetadata, &catalog,
                &CardCatalog::enrichCardMetadata);
        connect(&catalog, &CardCatalog::cardMetadataAvailable, &library,
                &hexproof::client::DeckLibraryModel::applyCatalogMetadata);
        QSignalSpy caching(&library, &hexproof::client::DeckLibraryModel::cardsNeedCaching);
        QVERIFY(library.importDeck(u"Local metadata only"_s, u"custom"_s,
                                   u"4 Lightning Bolt\n3 Murderous Rider\n"
                                   "Sideboard\n1 Sol Ring (CMM) 396\n"_s));
        const QString id =
            library.data(library.index(0), hexproof::client::DeckLibraryModel::IdRole).toString();
        QVERIFY(library.deckForMatch(id, true).isEmpty());
        QTRY_VERIFY(!library.deckForMatch(id, true).isEmpty());
        const QVariantMap deck = library.deckForMatch(id, true);
        for (const QVariant &value : deck.value(u"mainboard"_s).toList()) {
            const QVariantMap card = value.toMap();
            QVERIFY(!card.value(u"setCode"_s).toString().isEmpty());
            QVERIFY(!card.value(u"collectorNumber"_s).toString().isEmpty());
        }
        QCOMPARE(deck.value(u"sideboard"_s).toList().first().toMap().value(u"setCode"_s).toString(),
                 u"CMM"_s);
        QCOMPARE(caching.count(), 0);
    }

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

bool writeDoubleFacedCatalog(const QString &storagePath)
{
    const QString sourcePath = storagePath + QStringLiteral("/bulk.json");
    const QString databasePath = storagePath + QStringLiteral("/cards.sqlite");
    const QJsonArray cards{
        QJsonObject{
            {u"id"_s, u"delver-1"_s},
            {u"oracle_id"_s, u"delver-oracle"_s},
            {u"name"_s, u"Delver of Secrets // Insectile Aberration"_s},
            {u"type_line"_s, u"Creature — Human Wizard // Creature — Human Insect"_s},
            {u"set"_s, u"MID"_s},
            {u"collector_number"_s, u"47"_s},
            {u"lang"_s, u"en"_s},
            {u"layout"_s, u"transform"_s},
            {u"card_faces"_s,
             QJsonArray{
                 QJsonObject{
                     {u"name"_s, u"Delver of Secrets"_s},
                     {u"type_line"_s, u"Creature — Human Wizard"_s},
                     {u"image_uris"_s,
                      QJsonObject{{u"normal"_s, u"https://images.test/delver-front.png"_s}}}},
                 QJsonObject{
                     {u"name"_s, u"Insectile Aberration"_s},
                     {u"type_line"_s, u"Creature — Human Insect"_s},
                     {u"image_uris"_s,
                      QJsonObject{{u"normal"_s, u"https://images.test/delver-back.png"_s}}}},
             }},
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

bool writeBoltAndTokenCatalog(const QString &storagePath,
                              const QString &imageUrl = u"https://example.test/bolt.jpg"_s,
                              const QString &cardName = u"Lightning Bolt"_s)
{
    const QString sourcePath = storagePath + QStringLiteral("/bulk.json");
    const QString databasePath = storagePath + QStringLiteral("/cards.sqlite");
    const QJsonArray cards{
        QJsonObject{
            {u"id"_s, u"card-1"_s},
            {u"oracle_id"_s, u"oracle-1"_s},
            {u"name"_s, cardName},
            {u"type_line"_s, u"Instant"_s},
            {u"set"_s, u"M11"_s},
            {u"collector_number"_s, u"149"_s},
            {u"lang"_s, u"en"_s},
            {u"layout"_s, u"normal"_s},
            {u"image_uris"_s, QJsonObject{{u"normal"_s, imageUrl}}},
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

void TestCardCatalog::cachesEveryFaceOfDoubleFacedPrinting() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writeDoubleFacedCatalog(storage.path()), "test catalog import failed");
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    const QVariantList printing{
        QVariantMap{{u"name"_s, u"Delver of Secrets"_s},
                    {u"setCode"_s, u"MID"_s},
                    {u"collectorNumber"_s, u"47"_s}},
    };

    const QVariantList expanded = catalog.expandCardFaceRequests(printing);
    QCOMPARE(expanded.size(), 2);
    QCOMPARE(expanded.at(0).toMap().value(u"name"_s).toString(), u"Delver of Secrets"_s);
    QCOMPARE(expanded.at(1).toMap().value(u"name"_s).toString(), u"Insectile Aberration"_s);

    QSignalSpy cacheSpy(&catalog, &CardCatalog::cardCacheFinished);
    catalog.cacheCards(printing);
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 2, 3'000);
    QVERIFY(catalog.imageSource(u"Delver of Secrets"_s, u"MID"_s, u"47"_s).startsWith(u"file:"_s));
    QVERIFY(
        catalog.imageSource(u"Insectile Aberration"_s, u"MID"_s, u"47"_s).startsWith(u"file:"_s));
    QVERIFY(network.requestedUrls.contains(QUrl(u"https://images.test/delver-back.png"_s)));
}

void TestCardCatalog::coldDoubleFaceAvailabilityRefreshesCanonicalDeck_data() const
{
    QTest::addColumn<QString>("deckCardName");
    QTest::newRow("front-name") << u"Delver of Secrets"_s;
    QTest::newRow("canonical-name") << u"Delver of Secrets // Insectile Aberration"_s;
}

void TestCardCatalog::coldDoubleFaceAvailabilityRefreshesCanonicalDeck() const
{
    QFETCH(QString, deckCardName);
    using hexproof::client::DeckCard;
    using hexproof::client::DeckLibraryModel;
    QTemporaryDir storage;
    QTemporaryDir decks;
    QVERIFY(storage.isValid());
    QVERIFY(decks.isValid());
    QVERIFY2(writeDoubleFacedCatalog(storage.path()), "test catalog import failed");
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    DeckLibraryModel library(decks.path());
    library.setImagePathResolver([&catalog](const DeckCard &card) {
        return QUrl(catalog.imageSource(card.name, card.setCode, card.collectorNumber))
            .toLocalFile();
    });
    connect(&catalog, &CardCatalog::cardAvailable, &library, &DeckLibraryModel::applyCardMetadata);
    QVERIFY(library.importDeck(u"Other printing"_s, u"custom"_s,
                               u"7 %1 (V17) 7\n"_s.arg(deckCardName)));
    const QString otherDeckId = library.data(library.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(
        library.importDeck(u"Cold cache"_s, u"custom"_s, u"7 %1 (MID) 47\n"_s.arg(deckCardName)));
    const QString deckId = library.data(library.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(library.openDeck(deckId));
    QCOMPARE(library.currentMissingImageCount(), 1);
    QVERIFY(!library.currentReady());
    const QVariantMap initialCard = library.mainCards().first().toMap();
    QVERIFY(initialCard.value(u"imageSourceResolved"_s).toBool());
    QVERIFY(initialCard.value(u"imageSource"_s).toString().isEmpty());
    QVERIFY(network.requestedUrls.isEmpty());

    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    QSignalSpy available(&catalog, &CardCatalog::cardAvailable);
    const QVariantList faces =
        catalog.expandCardFaceRequests(library.cardArtExportRequests(deckId));
    QCOMPARE(faces.size(), 2);
    // Complete the reverse first, as can happen after a front download fails
    // and is retried. It must not make the whole printing ready with back art.
    catalog.cacheCards({faces.last()});
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), 1, 3'000);
    QVERIFY(completed.first().at(3).toBool());
    QCOMPARE(available.count(), 1);
    QCOMPARE(available.first().at(0).toString(), u"Insectile Aberration"_s);
    QVERIFY(catalog.imageSource(u"Delver of Secrets // Insectile Aberration"_s, u"MID"_s, u"47"_s)
                .isEmpty());
    QCOMPARE(library.currentMissingImageCount(), 1);
    QVERIFY(!library.currentReady());
    catalog.cacheCards({faces.first()});
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), 2, 3'000);
    for (const auto &completion : completed)
        QVERIFY(completion.at(3).toBool());
    const QString frontSource = catalog.imageSource(u"Delver of Secrets"_s, u"MID"_s, u"47"_s);
    QVERIFY(QFile::exists(QUrl(frontSource).toLocalFile()));
    QVERIFY(QFile::exists(
        QUrl(catalog.imageSource(u"Insectile Aberration"_s, u"MID"_s, u"47"_s)).toLocalFile()));
    QCOMPARE(catalog.imageSource(u"Delver of Secrets // Insectile Aberration"_s, u"MID"_s, u"47"_s),
             frontSource);
    QVERIFY(network.requestedUrls.contains(QUrl(u"https://images.test/delver-front.png"_s)));
    QVERIFY(network.requestedUrls.contains(QUrl(u"https://images.test/delver-back.png"_s)));

    // The catalog has both images, but a full-name imported row must also drop
    // its memoized missing path without reopening the deck or refreshing it.
    QTRY_COMPARE_WITH_TIMEOUT(library.currentMissingImageCount(), 0, 1'000);
    QVERIFY(library.currentReady());
    const QVariantMap card = library.mainCards().first().toMap();
    QCOMPARE(card.value(u"name"_s).toString(), deckCardName);
    QCOMPARE(card.value(u"setCode"_s).toString(), u"MID"_s);
    QCOMPARE(card.value(u"collectorNumber"_s).toString(), u"47"_s);
    QCOMPARE(card.value(u"imageSource"_s).toString(), frontSource);
    available.clear();
    catalog.cacheCards({faces.last()});
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), 3, 1'000);
    QCOMPARE(available.count(), 1);
    QCOMPARE(available.first().at(0).toString(), u"Insectile Aberration"_s);
    QCOMPARE(library.mainCards().first().toMap().value(u"imageSource"_s).toString(), frontSource);
    QVERIFY(library.openDeck(otherDeckId));
    QCOMPARE(library.currentMissingImageCount(), 1);
    QVERIFY(!library.currentReady());
    QVERIFY(library.mainCards().first().toMap().value(u"imageSource"_s).toString().isEmpty());
    QCOMPARE(library.mainCards().first().toMap().value(u"setCode"_s).toString(), u"V17"_s);
}

void TestCardCatalog::prepareAvailabilityDoesNotRefreshStandaloneNames() const
{
    using hexproof::client::DeckCard;
    using hexproof::client::DeckLibraryModel;
    QTemporaryDir storage;
    QTemporaryDir decks;
    QVERIFY(storage.isValid());
    QVERIFY(decks.isValid());
    const QString wholeName = u"Emeritus of Truce // Swords to Plowshares"_s;
    const QJsonArray cards{
        QJsonObject{
            {u"id"_s, u"emeritus-1"_s},
            {u"oracle_id"_s, u"emeritus-oracle"_s},
            {u"name"_s, wholeName},
            {u"type_line"_s, u"Creature — Cat Cleric // Instant"_s},
            {u"set"_s, u"SOS"_s},
            {u"collector_number"_s, u"13"_s},
            {u"lang"_s, u"en"_s},
            {u"layout"_s, u"prepare"_s},
            {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://images.test/emeritus.png"_s}}},
            {u"card_faces"_s, QJsonArray{QJsonObject{{u"name"_s, u"Emeritus of Truce"_s},
                                                     {u"type_line"_s, u"Creature — Cat Cleric"_s}},
                                         QJsonObject{{u"name"_s, u"Swords to Plowshares"_s},
                                                     {u"type_line"_s, u"Instant"_s}}}}},
        QJsonObject{
            {u"id"_s, u"swords-1"_s},
            {u"oracle_id"_s, u"swords-oracle"_s},
            {u"name"_s, u"Swords to Plowshares"_s},
            {u"type_line"_s, u"Instant"_s},
            {u"set"_s, u"STA"_s},
            {u"collector_number"_s, u"10"_s},
            {u"lang"_s, u"en"_s},
            {u"layout"_s, u"normal"_s},
            {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://images.test/swords.png"_s}}}},
    };
    QFile source(storage.filePath(u"bulk.json"_s));
    QVERIFY(source.open(QIODevice::WriteOnly));
    const QByteArray payload = QJsonDocument(cards).toJson(QJsonDocument::Compact);
    QCOMPARE(source.write(payload), payload.size());
    source.close();
    const auto imported = CardCatalog::importBulkFile(
        source.fileName(), storage.filePath(u"cards.sqlite"_s), u"default_cards"_s);
    QVERIFY(imported.ok);
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    DeckLibraryModel library(decks.path());
    library.setImagePathResolver([&catalog](const DeckCard &card) {
        return QUrl(catalog.imageSource(card.name, card.setCode, card.collectorNumber))
            .toLocalFile();
    });
    connect(&catalog, &CardCatalog::cardAvailable, &library, &DeckLibraryModel::applyCardMetadata);
    QVERIFY(library.importDeck(u"Standalone spell"_s, u"custom"_s,
                               u"7 Swords to Plowshares (STA) 10\n"_s));
    const QString standaloneId =
        library.data(library.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(
        library.importDeck(u"Prepare card"_s, u"custom"_s, u"7 %1 (SOS) 13\n"_s.arg(wholeName)));
    const QString prepareId = library.data(library.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(library.openDeck(prepareId));
    QCOMPARE(library.currentMissingImageCount(), 1);
    QVERIFY(!library.currentReady());
    const QVariantList requests =
        catalog.expandCardFaceRequests(library.cardArtExportRequests(prepareId));
    QCOMPARE(requests.size(), 1);
    QCOMPARE(requests.first().toMap().value(u"name"_s).toString(), wholeName);

    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    QSignalSpy available(&catalog, &CardCatalog::cardAvailable);
    catalog.cacheCards(requests);
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), 1, 3'000);
    QVERIFY(completed.first().at(3).toBool());
    QTRY_VERIFY_WITH_TIMEOUT(library.currentReady(), 1'000);
    QCOMPARE(library.currentMissingImageCount(), 0);
    QCOMPARE(available.count(), 1);
    QCOMPARE(available.first().at(0).toString(), wholeName);
    QCOMPARE(network.requestedUrls, QList<QUrl>{QUrl(u"https://images.test/emeritus.png"_s)});
    const QVariantMap prepared = library.mainCards().first().toMap();
    QCOMPARE(prepared.value(u"name"_s).toString(), wholeName);
    QCOMPARE(prepared.value(u"setCode"_s).toString(), u"SOS"_s);
    QVERIFY(!prepared.value(u"imageSource"_s).toString().isEmpty());
    QVERIFY(library.openDeck(standaloneId));
    QCOMPARE(library.currentMissingImageCount(), 1);
    QVERIFY(!library.currentReady());
    QVERIFY(library.mainCards().first().toMap().value(u"imageSource"_s).toString().isEmpty());
    QCOMPARE(library.mainCards().first().toMap().value(u"name"_s).toString(),
             u"Swords to Plowshares"_s);
    QCOMPARE(library.mainCards().first().toMap().value(u"setCode"_s).toString(), u"STA"_s);
}

void TestCardCatalog::exactArtUsesCatalogEnglishWhenChinesePrintingIsMissing() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writeBoltCatalog(storage.path()), "test catalog import failed");
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"zh"_s);
    catalog.setCardArtProvider(u"scryfall"_s);
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

void TestCardCatalog::cardSearchInvalidatesDuringCatalogReplacement_data() const
{
    QTest::addColumn<bool>("settledSearch");
    QTest::addColumn<bool>("failedImport");
    QTest::addColumn<bool>("clearDuringImport");
    for (const bool settled : {false, true}) {
        for (const bool failed : {false, true}) {
            for (const bool clear : {false, true}) {
                const QByteArray name = QByteArray(settled ? "settled" : "pending-result") +
                                        (failed ? "-failed-import" : "-replacement") +
                                        (clear ? "-closed" : "-open");
                QTest::newRow(name.constData()) << settled << failed << clear;
            }
        }
    }
}

void TestCardCatalog::cardSearchInvalidatesDuringCatalogReplacement() const
{
    QFETCH(bool, settledSearch);
    QFETCH(bool, failedImport);
    QFETCH(bool, clearDuringImport);
    QTemporaryDir storage;
    QTemporaryDir replacement;
    QVERIFY(storage.isValid());
    QVERIFY(replacement.isValid());
    QVERIFY(writeBoltAndTokenCatalog(storage.path()));
    QVERIFY(writeBoltAndTokenCatalog(replacement.path(), u"https://example.test/strike.jpg"_s,
                                     u"Lightning Strike"_s));
    QString importPath = replacement.filePath(u"cards.sqlite"_s);
    if (failedImport) {
        importPath = replacement.filePath(u"invalid.json"_s);
        QFile invalid(importPath);
        QVERIFY(invalid.open(QIODevice::WriteOnly));
        QCOMPARE(invalid.write("invalid"), 7);
    }
    CardCatalog catalog(storage.path());
    QSemaphore started, release;
    auto *pool = hexproof::client::BackgroundTaskPools::catalogMaintenance();
    const int workers = pool->maxThreadCount();
    for (int index = 0; index < workers; ++index) {
        pool->start([&] {
            started.release();
            release.acquire();
        });
    }
    const auto cleanup = qScopeGuard([&] {
        release.release(workers);
        pool->waitForDone();
    });
    QVERIFY(started.tryAcquire(workers, 5'000));

    catalog.search(u"Lightning"_s);
    if (settledSearch)
        QTRY_COMPARE(catalog.searchResults().size(), 1);
    else
        QVERIFY(catalog.searching());
    catalog.importCatalogFile(QUrl::fromLocalFile(importPath), u"default_cards"_s);
    QVERIFY(catalog.busy());
    // The old search may finish while the replacement is still queued. Neither
    // a settled list nor a late result may remain selectable during that wait.
    if (clearDuringImport)
        catalog.search({});
    QVERIFY(hexproof::client::BackgroundTaskPools::catalogSearch()->waitForDone(5'000));
    QTest::qWait(20);
    QVERIFY(catalog.busy());
    QVERIFY(!catalog.searching());
    QVERIFY(catalog.searchResults().isEmpty());

    release.release(workers);
    QTRY_VERIFY_WITH_TIMEOUT(!catalog.busy(), 5'000);
    QCOMPARE(catalog.operationError().isEmpty(), !failedImport);
    if (clearDuringImport) {
        QVERIFY(catalog.searchResults().isEmpty());
        catalog.search(u"Lightning"_s);
    }
    QTRY_COMPARE(catalog.searchResults().size(), 1);
    QCOMPARE(catalog.searchResults().first().toMap().value(u"name"_s).toString(),
             failedImport ? u"Lightning Bolt"_s : u"Lightning Strike"_s);
}

void TestCardCatalog::directImageRetryKeepsCacheOperationActive() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY(writeBoltAndTokenCatalog(storage.path(), u"https://cards.scryfall.io/bolt.jpg"_s));
    FakeNetworkAccessManager network;
    network.scryfallImageTimeoutsRemaining = 1;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    bool idleBeforeCompletion = false;
    connect(&catalog, &CardCatalog::busyChanged, &catalog, [&] {
        if (network.scryfallImageRequestCount > 0 && completed.isEmpty() && !catalog.busy())
            idleBeforeCompletion = true;
    });
    catalog.cacheCards({QVariantMap{{u"name"_s, u"Lightning Bolt"_s},
                                    {u"setCode"_s, u"M11"_s},
                                    {u"collectorNumber"_s, u"149"_s}}});
    QTRY_COMPARE(network.scryfallImageRequestCount, 1);
    // The first reply has failed, but its retry timer still owns the request.
    // Keep progress active and exclusive index operations blocked in that gap.
    QTest::qWait(50);
    QVERIFY(completed.isEmpty());
    QVERIFY(catalog.busy());
    QVERIFY(catalog.cacheProgressActive());
    QVERIFY(!idleBeforeCompletion);
    catalog.artManager()->exportPack(
        QUrl::fromLocalFile(storage.filePath(u"cache.hexproof-artpack"_s)), false);
    QVERIFY(!catalog.artManager()->busy());
    QVERIFY(!catalog.artManager()->lastError().isEmpty());
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), 1, 3'000);
    QVERIFY(completed.first().last().toBool());
    QTRY_VERIFY(!catalog.busy());
    QVERIFY(!catalog.cacheProgressActive());
    QCOMPARE(network.scryfallImageRequestCount, 2);
    QCOMPARE(network.scryfallRequestCount, 0);
    QVERIFY(!idleBeforeCompletion);
}
