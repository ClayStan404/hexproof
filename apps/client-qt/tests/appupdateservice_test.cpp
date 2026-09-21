// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/AppUpdateService.h"

#include <QCryptographicHash>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QSettings>
#include <QTemporaryDir>
#include <QTest>
#include <QTimer>
#include <QVersionNumber>

#include <cstring>

using namespace Qt::StringLiterals;
using hexproof::client::AppUpdateService;

namespace {

QString nextReleaseVersion(const AppUpdateService &service)
{
    const QVersionNumber current = QVersionNumber::fromString(service.currentVersion());
    return QVersionNumber(current.majorVersion(), current.minorVersion(),
                          current.microVersion() + 1)
        .toString();
}

QString expectedAssetName(const QString &version)
{
#if defined(Q_OS_WIN)
    return u"Hexproof-%1-windows-x64.zip"_s.arg(version);
#elif defined(Q_OS_MACOS) && defined(Q_PROCESSOR_ARM_64)
    return u"Hexproof-%1-macos-arm64.zip"_s.arg(version);
#elif defined(Q_OS_MACOS)
    return u"Hexproof-%1-macos-x86_64.zip"_s.arg(version);
#else
    return u"Hexproof-%1-linux-x86_64.tar.gz"_s.arg(version);
#endif
}

class StaticReply final : public QNetworkReply
{
  public:
    StaticReply(const QNetworkRequest &request, QByteArray payload, QByteArray contentType,
                int status, QNetworkReply::NetworkError error, QObject *parent,
                qint64 contentLength = -1)
        : QNetworkReply(parent),
          m_payload(std::move(payload))
    {
        setRequest(request);
        setUrl(request.url());
        setHeader(QNetworkRequest::ContentTypeHeader, QString::fromLatin1(contentType));
        setHeader(QNetworkRequest::ContentLengthHeader,
                  contentLength >= 0 ? contentLength : m_payload.size());
        setAttribute(QNetworkRequest::HttpStatusCodeAttribute, status);
        if (error != QNetworkReply::NoError)
            setError(error, u"Simulated network failure"_s);
        open(QIODevice::ReadOnly | QIODevice::Unbuffered);
        QTimer::singleShot(0, this, [this]() {
            emit downloadProgress(m_payload.size(), m_payload.size());
            emit readyRead();
            setFinished(true);
            emit finished();
        });
    }

    void abort() override
    {
        setError(QNetworkReply::OperationCanceledError, u"Cancelled"_s);
        close();
    }

    qint64 bytesAvailable() const override
    {
        return m_payload.size() - m_offset + QNetworkReply::bytesAvailable();
    }

  protected:
    qint64 readData(char *data, qint64 maximumSize) override
    {
        const qint64 remaining = m_payload.size() - m_offset;
        const qint64 count = qMin(maximumSize, remaining);
        if (count <= 0)
            return -1;
        std::memcpy(data, m_payload.constData() + m_offset, static_cast<size_t>(count));
        m_offset += count;
        return count;
    }

  private:
    QByteArray m_payload;
    qint64 m_offset = 0;
};

class UpdateNetworkAccessManager final : public QNetworkAccessManager
{
  public:
    QString version;
    QString releaseBody = u"Release notes"_s;
    QByteArray package = QByteArrayLiteral("portable application package");
    bool wrongChecksum = false;
    bool failApi = false;
    bool failFallbackChecksums = false;
    bool failHead = false;
    int apiStatus = 403;
    QList<QUrl> requestedUrls;

  protected:
    QNetworkReply *createRequest(Operation operation, const QNetworkRequest &request,
                                 QIODevice *outgoingData) override
    {
        Q_UNUSED(outgoingData)
        requestedUrls.append(request.url());
        const QString assetName = expectedAssetName(version);
        const QString tag = u"v%1"_s.arg(version);
        if (request.url().host() == u"api.github.com"_s) {
            if (failApi) {
                return new StaticReply(
                    request, QByteArrayLiteral("{\"message\":\"API rate limit exceeded\"}"),
                    QByteArrayLiteral("application/json"), apiStatus,
                    QNetworkReply::ContentAccessDenied, this);
            }
            const QJsonArray assets{
                QJsonObject{
                    {u"name"_s, assetName},
                    {u"size"_s, package.size()},
                    {u"browser_download_url"_s,
                     u"https://github.com/ClayStan404/hexproof/releases/download/%1/%2"_s.arg(
                         tag, assetName)}},
                QJsonObject{{u"name"_s, u"SHA256SUMS"_s},
                            {u"size"_s, 256},
                            {u"browser_download_url"_s,
                             u"https://github.com/ClayStan404/hexproof/releases/download/%1/"
                             "SHA256SUMS"_s.arg(tag)}},
            };
            const QByteArray payload =
                QJsonDocument(
                    QJsonObject{
                        {u"tag_name"_s, tag},
                        {u"name"_s, u"Hexproof %1"_s.arg(version)},
                        {u"body"_s, releaseBody},
                        {u"published_at"_s, u"2026-08-26T08:00:00Z"_s},
                        {u"html_url"_s,
                         u"https://github.com/ClayStan404/hexproof/releases/tag/%1"_s.arg(tag)},
                        {u"draft"_s, false},
                        {u"prerelease"_s, false},
                        {u"assets"_s, assets}})
                    .toJson(QJsonDocument::Compact);
            return new StaticReply(request, payload, QByteArrayLiteral("application/json"), 200,
                                   QNetworkReply::NoError, this);
        }
        if (operation == HeadOperation) {
            if (failHead || !request.url().path().endsWith(QLatin1Char('/') + assetName)) {
                return new StaticReply(request, {}, QByteArrayLiteral("text/plain"), 404,
                                       QNetworkReply::ContentNotFoundError, this);
            }
            return new StaticReply(request, {}, QByteArrayLiteral("application/octet-stream"), 200,
                                   QNetworkReply::NoError, this, package.size());
        }
        if (request.url().path().endsWith(u"/SHA256SUMS"_s)) {
            if (failFallbackChecksums &&
                request.url().path().contains(u"/releases/latest/download/"_s)) {
                return new StaticReply(request, {}, QByteArrayLiteral("text/plain"), 404,
                                       QNetworkReply::ContentNotFoundError, this);
            }
            const QByteArray checksum =
                wrongChecksum
                    ? QByteArray(64, '0')
                    : QCryptographicHash::hash(package, QCryptographicHash::Sha256).toHex();
            return new StaticReply(
                request, checksum + QByteArrayLiteral("  ") + assetName.toUtf8() + '\n',
                QByteArrayLiteral("text/plain"), 200, QNetworkReply::NoError, this);
        }
        if (request.url().path().endsWith(QLatin1Char('/') + assetName)) {
            return new StaticReply(request, package, QByteArrayLiteral("application/octet-stream"),
                                   200, QNetworkReply::NoError, this);
        }
        return new StaticReply(request, QByteArrayLiteral("{}"),
                               QByteArrayLiteral("application/json"), 404,
                               QNetworkReply::ContentNotFoundError, this);
    }
};

} // namespace

class TestAppUpdateService final : public QObject
{
    Q_OBJECT

  private slots:
    void initTestCase();
    void cleanup();
    void checksLatestReleaseAndSelectsPlatformPackage() const;
    void doesNotOfferCurrentOrOlderLatestRelease_data() const;
    void doesNotOfferCurrentOrOlderLatestRelease() const;
    void downloadsAndVerifiesPackage() const;
    void rejectsPackageWithWrongChecksum() const;
    void requestsExactServerVersion() const;
    void automaticCheckRunsAtMostOncePerDay() const;
    void fallsBackToGithubDownloadWhenApiFails() const;
    void fallsBackToTaggedDownloadWhenExactApiFails() const;
    void keepsCachedReleaseAndReportsFailureWhenLiveCheckFails() const;
    void reportsRateLimitWhenApiAndFallbackFail() const;
    void discoversReleaseWhenPackageHeadIsUnavailable() const;
    void stripsEmbeddedReleaseNoteComments() const;

  private:
    QTemporaryDir m_settings;
};

void TestAppUpdateService::initTestCase()
{
    QVERIFY(m_settings.isValid());
    QCoreApplication::setOrganizationName(u"HexproofUpdateTest"_s);
    QCoreApplication::setApplicationName(u"HexproofUpdateTest"_s);
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_settings.path());
}

void TestAppUpdateService::cleanup()
{
    QSettings settings;
    settings.clear();
    settings.sync();
}

void TestAppUpdateService::checksLatestReleaseAndSelectsPlatformPackage() const
{
    QTemporaryDir downloads;
    QVERIFY(downloads.isValid());
    UpdateNetworkAccessManager network;
    AppUpdateService service(downloads.path(), &network);
    network.version = nextReleaseVersion(service);

    service.checkForUpdates();

    QTRY_VERIFY_WITH_TIMEOUT(!service.checking(), 2'000);
    QVERIFY2(service.lastError().isEmpty(), qPrintable(service.lastError()));
    QVERIFY(service.releaseAvailable());
    QVERIFY(service.updateAvailable());
    QVERIFY(!service.exactVersion());
    QCOMPARE(service.targetVersion(), network.version);
    QCOMPARE(network.requestedUrls.size(), 2);
    QCOMPARE(network.requestedUrls.constFirst().path(),
             u"/repos/ClayStan404/hexproof/releases/latest"_s);
}

void TestAppUpdateService::doesNotOfferCurrentOrOlderLatestRelease_data() const
{
    QTest::addColumn<bool>("currentVersion");
    QTest::newRow("current") << true;
    QTest::newRow("older") << false;
}

void TestAppUpdateService::doesNotOfferCurrentOrOlderLatestRelease() const
{
    QFETCH(bool, currentVersion);
    QTemporaryDir downloads;
    QVERIFY(downloads.isValid());
    UpdateNetworkAccessManager network;
    AppUpdateService service(downloads.path(), &network);
    network.version = currentVersion ? service.currentVersion() : u"0.0.0"_s;

    service.checkForUpdates();

    QTRY_VERIFY_WITH_TIMEOUT(!service.checking(), 2'000);
    QVERIFY2(service.lastError().isEmpty(), qPrintable(service.lastError()));
    QVERIFY(service.releaseAvailable());
    QVERIFY(!service.updateAvailable());
    QCOMPARE(service.targetVersion(), network.version);
    QCOMPARE(network.requestedUrls.size(), 2);

    service.downloadUpdate();

    QVERIFY(!service.downloading());
    QVERIFY(!service.downloadReady());
    QCOMPARE(network.requestedUrls.size(), 2);
}

void TestAppUpdateService::downloadsAndVerifiesPackage() const
{
    QTemporaryDir downloads;
    QVERIFY(downloads.isValid());
    UpdateNetworkAccessManager network;
    AppUpdateService service(downloads.path(), &network);
    network.version = nextReleaseVersion(service);
    service.checkForUpdates();
    QTRY_VERIFY_WITH_TIMEOUT(!service.checking(), 2'000);

    service.downloadUpdate();

    QTRY_VERIFY_WITH_TIMEOUT(!service.downloading(), 2'000);
    QVERIFY2(service.lastError().isEmpty(), qPrintable(service.lastError()));
    QVERIFY(service.downloadReady());
    QCOMPARE(service.progress(), 1.0);
    QFile package(service.downloadPath());
    QVERIFY(package.open(QIODevice::ReadOnly));
    QCOMPARE(package.readAll(), network.package);
}

void TestAppUpdateService::rejectsPackageWithWrongChecksum() const
{
    QTemporaryDir downloads;
    QVERIFY(downloads.isValid());
    UpdateNetworkAccessManager network;
    network.wrongChecksum = true;
    AppUpdateService service(downloads.path(), &network);
    network.version = nextReleaseVersion(service);
    service.checkForUpdates();
    QTRY_VERIFY_WITH_TIMEOUT(!service.checking(), 2'000);

    service.downloadUpdate();

    QTRY_VERIFY_WITH_TIMEOUT(!service.downloading(), 2'000);
    QVERIFY(!service.downloadReady());
    QVERIFY(service.lastError().contains(u"checksum"_s, Qt::CaseInsensitive));
    QVERIFY(!QFileInfo::exists(downloads.filePath(expectedAssetName(network.version))));
}

void TestAppUpdateService::requestsExactServerVersion() const
{
    QTemporaryDir downloads;
    QVERIFY(downloads.isValid());
    UpdateNetworkAccessManager network;
    network.version = u"1.2.3"_s;
    AppUpdateService service(downloads.path(), &network);

    service.checkForVersion(network.version);

    QTRY_VERIFY_WITH_TIMEOUT(!service.checking(), 2'000);
    QVERIFY2(service.lastError().isEmpty(), qPrintable(service.lastError()));
    QVERIFY(service.exactVersion());
    QCOMPARE(service.targetVersion(), network.version);
    QCOMPARE(network.requestedUrls.constFirst().path(),
             u"/repos/ClayStan404/hexproof/releases/tags/v1.2.3"_s);
}

void TestAppUpdateService::automaticCheckRunsAtMostOncePerDay() const
{
    QTemporaryDir downloads;
    QVERIFY(downloads.isValid());
    UpdateNetworkAccessManager firstNetwork;
    {
        AppUpdateService first(downloads.path(), &firstNetwork);
        firstNetwork.version = nextReleaseVersion(first);
        first.checkAutomatically();
        QTRY_VERIFY_WITH_TIMEOUT(!first.checking(), 2'000);
        QCOMPARE(firstNetwork.requestedUrls.size(), 2);
    }

    UpdateNetworkAccessManager secondNetwork;
    AppUpdateService second(downloads.path(), &secondNetwork);
    second.checkAutomatically();
    QTest::qWait(50);
    QVERIFY(!second.checking());
    QCOMPARE(secondNetwork.requestedUrls.size(), 0);
    QCOMPARE(second.targetVersion(), firstNetwork.version);
}

void TestAppUpdateService::fallsBackToGithubDownloadWhenApiFails() const
{
    QTemporaryDir downloads;
    QVERIFY(downloads.isValid());
    UpdateNetworkAccessManager network;
    network.failApi = true;
    AppUpdateService service(downloads.path(), &network);
    network.version = nextReleaseVersion(service);

    service.checkForUpdates();

    QTRY_VERIFY_WITH_TIMEOUT(!service.checking(), 2'000);
    QVERIFY2(service.lastError().isEmpty(), qPrintable(service.lastError()));
    QVERIFY(service.releaseAvailable());
    QVERIFY(service.updateAvailable());
    QVERIFY(!service.cachedRelease());
    QCOMPARE(service.targetVersion(), network.version);
    QCOMPARE(network.requestedUrls.constFirst().path(),
             u"/repos/ClayStan404/hexproof/releases/latest"_s);
    QVERIFY(network.requestedUrls.contains(
        QUrl(u"https://github.com/ClayStan404/hexproof/releases/latest/download/SHA256SUMS"_s)));
}

void TestAppUpdateService::fallsBackToTaggedDownloadWhenExactApiFails() const
{
    QTemporaryDir downloads;
    QVERIFY(downloads.isValid());
    UpdateNetworkAccessManager network;
    network.failApi = true;
    network.version = u"1.2.3"_s;
    AppUpdateService service(downloads.path(), &network);

    service.checkForVersion(network.version);

    QTRY_VERIFY_WITH_TIMEOUT(!service.checking(), 2'000);
    QVERIFY2(service.lastError().isEmpty(), qPrintable(service.lastError()));
    QVERIFY(service.exactVersion());
    QCOMPARE(service.targetVersion(), network.version);
    QCOMPARE(network.requestedUrls.constFirst().path(),
             u"/repos/ClayStan404/hexproof/releases/tags/v1.2.3"_s);
    QVERIFY(network.requestedUrls.contains(
        QUrl(u"https://github.com/ClayStan404/hexproof/releases/download/v1.2.3/SHA256SUMS"_s)));
}

void TestAppUpdateService::keepsCachedReleaseAndReportsFailureWhenLiveCheckFails() const
{
    QTemporaryDir downloads;
    QVERIFY(downloads.isValid());
    UpdateNetworkAccessManager firstNetwork;
    firstNetwork.version = u"0.0.1"_s;
    {
        AppUpdateService first(downloads.path(), &firstNetwork);
        first.checkForUpdates();
        QTRY_VERIFY_WITH_TIMEOUT(!first.checking(), 2'000);
        QVERIFY(first.releaseAvailable());
    }

    UpdateNetworkAccessManager secondNetwork;
    secondNetwork.failApi = true;
    secondNetwork.failFallbackChecksums = true;
    secondNetwork.version = u"9.9.9"_s;
    AppUpdateService second(downloads.path(), &secondNetwork);
    QVERIFY(second.releaseAvailable());
    QVERIFY(second.cachedRelease());
    QCOMPARE(second.targetVersion(), firstNetwork.version);

    second.checkForUpdates();

    QTRY_VERIFY_WITH_TIMEOUT(!second.checking(), 2'000);
    QVERIFY(!second.lastError().isEmpty());
    QVERIFY(second.releaseAvailable());
    QVERIFY(second.cachedRelease());
    QVERIFY(!second.updateAvailable());
    QCOMPARE(second.targetVersion(), firstNetwork.version);
}

void TestAppUpdateService::reportsRateLimitWhenApiAndFallbackFail() const
{
    QTemporaryDir downloads;
    QVERIFY(downloads.isValid());
    UpdateNetworkAccessManager network;
    network.failApi = true;
    network.failFallbackChecksums = true;
    AppUpdateService service(downloads.path(), &network);
    network.version = nextReleaseVersion(service);

    service.checkForUpdates();

    QTRY_VERIFY_WITH_TIMEOUT(!service.checking(), 2'000);
    QVERIFY(service.lastError().contains(u"rate-limited"_s, Qt::CaseInsensitive));
    QVERIFY(!service.releaseAvailable());
}

void TestAppUpdateService::discoversReleaseWhenPackageHeadIsUnavailable() const
{
    QTemporaryDir downloads;
    QVERIFY(downloads.isValid());
    UpdateNetworkAccessManager network;
    network.failApi = true;
    network.failHead = true;
    AppUpdateService service(downloads.path(), &network);
    network.version = nextReleaseVersion(service);

    service.checkForUpdates();

    QTRY_VERIFY_WITH_TIMEOUT(!service.checking(), 2'000);
    QVERIFY2(service.lastError().isEmpty(), qPrintable(service.lastError()));
    QVERIFY(service.releaseAvailable());
    QCOMPARE(service.targetVersion(), network.version);

    service.downloadUpdate();

    QTRY_VERIFY_WITH_TIMEOUT(!service.downloading(), 2'000);
    QVERIFY2(service.lastError().isEmpty(), qPrintable(service.lastError()));
    QVERIFY(service.downloadReady());
}

void TestAppUpdateService::stripsEmbeddedReleaseNoteComments() const
{
    QTemporaryDir downloads;
    QVERIFY(downloads.isValid());
    UpdateNetworkAccessManager network;
    AppUpdateService service(downloads.path(), &network);
    network.version = nextReleaseVersion(service);
    network.releaseBody = u"<!-- hexproof-macos-install-notes:start -->\n"
                          "## macOS install notes\n\n"
                          "hidden install notes\n"
                          "<!-- hexproof-macos-install-notes:end -->\n\n"
                          "Actual notes.\n"_s;

    service.checkForUpdates();

    QTRY_VERIFY_WITH_TIMEOUT(!service.checking(), 2'000);
    QVERIFY2(service.lastError().isEmpty(), qPrintable(service.lastError()));
    QCOMPARE(service.releaseNotes(), u"Actual notes."_s);
}

QTEST_GUILESS_MAIN(TestAppUpdateService)

#include "appupdateservice_test.moc"
