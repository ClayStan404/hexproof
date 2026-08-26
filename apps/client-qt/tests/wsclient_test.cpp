// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "wsclient_test.h"

void TestWsClient::destroysParserWorkersDeterministically() const
{
    for (int iteration = 0; iteration < 25; ++iteration) {
        WsClient client;
        QCOMPARE(client.connectionState(), WsClient::Disconnected);
    }
}

void TestWsClient::limitedSessionRestoresPrivateDeckSelection() const
{
    LimitedSessionState state;
    state.applySnapshot(QJsonObject{
        {u"tournamentId"_s, u"ABC123"_s},
        {u"eventType"_s, u"set_sealed"_s},
        {u"stage"_s, u"deck_building"_s},
        {u"product"_s, QJsonObject{{u"id"_s, u"fdn-play"_s}}},
        {u"packRound"_s, 0},
        {u"direction"_s, 1},
        {u"currentPack"_s, QJsonArray{}},
        {u"pool"_s, QJsonArray{}},
        {u"mainboardInstanceIds"_s, QJsonArray{u"limited-1"_s, u"limited-2"_s}},
        {u"basicLands"_s, QJsonArray{QJsonObject{{u"name"_s, u"Island"_s}, {u"count"_s, 17}}}},
        {u"participants"_s, QJsonArray{}},
        {u"deckSubmitted"_s, true},
        {u"allDecksSubmitted"_s, false},
    });

    QCOMPARE(state.mainboardInstanceIds(), QVariantList({u"limited-1"_s, u"limited-2"_s}));
    QCOMPARE(state.basicLands().size(), 1);
    QCOMPARE(state.basicLands().first().toMap().value(u"count"_s).toInt(), 17);
    state.clear();
    QVERIFY(state.mainboardInstanceIds().isEmpty());
    QVERIFY(state.basicLands().isEmpty());
}

void TestWsClient::correlatesCommandOutcomes() const
{
    QWebSocketServer server(u"Hexproof command correlation server"_s,
                            QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));

    QWebSocket *peer = nullptr;
    connect(&server, &QWebSocketServer::newConnection, &server,
            [&]() { peer = takeServerPeer(server); });

    WsClient client;
    client.connectTo(u"ws://127.0.0.1:"_s + QString::number(server.serverPort()), u"Alice"_s);
    QTRY_VERIFY_WITH_TIMEOUT(peer != nullptr, 1000);
    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.id = u"1"_s;
    welcome.payload = QJsonObject{
        {u"v"_s, hexproof::protocol::kProtocolVersion},
        {u"connectionId"_s, u"conn-correlation"_s},
        {u"serverVersion"_s, buildVersion()},
    };
    sendEnvelope(peer, welcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 1000);

    QSignalSpy outbound(peer, &QWebSocket::textMessageReceived);
    QSignalSpy queued(&client, &WsClient::commandQueued);
    QSignalSpy succeeded(&client, &WsClient::commandSucceeded);
    QSignalSpy failed(&client, &WsClient::commandFailed);

    client.setCardTapped(u"card-a"_s, true);
    QTRY_COMPARE_WITH_TIMEOUT(queued.count(), 1, 1000);
    QCOMPARE(queued.at(0).at(1).toString(), hexproof::protocol::kTypeGameSetTapped);
    QCOMPARE(queued.at(0).at(2).toMap().value(u"cardId"_s).toString(), u"card-a"_s);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    bool ok = false;
    const Envelope tappedRequest =
        hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);

    Envelope tapped;
    tapped.type = hexproof::protocol::kTypeGameTappedSet;
    tapped.id = tappedRequest.id;
    sendEnvelope(peer, tapped);
    QTRY_COMPARE_WITH_TIMEOUT(succeeded.count(), 1, 1000);
    QCOMPARE(succeeded.at(0).at(0).toString(), tappedRequest.id);
    QCOMPARE(succeeded.at(0).at(1).toString(), hexproof::protocol::kTypeGameSetTapped);

    client.setCounter(u"life"_s, 19);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    const Envelope counterRequest =
        hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    Envelope rejected;
    rejected.type = hexproof::protocol::kTypeError;
    rejected.id = counterRequest.id;
    rejected.payload = QJsonObject{
        {u"code"_s, u"invalid_counter"_s},
        {u"message"_s, u"invalid counter"_s},
    };
    sendEnvelope(peer, rejected);
    QTRY_COMPARE_WITH_TIMEOUT(failed.count(), 1, 1000);
    QCOMPARE(failed.at(0).at(0).toString(), counterRequest.id);
    QCOMPARE(failed.at(0).at(1).toString(), hexproof::protocol::kTypeGameSetCounter);
    QCOMPARE(failed.at(0).at(2).toMap().value(u"counter"_s).toString(), u"life"_s);

    rejected.id = u"unrelated"_s;
    sendEnvelope(peer, rejected);
    QTest::qWait(50);
    QCOMPARE(failed.count(), 1);
}

void TestWsClient::rollsBackPendingCommandsBeforeRoomIdentityClears() const
{
    QWebSocketServer server(u"Hexproof room teardown server"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));

    QWebSocket *peer = nullptr;
    connect(&server, &QWebSocketServer::newConnection, &server,
            [&]() { peer = takeServerPeer(server); });

    WsClient client;
    client.connectTo(u"ws://127.0.0.1:"_s + QString::number(server.serverPort()), u"Alice"_s);
    QTRY_VERIFY_WITH_TIMEOUT(peer != nullptr, 1000);

    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.id = u"1"_s;
    welcome.payload = QJsonObject{
        {u"v"_s, hexproof::protocol::kProtocolVersion},
        {u"connectionId"_s, u"conn-room-teardown"_s},
        {u"serverVersion"_s, buildVersion()},
    };
    sendEnvelope(peer, welcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 1000);

    Envelope created;
    created.type = hexproof::protocol::kTypeRoomCreated;
    created.id = u"2"_s;
    created.payload = QJsonObject{{u"roomId"_s, u"ABCDEF"_s}};
    sendEnvelope(peer, created);
    sendEnvelope(peer, roomSnapshot(u"Room before teardown"_s));
    QTRY_VERIFY_WITH_TIMEOUT(client.inRoom(), 1000);
    QCOMPARE(client.seatIndex(), 0);

    QSignalSpy outbound(peer, &QWebSocket::textMessageReceived);
    int seatAtFailure = -2;
    connect(&client, &WsClient::commandFailed, &client,
            [&](const QString &, const QString &commandType, const QVariantMap &, const QString &) {
                if (commandType == hexproof::protocol::kTypeGameSetCounter)
                    seatAtFailure = client.seatIndex();
            });

    client.setCounter(hexproof::protocol::kPlayerCounterLife, 19);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);

    Envelope left;
    left.type = hexproof::protocol::kTypeRoomLeft;
    left.payload = QJsonObject{{u"roomId"_s, u"ABCDEF"_s}};
    sendEnvelope(peer, left);

    QTRY_COMPARE_WITH_TIMEOUT(seatAtFailure, 0, 1000);
    QCOMPARE(client.seatIndex(), -1);
    QVERIFY(!client.inRoom());
}

void TestWsClient::handlesP7DiscoveryReplayAndTableCommands() const
{
    QWebSocketServer server(u"Hexproof test server"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));

    QWebSocket *peer = nullptr;
    connect(&server, &QWebSocketServer::newConnection, &server,
            [&]() { peer = takeServerPeer(server); });

    WsClient client;
    client.connectTo(u"ws://127.0.0.1:"_s + QString::number(server.serverPort()), u"Alice"_s);
    QTRY_VERIFY_WITH_TIMEOUT(peer != nullptr, 1000);
    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.id = u"1"_s;
    welcome.payload = QJsonObject{
        {u"v"_s, hexproof::protocol::kProtocolVersion},
        {u"connectionId"_s, u"conn-p7"_s},
        {u"serverVersion"_s, buildVersion()},
    };
    sendEnvelope(peer, welcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 1000);

    QSignalSpy outbound(peer, &QWebSocket::textMessageReceived);
    auto nextOutbound = [&]() {
        if (outbound.isEmpty())
            outbound.wait(1000);
        if (outbound.isEmpty())
            return Envelope{};
        bool ok = false;
        const Envelope envelope =
            hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
        return ok ? envelope : Envelope{};
    };

    client.requestRoomList();
    QCOMPARE(nextOutbound().type, hexproof::protocol::kTypeRoomList);
    QSignalSpy roomListSpy(&client, &WsClient::roomListChanged);
    Envelope rooms;
    rooms.type = hexproof::protocol::kTypeRoomListed;
    rooms.payload = QJsonObject{{u"rooms"_s, QJsonArray{QJsonObject{
                                                 {u"roomId"_s, u"ABCDEF"_s},
                                                 {u"name"_s, u"Friday Modern"_s},
                                                 {u"format"_s, u"modern"_s},
                                                 {u"playerCount"_s, 1},
                                                 {u"maxSeats"_s, 2},
                                                 {u"playerJoinable"_s, true},
                                             }}}};
    sendEnvelope(peer, rooms);
    QTRY_COMPARE_WITH_TIMEOUT(roomListSpy.count(), 1, 1000);
    QCOMPARE(client.roomList().size(), 1);
    QCOMPARE(client.roomList().first().toMap().value(u"roomId"_s).toString(), u"ABCDEF"_s);

    client.requestReplayList();
    Envelope listRequest = nextOutbound();
    QCOMPARE(listRequest.type, hexproof::protocol::kTypeReplayList);
    QCOMPARE(listRequest.payload.value(u"offset"_s).toInt(), 0);
    QCOMPARE(listRequest.payload.value(u"limit"_s).toInt(), 50);
    QSignalSpy replayListSpy(&client, &WsClient::replayListChanged);
    Envelope replayList;
    replayList.type = hexproof::protocol::kTypeReplayListed;
    replayList.payload = QJsonObject{{u"replays"_s, QJsonArray{QJsonObject{
                                                        {u"replayId"_s, u"ABCDEF-1.json"_s},
                                                        {u"roomName"_s, u"Archived Table"_s},
                                                        {u"logEntryCount"_s, 2},
                                                    }}},
                                     {u"offset"_s, 50},
                                     {u"limit"_s, 50},
                                     {u"total"_s, 101},
                                     {u"hasMore"_s, true}};
    sendEnvelope(peer, replayList);
    QTRY_COMPARE_WITH_TIMEOUT(replayListSpy.count(), 1, 1000);
    QCOMPARE(client.replayList().size(), 1);
    QCOMPARE(client.replayOffset(), 50);
    QCOMPARE(client.replayLimit(), 50);
    QCOMPARE(client.replayTotal(), 101);
    QVERIFY(client.replayHasMore());

    client.requestReplayPage(100);
    listRequest = nextOutbound();
    QCOMPARE(listRequest.payload.value(u"offset"_s).toInt(), 100);
    QCOMPARE(listRequest.payload.value(u"limit"_s).toInt(), 50);

    client.loadReplay(u"ABCDEF-1.json"_s);
    Envelope request = nextOutbound();
    QCOMPARE(request.type, hexproof::protocol::kTypeReplayGet);
    QCOMPARE(request.payload.value(u"replayId"_s).toString(), u"ABCDEF-1.json"_s);
    QSignalSpy replayLoadedSpy(&client, &WsClient::replayLoaded);
    Envelope replay;
    replay.type = hexproof::protocol::kTypeReplayLoaded;
    replay.payload = QJsonObject{
        {u"replay"_s,
         QJsonObject{
             {u"replayId"_s, u"ABCDEF-1.json"_s},
             {u"roomName"_s, u"Archived Table"_s},
         }},
        {u"log"_s, QJsonArray{QJsonObject{
                       {u"id"_s, 1},
                       {u"kind"_s, u"draw"_s},
                       {u"seat"_s, 0},
                       {u"text"_s, u"Alice drew a card."_s},
                   }}},
    };
    sendEnvelope(peer, replay);
    QTRY_COMPARE_WITH_TIMEOUT(replayLoadedSpy.count(), 1, 1000);
    QCOMPARE(client.loadedReplay().value(u"log"_s).toList().size(), 1);

    Envelope game;
    game.type = hexproof::protocol::kTypeGameSnapshot;
    game.payload = QJsonObject{
        {u"seats"_s, QJsonArray{}},
        {u"stack"_s, QJsonArray{}},
        {u"revealed"_s, QJsonArray{}},
        {u"arrows"_s, QJsonArray{QJsonObject{
                          {u"seat"_s, 0},
                          {u"sourceCardId"_s, u"s0-c1"_s},
                          {u"kind"_s, u"target"_s},
                          {u"targetCardId"_s, u"s1-c1"_s},
                      }}},
        {u"attachments"_s, QJsonArray{QJsonObject{
                               {u"ownerSeat"_s, 0},
                               {u"sourceCardId"_s, u"s0-c2"_s},
                               {u"targetCardId"_s, u"s1-c1"_s},
                           }}},
        {u"log"_s, QJsonArray{}},
        {u"score"_s, QJsonArray{}},
    };
    sendEnvelope(peer, game);
    QTRY_COMPARE_WITH_TIMEOUT(client.gameArrows().size(), 1, 1000);
    QCOMPARE(client.gameAttachments().size(), 1);

    client.shuffleLibrary();
    QCOMPARE(nextOutbound().type, hexproof::protocol::kTypeGameShuffleLibrary);
    client.setCardCounter(
        u"s0-c1"_s,
        QVariantMap{{u"kind"_s, u"ability"_s}, {u"label"_s, u"Flying"_s}, {u"value"_s, 1}});
    request = nextOutbound();
    QCOMPARE(request.type, hexproof::protocol::kTypeGameSetCardCounter);
    QCOMPARE(request.payload.value(u"cardId"_s).toString(), u"s0-c1"_s);
    QCOMPARE(request.payload.value(u"label"_s).toString(), u"Flying"_s);
    client.arrangeBattlefield(QVariantList{QVariantMap{
        {u"cardId"_s, u"s0-c1"_s},
        {u"position"_s, QVariantMap{{u"x"_s, 0.1}, {u"y"_s, 0.9}}},
    }});
    request = nextOutbound();
    QCOMPARE(request.type, hexproof::protocol::kTypeGameArrangeBattlefield);
    const QJsonArray placements = request.payload.value(u"cards"_s).toArray();
    QCOMPARE(placements.size(), 1);
    QCOMPARE(placements.first().toObject().value(u"cardId"_s).toString(), u"s0-c1"_s);
    QCOMPARE(placements.first().toObject().value(u"position"_s).toObject().value(u"y"_s).toDouble(),
             0.9);
    client.setCombatArrows(QVariantList{u"s0-c1"_s}, u"attack"_s, {}, 1, QVariantList{u"s0-c1"_s});
    request = nextOutbound();
    QCOMPARE(request.type, hexproof::protocol::kTypeGameSetArrow);
    QCOMPARE(request.payload.value(u"sourceCardIds"_s).toArray().size(), 1);
    QCOMPARE(request.payload.value(u"kind"_s).toString(), u"attack"_s);
    QCOMPARE(request.payload.value(u"targetSeat"_s).toInt(), 1);
    QCOMPARE(request.payload.value(u"tappedSourceCardIds"_s).toArray().size(), 1);
    client.clearArrow();
    request = nextOutbound();
    QCOMPARE(request.type, hexproof::protocol::kTypeGameSetArrow);
    QVERIFY(request.payload.isEmpty());
    client.setAttachment(u"s0-c2"_s, u"s1-c1"_s);
    request = nextOutbound();
    QCOMPARE(request.type, hexproof::protocol::kTypeGameSetAttachment);
    QCOMPARE(request.payload.value(u"targetCardId"_s).toString(), u"s1-c1"_s);
    client.setAttachment(u"s0-c2"_s);
    request = nextOutbound();
    QCOMPARE(request.type, hexproof::protocol::kTypeGameSetAttachment);
    QVERIFY(!request.payload.contains(u"targetCardId"_s));
    client.castCommander(u"s0-commander"_s);
    request = nextOutbound();
    QCOMPARE(request.type, hexproof::protocol::kTypeGameCastCommander);
    QCOMPARE(request.payload.value(u"commanderId"_s).toString(), u"s0-commander"_s);
}

void TestWsClient::handlesTournamentCommandsAndSnapshots() const
{
    QWebSocketServer server(u"Hexproof tournament client server"_s,
                            QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));

    QWebSocket *peer = nullptr;
    connect(&server, &QWebSocketServer::newConnection, &server,
            [&]() { peer = takeServerPeer(server); });

    WsClient client;
    client.connectTo(u"ws://127.0.0.1:"_s + QString::number(server.serverPort()), u"Alice"_s);
    QTRY_VERIFY_WITH_TIMEOUT(peer != nullptr, 1000);
    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.payload = QJsonObject{
        {u"v"_s, hexproof::protocol::kProtocolVersion},
        {u"connectionId"_s, u"conn-tournament"_s},
        {u"serverVersion"_s, buildVersion()},
    };
    sendEnvelope(peer, welcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 1000);

    QSignalSpy outbound(peer, &QWebSocket::textMessageReceived);
    auto nextOutbound = [&]() {
        if (outbound.isEmpty())
            outbound.wait(1000);
        if (outbound.isEmpty())
            return Envelope{};
        bool ok = false;
        const Envelope envelope =
            hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
        return ok ? envelope : Envelope{};
    };

    client.createCasualLimitedEvent(u"Cube night"_s, hexproof::protocol::kLimitedEventCubeDraft,
                                    u"bo1"_s, 8,
                                    QVariantMap{{u"id"_s, u"cube-1"_s},
                                                {u"name"_s, u"Test Cube"_s},
                                                {u"productType"_s, u"cube"_s},
                                                {u"authentic"_s, false},
                                                {u"cardsPerPack"_s, 0},
                                                {u"sheets"_s, QVariantList{}},
                                                {u"variants"_s, QVariantList{}}});
    const Envelope createCasual = nextOutbound();
    QCOMPARE(createCasual.type, hexproof::protocol::kTypeTournamentCreate);
    QCOMPARE(createCasual.payload.value(u"eventType"_s).toString(),
             hexproof::protocol::kLimitedEventCubeDraft);
    QCOMPARE(createCasual.payload.value(u"format"_s).toString(), u"Cube"_s);
    QCOMPARE(createCasual.payload.value(u"coordinator"_s).toString(),
             hexproof::protocol::kLimitedCoordinatorCasual);
    QVERIFY(!createCasual.payload.contains(u"cardsPerPlayer"_s));

    client.requestTournamentList();
    QCOMPARE(nextOutbound().type, hexproof::protocol::kTypeTournamentList);
    Envelope listed;
    listed.type = hexproof::protocol::kTypeTournamentListed;
    listed.payload = QJsonObject{{u"tournaments"_s, QJsonArray{QJsonObject{
                                                        {u"tournamentId"_s, u"ABCDEFGH"_s},
                                                        {u"name"_s, u"Saturday Swiss"_s},
                                                        {u"format"_s, u"Pioneer"_s},
                                                        {u"coordinator"_s, u"swiss"_s},
                                                        {u"matchMode"_s, u"bo3"_s},
                                                        {u"status"_s, u"registration"_s},
                                                        {u"registered"_s, 4},
                                                    }}}};
    sendEnvelope(peer, listed);
    QTRY_COMPARE_WITH_TIMEOUT(client.tournamentSession()->tournamentList().size(), 1, 1000);

    client.enterTournament(u"abcdefgh"_s);
    const Envelope enterRequest = nextOutbound();
    QCOMPARE(enterRequest.type, hexproof::protocol::kTypeTournamentEnter);
    QCOMPARE(enterRequest.payload.value(u"tournamentId"_s).toString(), u"ABCDEFGH"_s);

    Envelope entered;
    entered.type = hexproof::protocol::kTypeTournamentEntered;
    entered.payload = QJsonObject{
        {u"tournamentId"_s, u"ABCDEFGH"_s},
        {u"role"_s, u"participant"_s},
        {u"participantId"_s, u"p-1"_s},
    };
    sendEnvelope(peer, entered);

    Envelope snapshot;
    snapshot.type = hexproof::protocol::kTypeTournamentSnapshot;
    snapshot.payload = QJsonObject{
        {u"tournamentId"_s, u"ABCDEFGH"_s},
        {u"name"_s, u"Saturday Swiss"_s},
        {u"format"_s, u"Pioneer"_s},
        {u"coordinator"_s, u"casual"_s},
        {u"matchMode"_s, u"bo3"_s},
        {u"status"_s, u"running"_s},
        {u"role"_s, u"participant"_s},
        {u"participantId"_s, u"p-1"_s},
        {u"organizerName"_s, u"Judge"_s},
        {u"roundMinutes"_s, 50},
        {u"roundStartedAt"_s, u"2026-08-08T12:00:00Z"_s},
        {u"maxPlayers"_s, 32},
        {u"plannedRounds"_s, 3},
        {u"currentRound"_s, 1},
        {u"registered"_s, 4},
        {u"checkedIn"_s, 4},
        {u"roundComplete"_s, false},
        {u"canRegister"_s, false},
        {u"participants"_s, QJsonArray{}},
        {u"pairings"_s, QJsonArray{}},
        {u"standings"_s, QJsonArray{}},
    };
    sendEnvelope(peer, snapshot);
    QTRY_COMPARE_WITH_TIMEOUT(client.tournamentSession()->name(), u"Saturday Swiss"_s, 1000);
    QCOMPARE(client.tournamentSession()->currentRound(), 1);
    QCOMPARE(client.tournamentSession()->roundStartedAt(), u"2026-08-08T12:00:00Z"_s);
    QCOMPARE(client.tournamentSession()->participantId(), u"p-1"_s);
    QCOMPARE(client.tournamentSession()->coordinator(), u"casual"_s);

    client.createLimitedCasualMatch(u"p-1"_s, u"p-2"_s);
    const Envelope casualMatch = nextOutbound();
    QCOMPARE(casualMatch.type, hexproof::protocol::kTypeLimitedCreateCasualMatch);
    QCOMPARE(casualMatch.payload.value(u"playerAId"_s).toString(), u"p-1"_s);
    QCOMPARE(casualMatch.payload.value(u"playerBId"_s).toString(), u"p-2"_s);

    client.reportTournamentResult(u"pair-1"_s, 2, 1, 0);
    const Envelope report = nextOutbound();
    QCOMPARE(report.type, hexproof::protocol::kTypeTournamentReportResult);
    QCOMPARE(report.payload.value(u"playerAWins"_s).toInt(), 2);
    QCOMPARE(report.payload.value(u"playerBWins"_s).toInt(), 1);

    snapshot.payload.insert(u"status"_s, u"registration"_s);
    snapshot.payload.insert(u"role"_s, u"viewer"_s);
    snapshot.payload.insert(u"canRegister"_s, true);
    snapshot.payload.remove(u"participantId"_s);
    sendEnvelope(peer, snapshot);
    QTRY_VERIFY_WITH_TIMEOUT(client.tournamentSession()->participantId().isEmpty(), 1000);
    QCOMPARE(client.tournamentSession()->role(), u"viewer"_s);
    QVERIFY(client.tournamentSession()->canRegister());
}

void TestWsClient::initTestCase()
{
    QVERIFY(m_settingsDir.isValid());
    QCoreApplication::setOrganizationName(u"HexproofTests"_s);
    QCoreApplication::setApplicationName(u"WsClientTest"_s);
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_settingsDir.path());
}

void TestWsClient::cleanup()
{
    qunsetenv("HEXPROOF_SERVER_DIRECTORY_FILE");
    QSettings settings;
    settings.clear();
    settings.sync();
}

void TestWsClient::loadsSavedResumeEndpoint() const
{
    QSettings settings;
    settings.setValue(u"network/resumeToken"_s, u"saved-token"_s);
    settings.setValue(u"network/resumeServerUrl"_s, u"ws://127.0.0.1:57320/ws"_s);
    settings.setValue(u"network/resumeDisplayName"_s, u"Saved player"_s);
    settings.setValue(u"network/resumeLastSeq"_s, 42);
    settings.sync();

    WsClient client;
    QCOMPARE(client.serverUrl(), u"ws://127.0.0.1:57320/ws"_s);
    QCOMPARE(client.serverIndex(), 3);
    QCOMPARE(client.customServerUrl(), u"ws://127.0.0.1:57320/ws"_s);
    QCOMPARE(client.displayName(), u"Saved player"_s);
}

void TestWsClient::loadsSecondaryPublicHubSelection() const
{
    const ServerDirectory directory;
    const QString secondaryUrl = directory.serverUrl(1);
    QSettings settings;
    settings.setValue(u"network/resumeToken"_s, u"saved-token"_s);
    settings.setValue(u"network/resumeServerUrl"_s, secondaryUrl);
    settings.sync();

    WsClient client;
    QCOMPARE(client.serverUrl(), secondaryUrl);
    QCOMPARE(client.serverIndex(), 1);
}

void TestWsClient::configuresAndPersistsCustomServer() const
{
    WsClient client;
    client.connectToCustomServer(u"https://invalid.example/ws"_s, u"Alice"_s);
    QVERIFY(client.lastError().startsWith(u"invalid_server_url:"_s));
    QCOMPARE(client.connectionState(), WsClient::Disconnected);

    client.connectToCustomServer(u" ws://127.0.0.1:9 "_s, u"Alice"_s);
    QCOMPARE(client.customServerUrl(), u"ws://127.0.0.1:9/ws"_s);
    QCOMPARE(client.serverUrl(), client.customServerUrl());
    QCOMPARE(client.serverIndex(), 3);

    QSettings settings;
    QCOMPARE(settings.value(u"network/customServerUrl"_s).toString(), client.customServerUrl());
    client.disconnectFromHub();
}

void TestWsClient::migratesLegacyPrimaryPublicHubEndpoint() const
{
    const QString directoryPath = m_settingsDir.filePath(u"legacy-servers.json"_s);
    QFile directoryFile(directoryPath);
    QVERIFY(directoryFile.open(QIODevice::WriteOnly));
    const QByteArray directoryPayload = R"({
  "schemaVersion": 1,
  "servers": [
    {
      "url": "wss://primary.example/ws",
      "legacyUrls": ["ws://retired-primary.example:57320/ws"]
    },
    {"url": "wss://secondary.example/ws"},
    {"url": "wss://tertiary.example/ws"}
  ]
})";
    QCOMPARE(directoryFile.write(directoryPayload), directoryPayload.size());
    directoryFile.close();
    qputenv("HEXPROOF_SERVER_DIRECTORY_FILE", directoryPath.toUtf8());

    QSettings settings;
    settings.setValue(u"network/resumeToken"_s, u"saved-token"_s);
    settings.setValue(u"network/resumeServerUrl"_s, u"ws://retired-primary.example:57320/ws"_s);
    settings.sync();

    WsClient client;
    QCOMPARE(client.serverUrl(), u"wss://primary.example/ws"_s);
    QCOMPARE(client.serverIndex(), 0);
}

void TestWsClient::exposesInitialServerLatencyState() const
{
    WsClient client;
    const QVariantList latencies = client.serverLatencies();
    QCOMPARE(latencies.size(), 4);
    QCOMPARE(latencies[0].toInt(), -2);
    QCOMPARE(latencies[1].toInt(), -2);
    QCOMPARE(latencies[2].toInt(), -2);
    QCOMPARE(latencies[3].toInt(), -2);
}

void TestWsClient::processesFinalMessageBeforeDisconnect() const
{
    QWebSocketServer server(u"Hexproof ordering test server"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));

    QWebSocket *peer = nullptr;
    connect(&server, &QWebSocketServer::newConnection, &server,
            [&]() { peer = takeServerPeer(server); });

    WsClient client;
    client.connectTo(u"ws://127.0.0.1:"_s + QString::number(server.serverPort()), u"Alice"_s);
    QTRY_VERIFY_WITH_TIMEOUT(peer != nullptr, 1000);

    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.id = u"1"_s;
    welcome.payload = QJsonObject{
        {u"v"_s, hexproof::protocol::kProtocolVersion},
        {u"connectionId"_s, u"conn-ordering"_s},
        {u"serverVersion"_s, buildVersion()},
    };
    sendEnvelope(peer, welcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 1000);

    QStringList events;
    connect(&client, &WsClient::roomListChanged, &client, [&]() { events.append(u"message"_s); });
    connect(&client, &WsClient::connectionStateChanged, &client, [&]() {
        if (client.connectionState() == WsClient::Disconnected)
            events.append(u"disconnect"_s);
    });

    Envelope rooms;
    rooms.type = hexproof::protocol::kTypeRoomListed;
    rooms.payload = QJsonObject{{u"rooms"_s, QJsonArray{QJsonObject{
                                                 {u"roomId"_s, u"ABCDEF"_s},
                                                 {u"name"_s, u"Last visible room"_s},
                                                 {u"format"_s, u"modern"_s},
                                                 {u"playerCount"_s, 1},
                                                 {u"maxSeats"_s, 2},
                                                 {u"playerJoinable"_s, true},
                                             }}}};
    sendEnvelope(peer, rooms);
    peer->close();

    QTRY_COMPARE_WITH_TIMEOUT(events.size(), 2, 1000);
    QCOMPARE(events, QStringList({u"message"_s, u"disconnect"_s}));
    QCOMPARE(client.roomList().first().toMap().value(u"name"_s).toString(), u"Last visible room"_s);
}

void TestWsClient::distinguishesHostKickReplyFromKickedPush() const
{
    QWebSocketServer server(u"Hexproof test server"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));

    QWebSocket *peer = nullptr;
    connect(&server, &QWebSocketServer::newConnection, &server,
            [&]() { peer = takeServerPeer(server); });

    WsClient client;
    client.connectTo(u"ws://127.0.0.1:"_s + QString::number(server.serverPort()), u"Alice"_s);
    QTRY_VERIFY_WITH_TIMEOUT(peer != nullptr, 1000);

    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.id = u"1"_s;
    welcome.payload = QJsonObject{
        {u"v"_s, hexproof::protocol::kProtocolVersion},
        {u"connectionId"_s, u"conn-1"_s},
        {u"serverVersion"_s, buildVersion()},
    };
    sendEnvelope(peer, welcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 1000);

    Envelope created;
    created.type = hexproof::protocol::kTypeRoomCreated;
    created.id = u"2"_s;
    created.payload = QJsonObject{{u"roomId"_s, u"ABCDEF"_s}};
    sendEnvelope(peer, created);
    sendEnvelope(peer, roomSnapshot(u"Room before kick"_s));
    QTRY_VERIFY_WITH_TIMEOUT(client.inRoom(), 1000);
    QVERIFY(client.youAreHost());
    QCOMPARE(client.seatIndex(), 0);
    QCOMPARE(client.matchMode(), hexproof::protocol::kMatchBO3);
    QCOMPARE(client.cardLoadMode(), hexproof::protocol::kCardLoadPreload);

    QSignalSpy kickedSpy(&client, &WsClient::kicked);

    Envelope error;
    error.type = hexproof::protocol::kTypeError;
    error.id = u"stale"_s;
    error.payload = QJsonObject{
        {u"code"_s, u"invalid_target"_s},
        {u"message"_s, u"invalid target"_s},
    };
    sendEnvelope(peer, error);
    QTRY_VERIFY_WITH_TIMEOUT(!client.lastError().isEmpty(), 1000);
    client.kickSeat(1);
    QVERIFY(client.lastError().isEmpty());

    // Correlated success reply to the host: remain in the room. The following
    // snapshot acts as an ordering barrier so the reply has been dispatched.
    Envelope hostReply;
    hostReply.type = hexproof::protocol::kTypeRoomKicked;
    hostReply.id = u"3"_s;
    hostReply.payload = QJsonObject{{u"roomId"_s, u"ABCDEF"_s}};
    sendEnvelope(peer, hostReply);
    sendEnvelope(peer, roomSnapshot(u"Room after kick"_s));
    QTRY_COMPARE_WITH_TIMEOUT(client.roomName(), u"Room after kick"_s, 1000);
    QVERIFY(client.inRoom());
    QVERIFY(client.youAreHost());
    QCOMPARE(client.roomRole(), u"player"_s);
    QCOMPARE(kickedSpy.count(), 0);

    // Uncorrelated server push to the target: leave the room but stay connected
    // to the hub and notify the UI exactly once.
    Envelope kickedPush;
    kickedPush.type = hexproof::protocol::kTypeRoomKicked;
    kickedPush.payload = QJsonObject{{u"roomId"_s, u"ABCDEF"_s}};
    sendEnvelope(peer, kickedPush);
    QTRY_COMPARE_WITH_TIMEOUT(kickedSpy.count(), 1, 1000);
    QVERIFY(!client.inRoom());
    QVERIFY(client.connected());
    QVERIFY(!client.youAreHost());
    QVERIFY(client.roomId().isEmpty());
    QVERIFY(client.roomRole().isEmpty());
}

void TestWsClient::exposesJoinedRoomRole() const
{
    QWebSocketServer server(u"Hexproof test server"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));

    QWebSocket *peer = nullptr;
    connect(&server, &QWebSocketServer::newConnection, &server,
            [&]() { peer = takeServerPeer(server); });

    WsClient client;
    client.connectTo(u"ws://127.0.0.1:"_s + QString::number(server.serverPort()), u"Observer"_s);
    QTRY_VERIFY_WITH_TIMEOUT(peer != nullptr, 1000);

    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.id = u"1"_s;
    welcome.payload = QJsonObject{
        {u"v"_s, hexproof::protocol::kProtocolVersion},
        {u"connectionId"_s, u"conn-2"_s},
        {u"serverVersion"_s, buildVersion()},
    };
    sendEnvelope(peer, welcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 1000);

    Envelope joined;
    joined.type = hexproof::protocol::kTypeRoomJoined;
    joined.id = u"2"_s;
    joined.payload = QJsonObject{
        {u"roomId"_s, u"ABCDEF"_s},
        {u"role"_s, u"spectator"_s},
    };
    sendEnvelope(peer, joined);
    sendEnvelope(peer, roomSnapshot(u"Observed room"_s));

    QTRY_VERIFY_WITH_TIMEOUT(client.inRoom(), 1000);
    QVERIFY(!client.youAreHost());
    QCOMPARE(client.roomRole(), u"spectator"_s);
    QCOMPARE(client.seatIndex(), -1);
    QCOMPARE(client.roomSession()->role(), u"spectator"_s);
    QCOMPARE(client.roomSession()->seatIndex(), -1);
    QVERIFY(!client.roomSession()->host());
}

void TestWsClient::roomSessionStateExposesQmlBindableIdentity() const
{
    RoomSessionState session;
    session.enter(u"ABCDEF"_s, u"player"_s, 1, true);
    session.rememberPendingDeck(u"req-1"_s, u"Burn"_s);
    session.takePendingDeck(u"req-1"_s);

    QCOMPARE(session.property("roomId").toString(), u"ABCDEF"_s);
    QCOMPARE(session.property("role").toString(), u"player"_s);
    QCOMPARE(session.property("seatIndex").toInt(), 1);
    QCOMPARE(session.property("host").toBool(), true);
    QCOMPARE(session.property("selectedDeckName").toString(), u"Burn"_s);
}

void TestWsClient::roomSessionStateExposesQmlBindableSnapshot() const
{
    RoomSessionState session;
    QJsonObject snapshot = roomSnapshot(u"Friday Night"_s).payload;
    snapshot.insert(u"playtest"_s, true);
    snapshot.insert(u"allowSpectators"_s, true);
    snapshot.insert(u"spectatorsSeeHands"_s, true);
    snapshot.insert(u"spectators"_s, QJsonArray{QJsonObject{{u"displayName"_s, u"Judge"_s}}});
    session.applySnapshot(snapshot);

    QCOMPARE(session.property("roomName").toString(), u"Friday Night"_s);
    QCOMPARE(session.property("format").toString(), u"modern"_s);
    QCOMPARE(session.property("playtest").toBool(), true);
    QCOMPARE(session.property("allowSpectators").toBool(), false);
    QCOMPARE(session.property("spectatorsSeeHands").toBool(), false);
    QCOMPARE(session.property("matchMode").toString(), u"bo3"_s);
    QCOMPARE(session.property("cardLoadMode").toString(), u"preload"_s);
    QCOMPARE(session.property("maxSeats").toInt(), 2);
    QCOMPARE(session.property("phase").toString(), u"waiting"_s);
    QCOMPARE(session.property("seats").toList().size(), 2);
    QCOMPARE(session.property("spectators").toList().size(), 1);

    snapshot.insert(u"playtest"_s, false);
    session.applySnapshot(snapshot);
    QCOMPARE(session.property("allowSpectators").toBool(), true);
    QCOMPARE(session.property("spectatorsSeeHands").toBool(), true);
}

void TestWsClient::gameSessionStateExposesQmlBindableSnapshot() const
{
    GameSessionState session;
    session.applySnapshot({
        {u"gameNumber"_s, 2},
        {u"startingSeat"_s, 1},
        {u"activeSeat"_s, 0},
        {u"currentPhase"_s, u"declare_attackers"_s},
        {u"score"_s, QVariantList{1, 0}},
        {u"drawnGames"_s, 1},
        {u"result"_s, QVariantMap{{u"winnerSeat"_s, 0}}},
        {u"sideboard"_s, QVariantMap{{u"deadlineMs"_s, 15000}}},
    });

    QCOMPARE(session.property("gameNumber").toInt(), 2);
    QCOMPARE(session.property("startingSeat").toInt(), 1);
    QCOMPARE(session.property("activeSeat").toInt(), 0);
    QCOMPARE(session.property("currentPhase").toString(), u"declare_attackers"_s);
    QCOMPARE(session.property("score").toList().size(), 2);
    QCOMPARE(session.property("drawnGames").toInt(), 1);
    QCOMPARE(session.property("result").toMap().value(u"winnerSeat"_s).toInt(), 0);
    QCOMPARE(session.property("finished").toBool(), true);
    QCOMPARE(session.property("sideboarding").toBool(), true);
}

void TestWsClient::dispatchesSharedSessionRoomAndGameFixtures() const
{
    QWebSocketServer server(u"Hexproof shared fixture server"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));

    QWebSocket *peer = nullptr;
    connect(&server, &QWebSocketServer::newConnection, &server,
            [&]() { peer = takeServerPeer(server); });

    WsClient client;
    client.connectTo(u"ws://127.0.0.1:"_s + QString::number(server.serverPort()), u"Alice"_s);
    QTRY_VERIFY_WITH_TIMEOUT(peer != nullptr, 1000);

    bool ok = false;
    Envelope welcome = sharedFixture(u"session-welcome.json"_s, &ok);
    QVERIFY(ok);
    welcome.payload.insert(u"serverVersion"_s, buildVersion());
    sendEnvelope(peer, welcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 1000);

    Envelope created = sharedFixture(u"room-created.json"_s, &ok);
    QVERIFY(ok);
    sendEnvelope(peer, created);
    Envelope room = sharedFixture(u"room-snapshot-owner.json"_s, &ok);
    QVERIFY(ok);
    sendEnvelope(peer, room);
    QTRY_VERIFY_WITH_TIMEOUT(client.inRoom(), 1000);
    QCOMPARE(client.roomSession()->roomName(), u"Friday EDH"_s);
    QCOMPARE(client.roomSession()->seatIndex(), 0);
    QCOMPARE(client.roomSession()->seats().size(), 4);
    QVERIFY(!client.roomSession()->seats().first().toMap().contains(u"deck"_s));

    QSignalSpy gameSnapshots(client.gameSession(), &GameSessionState::snapshotChanged);
    Envelope owner = sharedFixture(u"game-snapshot-owner.json"_s, &ok);
    QVERIFY(ok);
    sendEnvelope(peer, owner);
    QTRY_COMPARE_WITH_TIMEOUT(gameSnapshots.count(), 1, 1000);
    QVariantList seats = client.gameSession()->seats();
    QCOMPARE(seats.size(), 2);
    QCOMPARE(seats.at(0).toMap().value(u"hand"_s).toList().size(), 7);
    QVERIFY(seats.at(1).toMap().value(u"hand"_s).toList().isEmpty());

    Envelope opponent = sharedFixture(u"game-snapshot-opponent.json"_s, &ok);
    QVERIFY(ok);
    sendEnvelope(peer, opponent);
    QTRY_COMPARE_WITH_TIMEOUT(gameSnapshots.count(), 2, 1000);
    seats = client.gameSession()->seats();
    QVERIFY(seats.at(0).toMap().value(u"hand"_s).toList().isEmpty());
    QCOMPARE(seats.at(1).toMap().value(u"hand"_s).toList().size(), 7);
    QCOMPARE(
        seats.at(1).toMap().value(u"hand"_s).toList().first().toMap().value(u"name"_s).toString(),
        u"Island"_s);
}

void TestWsClient::exposesRoomAndGameSessionsToQml() const
{
    WsClient client;
    QVERIFY(client.metaObject()->indexOfProperty("roomSession") >= 0);
    QVERIFY(client.metaObject()->indexOfProperty("gameSession") >= 0);

    auto *room = qvariant_cast<RoomSessionState *>(client.property("roomSession"));
    auto *game = qvariant_cast<GameSessionState *>(client.property("gameSession"));
    QVERIFY(room != nullptr);
    QVERIFY(game != nullptr);
    QCOMPARE(room, client.findChild<RoomSessionState *>());
    QCOMPARE(game, client.findChild<GameSessionState *>());
}

void TestWsClient::hidesMirroredSessionPropertiesFromQml() const
{
    WsClient client;
    const QMetaObject *meta = client.metaObject();
    const QStringList mirrored = {
        u"youAreHost"_s,      u"roomRole"_s,     u"seatIndex"_s,    u"selectedDeckName"_s,
        u"roomId"_s,          u"roomName"_s,     u"format"_s,       u"playtest"_s,
        u"matchMode"_s,       u"cardLoadMode"_s, u"maxSeats"_s,     u"roomPhase"_s,
        u"loadId"_s,          u"seats"_s,        u"spectators"_s,   u"gameNumber"_s,
        u"startingSeat"_s,    u"activeSeat"_s,   u"currentPhase"_s, u"gameArrows"_s,
        u"gameAttachments"_s, u"gameLog"_s,      u"matchScore"_s,   u"gameResult"_s,
        u"sideboardState"_s,  u"sideboarding"_s, u"gameFinished"_s,
    };
    for (const QString &name : mirrored)
        QVERIFY2(meta->indexOfProperty(name.toUtf8().constData()) < 0,
                 qPrintable(name + u" should not be a QML property on WsClient"_s));

    QVERIFY(meta->indexOfProperty("inRoom") >= 0);
    QVERIFY(meta->indexOfProperty("connected") >= 0);
    QVERIFY(meta->indexOfProperty("lastError") >= 0);
    QVERIFY(meta->indexOfProperty("roomList") >= 0);
    QVERIFY(meta->indexOfProperty("replayList") >= 0);
    QVERIFY(meta->indexOfProperty("roomSession") >= 0);
    QVERIFY(meta->indexOfProperty("gameSession") >= 0);
    QCOMPARE(client.seatIndex(), -1);
    QCOMPARE(client.youAreHost(), false);
}

void TestWsClient::updatesHostAuthorityFromRoomSnapshots() const
{
    QWebSocketServer server(u"Hexproof host transfer server"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));

    QWebSocket *peer = nullptr;
    connect(&server, &QWebSocketServer::newConnection, &server,
            [&]() { peer = takeServerPeer(server); });

    WsClient client;
    client.connectTo(u"ws://127.0.0.1:"_s + QString::number(server.serverPort()), u"Bob"_s);
    QTRY_VERIFY_WITH_TIMEOUT(peer != nullptr, 1000);

    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.id = u"1"_s;
    welcome.payload = QJsonObject{
        {u"v"_s, hexproof::protocol::kProtocolVersion},
        {u"connectionId"_s, u"conn-guest"_s},
        {u"serverVersion"_s, buildVersion()},
    };
    sendEnvelope(peer, welcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 1000);

    Envelope joined;
    joined.type = hexproof::protocol::kTypeRoomJoined;
    joined.id = u"2"_s;
    joined.payload = QJsonObject{
        {u"roomId"_s, u"ABCDEF"_s},
        {u"role"_s, hexproof::protocol::kRolePlayer},
        {u"seat"_s, 1},
    };
    sendEnvelope(peer, joined);

    Envelope snapshot = roomSnapshot(u"Transferred room"_s);
    QJsonArray seats = snapshot.payload.value(u"seats"_s).toArray();
    QJsonObject guestSeat{
        {u"occupied"_s, true},
        {u"displayName"_s, u"Bob"_s},
        {u"host"_s, false},
    };
    seats.replace(1, guestSeat);
    snapshot.payload.insert(u"seats"_s, seats);
    sendEnvelope(peer, snapshot);
    QTRY_VERIFY_WITH_TIMEOUT(client.inRoom(), 1000);
    QVERIFY(!client.youAreHost());

    seats[0] = QJsonObject{
        {u"occupied"_s, false},
        {u"host"_s, false},
    };
    guestSeat.insert(u"host"_s, true);
    seats[1] = guestSeat;
    snapshot.seq = 2;
    snapshot.payload.insert(u"hostSeat"_s, 1);
    snapshot.payload.insert(u"seats"_s, seats);
    QSignalSpy hostChanged(&client, &WsClient::youAreHostChanged);
    sendEnvelope(peer, snapshot);
    QTRY_VERIFY_WITH_TIMEOUT(client.youAreHost(), 1000);
    QCOMPARE(hostChanged.count(), 1);
}

QTEST_GUILESS_MAIN(TestWsClient)
