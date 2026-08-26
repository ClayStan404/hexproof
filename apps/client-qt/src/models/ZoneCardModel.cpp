// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "ZoneCardModel.h"

#include <QSet>

#include <utility>

using namespace Qt::StringLiterals;

namespace hexproof::client {

ZoneCardModel::ZoneCardModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int ZoneCardModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_cards.size();
}

QVariant ZoneCardModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_cards.size())
        return {};

    const QVariantMap card = m_cards.at(index.row()).toMap();
    const QVariantMap position = card.value(u"position"_s).toMap();
    switch (role) {
    case CardIdRole:
        return card.value(u"id"_s);
    case NameRole:
        return card.value(u"name"_s);
    case SetCodeRole:
        return card.value(u"setCode"_s);
    case CollectorNumberRole:
        return card.value(u"collectorNumber"_s);
    case OwnerSeatRole:
        return card.value(u"ownerSeat"_s, -1);
    case CommanderRole:
        return card.value(u"commander"_s, false);
    case FaceNameRole:
        return card.value(u"faceName"_s);
    case FaceDownRole:
        return card.value(u"faceDown"_s, false);
    case HasPositionRole:
        return !position.isEmpty();
    case PositionXRole:
        return position.value(u"x"_s, 0.0);
    case PositionYRole:
        return position.value(u"y"_s, 0.0);
    case TokenRole:
        return card.value(u"token"_s, false);
    case TappedRole:
        return card.value(u"tapped"_s, false);
    case CountersRole:
        return card.value(u"counters"_s);
    case CardDataRole:
        return card;
    default:
        return {};
    }
}

QHash<int, QByteArray> ZoneCardModel::roleNames() const
{
    return {
        {CardIdRole, "cardId"},           {NameRole, "name"},
        {SetCodeRole, "setCode"},         {CollectorNumberRole, "collectorNumber"},
        {OwnerSeatRole, "ownerSeat"},     {CommanderRole, "commander"},
        {FaceNameRole, "faceName"},       {FaceDownRole, "faceDown"},
        {HasPositionRole, "hasPosition"}, {PositionXRole, "positionX"},
        {PositionYRole, "positionY"},     {TokenRole, "token"},
        {TappedRole, "tapped"},           {CountersRole, "counters"},
        {CardDataRole, "cardData"},
    };
}

quint64 ZoneCardModel::revision() const
{
    return m_revision;
}

QVariantMap ZoneCardModel::get(int row) const
{
    if (row < 0 || row >= m_cards.size())
        return {};
    return m_cards.at(row).toMap();
}

void ZoneCardModel::replaceCards(const QVariantList &cards)
{
    if (m_cards == cards)
        return;

    const auto cardId = [](const QVariant &value) {
        return value.toMap().value(u"id"_s).toString();
    };
    QSet<QString> incomingIds;
    bool canReconcile = true;
    for (const QVariant &card : cards) {
        const QString id = cardId(card);
        if (id.isEmpty() || incomingIds.contains(id)) {
            canReconcile = false;
            break;
        }
        incomingIds.insert(id);
    }
    if (canReconcile) {
        QSet<QString> currentIds;
        for (const QVariant &card : std::as_const(m_cards)) {
            const QString id = cardId(card);
            if (id.isEmpty() || currentIds.contains(id)) {
                canReconcile = false;
                break;
            }
            currentIds.insert(id);
        }
    }

    const int previousCount = m_cards.size();
    if (!canReconcile) {
        beginResetModel();
        m_cards = cards;
        endResetModel();
    } else {
        for (int row = m_cards.size() - 1; row >= 0; --row) {
            if (incomingIds.contains(cardId(m_cards.at(row))))
                continue;
            beginRemoveRows({}, row, row);
            m_cards.removeAt(row);
            endRemoveRows();
        }

        for (int targetRow = 0; targetRow < cards.size(); ++targetRow) {
            const QVariant &incoming = cards.at(targetRow);
            const QString incomingId = cardId(incoming);
            int currentRow = -1;
            for (int row = targetRow; row < m_cards.size(); ++row) {
                if (cardId(m_cards.at(row)) == incomingId) {
                    currentRow = row;
                    break;
                }
            }
            if (currentRow < 0) {
                beginInsertRows({}, targetRow, targetRow);
                m_cards.insert(targetRow, incoming);
                endInsertRows();
                continue;
            }
            if (currentRow != targetRow) {
                beginMoveRows({}, currentRow, currentRow, {}, targetRow);
                m_cards.move(currentRow, targetRow);
                endMoveRows();
            }
            if (m_cards.at(targetRow) != incoming) {
                m_cards[targetRow] = incoming;
                emit dataChanged(index(targetRow), index(targetRow));
            }
        }
    }

    ++m_revision;
    if (previousCount != m_cards.size())
        emit countChanged();
    emit cardsChanged();
}

} // namespace hexproof::client
