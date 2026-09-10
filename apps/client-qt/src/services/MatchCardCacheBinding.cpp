// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "MatchCardCacheBinding.h"

#include "MatchLoadCoordinator.h"
#include "RoomSessionState.h"
#include "RulesSessionState.h"
#include "models/GameTableModel.h"

#include <QSet>
#include <QStringList>

namespace hexproof::client {
namespace {

QVariantList visibleRulesCards(RulesSessionState *rules)
{
    QVariantList requests;
    QSet<QStringList> seen;
    const auto append = [&requests, &seen](const QVariantMap &card) {
        const QString name = card.value(QStringLiteral("name")).toString().simplified();
        if (name.isEmpty())
            return;
        const QString set = card.value(QStringLiteral("setCode")).toString().toUpper();
        const QString number = card.value(QStringLiteral("collectorNumber")).toString();
        const QStringList key{name.toCaseFolded(), set, number};
        if (seen.contains(key))
            return;
        seen.insert(key);
        requests.append(QVariantMap{{QStringLiteral("name"), name},
                                    {QStringLiteral("setCode"), set},
                                    {QStringLiteral("collectorNumber"), number}});
    };
    const auto appendModel = [&append](QAbstractItemModel *model) {
        const auto roles = model->roleNames();
        const int nameRole = roles.key("name", -1);
        const int setRole = roles.key("setCode", -1);
        const int numberRole = roles.key("collectorNumber", -1);
        const int visibleRole = roles.key("visibleIdentity", -1);
        for (int row = 0; row < model->rowCount(); ++row) {
            const QModelIndex index = model->index(row, 0);
            if (visibleRole >= 0 && !model->data(index, visibleRole).toBool())
                continue;
            append({{QStringLiteral("name"), model->data(index, nameRole)},
                    {QStringLiteral("setCode"), model->data(index, setRole)},
                    {QStringLiteral("collectorNumber"), model->data(index, numberRole)}});
        }
    };

    // These models contain only the current viewer's authorized identities.
    // Never infer an identity from object ids, labels, or hidden-zone counts.
    appendModel(rules->zoneCards());
    appendModel(rules->battlefieldCards());
    appendModel(rules->stack());
    if (rules->promptPending()) {
        appendModel(rules->promptCards());
        appendModel(rules->promptContextCards());
        appendModel(rules->promptTargets());
        appendModel(rules->promptContextTargets());
        appendModel(rules->promptOrderItems());
        appendModel(rules->promptCombat());
        appendModel(rules->promptDamageTargets());
        append(rules->promptDamageSource());
    }
    return requests;
}

} // namespace

MatchCardCacheBinding::MatchCardCacheBinding(GameTableModel *table, RulesSessionState *rules,
                                             RoomSessionState *room, MatchLoadCoordinator *loader,
                                             QObject *parent)
    : QObject(parent),
      m_table(table),
      m_rules(rules),
      m_room(room),
      m_loader(loader)
{
    m_visibleTimer.setSingleShot(true);
    m_visibleTimer.setInterval(0);
    connect(&m_visibleTimer, &QTimer::timeout, this,
            &MatchCardCacheBinding::prioritizeVisibleRulesCards);
    connect(table, &GameTableModel::snapshotChanged, this, &MatchCardCacheBinding::synchronize);
    connect(rules, &RulesSessionState::snapshotChanged, this, &MatchCardCacheBinding::synchronize);
    connect(rules, &RulesSessionState::promptChanged, this, &MatchCardCacheBinding::synchronize);
    connect(room, &RoomSessionState::snapshotChanged, this, &MatchCardCacheBinding::synchronize);
    connect(room, &RoomSessionState::roomIdChanged, this, &MatchCardCacheBinding::synchronize);
}

void MatchCardCacheBinding::setInRoom(bool inRoom)
{
    m_inRoom = inRoom;
    synchronize();
    if (!inRoom)
        m_loader->cancel();
}

bool MatchCardCacheBinding::hasCurrentRulesSnapshot() const
{
    return m_inRoom && !m_room->roomId().isEmpty() &&
           m_room->rulesMode() == QStringLiteral("forge") && m_rules->active() &&
           m_rules->roomId() == m_room->roomId();
}

void MatchCardCacheBinding::synchronize()
{
    const bool rulesReady = hasCurrentRulesSnapshot();
    const bool manualReady = m_inRoom && !m_room->roomId().isEmpty() &&
                             m_room->rulesMode() == QStringLiteral("manual") &&
                             m_table->hasSnapshot();
    m_loader->handleTableSnapshotStateChanged(rulesReady || manualReady);
    const QString gameId = rulesReady ? m_rules->gameId() : QString();
    if (gameId != m_visibleGameId) {
        m_visibleTimer.stop();
        m_visibleGameId = gameId;
        m_lastVisibleRequests.clear();
    }
    if (rulesReady && !m_visibleTimer.isActive())
        m_visibleTimer.start();
}

void MatchCardCacheBinding::refreshVisibleCards()
{
    // Language/provider changes invalidate priorities; image completion does not.
    m_lastVisibleRequests.clear();
    synchronize();
}

void MatchCardCacheBinding::prioritizeVisibleRulesCards()
{
    if (!hasCurrentRulesSnapshot())
        return;
    const QVariantList requests = visibleRulesCards(m_rules);
    if (requests == m_lastVisibleRequests)
        return;
    m_lastVisibleRequests = requests;
    if (!requests.isEmpty())
        emit visibleRulesCardsRequested(requests);
}

} // namespace hexproof::client
