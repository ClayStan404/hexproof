// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"fmt"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestCubeExplicitSeatControlAndWithdrawalOverWebSocket(t *testing.T) {
	for _, eventType := range []string{protocol.LimitedEventCubeDraft, protocol.LimitedEventCommanderCube} {
		t.Run(eventType, func(t *testing.T) {
			config := DefaultConfig()
			config.MessagesPerSecond = 10000
			srv, _ := newConfiguredTestServer(t, config)
			peers := make([]*casualCubePeer, 4)
			for index := range peers {
				client := dial(t, srv)
				defer client.close()
				client.hello(fmt.Sprintf("Seat player %d", index))
				peers[index] = &casualCubePeer{client: client}
			}
			host, guest, withdrawn, viewer := peers[0], peers[1], peers[2], peers[3]
			command := func(actor *casualCubePeer, kind string, payload any, want string) {
				t.Helper()
				casualCubeCommand(t, peers, actor, kind, payload, want)
				if len(viewer.pool.FallbackCommanders) != 0 || len(viewer.pool.CommanderInstanceIDs) != 0 || len(viewer.pool.BasicLands) != 0 {
					t.Fatal("viewer received private seat-control construction data")
				}
				for _, participant := range viewer.event.Participants {
					if participant.Deck != nil {
						t.Fatal("running free-play pool was made public")
					}
				}
			}
			request := cubeRoomRequest(3)
			request.EventType = eventType
			if eventType == protocol.LimitedEventCommanderCube {
				request.DraftSettings = &protocol.LimitedDraftSettings{PacksPerPlayer: 3, PacksPerBatch: 1}
			}
			request.Product.Sheets[0].Cards[0].Weight = 180
			command(host, protocol.TypeTournamentCreate, request, protocol.TypeTournamentCreated)
			for _, peer := range peers[1:3] {
				command(peer, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: host.event.TournamentID}, protocol.TypeTournamentEntered)
			}
			command(viewer, protocol.TypeRoomJoin, protocol.RoomJoin{RoomID: host.event.TournamentID, AsSpectator: true}, protocol.TypeTournamentEntered)
			for _, peer := range peers[:3] {
				command(peer, protocol.TypeTournamentCheckIn, protocol.TournamentCheckIn{CheckedIn: true}, protocol.TypeTournamentCheckInSet)
			}
			command(host, protocol.TypeTournamentStart, protocol.EmptyPayload{}, protocol.TypeTournamentStarted)
			command(host, protocol.TypeLimitedSetDraftControl, protocol.LimitedSetDraftControl{ParticipantID: guest.event.ParticipantID, Automatic: true}, protocol.TypeError)
			command(viewer, protocol.TypeLimitedSetDraftControl, protocol.LimitedSetDraftControl{ParticipantID: guest.event.ParticipantID, Automatic: true}, protocol.TypeError)
			command(guest, protocol.TypeLimitedSetDraftControl, map[string]any{}, protocol.TypeError)
			command(guest, protocol.TypeLimitedSetDraftControl, map[string]any{"automatic": nil}, protocol.TypeError)
			command(withdrawn, protocol.TypeLimitedSetParticipation, protocol.LimitedSetParticipation{Participating: false}, protocol.TypeError)
			for _, peer := range peers[:3] {
				command(peer, protocol.TypeLimitedSetDraftControl, protocol.LimitedSetDraftControl{Automatic: true}, protocol.TypeLimitedDraftControlSet)
			}
			wantCount := 45
			if eventType == protocol.LimitedEventCommanderCube {
				wantCount = 60
			}
			for _, peer := range peers[:3] {
				if peer.pool.Stage != protocol.LimitedStageDeckBuilding || len(peer.pool.Pool) != wantCount || len(peer.pool.CurrentPack) != 0 {
					t.Fatal("automatic draft did not deliver the complete private pool")
				}
			}
			for _, seat := range viewer.pool.Participants {
				if !seat.AutoDraft || seat.Picked != wantCount {
					t.Fatal("public seat progress omitted explicit control status")
				}
			}
			command(withdrawn, protocol.TypeLimitedSetParticipation, map[string]any{}, protocol.TypeError)
			command(withdrawn, protocol.TypeLimitedSetParticipation, protocol.LimitedSetParticipation{Participating: false}, protocol.TypeLimitedParticipationSet)
			for _, peer := range peers[:2] {
				deck := protocol.LimitedSubmitDeck{Name: "Seat-control deck"}
				for _, card := range peer.pool.Pool[:23] {
					deck.MainboardInstanceIDs = append(deck.MainboardInstanceIDs, card.InstanceID)
				}
				basics := 17
				if eventType == protocol.LimitedEventCommanderCube {
					basics = 37
					deck.CommanderInstanceIDs = deck.MainboardInstanceIDs[:1]
				}
				deck.BasicLands = []protocol.LimitedBasicLand{{Name: "Island", Count: basics}}
				command(peer, protocol.TypeLimitedSubmitDeck, deck, protocol.TypeLimitedDeckSubmitted)
			}
			if host.event.Stage != protocol.LimitedStageCompetition || !host.pool.AllDecksSubmitted || len(withdrawn.pool.Pool) != wantCount {
				t.Fatal("explicit withdrawal did not release other builders or preserve its pool")
			}
			command(withdrawn, protocol.TypeLimitedSetParticipation, protocol.LimitedSetParticipation{Participating: true}, protocol.TypeError)
			command(host, protocol.TypeTournamentDrop, protocol.TournamentParticipantCommand{ParticipantID: guest.event.ParticipantID}, protocol.TypeError)
		})
	}
}
