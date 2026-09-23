// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
)

func TestForgeTerminalReviewRetainsPublicBoardWithoutEngine(t *testing.T) {
	h, err := NewHandlerWithConfig(DefaultConfig())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = h.Close() })
	host := &Session{ConnectionID: "host", DisplayName: "Alice", Send: make(chan []byte, 16)}
	observer := &Session{ConnectionID: "observer", DisplayName: "Observer", Send: make(chan []byte, 16)}
	r, _, _, entry, err := h.hub.CreateRoomWithRulesMode("Review",
		protocol.FormatModern, protocol.DeckFormatCustom, protocol.MatchBO1,
		protocol.CardLoadBackground, protocol.RulesModeForge, 2, true, false, "", host)
	if err != nil {
		t.Fatal(err)
	}
	r.Seats[1] = room.Seat{Occupied: true, DisplayName: "Bob", ConnectionID: "bob"}
	r.Spectators = []room.Spectator{{DisplayName: observer.DisplayName, ConnectionID: observer.ConnectionID}}
	r.Phase = protocol.RoomPhaseStarted
	entry.opMu.Unlock()
	for _, sess := range []*Session{host, observer} {
		sess.setRoom(r)
		h.sessions[sess.ConnectionID] = sess
	}
	game := forgeRoomGame{gameID: "ended", playerToSeat: map[int]int{0: 0, 1: 1}}
	view := forge.GameView{GameID: "ended", ActivePlayerID: "player-0", PriorityPlayerID: "player-1",
		GameOver: true, WinnerID: "player-1", Players: []forge.PlayerView{{ID: "player-0"}, {ID: "player-1"}},
		Zones: []forge.ZoneView{
			{Zone: "battlefield", OwnerID: "player-0", Count: 1, Cards: []forge.CardView{
				{ID: "public-card", Visibility: "visible", Identity: &forge.CardIdentityView{Name: "Forest"}},
			}},
			{Zone: "graveyard", OwnerID: "player-1", Count: 1, Cards: []forge.CardView{
				{ID: "known-spell", Visibility: "visible", Identity: &forge.CardIdentityView{Name: "Lightning Bolt"}},
			}},
			{Zone: "hand", OwnerID: "player-1", Count: 1, Cards: []forge.CardView{
				{ID: "hidden-card", Visibility: "hidden", Identity: &forge.CardIdentityView{Name: "SECRET HAND"}},
			}},
		}}
	public, err := normalizeForgeSnapshot(r.ID, game, view)
	if err != nil {
		t.Fatal(err)
	}
	h.hub.UpdateRulesPublicLog(r, public)
	// Later viewer processing cannot rewrite the stored public publication.
	public.Zones[0].Cards[0].Identity.Name = "SECRET MUTATION"
	if _, err := h.hub.CompleteRulesGame(r, 1); err != nil {
		t.Fatal(err)
	}
	for range 2 { // Repeated fanout models a cold reconnect after engine exit.
		h.fanoutGameProjections(r)
		for _, sess := range []*Session{host, observer} {
			messages := receiveForgeSessionEnvelopes(t, sess, 2)
			if messages[0].Type != protocol.TypeGameSnapshot || messages[1].Type != protocol.TypeRulesSnapshot {
				t.Fatalf("missing match metadata or retained public board: %v", envelopeTypes(messages))
			}
			raw := string(messages[1].Payload)
			if strings.Contains(raw, "SECRET") || !strings.Contains(raw, "Forest") || !strings.Contains(raw, "Lightning Bolt") {
				t.Fatalf("incorrect public review: %s", raw)
			}
			if messages[1].SeqValue() <= messages[0].SeqValue() {
				t.Fatal("review publication did not follow metadata sequence")
			}
		}
	}
	if len(h.forgeClients) != 0 || len(h.forgeGames) != 0 {
		t.Fatal("board review started an engine")
	}
	// Room reuse cannot replay the previous game's board.
	r.ResetRulesLog()
	if _, ok := h.hub.RulesReviewProjection(r, time.Now().Unix()); ok {
		t.Fatal("old review survived a new match")
	}
}
