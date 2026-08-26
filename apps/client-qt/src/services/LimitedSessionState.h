// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

namespace hexproof::client {

class LimitedSessionState : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active NOTIFY snapshotChanged)
    Q_PROPERTY(QString tournamentId READ tournamentId NOTIFY snapshotChanged)
    Q_PROPERTY(QString eventType READ eventType NOTIFY snapshotChanged)
    Q_PROPERTY(QString stage READ stage NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantMap product READ product NOTIFY snapshotChanged)
    Q_PROPERTY(int packRound READ packRound NOTIFY snapshotChanged)
    Q_PROPERTY(int direction READ direction NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList currentPack READ currentPack NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList pool READ pool NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList mainboardInstanceIds READ mainboardInstanceIds NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList basicLands READ basicLands NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList participants READ participants NOTIFY snapshotChanged)
    Q_PROPERTY(bool deckSubmitted READ deckSubmitted NOTIFY snapshotChanged)
    Q_PROPERTY(bool allDecksSubmitted READ allDecksSubmitted NOTIFY snapshotChanged)

  public:
    explicit LimitedSessionState(QObject *parent = nullptr);

    bool active() const
    {
        return !m_tournamentId.isEmpty();
    }
    QString tournamentId() const
    {
        return m_tournamentId;
    }
    QString eventType() const
    {
        return m_eventType;
    }
    QString stage() const
    {
        return m_stage;
    }
    QVariantMap product() const
    {
        return m_product;
    }
    int packRound() const
    {
        return m_packRound;
    }
    int direction() const
    {
        return m_direction;
    }
    QVariantList currentPack() const
    {
        return m_currentPack;
    }
    QVariantList pool() const
    {
        return m_pool;
    }
    QVariantList mainboardInstanceIds() const
    {
        return m_mainboardInstanceIds;
    }
    QVariantList basicLands() const
    {
        return m_basicLands;
    }
    QVariantList participants() const
    {
        return m_participants;
    }
    bool deckSubmitted() const
    {
        return m_deckSubmitted;
    }
    bool allDecksSubmitted() const
    {
        return m_allDecksSubmitted;
    }

    void applySnapshot(const QJsonObject &payload);
    void clear();

  signals:
    void snapshotChanged();

  private:
    QString m_tournamentId;
    QString m_eventType;
    QString m_stage;
    QVariantMap m_product;
    int m_packRound = 0;
    int m_direction = 1;
    QVariantList m_currentPack;
    QVariantList m_pool;
    QVariantList m_mainboardInstanceIds;
    QVariantList m_basicLands;
    QVariantList m_participants;
    bool m_deckSubmitted = false;
    bool m_allDecksSubmitted = false;
};

} // namespace hexproof::client
