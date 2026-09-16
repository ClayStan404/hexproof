// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "WsMessageParser.h"

#include "protocol/Message.h"

namespace hexproof::client {

void WsMessageParser::parseMessage(quint64 transportGeneration, const QString &text)
{
    bool ok = false;
    protocol::Envelope envelope = protocol::parse(text.toUtf8(), &ok);
    if (!ok) {
        emit messageRejected(transportGeneration);
        return;
    }

    QVariantMap gameSnapshot;
    if (envelope.type == protocol::kTypeGameSnapshot)
        gameSnapshot = envelope.payload.toVariantMap();
    emit messageParsed(transportGeneration, envelope.type, envelope.id, envelope.seq,
                       envelope.hasSeq, envelope.payload, gameSnapshot);
}

void WsMessageParser::finishTransport(quint64 transportGeneration)
{
    emit transportFinished(transportGeneration);
}

} // namespace hexproof::client
