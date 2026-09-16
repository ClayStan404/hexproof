// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QAbstractListModel>
#include <QSet>
#include <QVector>
#include <utility>

namespace hexproof::client {

// Preserve table delegates across priority snapshots. Prompt models deliberately
// keep their separate reset semantics because response ids belong to a decision.
class RulesSnapshotModel : public QAbstractListModel
{
  public:
    using QAbstractListModel::QAbstractListModel;

  protected:
    template <typename Row, typename KeyFor>
    void replaceRows(QVector<Row> &current, QVector<Row> incoming, KeyFor keyFor)
    {
        if (current == incoming)
            return;

        QSet<decltype(keyFor(Row{}))> incomingKeys;
        QSet<decltype(keyFor(Row{}))> currentKeys;
        for (const Row &row : std::as_const(incoming))
            incomingKeys.insert(keyFor(row));
        for (const Row &row : std::as_const(current))
            currentKeys.insert(keyFor(row));
        // Ambiguous identities cannot preserve delegates safely.
        if (incomingKeys.size() != incoming.size() || currentKeys.size() != current.size()) {
            beginResetModel();
            current = std::move(incoming);
            endResetModel();
            return;
        }

        for (int row = current.size() - 1; row >= 0; --row) {
            if (incomingKeys.contains(keyFor(current.at(row))))
                continue;
            beginRemoveRows({}, row, row);
            current.removeAt(row);
            endRemoveRows();
        }

        for (int target = 0; target < incoming.size(); ++target) {
            const Row &next = incoming.at(target);
            const auto key = keyFor(next);
            int source = target;
            while (source < current.size() && keyFor(current.at(source)) != key)
                ++source;
            if (source == current.size()) {
                beginInsertRows({}, target, target);
                current.insert(target, next);
                endInsertRows();
                continue;
            }
            if (source != target) {
                beginMoveRows({}, source, source, {}, target);
                current.move(source, target);
                endMoveRows();
            }
            if (current.at(target) != next) {
                current[target] = next;
                emit dataChanged(index(target), index(target));
            }
        }
    }
};

} // namespace hexproof::client
