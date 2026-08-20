// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

namespace hexproof::client {

class GameSessionState : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int gameNumber READ gameNumber NOTIFY snapshotChanged)
    Q_PROPERTY(int startingSeat READ startingSeat NOTIFY snapshotChanged)
    Q_PROPERTY(int activeSeat READ activeSeat NOTIFY snapshotChanged)
    Q_PROPERTY(QString currentPhase READ currentPhase NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList score READ score NOTIFY snapshotChanged)
    Q_PROPERTY(int drawnGames READ drawnGames NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantMap result READ result NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantMap sideboard READ sideboard NOTIFY snapshotChanged)
    Q_PROPERTY(bool sideboarding READ sideboarding NOTIFY snapshotChanged)
    Q_PROPERTY(bool finished READ finished NOTIFY snapshotChanged)

  public:
    explicit GameSessionState(QObject *parent = nullptr);

    int gameNumber() const { return m_gameNumber; }
    int startingSeat() const { return m_startingSeat; }
    int activeSeat() const { return m_activeSeat; }
    QString currentPhase() const { return m_currentPhase; }
    QVariantList seats() const { return m_seats; }
    QVariantList stack() const { return m_stack; }
    QVariantList revealed() const { return m_revealed; }
    QVariantList arrows() const { return m_arrows; }
    QVariantList attachments() const { return m_attachments; }
    QVariantList log() const { return m_log; }
    QVariantList score() const { return m_score; }
    int drawnGames() const
    {
        return m_drawnGames;
    }
    QVariantMap result() const { return m_result; }
    QVariantMap sideboard() const { return m_sideboard; }
    bool sideboarding() const { return !m_sideboard.isEmpty(); }
    bool finished() const { return !m_result.isEmpty(); }

    void applySnapshot(const QVariantMap &snapshot);
    void clear();

  signals:
    void snapshotChanged();
    void snapshotDataChanged(const QVariantMap &snapshot);

  private:
    int m_gameNumber = 0;
    int m_startingSeat = -1;
    int m_activeSeat = -1;
    QString m_currentPhase;
    QVariantList m_seats;
    QVariantList m_stack;
    QVariantList m_revealed;
    QVariantList m_arrows;
    QVariantList m_attachments;
    QVariantList m_log;
    QVariantList m_score;
    int m_drawnGames = 0;
    QVariantMap m_result;
    QVariantMap m_sideboard;
};

} // namespace hexproof::client
