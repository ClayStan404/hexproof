// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/tournament"
)

func projectionTestEvent(t *testing.T, h *Handler, id, kind string, players int, start bool) *tournament.Tournament {
	t.Helper()
	config := tournament.Config{Name: "Review event", Format: "Modern", MatchMode: "bo3", RoundMinutes: 50, MaxPlayers: max(players, 4)}
	if kind != "" {
		cards := make([]protocol.LimitedCardDefinition, 60)
		for i := range cards {
			cards[i] = protocol.LimitedCardDefinition{Name: fmt.Sprintf("Review private creature %d", i+1), SetCode: "TST", CollectorNumber: fmt.Sprint(i + 1), TypeLine: "Creature — Human Wizard", Rarity: "common", Finish: "nonfoil", Weight: 1}
		}
		config.Format, config.EventType = "Limited", kind
		config.Product = &protocol.LimitedProductDefinition{
			ID: "review-draft", Name: "Review Draft Booster", SetCode: "TST", ProductType: "official", Authentic: true, CardsPerPack: 15,
			Sheets:   []protocol.LimitedSheetDefinition{{Name: "main", Cards: cards}},
			Variants: []protocol.LimitedPackVariantDefinition{{Weight: 1, Slots: []protocol.LimitedSlotDefinition{{Sheet: "main", Count: 15}}}},
		}
	}
	event, err := tournament.New(id, config, "Review organizer", "owner-"+id, tournament.CredentialHash("owner-token"), time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if _, err = h.tournaments.create(event); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < players; i++ {
		participant, err := event.Register(fmt.Sprintf("Player %d", i+1), fmt.Sprintf("%s-player-%d", id, i+1), tournament.CredentialHash(fmt.Sprintf("%s-token-%d", id, i+1)), time.Now())
		if err != nil {
			t.Fatal(err)
		}
		participant.CheckedIn = true
	}
	if start {
		if err := event.Start(tournament.Actor{ConnectionID: "owner-" + id, Role: tournament.RoleOrganizer}, 42, time.Now()); err != nil {
			t.Fatal(err)
		}
	}
	return event
}

func TestFanoutCrossEventPrivacy(t *testing.T) {
	h := NewHandler()
	old := projectionTestEvent(t, h, "OLD12345", protocol.LimitedEventSetSealed, 2, true)
	next := projectionTestEvent(t, h, "NEW12345", "", 2, false)
	viewers := make([]*Session, 2)
	for i := range viewers {
		viewers[i] = &Session{ConnectionID: fmt.Sprintf("viewer-%d", i), DisplayName: fmt.Sprintf("Viewer %d", i), Send: make(chan []byte, 64)}
		viewers[i].setTournament(tournamentBinding{TournamentID: old.ID, Role: tournament.RoleViewer})
		h.registerSession(viewers[i])
	}
	switched := false
	// Pause old-event fanout at its first serialization boundary. Other
	// connections may legitimately enter another event at this point.
	h.marshalEnvelope = func(env protocol.Envelope) ([]byte, error) {
		if !switched && env.Type == protocol.TypeTournamentSnapshot {
			switched = true
			for i, sess := range viewers {
				enter, _ := protocol.NewEnvelope(protocol.TypeTournamentEnter, protocol.TournamentEnter{TournamentID: next.ID, Credential: fmt.Sprintf("%s-token-%d", next.ID, i+1)})
				if err := h.handleTournamentEnter(sess, enter); err != nil {
					t.Fatal(err)
				}
				if sess.Tournament().TournamentID != next.ID {
					t.Fatal("legitimate event entry failed")
				}
			}
		}
		return env.Marshal()
	}
	h.fanoutTournament(old.ID)
	for _, sess := range viewers {
		for len(sess.Send) > 0 {
			env, err := protocol.ParseEnvelope(<-sess.Send)
			if err != nil {
				t.Fatal(err)
			}
			if env.Type != protocol.TypeLimitedSnapshot {
				continue
			}
			var snapshot protocol.LimitedSnapshot
			if err := env.DecodePayload(&snapshot); err != nil {
				t.Fatal(err)
			}
			if snapshot.TournamentID == old.ID && len(snapshot.Pool) > 0 {
				t.Errorf("PRIVACY: old-event viewer %s received %d private cards after switching to %s as %s; first=%s", sess.ConnectionID, len(snapshot.Pool), next.ID, sess.Tournament().ParticipantID, snapshot.Pool[0].Name)
			}
		}
	}
}

func TestDraftPickWireBudget(t *testing.T) {
	h := NewHandler()
	event := projectionTestEvent(t, h, "DRAFT123", protocol.LimitedEventSetDraft, 8, true)
	sessions := make([]*Session, len(event.Participants))
	for i, participant := range event.Participants {
		sess := &Session{ConnectionID: participant.ConnectionID, DisplayName: participant.DisplayName, Send: make(chan []byte, 64)}
		sess.setTournament(tournamentBinding{TournamentID: event.ID, Role: tournament.RoleParticipant, ParticipantID: participant.ID})
		sessions[i] = sess
		h.registerSession(sess)
	}
	h.fanoutTournament(event.ID)
	for _, sess := range sessions {
		for len(sess.Send) > 0 {
			<-sess.Send
		}
	}
	total, peak, unchangedPrivate, messages := 0, 0, 0, 0
	for pick := 0; pick < 42; pick++ {
		roundBytes := 0
		for _, actor := range sessions {
			previous := make(map[*Session]string)
			for _, sess := range sessions {
				snap := event.LimitedSnapshot(sess.Tournament().ParticipantID)
				state, _ := json.Marshal([]any{snap.CurrentPack, snap.Pool})
				previous[sess] = string(state)
			}
			snap := event.LimitedSnapshot(actor.Tournament().ParticipantID)
			if len(snap.CurrentPack) == 0 {
				t.Fatalf("unexpected empty pack at pick %d", pick)
			}
			request, _ := protocol.NewEnvelope(protocol.TypeLimitedPick, protocol.LimitedPick{InstanceID: snap.CurrentPack[0].InstanceID})
			if err := h.handleLimitedPick(actor, request); err != nil {
				t.Fatal(err)
			}
			for _, sess := range sessions {
				for len(sess.Send) > 0 {
					bytes := <-sess.Send
					roundBytes += len(bytes)
					messages++
					envelope, _ := protocol.ParseEnvelope(bytes)
					if envelope.Type == protocol.TypeError {
						t.Fatalf("pick failed: %s", bytes)
					}
					if envelope.Type == protocol.TypeLimitedSnapshot {
						var updated protocol.LimitedSnapshot
						_ = envelope.DecodePayload(&updated)
						state, _ := json.Marshal([]any{updated.CurrentPack, updated.Pool})
						if previous[sess] == string(state) {
							unchangedPrivate++
						}
					}
				}
			}
		}
		total += roundBytes
		if roundBytes > peak {
			peak = roundBytes
		}
	}
	if total > 8*1024*1024 || peak > 250000 {
		t.Errorf("redundant draft fanout: total=%d peak=%d", total, peak)
	}
	if unchangedPrivate > 8 {
		t.Errorf("unchanged private snapshots = %d", unchangedPrivate)
	}
	if event.Stage != protocol.LimitedStageDeckBuilding {
		t.Fatal("draft did not reach deck construction")
	}
	t.Logf("8 players x 42 manual picks + 24 automatic last picks: %d bytes (%.2f MiB), %d messages; unchanged private snapshots=%d/2688; largest 8-pick burst=%d bytes (%.2fs at 3,000,000 bits/s, JSON only)", total, float64(total)/1048576, messages, unchangedPrivate, peak, float64(peak)*8/3000000)
}

func drainProjection(t *testing.T, sess *Session) []protocol.Envelope {
	t.Helper()
	var envelopes []protocol.Envelope
	for len(sess.Send) > 0 {
		env, err := protocol.ParseEnvelope(<-sess.Send)
		if err != nil {
			t.Fatal(err)
		}
		envelopes = append(envelopes, env)
	}
	return envelopes
}

func TestFanoutPrivateOwnershipLifecycle(t *testing.T) {
	for _, mode := range []string{"participant", "organizer", "organizer-transferred-seat", "viewer", "revoked", "aba", "transfer-during-serialization"} {
		t.Run(mode, func(t *testing.T) {
			h := NewHandler()
			event := projectionTestEvent(t, h, "PRIVATE1", protocol.LimitedEventSetSealed, 2, true)
			player := event.Participants[0]
			sess := &Session{ConnectionID: player.ConnectionID, DisplayName: player.DisplayName, Send: make(chan []byte, 64)}
			binding := tournamentBinding{TournamentID: event.ID, Role: tournament.RoleParticipant, ParticipantID: player.ID}
			switch mode {
			case "organizer", "organizer-transferred-seat":
				binding.Role = tournament.RoleOrganizer
				event.OrganizerConnectionID = sess.ConnectionID
				event.OrganizerParticipantID = player.ID
			case "viewer":
				binding.Role, binding.ParticipantID = tournament.RoleViewer, ""
			}
			sess.setTournament(binding)
			h.registerSession(sess)
			transfer := func() {
				_, _, ok := event.BindCredential(player.CredentialHash, "replacement", time.Now())
				if !ok {
					t.Fatal("credential transfer failed")
				}
			}
			switch mode {
			case "revoked", "organizer-transferred-seat":
				transfer()
			case "aba", "transfer-during-serialization":
				changed := false
				h.marshalEnvelope = func(env protocol.Envelope) ([]byte, error) {
					if !changed && env.Type == protocol.TypeLimitedSnapshot {
						changed = true
						if mode == "aba" {
							sess.clearTournament()
							sess.setTournament(binding)
						} else {
							transfer()
						}
					}
					return env.Marshal()
				}
			}
			h.fanoutTournament(event.ID)
			found := false
			for _, env := range drainProjection(t, sess) {
				if env.Type != protocol.TypeLimitedSnapshot {
					continue
				}
				found = true
				var snapshot protocol.LimitedSnapshot
				if err := env.DecodePayload(&snapshot); err != nil {
					t.Fatal(err)
				}
				if mode == "participant" || mode == "organizer" {
					if len(snapshot.Pool) != 90 {
						t.Fatalf("owner lost pool: %d", len(snapshot.Pool))
					}
				} else if len(snapshot.Pool) != 0 || len(snapshot.CurrentPack) != 0 ||
					len(snapshot.MainboardInstanceIDs) != 0 || len(snapshot.BasicLands) != 0 || snapshot.DeckSubmitted {
					t.Fatal("non-owner received private Limited state")
				}
			}
			if (mode == "participant" || mode == "organizer" || mode == "viewer" || mode == "organizer-transferred-seat") && !found {
				t.Fatal("legitimate projection was not sent")
			}
			if (mode == "aba" || mode == "transfer-during-serialization") && found {
				t.Fatal("projection outlived its membership authorization")
			}
		})
	}
}

func TestRevokedParticipantCannotOpenExistingPairing(t *testing.T) {
	h := NewHandler()
	event := projectionTestEvent(t, h, "PAIRING1", "", 4, true)
	pairing := event.CurrentPairing(event.Participants[0].ID)
	left := event.Participant(pairing.PlayerAID)
	right := event.Participant(pairing.PlayerBID)
	session := func(player *tournament.Participant) *Session {
		sess := &Session{ConnectionID: player.ConnectionID, DisplayName: player.DisplayName, Send: make(chan []byte, 64)}
		sess.setTournament(tournamentBinding{TournamentID: event.ID, Role: tournament.RoleParticipant, ParticipantID: player.ID})
		h.registerSession(sess)
		return sess
	}
	first, revoked := session(left), session(right)
	open, _ := protocol.NewEnvelope(protocol.TypeTournamentOpenMatch, protocol.TournamentPairingCommand{PairingID: pairing.ID})
	if err := h.handleTournamentOpenMatch(first, open); err != nil {
		t.Fatal(err)
	}
	if first.Room() == nil {
		t.Fatal("legitimate participant could not create pairing room")
	}
	if _, _, ok := event.BindCredential(right.CredentialHash, "replacement", time.Now()); !ok {
		t.Fatal("rebind failed")
	}
	drainProjection(t, revoked)
	if err := h.handleTournamentOpenMatch(revoked, open); err != nil {
		t.Fatal(err)
	}
	if revoked.Room() != nil {
		t.Fatal("revoked connection entered pairing room")
	}
	replies := drainProjection(t, revoked)
	if len(replies) != 1 || replies[0].Type != protocol.TypeError {
		t.Fatal("expected forbidden reply")
	}
	var failure protocol.ErrorPayload
	if err := replies[0].DecodePayload(&failure); err != nil {
		t.Fatal(err)
	}
	if failure.Code != protocol.ErrTournamentForbidden {
		t.Fatalf("wrong error: %s", failure.Code)
	}
}

func TestOrganizerCannotUseTransferredLimitedSeat(t *testing.T) {
	for _, kind := range []string{protocol.LimitedEventSetDraft, protocol.LimitedEventSetSealed} {
		t.Run(kind, func(t *testing.T) {
			h := NewHandler()
			event := projectionTestEvent(t, h, "OWNER123", kind, 2, true)
			player := event.Participants[0]
			event.OrganizerConnectionID = player.ConnectionID
			event.OrganizerParticipantID = player.ID
			organizer := tournament.Actor{ConnectionID: player.ConnectionID, Role: tournament.RoleOrganizer, ParticipantID: player.ID}
			if _, _, ok := event.BindCredential(player.CredentialHash, "replacement", time.Now()); !ok {
				t.Fatal("seat transfer failed")
			}
			owner := tournament.Actor{ConnectionID: "replacement", Role: tournament.RoleParticipant, ParticipantID: player.ID}
			snapshot := event.LimitedSnapshot(player.ID)
			var rejected, accepted error
			if kind == protocol.LimitedEventSetDraft {
				_, rejected = event.PickLimited(organizer, snapshot.CurrentPack[0].InstanceID)
				_, accepted = event.PickLimited(owner, snapshot.CurrentPack[0].InstanceID)
			} else {
				request := protocol.LimitedSubmitDeck{Name: "Transferred seat deck"}
				for _, card := range snapshot.Pool[:40] {
					request.MainboardInstanceIDs = append(request.MainboardInstanceIDs, card.InstanceID)
				}
				_, rejected = event.SubmitLimitedDeck(organizer, request)
				_, accepted = event.SubmitLimitedDeck(owner, request)
			}
			if tournament.ErrorCode(rejected) != tournament.ErrForbidden {
				t.Errorf("transferred organizer seat was not rejected: %v", rejected)
			}
			if accepted != nil {
				t.Errorf("current participant lost legitimate seat action: %v", accepted)
			}
			if err := event.Cancel(organizer, time.Now()); err != nil {
				t.Errorf("organizer lost legitimate event control: %v", err)
			}
		})
	}
}
