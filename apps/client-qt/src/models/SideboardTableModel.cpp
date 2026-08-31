// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "SideboardTableModel.h"

#include <QHash>
#include <QStringList>
#include <QVariantMap>

#include <algorithm>

namespace hexproof::client {
namespace {

const QStringList &categoryOrder()
{
    static const QStringList categories{
        QStringLiteral("Artifact"), QStringLiteral("Creature"), QStringLiteral("Enchantment"),
        QStringLiteral("Instant"),  QStringLiteral("Land"),     QStringLiteral("Planeswalker"),
        QStringLiteral("Sorcery"),  QStringLiteral("Other"),
    };
    return categories;
}

QString categoryForTypeLine(QString typeLine)
{
    typeLine = typeLine.toLower();
    const qsizetype faceSeparator = typeLine.indexOf(QStringLiteral(" // "));
    if (faceSeparator >= 0)
        typeLine.truncate(faceSeparator);

    qsizetype subtypeSeparator = -1;
    for (const QChar separator : {QChar(0x2014), QChar(0x2013), QChar(0xff5e), QChar(0x301c)}) {
        const qsizetype candidate = typeLine.indexOf(separator);
        if (candidate >= 0 && (subtypeSeparator < 0 || candidate < subtypeSeparator))
            subtypeSeparator = candidate;
    }
    if (subtypeSeparator >= 0)
        typeLine.truncate(subtypeSeparator);

    if (typeLine.contains(QStringLiteral("land")) || typeLine.contains(QChar(0x5730)))
        return QStringLiteral("Land");
    if (typeLine.contains(QStringLiteral("creature")) ||
        typeLine.contains(QStringLiteral("生物"))) {
        return QStringLiteral("Creature");
    }
    if (typeLine.contains(QStringLiteral("planeswalker")) ||
        typeLine.contains(QStringLiteral("鹏洛客")) ||
        typeLine.contains(QStringLiteral("旅法师"))) {
        return QStringLiteral("Planeswalker");
    }
    if (typeLine.contains(QStringLiteral("artifact")) ||
        typeLine.contains(QStringLiteral("神器"))) {
        return QStringLiteral("Artifact");
    }
    if (typeLine.contains(QStringLiteral("enchantment")) ||
        typeLine.contains(QStringLiteral("结界"))) {
        return QStringLiteral("Enchantment");
    }
    if (typeLine.contains(QStringLiteral("instant")) || typeLine.contains(QStringLiteral("瞬间"))) {
        return QStringLiteral("Instant");
    }
    if (typeLine.contains(QStringLiteral("sorcery")) || typeLine.contains(QStringLiteral("法术"))) {
        return QStringLiteral("Sorcery");
    }
    return QStringLiteral("Other");
}

} // namespace

SideboardTableModel::SideboardTableModel(QObject *parent)
    : QObject(parent)
{
}

void SideboardTableModel::setMainboardCards(const QVariantList &cards)
{
    if (m_mainboardCards == cards)
        return;
    m_mainboardCards = cards;
    const GroupedCards grouped = buildGroups(cards);
    m_mainboardGroups = grouped.groups;
    m_mainboardCount = grouped.count;
    emit mainboardChanged();
}

void SideboardTableModel::setSideboardCards(const QVariantList &cards)
{
    if (m_sideboardCards == cards)
        return;
    m_sideboardCards = cards;
    const GroupedCards grouped = buildGroups(cards);
    m_sideboardGroups = grouped.groups;
    m_sideboardCount = grouped.count;
    emit sideboardChanged();
}

QString SideboardTableModel::cardCategory(const QString &typeLine) const
{
    return categoryForTypeLine(typeLine);
}

QVariantList SideboardTableModel::groupCards(const QVariantList &cards) const
{
    return buildGroups(cards).groups;
}

SideboardTableModel::GroupedCards SideboardTableModel::buildGroups(const QVariantList &cards)
{
    struct Pile
    {
        QString name;
        QString setCode;
        QString collectorNumber;
        QString typeLine;
        QString category;
        bool virtualCard = false;
        int count = 0;
    };

    QHash<QString, QList<Pile>> pilesByCategory;
    QHash<QString, QPair<QString, qsizetype>> locations;
    int totalCount = 0;
    for (const QVariant &value : cards) {
        const QVariantMap card = value.toMap();
        const QString name = card.value(QStringLiteral("name")).toString();
        const QString typeLine = card.value(QStringLiteral("typeLine")).toString();
        const QString category = categoryForTypeLine(typeLine);
        const int quantity = std::max(1, card.value(QStringLiteral("count"), 1).toInt());
        const QString setCode = card.value(QStringLiteral("setCode")).toString();
        const QString collectorNumber = card.value(QStringLiteral("collectorNumber")).toString();
        const bool virtualCard = setCode.trimmed().isEmpty() && collectorNumber.trimmed().isEmpty();
        const QString key = category + QChar(0x0001) + name.trimmed().toCaseFolded() +
                            QChar(0x0001) +
                            (virtualCard ? QStringLiteral("virtual") : QStringLiteral("printed"));
        totalCount += quantity;

        const auto existing = locations.constFind(key);
        if (existing != locations.cend()) {
            pilesByCategory[existing->first][existing->second].count += quantity;
            continue;
        }

        QList<Pile> &categoryPiles = pilesByCategory[category];
        locations.insert(key, qMakePair(category, categoryPiles.size()));
        categoryPiles.append(Pile{
            .name = name,
            .setCode = setCode,
            .collectorNumber = collectorNumber,
            .typeLine = typeLine,
            .category = category,
            .virtualCard = virtualCard,
            .count = quantity,
        });
    }

    QVariantList groups;
    int tableIndex = 0;
    for (const QString &category : categoryOrder()) {
        QList<Pile> categoryPiles = pilesByCategory.value(category);
        if (categoryPiles.isEmpty())
            continue;
        std::sort(categoryPiles.begin(), categoryPiles.end(),
                  [](const Pile &left, const Pile &right) {
                      return QString::localeAwareCompare(left.name, right.name) < 0;
                  });

        QVariantList pileCards;
        int categoryCount = 0;
        for (const Pile &pile : std::as_const(categoryPiles)) {
            pileCards.append(QVariantMap{
                {QStringLiteral("name"), pile.name},
                {QStringLiteral("count"), 1},
                {QStringLiteral("pileCount"), pile.count},
                {QStringLiteral("setCode"), pile.setCode},
                {QStringLiteral("collectorNumber"), pile.collectorNumber},
                {QStringLiteral("typeLine"), pile.typeLine},
                {QStringLiteral("category"), pile.category},
                {QStringLiteral("virtualCard"), pile.virtualCard},
                {QStringLiteral("tableIndex"), tableIndex++},
            });
            categoryCount += pile.count;
        }
        groups.append(QVariantMap{
            {QStringLiteral("category"), category},
            {QStringLiteral("count"), categoryCount},
            {QStringLiteral("cards"), pileCards},
        });
    }
    return GroupedCards{.groups = groups, .count = totalCount};
}

} // namespace hexproof::client
