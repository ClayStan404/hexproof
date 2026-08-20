// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QNetworkReply>
#include <QNetworkRequest>
#include <QtGlobal>

#include <limits>

namespace hexproof::client::network_limits {

inline constexpr quint64 kMaximumIncomingWebSocketBytes = 8ULL * 1024 * 1024;
inline constexpr qint64 kMaximumHealthResponseBytes = 64LL * 1024;
inline constexpr qint64 kMaximumJsonResponseBytes = 4LL * 1024 * 1024;
inline constexpr qint64 kMaximumCardImageResponseBytes = 32LL * 1024 * 1024;

inline constexpr auto kExceededProperty = "hexproof.responseSizeLimitExceeded";

inline bool responseSizeLimitExceeded(const QNetworkReply *reply)
{
    return reply && reply->property(kExceededProperty).toBool();
}

// Consumers read these replies only after finished(), so bounding the unread
// buffer also bounds memory. Declared and observed oversize responses are
// aborted before their payload can grow without limit.
inline void limitNetworkReply(QNetworkReply *reply, qint64 maximumBytes)
{
    if (!reply || maximumBytes < 0 || maximumBytes == std::numeric_limits<qint64>::max())
        return;

    reply->setReadBufferSize(maximumBytes + 1);
    const auto enforce = [reply, maximumBytes]() {
        if (responseSizeLimitExceeded(reply))
            return;
        bool contentLengthValid = false;
        const qint64 contentLength =
            reply->header(QNetworkRequest::ContentLengthHeader).toLongLong(&contentLengthValid);
        if ((contentLengthValid && contentLength > maximumBytes) ||
            reply->bytesAvailable() > maximumBytes) {
            reply->setProperty(kExceededProperty, true);
            reply->abort();
        }
    };
    QObject::connect(reply, &QNetworkReply::metaDataChanged, reply, enforce);
    QObject::connect(reply, &QIODevice::readyRead, reply, enforce);
    enforce();
}

} // namespace hexproof::client::network_limits
