// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "ProtocolSession.h"

#include "protocol/Message.h"

namespace hexproof::client {

namespace {
QJsonObject safeCommandMetadata(const QString &type, const QJsonObject &payload)
{
    QJsonObject metadata = payload;
    if (type == protocol::kTypeAccountCommand) {
        metadata = {{QStringLiteral("operation"), payload.value(QStringLiteral("operation"))}};
    } else if (type == protocol::kTypeSessionHello) {
        metadata.remove(QStringLiteral("accountSession"));
        metadata.remove(QStringLiteral("clusterTicket"));
    }
    return metadata;
}
} // namespace

ProtocolSession::ProtocolSession(QObject *parent)
    : QObject(parent)
{
}

ProtocolSession::OutboundCommand ProtocolSession::prepare(const QString &type,
                                                          const QJsonObject &payload)
{
    protocol::Envelope envelope;
    envelope.type = type;
    envelope.id = QString::number(m_nextId++);
    envelope.payload = payload;
    return OutboundCommand{envelope.id, type, payload, protocol::serialize(envelope)};
}

void ProtocolSession::markQueued(const OutboundCommand &command)
{
    const QJsonObject metadata = safeCommandMetadata(command.type, command.payload);
    m_pendingCommands.insert(command.id, PendingCommand{command.type, metadata});
    emit commandQueued(command.id, command.type, metadata.toVariantMap());
}

void ProtocolSession::reportUnqueuedFailure(const QString &type, const QJsonObject &payload,
                                            const QString &error)
{
    emit commandFailed({}, type, safeCommandMetadata(type, payload).toVariantMap(), error);
}

bool ProtocolSession::resolveSuccess(const QString &requestId)
{
    const auto pending = m_pendingCommands.constFind(requestId);
    if (pending == m_pendingCommands.cend())
        return false;

    const PendingCommand command = *pending;
    m_pendingCommands.erase(pending);
    emit commandSucceeded(requestId, command.type, command.payload.toVariantMap());
    return true;
}

bool ProtocolSession::resolveFailure(const QString &requestId, const QString &error)
{
    const auto pending = m_pendingCommands.constFind(requestId);
    if (pending == m_pendingCommands.cend())
        return false;

    const PendingCommand command = *pending;
    m_pendingCommands.erase(pending);
    emit commandFailed(requestId, command.type, command.payload.toVariantMap(), error);
    return true;
}

void ProtocolSession::failAll(const QString &error)
{
    const auto pending = m_pendingCommands;
    m_pendingCommands.clear();
    for (auto command = pending.constBegin(); command != pending.constEnd(); ++command) {
        emit commandFailed(command.key(), command->type, command->payload.toVariantMap(), error);
    }
}

void ProtocolSession::discardAll()
{
    failAll(QStringLiteral("room session ended before the server replied"));
}

void ProtocolSession::failAllExcept(const QString &requestId, const QString &error)
{
    const auto ids = m_pendingCommands.keys();
    for (const auto &id : ids) {
        if (id != requestId)
            resolveFailure(id, error);
    }
}

} // namespace hexproof::client
