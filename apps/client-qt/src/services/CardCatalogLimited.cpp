// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "CardCatalog.h"
#include "CatalogRepository.h"

#include <QMap>
#include <QRandomGenerator>

namespace hexproof::client {

namespace {
int weightedIndex(const QVariantList &values)
{
    qint64 total = 0;
    for (const QVariant &value : values)
        total += qMax<qint64>(0, value.toMap().value(QStringLiteral("weight"), 1).toLongLong());
    if (total <= 0)
        return -1;
    quint64 choice = QRandomGenerator::global()->generate64() % static_cast<quint64>(total);
    for (int index = 0; index < values.size(); ++index) {
        const quint64 weight = static_cast<quint64>(qMax<qint64>(
            0, values.at(index).toMap().value(QStringLiteral("weight"), 1).toLongLong()));
        if (choice < weight)
            return index;
        choice -= weight;
    }
    return values.size() - 1;
}

QVariantMap sheetByName(const QVariantList &sheets, const QString &name)
{
    for (const QVariant &sheetValue : sheets) {
        const QVariantMap sheet = sheetValue.toMap();
        if (sheet.value(QStringLiteral("name")).toString() == name)
            return sheet;
    }
    return {};
}

QVariantMap localCard(QVariantMap card, int serial)
{
    card.remove(QStringLiteral("weight"));
    card.insert(QStringLiteral("instanceId"), QStringLiteral("local-%1").arg(serial));
    return card;
}
} // namespace

QVariantList CardCatalog::limitedProducts() const
{
    if (m_catalogBusy || !installed())
        return {};
    return guiCatalog().limitedProducts();
}

QVariantList CardCatalog::limitedSets() const
{
    const QVariantList products = limitedProducts();
    QMap<QString, QVariantMap> preferredBySet;
    QMap<QString, int> rankBySet;
    const auto productRank = [](const QVariantMap &product) {
        const QString id = product.value(QStringLiteral("id")).toString().toLower();
        if (id.endsWith(QStringLiteral("-play")))
            return 400;
        if (id.endsWith(QStringLiteral("-draft")))
            return 350;
        if (id.endsWith(QStringLiteral("-default")))
            return 300;
        if (product.value(QStringLiteral("productType")).toString() ==
            QStringLiteral("approximate"))
            return 100;
        if (id.contains(QStringLiteral("collector")) || id.contains(QStringLiteral("sample")) ||
            id.contains(QStringLiteral("jumpstart")) || id.contains(QStringLiteral("theme")))
            return 0;
        return 200;
    };
    for (const QVariant &value : products) {
        QVariantMap product = value.toMap();
        const QString setCode = product.value(QStringLiteral("setCode")).toString().toUpper();
        const int rank = productRank(product);
        if (setCode.isEmpty() || rank == 0 || rank <= rankBySet.value(setCode, -1))
            continue;
        QString name = product.value(QStringLiteral("name")).toString();
        const qsizetype separator = name.indexOf(QStringLiteral(" — "));
        if (separator > 0)
            name = name.left(separator);
        if (name.endsWith(QStringLiteral(" approximate booster"), Qt::CaseInsensitive))
            name = setCode;
        product.insert(QStringLiteral("id"), setCode);
        product.insert(QStringLiteral("name"), QStringLiteral("%1 · %2").arg(setCode, name));
        product.insert(QStringLiteral("productId"), value.toMap().value(QStringLiteral("id")));
        product.insert(QStringLiteral("productName"), value.toMap().value(QStringLiteral("name")));
        product.insert(QStringLiteral("boosterKind"),
                       rank >= 400 ? QStringLiteral("play") : QStringLiteral("draft"));
        preferredBySet.insert(setCode, product);
        rankBySet.insert(setCode, rank);
    }

    QVariantList result;
    result.reserve(preferredBySet.size());
    for (auto iterator = preferredBySet.cbegin(); iterator != preferredBySet.cend(); ++iterator)
        result.append(iterator.value());
    return result;
}

QVariantMap CardCatalog::limitedProduct(const QString &productId) const
{
    if (m_catalogBusy || !installed())
        return {};
    return guiCatalog().limitedProduct(productId);
}

QVariantList CardCatalog::simulateLimitedPacks(const QVariantMap &product, int packCount) const
{
    QVariantList result;
    if (packCount < 1 || packCount > 36)
        return result;
    const int cardsPerPack = product.value(QStringLiteral("cardsPerPack")).toInt();
    const QVariantList sheets = product.value(QStringLiteral("sheets")).toList();
    if (cardsPerPack < 1 || cardsPerPack > 30 || sheets.isEmpty())
        return result;

    int serial = 0;
    if (product.value(QStringLiteral("productType")).toString() == QStringLiteral("cube")) {
        QVariantList stock;
        for (const QVariant &sheetValue : sheets) {
            const QVariantList cards = sheetValue.toMap().value(QStringLiteral("cards")).toList();
            for (const QVariant &cardValue : cards) {
                const QVariantMap card = cardValue.toMap();
                const int quantity =
                    qBound(1, card.value(QStringLiteral("weight"), 1).toInt(), 10000);
                for (int copy = 0; copy < quantity; ++copy)
                    stock.append(card);
            }
        }
        if (stock.size() < packCount * cardsPerPack)
            return {};
        for (int index = stock.size() - 1; index > 0; --index)
            stock.swapItemsAt(index, QRandomGenerator::global()->bounded(index + 1));
        for (int packIndex = 0; packIndex < packCount; ++packIndex) {
            QVariantList cards;
            for (int cardIndex = 0; cardIndex < cardsPerPack; ++cardIndex)
                cards.append(
                    localCard(stock.at(packIndex * cardsPerPack + cardIndex).toMap(), ++serial));
            result.append(QVariantMap{{QStringLiteral("cards"), cards}});
        }
        return result;
    }

    const QVariantList variants = product.value(QStringLiteral("variants")).toList();
    if (variants.isEmpty())
        return result;
    for (int packIndex = 0; packIndex < packCount; ++packIndex) {
        const int variantIndex = weightedIndex(variants);
        if (variantIndex < 0)
            return {};
        const QVariantList packSlots =
            variants.at(variantIndex).toMap().value(QStringLiteral("slots")).toList();
        QVariantList packCards;
        for (const QVariant &slotValue : packSlots) {
            const QVariantMap slot = slotValue.toMap();
            const QVariantMap sheet =
                sheetByName(sheets, slot.value(QStringLiteral("sheet")).toString());
            QVariantList available = sheet.value(QStringLiteral("cards")).toList();
            const bool replacement = sheet.value(QStringLiteral("withReplacement")).toBool();
            const int count = slot.value(QStringLiteral("count")).toInt();
            for (int cardIndex = 0; cardIndex < count; ++cardIndex) {
                const int choice = weightedIndex(available);
                if (choice < 0)
                    return {};
                packCards.append(localCard(available.at(choice).toMap(), ++serial));
                if (!replacement)
                    available.removeAt(choice);
            }
        }
        if (packCards.size() != cardsPerPack)
            return {};
        result.append(QVariantMap{{QStringLiteral("cards"), packCards}});
    }
    return result;
}

} // namespace hexproof::client
