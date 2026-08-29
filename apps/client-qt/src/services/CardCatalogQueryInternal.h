// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
#pragma once
#include "CardCatalogCommon.h"
namespace hexproof::client::catalog_internal {

inline QString escapedLike(const QString &text)
{
    QString escaped = text;
    escaped.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
    escaped.replace(QLatin1Char('%'), QStringLiteral("\\%"));
    escaped.replace(QLatin1Char('_'), QStringLiteral("\\_"));
    return escaped;
}

inline QString fuzzyLike(const QString &text)
{
    QString pattern = QStringLiteral("%");
    for (const QChar character : text) {
        if (character.isSpace())
            continue;
        pattern += escapedLike(QString(character)) + QLatin1Char('%');
    }
    return pattern;
}

inline QString catalogNameMatchesSql(const QString &columnPrefix = QStringLiteral("c."))
{
    return QStringLiteral("(%1name = ? COLLATE NOCASE "
                          "OR (instr(%1name, ' // ') > 0 AND ("
                          "substr(%1name, 1, instr(%1name, ' // ') - 1) = ? COLLATE NOCASE "
                          "OR substr(%1name, instr(%1name, ' // ') + 4) = ? COLLATE NOCASE)))")
        .arg(columnPrefix);
}

inline QString catalogPlayablePrintingSql(const QString &columnPrefix = QStringLiteral("c."))
{
    return QStringLiteral("COALESCE(%1layout, '') NOT IN "
                          "('art_series','token','double_faced_token','emblem')")
        .arg(columnPrefix);
}

inline QString localizedNameExpression(const QString &cardAlias)
{
    return QStringLiteral("COALESCE(("
                          "SELECT group_concat(localized_name, ' // ') FROM ("
                          "SELECT localized_name FROM card_aliases ax "
                          "WHERE ax.oracle_id = %1.oracle_id AND ax.preferred = 1 "
                          "ORDER BY ax.face_order)), NULLIF(%1.printed_name, ''))")
        .arg(cardAlias);
}

inline QString localizedTypeExpression(const QString &cardAlias)
{
    return QStringLiteral("COALESCE((SELECT group_concat(localized_type, ' // ') FROM ("
                          "SELECT localized_type FROM card_aliases tx "
                          "WHERE tx.oracle_id = %1.oracle_id AND tx.preferred = 1 "
                          "AND tx.localized_type != '' ORDER BY tx.face_order)), %1.type_line)")
        .arg(cardAlias);
}

} // namespace hexproof::client::catalog_internal
