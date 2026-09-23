// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#include "ForgeReplayService.h"
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QtEndian>
#include <algorithm>
#include <zlib.h>

namespace hexproof::client {
namespace {
using namespace Qt::StringLiterals;
constexpr qint64 maximumBytes = 128 * 1024 * 1024;
const QByteArray magic("HEXPROOF-REPLAY-1\n");
bool validId(const QString &id)
{
    static const QRegularExpression pattern(u"^[a-f0-9]{64}$"_s);
    return pattern.match(id).hasMatch();
}
QJsonObject portableMetadata(QJsonObject value)
{
    value.remove(u"token"_s);
    value.remove(u"server"_s);
    value.remove(u"local"_s);
    return value;
}
bool save(const QString &path, const QByteArray &bytes)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    return file.write(bytes) == bytes.size() && file.commit();
}
} // namespace

ForgeReplayService::ForgeReplayService(QObject *parent, const QString &directory)
    : QObject(parent),
      m_directory(directory.isEmpty()
                      ? QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation) +
                            u"/replays"_s
                      : directory)
{
    QDir().mkpath(m_directory);
    QFile index(m_directory + u"/index.json"_s);
    if (index.open(QIODevice::ReadOnly) && index.size() <= 2 * 1024 * 1024)
        m_entries = QJsonDocument::fromJson(index.readAll()).array();
    m_timer.setInterval(700);
    m_pageTimer.setSingleShot(true);
    m_pageTimer.setInterval(35); // Leave room in the hub's ordinary message budget.
    connect(&m_pageTimer, &QTimer::timeout, this, &ForgeReplayService::requestNext);
    m_downloadTimeout.setSingleShot(true);
    m_downloadTimeout.setInterval(15000);
    connect(&m_downloadTimeout, &QTimer::timeout, this,
            [this] { fail(tr("The replay download timed out.")); });
    connect(&m_timer, &QTimer::timeout, this, [this] {
        int next = m_position + 1;
        // Empty priority boundaries are retained for manual stepping but folded
        // during playback. Meaningful automatic engine events are never skipped.
        while (next < count() - 1 && m_frames.at(next).toObject().value(u"kind"_s) == u"Decision"_s)
            ++next;
        if (next >= count()) {
            pause();
            return;
        }
        seek(next);
    });
}

QVariantList ForgeReplayService::entries() const
{
    QVariantList result;
    for (const auto &value : m_entries) {
        auto entry = value.toObject();
        entry.remove(u"token"_s);
        entry.insert(u"local"_s, QFile::exists(filePath(entry.value(u"replayId"_s).toString())));
        result.append(entry.toVariantMap());
    }
    return result;
}

QString ForgeReplayService::filePath(const QString &id) const
{
    return validId(id) ? m_directory + u"/"_s + id + u".hpr"_s : QString{};
}

void ForgeReplayService::saveIndex()
{
    while (m_entries.size() > 512)
        m_entries.removeLast();
    if (!save(m_directory + u"/index.json"_s,
              QJsonDocument(m_entries).toJson(QJsonDocument::Compact)))
        fail(tr("Could not save the replay library."));
    emit entriesChanged();
}

void ForgeReplayService::acceptGrant(const QString &server, const QJsonObject &grant)
{
    const QString id = grant.value(u"replayId"_s).toString();
    if (!validId(id) || !validId(grant.value(u"token"_s).toString()) || server.isEmpty())
        return;
    QJsonObject entry = grant;
    entry.insert(u"server"_s, server);
    for (int i = 0; i < m_entries.size(); ++i) {
        const auto old = m_entries[i].toObject();
        if (old.value(u"replayId"_s) == id && old.value(u"server"_s) == server) {
            if (old == entry)
                return;
            m_entries.removeAt(i);
            break;
        }
    }
    m_entries.prepend(entry);
    saveIndex();
}

void ForgeReplayService::download(const QString &id)
{
    if (busy())
        return;
    for (const auto &value : m_entries) {
        const auto entry = value.toObject();
        if (entry.value(u"replayId"_s) != id)
            continue;
        m_downloading = id;
        m_downloadServer = entry.value(u"server"_s).toString();
        m_downloadToken = entry.value(u"token"_s).toString();
        m_received = {};
        m_receivedBytes = 0;
        m_expectedTotal = -1;
        m_error.clear();
        emit statusChanged();
        requestNext();
        return;
    }
    fail(tr("Replay is unavailable."));
}

void ForgeReplayService::requestNext()
{
    if (!busy())
        return;
    m_downloadTimeout.start();
    emit requestPage(m_downloadServer, QJsonObject{{u"replayId"_s, m_downloading},
                                                   {u"token"_s, m_downloadToken},
                                                   {u"offset"_s, m_received.size()}});
}

void ForgeReplayService::acceptPage(const QString &server, const QJsonObject &page)
{
    if (!busy() || server != m_downloadServer || page.value(u"replayId"_s) != m_downloading)
        return;
    const auto frames = page.value(u"frames"_s).toArray();
    const int total = page.value(u"total"_s).toInt(-1);
    if (page.value(u"schemaVersion"_s).toInt() != 1 ||
        page.value(u"offset"_s).toInt(-1) != m_received.size() || total < 1 || total > 20000 ||
        (m_expectedTotal >= 0 && total != m_expectedTotal) || frames.isEmpty() ||
        m_received.size() + frames.size() > total) {
        fail(tr("The replay download is invalid or incomplete."));
        return;
    }
    m_expectedTotal = total;
    m_receivedBytes += QJsonDocument(frames).toJson(QJsonDocument::Compact).size();
    if (m_receivedBytes > maximumBytes) {
        fail(tr("The replay exceeds the size limit."));
        return;
    }
    for (const auto &frame : frames)
        m_received.append(frame);
    if (m_received.size() < total) {
        m_pageTimer.start();
        return;
    }
    QJsonObject metadata;
    for (int i = 0; i < m_entries.size(); ++i) {
        auto entry = m_entries[i].toObject();
        if (entry.value(u"replayId"_s) != m_downloading || entry.value(u"server"_s) != server)
            continue;
        entry.insert(u"finished"_s, true);
        entry.insert(u"complete"_s, page.value(u"complete"_s));
        entry.insert(u"frameCount"_s, total);
        m_entries.replace(i, entry);
        metadata = portableMetadata(entry);
        break;
    }
    const QString id = m_downloading;
    m_downloadTimeout.stop();
    m_downloading.clear();
    m_downloadToken.clear();
    const QJsonObject document{
        {u"schemaVersion"_s, 1}, {u"metadata"_s, metadata}, {u"frames"_s, m_received}};
    m_received = {};
    if (load(document) && writeFile(filePath(id)))
        saveIndex();
    emit statusChanged();
}

bool ForgeReplayService::load(const QJsonObject &document)
{
    const auto frames = document.value(u"frames"_s).toArray();
    const auto metadata = document.value(u"metadata"_s).toObject();
    if (document.value(u"schemaVersion"_s).toInt() != 1 || frames.isEmpty() ||
        frames.size() > 20000 || !validId(metadata.value(u"replayId"_s).toString()) ||
        !metadata.value(u"finished"_s).toBool()) {
        fail(tr("This is not a supported finished Forge replay."));
        return false;
    }
    for (int i = 0; i < frames.size(); ++i) {
        const auto frame = frames.at(i).toObject();
        const auto snapshot = frame.value(u"snapshot"_s).toObject();
        if (frame.value(u"sequence"_s).toInteger() != i + 1 ||
            snapshot.value(u"gameId"_s).toString().isEmpty() ||
            snapshot.value(u"roomId"_s).toString().isEmpty() ||
            snapshot.value(u"players"_s).toArray().size() != 2 ||
            !snapshot.value(u"zones"_s).isArray() || !snapshot.value(u"stack"_s).isArray()) {
            fail(tr("The replay contains an invalid frame."));
            return false;
        }
    }
    pause();
    m_frames = frames;
    m_metadata = portableMetadata(metadata);
    m_position = -1;
    m_error.clear();
    emit loaded();
    seek(0);
    emit statusChanged();
    return true;
}

bool ForgeReplayService::readFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly) || file.size() > maximumBytes ||
        file.size() < magic.size() + 4) {
        fail(tr("Could not open the replay file."));
        return false;
    }
    const QByteArray bytes = file.readAll();
    if (!bytes.startsWith(magic) ||
        qFromBigEndian<quint32>(bytes.constData() + magic.size()) > maximumBytes) {
        fail(tr("The replay file is invalid or too large."));
        return false;
    }
    // qUncompress treats the length prefix as a hint and can grow beyond it.
    // Bound the actual zlib output, including when a file lies about its size.
    const quint32 declaredSize = qFromBigEndian<quint32>(bytes.constData() + magic.size());
    QByteArray raw(declaredSize, Qt::Uninitialized);
    uLongf outputSize = declaredSize;
    const int result =
        uncompress(reinterpret_cast<Bytef *>(raw.data()), &outputSize,
                   reinterpret_cast<const Bytef *>(bytes.constData() + magic.size() + 4),
                   bytes.size() - magic.size() - 4);
    if (result != Z_OK || outputSize != declaredSize) {
        fail(tr("The replay file is invalid or too large."));
        return false;
    }
    const auto document = QJsonDocument::fromJson(raw);
    return load(document.object());
}

bool ForgeReplayService::writeFile(const QString &path)
{
    const QJsonObject document{{u"schemaVersion"_s, 1},
                               {u"metadata"_s, portableMetadata(m_metadata)},
                               {u"frames"_s, m_frames}};
    if (m_frames.isEmpty() ||
        !save(path, magic + qCompress(QJsonDocument(document).toJson(QJsonDocument::Compact), 6))) {
        fail(tr("Could not save the replay file."));
        return false;
    }
    return true;
}

bool ForgeReplayService::open(const QString &id)
{
    return readFile(filePath(id));
}
bool ForgeReplayService::importFile(const QUrl &url)
{
    if (!url.isLocalFile() || !readFile(url.toLocalFile()))
        return false;
    const QString id = m_metadata.value(u"replayId"_s).toString();
    if (!writeFile(filePath(id)))
        return false;
    bool exists = false;
    for (const auto &entry : m_entries)
        exists |= entry.toObject().value(u"replayId"_s) == id;
    if (!exists)
        m_entries.prepend(m_metadata);
    saveIndex();
    return true;
}
bool ForgeReplayService::exportFile(const QUrl &url)
{
    return url.isLocalFile() && writeFile(url.toLocalFile());
}
QVariantMap ForgeReplayService::frame() const
{
    return m_position >= 0 ? m_frames.at(m_position).toObject().toVariantMap() : QVariantMap{};
}
QVariantList ForgeReplayService::events() const
{
    QVariantList result;
    for (int i = 0; i < m_frames.size(); ++i) {
        const auto f = m_frames.at(i).toObject();
        const auto s = f.value(u"snapshot"_s).toObject();
        result.append(QVariantMap{{u"index"_s, i},
                                  {u"text"_s, f.value(u"text"_s).toString()},
                                  {u"kind"_s, f.value(u"kind"_s).toString()},
                                  {u"elapsedMs"_s, f.value(u"elapsedMs"_s).toInteger()},
                                  {u"actorSeat"_s, f.value(u"actorSeat"_s).toInt(-1)},
                                  {u"turn"_s, s.value(u"turn"_s).toInt()},
                                  {u"activeSeat"_s, s.value(u"activeSeat"_s).toInt()},
                                  {u"gameNumber"_s, f.value(u"gameNumber"_s).toInt()},
                                  {u"step"_s, s.value(u"step"_s).toString()}});
    }
    return result;
}
void ForgeReplayService::seek(int position)
{
    if (position < 0 || position >= count())
        return;
    if (!m_session.applySnapshot(m_frames.at(position).toObject().value(u"snapshot"_s).toObject()))
        return;
    m_position = position;
    emit positionChanged();
}
void ForgeReplayService::step(int delta)
{
    pause();
    seek(std::clamp(m_position + delta, 0, std::max(0, count() - 1)));
}
void ForgeReplayService::nextTurn(int direction)
{
    pause();
    if (m_position < 0 || direction == 0)
        return;
    const auto current = m_frames.at(m_position).toObject().value(u"snapshot"_s).toObject();
    const int step = direction > 0 ? 1 : -1;
    for (int i = m_position + step; i >= 0 && i < count(); i += step) {
        const auto snapshot = m_frames.at(i).toObject().value(u"snapshot"_s).toObject();
        if (snapshot.value(u"turn"_s) != current.value(u"turn"_s) ||
            snapshot.value(u"gameId"_s) != current.value(u"gameId"_s)) {
            if (step < 0)
                while (i > 0) {
                    const auto prior =
                        m_frames.at(i - 1).toObject().value(u"snapshot"_s).toObject();
                    if (prior.value(u"turn"_s) != snapshot.value(u"turn"_s) ||
                        prior.value(u"gameId"_s) != snapshot.value(u"gameId"_s))
                        break;
                    --i;
                }
            seek(i);
            return;
        }
    }
}
void ForgeReplayService::togglePlaying()
{
    if (playing())
        pause();
    else if (count() > 0) {
        if (m_position == count() - 1)
            seek(0);
        m_timer.start();
        emit playingChanged();
    }
}
void ForgeReplayService::pause()
{
    if (playing()) {
        m_timer.stop();
        emit playingChanged();
    }
}
void ForgeReplayService::setSpeed(double speed)
{
    m_speed = std::clamp(speed, 0.25, 8.0);
    m_timer.setInterval(qRound(700 / m_speed));
    emit playingChanged();
}
void ForgeReplayService::fail(const QString &message)
{
    m_pageTimer.stop();
    m_downloadTimeout.stop();
    m_downloading.clear();
    m_downloadToken.clear();
    m_received = {};
    m_error = message;
    emit statusChanged();
}
} // namespace hexproof::client
