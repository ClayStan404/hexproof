// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

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
#include <QSettings>
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

[[maybe_unused]] inline bool writeTestTarGzip(const QString &path, const QByteArray &entryName,
                                              const QByteArray &payload)
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

[[maybe_unused]] inline bool writeTestGzip(const QString &path, const QByteArray &payload)
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
    bool missMtgchRequests = false;
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
            if (missMtgchRequests) {
                return new StaticNetworkReply(request, QByteArrayLiteral("{}"),
                                              QByteArrayLiteral("application/json"), this, 404,
                                              QNetworkReply::ContentNotFoundError);
            }
            const QStringList pathParts = request.url().path().split(u'/', Qt::SkipEmptyParts);
            const QString setCode =
                pathParts.size() >= 2 ? pathParts.at(pathParts.size() - 2) : u"M11"_s;
            const QString collectorNumber = pathParts.isEmpty() ? u"146"_s : pathParts.constLast();
            const QJsonObject card{
                {u"name"_s, u"Lightning Bolt"_s},
                {u"zhs_name"_s, u"闪电击"_s},
                {u"zhs_type_line"_s, u"瞬间"_s},
                {u"set"_s, setCode},
                {u"collector_number"_s, collectorNumber},
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
    void prefersMtgchBeforeScryfallFallback() const;
    void prefersMtgchForEnglishArt() const;
    void positiveCacheHitDoesNotBumpImageRevision() const;
    void providerFallbackSurvivesDisabledLocalReuse() const;
    void migratesUsablePreviousPolicyCache() const;
    void resolvedPrintingAliasBumpsImageRevision() const;
    void incrementalCacheCoalescesDuplicateRequests() const;
    void exactArtRequestDoesNotCoalesceWithNormalRequest() const;
    void exactArtUsesSamePrintingProviderFallback() const;
    void exactArtUsesCatalogEnglishWhenChinesePrintingIsMissing() const;
    void mtgchPreferenceBypassesCatalogScryfallFastPath() const;
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
    void catalogAutomaticCheckRunsAtMostOncePerDay() const;
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
