// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
// Test-only executable reuses upstream initialization, not TestSuiteAI's loser reset.
#define main wagicUpstreamConsoleMain
#include WAGIC_QT_CONSOLE_SOURCE
#undef main
#include "ActionLayer.h"
#include "GameObserver.h"
#include "GameStateShop.h"
#include "GuiCombat.h"
#include "MTGCardInstance.h"
#include "Rules.h"
#include "SimpleButton.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <functional>
#include <memory>
#include <stdexcept>

namespace {
std::unique_ptr<GameObserver> game;
QJsonArray assertions, decisions;
QJsonObject observed;
int frame = 0;
bool negativeControl = false;
// Synthetic decks have no persisted deck/statistics filename. Keep the real human
// Player behavior, but do not ask Player::End to save absent deck metadata.
class FixturePlayer : public Player
{
  public:
    explicit FixturePlayer(GameObserver *observer)
        : Player(observer, "", "")
    {
    }
    void End() override {}
};
int pendingActor = -1;
int pendingId = 0;
void offer(int actor)
{
    pendingActor = actor;
    ++pendingId;
}
bool respond(int actor, int id, const std::function<void()> &action)
{
    if (actor != pendingActor || id != pendingId)
        return false;
    pendingActor = -1;
    action();
    return true;
}
Player *player(int seat)
{
    return game->players.at(seat);
}
ActionStack *stack()
{
    return game->mLayers->stackLayer();
}
void check(const char *message, bool valid)
{
    if (negativeControl && std::string(message) == "Exactly three damage")
        valid = false;
    assertions.append(QJsonObject{{"name", message}, {"passed", valid}});
    if (!valid)
        throw std::runtime_error(std::string("ASSERTION: ") + message);
}
void tick(int count = 1)
{
    for (int i = 0; i < count; ++i) {
        game->Update(0.016f);
        frame++;
    }
}
QJsonArray zone(MTGGameZone *value)
{
    QJsonArray cards;
    for (auto *card : value->cards) {
        cards.append(QJsonObject{{"name", QString::fromStdString(card->name)},
                                 {"catalogId", card->getMTGId()},
                                 {"entity", QString::number(reinterpret_cast<quintptr>(card), 16)},
                                 {"tapped", bool(card->isTapped())},
                                 {"power", card->getPower()},
                                 {"toughness", card->getToughness()},
                                 {"token", bool(card->isToken)},
                                 {"colorMask", card->colors},
                                 {"manaValue", card->getManaCost()->getConvertedCost()},
                                 {"isMorphed", card->isMorphed}});
    }
    return cards;
}
QJsonObject state()
{
    QJsonArray players;
    for (size_t seat = 0; seat < game->players.size(); ++seat) {
        Player *p = player(seat);
        players.append(QJsonObject{{"seat", int(seat)},
                                   {"life", p->life},
                                   {"hand", zone(p->game->hand)},
                                   {"library", zone(p->game->library)},
                                   {"battlefield", zone(p->game->inPlay)},
                                   {"graveyard", zone(p->game->graveyard)},
                                   {"exile", zone(p->game->exile)},
                                   {"cardStack", zone(p->game->stack)},
                                   {"mana", p->getManaPool()->getConvertedCost()}});
    }
    QJsonArray actions;
    for (Interruptible *action = stack()->getNext(nullptr, 0, NOT_RESOLVED); action;
         action = stack()->getNext(action, 0, NOT_RESOLVED))
        actions.append(QJsonObject{
            {"source", action->source ? QString::fromStdString(action->source->name) : QString()},
            {"type", action->type}});
    QJsonArray menu;
    auto *layer = game->mLayers->actionLayer();
    if (layer->menuObject && layer->abilitiesMenu)
        for (auto *item : layer->abilitiesMenu->mObjects) {
            auto *button = dynamic_cast<SimpleButton *>(item);
            menu.append(QJsonObject{
                {"id", item->GetId()},
                {"text", button ? QString::fromStdString(button->getText()) : QString()}});
        }
    return {{"players", players},
            {"stack", actions},
            {"phase", int(game->getCurrentGamePhase())},
            {"combatStep", int(game->combatStep)},
            {"menu", menu},
            {"frame", frame}};
}
int named(MTGGameZone *zone, const std::string &name)
{
    int count = 0;
    for (auto *card : zone->cards)
        if (card->name == name)
            count++;
    return count;
}
MTGCardInstance *find(MTGGameZone *zone, const std::string &name)
{
    for (auto *card : zone->cards)
        if (card->name == name)
            return card;
    throw std::runtime_error("Named card missing from expected zone: " + name);
}
MTGCardInstance *add(int seat, const std::string &name, MTGGameZone *destination)
{
    MTGCard *definition = MTGCollection()->getCardByName(name);
    if (!definition)
        throw std::runtime_error("CATALOG: " + name);
    auto *card = new MTGCardInstance(definition, player(seat)->game);
    if (destination == player(seat)->game->hand) {
        // Zone-change events register real autohand/anyzone abilities, notably
        // modal faces. Directly pushing into the vector would skip that setup.
        player(seat)->game->library->addCard(card);
        return player(seat)->game->putInZone(card, player(seat)->game->library, destination);
    }
    destination->addCard(card);
    return card;
}
void fixture(bool opening = false)
{
    game.reset(new GameObserver());
    for (int seat = 0; seat < 2; ++seat) {
        auto *p = new FixturePlayer(game.get());
        game->loadPlayer(seat, p);
        for (int i = 0; i < (opening ? 60 : 30); ++i)
            add(seat, "Plains", p->game->library);
    }
    options[Options::FIRSTPLAYER].number = 0;
    Rules *rules = Rules::getRulesByFilename(opening ? "classic.txt" : "mtg.txt");
    if (!rules)
        throw std::runtime_error("Declared upstream rule file missing");
    game->startGame(GAME_TYPE_CLASSIC, rules);
    if (!opening) {
        game->phaseRing->goToPhase(MTG_PHASE_FIRSTMAIN, player(0), false);
        game->setCurrentGamePhase(MTG_PHASE_FIRSTMAIN);
    }
    tick(3);
}
MTGCardInstance *permanent(int seat, const std::string &name)
{
    auto *card = add(seat, name, player(seat)->game->library);
    card =
        player(seat)->game->putInZone(card, player(seat)->game->library, player(seat)->game->stack);
    Spell spell(game.get(), card);
    spell.resolve();
    auto *result = find(player(seat)->game->inPlay, name);
    result->summoningSickness = 0;
    tick(3);
    return result;
}
void click(MTGCardInstance *card)
{
    decisions.append(QJsonObject{{"kind", "cardClick"},
                                 {"card", QString::fromStdString(card->name)},
                                 {"actor", game->currentlyActing() == player(0) ? 0 : 1}});
    game->cardClick(card, card);
    tick();
}
void menu(const std::string &text)
{
    auto *layer = game->mLayers->actionLayer();
    observed["lastMenu"] = state();
    if (!layer->menuObject || !layer->abilitiesMenu)
        throw std::runtime_error("No native menu for " + text);
    for (size_t index = 0; index < layer->abilitiesMenu->mObjects.size(); ++index) {
        auto *button = dynamic_cast<SimpleButton *>(layer->abilitiesMenu->mObjects[index]);
        if (button && QString::fromStdString(button->getText())
                          .contains(QString::fromStdString(text), Qt::CaseInsensitive)) {
            decisions.append(QJsonObject{{"kind", "menu"},
                                         {"index", int(index)},
                                         {"text", QString::fromStdString(button->getText())}});
            layer->doReactTo(index);
            tick();
            return;
        }
    }
    throw std::runtime_error("No native menu label matching " + text);
}
void settle();
void advance(int phase, int owner = 0)
{
    for (int steps = 0; steps < 100; ++steps) {
        if (game->getCurrentGamePhase() == phase && game->currentPlayer == player(owner))
            return;
        if (game->getCurrentGamePhase() == MTG_PHASE_COMBATDAMAGE && game->combatStep == DAMAGE) {
            game->mLayers->combatLayer()->clickOK();
            tick();
        } else {
            game->userRequestNextGamePhase();
            tick();
        }
        settle();
    }
    throw std::runtime_error("Phase progression exceeded bound");
}
void pass()
{
    decisions.append(
        QJsonObject{{"kind", "pass"}, {"actor", game->isInterrupting == player(1) ? 1 : 0}});
    if (stack()->askIfWishesToInterrupt)
        stack()->cancelInterruptOffer();
    else if (game->isInterrupting)
        stack()->endOfInterruption();
    tick();
}
void settle()
{
    for (int step = 0; step < 400; ++step) {
        if (stack()->count(0, NOT_RESOLVED) == 0 && !game->getCurrentTargetChooser()) {
            tick(2);
            return;
        }
        pass();
    }
    throw std::runtime_error("Unresolved stack after bounded pass loop");
}
void priority(int seat)
{
    for (int step = 0; step < 40; ++step) {
        if (game->currentlyActing() == player(seat) && !stack()->askIfWishesToInterrupt)
            return;
        if (stack()->askIfWishesToInterrupt == player(seat)) {
            stack()->setIsInterrupting(player(seat));
            tick();
            return;
        }
        pass();
    }
    throw std::runtime_error("Requested player did not receive interrupt/priority");
}
void mana(int seat, const std::vector<std::string> &lands)
{
    priority(seat);
    for (const auto &name : lands) {
        MTGCardInstance *chosen = nullptr;
        for (auto *card : player(seat)->game->inPlay->cards)
            if (card->name == name && !card->isTapped()) {
                chosen = card;
                break;
            }
        if (!chosen)
            throw std::runtime_error("No untapped mana source: " + name);
        click(chosen);
    }
}
void cast(int seat, const std::string &name, Targetable *target = nullptr)
{
    priority(seat);
    auto *card = find(player(seat)->game->hand, name);
    click(card);
    if (target && game->getCurrentTargetChooser()) {
        if (auto *stackTarget = dynamic_cast<Interruptible *>(target))
            game->stackObjectClicked(stackTarget);
        else
            game->cardClick(dynamic_cast<MTGCardInstance *>(target), target);
        tick();
    }
    observed["lastCastBeforeResolution"] = state();
    if (named(player(seat)->game->stack, name) == 0)
        throw std::runtime_error("Cast did not produce named card on stack: " + name);
}
void opening()
{
    fixture(true);
    QJsonArray keeps;
    for (int seat = 0; seat < 2; ++seat) {
        offer(seat);
        const int id = pendingId;
        const bool accepted = respond(seat, id, [&]() { keeps.append(seat); });
        if (!accepted)
            throw std::runtime_error("Host keep response rejected");
    }
    observed["explicitHostKeeps"] = keeps;
    observed["opening"] = state();
    check("Both normal decks draw seven",
          player(0)->game->hand->nb_cards == 7 && player(1)->game->hand->nb_cards == 7);
    check("Both libraries contain 53",
          player(0)->game->library->nb_cards == 53 && player(1)->game->library->nb_cards == 53);
    check("Starting player did not draw an eighth card", player(0)->game->hand->nb_cards == 7);
    check("Starting player owns main-phase interaction",
          game->getCurrentGamePhase() == MTG_PHASE_FIRSTMAIN &&
              game->currentlyActing() == player(0));
    observed["layerHint"] = "adapter";
    observed["limitation"] = "Native normal startup/draw plus test-only host explicit keep gate; "
                             "native UI has no serialized keep request";
}
void land()
{
    fixture();
    auto *first = add(0, "Plains", player(0)->game->hand);
    add(0, "Plains", player(0)->game->hand);
    offer(0);
    const int id = pendingId;
    QJsonObject before = state();
    check("Host rejects non-owning actor without engine mutation",
          !respond(1, id, [&]() { click(first); }) && before == state());
    check("Host rejects stale request without engine mutation",
          !respond(0, id - 1, [&]() { click(first); }) && before == state());
    check("Owner can answer actual land decision", respond(0, id, [&]() { click(first); }));
    check("Exactly one Plains played",
          player(0)->game->hand->nb_cards == 1 && named(player(0)->game->inPlay, "Plains") == 1);
    QJsonObject beforeSecondLand = state();
    beforeSecondLand.remove("frame");
    click(find(player(0)->game->hand, "Plains"));
    QJsonObject afterSecondLand = state();
    afterSecondLand.remove("frame");
    check("Second Plains rejected", player(0)->game->hand->nb_cards == 1 &&
                                        named(player(0)->game->inPlay, "Plains") == 1 &&
                                        beforeSecondLand == afterSecondLand);
    observed["layerHint"] = "adapter";
    observed["limitation"] = "Native land rules with test-only host actor/request-id guard; not a "
                             "claim of native network authentication";
}
void bolt(bool creature, bool replacement)
{
    fixture();
    if (replacement)
        permanent(0, "Rest in Peace");
    auto *mountain = permanent(0, "Mountain");
    auto *bears = creature ? permanent(1, "Grizzly Bears") : nullptr;
    add(0, "Lightning Bolt", player(0)->game->hand);
    mana(0, {"Mountain"});
    cast(0, "Lightning Bolt",
         creature ? static_cast<Targetable *>(bears) : static_cast<Targetable *>(player(1)));
    if (!creature)
        check("Bolt on stack before damage",
              player(1)->life == 20 && named(player(0)->game->stack, "Lightning Bolt") == 1);
    settle();
    if (replacement) {
        check("Bears exiled", named(player(1)->game->exile, "Grizzly Bears") == 1 &&
                                  named(player(1)->game->graveyard, "Grizzly Bears") == 0);
        check("Bolt exiled", named(player(0)->game->exile, "Lightning Bolt") == 1 &&
                                 named(player(0)->game->graveyard, "Lightning Bolt") == 0);
        check("Both graveyards empty", player(0)->game->graveyard->nb_cards == 0 &&
                                           player(1)->game->graveyard->nb_cards == 0);
    } else if (creature) {
        check("Both cards in owners graveyards",
              named(player(1)->game->graveyard, "Grizzly Bears") == 1 &&
                  named(player(0)->game->graveyard, "Lightning Bolt") == 1);
        check("Player life unchanged", player(1)->life == 20);
        check("Bears absent from battlefield",
              named(player(1)->game->inPlay, "Grizzly Bears") == 0);
    } else {
        check("Exactly three damage", player(1)->life == 17);
        check("Bolt in graveyard and Mountain tapped",
              named(player(0)->game->graveyard, "Lightning Bolt") == 1 && mountain->isTapped());
    }
}
void counterspell()
{
    fixture();
    permanent(0, "Mountain");
    permanent(1, "Island");
    permanent(1, "Island");
    add(0, "Lightning Bolt", player(0)->game->hand);
    add(1, "Counterspell", player(1)->game->hand);
    mana(0, {"Mountain"});
    cast(0, "Lightning Bolt", player(1));
    auto *bolt = stack()->getLatest(NOT_RESOLVED);
    mana(1, {"Island", "Island"});
    cast(1, "Counterspell", bolt);
    check("Counterspell above Bolt",
          stack()->getLatest(NOT_RESOLVED)->source->name == "Counterspell" &&
              stack()->count(ACTION_SPELL, NOT_RESOLVED) == 2);
    settle();
    check("Neither player damaged", player(0)->life == 20 && player(1)->life == 20);
    check("Both spells in graveyards and empty stack",
          named(player(0)->game->graveyard, "Lightning Bolt") == 1 &&
              named(player(1)->game->graveyard, "Counterspell") == 1 &&
              stack()->count(0, NOT_RESOLVED) == 0);
}
void visionary()
{
    fixture();
    permanent(0, "Forest");
    permanent(0, "Plains");
    add(0, "Elvish Visionary", player(0)->game->hand);
    mana(0, {"Forest", "Plains"});
    cast(0, "Elvish Visionary");
    bool trigger = false;
    for (int step = 0; step < 200; ++step) {
        if (named(player(0)->game->inPlay, "Elvish Visionary") == 1) {
            trigger =
                player(0)->game->library->nb_cards == 30 && stack()->count(0, NOT_RESOLVED) > 0;
            observed["afterCreatureBeforeTrigger"] = state();
            break;
        }
        pass();
    }
    settle();
    check("Visionary on battlefield", named(player(0)->game->inPlay, "Elvish Visionary") == 1);
    check("Exactly one card drawn",
          player(0)->game->library->nb_cards == 29 && player(0)->game->hand->nb_cards == 1);
    check("ETB separately used stack", trigger);
}
void tokens()
{
    fixture();
    permanent(0, "Plains");
    permanent(0, "Plains");
    add(0, "Raise the Alarm", player(0)->game->hand);
    mana(0, {"Plains", "Plains"});
    cast(0, "Raise the Alarm");
    settle();
    int tokens = 0;
    bool exact = true;
    for (auto *card : player(0)->game->inPlay->cards)
        if (card->isToken) {
            tokens++;
            exact &= card->getPower() == 1 && card->getToughness() == 1 &&
                     card->hasType("Soldier") && card->hasColor(Constants::MTG_COLOR_WHITE);
        }
    check("Exactly two white 1/1 Soldier tokens", tokens == 2 && exact);
    check("Raise the Alarm in graveyard",
          named(player(0)->game->graveyard, "Raise the Alarm") == 1);
    check("No token card consumed from hand/library",
          player(0)->game->library->nb_cards == 30 && player(0)->game->hand->nb_cards == 0);
}
void combat()
{
    fixture();
    auto *attacker = permanent(0, "Grizzly Bears");
    auto *blocker = permanent(1, "Grizzly Bears");
    advance(MTG_PHASE_COMBATATTACKERS);
    click(attacker);
    check("Attacker declared through native card input", attacker->isAttacker());
    advance(MTG_PHASE_COMBATBLOCKERS);
    click(blocker);
    click(attacker);
    observed["declaredBlock"] = state();
    check("Real blocker was assigned to declared attacker", blocker->isDefenser() == attacker);
    advance(MTG_PHASE_SECONDMAIN);
    check("Both Bears die", named(player(0)->game->inPlay, "Grizzly Bears") == 0 &&
                                named(player(1)->game->inPlay, "Grizzly Bears") == 0);
    check("Both life totals stay twenty", player(0)->life == 20 && player(1)->life == 20);
    check("Both Bears in owners graveyards",
          named(player(0)->game->graveyard, "Grizzly Bears") == 1 &&
              named(player(1)->game->graveyard, "Grizzly Bears") == 1);
}
void copy()
{
    fixture();
    auto *bears = permanent(1, "Grizzly Bears");
    permanent(0, "Forest");
    permanent(0, "Island");
    for (int i = 0; i < 3; ++i)
        permanent(0, "Plains");
    add(0, "Giant Growth", player(0)->game->hand);
    add(0, "Clone", player(0)->game->hand);
    mana(0, {"Forest"});
    cast(0, "Giant Growth", bears);
    settle();
    check("Original really grew to 5/5", bears->getPower() == 5 && bears->getToughness() == 5);
    mana(0, {"Island", "Plains", "Plains", "Plains"});
    cast(0, "Clone");
    for (int step = 0; step < 100; ++step) {
        if (game->mLayers->actionLayer()->menuObject)
            menu("copy");
        else if (game->getCurrentTargetChooser()) {
            game->cardClick(bears, bears);
            tick();
        } else if (stack()->count(0, NOT_RESOLVED) == 0)
            break;
        else
            pass();
    }
    settle();
    check("Clone enters as Bears copy", named(player(0)->game->inPlay, "Grizzly Bears") == 1);
    auto *clone = find(player(0)->game->inPlay, "Grizzly Bears");
    check("Copy is 2/2", clone->getPower() == 2 && clone->getToughness() == 2);
    check("Original remains 5/5", bears->getPower() == 5 && bears->getToughness() == 5);
}
void adventure()
{
    fixture();
    permanent(0, "Forest");
    permanent(0, "Forest");
    permanent(0, "Plains");
    permanent(0, "Plains");
    const std::string name = "Lovestruck Beast // Heart's Desire";
    add(0, name, player(0)->game->hand);
    mana(0, {"Forest"});
    click(find(player(0)->game->hand, name));
    if (game->mLayers->actionLayer()->menuObject)
        menu("adventure");
    settle();
    observed["adventureResolved"] = state();
    int humans = 0;
    for (auto *card : player(0)->game->inPlay->cards)
        if (card->isToken && card->hasType("Human") && card->hasColor(Constants::MTG_COLOR_WHITE) &&
            card->getPower() == 1 && card->getToughness() == 1)
            humans++;
    check("Exactly one white 1/1 Human token", humans == 1);
    check("Adventure card in exile", named(player(0)->game->exile, name) == 1);
    mana(0, {"Forest", "Plains", "Plains"});
    click(find(player(0)->game->exile, name));
    if (game->mLayers->actionLayer()->menuObject)
        menu("cast");
    settle();
    auto *beast = find(player(0)->game->inPlay, name);
    check("Same adventure card cast from exile as 5/5",
          beast->getPower() == 5 && beast->getToughness() == 5 &&
              named(player(0)->game->exile, name) == 0);
}
void modal()
{
    fixture();
    auto *card = add(0, "Bala Ged Recovery", player(0)->game->hand);
    tick(3);
    click(card);
    if (game->mLayers->actionLayer()->menuObject)
        menu("Bala Ged Sanctuary");
    settle();
    if (named(player(0)->game->inPlay, "Bala Ged Sanctuary") == 0) {
        click(find(player(0)->game->hand, "Bala Ged Sanctuary"));
        if (game->mLayers->actionLayer()->menuObject)
            menu("Bala Ged Sanctuary");
        settle();
    }
    observed["afterFaceChoice"] = state();
    check("Land face enters tapped",
          named(player(0)->game->inPlay, "Bala Ged Sanctuary") == 1 &&
              find(player(0)->game->inPlay, "Bala Ged Sanctuary")->isTapped());
    check("No sorcery resolved", player(0)->game->graveyard->nb_cards == 0 &&
                                     player(0)->game->hand->nb_cards == 0 &&
                                     stack()->count(ACTION_SPELL, NOT_RESOLVED) == 0);
    advance(MTG_PHASE_FIRSTMAIN, 1);
    advance(MTG_PHASE_FIRSTMAIN, 0);
    auto *sanctuary = find(player(0)->game->inPlay, "Bala Ged Sanctuary");
    check("Land naturally untapped next turn", !sanctuary->isTapped());
    click(sanctuary);
    check("Tap produces green mana", sanctuary->isTapped() && player(0)->getManaPool()->getCost(
                                                                  Constants::MTG_COLOR_GREEN) == 1);
}
void four(const std::string &id)
{
    fixture();
    observed["runtimeInitializedPlayers"] = int(game->players.size());
    observed["requestedScenarioPlayers"] = 4;
    observed["sourceGate"] =
        "Rules::initPlayers initializes exactly two; GameObserver::receiveEvent loops exactly two; "
        "ActionStack interruptDecision[2]; GameObserver ExtraRules[2]; Player::opponent returns "
        "one other seat";
    observed["statusHint"] = "UNSUPPORTED";
    observed["limitation"] = QString::fromStdString(
        id +
        " requires a four-player game; actual declared rules create two players and core "
        "event/priority state is two-player. No fabricated four-player fixture or 1v1 substitute.");
}
QJsonArray names(MTGGameZone *zone)
{
    QJsonArray result;
    for (auto *card : zone->cards)
        result.append(QString::fromStdString(card->name));
    return result;
}
QJsonObject project(int viewer)
{
    QJsonArray players;
    for (int seat = 0; seat < 2; ++seat) {
        auto *p = player(seat);
        QJsonObject hand{{"count", p->game->hand->nb_cards}};
        if (seat == viewer)
            hand["cards"] = names(p->game->hand);
        players.append(QJsonObject{{"seat", seat},
                                   {"life", p->life},
                                   {"hand", hand},
                                   {"library", QJsonObject{{"count", p->game->library->nb_cards}}},
                                   {"battlefield", names(p->game->inPlay)},
                                   {"graveyard", names(p->game->graveyard)},
                                   {"exile", names(p->game->exile)}});
    }
    return {{"viewer", viewer}, {"players", players}};
}
QString nativePlayers()
{
    // These are the real nested serializers used by GameObserver's [init]
    // network synchronization. No socket delivery or redacted native DTO is claimed.
    std::ostringstream out;
    out << "[player1]\n" << *player(0) << "[player2]\n" << *player(1);
    return QString::fromStdString(out.str());
}
void hidden()
{
    fixture();
    add(0, "Shock", player(0)->game->hand);
    add(1, "Healing Salve", player(1)->game->hand);
    for (int seat = 0; seat < 2; ++seat) {
        auto *lib = player(seat)->game->library;
        delete lib->removeCard(lib->cards.front(), 0);
        add(seat, seat == 0 ? "Ancestral Recall" : "Counterspell", lib);
    }
    auto *bears = permanent(1, "Grizzly Bears");
    const int knownBearsId = bears->getMTGId();
    QString raw = nativePlayers();
    observed["nativePlayerSerialization"] = raw;
    observed["nativeSecretRecovery"] = QJsonObject{
        {"shockCatalogId", MTGCollection()->getCardByName("Shock")->getMTGId()},
        {"healingSalveCatalogId", MTGCollection()->getCardByName("Healing Salve")->getMTGId()}};
    const QString secret =
        QString::number(MTGCollection()->getCardByName("Healing Salve")->getMTGId());
    if (!raw.contains("hand=" + secret))
        throw std::runtime_error("Native serialization leak hypothesis not reproduced");
    observed["nativeIdentityRecoverable"] = true;
    QJsonObject owner = project(0), opponent = project(1), spectator = project(-1);
    observed["hostViews"] = QJsonArray{owner, opponent, spectator};
    check("Host owner sees own hand",
          owner["players"].toArray()[0].toObject()["hand"].toObject()["cards"].toArray().contains(
              "Shock"));
    check("Host opponent and spectator cannot identify secret hands",
          !QJsonDocument(opponent).toJson().contains("Shock") &&
              !QJsonDocument(owner).toJson().contains("Healing Salve") &&
              !QJsonDocument(spectator).toJson().contains("Shock") &&
              !QJsonDocument(spectator).toJson().contains("Healing Salve"));
    bool countOnly = true;
    for (auto view : {owner, opponent, spectator})
        for (auto p : view["players"].toArray())
            countOnly &= p.toObject()["library"].toObject().size() == 1 &&
                         p.toObject()["library"].toObject().contains("count");
    check("Host libraries are count-only for every viewer", countOnly);
    check("Host public Bears and counts visible",
          QJsonDocument(spectator).toJson().contains("Grizzly Bears") &&
              spectator["players"].toArray()[1].toObject()["hand"].toObject()["count"].toInt() ==
                  1);
    permanent(0, "Island");
    permanent(0, "Plains");
    permanent(0, "Plains");
    auto *myr = permanent(1, "Myr Mindservant");
    permanent(1, "Plains");
    permanent(1, "Plains");
    add(0, "Time Ebb", player(0)->game->hand);
    mana(0, {"Island", "Plains", "Plains"});
    cast(0, "Time Ebb", bears);
    settle();
    check("Real Time Ebb moves known public Bears into library",
          named(player(1)->game->library, "Grizzly Bears") == 1 &&
              named(player(1)->game->inPlay, "Grizzly Bears") == 0);
    observed["beforeShuffleOracle"] = state();
    const QJsonArray beforeShuffleLibrary = zone(player(1)->game->library);
    // Give P1 a real interrupt opportunity without advancing through a draw,
    // which would otherwise remove the known top card before the shuffle.
    permanent(0, "Mountain");
    mana(0, {"Mountain"});
    cast(0, "Shock", player(1));
    observed["knownPublicCatalogId"] = knownBearsId;
    mana(1, {"Plains", "Plains"});
    click(myr);
    settle();
    check("Myr activation actually pays and taps",
          myr->isTapped() && player(1)->getManaPool()->getConvertedCost() == 0);
    check("Real paid shuffle changes ordered library instances",
          beforeShuffleLibrary != zone(player(1)->game->library));
    check("Known public card remains in shuffled library",
          named(player(1)->game->library, "Grizzly Bears") == 1 &&
              find(player(1)->game->library, "Grizzly Bears")->getMTGId() == knownBearsId);
    observed["afterShuffleNativeSerialization"] = nativePlayers();
    observed["afterShuffleOracle"] = state();
    QJsonArray after;
    bool noTrackedId = true;
    for (int viewer : {0, 1, -1}) {
        auto view = project(viewer);
        after.append(view);
        for (auto p : view["players"].toArray())
            noTrackedId &= p.toObject()["library"].toObject().size() == 1;
    }
    check("Host library projection has no names or ordered stable IDs after shuffle", noTrackedId);
    observed["hostAfterShuffleViews"] = after;
    observed["hostRemediationStatus"] = "PASS";
    assertions.append(QJsonObject{
        {"name", "Native network component serializer conceals private card identities"},
        {"passed", false}});
    observed["failureReason"] =
        "Native hand/library catalog IDs are recoverable through actual serialized bytes";
    observed["statusHint"] = "FAIL";
    observed["layerHint"] = "adapter";
    observed["limitation"] = "Actual native network component serialization reveals hand and "
                             "library catalog IDs. Separately tested host whitelist remediation "
                             "passes; not a native privacy PASS or production DTO certification.";
}
void morph()
{
    observed["defaultCatalogHasWillbender"] = bool(MTGCollection()->getCardByName("Willbender"));
    // Upstream documents grades and ships this exact card in unsupported.txt.
    // Explicitly test that opt-in catalog instead of substituting another morph.
    options[Options::MAX_GRADE].number = Constants::GRADE_UNSUPPORTED;
    // Loading every unsupported card recurses forever on another card's {PW}
    // cost. The runner copies only the exact, unmodified Willbender block into
    // this isolated profile; no upstream definition is repaired or synthesized.
    MTGCollection()->load("evaluation-assets/willbender-eval.txt");
    MTGCollection()->loadFolder("sets/", "_cards.dat");
    MTGCollection()->prefetchCardNameCache(); // Refresh the earlier negative name lookup after
                                              // adding the exact original primitive.
    observed["catalogConfiguration"] =
        "Curated exact upstream Willbender block from unsupported.txt through native catalog "
        "loader, MAX_GRADE=GRADE_UNSUPPORTED; not the default card pool nor a claim that the "
        "entire unsupported-grade catalog loads";
    fixture();
    permanent(0, "Island");
    for (int i = 0; i < 4; ++i)
        permanent(0, "Plains");
    add(0, "Willbender", player(0)->game->hand);
    mana(0, {"Plains", "Plains", "Plains"});
    click(find(player(0)->game->hand, "Willbender"));
    if (game->mLayers->actionLayer()->menuObject)
        menu("morph");
    observed["faceDownStackOracle"] = state();
    MTGCardInstance *spell =
        player(0)->game->stack->nb_cards ? player(0)->game->stack->cards.front() : nullptr;
    check("Face-down spell has real 3 payment and 2/2 colorless zero mana cost",
          spell && spell->isMorphed && spell->getPower() == 2 && spell->getToughness() == 2 &&
              spell->getColor() == Constants::MTG_COLOR_ARTIFACT &&
              spell->getManaCost()->getConvertedCost() == 0 &&
              player(0)->getManaPool()->getConvertedCost() == 0);
    std::ostringstream stackBytes;
    stackBytes << *player(0)->game->stack;
    observed["nativeFaceDownStackZoneSerializer"] = QString::fromStdString(stackBytes.str());
    settle();
    MTGCardInstance *facedown = nullptr;
    for (auto *card : player(0)->game->inPlay->cards)
        if (card->isMorphed)
            facedown = card;
    observed["faceDownBattlefieldOracle"] = state();
    check("Face-down permanent resolves as 2/2 colorless",
          facedown && facedown->getPower() == 2 && facedown->getToughness() == 2 &&
              facedown->getColor() == Constants::MTG_COLOR_ARTIFACT &&
              facedown->getManaCost()->getConvertedCost() == 0);
    const quintptr identity = reinterpret_cast<quintptr>(facedown);
    const QString secretId = QString::number(facedown->getMTGId());
    const QString bytes = nativePlayers();
    observed["nativeFaceDownBattlefieldSerializer"] = bytes;
    const bool leaked =
        bytes.contains(secretId) &&
        MTGCollection()->getCardById(facedown->getMTGId())->data->name == "Willbender";
    observed["nativeFaceDownIdentityRecoverable"] = leaked;
    assertions.append(QJsonObject{
        {"name", "Native face-down serializers do not disclose Willbender"}, {"passed", !leaked}});
    mana(0, {"Island", "Plains"});
    click(facedown);
    if (game->mLayers->actionLayer()->menuObject)
        menu("morph");
    settle();
    check("Turning face up preserves permanent and becomes Willbender 1/2",
          facedown->name == "Willbender" &&
              reinterpret_cast<quintptr>(find(player(0)->game->inPlay, "Willbender")) == identity &&
              facedown->getPower() == 1 && facedown->getToughness() == 2);
    observed["layerHint"] = "adapter";
    observed["limitation"] =
        "Opt-in unsupported-grade exact Willbender; rules actions run, but actual native "
        "public-zone serializers expose its recoverable catalog ID while face down";
    observed["willbenderCountAfterTurningUp"] = named(player(0)->game->inPlay, "Willbender");
    if (named(player(0)->game->inPlay, "Willbender") != 1) {
        observed["layerHint"] = "engine";
        observed["additionalAdapterFailure"] =
            "Native face-down card catalog IDs also disclose identity";
        check("Turning Willbender face up does not create an extra copy token", false);
    }
}
void booster()
{
    srand(1024);
    ShopBooster boosters;
    for (int i = 0; i < 5; ++i)
        check("Upstream ShopBooster unitTest", boosters.unitTest());
    observed["supplement"] =
        "Five actual upstream TestSuite::pregameTests booster checks; separate from the 720 "
        "console card fixtures and from shared semantic cases";
}
} // namespace

void prepareCatalog()
{
    QJsonArray lookups;
    bool missing = false;
    for (const std::string name : {"Goblin Glasswright", "Craft with Pride"}) {
        const auto *card = MTGCollection()->getCardByName(name);
        missing |= !card;
        lookups.append(QJsonObject{{"name", QString::fromStdString(name)}, {"loaded", bool(card)}});
    }
    observed["cardLookups"] = lookups;
    observed["SOSSetIndex"] = setlist["SOS"];
    observed["loadedSetCount"] = setlist.size();
    observed["statusHint"] = missing ? "UNSUPPORTED" : "UNVERIFIED";
    observed["layerHint"] = missing ? "engine" : "fixture";
    observed["limitation"] =
        missing ? "Actual initialized native catalog cannot find the exact Prepare cards; SOS "
                  "lookup is separately recorded. No substitute card or new mechanic "
                  "implementation is injected; frozen casting/removal actions cannot begin."
                : "Cards exist; full Prepare fixture requires implementation.";
}

int main(int argc, char **argv)
{
    QCoreApplication qt(argc, argv);
    WagicWrapper core;
    MTGCollection()->loadFolder("sets/primitives/");
    MTGCollection()->loadFolder("sets/", "_cards.dat");
    options.reloadProfile();
    const std::string id = argc > 1 ? argv[1] : "bolt_player";
    negativeControl = argc > 2 && std::string(argv[2]) == "negative_control";
    if (negativeControl)
        observed["negativeControl"] = true;
    QJsonObject result{{"id", QString::fromStdString(id)}};
    try {
        if (id == "opening")
            opening();
        else if (id == "land_priority")
            land();
        else if (id == "bolt_player")
            bolt(false, false);
        else if (id == "bolt_creature")
            bolt(true, false);
        else if (id == "replacement")
            bolt(true, true);
        else if (id == "counterspell")
            counterspell();
        else if (id == "etb_draw")
            visionary();
        else if (id == "tokens")
            tokens();
        else if (id == "blocked_combat")
            combat();
        else if (id == "copy")
            copy();
        else if (id == "adventure")
            adventure();
        else if (id == "modal_dfc")
            modal();
        else if (id == "hidden_views")
            hidden();
        else if (id == "morph")
            morph();
        else if (id == "upstream_boosters")
            booster();
        else if (id == "prepare_cast" || id == "prepare_source_leaves")
            prepareCatalog();
        else if (id == "four_player_departure" || id == "commander_tax" || id == "commander_damage")
            four(id);
        else
            throw std::runtime_error("Fixture adapter not yet implemented");
    } catch (const std::exception &error) {
        result["error"] = error.what();
    }
    if (game && game->mLayers)
        observed["final"] = state();
    result["assertions"] = assertions;
    result["observed"] = observed;
    result["decisions"] = decisions;
    std::cout << "HEXPROOF_OBSERVATION "
              << QJsonDocument(result).toJson(QJsonDocument::Compact).constData() << std::endl;
    game.reset();
    return result.contains("error") ? 1 : 0;
}
