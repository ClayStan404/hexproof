// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func sendTournamentCommand(t *testing.T, client *wsClient, messageType, id string,
	payload any) {
	t.Helper()
	envelope, err := protocol.NewEnvelope(messageType, payload)
	if err != nil {
		t.Fatalf("new %s: %v", messageType, err)
	}
	envelope.ID = id
	client.send(envelope)
}

func receiveTournamentSnapshot(t *testing.T, client *wsClient) protocol.TournamentSnapshot {
	t.Helper()
	envelope := client.recvType(protocol.TypeTournamentSnapshot)
	var snapshot protocol.TournamentSnapshot
	if err := envelope.DecodePayload(&snapshot); err != nil {
		t.Fatalf("decode tournament snapshot: %v", err)
	}
	return snapshot
}

func drainTournamentSnapshots(t *testing.T, clients ...*wsClient) []protocol.TournamentSnapshot {
	t.Helper()
	snapshots := make([]protocol.TournamentSnapshot, 0, len(clients))
	for _, client := range clients {
		snapshots = append(snapshots, receiveTournamentSnapshot(t, client))
	}
	return snapshots
}

func TestTournamentRegistrationPairingResultsAndPrivateMatchRoom(t *testing.T) {
	server, _ := newTestServer(t)
	organizer := dial(t, server)
	defer organizer.close()
	organizer.hello("Judge")

	sendTournamentCommand(t, organizer, protocol.TypeTournamentCreate, "create-tournament",
		protocol.TournamentCreate{
			Name: "Friday Swiss", Format: protocol.FormatModern,
			MatchMode: protocol.MatchBO3, RoundMinutes: 50, MaxPlayers: 16,
		})
	createdEnvelope := organizer.recvType(protocol.TypeTournamentCreated)
	var created protocol.TournamentCreated
	if err := createdEnvelope.DecodePayload(&created); err != nil {
		t.Fatalf("decode tournament.created: %v", err)
	}
	if created.TournamentID == "" || created.OrganizerToken == "" {
		t.Fatalf("created = %+v", created)
	}
	boundClients := []*wsClient{organizer}
	drainTournamentSnapshots(t, boundClients...)

	players := make([]*wsClient, 0, 4)
	clientByParticipant := make(map[string]*wsClient)
	tokenByParticipant := make(map[string]string)
	for index, name := range []string{"Alice", "Bob", "Carol", "Dave"} {
		client := dial(t, server)
		defer client.close()
		client.hello(name)
		sendTournamentCommand(t, client, protocol.TypeTournamentEnter,
			"enter-"+name, protocol.TournamentEnter{TournamentID: created.TournamentID})
		client.recvType(protocol.TypeTournamentEntered)
		boundClients = append(boundClients, client)
		drainTournamentSnapshots(t, boundClients...)

		sendTournamentCommand(t, client, protocol.TypeTournamentRegister,
			"register-"+name,
			protocol.TournamentRegister{TournamentID: created.TournamentID})
		registeredEnvelope := client.recvType(protocol.TypeTournamentRegistered)
		var registered protocol.TournamentRegistered
		if err := registeredEnvelope.DecodePayload(&registered); err != nil {
			t.Fatalf("decode registered player %d: %v", index, err)
		}
		if registered.ParticipantToken == "" {
			t.Fatalf("player %d received empty participant credential", index)
		}
		clientByParticipant[registered.ParticipantID] = client
		tokenByParticipant[registered.ParticipantID] = registered.ParticipantToken
		drainTournamentSnapshots(t, boundClients...)

		sendTournamentCommand(t, client, protocol.TypeTournamentCheckIn,
			"check-in-"+name, protocol.TournamentCheckIn{CheckedIn: true})
		client.recvType(protocol.TypeTournamentCheckInSet)
		drainTournamentSnapshots(t, boundClients...)
		players = append(players, client)
	}

	sendTournamentCommand(t, organizer, protocol.TypeTournamentStart, "start-tournament",
		protocol.EmptyPayload{})
	organizer.recvType(protocol.TypeTournamentStarted)
	snapshots := drainTournamentSnapshots(t, boundClients...)
	organizerSnapshot := snapshots[0]
	if organizerSnapshot.Status != "running" || organizerSnapshot.CurrentRound != 1 ||
		organizerSnapshot.PlannedRounds != 3 || len(organizerSnapshot.Pairings) != 2 ||
		len(organizerSnapshot.Standings) != 4 {
		t.Fatalf("started snapshot = %+v", organizerSnapshot)
	}

	firstPairing := organizerSnapshot.Pairings[0]
	firstPlayer := clientByParticipant[firstPairing.PlayerAID]
	secondPlayer := clientByParticipant[firstPairing.PlayerBID]
	if firstPlayer == nil || secondPlayer == nil {
		t.Fatalf("pairing references unknown players: %+v", firstPairing)
	}
	sendTournamentCommand(t, firstPlayer, protocol.TypeTournamentOpenMatch, "open-match-a",
		protocol.TournamentPairingCommand{PairingID: firstPairing.PairingID})
	openedEnvelope := firstPlayer.recvType(protocol.TypeTournamentMatchOpened)
	var opened protocol.TournamentMatchOpened
	if err := openedEnvelope.DecodePayload(&opened); err != nil {
		t.Fatalf("decode first match open: %v", err)
	}
	firstPlayer.recvType(protocol.TypeRoomCreated)
	firstPlayer.recvType(protocol.TypeRoomSnapshot)
	if opened.RoomID == "" {
		t.Fatal("pairing room id is empty")
	}
	drainTournamentSnapshots(t, boundClients...)

	// Rebinding the first player's tournament credential must not let the new
	// connection occupy the second seat in the same pairing room.
	reboundFirstPlayer := dial(t, server)
	reboundFirstPlayer.hello("Alice rebound")
	sendTournamentCommand(t, reboundFirstPlayer, protocol.TypeTournamentEnter,
		"rebind-first-player", protocol.TournamentEnter{
			TournamentID: created.TournamentID,
			Credential:   tokenByParticipant[firstPairing.PlayerAID],
		})
	reboundFirstPlayer.recvType(protocol.TypeTournamentEntered)
	drainTournamentSnapshots(t, append(boundClients, reboundFirstPlayer)...)
	sendTournamentCommand(t, reboundFirstPlayer, protocol.TypeTournamentOpenMatch,
		"duplicate-seat", protocol.TournamentPairingCommand{PairingID: firstPairing.PairingID})
	duplicateSeatError := reboundFirstPlayer.recvType(protocol.TypeError)
	var duplicateSeatPayload protocol.ErrorPayload
	if err := duplicateSeatError.DecodePayload(&duplicateSeatPayload); err != nil {
		t.Fatalf("decode duplicate-seat error: %v", err)
	}
	if duplicateSeatPayload.Code != protocol.ErrAlreadyInRoom {
		t.Fatalf("duplicate participant seat code = %q, want %q",
			duplicateSeatPayload.Code, protocol.ErrAlreadyInRoom)
	}

	// Restore the tournament role to the original connection so the remainder
	// of this full-flow test continues with the original player objects.
	sendTournamentCommand(t, firstPlayer, protocol.TypeTournamentEnter,
		"restore-first-player", protocol.TournamentEnter{
			TournamentID: created.TournamentID,
			Credential:   tokenByParticipant[firstPairing.PlayerAID],
		})
	firstPlayer.recvType(protocol.TypeTournamentEntered)
	drainTournamentSnapshots(t, append(boundClients, reboundFirstPlayer)...)
	reboundFirstPlayer.close()

	// Pairing rooms must not leak into the ordinary public room browser.
	browser := dial(t, server)
	defer browser.close()
	browser.hello("Browser")
	sendTournamentCommand(t, browser, protocol.TypeRoomList, "list-rooms",
		protocol.EmptyPayload{})
	roomListEnvelope := browser.recvType(protocol.TypeRoomListed)
	var roomList protocol.RoomListed
	if err := roomListEnvelope.DecodePayload(&roomList); err != nil {
		t.Fatalf("decode room list: %v", err)
	}
	if len(roomList.Rooms) != 0 {
		t.Fatalf("tournament room leaked into room list: %+v", roomList.Rooms)
	}

	// Knowing the pairing room id, including from a tournament snapshot, must
	// not admit a viewer through the public room.join path.
	sendTournamentCommand(t, browser, protocol.TypeRoomJoin, "join-pairing-room",
		protocol.RoomJoin{RoomID: opened.RoomID})
	joinError := browser.recvType(protocol.TypeError)
	var joinPayload protocol.ErrorPayload
	if err := joinError.DecodePayload(&joinPayload); err != nil {
		t.Fatalf("decode pairing-room join error: %v", err)
	}
	if joinPayload.Code != protocol.ErrTournamentForbidden {
		t.Fatalf("room.join pairing room code = %q, want %q",
			joinPayload.Code, protocol.ErrTournamentForbidden)
	}

	sendTournamentCommand(t, secondPlayer, protocol.TypeTournamentOpenMatch, "open-match-b",
		protocol.TournamentPairingCommand{PairingID: firstPairing.PairingID})
	joinedOpenEnvelope := secondPlayer.recvType(protocol.TypeTournamentMatchOpened)
	var joinedOpen protocol.TournamentMatchOpened
	_ = joinedOpenEnvelope.DecodePayload(&joinedOpen)
	if joinedOpen.RoomID != opened.RoomID {
		t.Fatalf("players opened different rooms: %q vs %q", opened.RoomID, joinedOpen.RoomID)
	}
	secondPlayer.recvType(protocol.TypeRoomJoined)
	secondPlayer.recvType(protocol.TypeRoomSnapshot)
	drainTournamentSnapshots(t, boundClients...)

	// Both pairings report and mutually confirm official game scores.
	for index, pairing := range organizerSnapshot.Pairings {
		left := clientByParticipant[pairing.PlayerAID]
		right := clientByParticipant[pairing.PlayerBID]
		sendTournamentCommand(t, left, protocol.TypeTournamentReportResult,
			"report-result", protocol.TournamentResultCommand{
				PairingID: pairing.PairingID, PlayerAWins: 2, PlayerBWins: index,
			})
		left.recvType(protocol.TypeTournamentResultReported)
		drainTournamentSnapshots(t, boundClients...)
		sendTournamentCommand(t, right, protocol.TypeTournamentConfirmResult,
			"confirm-result", protocol.TournamentPairingCommand{PairingID: pairing.PairingID})
		right.recvType(protocol.TypeTournamentResultConfirmed)
		snapshots = drainTournamentSnapshots(t, boundClients...)
	}
	if !snapshots[0].RoundComplete || snapshots[0].Standings[0].MatchPoints != 3 {
		t.Fatalf("completed round standings = %+v", snapshots[0])
	}

	sendTournamentCommand(t, organizer, protocol.TypeTournamentNextRound, "next-round",
		protocol.EmptyPayload{})
	organizer.recvType(protocol.TypeTournamentRoundStarted)
	snapshots = drainTournamentSnapshots(t, boundClients...)
	if snapshots[0].CurrentRound != 2 || len(snapshots[0].Pairings) != 2 {
		t.Fatalf("round two snapshot = %+v", snapshots[0])
	}

	// Public discovery contains counts but no credential or participant identity.
	sendTournamentCommand(t, browser, protocol.TypeTournamentList, "list-tournaments",
		protocol.EmptyPayload{})
	listedEnvelope := browser.recvType(protocol.TypeTournamentListed)
	var listed protocol.TournamentListed
	if err := listedEnvelope.DecodePayload(&listed); err != nil {
		t.Fatalf("decode tournament list: %v", err)
	}
	if len(listed.Tournaments) != 1 || listed.Tournaments[0].Registered != 4 {
		t.Fatalf("tournament list = %+v", listed.Tournaments)
	}
	raw := string(listedEnvelope.Payload)
	if strings.Contains(raw, "Alice") || strings.Contains(raw, "participantToken") ||
		strings.Contains(raw, created.OrganizerToken) {
		t.Fatalf("public tournament list leaked private data: %s", raw)
	}
}
