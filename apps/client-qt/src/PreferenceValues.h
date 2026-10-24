// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QString>

#include <algorithm>
#include <cmath>

namespace hexproof::client::preferenceValues {

inline QString cardArtProvider(const QString &provider)
{
    const QString lowered = provider.toLower();
    return lowered == QStringLiteral("mtgch") || lowered == QStringLiteral("scryfall") ||
                   lowered == QStringLiteral("parallel")
               ? lowered
               : QStringLiteral("auto");
}

inline qreal interfaceScale(qreal scale)
{
    if (!std::isfinite(scale))
        return 1.0;
    return std::clamp(std::round(scale * 20.0) / 20.0, 0.75, 1.5);
}

inline QString uiTheme(const QString &theme)
{
    return theme.compare(QStringLiteral("glass"), Qt::CaseInsensitive) == 0
               ? QStringLiteral("glass")
               : QStringLiteral("classic");
}

inline qreal tableCardScale(qreal scale)
{
    if (!std::isfinite(scale) || scale <= 0.0)
        return 0.0;
    return std::clamp(std::round(scale * 20.0) / 20.0, 0.5, 1.25);
}

inline qreal tableControlPosition(qreal position)
{
    if (!std::isfinite(position) || position < 0.0)
        return -1.0;
    return std::clamp(position, 0.0, 1.0);
}

} // namespace hexproof::client::preferenceValues
