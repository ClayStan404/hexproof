// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#pragma once

#include "RulesSessionState.h"
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QTimer>
#include <QUrl>
#include <QVariantList>

namespace hexproof::client {

class ForgeReplayService final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList entries READ entries NOTIFY entriesChanged)
    Q_PROPERTY(QVariantMap metadata READ metadata NOTIFY loaded)
    Q_PROPERTY(QVariantMap frame READ frame NOTIFY positionChanged)
    Q_PROPERTY(QVariantList events READ events NOTIFY loaded)
    Q_PROPERTY(int position READ position NOTIFY positionChanged)
    Q_PROPERTY(int count READ count NOTIFY loaded)
    Q_PROPERTY(bool busy READ busy NOTIFY statusChanged)
    Q_PROPERTY(QString error READ error NOTIFY statusChanged)
    Q_PROPERTY(bool playing READ playing NOTIFY playingChanged)
    Q_PROPERTY(double speed READ speed WRITE setSpeed NOTIFY playingChanged)
    Q_PROPERTY(RulesSessionState *session READ session CONSTANT)

  public:
    explicit ForgeReplayService(QObject *parent = nullptr, const QString &directory = {});
    QVariantList entries() const;
    QVariantMap metadata() const
    {
        return m_metadata.toVariantMap();
    }
    QVariantMap frame() const;
    QVariantList events() const;
    int position() const
    {
        return m_position;
    }
    int count() const
    {
        return m_frames.size();
    }
    bool busy() const
    {
        return !m_downloading.isEmpty();
    }
    QString error() const
    {
        return m_error;
    }
    bool playing() const
    {
        return m_timer.isActive();
    }
    double speed() const
    {
        return m_speed;
    }
    RulesSessionState *session()
    {
        return &m_session;
    }
    void acceptGrant(const QString &server, const QJsonObject &grant);
    void acceptPage(const QString &server, const QJsonObject &page);
    void fail(const QString &message);
    void setSpeed(double speed);
    Q_INVOKABLE bool open(const QString &id);
    Q_INVOKABLE void download(const QString &id);
    Q_INVOKABLE bool importFile(const QUrl &url);
    Q_INVOKABLE bool exportFile(const QUrl &url);
    Q_INVOKABLE void seek(int position);
    Q_INVOKABLE void step(int delta);
    Q_INVOKABLE void nextTurn(int direction);
    Q_INVOKABLE void togglePlaying();
    Q_INVOKABLE void pause();

  signals:
    void entriesChanged();
    void loaded();
    void positionChanged();
    void statusChanged();
    void playingChanged();
    void requestPage(const QString &server, const QJsonObject &payload);

  private:
    bool readFile(const QString &path);
    bool writeFile(const QString &path);
    bool load(const QJsonObject &document);
    void saveIndex();
    void requestNext();
    QString filePath(const QString &id) const;
    QString m_directory;
    QJsonArray m_entries;
    QJsonObject m_metadata;
    QJsonArray m_frames;
    QJsonArray m_received;
    QString m_downloading;
    QString m_downloadServer;
    QString m_downloadToken;
    QString m_error;
    qint64 m_receivedBytes = 0;
    int m_expectedTotal = -1;
    int m_position = -1;
    double m_speed = 1;
    RulesSessionState m_session;
    QTimer m_timer;
    QTimer m_pageTimer;
    QTimer m_downloadTimeout;
};
} // namespace hexproof::client
