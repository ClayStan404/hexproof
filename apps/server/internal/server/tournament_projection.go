// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/tournament"
)

func (h *Handler) clearTournamentParticipantBindings(tournamentID, participantID string) {
	h.sessionsMu.RLock()
	sessions := make([]*Session, 0)
	for _, sess := range h.sessions {
		binding := sess.Tournament()
		if binding.TournamentID == tournamentID && binding.ParticipantID == participantID {
			sessions = append(sessions, sess)
		}
	}
	h.sessionsMu.RUnlock()
	for _, sess := range sessions {
		binding := sess.Tournament()
		if binding.TournamentID != tournamentID || binding.ParticipantID != participantID {
			continue
		}
		binding.ParticipantID = ""
		if binding.Role == tournament.RoleParticipant {
			binding.Role = tournament.RoleViewer
		}
		sess.setTournament(binding)
	}
}

func (h *Handler) recordTournamentDeck(sess *Session, r *room.Room,
	deck protocol.DeckSelect) {
	tournamentID := h.hub.TournamentForRoom(r)
	binding := sess.Tournament()
	if tournamentID == "" || binding.TournamentID != tournamentID ||
		binding.ParticipantID == "" {
		return
	}
	entry := h.tournaments.entry(tournamentID)
	if entry == nil {
		return
	}
	entry.mu.Lock()
	entry.event.RecordDeck(tournamentActor(sess), deck)
	entry.mu.Unlock()
}

func (h *Handler) detachTournamentSession(sess *Session) {
	previous := sess.clearTournament()
	if previous.TournamentID == "" {
		return
	}
	entry := h.tournaments.entry(previous.TournamentID)
	if entry == nil {
		return
	}
	entry.mu.Lock()
	entry.event.Disconnect(sess.ConnectionID, time.Now().UTC())
	entry.mu.Unlock()
}

func (h *Handler) disconnectTournamentSession(sess *Session) {
	binding := sess.Tournament()
	if binding.TournamentID == "" {
		return
	}
	entry := h.tournaments.entry(binding.TournamentID)
	if entry == nil {
		return
	}
	entry.mu.Lock()
	entry.event.Disconnect(sess.ConnectionID, time.Now().UTC())
	entry.mu.Unlock()
}

func (h *Handler) fanoutTournament(tournamentID string) {
	h.sessionsMu.RLock()
	members := make([]*Session, 0)
	for _, sess := range h.sessions {
		if sess.Tournament().TournamentID == tournamentID {
			members = append(members, sess)
		}
	}
	h.sessionsMu.RUnlock()
	entry := h.tournaments.entry(tournamentID)
	if entry == nil {
		return
	}
	for _, sess := range members {
		binding := sess.Tournament()
		entry.mu.Lock()
		snapshot := tournamentSnapshot(entry.event, binding)
		entry.mu.Unlock()
		envelope, _ := protocol.NewEnvelope(protocol.TypeTournamentSnapshot, snapshot)
		h.send(sess, envelope)
		entry.mu.Lock()
		limitedSnapshot := entry.event.LimitedSnapshot(binding.ParticipantID)
		entry.mu.Unlock()
		if limitedSnapshot != nil {
			limitedEnvelope, _ := protocol.NewEnvelope(
				protocol.TypeLimitedSnapshot, *limitedSnapshot)
			h.send(sess, limitedEnvelope)
		}
	}
}

func tournamentSnapshot(event *tournament.Tournament,
	binding tournamentBinding) protocol.TournamentSnapshot {
	checkedIn := 0
	participants := make([]protocol.TournamentParticipantView, 0, len(event.Participants))
	for _, participant := range event.Participants {
		if participant.CheckedIn {
			checkedIn++
		}
		participantView := protocol.TournamentParticipantView{
			ParticipantID: participant.ID, DisplayName: participant.DisplayName,
			CheckedIn: participant.CheckedIn, Competing: participant.Competing,
			Dropped: participant.Dropped, Online: participant.ConnectionID != "",
		}
		if event.Status == tournament.StatusCompleted && participant.Deck != nil {
			deck := tournamentDeckView(*participant.Deck)
			participantView.Deck = &deck
		}
		participants = append(participants, participantView)
	}

	pairings := make([]protocol.TournamentPairingView, 0)
	visiblePairings := event.VisiblePairings()
	if len(visiblePairings) > 0 {
		pairings = make([]protocol.TournamentPairingView, 0, len(visiblePairings))
		for _, pairing := range visiblePairings {
			view := protocol.TournamentPairingView{
				PairingID: pairing.ID, Table: pairing.Table,
				PlayerAID:   pairing.PlayerAID,
				PlayerAName: event.Participant(pairing.PlayerAID).DisplayName,
				Bye:         pairing.Bye(), RoomID: pairing.RoomID, Status: "open",
			}
			if pairing.PlayerBID != "" {
				view.PlayerBID = pairing.PlayerBID
				view.PlayerBName = event.Participant(pairing.PlayerBID).DisplayName
			}
			if pairing.Pending != nil {
				view.Status = "reported"
				view.PlayerAWins = pairing.Pending.Score.PlayerAWins
				view.PlayerBWins = pairing.Pending.Score.PlayerBWins
				view.DrawnGames = pairing.Pending.Score.DrawnGames
				view.ReporterID = pairing.Pending.ReporterID
			}
			if pairing.Result != nil {
				view.Status = "confirmed"
				view.PlayerAWins = pairing.Result.Score.PlayerAWins
				view.PlayerBWins = pairing.Result.Score.PlayerBWins
				view.DrawnGames = pairing.Result.Score.DrawnGames
				view.Corrected = pairing.Result.Corrected
			}
			pairings = append(pairings, view)
		}
	}

	standings := event.Standings()
	standingViews := make([]protocol.TournamentStandingView, 0, len(standings))
	for _, standing := range standings {
		standingViews = append(standingViews, protocol.TournamentStandingView{
			Rank: standing.Rank, ParticipantID: standing.ParticipantID,
			DisplayName: standing.DisplayName, Wins: standing.Wins,
			Losses: standing.Losses, Draws: standing.Draws,
			MatchPoints: standing.MatchPoints, OppMatchWin: standing.OppMatchWin,
			GameWin: standing.GameWin, OppGameWin: standing.OppGameWin,
			Byes: standing.Byes, Dropped: standing.Dropped,
		})
	}
	roundStartedAt := ""
	if round := event.CurrentRound(); round != nil {
		roundStartedAt = round.StartedAt.UTC().Format(time.RFC3339)
	}
	return protocol.TournamentSnapshot{
		TournamentID: event.ID, Name: event.Name, Format: event.Format,
		EventType: event.EventType, Coordinator: event.Coordinator, Stage: event.Stage,
		MatchMode: event.MatchMode, Status: event.Status,
		RoundMinutes: event.RoundMinutes, RoundStartedAt: roundStartedAt,
		MaxPlayers:    event.MaxPlayers,
		PlannedRounds: event.PlannedRounds, CurrentRound: len(event.Rounds),
		Registered: len(event.Participants), CheckedIn: checkedIn,
		RoundComplete: event.RoundComplete(), OrganizerName: event.OrganizerName,
		Role: binding.Role, ParticipantID: binding.ParticipantID,
		CanRegister: event.Status == tournament.StatusRegistration &&
			binding.ParticipantID == "" && len(event.Participants) < event.MaxPlayers,
		Participants: participants, Pairings: pairings, Standings: standingViews,
	}
}

func tournamentDeckView(deck protocol.DeckSelect) protocol.TournamentDeckView {
	return protocol.TournamentDeckView{
		Name: deck.Name, Format: deck.Format, Commander: deck.Commander,
		Commanders: append([]string(nil), deck.Commanders...),
		Mainboard:  append([]protocol.DeckCard(nil), deck.Mainboard...),
		Sideboard:  append([]protocol.DeckCard(nil), deck.Sideboard...),
	}
}
