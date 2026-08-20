// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/CardCatalog.h"
#include "services/CardCatalogCommon.h"

#include <QBuffer>
#include <QCryptographicHash>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QSignalSpy>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QTemporaryDir>
#include <QTest>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>

#include <algorithm>
#include <array>
#include <cstdio>
#include <cstring>

#include <zlib.h>

using namespace Qt::StringLiterals;
using hexproof::client::CardCatalog;
using hexproof::client::catalog_internal::kCardResolutionVersion;
using hexproof::client::catalog_internal::kNegativeCacheVersion;

namespace {

bool writeTestTarGzip(const QString &path, const QByteArray &entryName, const QByteArray &payload)
{
    QByteArray header(512, '\0');
    if (entryName.size() >= 100)
        return false;
    memcpy(header.data(), entryName.constData(), static_cast<size_t>(entryName.size()));
    std::snprintf(header.data() + 100, 8, "%07o", 0644);
    std::snprintf(header.data() + 108, 8, "%07o", 0);
    std::snprintf(header.data() + 116, 8, "%07o", 0);
    std::snprintf(header.data() + 124, 12, "%011llo",
                  static_cast<unsigned long long>(payload.size()));
    std::snprintf(header.data() + 136, 12, "%011o", 0);
    memset(header.data() + 148, ' ', 8);
    header[156] = '0';
    memcpy(header.data() + 257, "ustar", 5);
    memcpy(header.data() + 263, "00", 2);
    unsigned int checksum = 0;
    for (const char byte : header)
        checksum += static_cast<unsigned char>(byte);
    std::snprintf(header.data() + 148, 8, "%06o", checksum);
    header[154] = '\0';
    header[155] = ' ';

    gzFile output = gzopen(QFile::encodeName(path).constData(), "wb");
    if (!output)
        return false;
    const QByteArray padding((512 - payload.size() % 512) % 512, '\0');
    const QByteArray end(1024, '\0');
    const bool ok = gzwrite(output, header.constData(), header.size()) == header.size() &&
                    gzwrite(output, payload.constData(), payload.size()) == payload.size() &&
                    (padding.isEmpty() ||
                     gzwrite(output, padding.constData(), padding.size()) == padding.size()) &&
                    gzwrite(output, end.constData(), end.size()) == end.size();
    return gzclose(output) == Z_OK && ok;
}

bool writeTestGzip(const QString &path, const QByteArray &payload)
{
    gzFile output = gzopen(QFile::encodeName(path).constData(), "wb");
    if (!output)
        return false;
    const bool ok = gzwrite(output, payload.constData(),
                            static_cast<unsigned int>(payload.size())) == payload.size();
    return gzclose(output) == Z_OK && ok;
}

} // namespace

class StaticNetworkReply final : public QNetworkReply
{
  public:
    StaticNetworkReply(const QNetworkRequest &request, const QByteArray &payload,
                       const QByteArray &contentType, QObject *parent, int statusCode = 200,
                       QNetworkReply::NetworkError networkError = QNetworkReply::NoError)
        : QNetworkReply(parent),
          m_payload(payload)
    {
        setRequest(request);
        setUrl(request.url());
        setHeader(QNetworkRequest::ContentTypeHeader, QString::fromLatin1(contentType));
        setAttribute(QNetworkRequest::HttpStatusCodeAttribute, statusCode);
        if (networkError != QNetworkReply::NoError)
            setError(networkError, QStringLiteral("Simulated network failure"));
        open(QIODevice::ReadOnly | QIODevice::Unbuffered);
        QTimer::singleShot(0, this,
                           [this, closeBeforeFinished = networkError != QNetworkReply::NoError]() {
                               if (closeBeforeFinished)
                                   close();
                               setFinished(true);
                               emit readyRead();
                               emit finished();
                           });
    }

    void abort() override {}

    qint64 bytesAvailable() const override
    {
        if (!isOpen())
            return QNetworkReply::bytesAvailable();
        return m_payload.size() - m_offset + QNetworkReply::bytesAvailable();
    }

  protected:
    qint64 readData(char *data, qint64 maxSize) override
    {
        const qint64 remaining = m_payload.size() - m_offset;
        const qint64 size = qMin(maxSize, remaining);
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

class FakeNetworkAccessManager final : public QNetworkAccessManager
{
  public:
    QList<QUrl> requestedUrls;
    bool failFirstScryfallRequest = false;
    bool forbidScryfallRequests = false;
    bool failAllScryfallRequests = false;
    bool missFirstScryfallRequest = false;
    bool invalidImageResponse = false;
    bool serveScryfallCdnImages = false;
    int scryfallRequestCount = 0;
    int scryfallImageRequestCount = 0;
    int scryfallImageTimeoutsRemaining = 0;
    int scryfallImageRemoteClosesRemaining = 0;

  protected:
    QNetworkReply *createRequest(Operation operation, const QNetworkRequest &request,
                                 QIODevice *outgoingData) override
    {
        Q_UNUSED(operation)
        Q_UNUSED(outgoingData)
        requestedUrls.append(request.url());
        if (request.url().host() == u"api.scryfall.com"_s) {
            ++scryfallRequestCount;
            if (forbidScryfallRequests) {
                return new StaticNetworkReply(request, QByteArrayLiteral("{}"),
                                              QByteArrayLiteral("application/json"), this, 403,
                                              QNetworkReply::ContentAccessDenied);
            }
            if (failAllScryfallRequests) {
                return new StaticNetworkReply(request, QByteArrayLiteral("{}"),
                                              QByteArrayLiteral("application/json"), this, 503,
                                              QNetworkReply::UnknownServerError);
            }
            if (missFirstScryfallRequest && scryfallRequestCount == 1) {
                return new StaticNetworkReply(request, QByteArrayLiteral("{}"),
                                              QByteArrayLiteral("application/json"), this, 404,
                                              QNetworkReply::ContentNotFoundError);
            }
            if (failFirstScryfallRequest && scryfallRequestCount == 1) {
                return new StaticNetworkReply(request, QByteArrayLiteral("{}"),
                                              QByteArrayLiteral("application/json"), this, 503,
                                              QNetworkReply::UnknownServerError);
            }
            QJsonObject card{
                {u"name"_s, u"Wear // Tear"_s},
                {u"oracle_id"_s, u"wear-tear-oracle"_s},
                {u"type_line"_s, u"Instant // Instant"_s},
                {u"set"_s, u"MOC"_s},
                {u"collector_number"_s, u"343"_s},
                {u"image_uris"_s,
                 QJsonObject{{u"normal"_s, serveScryfallCdnImages
                                               ? u"https://cards.scryfall.io/normal/wear-tear.jpg"_s
                                               : u"https://images.test/wear-tear.png"_s}}},
            };
            if (request.url().path().endsWith(u"/zhs"_s) ||
                request.url().path() == u"/cards/search"_s) {
                card = QJsonObject{
                    {u"name"_s, u"Lightning Bolt"_s},
                    {u"oracle_id"_s, u"bolt-oracle"_s},
                    {u"printed_name"_s, u"闪电击"_s},
                    {u"printed_type_line"_s, u"瞬间"_s},
                    {u"type_line"_s, u"Instant"_s},
                    {u"lang"_s, u"zhs"_s},
                    {u"set"_s, u"M11"_s},
                    {u"collector_number"_s, u"146"_s},
                    {u"image_uris"_s,
                     QJsonObject{{u"normal"_s, serveScryfallCdnImages
                                                   ? u"https://cards.scryfall.io/normal/bolt.jpg"_s
                                                   : u"https://images.test/bolt.png"_s}}},
                };
            }
            const QJsonDocument response =
                request.url().path() == u"/cards/search"_s
                    ? QJsonDocument(QJsonObject{{u"data"_s, QJsonArray{card}}})
                    : QJsonDocument(card);
            return new StaticNetworkReply(request, response.toJson(QJsonDocument::Compact),
                                          QByteArrayLiteral("application/json"), this);
        }
        if (request.url().host() == u"mtgch.com"_s) {
            const QJsonObject card{
                {u"name"_s, u"Lightning Bolt"_s},
                {u"zhs_name"_s, u"闪电击"_s},
                {u"zhs_type_line"_s, u"瞬间"_s},
                {u"set"_s, u"M11"_s},
                {u"collector_number"_s, u"146"_s},
                {u"zhs_image_uris"_s,
                 QJsonObject{{u"normal"_s, u"https://images.test/bolt.png"_s}}},
                {u"image_uris"_s, QJsonObject{{u"normal"_s, u"https://images.test/bolt-en.png"_s}}},
            };
            return new StaticNetworkReply(request,
                                          QJsonDocument(card).toJson(QJsonDocument::Compact),
                                          QByteArrayLiteral("application/json"), this);
        }
        if (request.url().host() == u"cards.scryfall.io"_s) {
            ++scryfallImageRequestCount;
            if (scryfallImageRemoteClosesRemaining > 0) {
                --scryfallImageRemoteClosesRemaining;
                return new StaticNetworkReply(request, {}, QByteArrayLiteral("image/jpeg"), this, 0,
                                              QNetworkReply::RemoteHostClosedError);
            }
            if (scryfallImageTimeoutsRemaining > 0) {
                --scryfallImageTimeoutsRemaining;
                return new StaticNetworkReply(request, {}, QByteArrayLiteral("image/jpeg"), this, 0,
                                              QNetworkReply::TimeoutError);
            }
        }
        if (invalidImageResponse) {
            return new StaticNetworkReply(request, QByteArrayLiteral("<html>not an image</html>"),
                                          QByteArrayLiteral("text/html"), this);
        }

        QImage image(1, 1, QImage::Format_ARGB32);
        image.fill(Qt::transparent);
        QByteArray png;
        QBuffer buffer(&png);
        buffer.open(QIODevice::WriteOnly);
        image.save(&buffer, "PNG");
        return new StaticNetworkReply(request, png, QByteArrayLiteral("image/png"), this);
    }
};

class CatalogDownloadNetworkAccessManager final : public QNetworkAccessManager
{
  public:
    QByteArray officialManifest;
    QByteArray officialArchive;
    QList<QUrl> requestedUrls;

  protected:
    QNetworkReply *createRequest(Operation operation, const QNetworkRequest &request,
                                 QIODevice *outgoingData) override
    {
        Q_UNUSED(operation)
        Q_UNUSED(outgoingData)
        requestedUrls.append(request.url());
        const QUrl url = request.url();
        if (url.host() == u"github.com"_s &&
            url.path().endsWith(u"/card-database-manifest.json"_s)) {
            return new StaticNetworkReply(
                request, officialManifest, QByteArrayLiteral("application/json"), this,
                officialManifest.isEmpty() ? 404 : 200,
                officialManifest.isEmpty() ? QNetworkReply::ContentNotFoundError
                                           : QNetworkReply::NoError);
        }
        if (url.host() == u"github.com"_s &&
            url.path().endsWith(u"/hexproof-default-cards.sqlite.gz"_s) &&
            !officialArchive.isEmpty()) {
            return new StaticNetworkReply(request, officialArchive,
                                          QByteArrayLiteral("application/gzip"), this);
        }
        return new StaticNetworkReply(request, QByteArrayLiteral("{}"),
                                      QByteArrayLiteral("application/json"), this, 404,
                                      QNetworkReply::ContentNotFoundError);
    }
};

class TestCardCatalog : public QObject
{
    Q_OBJECT

  private slots:
    void prefersMtgchChineseFields() const;
    void rejectsUnverifiedChineseFallbacks() const;
    void rejectsScryfallPlaceholderImages() const;
    void filtersPlaceholderImagesFromBulkCatalog() const;
    void usesWholeCardImageForAdventureFace() const;
    void preservesScryfallFlavorName() const;
    void importsAndSearchesBulkData() const;
    void importsChineseNameIndex() const;
    void rejectsTruncatedBulkData() const;
    void recoversInterruptedDatabaseReplacement() const;
    void prefersScryfallBeforeMtgchFallback() const;
    void positiveCacheHitDoesNotBumpImageRevision() const;
    void providerFallbackSurvivesDisabledLocalReuse() const;
    void migratesUsablePreviousPolicyCache() const;
    void resolvedPrintingAliasBumpsImageRevision() const;
    void incrementalCacheCoalescesDuplicateRequests() const;
    void exactArtRequestDoesNotCoalesceWithNormalRequest() const;
    void exactArtFallsBackToSamePrintingEnglish() const;
    void exactArtUsesCatalogEnglishWhenChinesePrintingIsMissing() const;
    void reusesNameOnlyCacheForResolvedPrinting() const;
    void reusesLocalArtAcrossPrintings() const;
    void retriesTransientFailureForSplitCard() const;
    void reportsImageDecoderFailure() const;
    void clearsStaleErrorForNewCacheBatch() const;
    void doesNotRetryForbiddenRequests() const;
    void circuitBreaksUnavailableProvider() const;
    void retriesImageTimeoutThenSucceeds() const;
    void imageTimeoutDoesNotCircuitBreakLaterCards() const;
    void remoteCloseDoesNotCircuitBreakLaterCards() const;
    void manualRetryBypassesNegativeCache() const;
    void downloadsVerifiedOfficialDatabase() const;
    void reportsCatalogReleaseVersions() const;
    void doesNotBuildCatalogWhenOfficialPackageIsUnavailable() const;
    void doesNotCacheBusyCatalogFilterMisses() const;
    void hydratesLookupsWhenCatalogChangedFires() const;
    void clearsQueryErrorAfterSuccessfulPrintings() const;
    void keepsOperationErrorAfterSuccessfulPrintings() const;
    void incrementalCacheDoesNotClearPrintingsError() const;
    void successfulPrintingsKeepSearchError() const;
    void successfulCardSearchKeepsTokenSearchError() const;
    void successfulTokenSearchKeepsCardSearchError() const;
    void exposesIndependentCatalogErrorsWhenMultipleSubsystemsFail() const;
};

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
    QCOMPARE(network.requestedUrls.size(), 2);
    QCOMPARE(network.requestedUrls.at(0).host(), u"api.scryfall.com"_s);
    QCOMPARE(network.requestedUrls.at(1), QUrl(u"https://images.test/bolt.png"_s));
    const QList<QVariant> arguments = availableSpy.takeFirst();
    QCOMPARE(arguments.at(1).toString(), u"闪电击"_s);
    QCOMPARE(arguments.at(2).toString(), u"瞬间"_s);
    QVERIFY(QFileInfo::exists(arguments.at(3).toString()));

    // A match prefetch for an already-cached printing completes immediately
    // without another network request.
    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }});
    QCOMPARE(cacheSpy.count(), 2);
    QCOMPARE(network.requestedUrls.size(), 2);
    QVERIFY(catalog.imageSource(u"Lightning Bolt"_s, u"M11"_s, u"146"_s).startsWith(u"file:"_s));
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
    const QVariantList request{QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }};

    catalog.cacheCards(request);
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 2'000);
    QVERIFY(cacheSpy.first().at(3).toBool());
    QCOMPARE(availableSpy.count(), 1);
    const int revisionAfterDownload = catalog.imageRevision();
    QVERIFY(revisionAfterDownload > 0);
    const int revisionSignalsAfterDownload = revisionSpy.count();
    QVERIFY(revisionSignalsAfterDownload > 0);

    catalog.cacheCards(request);
    QCOMPARE(cacheSpy.count(), 2);
    QVERIFY(cacheSpy.at(1).at(3).toBool());
    QCOMPARE(cacheSpy.at(1).at(0).toString(), u"Lightning Bolt"_s);
    QCOMPARE(cacheSpy.at(1).at(1).toString(), u"M11"_s);
    QCOMPARE(cacheSpy.at(1).at(2).toString(), u"146"_s);
    QCOMPARE(availableSpy.count(), 2);
    QCOMPARE(catalog.imageRevision(), revisionAfterDownload);
    QCOMPARE(revisionSpy.count(), revisionSignalsAfterDownload);
    QCOMPARE(network.requestedUrls.size(), 2);
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

    QVERIFY(cacheFile.open(QIODevice::ReadOnly));
    const QJsonObject saved = QJsonDocument::fromJson(cacheFile.readAll()).object();
    QCOMPARE(saved.value(u"version"_s).toInt(), 6);
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

    catalog.cacheCards({QVariantMap{{u"name"_s, u"Lightning Bolt"_s}}});
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 1, 2'000);
    QVERIFY(cacheSpy.first().at(3).toBool());
    const int revisionAfterNameOnly = catalog.imageRevision();
    QVERIFY(revisionAfterNameOnly > 0);
    const int revisionSignalsAfterNameOnly = revisionSpy.count();
    const qsizetype initialRequests = network.requestedUrls.size();

    catalog.cacheCards({QVariantMap{
        {u"name"_s, u"Lightning Bolt"_s},
        {u"setCode"_s, u"M11"_s},
        {u"collectorNumber"_s, u"146"_s},
    }});
    QCOMPARE(cacheSpy.count(), 2);
    QVERIFY(cacheSpy.at(1).at(3).toBool());
    QCOMPARE(catalog.imageRevision(), revisionAfterNameOnly + 1);
    QCOMPARE(revisionSpy.count(), revisionSignalsAfterNameOnly + 1);
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

void TestCardCatalog::exactArtFallsBackToSamePrintingEnglish() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
    FakeNetworkAccessManager network;
    network.missFirstScryfallRequest = true;
    CardCatalog catalog(storage.path(), &network);
    catalog.setLanguage(u"zh"_s);
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
    QCOMPARE(network.requestedUrls.at(1).path(), u"/cards/cmm/1"_s);
    QVERIFY(std::none_of(
        network.requestedUrls.cbegin(), network.requestedUrls.cend(), [](const QUrl &url) {
            return url.path() == u"/cards/search"_s || url.host() == u"mtgch.com"_s;
        }));
    QVERIFY(
        catalog.printingImageSource(u"Wear // Tear"_s, u"CMM"_s, u"1"_s).startsWith(u"file:"_s));
}

void TestCardCatalog::reusesNameOnlyCacheForResolvedPrinting() const
{
    QTemporaryDir storage;
    QVERIFY(storage.isValid());
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
    QCOMPARE(cacheSpy.count(), 2);
    QVERIFY(cacheSpy.at(1).at(3).toBool());
    QCOMPARE(network.requestedUrls.size(), initialRequests);

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
    QCOMPARE(restartedSpy.count(), 1);
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
    QCOMPARE(cacheSpy.count(), 2);
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
    QCOMPARE(cacheSpy.count(), 2);
    QCOMPARE(network.scryfallRequestCount, 1);

    catalog.retryCards(cards);
    QTRY_COMPARE_WITH_TIMEOUT(cacheSpy.count(), 3, 2'000);
    QVERIFY(cacheSpy.at(2).at(3).toBool());
    QCOMPARE(network.scryfallRequestCount, 2);
    QVERIFY(catalog.lastError().isEmpty());
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
                {u"schemaVersion"_s, 9},
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
    QCOMPARE(catalog.installedCatalogSchemaVersion(), 9);
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
                          {u"schemaVersion"_s, 9},
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
    QCOMPARE(catalog.latestCatalogSchemaVersion(), 9);
    QVERIFY(catalog.catalogVersionError().isEmpty());
    QCOMPARE(network.requestedUrls.size(), 1);
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

QTEST_GUILESS_MAIN(TestCardCatalog)
#include "cardcatalog_test.moc"
