// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "services/RulesLaneSlotModel.h"
#include "services/RulesSessionState.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QtTest>

using namespace hexproof::client;
using namespace Qt::StringLiterals;

namespace {
QJsonObject card(const QString &id, const QString &name)
{
    return {{u"id"_s, id},
            {u"ownerSeat"_s, 0},
            {u"controllerSeat"_s, 0},
            {u"visible"_s, true},
            {u"identity"_s, QJsonObject{{u"name"_s, name}}}};
}

QJsonObject snapshot(const QJsonArray &hand, const QJsonArray &field,
                     const QString &gameId = u"game"_s, int opponentLibrary = 40,
                     int opponentHand = 7, int life = 20)
{
    return {{u"roomId"_s, u"ROOM01"_s},
            {u"gameId"_s, gameId},
            {u"turn"_s, 1},
            {u"step"_s, u"main1"_s},
            {u"activeSeat"_s, 0},
            {u"prioritySeat"_s, 0},
            {u"players"_s,
             QJsonArray{QJsonObject{{u"seat"_s, 0}, {u"name"_s, u"Ada"_s}, {u"life"_s, life}},
                        QJsonObject{{u"seat"_s, 1}, {u"name"_s, u"Bea"_s}, {u"life"_s, 20}}}},
            {u"zones"_s, QJsonArray{QJsonObject{{u"zone"_s, u"hand"_s},
                                                {u"ownerSeat"_s, 0},
                                                {u"count"_s, hand.size()},
                                                {u"cards"_s, hand}},
                                    QJsonObject{{u"zone"_s, u"library"_s},
                                                {u"ownerSeat"_s, 1},
                                                {u"count"_s, opponentLibrary},
                                                {u"cards"_s, QJsonArray{}}},
                                    QJsonObject{{u"zone"_s, u"hand"_s},
                                                {u"ownerSeat"_s, 1},
                                                {u"count"_s, opponentHand},
                                                {u"cards"_s, QJsonArray{}}},
                                    QJsonObject{{u"zone"_s, u"battlefield"_s},
                                                {u"ownerSeat"_s, 0},
                                                {u"count"_s, field.size()},
                                                {u"cards"_s, field}}}},
            {u"stack"_s, QJsonArray{}}};
}

QJsonObject withZone(QJsonObject state, const QString &zone, int ownerSeat, const QJsonArray &cards)
{
    QJsonArray zones = state.value(u"zones"_s).toArray();
    for (qsizetype index = 0; index < zones.size(); ++index) {
        const QJsonObject existing = zones.at(index).toObject();
        if (existing.value(u"zone"_s) == zone && existing.value(u"ownerSeat"_s) == ownerSeat)
            zones.removeAt(index--);
    }
    zones.append(QJsonObject{{u"zone"_s, zone},
                             {u"ownerSeat"_s, ownerSeat},
                             {u"count"_s, cards.size()},
                             {u"cards"_s, cards}});
    state.insert(u"zones"_s, zones);
    return state;
}

QJsonObject hiddenCard(const QString &id, int seat)
{
    return {
        {u"id"_s, id}, {u"ownerSeat"_s, seat}, {u"controllerSeat"_s, seat}, {u"visible"_s, false}};
}

QJsonObject option(const QString &responseId, const QString &label, const QString &cardId = {})
{
    QJsonObject result{{u"responseId"_s, responseId},
                       {u"kind"_s, cardId.isEmpty() ? u"pass"_s : u"cast"_s},
                       {u"label"_s, label}};
    if (!cardId.isEmpty())
        result.insert(u"cardId"_s, cardId);
    return result;
}

QJsonObject chooseAction(int promptId, const QJsonArray &options)
{
    QJsonObject prompt{{u"roomId"_s, u"ROOM01"_s},     {u"gameId"_s, u"game"_s},
                       {u"pending"_s, true},           {u"promptId"_s, promptId},
                       {u"kind"_s, u"chooseAction"_s}, {u"supported"_s, true},
                       {u"options"_s, options},        {u"totalDamage"_s, 0}};
    for (const QString &key :
         {u"choices"_s, u"cards"_s, u"scryDestinations"_s, u"targets"_s, u"contextCards"_s,
          u"contextTargets"_s, u"combatSources"_s, u"combatTargets"_s, u"damageTargets"_s})
        prompt.insert(key, QJsonArray{});
    return prompt;
}

QVariantMap eventFor(const QVariantList &events, const QString &id)
{
    for (const QVariant &value : events) {
        const QVariantMap event = value.toMap();
        if (event.value(u"id"_s).toString() == id)
            return event;
    }
    return {};
}
} // namespace

class TypeCatalog final : public QObject
{
    Q_OBJECT

  public:
    Q_INVOKABLE QString cardTypeLine(const QString &name, const QString &setCode = {},
                                     const QString &collectorNumber = {}) const
    {
        ++lookups;
        requestedNames.append(name);
        const QString printing = QStringList{name, setCode, collectorNumber}.join(u'\u001f');
        if (printingOverrides.contains(printing))
            return printingOverrides.value(printing);
        if (overrides.contains(name))
            return overrides.value(name);
        return name == u"Plains"_s ? u"Land"_s : u"Creature"_s;
    }
    QHash<QString, QString> overrides;
    QHash<QString, QString> printingOverrides;
    mutable int lookups = 0;
    mutable QStringList requestedNames;

  signals:
    void cardAvailable(const QString &requestedName, const QString &localizedName,
                       const QString &typeLine, const QString &imagePath, const QString &setCode,
                       const QString &collectorNumber);
    void languageChanged();
};

struct LaneSignals
{
    explicit LaneSignals(QAbstractItemModel *model)
        : resets(model, &QAbstractItemModel::modelReset),
          inserted(model, &QAbstractItemModel::rowsInserted),
          removed(model, &QAbstractItemModel::rowsRemoved),
          moved(model, &QAbstractItemModel::rowsMoved),
          changed(model, &QAbstractItemModel::dataChanged)
    {
    }
    QSignalSpy resets;
    QSignalSpy inserted;
    QSignalSpy removed;
    QSignalSpy moved;
    QSignalSpy changed;
};

QStringList laneIds(const QAbstractItemModel *model)
{
    QStringList ids;
    for (int row = 0; row < model->rowCount(); ++row)
        ids.append(model->data(model->index(row, 0), RulesCardModel::IdRole).toString());
    return ids;
}

QVector<RulesCardRow> identicalCreatures()
{
    QVector<RulesCardRow> rows;
    for (int index = 0; index < 4; ++index) {
        RulesCardRow row;
        row.id = u"creature-%1"_s.arg(index);
        row.name = u"Soldier"_s;
        row.zone = u"battlefield"_s;
        row.zoneOwnerSeat = 0;
        row.ownerSeat = 0;
        row.controllerSeat = 0;
        row.visible = true;
        row.token = true;
        row.power = u"1"_s;
        row.toughness = u"1"_s;
        rows.append(row);
    }
    return rows;
}

class RulesTransitionsTest final : public QObject
{
    Q_OBJECT

  private slots:
    void sameIdMoveIsOneFlight() const;
    void laneSlotsPileLandsAndKeepCreaturesSeparate() const;
    void laneLayoutBudgetsPublicPilesAcrossTapChanges() const;
    void combatParticipantsLeavePiles_data() const;
    void combatParticipantsLeavePiles() const;
    void combatRelationshipOrderDoesNotSplitPiles_data() const;
    void combatRelationshipOrderDoesNotSplitPiles() const;
    void draftCombatSplitsBatchAndPreserveAttachments() const;
    void publicBlockersRepileOncePerSnapshot() const;
    void attachmentHostKeepsItsOwnSlot() const;
    void reorderedSnapshotKeepsRowsOnTheirCards() const;
    void untapStepRepilesOncePerLane() const;
    void knownCardArrivalTouchesNoRows() const;
    void planeswalkerLaneUsesPublicTypes_data() const;
    void planeswalkerLaneUsesPublicTypes() const;
    void planeswalkerLaneTracksIdentityAndPrintingChanges() const;
    void planeswalkerLaneBatchesTransformationsAndAttachments() const;
    void cardPresentationAvoidsScanningEveryRelationship() const;
    void changedIdIsInferredOnce() const;
    void ambiguousNamesStaySeparate() const;
    void gameChangeAndSeekJumpDoNotAnimate() const;
    void reconnectJumpsOnce() const;
    void hiddenOpponentDrawHasNoName() const;
    void projectionsNameOnlyWhatTheViewerSees_data() const;
    void projectionsNameOnlyWhatTheViewerSees() const;
    void placementReportsOnlyVisibleCards() const;
    void seatZoneFollowsMovesWithinZoneCards() const;
    void promptOptionsUpdateInPlace() const;
    void mulliganOffersOnlyTypedAbilitiesAndClearsThemAfterRedraw() const;
};

void RulesTransitionsTest::laneSlotsPileLandsAndKeepCreaturesSeparate() const
{
    RulesSessionState session;
    TypeCatalog catalog;
    session.setPresentationCatalog(&catalog);
    QJsonObject plains = card(u"land-a"_s, u"Plains"_s);
    QJsonObject tapped = card(u"land-b"_s, u"Plains"_s);
    tapped.insert(u"tapped"_s, true);
    QJsonObject bear = card(u"bear"_s, u"Bear"_s);
    bear.insert(u"power"_s, u"2"_s);
    bear.insert(u"toughness"_s, u"2"_s);
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{plains, tapped, bear})));
    QAbstractItemModel *lands = session.laneSlots(0, u"battlefield"_s, u"land"_s);
    QAbstractItemModel *creatures = session.laneSlots(0, u"battlefield"_s, u"creature"_s);
    QVERIFY(lands);
    QVERIFY(creatures);
    QCOMPARE(lands->rowCount(), 2);
    QCOMPARE(creatures->rowCount(), 1);
    QCOMPARE(lands->data(lands->index(0, 0), RulesLaneSlotModel::SlotSizeRole).toInt(), 1);
    QCOMPARE(lands->data(lands->index(0, 0), RulesCardModel::IdRole).toString(), u"land-a"_s);
    QCOMPARE(lands->data(lands->index(1, 0), RulesLaneSlotModel::SlotIndexRole).toInt(), 1);
    QCOMPARE(lands->data(lands->index(1, 0), RulesCardModel::IdRole).toString(), u"land-b"_s);
    QCOMPARE(lands->property("stacks").toList().size(), 2);
    QCOMPARE(creatures->data(creatures->index(0, 0), RulesCardModel::IdRole).toString(), u"bear"_s);
}

void RulesTransitionsTest::laneLayoutBudgetsPublicPilesAcrossTapChanges() const
{
    RulesSessionState session;
    TypeCatalog catalog;
    session.setPresentationCatalog(&catalog);
    QJsonArray field;
    for (int index = 0; index < 100; ++index)
        field.append(card(u"land-%1"_s.arg(index), u"Plains"_s));
    QVERIFY(session.applySnapshot(snapshot({}, field)));
    QAbstractItemModel *lands = session.laneSlots(0, u"battlefield"_s, u"land"_s);
    QCOMPARE(lands->rowCount(), 100);
    QCOMPARE(lands->property("stacks").toList().size(), 1);
    QCOMPARE(lands->property("layoutStackCount").toInt(), 2);
    QSignalSpy layoutChanges(lands, SIGNAL(layoutStackCountChanged()));
    QVERIFY(layoutChanges.isValid());

    for (bool tapped : {true, false}) {
        for (int index = 0; index < 50; ++index) {
            QJsonObject land = field.at(index).toObject();
            land.insert(u"tapped"_s, tapped);
            field.replace(index, land);
        }
        QVERIFY(session.applySnapshot(snapshot({}, field)));
        QCOMPARE(lands->property("stacks").toList().size(), tapped ? 2 : 1);
        QCOMPARE(lands->property("layoutStackCount").toInt(), 2);
        QCOMPARE(layoutChanges.count(), 0);
    }

    // A distinct public identity needs a separate slot; concealed identities
    // never share a budget through their names or a catalog lookup.
    field.append(card(u"different-land"_s, u"Forest"_s));
    catalog.overrides.insert(u"Forest"_s, u"Land"_s);
    QVERIFY(session.applySnapshot(snapshot({}, field)));
    QCOMPARE(lands->property("layoutStackCount").toInt(), 3);
    QCOMPARE(layoutChanges.count(), 1);
    QAbstractItemModel *others = session.laneSlots(0, u"battlefield"_s, u"other"_s);
    const int publicLookups = catalog.lookups;
    field.append(hiddenCard(u"hidden-a"_s, 0));
    field.append(hiddenCard(u"hidden-b"_s, 0));
    QVERIFY(session.applySnapshot(snapshot({}, field)));
    QCOMPARE(others->property("layoutStackCount").toInt(), 2);
    QCOMPARE(catalog.lookups, publicLookups);
    QCOMPARE(layoutChanges.count(), 1);

    QVERIFY(session.applySnapshot(snapshot({}, {})));
    QCOMPARE(lands->property("layoutStackCount").toInt(), 0);
    QCOMPARE(others->property("layoutStackCount").toInt(), 0);
    QCOMPARE(layoutChanges.count(), 2);
}

void RulesTransitionsTest::combatParticipantsLeavePiles_data() const
{
    QTest::addColumn<int>("role");
    QTest::newRow("attacker-without-tapping") << int(RulesCardModel::AttackingRole);
    QTest::newRow("attacking-permanent") << int(RulesCardModel::AttackingTargetRole);
    QTest::newRow("attacking-player") << int(RulesCardModel::AttackingSeatRole);
    QTest::newRow("blocking") << int(RulesCardModel::BlockingIdsRole);
    QTest::newRow("blocked-by") << int(RulesCardModel::BlockedByIdsRole);
    QTest::newRow("attacked-by") << int(RulesCardModel::AttackedByIdsRole);
}

void RulesTransitionsTest::combatParticipantsLeavePiles() const
{
    QFETCH(int, role);
    RulesCardModel source;
    source.replace(identicalCreatures());
    RulesLaneSlotModel lane(&source, 0, u"battlefield"_s, u"creature"_s);
    QCOMPARE(lane.stacks().size(), 1);
    QCOMPARE(lane.layoutStackCount(), 2);
    LaneSignals laneSignals(&lane);
    QSignalSpy stackChanges(&lane, &RulesLaneSlotModel::stacksChanged);
    const auto updateCombat = [&](int count, const QString &relatedId, bool distinct = false) {
        QVector<RulesCardRow> rows = identicalCreatures();
        QHash<QString, RulesCardModel::Presentation> presentations;
        for (int index = 0; index < count; ++index) {
            RulesCardRow &row = rows[index];
            const QString target = distinct && index == 1 ? u"other-opponent"_s : relatedId;
            auto &presentation = presentations[row.id];
            switch (role) {
            case RulesCardModel::AttackingRole:
                row.attacking = true;
                break;
            case RulesCardModel::AttackingTargetRole:
                row.attackingTarget = target;
                break;
            case RulesCardModel::AttackingSeatRole:
                row.attackingSeat = distinct && index == 1 ? 2 : 1;
                break;
            case RulesCardModel::BlockingIdsRole:
                presentation.blockingIds = {target};
                break;
            case RulesCardModel::BlockedByIdsRole:
                presentation.blockedByIds = {target};
                break;
            case RulesCardModel::AttackedByIdsRole:
                presentation.attackedByIds = {target};
                break;
            }
        }
        lane.beginBatch();
        source.replace(rows);
        source.setPresentations(presentations);
        lane.endBatch();
    };

    updateCombat(1, u"opponent-a"_s);
    QCOMPARE(lane.stacks().size(), 2);
    QCOMPARE(lane.layoutStackCount(), 3);
    QCOMPARE(stackChanges.count(), 1);
    const int firstRow = laneIds(&lane).indexOf(u"creature-0"_s);
    QCOMPARE(lane.data(lane.index(firstRow, 0), RulesLaneSlotModel::SlotSizeRole).toInt(), 1);
    QVERIFY(!lane.data(lane.index(firstRow, 0), RulesCardModel::TappedRole).toBool());

    // Changing a combat partner preserves the split and forwards the new relationship.
    updateCombat(1, u"opponent-b"_s);
    QCOMPARE(lane.stacks().size(), 2);
    QCOMPARE(stackChanges.count(), 1);
    if (role == RulesCardModel::AttackingTargetRole)
        QCOMPARE(lane.data(lane.index(firstRow, 0), role).toString(), u"opponent-b"_s);
    else if (role >= RulesCardModel::BlockingIdsRole)
        QCOMPARE(lane.data(lane.index(firstRow, 0), role).toStringList(),
                 QStringList{u"opponent-b"_s});

    updateCombat(2, u"opponent-b"_s);
    QCOMPARE(lane.stacks().size(), 2);
    QCOMPARE(lane.layoutStackCount(), 4);
    for (const QString &id : {u"creature-0"_s, u"creature-1"_s}) {
        const int row = laneIds(&lane).indexOf(id);
        QCOMPARE(lane.data(lane.index(row, 0), RulesLaneSlotModel::SlotSizeRole).toInt(), 2);
    }
    int expectedStackChanges = 3;
    if (role != RulesCardModel::AttackingRole) {
        updateCombat(2, u"opponent-b"_s, true);
        QCOMPARE(lane.stacks().size(), 3);
        QCOMPARE(lane.layoutStackCount(), 4);
        ++expectedStackChanges;
    }
    updateCombat(0, {});
    QCOMPARE(lane.stacks().size(), 1);
    QCOMPARE(lane.layoutStackCount(), 2);
    QCOMPARE(stackChanges.count(), expectedStackChanges);
    QCOMPARE(
        laneSignals.resets.count() + laneSignals.inserted.count() + laneSignals.removed.count(), 0);

    // Legal-action hints still update in place without changing pile geometry.
    RulesCardModel::Presentation action;
    action.actionCount = 1;
    action.primaryResponseId = u"activate"_s;
    laneSignals.changed.clear();
    source.setPresentations({{u"creature-0"_s, action}});
    QCOMPARE(stackChanges.count(), expectedStackChanges);
    QCOMPARE(laneSignals.changed.count(), 1);
    QCOMPARE(qvariant_cast<QList<int>>(laneSignals.changed.constFirst().at(2)),
             (QList<int>{RulesCardModel::ActionCountRole, RulesCardModel::PrimaryResponseIdRole}));
}

void RulesTransitionsTest::combatRelationshipOrderDoesNotSplitPiles_data() const
{
    QTest::addColumn<int>("role");
    QTest::newRow("blocking") << int(RulesCardModel::BlockingIdsRole);
    QTest::newRow("blocked-by") << int(RulesCardModel::BlockedByIdsRole);
    QTest::newRow("attacked-by") << int(RulesCardModel::AttackedByIdsRole);
}

void RulesTransitionsTest::combatRelationshipOrderDoesNotSplitPiles() const
{
    QFETCH(int, role);
    RulesCardModel source;
    QVector<RulesCardRow> rows = identicalCreatures();
    if (role == RulesCardModel::BlockedByIdsRole) {
        for (RulesCardRow &row : rows) {
            row.attacking = true;
            row.attackingSeat = 1;
        }
    }
    source.replace(rows);
    RulesLaneSlotModel lane(&source, 0, u"battlefield"_s, u"creature"_s);
    QHash<QString, RulesCardModel::Presentation> presentations;
    const auto setRelationships = [&](const QString &id, const QStringList &ids) {
        auto &presentation = presentations[id];
        if (role == RulesCardModel::BlockingIdsRole)
            presentation.blockingIds = ids;
        else if (role == RulesCardModel::BlockedByIdsRole)
            presentation.blockedByIds = ids;
        else
            presentation.attackedByIds = ids;
    };
    setRelationships(u"creature-0"_s, {u"first"_s, u"second"_s});
    setRelationships(u"creature-1"_s, {u"second"_s, u"first"_s, u"first"_s});
    source.setPresentations(presentations);
    QCOMPARE(lane.stacks().size(), 2);
    for (int row = 0; row < lane.rowCount(); ++row)
        QCOMPARE(lane.data(lane.index(row, 0), RulesLaneSlotModel::SlotSizeRole).toInt(), 2);
    QSignalSpy stackChanges(&lane, &RulesLaneSlotModel::stacksChanged);
    setRelationships(u"creature-1"_s, {u"first"_s, u"second"_s});
    source.setPresentations(presentations);
    QCOMPARE(stackChanges.count(), 0);
    setRelationships(u"creature-1"_s, {u"first"_s});
    source.setPresentations(presentations);
    QCOMPARE(lane.stacks().size(), 3);
    QCOMPARE(stackChanges.count(), 1);
    source.setPresentations({});
    QCOMPARE(lane.stacks().size(), 1);
}

void RulesTransitionsTest::draftCombatSplitsBatchAndPreserveAttachments() const
{
    RulesCardModel source;
    QVector<RulesCardRow> rows = identicalCreatures();
    RulesCardRow attachment = rows.constFirst();
    attachment.id = u"attachment"_s;
    attachment.attachedTo = u"creature-0"_s;
    rows.append(attachment);
    source.replace(rows);
    RulesLaneSlotModel lane(&source, 0, u"battlefield"_s, u"creature"_s);
    QCOMPARE(lane.stacks().size(), 2);
    QCOMPARE(lane.layoutStackCount(), 3);
    QSignalSpy stackChanges(&lane, &RulesLaneSlotModel::stacksChanged);
    QSignalSpy stackPreparations(&lane, &RulesLaneSlotModel::stacksAboutToChange);
    QSignalSpy draftChanges(&lane, &RulesLaneSlotModel::combatGroupingKeysChanged);
    LaneSignals laneSignals(&lane);
    bool publishingStacks = false;
    bool movesDuringPublication = true;
    connect(&lane, &RulesLaneSlotModel::stacksAboutToChange, &lane,
            [&] { publishingStacks = true; });
    connect(&lane, &QAbstractItemModel::rowsAboutToBeMoved, &lane,
            [&] { movesDuringPublication &= publishingStacks; });
    connect(&lane, &RulesLaneSlotModel::stacksChanged, &lane, [&] { publishingStacks = false; });

    lane.beginBatch();
    lane.setCombatGroupingKeys({{u"creature-1"_s, u"block:opponent"_s}});
    const QVariantMap groupingKeys{{u"creature-1"_s, u"block:opponent"_s},
                                   {u"creature-3"_s, u"block:opponent"_s},
                                   {u"attachment"_s, u"block:opponent"_s}};
    lane.setCombatGroupingKeys(groupingKeys);
    QCOMPARE(lane.stacks().size(), 2);
    QCOMPARE(stackChanges.count(), 0);
    lane.endBatch();
    QCOMPARE(lane.combatGroupingKeys(), groupingKeys);
    QCOMPARE(lane.stacks().size(), 3);
    QCOMPARE(lane.layoutStackCount(), 4);
    QCOMPARE(stackChanges.count(), 1);
    QCOMPARE(stackPreparations.count(), 1);
    QVERIFY(laneSignals.moved.count() > 0);
    QVERIFY(movesDuringPublication);
    QVERIFY(!publishingStacks);
    const int attachedRow = laneIds(&lane).indexOf(u"attachment"_s);
    QCOMPARE(lane.data(lane.index(attachedRow, 0), RulesLaneSlotModel::SlotIndexRole).toInt(), -1);
    QCOMPARE(lane.data(lane.index(attachedRow, 0), RulesCardModel::AttachedToRole).toString(),
             u"creature-0"_s);

    QVariantMap unchangedKeys = groupingKeys;
    unchangedKeys.insert(u"creature-2"_s, QString());
    unchangedKeys.insert(QString(), u"block:opponent"_s);
    lane.setCombatGroupingKeys(unchangedKeys);
    QCOMPARE(draftChanges.count(), 2);
    QCOMPARE(stackChanges.count(), 1);
    QCOMPARE(stackPreparations.count(), 1);
    QVariantMap differentKeys = groupingKeys;
    differentKeys.insert(u"creature-3"_s, u"block:other"_s);
    lane.setCombatGroupingKeys(differentKeys);
    QCOMPARE(lane.stacks().size(), 4);
    lane.setCombatGroupingKeys({});
    QCOMPARE(lane.stacks().size(), 2);
    QCOMPARE(lane.layoutStackCount(), 3);
    QCOMPARE(stackChanges.count(), 3);
    QCOMPARE(stackPreparations.count(), 3);
    QVERIFY(movesDuringPublication);
    QVERIFY(!publishingStacks);
    QCOMPARE(
        laneSignals.resets.count() + laneSignals.inserted.count() + laneSignals.removed.count(), 0);

    RulesCardModel handSource;
    rows = identicalCreatures();
    for (RulesCardRow &row : rows)
        row.zone = u"hand"_s;
    handSource.replace(rows);
    RulesLaneSlotModel hand(&handSource, 0, u"hand"_s, {});
    LaneSignals handSignals(&hand);
    hand.setCombatGroupingKeys({{u"creature-0"_s, u"attack:opponent"_s}});
    QCOMPARE(hand.stacks().size(), 4);
    QCOMPARE(handSignals.changed.count() + handSignals.moved.count(), 0);
}

void RulesTransitionsTest::publicBlockersRepileOncePerSnapshot() const
{
    RulesSessionState session;
    QJsonArray field;
    for (int index = 0; index < 4; ++index) {
        QJsonObject creature = card(u"creature-%1"_s.arg(index), u"Soldier"_s);
        creature.insert(u"power"_s, u"1"_s);
        creature.insert(u"toughness"_s, u"1"_s);
        field.append(creature);
    }
    QJsonObject attacker = field.first().toObject();
    attacker.insert(u"id"_s, u"attacker"_s);
    attacker.insert(u"controllerSeat"_s, 1);
    attacker.insert(u"ownerSeat"_s, 1);
    attacker.insert(u"attacking"_s, true);
    attacker.insert(u"attackingPlayer"_s, 0);
    field.append(attacker);
    QVERIFY(session.applySnapshot(snapshot({}, field)));
    auto *lane = session.laneSlots(0, u"battlefield"_s, u"creature"_s);
    QCOMPARE(lane->property("stacks").toList().size(), 1);
    QSignalSpy stackChanges(lane, SIGNAL(stacksChanged()));
    for (int index = 0; index < 2; ++index) {
        QJsonObject blocker = field.at(index).toObject();
        blocker.insert(u"blocking"_s, QJsonArray{u"attacker"_s});
        field.replace(index, blocker);
    }
    QVERIFY(session.applySnapshot(snapshot({}, field)));
    QCOMPARE(lane->property("stacks").toList().size(), 2);
    QCOMPARE(lane->property("layoutStackCount").toInt(), 4);
    QCOMPARE(stackChanges.count(), 1);
    for (int index = 0; index < 2; ++index) {
        QJsonObject blocker = field.at(index).toObject();
        blocker.remove(u"blocking"_s);
        field.replace(index, blocker);
    }
    QVERIFY(session.applySnapshot(snapshot({}, field)));
    QCOMPARE(lane->property("stacks").toList().size(), 1);
    QCOMPARE(stackChanges.count(), 2);
}

void RulesTransitionsTest::attachmentHostKeepsItsOwnSlot() const
{
    RulesSessionState session;
    TypeCatalog catalog;
    session.setPresentationCatalog(&catalog);
    QJsonObject first = card(u"own-0"_s, u"Grizzly Bears"_s);
    QJsonObject second = card(u"own-1"_s, u"Grizzly Bears"_s);
    for (QJsonObject *bear : {&first, &second}) {
        bear->insert(u"power"_s, u"2"_s);
        bear->insert(u"toughness"_s, u"2"_s);
    }
    QJsonObject aura = card(u"aura"_s, u"Pacifism"_s);
    aura.insert(u"attachedTo"_s, u"own-0"_s);
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{first, second, aura})));
    QAbstractItemModel *creatures = session.laneSlots(0, u"battlefield"_s, u"creature"_s);
    QCOMPARE(creatures->property("stacks").toList().size(), 2);
    QCOMPARE(creatures->property("layoutStackCount").toInt(), 2);
    for (int row = 0; row < creatures->rowCount(); ++row)
        QCOMPARE(
            creatures->data(creatures->index(row, 0), RulesLaneSlotModel::SlotSizeRole).toInt(), 1);

    aura.remove(u"attachedTo"_s);
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{first, second, aura})));
    QCOMPARE(creatures->property("stacks").toList().size(), 1);
}

void RulesTransitionsTest::reorderedSnapshotKeepsRowsOnTheirCards() const
{
    RulesSessionState session;
    QJsonObject ape = card(u"ape"_s, u"Ape"_s);
    QJsonObject bear = card(u"bear"_s, u"Bear"_s);
    for (QJsonObject *creature : {&ape, &bear}) {
        creature->insert(u"power"_s, u"2"_s);
        creature->insert(u"toughness"_s, u"2"_s);
    }
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{ape, bear})));
    QAbstractItemModel *creatures = session.laneSlots(0, u"battlefield"_s, u"creature"_s);
    QCOMPARE(laneIds(creatures), (QStringList{u"ape"_s, u"bear"_s}));
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{bear, ape})));
    QCOMPARE(laneIds(creatures), (QStringList{u"ape"_s, u"bear"_s}));
    QCOMPARE(creatures->data(creatures->index(0, 0), RulesCardModel::NameRole).toString(),
             u"Ape"_s);
}

void RulesTransitionsTest::untapStepRepilesOncePerLane() const
{
    RulesSessionState session;
    TypeCatalog catalog;
    session.setPresentationCatalog(&catalog);
    QJsonArray field;
    for (int index = 0; index < 6; ++index) {
        QJsonObject land = card(u"land-%1"_s.arg(index), u"Plains"_s);
        land.insert(u"tapped"_s, true);
        field.append(land);
    }
    QJsonObject bear = card(u"bear"_s, u"Bear"_s);
    bear.insert(u"power"_s, u"2"_s);
    bear.insert(u"toughness"_s, u"2"_s);
    field.append(bear);
    QVERIFY(session.applySnapshot(snapshot({}, field)));
    QAbstractItemModel *lands = session.laneSlots(0, u"battlefield"_s, u"land"_s);
    QAbstractItemModel *creatures = session.laneSlots(0, u"battlefield"_s, u"creature"_s);
    QCOMPARE(lands->rowCount(), 6);

    LaneSignals landSignals(lands);
    LaneSignals creatureSignals(creatures);
    for (int index = 0; index < 6; ++index) {
        QJsonObject land = field.at(index).toObject();
        land.insert(u"tapped"_s, false);
        field.replace(index, land);
    }
    QVERIFY(session.applySnapshot(snapshot({}, field)));
    QCOMPARE(landSignals.resets.count(), 0);
    QCOMPARE(landSignals.inserted.count(), 0);
    QCOMPARE(landSignals.removed.count(), 0);
    QCOMPARE(landSignals.changed.count(), 6);
    QCOMPARE(creatureSignals.changed.count(), 0);
    QCOMPARE(creatureSignals.resets.count(), 0);

    landSignals.changed.clear();
    QJsonObject tapped = field.at(3).toObject();
    tapped.insert(u"tapped"_s, true);
    field.replace(3, tapped);
    QVERIFY(session.applySnapshot(snapshot({}, field)));
    QCOMPARE(landSignals.resets.count(), 0);
    QCOMPARE(landSignals.moved.count(), 2);
    QCOMPARE(laneIds(lands).constLast(), u"land-3"_s);
    const QModelIndex spent = lands->index(5, 0);
    QCOMPARE(lands->data(spent, RulesCardModel::TappedRole).toBool(), true);
    QCOMPARE(lands->data(spent, RulesLaneSlotModel::SlotIndexRole).toInt(), 1);
    QCOMPARE(lands->data(spent, RulesLaneSlotModel::MemberRankRole).toInt(), 0);
    QCOMPARE(lands->data(lands->index(0, 0), RulesCardModel::TappedRole).toBool(), false);
}

void RulesTransitionsTest::knownCardArrivalTouchesNoRows() const
{
    RulesSessionState session;
    TypeCatalog catalog;
    session.setPresentationCatalog(&catalog);
    QJsonObject bear = card(u"bear"_s, u"Bear"_s);
    bear.insert(u"power"_s, u"2"_s);
    bear.insert(u"toughness"_s, u"2"_s);
    QVERIFY(session.applySnapshot(snapshot(
        {}, QJsonArray{card(u"land"_s, u"Plains"_s), card(u"relic"_s, u"Relic"_s), bear})));
    QAbstractItemModel *lands = session.laneSlots(0, u"battlefield"_s, u"land"_s);
    QAbstractItemModel *others = session.laneSlots(0, u"battlefield"_s, u"other"_s);
    QAbstractItemModel *creatures = session.laneSlots(0, u"battlefield"_s, u"creature"_s);
    QCOMPARE(laneIds(others), QStringList{u"relic"_s});

    LaneSignals landSignals(lands);
    LaneSignals otherSignals(others);
    LaneSignals creatureSignals(creatures);
    emit catalog.cardAvailable(u"Plains"_s, u"Plains"_s, u"Land"_s, u"/art/plains.jpg"_s, {}, {});
    QCOMPARE(
        landSignals.changed.count() + landSignals.resets.count() + landSignals.inserted.count(), 0);
    QCOMPARE(otherSignals.changed.count() + otherSignals.resets.count() +
                 otherSignals.removed.count(),
             0);

    catalog.overrides.insert(u"Relic"_s, u"Land"_s);
    emit catalog.cardAvailable(u"relic"_s, u"Relic"_s, u"Land"_s, {}, {}, {});
    QCOMPARE(laneIds(lands), (QStringList{u"land"_s, u"relic"_s}));
    QVERIFY(laneIds(others).isEmpty());
    QCOMPARE(landSignals.resets.count(), 0);
    QCOMPARE(landSignals.inserted.count(), 1);
    QCOMPARE(creatureSignals.changed.count() + creatureSignals.resets.count(), 0);
}

void RulesTransitionsTest::planeswalkerLaneUsesPublicTypes_data() const
{
    QTest::addColumn<QString>("typeLine");
    QTest::addColumn<QString>("expectedCategory");
    QTest::addColumn<QString>("power");
    QTest::addColumn<bool>("visible");
    QTest::addColumn<bool>("faceDown");
    QTest::addColumn<int>("loyalty");
    QTest::newRow("english-without-loyalty")
        << u"Legendary Planeswalker — Jace"_s << u"planeswalker"_s << QString() << true << false
        << 0;
    QTest::newRow("english-uppercase") << u"LEGENDARY PLANESWALKER — Jace"_s << u"planeswalker"_s
                                       << QString() << true << false << 3;
    QTest::newRow("simplified") << u"传奇鹏洛客～杰斯"_s << u"planeswalker"_s << QString() << true
                                << false << 3;
    QTest::newRow("traditional") << u"傳奇鵬洛客～傑斯"_s << u"planeswalker"_s << QString() << true
                                 << false << 3;
    QTest::newRow("legacy-simplified")
        << u"传奇旅法师 — 杰斯"_s << u"planeswalker"_s << QString() << true << false << 3;
    QTest::newRow("legacy-traditional")
        << u"傳奇旅法師 — 傑斯"_s << u"planeswalker"_s << QString() << true << false << 3;
    QTest::newRow("land-before-planeswalker")
        << u"Land Planeswalker — Test"_s << u"land"_s << QString() << true << false << 3;
    QTest::newRow("public-creature-before-land-and-planeswalker")
        << u"Land Planeswalker — Test"_s << u"creature"_s << u"3"_s << true << false << 3;
    QTest::newRow("unknown-with-loyalty")
        << QString() << u"other"_s << QString() << true << false << 4;
    QTest::newRow("nonwalker-with-loyalty")
        << u"Artifact"_s << u"other"_s << QString() << true << false << 4;
    QTest::newRow("subtype-does-not-classify")
        << u"Artifact — Planeswalker"_s << u"other"_s << QString() << true << false << 0;
    QTest::newRow("back-face-does-not-classify-front")
        << u"Artifact // Legendary Planeswalker — Test"_s << u"other"_s << QString() << true
        << false << 0;
    QTest::newRow("planeswalker-front-face")
        << u"Legendary Planeswalker — Test // Creature — Wizard"_s << u"planeswalker"_s << QString()
        << true << false << 0;
    QTest::newRow("hidden-identity")
        << u"Legendary Planeswalker — Test"_s << u"other"_s << QString() << false << false << 4;
    QTest::newRow("face-down-identity")
        << u"Legendary Planeswalker — Test"_s << u"other"_s << QString() << true << true << 4;
    QTest::newRow("face-down-public-creature")
        << u"Legendary Planeswalker — Test"_s << u"creature"_s << u"2"_s << true << true << 4;
}

void RulesTransitionsTest::planeswalkerLaneUsesPublicTypes() const
{
    QFETCH(QString, typeLine);
    QFETCH(QString, expectedCategory);
    QFETCH(QString, power);
    QFETCH(bool, visible);
    QFETCH(bool, faceDown);
    QFETCH(int, loyalty);
    TypeCatalog catalog;
    catalog.overrides.insert(u"Test permanent"_s, typeLine);
    RulesSessionState session;
    session.setPresentationCatalog(&catalog);
    QJsonObject permanent = card(u"test"_s, u"Test permanent"_s);
    permanent.insert(u"visible"_s, visible);
    permanent.insert(u"faceDown"_s, faceDown);
    if (!power.isEmpty()) {
        permanent.insert(u"power"_s, power);
        permanent.insert(u"toughness"_s, power);
    }
    permanent.insert(u"counters"_s,
                     QJsonArray{QJsonObject{{u"name"_s, u"LOYALTY"_s}, {u"value"_s, loyalty}}});
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{permanent})));
    for (const QString &category : {u"creature"_s, u"land"_s, u"planeswalker"_s, u"other"_s}) {
        QAbstractItemModel *lane = session.laneSlots(0, u"battlefield"_s, category);
        QVERIFY(lane);
        QCOMPARE(session.laneSlots(0, u"battlefield"_s, category), lane);
        QCOMPARE(laneIds(lane),
                 category == expectedCategory ? QStringList{u"test"_s} : QStringList{});
    }
    if (!visible || faceDown || !power.isEmpty())
        QVERIFY(catalog.requestedNames.isEmpty());
}

void RulesTransitionsTest::planeswalkerLaneTracksIdentityAndPrintingChanges() const
{
    TypeCatalog catalog;
    const QString firstPrinting = QStringList{u"Walker"_s, u"set-a"_s, u"1"_s}.join(u'\u001f');
    const QString secondPrinting = QStringList{u"Walker"_s, u"set-b"_s, u"2"_s}.join(u'\u001f');
    const QString thirdPrinting = QStringList{u"Walker"_s, u"set-b"_s, u"3"_s}.join(u'\u001f');
    catalog.printingOverrides.insert(firstPrinting, QString());
    catalog.printingOverrides.insert(secondPrinting, u"Land"_s);
    catalog.printingOverrides.insert(thirdPrinting, u"Legendary Planeswalker — Test"_s);
    RulesSessionState session;
    session.setPresentationCatalog(&catalog);
    QJsonObject permanent = card(u"walker"_s, u"Walker"_s);
    permanent.insert(u"identity"_s, QJsonObject{{u"name"_s, u"Walker"_s},
                                                {u"setCode"_s, u"set-a"_s},
                                                {u"collectorNumber"_s, u"1"_s}});
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{permanent})));
    auto *creatures = session.laneSlots(0, u"battlefield"_s, u"creature"_s);
    auto *lands = session.laneSlots(0, u"battlefield"_s, u"land"_s);
    auto *walkers = session.laneSlots(0, u"battlefield"_s, u"planeswalker"_s);
    auto *others = session.laneSlots(0, u"battlefield"_s, u"other"_s);
    LaneSignals creatureSignals(creatures), landSignals(lands), walkerSignals(walkers),
        otherSignals(others);
    QCOMPARE(laneIds(others), QStringList{u"walker"_s});

    catalog.printingOverrides.insert(firstPrinting, u"Legendary Planeswalker — Test"_s);
    emit catalog.cardAvailable(u"walker"_s, u"Walker"_s, {}, {}, u"set-a"_s, u"1"_s);
    QCOMPARE(laneIds(walkers), QStringList{u"walker"_s});
    QVERIFY(laneIds(others).isEmpty());
    QCOMPARE(walkerSignals.inserted.count(), 1);
    catalog.printingOverrides.insert(firstPrinting, u"传奇鹏洛客～测试"_s);
    emit catalog.languageChanged();
    QCOMPARE(laneIds(walkers), QStringList{u"walker"_s});
    QCOMPARE(walkerSignals.inserted.count(), 1);

    permanent.insert(u"identity"_s, QJsonObject{{u"name"_s, u"Walker"_s},
                                                {u"setCode"_s, u"set-b"_s},
                                                {u"collectorNumber"_s, u"2"_s}});
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{permanent})));
    QCOMPARE(laneIds(lands), QStringList{u"walker"_s});
    QVERIFY(laneIds(walkers).isEmpty());
    QJsonObject identity = permanent.value(u"identity"_s).toObject();
    identity.insert(u"collectorNumber"_s, u"3"_s);
    permanent.insert(u"identity"_s, identity);
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{permanent})));
    QCOMPARE(laneIds(walkers), QStringList{u"walker"_s});
    QVERIFY(laneIds(lands).isEmpty());

    permanent.insert(u"power"_s, u"4"_s);
    permanent.insert(u"toughness"_s, u"4"_s);
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{permanent})));
    QCOMPARE(laneIds(creatures), QStringList{u"walker"_s});
    QVERIFY(laneIds(walkers).isEmpty());
    permanent.remove(u"power"_s);
    permanent.remove(u"toughness"_s);
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{permanent})));
    QCOMPARE(laneIds(walkers), QStringList{u"walker"_s});
    QVERIFY(laneIds(creatures).isEmpty());

    permanent.insert(u"visible"_s, false);
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{permanent})));
    QCOMPARE(laneIds(others), QStringList{u"walker"_s});
    QVERIFY(laneIds(walkers).isEmpty());
    permanent.insert(u"visible"_s, true);
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{permanent})));
    QCOMPARE(laneIds(walkers), QStringList{u"walker"_s});
    catalog.overrides.insert(u"Relic"_s, u"Artifact"_s);
    permanent.insert(u"identity"_s, QJsonObject{{u"name"_s, u"Relic"_s}});
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{permanent})));
    QCOMPARE(laneIds(others), QStringList{u"walker"_s});
    QVERIFY(laneIds(walkers).isEmpty());
    QCOMPARE(creatureSignals.resets.count() + landSignals.resets.count() +
                 walkerSignals.resets.count() + otherSignals.resets.count(),
             0);
}

void RulesTransitionsTest::planeswalkerLaneBatchesTransformationsAndAttachments() const
{
    TypeCatalog catalog;
    catalog.overrides.insert(u"Walker"_s, u"Legendary Planeswalker — Test"_s);
    catalog.overrides.insert(u"Aura"_s, u"Enchantment — Aura"_s);
    RulesSessionState session;
    session.setPresentationCatalog(&catalog);
    QJsonObject host = card(u"host"_s, u"Walker"_s);
    QJsonObject second = card(u"second"_s, u"Walker"_s);
    QJsonObject attached = card(u"attached"_s, u"Walker"_s);
    attached.insert(u"attachedTo"_s, u"host"_s);
    QJsonObject aura = card(u"aura"_s, u"Aura"_s);
    aura.insert(u"attachedTo"_s, u"host"_s);
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{host, second, attached, aura})));
    auto *creatures = session.laneSlots(0, u"battlefield"_s, u"creature"_s);
    auto *lands = session.laneSlots(0, u"battlefield"_s, u"land"_s);
    auto *walkers = session.laneSlots(0, u"battlefield"_s, u"planeswalker"_s);
    auto *others = session.laneSlots(0, u"battlefield"_s, u"other"_s);
    QCOMPARE(walkers->rowCount(), 3);
    QCOMPARE(walkers->property("stacks").toList().size(), 2);
    const int attachedRow = laneIds(walkers).indexOf(u"attached"_s);
    QVERIFY(attachedRow >= 0);
    QCOMPARE(
        walkers->data(walkers->index(attachedRow, 0), RulesLaneSlotModel::SlotIndexRole).toInt(),
        -1);
    const int hostRow = laneIds(walkers).indexOf(u"host"_s);
    QCOMPARE(walkers->data(walkers->index(hostRow, 0), RulesCardModel::AttachmentCountRole).toInt(),
             2);

    QSignalSpy walkerStacks(walkers, SIGNAL(stacksChanged()));
    QSignalSpy creatureStacks(creatures, SIGNAL(stacksChanged()));
    LaneSignals walkerSignals(walkers), creatureSignals(creatures);
    bool completeAtSnapshot = false;
    connect(&session, &RulesSessionState::snapshotChanged, &session, [&] {
        QStringList ids = laneIds(creatures) + laneIds(lands) + laneIds(walkers) + laneIds(others);
        ids.sort();
        completeAtSnapshot = ids == QStringList{u"attached"_s, u"aura"_s, u"host"_s, u"second"_s} &&
                             laneIds(creatures) == QStringList{u"host"_s, u"attached"_s} &&
                             laneIds(walkers) == QStringList{u"second"_s};
    });
    for (QJsonObject *permanent : {&host, &attached}) {
        permanent->insert(u"power"_s, u"4"_s);
        permanent->insert(u"toughness"_s, u"4"_s);
    }
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{second, aura, attached, host})));
    QVERIFY(completeAtSnapshot);
    QCOMPARE(walkerStacks.count(), 1);
    QCOMPARE(creatureStacks.count(), 1);
    QCOMPARE(walkerSignals.resets.count() + creatureSignals.resets.count(), 0);

    attached.remove(u"attachedTo"_s);
    attached.remove(u"power"_s);
    attached.remove(u"toughness"_s);
    host.remove(u"power"_s);
    host.remove(u"toughness"_s);
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{host, second, attached, aura})));
    QCOMPARE(walkers->rowCount(), 3);
    QCOMPARE(walkers->property("stacks").toList().size(), 2);
    QVERIFY(laneIds(creatures).isEmpty());
    QCOMPARE(laneIds(others), QStringList{u"aura"_s});
}

void RulesTransitionsTest::cardPresentationAvoidsScanningEveryRelationship() const
{
    RulesSessionState session;
    QJsonObject host = card(u"host"_s, u"Bear"_s);
    host.insert(u"power"_s, u"2"_s);
    host.insert(u"toughness"_s, u"2"_s);
    QJsonObject aura = card(u"aura"_s, u"Rancor"_s);
    aura.insert(u"attachedTo"_s, u"host"_s);
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{host, aura})));
    QAbstractItemModel *cards = session.battlefieldCards();
    int hostRow = -1;
    for (int row = 0; row < cards->rowCount(); ++row) {
        if (cards->data(cards->index(row, 0), RulesCardModel::IdRole).toString() == u"host"_s)
            hostRow = row;
    }
    QVERIFY(hostRow >= 0);
    QCOMPARE(cards->data(cards->index(hostRow, 0), RulesCardModel::AttachmentCountRole).toInt(), 1);
    QCOMPARE(cards->data(cards->index(hostRow, 0), RulesCardModel::StructuralLinkRole).toBool(),
             true);
    QCOMPARE(
        cards->data(cards->index(hostRow, 0), RulesCardModel::AttachmentCardsRole).toList().size(),
        1);

    const QJsonObject prompt{
        {u"roomId"_s, u"ROOM01"_s},
        {u"gameId"_s, u"game"_s},
        {u"pending"_s, true},
        {u"supported"_s, true},
        {u"promptId"_s, 4},
        {u"kind"_s, u"payManaCost"_s},
        {u"title"_s, u"Pay"_s},
        {u"detail"_s, u""_s},
        {u"options"_s, QJsonArray{QJsonObject{{u"responseId"_s, u"pay-0"_s},
                                              {u"kind"_s, u"activateAbility"_s},
                                              {u"label"_s, u"Tap"_s},
                                              {u"cardId"_s, u"host"_s}}}},
        {u"choices"_s, QJsonArray{}},
        {u"cards"_s, QJsonArray{}},
        {u"scryDestinations"_s, QJsonArray{}},
        {u"targets"_s, QJsonArray{}},
        {u"contextCards"_s, QJsonArray{}},
        {u"contextTargets"_s, QJsonArray{}},
        {u"combatSources"_s, QJsonArray{}},
        {u"combatTargets"_s, QJsonArray{}},
        {u"damageTargets"_s, QJsonArray{}},
        {u"totalDamage"_s, 0}};
    QVERIFY(session.applyPrompt(prompt));
    QCOMPARE(cards->data(cards->index(hostRow, 0), RulesCardModel::HintKeyRole).toString(),
             u"pay"_s);
    QCOMPARE(cards->data(cards->index(hostRow, 0), RulesCardModel::ActionCountRole).toInt(), 1);
    QCOMPARE(
        cards->data(cards->index(hostRow, 0), RulesCardModel::PrimaryResponseIdRole).toString(),
        u"pay-0"_s);
}

void RulesTransitionsTest::sameIdMoveIsOneFlight() const
{
    RulesSessionState session;
    QVERIFY(session.applySnapshot(snapshot(QJsonArray{card(u"bolt"_s, u"Bolt"_s)}, {})));
    QCOMPARE(session.transitions().size(), 0);
    QVERIFY(session.transitionSnap());
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{card(u"bolt"_s, u"Bolt"_s)})));
    QCOMPARE(session.transitions().size(), 1);
    const QVariantMap move = eventFor(session.transitions(), u"bolt"_s);
    QCOMPARE(move.value(u"kind"_s).toString(), u"move"_s);
    QCOMPARE(move.value(u"fromZone"_s).toString(), u"hand"_s);
    QCOMPARE(move.value(u"toZone"_s).toString(), u"battlefield"_s);
    QVERIFY(move.value(u"flight"_s).toBool());
    QCOMPARE(move.value(u"name"_s).toString(), u"Bolt"_s);
    QCOMPARE(session.cardForInspection(u"bolt"_s).value(u"zone"_s).toString(), u"battlefield"_s);
    QVERIFY(session.cardForInspection(u"missing"_s).isEmpty());
}

void RulesTransitionsTest::changedIdIsInferredOnce() const
{
    RulesSessionState session;
    QVERIFY(session.applySnapshot(snapshot(QJsonArray{card(u"old"_s, u"Bolt"_s)}, {})));
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{card(u"new"_s, u"Bolt"_s)})));
    QCOMPARE(session.transitions().size(), 1);
    const QVariantMap move = eventFor(session.transitions(), u"new"_s);
    QCOMPARE(move.value(u"kind"_s).toString(), u"move"_s);
    QCOMPARE(move.value(u"fromZone"_s).toString(), u"hand"_s);
    QCOMPARE(move.value(u"toZone"_s).toString(), u"battlefield"_s);
    QVERIFY(eventFor(session.transitions(), u"old"_s).isEmpty());
}

void RulesTransitionsTest::ambiguousNamesStaySeparate() const
{
    RulesSessionState session;
    QVERIFY(session.applySnapshot(
        snapshot(QJsonArray{card(u"a"_s, u"Bolt"_s), card(u"b"_s, u"Bolt"_s)}, {})));
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{card(u"c"_s, u"Bolt"_s)})));
    QCOMPARE(eventFor(session.transitions(), u"c"_s).value(u"kind"_s).toString(), u"enter"_s);
    QCOMPARE(eventFor(session.transitions(), u"a"_s).value(u"kind"_s).toString(), u"leave"_s);
    QCOMPARE(eventFor(session.transitions(), u"b"_s).value(u"kind"_s).toString(), u"leave"_s);
}

void RulesTransitionsTest::gameChangeAndSeekJumpDoNotAnimate() const
{
    RulesSessionState session;
    QVERIFY(session.applySnapshot(snapshot(QJsonArray{card(u"bolt"_s, u"Bolt"_s)}, {})));
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{card(u"bolt"_s, u"Bolt"_s)}, u"next"_s)));
    QCOMPARE(session.transitions().size(), 0);
    QVERIFY(session.transitionSnap());

    QVERIFY(session.applySnapshot(snapshot(QJsonArray{card(u"bolt"_s, u"Bolt"_s)}, {}, u"next"_s)));
    session.setRecordTransitions(false);
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{card(u"bolt"_s, u"Bolt"_s)}, u"next"_s)));
    QCOMPARE(session.transitions().size(), 0);
    session.setRecordTransitions(true);
    QVERIFY(session.applySnapshot(
        snapshot({}, QJsonArray{card(u"bolt"_s, u"Bolt"_s)}, u"next"_s, 40, 7, 17)));
    QCOMPARE(session.transitions().size(), 1);
    QCOMPARE(eventFor(session.transitions(), u"player:0"_s).value(u"kind"_s).toString(), u"life"_s);
    QCOMPARE(eventFor(session.transitions(), u"player:0"_s).value(u"amount"_s).toInt(), -3);
}

void RulesTransitionsTest::hiddenOpponentDrawHasNoName() const
{
    RulesSessionState session;
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{card(u"land"_s, u"Forest"_s)})));
    QVERIFY(session.applySnapshot(
        snapshot({}, QJsonArray{card(u"land"_s, u"Forest"_s)}, u"game"_s, 39, 8)));
    const QVariantMap draw = eventFor(session.transitions(), u"hidden-draw:1:0"_s);
    QCOMPARE(draw.value(u"kind"_s).toString(), u"move"_s);
    QCOMPARE(draw.value(u"fromZone"_s).toString(), u"library"_s);
    QCOMPARE(draw.value(u"toZone"_s).toString(), u"hand"_s);
    QCOMPARE(draw.value(u"name"_s).toString(), QString());
    QVERIFY(draw.value(u"flight"_s).toBool());
}

void RulesTransitionsTest::reconnectJumpsOnce() const
{
    RulesSessionState session;
    QVERIFY(session.applySnapshot(snapshot(QJsonArray{card(u"bolt"_s, u"Bolt"_s)}, {})));
    session.jumpNextSnapshot();
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{card(u"bolt"_s, u"Bolt"_s)})));
    QVERIFY(session.transitionSnap());
    QCOMPARE(session.transitions().size(), 0);
    QVERIFY(session.applySnapshot(
        snapshot({}, QJsonArray{card(u"bolt"_s, u"Bolt"_s)}, u"game"_s, 40, 7, 17)));
    QVERIFY(!session.transitionSnap());
    QCOMPARE(session.transitions().size(), 1);
}

void RulesTransitionsTest::projectionsNameOnlyWhatTheViewerSees_data() const
{
    QTest::addColumn<bool>("handVisible");
    QTest::addColumn<bool>("redacted");
    QTest::addColumn<QString>("expectedName");
    QTest::newRow("owner") << true << false << u"Secret Plan"_s;
    // Defensive: a hidden row that still carries an identity.
    QTest::newRow("opponent") << false << false << QString();
    QTest::newRow("spectator") << false << true << QString();
}

void RulesTransitionsTest::projectionsNameOnlyWhatTheViewerSees() const
{
    QFETCH(bool, handVisible);
    QFETCH(bool, redacted);
    QFETCH(QString, expectedName);
    // A hand card turned face down onto the battlefield.
    QJsonObject inHand = card(u"secret"_s, u"Secret Plan"_s);
    inHand.insert(u"visible"_s, handVisible);
    QJsonObject faceDown = card(u"secret"_s, u"Secret Plan"_s);
    if (redacted) {
        inHand.remove(u"identity"_s);
        faceDown.remove(u"identity"_s);
    }
    faceDown.insert(u"faceDown"_s, true);
    faceDown.insert(u"power"_s, u"2"_s);
    faceDown.insert(u"toughness"_s, u"2"_s);
    RulesSessionState session;
    QVERIFY(session.applySnapshot(snapshot(QJsonArray{inHand}, {})));
    QVERIFY(session.applySnapshot(snapshot({}, QJsonArray{faceDown})));
    const QVariantMap move = eventFor(session.transitions(), u"secret"_s);
    QCOMPARE(move.value(u"fromZone"_s).toString(), u"hand"_s);
    QCOMPARE(move.value(u"toZone"_s).toString(), u"battlefield"_s);
    QCOMPARE(move.value(u"name"_s).toString(), expectedName);
    for (const QVariant &value : session.transitions()) {
        if (!handVisible)
            QVERIFY(!value.toMap().value(u"name"_s).toString().contains(u"Secret"_s));
    }
}

void RulesTransitionsTest::placementReportsOnlyVisibleCards() const
{
    QJsonObject state = withZone(
        snapshot(QJsonArray{card(u"bolt"_s, u"Bolt"_s)}, QJsonArray{card(u"land"_s, u"Forest"_s)}),
        u"hand"_s, 1, QJsonArray{hiddenCard(u"secret"_s, 1)});
    state.insert(u"stack"_s,
                 QJsonArray{QJsonObject{{u"id"_s, u"shock"_s},
                                        {u"controllerSeat"_s, 0},
                                        {u"ownerSeat"_s, 0},
                                        {u"identity"_s, QJsonObject{{u"name"_s, u"Shock"_s}}},
                                        {u"targets"_s, QJsonArray{}}}});
    RulesSessionState session;
    QVERIFY(session.applySnapshot(state));

    const QVariantMap land = session.cardPlacement(u"land"_s);
    QCOMPARE(land.value(u"zone"_s).toString(), u"battlefield"_s);
    QCOMPARE(land.value(u"zoneOwnerSeat"_s).toInt(), 0);
    QVERIFY(land.value(u"visibleIdentity"_s).toBool());
    const QVariantMap bolt = session.cardPlacement(u"bolt"_s);
    QCOMPARE(bolt.value(u"zone"_s).toString(), u"hand"_s);
    QCOMPARE(bolt.value(u"zoneOwnerSeat"_s).toInt(), 0);
    QVERIFY(bolt.value(u"visibleIdentity"_s).toBool());
    for (const QString &id : {u"land"_s, u"bolt"_s}) {
        const QVariantMap placement = session.cardPlacement(id);
        const QVariantMap inspected = session.cardForInspection(id);
        for (auto it = placement.cbegin(); it != placement.cend(); ++it)
            QCOMPARE(it.value(), inspected.value(it.key()));
    }
    const QVariantMap shock = session.cardPlacement(u"shock"_s);
    QCOMPARE(shock.value(u"zone"_s).toString(), u"stack"_s);
    QVERIFY(shock.value(u"visibleIdentity"_s).toBool());

    QVERIFY(session.cardPlacement(u"secret"_s).isEmpty());
    QVERIFY(session.cardForInspection(u"secret"_s).isEmpty());
    QVERIFY(session.cardPlacement(u"missing"_s).isEmpty());
    QVERIFY(session.cardPlacement({}).isEmpty());
}

void RulesTransitionsTest::seatZoneFollowsMovesWithinZoneCards() const
{
    RulesSessionState session;
    QVERIFY(session.applySnapshot(
        withZone(snapshot(QJsonArray{card(u"bolt"_s, u"Bolt"_s), card(u"shock"_s, u"Shock"_s)}, {}),
                 u"hand"_s, 1, QJsonArray{hiddenCard(u"secret"_s, 1)})));
    QAbstractItemModel *ownHand = session.zoneCardsFor(0, u"hand"_s);
    QVERIFY(ownHand);
    QCOMPARE(session.zoneCardsFor(0, u"hand"_s), ownHand);
    QVERIFY(!session.zoneCardsFor(-1, u"hand"_s));
    QVERIFY(!session.zoneCardsFor(0, {}));
    QCOMPARE(laneIds(ownHand), QStringList({u"bolt"_s, u"shock"_s}));
    QCOMPARE(laneIds(session.zoneCardsFor(1, u"hand"_s)), QStringList({u"secret"_s}));

    // A reordered hand moves rows, so views keep each card's delegate.
    LaneSignals spy(ownHand);
    QVERIFY(session.applySnapshot(
        withZone(snapshot(QJsonArray{card(u"shock"_s, u"Shock"_s), card(u"bolt"_s, u"Bolt"_s)}, {}),
                 u"hand"_s, 1, QJsonArray{hiddenCard(u"secret"_s, 1)})));
    QCOMPARE(laneIds(ownHand), QStringList({u"shock"_s, u"bolt"_s}));
    QVERIFY(spy.moved.count() > 0);
    QCOMPARE(spy.resets.count(), 0);
    QCOMPARE(spy.inserted.count(), 0);
    QCOMPARE(spy.removed.count(), 0);

    // The same id moving between zones keeps its zoneCards row.
    QVERIFY(session.applySnapshot(
        withZone(withZone(snapshot(QJsonArray{card(u"shock"_s, u"Shock"_s)}, {}), u"graveyard"_s, 0,
                          QJsonArray{card(u"bolt"_s, u"Bolt"_s)}),
                 u"hand"_s, 1, QJsonArray{hiddenCard(u"secret"_s, 1)})));
    QCOMPARE(laneIds(ownHand), QStringList({u"shock"_s}));
    QCOMPARE(laneIds(session.zoneCardsFor(0, u"graveyard"_s)), QStringList({u"bolt"_s}));

    session.clear();
    QCOMPARE(ownHand->rowCount(), 0);
}

void RulesTransitionsTest::promptOptionsUpdateInPlace() const
{
    RulesSessionState session;
    QVERIFY(session.applySnapshot(snapshot(QJsonArray{card(u"bolt"_s, u"Bolt"_s)}, {})));
    QVERIFY(session.applyPrompt(
        chooseAction(1, QJsonArray{option(u"action:0"_s, u"Cast Bolt"_s, u"bolt"_s),
                                   option(u"$pass"_s, u"Pass priority"_s)})));
    QAbstractListModel *options = session.promptOptions();
    const auto ids = [options] {
        QStringList result;
        const int role = options->roleNames().key(QByteArrayLiteral("responseId"));
        for (int row = 0; row < options->rowCount(); ++row)
            result.append(options->data(options->index(row), role).toString());
        return result;
    };
    LaneSignals spy(options);

    QVERIFY(session.applyPrompt(
        chooseAction(2, QJsonArray{option(u"action:0"_s, u"Cast Bolt"_s, u"bolt"_s),
                                   option(u"$pass"_s, u"Pass priority"_s)})));
    QCOMPARE(spy.changed.count(), 0);

    QVERIFY(session.applyPrompt(
        chooseAction(3, QJsonArray{option(u"action:0"_s, u"Cast Bolt with kicker"_s, u"bolt"_s),
                                   option(u"$pass"_s, u"Pass priority"_s)})));
    QCOMPARE(spy.changed.count(), 1);
    QCOMPARE(spy.changed.first().at(0).toModelIndex().row(), 0);

    QVERIFY(session.applyPrompt(chooseAction(4, QJsonArray{option(u"$pass"_s, u"Pass"_s)})));
    QCOMPARE(ids(), QStringList({u"$pass"_s}));
    QCOMPARE(spy.removed.count(), 1);

    QVERIFY(session.applyPrompt(
        chooseAction(5, QJsonArray{option(u"$pass"_s, u"Pass"_s),
                                   option(u"action:1"_s, u"Cast Bolt"_s, u"bolt"_s)})));
    QCOMPARE(ids(), QStringList({u"$pass"_s, u"action:1"_s}));
    QCOMPARE(spy.inserted.count(), 1);

    // Response ids are positional, so the same id can name another card. That
    // row is replaced, never relabelled in place.
    const qsizetype changedBefore = spy.changed.count();
    QVERIFY(session.applyPrompt(
        chooseAction(6, QJsonArray{option(u"$pass"_s, u"Pass"_s),
                                   option(u"action:1"_s, u"Cast Shock"_s, u"shock"_s)})));
    QCOMPARE(spy.changed.count(), changedBefore);
    QCOMPARE(spy.removed.count(), 2);
    QCOMPARE(spy.inserted.count(), 2);
    QCOMPARE(spy.resets.count(), 0);
}

void RulesTransitionsTest::mulliganOffersOnlyTypedAbilitiesAndClearsThemAfterRedraw() const
{
    RulesSessionState session;
    QVERIFY(session.applySnapshot(snapshot(
        QJsonArray{card(u"powder"_s, u"Serum Powder"_s), card(u"land"_s, u"Plains"_s)}, {})));
    QJsonObject ability = option(u"opaque-powder"_s, u"Exile hand and redraw"_s, u"powder"_s);
    ability.insert(u"kind"_s, u"activateAbility"_s);
    QJsonObject prompt = chooseAction(
        1, QJsonArray{ability, option(u"not-a-mulligan-cast"_s, u"Cast"_s, u"land"_s)});
    prompt.insert(u"kind"_s, u"mulligan"_s);
    QVERIFY(session.applyPrompt(prompt));
    QCOMPARE(session.cardActionsForCard(u"powder"_s).size(), 1);
    QCOMPARE(session.cardActionsForCard(u"powder"_s).first().toMap().value(u"responseId"_s),
             u"opaque-powder"_s);
    QVERIFY(session.cardActionsForCard(u"land"_s).isEmpty());
    QAbstractItemModel *hand = session.zoneCardsFor(0, u"hand"_s);
    QCOMPARE(hand->data(hand->index(0, 0), RulesCardModel::ActionCountRole).toInt(), 1);
    QCOMPARE(hand->data(hand->index(0, 0), RulesCardModel::HintKeyRole).toString(), u"activate"_s);
    QCOMPARE(hand->data(hand->index(1, 0), RulesCardModel::ActionCountRole).toInt(), 0);
    prompt.insert(u"promptId"_s, 2);
    prompt.insert(u"options"_s, QJsonArray{option(u"$keep"_s, u"Keep"_s)});
    QVERIFY(session.applyPrompt(prompt));
    QVERIFY(session.cardActionsForCard(u"powder"_s).isEmpty());
    QCOMPARE(hand->data(hand->index(0, 0), RulesCardModel::ActionCountRole).toInt(), 0);
}

QTEST_GUILESS_MAIN(RulesTransitionsTest)
#include "rules_transitions_test.moc"
