// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "DeckFormat.h"

namespace hexproof::client {

QString normalizedDeckFormat(const QString &format)
{
    const QString normalized = format.simplified().toLower();
    return normalized == QStringLiteral("edh") ? QString::fromLatin1(kDeckFormatCommander)
                                               : normalized;
}

QStringList supportedDeckFormats()
{
    return {
        QString::fromLatin1(kDeckFormatCustom),    QString::fromLatin1(kDeckFormatStandard),
        QString::fromLatin1(kDeckFormatPioneer),   QString::fromLatin1(kDeckFormatModern),
        QString::fromLatin1(kDeckFormatLegacy),    QString::fromLatin1(kDeckFormatVintage),
        QString::fromLatin1(kDeckFormatPauper),    QString::fromLatin1(kDeckFormatDuel),
        QString::fromLatin1(kDeckFormatCommander), QString::fromLatin1(kDeckFormatCube),
    };
}

bool supportedDeckFormat(const QString &format)
{
    return supportedDeckFormats().contains(normalizedDeckFormat(format));
}

bool supportedTableMode(const QString &mode)
{
    const QString normalized = mode.simplified().toLower();
    return normalized == QString::fromLatin1(kTableModeOneVsOne) ||
           normalized == QString::fromLatin1(kTableModeDuel) ||
           normalized == QString::fromLatin1(kTableModeEDH);
}

bool isCommanderTableMode(const QString &mode)
{
    const QString normalized = mode.simplified().toLower();
    return normalized == QString::fromLatin1(kTableModeDuel) ||
           normalized == QString::fromLatin1(kTableModeEDH);
}

bool isCubeDeckFormat(const QString &format)
{
    return normalizedDeckFormat(format) == QString::fromLatin1(kDeckFormatCube);
}

bool isNamedConstructedFormat(const QString &format)
{
    const QString normalized = normalizedDeckFormat(format);
    return supportedDeckFormat(normalized) &&
           normalized != QString::fromLatin1(kDeckFormatCustom) &&
           normalized != QString::fromLatin1(kDeckFormatCube);
}

QString tableModeForDeckFormat(const QString &format)
{
    const QString normalized = normalizedDeckFormat(format);
    if (normalized == QString::fromLatin1(kDeckFormatDuel))
        return QString::fromLatin1(kTableModeDuel);
    if (normalized == QString::fromLatin1(kDeckFormatCommander))
        return QString::fromLatin1(kTableModeEDH);
    return supportedDeckFormat(normalized) ? QString::fromLatin1(kTableModeOneVsOne) : QString{};
}

QString defaultDeckFormatForTableMode(const QString &mode)
{
    const QString normalized = mode.simplified().toLower();
    if (normalized == QString::fromLatin1(kTableModeDuel))
        return QString::fromLatin1(kDeckFormatDuel);
    if (normalized == QString::fromLatin1(kTableModeEDH))
        return QString::fromLatin1(kDeckFormatCommander);
    return normalized == QString::fromLatin1(kTableModeOneVsOne)
               ? QString::fromLatin1(kDeckFormatCustom)
               : QString{};
}

} // namespace hexproof::client
