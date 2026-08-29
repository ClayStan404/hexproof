// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "AppUpdateService.h"

#include "NetworkLimits.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QSysInfo>

namespace hexproof::client {
namespace {

constexpr qint64 kMaximumReleaseMetadataBytes = 4 * 1024 * 1024;
constexpr qint64 kMaximumChecksumsBytes = 1024 * 1024;
constexpr qint64 kMaximumUpdatePackageBytes = 2LL * 1024 * 1024 * 1024;
constexpr qint64 kAutomaticCheckIntervalSeconds = 24 * 60 * 60;
constexpr auto kLatestReleaseApi =
    "https://api.github.com/repos/ClayStan404/hexproof/releases/latest";
constexpr auto kReleaseApiPrefix =
    "https://api.github.com/repos/ClayStan404/hexproof/releases/tags/v";
constexpr auto kReleaseListUrl = "https://github.com/ClayStan404/hexproof/releases";
constexpr auto kLastCheckKey = "updates/applicationLastCheckUtc";
constexpr auto kCachePrefix = "updates/latestApplicationRelease/";

QNetworkRequest githubRequest(const QUrl &url, const QByteArray &accept,
                              int transferTimeoutMs = 15'000)
{
    QNetworkRequest request(url);
    request.setRawHeader(QByteArrayLiteral("User-Agent"),
                         QByteArrayLiteral("Hexproof/") + QByteArrayLiteral(HEXPROOF_VERSION) +
                             QByteArrayLiteral(" (+https://github.com/ClayStan404/hexproof)"));
    request.setRawHeader(QByteArrayLiteral("Accept"), accept);
    request.setRawHeader(QByteArrayLiteral("X-GitHub-Api-Version"),
                         QByteArrayLiteral("2022-11-28"));
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setTransferTimeout(transferTimeoutMs);
    return request;
}

bool successfulReply(const QNetworkReply *reply)
{
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    return reply->error() == QNetworkReply::NoError && status >= 200 && status < 300;
}

QString normalizedArchitecture()
{
    const QString architecture = QSysInfo::buildCpuArchitecture().toLower();
    if (architecture == QStringLiteral("amd64") || architecture == QStringLiteral("x86-64"))
        return QStringLiteral("x86_64");
    if (architecture == QStringLiteral("aarch64"))
        return QStringLiteral("arm64");
    return architecture;
}

bool validSha256(const QByteArray &checksum)
{
    static const QRegularExpression pattern(QStringLiteral(R"(^[0-9a-f]{64}$)"));
    return pattern.match(QString::fromLatin1(checksum)).hasMatch();
}

} // namespace

AppUpdateService::AppUpdateService(QObject *parent)
    : AppUpdateService(defaultDownloadRoot(), nullptr, parent)
{
}

AppUpdateService::AppUpdateService(const QString &downloadRoot, QNetworkAccessManager *network,
                                   QObject *parent)
    : QObject(parent),
      m_currentVersion(QStringLiteral(HEXPROOF_VERSION)),
      m_downloadRoot(downloadRoot)
{
    if (network) {
        m_network = network;
    } else {
        m_ownedNetwork = std::make_unique<QNetworkAccessManager>();
        m_network = m_ownedNetwork.get();
    }
    loadCachedLatestRelease();
}

AppUpdateService::~AppUpdateService()
{
    if (m_checkReply) {
        disconnect(m_checkReply, nullptr, this, nullptr);
        if (m_ownedNetwork)
            m_checkReply->abort();
    }
    if (m_downloadReply) {
        disconnect(m_downloadReply, nullptr, this, nullptr);
        if (m_ownedNetwork)
            m_downloadReply->abort();
    }
    if (m_downloadFile)
        m_downloadFile->cancelWriting();
}

QString AppUpdateService::currentVersion() const
{
    return m_currentVersion;
}

QString AppUpdateService::targetVersion() const
{
    return m_release.version;
}

QString AppUpdateService::releaseName() const
{
    return m_release.name;
}

QString AppUpdateService::releaseNotes() const
{
    return m_release.notes;
}

QString AppUpdateService::publishedAt() const
{
    return m_release.publishedAt;
}

QString AppUpdateService::releaseUrl() const
{
    return m_release.releaseUrl.toString();
}

bool AppUpdateService::exactVersion() const
{
    return m_release.exact;
}

bool AppUpdateService::releaseAvailable() const
{
    return !m_release.version.isEmpty() && !m_release.assetName.isEmpty() &&
           m_release.assetUrl.isValid() && m_release.assetSize > 0 &&
           validSha256(m_release.checksum);
}

bool AppUpdateService::updateAvailable() const
{
    if (!releaseAvailable())
        return false;
    if (m_release.exact)
        return m_release.version != m_currentVersion;
    return compareVersions(m_release.version, m_currentVersion) > 0;
}

bool AppUpdateService::checking() const
{
    return m_checking;
}

bool AppUpdateService::downloading() const
{
    return m_downloading;
}

qreal AppUpdateService::progress() const
{
    return m_progress;
}

bool AppUpdateService::downloadReady() const
{
    return m_downloadReady && QFileInfo::exists(m_downloadPath);
}

QString AppUpdateService::downloadPath() const
{
    return m_downloadPath;
}

QString AppUpdateService::lastError() const
{
    return m_lastError;
}

void AppUpdateService::checkForUpdates()
{
    if (m_checking || m_downloading)
        return;
    recordLatestCheckAttempt();
    requestRelease(QUrl(QString::fromLatin1(kLatestReleaseApi)));
}

void AppUpdateService::checkForVersion(const QString &version)
{
    const QString normalized = version.trimmed();
    if (m_checking || m_downloading)
        return;
    if (!validVersion(normalized)) {
        setLastError(QStringLiteral("The requested application version is invalid."));
        emit stateChanged();
        return;
    }
    requestRelease(QUrl(QString::fromLatin1(kReleaseApiPrefix) + normalized), normalized);
}

void AppUpdateService::checkAutomatically()
{
    if (m_automaticCheckStarted)
        return;
    m_automaticCheckStarted = true;
    if (automaticCheckIsDue())
        checkForUpdates();
}

void AppUpdateService::requestRelease(const QUrl &apiUrl, const QString &exactVersion)
{
    m_lastError.clear();
    m_checking = true;
    m_pendingRelease = {};
    m_requestedExactVersion = exactVersion;
    emit stateChanged();

    QNetworkReply *reply =
        m_network->get(githubRequest(apiUrl, QByteArrayLiteral("application/vnd.github+json")));
    m_checkReply = reply;
    network_limits::limitNetworkReply(reply, kMaximumReleaseMetadataBytes);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() { handleReleaseReply(reply); });
}

void AppUpdateService::handleReleaseReply(QNetworkReply *reply)
{
    if (reply != m_checkReply)
        return;
    m_checkReply = nullptr;
    const bool networkOk = successfulReply(reply);
    const QByteArray payload = reply->readAll();
    const QString exactVersion = m_requestedExactVersion;
    reply->deleteLater();
    if (!networkOk) {
        finishCheckWithError(QStringLiteral("Application update check failed."));
        return;
    }

    ReleaseInfo release = parseRelease(payload, exactVersion);
    if (release.version.isEmpty()) {
        finishCheckWithError(QStringLiteral("The application release metadata is invalid."));
        return;
    }
    requestChecksums(std::move(release));
}

void AppUpdateService::requestChecksums(ReleaseInfo release)
{
    m_pendingRelease = std::move(release);
    QNetworkReply *reply = m_network->get(
        githubRequest(m_pendingRelease.checksumsUrl, QByteArrayLiteral("text/plain")));
    m_checkReply = reply;
    network_limits::limitNetworkReply(reply, kMaximumChecksumsBytes);
    connect(reply, &QNetworkReply::finished, this,
            [this, reply]() { handleChecksumsReply(reply); });
}

void AppUpdateService::handleChecksumsReply(QNetworkReply *reply)
{
    if (reply != m_checkReply)
        return;
    m_checkReply = nullptr;
    const bool networkOk = successfulReply(reply);
    const QByteArray payload = reply->readAll();
    reply->deleteLater();
    if (!networkOk) {
        finishCheckWithError(QStringLiteral("Release checksums are unavailable."));
        return;
    }
    m_pendingRelease.checksum = checksumForAsset(payload, m_pendingRelease.assetName);
    if (m_pendingRelease.checksum.size() != 64) {
        finishCheckWithError(QStringLiteral("Release checksums are unavailable."));
        return;
    }
    applyRelease(std::move(m_pendingRelease));
}

void AppUpdateService::applyRelease(ReleaseInfo release)
{
    const bool sameDownload = m_release.assetName == release.assetName &&
                              m_release.checksum == release.checksum && downloadReady();
    m_release = std::move(release);
    m_pendingRelease = {};
    m_requestedExactVersion.clear();
    m_checking = false;
    m_lastError.clear();
    if (!sameDownload)
        resetDownloadedUpdate();
    if (!m_release.exact)
        cacheLatestRelease();
    emit stateChanged();
}

void AppUpdateService::finishCheckWithError(const QString &error)
{
    m_checking = false;
    m_pendingRelease = {};
    m_requestedExactVersion.clear();
    setLastError(error);
    emit stateChanged();
}

void AppUpdateService::downloadUpdate()
{
    if (m_checking || m_downloading || !updateAvailable())
        return;
    if (!QDir().mkpath(m_downloadRoot)) {
        setLastError(QStringLiteral("Could not create the update download directory."));
        emit stateChanged();
        return;
    }

    resetDownloadedUpdate();
    m_lastError.clear();
    m_downloadPath = QDir(m_downloadRoot).filePath(m_release.assetName);
    m_downloadFile = std::make_unique<QSaveFile>(m_downloadPath);
    m_downloadFile->setDirectWriteFallback(false);
    if (!m_downloadFile->open(QIODevice::WriteOnly)) {
        m_downloadFile.reset();
        m_downloadPath.clear();
        setLastError(QStringLiteral("Could not write the update package."));
        emit stateChanged();
        return;
    }

    m_downloadHash = std::make_unique<QCryptographicHash>(QCryptographicHash::Sha256);
    m_downloadedBytes = 0;
    m_downloadCancelled = false;
    m_downloadWriteFailed = false;
    m_downloading = true;
    m_progress = 0.0;
    emit progressChanged();
    emit stateChanged();

    QNetworkReply *reply = m_network->get(
        githubRequest(m_release.assetUrl, QByteArrayLiteral("application/octet-stream"), 30'000));
    m_downloadReply = reply;
    connect(reply, &QNetworkReply::readyRead, this, [this, reply]() {
        if (reply != m_downloadReply || readDownloadData())
            return;
        m_downloadWriteFailed = true;
        reply->abort();
    });
    connect(reply, &QNetworkReply::downloadProgress, this, [this, reply](qint64 received, qint64) {
        if (reply != m_downloadReply || m_release.assetSize <= 0)
            return;
        const qreal next = qBound(0.0, qreal(received) / qreal(m_release.assetSize), 1.0);
        if (qFuzzyCompare(next, m_progress))
            return;
        m_progress = next;
        emit progressChanged();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply]() { finishDownload(reply); });
}

bool AppUpdateService::readDownloadData()
{
    if (!m_downloadReply || !m_downloadFile || !m_downloadHash)
        return false;
    const QByteArray data = m_downloadReply->readAll();
    if (data.isEmpty())
        return true;
    if (m_downloadedBytes > m_release.assetSize - data.size() ||
        m_downloadedBytes > kMaximumUpdatePackageBytes - data.size()) {
        return false;
    }
    if (m_downloadFile->write(data) != data.size())
        return false;
    m_downloadHash->addData(data);
    m_downloadedBytes += data.size();
    return true;
}

void AppUpdateService::finishDownload(QNetworkReply *reply)
{
    if (reply != m_downloadReply)
        return;
    const bool finalReadOk = readDownloadData();
    const bool networkOk = successfulReply(reply);
    m_downloadReply = nullptr;
    reply->deleteLater();

    if (m_downloadCancelled) {
        if (m_downloadFile)
            m_downloadFile->cancelWriting();
        m_downloadFile.reset();
        m_downloadHash.reset();
        m_downloading = false;
        m_downloadPath.clear();
        m_progress = 0.0;
        emit progressChanged();
        emit stateChanged();
        return;
    }
    if (!finalReadOk || m_downloadWriteFailed) {
        failDownload(QStringLiteral("Could not write the update package."));
        return;
    }
    if (!networkOk || m_downloadedBytes != m_release.assetSize) {
        failDownload(QStringLiteral("The application update download failed."));
        return;
    }
    if (!m_downloadHash || m_downloadHash->result().toHex().toLower() != m_release.checksum) {
        failDownload(QStringLiteral("The downloaded update did not match its published checksum."));
        return;
    }
    if (!m_downloadFile || !m_downloadFile->commit()) {
        failDownload(QStringLiteral("Could not write the update package."));
        return;
    }

    m_downloadFile.reset();
    m_downloadHash.reset();
    m_downloading = false;
    m_downloadReady = true;
    m_progress = 1.0;
    emit progressChanged();
    emit stateChanged();
}

void AppUpdateService::cancelDownload()
{
    if (!m_downloadReply || !m_downloading)
        return;
    m_downloadCancelled = true;
    m_downloadReply->abort();
}

void AppUpdateService::failDownload(const QString &error)
{
    if (m_downloadFile)
        m_downloadFile->cancelWriting();
    m_downloadFile.reset();
    m_downloadHash.reset();
    m_downloading = false;
    m_downloadReady = false;
    m_downloadPath.clear();
    m_progress = 0.0;
    setLastError(error);
    emit progressChanged();
    emit stateChanged();
}

bool AppUpdateService::openDownloadLocation()
{
    const QString directory =
        downloadReady() ? QFileInfo(m_downloadPath).absolutePath() : m_downloadRoot;
    if (directory.isEmpty() || !QFileInfo(directory).isDir() ||
        !QDesktopServices::openUrl(QUrl::fromLocalFile(directory))) {
        setLastError(QStringLiteral("Could not open the update download location."));
        emit stateChanged();
        return false;
    }
    return true;
}

bool AppUpdateService::openReleasePage()
{
    const QUrl url = m_release.releaseUrl.isValid() ? m_release.releaseUrl
                                                    : QUrl(QString::fromLatin1(kReleaseListUrl));
    if (QDesktopServices::openUrl(url))
        return true;
    setLastError(QStringLiteral("Could not open the application release page."));
    emit stateChanged();
    return false;
}

void AppUpdateService::clearLastError()
{
    if (m_lastError.isEmpty())
        return;
    m_lastError.clear();
    emit stateChanged();
}

void AppUpdateService::resetDownloadedUpdate()
{
    m_downloadReady = false;
    m_downloadPath.clear();
}

void AppUpdateService::setLastError(const QString &error)
{
    m_lastError = error;
}

QString AppUpdateService::defaultDownloadRoot()
{
    QString root = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (root.isEmpty())
        root = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    if (root.isEmpty())
        root = QDir::homePath();
    return QDir(root).filePath(QStringLiteral("Hexproof"));
}

QString AppUpdateService::platformAssetName(const QString &version)
{
    const QString architecture = normalizedArchitecture();
#if defined(Q_OS_WIN)
    if (architecture == QStringLiteral("x86_64"))
        return QStringLiteral("Hexproof-%1-windows-x64.zip").arg(version);
#elif defined(Q_OS_MACOS)
    if (architecture == QStringLiteral("arm64") || architecture == QStringLiteral("x86_64"))
        return QStringLiteral("Hexproof-%1-macos-%2.zip").arg(version, architecture);
#elif defined(Q_OS_LINUX)
    if (architecture == QStringLiteral("x86_64"))
        return QStringLiteral("Hexproof-%1-linux-x86_64.tar.gz").arg(version);
#endif
    return {};
}

bool AppUpdateService::validVersion(const QString &version)
{
    static const QRegularExpression pattern(QStringLiteral(R"(^[0-9]+\.[0-9]+\.[0-9]+$)"));
    if (!pattern.match(version).hasMatch())
        return false;
    for (const QString &part : version.split(QLatin1Char('.'))) {
        bool ok = false;
        part.toUInt(&ok);
        if (!ok)
            return false;
    }
    return true;
}

int AppUpdateService::compareVersions(const QString &left, const QString &right)
{
    if (!validVersion(left) || !validVersion(right))
        return QString::compare(left, right, Qt::CaseSensitive);
    const QStringList leftParts = left.split(QLatin1Char('.'));
    const QStringList rightParts = right.split(QLatin1Char('.'));
    for (qsizetype index = 0; index < leftParts.size(); ++index) {
        const quint32 leftPart = leftParts.at(index).toUInt();
        const quint32 rightPart = rightParts.at(index).toUInt();
        if (leftPart < rightPart)
            return -1;
        if (leftPart > rightPart)
            return 1;
    }
    return 0;
}

bool AppUpdateService::officialReleaseUrl(const QUrl &url, const QString &tag,
                                          const QString &assetName)
{
    return url.scheme() == QStringLiteral("https") &&
           url.host().compare(QStringLiteral("github.com"), Qt::CaseInsensitive) == 0 &&
           url.path() ==
               QStringLiteral("/ClayStan404/hexproof/releases/download/%1/%2").arg(tag, assetName);
}

bool AppUpdateService::officialReleasePageUrl(const QUrl &url, const QString &tag)
{
    return url.scheme() == QStringLiteral("https") &&
           url.host().compare(QStringLiteral("github.com"), Qt::CaseInsensitive) == 0 &&
           url.path() == QStringLiteral("/ClayStan404/hexproof/releases/tag/%1").arg(tag);
}

AppUpdateService::ReleaseInfo AppUpdateService::parseRelease(const QByteArray &payload,
                                                             const QString &exactVersion)
{
    ReleaseInfo result;
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject())
        return {};
    const QJsonObject object = document.object();
    if (object.value(QStringLiteral("draft")).toBool(true) ||
        object.value(QStringLiteral("prerelease")).toBool(true)) {
        return {};
    }
    const QString tag = object.value(QStringLiteral("tag_name")).toString();
    if (!tag.startsWith(QLatin1Char('v')) || !validVersion(tag.mid(1)))
        return {};
    result.version = tag.mid(1);
    if (!exactVersion.isEmpty() && result.version != exactVersion)
        return {};
    result.exact = !exactVersion.isEmpty();
    result.assetName = platformAssetName(result.version);
    if (result.assetName.isEmpty())
        return {};

    const QDateTime publishedAt =
        QDateTime::fromString(object.value(QStringLiteral("published_at")).toString(), Qt::ISODate);
    result.publishedAt = publishedAt.isValid() ? publishedAt.toUTC().toString(Qt::ISODate) : "";
    result.name = object.value(QStringLiteral("name")).toString().trimmed();
    if (result.name.isEmpty())
        result.name = tag;
    result.notes = object.value(QStringLiteral("body")).toString().trimmed().left(16 * 1024);
    result.releaseUrl = QUrl(object.value(QStringLiteral("html_url")).toString());
    if (!officialReleasePageUrl(result.releaseUrl, tag)) {
        return {};
    }

    const QJsonArray assets = object.value(QStringLiteral("assets")).toArray();
    for (const QJsonValue &value : assets) {
        const QJsonObject asset = value.toObject();
        const QString name = asset.value(QStringLiteral("name")).toString();
        const QUrl url(asset.value(QStringLiteral("browser_download_url")).toString());
        if (name == result.assetName) {
            result.assetUrl = url;
            result.assetSize = asset.value(QStringLiteral("size")).toInteger();
        } else if (name == QStringLiteral("SHA256SUMS")) {
            result.checksumsUrl = url;
        }
    }
    if (result.assetSize <= 0 || result.assetSize > kMaximumUpdatePackageBytes ||
        !officialReleaseUrl(result.assetUrl, tag, result.assetName) ||
        !officialReleaseUrl(result.checksumsUrl, tag, QStringLiteral("SHA256SUMS"))) {
        return {};
    }
    return result;
}

QByteArray AppUpdateService::checksumForAsset(const QByteArray &payload, const QString &assetName)
{
    const QList<QByteArray> lines = payload.split('\n');
    for (QByteArray line : lines) {
        line = line.trimmed();
        if (line.size() < 67)
            continue;
        const QByteArray checksum = line.first(64).toLower();
        QByteArray name = line.mid(64).trimmed();
        if (name.startsWith('*'))
            name.remove(0, 1);
        if (name == assetName.toUtf8() && validSha256(checksum)) {
            return checksum;
        }
    }
    return {};
}

void AppUpdateService::loadCachedLatestRelease()
{
    QSettings settings;
    ReleaseInfo cached;
    cached.version = settings.value(QString::fromLatin1(kCachePrefix) + "version").toString();
    cached.name = settings.value(QString::fromLatin1(kCachePrefix) + "name").toString();
    cached.notes = settings.value(QString::fromLatin1(kCachePrefix) + "notes").toString();
    cached.publishedAt =
        settings.value(QString::fromLatin1(kCachePrefix) + "publishedAt").toString();
    cached.releaseUrl = settings.value(QString::fromLatin1(kCachePrefix) + "releaseUrl").toUrl();
    cached.assetName = settings.value(QString::fromLatin1(kCachePrefix) + "assetName").toString();
    cached.assetUrl = settings.value(QString::fromLatin1(kCachePrefix) + "assetUrl").toUrl();
    cached.assetSize = settings.value(QString::fromLatin1(kCachePrefix) + "assetSize").toLongLong();
    cached.checksumsUrl =
        settings.value(QString::fromLatin1(kCachePrefix) + "checksumsUrl").toUrl();
    cached.checksum =
        settings.value(QString::fromLatin1(kCachePrefix) + "checksum").toByteArray().toLower();
    const QString tag = QStringLiteral("v") + cached.version;
    if (!validVersion(cached.version) || cached.assetName != platformAssetName(cached.version) ||
        cached.assetSize <= 0 || cached.assetSize > kMaximumUpdatePackageBytes ||
        !officialReleasePageUrl(cached.releaseUrl, tag) ||
        !officialReleaseUrl(cached.assetUrl, tag, cached.assetName) ||
        !officialReleaseUrl(cached.checksumsUrl, tag, QStringLiteral("SHA256SUMS")) ||
        !validSha256(cached.checksum)) {
        return;
    }
    m_release = std::move(cached);
}

void AppUpdateService::cacheLatestRelease() const
{
    QSettings settings;
    settings.setValue(QString::fromLatin1(kCachePrefix) + "version", m_release.version);
    settings.setValue(QString::fromLatin1(kCachePrefix) + "name", m_release.name);
    settings.setValue(QString::fromLatin1(kCachePrefix) + "notes", m_release.notes);
    settings.setValue(QString::fromLatin1(kCachePrefix) + "publishedAt", m_release.publishedAt);
    settings.setValue(QString::fromLatin1(kCachePrefix) + "releaseUrl", m_release.releaseUrl);
    settings.setValue(QString::fromLatin1(kCachePrefix) + "assetName", m_release.assetName);
    settings.setValue(QString::fromLatin1(kCachePrefix) + "assetUrl", m_release.assetUrl);
    settings.setValue(QString::fromLatin1(kCachePrefix) + "assetSize", m_release.assetSize);
    settings.setValue(QString::fromLatin1(kCachePrefix) + "checksumsUrl", m_release.checksumsUrl);
    settings.setValue(QString::fromLatin1(kCachePrefix) + "checksum", m_release.checksum);
}

void AppUpdateService::recordLatestCheckAttempt() const
{
    QSettings settings;
    settings.setValue(QString::fromLatin1(kLastCheckKey),
                      QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
}

bool AppUpdateService::automaticCheckIsDue() const
{
    QSettings settings;
    const QDateTime lastCheck = QDateTime::fromString(
        settings.value(QString::fromLatin1(kLastCheckKey)).toString(), Qt::ISODate);
    if (!lastCheck.isValid())
        return true;
    const qint64 elapsed = lastCheck.toUTC().secsTo(QDateTime::currentDateTimeUtc());
    return elapsed < 0 || elapsed >= kAutomaticCheckIntervalSeconds;
}

} // namespace hexproof::client
