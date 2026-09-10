// SPDX-License-Identifier: GPL-3.0-or-later
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
    Q_PROPERTY(bool active READ active NOTIFY headerChanged)
    Q_PROPERTY(QString tournamentId READ tournamentId NOTIFY headerChanged)
    Q_PROPERTY(QString eventType READ eventType NOTIFY headerChanged)
    Q_PROPERTY(bool commanderDraft READ commanderDraft NOTIFY headerChanged)
    Q_PROPERTY(int minimumDeckCards READ minimumDeckCards NOTIFY headerChanged)
    Q_PROPERTY(int packsPerPlayer READ packsPerPlayer NOTIFY headerChanged)
    Q_PROPERTY(int picksRequired READ picksRequired NOTIFY packChanged)
    Q_PROPERTY(QString stage READ stage NOTIFY headerChanged)
    Q_PROPERTY(QVariantMap product READ product NOTIFY headerChanged)
    Q_PROPERTY(int packRound READ packRound NOTIFY headerChanged)
    Q_PROPERTY(int direction READ direction NOTIFY headerChanged)
    Q_PROPERTY(QVariantList currentPack READ currentPack NOTIFY packChanged)
    Q_PROPERTY(QVariantList pool READ pool NOTIFY poolChanged)
    Q_PROPERTY(QVariantList mainboardInstanceIds READ mainboardInstanceIds NOTIFY deckChanged)
    Q_PROPERTY(QVariantList commanderInstanceIds READ commanderInstanceIds NOTIFY deckChanged)
    Q_PROPERTY(QVariantList fallbackCommanders READ fallbackCommanders NOTIFY deckChanged)
    Q_PROPERTY(QVariantList commanderColors READ commanderColors NOTIFY deckChanged)
    Q_PROPERTY(QVariantList basicLands READ basicLands NOTIFY deckChanged)
    Q_PROPERTY(QVariantList participants READ participants NOTIFY participantsChanged)
    Q_PROPERTY(bool deckSubmitted READ deckSubmitted NOTIFY deckChanged)
    Q_PROPERTY(bool allDecksSubmitted READ allDecksSubmitted NOTIFY headerChanged)

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
    bool commanderDraft() const
    {
        return m_eventType == QStringLiteral("commander_cube");
    }
    int minimumDeckCards() const
    {
        return m_minimumDeckCards;
    }
    int packsPerPlayer() const
    {
        return m_packsPerPlayer;
    }
    int picksRequired() const
    {
        return m_picksRequired;
    }
    QVariantList commanderInstanceIds() const
    {
        return m_commanderInstanceIds;
    }
    QVariantList fallbackCommanders() const
    {
        return m_fallbackCommanders;
    }
    QVariantList commanderColors() const
    {
        return m_commanderColors;
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
    void applyProgress(const QJsonObject &payload);
    void clear();

  signals:
    void snapshotChanged();
    void headerChanged();
    void packChanged();
    void poolChanged();
    void deckChanged();
    void participantsChanged();

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
    QVariantList m_commanderInstanceIds;
    QVariantList m_fallbackCommanders;
    QVariantList m_commanderColors;
    int m_minimumDeckCards = 40;
    int m_packsPerPlayer = 3;
    int m_picksRequired = 0;
    QVariantList m_basicLands;
    QVariantList m_participants;
    bool m_deckSubmitted = false;
    bool m_allDecksSubmitted = false;
};

} // namespace hexproof::client
