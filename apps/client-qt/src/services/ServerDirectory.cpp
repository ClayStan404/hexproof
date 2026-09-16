// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "ServerDirectory.h"

#include "NetworkLimits.h"

#include <QCryptographicHash>
#include <QDebug>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

#include <optional>

namespace hexproof::client {
namespace {
using namespace Qt::StringLiterals;

constexpr qsizetype kMaximumDirectoryBytes = 64 * 1024;
constexpr int kMaximumServers = 32;
constexpr qint64 kRefreshIntervalMs = 5 * 60 * 1000;

QString normalizedServerUrl(const QString &value)
{
    QUrl url(value.trimmed(), QUrl::StrictMode);
    if (!url.isValid() || url.host().isEmpty() || url.port(-1) == 0 ||
        (url.scheme() != u"ws"_s && url.scheme() != u"wss"_s))
        return {};
    if (url.path().isEmpty() || url.path() == u"/"_s)
        url.setPath(u"/ws"_s);
    url.setFragment({});
    return url.toString(QUrl::FullyEncoded);
}

bool isLoopback(const QUrl &url)
{
    return url.host() == u"localhost"_s || QHostAddress(url.host()).isLoopback();
}

bool validDirectoryUrl(const QString &value)
{
    const QUrl url(value, QUrl::StrictMode);
    return value.size() <= 2048 && url.isValid() && !url.host().isEmpty() && url.port(-1) != 0 &&
           url.userInfo().isEmpty() && !url.hasFragment() &&
           (url.scheme() == u"https"_s || (url.scheme() == u"http"_s && isLoopback(url)));
}

bool hasOnlyKeys(const QJsonObject &object, const QSet<QString> &allowed)
{
    for (auto it = object.constBegin(); it != object.constEnd(); ++it) {
        if (!allowed.contains(it.key()))
            return false;
    }
    return true;
}

std::optional<QJsonObject> parseDirectory(const QByteArray &bytes, bool online)
{
    if (bytes.isEmpty() || bytes.size() > kMaximumDirectoryBytes)
        return std::nullopt;
    const QJsonDocument document = QJsonDocument::fromJson(bytes);
    if (!document.isObject())
        return std::nullopt;
    const QJsonObject root = document.object();
    const int schema = root.value(u"schemaVersion"_s).toInt();
    if ((schema != 1 && schema != 2) || root.value(u"schemaVersion"_s).toDouble() != schema ||
        (online && schema != 2) || !root.value(u"servers"_s).isArray())
        return std::nullopt;
    const QSet<QString> keys = schema == 1 ? QSet<QString>{u"schemaVersion"_s, u"servers"_s}
                                           : QSet<QString>{u"schemaVersion"_s, u"revision"_s,
                                                           u"directoryUrls"_s, u"servers"_s};
    if (!hasOnlyKeys(root, keys))
        return std::nullopt;
    if (schema == 2) {
        const double revision = root.value(u"revision"_s).toDouble(-1);
        if (revision < 1 || revision > 9007199254740991.0 ||
            revision != root.value(u"revision"_s).toInteger())
            return std::nullopt;
        const QJsonValue sources = root.value(u"directoryUrls"_s);
        if (!sources.isUndefined() && (!sources.isArray() || sources.toArray().size() > 4))
            return std::nullopt;
        for (const auto &source : sources.toArray()) {
            if (!source.isString() || !validDirectoryUrl(source.toString()))
                return std::nullopt;
        }
    }
    const QJsonArray servers = root.value(u"servers"_s).toArray();
    if (servers.size() > kMaximumServers || (schema == 1 && servers.isEmpty()))
        return std::nullopt;
    QSet<QString> ids;
    QSet<QString> urls;
    for (const auto &value : servers) {
        if (!value.isObject())
            return std::nullopt;
        const QJsonObject entry = value.toObject();
        const QSet<QString> entryKeys = schema == 1
                                            ? QSet<QString>{u"url"_s, u"legacyUrls"_s}
                                            : QSet<QString>{u"id"_s,  u"name"_s,  u"sponsor"_s,
                                                            u"url"_s, u"forge"_s, u"legacyUrls"_s};
        const QString endpoint = normalizedServerUrl(entry.value(u"url"_s).toString());
        const QUrl url(endpoint);
        if (!hasOnlyKeys(entry, entryKeys) || endpoint.isEmpty() || endpoint.size() > 2048 ||
            urls.contains(endpoint))
            return std::nullopt;
        if (online &&
            ((!isLoopback(url) && url.scheme() != u"wss"_s) || !url.userInfo().isEmpty() ||
             url.hasQuery() || QUrl(entry.value(u"url"_s).toString()).hasFragment()))
            return std::nullopt;
        urls.insert(endpoint);
        if (schema == 2) {
            const QString id = entry.value(u"id"_s).toString();
            const QString name = entry.value(u"name"_s).toString().trimmed();
            if (id.isEmpty() || id.size() > 64 || ids.contains(id) || id == u"custom"_s ||
                name.isEmpty() || name.size() > 120 || !entry.value(u"forge"_s).isBool())
                return std::nullopt;
            for (const QChar character : id) {
                if (!(character >= u'a' && character <= u'z') &&
                    !(character >= u'0' && character <= u'9') && character != u'-' &&
                    character != u'_')
                    return std::nullopt;
            }
            const QJsonValue sponsor = entry.value(u"sponsor"_s);
            if (!sponsor.isUndefined() && (!sponsor.isString() || sponsor.toString().size() > 120))
                return std::nullopt;
            ids.insert(id);
        }
        const QJsonValue legacy = entry.value(u"legacyUrls"_s);
        if (!legacy.isUndefined() && (!legacy.isArray() || legacy.toArray().size() > 8))
            return std::nullopt;
        for (const auto &old : legacy.toArray()) {
            if (!old.isString() || old.toString().size() > 2048 ||
                normalizedServerUrl(old.toString()).isEmpty())
                return std::nullopt;
        }
    }
    return root;
}

std::optional<QJsonObject> readDirectory(const QString &path, bool online = false)
{
    if (path.isEmpty())
        return std::nullopt;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly) || file.size() > kMaximumDirectoryBytes)
        return std::nullopt;
    return parseDirectory(file.read(kMaximumDirectoryBytes + 1), online);
}

bool canReplace(const QJsonObject &current, const QJsonObject &next)
{
    const qint64 oldRevision = current.value(u"revision"_s).toInteger();
    const qint64 nextRevision = next.value(u"revision"_s).toInteger();
    return nextRevision > oldRevision ||
           (nextRevision == oldRevision && current.value(u"servers"_s) == next.value(u"servers"_s));
}

QUrl healthUrl(const QString &endpoint)
{
    QUrl url(endpoint);
    url.setScheme(url.scheme() == u"wss"_s ? u"https"_s : u"http"_s);
    QString path = url.path();
    if (path.endsWith(u"/ws"_s)) {
        path.chop(3);
        path += u"/healthz"_s;
    } else {
        path = u"/healthz"_s;
    }
    url.setPath(path);
    url.setQuery(QString{});
    url.setFragment({});
    return url;
}
} // namespace

ServerDirectory::ServerDirectory(QObject *parent)
    : QObject(parent)
{
    auto document = readDirectory(u":/config/servers.json"_s);
    QString initialSource = u"bundled"_s;
    const QString localPath = qEnvironmentVariable("HEXPROOF_SERVER_DIRECTORY_FILE").trimmed();
    if (!localPath.isEmpty()) {
        const auto local = readDirectory(localPath);
        if (local) {
            document = local;
            initialSource = u"local"_s;
        } else {
            qWarning() << "Hexproof server directory override is invalid; using bundled fallback";
        }
    }
    if (!document) {
        qCritical() << "Hexproof bundled server directory is invalid";
        m_latencyMs = {-2};
        return;
    }
    for (const auto &source : document->value(u"directoryUrls"_s).toArray())
        m_directoryUrls.push_back(source.toString());
    // Local endpoint overrides are an isolated development configuration.
    // They must not be replaced by a background production directory fetch.
    for (int index = 1; index <= kMaximumServers; ++index) {
        if (qEnvironmentVariableIsSet(qPrintable(u"HEXPROOF_SERVER_%1_URL"_s.arg(index)))) {
            m_directoryUrls.clear();
            break;
        }
    }
    if (qEnvironmentVariableIsSet("HEXPROOF_SERVER_DIRECTORY_URL")) {
        m_directoryUrls.clear();
        const QString source = qEnvironmentVariable("HEXPROOF_SERVER_DIRECTORY_URL").trimmed();
        if (validDirectoryUrl(source))
            m_directoryUrls.push_back(source);
    }
    applyDirectory(*document, initialSource);
    if (!m_directoryUrls.isEmpty()) {
        const auto cached = readDirectory(cachePath(), true);
        if (cached && canReplace(m_document, *cached))
            applyDirectory(*cached, u"cache"_s);
    }
}

int ServerDirectory::configuredServerCount() const
{
    return static_cast<int>(m_servers.size());
}
int ServerDirectory::customServerIndex() const
{
    return configuredServerCount();
}
QString ServerDirectory::source() const
{
    return m_source;
}
bool ServerDirectory::refreshing() const
{
    return m_refreshing;
}
bool ServerDirectory::refreshFailed() const
{
    return m_refreshFailed;
}

QVariantList ServerDirectory::entries() const
{
    QVariantList result = m_servers;
    result.push_back(
        QVariantMap{{u"id"_s, u"custom"_s}, {u"url"_s, m_customServerUrl}, {u"forge"_s, -1}});
    for (QVariant &item : result) {
        QVariantMap entry = item.toMap();
        const auto found = m_observedForge.constFind(entry.value(u"url"_s).toString());
        if (found != m_observedForge.cend())
            entry.insert(u"forge"_s, *found);
        item = entry;
    }
    return result;
}

void ServerDirectory::applyDirectory(const QJsonObject &document, const QString &source)
{
    m_document = document;
    m_source = source;
    m_servers.clear();
    const QJsonArray entries = document.value(u"servers"_s).toArray();
    for (int index = 0; index < entries.size(); ++index) {
        QVariantMap entry = entries[index].toObject().toVariantMap();
        if (!entry.contains(u"id"_s)) {
            entry.insert(u"id"_s, u"server-%1"_s.arg(index + 1));
            entry.insert(u"name"_s, u"Server %1"_s.arg(index + 1));
        }
        const QJsonValue forge = entries[index].toObject().value(u"forge"_s);
        entry.insert(u"forge"_s, forge.isBool() ? static_cast<int>(forge.toBool()) : -1);
        QString endpoint = normalizedServerUrl(entry.value(u"url"_s).toString());
        const QString overrideUrl =
            qEnvironmentVariable(qPrintable(u"HEXPROOF_SERVER_%1_URL"_s.arg(index + 1)));
        if (!overrideUrl.isEmpty()) {
            const QString normalized = normalizedServerUrl(overrideUrl);
            if (!normalized.isEmpty()) {
                endpoint = normalized;
                entry.insert(u"forge"_s, -1);
            }
        }
        entry.insert(u"url"_s, endpoint);
        m_servers.push_back(entry);
    }
    ++m_catalogGeneration;
    m_latencyMs.fill(-2, configuredServerCount() + 1);
    emit directoryChanged();
    emit latenciesChanged();
    emit statusChanged();
}

QString ServerDirectory::serverUrl(int index) const
{
    if (index == customServerIndex())
        return m_customServerUrl;
    return index >= 0 && index < configuredServerCount()
               ? m_servers[index].toMap().value(u"url"_s).toString()
               : QString{};
}

QString ServerDirectory::customServerUrl() const
{
    return m_customServerUrl;
}

bool ServerDirectory::setCustomServerUrl(const QString &value)
{
    const QString normalized = value.trimmed().isEmpty() ? QString{} : normalizedServerUrl(value);
    if (!value.trimmed().isEmpty() && normalized.isEmpty())
        return false;
    if (m_customServerUrl == normalized)
        return true;
    m_customServerUrl = normalized;
    ++m_customGeneration;
    m_latencyMs[customServerIndex()] = -2;
    emit customServerUrlChanged();
    emit directoryChanged();
    emit latenciesChanged();
    return true;
}

int ServerDirectory::indexForUrl(const QString &url) const
{
    for (int index = configuredServerCount() - 1; index >= 0; --index) {
        if (url == serverUrl(index))
            return index;
    }
    return url.isEmpty() && configuredServerCount() > 0 ? 0 : customServerIndex();
}

QString ServerDirectory::normalizePersistedUrl(const QString &url) const
{
    for (int index = 0; index < configuredServerCount(); ++index) {
        if (m_servers[index].toMap().value(u"legacyUrls"_s).toStringList().contains(url))
            return serverUrl(index);
    }
    return url;
}

QVariantList ServerDirectory::latencies() const
{
    QVariantList result;
    for (int latency : m_latencyMs)
        result.push_back(latency);
    return result;
}

void ServerDirectory::recordForgeCapability(const QString &url, bool supported)
{
    m_observedForge.insert(url, supported ? 1 : 0);
    emit directoryChanged();
}

QString ServerDirectory::cachePath() const
{
    if (qEnvironmentVariableIsSet("HEXPROOF_SERVER_DIRECTORY_CACHE"))
        return qEnvironmentVariable("HEXPROOF_SERVER_DIRECTORY_CACHE");
    const QByteArray scope =
        QCryptographicHash::hash(m_directoryUrls.join(u'\n').toUtf8(), QCryptographicHash::Sha256)
            .toHex();
    return QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation) +
           u"/network/servers-%1.json"_s.arg(QString::fromLatin1(scope.left(16)));
}

void ServerDirectory::refreshDirectory(bool force)
{
    if (m_refreshing || m_directoryUrls.isEmpty() ||
        (!force && m_lastDirectoryAttempt.isValid() &&
         m_lastDirectoryAttempt.elapsed() < kRefreshIntervalMs))
        return;
    m_lastDirectoryAttempt.start();
    m_refreshing = true;
    m_refreshFailed = false;
    emit statusChanged();
    fetchNextSource(0);
}

void ServerDirectory::fetchNextSource(int index)
{
    if (index >= m_directoryUrls.size()) {
        m_refreshing = false;
        m_refreshFailed = true;
        emit statusChanged();
        return;
    }
    QNetworkRequest request{QUrl(m_directoryUrls[index])};
    request.setTransferTimeout(5000);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::SameOriginRedirectPolicy);
    request.setRawHeader("Accept", "application/json");
    QNetworkReply *reply = m_networkManager.get(request);
    network_limits::limitNetworkReply(reply, kMaximumDirectoryBytes);
    QTimer::singleShot(5000, reply, [reply]() {
        if (reply->isRunning())
            reply->abort();
    });
    connect(reply, &QNetworkReply::finished, this, [this, index, reply]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto document = reply->error() == QNetworkReply::NoError && status == 200
                                  ? parseDirectory(reply->readAll(), true)
                                  : std::nullopt;
        reply->deleteLater();
        if (!document || !canReplace(m_document, *document)) {
            fetchNextSource(index + 1);
            return;
        }
        const bool changed = document->value(u"servers"_s) != m_document.value(u"servers"_s);
        m_refreshing = false;
        m_refreshFailed = false;
        if (changed)
            applyDirectory(*document, u"online"_s);
        else {
            m_document = *document;
            m_source = u"online"_s;
            emit statusChanged();
        }
        // Sources are fixed by the bundled/local bootstrap; an online document
        // cannot silently move future fetches to an unrelated directory service.
        const QString path = cachePath();
        if (!path.isEmpty() && QDir().mkpath(QFileInfo(path).absolutePath())) {
            QSaveFile file(path);
            const QByteArray bytes = QJsonDocument(*document).toJson(QJsonDocument::Compact);
            if (file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size())
                file.commit();
        }
        if (changed)
            refreshLatencies();
    });
}

void ServerDirectory::refreshLatencies()
{
    const quint64 probeGeneration = ++m_probeGeneration;
    const quint64 catalogGeneration = m_catalogGeneration;
    const quint64 customGeneration = m_customGeneration;
    m_latencyMs.fill(-2, configuredServerCount() + 1);
    emit latenciesChanged();
    for (int index = 0; index <= customServerIndex(); ++index) {
        const QString endpoint = serverUrl(index);
        if (endpoint.isEmpty())
            continue;
        const bool custom = index == customServerIndex();
        QNetworkRequest request(healthUrl(endpoint));
        request.setTransferTimeout(4000);
        QElapsedTimer timer;
        timer.start();
        QNetworkReply *reply = m_networkManager.get(request);
        network_limits::limitNetworkReply(reply, network_limits::kMaximumHealthResponseBytes);
        connect(reply, &QNetworkReply::finished, this,
                [this, index, custom, probeGeneration, catalogGeneration, customGeneration, reply,
                 timer]() {
                    const int status =
                        reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
                    const bool healthy =
                        reply->error() == QNetworkReply::NoError && status >= 200 && status < 300;
                    reply->deleteLater();
                    if (catalogGeneration != m_catalogGeneration ||
                        probeGeneration != m_probeGeneration ||
                        (custom && customGeneration != m_customGeneration))
                        return;
                    m_latencyMs[index] =
                        healthy ? qBound(0, static_cast<int>(timer.elapsed()), 9999) : -1;
                    emit latenciesChanged();
                });
    }
}
} // namespace hexproof::client
