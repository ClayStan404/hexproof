// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "RulesSessionState.h"

#include <QJsonArray>
#include <QSet>
#include <utility>

namespace hexproof::client {

namespace {
using namespace Qt::StringLiterals;

QVector<RulesNamedValue> parseNamedValues(const QJsonArray &array)
{
    QVector<RulesNamedValue> result;
    result.reserve(array.size());
    for (const QJsonValue &value : array) {
        const QJsonObject item = value.toObject();
        result.append({item.value(u"name"_s).toString(), item.value(u"value"_s).toInt()});
    }
    return result;
}

void applyIdentity(const QJsonObject &identity, QString &name, QString &setCode,
                   QString &collectorNumber, bool &token)
{
    name = identity.value(u"name"_s).toString();
    setCode = identity.value(u"setCode"_s).toString();
    collectorNumber = identity.value(u"collectorNumber"_s).toString();
    token = identity.value(u"token"_s).toBool();
}
} // namespace

RulesSessionState::RulesSessionState(QObject *parent)
    : QObject(parent),
      m_players(this),
      m_zones(this),
      m_battlefieldCards(this),
      m_zoneCards(this),
      m_stack(this),
      m_promptOptions(this),
      m_promptChoices(this),
      m_promptCards(this),
      m_promptTargets(this),
      m_promptCombat(this)
{
}

bool RulesSessionState::applyPrompt(const QJsonObject &prompt)
{
    const QString roomId = prompt.value(u"roomId"_s).toString();
    const QString gameId = prompt.value(u"gameId"_s).toString();
    if (roomId.isEmpty() || gameId.isEmpty() || !prompt.value(u"options"_s).isArray() ||
        !prompt.value(u"choices"_s).isArray() || !prompt.value(u"cards"_s).isArray() ||
        !prompt.value(u"targets"_s).isArray() || !prompt.value(u"combatSources"_s).isArray() ||
        !prompt.value(u"combatTargets"_s).isArray())
        return false;
    if (!m_roomId.isEmpty() && (roomId != m_roomId || gameId != m_gameId))
        return false;

    QVector<RulesPromptOptionRow> options;
    const QJsonArray optionArray = prompt.value(u"options"_s).toArray();
    options.reserve(optionArray.size());
    for (const QJsonValue &value : optionArray) {
        const QJsonObject option = value.toObject();
        RulesPromptOptionRow row{
            option.value(u"responseId"_s).toString(), option.value(u"kind"_s).toString(),
            option.value(u"label"_s).toString(), option.value(u"cardId"_s).toString()};
        if (row.responseId.isEmpty() || row.label.isEmpty())
            return false;
        options.append(std::move(row));
    }
    QVector<RulesChoiceRow> choices;
    QSet<QString> choiceIds;
    const QJsonArray choiceArray = prompt.value(u"choices"_s).toArray();
    choices.reserve(choiceArray.size());
    for (const QJsonValue &value : choiceArray) {
        const QJsonObject choice = value.toObject();
        RulesChoiceRow row{choice.value(u"responseId"_s).toString(),
                           choice.value(u"label"_s).toString(), choice.value(u"weight"_s).toInt(),
                           choice.value(u"canRepeat"_s).toBool()};
        if (!row.responseId.startsWith(u"choice:"_s) || row.label.isEmpty() || row.weight <= 0 ||
            choiceIds.contains(row.responseId)) {
            return false;
        }
        choiceIds.insert(row.responseId);
        choices.append(std::move(row));
    }
    QVector<RulesPromptCardRow> cards;
    QSet<QString> cardIds;
    const QJsonArray cardArray = prompt.value(u"cards"_s).toArray();
    cards.reserve(cardArray.size());
    for (const QJsonValue &value : cardArray) {
        const QJsonObject card = value.toObject();
        RulesPromptCardRow row{card.value(u"id"_s).toString(), card.value(u"name"_s).toString(),
                               card.value(u"setCode"_s).toString(),
                               card.value(u"collectorNumber"_s).toString(),
                               card.value(u"token"_s).toBool()};
        if (row.id.isEmpty() || cardIds.contains(row.id))
            return false;
        cardIds.insert(row.id);
        cards.append(std::move(row));
    }
    const int requiredSelections = prompt.value(u"requiredSelections"_s).toInt();
    if (requiredSelections < 0 || requiredSelections > cards.size())
        return false;
    const int minCardSelections = prompt.value(u"minCardSelections"_s).toInt();
    const int maxCardSelections = prompt.value(u"maxCardSelections"_s).toInt();
    if (minCardSelections < 0 || maxCardSelections < minCardSelections ||
        maxCardSelections > cards.size()) {
        return false;
    }
    QVector<RulesOrderRow> orderItems;
    QSet<QString> orderIds;
    const QJsonArray orderArray = prompt.value(u"orderItems"_s).toArray();
    orderItems.reserve(orderArray.size());
    for (const QJsonValue &value : orderArray) {
        const QJsonObject item = value.toObject();
        RulesOrderRow row{
            item.value(u"responseId"_s).toString(), item.value(u"name"_s).toString(),
            item.value(u"setCode"_s).toString(),    item.value(u"collectorNumber"_s).toString(),
            item.value(u"token"_s).toBool(),        item.value(u"oracle"_s).toString()};
        if (!row.responseId.startsWith(u"order:"_s) || orderIds.contains(row.responseId))
            return false;
        orderIds.insert(row.responseId);
        orderItems.append(std::move(row));
    }
    QVector<RulesPromptTargetRow> targets;
    const QJsonArray targetArray = prompt.value(u"targets"_s).toArray();
    targets.reserve(targetArray.size());
    for (const QJsonValue &value : targetArray) {
        const QJsonObject target = value.toObject();
        RulesPromptTargetRow row{
            target.value(u"responseId"_s).toString(),
            target.value(u"kind"_s).toString(),
            target.value(u"label"_s).toString(),
            target.value(u"objectId"_s).toString(),
            target.value(u"name"_s).toString(),
            target.value(u"setCode"_s).toString(),
            target.value(u"collectorNumber"_s).toString(),
            target.value(u"token"_s).toBool(),
        };
        if (row.responseId.isEmpty() || row.kind.isEmpty() || row.label.isEmpty())
            return false;
        targets.append(std::move(row));
    }
    const int minSelections = prompt.value(u"minSelections"_s).toInt();
    const int maxSelections = prompt.value(u"maxSelections"_s).toInt();
    if (minSelections < 0 || maxSelections < minSelections || maxSelections > targets.size())
        return false;
    const int minChoiceTotal = prompt.value(u"minChoiceTotal"_s).toInt();
    const int maxChoiceTotal = prompt.value(u"maxChoiceTotal"_s).toInt();
    const int minNumber = prompt.value(u"minNumber"_s).toInt();
    const int maxNumber = prompt.value(u"maxNumber"_s).toInt();
    if (minChoiceTotal < 0 || maxChoiceTotal < minChoiceTotal || maxChoiceTotal > 512 ||
        minNumber > maxNumber) {
        return false;
    }
    QVector<RulesCombatTargetRow> combatTargets;
    QSet<QString> combatTargetIds;
    const QJsonArray combatTargetArray = prompt.value(u"combatTargets"_s).toArray();
    combatTargets.reserve(combatTargetArray.size());
    for (const QJsonValue &value : combatTargetArray) {
        const QJsonObject target = value.toObject();
        RulesCombatTargetRow row{
            target.value(u"responseId"_s).toString(),
            target.value(u"kind"_s).toString(),
            target.value(u"label"_s).toString(),
            target.value(u"objectId"_s).toString(),
            target.value(u"name"_s).toString(),
            target.value(u"setCode"_s).toString(),
            target.value(u"collectorNumber"_s).toString(),
            target.value(u"token"_s).toBool(),
            target.value(u"minAssignments"_s).toInt(),
            target.value(u"maxAssignments"_s).toInt(),
            target.value(u"mustReceiveIfAble"_s).toBool(),
        };
        if (row.responseId.isEmpty() || row.kind.isEmpty() || row.label.isEmpty() ||
            row.minimum < 0 || row.maximum < 0 || combatTargetIds.contains(row.responseId)) {
            return false;
        }
        combatTargetIds.insert(row.responseId);
        combatTargets.append(std::move(row));
    }
    QVector<RulesCombatSourceRow> combatSources;
    QSet<QString> combatSourceIds;
    const QJsonArray combatSourceArray = prompt.value(u"combatSources"_s).toArray();
    combatSources.reserve(combatSourceArray.size());
    for (const QJsonValue &value : combatSourceArray) {
        const QJsonObject source = value.toObject();
        RulesCombatSourceRow row{
            source.value(u"responseId"_s).toString(),
            source.value(u"objectId"_s).toString(),
            source.value(u"label"_s).toString(),
            source.value(u"name"_s).toString(),
            source.value(u"setCode"_s).toString(),
            source.value(u"collectorNumber"_s).toString(),
            source.value(u"token"_s).toBool(),
            {},
            source.value(u"mustAssignIfAble"_s).toBool(),
        };
        if (row.responseId.isEmpty() || row.objectId.isEmpty() || row.label.isEmpty() ||
            !source.value(u"validTargetIds"_s).isArray() ||
            combatSourceIds.contains(row.responseId)) {
            return false;
        }
        QSet<QString> validTargetIds;
        for (const QJsonValue &targetIdValue : source.value(u"validTargetIds"_s).toArray()) {
            const QString targetId = targetIdValue.toString();
            if (targetId.isEmpty() || !combatTargetIds.contains(targetId) ||
                validTargetIds.contains(targetId)) {
                return false;
            }
            validTargetIds.insert(targetId);
            row.validTargetIds.append(targetId);
        }
        combatSourceIds.insert(row.responseId);
        combatSources.append(std::move(row));
    }
    m_promptPending = prompt.value(u"pending"_s).toBool();
    m_promptId = prompt.value(u"promptId"_s).toInteger();
    m_promptKind = prompt.value(u"kind"_s).toString();
    m_promptSupported = prompt.value(u"supported"_s).toBool();
    m_promptTitle = prompt.value(u"title"_s).toString();
    m_promptDetail = prompt.value(u"detail"_s).toString();
    m_promptRequiredSelections = requiredSelections;
    m_promptMinCardSelections = minCardSelections;
    m_promptMaxCardSelections = maxCardSelections;
    m_promptMinSelections = minSelections;
    m_promptMaxSelections = maxSelections;
    m_promptCancellable = prompt.value(u"cancellable"_s).toBool();
    m_promptMinChoiceTotal = minChoiceTotal;
    m_promptMaxChoiceTotal = maxChoiceTotal;
    m_promptMinNumber = minNumber;
    m_promptMaxNumber = maxNumber;
    if (!m_promptPending) {
        m_promptId = 0;
        m_promptKind.clear();
        m_promptSupported = false;
        m_promptTitle.clear();
        m_promptDetail.clear();
        m_promptRequiredSelections = 0;
        m_promptMinCardSelections = 0;
        m_promptMaxCardSelections = 0;
        m_promptMinSelections = 0;
        m_promptMaxSelections = 0;
        m_promptCancellable = false;
        m_promptMinChoiceTotal = 0;
        m_promptMaxChoiceTotal = 0;
        m_promptMinNumber = 0;
        m_promptMaxNumber = 0;
        options.clear();
        choices.clear();
        cards.clear();
        orderItems.clear();
        targets.clear();
        combatSources.clear();
        combatTargets.clear();
    }
    m_promptOptions.replace(std::move(options));
    m_promptChoices.replace(std::move(choices));
    m_promptCards.replace(std::move(cards));
    m_promptOrderItems.replace(std::move(orderItems));
    m_promptTargets.replace(std::move(targets));
    m_promptCombat.replace(std::move(combatSources), std::move(combatTargets));
    emit promptChanged();
    return true;
}

bool RulesSessionState::applySnapshot(const QJsonObject &snapshot)
{
    const QString roomId = snapshot.value(u"roomId"_s).toString();
    const QString gameId = snapshot.value(u"gameId"_s).toString();
    if (roomId.isEmpty() || gameId.isEmpty() || !snapshot.value(u"players"_s).isArray() ||
        !snapshot.value(u"zones"_s).isArray() || !snapshot.value(u"stack"_s).isArray()) {
        return false;
    }

    QVector<RulesPlayerRow> players;
    const QJsonArray playerArray = snapshot.value(u"players"_s).toArray();
    players.reserve(playerArray.size());
    for (const QJsonValue &value : playerArray) {
        const QJsonObject player = value.toObject();
        RulesPlayerRow row;
        row.seat = player.value(u"seat"_s).toInt(-1);
        row.name = player.value(u"name"_s).toString();
        row.status = player.value(u"status"_s).toString();
        row.life = player.value(u"life"_s).toInt();
        row.counters = parseNamedValues(player.value(u"counters"_s).toArray());
        row.manaPool = parseNamedValues(player.value(u"manaPool"_s).toArray());
        players.append(std::move(row));
    }

    QVector<RulesZoneRow> zones;
    QVector<RulesCardRow> battlefieldCards;
    QVector<RulesCardRow> zoneCards;
    const QJsonArray zoneArray = snapshot.value(u"zones"_s).toArray();
    zones.reserve(zoneArray.size());
    for (const QJsonValue &value : zoneArray) {
        const QJsonObject zone = value.toObject();
        RulesZoneRow zoneRow{zone.value(u"zone"_s).toString(), zone.value(u"ownerSeat"_s).toInt(-1),
                             zone.value(u"count"_s).toInt()};
        zones.append(zoneRow);
        for (const QJsonValue &cardValue : zone.value(u"cards"_s).toArray()) {
            const QJsonObject card = cardValue.toObject();
            RulesCardRow cardRow;
            cardRow.id = card.value(u"id"_s).toString();
            cardRow.zone = zoneRow.zone;
            cardRow.zoneOwnerSeat = zoneRow.ownerSeat;
            const bool declaredVisible = card.value(u"visible"_s).toBool();
            if (declaredVisible && card.value(u"identity"_s).isObject()) {
                applyIdentity(card.value(u"identity"_s).toObject(), cardRow.name, cardRow.setCode,
                              cardRow.collectorNumber, cardRow.token);
            }
            cardRow.visible = declaredVisible && !cardRow.name.isEmpty();
            cardRow.ownerSeat = card.value(u"ownerSeat"_s).toInt(-1);
            cardRow.controllerSeat = card.value(u"controllerSeat"_s).toInt(-1);
            cardRow.tapped = card.value(u"tapped"_s).toBool();
            cardRow.faceDown = card.value(u"faceDown"_s).toBool();
            cardRow.attacking = card.value(u"attacking"_s).toBool();
            cardRow.power = card.value(u"power"_s).toString();
            cardRow.toughness = card.value(u"toughness"_s).toString();
            cardRow.damage = card.value(u"damage"_s).toInt();
            cardRow.attachedTo = card.value(u"attachedTo"_s).toString();
            cardRow.counters = parseNamedValues(card.value(u"counters"_s).toArray());
            if (cardRow.zone == u"battlefield"_s) {
                battlefieldCards.append(std::move(cardRow));
            } else if (cardRow.zone == u"hand"_s || cardRow.zone == u"graveyard"_s ||
                       cardRow.zone == u"exile"_s || cardRow.zone == u"command"_s) {
                zoneCards.append(std::move(cardRow));
            }
        }
    }

    QVector<RulesStackRow> stack;
    const QJsonArray stackArray = snapshot.value(u"stack"_s).toArray();
    stack.reserve(stackArray.size());
    for (const QJsonValue &value : stackArray) {
        const QJsonObject object = value.toObject();
        RulesStackRow row;
        row.id = object.value(u"id"_s).toString();
        row.sourceId = object.value(u"sourceId"_s).toString();
        row.controllerSeat = object.value(u"controllerSeat"_s).toInt(-1);
        row.ownerSeat = object.value(u"ownerSeat"_s).toInt(-1);
        applyIdentity(object.value(u"identity"_s).toObject(), row.name, row.setCode,
                      row.collectorNumber, row.token);
        row.text = object.value(u"text"_s).toString();
        stack.append(std::move(row));
    }

    m_roomId = roomId;
    m_gameId = gameId;
    m_turn = snapshot.value(u"turn"_s).toInt();
    m_step = snapshot.value(u"step"_s).toString();
    m_activeSeat = snapshot.value(u"activeSeat"_s).toInt(-1);
    m_prioritySeat = snapshot.value(u"prioritySeat"_s).toInt(-1);
    m_gameOver = snapshot.value(u"gameOver"_s).toBool();
    m_hasWinner = snapshot.contains(u"winnerSeat"_s) && !snapshot.value(u"winnerSeat"_s).isNull();
    m_winnerSeat = m_hasWinner ? snapshot.value(u"winnerSeat"_s).toInt(-1) : -1;
    m_battlefieldCardCount = battlefieldCards.size();
    m_visibleZoneCardCount = zoneCards.size();
    m_players.replace(std::move(players));
    m_zones.replace(std::move(zones));
    m_battlefieldCards.replace(std::move(battlefieldCards));
    m_zoneCards.replace(std::move(zoneCards));
    m_stack.replace(std::move(stack));
    emit snapshotChanged();
    return true;
}

void RulesSessionState::clear()
{
    m_roomId.clear();
    m_gameId.clear();
    m_turn = 0;
    m_step.clear();
    m_activeSeat = -1;
    m_prioritySeat = -1;
    m_gameOver = false;
    m_hasWinner = false;
    m_winnerSeat = -1;
    m_battlefieldCardCount = 0;
    m_visibleZoneCardCount = 0;
    m_players.clear();
    m_zones.clear();
    m_battlefieldCards.clear();
    m_zoneCards.clear();
    m_stack.clear();
    m_promptPending = false;
    m_promptId = 0;
    m_promptKind.clear();
    m_promptSupported = false;
    m_promptTitle.clear();
    m_promptDetail.clear();
    m_promptRequiredSelections = 0;
    m_promptMinCardSelections = 0;
    m_promptMaxCardSelections = 0;
    m_promptMinSelections = 0;
    m_promptMaxSelections = 0;
    m_promptCancellable = false;
    m_promptMinChoiceTotal = 0;
    m_promptMaxChoiceTotal = 0;
    m_promptMinNumber = 0;
    m_promptMaxNumber = 0;
    m_promptOptions.clear();
    m_promptChoices.clear();
    m_promptCards.clear();
    m_promptOrderItems.clear();
    m_promptTargets.clear();
    m_promptCombat.clear();
    emit snapshotChanged();
    emit promptChanged();
}

} // namespace hexproof::client
