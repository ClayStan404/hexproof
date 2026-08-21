// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QObject>
#include <QString>
#include <QTimer>

namespace hexproof::client {

class ServerDirectory;

// ReconnectController owns persisted resume credentials, the bounded reconnect
// window, retry backoff, and delayed sequence persistence. The WebSocket itself
// remains in WsClient so transport and gameplay dispatch stay independent.
class ReconnectController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int remainingSeconds READ remainingSeconds NOTIFY remainingSecondsChanged)

  public:
    explicit ReconnectController(ServerDirectory *serverDirectory, QObject *parent = nullptr);
    ~ReconnectController() override;

    QString token() const
    {
        return m_token;
    }
    QString serverUrl() const
    {
        return m_serverUrl;
    }
    QString displayName() const
    {
        return m_displayName;
    }
    qint64 lastSeq() const
    {
        return m_lastSeq;
    }
    bool hasCredentials() const
    {
        return !m_token.isEmpty();
    }
    bool matches(const QString &serverUrl, const QString &displayName) const;
    int remainingSeconds() const
    {
        return m_remainingSeconds;
    }

    void updateSession(const QString &token, const QString &serverUrl, const QString &displayName);
    void observeSequence(qint64 seq);
    void resetSequence();

    void beginReconnectWindow();
    void scheduleRetry();
    void stopRetry();

    void flush();
    void clear();

    static int retryDelayMs(int attempt);

  signals:
    void retryDue();
    void reconnectExpired();
    void remainingSecondsChanged();

  private:
    void load();
    void persist();
    void updateRemainingSeconds();

    ServerDirectory *m_serverDirectory = nullptr;
    QTimer m_retryTimer;
    QTimer m_persistTimer;
    QTimer m_countdownTimer;
    QString m_token;
    QString m_serverUrl;
    QString m_displayName;
    qint64 m_lastSeq = 0;
    qint64 m_deadlineMs = 0;
    int m_attempt = 0;
    int m_remainingSeconds = 0;
};

} // namespace hexproof::client
