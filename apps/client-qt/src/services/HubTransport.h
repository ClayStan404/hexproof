// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QAbstractSocket>
#include <QByteArray>
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QUrl>
#include <QtWebSockets/QWebSocket>

namespace hexproof::client {

// One ordered hub connection. Home helpers choose their path before the first
// application message; changing a live connection always uses normal resume.
class HubTransport : public QObject
{
    Q_OBJECT

  public:
    explicit HubTransport(QObject *parent = nullptr);
    explicit HubTransport(const QString &helperPath, QObject *parent = nullptr);
    ~HubTransport() override;

    static bool isHomeUrl(const QUrl &url);
    void open(const QUrl &url);
    void abort();
    void close();
    qint64 sendTextMessage(const QString &message);
    void ping(const QByteArray &payload = {});
    void setMaxAllowedIncomingFrameSize(quint64 size);
    void setMaxAllowedIncomingMessageSize(quint64 size);

    QAbstractSocket::SocketState state() const
    {
        return m_state;
    }
    QString errorString() const
    {
        return m_error;
    }
    QString transportState() const
    {
        return m_transportState;
    }
    QUrl url() const
    {
        return m_url;
    }

  signals:
    void connected();
    void disconnected();
    void textMessageReceived(const QString &message);
    void errorOccurred(QAbstractSocket::SocketError error);
    void transportStateChanged();

  private:
    void openSocket();
    void openHelper();
    void stopBackend();
    void finish();
    void helperFailed();
    void readHelperOutput(QProcess *process, quint64 generation);
    bool writeHelper(const QJsonObject &value);
    void setTransportState(const QString &state);

    QString m_helperPath;
    QUrl m_url;
    QWebSocket *m_socket = nullptr;
    QProcess *m_process = nullptr;
    QTimer m_helperTimer;
    QByteArray m_output;
    QString m_error;
    QString m_transportState;
    QAbstractSocket::SocketState m_state = QAbstractSocket::UnconnectedState;
    quint64 m_generation = 0;
    quint64 m_maximumFrameBytes = 8 * 1024 * 1024;
    quint64 m_maximumMessageBytes = 8 * 1024 * 1024;
    bool m_home = false;
    bool m_forceTurn = false;
    bool m_sentApplication = false;
    bool m_reportedConnected = false;
};

} // namespace hexproof::client
