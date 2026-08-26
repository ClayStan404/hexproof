// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#include "wsclient_test.h"

void TestWsClient::sendsDeckAndReadyCommands() const
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
        {u"connectionId"_s, u"conn-3"_s},
        {u"serverVersion"_s, buildVersion()},
    };
    sendEnvelope(peer, welcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 1000);

    Envelope created;
    created.type = hexproof::protocol::kTypeRoomCreated;
    created.id = u"2"_s;
    created.payload = QJsonObject{{u"roomId"_s, u"ABCDEF"_s}};
    sendEnvelope(peer, created);
    sendEnvelope(peer, roomSnapshot(u"Ready room"_s, true, false));
    QTRY_VERIFY_WITH_TIMEOUT(client.inRoom(), 1000);
    QCOMPARE(client.seatIndex(), 0);
    QVERIFY(client.seats().first().toMap().value(u"deckSelected"_s).toBool());

    QSignalSpy outbound(peer, &QWebSocket::textMessageReceived);
    const QVariantMap deck{
        {u"name"_s, u"Burn"_s},
        {u"format"_s, u"modern"_s},
        {u"commander"_s, QString{}},
        {u"mainboard"_s, QVariantList{QVariantMap{
                             {u"name"_s, u"Lightning Bolt"_s},
                             {u"count"_s, 7},
                             {u"setCode"_s, u"M11"_s},
                             {u"collectorNumber"_s, u"149"_s},
                             {u"typeLine"_s, u"Instant"_s},
                         }}},
        {u"sideboard"_s, QVariantList{}},
    };
    client.selectDeck(deck);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    bool ok = false;
    Envelope sent =
        hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeDeckSelect);
    QVERIFY(!sent.id.isEmpty());
    QCOMPARE(sent.payload.value(u"name"_s).toString(), u"Burn"_s);
    QCOMPARE(
        sent.payload.value(u"mainboard"_s).toArray().first().toObject().value(u"name"_s).toString(),
        u"Lightning Bolt"_s);
    QCOMPARE(sent.payload.value(u"mainboard"_s)
                 .toArray()
                 .first()
                 .toObject()
                 .value(u"typeLine"_s)
                 .toString(),
             u"Instant"_s);
    QVERIFY(client.selectedDeckName().isEmpty());

    Envelope selected;
    selected.type = hexproof::protocol::kTypeDeckSelected;
    selected.id = sent.id;
    selected.payload = QJsonObject{{u"name"_s, u"Burn"_s}};
    sendEnvelope(peer, selected);
    QTRY_COMPARE_WITH_TIMEOUT(client.selectedDeckName(), u"Burn"_s, 1000);

    QVariantMap rejectedDeck = deck;
    rejectedDeck.insert(u"name"_s, u"Rejected"_s);
    client.selectDeck(rejectedDeck);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    Envelope rejectedRequest =
        hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    Envelope rejected;
    rejected.type = hexproof::protocol::kTypeError;
    rejected.id = rejectedRequest.id;
    rejected.payload = QJsonObject{
        {u"code"_s, u"invalid_deck"_s},
        {u"message"_s, u"invalid_deck"_s},
    };
    sendEnvelope(peer, rejected);
    QTRY_VERIFY_WITH_TIMEOUT(client.lastError().contains(u"invalid_deck"_s), 1000);
    QCOMPARE(client.selectedDeckName(), u"Burn"_s);

    client.setReady(true);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypePlayerReady);
    QVERIFY(sent.payload.value(u"ready"_s).toBool());

    QSignalSpy loadSpy(&client, &WsClient::loadRequired);
    QSignalSpy cancelledSpy(&client, &WsClient::loadCancelled);
    QSignalSpy startedSpy(&client, &WsClient::matchStarted);
    QSignalSpy gameSpy(&client, &WsClient::gameSnapshotChanged);
    QSignalSpy librarySpy(&client, &WsClient::libraryDumped);
    QSignalSpy publicZoneMoveSpy(&client, &WsClient::publicZoneMoveRequested);
    Envelope load;
    load.type = hexproof::protocol::kTypeMatchLoadRequired;
    load.hasSeq = true;
    load.seq = 8;
    load.payload = QJsonObject{
        {u"loadId"_s, 4},
        {u"cardKeys"_s, QJsonArray{QJsonObject{
                            {u"name"_s, u"Lightning Bolt"_s},
                            {u"setCode"_s, u"M11"_s},
                            {u"collectorNumber"_s, u"149"_s},
                        }}},
    };
    sendEnvelope(peer, load);
    QTRY_COMPARE_WITH_TIMEOUT(loadSpy.count(), 1, 1000);
    QCOMPARE(client.roomPhase(), hexproof::protocol::kRoomPhaseLoading);
    QCOMPARE(client.loadId(), 4);
    QCOMPARE(loadSpy.first().at(1).toList().size(), 1);

    sendEnvelope(peer, roomSnapshot(u"Cancelled load"_s, true, false));
    QTRY_COMPARE_WITH_TIMEOUT(cancelledSpy.count(), 1, 1000);
    QCOMPARE(client.roomPhase(), hexproof::protocol::kRoomPhaseWaiting);
    QCOMPARE(client.loadId(), 0);

    load.seq = 9;
    load.payload.insert(u"loadId"_s, 5);
    sendEnvelope(peer, load);
    QTRY_COMPARE_WITH_TIMEOUT(loadSpy.count(), 2, 1000);
    QCOMPARE(client.loadId(), 5);

    client.completeLoad(5);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeClientLoadComplete);
    QCOMPARE(sent.payload.value(u"loadId"_s).toInteger(), 5);

    Envelope started;
    started.type = hexproof::protocol::kTypeMatchStarted;
    started.hasSeq = true;
    started.seq = 10;
    started.payload = QJsonObject{{u"roomId"_s, u"ABCDEF"_s}, {u"loadId"_s, 5}};
    sendEnvelope(peer, started);
    QTRY_COMPARE_WITH_TIMEOUT(startedSpy.count(), 1, 1000);
    QCOMPARE(client.roomPhase(), hexproof::protocol::kRoomPhaseStarted);

    Envelope game;
    game.type = hexproof::protocol::kTypeGameSnapshot;
    game.hasSeq = true;
    game.seq = 11;
    game.payload = QJsonObject{
        {u"roomId"_s, u"ABCDEF"_s},
        {u"gameNumber"_s, 1},
        {u"startingSeat"_s, 1},
        {u"activeSeat"_s, 0},
        {u"currentPhase"_s, hexproof::protocol::kGamePhaseUntap},
        {u"seats"_s,
         QJsonArray{
             QJsonObject{
                 {u"seat"_s, 0},
                 {u"displayName"_s, u"Alice"_s},
                 {u"life"_s, 20},
                 {u"libraryCount"_s, 52},
                 {u"handCount"_s, 8},
                 {u"hand"_s, QJsonArray{QJsonObject{
                                 {u"id"_s, u"s0-c1"_s},
                                 {u"name"_s, u"Lightning Bolt"_s},
                                 {u"setCode"_s, u"M11"_s},
                                 {u"collectorNumber"_s, u"149"_s},
                             }}},
                 {u"battlefield"_s, QJsonArray{}},
                 {u"graveyard"_s, QJsonArray{}},
                 {u"exile"_s, QJsonArray{}},
             },
             QJsonObject{
                 {u"seat"_s, 1},
                 {u"displayName"_s, u"Bob"_s},
                 {u"life"_s, 20},
                 {u"libraryCount"_s, 53},
                 {u"handCount"_s, 7},
                 {u"battlefield"_s, QJsonArray{}},
                 {u"graveyard"_s, QJsonArray{}},
                 {u"exile"_s, QJsonArray{}},
             },
         }},
        {u"stack"_s, QJsonArray{QJsonObject{
                         {u"id"_s, u"s0-stack"_s},
                         {u"name"_s, u"Counterspell"_s},
                         {u"setCode"_s, u"MH2"_s},
                         {u"collectorNumber"_s, u"267"_s},
                         {u"ownerSeat"_s, 0},
                     }}},
        {u"revealed"_s, QJsonArray{QJsonObject{
                            {u"id"_s, u"s0-reveal"_s},
                            {u"name"_s, u"Mountain"_s},
                            {u"setCode"_s, u"M11"_s},
                            {u"collectorNumber"_s, u"242"_s},
                            {u"ownerSeat"_s, 0},
                        }}},
        {u"score"_s, QJsonArray{0, 0}},
        {u"log"_s, QJsonArray{QJsonObject{
                       {u"id"_s, 1},
                       {u"kind"_s, u"roll"_s},
                       {u"seat"_s, 1},
                       {u"text"_s, u"Bob won the opening roll."_s},
                   }}},
    };
    sendEnvelope(peer, game);
    QTRY_COMPARE_WITH_TIMEOUT(gameSpy.count(), 1, 1000);
    QCOMPARE(client.gameNumber(), 1);
    QCOMPARE(client.startingSeat(), 1);
    QCOMPARE(client.activeSeat(), 0);
    QCOMPARE(client.currentPhase(), hexproof::protocol::kGamePhaseUntap);
    QCOMPARE(client.gameSeats().size(), 2);
    QCOMPARE(client.gameSeats().first().toMap().value(u"hand"_s).toList().size(), 1);
    QCOMPARE(client.gameStack().size(), 1);
    QCOMPARE(client.gameStack().first().toMap().value(u"ownerSeat"_s).toInt(), 0);
    QCOMPARE(client.gameRevealed().size(), 1);
    QCOMPARE(client.gameRevealed().first().toMap().value(u"name"_s).toString(), u"Mountain"_s);
    QCOMPARE(client.gameLog().size(), 1);
    QCOMPARE(client.matchScore(), QVariantList({0, 0}));
    QVERIFY(!client.gameFinished());
    QVERIFY(client.gameResult().isEmpty());

    client.dumpLibrary();
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameDumpZone);
    QCOMPARE(sent.payload.value(u"zone"_s).toString(), u"library"_s);

    Envelope dumped;
    dumped.type = hexproof::protocol::kTypeGameZoneDumped;
    dumped.id = sent.id;
    dumped.payload = QJsonObject{
        {u"roomId"_s, u"ABCDEF"_s},
        {u"zone"_s, u"library"_s},
        {u"cards"_s,
         QJsonArray{
             QJsonObject{
                 {u"id"_s, u"s0-c8"_s},
                 {u"name"_s, u"Island"_s},
                 {u"setCode"_s, u"M21"_s},
                 {u"collectorNumber"_s, u"265"_s},
             },
             QJsonObject{
                 {u"id"_s, u"s0-c9"_s},
                 {u"name"_s, u"Demonic Tutor"_s},
                 {u"setCode"_s, u"STA"_s},
                 {u"collectorNumber"_s, u"27"_s},
             },
         }},
    };
    sendEnvelope(peer, dumped);
    QTRY_COMPARE_WITH_TIMEOUT(librarySpy.count(), 1, 1000);
    const QVariantList dumpedCards = librarySpy.first().first().toList();
    QCOMPARE(dumpedCards.size(), 2);
    QCOMPARE(dumpedCards.last().toMap().value(u"name"_s).toString(), u"Demonic Tutor"_s);
    QCOMPARE(librarySpy.first().at(3).toInt(), 0);

    Envelope publicZoneRequested;
    publicZoneRequested.type = hexproof::protocol::kTypeGamePublicZoneMoveRequested;
    publicZoneRequested.payload = QJsonObject{
        {u"roomId"_s, u"ABCDEF"_s},
        {u"approvalId"_s, u"public-zone-move-1"_s},
        {u"requesterSeat"_s, 1},
        {u"requesterName"_s, u"Bob"_s},
        {u"sourceZone"_s, hexproof::protocol::kZoneGraveyard},
        {u"cardCount"_s, 2},
        {u"toZone"_s, hexproof::protocol::kZoneBattlefield},
    };
    sendEnvelope(peer, publicZoneRequested);
    QTRY_COMPARE_WITH_TIMEOUT(publicZoneMoveSpy.count(), 1, 1000);
    QCOMPARE(publicZoneMoveSpy.first().at(0).toString(), u"public-zone-move-1"_s);
    QCOMPARE(publicZoneMoveSpy.first().at(1).toString(), u"Bob"_s);
    QCOMPARE(publicZoneMoveSpy.first().at(3).toString(), hexproof::protocol::kZoneGraveyard);
    QCOMPARE(publicZoneMoveSpy.first().at(4).toInt(), 2);
    QCOMPARE(publicZoneMoveSpy.first().at(5).toString(), hexproof::protocol::kZoneBattlefield);

    client.respondPublicZoneMove(u"public-zone-move-1"_s, true);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameRespondPublicZoneMove);
    QCOMPARE(sent.payload.value(u"approvalId"_s).toString(), u"public-zone-move-1"_s);
    QVERIFY(sent.payload.value(u"approved"_s).toBool());

    client.dumpLibrary(0, 5);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameDumpZone);
    QCOMPARE(sent.payload.value(u"seat"_s).toInt(), 0);
    QCOMPARE(sent.payload.value(u"topCount"_s).toInt(), 5);

    client.recallRevealed();
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameRecallRevealed);

    client.moveCards(QVariantList{u"s0-c1"_s, u"s0-c2"_s}, hexproof::protocol::kZoneBattlefield,
                     hexproof::protocol::kZoneLibrary, u"bottom"_s, true);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameMoveCards);
    QCOMPARE(sent.payload.value(u"cardIds"_s).toArray().size(), 2);
    QCOMPARE(sent.payload.value(u"libraryPlacement"_s).toString(), u"bottom"_s);
    QVERIFY(sent.payload.value(u"randomize"_s).toBool());

    client.movePublicCards(QVariantList{u"s0-g1"_s, u"s0-g2"_s}, hexproof::protocol::kZoneGraveyard,
                           0, hexproof::protocol::kZoneBattlefield, 0,
                           QVariantMap{{u"x"_s, 0.5}, {u"y"_s, 0.3}});
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameMoveCards);
    QCOMPARE(sent.payload.value(u"cardIds"_s).toArray().size(), 2);
    QCOMPARE(sent.payload.value(u"fromZone"_s).toString(), hexproof::protocol::kZoneGraveyard);
    QCOMPARE(sent.payload.value(u"fromSeat"_s).toInt(), 0);
    QCOMPARE(sent.payload.value(u"toZone"_s).toString(), hexproof::protocol::kZoneBattlefield);
    QCOMPARE(sent.payload.value(u"toSeat"_s).toInt(), 0);
    QCOMPARE(sent.payload.value(u"position"_s).toObject().value(u"y"_s).toDouble(), 0.3);

    client.moveLibraryCards(3, hexproof::protocol::kZoneExile);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameMoveLibraryCards);
    QCOMPARE(sent.payload.value(u"count"_s).toInt(), 3);
    QCOMPARE(sent.payload.value(u"toZone"_s).toString(), hexproof::protocol::kZoneExile);

    client.searchLibraryCards(QVariantList{u"s0-c8"_s, u"s0-c9"_s},
                              hexproof::protocol::kZoneGraveyard, false, true);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameSearchLibrary);
    QCOMPARE(sent.payload.value(u"cardIds"_s).toArray().size(), 2);
    QVERIFY(sent.payload.value(u"randomize"_s).toBool());

    client.reorderLibrary(QVariantList{u"s0-c9"_s, u"s0-c8"_s});
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameReorderLibrary);
    QCOMPARE(sent.payload.value(u"cardIds"_s).toArray().first().toString(), u"s0-c9"_s);

    client.resolveLibraryView(QVariantList{u"s1-c8"_s}, QVariantList{u"s1-c9"_s},
                              hexproof::protocol::kZoneHand, u"bottom"_s, false, false, {}, 1,
                              u"zone-dump-1"_s);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameResolveLibraryView);
    QCOMPARE(sent.payload.value(u"sourceSeat"_s).toInt(), 1);
    QCOMPARE(sent.payload.value(u"approvalId"_s).toString(), u"zone-dump-1"_s);
    QCOMPARE(sent.payload.value(u"selectedCardIds"_s).toArray().first().toString(), u"s1-c8"_s);
    QCOMPARE(sent.payload.value(u"remainderCardIds"_s).toArray().first().toString(), u"s1-c9"_s);
    QCOMPARE(sent.payload.value(u"toZone"_s).toString(), hexproof::protocol::kZoneHand);

    client.resolveLibraryView(QVariantList{u"s1-c8"_s}, QVariantList{u"s1-c9"_s},
                              hexproof::protocol::kLibraryDestinationBottom, u"top"_s, false, false,
                              {}, 1, u"zone-dump-1"_s);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameResolveLibraryView);
    QCOMPARE(sent.payload.value(u"toZone"_s).toString(),
             hexproof::protocol::kLibraryDestinationBottom);
    QCOMPARE(sent.payload.value(u"remainderPlacement"_s).toString(), u"top"_s);

    client.searchLibrary(u"s0-c8"_s, hexproof::protocol::kZoneBattlefield, true,
                         QVariantMap{{u"x"_s, 0.5}, {u"y"_s, 0.5}});
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameSearchLibrary);
    QCOMPARE(sent.payload.value(u"cardId"_s).toString(), u"s0-c8"_s);
    QCOMPARE(sent.payload.value(u"toZone"_s).toString(), hexproof::protocol::kZoneBattlefield);
    QVERIFY(sent.payload.value(u"reveal"_s).toBool());
    QCOMPARE(sent.payload.value(u"position"_s).toObject().value(u"x"_s).toDouble(), 0.5);

    client.drawCards();
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameDraw);
    QVERIFY(sent.payload.isEmpty());

    client.drawCards(3);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameDraw);
    QCOMPARE(sent.payload.value(u"count"_s).toInt(), 3);

    client.mulligan();
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameMulligan);

    client.discardHand();
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameDiscardHand);
    QVERIFY(sent.payload.isEmpty());

    client.discardHand(true);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameDiscardHand);
    QVERIFY(sent.payload.value(u"all"_s).toBool());

    client.moveCard(u"s0-c1"_s, hexproof::protocol::kZoneHand, hexproof::protocol::kZoneBattlefield,
                    QVariantMap{{u"x"_s, 0.25}, {u"y"_s, 0.6}}, 1);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameMoveCard);
    QCOMPARE(sent.payload.value(u"cardId"_s).toString(), u"s0-c1"_s);
    QCOMPARE(sent.payload.value(u"fromZone"_s).toString(), hexproof::protocol::kZoneHand);
    QCOMPARE(sent.payload.value(u"toZone"_s).toString(), hexproof::protocol::kZoneBattlefield);
    QCOMPARE(sent.payload.value(u"toSeat"_s).toInt(), 1);
    const QJsonObject position = sent.payload.value(u"position"_s).toObject();
    QCOMPARE(position.value(u"x"_s).toDouble(), 0.25);
    QCOMPARE(position.value(u"y"_s).toDouble(), 0.6);

    client.moveCard(u"s1-gy1"_s, hexproof::protocol::kZoneGraveyard,
                    hexproof::protocol::kZoneBattlefield, QVariantMap{{u"x"_s, 0.5}, {u"y"_s, 0.3}},
                    0, {}, -1, 1);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.payload.value(u"fromSeat"_s).toInt(), 1);
    QCOMPARE(sent.payload.value(u"toSeat"_s).toInt(), 0);

    client.setCardTapped(u"s0-c1"_s, true);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameSetTapped);
    QCOMPARE(sent.payload.value(u"cardId"_s).toString(), u"s0-c1"_s);
    QVERIFY(sent.payload.value(u"tapped"_s).toBool());

    client.setCardFaceDown(u"s0-c1"_s, true);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameSetFaceDown);
    QCOMPARE(sent.payload.value(u"cardId"_s).toString(), u"s0-c1"_s);
    QVERIFY(sent.payload.value(u"faceDown"_s).toBool());

    client.declareDraw();
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameDeclareDraw);

    client.restartGame();
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameRestart);

    client.rollDice(6, 3);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameRoll);
    QCOMPARE(sent.payload.value(u"sides"_s).toInt(), 6);
    QCOMPARE(sent.payload.value(u"count"_s).toInt(), 3);

    client.flipCoin();
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameFlipCoin);

    client.randomSelectPlayer();
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameRandomSelect);
    QCOMPARE(sent.payload.value(u"kind"_s).toString(), u"player"_s);

    client.randomSelectCards(QVariantList{u"card-a"_s, u"card-b"_s});
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameRandomSelect);
    QCOMPARE(sent.payload.value(u"kind"_s).toString(), u"card"_s);
    QCOMPARE(sent.payload.value(u"cardIds"_s).toArray().size(), 2);

    client.setPhase(hexproof::protocol::kGamePhaseDeclareAttackers);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameSetPhase);
    QCOMPARE(sent.payload.value(u"phase"_s).toString(),
             hexproof::protocol::kGamePhaseDeclareAttackers);

    client.setResponseStatus(hexproof::protocol::kResponseStatusHold);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameSetResponseStatus);
    QCOMPARE(sent.payload.value(u"status"_s).toString(), hexproof::protocol::kResponseStatusHold);

    client.setCounter(hexproof::protocol::kPlayerCounterLife, 17);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameSetCounter);
    QCOMPARE(sent.payload.value(u"counter"_s).toString(), hexproof::protocol::kPlayerCounterLife);
    QCOMPARE(sent.payload.value(u"value"_s).toInt(), 17);

    const QString counterKey = hexproof::protocol::kPlayerCounterSlotPrefix + u"1"_s;
    client.adjustCounter(counterKey, 1);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameSetCounter);
    QCOMPARE(sent.payload.value(u"counter"_s).toString(), counterKey);
    QCOMPARE(sent.payload.value(u"delta"_s).toInt(), 1);
    QVERIFY(!sent.payload.contains(u"value"_s));

    client.renameCounter(counterKey, u"Energy"_s);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameSetCounter);
    QCOMPARE(sent.payload.value(u"counter"_s).toString(), counterKey);
    QCOMPARE(sent.payload.value(u"label"_s).toString(), u"Energy"_s);
    QVERIFY(!sent.payload.contains(u"value"_s));
    QVERIFY(!sent.payload.contains(u"delta"_s));

    client.setCounterCount(3);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameSetCounterCount);
    QCOMPARE(sent.payload.value(u"count"_s).toInt(), 3);

    client.nextTurn();
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameNextTurn);
    QVERIFY(sent.payload.isEmpty());

    client.revealHand();
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameReveal);
    QCOMPARE(sent.payload.value(u"zone"_s).toString(), hexproof::protocol::kZoneHand);

    client.sayGameMessage(u"  Good luck!  "_s);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameSay);
    QCOMPARE(sent.payload.value(u"message"_s).toString(), u"Good luck!"_s);

    client.createToken(
        QVariantMap{
            {u"name"_s, u"Goblin"_s},
            {u"setCode"_s, u"TNEO"_s},
            {u"collectorNumber"_s, u"12"_s},
            {u"typeLine"_s, u"Token Creature — Goblin"_s},
        },
        QVariantMap{{u"x"_s, 0.5}, {u"y"_s, 0.3}});
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameCreateToken);
    QCOMPARE(sent.payload.value(u"name"_s).toString(), u"Goblin"_s);
    QCOMPARE(sent.payload.value(u"typeLine"_s).toString(), u"Token Creature — Goblin"_s);
    QCOMPARE(sent.payload.value(u"position"_s).toObject().value(u"y"_s).toDouble(), 0.3);

    client.adjustCommanderTax(u"s0-c1"_s, 1);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameAdjustCommanderTax);
    QCOMPARE(sent.payload.value(u"commanderId"_s).toString(), u"s0-c1"_s);
    QCOMPARE(sent.payload.value(u"delta"_s).toInt(), 1);

    const QVariantMap sideboardCard{
        {u"name"_s, u"Wear // Tear"_s},
        {u"count"_s, 2},
        {u"setCode"_s, u"DGM"_s},
        {u"collectorNumber"_s, u"135"_s},
    };
    client.moveSideboardCard(sideboardCard, hexproof::protocol::kSideboardZoneSide,
                             hexproof::protocol::kSideboardZoneMain);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeSideboardMove);
    QCOMPARE(sent.payload.value(u"fromZone"_s).toString(), hexproof::protocol::kSideboardZoneSide);
    QCOMPARE(sent.payload.value(u"toZone"_s).toString(), hexproof::protocol::kSideboardZoneMain);
    QVERIFY(!sent.payload.contains(u"count"_s));

    client.setSideboardReady(true);
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeSideboardReady);
    QVERIFY(sent.payload.value(u"ready"_s).toBool());

    client.concede();
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameConcede);
    QVERIFY(sent.payload.isEmpty());

    client.returnToRoom();
    QTRY_COMPARE_WITH_TIMEOUT(outbound.count(), 1, 1000);
    sent = hexproof::protocol::parse(outbound.takeFirst().first().toString().toUtf8(), &ok);
    QVERIFY(ok);
    QCOMPARE(sent.type, hexproof::protocol::kTypeGameReturnToRoom);
    QVERIFY(sent.payload.isEmpty());

    game.seq = 12;
    game.payload.insert(u"activeSeat"_s, -1);
    game.payload.insert(u"score"_s, QJsonArray{0, 1});
    game.payload.insert(u"result"_s, QJsonObject{
                                         {u"reason"_s, u"concede"_s},
                                         {u"winnerSeat"_s, 1},
                                         {u"concededSeat"_s, 0},
                                         {u"matchFinished"_s, false},
                                     });
    game.payload.insert(u"sideboard"_s, QJsonObject{
                                            {u"deadlineUnixMs"_s, 1784721900000LL},
                                            {u"seats"_s,
                                             QJsonArray{
                                                 QJsonObject{
                                                     {u"seat"_s, 0},
                                                     {u"ready"_s, false},
                                                     {u"mainboardCount"_s, 60},
                                                     {u"sideboardCount"_s, 15},
                                                 },
                                                 QJsonObject{
                                                     {u"seat"_s, 1},
                                                     {u"ready"_s, true},
                                                     {u"mainboardCount"_s, 60},
                                                     {u"sideboardCount"_s, 15},
                                                 },
                                             }},
                                            {u"mainboard"_s, QJsonArray{QJsonObject{
                                                                 {u"name"_s, u"Lightning Bolt"_s},
                                                                 {u"count"_s, 4},
                                                                 {u"setCode"_s, u"M11"_s},
                                                                 {u"collectorNumber"_s, u"149"_s},
                                                                 {u"typeLine"_s, u"Instant"_s},
                                                             }}},
                                            {u"sideboard"_s, QJsonArray{QJsonObject{
                                                                 {u"name"_s, u"Wear // Tear"_s},
                                                                 {u"count"_s, 2},
                                                                 {u"setCode"_s, u"DGM"_s},
                                                                 {u"collectorNumber"_s, u"135"_s},
                                                                 {u"typeLine"_s, u"Instant"_s},
                                                             }}},
                                        });
    sendEnvelope(peer, game);
    QTRY_COMPARE_WITH_TIMEOUT(gameSpy.count(), 2, 1000);
    QVERIFY(client.gameFinished());
    QCOMPARE(client.activeSeat(), -1);
    QCOMPARE(client.matchScore(), QVariantList({0, 1}));
    QCOMPARE(client.gameResult().value(u"winnerSeat"_s).toInt(), 1);
    QVERIFY(client.sideboarding());
    QCOMPARE(client.sideboardState().value(u"mainboard"_s).toList().size(), 1);
    QCOMPARE(client.sideboardState().value(u"seats"_s).toList().size(), 2);
    QCOMPARE(client.sideboardState()
                 .value(u"mainboard"_s)
                 .toList()
                 .first()
                 .toMap()
                 .value(u"typeLine"_s)
                 .toString(),
             u"Instant"_s);
}

void TestWsClient::handshakeErrorDisconnects() const
{
    QWebSocketServer server(u"Hexproof test server"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));

    QWebSocket *peer = nullptr;
    connect(&server, &QWebSocketServer::newConnection, &server,
            [&]() { peer = takeServerPeer(server); });

    WsClient client;
    client.connectTo(u"ws://127.0.0.1:"_s + QString::number(server.serverPort()), u"Alice"_s);
    QVERIFY(client.connecting());
    QTRY_VERIFY_WITH_TIMEOUT(peer != nullptr, 1000);

    Envelope error;
    error.type = hexproof::protocol::kTypeError;
    error.id = u"1"_s;
    error.payload = QJsonObject{
        {u"code"_s, hexproof::protocol::kErrClientVersionMismatch},
        {u"message"_s, u"client update required"_s},
        {u"clientVersion"_s, buildVersion()},
        {u"requiredVersion"_s, u"9.9.9"_s},
    };
    sendEnvelope(peer, error);

    QTRY_COMPARE_WITH_TIMEOUT(client.connectionState(), WsClient::Disconnected, 1000);
    QCOMPARE(client.lastError(), u"client_version_mismatch: client update required"_s);
    QVERIFY(client.versionMismatch());
    QCOMPARE(client.clientVersion(), buildVersion());
    QCOMPARE(client.requiredVersion(), u"9.9.9"_s);
    QVERIFY(client.releaseDownloadUrl().contains(u"github.com/ClayStan404/hexproof/releases"_s));
}

void TestWsClient::rejectsOversizeIncomingMessages() const
{
    QWebSocketServer server(u"Hexproof incoming limit server"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));

    QWebSocket *peer = nullptr;
    connect(&server, &QWebSocketServer::newConnection, &server,
            [&]() { peer = takeServerPeer(server); });

    WsClient client;
    client.connectTo(u"ws://127.0.0.1:"_s + QString::number(server.serverPort()), u"Alice"_s);
    QTRY_VERIFY_WITH_TIMEOUT(peer != nullptr, 1000);
    QSignalSpy disconnected(peer, &QWebSocket::disconnected);

    const QByteArray payload(
        static_cast<qsizetype>(network_limits::kMaximumIncomingWebSocketBytes + 1), 'x');
    peer->sendTextMessage(QString::fromLatin1(payload));
    QTRY_VERIFY_WITH_TIMEOUT(disconnected.count() > 0, 5000);
    QVERIFY(!client.connected());
}

void TestWsClient::welcomeVersionMismatchDisconnects() const
{
    QWebSocketServer server(u"Hexproof version mismatch server"_s, QWebSocketServer::NonSecureMode);
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
        {u"connectionId"_s, u"conn-version-mismatch"_s},
        {u"serverVersion"_s, u"9.9.9"_s},
    };
    sendEnvelope(peer, welcome);

    QTRY_COMPARE_WITH_TIMEOUT(client.connectionState(), WsClient::Disconnected, 1000);
    QVERIFY(client.versionMismatch());
    QCOMPARE(client.requiredVersion(), u"9.9.9"_s);
    QVERIFY(client.lastError().contains(hexproof::protocol::kErrClientVersionMismatch));
}

void TestWsClient::resumesRoomAfterUnexpectedDisconnect() const
{
    QWebSocketServer server(u"Hexproof reconnect test server"_s, QWebSocketServer::NonSecureMode);
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));

    QList<QWebSocket *> peers;
    QList<QList<Envelope>> received;
    connect(&server, &QWebSocketServer::newConnection, &server, [&]() {
        QWebSocket *peer = takeServerPeer(server);
        const qsizetype index = peers.size();
        peers.append(peer);
        received.append(QList<Envelope>{});
        connect(peer, &QWebSocket::textMessageReceived, &server, [&, index](const QString &text) {
            bool ok = false;
            const Envelope env = hexproof::protocol::parse(text.toUtf8(), &ok);
            if (ok)
                received[index].append(env);
        });
    });

    WsClient client;
    const QString serverUrl = u"ws://127.0.0.1:"_s + QString::number(server.serverPort());
    client.connectTo(serverUrl, u"Alice"_s);
    QTRY_VERIFY_WITH_TIMEOUT(peers.size() == 1, 1000);
    QTRY_VERIFY_WITH_TIMEOUT(!received[0].isEmpty(), 1000);
    QCOMPARE(received[0].first().type, hexproof::protocol::kTypeSessionHello);
    QVERIFY(!received[0].first().payload.contains(u"resumeToken"_s));

    Envelope welcome;
    welcome.type = hexproof::protocol::kTypeSessionWelcome;
    welcome.id = received[0].first().id;
    welcome.payload = QJsonObject{
        {u"v"_s, hexproof::protocol::kProtocolVersion},
        {u"connectionId"_s, u"conn-before-drop"_s},
        {u"serverVersion"_s, buildVersion()},
        {u"resumeToken"_s, u"resume-secret"_s},
    };
    sendEnvelope(peers[0], welcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 1000);

    Envelope created;
    created.type = hexproof::protocol::kTypeRoomCreated;
    created.id = u"2"_s;
    created.payload = QJsonObject{{u"roomId"_s, u"ABCDEF"_s}};
    sendEnvelope(peers[0], created);
    Envelope beforeDrop = roomSnapshot(u"Room before drop"_s, true, true);
    beforeDrop.seq = 7;
    sendEnvelope(peers[0], beforeDrop);
    QTRY_VERIFY_WITH_TIMEOUT(client.inRoom(), 1000);

    peers[0]->close();
    QTRY_VERIFY_WITH_TIMEOUT(client.reconnecting(), 1000);
    client.drawCards(1);
    QCOMPARE(client.lastError(),
             u"connection: action not sent while the connection is unavailable"_s);
    QTRY_VERIFY_WITH_TIMEOUT(peers.size() == 2, 4000);
    QTRY_VERIFY_WITH_TIMEOUT(!received[1].isEmpty(), 1000);

    const Envelope resumeHello = received[1].first();
    QCOMPARE(resumeHello.type, hexproof::protocol::kTypeSessionHello);
    QCOMPARE(resumeHello.payload.value(u"resumeToken"_s).toString(), u"resume-secret"_s);
    QCOMPARE(resumeHello.payload.value(u"lastSeq"_s).toInteger(), 7);

    Envelope prematureFreshWelcome;
    prematureFreshWelcome.type = hexproof::protocol::kTypeSessionWelcome;
    prematureFreshWelcome.id = resumeHello.id;
    prematureFreshWelcome.payload = QJsonObject{
        {u"v"_s, hexproof::protocol::kProtocolVersion},
        {u"connectionId"_s, u"conn-premature"_s},
        {u"serverVersion"_s, buildVersion()},
        {u"resumeToken"_s, u"do-not-adopt"_s},
    };
    sendEnvelope(peers[1], prematureFreshWelcome);
    QTRY_VERIFY_WITH_TIMEOUT(client.reconnecting(), 1000);
    QTRY_VERIFY_WITH_TIMEOUT(peers.size() == 3, 5000);
    QTRY_VERIFY_WITH_TIMEOUT(!received[2].isEmpty(), 1000);
    const Envelope retriedResumeHello = received[2].first();
    QCOMPARE(retriedResumeHello.type, hexproof::protocol::kTypeSessionHello);
    QCOMPARE(retriedResumeHello.payload.value(u"resumeToken"_s).toString(), u"resume-secret"_s);

    Envelope resumed;
    resumed.type = hexproof::protocol::kTypeSessionWelcome;
    resumed.id = retriedResumeHello.id;
    resumed.payload = QJsonObject{
        {u"v"_s, hexproof::protocol::kProtocolVersion},
        {u"connectionId"_s, u"conn-after-drop"_s},
        {u"serverVersion"_s, buildVersion()},
        {u"resumeToken"_s, u"resume-secret"_s},
        {u"resumed"_s, true},
        {u"roomId"_s, u"ABCDEF"_s},
        {u"role"_s, hexproof::protocol::kRolePlayer},
        {u"seat"_s, 0},
        {u"host"_s, true},
    };
    sendEnvelope(peers[2], resumed);
    Envelope restoredRoom = roomSnapshot(u"Restored room"_s, true, true);
    restoredRoom.seq = 8;
    restoredRoom.payload.insert(u"phase"_s, hexproof::protocol::kRoomPhaseStarted);
    sendEnvelope(peers[2], restoredRoom);

    Envelope restoredGame;
    restoredGame.type = hexproof::protocol::kTypeGameSnapshot;
    restoredGame.hasSeq = true;
    restoredGame.seq = 9;
    restoredGame.payload = QJsonObject{
        {u"roomId"_s, u"ABCDEF"_s},
        {u"gameNumber"_s, 1},
        {u"startingSeat"_s, 0},
        {u"activeSeat"_s, 0},
        {u"currentPhase"_s, hexproof::protocol::kGamePhaseUntap},
        {u"seats"_s,
         QJsonArray{
             QJsonObject{
                 {u"seat"_s, 0},
                 {u"displayName"_s, u"Alice"_s},
                 {u"life"_s, 20},
                 {u"libraryCount"_s, 52},
                 {u"handCount"_s, 1},
                 {u"hand"_s, QJsonArray{QJsonObject{
                                 {u"id"_s, u"alice-secret"_s},
                                 {u"name"_s, u"Lightning Bolt"_s},
                                 {u"setCode"_s, u"M11"_s},
                                 {u"collectorNumber"_s, u"149"_s},
                             }}},
                 {u"battlefield"_s, QJsonArray{}},
                 {u"graveyard"_s, QJsonArray{}},
                 {u"exile"_s, QJsonArray{}},
             },
             QJsonObject{
                 {u"seat"_s, 1},
                 {u"displayName"_s, u"Bob"_s},
                 {u"life"_s, 20},
                 {u"libraryCount"_s, 53},
                 {u"handCount"_s, 7},
                 {u"battlefield"_s, QJsonArray{}},
                 {u"graveyard"_s, QJsonArray{}},
                 {u"exile"_s, QJsonArray{}},
             },
         }},
        {u"stack"_s, QJsonArray{}},
        {u"revealed"_s, QJsonArray{}},
        {u"score"_s, QJsonArray{0, 0}},
        {u"log"_s, QJsonArray{}},
    };
    sendEnvelope(peers[2], restoredGame);

    QTRY_VERIFY_WITH_TIMEOUT(client.inRoom(), 1000);
    QTRY_COMPARE_WITH_TIMEOUT(client.roomName(), u"Restored room"_s, 1000);
    QTRY_VERIFY_WITH_TIMEOUT(client.gameSeats().size() == 2, 1000);
    QVERIFY(client.youAreHost());
    QCOMPARE(client.roomRole(), hexproof::protocol::kRolePlayer);
    QCOMPARE(client.seatIndex(), 0);
    QCOMPARE(client.gameSeats()
                 .first()
                 .toMap()
                 .value(u"hand"_s)
                 .toList()
                 .first()
                 .toMap()
                 .value(u"id"_s)
                 .toString(),
             u"alice-secret"_s);
    QVERIFY(client.gameSeats().last().toMap().value(u"hand"_s).toList().isEmpty());
}
