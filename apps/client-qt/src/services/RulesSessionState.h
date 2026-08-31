// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include "RulesChoiceModel.h"
#include "RulesCombatModel.h"
#include "RulesDamageModel.h"
#include "RulesOrderModel.h"
#include "RulesStateModels.h"

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QStringList>

namespace hexproof::client {

class RulesSessionState final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active NOTIFY snapshotChanged)
    Q_PROPERTY(QString roomId READ roomId NOTIFY snapshotChanged)
    Q_PROPERTY(QString gameId READ gameId NOTIFY snapshotChanged)
    Q_PROPERTY(int turn READ turn NOTIFY snapshotChanged)
    Q_PROPERTY(QString step READ step NOTIFY snapshotChanged)
    Q_PROPERTY(int activeSeat READ activeSeat NOTIFY snapshotChanged)
    Q_PROPERTY(int prioritySeat READ prioritySeat NOTIFY snapshotChanged)
    Q_PROPERTY(bool gameOver READ gameOver NOTIFY snapshotChanged)
    Q_PROPERTY(bool hasWinner READ hasWinner NOTIFY snapshotChanged)
    Q_PROPERTY(int winnerSeat READ winnerSeat NOTIFY snapshotChanged)
    Q_PROPERTY(int battlefieldCardCount READ battlefieldCardCount NOTIFY snapshotChanged)
    Q_PROPERTY(int visibleZoneCardCount READ visibleZoneCardCount NOTIFY snapshotChanged)
    Q_PROPERTY(QAbstractListModel *players READ players CONSTANT)
    Q_PROPERTY(QAbstractListModel *zones READ zones CONSTANT)
    Q_PROPERTY(QAbstractListModel *battlefieldCards READ battlefieldCards CONSTANT)
    Q_PROPERTY(QAbstractListModel *zoneCards READ zoneCards CONSTANT)
    Q_PROPERTY(QAbstractListModel *stack READ stack CONSTANT)
    Q_PROPERTY(bool promptPending READ promptPending NOTIFY promptChanged)
    Q_PROPERTY(qint64 promptId READ promptId NOTIFY promptChanged)
    Q_PROPERTY(QString promptKind READ promptKind NOTIFY promptChanged)
    Q_PROPERTY(bool promptSupported READ promptSupported NOTIFY promptChanged)
    Q_PROPERTY(QString promptTitle READ promptTitle NOTIFY promptChanged)
    Q_PROPERTY(QString promptDetail READ promptDetail NOTIFY promptChanged)
    Q_PROPERTY(int promptRequiredSelections READ promptRequiredSelections NOTIFY promptChanged)
    Q_PROPERTY(int promptMinCardSelections READ promptMinCardSelections NOTIFY promptChanged)
    Q_PROPERTY(int promptMaxCardSelections READ promptMaxCardSelections NOTIFY promptChanged)
    Q_PROPERTY(int promptMinSelections READ promptMinSelections NOTIFY promptChanged)
    Q_PROPERTY(int promptMaxSelections READ promptMaxSelections NOTIFY promptChanged)
    Q_PROPERTY(bool promptCancellable READ promptCancellable NOTIFY promptChanged)
    Q_PROPERTY(QAbstractListModel *promptOptions READ promptOptions CONSTANT)
    Q_PROPERTY(QAbstractListModel *promptChoices READ promptChoices CONSTANT)
    Q_PROPERTY(QAbstractListModel *promptCards READ promptCards CONSTANT)
    Q_PROPERTY(QStringList promptScryDestinations READ promptScryDestinations NOTIFY promptChanged)
    Q_PROPERTY(RulesOrderModel *promptOrderItems READ promptOrderItems CONSTANT)
    Q_PROPERTY(QAbstractListModel *promptContextCards READ promptContextCards CONSTANT)
    Q_PROPERTY(QAbstractListModel *promptContextTargets READ promptContextTargets CONSTANT)
    Q_PROPERTY(QString promptContextText READ promptContextText NOTIFY promptChanged)
    Q_PROPERTY(QAbstractListModel *promptTargets READ promptTargets CONSTANT)
    Q_PROPERTY(RulesCombatModel *promptCombat READ promptCombat CONSTANT)
    Q_PROPERTY(QVariantMap promptDamageSource READ promptDamageSource NOTIFY promptChanged)
    Q_PROPERTY(RulesDamageModel *promptDamageTargets READ promptDamageTargets CONSTANT)
    Q_PROPERTY(int promptTotalDamage READ promptTotalDamage NOTIFY promptChanged)
    Q_PROPERTY(bool promptDamageDeathtouch READ promptDamageDeathtouch NOTIFY promptChanged)
    Q_PROPERTY(int promptMinChoiceTotal READ promptMinChoiceTotal NOTIFY promptChanged)
    Q_PROPERTY(int promptMaxChoiceTotal READ promptMaxChoiceTotal NOTIFY promptChanged)
    Q_PROPERTY(int promptMinNumber READ promptMinNumber NOTIFY promptChanged)
    Q_PROPERTY(int promptMaxNumber READ promptMaxNumber NOTIFY promptChanged)

  public:
    explicit RulesSessionState(QObject *parent = nullptr);

    bool active() const
    {
        return !m_gameId.isEmpty();
    }
    QString roomId() const
    {
        return m_roomId;
    }
    QString gameId() const
    {
        return m_gameId;
    }
    int turn() const
    {
        return m_turn;
    }
    QString step() const
    {
        return m_step;
    }
    int activeSeat() const
    {
        return m_activeSeat;
    }
    int prioritySeat() const
    {
        return m_prioritySeat;
    }
    bool gameOver() const
    {
        return m_gameOver;
    }
    bool hasWinner() const
    {
        return m_hasWinner;
    }
    int winnerSeat() const
    {
        return m_winnerSeat;
    }
    int battlefieldCardCount() const
    {
        return m_battlefieldCardCount;
    }
    int visibleZoneCardCount() const
    {
        return m_visibleZoneCardCount;
    }
    QAbstractListModel *players()
    {
        return &m_players;
    }
    QAbstractListModel *zones()
    {
        return &m_zones;
    }
    QAbstractListModel *battlefieldCards()
    {
        return &m_battlefieldCards;
    }
    QAbstractListModel *zoneCards()
    {
        return &m_zoneCards;
    }
    QAbstractListModel *stack()
    {
        return &m_stack;
    }
    bool promptPending() const
    {
        return m_promptPending;
    }
    qint64 promptId() const
    {
        return m_promptId;
    }
    QString promptKind() const
    {
        return m_promptKind;
    }
    bool promptSupported() const
    {
        return m_promptSupported;
    }
    QString promptTitle() const
    {
        return m_promptTitle;
    }
    QString promptDetail() const
    {
        return m_promptDetail;
    }
    int promptRequiredSelections() const
    {
        return m_promptRequiredSelections;
    }
    int promptMinCardSelections() const
    {
        return m_promptMinCardSelections;
    }
    int promptMaxCardSelections() const
    {
        return m_promptMaxCardSelections;
    }
    int promptMinSelections() const
    {
        return m_promptMinSelections;
    }
    int promptMaxSelections() const
    {
        return m_promptMaxSelections;
    }
    bool promptCancellable() const
    {
        return m_promptCancellable;
    }
    QAbstractListModel *promptOptions()
    {
        return &m_promptOptions;
    }
    QAbstractListModel *promptChoices()
    {
        return &m_promptChoices;
    }
    RulesPromptCardModel *promptCards()
    {
        return &m_promptCards;
    }
    QStringList promptScryDestinations() const
    {
        return m_promptScryDestinations;
    }
    RulesOrderModel *promptOrderItems()
    {
        return &m_promptOrderItems;
    }
    QAbstractListModel *promptContextCards()
    {
        return &m_promptContextCards;
    }
    QAbstractListModel *promptContextTargets()
    {
        return &m_promptContextTargets;
    }
    QString promptContextText() const
    {
        return m_promptContextText;
    }
    QAbstractListModel *promptTargets()
    {
        return &m_promptTargets;
    }
    RulesCombatModel *promptCombat()
    {
        return &m_promptCombat;
    }
    QVariantMap promptDamageSource() const
    {
        return m_promptDamageSource;
    }
    RulesDamageModel *promptDamageTargets()
    {
        return &m_promptDamageTargets;
    }
    int promptTotalDamage() const
    {
        return m_promptTotalDamage;
    }
    bool promptDamageDeathtouch() const
    {
        return m_promptDamageDeathtouch;
    }
    int promptMinChoiceTotal() const
    {
        return m_promptMinChoiceTotal;
    }
    int promptMaxChoiceTotal() const
    {
        return m_promptMaxChoiceTotal;
    }
    int promptMinNumber() const
    {
        return m_promptMinNumber;
    }
    int promptMaxNumber() const
    {
        return m_promptMaxNumber;
    }
    Q_INVOKABLE int zoneCount(int ownerSeat, const QString &zone) const
    {
        return m_zones.countFor(ownerSeat, zone);
    }
    Q_INVOKABLE QVariantList castActionsForCard(const QString &cardId) const
    {
        if (!m_promptPending || !m_promptSupported ||
            m_promptKind != QStringLiteral("chooseAction"))
            return {};
        return m_promptOptions.castActionsForCard(cardId);
    }

    bool applySnapshot(const QJsonObject &snapshot);
    bool applyPrompt(const QJsonObject &prompt);
    void clear();

  signals:
    void snapshotChanged();
    void promptChanged();

  private:
    QString m_roomId;
    QString m_gameId;
    int m_turn = 0;
    QString m_step;
    int m_activeSeat = -1;
    int m_prioritySeat = -1;
    bool m_gameOver = false;
    bool m_hasWinner = false;
    int m_winnerSeat = -1;
    int m_battlefieldCardCount = 0;
    int m_visibleZoneCardCount = 0;
    RulesPlayerModel m_players;
    RulesZoneModel m_zones;
    RulesCardModel m_battlefieldCards;
    RulesCardModel m_zoneCards;
    RulesStackModel m_stack;
    bool m_promptPending = false;
    qint64 m_promptId = 0;
    QString m_promptKind;
    bool m_promptSupported = false;
    QString m_promptTitle;
    QString m_promptDetail;
    int m_promptRequiredSelections = 0;
    int m_promptMinCardSelections = 0;
    int m_promptMaxCardSelections = 0;
    int m_promptMinSelections = 0;
    int m_promptMaxSelections = 0;
    bool m_promptCancellable = false;
    RulesPromptOptionModel m_promptOptions;
    RulesChoiceModel m_promptChoices;
    RulesPromptCardModel m_promptCards;
    QStringList m_promptScryDestinations;
    RulesOrderModel m_promptOrderItems;
    RulesPromptCardModel m_promptContextCards;
    RulesPromptTargetModel m_promptContextTargets;
    QString m_promptContextText;
    RulesPromptTargetModel m_promptTargets;
    RulesCombatModel m_promptCombat;
    QVariantMap m_promptDamageSource;
    RulesDamageModel m_promptDamageTargets;
    int m_promptTotalDamage = 0;
    bool m_promptDamageDeathtouch = false;
    int m_promptMinChoiceTotal = 0;
    int m_promptMaxChoiceTotal = 0;
    int m_promptMinNumber = 0;
    int m_promptMaxNumber = 0;
};

} // namespace hexproof::client
