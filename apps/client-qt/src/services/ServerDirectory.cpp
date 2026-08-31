// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "ServerDirectory.h"

#include "NetworkLimits.h"

#include <QDebug>
#include <QElapsedTimer>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSet>
#include <QUrl>

#include <optional>
#include <utility>

namespace hexproof::client {

namespace {
using namespace Qt::StringLiterals;

constexpr auto kBundledServerDirectoryPath = ":/config/servers.json";
constexpr auto kServerDirectoryOverride = "HEXPROOF_SERVER_DIRECTORY_FILE";
constexpr qsizetype kMaximumServerDirectoryBytes = 64 * 1024;

struct ServerDirectoryConfig
{
    std::array<QString, ServerDirectory::ConfiguredServerCount> urls;
    std::array<QStringList, ServerDirectory::ConfiguredServerCount> legacyUrls;
};

QString normalizedCustomServerUrl(const QString &serverUrl)
{
    QUrl url(serverUrl.trimmed(), QUrl::StrictMode);
    if (!url.isValid() || url.host().isEmpty() ||
        (url.scheme() != u"ws"_s && url.scheme() != u"wss"_s)) {
        return {};
    }
    if (url.path().isEmpty() || url.path() == u"/"_s)
        url.setPath(u"/ws"_s);
    url.setFragment({});
    return url.toString(QUrl::FullyEncoded);
}

bool hasOnlyKeys(const QJsonObject &object, const QSet<QString> &allowed)
{
    for (auto iterator = object.constBegin(); iterator != object.constEnd(); ++iterator) {
        if (!allowed.contains(iterator.key()))
            return false;
    }
    return true;
}

std::optional<ServerDirectoryConfig> loadServerDirectory(const QString &path, QString *error)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        *error = u"could not open %1: %2"_s.arg(path, file.errorString());
        return std::nullopt;
    }
    if (file.size() > kMaximumServerDirectoryBytes) {
        *error = u"%1 exceeds %2 bytes"_s.arg(path).arg(kMaximumServerDirectoryBytes);
        return std::nullopt;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        *error = u"could not parse %1: %2"_s.arg(path, parseError.errorString());
        return std::nullopt;
    }

    const QJsonObject root = document.object();
    static const QSet<QString> rootKeys{u"schemaVersion"_s, u"servers"_s};
    if (!hasOnlyKeys(root, rootKeys) || root.value(u"schemaVersion"_s).toInt(-1) != 1 ||
        !root.value(u"servers"_s).isArray()) {
        *error = u"%1 does not contain a supported server directory"_s.arg(path);
        return std::nullopt;
    }

    const QJsonArray servers = root.value(u"servers"_s).toArray();
    if (servers.size() != ServerDirectory::ConfiguredServerCount) {
        *error = u"%1 must contain exactly %2 servers"_s.arg(path).arg(
            ServerDirectory::ConfiguredServerCount);
        return std::nullopt;
    }

    ServerDirectoryConfig result;
    static const QSet<QString> serverKeys{u"url"_s, u"legacyUrls"_s};
    for (int index = 0; index < servers.size(); ++index) {
        if (!servers.at(index).isObject()) {
            *error = u"server %1 in %2 must be an object"_s.arg(index + 1).arg(path);
            return std::nullopt;
        }
        const QJsonObject entry = servers.at(index).toObject();
        const QString url = normalizedCustomServerUrl(entry.value(u"url"_s).toString());
        if (!hasOnlyKeys(entry, serverKeys) || url.isEmpty()) {
            *error = u"server %1 in %2 has an invalid URL"_s.arg(index + 1).arg(path);
            return std::nullopt;
        }
        const std::size_t resultIndex = static_cast<std::size_t>(index);
        result.urls.at(resultIndex) = url;

        const QJsonValue legacyValue = entry.value(u"legacyUrls"_s);
        if (!legacyValue.isUndefined() && !legacyValue.isArray()) {
            *error = u"server %1 in %2 has invalid legacy URLs"_s.arg(index + 1).arg(path);
            return std::nullopt;
        }
        const QJsonArray legacyUrls = legacyValue.toArray();
        for (const QJsonValue &legacyValue : legacyUrls) {
            if (!legacyValue.isString()) {
                *error = u"server %1 in %2 has invalid legacy URLs"_s.arg(index + 1).arg(path);
                return std::nullopt;
            }
            const QString legacyUrl = normalizedCustomServerUrl(legacyValue.toString());
            if (legacyUrl.isEmpty()) {
                *error = u"server %1 in %2 has invalid legacy URLs"_s.arg(index + 1).arg(path);
                return std::nullopt;
            }
            result.legacyUrls.at(resultIndex).push_back(legacyUrl);
        }
    }
    return result;
}

ServerDirectoryConfig configuredServers()
{
    const QString externalPath = qEnvironmentVariable(kServerDirectoryOverride).trimmed();
    QString error;
    if (!externalPath.isEmpty()) {
        const auto external = loadServerDirectory(externalPath, &error);
        if (external)
            return *external;
        qWarning().noquote() << "Hexproof server directory override ignored:" << error;
    }

    const auto bundled =
        loadServerDirectory(QString::fromLatin1(kBundledServerDirectoryPath), &error);
    if (!bundled) {
        qCritical().noquote() << "Hexproof bundled server directory is invalid:" << error;
        return {};
    }
    return *bundled;
}

QString environmentServerUrl(int serverIndex)
{
    static constexpr std::array names{
        "HEXPROOF_SERVER_1_URL", "HEXPROOF_SERVER_2_URL", "HEXPROOF_SERVER_3_URL",
        "HEXPROOF_SERVER_4_URL", "HEXPROOF_SERVER_5_URL",
    };
    return qEnvironmentVariable(names.at(static_cast<std::size_t>(serverIndex))).trimmed();
}

QUrl serverHealthUrl(const QString &serverUrl)
{
    QUrl url(serverUrl);
    if (url.scheme() == u"wss"_s)
        url.setScheme(u"https"_s);
    else
        url.setScheme(u"http"_s);
    QString healthPath = url.path();
    if (healthPath.endsWith(u"/ws"_s)) {
        healthPath.chop(3);
        healthPath += u"/healthz"_s;
    } else {
        healthPath = u"/healthz"_s;
    }
    url.setPath(healthPath);
    url.setQuery(QString{});
    url.setFragment(QString{});
    return url;
}
} // namespace

ServerDirectory::ServerDirectory(QObject *parent)
    : QObject(parent)
{
    ServerDirectoryConfig config = configuredServers();
    m_configuredServerUrls = std::move(config.urls);
    m_legacyServerUrls = std::move(config.legacyUrls);
    m_latencyMs.fill(-2);
    for (int index = 0; index < ConfiguredServerCount; ++index) {
        const QString overrideUrl = environmentServerUrl(index);
        if (!overrideUrl.isEmpty())
            m_configuredServerUrls.at(static_cast<std::size_t>(index)) = overrideUrl;
    }
}

QString ServerDirectory::serverUrl(int serverIndex) const
{
    if (serverIndex == CustomServerIndex)
        return m_customServerUrl;
    if (serverIndex < 0 || serverIndex >= ConfiguredServerCount)
        return {};
    return m_configuredServerUrls.at(static_cast<std::size_t>(serverIndex));
}

QString ServerDirectory::customServerUrl() const
{
    return m_customServerUrl;
}

bool ServerDirectory::setCustomServerUrl(const QString &url)
{
    const QString trimmed = url.trimmed();
    const QString normalized = trimmed.isEmpty() ? QString{} : normalizedCustomServerUrl(trimmed);
    if (!trimmed.isEmpty() && normalized.isEmpty())
        return false;
    if (m_customServerUrl == normalized)
        return true;

    m_customServerUrl = normalized;
    ++m_probeGeneration;
    m_latencyMs[CustomServerIndex] = -2;
    emit customServerUrlChanged();
    emit latenciesChanged();
    return true;
}

int ServerDirectory::indexForUrl(const QString &url) const
{
    for (int index = ConfiguredServerCount - 1; index >= 0; --index) {
        if (url == serverUrl(index))
            return index;
    }
    if (!url.isEmpty())
        return CustomServerIndex;
    return 0;
}

QString ServerDirectory::normalizePersistedUrl(const QString &url) const
{
    for (int index = 0; index < ConfiguredServerCount; ++index) {
        if (m_legacyServerUrls.at(static_cast<std::size_t>(index)).contains(url))
            return serverUrl(index);
    }
    return url;
}

QVariantList ServerDirectory::latencies() const
{
    QVariantList result;
    result.reserve(ServerCount);
    for (const int latency : m_latencyMs)
        result.push_back(latency);
    return result;
}

void ServerDirectory::refreshLatencies()
{
    const quint64 generation = ++m_probeGeneration;
    m_latencyMs.fill(-2);
    emit latenciesChanged();

    for (int index = 0; index < ServerCount; ++index) {
        const QString endpoint = serverUrl(index);
        if (endpoint.isEmpty())
            continue;
        QNetworkRequest request(serverHealthUrl(endpoint));
        request.setTransferTimeout(4000);
        QElapsedTimer timer;
        timer.start();
        QNetworkReply *reply = m_networkManager.get(request);
        network_limits::limitNetworkReply(reply, network_limits::kMaximumHealthResponseBytes);
        connect(reply, &QNetworkReply::finished, this, [this, generation, index, reply, timer]() {
            if (generation != m_probeGeneration) {
                reply->deleteLater();
                return;
            }

            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const bool healthy =
                reply->error() == QNetworkReply::NoError && status >= 200 && status < 400;
            reply->deleteLater();
            m_latencyMs[index] = healthy ? qBound(0, static_cast<int>(timer.elapsed()), 9999) : -1;
            emit latenciesChanged();
        });
    }
}

} // namespace hexproof::client
