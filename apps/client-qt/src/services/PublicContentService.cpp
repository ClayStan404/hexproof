// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "PublicContentService.h"

#include "NetworkLimits.h"
#include "PublicContentSchema.h"

#include <QBuffer>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QSaveFile>

static void initializePublicContentResources()
{
    Q_INIT_RESOURCE(content_defaults);
}

namespace hexproof::client {
namespace {
using namespace Qt::StringLiterals;
using namespace public_content;

constexpr qint64 maximumCacheBytes = 16 * 1024 * 1024;

QByteArray readFile(const QString &path, qint64 limit)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly) || file.size() > limit)
        return {};
    return file.read(limit + 1);
}

bool writeFile(const QString &path, const QByteArray &bytes)
{
    if (bytes.size() > maximumCacheBytes || !QDir().mkpath(QFileInfo(path).absolutePath()))
        return false;
    QSaveFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size() && file.commit();
}

bool validAvatar(const QByteArray &bytes, const QString &hash)
{
    if (bytes.isEmpty() || bytes.size() > maximumAvatarBytes || digest(bytes) != hash.toLatin1())
        return false;
    QBuffer buffer;
    buffer.setData(bytes);
    buffer.open(QIODevice::ReadOnly);
    QImageReader reader(&buffer);
    const auto size = reader.size();
    const auto format = reader.format();
    return (format == "png" || format == "jpeg" || format == "webp") && size.width() > 0 &&
           size.height() > 0 && size.width() <= 2048 && size.height() <= 2048 &&
           !reader.read().isNull();
}

QJsonObject readObject(const QString &path)
{
    return QJsonDocument::fromJson(readFile(path, maximumCacheBytes)).object();
}

const QStringList kinds = {u"sponsors"_s, u"announcements"_s};
} // namespace

QStringList PublicContentService::defaultSources()
{
    if (qEnvironmentVariableIsSet("HEXPROOF_CONTENT_INDEX_URL")) {
        const QUrl url(qEnvironmentVariable("HEXPROOF_CONTENT_INDEX_URL"), QUrl::StrictMode);
        return validSource(url) ? QStringList{url.toString()} : QStringList{};
    }
    const auto bootstrap = readObject(u":/config/servers.json"_s);
    QStringList sources;
    for (const auto &value : bootstrap.value(u"directoryUrls"_s).toArray()) {
        const QUrl source(value.toString(), QUrl::StrictMode);
        if (validSource(source) && sources.size() < 4)
            sources.append(source.resolved(QUrl(u"content/index.json"_s)).toString());
    }
    return sources;
}

PublicContentService::PublicContentService(const QString &storageRoot, QObject *parent)
    : PublicContentService(storageRoot, defaultSources(), parent)
{
}

PublicContentService::PublicContentService(const QString &storageRoot, const QStringList &sources,
                                           QObject *parent)
    : QObject(parent)
{
    initializePublicContentResources();
    for (const auto &source : sources) {
        if (validSource(QUrl(source, QUrl::StrictMode)) && !m_sources.contains(source) &&
            m_sources.size() < 4)
            m_sources.append(source);
    }
    const auto scope = QString::fromLatin1(digest(m_sources.join(u'\n').toUtf8()).left(16));
    m_root = QDir(storageRoot).filePath(u"public-content/"_s + scope);
    load(storageRoot);
    m_refreshTimer.setInterval(30 * 60 * 1000);
    connect(&m_refreshTimer, &QTimer::timeout, this, [this]() { refresh(); });
    m_displayTimer.setInterval(60 * 1000);
    connect(&m_displayTimer, &QTimer::timeout, this, &PublicContentService::contentChanged);
}

QString PublicContentService::cachePath(const QString &name) const
{
    return QDir(m_root).filePath(u"cache/"_s + name);
}

QString PublicContentService::avatarPath(const QString &hash) const
{
    return cachePath(u"avatars/"_s + hash + u".image"_s);
}

void PublicContentService::load(const QString &storageRoot)
{
    for (const auto &kind : kinds) {
        const auto bytes =
            readFile(u":/config/content/"_s + kind + u".json"_s, maximumDocumentBytes);
        const auto document = QJsonDocument::fromJson(bytes).object();
        if (validDocument(kind, document)) {
            m_documents.insert(kind, document);
            m_hashes.insert(kind, QString::fromLatin1(digest(bytes)));
        }
    }
    const auto bundled = m_documents.value(u"sponsors"_s).value(u"sponsors"_s).toArray();
    for (const auto &value : bundled) {
        const auto avatar = value.toObject().value(u"avatar"_s).toObject();
        const auto name = QFileInfo(avatar.value(u"path"_s).toString()).fileName();
        const auto hash = avatar.value(u"sha256"_s).toString();
        const auto path = u":/assets/sponsors/"_s + name;
        if (validAvatar(readFile(path, maximumAvatarBytes), hash))
            m_bundledAvatars.insert(hash, u"qrc"_s + path);
    }
    m_state = readObject(QDir(m_root).filePath(u"state.json"_s));
    if (!m_state.contains(u"seenSponsors"_s)) {
        const auto preferences = readObject(QDir(storageRoot).filePath(u"settings.json"_s));
        QJsonObject seen;
        if (!preferences.value(u"sponsorAnnouncementId"_s).toString().isEmpty()) {
            for (const auto &value : bundled)
                seen.insert(value.toObject().value(u"id"_s).toString(), true);
        }
        auto next = m_state;
        next.insert(u"seenSponsors"_s, seen);
        saveState(next);
    }
    const auto cachedIndex = readObject(cachePath(u"index.json"_s));
    if (validIndex(cachedIndex.value(u"document"_s).toObject())) {
        m_index = cachedIndex.value(u"document"_s).toObject();
        m_etags = cachedIndex.value(u"etags"_s).toObject();
    }
    for (const auto &kind : kinds) {
        const bool previouslyInstalled =
            m_state.value(u"installedRevisions"_s).toObject().value(kind).toInteger() > 0;
        if (previouslyInstalled) {
            // A damaged/cleared cache must not resurrect retired bundled sponsors.
            m_documents.remove(kind);
            m_hashes.remove(kind);
        }
        const auto cached = readObject(cachePath(kind + u".json"_s));
        const auto payload =
            QByteArray::fromBase64(cached.value(u"payload"_s).toString().toLatin1());
        const auto document = QJsonDocument::fromJson(payload).object();
        const QUrl source(cached.value(u"source"_s).toString(), QUrl::StrictMode);
        bool trusted = false;
        for (const auto &indexUrl : m_sources) {
            const auto base = QUrl(indexUrl).resolved(QUrl(u"."_s)).toString();
            trusted |= source.toString().startsWith(base);
        }
        if (payload.size() > maximumDocumentBytes || !trusted || !validSource(source) ||
            digest(payload) != cached.value(u"sha256"_s).toString().toLatin1() ||
            !validDocument(kind, document) ||
            document.value(u"revision"_s).toInteger() <
                m_state.value(u"installedRevisions"_s).toObject().value(kind).toInteger())
            continue;
        // A valid online snapshot wins over bundled display data, including an empty roster.
        m_documents.insert(kind, document);
        m_hashes.insert(kind, QString::fromLatin1(digest(payload)));
        m_documentUrls.insert(kind, source);
        if (kind == u"announcements"_s) {
            const auto history = cached.value(u"archive"_s).toObject();
            for (auto it = history.begin(); it != history.end(); ++it) {
                if (validAnnouncement(it.value().toObject()) &&
                    it.value().toObject().value(u"id"_s).toString() == it.key())
                    m_archive.insert(it.key(), it.value());
            }
        }
    }
    pruneAvatars();
    for (const auto &value : m_documents.value(u"sponsors"_s).value(u"sponsors"_s).toArray()) {
        const auto hash =
            value.toObject().value(u"avatar"_s).toObject().value(u"sha256"_s).toString();
        if (validHash(hash) && validAvatar(readFile(avatarPath(hash), maximumAvatarBytes), hash))
            m_validAvatars.insert(hash);
    }
}

void PublicContentService::start()
{
    if (m_started)
        return;
    m_started = true;
    m_refreshTimer.start();
    m_displayTimer.start();
    // Only startup notices wait briefly; the main window always uses local content immediately.
    QTimer::singleShot(4000, this, &PublicContentService::readyForStartup);
    refresh();
}

void PublicContentService::readyForStartup()
{
    if (!m_startupReady) {
        m_startupReady = true;
        emit startupReadyChanged();
    }
}

QNetworkReply *PublicContentService::get(const QUrl &url, qint64 limit, const QByteArray &etag,
                                         ReplyHandler handler)
{
    QNetworkRequest request(url);
    request.setTransferTimeout(5000);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::SameOriginRedirectPolicy);
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute,
                         QNetworkRequest::AlwaysNetwork);
    request.setRawHeader("Accept", "application/json, image/png, image/jpeg, image/webp");
    if (!etag.isEmpty() && etag.size() <= 512 && !etag.contains('\r') && !etag.contains('\n'))
        request.setRawHeader("If-None-Match", etag);
    auto *reply = m_network.get(request);
    network_limits::limitNetworkReply(reply, limit);
    QTimer::singleShot(5000, reply, [reply]() {
        if (reply->isRunning())
            reply->abort();
    });
    connect(reply, &QNetworkReply::finished, this, [reply, handler = std::move(handler)]() {
        const int status = reply->error() == QNetworkReply::NoError
                               ? reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt()
                               : 0;
        const auto bytes = reply->isOpen() ? reply->readAll() : QByteArray{};
        const auto responseEtag = reply->rawHeader("ETag");
        reply->deleteLater();
        handler(status, bytes, responseEtag);
    });
    return reply;
}

void PublicContentService::refresh(bool force)
{
    if (m_refreshing ||
        (!force && m_lastAttempt.isValid() && m_lastAttempt.elapsed() < 5 * 60 * 1000))
        return;
    if (m_sources.isEmpty()) {
        readyForStartup();
        return;
    }
    m_lastAttempt.start();
    m_refreshing = true;
    m_refreshFailed = false;
    emit statusChanged();
    fetchIndex(0);
}

void PublicContentService::fetchIndex(int source)
{
    if (source >= m_sources.size()) {
        m_refreshFailed = true;
        finishRefresh();
        return;
    }
    const auto url = m_sources[source];
    const auto etag = m_index.isEmpty() ? QByteArray{} : m_etags.value(url).toString().toLatin1();
    get(QUrl(url), maximumIndexBytes, etag,
        [this, source, url](int status, const QByteArray &bytes, const QByteArray &etag) {
            if (status == 304 && !m_index.isEmpty()) {
                fetchDocument(source, 0);
                return;
            }
            const auto document = QJsonDocument::fromJson(bytes).object();
            const auto revision = document.value(u"revision"_s).toInteger();
            const auto oldRevision = m_index.value(u"revision"_s).toInteger();
            if (status != 200 || !validIndex(document) || revision < oldRevision ||
                (revision == oldRevision && document != m_index)) {
                fetchIndex(source + 1);
                return;
            }
            if (document != m_index)
                m_etags = {};
            m_index = document;
            m_etags.insert(url, QString::fromLatin1(etag));
            writeFile(cachePath(u"index.json"_s),
                      QJsonDocument(QJsonObject{{u"document"_s, m_index}, {u"etags"_s, m_etags}})
                          .toJson());
            fetchDocument(source, 0);
        });
}

void PublicContentService::fetchDocument(int source, int kindIndex)
{
    if (kindIndex >= kinds.size()) {
        finishRefresh();
        return;
    }
    const auto kind = kinds[kindIndex];
    const auto descriptor = m_index.value(kind).toObject();
    const auto installed =
        std::max(m_documents.value(kind).value(u"revision"_s).toInteger(),
                 m_state.value(u"installedRevisions"_s).toObject().value(kind).toInteger());
    if (descriptor.value(u"revision"_s).toInteger() < installed) {
        m_refreshFailed = true;
        fetchDocument(source, kindIndex + 1);
        return;
    }
    if (m_hashes.value(kind) == descriptor.value(u"sha256"_s).toString()) {
        fetchDocument(source, kindIndex + 1);
        return;
    }
    const QUrl url = QUrl(m_sources[source]).resolved(QUrl(descriptor.value(u"path"_s).toString()));
    get(url, maximumDocumentBytes, {},
        [this, source, kindIndex, kind, descriptor, url](int status, const QByteArray &bytes,
                                                         const QByteArray &) {
            if (status != 200 || !installDocument(kind, bytes, descriptor, url))
                m_refreshFailed = true;
            fetchDocument(source, kindIndex + 1);
        });
}

bool PublicContentService::installDocument(const QString &kind, const QByteArray &payload,
                                           const QJsonObject &descriptor, const QUrl &url)
{
    const auto document = QJsonDocument::fromJson(payload).object();
    const auto previous = m_documents.value(kind);
    const auto revision = document.value(u"revision"_s).toInteger();
    if (digest(payload) != descriptor.value(u"sha256"_s).toString().toLatin1() ||
        !validDocument(kind, document) || revision != descriptor.value(u"revision"_s).toInteger() ||
        revision < previous.value(u"revision"_s).toInteger() ||
        (revision == previous.value(u"revision"_s).toInteger() && document != previous))
        return false;
    auto archive = m_archive;
    if (kind == u"announcements"_s) {
        for (const auto &entry : previous.value(kind).toArray())
            archive.insert(entry.toObject().value(u"id"_s).toString(), entry);
        for (const auto &entry : document.value(kind).toArray()) {
            const auto object = entry.toObject();
            const auto id = object.value(u"id"_s).toString();
            if (object.value(u"notificationRevision"_s).toInteger() <
                archive.value(id).toObject().value(u"notificationRevision"_s).toInteger())
                return false;
            archive.remove(id);
        }
    }
    QJsonObject cache{{u"payload"_s, QString::fromLatin1(payload.toBase64())},
                      {u"sha256"_s, QString::fromLatin1(digest(payload))},
                      {u"source"_s, url.toString()}};
    if (kind == u"announcements"_s)
        cache.insert(u"archive"_s, archive);
    if (!writeFile(cachePath(kind + u".json"_s), QJsonDocument(cache).toJson()))
        return false;
    m_documents.insert(kind, document);
    m_hashes.insert(kind, QString::fromLatin1(digest(payload)));
    m_documentUrls.insert(kind, url);
    auto nextState = m_state;
    auto revisions = nextState.value(u"installedRevisions"_s).toObject();
    revisions.insert(kind, revision);
    nextState.insert(u"installedRevisions"_s, revisions);
    saveState(nextState);
    if (kind == u"announcements"_s)
        m_archive = archive;
    else {
        // Roster snapshots replace, never merge. Cancel obsolete downloads before pruning.
        ++m_avatarGeneration;
        m_avatarQueue.clear();
        if (m_avatarReply)
            m_avatarReply->abort();
        m_avatarReply = nullptr;
        pruneAvatars();
    }
    emit contentChanged();
    return true;
}

void PublicContentService::finishRefresh()
{
    m_refreshing = false;
    if (!m_refreshFailed)
        m_lastChecked = QDateTime::currentDateTimeUtc();
    emit statusChanged();
    readyForStartup();
    refreshAvatars();
}

void PublicContentService::pruneAvatars()
{
    QSet<QString> keep;
    for (const auto &entry : m_documents.value(u"sponsors"_s).value(u"sponsors"_s).toArray())
        keep.insert(entry.toObject().value(u"avatar"_s).toObject().value(u"sha256"_s).toString());
    const QDir directory(cachePath(u"avatars"_s));
    for (const auto &name : directory.entryList({u"*.image"_s}, QDir::Files)) {
        const auto hash = name.chopped(6);
        if (validHash(hash) && !keep.contains(hash)) {
            QFile::remove(directory.filePath(name));
            m_validAvatars.remove(hash);
        }
    }
}

void PublicContentService::refreshAvatars()
{
    if (m_avatarReply || !m_documentUrls.contains(u"sponsors"_s))
        return;
    m_avatarQueue.clear();
    QSet<QString> queued;
    for (const auto &entry : m_documents.value(u"sponsors"_s).value(u"sponsors"_s).toArray()) {
        const auto avatar = entry.toObject().value(u"avatar"_s).toObject();
        const auto hash = avatar.value(u"sha256"_s).toString();
        if (!validHash(hash) || m_bundledAvatars.contains(hash) || queued.contains(hash))
            continue;
        if (validAvatar(readFile(avatarPath(hash), maximumAvatarBytes), hash)) {
            m_validAvatars.insert(hash);
            continue;
        }
        m_validAvatars.remove(hash);
        QFile::remove(avatarPath(hash));
        queued.insert(hash);
        m_avatarQueue.append({hash, m_documentUrls.value(u"sponsors"_s)
                                        .resolved(QUrl(avatar.value(u"path"_s).toString()))});
    }
    emit contentChanged();
    nextAvatar();
}

void PublicContentService::nextAvatar()
{
    if (m_avatarQueue.isEmpty())
        return;
    const auto avatar = m_avatarQueue.takeFirst();
    const auto generation = m_avatarGeneration;
    m_avatarReply =
        get(avatar.url, maximumAvatarBytes, {},
            [this, avatar, generation](int status, const QByteArray &bytes, const QByteArray &) {
                if (generation != m_avatarGeneration)
                    return;
                m_avatarReply = nullptr;
                if (status == 200 && validAvatar(bytes, avatar.hash) &&
                    writeFile(avatarPath(avatar.hash), bytes)) {
                    m_validAvatars.insert(avatar.hash);
                    emit contentChanged();
                }
                nextAvatar();
            });
}

bool PublicContentService::saveState(const QJsonObject &next)
{
    if (!writeFile(QDir(m_root).filePath(u"state.json"_s), QJsonDocument(next).toJson()))
        return false;
    m_state = next;
    emit contentChanged();
    return true;
}
} // namespace hexproof::client
