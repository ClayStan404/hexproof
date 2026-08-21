// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "WsMessageParser.h"

#include "protocol/Message.h"

namespace hexproof::client {

void WsMessageParser::parseMessage(const QString &text)
{
    bool ok = false;
    protocol::Envelope envelope = protocol::parse(text.toUtf8(), &ok);
    if (!ok) {
        emit messageRejected();
        return;
    }

    QVariantMap gameSnapshot;
    if (envelope.type == protocol::kTypeGameSnapshot)
        gameSnapshot = envelope.payload.toVariantMap();
    emit messageParsed(envelope.type, envelope.id, envelope.seq, envelope.hasSeq, envelope.payload,
                       gameSnapshot);
}

void WsMessageParser::finishTransport()
{
    emit transportFinished();
}

} // namespace hexproof::client
