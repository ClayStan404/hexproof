// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#include "FeedbackService.h"
#include <QDir>
#include <QFile>
#include <QFutureWatcher>
#include <QJsonDocument>
#include <QRandomGenerator>
#include <QtConcurrentRun>
#include <algorithm>

namespace hexproof::client {
using namespace Qt::StringLiterals;
void FeedbackService::load()
{
    struct Loaded
    {
        QList<feedback::Record> records;
        bool ok = true;
    };
    auto *watcher = new QFutureWatcher<Loaded>(this);
    connect(watcher, &QFutureWatcher<Loaded>::finished, this, [this, watcher] {
        const auto result = watcher->result();
        watcher->deleteLater();
        m_loading = false;
        for (auto r : result.records) {
            bool dirty = false;
            if (r.state == u"sending") {
                r.state = u"unconfirmed"_s;
                dirty = true;
            }
            if (r.authorized && (r.apiVersion != 2 || !m_enabled || r.endpoint != m_apiBase)) {
                r.authorized = false;
                r.reason = r.apiVersion == 1 ? u"legacy_private"_s : u"endpoint_changed"_s;
                r.state = r.dispatched ? u"unconfirmed"_s : u"needs_attention"_s;
                dirty = true;
            }
            if (r.authorized) {
                const auto wake = QDateTime::currentDateTimeUtc().addMSecs(
                    1000 + QRandomGenerator::global()->bounded(4000));
                if (!r.nextAttempt.isValid() || r.nextAttempt < wake)
                    r.nextAttempt = wake;
                dirty = true;
            }
            if (r.removalAuthorized && !trustedQuery(r.endpoint)) {
                r.removalAuthorized = false;
                r.removalState = u"stalled"_s;
                r.reason = u"endpoint_untrusted"_s;
                dirty = true;
            }
            if (r.closureAuthorized && (!trustedQuery(r.endpoint) || r.removalState != u"none" ||
                                        r.caseState == u"closed")) {
                r.closureAuthorized = false;
                r.closureRequestState = r.caseState == u"closed" ? u"none"_s : u"stalled"_s;
                if (!trustedQuery(r.endpoint))
                    r.reason = u"endpoint_untrusted"_s;
                dirty = true;
            }
            m_records.insert(r.id, r);
            m_generation[r.id] = 1;
            m_persisted[r.id] = 1;
            if (dirty) {
                ++m_generation[r.id];
                m_dirty.insert(r.id);
            }
        }
        for (auto it = m_records.begin(); it != m_records.end(); ++it) {
            bool dirty = false;
            if (it->authorized && !replyAllowed(*it)) {
                it->authorized = false;
                it->state = it->dispatched ? u"unconfirmed"_s : u"needs_attention"_s;
                it->reason = u"parent_unavailable"_s;
                dirty = true;
            }
            const auto parentRemoval = m_records.value(it->parentId).removalState;
            if (!it->parentId.isEmpty() && parentRemoval != u"none" &&
                it->removalState != u"removed" && it->removalState != parentRemoval) {
                it->removalState = parentRemoval;
                dirty = true;
            }
            const auto parent = m_records.constFind(it->parentId);
            if (!it->parentId.isEmpty() && parent != m_records.cend() &&
                (it->caseState != parent->caseState ||
                 it->closureRequestState != parent->closureRequestState ||
                 it->closurePublicationState != parent->closurePublicationState ||
                 it->closedAt != parent->closedAt || it->closureReason != parent->closureReason)) {
                it->caseState = parent->caseState;
                it->closureRequestState = parent->closureRequestState;
                it->closurePublicationState = parent->closurePublicationState;
                it->closedAt = parent->closedAt;
                it->closureReason = parent->closureReason;
                dirty = true;
            }
            if (dirty) {
                ++m_generation[it.key()];
                m_dirty.insert(it.key());
            }
        }
        if (!result.ok) {
            m_storageFailed = true;
            fail(u"storage_unavailable"_s);
        }
        prune();
        emit changed();
        emit statusChanged();
        writeNext();
    });
    const auto dir = m_directory;
    watcher->setFuture(QtConcurrent::run(&m_io, [dir] {
        Loaded out;
        QDir directory(dir);
        const auto files =
            directory.entryInfoList({u"*.json"_s}, QDir::Files | QDir::NoSymLinks, QDir::Name);
        if (files.size() > 120) {
            out.ok = false;
            return out;
        }
        qsizetype bytes = 0;
        for (const auto &info : files) {
            const auto prefix = directory.filePath(info.baseName());
            if (QFile::exists(prefix + u".deleted"_s)) {
                QFile marker(prefix + u".deleted"_s);
                if (QFileInfo(marker).isFile() && marker.open(QIODevice::ReadOnly) &&
                    marker.size() == 7 && marker.readAll() == "deleted") {
                    if (QFile::remove(info.filePath())) {
                        QFile::remove(prefix + u".revoked"_s);
                        QFile::remove(prefix + u".removal"_s);
                        QFile::remove(prefix + u".closure"_s);
                        QFile::remove(prefix + u".deleted"_s);
                    }
                    continue;
                }
                out.ok = false;
            }
            QFile file(info.filePath());
            if (info.size() > 8 * 1024 * 1024 || !file.open(QIODevice::ReadOnly)) {
                out.ok = false;
                continue;
            }
            auto record = feedback::decode(QJsonDocument::fromJson(file.readAll()).object());
            if (!record || info.baseName() != record->id) {
                out.ok = false;
                continue;
            }
            QFile revoked(prefix + u".revoked"_s);
            if (revoked.exists()) {
                if (!revoked.open(QIODevice::ReadOnly) || revoked.size() != 64) {
                    out.ok = false;
                    record->authorized = false;
                } else if (revoked.readAll() == feedback::revocationDigest(*record)) {
                    record->authorized = false;
                    record->reason = u"stopped"_s;
                    if (record->state != u"received" && record->state != u"accepted" &&
                        record->state != u"draft")
                        record->state =
                            record->dispatched ? u"unconfirmed"_s : u"needs_attention"_s;
                }
            }
            QFile removal(prefix + u".removal"_s);
            if (removal.exists()) {
                if (!removal.open(QIODevice::ReadOnly) || removal.size() > 512) {
                    out.ok = false;
                } else {
                    const auto journal = QJsonDocument::fromJson(removal.readAll()).object();
                    const auto requested =
                        QDateTime::fromString(journal.value(u"requestedAt"_s).toString(),
                                              Qt::ISODateWithMs)
                            .toUTC();
                    if (record->apiVersion != 2 || !requested.isValid() ||
                        journal.value(u"secretDigest"_s).toString().toLatin1() !=
                            feedback::digest(record->secret)) {
                        out.ok = false;
                    } else if (record->removalRequestedAt < requested ||
                               !record->removalRequestedAt.isValid()) {
                        record->removalAuthorized = true;
                        record->removalState = u"requested"_s;
                        record->removalRequestedAt = requested;
                        record->removalAttempts = 0;
                        record->nextAttempt = requested;
                        record->authorized = false;
                    }
                }
            }
            QFile closure(prefix + u".closure"_s);
            if (closure.exists()) {
                if (!closure.open(QIODevice::ReadOnly) || closure.size() > 512) {
                    out.ok = false;
                } else {
                    const auto journal = QJsonDocument::fromJson(closure.readAll()).object();
                    const auto requested =
                        QDateTime::fromString(journal.value(u"requestedAt"_s).toString(),
                                              Qt::ISODateWithMs)
                            .toUTC();
                    if (record->apiVersion != 2 || !record->parentId.isEmpty() ||
                        !requested.isValid() ||
                        journal.value(u"secretDigest"_s).toString().toLatin1() !=
                            feedback::digest(record->secret)) {
                        out.ok = false;
                    } else if (record->caseState != u"closed" && record->removalState == u"none" &&
                               (!record->closureRequestedAt.isValid() ||
                                record->closureRequestedAt < requested)) {
                        record->closureAuthorized = true;
                        record->closureRequestState = u"requested"_s;
                        record->closureRequestedAt = requested;
                        record->closureAttempts = 0;
                        record->nextAttempt = requested;
                        record->authorized = false;
                    }
                }
            }
            for (const auto &a : record->attachments)
                bytes += a.bytes.size();
            bytes += record->description.toUtf8().size() + record->manifest.size();
            bytes += QJsonDocument(record->threadPage).toJson(QJsonDocument::Compact).size();
            if (bytes > feedback::MaxStoreBytes) {
                out.ok = false;
                break;
            }
            out.records.append(*record);
        }
        return out;
    }));
}
void FeedbackService::changedRecord(const QString &id)
{
    ++m_generation[id];
    m_dirty.insert(id);
    emit changed();
    emit statusChanged();
    writeNext();
}
void FeedbackService::writeNext()
{
    if (m_loading || m_writing || m_storageFailed || (m_dirty.isEmpty() && m_deleting.isEmpty()))
        return;
    const bool deleting = !m_deleting.isEmpty();
    const QString id = deleting ? *m_deleting.begin() : *m_dirty.begin();
    if (!deleting && !m_records.contains(id)) {
        m_dirty.remove(id);
        writeNext();
        return;
    }
    const quint64 generation = m_generation.value(id);
    const auto record = m_records.value(id);
    const auto path = m_directory + u"/"_s + id + u".json"_s;
    m_writing = true;
    emit statusChanged();
    auto *watcher = new QFutureWatcher<bool>(this);
    connect(watcher, &QFutureWatcher<bool>::finished, this,
            [this, watcher, id, generation, deleting] {
                const bool ok = watcher->result();
                watcher->deleteLater();
                m_writing = false;
                if (!ok) {
                    m_storageFailed = true;
                    fail(u"storage_unavailable"_s);
                } else if (deleting) {
                    m_deleting.remove(id);
                    m_generation.remove(id);
                    m_persisted.remove(id);
                } else if (m_records.contains(id)) {
                    m_persisted[id] = generation;
                    if (m_generation.value(id) == generation)
                        m_dirty.remove(id);
                }
                emit statusChanged();
                writeNext();
                if (!m_dispatchId.isEmpty() &&
                    m_persisted.value(m_dispatchId) == m_generation.value(m_dispatchId) &&
                    !m_storageFailed)
                    dispatch();
                pump();
            });
    watcher->setFuture(QtConcurrent::run(&m_io, [path, record, deleting] {
        if (deleting) {
            const bool ok = !QFile::exists(path) || QFile::remove(path);
            if (ok) {
                const auto prefix = path.chopped(5);
                QFile::remove(prefix + u".revoked"_s);
                QFile::remove(prefix + u".removal"_s);
                QFile::remove(prefix + u".closure"_s);
                QFile::remove(prefix + u".deleted"_s);
            }
            return ok;
        }
        return feedback::writePrivate(
            path, QJsonDocument(feedback::encode(record, true)).toJson(QJsonDocument::Compact));
    }));
}
void FeedbackService::retryStorage()
{
    if (!m_lock || !m_lock->isLocked()) {
        fail(u"storage_unavailable"_s);
        return;
    }
    m_storageFailed = false;
    m_error.clear();
    emit statusChanged();
    writeNext();
}
qsizetype FeedbackService::payloadBytes() const
{
    qsizetype total = 0;
    for (const auto &r : m_records) {
        total += r.description.toUtf8().size() + r.manifest.size();
        total += QJsonDocument(r.threadPage).toJson(QJsonDocument::Compact).size();
        for (const auto &a : r.attachments)
            total += a.bytes.size();
    }
    return total;
}
void FeedbackService::prune(qsizetype additionalBytes)
{
    const auto now = QDateTime::currentDateTimeUtc();
    QList<feedback::Record> received;
    for (const auto &r : m_records)
        if (r.state == u"received" || r.state == u"accepted")
            received.append(r);
    std::sort(received.begin(), received.end(),
              [](const auto &a, const auto &b) { return a.acceptedAt < b.acceptedAt; });
    int count = received.size();
    for (const auto &old : received) {
        if (!m_records.contains(old.id))
            continue;
        const auto current = m_records.value(old.id);
        const bool legacyExpired =
            old.apiVersion == 1 && (old.acceptedAt.addDays(90) <= now || count > 100);
        const bool publicExpired = current.apiVersion == 2 && current.accessExpiresAt.isValid() &&
                                   current.accessExpiresAt <= now &&
                                   current.removalState == u"removed";
        if (legacyExpired || publicExpired) {
            deleteRecord(old.id);
            --count;
            continue;
        }
        if (old.payloadAvailable && (old.acceptedAt.addDays(30) <= now ||
                                     payloadBytes() + additionalBytes > feedback::MaxStoreBytes)) {
            auto &r = m_records[old.id];
            r.attachments.clear();
            r.manifest.clear();
            r.email.clear();
            r.description = r.description.left(160);
            r.payloadAvailable = false;
            changedRecord(r.id);
        }
        if (!old.threadPage.isEmpty() &&
            (!old.threadSyncedAt.isValid() || old.threadSyncedAt.addDays(30) <= now ||
             payloadBytes() + additionalBytes > feedback::MaxStoreBytes)) {
            // Public conversation snapshots are replaceable cache. Reclaim
            // them independently from the capability needed to refresh later.
            auto &r = m_records[old.id];
            r.threadPage = {};
            r.threadSyncedAt = {};
            changedRecord(r.id);
        }
    }
}
} // namespace hexproof::client
