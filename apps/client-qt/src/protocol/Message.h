// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QByteArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QString>

#include "WireConstantsGenerated.h"

namespace hexproof::protocol {

// A canonical generation is useful for update guidance; support still requires
// exact equality with kProtocolVersion, never a numeric range.
inline int protocolGeneration(const QString &value)
{
    const QString prefix = QStringLiteral("hexproof.v");
    if (!value.startsWith(prefix))
        return 0;
    const QString number = value.mid(prefix.size());
    if (number.isEmpty() || number.size() > 10 || number.front() == QLatin1Char('0'))
        return 0;
    for (const auto c : number)
        if (c < QLatin1Char('0') || c > QLatin1Char('9'))
            return 0;
    bool ok = false;
    const int generation = number.toInt(&ok);
    return ok && generation > 0 ? generation : 0;
}

// Wire protocol version. Negotiated once at handshake; the authoritative value
// lives only in the session.welcome payload (no top-level `v` on other
// messages).

// Stable wire names are generated from protocol/v2/wire-schema.json. Add or
// rename them in that schema, then run tools/protocol_codegen.py; do not add
// duplicate literals here.

// Envelope is the top-level wire object. One per WebSocket message.
// There is NO top-level `v` field by design; the protocol version lives only
// inside the session.welcome payload. `id` correlates client commands with
// server success events / errors. `seq` identifies a room publication for
// reconnect and ordering. Paired rules snapshots/prompts share a sequence,
// even when intervening metadata carries a higher one.
struct Envelope
{
    QString type;
    QString id;
    qint64 seq = 0;
    QJsonObject payload;

    bool hasSeq = false; // disambiguates "seq absent" from "seq == 0"
};

// Serialize an envelope to UTF-8 JSON. Omits empty `id`, and omits `seq` when
// hasSeq is false (mirrors the Go side's omitempty semantics).
inline QByteArray serialize(const Envelope &env)
{
    QJsonObject obj;
    obj.insert(QStringLiteral("type"), env.type);
    if (!env.id.isEmpty())
        obj.insert(QStringLiteral("id"), env.id);
    if (env.hasSeq)
        obj.insert(QStringLiteral("seq"), env.seq);
    if (!env.payload.isEmpty())
        obj.insert(QStringLiteral("payload"), env.payload);
    return QJsonDocument(obj).toJson(QJsonDocument::Compact);
}

// Parse a JSON byte slice into an envelope. Does NOT require a top-level `v`:
// only session.welcome carries `v`, and only in its payload. Returns a null
// envelope on JSON error (error set on *ok).
inline Envelope parse(const QByteArray &data, bool *ok = nullptr)
{
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(data, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        if (ok)
            *ok = false;
        return {};
    }
    const QJsonObject obj = doc.object();

    if (obj.value(QStringLiteral("type")).toString().isEmpty()) {
        if (ok)
            *ok = false;
        return {};
    }

    Envelope env;
    env.type = obj.value(QStringLiteral("type")).toString();
    env.id = obj.value(QStringLiteral("id")).toString();
    if (const QJsonValue v = obj.value(QStringLiteral("seq")); v.isDouble()) {
        env.seq = v.toInteger();
        env.hasSeq = true;
    }
    env.payload = obj.value(QStringLiteral("payload")).toObject();

    if (ok)
        *ok = true;
    return env;
}

} // namespace hexproof::protocol
