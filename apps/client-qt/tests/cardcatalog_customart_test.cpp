// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "models/DeckLibraryModel.h"
#include "services/CardArtCache.h"
#include "services/CardArtManager.h"
#include "services/CardArtStorage.h"
#include "services/CardCatalog.h"
#include "services/CardCatalogCommon.h"
#include "services/CatalogRepository.h"
#include "services/CustomCardArtStore.h"

#include <QColor>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSaveFile>
#include <QSignalSpy>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QTemporaryDir>
#include <QTest>
#include <QTimer>

using namespace Qt::StringLiterals;
using namespace hexproof::client;

namespace {

class UnavailableReply final : public QNetworkReply
{
  public:
    UnavailableReply(const QNetworkRequest &request, QObject *parent)
        : QNetworkReply(parent)
    {
        setRequest(request);
        setUrl(request.url());
        open(QIODevice::ReadOnly | QIODevice::Unbuffered);
        setError(QNetworkReply::ContentNotFoundError, u"No network is available in this test."_s);
        QTimer::singleShot(0, this, [this]() {
            setFinished(true);
            emit errorOccurred(error());
            emit finished();
        });
    }
    void abort() override {}

  protected:
    qint64 readData(char *, qint64) override
    {
        return -1;
    }
};

class CountingNetwork final : public QNetworkAccessManager
{
  public:
    QList<QUrl> requests;
    bool holdReplies = false;

  protected:
    QNetworkReply *createRequest(Operation, const QNetworkRequest &request, QIODevice *) override
    {
        requests.append(request.url());
        if (holdReplies) {
            class PendingReply final : public QNetworkReply
            {
              public:
                PendingReply(const QNetworkRequest &request, QObject *parent)
                    : QNetworkReply(parent)
                {
                    setRequest(request);
                    setUrl(request.url());
                    open(QIODevice::ReadOnly | QIODevice::Unbuffered);
                }
                void abort() override {}

              protected:
                qint64 readData(char *, qint64) override
                {
                    return -1;
                }
            };
            return new PendingReply(request, this);
        }
        return new UnavailableReply(request, this);
    }
};

bool writeBytes(const QString &path, const QByteArray &bytes)
{
    if (!QDir().mkpath(QFileInfo(path).absolutePath()))
        return false;
    QSaveFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size() && file.commit();
}

QByteArray readBytes(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray{};
}

bool writePng(const QString &path, const QColor &color)
{
    if (!QDir().mkpath(QFileInfo(path).absolutePath()))
        return false;
    QImage image(32, 44, QImage::Format_ARGB32);
    image.fill(color);
    return image.save(path, "PNG");
}

QJsonObject card(const QString &name, const QString &collector, const QString &layout = u"normal"_s)
{
    return {{u"id"_s, u"test-printing-"_s + collector},
            {u"oracle_id"_s, u"test-oracle-"_s + name},
            {u"name"_s, name},
            {u"type_line"_s, u"Creature"_s},
            {u"set"_s, u"TST"_s},
            {u"collector_number"_s, collector},
            {u"lang"_s, u"en"_s},
            {u"layout"_s, layout},
            {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://custom-test.invalid/"_s +
                                                            collector + u".png"_s}}}};
}

bool writeCatalog(const QString &profile)
{
    QJsonObject transform = card(u"Front // Reverse"_s, u"1"_s, u"transform"_s);
    transform.remove(u"image_uris"_s);
    transform.insert(
        u"card_faces"_s,
        QJsonArray{
            QJsonObject{{u"name"_s, u"Front"_s},
                        {u"type_line"_s, u"Creature — Human"_s},
                        {u"image_uris"_s,
                         QJsonObject{{u"normal"_s, u"https://custom-test.invalid/front.png"_s}}}},
            QJsonObject{{u"name"_s, u"Reverse"_s},
                        {u"type_line"_s, u"Creature — Beast"_s},
                        {u"image_uris"_s,
                         QJsonObject{{u"normal"_s, u"https://custom-test.invalid/back.png"_s}}}}});
    QJsonObject another = transform;
    another.insert(u"id"_s, u"test-printing-2"_s);
    another.insert(u"collector_number"_s, u"2"_s);
    QJsonObject part = card(u"Bruna, the Fading Light"_s, u"10"_s, u"meld"_s);
    QJsonObject result = card(u"Brisela, Voice of Nightmares"_s, u"20"_s, u"meld"_s);
    const QJsonArray parts{QJsonObject{{u"id"_s, part.value(u"id"_s)},
                                       {u"name"_s, part.value(u"name"_s)},
                                       {u"component"_s, u"meld_part"_s}},
                           QJsonObject{{u"id"_s, result.value(u"id"_s)},
                                       {u"name"_s, result.value(u"name"_s)},
                                       {u"component"_s, u"meld_result"_s}}};
    part.insert(u"all_parts"_s, parts);
    result.insert(u"all_parts"_s, parts);
    const QJsonArray cards{
        transform, another, part, result,
        card(u"Emeritus of Truce // Swords to Plowshares"_s, u"13"_s, u"prepare"_s)};
    const QString source = QDir(profile).filePath(u"fixture.json"_s);
    return writeBytes(source, QJsonDocument(cards).toJson()) &&
           CardCatalog::importBulkFile(source, QDir(profile).filePath(u"cards.sqlite"_s),
                                       u"default_cards"_s)
               .ok;
}

QVariantMap request(const QString &name = u"Front"_s, const QString &collector = u"1"_s)
{
    return {{u"name"_s, name}, {u"setCode"_s, u"TST"_s}, {u"collectorNumber"_s, collector}};
}

bool installImage(CustomCardArtStore *store, const QString &path, const QVariantMap &binding)
{
    QSignalSpy finished(store, &CustomCardArtStore::operationFinished);
    store->setImage(QUrl::fromLocalFile(path), binding);
    if (finished.isEmpty() && !finished.wait(10000))
        return false;
    return finished.last().first().toMap().value(u"ok"_s).toBool();
}

bool removeBinding(CustomCardArtStore *store, const QVariantMap &binding)
{
    QSignalSpy finished(store, &CustomCardArtStore::operationFinished);
    store->removeBindings(binding);
    if (finished.isEmpty() && !finished.wait(10000))
        return false;
    return finished.last().first().toMap().value(u"ok"_s).toBool();
}

QString seedOfficialImage(const QString &profile)
{
    CardArtCache cache(profile);
    CardRecord record;
    record.requestedName = u"Front"_s;
    record.name = u"Front // Reverse"_s;
    record.faceName = u"Front"_s;
    record.setCode = u"TST"_s;
    record.collectorNumber = u"1"_s;
    record.imageLanguage = u"en"_s;
    record.imageUrl = u"https://custom-test.invalid/front.png"_s;
    record.imagePath = cache.imagePath(record.requestedName, record.imageUrl, u"en"_s);
    record.resolutionVersion = catalog_internal::kCardResolutionVersion;
    if (!writePng(record.imagePath, Qt::green))
        return {};
    cache.rememberSuccess(cache.key(record.requestedName, u"en"_s, u"TST"_s, u"1"_s), record);
    return cache.save() ? record.imagePath : QString{};
}

} // namespace

class CardCatalogCustomArtTest final : public QObject
{
    Q_OBJECT

  private slots:
    void backOverrideNeverBecomesFrontAndBothFacesIgnoreLanguage();
    void officialPrintingPreviewAndRemovalKeepDownloadedImage();
    void matchReadinessUsesOverridesWithoutNormalCacheOrNetwork();
    void cardScopeSharesVersionsButPrintingScopeWins();
    void prepareHasOneImageAndMeldUsesResultPrinting();
    void migrationRequiresRestartAndRejectsNewDownloads();
    void pendingRestartRetainsReadOnlyCustomMatchReadiness();
    void explicitCacheAndRepairStillRequestOfficialArtwork_data();
    void explicitCacheAndRepairStillRequestOfficialArtwork();
    void deckDisplayPathsAreTransientAndRefreshAfterRemoval();
    void prepareCharacteristicRequiresAnExactPrinting();
    void loneTranslatedBackAliasCannotResolveToFrontOverride();
    void sameNamedTokenCacheFallbackNeverCrossesFaces_data();
    void sameNamedTokenCacheFallbackNeverCrossesFaces();
    void restoresDuringUnrelatedOrdinaryArtworkWork_data();
    void restoresDuringUnrelatedOrdinaryArtworkWork();
    void restoreStillRequiresAvailableUnmigratedStorage();
};

void CardCatalogCustomArtTest::restoresDuringUnrelatedOrdinaryArtworkWork_data()
{
    QTest::addColumn<QString>("work");
    for (const QString &work :
         {u"hydration"_s, u"incremental-cache"_s, u"search"_s, u"network"_s, u"normal-manager"_s}) {
        QTest::newRow(qPrintable(work)) << work;
    }
}

void CardCatalogCustomArtTest::restoresDuringUnrelatedOrdinaryArtworkWork()
{
    QFETCH(QString, work);
    QTemporaryDir directory;
    QVERIFY(writeCatalog(directory.path()));
    const QString officialPath = seedOfficialImage(directory.path());
    QVERIFY(!officialPath.isEmpty());
    CountingNetwork network;
    CardCatalog catalog(directory.path(), &network);
    catalog.setLanguage(u"en"_s);
    const auto binding = catalog.customArtBindings(request()).first().toMap();
    const QString image = directory.filePath(u"custom.png"_s);
    QVERIFY(writePng(image, Qt::red));
    auto *store = catalog.customArtStore();
    QVERIFY2(installImage(store, image, binding), qPrintable(store->lastError()));
    QSignalSpy ordinaryChanges(&catalog, &CardCatalog::artCacheContentsChanged);
    QSignalSpy customChanges(&catalog, &CardCatalog::customArtContentsChanged);
    if (work == u"hydration"_s) {
        catalog.hydrateCachedCards({request()});
    } else if (work == u"incremental-cache"_s) {
        catalog.cacheCardsIncrementally({request()});
    } else if (work == u"search"_s) {
        catalog.search(u"Front"_s);
        QVERIFY(catalog.searching());
    } else if (work == u"network"_s) {
        network.holdReplies = true;
        catalog.setCardArtProvider(u"scryfall"_s);
        catalog.cacheCardsIncrementally({request(u"Uncached card"_s, u"999"_s)});
        QTRY_VERIFY_WITH_TIMEOUT(!network.requests.isEmpty(), 5000);
        QVERIFY(catalog.busy());
    } else {
        catalog.artManager()->refresh();
        QVERIFY(catalog.artManager()->busy());
    }
    const int requestsBeforeRestore = network.requests.size();
    QSignalSpy finished(store, &CustomCardArtStore::operationFinished);
    store->removeBindings(binding);
    QVERIFY2(store->busy(), qPrintable(store->lastError()));
    QTRY_COMPARE_WITH_TIMEOUT(finished.count(), 1, 5000);
    QVERIFY2(finished.first().first().toMap().value(u"ok"_s).toBool(),
             qPrintable(store->lastError()));
    QVERIFY(store->entries().isEmpty());
    QCOMPARE(catalog.imageSource(u"Front"_s, u"TST"_s, u"1"_s),
             QUrl::fromLocalFile(officialPath).toString());
    QVERIFY(QFileInfo::exists(officialPath));
    QCOMPARE(ordinaryChanges.count(), 0);
    QCOMPARE(customChanges.count(), 1);
    QCOMPARE(customChanges.first().first().toList().size(), 1);
    QCOMPARE(network.requests.size(), requestsBeforeRestore);
}

void CardCatalogCustomArtTest::restoreStillRequiresAvailableUnmigratedStorage()
{
    QTemporaryDir directory;
    const QString profile = directory.filePath(u"profile"_s);
    QVERIFY(writeCatalog(profile));
    const QString image = directory.filePath(u"custom.png"_s);
    QVERIFY(writePng(image, Qt::red));
    const QString destination = directory.filePath(u"destination"_s);
    QVERIFY(QDir().mkpath(destination));
    QString managedDirectory;
    {
        CountingNetwork network;
        CardCatalog catalog(profile, &network);
        auto *store = catalog.customArtStore();
        const auto binding = catalog.customArtBindings(request()).first().toMap();
        QSignalSpy installed(store, &CustomCardArtStore::operationFinished);
        store->setImage(QUrl::fromLocalFile(image), binding);
        QVERIFY(store->busy());
        catalog.artStorage()->migrateTo(QUrl::fromLocalFile(destination));
        QVERIFY(!catalog.artStorage()->busy());
        QVERIFY(!catalog.artStorage()->lastError().isEmpty());
        QTRY_COMPARE(installed.count(), 1);
        QVERIFY(installed.first().first().toMap().value(u"ok"_s).toBool());
        managedDirectory = catalog.artStorage()
                               ->previewDirectory(QUrl::fromLocalFile(destination))
                               .value(u"managedDirectory"_s)
                               .toString();
        QVERIFY(!managedDirectory.isEmpty());
        QSignalSpy migrated(catalog.artStorage(), &CardArtStorage::migrationFinished);
        catalog.artStorage()->migrateTo(QUrl::fromLocalFile(destination));
        QVERIFY(catalog.artStorage()->busy());
        QVERIFY(!removeBinding(store, binding));
        QCOMPARE(store->entries().size(), 1);
        QTRY_COMPARE(migrated.count(), 1);
        QVERIFY(catalog.artStorage()->restartRequired());
        QVERIFY(!removeBinding(store, binding));
        QCOMPARE(store->entries().size(), 1);
    }
    // A disconnected configured directory must not turn Restore into a write
    // to an automatically recreated directory or to the old default location.
    QVERIFY(QDir().rename(managedDirectory, managedDirectory + u"-offline"_s));
    const QByteArray indexBefore = readBytes(QDir(profile).filePath(u"custom-art.json"_s));
    CountingNetwork network;
    CardCatalog offline(profile, &network);
    QVERIFY(!offline.artStorage()->available());
    auto *store = offline.customArtStore();
    QSignalSpy finished(store, &CustomCardArtStore::operationFinished);
    store->clear();
    QCOMPARE(finished.count(), 1);
    QVERIFY(!finished.first().first().toMap().value(u"ok"_s).toBool());
    QCOMPARE(store->entries().size(), 1);
    QCOMPARE(readBytes(QDir(profile).filePath(u"custom-art.json"_s)), indexBefore);
    QVERIFY(!QFileInfo::exists(managedDirectory));
}

void CardCatalogCustomArtTest::backOverrideNeverBecomesFrontAndBothFacesIgnoreLanguage()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QVERIFY(writeCatalog(directory.path()));
    CountingNetwork network;
    CardCatalog catalog(directory.path(), &network);
    catalog.setLanguage(u"en"_s);
    const auto bindings = catalog.customArtBindings(request());
    QCOMPARE(bindings.size(), 2);
    const QVariantMap front = bindings.first().toMap();
    const QVariantMap back = bindings.last().toMap();
    QVERIFY(front.value(u"faceName"_s).toString().isEmpty());
    QCOMPARE(back.value(u"faceName"_s).toString(), u"Reverse"_s);
    const QString backSource = directory.filePath(u"back.png"_s);
    const QString frontSource = directory.filePath(u"front.png"_s);
    QVERIFY(writePng(backSource, Qt::blue));
    QVERIFY(writePng(frontSource, Qt::red));
    auto *store = catalog.customArtStore();
    QVERIFY2(installImage(store, backSource, back), qPrintable(store->lastError()));
    QVERIFY(catalog.imageSource(u"Front"_s, u"TST"_s, u"1"_s).isEmpty());
    QVERIFY(catalog.imageSource(u"Front // Reverse"_s, u"TST"_s, u"1"_s).isEmpty());
    const QString backImage = catalog.imageSource(u"Reverse"_s, u"TST"_s, u"1"_s);
    QVERIFY(!backImage.isEmpty());
    QVERIFY2(installImage(store, frontSource, front), qPrintable(store->lastError()));
    const QString frontImage = catalog.imageSource(u"Front"_s, u"TST"_s, u"1"_s);
    QVERIFY(!frontImage.isEmpty());
    QVERIFY(frontImage != backImage);
    for (const QString &language : {u"zh"_s, u"en"_s}) {
        catalog.setLanguage(language);
        QCOMPARE(catalog.imageSource(u"Front"_s, u"TST"_s, u"1"_s), frontImage);
        QCOMPARE(catalog.imageSource(u"Front // Reverse"_s, u"TST"_s, u"1"_s), frontImage);
        QCOMPARE(catalog.imageSource(u"Reverse"_s, u"TST"_s, u"1"_s), backImage);
    }
    QCOMPARE(network.requests.size(), 0);
}

void CardCatalogCustomArtTest::officialPrintingPreviewAndRemovalKeepDownloadedImage()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QVERIFY(writeCatalog(directory.path()));
    const QString officialPath = seedOfficialImage(directory.path());
    QVERIFY(!officialPath.isEmpty());
    CountingNetwork network;
    CardCatalog catalog(directory.path(), &network);
    catalog.setLanguage(u"en"_s);
    const QVariantMap binding = catalog.customArtBindings(request()).first().toMap();
    const QString customFile = directory.filePath(u"custom.png"_s);
    QVERIFY(writePng(customFile, Qt::red));
    auto *store = catalog.customArtStore();
    const QString official = QUrl::fromLocalFile(officialPath).toString();
    QCOMPARE(catalog.imageSource(u"Front"_s, u"TST"_s, u"1"_s), official);
    QVERIFY2(installImage(store, customFile, binding), qPrintable(store->lastError()));
    QVERIFY(catalog.imageSource(u"Front"_s, u"TST"_s, u"1"_s) != official);
    QCOMPARE(catalog.printingImageSource(u"Front"_s, u"TST"_s, u"1"_s), official);
    QSignalSpy revision(&catalog, &CardCatalog::imageRevisionChanged);
    QVERIFY2(removeBinding(store, binding), qPrintable(store->lastError()));
    QVERIFY(revision.count() > 0);
    QCOMPARE(catalog.imageSource(u"Front"_s, u"TST"_s, u"1"_s), official);
    QVERIFY(QFileInfo::exists(officialPath));
    QCOMPARE(network.requests.size(), 0);
}

void CardCatalogCustomArtTest::matchReadinessUsesOverridesWithoutNormalCacheOrNetwork()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QVERIFY(writeCatalog(directory.path()));
    CountingNetwork network;
    CardCatalog catalog(directory.path(), &network);
    catalog.setLanguage(u"en"_s);
    const QString file = directory.filePath(u"custom.png"_s);
    QVERIFY(writePng(file, Qt::red));
    auto *store = catalog.customArtStore();
    for (const QVariant &binding : catalog.customArtBindings(request()))
        QVERIFY2(installImage(store, file, binding.toMap()), qPrintable(store->lastError()));
    const QString cacheFile = directory.filePath(u"card-cache.json"_s);
    const QByteArray before = readBytes(cacheFile);
    QSignalSpy readiness(&catalog, &CardCatalog::matchCardCacheFinished);
    QSignalSpy downloaded(&catalog, &CardCatalog::cardCacheFinished);
    const auto expanded = catalog.expandCardFaceRequests({request()});
    QCOMPARE(expanded.size(), 2);
    catalog.cacheMatchCardsIncrementally(18, 4, expanded);
    QTRY_COMPARE(readiness.count(), 2);
    for (const auto &signal : readiness) {
        QCOMPARE(signal.at(0).toLongLong(), 18);
        QCOMPARE(signal.at(1).toULongLong(), quint64(4));
        QVERIFY(signal.last().toBool());
    }
    catalog.retryMatchCards(18, 5, expanded);
    QTRY_COMPARE(readiness.count(), 4);
    QTest::qWait(200);
    QCOMPARE(downloaded.count(), 0);
    QCOMPARE(network.requests.size(), 0);
    QCOMPARE(readBytes(cacheFile), before);
    QVERIFY(!catalog.busy());
}

void CardCatalogCustomArtTest::cardScopeSharesVersionsButPrintingScopeWins()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QVERIFY(writeCatalog(directory.path()));
    CountingNetwork network;
    CardCatalog catalog(directory.path(), &network);
    const auto bindings = catalog.customArtBindings(request());
    QVariantMap broad = bindings.first().toMap();
    broad.insert(u"scope"_s, u"card"_s);
    const QString blue = directory.filePath(u"blue.png"_s);
    const QString red = directory.filePath(u"red.png"_s);
    QVERIFY(writePng(blue, Qt::blue));
    QVERIFY(writePng(red, Qt::red));
    auto *store = catalog.customArtStore();
    QVERIFY2(installImage(store, blue, broad), qPrintable(store->lastError()));
    const QString acrossVersions = catalog.imageSource(u"Front"_s, u"TST"_s, u"2"_s);
    QVERIFY(!acrossVersions.isEmpty());
    QCOMPARE(catalog.imageSource(u"Front"_s, u"TST"_s, u"1"_s), acrossVersions);
    QVERIFY2(installImage(store, red, bindings.first().toMap()), qPrintable(store->lastError()));
    QVERIFY(catalog.imageSource(u"Front"_s, u"TST"_s, u"1"_s) != acrossVersions);
    QCOMPARE(catalog.imageSource(u"Front"_s, u"TST"_s, u"2"_s), acrossVersions);
    QVERIFY(catalog.imageSource(u"Reverse"_s, u"TST"_s, u"2"_s).isEmpty());
}

void CardCatalogCustomArtTest::prepareHasOneImageAndMeldUsesResultPrinting()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QVERIFY(writeCatalog(directory.path()));
    CountingNetwork network;
    CardCatalog catalog(directory.path(), &network);
    const auto prepare =
        catalog.customArtBindings(request(u"Emeritus of Truce // Swords to Plowshares"_s, u"13"_s));
    QCOMPARE(prepare.size(), 1);
    QVERIFY(prepare.first().toMap().value(u"faceName"_s).toString().isEmpty());
    const auto bindings = catalog.customArtBindings(request(u"Bruna, the Fading Light"_s, u"10"_s));
    QCOMPARE(bindings.size(), 2);
    const QVariantMap result = bindings.last().toMap();
    QVERIFY(result.value(u"relatedCard"_s).toBool());
    QCOMPARE(result.value(u"name"_s).toString(), u"Brisela, Voice of Nightmares"_s);
    QCOMPARE(result.value(u"collectorNumber"_s).toString(), u"20"_s);
    QVERIFY(result.value(u"faceName"_s).toString().isEmpty());
    const QString file = directory.filePath(u"meld-result.png"_s);
    QVERIFY(writePng(file, Qt::red));
    auto *store = catalog.customArtStore();
    QVERIFY2(installImage(store, file, result), qPrintable(store->lastError()));
    const QString resultImage =
        catalog.imageSource(u"Brisela, Voice of Nightmares"_s, u"TST"_s, u"20"_s);
    QVERIFY(!resultImage.isEmpty());
    QCOMPARE(catalog.imageSource(u"Brisela, Voice of Nightmares"_s, u"TST"_s, u"10"_s),
             resultImage);
    QVERIFY(catalog.imageSource(u"Bruna, the Fading Light"_s, u"TST"_s, u"10"_s).isEmpty());
    const auto expanded =
        catalog.expandCardFaceRequests({request(u"Bruna, the Fading Light"_s, u"10"_s)});
    QCOMPARE(expanded.size(), 2);
    QCOMPARE(expanded.last().toMap().value(u"collectorNumber"_s).toString(), u"20"_s);
}

void CardCatalogCustomArtTest::migrationRequiresRestartAndRejectsNewDownloads()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString profile = directory.filePath(u"profile"_s);
    QVERIFY(writeCatalog(profile));
    CountingNetwork network;
    CardCatalog catalog(profile, &network);
    const QString base = directory.filePath(u"destination"_s);
    QVERIFY(QDir().mkpath(base));
    QSignalSpy migrated(catalog.artStorage(), &CardArtStorage::migrationFinished);
    catalog.artStorage()->migrateTo(QUrl::fromLocalFile(base));
    QTRY_COMPARE(migrated.count(), 1);
    QVERIFY2(catalog.artStorage()->restartRequired(),
             qPrintable(catalog.artStorage()->lastError()));
    QSignalSpy readiness(&catalog, &CardCatalog::matchCardCacheFinished);
    catalog.cacheMatchCardsIncrementally(22, 1, {request()});
    QTRY_COMPARE(readiness.count(), 1);
    QVERIFY(!readiness.first().last().toBool());
    QTest::qWait(200);
    QCOMPARE(network.requests.size(), 0);
    QVERIFY(!catalog.busy());
    QVERIFY(!catalog.lastError().isEmpty());
}

void CardCatalogCustomArtTest::deckDisplayPathsAreTransientAndRefreshAfterRemoval()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QVERIFY(writeCatalog(directory.path()));
    CountingNetwork network;
    CardCatalog catalog(directory.path(), &network);
    DeckLibraryModel decks(directory.path());
    QVERIFY(decks.importDeck(u"Custom art deck"_s, u"custom"_s, u"7 Front (TST) 1\n"_s));
    const QString id = decks.data(decks.index(0), DeckLibraryModel::IdRole).toString();
    QVERIFY(decks.openDeck(id));
    decks.setImagePathResolver([&catalog](const DeckCard &card) {
        return QUrl(catalog.imageSource(card.name, card.setCode, card.collectorNumber))
            .toLocalFile();
    });
    connect(&catalog, &CardCatalog::customArtContentsChanged, &decks,
            &DeckLibraryModel::refreshCustomCardArt);
    QCOMPARE(decks.currentMissingImageCount(), 1);
    QVERIFY(!decks.currentReady());
    const QString file = directory.filePath(u"custom.png"_s);
    QVERIFY(writePng(file, Qt::red));
    const auto binding = catalog.customArtBindings(request()).first().toMap();
    auto *store = catalog.customArtStore();
    QVERIFY2(installImage(store, file, binding), qPrintable(store->lastError()));
    QTRY_COMPARE(decks.currentMissingImageCount(), 0);
    const QString displayed = decks.mainCards().first().toMap().value(u"imageSource"_s).toString();
    const QString localPath = QUrl(displayed).toLocalFile();
    QVERIFY(QFileInfo::exists(localPath));
    QVERIFY(localPath.contains(u"custom-art"_s));
    QCOMPARE(decks.currentMissingImageCount(), 0);
    QVERIFY(decks.currentReady());
    const QByteArray persisted = readBytes(directory.filePath(u"decks.json"_s));
    QVERIFY(!persisted.isEmpty());
    QVERIFY(!persisted.contains(displayed.toUtf8()));
    QVERIFY(!persisted.contains(localPath.toUtf8()));
    QVERIFY2(removeBinding(store, binding), qPrintable(store->lastError()));
    QTRY_VERIFY(decks.mainCards().first().toMap().value(u"imageSource"_s).toString().isEmpty());
    QCOMPARE(decks.currentMissingImageCount(), 1);
    QVERIFY(!decks.currentReady());
}

void CardCatalogCustomArtTest::prepareCharacteristicRequiresAnExactPrinting()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QVERIFY(writeCatalog(directory.path()));
    CountingNetwork network;
    CardCatalog catalog(directory.path(), &network);
    const QString canonical = u"Emeritus of Truce // Swords to Plowshares"_s;
    const auto bindings = catalog.customArtBindings(request(canonical, u"13"_s));
    QCOMPARE(bindings.size(), 1);
    const QString file = directory.filePath(u"prepare.png"_s);
    QVERIFY(writePng(file, Qt::yellow));
    auto *store = catalog.customArtStore();
    QVERIFY2(installImage(store, file, bindings.first().toMap()), qPrintable(store->lastError()));
    const QString wholeImage = catalog.imageSource(canonical, u"TST"_s, u"13"_s);
    QVERIFY(!wholeImage.isEmpty());
    QCOMPARE(catalog.imageSource(u"Swords to Plowshares"_s, u"TST"_s, u"13"_s), wholeImage);
    // This fixture deliberately has no standalone Swords printing. A fuzzy database
    // match to a Prepare characteristic must not become a name-only art alias.
    QVERIFY(catalog.imageSource(u"Swords to Plowshares"_s, {}, {}).isEmpty());
    QCOMPARE(network.requests.size(), 0);
}

void CardCatalogCustomArtTest::loneTranslatedBackAliasCannotResolveToFrontOverride()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QVERIFY(writeCatalog(directory.path()));
    const QString databasePath = directory.filePath(u"cards.sqlite"_s);
    const QString connectionName = u"custom-art-back-alias-fixture"_s;
    const bool inserted = [&]() {
        auto database = QSqlDatabase::addDatabase(u"QSQLITE"_s, connectionName);
        database.setDatabaseName(databasePath);
        if (!database.open())
            return false;
        QSqlQuery query(database);
        query.prepare(
            u"INSERT INTO card_aliases "
            "(oracle_id, face_name, localized_name, localized_type, preferred, face_order) "
            "VALUES (?, ?, ?, ?, 1, 1)"_s);
        query.addBindValue(u"test-oracle-Front // Reverse"_s);
        query.addBindValue(u"Reverse"_s);
        query.addBindValue(u"反面译名"_s);
        query.addBindValue(u"生物 — 野兽"_s);
        return query.exec();
    }();
    QSqlDatabase::removeDatabase(connectionName);
    QVERIFY(inserted);
    {
        CatalogRepository repository(databasePath);
        const CardRecord identity = repository.lookup({u"反面译名"_s, u"TST"_s, u"1"_s, u"zh"_s});
        QCOMPARE(identity.name, u"Front // Reverse"_s);
        QCOMPARE(identity.localizedName, u"反面译名"_s);
    }
    CountingNetwork network;
    CardCatalog catalog(directory.path(), &network);
    catalog.setLanguage(u"zh"_s);
    const auto bindings = catalog.customArtBindings(request());
    QCOMPARE(bindings.size(), 2);
    const QString file = directory.filePath(u"front-only.png"_s);
    QVERIFY(writePng(file, Qt::red));
    auto *store = catalog.customArtStore();
    QVERIFY2(installImage(store, file, bindings.first().toMap()), qPrintable(store->lastError()));
    QVERIFY(!catalog.imageSource(u"Front"_s, u"TST"_s, u"1"_s).isEmpty());
    QVERIFY(catalog.imageSource(u"Reverse"_s, u"TST"_s, u"1"_s).isEmpty());
    QVERIFY(catalog.imageSource(u"反面译名"_s, u"TST"_s, u"1"_s).isEmpty());
    QVERIFY(catalog.imageSource(u"反面译名"_s, {}, {}).isEmpty());
    QCOMPARE(network.requests.size(), 0);
}

void CardCatalogCustomArtTest::sameNamedTokenCacheFallbackNeverCrossesFaces_data()
{
    QTest::addColumn<bool>("reverseCached");
    QTest::newRow("cached-front-only") << false;
    QTest::newRow("cached-reverse-only") << true;
}

void CardCatalogCustomArtTest::sameNamedTokenCacheFallbackNeverCrossesFaces()
{
    QFETCH(bool, reverseCached);
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString canonical = u"Angel // Angel"_s;
    const QString cachedName = reverseCached ? u"Angel"_s : canonical;
    const QString missingName = reverseCached ? canonical : u"Angel"_s;
    QString cachedPath;
    {
        CardArtCache cache(directory.path());
        CardRecord record;
        record.name = canonical;
        record.requestedName = cachedName;
        record.faceName = u"Angel"_s;
        record.setCode = u"TST"_s;
        record.collectorNumber = u"30"_s;
        record.imageLanguage = u"en"_s;
        record.resolutionVersion = catalog_internal::kCardResolutionVersion;
        record.imagePath = QDir(cache.imageRoot()).filePath(u"cached.png"_s);
        QVERIFY(writePng(record.imagePath, Qt::blue));
        cachedPath = record.imagePath;
        cache.rememberSuccess(cache.key(cachedName, u"en"_s, u"TST"_s, u"30"_s), record);
        QVERIFY(cache.save());
    }
    CountingNetwork network;
    CardCatalog catalog(directory.path(), &network);
    catalog.setLanguage(u"en"_s);
    const QString cachedSource = QUrl::fromLocalFile(cachedPath).toString();
    QCOMPARE(catalog.imageSource(cachedName, u"TST"_s, u"30"_s), cachedSource);
    QCOMPARE(catalog.tableImageSource(cachedName, u"TST"_s, u"30"_s), cachedSource);
    QVERIFY(catalog.imageSource(missingName, u"TST"_s, u"30"_s).isEmpty());
    QVERIFY(catalog.tableImageSource(missingName, u"TST"_s, u"30"_s).isEmpty());
    const QVariantMap binding{{u"scope"_s, u"printing"_s},
                              {u"name"_s, canonical},
                              {u"faceName"_s, reverseCached ? QString{} : u"Angel"_s},
                              {u"setCode"_s, u"TST"_s},
                              {u"collectorNumber"_s, u"30"_s}};
    const QString customPath = directory.filePath(u"custom.png"_s);
    QVERIFY(writePng(customPath, Qt::red));
    auto *store = catalog.customArtStore();
    QVERIFY2(installImage(store, customPath, binding), qPrintable(store->lastError()));
    const QString customSource = catalog.imageSource(missingName, u"TST"_s, u"30"_s);
    QVERIFY(!customSource.isEmpty());
    QVERIFY(customSource != cachedSource);
    QCOMPARE(catalog.imageSource(cachedName, u"TST"_s, u"30"_s), cachedSource);
    QVERIFY2(removeBinding(store, binding), qPrintable(store->lastError()));
    QVERIFY(catalog.imageSource(missingName, u"TST"_s, u"30"_s).isEmpty());
    QVERIFY(catalog.tableImageSource(missingName, u"TST"_s, u"30"_s).isEmpty());
    QCOMPARE(catalog.imageSource(cachedName, u"TST"_s, u"30"_s), cachedSource);
    QCOMPARE(network.requests.size(), 0);
}

void CardCatalogCustomArtTest::pendingRestartRetainsReadOnlyCustomMatchReadiness()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString profile = directory.filePath(u"profile"_s);
    QVERIFY(writeCatalog(profile));
    CountingNetwork network;
    CardCatalog catalog(profile, &network);
    const QString file = directory.filePath(u"custom.png"_s);
    QVERIFY(writePng(file, Qt::blue));
    auto *store = catalog.customArtStore();
    const auto binding = catalog.customArtBindings(request()).first().toMap();
    QVERIFY2(installImage(store, file, binding), qPrintable(store->lastError()));
    const QString oldImage = catalog.imageSource(u"Front"_s, u"TST"_s, u"1"_s);
    const QString base = directory.filePath(u"destination"_s);
    QVERIFY(QDir().mkpath(base));
    QSignalSpy migrated(catalog.artStorage(), &CardArtStorage::migrationFinished);
    catalog.artStorage()->migrateTo(QUrl::fromLocalFile(base));
    QTRY_COMPARE(migrated.count(), 1);
    QVERIFY2(catalog.artStorage()->restartRequired(),
             qPrintable(catalog.artStorage()->lastError()));
    catalog.clearLastError();
    QSignalSpy ready(&catalog, &CardCatalog::matchCardCacheFinished);
    catalog.cacheMatchCardsIncrementally(31, 2, {request()});
    QTRY_COMPARE(ready.count(), 1);
    QVERIFY(ready.first().last().toBool());
    QCOMPARE(catalog.imageSource(u"Front"_s, u"TST"_s, u"1"_s), oldImage);
    QVERIFY(catalog.lastError().isEmpty());
    QVERIFY(!catalog.busy());
    QCOMPARE(network.requests.size(), 0);
}

void CardCatalogCustomArtTest::explicitCacheAndRepairStillRequestOfficialArtwork_data()
{
    QTest::addColumn<bool>("retry");
    QTest::newRow("cache") << false;
    QTest::newRow("repair-retry") << true;
}

void CardCatalogCustomArtTest::explicitCacheAndRepairStillRequestOfficialArtwork()
{
    QFETCH(bool, retry);
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QVERIFY(writeCatalog(directory.path()));
    CountingNetwork network;
    CardCatalog catalog(directory.path(), &network);
    catalog.setLanguage(u"en"_s);
    catalog.setCardArtProvider(u"scryfall"_s);
    const QString file = directory.filePath(u"custom.png"_s);
    QVERIFY(writePng(file, Qt::red));
    auto *store = catalog.customArtStore();
    for (const QVariant &binding : catalog.customArtBindings(request()))
        QVERIFY2(installImage(store, file, binding.toMap()), qPrintable(store->lastError()));
    QCOMPARE(network.requests.size(), 0);
    if (retry)
        catalog.retryCards({request()});
    else
        catalog.cacheCards({request()});
    QTRY_VERIFY_WITH_TIMEOUT(!network.requests.isEmpty(), 5000);
}

QTEST_GUILESS_MAIN(CardCatalogCustomArtTest)
#include "cardcatalog_customart_test.moc"
