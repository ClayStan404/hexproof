// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"hexproof/server/internal/protocol"
	"sort"
	"strings"
)

// GameSnapshot returns the role-specific game projection for connID. Hidden
// hand identities are included only when connID owns that seat.
func (r *Room) GameSnapshot(connID string) (protocol.GameSnapshot, error) {
	if r.Phase != protocol.RoomPhaseStarted || r.Game == nil {
		return protocol.GameSnapshot{}, newError(protocol.ErrGameNotStarted)
	}
	if !r.Member(connID) {
		return protocol.GameSnapshot{}, newError(protocol.ErrNotInRoom)
	}
	ownerSeat := r.FindSeatByConnection(connID)
	seats := make([]protocol.GameSeatProjection, 0, len(r.Game.Seats))
	for _, state := range r.Game.Seats {
		// Never project a seat that was empty when this game started. A player
		// who leaves after start keeps their named, eliminated game state visible
		// so the public battlefield does not disappear.
		if state.DisplayName == "" {
			continue
		}
		projection := protocol.GameSeatProjection{
			Seat:           state.Seat,
			DisplayName:    state.DisplayName,
			Life:           state.Life,
			Counters:       clonePlayerCounters(state.Counters),
			CounterCount:   state.CounterCount,
			LibraryCount:   len(state.Library),
			HandCount:      len(state.Hand),
			SideboardCount: len(state.Sideboard),
			MulliganCount:  state.MulliganCount,
			Battlefield: projectBattlefieldCards(
				state.Battlefield, state.Seat, ownerSeat),
			Graveyard:      cloneGameCards(state.Graveyard),
			Exile:          cloneGameCards(state.Exile),
			CommandZone:    cloneGameCards(state.CommandZone),
			CommanderTax:   state.CommanderTax,
			CommanderTaxes: cloneCommanderTaxes(state.CommanderTaxes),
			Eliminated:     state.Eliminated,
			ResponseStatus: state.ResponseStatus,
		}
		if ownerSeat == state.Seat {
			projection.Hand = cloneGameCards(state.Hand)
			projection.Sideboard = cloneGameCards(state.Sideboard)
		}
		seats = append(seats, projection)
	}
	var gameResult *protocol.GameResult
	if r.Game.Result != nil {
		result := *r.Game.Result
		gameResult = &result
	}
	var sideboardProjection *protocol.SideboardProjection
	if r.Game.Sideboard != nil {
		sideboardSeats := make([]protocol.SideboardSeatProjection,
			len(r.Game.Sideboard.Players))
		for index, player := range r.Game.Sideboard.Players {
			sideboardSeats[index] = protocol.SideboardSeatProjection{
				Seat:           index,
				Ready:          player.Ready,
				MainboardCount: deckCardCount(player.Mainboard),
				SideboardCount: deckCardCount(player.Sideboard),
			}
		}
		sideboardProjection = &protocol.SideboardProjection{
			DeadlineUnixMS: r.Game.Sideboard.Deadline.UnixMilli(),
			Seats:          sideboardSeats,
		}
		if ownerSeat >= 0 {
			sideboardProjection.Mainboard =
				cloneDeckCards(r.Game.Sideboard.Players[ownerSeat].Mainboard)
			sideboardProjection.Sideboard =
				cloneDeckCards(r.Game.Sideboard.Players[ownerSeat].Sideboard)
			sideboardProjection.Commanders = append([]string{},
				r.Game.Sideboard.Players[ownerSeat].Commanders...)
		}
	}
	projectedLog, logStartID, logTruncated := projectGameLog(
		r.Game.Log, r.Game.NextLogID)
	commanders := r.projectCommanderIdentities()
	return protocol.GameSnapshot{
		RoomID:            r.ID,
		GameNumber:        r.Game.Number,
		StartingSeat:      r.Game.StartingSeat,
		ActiveSeat:        r.Game.ActiveSeat,
		CurrentPhase:      r.Game.CurrentPhase,
		LandPlaysThisTurn: r.Game.LandPlaysThisTurn,
		Seats:             seats,
		Stack:             cloneSharedCards(r.Game.Stack),
		Revealed:          cloneSharedCards(r.Game.Revealed),
		Arrows:            append([]protocol.GameArrow{}, r.Game.Arrows...),
		Attachments:       append([]protocol.GameAttachment{}, r.Game.Attachments...),
		Commanders:        commanders,
		CommanderDamage: projectCommanderDamage(
			r.Game.CommanderDamage, commanders),
		Log:          projectedLog,
		LogStartID:   logStartID,
		LogTruncated: logTruncated,
		Score:        append([]int{}, r.Score...),
		DrawnGames:   r.DrawnGames,
		Result:       gameResult,
		Sideboard:    sideboardProjection,
	}, nil
}

func (r *Room) projectCommanderIdentities() []protocol.GameCommanderIdentity {
	identities := make([]protocol.GameCommanderIdentity, 0)
	for ownerSeat, state := range r.Game.Seats {
		ids := make([]string, 0, len(state.CommanderTaxes))
		for commanderID := range state.CommanderTaxes {
			ids = append(ids, commanderID)
		}
		sort.Strings(ids)
		for _, commanderID := range ids {
			name := commanderID
			if card, _, found := r.findDesignatedCommander(commanderID); found {
				name = card.Name
			}
			identities = append(identities, protocol.GameCommanderIdentity{
				CardID: commanderID, OwnerSeat: ownerSeat, Name: name,
			})
		}
	}
	return identities
}

func projectCommanderDamage(values map[string]map[int]int,
	commanders []protocol.GameCommanderIdentity) []protocol.GameCommanderDamage {
	ownerByID := make(map[string]int, len(commanders))
	for _, commander := range commanders {
		ownerByID[commander.CardID] = commander.OwnerSeat
	}
	commanderIDs := make([]string, 0, len(values))
	for commanderID := range values {
		commanderIDs = append(commanderIDs, commanderID)
	}
	sort.Strings(commanderIDs)
	result := make([]protocol.GameCommanderDamage, 0)
	for _, commanderID := range commanderIDs {
		targets := make([]int, 0, len(values[commanderID]))
		for targetSeat := range values[commanderID] {
			targets = append(targets, targetSeat)
		}
		sort.Ints(targets)
		for _, targetSeat := range targets {
			value := values[commanderID][targetSeat]
			if value == 0 {
				continue
			}
			result = append(result, protocol.GameCommanderDamage{
				CommanderID:        commanderID,
				CommanderOwnerSeat: ownerByID[commanderID],
				TargetSeat:         targetSeat,
				Value:              value,
			})
		}
	}
	return result
}

func cloneCommanderTaxes(values map[string]int) map[string]int {
	if len(values) == 0 {
		return nil
	}
	clone := make(map[string]int, len(values))
	for key, value := range values {
		clone[key] = value
	}
	return clone
}

func projectGameLog(log []protocol.GameLogEntry,
	nextLogID int64) ([]protocol.GameLogEntry, int64, bool) {
	start := 0
	if len(log) > protocol.MaxProjectedGameLog {
		start = len(log) - protocol.MaxProjectedGameLog
	}
	projected := append([]protocol.GameLogEntry(nil), log[start:]...)
	logStartID := nextLogID
	if len(projected) > 0 {
		logStartID = projected[0].ID
	}
	if logStartID <= 0 {
		logStartID = 1
	}
	return projected, logStartID, start > 0 || logStartID > 1
}

func clonePlayerCounters(counters []protocol.GamePlayerCounter) []protocol.GamePlayerCounter {
	return append([]protocol.GamePlayerCounter{}, counters...)
}

func cloneGameCards(cards []protocol.GameCard) []protocol.GameCard {
	cloned := append([]protocol.GameCard{}, cards...)
	for i := range cloned {
		if cards[i].Position != nil {
			position := *cards[i].Position
			cloned[i].Position = &position
		}
		cloned[i].Counters = append([]protocol.GameCardCounter{}, cards[i].Counters...)
	}
	return cloned
}

func projectBattlefieldCards(cards []protocol.GameCard, controllerSeat,
	viewerSeat int) []protocol.GameCard {
	projected := cloneGameCards(cards)
	for index := range projected {
		card := &projected[index]
		if !card.FaceDown || viewerSeat == controllerSeat {
			continue
		}
		card.Name = ""
		card.SetCode = ""
		card.CollectorNumber = ""
		card.TypeLine = ""
		card.FaceName = ""
	}
	return projected
}

func cloneSharedCards(cards []protocol.GameSharedCard) []protocol.GameSharedCard {
	cloned := append([]protocol.GameSharedCard{}, cards...)
	for i := range cloned {
		if cards[i].Position != nil {
			position := *cards[i].Position
			cloned[i].Position = &position
		}
		cloned[i].Counters = append([]protocol.GameCardCounter{}, cards[i].Counters...)
	}
	return cloned
}

func cloneDeckCards(cards []protocol.DeckCard) []protocol.DeckCard {
	cloned := append([]protocol.DeckCard(nil), cards...)
	for index := range cloned {
		cloned[index].Name = strings.TrimSpace(cloned[index].Name)
		cloned[index].SetCode = strings.TrimSpace(cloned[index].SetCode)
		cloned[index].CollectorNumber =
			strings.TrimSpace(cloned[index].CollectorNumber)
		cloned[index].TypeLine = strings.TrimSpace(cloned[index].TypeLine)
	}
	return cloned
}

func deckCardCount(cards []protocol.DeckCard) int {
	count := 0
	for _, card := range cards {
		count += card.Count
	}
	return count
}

// snapshotEnvelope builds a room.snapshot stamped with the next seq.
func (r *Room) snapshotEnvelope() protocol.Envelope {
	snap := r.Snapshot()
	env, _ := protocol.NewEnvelope(protocol.TypeRoomSnapshot, snap)
	env.SeqPtr = seqPtr(r.allocSeq())
	return env
}

// Snapshot returns public room structure and ready/load status. Selected deck
// identities remain server-internal and are never embedded in snapshots.
func (r *Room) Snapshot() protocol.RoomSnapshot {
	loadID := r.LoadID
	if r.Phase == protocol.RoomPhaseWaiting {
		loadID = 0
	}
	seats := make([]protocol.Seat, len(r.Seats))
	for i, s := range r.Seats {
		seats[i] = protocol.Seat{
			Occupied:     s.Occupied,
			DisplayName:  s.DisplayName,
			Host:         s.Host,
			DeckSelected: s.Deck != nil,
			Ready:        s.Ready,
			Loaded:       s.Loaded,
		}
	}
	spectators := make([]protocol.SpectatorProjection, len(r.Spectators))
	for i, sp := range r.Spectators {
		spectators[i] = protocol.SpectatorProjection{DisplayName: sp.DisplayName}
	}
	return protocol.RoomSnapshot{
		RoomID:          r.ID,
		Name:            r.Name,
		Format:          r.Format,
		DeckFormat:      r.DeckFormat,
		MaxSeats:        r.MaxSeats,
		Playtest:        r.Playtest,
		MatchMode:       r.MatchMode,
		CardLoadMode:    r.CardLoadMode,
		HostSeat:        r.HostSeat,
		HasPassword:     r.HasPassword,
		Seats:           seats,
		Spectators:      spectators,
		AllowSpectators: r.AllowSpectators,
		Phase:           r.Phase,
		LoadID:          loadID,
	}
}

// ListEntry returns a public room-browser projection for this hub only.
func (r *Room) ListEntry() protocol.RoomListEntry {
	playerCount := r.PlayerCount()
	return protocol.RoomListEntry{
		RoomID:          r.ID,
		Name:            r.Name,
		Format:          r.Format,
		DeckFormat:      r.DeckFormat,
		MatchMode:       r.MatchMode,
		CardLoadMode:    r.CardLoadMode,
		MaxSeats:        r.MaxSeats,
		PlayerCount:     playerCount,
		SpectatorCount:  len(r.Spectators),
		AllowSpectators: r.AllowSpectators,
		HasPassword:     r.HasPassword,
		Phase:           r.Phase,
		PlayerJoinable: !r.Disbanded && r.Phase == protocol.RoomPhaseWaiting &&
			playerCount < r.MaxSeats,
		SpectatorJoinable: !r.Disbanded && r.AllowSpectators &&
			len(r.Spectators) < protocol.MaxSpectators,
	}
}

func seqPtr(s int64) *int64 { return &s }
