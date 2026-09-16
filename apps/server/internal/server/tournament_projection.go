// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"reflect"
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
		sess.tournamentMu.Lock()
		binding := sess.tournament
		if binding.TournamentID != tournamentID || binding.ParticipantID != participantID {
			sess.tournamentMu.Unlock()
			continue
		}
		binding.ParticipantID = ""
		if binding.Role == tournament.RoleParticipant {
			binding.Role = tournament.RoleViewer
		}
		binding.generation++
		sess.tournament = binding
		sess.tournamentMu.Unlock()
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

func (h *Handler) detachTournamentSession(sess *Session) string {
	previous := sess.clearTournament()
	if previous.TournamentID == "" {
		return ""
	}
	entry := h.tournaments.entry(previous.TournamentID)
	if entry == nil {
		return ""
	}
	entry.mu.Lock()
	changed := entry.event.Disconnect(sess.ConnectionID, time.Now())
	entry.mu.Unlock()
	if changed {
		return previous.TournamentID
	}
	return ""
}

// Call only after releasing any other event's operation lock. Cross-event
// switches must not acquire event operation locks in opposite orders.
func (h *Handler) refreshTournament(tournamentID string) {
	if tournamentID == "" {
		return
	}
	entry, err := h.tournaments.lockOperation(tournamentID)
	if err != nil {
		return
	}
	defer entry.opMu.Unlock()
	h.fanoutTournament(tournamentID)
}

func (h *Handler) disconnectTournamentSession(sess *Session) {
	binding := sess.Tournament()
	if binding.TournamentID == "" {
		return
	}
	entry, err := h.tournaments.lockOperation(binding.TournamentID)
	if err != nil {
		return
	}
	defer entry.opMu.Unlock()
	entry.mu.Lock()
	changed := entry.event.Disconnect(sess.ConnectionID, time.Now())
	entry.mu.Unlock()
	if changed {
		h.fanoutTournament(binding.TournamentID)
	}
}

func (h *Handler) fanoutTournament(tournamentID string) {
	h.fanoutTournamentState(tournamentID, nil)
	if entry := h.tournaments.entry(tournamentID); entry != nil {
		h.reconcileTournamentRetentionLocked(tournamentID, entry, time.Now().UTC(), false)
	}
}

// Pick-only fanout can replace unchanged private snapshots with public progress.
// All other operations (including entry/recovery) retain full snapshots.
func (h *Handler) fanoutTournamentState(tournamentID string,
	previous map[string]protocol.LimitedSnapshot) {
	type member struct {
		session *Session
		binding tournamentBinding
	}
	type projection struct {
		kind    string
		payload any
	}
	h.sessionsMu.RLock()
	members := make([]member, 0)
	for _, sess := range h.sessions {
		binding := sess.Tournament()
		if binding.TournamentID == tournamentID {
			members = append(members, member{sess, binding})
		}
	}
	h.sessionsMu.RUnlock()
	entry := h.tournaments.entry(tournamentID)
	if entry == nil {
		return
	}
	for _, member := range members {
		sess, binding := member.session, member.binding
		entry.mu.Lock()
		sess.tournamentMu.RLock()
		privateID, valid := tournamentProjectionIdentity(entry.event, sess, binding)
		var projections []projection
		if valid {
			if previous == nil {
				projections = append(projections, projection{protocol.TypeTournamentSnapshot,
					tournamentSnapshot(entry.event, binding)})
			}
			if snapshot := entry.event.LimitedSnapshot(privateID); snapshot != nil {
				before, known := previous[privateID]
				comparison := *snapshot
				before.Participants, comparison.Participants = nil, nil
				if known && reflect.DeepEqual(before, comparison) {
					projections = append(projections, projection{protocol.TypeLimitedProgress,
						protocol.LimitedProgress{TournamentID: tournamentID, Participants: snapshot.Participants}})
				} else {
					projections = append(projections, projection{protocol.TypeLimitedSnapshot, *snapshot})
				}
			}
		}
		sess.tournamentMu.RUnlock()
		entry.mu.Unlock()
		for _, projected := range projections {
			envelope, err := protocol.NewEnvelope(projected.kind, projected.payload)
			if err != nil {
				h.failClosedSession(sess, err)
				break
			}
			h.sendTournamentProjection(entry, sess, binding, privateID, envelope)
		}
	}
}

// Both locks must be held: entry.mu, then sess.tournamentMu. A cached binding
// is not authority after an event switch or a credential transfer.
func tournamentProjectionIdentity(event *tournament.Tournament, sess *Session,
	binding tournamentBinding) (string, bool) {
	if binding != sess.tournament || binding.TournamentID != event.ID {
		return "", false
	}
	participant := event.Participant(binding.ParticipantID)
	privateID := ""
	if participant != nil && participant.ConnectionID == sess.ConnectionID {
		privateID = participant.ID
	}
	switch binding.Role {
	case tournament.RoleOrganizer:
		return privateID, event.OrganizerConnectionID == sess.ConnectionID
	case tournament.RoleParticipant:
		return privateID, privateID != ""
	case tournament.RoleViewer:
		return "", binding.ParticipantID == ""
	default:
		return "", false
	}
}

func (h *Handler) sendTournamentProjection(entry *tournamentEntry, sess *Session,
	binding tournamentBinding, privateID string, envelope protocol.Envelope) {
	// Serialization may be slow; never hold membership/state locks across it.
	data, err := h.sessionEnvelopeBytes(envelope)
	if err != nil {
		h.failClosedSession(sess, err)
		return
	}
	entry.mu.Lock()
	sess.tournamentMu.RLock()
	currentPrivateID, valid := tournamentProjectionIdentity(entry.event, sess, binding)
	if valid && currentPrivateID == privateID {
		sess.trySend(data)
	}
	sess.tournamentMu.RUnlock()
	entry.mu.Unlock()
}

// The terminal projection may race with a member entering another pod after
// cancellation. Clear only the captured binding, and enqueue its leave while
// holding the same membership lock: a newer entry must never receive a late
// leave for this pod after its own acknowledgement.
func (h *Handler) closeTournamentMembership(entry *tournamentEntry, sess *Session,
	expected tournamentBinding, replyID string) {
	left, _ := protocol.NewEnvelope(protocol.TypeTournamentLeft,
		protocol.TournamentLeft{TournamentID: expected.TournamentID})
	left.ID = replyID
	data, err := h.sessionEnvelopeBytes(left)
	if err != nil {
		h.failClosedSession(sess, err)
		return
	}
	entry.mu.Lock()
	defer entry.mu.Unlock()
	sess.tournamentMu.Lock()
	defer sess.tournamentMu.Unlock()
	if expected.TournamentID != entry.event.ID || sess.tournament != expected {
		return
	}
	sess.tournament = tournamentBinding{generation: expected.generation + 1}
	entry.event.Disconnect(sess.ConnectionID, time.Now())
	sess.trySend(data)
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
		if event.IsCubeRoom() && participant.ConnectionID == "" && !participant.DisconnectedAt.IsZero() {
			participantView.DisconnectedAt = participant.DisconnectedAt.UTC().Format(time.RFC3339Nano)
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
			if pairing.Invited {
				view.Status = "invited"
			}
			view.AutoEnter = (binding.Role == tournament.RoleParticipant || binding.Role == tournament.RoleOrganizer) &&
				pairing.AutoEntryPending(binding.ParticipantID)
			if pairing.Group != nil {
				view.PlayerIDs = append([]string(nil), pairing.Group.PlayerIDs...)
				view.AcceptedPlayerIDs = append([]string(nil), pairing.Group.AcceptedPlayerIDs...)
				for _, id := range pairing.Group.PlayerIDs {
					view.PlayerNames = append(view.PlayerNames, event.Participant(id).DisplayName)
				}
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
		MaxPlayers:     event.MaxPlayers,
		MinimumPlayers: event.MinimumPlayers(),
		PlannedRounds:  event.PlannedRounds, CurrentRound: len(event.Rounds),
		Registered: len(event.Participants), CheckedIn: checkedIn,
		RoundComplete: event.RoundComplete(), OrganizerName: event.OrganizerName,
		Role: binding.Role, ParticipantID: binding.ParticipantID,
		CanRegister: !event.IsCubeRoom() && event.Status == tournament.StatusRegistration &&
			binding.ParticipantID == "" && len(event.Participants) < event.MaxPlayers,
		Product:       event.LimitedProductView(),
		DraftSettings: event.DraftSettings(),
		Participants:  participants, Pairings: pairings, Standings: standingViews,
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
