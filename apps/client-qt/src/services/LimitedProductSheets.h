// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QVariantMap>

namespace hexproof::client {

inline bool limitedReferenceInteger(const QVariant &value)
{
    const int type = value.metaType().id();
    return (type == QMetaType::Int || type == QMetaType::UInt || type == QMetaType::LongLong ||
            type == QMetaType::ULongLong || type == QMetaType::Double ||
            type == QMetaType::Float) &&
           value.toDouble() == static_cast<double>(value.toLongLong());
}

// Resolve references for generation/art only; callers keep the compact
// catalog definition for transmission and hashing.
inline bool resolveLimitedProductSheets(const QVariantMap &product, QVariantList *resolved)
{
    const QVariantList pool = product.value(QStringLiteral("cardPool")).toList();
    const QVariantList sheets = product.value(QStringLiteral("sheets")).toList();
    if (pool.size() > 10000 || sheets.isEmpty() || sheets.size() > 128)
        return false;
    for (const QVariant &value : pool) {
        const QVariantMap card = value.toMap();
        if (card.value(QStringLiteral("name")).toString().trimmed().isEmpty() ||
            card.value(QStringLiteral("setCode")).toString().trimmed().isEmpty() ||
            card.value(QStringLiteral("collectorNumber")).toString().trimmed().isEmpty() ||
            !limitedReferenceInteger(card.value(QStringLiteral("weight"))) ||
            card.value(QStringLiteral("weight")).toLongLong() != 1)
            return false;
    }
    QVariantList result;
    qsizetype total = 0;
    for (const QVariant &sheetValue : sheets) {
        QVariantMap sheet = sheetValue.toMap();
        QVariantList cards = sheet.value(QStringLiteral("cards")).toList();
        const QVariantList refs = sheet.value(QStringLiteral("cardRefs")).toList();
        total += cards.size() + refs.size();
        if (total > 10000 || (!cards.isEmpty() && !refs.isEmpty()))
            return false;
        for (const QVariant &refValue : refs) {
            const QVariantMap ref = refValue.toMap();
            const QVariant indexValue = ref.value(QStringLiteral("cardIndex"));
            const QVariant weightValue = ref.value(QStringLiteral("weight"));
            const qint64 index = indexValue.toLongLong();
            const qint64 weight = weightValue.toLongLong();
            if (!limitedReferenceInteger(indexValue) || !limitedReferenceInteger(weightValue) ||
                index < 1 || index > pool.size() || weight < 1 || weight > 9007199254740991LL)
                return false;
            QVariantMap card = pool.at(index - 1).toMap();
            card.insert(QStringLiteral("weight"), weight);
            cards.append(card);
        }
        if (cards.isEmpty())
            return false;
        sheet.insert(QStringLiteral("cards"), cards);
        result.append(sheet);
    }
    *resolved = result;
    return true;
}

} // namespace hexproof::client
