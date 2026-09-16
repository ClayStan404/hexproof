// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "cardcatalog_test.h"
#include "services/BackgroundTaskPools.h"

#include <QElapsedTimer>
#include <QPointer>
#include <QScopeGuard>
#include <QSemaphore>

#include <utility>

namespace {

constexpr int cardCount = 16;
const QString scryfallApi = u"api.scryfall.com"_s;
const QString mtgchApi = u"mtgch.com"_s;
const QString scryfallImages = u"cards.scryfall.io"_s;
const QString mtgchImages = u"images.mtgch.com"_s;

QJsonObject parallelCard(const QString &number, const QString &language = u"en"_s)
{
    const QString path = u"/"_s + number + u"-"_s + language + u".png"_s;
    return {{u"id"_s, u"card-"_s + number},
            {u"oracle_id"_s, u"oracle-"_s + number},
            {u"name"_s, u"Card "_s + number},
            {u"set"_s, u"tst"_s},
            {u"collector_number"_s, number},
            {u"lang"_s, language == u"zh"_s ? u"zhs"_s : u"en"_s},
            {u"layout"_s, u"normal"_s},
            {u"type_line"_s, u"Instant"_s},
            {u"oracle_text"_s, u"Draw a card."_s},
            {u"image_status"_s, u"highres_scan"_s},
            {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://"_s + scryfallImages + path}}},
            {u"zhs_name"_s, u"卡牌 "_s + number},
            {u"zhs_image_uris"_s, QJsonObject{{u"normal"_s, u"https://"_s + mtgchImages + u"/"_s +
                                                                number + u"-zh.png"_s}}}};
}

QVariantList parallelCards()
{
    QVariantList cards;
    for (int number = 1; number <= cardCount; ++number)
        cards.append(QVariantMap{{u"name"_s, u"Card %1"_s.arg(number)},
                                 {u"setCode"_s, u"TST"_s},
                                 {u"collectorNumber"_s, QString::number(number)},
                                 {u"exactArt"_s, true}});
    return cards;
}

bool writeParallelCatalog(const QString &root)
{
    QJsonArray cards;
    for (int number = 1; number <= cardCount; ++number)
        cards.append(parallelCard(QString::number(number)));
    const QString sourcePath = QDir(root).filePath(u"cards.json"_s);
    QFile source(sourcePath);
    if (!source.open(QIODevice::WriteOnly))
        return false;
    const QByteArray bytes = QJsonDocument(cards).toJson();
    if (source.write(bytes) != bytes.size())
        return false;
    source.close();
    return CardCatalog::importBulkFile(sourcePath, QDir(root).filePath(u"cards.sqlite"_s),
                                       u"default_cards"_s)
        .ok;
}

class ParallelNetwork final : public QNetworkAccessManager
{
  public:
    ParallelNetwork()
    {
        clock.start();
        QImage image(2, 2, QImage::Format_ARGB32);
        image.fill(Qt::green);
        QBuffer buffer(&png);
        buffer.open(QIODevice::WriteOnly);
        image.save(&buffer, "PNG");
    }

    QList<QUrl> urls;
    QHash<QString, QList<qint64>> metadataStarts;
    QHash<QString, int> metadataActive;
    QHash<QString, int> metadataPeak;
    QHash<QString, int> imagesActive;
    QList<QPointer<QNetworkReply>> heldImages;
    QList<QPointer<QNetworkReply>> heldMetadata;
    QString stalledMetadataHost;
    bool stallFirstMetadataOnly = false;
    bool holdImages = true;
    bool throttleMtgch = false;
    int imageTimeoutsRemaining = 0;
    int truncatedImagesRemaining = 0;
    int imagePeak = 0;

    void releaseImages()
    {
        holdImages = false;
        release(heldImages);
    }

    void releaseMetadata()
    {
        stalledMetadataHost.clear();
        release(heldMetadata);
    }

  protected:
    QNetworkReply *createRequest(Operation, const QNetworkRequest &request, QIODevice *) override
    {
        const QUrl url = request.url();
        urls.append(url);
        const QString host = url.host();
        if (host == scryfallApi || host == mtgchApi) {
            metadataStarts[host].append(clock.elapsed());
            metadataPeak[host] = qMax(metadataPeak.value(host), ++metadataActive[host]);
            auto parts = url.path().split(u'/', Qt::SkipEmptyParts);
            const bool chinese = parts.last() == u"zhs"_s;
            if (chinese)
                parts.removeLast();
            const QString number = parts.last();
            QJsonObject card = parallelCard(number, chinese ? u"zh"_s : u"en"_s);
            if (host == scryfallApi)
                card.remove(u"zhs_image_uris"_s);
            if (host == mtgchApi) {
                card.insert(u"image_uris"_s,
                            QJsonObject{{u"normal"_s, u"https://"_s + mtgchImages + u"/"_s +
                                                          number + u"-en.png"_s}});
            }
            auto *reply =
                new StaticNetworkReply(request, QJsonDocument(card).toJson(), "application/json",
                                       this, throttleMtgch && host == mtgchApi ? 429 : 200);
            connect(reply, &QNetworkReply::finished, this,
                    [this, host] { --metadataActive[host]; });
            if (host == stalledMetadataHost &&
                (!stallFirstMetadataOnly || metadataStarts.value(host).size() == 1)) {
                reply->blockSignals(true);
                heldMetadata.append(reply);
            }
            return reply;
        }
        ++imagesActive[host];
        imagePeak =
            qMax(imagePeak, imagesActive.value(scryfallImages) + imagesActive.value(mtgchImages));
        const bool timeout = host == scryfallImages && imageTimeoutsRemaining > 0;
        if (timeout)
            --imageTimeoutsRemaining;
        QByteArray bytes = timeout ? QByteArray{} : png;
        if (!timeout && truncatedImagesRemaining > 0) {
            --truncatedImagesRemaining;
            bytes = png.first(33); // PNG signature and IHDR, without image data.
        }
        auto *reply =
            new StaticNetworkReply(request, bytes, "image/png", this, timeout ? 0 : 200,
                                   timeout ? QNetworkReply::TimeoutError : QNetworkReply::NoError);
        connect(reply, &QNetworkReply::finished, this, [this, host] { --imagesActive[host]; });
        if (holdImages && !timeout) {
            reply->blockSignals(true);
            heldImages.append(reply);
        }
        return reply;
    }

  private:
    static void release(QList<QPointer<QNetworkReply>> &replies)
    {
        const auto pending = std::exchange(replies, {});
        for (const auto &reply : pending) {
            if (reply) {
                reply->blockSignals(false);
                emit reply->finished();
            }
        }
    }

    QElapsedTimer clock;
    QByteArray png;
};

} // namespace

void TestCardCatalog::parallelProvidersShareDownloads_data() const
{
    QTest::addColumn<QString>("language");
    QTest::addColumn<bool>("localCatalog");
    QTest::newRow("english-cold") << u"en"_s << false;
    QTest::newRow("chinese-cold") << u"zh"_s << false;
    QTest::newRow("english-catalog") << u"en"_s << true;
    QTest::newRow("chinese-catalog") << u"zh"_s << true;
}

void TestCardCatalog::parallelProvidersShareDownloads() const
{
    QFETCH(QString, language);
    QFETCH(bool, localCatalog);
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    if (localCatalog)
        QVERIFY(writeParallelCatalog(storage.path()));
    ParallelNetwork network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(language);
    catalog.setCardArtProvider(u"parallel"_s);
    QCOMPARE(catalog.cardArtProvider(), u"parallel"_s);
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    const QVariantList cards = parallelCards();
    catalog.cacheCards(cards);
    catalog.cacheCards(cards);
    QTRY_COMPARE(network.imagesActive.value(scryfallImages), 3);
    QTRY_COMPARE(network.imagesActive.value(mtgchImages), 3);
    QVERIFY(catalog.busy());
    QVERIFY(completed.isEmpty());
    network.releaseImages();
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), cardCount, 6'000);
    QTRY_VERIFY(!catalog.busy());
    QVERIFY(network.imagePeak <= 6);
    for (const auto &result : completed)
        QVERIFY(result.last().toBool());
    QSet<QString> imageNumbers;
    for (const QUrl &url : network.urls) {
        if (url.host() == scryfallImages || url.host() == mtgchImages) {
            QVERIFY(url.path().endsWith(u"-"_s + language + u".png"_s));
            const QString number = url.path().section(u'-', 0, 0);
            QVERIFY(!imageNumbers.contains(number));
            imageNumbers.insert(number);
        }
    }
    QCOMPARE(imageNumbers.size(), cardCount);
    for (const QString &host : {scryfallApi, mtgchApi}) {
        QVERIFY(network.metadataPeak.value(host) <= 3);
        const auto starts = network.metadataStarts.value(host);
        for (qsizetype i = 1; i < starts.size(); ++i)
            QVERIFY(starts.at(i) - starts.at(i - 1) >= 100);
    }
    const auto requests = network.urls.size();
    catalog.cacheCards(cards);
    QTRY_COMPARE(completed.count(), cardCount * 2);
    QCOMPARE(network.urls.size(), requests);
}

void TestCardCatalog::parallelProviderStallDoesNotBlockOtherSource() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    ParallelNetwork network;
    network.stalledMetadataHost = mtgchApi;
    network.holdImages = false;
    CardCatalog catalog(storage.path(), &network);
    catalog.setCardArtProvider(u"parallel"_s);
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    catalog.cacheCards(parallelCards());
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), cardCount - 3, 6'000);
    QCOMPARE(network.metadataStarts.value(mtgchApi).size(), 3);
    QVERIFY(catalog.busy());
    network.releaseMetadata();
    QTRY_COMPARE(completed.count(), cardCount);
    QTRY_VERIFY(!catalog.busy());
}

void TestCardCatalog::slowMetadataDoesNotBlockSameProvider() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    ParallelNetwork network;
    network.stalledMetadataHost = mtgchApi;
    network.stallFirstMetadataOnly = true;
    network.holdImages = false;
    CardCatalog catalog(storage.path(), &network);
    catalog.setCardArtProvider(u"parallel"_s);
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    catalog.cacheCards(parallelCards());
    // One unresponsive lookup must not occupy the entire API host. Other
    // cards can use its remaining slots without waiting for a timeout.
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), cardCount - 1, 6'000);
    QVERIFY(network.metadataStarts.value(mtgchApi).size() > 1);
    QVERIFY(network.metadataPeak.value(mtgchApi) <= 3);
    QVERIFY(catalog.busy());
    network.releaseMetadata();
    QTRY_COMPARE(completed.count(), cardCount);
    QTRY_VERIFY(!catalog.busy());
}

void TestCardCatalog::parallelMetadataFallbackKeepsHostLimit() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    ParallelNetwork network;
    network.throttleMtgch = true;
    network.stalledMetadataHost = scryfallApi;
    network.holdImages = false;
    CardCatalog catalog(storage.path(), &network);
    catalog.setCardArtProvider(u"parallel"_s);
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    catalog.cacheCards(parallelCards());
    QTRY_COMPARE(network.metadataStarts.value(scryfallApi).size(), 3);
    QTest::qWait(400);
    QCOMPARE(network.metadataStarts.value(scryfallApi).size(), 3);
    QCOMPARE(network.metadataPeak.value(scryfallApi), 3);
    network.releaseMetadata();
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), cardCount, 6'000);
    QTRY_VERIFY(!catalog.busy());
    QCOMPARE(network.metadataStarts.value(mtgchApi).size(), 1);
    QVERIFY(network.metadataPeak.value(scryfallApi) <= 3);
    const auto starts = network.metadataStarts.value(scryfallApi);
    for (qsizetype i = 1; i < starts.size(); ++i)
        QVERIFY(starts.at(i) - starts.at(i - 1) >= 100);
}

void TestCardCatalog::retriesTruncatedImagePayload_data() const
{
    QTest::addColumn<bool>("localCatalog");
    QTest::newRow("resolver") << false;
    QTest::newRow("direct") << true;
}

void TestCardCatalog::retriesTruncatedImagePayload() const
{
    QFETCH(bool, localCatalog);
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    if (localCatalog)
        QVERIFY(writeParallelCatalog(storage.path()));
    ParallelNetwork network;
    network.holdImages = false;
    network.truncatedImagesRemaining = 1;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    catalog.cacheCards({parallelCards().first()});
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), 1, 6'000);
    QVERIFY(completed.first().last().toBool());
    const QString path = QUrl(catalog.imageSource(u"Card 1"_s, u"TST"_s, u"1"_s)).toLocalFile();
    QVERIFY2(!QImage(path).isNull(), "A readable header must not make a truncated download ready");
    QCOMPARE(std::count_if(network.urls.cbegin(), network.urls.cend(),
                           [](const QUrl &url) { return url.host() == scryfallImages; }),
             2);
}

void TestCardCatalog::imageValidationRetainsSlotsAndCancelsOnDestruction() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY(writeParallelCatalog(storage.path()));
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
    ParallelNetwork network;
    network.holdImages = false;
    auto catalog = std::make_unique<CardCatalog>(storage.path(), &network);
    catalog->setCardArtProvider(u"parallel"_s);
    QSignalSpy completed(catalog.get(), &CardCatalog::cardCacheFinished);
    catalog->cacheCards(parallelCards());
    const auto imageRequests = [&]() {
        return std::count_if(network.urls.cbegin(), network.urls.cend(), [](const QUrl &url) {
            return url.host() == scryfallImages || url.host() == mtgchImages;
        });
    };
    QTRY_COMPARE(imageRequests(), 6);
    QTest::qWait(250);
    QCOMPARE(imageRequests(), 6);
    QVERIFY(catalog->busy());
    QVERIFY(completed.isEmpty());
    catalog.reset();
    release.release(2);
    pool->waitForDone();
    QTest::qWait(50);
    QVERIFY(QDir(storage.filePath(u"images"_s)).entryList(QDir::Files).isEmpty());
}

void TestCardCatalog::parallelProvidersShareCooldowns() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    ParallelNetwork network;
    network.throttleMtgch = true;
    network.holdImages = false;
    CardCatalog catalog(storage.path(), &network);
    catalog.setCardArtProvider(u"parallel"_s);
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    catalog.cacheCards(parallelCards());
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), cardCount, 6'000);
    QTRY_VERIFY(!catalog.busy());
    QCOMPARE(network.metadataStarts.value(mtgchApi).size(), 1);
    QVERIFY(network.imagePeak <= 6);
    QCOMPARE(network.metadataPeak.value(scryfallApi), 1);
    for (const auto &result : completed)
        QVERIFY(result.last().toBool());
}

void TestCardCatalog::parallelDownloadsReserveRetrySlots() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    QVERIFY(writeParallelCatalog(storage.path()));
    ParallelNetwork network;
    network.imageTimeoutsRemaining = 3;
    CardCatalog catalog(storage.path(), &network);
    catalog.setCardArtProvider(u"parallel"_s);
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    catalog.cacheCards(parallelCards());
    QTRY_COMPARE(network.imageTimeoutsRemaining, 0);
    QVERIFY(completed.isEmpty());
    QVERIFY(catalog.busy());
    QTRY_COMPARE(network.imagesActive.value(mtgchImages), 3);
    QTRY_COMPARE(network.imagesActive.value(scryfallImages), 3);
    QCOMPARE(network.imagePeak, 6);
    network.releaseImages();
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), cardCount, 6'000);
    QTRY_VERIFY(!catalog.busy());
    QVERIFY(network.imagePeak <= 6);
}

void TestCardCatalog::parallelProviderChangeFinishesQueuedWork() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    ParallelNetwork network;
    CardCatalog catalog(storage.path(), &network);
    catalog.setCardArtProvider(u"parallel"_s);
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    catalog.cacheCards(parallelCards());
    QTRY_COMPARE(network.heldImages.size(), 6);
    catalog.setCardArtProvider(u"scryfall"_s);
    network.releaseImages();
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), cardCount, 6'000);
    QTRY_VERIFY(!catalog.busy());
    QVERIFY(network.imagePeak <= 6);
    QCOMPARE(network.metadataStarts.value(mtgchApi).size(), 3);
}

void TestCardCatalog::enablingParallelUsesExistingBacklog() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    ParallelNetwork network;
    CardCatalog catalog(storage.path(), &network);
    QSignalSpy completed(&catalog, &CardCatalog::cardCacheFinished);
    catalog.cacheCards(parallelCards());
    QTRY_COMPARE(network.heldImages.size(), 1);
    catalog.setCardArtProvider(u"parallel"_s);
    QTRY_COMPARE(network.heldImages.size(), 6);
    QVERIFY(network.imagesActive.value(mtgchImages) > 0);
    QVERIFY(network.imagesActive.value(scryfallImages) > 0);
    network.releaseImages();
    QTRY_COMPARE_WITH_TIMEOUT(completed.count(), cardCount, 6'000);
    QTRY_VERIFY(!catalog.busy());
    QVERIFY(network.imagePeak <= 6);
}

void TestCardCatalog::destroyingParallelCatalogCancelsQueuedRequests() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    ParallelNetwork network;
    network.stalledMetadataHost = mtgchApi;
    auto catalog = std::make_unique<CardCatalog>(storage.path(), &network);
    catalog->setCardArtProvider(u"parallel"_s);
    catalog->cacheCards(parallelCards());
    QTRY_COMPARE(network.heldMetadata.size(), 1);
    QTRY_COMPARE(network.imagesActive.value(scryfallImages), 3);
    const auto requests = network.urls.size();
    catalog.reset();
    network.releaseImages();
    network.releaseMetadata();
    QTest::qWait(250);
    QCOMPARE(network.urls.size(), requests);
}
