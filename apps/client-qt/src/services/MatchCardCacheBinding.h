// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantList>

namespace hexproof::client {

class GameTableModel;
class MatchLoadCoordinator;
class RoomSessionState;
class RulesSessionState;

// Runtime wiring shared by both table modes, independent of card network services.
class MatchCardCacheBinding final : public QObject
{
    Q_OBJECT

  public:
    MatchCardCacheBinding(GameTableModel *table, RulesSessionState *rules, RoomSessionState *room,
                          MatchLoadCoordinator *loader, QObject *parent = nullptr);

  public slots:
    void setInRoom(bool inRoom);
    void refreshVisibleCards();

  signals:
    void visibleRulesCardsRequested(const QVariantList &cards);

  private:
    bool hasCurrentRulesSnapshot() const;
    void synchronize();
    void prioritizeVisibleRulesCards();

    GameTableModel *m_table;
    RulesSessionState *m_rules;
    RoomSessionState *m_room;
    MatchLoadCoordinator *m_loader;
    bool m_inRoom = false;
    QString m_visibleGameId;
    QVariantList m_lastVisibleRequests;
    QTimer m_visibleTimer;
};

} // namespace hexproof::client
