// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"fmt"
	"hexproof/server/internal/protocol"
	"strings"
)

// Join attempts to add a connection as player or spectator. Returns a Result
// with room.joined reply + a room.snapshot broadcast, or an error.
//
// The password parameter is NOT validated here (the reducer is pure and holds
// no hash); password checking is the hub's responsibility via bcrypt. It is
// kept on the signature for reducer transparency / future use.
func (r *Room) Join(connID, display string, asSpectator bool, password string) (Result, error) {
	return r.join(connID, display, asSpectator, password, "")
}

// JoinTournamentParticipant adds one tournament identity to a pairing room.
// The identity is server-internal and prevents one credential rebound onto a
// second connection from occupying both seats.
func (r *Room) JoinTournamentParticipant(connID, display, participantID string) (Result, error) {
	if strings.TrimSpace(participantID) == "" {
		return Result{}, newError(protocol.ErrInvalidMessage)
	}
	return r.join(connID, display, false, "", participantID)
}

func (r *Room) join(connID, display string, asSpectator bool, password,
	tournamentParticipantID string) (Result, error) {
	if r.Disbanded {
		return Result{}, newError(protocol.ErrRoomNotFound)
	}
	if r.Member(connID) {
		return Result{}, newError(protocol.ErrAlreadyInRoom)
	}
	if tournamentParticipantID != "" {
		for _, occupiedSeat := range r.Seats {
			if occupiedSeat.Occupied &&
				occupiedSeat.TournamentParticipantID == tournamentParticipantID {
				return Result{}, newError(protocol.ErrAlreadyInRoom)
			}
		}
	}
	if asSpectator {
		if !r.AllowSpectators {
			return Result{}, newError(protocol.ErrSpectatorsNotAllowed)
		}
		if len(r.Spectators) >= protocol.MaxSpectators {
			return Result{}, newError(protocol.ErrSpectatorLimit)
		}
		r.Spectators = append(r.Spectators, Spectator{DisplayName: display, ConnectionID: connID})
		return r.buildJoinResult(connID, "spectator", nil)
	}
	// player join
	if r.Phase != protocol.RoomPhaseWaiting {
		return Result{}, newError(protocol.ErrMatchStarted)
	}
	if r.PlayerCount() >= r.MaxSeats {
		return Result{}, newError(protocol.ErrRoomFull)
	}
	seat := r.firstFreeSeat()
	r.Seats[seat] = Seat{
		Occupied: true, DisplayName: display, ConnectionID: connID,
		TournamentParticipantID: tournamentParticipantID,
	}
	if r.HostSeat < 0 {
		r.Seats[seat].Host = true
		r.HostSeat = seat
	}
	return r.buildJoinResult(connID, "player", &seat)
}

func (r *Room) firstFreeSeat() int {
	for i, s := range r.Seats {
		if !s.Occupied {
			return i
		}
	}
	return -1
}

func (r *Room) buildJoinResult(connID, role string, seat *int) (Result, error) {
	joined := protocol.RoomJoined{RoomID: r.ID, Role: role, Seat: seat}
	replyEnv, err := protocol.NewEnvelope(protocol.TypeRoomJoined, joined)
	if err != nil {
		return Result{}, err
	}
	broadcast := []protocol.Envelope{r.snapshotEnvelope()}
	if r.Phase == protocol.RoomPhaseLoading ||
		(r.Phase == protocol.RoomPhaseStarted &&
			r.CardLoadMode == protocol.CardLoadBackground) {
		broadcast = append(broadcast, r.loadRequiredEnvelope())
	}
	return Result{
		Reply:       &replyEnv,
		Broadcast:   broadcast,
		ProjectGame: r.Phase == protocol.RoomPhaseStarted && r.Game != nil,
	}, nil
}

// Reconnect atomically rebinds one held player or spectator membership to a
// new transport connection. All deck, hand, library, and game state stays on
// the server unchanged.
func (r *Room) Reconnect(oldConnID, newConnID string) (ReconnectInfo, error) {
	if r.Disbanded || strings.TrimSpace(oldConnID) == "" ||
		strings.TrimSpace(newConnID) == "" || r.Member(newConnID) {
		return ReconnectInfo{}, newError(protocol.ErrNotInRoom)
	}
	if seat := r.FindSeatByConnection(oldConnID); seat >= 0 {
		r.Seats[seat].ConnectionID = newConnID
		seatCopy := seat
		return ReconnectInfo{
			Role: protocol.RolePlayer,
			Seat: &seatCopy,
			Host: r.Seats[seat].Host,
		}, nil
	}
	for index := range r.Spectators {
		if r.Spectators[index].ConnectionID == oldConnID {
			r.Spectators[index].ConnectionID = newConnID
			return ReconnectInfo{Role: protocol.RoleSpectator}, nil
		}
	}
	return ReconnectInfo{}, newError(protocol.ErrNotInRoom)
}

// ExpireDisconnected frees a membership whose reconnect window elapsed. A
// disconnected host does not disband the room. Once the hold expires, host
// authority transfers to the lowest occupied player seat. The bool reports
// whether no membership remains and the hub may archive and remove the room.
func (r *Room) ExpireDisconnected(connID string) (Result, bool, error) {
	if !r.Member(connID) {
		return Result{}, false, newError(protocol.ErrNotInRoom)
	}
	wasPlayer := false
	projectGame := false
	if seat := r.FindSeatByConnection(connID); seat >= 0 {
		wasPlayer = true
		projectGame = r.forfeitDepartedPlayer(seat)
		wasHost := r.Seats[seat].Host
		r.Seats[seat] = Seat{}
		if wasHost {
			r.transferHost()
		}
	}
	for index, spectator := range r.Spectators {
		if spectator.ConnectionID == connID {
			r.Spectators = append(r.Spectators[:index], r.Spectators[index+1:]...)
			break
		}
	}
	if wasPlayer {
		r.cancelLoading()
	}
	empty := r.PlayerCount() == 0 && len(r.Spectators) == 0
	return Result{
		Broadcast:   []protocol.Envelope{r.snapshotEnvelope()},
		ProjectGame: projectGame,
	}, empty, nil
}

func (r *Room) transferHost() {
	r.HostSeat = -1
	for index := range r.Seats {
		r.Seats[index].Host = false
	}
	for index := range r.Seats {
		if !r.Seats[index].Occupied {
			continue
		}
		r.Seats[index].Host = true
		r.HostSeat = index
		return
	}
}

// Leave removes a connection from the room after an intentional leave. A
// network drop uses the separate reconnect hold. A non-host leaver gets a room.left
// reply + a snapshot broadcast to remaining members. The host leaving
// disbands the room: the host gets a room.disbanded reply and remaining
// members get a room.disbanded broadcast (no snapshot).
func (r *Room) Leave(connID string) (Result, error) {
	if !r.Member(connID) {
		return Result{}, newError(protocol.ErrNotInRoom)
	}
	wasHost := r.IsHost(connID)

	// Remove from seats.
	wasPlayer := false
	projectGame := false
	if i := r.FindSeatByConnection(connID); i >= 0 {
		wasPlayer = true
		if !wasHost {
			projectGame = r.forfeitDepartedPlayer(i)
		}
		r.Seats[i] = Seat{}
	}
	// Remove from spectators.
	for i, sp := range r.Spectators {
		if sp.ConnectionID == connID {
			r.Spectators = append(r.Spectators[:i], r.Spectators[i+1:]...)
			break
		}
	}

	left := protocol.RoomLeft{RoomID: r.ID}
	leftEnv, _ := protocol.NewEnvelope(protocol.TypeRoomLeft, left)

	if wasHost {
		// Host leave => disband. The host receives room.disbanded as its reply
		// (semantically "the room is gone"), and the same event is broadcast
		// to remaining members as the last fan-out. No snapshot. The reply and
		// broadcast are separate envelope instances (so the handler can stamp
		// the echoed id on the reply without affecting the broadcast) but share
		// the same seq value.
		r.Disbanded = true
		seq := r.allocSeq()
		reply, _ := protocol.NewEnvelope(protocol.TypeRoomDisbanded, map[string]any{"roomId": r.ID})
		reply.SeqPtr = seqPtr(seq)
		bcast, _ := protocol.NewEnvelope(protocol.TypeRoomDisbanded, map[string]any{"roomId": r.ID})
		bcast.SeqPtr = seqPtr(seq)
		return Result{Reply: &reply, Broadcast: []protocol.Envelope{bcast}}, nil
	}
	if wasPlayer {
		r.cancelLoading()
	}
	return Result{
		Reply:       &leftEnv,
		Broadcast:   []protocol.Envelope{r.snapshotEnvelope()},
		ProjectGame: projectGame,
	}, nil
}

// Kick removes a member by seat index or spectator index. Host only. The host
// seat cannot be kicked (use Leave/Disband instead). seat and spectatorIndex
// are mutually exclusive (exactly one must be non-nil). On success the kicked
// connection's id is returned in Result.TargetConnID so the handler can notify
// and unbind it before fanning out the snapshot to remaining members.
func (r *Room) Kick(actorConnID string, seat, spectatorIndex *int) (Result, error) {
	if !r.IsHost(actorConnID) {
		return Result{}, newError(protocol.ErrNotHost)
	}
	if code := (protocol.RoomKick{Seat: seat, SpectatorIndex: spectatorIndex}).Validate(); code != "" {
		return Result{}, newError(code)
	}

	if seat != nil {
		i := *seat
		if i < 0 || i >= len(r.Seats) || !r.Seats[i].Occupied {
			return Result{}, newError(protocol.ErrInvalidTarget)
		}
		if r.Seats[i].Host {
			return Result{}, newError(protocol.ErrCannotKickHost)
		}
		targetConn := r.Seats[i].ConnectionID
		projectGame := r.forfeitDepartedPlayer(i)
		r.Seats[i] = Seat{}
		r.cancelLoading()
		return r.buildKickResult(targetConn, projectGame)
	}

	// spectator
	i := *spectatorIndex
	if i < 0 || i >= len(r.Spectators) {
		return Result{}, newError(protocol.ErrInvalidTarget)
	}
	targetConn := r.Spectators[i].ConnectionID
	r.Spectators = append(r.Spectators[:i], r.Spectators[i+1:]...)
	return r.buildKickResult(targetConn, false)
}

func (r *Room) buildKickResult(targetConnID string, projectGame bool) (Result, error) {
	kicked, _ := protocol.NewEnvelope(protocol.TypeRoomKicked, map[string]any{"roomId": r.ID})
	return Result{
		Reply:        &kicked,
		Broadcast:    []protocol.Envelope{r.snapshotEnvelope()},
		TargetConnID: targetConnID,
		ProjectGame:  projectGame,
	}, nil
}

// forfeitDepartedPlayer resolves a player membership that disappears after a
// match has started. Two-player departures forfeit the whole match so a BO3 table
// cannot enter a sideboard or later game with an empty seat. EDH departures
// eliminate that player and advance the turn when necessary.
func (r *Room) forfeitDepartedPlayer(seat int) bool {
	if r.Phase != protocol.RoomPhaseStarted || r.Game == nil ||
		seat < 0 || seat >= len(r.Game.Seats) ||
		(r.Game.Result != nil && r.Game.Result.MatchFinished) {
		return false
	}
	if r.Format == protocol.FormatEDH {
		state := &r.Game.Seats[seat]
		if state.Eliminated {
			return false
		}
		state.Eliminated = true
		r.appendGameLog("departure", seat,
			fmt.Sprintf("%s left the game and was eliminated.", state.DisplayName))

		remaining := 0
		winnerSeat := -1
		for index := range r.Game.Seats {
			if !r.Game.Seats[index].Eliminated {
				remaining++
				winnerSeat = index
			}
		}
		if remaining <= 1 {
			r.Game.ActiveSeat = -1
			if remaining == 1 {
				if len(r.Score) != len(r.Game.Seats) {
					r.Score = make([]int, len(r.Game.Seats))
				}
				r.Score[winnerSeat] = 1
				r.appendGameLog("result", winnerSeat,
					fmt.Sprintf("%s wins the Commander game.",
						r.Game.Seats[winnerSeat].DisplayName))
			}
			r.Game.Result = &protocol.GameResult{
				Reason:        protocol.GameResultDeparture,
				WinnerSeat:    winnerSeat,
				ConcededSeat:  seat,
				MatchFinished: true,
			}
		} else if r.Game.ActiveSeat == seat {
			r.Game.ActiveSeat = r.nextActiveSeat(seat)
			r.Game.CurrentPhase = protocol.GamePhaseUntap
			r.Game.LandPlaysThisTurn = 0
		}
		return true
	}
	if !protocol.IsTwoPlayerFormat(r.Format) || len(r.Game.Seats) != 2 {
		return false
	}

	winnerSeat := 1 - seat
	if len(r.Score) != len(r.Game.Seats) {
		r.Score = make([]int, len(r.Game.Seats))
	}
	winsRequired := 1
	if r.MatchMode == protocol.MatchBO3 {
		winsRequired = 2
	}
	if r.Score[winnerSeat] < winsRequired {
		r.Score[winnerSeat] = winsRequired
	}
	r.Game.ActiveSeat = -1
	r.Game.Sideboard = nil
	r.Game.Result = &protocol.GameResult{
		Reason:        protocol.GameResultDeparture,
		WinnerSeat:    winnerSeat,
		ConcededSeat:  seat,
		MatchFinished: true,
	}
	r.appendGameLog("departure", seat,
		fmt.Sprintf("%s left the match. %s wins.",
			r.Game.Seats[seat].DisplayName,
			r.Game.Seats[winnerSeat].DisplayName))
	return true
}
