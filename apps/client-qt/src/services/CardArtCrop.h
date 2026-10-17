// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QRegularExpression>
#include <QString>
#include <QUrl>

namespace hexproof::client::catalog_internal {

// Derive only a known CDN variant of the actual selected image. Never infer
// another printing, face, language, or provider from the requested card name.
inline QString artCropUrlForImage(const QString &imageUrl)
{
    QUrl url(imageUrl, QUrl::StrictMode);
    if (!url.isValid() || url.scheme() != QStringLiteral("https") ||
        url.host() != QStringLiteral("cards.scryfall.io") ||
        (url.port() != -1 && url.port() != 443) || !url.userInfo().isEmpty() || url.hasFragment())
        return {};
    static const QRegularExpression pattern(
        QStringLiteral("^/(?:normal|large|small)/(front|back)/([0-9a-f])/([0-9a-f])/"
                       "([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\\.jpg$"));
    const QRegularExpressionMatch match = pattern.match(url.path());
    if (!match.hasMatch() || !match.captured(4).startsWith(match.captured(2) + match.captured(3)))
        return {};
    url.setPath(QStringLiteral("/art_crop/") + match.captured(1) + QLatin1Char('/') +
                match.captured(2) + QLatin1Char('/') + match.captured(3) + QLatin1Char('/') +
                match.captured(4) + QStringLiteral(".jpg"));
    return url.toString();
}

} // namespace hexproof::client::catalog_internal
