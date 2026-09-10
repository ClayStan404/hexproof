// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "LimitedDeckDraftStore.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSaveFile>

namespace hexproof::client {
namespace {
constexpr qint64 retentionMs = 7LL * 24 * 60 * 60 * 1000;
constexpr qint64 maximumBytes = 4 * 1024 * 1024;
constexpr int maximumDrafts = 32;
} // namespace

LimitedDeckDraftStore::LimitedDeckDraftStore(const QString &storageRoot, QObject *parent)
    : QObject(parent),
      m_path(QDir(storageRoot).filePath(QStringLiteral("limited-deck-drafts.json")))
{
    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(250);
    connect(&m_saveTimer, &QTimer::timeout, this, [this] { flush(); });
    QFile file(m_path);
    if (file.exists()) {
        if (!file.open(QIODevice::ReadOnly) || file.size() > maximumBytes) {
            m_storageReadable = false;
            setError(QStringLiteral("Could not read local Limited deck drafts."));
            return;
        }
        const QJsonDocument document = QJsonDocument::fromJson(file.read(maximumBytes));
        if (!document.isObject() ||
            document.object().value(QStringLiteral("schemaVersion")).toInt() != 1 ||
            !document.object().value(QStringLiteral("drafts")).isObject()) {
            m_storageReadable = false;
            setError(QStringLiteral("Could not read local Limited deck drafts."));
            return;
        }
        m_entries = document.object().value(QStringLiteral("drafts")).toObject();
        prune();
    }
}

LimitedDeckDraftStore::~LimitedDeckDraftStore()
{
    flush();
}

QString LimitedDeckDraftStore::key(const QString &server, const QString &event,
                                   const QString &participant)
{
    if (server.isEmpty() || event.isEmpty() || participant.isEmpty())
        return {};
    const QByteArray identity =
        QJsonDocument(QJsonArray{server, event, participant}).toJson(QJsonDocument::Compact);
    return QString::fromLatin1(
        QCryptographicHash::hash(identity, QCryptographicHash::Sha256).toHex());
}

QVariantMap LimitedDeckDraftStore::loadDraft(const QString &server, const QString &event,
                                             const QString &participant) const
{
    const QJsonObject entry = m_entries.value(key(server, event, participant)).toObject();
    if (entry.value(QStringLiteral("savedAt")).toDouble() <
        QDateTime::currentMSecsSinceEpoch() - retentionMs)
        return {};
    return entry.value(QStringLiteral("draft")).toObject().toVariantMap();
}

void LimitedDeckDraftStore::saveDraft(const QString &server, const QString &event,
                                      const QString &participant, const QVariantMap &draft)
{
    const QString identity = key(server, event, participant);
    if (identity.isEmpty())
        return;
    const QJsonObject object = QJsonObject::fromVariantMap(draft);
    if (QJsonDocument(object).toJson(QJsonDocument::Compact).size() > 64 * 1024)
        return;
    m_entries.insert(identity,
                     QJsonObject{{QStringLiteral("savedAt"), QDateTime::currentMSecsSinceEpoch()},
                                 {QStringLiteral("draft"), object}});
    m_dirty = true;
    prune(identity);
    m_saveTimer.start();
}

void LimitedDeckDraftStore::removeDraft(const QString &server, const QString &event,
                                        const QString &participant)
{
    const QString identity = key(server, event, participant);
    if (!m_entries.contains(identity))
        return;
    m_entries.remove(identity);
    m_dirty = true;
    m_saveTimer.start();
}

void LimitedDeckDraftStore::prune(const QString &preserveKey)
{
    const qint64 oldest = QDateTime::currentMSecsSinceEpoch() - retentionMs;
    for (const QString &identity : m_entries.keys()) {
        if (m_entries.value(identity).toObject().value(QStringLiteral("savedAt")).toDouble() <
            oldest) {
            m_entries.remove(identity);
            m_dirty = true;
        }
    }
    while (m_entries.size() > maximumDrafts) {
        QString oldestKey;
        double oldestTime = 0;
        bool candidateFound = false;
        for (auto it = m_entries.constBegin(); it != m_entries.constEnd(); ++it) {
            if (it.key() == preserveKey)
                continue;
            const double time = it.value().toObject().value(QStringLiteral("savedAt")).toDouble();
            if (!candidateFound || time < oldestTime) {
                oldestKey = it.key();
                oldestTime = time;
                candidateFound = true;
            }
        }
        m_entries.remove(oldestKey);
        m_dirty = true;
    }
}

bool LimitedDeckDraftStore::flush()
{
    m_saveTimer.stop();
    if (!m_dirty)
        return true;
    // Never replace an unreadable or newer-schema file with a partial draft set.
    if (!m_storageReadable)
        return false;
    const QByteArray data = QJsonDocument(QJsonObject{{QStringLiteral("schemaVersion"), 1},
                                                      {QStringLiteral("drafts"), m_entries}})
                                .toJson(QJsonDocument::Compact);
    QSaveFile file(m_path);
    if (!QDir().mkpath(QFileInfo(m_path).absolutePath()) || !file.open(QIODevice::WriteOnly) ||
        file.write(data) != data.size() || !file.commit()) {
        setError(QStringLiteral("Could not save local Limited deck drafts."));
        return false;
    }
    m_dirty = false;
    setError({});
    return true;
}

void LimitedDeckDraftStore::setError(const QString &error)
{
    if (error == m_lastError)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}
} // namespace hexproof::client
