// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QJsonObject>
#include <QObject>
#include <QTimer>
#include <QVariantMap>

namespace hexproof::client {

// Device-local construction notes, never an authoritative submitted deck.
class LimitedDeckDraftStore : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

  public:
    explicit LimitedDeckDraftStore(const QString &storageRoot, QObject *parent = nullptr);
    ~LimitedDeckDraftStore() override;
    QString lastError() const
    {
        return m_lastError;
    }
    Q_INVOKABLE QVariantMap loadDraft(const QString &server, const QString &event,
                                      const QString &participant) const;
    Q_INVOKABLE void saveDraft(const QString &server, const QString &event,
                               const QString &participant, const QVariantMap &draft);
    Q_INVOKABLE void removeDraft(const QString &server, const QString &event,
                                 const QString &participant);
    bool flush();

  signals:
    void lastErrorChanged();

  private:
    static QString key(const QString &server, const QString &event, const QString &participant);
    void prune(const QString &preserveKey = {});
    void setError(const QString &error);
    QString m_path;
    QString m_lastError;
    QJsonObject m_entries;
    QTimer m_saveTimer;
    bool m_dirty = false;
    bool m_storageReadable = true;
};

} // namespace hexproof::client
