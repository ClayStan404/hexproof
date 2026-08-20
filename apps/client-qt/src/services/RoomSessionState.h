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

class RoomSessionState : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString roomId READ roomId NOTIFY roomIdChanged)
    Q_PROPERTY(QString roomName READ roomName NOTIFY snapshotChanged)
    Q_PROPERTY(QString format READ format NOTIFY snapshotChanged)
    Q_PROPERTY(QString deckFormat READ deckFormat NOTIFY snapshotChanged)
    Q_PROPERTY(bool playtest READ playtest NOTIFY snapshotChanged)
    Q_PROPERTY(QString matchMode READ matchMode NOTIFY snapshotChanged)
    Q_PROPERTY(QString cardLoadMode READ cardLoadMode NOTIFY snapshotChanged)
    Q_PROPERTY(int maxSeats READ maxSeats NOTIFY snapshotChanged)
    Q_PROPERTY(QString phase READ phase NOTIFY snapshotChanged)
    Q_PROPERTY(qint64 loadId READ loadId NOTIFY snapshotChanged)
    Q_PROPERTY(bool host READ host NOTIFY hostChanged)
    Q_PROPERTY(QString role READ role NOTIFY roleChanged)
    Q_PROPERTY(int seatIndex READ seatIndex NOTIFY roleChanged)
    Q_PROPERTY(QString selectedDeckName READ selectedDeckName NOTIFY selectedDeckNameChanged)
    Q_PROPERTY(QVariantList seats READ seats NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList spectators READ spectators NOTIFY snapshotChanged)

  public:
    struct SnapshotTransition
    {
        bool loadCancelled = false;
        bool returnedToRoom = false;
    };

    explicit RoomSessionState(QObject *parent = nullptr);

    QString roomId() const { return m_roomId; }
    QString roomName() const { return m_roomName; }
    QString format() const { return m_format; }
    QString deckFormat() const
    {
        return m_deckFormat;
    }
    bool playtest() const { return m_playtest; }
    QString matchMode() const { return m_matchMode; }
    QString cardLoadMode() const { return m_cardLoadMode; }
    int maxSeats() const { return m_maxSeats; }
    QString phase() const { return m_phase; }
    qint64 loadId() const { return m_loadId; }
    bool host() const { return m_host; }
    QString role() const { return m_role; }
    int seatIndex() const { return m_seatIndex; }
    QString selectedDeckName() const { return m_selectedDeckName; }
    bool pendingEntry() const { return m_pendingEntry; }
    QVariantList seats() const { return m_seats; }
    QVariantList spectators() const { return m_spectators; }

    void enter(const QString &roomId, const QString &role, int seatIndex, bool host);
    SnapshotTransition applySnapshot(const QJsonObject &snapshot);
    bool applyLoadRequired(qint64 loadId);
    void applyMatchStarted(qint64 loadId);
    bool completePendingEntry();
    void rememberPendingDeck(const QString &requestId, const QString &deckName);
    QString takePendingDeck(const QString &requestId);
    void discardPendingDeck(const QString &requestId);
    void clear();

  signals:
    void roomIdChanged();
    void hostChanged();
    void roleChanged();
    void selectedDeckNameChanged();
    void snapshotChanged();

  private:
    QString m_roomId;
    QString m_roomName;
    QString m_format;
    QString m_deckFormat;
    bool m_playtest = false;
    QString m_matchMode;
    QString m_cardLoadMode;
    int m_maxSeats = 0;
    QString m_phase;
    qint64 m_loadId = 0;
    qint64 m_announcedLoadId = 0;
    bool m_host = false;
    QString m_role;
    int m_seatIndex = -1;
    QString m_selectedDeckName;
    QHash<QString, QString> m_pendingDeckNames;
    bool m_pendingEntry = false;
    QVariantList m_seats;
    QVariantList m_spectators;
};

} // namespace hexproof::client
