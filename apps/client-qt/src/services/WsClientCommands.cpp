// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "WsClient.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QSet>

namespace hexproof::client {

namespace {
using namespace hexproof::protocol;
using namespace Qt::StringLiterals;

// Format -> seat cap (mirror server FormatMaxSeats).
int formatMaxSeats(const QString &format, bool playtest)
{
    if (playtest)
        return 1;
    if (format == kFormatEDH)
        return 4;
    if (format == kFormatModern || format == kFormatDuel)
        return 2;
    return 0;
}

} // namespace

void WsClient::createRoom(const QString &name, const QString &format, const QString &deckFormat,
                          bool allowSpectators, bool spectatorsSeeHands, const QString &matchMode,
                          const QString &cardLoadMode, const QString &password, bool playtest,
                          const QString &rulesMode)
{
    QJsonObject p;
    p.insert(u"name"_s, name);
    p.insert(u"format"_s, format);
    p.insert(u"deckFormat"_s, deckFormat);
    p.insert(u"maxSeats"_s, formatMaxSeats(format, playtest));
    p.insert(u"playtest"_s, playtest);
    p.insert(u"allowSpectators"_s, playtest ? false : allowSpectators);
    p.insert(u"spectatorsSeeHands"_s, playtest ? false : allowSpectators && spectatorsSeeHands);
    p.insert(u"matchMode"_s, playtest ? kMatchBO1 : matchMode);
    p.insert(u"cardLoadMode"_s, cardLoadMode);
    p.insert(u"rulesMode"_s, playtest ? kRulesModeManual : rulesMode);
    if (!password.isEmpty())
        p.insert(u"password"_s, password);
    send(kTypeRoomCreate, p);
}

void WsClient::requestRoomList()
{
    send(kTypeRoomList);
}

void WsClient::joinRoom(const QString &roomId, bool asSpectator, const QString &password)
{
    QJsonObject p;
    p.insert(u"roomId"_s, roomId);
    p.insert(u"asSpectator"_s, asSpectator);
    if (!password.isEmpty())
        p.insert(u"password"_s, password);
    send(kTypeRoomJoin, p);
}

void WsClient::leaveRoom()
{
    send(kTypeRoomLeave);
}

void WsClient::kickSeat(int seat)
{
    QJsonObject p;
    p.insert(u"seat"_s, seat);
    send(kTypeRoomKick, p);
}

void WsClient::kickSpectator(int index)
{
    QJsonObject p;
    p.insert(u"spectatorIndex"_s, index);
    send(kTypeRoomKick, p);
}

void WsClient::disbandRoom()
{
    send(kTypeRoomDisband);
}

void WsClient::selectDeck(const QVariantMap &deck)
{
    if (deck.isEmpty())
        return;
    const QString requestId = send(kTypeDeckSelect, QJsonObject::fromVariantMap(deck));
    if (!requestId.isEmpty())
        m_roomSession->rememberPendingDeck(requestId, deck.value(u"name"_s).toString());
}

void WsClient::setReady(bool ready)
{
    send(kTypePlayerReady, QJsonObject{{u"ready"_s, ready}});
}

void WsClient::completeLoad(qint64 loadId)
{
    send(kTypeClientLoadComplete, QJsonObject{{u"loadId"_s, loadId}});
}

void WsClient::respondRulesPrompt(qint64 promptId, const QString &responseId)
{
    const QString choice = responseId.trimmed();
    if (promptId <= 0 || choice.isEmpty())
        return;
    send(kTypeRulesRespond, QJsonObject{{u"promptId"_s, promptId}, {u"responseId"_s, choice}});
}

void WsClient::respondRulesPromptWithCards(qint64 promptId, const QString &responseId,
                                           const QVariantList &cardIds)
{
    const QString choice = responseId.trimmed();
    if (promptId <= 0 || choice.isEmpty())
        return;
    QJsonArray cards;
    for (const QVariant &value : cardIds) {
        const QString cardId = value.toString();
        if (cardId.isEmpty())
            return;
        cards.append(cardId);
    }
    send(kTypeRulesRespond,
         QJsonObject{{u"promptId"_s, promptId}, {u"responseId"_s, choice}, {u"cardIds"_s, cards}});
}

void WsClient::respondRulesPromptWithTargets(qint64 promptId, const QString &responseId,
                                             const QVariantList &targetIds)
{
    const QString choice = responseId.trimmed();
    if (promptId <= 0 || choice.isEmpty())
        return;
    QJsonArray targets;
    for (const QVariant &value : targetIds) {
        const QString targetId = value.toString();
        if (targetId.isEmpty())
            return;
        targets.append(targetId);
    }
    send(kTypeRulesRespond, QJsonObject{{u"promptId"_s, promptId},
                                        {u"responseId"_s, choice},
                                        {u"targetIds"_s, targets}});
}

void WsClient::respondRulesPromptWithOrder(qint64 promptId, const QVariantList &orderedIds)
{
    if (promptId <= 0)
        return;
    QJsonArray order;
    QSet<QString> seen;
    for (const QVariant &value : orderedIds) {
        const QString itemId = value.toString();
        if (!itemId.startsWith(u"order:"_s) || seen.contains(itemId))
            return;
        seen.insert(itemId);
        order.append(itemId);
    }
    send(kTypeRulesRespond, QJsonObject{{u"promptId"_s, promptId},
                                        {u"responseId"_s, u"$submit"_s},
                                        {u"orderedIds"_s, order}});
}

void WsClient::respondRulesPromptWithDamageOrder(qint64 promptId, const QVariantList &orderedIds)
{
    if (promptId <= 0)
        return;
    QJsonArray order;
    QSet<QString> seen;
    for (const QVariant &value : orderedIds) {
        const QString targetId = value.toString();
        if (!targetId.startsWith(u"damage-target:"_s) || seen.contains(targetId))
            return;
        seen.insert(targetId);
        order.append(targetId);
    }
    send(kTypeRulesRespond, QJsonObject{{u"promptId"_s, promptId},
                                        {u"responseId"_s, u"$submit"_s},
                                        {u"damageOrderIds"_s, order}});
}

void WsClient::respondRulesPromptWithDamage(qint64 promptId, const QVariantList &assignments)
{
    if (promptId <= 0 || assignments.size() > 512)
        return;
    QJsonArray encodedAssignments;
    QSet<QString> seen;
    for (const QVariant &value : assignments) {
        const QVariantMap assignment = value.toMap();
        const QString targetId = assignment.value(u"targetId"_s).toString();
        bool validDamage = false;
        const int damage = assignment.value(u"damage"_s).toInt(&validDamage);
        if (!targetId.startsWith(u"damage-target:"_s) || seen.contains(targetId) || !validDamage ||
            damage < 0) {
            return;
        }
        seen.insert(targetId);
        encodedAssignments.append(QJsonObject{{u"targetId"_s, targetId}, {u"damage"_s, damage}});
    }
    send(kTypeRulesRespond, QJsonObject{{u"promptId"_s, promptId},
                                        {u"responseId"_s, u"$submit"_s},
                                        {u"damageAssignments"_s, encodedAssignments}});
}

void WsClient::respondRulesPromptWithScry(qint64 promptId, const QVariantList &piles)
{
    if (promptId <= 0 || piles.isEmpty() || piles.size() > 5)
        return;
    const QSet<QString> supportedDestinations{u"libraryTop"_s, u"libraryBottom"_s, u"graveyard"_s,
                                              u"exile"_s, u"hand"_s};
    QSet<QString> destinations;
    QSet<QString> seenCards;
    QJsonArray encodedPiles;
    for (const QVariant &value : piles) {
        const QVariantMap pile = value.toMap();
        const QString destination = pile.value(u"destination"_s).toString();
        if (!supportedDestinations.contains(destination) || destinations.contains(destination))
            return;
        destinations.insert(destination);
        QJsonArray cardIds;
        for (const QVariant &cardValue : pile.value(u"cardIds"_s).toList()) {
            const QString cardId = cardValue.toString();
            if (!cardId.startsWith(u"scry:"_s) || seenCards.contains(cardId) ||
                seenCards.size() >= 512) {
                return;
            }
            seenCards.insert(cardId);
            cardIds.append(cardId);
        }
        encodedPiles.append(QJsonObject{{u"destination"_s, destination}, {u"cardIds"_s, cardIds}});
    }
    send(kTypeRulesRespond, QJsonObject{{u"promptId"_s, promptId},
                                        {u"responseId"_s, u"$submit"_s},
                                        {u"scryPiles"_s, encodedPiles}});
}

void WsClient::respondRulesPromptWithAssignments(qint64 promptId, const QVariantList &assignments)
{
    if (promptId <= 0)
        return;
    QJsonArray encodedAssignments;
    for (const QVariant &value : assignments) {
        const QVariantMap assignment = value.toMap();
        const QString sourceId = assignment.value(u"sourceId"_s).toString();
        const QString targetId = assignment.value(u"targetId"_s).toString();
        if (sourceId.isEmpty() || targetId.isEmpty())
            return;
        encodedAssignments.append(
            QJsonObject{{u"sourceId"_s, sourceId}, {u"targetId"_s, targetId}});
    }
    send(kTypeRulesRespond, QJsonObject{{u"promptId"_s, promptId},
                                        {u"responseId"_s, u"$submit"_s},
                                        {u"assignments"_s, encodedAssignments}});
}

void WsClient::respondRulesPromptWithChoices(qint64 promptId, const QVariantList &choiceIds)
{
    if (promptId <= 0 || choiceIds.size() > 512)
        return;
    QJsonArray choices;
    for (const QVariant &value : choiceIds) {
        const QString choiceId = value.toString().trimmed();
        if (!choiceId.startsWith(u"choice:"_s))
            return;
        choices.append(choiceId);
    }
    send(kTypeRulesRespond, QJsonObject{{u"promptId"_s, promptId},
                                        {u"responseId"_s, u"$submit"_s},
                                        {u"choiceIds"_s, choices}});
}

void WsClient::respondRulesPromptWithNumber(qint64 promptId, int chosenNumber)
{
    if (promptId <= 0)
        return;
    send(kTypeRulesRespond, QJsonObject{{u"promptId"_s, promptId},
                                        {u"responseId"_s, u"$submit"_s},
                                        {u"chosenNumber"_s, chosenNumber}});
}

void WsClient::drawCards(int count)
{
    if (count < 1 || count > 1000)
        return;
    QJsonObject payload;
    if (count != 1)
        payload.insert(u"count"_s, count);
    send(kTypeGameDraw, payload);
}

void WsClient::shuffleLibrary()
{
    send(kTypeGameShuffleLibrary);
}

void WsClient::mulligan()
{
    send(kTypeGameMulligan);
}

void WsClient::discardHand(bool all)
{
    QJsonObject payload;
    if (all)
        payload.insert(u"all"_s, true);
    send(kTypeGameDiscardHand, payload);
}

void WsClient::moveCard(const QString &cardId, const QString &fromZone, const QString &toZone,
                        const QVariantMap &position, int toSeat, const QString &libraryPlacement,
                        int libraryIndex, int fromSeat, const QString &faceName, bool faceDown)
{
    QJsonObject payload{
        {u"cardId"_s, cardId},
        {u"fromZone"_s, fromZone},
        {u"toZone"_s, toZone},
    };
    if (!position.isEmpty())
        payload.insert(u"position"_s, QJsonObject::fromVariantMap(position));
    if (fromSeat >= 0)
        payload.insert(u"fromSeat"_s, fromSeat);
    if (toSeat >= 0)
        payload.insert(u"toSeat"_s, toSeat);
    if (!libraryPlacement.isEmpty())
        payload.insert(u"libraryPlacement"_s, libraryPlacement);
    if (libraryPlacement == u"index"_s && libraryIndex >= 0)
        payload.insert(u"libraryIndex"_s, libraryIndex);
    if (!faceName.isEmpty())
        payload.insert(u"faceName"_s, faceName);
    if (faceDown)
        payload.insert(u"faceDown"_s, true);
    send(kTypeGameMoveCard, payload);
}

void WsClient::arrangeBattlefield(const QVariantList &cards)
{
    QJsonArray placements;
    for (const QVariant &value : cards) {
        const QVariantMap card = value.toMap();
        const QString cardId = card.value(QStringLiteral("cardId")).toString().trimmed();
        const QVariantMap position = card.value(QStringLiteral("position")).toMap();
        if (cardId.isEmpty() || position.isEmpty())
            continue;
        placements.append(QJsonObject{
            {QStringLiteral("cardId"), cardId},
            {QStringLiteral("position"), QJsonObject::fromVariantMap(position)},
        });
    }
    if (placements.isEmpty())
        return;
    send(kTypeGameArrangeBattlefield, QJsonObject{{u"cards"_s, placements}});
}

void WsClient::setCardTapped(const QString &cardId, bool tapped)
{
    send(kTypeGameSetTapped, QJsonObject{
                                 {u"cardId"_s, cardId},
                                 {u"tapped"_s, tapped},
                             });
}

void WsClient::setCardFace(const QString &cardId, const QString &faceName)
{
    send(kTypeGameSetCardFace, QJsonObject{
                                   {u"cardId"_s, cardId},
                                   {u"faceName"_s, faceName},
                               });
}

void WsClient::setCardFaceDown(const QString &cardId, bool faceDown)
{
    send(kTypeGameSetFaceDown, QJsonObject{
                                   {u"cardId"_s, cardId},
                                   {u"faceDown"_s, faceDown},
                               });
}

void WsClient::setCardCounter(const QString &cardId, const QVariantMap &counter)
{
    QJsonObject payload = QJsonObject::fromVariantMap(counter);
    payload.insert(u"cardId"_s, cardId);
    send(kTypeGameSetCardCounter, payload);
}

void WsClient::setPhase(const QString &phase)
{
    send(kTypeGameSetPhase, QJsonObject{{u"phase"_s, phase}});
}

void WsClient::playLand(const QString &cardId, const QVariantMap &position, const QString &faceName)
{
    const QString normalizedCardID = cardId.trimmed();
    if (normalizedCardID.isEmpty() || position.isEmpty())
        return;
    QJsonObject payload{
        {u"cardId"_s, normalizedCardID},
        {u"position"_s, QJsonObject::fromVariantMap(position)},
    };
    const QString normalizedFaceName = faceName.trimmed();
    if (!normalizedFaceName.isEmpty())
        payload.insert(u"faceName"_s, normalizedFaceName);
    send(kTypeGamePlayLand, payload);
}

void WsClient::setLandPlayCount(int value)
{
    if (value < 0)
        return;
    send(kTypeGameSetLandPlayCount, QJsonObject{{u"value"_s, value}});
}

void WsClient::setResponseStatus(const QString &status)
{
    const QString value = status.trimmed();
    if (value.isEmpty())
        return;
    send(kTypeGameSetResponseStatus, QJsonObject{{u"status"_s, value}});
}

void WsClient::setCounter(const QString &counter, int value)
{
    send(kTypeGameSetCounter, QJsonObject{
                                  {u"counter"_s, counter},
                                  {u"value"_s, value},
                              });
}

void WsClient::adjustCounter(const QString &counter, int delta)
{
    send(kTypeGameSetCounter, QJsonObject{
                                  {u"counter"_s, counter},
                                  {u"delta"_s, delta},
                              });
}

void WsClient::renameCounter(const QString &counter, const QString &label)
{
    send(kTypeGameSetCounter, QJsonObject{
                                  {u"counter"_s, counter},
                                  {u"label"_s, label},
                              });
}

void WsClient::setCounterCount(int count)
{
    send(kTypeGameSetCounterCount, QJsonObject{{u"count"_s, count}});
}

void WsClient::concede()
{
    send(kTypeGameConcede);
}

void WsClient::declareDraw()
{
    send(kTypeGameDeclareDraw);
}

void WsClient::restartGame()
{
    send(kTypeGameRestart);
}

void WsClient::rollDice(int sides, int count)
{
    send(kTypeGameRoll, QJsonObject{
                            {u"sides"_s, sides},
                            {u"count"_s, count},
                        });
}

void WsClient::flipCoin()
{
    send(kTypeGameFlipCoin);
}

void WsClient::randomSelectPlayer()
{
    send(kTypeGameRandomSelect, QJsonObject{{u"kind"_s, u"player"_s}});
}

void WsClient::randomSelectCards(const QVariantList &cardIds)
{
    if (cardIds.isEmpty())
        return;
    send(kTypeGameRandomSelect, QJsonObject{
                                    {u"kind"_s, u"card"_s},
                                    {u"cardIds"_s, QJsonArray::fromVariantList(cardIds)},
                                });
}

void WsClient::returnToRoom()
{
    send(kTypeGameReturnToRoom);
}

void WsClient::sayGameMessage(const QString &message)
{
    const QString trimmed = message.trimmed();
    if (trimmed.isEmpty())
        return;
    send(kTypeGameSay, QJsonObject{{u"message"_s, trimmed}});
}

void WsClient::createToken(const QVariantMap &token, const QVariantMap &position)
{
    const QString name = token.value(u"name"_s).toString().trimmed();
    if (name.isEmpty() || position.isEmpty())
        return;
    send(kTypeGameCreateToken,
         QJsonObject{
             {u"name"_s, name},
             {u"setCode"_s, token.value(u"setCode"_s).toString()},
             {u"collectorNumber"_s, token.value(u"collectorNumber"_s).toString()},
             {u"typeLine"_s, token.value(u"typeLine"_s).toString()},
             {u"position"_s, QJsonObject::fromVariantMap(position)},
         });
}

void WsClient::adjustCommanderTax(const QString &commanderId, int delta)
{
    const QString id = commanderId.trimmed();
    if (id.isEmpty() || (delta != 1 && delta != -1))
        return;
    send(kTypeGameAdjustCommanderTax, QJsonObject{{u"commanderId"_s, id}, {u"delta"_s, delta}});
}

void WsClient::castCommander(const QString &commanderId)
{
    const QString id = commanderId.trimmed();
    if (id.isEmpty())
        return;
    send(kTypeGameCastCommander, QJsonObject{{u"commanderId"_s, id}});
}

void WsClient::setCommanderDamage(const QString &commanderId, int targetSeat, int amount,
                                  bool exact, bool applyToLife)
{
    const QString id = commanderId.trimmed();
    if (id.isEmpty() || targetSeat < 0 || (exact && amount < 0) || (!exact && amount == 0) ||
        (applyToLife && (exact || amount <= 0))) {
        return;
    }
    QJsonObject payload{
        {u"commanderId"_s, id},
        {u"targetSeat"_s, targetSeat},
        {u"applyToLife"_s, applyToLife},
    };
    if (exact)
        payload.insert(u"value"_s, amount);
    else
        payload.insert(u"delta"_s, amount);
    send(kTypeGameSetCommanderDamage, payload);
}

void WsClient::setCombatArrows(const QVariantList &sourceCardIds, const QString &kind,
                               const QString &targetCardId, int targetSeat,
                               const QVariantList &tappedSourceCardIds)
{
    QJsonArray sources;
    for (const QVariant &value : sourceCardIds) {
        const QString source = value.toString().trimmed();
        if (source.isEmpty())
            return;
        sources.append(source);
    }
    const QString relationKind = kind.trimmed();
    const QString target = targetCardId.trimmed();
    if (sources.isEmpty() || relationKind.isEmpty())
        return;
    QJsonObject payload{{u"sourceCardIds"_s, sources}, {u"kind"_s, relationKind}};
    if (!target.isEmpty())
        payload.insert(u"targetCardId"_s, target);
    if (targetSeat >= 0)
        payload.insert(u"targetSeat"_s, targetSeat);
    if (!tappedSourceCardIds.isEmpty()) {
        QJsonArray tappedSources;
        for (const QVariant &value : tappedSourceCardIds) {
            const QString source = value.toString().trimmed();
            if (source.isEmpty())
                return;
            tappedSources.append(source);
        }
        payload.insert(u"tappedSourceCardIds"_s, tappedSources);
    }
    send(kTypeGameSetArrow, payload);
}

void WsClient::clearCombatArrows(const QVariantList &sourceCardIds)
{
    QJsonArray sources;
    for (const QVariant &value : sourceCardIds) {
        const QString source = value.toString().trimmed();
        if (!source.isEmpty())
            sources.append(source);
    }
    if (sources.isEmpty())
        return;
    send(kTypeGameSetArrow, QJsonObject{{u"sourceCardIds"_s, sources}});
}

void WsClient::clearArrow()
{
    send(kTypeGameSetArrow);
}

void WsClient::setAttachment(const QString &sourceCardId, const QString &targetCardId)
{
    const QString source = sourceCardId.trimmed();
    const QString target = targetCardId.trimmed();
    if (source.isEmpty() || source == target)
        return;
    QJsonObject payload{{u"sourceCardId"_s, source}};
    if (!target.isEmpty())
        payload.insert(u"targetCardId"_s, target);
    send(kTypeGameSetAttachment, payload);
}

void WsClient::moveSideboardCard(const QVariantMap &card, const QString &fromZone,
                                 const QString &toZone)
{
    if (card.isEmpty() || fromZone == toZone)
        return;
    send(kTypeSideboardMove,
         QJsonObject{
             {u"name"_s, card.value(u"name"_s).toString()},
             {u"setCode"_s, card.value(u"setCode"_s).toString()},
             {u"collectorNumber"_s, card.value(u"collectorNumber"_s).toString()},
             {u"fromZone"_s, fromZone},
             {u"toZone"_s, toZone},
         });
}

void WsClient::setSideboardCommander(const QString &name, bool designated)
{
    const QString commanderName = name.trimmed();
    if (commanderName.isEmpty())
        return;
    send(kTypeSideboardSetCommander,
         QJsonObject{{u"name"_s, commanderName}, {u"designated"_s, designated}});
}

void WsClient::setSideboardReady(bool ready)
{
    send(kTypeSideboardReady, QJsonObject{{u"ready"_s, ready}});
}

void WsClient::nextTurn()
{
    send(kTypeGameNextTurn);
}

void WsClient::revealHand()
{
    send(kTypeGameReveal, QJsonObject{{u"zone"_s, kZoneHand}});
}

void WsClient::recallRevealed()
{
    send(kTypeGameRecallRevealed);
}

void WsClient::moveCards(const QVariantList &cardIds, const QString &fromZone,
                         const QString &toZone, const QString &libraryPlacement, bool randomize)
{
    if (cardIds.isEmpty())
        return;
    QJsonObject payload{
        {u"cardIds"_s, QJsonArray::fromVariantList(cardIds)},
        {u"fromZone"_s, fromZone},
        {u"toZone"_s, toZone},
    };
    if (!libraryPlacement.isEmpty())
        payload.insert(u"libraryPlacement"_s, libraryPlacement);
    if (randomize)
        payload.insert(u"randomize"_s, true);
    send(kTypeGameMoveCards, payload);
}

void WsClient::movePublicCards(const QVariantList &cardIds, const QString &fromZone, int fromSeat,
                               const QString &toZone, int toSeat, const QVariantMap &position)
{
    if (cardIds.isEmpty() || fromSeat < 0)
        return;
    QJsonObject payload{
        {u"cardIds"_s, QJsonArray::fromVariantList(cardIds)},
        {u"fromZone"_s, fromZone},
        {u"fromSeat"_s, fromSeat},
        {u"toZone"_s, toZone},
    };
    if (toSeat >= 0)
        payload.insert(u"toSeat"_s, toSeat);
    if (!position.isEmpty())
        payload.insert(u"position"_s, QJsonObject::fromVariantMap(position));
    send(kTypeGameMoveCards, payload);
}

void WsClient::moveLibraryCards(int count, const QString &toZone)
{
    if (count < 1 || (toZone != kZoneGraveyard && toZone != kZoneExile))
        return;
    send(kTypeGameMoveLibraryCards, QJsonObject{{u"count"_s, count}, {u"toZone"_s, toZone}});
}

void WsClient::dumpLibrary(int sourceSeat, int topCount)
{
    QJsonObject payload{{u"zone"_s, kZoneLibrary}};
    if (sourceSeat >= 0)
        payload.insert(u"seat"_s, sourceSeat);
    if (topCount > 0)
        payload.insert(u"topCount"_s, topCount);
    send(kTypeGameDumpZone, payload);
}

void WsClient::respondZoneDump(const QString &approvalId, bool approved)
{
    const QString id = approvalId.trimmed();
    if (id.isEmpty())
        return;
    send(kTypeGameRespondZoneDump, QJsonObject{{u"approvalId"_s, id}, {u"approved"_s, approved}});
}

void WsClient::respondPublicZoneMove(const QString &approvalId, bool approved)
{
    const QString id = approvalId.trimmed();
    if (id.isEmpty())
        return;
    send(kTypeGameRespondPublicZoneMove,
         QJsonObject{{u"approvalId"_s, id}, {u"approved"_s, approved}});
}

void WsClient::searchLibrary(const QString &cardId, const QString &toZone, bool reveal,
                             const QVariantMap &position, int sourceSeat, const QString &approvalId,
                             int toSeat, bool faceDown)
{
    QJsonObject payload{
        {u"cardId"_s, cardId},
        {u"toZone"_s, toZone},
        {u"reveal"_s, reveal},
    };
    if (!position.isEmpty())
        payload.insert(u"position"_s, QJsonObject::fromVariantMap(position));
    if (sourceSeat >= 0)
        payload.insert(u"sourceSeat"_s, sourceSeat);
    if (toSeat >= 0)
        payload.insert(u"toSeat"_s, toSeat);
    if (!approvalId.trimmed().isEmpty())
        payload.insert(u"approvalId"_s, approvalId.trimmed());
    if (faceDown)
        payload.insert(u"faceDown"_s, true);
    send(kTypeGameSearchLibrary, payload);
}

void WsClient::searchLibraryCards(const QVariantList &cardIds, const QString &toZone, bool reveal,
                                  bool randomize, const QVariantMap &position, int sourceSeat,
                                  const QString &approvalId, int toSeat, bool faceDown)
{
    if (cardIds.isEmpty())
        return;
    QJsonObject payload{
        {u"cardIds"_s, QJsonArray::fromVariantList(cardIds)},
        {u"toZone"_s, toZone},
        {u"reveal"_s, reveal},
    };
    if (randomize)
        payload.insert(u"randomize"_s, true);
    if (!position.isEmpty())
        payload.insert(u"position"_s, QJsonObject::fromVariantMap(position));
    if (sourceSeat >= 0)
        payload.insert(u"sourceSeat"_s, sourceSeat);
    if (toSeat >= 0)
        payload.insert(u"toSeat"_s, toSeat);
    if (!approvalId.trimmed().isEmpty())
        payload.insert(u"approvalId"_s, approvalId.trimmed());
    if (faceDown)
        payload.insert(u"faceDown"_s, true);
    send(kTypeGameSearchLibrary, payload);
}

void WsClient::resolveLibraryView(const QVariantList &selectedCardIds,
                                  const QVariantList &remainderCardIds, const QString &toZone,
                                  const QString &remainderPlacement, bool randomizeRemainder,
                                  bool faceDown, const QVariantMap &position, int sourceSeat,
                                  const QString &approvalId)
{
    sendLibraryViewResolution({}, selectedCardIds, remainderCardIds, toZone, remainderPlacement,
                              randomizeRemainder, false, false, faceDown, position, sourceSeat,
                              approvalId);
}

void WsClient::resolveLibraryViewAssignments(const QVariantList &assignments, bool randomizeTop,
                                             bool randomizeBottom, const QVariantMap &position,
                                             int sourceSeat, const QString &approvalId)
{
    if (assignments.isEmpty())
        return;
    sendLibraryViewResolution(assignments, {}, {}, {}, u"top"_s, false, randomizeTop,
                              randomizeBottom, false, position, sourceSeat, approvalId);
}

void WsClient::sendLibraryViewResolution(
    const QVariantList &assignments, const QVariantList &selectedCardIds,
    const QVariantList &remainderCardIds, const QString &toZone, const QString &remainderPlacement,
    bool randomizeRemainder, bool randomizeTop, bool randomizeBottom, bool faceDown,
    const QVariantMap &position, int sourceSeat, const QString &approvalId)
{
    if (remainderPlacement != u"top"_s && remainderPlacement != u"bottom"_s)
        return;
    QJsonObject payload{
        {u"selectedCardIds"_s, QJsonArray::fromVariantList(selectedCardIds)},
        {u"remainderCardIds"_s, QJsonArray::fromVariantList(remainderCardIds)},
        {u"remainderPlacement"_s, remainderPlacement},
    };
    if (!assignments.isEmpty())
        payload.insert(u"assignments"_s, QJsonArray::fromVariantList(assignments));
    if (!selectedCardIds.isEmpty())
        payload.insert(u"toZone"_s, toZone);
    if (randomizeRemainder)
        payload.insert(u"randomizeRemainder"_s, true);
    if (randomizeTop)
        payload.insert(u"randomizeTop"_s, true);
    if (randomizeBottom)
        payload.insert(u"randomizeBottom"_s, true);
    if (faceDown)
        payload.insert(u"faceDown"_s, true);
    if (!position.isEmpty())
        payload.insert(u"position"_s, QJsonObject::fromVariantMap(position));
    if (sourceSeat >= 0)
        payload.insert(u"sourceSeat"_s, sourceSeat);
    if (!approvalId.trimmed().isEmpty())
        payload.insert(u"approvalId"_s, approvalId.trimmed());
    send(kTypeGameResolveLibraryView, payload);
}

void WsClient::reorderLibrary(const QVariantList &cardIds)
{
    if (cardIds.isEmpty())
        return;
    send(kTypeGameReorderLibrary,
         QJsonObject{{u"cardIds"_s, QJsonArray::fromVariantList(cardIds)}});
}

void WsClient::requestReplayList()
{
    requestReplayPage(0);
}

void WsClient::requestReplayPage(int offset)
{
    send(kTypeReplayList, QJsonObject{{u"offset"_s, qMax(0, offset)}, {u"limit"_s, 50}});
}

void WsClient::loadReplay(const QString &replayId)
{
    const QString id = replayId.trimmed();
    if (id.isEmpty())
        return;
    send(kTypeReplayGet, QJsonObject{{u"replayId"_s, id}});
}

} // namespace hexproof::client
