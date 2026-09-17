// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QJsonObject>
#include <QObject>
#include <QProcess>

namespace hexproof::client {

// Only the authenticated WsClient sees grants/signaling/application messages.
// QML and diagnostic exports receive transport state and counters, never SDP.
class PeerTransportService : public QObject
{
    Q_OBJECT
  public:
    explicit PeerTransportService(QObject *parent = nullptr);
    ~PeerTransportService() override;
    void start(const QJsonObject &grant);
    void stop();
    bool send(const QJsonObject &message);
    void signal(const QJsonObject &value);
    bool ready() const
    {
        return m_state == QStringLiteral("direct");
    }
    QString state() const
    {
        return m_state;
    }
    QString bindingId() const
    {
        return m_bindingId;
    }
    QString gameId() const
    {
        return m_gameId;
    }
    int hostSeat() const
    {
        return m_hostSeat;
    }

  signals:
    void changed();
    void localSignal(const QJsonObject &value);
    void messageReceived(const QJsonObject &value);

  private:
    bool write(const QJsonObject &value);
    void readOutput();
    void setState(const QString &state);
    QProcess *m_process = nullptr;
    QByteArray m_output;
    QString m_bindingId;
    QString m_gameId;
    int m_hostSeat = -1;
    QString m_state = QStringLiteral("relay");
};
} // namespace hexproof::client
