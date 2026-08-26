// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

namespace hexproof::client {

class TournamentSessionState : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool inTournament READ inTournament NOTIFY inTournamentChanged)
    Q_PROPERTY(QVariantList tournamentList READ tournamentList NOTIFY tournamentListChanged)
    Q_PROPERTY(QString tournamentId READ tournamentId NOTIFY snapshotChanged)
    Q_PROPERTY(QString name READ name NOTIFY snapshotChanged)
    Q_PROPERTY(QString format READ format NOTIFY snapshotChanged)
    Q_PROPERTY(QString eventType READ eventType NOTIFY snapshotChanged)
    Q_PROPERTY(QString coordinator READ coordinator NOTIFY snapshotChanged)
    Q_PROPERTY(QString stage READ stage NOTIFY snapshotChanged)
    Q_PROPERTY(QString matchMode READ matchMode NOTIFY snapshotChanged)
    Q_PROPERTY(QString status READ status NOTIFY snapshotChanged)
    Q_PROPERTY(QString role READ role NOTIFY snapshotChanged)
    Q_PROPERTY(QString participantId READ participantId NOTIFY snapshotChanged)
    Q_PROPERTY(QString organizerName READ organizerName NOTIFY snapshotChanged)
    Q_PROPERTY(int roundMinutes READ roundMinutes NOTIFY snapshotChanged)
    Q_PROPERTY(QString roundStartedAt READ roundStartedAt NOTIFY snapshotChanged)
    Q_PROPERTY(int maxPlayers READ maxPlayers NOTIFY snapshotChanged)
    Q_PROPERTY(int plannedRounds READ plannedRounds NOTIFY snapshotChanged)
    Q_PROPERTY(int currentRound READ currentRound NOTIFY snapshotChanged)
    Q_PROPERTY(int registered READ registered NOTIFY snapshotChanged)
    Q_PROPERTY(int checkedIn READ checkedIn NOTIFY snapshotChanged)
    Q_PROPERTY(bool roundComplete READ roundComplete NOTIFY snapshotChanged)
    Q_PROPERTY(bool canRegister READ canRegister NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList participants READ participants NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList pairings READ pairings NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList standings READ standings NOTIFY snapshotChanged)

  public:
    explicit TournamentSessionState(QObject *parent = nullptr);

    bool inTournament() const
    {
        return !m_tournamentId.isEmpty();
    }
    QVariantList tournamentList() const
    {
        return m_tournamentList;
    }
    QString tournamentId() const
    {
        return m_tournamentId;
    }
    QString name() const
    {
        return m_name;
    }
    QString format() const
    {
        return m_format;
    }
    QString eventType() const
    {
        return m_eventType;
    }
    QString coordinator() const
    {
        return m_coordinator;
    }
    QString stage() const
    {
        return m_stage;
    }
    QString matchMode() const
    {
        return m_matchMode;
    }
    QString status() const
    {
        return m_status;
    }
    QString role() const
    {
        return m_role;
    }
    QString participantId() const
    {
        return m_participantId;
    }
    QString organizerName() const
    {
        return m_organizerName;
    }
    int roundMinutes() const
    {
        return m_roundMinutes;
    }
    QString roundStartedAt() const
    {
        return m_roundStartedAt;
    }
    int maxPlayers() const
    {
        return m_maxPlayers;
    }
    int plannedRounds() const
    {
        return m_plannedRounds;
    }
    int currentRound() const
    {
        return m_currentRound;
    }
    int registered() const
    {
        return m_registered;
    }
    int checkedIn() const
    {
        return m_checkedIn;
    }
    bool roundComplete() const
    {
        return m_roundComplete;
    }
    bool canRegister() const
    {
        return m_canRegister;
    }
    QVariantList participants() const
    {
        return m_participants;
    }
    QVariantList pairings() const
    {
        return m_pairings;
    }
    QVariantList standings() const
    {
        return m_standings;
    }

    Q_INVOKABLE void rememberTabletopScore(const QString &roomId, const QVariantList &seats,
                                           int drawnGames = 0);
    Q_INVOKABLE QVariantMap tabletopScoreForRoom(const QString &roomId) const;

    void applyList(const QJsonObject &payload);
    void enter(const QString &tournamentId, const QString &role, const QString &participantId = {});
    void applyRegistration(const QString &participantId);
    void applySnapshot(const QJsonObject &payload);
    void clear();

  signals:
    void inTournamentChanged();
    void tournamentListChanged();
    void snapshotChanged();

  private:
    QVariantList m_tournamentList;
    QString m_tournamentId;
    QString m_name;
    QString m_format;
    QString m_eventType;
    QString m_coordinator;
    QString m_stage;
    QString m_matchMode;
    QString m_status;
    QString m_role;
    QString m_participantId;
    QString m_organizerName;
    int m_roundMinutes = 0;
    QString m_roundStartedAt;
    int m_maxPlayers = 0;
    int m_plannedRounds = 0;
    int m_currentRound = 0;
    int m_registered = 0;
    int m_checkedIn = 0;
    bool m_roundComplete = false;
    bool m_canRegister = false;
    QVariantList m_participants;
    QVariantList m_pairings;
    QVariantList m_standings;
    QHash<QString, QVariantMap> m_tabletopScores;
};

} // namespace hexproof::client
