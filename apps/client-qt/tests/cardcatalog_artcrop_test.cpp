// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "cardcatalog_test.h"

#include "services/BackgroundTaskPools.h"
#include "services/CardArtCache.h"
#include "services/CardArtCrop.h"
#include "services/CardArtManager.h"

#include <QPointer>
#include <QScopeGuard>
#include <QSemaphore>

using hexproof::client::CardArtCache;
using hexproof::client::CardRecord;
using hexproof::client::catalog_internal::artCropUrlForImage;

namespace {

QString fullUrl(int number)
{
    return u"https://cards.scryfall.io/normal/front/0/0/00000000-0000-4000-8000-%1.jpg"_s.arg(
        number, 12, 10, QLatin1Char('0'));
}

QVariantMap cropCard(int number = 1)
{
    return {{u"name"_s, u"Crop Card %1"_s.arg(number)},
            {u"setCode"_s, u"TST"_s},
            {u"collectorNumber"_s, QString::number(number)}};
}

QJsonObject cropMetadata(int number = 1, int imageNumber = 0)
{
    return {
        {u"id"_s, u"00000000-0000-4000-8000-%1"_s.arg(number, 12, 10, QLatin1Char('0'))},
        {u"oracle_id"_s, u"crop-oracle-%1"_s.arg(number)},
        {u"name"_s, u"Crop Card %1"_s.arg(number)},
        {u"set"_s, u"tst"_s},
        {u"collector_number"_s, QString::number(number)},
        {u"layout"_s, u"normal"_s},
        {u"type_line"_s, u"Creature"_s},
        {u"oracle_text"_s, u"Current rules"_s},
        {u"image_status"_s, u"highres_scan"_s},
        {u"image_uris"_s, QJsonObject{{u"normal"_s, fullUrl(imageNumber ? imageNumber : number)}}}};
}

bool writeCropCatalog(const QString &root, int count = 1, int firstImage = 0)
{
    QJsonArray cards;
    for (int number = 1; number <= count; ++number)
        cards.append(cropMetadata(number, number == 1 ? firstImage : 0));
    const QString path = QDir(root).filePath(u"cards.json"_s);
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(QJsonDocument(cards).toJson());
    file.close();
    return CardCatalog::importBulkFile(path, QDir(root).filePath(u"cards.sqlite"_s),
                                       u"default_cards"_s)
        .ok;
}

QString seedFullImage(const QString &root, int number = 1, const QString &language = u"en"_s)
{
    CardArtCache cache(root);
    cache.load();
    CardRecord record = CardCatalog::parseCardObject(cropMetadata(number), u"en"_s,
                                                     cropCard(number).value(u"name"_s).toString());
    record.requestedName = record.name;
    record.resolutionVersion = kCardResolutionVersion;
    record.imagePath = cache.imagePath(record.name, record.imageUrl, language);
    QImage image(8, 12, QImage::Format_RGB32);
    image.fill(Qt::blue);
    if (!image.save(record.imagePath))
        return {};
    cache.rememberSuccess(cache.key(record.name, language, record.setCode, record.collectorNumber),
                          record);
    return cache.save() ? record.imagePath : QString{};
}

QByteArray localCropBytes()
{
    QImage image(12, 8, QImage::Format_RGB32);
    image.fill(Qt::green);
    QByteArray bytes;
    QBuffer buffer(&bytes);
    buffer.open(QIODevice::WriteOnly);
    image.save(&buffer, "PNG");
    return bytes;
}

QString seedLocalCrop(const QString &root, const QByteArray &bytes)
{
    CardArtCache cache(root);
    cache.load();
    const QString key = cache.key(u"Crop Card 1"_s, u"en"_s, u"TST"_s, u"1"_s);
    CardRecord record = cache.exactRecord(key);
    record.artCropUrl = artCropUrlForImage(record.imageUrl);
    record.artCropPath = cache.imagePath(record.name, record.artCropUrl, u"en"_s);
    QFile file(record.artCropPath);
    if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size())
        return {};
    file.close();
    cache.rememberSuccess(key, record);
    return cache.save() ? record.artCropPath : QString{};
}

class CropReply final : public QNetworkReply
{
  public:
    CropReply(const QNetworkRequest &request, QByteArray payload, const QByteArray &type,
              int status, QObject *parent)
        : QNetworkReply(parent),
          m_payload(std::move(payload))
    {
        setRequest(request);
        setUrl(request.url());
        setAttribute(QNetworkRequest::HttpStatusCodeAttribute, status);
        setHeader(QNetworkRequest::ContentTypeHeader, type);
        if (status == 404)
            setError(ContentNotFoundError, u"Missing optional crop"_s);
        open(QIODevice::ReadOnly | QIODevice::Unbuffered);
    }

    void finish()
    {
        if (isFinished())
            return;
        setFinished(true);
        emit readyRead();
        emit finished();
    }

    void abort() override
    {
        setError(OperationCanceledError, u"Cancelled"_s);
        finish();
    }

    qint64 bytesAvailable() const override
    {
        return m_payload.size() - m_offset + QNetworkReply::bytesAvailable();
    }

  protected:
    qint64 readData(char *data, qint64 maximum) override
    {
        const qint64 size = qMin(maximum, m_payload.size() - m_offset);
        if (size <= 0)
            return -1;
        memcpy(data, m_payload.constData() + m_offset, static_cast<size_t>(size));
        m_offset += size;
        return size;
    }

  private:
    QByteArray m_payload;
    qint64 m_offset = 0;
};

class CropNetwork final : public QNetworkAccessManager
{
  public:
    CropNetwork()
    {
        QImage image(12, 8, QImage::Format_RGB32);
        image.fill(Qt::green);
        QBuffer buffer(&imageBytes);
        buffer.open(QIODevice::WriteOnly);
        image.save(&buffer, "PNG");
    }

    QList<QUrl> urls;
    QList<QPointer<CropReply>> held;
    bool holdCrops = true;
    bool holdFull = false;
    bool holdRules = false;
    bool failCrops = false;
    bool invalidCrops = false;
    int imageActive = 0;
    int imagePeak = 0;

    int cropCount() const
    {
        return std::count_if(urls.cbegin(), urls.cend(), [](const QUrl &url) {
            return url.path().startsWith(u"/art_crop/"_s);
        });
    }

    void release(bool crops, bool rules = false)
    {
        if (rules)
            holdRules = false;
        else if (crops)
            holdCrops = false;
        else
            holdFull = false;
        for (const auto &reply : std::as_const(held)) {
            if (!reply)
                continue;
            const bool isRules = reply->url().host() == u"mtgch.com"_s;
            const bool isCrop = reply->url().path().startsWith(u"/art_crop/"_s);
            if (rules ? isRules : (!isRules && isCrop == crops)) {
                QTimer::singleShot(0, reply, [reply] {
                    if (reply)
                        reply->finish();
                });
            }
        }
    }

  protected:
    QNetworkReply *createRequest(Operation, const QNetworkRequest &request, QIODevice *) override
    {
        const QUrl url = request.url();
        urls.append(url);
        const bool image = url.host() == u"cards.scryfall.io"_s;
        const bool crop = image && url.path().startsWith(u"/art_crop/"_s);
        const bool rules = url.host() == u"mtgch.com"_s;
        QByteArray bytes = imageBytes;
        if (!image) {
            QJsonObject object = cropMetadata();
            if (rules) {
                object.insert(u"zhs_name"_s, u"测试生物"_s);
                object.insert(u"zhs_text"_s, u"后到的中文规则。"_s);
            }
            bytes = QJsonDocument(object).toJson();
        } else if (crop && invalidCrops) {
            bytes = QByteArrayLiteral("not an image");
        }
        auto *reply = new CropReply(request, bytes, image ? "image/png" : "application/json",
                                    crop && failCrops ? 404 : 200, this);
        if (image) {
            imagePeak = qMax(imagePeak, ++imageActive);
            connect(reply, &QNetworkReply::finished, this, [this] { --imageActive; });
        }
        if ((image && (crop ? holdCrops : holdFull)) || (rules && holdRules))
            held.append(reply);
        else
            QTimer::singleShot(0, reply, [reply] { reply->finish(); });
        return reply;
    }

  private:
    QByteArray imageBytes;
};

} // namespace

void TestCardCatalog::optionalArtCropFollowsSuccessfulFullImage() const
{
    // Exercise both the indexed direct-image path and the provider resolver.
    for (bool indexed : {false, true}) {
        QTemporaryDir storage;
        QVERIFY(storage.isValid());
        if (indexed)
            QVERIFY(writeCropCatalog(storage.path()));
        CropNetwork network;
        CardCatalog catalog(storage.path(), &network);
        catalog.setLanguage(u"en"_s);
        catalog.setCardArtProvider(u"scryfall"_s);
        QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
        QSignalSpy crops(&catalog, &CardCatalog::cardArtCropAvailable);
        int notifiedImageRevision = -1;
        connect(&catalog, &CardCatalog::imageRevisionChanged, &catalog,
                [&]() { notifiedImageRevision = catalog.imageRevision(); });
        catalog.cacheCards({cropCard()});
        QTRY_COMPARE(completed.size(), 1);
        QVERIFY(completed.first().last().toBool());
        QTRY_COMPARE(network.cropCount(), 1);
        QVERIFY(catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
        const QString full = catalog.imageSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s);
        QVERIFY(!full.isEmpty());
        QVERIFY(!catalog.cacheProgressActive());
        QTRY_COMPARE(notifiedImageRevision, catalog.imageRevision());
        const int fullImageRevision = catalog.imageRevision();
        network.release(true);
        QTRY_VERIFY(!catalog.busy());
        QVERIFY(!catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
        QCOMPARE(catalog.imageSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s), full);
        QCOMPARE(completed.size(), 1);
        QCOMPARE(crops.size(), 1);
        QCOMPARE(crops.first().first().toString(), u"Crop Card 1"_s);
        QCOMPARE(catalog.imageRevision(), fullImageRevision);
        QVERIFY(catalog.lastError().isEmpty());
    }
}

void TestCardCatalog::optionalArtCropCacheHitsRetryAndStayLocalOnReads() const
{
    for (bool invalid : {false, true}) {
        QTemporaryDir storage;
        QVERIFY(!seedFullImage(storage.path()).isEmpty());
        CropNetwork network;
        network.failCrops = !invalid;
        network.invalidCrops = invalid;
        CardCatalog catalog(storage.path(), &network);
        catalog.setLanguage(u"en"_s);
        const QString full = catalog.imageSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s);
        QVERIFY(!full.isEmpty());
        QVERIFY(catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
        catalog.hydrateCachedCards({cropCard()});
        QTest::qWait(40);
        QVERIFY(network.urls.isEmpty());
        QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
        catalog.cacheCards({cropCard(), cropCard()});
        QTRY_COMPARE(network.cropCount(), 1);
        QTRY_COMPARE(completed.size(), 1);
        network.release(true);
        QTRY_VERIFY(!catalog.busy());
        QVERIFY(completed.first().last().toBool());
        QVERIFY(catalog.lastError().isEmpty());
        catalog.cacheCards({cropCard()});
        QTRY_COMPARE(completed.size(), 2);
        QTRY_VERIFY(!catalog.busy());
        QCOMPARE(network.cropCount(), 1);
        network.failCrops = false;
        network.invalidCrops = false;
        catalog.retryCards({cropCard()});
        QTRY_COMPARE(completed.size(), 3);
        QTRY_VERIFY(!catalog.busy());
        QCOMPARE(network.cropCount(), 2);
        QVERIFY(!catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
        QCOMPARE(catalog.imageSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s), full);
        QCOMPARE(network.urls.size(), 2);
    }
}

void TestCardCatalog::optionalArtCropSharesSlotsAndKeepsMaintenanceExclusive() const
{
    QTemporaryDir storage;
    QVERIFY(writeCropCatalog(storage.path(), 9));
    QVERIFY(!seedFullImage(storage.path()).isEmpty());
    CropNetwork network;
    network.holdFull = true;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"en"_s);
    catalog.setCardArtProvider(u"scryfall"_s);
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    catalog.prepareTableArtCrops({cropCard()});
    QTRY_COMPARE(network.cropCount(), 1);
    QCOMPARE(completed.size(), 0);
    QVariantList cards;
    for (int number = 2; number <= 9; ++number)
        cards.append(cropCard(number));
    catalog.cacheCards(cards);
    QTRY_COMPARE(network.imageActive, 6);
    QVERIFY(network.imagePeak <= 6);
    auto *manager = catalog.artManager();
    manager->removeSelection(false);
    QVERIFY(!manager->busy());
    QVERIFY(!manager->lastError().isEmpty());
    network.release(false);
    QTRY_COMPARE(completed.size(), 8);
    QVERIFY(catalog.busy());
    QVERIFY(!catalog.cacheProgressActive());
    QCOMPARE(network.cropCount(), 1);
    network.release(true);
    QTRY_VERIFY(!catalog.busy());
    QCOMPARE(network.cropCount(), 9);
    QVERIFY(network.imagePeak <= 6);
    QCOMPARE(completed.size(), 8);
}

void TestCardCatalog::optionalArtCropDiscardsSupersededSource() const
{
    QTemporaryDir storage;
    QVERIFY(writeCropCatalog(storage.path(), 1, 1001));
    const QString oldPath = seedFullImage(storage.path());
    QVERIFY(!oldPath.isEmpty());
    CropNetwork network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"en"_s);
    catalog.setCardArtProvider(u"scryfall"_s);
    catalog.prepareTableArtCrops({cropCard()});
    QTRY_COMPARE(network.cropCount(), 1);
    QVERIFY(QFile::remove(oldPath));
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    catalog.retryCards({cropCard()});
    QTRY_COMPARE(completed.size(), 1);
    QVERIFY(completed.first().last().toBool());
    const QString newFull = catalog.imageSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s);
    QVERIFY(!newFull.isEmpty());
    QVERIFY(QUrl(newFull).toLocalFile() != oldPath);
    network.release(true);
    QTRY_VERIFY(!catalog.busy());
    QCOMPARE(network.cropCount(), 2);
    QVERIFY(!catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
    QCOMPARE(catalog.imageSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s), newFull);
    QCOMPARE(network.urls.last().toString(), artCropUrlForImage(fullUrl(1001)));
    CardArtCache paths(storage.path());
    QVERIFY(!QFileInfo::exists(
        paths.imagePath(u"Crop Card 1"_s, artCropUrlForImage(fullUrl(1)), u"en"_s)));
}

void TestCardCatalog::optionalArtCropPreservesLaterLocalizedRules() const
{
    for (bool cropFirst : {false, true}) {
        QTemporaryDir storage;
        QVERIFY(!seedFullImage(storage.path(), 1, u"zh"_s).isEmpty());
        CropNetwork network;
        network.holdRules = true;
        auto catalog = std::make_unique<CardCatalog>(storage.path(), &network);
        catalog->setLanguage(u"zh"_s);
        catalog->cacheCards({cropCard()});
        QTRY_COMPARE(network.cropCount(), 1);
        QTRY_COMPARE(network.urls.size(), 2);
        if (cropFirst) {
            network.release(true);
            QTRY_VERIFY(!catalog->tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
            network.release(false, true);
        } else {
            network.release(false, true);
            QTRY_COMPARE(catalog->cardRulesText(u"Crop Card 1"_s, u"TST"_s, u"1"_s, u"zh"_s),
                         u"后到的中文规则。"_s);
            network.release(true);
        }
        QTRY_VERIFY(!catalog->tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
        QTRY_COMPARE(catalog->cardRulesText(u"Crop Card 1"_s, u"TST"_s, u"1"_s, u"zh"_s),
                     u"后到的中文规则。"_s);
        QTRY_VERIFY(!catalog->busy());
        catalog.reset();
        CardArtCache cache(storage.path());
        cache.load();
        const CardRecord record =
            cache.exactRecord(cache.key(u"Crop Card 1"_s, u"zh"_s, u"TST"_s, u"1"_s));
        QVERIFY(!record.artCropPath.isEmpty());
        QCOMPARE(record.artCropUrl, artCropUrlForImage(record.imageUrl));
        QCOMPARE(record.oracleText, u"后到的中文规则。"_s);
    }
}

void TestCardCatalog::optionalArtCropStopsOnDestruction() const
{
    QTemporaryDir storage;
    QVERIFY(!seedFullImage(storage.path()).isEmpty());
    CropNetwork network;
    auto catalog = std::make_unique<CardCatalog>(storage.path(), &network);
    catalog->setLanguage(u"en"_s);
    catalog->prepareTableArtCrops({cropCard()});
    QTRY_COMPARE(network.imageActive, 1);
    catalog.reset();
    QTRY_COMPARE(network.imageActive, 0);
    network.release(true);
    QTest::qWait(20);
    CardArtCache cache(storage.path());
    cache.load();
    const CardRecord record =
        cache.exactRecord(cache.key(u"Crop Card 1"_s, u"en"_s, u"TST"_s, u"1"_s));
    QVERIFY(record.artCropPath.isEmpty());
    QVERIFY(QFileInfo::exists(record.imagePath));
    QCOMPARE(network.urls.size(), 1);
}

void TestCardCatalog::optionalArtCropValidationStopsOnDestruction() const
{
    QTemporaryDir storage;
    QVERIFY(!seedFullImage(storage.path()).isEmpty());
    auto *pool = hexproof::client::BackgroundTaskPools::cardImageValidation();
    QSemaphore entered;
    QSemaphore release;
    const auto unblock = qScopeGuard([&]() {
        release.release(2);
        pool->waitForDone();
    });
    for (int i = 0; i < 2; ++i) {
        pool->start([&]() {
            entered.release();
            release.acquire();
        });
    }
    QVERIFY(entered.tryAcquire(2, 3'000));
    CropNetwork network;
    network.holdCrops = false;
    auto catalog = std::make_unique<CardCatalog>(storage.path(), &network);
    catalog->setLanguage(u"en"_s);
    catalog->prepareTableArtCrops({cropCard()});
    QTRY_COMPARE(network.cropCount(), 1);
    QTRY_COMPARE(network.imageActive, 0);
    QVERIFY(catalog->busy());
    catalog->artManager()->removeSelection(false);
    QVERIFY(!catalog->artManager()->busy());
    QVERIFY(!catalog->artManager()->lastError().isEmpty());
    catalog.reset();
    release.release(2);
    pool->waitForDone();
    QTest::qWait(20);
    CardArtCache cache(storage.path());
    cache.load();
    const CardRecord record =
        cache.exactRecord(cache.key(u"Crop Card 1"_s, u"en"_s, u"TST"_s, u"1"_s));
    QVERIFY(record.artCropPath.isEmpty());
    QVERIFY(!QFileInfo::exists(
        cache.imagePath(record.name, artCropUrlForImage(record.imageUrl), u"en"_s)));
}

void TestCardCatalog::optionalArtCropRetryReplacesDamagedFile() const
{
    QTemporaryDir storage;
    QVERIFY(!seedFullImage(storage.path()).isEmpty());
    QString cropPath;
    {
        CardArtCache cache(storage.path());
        cache.load();
        const QString key = cache.key(u"Crop Card 1"_s, u"en"_s, u"TST"_s, u"1"_s);
        CardRecord record = cache.exactRecord(key);
        record.artCropUrl = artCropUrlForImage(record.imageUrl);
        record.artCropPath = cache.imagePath(record.name, record.artCropUrl, u"en"_s);
        cropPath = record.artCropPath;
        QFile damaged(cropPath);
        QVERIFY(damaged.open(QIODevice::WriteOnly));
        damaged.write("broken crop");
        damaged.close();
        cache.rememberSuccess(key, record);
        QVERIFY(cache.save());
    }
    CropNetwork network;
    network.holdCrops = false;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"en"_s);
    QSignalSpy crops(&catalog, &CardCatalog::cardArtCropAvailable);
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    QVERIFY(catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
    QVERIFY(hexproof::client::BackgroundTaskPools::cardImageValidation()->waitForDone(3'000));
    QCoreApplication::processEvents();
    QVERIFY(catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
    QVERIFY(network.urls.isEmpty());
    QCOMPARE(crops.size(), 0);
    catalog.retryCards({cropCard()});
    QTRY_COMPARE(completed.size(), 1);
    QTRY_VERIFY(!catalog.busy());
    QCOMPARE(network.cropCount(), 1);
    QCOMPARE(crops.size(), 1);
    QVERIFY(!QImage(cropPath).isNull());
    QVERIFY(!catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
    QVERIFY(completed.first().last().toBool());
}

void TestCardCatalog::optionalArtCropLocalReadsValidateWithoutNetwork() const
{
    QTemporaryDir storage;
    QVERIFY(!seedFullImage(storage.path()).isEmpty());
    QVERIFY(!seedLocalCrop(storage.path(), localCropBytes()).isEmpty());
    auto *pool = hexproof::client::BackgroundTaskPools::cardImageValidation();
    QSemaphore entered;
    QSemaphore release;
    const auto unblock = qScopeGuard([&]() {
        release.release(2);
        pool->waitForDone();
    });
    for (int i = 0; i < 2; ++i) {
        pool->start([&]() {
            entered.release();
            release.acquire();
        });
    }
    QVERIFY(entered.tryAcquire(2, 3'000));
    CropNetwork network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"en"_s);
    QSignalSpy crops(&catalog, &CardCatalog::cardArtCropAvailable);
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    const int revision = catalog.imageRevision();
    const QString full = catalog.imageSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s);
    QVERIFY(!full.isEmpty());
    for (int i = 0; i < 20; ++i)
        QVERIFY(catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
    catalog.hydrateCachedCards({cropCard()});
    QVERIFY(!catalog.busy());
    QVERIFY(network.urls.isEmpty());
    // An import can replace bytes while old validation is queued, including
    // replacements whose stat fingerprint is unchanged. Only its new read wins.
    emit catalog.artCacheContentsChanged();
    QVERIFY(catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
    release.release(2);
    QVERIFY(pool->waitForDone(3'000));
    QTRY_COMPARE(crops.size(), 1);
    for (int i = 0; i < 20; ++i)
        QVERIFY(!catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
    QCoreApplication::processEvents();
    QCOMPARE(crops.size(), 1);
    QCOMPARE(crops.first().first().toString(), u"Crop Card 1"_s);
    QCOMPARE(completed.size(), 0);
    QCOMPARE(catalog.imageRevision(), revision);
    QCOMPARE(catalog.imageSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s), full);
    QVERIFY(network.urls.isEmpty());
}

void TestCardCatalog::optionalArtCropLocalDamageIsMemoizedUntilContentsChange() const
{
    QTemporaryDir storage;
    QVERIFY(!seedFullImage(storage.path()).isEmpty());
    const QByteArray repairedBytes = localCropBytes();
    const QString cropPath = seedLocalCrop(storage.path(), QByteArray(repairedBytes.size(), 'x'));
    QVERIFY(!cropPath.isEmpty());
    const QDateTime modified = QFileInfo(cropPath).lastModified();
    CropNetwork network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"en"_s);
    QSignalSpy crops(&catalog, &CardCatalog::cardArtCropAvailable);
    auto *pool = hexproof::client::BackgroundTaskPools::cardImageValidation();
    for (int i = 0; i < 20; ++i)
        QVERIFY(catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
    QVERIFY(pool->waitForDone(3'000));
    QCoreApplication::processEvents();
    QCOMPARE(crops.size(), 0);
    // Preserve both size and mtime to exercise the explicit import invalidation,
    // rather than accidentally passing via a new stat fingerprint.
    QFile repaired(cropPath);
    QVERIFY(repaired.open(QIODevice::WriteOnly));
    QCOMPARE(repaired.write(repairedBytes), repairedBytes.size());
    QVERIFY(repaired.flush());
    QVERIFY(repaired.setFileTime(modified, QFileDevice::FileModificationTime));
    repaired.close();
    QCOMPARE(QFileInfo(cropPath).lastModified(), modified);
    QVERIFY(catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
    QVERIFY(pool->waitForDone(3'000));
    QCoreApplication::processEvents();
    QVERIFY(catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
    QCOMPARE(crops.size(), 0);
    emit catalog.artCacheContentsChanged();
    QVERIFY(catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
    QTRY_COMPARE(crops.size(), 1);
    QVERIFY(!catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
    QVERIFY(network.urls.isEmpty());
    QVERIFY(!catalog.busy());
}

void TestCardCatalog::optionalArtCropLocalValidationAllowsMaintenanceAndDestruction() const
{
    for (bool remove : {false, true}) {
        QTemporaryDir storage;
        QVERIFY(!seedFullImage(storage.path()).isEmpty());
        const QString cropPath = seedLocalCrop(storage.path(), localCropBytes());
        QVERIFY(!cropPath.isEmpty());
        auto *pool = hexproof::client::BackgroundTaskPools::cardImageValidation();
        QSemaphore entered;
        QSemaphore release;
        const auto unblock = qScopeGuard([&]() {
            release.release(2);
            pool->waitForDone();
        });
        for (int i = 0; i < 2; ++i) {
            pool->start([&]() {
                entered.release();
                release.acquire();
            });
        }
        QVERIFY(entered.tryAcquire(2, 3'000));
        CropNetwork network;
        auto catalog = std::make_unique<CardCatalog>(storage.path(), &network);
        catalog->setLanguage(u"en"_s);
        QSignalSpy crops(catalog.get(), &CardCatalog::cardArtCropAvailable);
        QVERIFY(catalog->tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
        QVERIFY(!catalog->busy());
        if (remove) {
            catalog->artManager()->removeSelection(false);
            QTRY_VERIFY(!catalog->artManager()->busy());
            QVERIFY(catalog->artManager()->lastError().isEmpty());
            QVERIFY(!QFileInfo::exists(cropPath));
        } else {
            catalog.reset();
        }
        release.release(2);
        QVERIFY(pool->waitForDone(3'000));
        QCoreApplication::processEvents();
        QCOMPARE(crops.size(), 0);
        QVERIFY(network.urls.isEmpty());
        CardArtCache cache(storage.path());
        cache.load();
        const CardRecord record =
            cache.exactRecord(cache.key(u"Crop Card 1"_s, u"en"_s, u"TST"_s, u"1"_s));
        QCOMPARE(record.valid(), !remove);
    }
}

void TestCardCatalog::optionalArtCropRestoresMissingFileAndNotifies() const
{
    QTemporaryDir storage;
    QVERIFY(!seedFullImage(storage.path()).isEmpty());
    const QString cropPath = seedLocalCrop(storage.path(), localCropBytes());
    QVERIFY(!cropPath.isEmpty());
    QVERIFY(QFile::remove(cropPath));
    CropNetwork network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"en"_s);
    QSignalSpy crops(&catalog, &CardCatalog::cardArtCropAvailable);
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    QVERIFY(catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
    catalog.prepareTableArtCrops({cropCard()});
    QTRY_COMPARE(network.cropCount(), 1);
    QCOMPARE(crops.size(), 0);
    network.release(true);
    QTRY_VERIFY(!catalog.busy());
    QCOMPARE(crops.size(), 1);
    QCOMPARE(completed.size(), 0);
    QVERIFY(!catalog.tableArtCropSource(u"Crop Card 1"_s, u"TST"_s, u"1"_s).isEmpty());
    QVERIFY(!QImage(cropPath).isNull());
}
