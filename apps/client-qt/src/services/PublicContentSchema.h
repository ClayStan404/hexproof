// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QJsonObject>
#include <QUrl>

namespace hexproof::client::public_content {

inline constexpr qint64 maximumIndexBytes = 32 * 1024;
inline constexpr qint64 maximumDocumentBytes = 2 * 1024 * 1024;
inline constexpr qint64 maximumAvatarBytes = 1024 * 1024;

bool validSource(const QUrl &url);
bool validPath(const QString &path);
bool validHash(const QString &hash);
bool validIndex(const QJsonObject &object);
bool validDocument(const QString &kind, const QJsonObject &object);
bool validAnnouncement(const QJsonObject &object);
QString localized(const QJsonValue &value, const QString &language);
QByteArray digest(const QByteArray &bytes);

} // namespace hexproof::client::public_content
