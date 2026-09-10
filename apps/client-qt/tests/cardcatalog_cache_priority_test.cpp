// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "cardcatalog_test.h"

#include "services/CardArtCache.h"
#include "services/CardImageProvider.h"

#include <QPointer>

namespace {

class PriorityMetadataNetwork final : public QNetworkAccessManager
{
  public:
    QStringList requestedNumbers;
    QPointer<QNetworkReply> firstMetadata;

  protected:
    QNetworkReply *createRequest(Operation, const QNetworkRequest &request, QIODevice *) override
    {
        if (request.url().host() == u"mtgch.com"_s) {
            const QString number = request.url().path().split(u'/', Qt::SkipEmptyParts).last();
            requestedNumbers.append(number);
            const QJsonObject card{
                {u"name"_s, u"Token "_s + number},
                {u"set"_s, u"ttst"_s},
                {u"collector_number"_s, number},
                {u"zhs_name"_s, u"衍生物 "_s + number},
                {u"zhs_type_line"_s, u"衍生生物"_s},
                {u"zhs_text"_s, u"飞行"_s},
                {u"zhs_image_uris"_s,
                 QJsonObject{{u"normal"_s, u"https://images.test/token-"_s + number + u".png"_s}}}};
            auto *reply = new StaticNetworkReply(request, QJsonDocument(card).toJson(),
                                                 "application/json", this);
            if (requestedNumbers.size() == 1) {
                // Keep the resolver occupied while incremental background work
                // enters its fallback queue. The test releases this exact reply.
                firstMetadata = reply;
                reply->blockSignals(true);
            }
            return reply;
        }
        QImage image(1, 1, QImage::Format_ARGB32);
        image.fill(Qt::green);
        QByteArray bytes;
        QBuffer buffer(&bytes);
        buffer.open(QIODevice::WriteOnly);
        image.save(&buffer, "PNG");
        return new StaticNetworkReply(request, bytes, "image/png", this);
    }
};

bool writePriorityDoubleFacedCatalog(const QString &storagePath)
{
    const QString sourcePath = QDir(storagePath).filePath(u"priority-bulk.json"_s);
    const QString databasePath = QDir(storagePath).filePath(u"cards.sqlite"_s);
    const QJsonArray cards{QJsonObject{
        {u"id"_s, u"delver-priority"_s},
        {u"oracle_id"_s, u"delver-oracle"_s},
        {u"name"_s, u"Delver of Secrets // Insectile Aberration"_s},
        {u"type_line"_s, u"Creature — Human Wizard // Creature — Human Insect"_s},
        {u"set"_s, u"MID"_s},
        {u"collector_number"_s, u"47"_s},
        {u"lang"_s, u"en"_s},
        {u"layout"_s, u"transform"_s},
        {u"card_faces"_s,
         QJsonArray{
             QJsonObject{{u"name"_s, u"Delver of Secrets"_s},
                         {u"type_line"_s, u"Creature — Human Wizard"_s},
                         {u"image_uris"_s,
                          QJsonObject{{u"normal"_s, u"https://images.test/delver-front.png"_s}}}},
             QJsonObject{{u"name"_s, u"Insectile Aberration"_s},
                         {u"type_line"_s, u"Creature — Human Insect"_s},
                         {u"image_uris"_s,
                          QJsonObject{{u"normal"_s, u"https://images.test/delver-back.png"_s}}}},
         }},
    }};
    QFile source(sourcePath);
    if (!source.open(QIODevice::WriteOnly))
        return false;
    const QByteArray payload = QJsonDocument(cards).toJson(QJsonDocument::Compact);
    const bool written = source.write(payload) == payload.size();
    source.close();
    return written && CardCatalog::importBulkFile(sourcePath, databasePath, u"default_cards"_s).ok;
}

bool dropPriorityCardsTable(const QString &databasePath)
{
    const QString connectionName =
        QStringLiteral("priority-drop-%1").arg(QDateTime::currentMSecsSinceEpoch());
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

} // namespace

void TestCardCatalog::prioritizeSupportMetadataAheadOfBackground_data() const
{
    QTest::addColumn<bool>("alreadyQueued");
    QTest::newRow("promote-existing-fallback") << true;
    QTest::newRow("new-explicit-request") << false;
}

void TestCardCatalog::prioritizeSupportMetadataAheadOfBackground() const
{
    QFETCH(bool, alreadyQueued);
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    PriorityMetadataNetwork network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"zh"_s);
    const auto card = [](int number) {
        return QVariantMap{{u"name"_s, u"Token %1"_s.arg(number)},
                           {u"setCode"_s, u"TTST"_s},
                           {u"collectorNumber"_s, QString::number(number)},
                           {u"kind"_s, u"token"_s}};
    };
    QVariantList background;
    for (int number = 0; number < 12; ++number)
        background.append(card(number));
    catalog.cacheCardsIncrementally(background);
    QTRY_VERIFY(network.firstMetadata);
    // All three four-card batches can be discovered, but the first network
    // reply remains blocked so none of the queued cards can resolve yet.
    QTest::qWait(60);
    QCOMPARE(network.requestedNumbers, QStringList{u"0"_s});
    const int target = alreadyQueued ? 11 : 12;
    catalog.prioritizeCards({card(target)});
    QTest::qWait(30);
    QVERIFY(network.firstMetadata->isFinished());
    network.firstMetadata->blockSignals(false);
    emit network.firstMetadata->finished();
    QTRY_VERIFY(network.requestedNumbers.size() >= 2);
    QCOMPARE(network.requestedNumbers.at(1), QString::number(target));
}

void TestCardCatalog::prioritizeCardsDefersCacheDiscovery() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString imagePath = storage.filePath(u"cached-card.jpg"_s);
    QFile image(imagePath);
    QVERIFY(image.open(QIODevice::WriteOnly));
    QCOMPARE(image.write("cached image"), 12);
    image.close();

    hexproof::client::CardArtCache cache(storage.path());
    CardCatalog::CardRecord record;
    record.requestedName = u"Lightning Bolt"_s;
    record.name = u"Lightning Bolt"_s;
    record.localizedName = u"Lightning Bolt"_s;
    record.typeLine = u"Instant"_s;
    record.setCode = u"M11"_s;
    record.collectorNumber = u"146"_s;
    record.imagePath = imagePath;
    record.imageLanguage = u"en"_s;
    record.resolutionVersion = kCardResolutionVersion;
    cache.rememberSuccess(cache.key(record.name, u"en"_s, record.setCode, record.collectorNumber),
                          record);
    QVERIFY(cache.save());

    CardCatalog catalog(storage.path());
    QSignalSpy availableSpy(&catalog, &CardCatalog::cardAvailable);
    const QVariantList cards{QVariantMap{
        {u"name"_s, record.name},
        {u"setCode"_s, record.setCode},
        {u"collectorNumber"_s, record.collectorNumber},
    }};

    catalog.prioritizeCards(cards);

    QCOMPARE(availableSpy.count(), 0);
    QTRY_COMPARE_WITH_TIMEOUT(availableSpy.count(), 1, 1'000);
}

void TestCardCatalog::prioritizeCardsDefersFaceExpansion() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writePriorityDoubleFacedCatalog(storage.path()), "test catalog import failed");
    CardCatalog catalog(storage.path());
    QVERIFY(catalog.installed());
    QVERIFY2(dropPriorityCardsTable(storage.filePath(u"cards.sqlite"_s)),
             "could not remove the test cards table");
    QSignalSpy errorSpy(&catalog, &CardCatalog::printingsErrorChanged);
    const QVariantList cards{QVariantMap{
        {u"name"_s, u"Delver of Secrets"_s},
        {u"setCode"_s, u"MID"_s},
        {u"collectorNumber"_s, u"47"_s},
    }};

    catalog.prioritizeCards(cards);

    QCOMPARE(errorSpy.count(), 0);
    QTRY_COMPARE_WITH_TIMEOUT(errorSpy.count(), 1, 1'000);
    QVERIFY(!catalog.printingsError().isEmpty());
}

void TestCardCatalog::prioritizeCardsDistinguishesExactArtQueueEntries() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    network.missFirstScryfallRequest = true;
    network.missMtgchRequests = true;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"zh"_s);
    catalog.setCardArtProvider(u"scryfall"_s);
    QVariantMap printing{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    };
    QVariantMap exactPrinting = printing;
    exactPrinting.insert(u"exactArt"_s, true);

    catalog.downloadCatalog(u"default_cards"_s);
    QVERIFY(catalog.busy());
    catalog.cacheCards({printing, exactPrinting});
    catalog.prioritizeCards({exactPrinting});

    QTRY_VERIFY_WITH_TIMEOUT(network.requestedUrls.size() >= 3, 2'000);
    QCOMPARE(network.requestedUrls.at(1).path(), u"/cards/m11/146/zhs"_s);
    QCOMPARE(network.requestedUrls.at(2).host(), u"mtgch.com"_s);
}

void TestCardCatalog::prioritizeRawCardMovesAllQueuedFaces() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY2(writePriorityDoubleFacedCatalog(storage.path()), "test catalog import failed");
    FakeNetworkAccessManager network;
    CardCatalog catalog(storage.path(), &network);
    const QVariantList rawPrinting{QVariantMap{
        {u"name"_s, u"Delver of Secrets"_s},
        {u"setCode"_s, u"MID"_s},
        {u"collectorNumber"_s, u"47"_s},
    }};
    const QVariantList faces = catalog.expandCardFaceRequests(rawPrinting);
    QCOMPARE(faces.size(), 2);
    const QVariantMap unrelated{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    };

    catalog.downloadCatalog(u"default_cards"_s);
    QVERIFY(catalog.busy());
    catalog.cacheCards({unrelated});
    catalog.cacheCards(faces);
    catalog.prioritizeCards(rawPrinting);

    const auto cardApiPaths = [&network] {
        QStringList paths;
        for (const QUrl &url : network.requestedUrls) {
            if (url.host() == u"api.scryfall.com"_s && url.path().startsWith(u"/cards/"_s))
                paths.append(url.path());
        }
        return paths;
    };
    QTRY_VERIFY_WITH_TIMEOUT(cardApiPaths().size() >= 3, 2'000);
    QCOMPARE(cardApiPaths().at(0), u"/cards/mid/47"_s);
    QCOMPARE(cardApiPaths().at(1), u"/cards/mid/47"_s);
    QCOMPARE(cardApiPaths().at(2), u"/cards/m11/146"_s);
}

void TestCardCatalog::prioritizeCardsEmitsMultiCardCacheHitsOnce() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    hexproof::client::CardArtCache cache(storage.path());
    const QStringList names{u"Alpha"_s, u"Beta"_s, u"Gamma"_s};
    QVariantList cards;
    for (int index = 0; index < names.size(); ++index) {
        const QString imagePath = storage.filePath(QStringLiteral("card-%1.jpg").arg(index));
        QFile image(imagePath);
        QVERIFY(image.open(QIODevice::WriteOnly));
        QCOMPARE(image.write("cached image"), 12);
        image.close();
        CardCatalog::CardRecord record;
        record.requestedName = names.at(index);
        record.name = names.at(index);
        record.localizedName = names.at(index);
        record.typeLine = u"Instant"_s;
        record.setCode = u"TST"_s;
        record.collectorNumber = QString::number(index + 1);
        record.imagePath = imagePath;
        record.imageLanguage = u"en"_s;
        record.resolutionVersion = kCardResolutionVersion;
        cache.rememberSuccess(
            cache.key(record.name, u"en"_s, record.setCode, record.collectorNumber), record);
        cards.append(QVariantMap{
            {u"name"_s, record.name},
            {u"setCode"_s, record.setCode},
            {u"collectorNumber"_s, record.collectorNumber},
        });
    }
    QVERIFY(cache.save());

    CardCatalog catalog(storage.path());
    QSignalSpy availableSpy(&catalog, &CardCatalog::cardAvailable);
    catalog.cacheCardsIncrementally(cards);
    catalog.prioritizeCards({cards.at(2), cards.at(0)});

    QCOMPARE(availableSpy.count(), 0);
    QTRY_COMPARE_WITH_TIMEOUT(availableSpy.count(), 3, 1'000);
    QCOMPARE(availableSpy.at(0).at(0).toString(), u"Gamma"_s);
    QCOMPARE(availableSpy.at(1).at(0).toString(), u"Alpha"_s);
    QCOMPARE(availableSpy.at(2).at(0).toString(), u"Beta"_s);
}

void TestCardCatalog::tableImageSourceUsesStaleCacheMetadata() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString stalePath = storage.filePath(u"missing-card.jpg"_s);
    QVERIFY(!QFileInfo::exists(stalePath));

    hexproof::client::CardArtCache cache(storage.path());
    CardCatalog::CardRecord record;
    record.requestedName = u"Lightning Bolt"_s;
    record.name = u"Lightning Bolt"_s;
    record.localizedName = u"Lightning Bolt"_s;
    record.typeLine = u"Instant"_s;
    record.setCode = u"M11"_s;
    record.collectorNumber = u"146"_s;
    record.imagePath = stalePath;
    record.imageLanguage = u"en"_s;
    record.resolutionVersion = kCardResolutionVersion;
    cache.rememberSuccess(cache.key(record.name, u"en"_s, record.setCode, record.collectorNumber),
                          record);
    QVERIFY(cache.save());

    CardCatalog catalog(storage.path());
    hexproof::client::CardImageProvider provider;
    catalog.setCardImageProvider(&provider);
    QVERIFY(catalog.imageSource(record.name, record.setCode, record.collectorNumber).isEmpty());
    QVERIFY(
        catalog.printingImageSource(record.name, record.setCode, record.collectorNumber).isEmpty());

    QVERIFY(catalog.tableImageSource(record.name, record.setCode, record.collectorNumber)
                .startsWith(u"image://card-table/"_s));
}
