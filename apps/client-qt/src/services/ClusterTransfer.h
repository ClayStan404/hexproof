// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "protocol/Message.h"
#include <QObject>
#include <QTimer>

namespace hexproof::client {

// Owns one command's private transfer state. Transport and directory lookup
// stay in WsClient; no credentials enter URL or diagnostic projections here.
class ClusterTransfer : public QObject
{
    Q_OBJECT

  public:
    explicit ClusterTransfer(QObject *parent = nullptr);
    void track(const QString &id, const QString &type, const QByteArray &wire);
    void clear();
    void resolve(const QString &id);
    bool pending() const
    {
        return !m_requestId.isEmpty();
    }
    bool routing() const
    {
        return m_routing;
    }
    bool routed() const
    {
        return !m_destination.isEmpty();
    }
    QString requestId() const
    {
        return m_requestId;
    }
    QString commandType() const
    {
        return m_commandType;
    }
    QString ticket() const
    {
        return m_ticket;
    }

    bool acceptRoute(const protocol::Envelope &route, const QString &sourceUrl,
                     const QString &sourceRealm, const QString &destinationRealm,
                     const QString &accountId, bool canTransfer);
    // Consumes the only permitted replay, after a verified destination welcome.
    QByteArray takeCommand(const protocol::Envelope &welcome, const QString &node);

  signals:
    void timedOut();

  private:
    QString m_requestId;
    QString m_commandType;
    QByteArray m_wire;
    QString m_ticket;
    QString m_destination;
    QString m_accountId;
    QTimer m_timer;
    bool m_routing = false;
};

} // namespace hexproof::client
