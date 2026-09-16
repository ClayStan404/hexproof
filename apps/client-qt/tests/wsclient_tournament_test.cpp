// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "wsclient_test.h"

#include <QSet>

void TestWsClient::pairedDraftAndOptionalCardsClearOnPublicReplacement() const
{
    LimitedSessionState state;
    const QJsonArray first{QJsonObject{{u"instanceId"_s, u"a"_s}}};
    const QJsonArray second{QJsonObject{{u"instanceId"_s, u"b"_s}}};
    const QJsonArray packs{
        QJsonObject{{u"packId"_s, u"pack-a"_s}, {u"cards"_s, first}, {u"picksRequired"_s, 1}},
        QJsonObject{{u"packId"_s, u"pack-b"_s}, {u"cards"_s, second}, {u"picksRequired"_s, 1}}};
    const QJsonArray optional{
        QJsonObject{{u"instanceId"_s, u"optional-sol"_s}, {u"name"_s, u"Sol Ring"_s}}};
    state.applySnapshot(QJsonObject{{u"tournamentId"_s, u"PAIRED"_s},
                                    {u"eventType"_s, u"commander_cube"_s},
                                    {u"stage"_s, u"draft"_s},
                                    {u"packsPerPlayer"_s, 6},
                                    {u"packsThisBatch"_s, 2},
                                    {u"packRound"_s, 2},
                                    {u"picksRequired"_s, 2},
                                    {u"currentPacks"_s, packs}});
    QCOMPARE(state.currentPacks(), packs.toVariantList());
    QCOMPARE(state.packsThisBatch(), 2);
    QCOMPARE(state.packsPerPlayer(), 6);
    state.applySnapshot(QJsonObject{{u"tournamentId"_s, u"PAIRED"_s},
                                    {u"eventType"_s, u"commander_cube"_s},
                                    {u"stage"_s, u"deck_building"_s},
                                    {u"optionalCards"_s, optional},
                                    {u"mainboardInstanceIds"_s, QJsonArray{u"optional-sol"_s}}});
    QVERIFY(state.currentPacks().isEmpty());
    QCOMPARE(state.optionalCards(), optional.toVariantList());
    QCOMPARE(state.mainboardInstanceIds(), QVariantList{u"optional-sol"_s});
    state.applySnapshot(QJsonObject{{u"tournamentId"_s, u"PAIRED"_s},
                                    {u"eventType"_s, u"commander_cube"_s},
                                    {u"stage"_s, u"deck_building"_s}});
    QVERIFY(state.optionalCards().isEmpty());
    QVERIFY(state.mainboardInstanceIds().isEmpty());
    hexproof::client::TournamentSessionState tournament;
    const QJsonObject settings{
        {u"packsPerPlayer"_s, 6}, {u"packsPerBatch"_s, 2}, {u"cardsPerPack"_s, 25}};
    tournament.applySnapshot(
        QJsonObject{{u"tournamentId"_s, u"PAIRED"_s}, {u"draftSettings"_s, settings}});
    QCOMPARE(tournament.draftSettings(), settings.toVariantMap());
    tournament.enter(u"ORDINARY"_s, u"participant"_s, u"p-1"_s);
    QVERIFY(tournament.draftSettings().isEmpty());
}

void TestWsClient::commanderDraftMetadataAndPrivateSelectionResetTogether() const
{
    LimitedSessionState state;
    QVERIFY(!state.commanderDraft());
    QCOMPARE(state.minimumDeckCards(), 40);
    QCOMPARE(state.packsPerPlayer(), 3);
    QCOMPARE(state.picksRequired(), 0);
    QSignalSpy headers(&state, &LimitedSessionState::headerChanged);
    QSignalSpy packs(&state, &LimitedSessionState::packChanged);
    QSignalSpy decks(&state, &LimitedSessionState::deckChanged);
    QSignalSpy changes(&state, &LimitedSessionState::snapshotChanged);
    QVariantMap observedAtHeader;
    connect(&state, &LimitedSessionState::headerChanged, &state, [&] {
        observedAtHeader = {{u"commanderDraft"_s, state.commanderDraft()},
                            {u"minimumDeckCards"_s, state.minimumDeckCards()},
                            {u"packsPerPlayer"_s, state.packsPerPlayer()},
                            {u"picksRequired"_s, state.picksRequired()},
                            {u"commanders"_s, state.commanderInstanceIds()},
                            {u"fallbacks"_s, state.fallbackCommanders()},
                            {u"colors"_s, state.commanderColors()}};
    });
    QJsonObject snapshot{
        {u"tournamentId"_s, u"COMMANDER"_s},
        {u"eventType"_s, u"commander_cube"_s},
        {u"stage"_s, u"draft"_s},
        {u"minimumDeckCards"_s, 60},
        {u"packsPerPlayer"_s, 4},
        {u"picksRequired"_s, 2},
        {u"currentPack"_s, QJsonArray{QJsonObject{{u"instanceId"_s, u"card-c"_s}},
                                      QJsonObject{{u"instanceId"_s, u"card-d"_s}}}},
        {u"pool"_s, QJsonArray{QJsonObject{{u"instanceId"_s, u"card-a"_s}},
                               QJsonObject{{u"instanceId"_s, u"card-b"_s}}}},
    };
    state.applySnapshot(snapshot);
    QVERIFY(state.commanderDraft());
    QCOMPARE(state.minimumDeckCards(), 60);
    QCOMPARE(state.packsPerPlayer(), 4);
    QCOMPARE(state.picksRequired(), 2);
    QCOMPARE(headers.count(), 1);
    QCOMPARE(packs.count(), 1);
    QCOMPARE(observedAtHeader.value(u"minimumDeckCards"_s).toInt(), 60);
    QCOMPARE(observedAtHeader.value(u"packsPerPlayer"_s).toInt(), 4);
    QCOMPARE(observedAtHeader.value(u"picksRequired"_s).toInt(), 2);

    // A final odd pack allows one card, without changing unrelated header/deck state.
    snapshot.insert(u"currentPack"_s, QJsonArray{QJsonObject{{u"instanceId"_s, u"card-c"_s}}});
    snapshot.insert(u"picksRequired"_s, 1);
    state.applySnapshot(snapshot);
    QCOMPARE(state.picksRequired(), 1);
    QCOMPARE(headers.count(), 1);
    QCOMPARE(packs.count(), 2);
    QCOMPARE(decks.count(), 0);

    snapshot.insert(u"stage"_s, u"deck_building"_s);
    snapshot.insert(u"currentPack"_s, QJsonArray{});
    snapshot.insert(u"picksRequired"_s, 0);
    snapshot.insert(u"mainboardInstanceIds"_s, QJsonArray{u"card-b"_s, u"card-a"_s});
    snapshot.insert(u"commanderInstanceIds"_s, QJsonArray{u"card-b"_s, u"card-a"_s});
    const QJsonArray fallbacks{QJsonObject{{u"instanceId"_s, u"piper-fallback-1"_s},
                                           {u"name"_s, u"The Prismatic Piper"_s}}};
    const QJsonArray colors{QJsonObject{{u"instanceId"_s, u"card-b"_s}, {u"color"_s, u"U"_s}}};
    snapshot.insert(u"fallbackCommanders"_s, fallbacks);
    snapshot.insert(u"commanderColors"_s, colors);
    snapshot.insert(u"basicLands"_s,
                    QJsonArray{QJsonObject{{u"name"_s, u"Island"_s}, {u"count"_s, 58}}});
    snapshot.insert(u"deckSubmitted"_s, true);
    state.applySnapshot(snapshot);
    const QVariantList commanders{u"card-b"_s, u"card-a"_s};
    QCOMPARE(state.commanderInstanceIds(), commanders);
    QCOMPARE(state.mainboardInstanceIds(), commanders);
    QCOMPARE(observedAtHeader.value(u"commanders"_s).toList(), commanders);
    QCOMPARE(state.fallbackCommanders(), fallbacks.toVariantList());
    QCOMPARE(state.commanderColors(), colors.toVariantList());
    QCOMPARE(observedAtHeader.value(u"fallbacks"_s).toList(), fallbacks.toVariantList());
    QCOMPARE(observedAtHeader.value(u"colors"_s).toList(), colors.toVariantList());
    QCOMPARE(observedAtHeader.value(u"picksRequired"_s).toInt(), 0);
    QVERIFY(state.deckSubmitted());
    QCOMPARE(decks.count(), 1);
    const int notifications = changes.count();
    state.applySnapshot(snapshot);
    QCOMPARE(changes.count(), notifications);

    snapshot.insert(u"commanderInstanceIds"_s, QJsonArray{u"card-a"_s});
    state.applySnapshot(snapshot);
    QCOMPARE(state.commanderInstanceIds(), QVariantList{u"card-a"_s});
    QCOMPARE(decks.count(), 2);
    QCOMPARE(headers.count(), 2);

    // A public replacement contains no private selection, not an instruction to retain it.
    state.applySnapshot(QJsonObject{{u"tournamentId"_s, u"COMMANDER"_s},
                                    {u"eventType"_s, u"commander_cube"_s},
                                    {u"stage"_s, u"competition"_s},
                                    {u"minimumDeckCards"_s, 60},
                                    {u"packsPerPlayer"_s, 3}});
    QVERIFY(state.commanderDraft());
    QVERIFY(state.commanderInstanceIds().isEmpty());
    QVERIFY(state.fallbackCommanders().isEmpty());
    QVERIFY(state.commanderColors().isEmpty());
    QVERIFY(state.mainboardInstanceIds().isEmpty());
    QVERIFY(state.basicLands().isEmpty());
    QVERIFY(state.pool().isEmpty());
    QVERIFY(state.currentPack().isEmpty());
    QVERIFY(!state.deckSubmitted());
    QCOMPARE(state.picksRequired(), 0);

    state.clear();
    QVERIFY(!state.active());
    QVERIFY(!state.commanderDraft());
    QCOMPARE(state.minimumDeckCards(), 40);
    QCOMPARE(state.packsPerPlayer(), 3);
    QCOMPARE(state.picksRequired(), 0);
    const int clearedNotifications = changes.count();
    state.clear();
    QCOMPARE(changes.count(), clearedNotifications);
    state.applySnapshot(
        QJsonObject{{u"tournamentId"_s, u"ORDINARY"_s},
                    {u"eventType"_s, u"cube_draft"_s},
                    {u"currentPack"_s, QJsonArray{QJsonObject{{u"instanceId"_s, u"ordinary"_s}}}}});
    QVERIFY(!state.commanderDraft());
    QCOMPARE(state.minimumDeckCards(), 40);
    QCOMPARE(state.picksRequired(), 1);
}

void TestWsClient::commanderProgressCannotReplacePrivateState() const
{
    LimitedSessionState state;
    const QJsonObject snapshot{
        {u"tournamentId"_s, u"COMMANDER"_s},
        {u"eventType"_s, u"commander_cube"_s},
        {u"minimumDeckCards"_s, 60},
        {u"packsPerPlayer"_s, 3},
        {u"picksRequired"_s, 2},
        {u"currentPack"_s, QJsonArray{QJsonObject{{u"instanceId"_s, u"private-pack"_s}}}},
        {u"pool"_s, QJsonArray{QJsonObject{{u"instanceId"_s, u"private-pool"_s}}}},
        {u"mainboardInstanceIds"_s, QJsonArray{u"private-pool"_s}},
        {u"commanderInstanceIds"_s, QJsonArray{u"private-pool"_s}},
        {u"basicLands"_s, QJsonArray{QJsonObject{{u"name"_s, u"Island"_s}, {u"count"_s, 59}}}},
        {u"deckSubmitted"_s, true}};
    state.applySnapshot(snapshot);
    QSignalSpy headers(&state, &LimitedSessionState::headerChanged);
    QSignalSpy packs(&state, &LimitedSessionState::packChanged);
    QSignalSpy pools(&state, &LimitedSessionState::poolChanged);
    QSignalSpy decks(&state, &LimitedSessionState::deckChanged);
    QSignalSpy participants(&state, &LimitedSessionState::participantsChanged);
    QJsonObject progress{{u"tournamentId"_s, u"COMMANDER"_s},
                         {u"participants"_s, QJsonArray{QJsonObject{{u"participantId"_s, u"p-2"_s},
                                                                    {u"picked"_s, 6}}}},
                         {u"eventType"_s, u"cube_draft"_s},
                         {u"minimumDeckCards"_s, 40},
                         {u"packsPerPlayer"_s, 4},
                         {u"picksRequired"_s, 1},
                         {u"commanderInstanceIds"_s, QJsonArray{u"other-player"_s}},
                         {u"mainboardInstanceIds"_s, QJsonArray{}},
                         {u"basicLands"_s, QJsonArray{}},
                         {u"currentPack"_s, QJsonArray{}},
                         {u"pool"_s, QJsonArray{}},
                         {u"deckSubmitted"_s, false}};
    state.applyProgress(progress);
    QCOMPARE(participants.count(), 1);
    QCOMPARE(headers.count(), 0);
    QCOMPARE(packs.count(), 0);
    QCOMPARE(pools.count(), 0);
    QCOMPARE(decks.count(), 0);
    QVERIFY(state.commanderDraft());
    QCOMPARE(state.minimumDeckCards(), 60);
    QCOMPARE(state.packsPerPlayer(), 3);
    QCOMPARE(state.picksRequired(), 2);
    QCOMPARE(state.commanderInstanceIds(), QVariantList{u"private-pool"_s});
    QCOMPARE(state.mainboardInstanceIds(), QVariantList{u"private-pool"_s});
    QCOMPARE(state.basicLands(), snapshot.value(u"basicLands"_s).toArray().toVariantList());
    QCOMPARE(state.pool(), snapshot.value(u"pool"_s).toArray().toVariantList());
    QCOMPARE(state.currentPack(), snapshot.value(u"currentPack"_s).toArray().toVariantList());
    QVERIFY(state.deckSubmitted());
    progress.insert(u"tournamentId"_s, u"OTHER"_s);
    state.applyProgress(progress);
    QCOMPARE(participants.count(), 1);
    state.clear();
    progress.insert(u"tournamentId"_s, u"COMMANDER"_s);
    state.applyProgress(progress);
    QVERIFY(!state.active());
    QVERIFY(state.commanderInstanceIds().isEmpty());
}

void TestWsClient::sendsCommanderCubeCommandsWithinSizeBounds() const
{
    QWebSocketServer server(u"Commander Cube commands"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));
    WsClient client;
    client.connectTo(u"ws://127.0.0.1:"_s + QString::number(server.serverPort()), u"Alice"_s);
    QTRY_VERIFY_WITH_TIMEOUT(server.hasPendingConnections(), 1000);
    auto *peer = takeServerPeer(server);
    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.payload = {{u"v"_s, hexproof::protocol::kProtocolVersion},
                       {u"connectionId"_s, u"conn-commander"_s},
                       {u"serverVersion"_s, buildVersion()}};
    sendEnvelope(peer, welcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 1000);
    QSignalSpy outbound(peer, &QWebSocket::textMessageReceived);
    QList<QPair<QString, QJsonObject>> expected;
    const auto expect = [&](const QString &type, const QJsonObject &payload) {
        expected.append({type, payload});
    };

    // Out-of-range selections/invites must not produce any network command.
    client.pickLimitedCards({});
    client.pickLimitedCards({u"card-a"_s, u"card-b"_s, u"card-c"_s, u"card-d"_s, u"card-e"_s});
    client.inviteCommanderCubePlayers({});
    client.inviteCommanderCubePlayers({u"p-1"_s});
    client.inviteCommanderCubePlayers({u"p-1"_s, u"p-2"_s, u"p-3"_s, u"p-4"_s, u"p-5"_s});
    client.respondCommanderCubeInvitation({}, true);
    client.respondCommanderCubeInvitation({}, false);
    client.setLimitedDraftControl({}, true);

    client.setLimitedDraftControl(u"p-2"_s, true);
    expect(hexproof::protocol::kTypeLimitedSetDraftControl,
           {{u"participantId"_s, u"p-2"_s}, {u"automatic"_s, true}});
    client.setLimitedDraftControl(u"p-1"_s, false);
    expect(hexproof::protocol::kTypeLimitedSetDraftControl,
           {{u"participantId"_s, u"p-1"_s}, {u"automatic"_s, false}});
    client.setLimitedParticipation(false);
    expect(hexproof::protocol::kTypeLimitedSetParticipation, {{u"participating"_s, false}});
    client.setLimitedParticipation(true);
    expect(hexproof::protocol::kTypeLimitedSetParticipation, {{u"participating"_s, true}});

    client.pickLimitedCards({u"last-card"_s});
    expect(hexproof::protocol::kTypeLimitedPick, {{u"instanceIds"_s, QJsonArray{u"last-card"_s}}});
    client.pickLimitedCards({u"card-b"_s, u"card-a"_s});
    expect(hexproof::protocol::kTypeLimitedPick,
           {{u"instanceIds"_s, QJsonArray{u"card-b"_s, u"card-a"_s}}});
    client.pickLimitedCards({u"card-a"_s, u"card-b"_s, u"card-c"_s, u"card-d"_s});
    expect(hexproof::protocol::kTypeLimitedPick,
           {{u"instanceIds"_s, QJsonArray{u"card-a"_s, u"card-b"_s, u"card-c"_s, u"card-d"_s}}});
    const QVariantMap draftSettings{
        {u"packsPerPlayer"_s, 6}, {u"packsPerBatch"_s, 2}, {u"cardsPerPack"_s, 25}};
    const QVariantMap product{{u"id"_s, u"cube"_s}};
    client.createCasualLimitedEvent(u"Paired Cube"_s, u"commander_cube"_s, u"bo1"_s, 4, product,
                                    draftSettings);
    expect(hexproof::protocol::kTypeTournamentCreate,
           {{u"name"_s, u"Paired Cube"_s},
            {u"format"_s, u"Limited"_s},
            {u"eventType"_s, u"commander_cube"_s},
            {u"coordinator"_s, u"casual"_s},
            {u"matchMode"_s, u"bo1"_s},
            {u"roundMinutes"_s, 50},
            {u"maxPlayers"_s, 4},
            {u"product"_s, QJsonObject::fromVariantMap(product)},
            {u"draftSettings"_s, QJsonObject::fromVariantMap(draftSettings)}});

    for (int count = 2; count <= 4; ++count) {
        QVariantList players;
        for (int index = 1; index <= count; ++index)
            players.append(u"p-"_s + QString::number(index));
        client.inviteCommanderCubePlayers(players);
        expect(
            hexproof::protocol::kTypeLimitedCreateCasualMatch,
            {{u"action"_s, u"invite"_s}, {u"playerIds"_s, QJsonArray::fromVariantList(players)}});
    }
    client.respondCommanderCubeInvitation(u"pair-commander"_s, true);
    expect(hexproof::protocol::kTypeLimitedCreateCasualMatch,
           {{u"pairingId"_s, u"pair-commander"_s}, {u"action"_s, u"accept"_s}});
    client.respondCommanderCubeInvitation(u"pair-commander"_s, false);
    expect(hexproof::protocol::kTypeLimitedCreateCasualMatch,
           {{u"pairingId"_s, u"pair-commander"_s}, {u"action"_s, u"cancel"_s}});

    const QVariantList mainboard{u"card-b"_s, u"card-a"_s, u"card-c"_s};
    const QVariantList commanders{u"card-b"_s, u"card-a"_s};
    const QVariantList basics{QVariantMap{{u"name"_s, u"Forest"_s}, {u"count"_s, 29}},
                              QVariantMap{{u"name"_s, u"Island"_s}, {u"count"_s, 28}}};
    QJsonObject deck{{u"name"_s, u"Two leaders"_s},
                     {u"mainboardInstanceIds"_s, QJsonArray::fromVariantList(mainboard)},
                     {u"basicLands"_s, QJsonArray::fromVariantList(basics)},
                     {u"commanderInstanceIds"_s, QJsonArray::fromVariantList(commanders)},
                     {u"commanderColors"_s, QJsonArray{}}};
    client.submitLimitedCommanderDeck(u"Two leaders"_s, mainboard, basics, commanders);
    expect(hexproof::protocol::kTypeLimitedSubmitDeck, deck);
    const QVariantList colors{QVariantMap{{u"instanceId"_s, u"card-b"_s}, {u"color"_s, u"U"_s}},
                              QVariantMap{{u"instanceId"_s, u"card-a"_s}, {u"color"_s, u"G"_s}}};
    client.submitLimitedCommanderDeck(u"Two leaders"_s, mainboard, basics, commanders, colors);
    deck.insert(u"commanderColors"_s, QJsonArray::fromVariantList(colors));
    expect(hexproof::protocol::kTypeLimitedSubmitDeck, deck);
    // Explicitly clearing a choice must not reuse an earlier submitted commander list.
    client.submitLimitedCommanderDeck(u"Two leaders"_s, mainboard, basics, {});
    deck.insert(u"commanderInstanceIds"_s, QJsonArray{});
    deck.insert(u"commanderColors"_s, QJsonArray{});
    expect(hexproof::protocol::kTypeLimitedSubmitDeck, deck);
    client.submitLimitedDeck(u"Two leaders"_s, mainboard, basics);
    deck.remove(u"commanderInstanceIds"_s);
    deck.remove(u"commanderColors"_s);
    expect(hexproof::protocol::kTypeLimitedSubmitDeck, deck);

    // The final valid message is an ordered barrier behind all rejected calls above.
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), expected.size(), 1000);
    QSet<QString> requestIds;
    for (int index = 0; index < expected.size(); ++index) {
        bool ok = false;
        const auto command =
            hexproof::protocol::parse(outbound.at(index).first().toString().toUtf8(), &ok);
        QVERIFY(ok);
        QCOMPARE(command.type, expected.at(index).first);
        QCOMPARE(command.payload, expected.at(index).second);
        QVERIFY(!command.id.isEmpty());
        QVERIFY(!requestIds.contains(command.id));
        requestIds.insert(command.id);
    }
}

void TestWsClient::rejectsCommanderCubeCommandsWhileDisconnected() const
{
    WsClient client;
    QSignalSpy queued(&client, &WsClient::commandQueued);
    QSignalSpy failed(&client, &WsClient::commandFailed);
    client.pickLimitedCards({u"card-a"_s, u"card-b"_s});
    client.inviteCommanderCubePlayers({u"p-1"_s, u"p-2"_s});
    client.respondCommanderCubeInvitation(u"pair-commander"_s, true);
    client.submitLimitedCommanderDeck(u"Local draft"_s, {u"card-a"_s}, {}, {u"card-a"_s});
    QCOMPARE(queued.count(), 0);
    QCOMPARE(failed.count(), 4);
    QVERIFY(!client.lastError().isEmpty());
    QVERIFY(!client.limitedSession()->active());
}

void TestWsClient::distinguishesCubeRoomsAndClearsOldLobbyState() const
{
    hexproof::client::TournamentSessionState state;
    state.enter(u"CUBE01"_s, u"organizer"_s);
    QVERIFY(!state.cubeRoom());
    state.applySnapshot(QJsonObject{{u"tournamentId"_s, u"CUBE01"_s},
                                    {u"name"_s, u"Cube night"_s},
                                    {u"eventType"_s, u"cube_draft"_s},
                                    {u"coordinator"_s, u"casual"_s},
                                    {u"stage"_s, u"registration"_s}});
    QVERIFY(state.cubeRoom());
    // Reentering this same pod keeps its screen until the reconnect snapshot.
    state.enter(u"CUBE01"_s, u"organizer"_s);
    QVERIFY(state.cubeRoom());
    QCOMPARE(state.stage(), u"registration"_s);
    // Switching sessions must not briefly render the previous pod's controls.
    state.enter(u"SWISS1"_s, u"viewer"_s);
    QVERIFY(!state.cubeRoom());
    QVERIFY(state.stage().isEmpty());
    QVERIFY(state.name().isEmpty());
    QVERIFY(state.participants().isEmpty());
    state.applySnapshot(QJsonObject{{u"tournamentId"_s, u"SWISS1"_s},
                                    {u"eventType"_s, u"cube_draft"_s},
                                    {u"coordinator"_s, u"swiss"_s},
                                    {u"stage"_s, u"registration"_s}});
    QVERIFY(!state.cubeRoom());
}

void TestWsClient::cubeAutoEntryIsReplacedWithItsOwnerSnapshot() const
{
    using hexproof::client::TournamentSessionState;
    TournamentSessionState state;
    QJsonObject pairing{{u"pairingId"_s, u"casual-1"_s},
                        {u"playerAId"_s, u"player-a"_s},
                        {u"playerBId"_s, u"player-b"_s},
                        {u"status"_s, u"open"_s},
                        {u"autoEnter"_s, true}};
    QJsonObject snapshot{{u"tournamentId"_s, u"CUBE01"_s},    {u"eventType"_s, u"commander_cube"_s},
                         {u"coordinator"_s, u"casual"_s},     {u"stage"_s, u"competition"_s},
                         {u"role"_s, u"participant"_s},       {u"participantId"_s, u"player-a"_s},
                         {u"pairings"_s, QJsonArray{pairing}}};
    QSignalSpy changes(&state, &TournamentSessionState::snapshotChanged);
    state.applySnapshot(snapshot);
    QCOMPARE(changes.count(), 1);
    QCOMPARE(state.pairings().size(), 1);
    QVERIFY(state.pairings().first().toMap().value(u"autoEnter"_s).toBool());

    // Entry consumes the one-shot flag; a replacement must not retain it.
    pairing.remove(u"autoEnter"_s);
    pairing.insert(u"roomId"_s, u"TABLE1"_s);
    snapshot.insert(u"pairings"_s, QJsonArray{pairing});
    state.applySnapshot(snapshot);
    QVERIFY(!state.pairings().first().toMap().contains(u"autoEnter"_s));

    pairing.insert(u"autoEnter"_s, true);
    snapshot.insert(u"pairings"_s, QJsonArray{pairing});
    state.applySnapshot(snapshot);
    snapshot.insert(u"role"_s, u"viewer"_s);
    snapshot.remove(u"participantId"_s);
    pairing.remove(u"autoEnter"_s);
    snapshot.insert(u"pairings"_s, QJsonArray{pairing});
    state.applySnapshot(snapshot);
    QVERIFY(state.participantId().isEmpty());
    QVERIFY(!state.pairings().first().toMap().contains(u"autoEnter"_s));
    state.clear();
    QVERIFY(state.pairings().isEmpty());
}

void TestWsClient::sendsCubeJoinCredentialsAndInvitationCancellation() const
{
    QWebSocketServer server(u"Cube commands"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));
    WsClient client;
    client.connectTo(u"ws://127.0.0.1:"_s + QString::number(server.serverPort()), u"Alice"_s);
    QTRY_VERIFY_WITH_TIMEOUT(server.hasPendingConnections(), 1000);
    auto *peer = takeServerPeer(server);
    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.payload = {{u"v"_s, hexproof::protocol::kProtocolVersion},
                       {u"connectionId"_s, u"conn-cube"_s},
                       {u"serverVersion"_s, buildVersion()}};
    sendEnvelope(peer, welcome);
    QTRY_VERIFY(client.connected());
    Envelope created;
    created.type = hexproof::protocol::kTypeTournamentCreated;
    created.payload = {{u"tournamentId"_s, u"CUBE01"_s},
                       {u"organizerToken"_s, u"private-cube-token"_s}};
    sendEnvelope(peer, created);
    QTRY_COMPARE(client.tournamentSession()->tournamentId(), u"CUBE01"_s);
    QVERIFY(client.hasCubeRoomCredential(u"cube01"_s));
    QVERIFY(!client.hasCubeRoomCredential(u"OTHER1"_s));
    QSignalSpy outbound(peer, &QWebSocket::textMessageReceived);
    client.joinRoom(u"cube01"_s, false, {});
    QTRY_COMPARE(outbound.count(), 1);
    bool ok = false;
    auto request = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(request.type, hexproof::protocol::kTypeRoomJoin);
    QCOMPARE(request.payload.value(u"credential"_s).toString(), u"private-cube-token"_s);
    client.joinRoom(u"CUBE01"_s, true, {});
    QTRY_COMPARE(outbound.count(), 1);
    request = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QVERIFY(!request.payload.contains(u"credential"_s));
    client.joinRoom(u"OTHER1"_s, false, {});
    QTRY_COMPARE(outbound.count(), 1);
    request = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QVERIFY(!request.payload.contains(u"credential"_s));
    client.cancelLimitedCasualMatch(u"p-1"_s, u"p-2"_s);
    QTRY_COMPARE(outbound.count(), 1);
    request = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(request.type, hexproof::protocol::kTypeLimitedCreateCasualMatch);
    QCOMPARE(request.payload.value(u"action"_s).toString(), u"cancel"_s);
    QCOMPARE(request.payload.value(u"playerAId"_s).toString(), u"p-1"_s);
    QCOMPARE(request.payload.value(u"playerBId"_s).toString(), u"p-2"_s);

    QJsonObject cubeSnapshot{{u"tournamentId"_s, u"CUBE01"_s},
                             {u"eventType"_s, u"cube_draft"_s},
                             {u"coordinator"_s, u"casual"_s},
                             {u"role"_s, u"participant"_s},
                             {u"participantId"_s, u"p-1"_s},
                             {u"stage"_s, u"competition"_s},
                             {u"pairings"_s, QJsonArray{QJsonObject{{u"roomId"_s, u"TABLE1"_s}}}}};
    client.tournamentSession()->applySnapshot(cubeSnapshot);
    client.roomSession()->enter(u"TABLE1"_s, u"player"_s, 0, false);
    client.returnToRoom();
    QTRY_COMPARE(outbound.count(), 1);
    request = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(request.type, hexproof::protocol::kTypeRoomLeave);

    QJsonObject publicView = cubeSnapshot;
    publicView.insert(u"role"_s, u"viewer"_s);
    publicView.remove(u"participantId"_s);
    client.tournamentSession()->applySnapshot(publicView);
    Envelope table = roomSnapshot(u"Cube table"_s);
    table.payload.insert(u"roomId"_s, u"TABLE1"_s);
    sendEnvelope(peer, table);
    QTRY_COMPARE(outbound.count(), 1);
    request = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(request.type, hexproof::protocol::kTypeTournamentEnter);
    QVERIFY(!request.payload.contains(u"credential"_s));
    QVERIFY(client.hasCubeRoomCredential(u"CUBE01"_s));
    client.tournamentSession()->applySnapshot(cubeSnapshot);

    Envelope left;
    left.type = hexproof::protocol::kTypeTournamentLeft;
    left.payload = {{u"tournamentId"_s, u"CUBE01"_s}};
    sendEnvelope(peer, left);
    QTRY_VERIFY(!client.tournamentSession()->inTournament());
    QVERIFY(client.hasCubeRoomCredential(u"CUBE01"_s));

    // Before drafting, a guest's departure actually vacates its seat.
    sendEnvelope(peer, created);
    QTRY_VERIFY(client.tournamentSession()->inTournament());
    cubeSnapshot.insert(u"stage"_s, u"registration"_s);
    client.tournamentSession()->applySnapshot(cubeSnapshot);
    sendEnvelope(peer, left);
    QTRY_VERIFY(!client.tournamentSession()->inTournament());
    QVERIFY(!client.hasCubeRoomCredential(u"CUBE01"_s));
}

void TestWsClient::limitedProgressPreservesPrivateModels() const
{
    bool ok = false;
    Envelope snapshot = sharedFixture(u"limited-snapshot.json"_s, &ok);
    QVERIFY(ok);
    LimitedSessionState state;
    state.applySnapshot(snapshot.payload);
    const auto pool = state.pool();
    const auto pack = state.currentPack();
    QSignalSpy poolChanged(&state, &LimitedSessionState::poolChanged);
    QSignalSpy packChanged(&state, &LimitedSessionState::packChanged);
    QSignalSpy changed(&state, &LimitedSessionState::snapshotChanged);
    state.applySnapshot(snapshot.payload);
    QCOMPARE(changed.count(), 0);
    Envelope progress = sharedFixture(u"limited-progress.json"_s, &ok);
    QVERIFY(ok);
    state.applyProgress(progress.payload);
    QCOMPARE(changed.count(), 1);
    QCOMPARE(state.participants().first().toMap().value(u"picked"_s).toInt(), 2);
    QCOMPARE(state.pool(), pool);
    QCOMPARE(state.currentPack(), pack);
    QCOMPARE(poolChanged.count(), 0);
    QCOMPARE(packChanged.count(), 0);
    progress.payload.insert(u"tournamentId"_s, u"WRONG"_s);
    state.applyProgress(progress.payload);
    QCOMPARE(changed.count(), 1);
    state.clear();
    QVERIFY(state.pool().isEmpty());
    QCOMPARE(poolChanged.count(), 1);
    QCOMPARE(packChanged.count(), 1);
    progress.payload.insert(u"tournamentId"_s, u"ABC123"_s);
    state.applyProgress(progress.payload);
    QVERIFY(!state.active());
}

void TestWsClient::ignoresStaleTournamentAndLimitedSnapshots() const
{
    QWebSocketServer server(u"Scoped snapshots"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));
    WsClient client;
    client.connectTo(u"ws://127.0.0.1:"_s + QString::number(server.serverPort()), u"Alice"_s);
    QTRY_VERIFY_WITH_TIMEOUT(server.hasPendingConnections(), 1000);
    auto *peer = takeServerPeer(server);
    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.payload = {{u"v"_s, hexproof::protocol::kProtocolVersion},
                       {u"connectionId"_s, u"conn-scoped"_s},
                       {u"serverVersion"_s, buildVersion()}};
    sendEnvelope(peer, welcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 1000);
    Envelope entered;
    entered.type = hexproof::protocol::kTypeTournamentEntered;
    entered.payload = {{u"tournamentId"_s, u"OLD"_s},
                       {u"role"_s, u"participant"_s},
                       {u"participantId"_s, u"p-1"_s}};
    sendEnvelope(peer, entered);
    QTRY_COMPARE(client.tournamentSession()->tournamentId(), u"OLD"_s);
    bool ok = false;
    Envelope limited = sharedFixture(u"limited-snapshot.json"_s, &ok);
    QVERIFY(ok);
    limited.payload.insert(u"tournamentId"_s, u"OLD"_s);
    limited.payload.insert(u"eventType"_s, u"commander_cube"_s);
    limited.payload.insert(u"minimumDeckCards"_s, 60);
    limited.payload.insert(u"picksRequired"_s, 2);
    limited.payload.insert(u"commanderInstanceIds"_s, QJsonArray{u"limited-2"_s});
    sendEnvelope(peer, limited);
    QTRY_VERIFY(client.limitedSession()->active());
    QVERIFY(client.limitedSession()->commanderDraft());
    QCOMPARE(client.limitedSession()->commanderInstanceIds(), QVariantList{u"limited-2"_s});
    entered.payload.insert(u"tournamentId"_s, u"NEW"_s);
    sendEnvelope(peer, entered);
    QTRY_COMPARE(client.tournamentSession()->tournamentId(), u"NEW"_s);
    QVERIFY(!client.limitedSession()->active());
    QVERIFY(!client.limitedSession()->commanderDraft());
    QVERIFY(client.limitedSession()->commanderInstanceIds().isEmpty());
    QCOMPARE(client.limitedSession()->minimumDeckCards(), 40);
    QCOMPARE(client.limitedSession()->picksRequired(), 0);
    QSignalSpy changed(client.tournamentSession(),
                       &hexproof::client::TournamentSessionState::snapshotChanged);
    QSignalSpy privateChanged(client.limitedSession(), &LimitedSessionState::snapshotChanged);
    Envelope stale;
    stale.type = hexproof::protocol::kTypeTournamentSnapshot;
    stale.payload = {{u"tournamentId"_s, u"OLD"_s}, {u"role"_s, u"viewer"_s}};
    sendEnvelope(peer, stale);
    sendEnvelope(peer, limited);
    // A current snapshot acts as an ordered barrier after the stale frames.
    stale.payload = {{u"tournamentId"_s, u"NEW"_s},
                     {u"participantId"_s, u"p-1"_s},
                     {u"role"_s, u"participant"_s},
                     {u"name"_s, u"Current event"_s}};
    sendEnvelope(peer, stale);
    QTRY_COMPARE(changed.count(), 1);
    QCOMPARE(privateChanged.count(), 0);
    QVERIFY(client.limitedSession()->commanderInstanceIds().isEmpty());
    QCOMPARE(client.tournamentSession()->participantId(), u"p-1"_s);
    QCOMPARE(client.tournamentSession()->tournamentId(), u"NEW"_s);
    limited.payload.insert(u"tournamentId"_s, u"NEW"_s);
    sendEnvelope(peer, limited);
    QTRY_VERIFY(client.limitedSession()->active());
    QCOMPARE(client.limitedSession()->pool().size(), 1);
    QCOMPARE(client.limitedSession()->commanderInstanceIds(), QVariantList{u"limited-2"_s});
}

void TestWsClient::scopesAndBoundsTournamentChat() const
{
    hexproof::client::TournamentSessionState state;
    state.enter(u"A"_s, u"organizer"_s);
    QSignalSpy changed(&state, &hexproof::client::TournamentSessionState::chatChanged);
    const auto message = [](int sequence) {
        return QJsonObject{{u"tournamentId"_s, u"A"_s},
                           {u"sequence"_s, sequence},
                           {u"displayName"_s, u"Judge"_s},
                           {u"text"_s, u"Hello"_s},
                           {u"sentAt"_s, u"2026-09-08T10:00:00Z"_s}};
    };
    state.applyChatMessage(message(105));
    state.applyChatMessage(message(105));
    QCOMPARE(changed.count(), 1);
    QJsonArray history;
    for (int index = 1; index <= 104; ++index)
        history.append(message(index));
    state.applyChatHistory(QJsonObject{{u"tournamentId"_s, u"A"_s}, {u"messages"_s, history}});
    QCOMPARE(changed.count(), 2);
    QCOMPARE(state.chatMessages().size(), 100);
    QCOMPARE(state.chatMessages().first().toMap().value(u"sequence"_s).toInt(), 6);
    QCOMPARE(state.chatMessages().last().toMap().value(u"sequence"_s).toInt(), 105);
    state.enter(u"B"_s, u"viewer"_s);
    QVERIFY(state.chatMessages().isEmpty());
    state.applyChatMessage(message(106));
    state.applyChatHistory(QJsonObject{{u"tournamentId"_s, u"A"_s}, {u"messages"_s, history}});
    QVERIFY(state.chatMessages().isEmpty());
    state.enter(u"A"_s, u"organizer"_s);
    state.applyChatMessage(message(107));
    state.clear();
    QVERIFY(state.chatMessages().isEmpty());
}
