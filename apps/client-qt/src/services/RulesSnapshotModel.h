// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QAbstractListModel>
#include <QSet>
#include <QVector>
#include <utility>

namespace hexproof::client {

// Preserve delegates across snapshots and decisions: rows with the same key
// move or change in place, other rows are removed or inserted.
class RulesSnapshotModel : public QAbstractListModel
{
  public:
    using QAbstractListModel::QAbstractListModel;

  protected:
    enum class Ambiguous
    {
        Reset,
        // For views that may still be incubating delegates: a reset can cancel
        // an index after Qt has already replaced the rows.
        RemoveAndInsert
    };

    template <typename Row, typename KeyFor>
    void replaceRows(QVector<Row> &current, QVector<Row> incoming, KeyFor keyFor,
                     Ambiguous ambiguous = Ambiguous::Reset)
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
            if (ambiguous == Ambiguous::Reset) {
                beginResetModel();
                current = std::move(incoming);
                endResetModel();
                return;
            }
            if (!current.isEmpty()) {
                beginRemoveRows({}, 0, int(current.size() - 1));
                current.clear();
                endRemoveRows();
            }
            if (!incoming.isEmpty()) {
                beginInsertRows({}, 0, int(incoming.size() - 1));
                current = std::move(incoming);
                endInsertRows();
            }
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
