// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QByteArray>
#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QVariantMap>

namespace hexproof::client {

// ProtocolSession owns client request ids and the pending-command registry.
// WsClient decides when transport is available and performs the actual socket
// write; this class keeps command correlation independent from WebSocket state.
class ProtocolSession : public QObject
{
    Q_OBJECT

  public:
    struct OutboundCommand
    {
        QString id;
        QString type;
        QJsonObject payload;
        QByteArray wire;
    };

    explicit ProtocolSession(QObject *parent = nullptr);

    OutboundCommand prepare(const QString &type, const QJsonObject &payload = {});
    void markQueued(const OutboundCommand &command);
    void reportUnqueuedFailure(const QString &type, const QJsonObject &payload,
                               const QString &error);

    bool resolveSuccess(const QString &requestId);
    bool resolveFailure(const QString &requestId, const QString &error);
    void failAll(const QString &error);
    // End room-scoped ownership and notify observers so optimistic state rolls back.
    void discardAll();

    int pendingCount() const
    {
        return m_pendingCommands.size();
    }

  signals:
    void commandQueued(const QString &requestId, const QString &commandType,
                       const QVariantMap &payload);
    void commandSucceeded(const QString &requestId, const QString &commandType,
                          const QVariantMap &payload);
    void commandFailed(const QString &requestId, const QString &commandType,
                       const QVariantMap &payload, const QString &error);

  private:
    struct PendingCommand
    {
        QString type;
        QJsonObject payload;
    };

    QHash<QString, PendingCommand> m_pendingCommands;
    int m_nextId = 1;
};

} // namespace hexproof::client
