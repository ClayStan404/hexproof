// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QHash>
#include <QObject>
#include <QSet>
#include <QVariantList>
#include <QVariantMap>

namespace hexproof::client {

class MatchLoadCoordinator : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active NOTIFY stateChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY stateChanged)
    Q_PROPERTY(qint64 loadId READ loadId NOTIFY stateChanged)
    Q_PROPERTY(int total READ total NOTIFY stateChanged)
    Q_PROPERTY(int completed READ completed NOTIFY stateChanged)
    Q_PROPERTY(int failed READ failed NOTIFY stateChanged)
    Q_PROPERTY(qreal progress READ progress NOTIFY stateChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY stateChanged)

  public:
    explicit MatchLoadCoordinator(QObject *parent = nullptr);

    bool active() const
    {
        return m_active;
    }
    bool ready() const
    {
        return m_ready;
    }
    qint64 loadId() const
    {
        return m_loadId;
    }
    int total() const
    {
        return m_requests.size();
    }
    int completed() const
    {
        return m_requests.size() - m_pending.size();
    }
    int failed() const
    {
        return m_failed.size();
    }
    qreal progress() const;
    QString lastError() const
    {
        return m_lastError;
    }

  public slots:
    void beginLoad(qint64 loadId, const QVariantList &cardKeys);
    void handleCardCacheFinished(const QString &name, const QString &setCode,
                                 const QString &collectorNumber, bool success);
    Q_INVOKABLE void retry();
    Q_INVOKABLE void cancel();

  signals:
    void stateChanged();
    void cardsRequested(const QVariantList &cards);
    void loadComplete(qint64 loadId);

  private:
    static QString requestKey(const QString &name, const QString &setCode,
                              const QString &collectorNumber);
    void finishIfSettled();
    QVariantList requestsFor(const QSet<QString> &keys) const;

    qint64 m_loadId = 0;
    bool m_active = false;
    bool m_ready = false;
    QHash<QString, QVariantMap> m_requests;
    QSet<QString> m_pending;
    QSet<QString> m_failed;
    QString m_lastError;
};

} // namespace hexproof::client
