// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "cardcatalog_test.h"

#include "services/CardArtArchive.h"
#include "services/CardArtCache.h"
#include "services/CardArtManager.h"
#include "services/CardImageProvider.h"

using hexproof::client::CardImageProvider;

namespace {

QJsonObject independentFaceFixture(const QString &layout = u"transform"_s,
                                   const QString &front = u"Front"_s,
                                   const QString &back = u"Back"_s,
                                   const QString &collector = u"7"_s)
{
    return {{u"id"_s, u"62c3e909-ae90-49c4-b60e-f4f58695f32f"_s},
            {u"name"_s, front + u" // "_s + back},
            {u"layout"_s, layout},
            {u"set"_s, u"TST"_s},
            {u"collector_number"_s, collector},
            {u"card_faces"_s,
             QJsonArray{
                 QJsonObject{{u"name"_s, front},
                             {u"type_line"_s, u"Creature"_s},
                             {u"oracle_text"_s, u"Front rules"_s},
                             {u"image_uris"_s,
                              QJsonObject{{u"normal"_s, u"https://faces.test/front.png"_s}}}},
                 QJsonObject{{u"name"_s, back},
                             {u"type_line"_s, u"Land"_s},
                             {u"oracle_text"_s, u"Back rules"_s},
                             {u"image_uris"_s,
                              QJsonObject{{u"normal"_s, u"https://faces.test/back.png"_s}}}},
             }}};
}

class FaceMetadataNetwork final : public QNetworkAccessManager
{
  public:
    QHash<QString, QJsonObject> cards;
    QList<QUrl> requests;
    QByteArray image;
    int inFlight = 0;
    int maximumInFlight = 0;
    int metadataDelayMs = 0;

  protected:
    QNetworkReply *createRequest(Operation, const QNetworkRequest &request, QIODevice *) override
    {
        requests.append(request.url());
        ++inFlight;
        maximumInFlight = qMax(maximumInFlight, inFlight);
        QNetworkReply *reply = nullptr;
        if (request.url().host() == u"api.scryfall.com"_s && cards.contains(request.url().path()))
            reply = new StaticNetworkReply(
                request, QJsonDocument(cards.value(request.url().path())).toJson(),
                "application/json", this, 200, QNetworkReply::NoError, metadataDelayMs);
        else if (request.url().host() == u"faces.test"_s && !image.isEmpty())
            reply = new StaticNetworkReply(request, image, "image/png", this);
        else
            reply = new StaticNetworkReply(request, "{}", "application/json", this, 404,
                                           QNetworkReply::ContentNotFoundError);
        connect(reply, &QNetworkReply::finished, this, [this]() { --inFlight; });
        return reply;
    }
};

bool saveLegacyFaceArt(const QString &root, const QString &name = u"Front // Back"_s,
                       const QString &collector = u"7"_s)
{
    QImage image(4, 4, QImage::Format_RGB32);
    image.fill(Qt::red);
    const QString path = QDir(root).filePath(u"front-"_s + collector + u".png"_s);
    if (!image.save(path))
        return false;
    hexproof::client::CardArtCache cache(root);
    cache.load();
    hexproof::client::CardRecord record;
    record.name = name;
    record.requestedName = name;
    record.setCode = u"TST"_s;
    record.collectorNumber = collector;
    record.imageLanguage = u"en"_s;
    record.imagePath = path;
    record.imageUrl = u"https://faces.test/front.png"_s;
    record.resolutionVersion = kCardResolutionVersion;
    cache.rememberSuccess(cache.key(name, u"en"_s, u"TST"_s, collector), record);
    return cache.save();
}

} // namespace

void TestCardCatalog::cachedFacesPreserveProviderEvidence_data() const
{
    QTest::addColumn<QString>("layout");
    QTest::addColumn<bool>("independent");
    for (const QString &layout :
         {u"transform"_s, u"modal_dfc"_s, u"double_faced_token"_s, u"reversible_card"_s})
        QTest::newRow(qPrintable(layout)) << layout << true;
    for (const QString &layout :
         {u"split"_s, u"adventure"_s, u"prepare"_s, u"flip"_s, u"normal"_s, QString{}})
        QTest::newRow(qPrintable(layout.isEmpty() ? u"legacy-unknown"_s : layout))
            << layout << false;
}

void TestCardCatalog::cachedFacesPreserveProviderEvidence() const
{
    QFETCH(QString, layout);
    QFETCH(bool, independent);
    const auto record =
        CardCatalog::parseCardObject(independentFaceFixture(layout), u"en"_s, u"Front // Back"_s);
    QCOMPARE(record.independentFaces.size(), independent ? 2 : 0);
    QCOMPARE(record.faceMetadataChecked, !layout.isEmpty());
    const auto roundTrip = hexproof::client::catalog_internal::recordFromJson(
        hexproof::client::catalog_internal::recordToJson(record));
    QCOMPARE(roundTrip.layout, layout);
    QCOMPARE(roundTrip.independentFaces, record.independentFaces);
    QCOMPARE(roundTrip.printingId, record.printingId);
    if (independent) {
        QCOMPARE(roundTrip.independentFaces.at(1).toMap().value(u"name"_s).toString(), u"Back"_s);
        QCOMPARE(roundTrip.independentFaces.at(1).toMap().value(u"collectorNumber"_s).toString(),
                 u"7"_s);
    }
    auto sameNamed = independentFaceFixture(u"double_faced_token"_s, u"Goblin"_s, u"Goblin"_s);
    const auto tokenFront = CardCatalog::parseCardObject(sameNamed, u"en"_s, u"Goblin // Goblin"_s);
    const auto tokenBack = CardCatalog::parseCardObject(sameNamed, u"en"_s, u"Goblin"_s);
    QCOMPARE(tokenFront.independentFaces.first().toMap().value(u"name"_s).toString(),
             u"Goblin // Goblin"_s);
    QCOMPARE(tokenFront.independentFaces.last().toMap().value(u"name"_s).toString(), u"Goblin"_s);
    QCOMPARE(tokenFront.imageUrl, u"https://faces.test/front.png"_s);
    QCOMPARE(tokenBack.imageUrl, u"https://faces.test/back.png"_s);
    QCOMPARE(tokenBack.oracleText, u"Back rules"_s);
}

void TestCardCatalog::cachedFacesWorkWithoutDatabase() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const auto record =
        CardCatalog::parseCardObject(independentFaceFixture(), u"en"_s, u"Front // Back"_s);
    {
        hexproof::client::CardArtCache cache(storage.path());
        cache.rememberSuccess(cache.key(record.name, u"en"_s, u"TST"_s, u"7"_s), record);
        QVERIFY(cache.save());
    }
    FaceMetadataNetwork network;
    CardCatalog catalog(storage.path(), &network);
    QVERIFY(!catalog.installed());
    const auto faces = catalog.cardFaces(u"Front"_s, u"tst"_s, u"7"_s);
    QCOMPARE(faces.size(), 2);
    QCOMPARE(catalog.cardFaces(u"Back"_s, u"TST"_s, u"7"_s), faces);
    QVERIFY(catalog.cardFaces(u"Front // Back"_s, u"OTHER"_s, u"7"_s).isEmpty());
    QVERIFY(catalog.cardFaces(u"Front // Back"_s, u"TST"_s, u"8"_s).isEmpty());
    QVERIFY(catalog.cardFaces(u"Different"_s, u"TST"_s, u"7"_s).isEmpty());
    QVERIFY(catalog.cardFaces(u"Front // Back"_s, {}, {}).isEmpty());
    catalog.setLanguage(u"zh"_s);
    QCOMPARE(catalog.cardFaces(u"Front"_s, u"TST"_s, u"7"_s), faces);
    catalog.prepareCardFacePreview(u"Front"_s, u"TST"_s, u"7"_s);
    QVERIFY(network.requests.isEmpty());
    QVERIFY(catalog.imageSource(u"Back"_s, u"TST"_s, u"7"_s).isEmpty());
}

void TestCardCatalog::legacyFacePreviewRefreshIsBoundedAndPreservesArt() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY(saveLegacyFaceArt(storage.path()));
    FaceMetadataNetwork network;
    network.cards.insert(u"/cards/tst/7"_s, independentFaceFixture());
    CardCatalog catalog(storage.path(), &network);
    const QString original = catalog.imageSource(u"Front // Back"_s, u"TST"_s, u"7"_s);
    QVERIFY(!original.isEmpty());
    QVERIFY(catalog.cardFaces(u"Front // Back"_s, u"TST"_s, u"7"_s).isEmpty());
    QVERIFY(network.requests.isEmpty());
    const QVariantMap card{
        {u"name"_s, u"Front // Back"_s}, {u"setCode"_s, u"TST"_s}, {u"collectorNumber"_s, u"7"_s}};
    catalog.cacheCards({card});
    catalog.prepareCardFacePreview(u"Front // Back"_s, u"TST"_s, u"7"_s);
    QTRY_COMPARE(catalog.cardFaces(u"Front // Back"_s, u"TST"_s, u"7"_s).size(), 2);
    QCOMPARE(network.requests.size(), 1);
    QCOMPARE(catalog.imageSource(u"Front // Back"_s, u"TST"_s, u"7"_s), original);
    QVERIFY(catalog.imageSource(u"Back"_s, u"TST"_s, u"7"_s).isEmpty());
    for (int count = 0; count < 4; ++count)
        catalog.prepareCardFacePreview(u"Front // Back"_s, u"TST"_s, u"7"_s);
    QCOMPARE(network.requests.size(), 1);

    QTemporaryDir ordinary;
    QVERIFY(saveLegacyFaceArt(ordinary.path(), u"Front // Back"_s, u"8"_s));
    network.cards.insert(u"/cards/tst/8"_s,
                         independentFaceFixture(u"prepare"_s, u"Front"_s, u"Back"_s, u"8"_s));
    CardCatalog single(ordinary.path(), &network);
    single.prepareCardFacePreview(u"Front // Back"_s, u"TST"_s, u"8"_s);
    QTRY_COMPARE(network.requests.size(), 2);
    QTRY_VERIFY(single.imageRevision() > 0);
    QVERIFY(single.cardFaces(u"Front // Back"_s, u"TST"_s, u"8"_s).isEmpty());
    single.prepareCardFacePreview(u"Front // Back"_s, u"TST"_s, u"8"_s);
    QCOMPARE(network.requests.size(), 2);

    QTemporaryDir failed;
    QVERIFY(saveLegacyFaceArt(failed.path(), u"Front // Back"_s, u"9"_s));
    CardCatalog offline(failed.path(), &network);
    offline.prepareCardFacePreview(u"Front // Back"_s, u"TST"_s, u"9"_s);
    QTRY_COMPARE(network.requests.size(), 3);
    QTest::qWait(1);
    offline.prepareCardFacePreview(u"Back"_s, u"TST"_s, u"9"_s);
    QCOMPARE(network.requests.size(), 3);
    QVERIFY(offline.cardFaces(u"Front // Back"_s, u"TST"_s, u"9"_s).isEmpty());
}

void TestCardCatalog::ordinaryLegacyCacheHitsStayLocalUntilExplicitInspection() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY(saveLegacyFaceArt(storage.path(), u"Island"_s));
    FaceMetadataNetwork network;
    network.cards.insert(u"/cards/tst/7"_s, QJsonObject{{u"name"_s, u"Island"_s},
                                                        {u"layout"_s, u"normal"_s},
                                                        {u"set"_s, u"TST"_s},
                                                        {u"collector_number"_s, u"7"_s}});
    CardCatalog catalog(storage.path(), &network);
    const int revision = catalog.imageRevision();
    const QString original = catalog.imageSource(u"Island"_s, u"TST"_s, u"7"_s);
    QVERIFY(!original.isEmpty());
    const QVariantMap card{
        {u"name"_s, u"Island"_s}, {u"setCode"_s, u"TST"_s}, {u"collectorNumber"_s, u"7"_s}};
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    catalog.cacheCards({card});
    QTRY_COMPARE(completed.count(), 1);
    catalog.cacheCards({card});
    QTRY_COMPARE(completed.count(), 2);
    QVERIFY(network.requests.isEmpty());
    QCOMPARE(catalog.imageRevision(), revision);
    QCOMPARE(catalog.imageSource(u"Island"_s, u"TST"_s, u"7"_s), original);
    catalog.prepareCardFacePreview(u"Island"_s, u"TST"_s, u"7"_s);
    QTRY_VERIFY(catalog.imageRevision() > revision);
    QCOMPARE(network.requests.size(), 1);
    QVERIFY(catalog.cardFaces(u"Island"_s, u"TST"_s, u"7"_s).isEmpty());
    catalog.prepareCardFacePreview(u"Island"_s, u"TST"_s, u"7"_s);
    QCOMPARE(network.requests.size(), 1);
    QCOMPARE(catalog.imageSource(u"Island"_s, u"TST"_s, u"7"_s), original);
}

void TestCardCatalog::faceMetadataProbesAreSerialAndStopOnDestruction() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY(saveLegacyFaceArt(storage.path()));
    QVERIFY(saveLegacyFaceArt(storage.path(), u"Front // Back"_s, u"8"_s));
    FaceMetadataNetwork network;
    network.cards.insert(u"/cards/tst/7"_s, independentFaceFixture());
    network.cards.insert(u"/cards/tst/8"_s,
                         independentFaceFixture(u"transform"_s, u"Front"_s, u"Back"_s, u"8"_s));
    CardCatalog catalog(storage.path(), &network);
    catalog.cacheCards({QVariantMap{{u"name"_s, u"Front // Back"_s},
                                    {u"setCode"_s, u"TST"_s},
                                    {u"collectorNumber"_s, u"7"_s}},
                        QVariantMap{{u"name"_s, u"Front // Back"_s},
                                    {u"setCode"_s, u"TST"_s},
                                    {u"collectorNumber"_s, u"8"_s}}});
    QTRY_COMPARE(network.requests.size(), 1);
    QTRY_COMPARE(catalog.cardFaces(u"Front // Back"_s, u"TST"_s, u"7"_s).size(), 2);
    QTest::qWait(40);
    QCOMPARE(network.requests.size(), 1);
    QTRY_COMPARE(catalog.cardFaces(u"Front // Back"_s, u"TST"_s, u"8"_s).size(), 2);
    QCOMPARE(network.maximumInFlight, 1);

    QTemporaryDir departed;
    QVERIFY(saveLegacyFaceArt(departed.path()));
    QVERIFY(saveLegacyFaceArt(departed.path(), u"Front // Back"_s, u"8"_s));
    FaceMetadataNetwork shutdownNetwork;
    shutdownNetwork.cards = network.cards;
    auto shuttingDown = std::make_unique<CardCatalog>(departed.path(), &shutdownNetwork);
    shuttingDown->prepareCardFacePreview(u"Front // Back"_s, u"TST"_s, u"7"_s);
    shuttingDown->prepareCardFacePreview(u"Front // Back"_s, u"TST"_s, u"8"_s);
    QCOMPARE(shutdownNetwork.requests.size(), 1);
    shuttingDown.reset();
    QTest::qWait(220);
    QCOMPARE(shutdownNetwork.requests.size(), 1);
    QCOMPARE(shutdownNetwork.inFlight, 0);
}

void TestCardCatalog::faceMetadataProbesRespectArtMaintenance() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY(saveLegacyFaceArt(storage.path()));
    FaceMetadataNetwork network;
    network.metadataDelayMs = 100;
    network.cards.insert(u"/cards/tst/7"_s, independentFaceFixture());
    CardCatalog catalog(storage.path(), &network);
    auto *manager = catalog.artManager();
    manager->refresh();
    QVERIFY(manager->busy());
    catalog.prepareCardFacePreview(u"Front // Back"_s, u"TST"_s, u"7"_s);
    QVERIFY(network.requests.isEmpty());
    QTRY_COMPARE(network.requests.size(), 1);
    QCOMPARE(network.inFlight, 1);
    QVERIFY(!manager->busy());
    manager->removeSelection(false);
    QVERIFY(!manager->busy());
    QVERIFY(!manager->lastError().isEmpty());
    QVERIFY(!catalog.imageSource(u"Front // Back"_s, u"TST"_s, u"7"_s).isEmpty());
    QTRY_COMPARE(catalog.cardFaces(u"Front // Back"_s, u"TST"_s, u"7"_s).size(), 2);
    QTest::qWait(170);
    manager->removeSelection(false);
    QVERIFY2(manager->busy(), qPrintable(manager->lastError()));
    QTRY_VERIFY(!manager->busy());
    QVERIFY(catalog.imageSource(u"Front // Back"_s, u"TST"_s, u"7"_s).isEmpty());
    QTest::qWait(170);
    QVERIFY(catalog.cardFaces(u"Front // Back"_s, u"TST"_s, u"7"_s).isEmpty());
    QCOMPARE(network.requests.size(), 1);
}

void TestCardCatalog::cachedFacesFillDatabaseMisses() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const auto record =
        CardCatalog::parseCardObject(independentFaceFixture(), u"en"_s, u"Front // Back"_s);
    {
        hexproof::client::CardArtCache cache(storage.path());
        cache.rememberSuccess(cache.key(record.name, u"en"_s, u"TST"_s, u"7"_s), record);
        QVERIFY(cache.save());
    }
    const QString source = storage.filePath(u"ordinary.json"_s);
    QFile file(source);
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(QJsonDocument(QJsonArray{QJsonObject{{u"id"_s, u"ordinary-id"_s},
                                                    {u"name"_s, u"Ordinary"_s},
                                                    {u"layout"_s, u"normal"_s},
                                                    {u"set"_s, u"TST"_s},
                                                    {u"collector_number"_s, u"99"_s}}})
                   .toJson());
    file.close();
    const auto imported = CardCatalog::importBulkFile(source, storage.filePath(u"cards.sqlite"_s),
                                                      u"default_cards"_s);
    QVERIFY2(imported.ok, qPrintable(imported.error));
    FaceMetadataNetwork network;
    CardCatalog catalog(storage.path(), &network);
    QVERIFY(catalog.installed());
    QCOMPARE(catalog.cardFaces(u"Front // Back"_s, u"TST"_s, u"7"_s).size(), 2);
    catalog.prepareCardFacePreview(u"Ordinary"_s, u"TST"_s, u"99"_s);
    QVERIFY(network.requests.isEmpty());
}

void TestCardCatalog::cachedMeldFacesRequireRelatedPrintingEvidence() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString targetId = u"e195668b-4787-4b53-a69e-e75d9ce30000"_s;
    const QJsonArray parts{QJsonObject{
        {u"component"_s, u"meld_result"_s}, {u"id"_s, targetId}, {u"name"_s, u"Meld Result"_s}}};
    const QJsonObject component{{u"id"_s, u"c195668b-4787-4b53-a69e-e75d9ce30000"_s},
                                {u"name"_s, u"Meld Component"_s},
                                {u"layout"_s, u"meld"_s},
                                {u"set"_s, u"TST"_s},
                                {u"collector_number"_s, u"7"_s},
                                {u"all_parts"_s, parts}};
    const QJsonObject result{
        {u"id"_s, targetId},  {u"name"_s, u"Meld Result"_s},    {u"layout"_s, u"meld"_s},
        {u"set"_s, u"TST"_s}, {u"collector_number"_s, u"99"_s}, {u"all_parts"_s, parts}};
    {
        hexproof::client::CardArtCache cache(storage.path());
        auto record = CardCatalog::parseCardObject(component, u"en"_s, u"Meld Component"_s);
        cache.rememberSuccess(cache.key(record.name, u"en"_s, u"TST"_s, u"7"_s), record);
        auto impostor = result;
        impostor.insert(u"id"_s, u"different-printing-id"_s);
        record = CardCatalog::parseCardObject(impostor, u"en"_s, u"Meld Result"_s);
        cache.rememberSuccess(cache.key(record.name, u"en"_s, u"TST"_s, u"99"_s), record);
        QVERIFY(cache.save());
    }
    FaceMetadataNetwork network;
    network.cards.insert(u"/cards/"_s + targetId, result);
    CardCatalog catalog(storage.path(), &network);
    QVERIFY(catalog.cardFaces(u"Meld Component"_s, u"TST"_s, u"7"_s).isEmpty());
    catalog.prepareCardFacePreview(u"Meld Component"_s, u"TST"_s, u"7"_s);
    QTRY_COMPARE(catalog.cardFaces(u"Meld Component"_s, u"TST"_s, u"7"_s).size(), 2);
    const auto back = catalog.cardFaces(u"Meld Component"_s, u"TST"_s, u"7"_s).last().toMap();
    QCOMPARE(back.value(u"collectorNumber"_s).toString(), u"99"_s);
    QVERIFY(back.value(u"relatedCard"_s).toBool());
    QVERIFY(catalog.imageSource(u"Meld Result"_s, u"TST"_s, u"99"_s).isEmpty());
    catalog.prepareCardFacePreview(u"Meld Component"_s, u"TST"_s, u"7"_s);
    QCOMPARE(network.requests.size(), 1);
}

void TestCardCatalog::uncachedMeldResolutionHydratesRelatedPrinting_data() const
{
    QTest::addColumn<bool>("imageSucceeds");
    QTest::newRow("art-completion") << true;
    QTest::newRow("metadata-only-after-art-failure") << false;
}

void TestCardCatalog::uncachedMeldResolutionHydratesRelatedPrinting() const
{
    QFETCH(bool, imageSucceeds);
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    const QString targetId = u"e195668b-4787-4b53-a69e-e75d9ce30000"_s;
    const QJsonArray parts{QJsonObject{
        {u"component"_s, u"meld_result"_s}, {u"id"_s, targetId}, {u"name"_s, u"Meld Result"_s}}};
    const QJsonObject component{
        {u"id"_s, u"c195668b-4787-4b53-a69e-e75d9ce30000"_s},
        {u"name"_s, u"Meld Component"_s},
        {u"layout"_s, u"meld"_s},
        {u"set"_s, u"TST"_s},
        {u"collector_number"_s, u"7"_s},
        {u"oracle_text"_s, u"Meld component rules"_s},
        {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://faces.test/front.png"_s}}},
        {u"all_parts"_s, parts}};
    const QJsonObject result{
        {u"id"_s, targetId},  {u"name"_s, u"Meld Result"_s},    {u"layout"_s, u"meld"_s},
        {u"set"_s, u"TST"_s}, {u"collector_number"_s, u"99"_s}, {u"all_parts"_s, parts}};
    FaceMetadataNetwork network;
    network.cards.insert(u"/cards/tst/7"_s, component);
    network.cards.insert(u"/cards/"_s + targetId, result);
    if (imageSucceeds) {
        QImage image(300, 420, QImage::Format_RGB32);
        image.fill(Qt::green);
        QBuffer buffer(&network.image);
        QVERIFY(buffer.open(QIODevice::WriteOnly));
        QVERIFY(image.save(&buffer, "PNG"));
    }
    CardCatalog catalog(storage.path(), &network);
    catalog.setCardArtProvider(u"scryfall"_s);
    catalog.prepareCardFacePreview(u"Meld Component"_s, u"TST"_s, u"7"_s);
    QVERIFY(network.requests.isEmpty());
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    catalog.cacheCards({QVariantMap{{u"name"_s, u"Meld Component"_s},
                                    {u"setCode"_s, u"TST"_s},
                                    {u"collectorNumber"_s, u"7"_s}}});
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), 1, 10000);
    QCOMPARE(completed.first().last().toBool(), imageSucceeds);
    QTRY_COMPARE(catalog.cardFaces(u"Meld Component"_s, u"TST"_s, u"7"_s).size(), 2);
    const auto back = catalog.cardFaces(u"Meld Component"_s, u"TST"_s, u"7"_s).last().toMap();
    QCOMPARE(back.value(u"name"_s).toString(), u"Meld Result"_s);
    QCOMPARE(back.value(u"collectorNumber"_s).toString(), u"99"_s);
    QVERIFY(back.value(u"relatedCard"_s).toBool());
    QCOMPARE(std::count_if(
                 network.requests.cbegin(), network.requests.cend(),
                 [&targetId](const QUrl &url) { return url.path() == u"/cards/"_s + targetId; }),
             1);
}

void TestCardCatalog::legacySameNamedTokenReverseIsRefreshed_data() const
{
    QTest::addColumn<bool>("metadataProbe");
    QTest::addColumn<bool>("imageSucceeds");
    QTest::newRow("metadata-probe-then-cache") << true << true;
    QTest::newRow("normal-cache-success") << false << true;
    QTest::newRow("normal-cache-image-failure") << false << false;
}

void TestCardCatalog::legacySameNamedTokenReverseIsRefreshed() const
{
    QFETCH(bool, metadataProbe);
    QFETCH(bool, imageSucceeds);
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY(saveLegacyFaceArt(storage.path(), u"Goblin // Goblin"_s));
    {
        hexproof::client::CardArtCache cache(storage.path());
        cache.load();
        auto legacy =
            cache.exactRecord(cache.key(u"Goblin // Goblin"_s, u"en"_s, u"TST"_s, u"7"_s));
        legacy.requestedName = u"Goblin"_s;
        legacy.faceName = u"Goblin"_s;
        legacy.typeLine = u"Creature"_s;
        legacy.oracleText = u"Front rules"_s;
        legacy.oracleTextLanguage = u"en"_s;
        cache.rememberSuccess(cache.key(u"Goblin"_s, u"en"_s, u"TST"_s, u"7"_s), legacy);
        QVERIFY(cache.save());
    }
    FaceMetadataNetwork network;
    network.cards.insert(u"/cards/tst/7"_s,
                         independentFaceFixture(u"double_faced_token"_s, u"Goblin"_s, u"Goblin"_s));
    if (imageSucceeds) {
        QImage image(300, 420, QImage::Format_RGB32);
        image.fill(Qt::green);
        QBuffer buffer(&network.image);
        QVERIFY(buffer.open(QIODevice::WriteOnly));
        QVERIFY(image.save(&buffer, "PNG"));
    }
    CardCatalog catalog(storage.path(), &network);
    catalog.setCardArtProvider(u"scryfall"_s);
    catalog.setReuseLocalCardArt(true);
    const QString front = catalog.imageSource(u"Goblin // Goblin"_s, u"TST"_s, u"7"_s);
    QVERIFY(!front.isEmpty());
    QVERIFY(catalog.imageSource(u"Goblin"_s, u"TST"_s, u"7"_s).isEmpty());
    QVERIFY(catalog.cardRulesText(u"Goblin"_s, u"TST"_s, u"7"_s).isEmpty());
    if (metadataProbe) {
        catalog.prepareCardFacePreview(u"Goblin"_s, u"TST"_s, u"7"_s);
        QTRY_COMPARE(catalog.cardFaces(u"Goblin"_s, u"TST"_s, u"7"_s).size(), 2);
        QVERIFY(catalog.imageSource(u"Goblin"_s, u"TST"_s, u"7"_s).isEmpty());
        QCOMPARE(catalog.cardRulesText(u"Goblin"_s, u"TST"_s, u"7"_s), u"Back rules"_s);
        QCOMPARE(network.requests.size(), 1);
    }
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Goblin"_s}, {u"setCode"_s, u"TST"_s}, {u"collectorNumber"_s, u"7"_s}}});
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), metadataProbe ? 2 : 1, 10000);
    QCOMPARE(completed.last().last().toBool(), imageSucceeds);
    QTRY_COMPARE(catalog.cardFaces(u"Goblin"_s, u"TST"_s, u"7"_s).size(), 2);
    QCOMPARE(catalog.cardRulesText(u"Goblin"_s, u"TST"_s, u"7"_s), u"Back rules"_s);
    QCOMPARE(catalog.tokenDetails(u"Goblin"_s, u"TST"_s, u"7"_s).value(u"typeLine"_s).toString(),
             u"Land"_s);
    QCOMPARE(catalog.imageSource(u"Goblin"_s, u"TST"_s, u"7"_s).isEmpty(), !imageSucceeds);
    QCOMPARE(catalog.imageSource(u"Goblin // Goblin"_s, u"TST"_s, u"7"_s), front);
    QVERIFY(network.requests.contains(QUrl(u"https://faces.test/back.png"_s)));
    QVERIFY(!network.requests.contains(QUrl(u"https://faces.test/front.png"_s)));
}

void TestCardCatalog::verifiedTokenBackImportReplacesAmbiguousLegacyArt() const
{
    QTemporaryDir source, destination, archive;
    QVERIFY(source.isValid() && destination.isValid() && archive.isValid());
    hexproof::client::CardArtCache incoming(source.path()), previous(destination.path());
    QVERIFY(QDir().mkpath(incoming.imageRoot()));
    QVERIFY(QDir().mkpath(previous.imageRoot()));
    auto verified = CardCatalog::parseCardObject(
        independentFaceFixture(u"double_faced_token"_s, u"Goblin"_s, u"Goblin"_s), u"en"_s,
        u"Goblin"_s);
    QImage correct(4, 4, QImage::Format_RGB32);
    correct.fill(Qt::green);
    verified.imagePath = QDir(incoming.imageRoot()).filePath(u"back.png"_s);
    QVERIFY(correct.save(verified.imagePath));
    verified.imageLanguage = u"en"_s;
    verified.imageUrl = u"https://cards.scryfall.io/normal/back/token.png"_s;
    verified.resolutionVersion = kCardResolutionVersion;
    const QString key = incoming.key(u"Goblin"_s, u"en"_s, u"TST"_s, u"7"_s);
    incoming.rememberSuccess(key, verified);
    auto ambiguous = verified;
    ambiguous.faceMetadataChecked = false;
    ambiguous.independentFaces.clear();
    ambiguous.imageUrl = u"https://faces.test/front.png"_s;
    ambiguous.oracleText = u"Front rules"_s;
    ambiguous.typeLine = u"Creature"_s;
    ambiguous.imagePath = QDir(previous.imageRoot()).filePath(u"wrong-front.png"_s);
    correct.fill(Qt::red);
    QVERIFY(correct.save(ambiguous.imagePath));
    previous.rememberSuccess(key, ambiguous);
    const QString pack = archive.filePath(u"verified.hexproof-artpack"_s);
    const auto exported = hexproof::client::cardart::exportPack(pack, incoming.imageRoot(),
                                                                incoming.entries(), false, {}, {});
    QVERIFY2(exported.ok, qPrintable(exported.error));
    const auto imported =
        hexproof::client::cardart::importPack(pack, previous.imageRoot(), previous.entries());
    QVERIFY2(imported.ok, qPrintable(imported.error));
    QCOMPARE(imported.importedEntries.size(), 1);
    const auto replaced = imported.importedEntries.first().record;
    QVERIFY(replaced.faceMetadataChecked);
    QCOMPARE(replaced.imageUrl, verified.imageUrl);
    QCOMPARE(replaced.oracleText, u"Back rules"_s);
    QVERIFY(replaced.imagePath != ambiguous.imagePath);
    QImage restored(replaced.imagePath);
    QCOMPARE(restored.pixelColor(0, 0), QColor(Qt::green));
}

void TestCardCatalog::initTestCase()
{
    QVERIFY(m_settingsDir.isValid());
    QCoreApplication::setOrganizationName(u"HexproofTests"_s);
    QCoreApplication::setApplicationName(u"CardCatalogTest"_s);
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_settingsDir.path());
    QSettings settings;
    QVERIFY(settings.isWritable());
    QCOMPARE(settings.status(), QSettings::NoError);
}

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
    QCOMPARE(network.requestedUrls.size(), 3);
    QCOMPARE(network.requestedUrls.at(0).host(), u"api.scryfall.com"_s);
    QCOMPARE(network.requestedUrls.at(1), QUrl(u"https://mtgch.com/api/v1/card/M11/146/"_s));
    QCOMPARE(network.requestedUrls.at(2), QUrl(u"https://images.test/bolt.png"_s));
    const QList<QUrl> cachedRequests = network.requestedUrls;
    const QList<QVariant> arguments = availableSpy.takeFirst();
    QCOMPARE(arguments.at(1).toString(), u"闪电击"_s);
    QCOMPARE(arguments.at(2).toString(), u"瞬间"_s);
    QVERIFY(QFileInfo::exists(arguments.at(3).toString()));

    // A match prefetch for an already-cached printing completes on its queued
    // incremental batch without another network request.
    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }});
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 2, 1'000);
    QCOMPARE(network.requestedUrls, cachedRequests);
    QVERIFY(catalog.imageSource(u"Lightning Bolt"_s, u"M11"_s, u"146"_s).startsWith(u"file:"_s));

    catalog.setCardArtProvider(u"mtgch"_s);
    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }});
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 3, 1'000);
    QCOMPARE(network.requestedUrls, cachedRequests);
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
    int notifiedRevision = catalog.imageRevision();
    connect(&catalog, &CardCatalog::imageRevisionChanged, &catalog,
            [&]() { notifiedRevision = catalog.imageRevision(); });
    const QVariantList request{QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }};

    catalog.cacheCards(request);
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 2'000);
    QVERIFY(cacheSpy.first().at(3).toBool());
    QCOMPARE(availableSpy.count(), 1);
    QTRY_COMPARE(notifiedRevision, catalog.imageRevision());
    const int revisionAfterDownload = catalog.imageRevision();
    QVERIFY(revisionAfterDownload > 0);
    const int revisionSignalsAfterDownload = revisionSpy.count();
    QVERIFY(revisionSignalsAfterDownload > 0);

    catalog.cacheCards(request);
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 2, 1'000);
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

void TestCardCatalog::imageProviderForcesAsyncLoads() const
{
    CardImageProvider provider;
    QVERIFY(provider.flags().testFlag(QQuickImageProvider::ForceAsynchronousImageLoading));
    QVERIFY(provider.sourceForPath(QStringLiteral("/definitely/missing/card.jpg"))
                .startsWith(QStringLiteral("image://card-table/")));
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
    int notifiedRevision = catalog.imageRevision();
    connect(&catalog, &CardCatalog::imageRevisionChanged, &catalog,
            [&]() { notifiedRevision = catalog.imageRevision(); });

    catalog.cacheCards({QVariantMap{{u"name"_s, u"Lightning Bolt"_s}}});
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 2'000);
    QVERIFY(cacheSpy.first().at(3).toBool());
    QTRY_COMPARE(notifiedRevision, catalog.imageRevision());
    const int revisionAfterNameOnly = catalog.imageRevision();
    QVERIFY(revisionAfterNameOnly > 0);
    const int revisionSignalsAfterNameOnly = revisionSpy.count();
    const qsizetype initialRequests = network.requestedUrls.size();

    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }});
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 2, 1'000);
    QVERIFY(cacheSpy.at(1).at(3).toBool());
    QCOMPARE(catalog.imageRevision(), revisionAfterNameOnly + 1);
    QTRY_COMPARE(revisionSpy.count(), revisionSignalsAfterNameOnly + 1);
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
    {
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
        QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 2, 1'000);
        QVERIFY(cacheSpy.at(1).at(3).toBool());
        QCOMPARE(network.requestedUrls.size(), initialRequests);
    } // Close and flush the first process before reacquiring its image directory.

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
    QTRY_COMPARE_WITH_TIMEOUT(restartedSpy.count(), 1, 1'000);
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
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 2, 1'000);
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
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 2, 1'000);
    QCOMPARE(network.scryfallRequestCount, 1);

    catalog.retryCards(cards);
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 3, 2'000);
    QVERIFY(cacheSpy.at(2).at(3).toBool());
    QCOMPARE(network.scryfallRequestCount, 2);
    QVERIFY(catalog.lastError().isEmpty());
}

QTEST_GUILESS_MAIN(TestCardCatalog)
