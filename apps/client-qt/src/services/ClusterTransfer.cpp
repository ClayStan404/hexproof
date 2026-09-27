// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "ClusterTransfer.h"
#include <QRegularExpression>
#include <utility>

namespace hexproof::client {
using namespace Qt::StringLiterals;

ClusterTransfer::ClusterTransfer(QObject *parent)
    : QObject(parent)
{
    m_timer.setSingleShot(true);
    connect(&m_timer, &QTimer::timeout, this, &ClusterTransfer::timedOut);
}

void ClusterTransfer::track(const QString &id, const QString &type, const QByteArray &wire)
{
    clear();
    m_requestId = id;
    m_commandType = type;
    m_wire = wire;
}

void ClusterTransfer::clear()
{
    m_timer.stop();
    m_requestId.clear();
    m_commandType.clear();
    m_wire.clear();
    m_ticket.clear();
    m_destination.clear();
    m_accountId.clear();
    m_routing = false;
}

void ClusterTransfer::resolve(const QString &id)
{
    if (!id.isEmpty() && id == m_requestId)
        clear();
}

bool ClusterTransfer::acceptRoute(const protocol::Envelope &route, const QString &sourceUrl,
                                  const QString &sourceRealm, const QString &destinationRealm,
                                  const QString &accountId, bool canTransfer)
{
    static const QRegularExpression nodePattern(u"^[A-Z0-9]{2,8}$"_s);
    static const QRegularExpression ticketPattern(u"^[a-f0-9]{64}$"_s);
    const QString url = route.payload.value(u"url"_s).toString();
    const QString node = route.payload.value(u"nodeId"_s).toString();
    const QString ticket = route.payload.value(u"ticket"_s).toString();
    if (!canTransfer || route.id.isEmpty() || route.id != m_requestId || routed() ||
        sourceRealm.isEmpty() || route.payload.value(u"realm"_s).toString() != sourceRealm ||
        destinationRealm != sourceRealm || url == sourceUrl ||
        !nodePattern.match(node).hasMatch() || !ticketPattern.match(ticket).hasMatch())
        return false;
    m_routing = true;
    m_destination = node;
    m_accountId = accountId;
    m_ticket = ticket;
    m_timer.start(30000);
    return true;
}

QByteArray ClusterTransfer::takeCommand(const protocol::Envelope &welcome, const QString &node)
{
    if (!m_routing || node != m_destination ||
        welcome.payload.value(u"accountId"_s).toString() != m_accountId ||
        welcome.payload.value(u"resumed"_s).toBool())
        return {};
    m_routing = false;
    m_ticket.clear();
    return std::exchange(m_wire, {});
}

} // namespace hexproof::client
