// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QJsonObject>
#include <QObject>
#include <QVariantMap>

namespace hexproof::client {

class WsMessageParser : public QObject
{
    Q_OBJECT

  public slots:
    void parseMessage(const QString &text);
    void finishTransport();

  signals:
    void messageParsed(const QString &type, const QString &id, qint64 seq, bool hasSeq,
                       const QJsonObject &payload, const QVariantMap &gameSnapshot);
    void messageRejected();
    void transportFinished();
};

} // namespace hexproof::client
