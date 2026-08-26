// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"crypto/rand"
	"errors"
	"fmt"
	"hexproof/server/internal/protocol"
	"math/big"
	"strings"
	"unicode"
	"unicode/utf8"
)

// SelectDeck validates and stores a player's complete deck identity. The deck
// remains server-internal; only DeckSelected is projected in room snapshots.
// Selecting or changing a deck always clears the player's ready state.
func (r *Room) SelectDeck(connID string, deck protocol.DeckSelect) (Result, error) {
	if r.Phase == protocol.RoomPhaseStarted {
		return Result{}, newError(protocol.ErrMatchStarted)
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if err := r.validateDeck(deck); err != nil {
		return Result{}, err
	}

	registered := cloneDeck(deck)
	active := cloneDeck(deck)
	r.Seats[seat].RegisteredDeck = &registered
	r.Seats[seat].Deck = &active
	r.Seats[seat].Ready = false
	r.cancelLoading()
	reply, _ := protocol.NewEnvelope(protocol.TypeDeckSelected, protocol.DeckSelected{
		RoomID: r.ID,
		Seat:   seat,
	})
	return Result{
		Reply:     &reply,
		Broadcast: []protocol.Envelope{r.snapshotEnvelope()},
	}, nil
}

// SetReady changes a player's ready state. A player may become ready only when
// the room has enough seated players to start and that player has selected a
// valid deck. Commander keeps a fourth seat available but may start with three.
func (r *Room) SetReady(connID string, ready bool) (Result, error) {
	if r.Phase == protocol.RoomPhaseStarted {
		return Result{}, newError(protocol.ErrMatchStarted)
	}
	seat, err := r.playerSeat(connID, false)
	if err != nil {
		return Result{}, err
	}
	if ready {
		if r.PlayerCount() < r.minimumPlayersToStart() {
			return Result{}, newError(protocol.ErrSeatsNotFilled)
		}
		if r.Seats[seat].Deck == nil {
			return Result{}, newError(protocol.ErrDeckRequired)
		}
	}

	previousReady := r.Seats[seat].Ready
	r.Seats[seat].Ready = ready
	if !ready {
		r.cancelLoading()
	}
	reply, _ := protocol.NewEnvelope(protocol.TypePlayerReadyChanged,
		protocol.PlayerReadyChanged{RoomID: r.ID, Seat: seat, Ready: ready})
	startedLoading, err := r.beginLoadingIfReady()
	if err != nil {
		r.Seats[seat].Ready = previousReady
		return Result{}, err
	}
	broadcast := []protocol.Envelope{r.snapshotEnvelope()}
	if startedLoading {
		broadcast = append(broadcast, r.loadRequiredEnvelope())
	}
	startedMatch := startedLoading && r.Phase == protocol.RoomPhaseStarted
	if startedMatch {
		started, _ := protocol.NewEnvelope(protocol.TypeMatchStarted,
			protocol.MatchStarted{RoomID: r.ID, LoadID: r.LoadID})
		started.SeqPtr = seqPtr(r.allocSeq())
		broadcast = append(broadcast, started)
	}
	return Result{
		Reply:       &reply,
		Broadcast:   broadcast,
		ProjectGame: startedMatch,
	}, nil
}

// CompleteLoad marks one member complete for the active load generation.
// Spectators may acknowledge prefetch but never participate in the start gate.
func (r *Room) CompleteLoad(connID string, loadID int64) (Result, error) {
	if !r.Member(connID) {
		return Result{}, newError(protocol.ErrNotInRoom)
	}
	if r.Phase != protocol.RoomPhaseLoading {
		return Result{}, newError(protocol.ErrNotLoading)
	}
	if loadID != r.LoadID {
		return Result{}, newError(protocol.ErrStaleLoad)
	}

	reply, _ := protocol.NewEnvelope(protocol.TypeClientLoadCompleted,
		protocol.ClientLoadCompleted{RoomID: r.ID, LoadID: loadID})
	seat := r.FindSeatByConnection(connID)
	if seat < 0 {
		return Result{Reply: &reply}, nil
	}
	r.Seats[seat].Loaded = true
	allLoaded := true
	for _, player := range r.Seats {
		if player.Occupied && !player.Loaded {
			allLoaded = false
			break
		}
	}
	if allLoaded {
		if err := r.setupGame(); err != nil {
			r.resetAfterGameSetupFailure()
			return Result{
				Broadcast: []protocol.Envelope{r.snapshotEnvelope()},
			}, newError(protocol.ErrGameSetupFailed)
		}
		r.Phase = protocol.RoomPhaseStarted
	}
	broadcast := []protocol.Envelope{r.snapshotEnvelope()}
	if allLoaded {
		started, _ := protocol.NewEnvelope(protocol.TypeMatchStarted,
			protocol.MatchStarted{RoomID: r.ID, LoadID: r.LoadID})
		started.SeqPtr = seqPtr(r.allocSeq())
		broadcast = append(broadcast, started)
	}
	return Result{Reply: &reply, Broadcast: broadcast, ProjectGame: allLoaded}, nil
}

func (r *Room) beginLoadingIfReady() (bool, error) {
	if r.Phase != protocol.RoomPhaseWaiting ||
		r.PlayerCount() < r.minimumPlayersToStart() {
		return false, nil
	}
	for _, seat := range r.Seats {
		if seat.Occupied && (seat.Deck == nil || !seat.Ready) {
			return false, nil
		}
	}
	if r.CardLoadMode == protocol.CardLoadBackground {
		if err := r.setupGame(); err != nil {
			return false, newError(protocol.ErrGameSetupFailed)
		}
		r.LoadID++
		for i := range r.Seats {
			r.Seats[i].Loaded = false
		}
		r.Phase = protocol.RoomPhaseStarted
	} else {
		r.LoadID++
		for i := range r.Seats {
			r.Seats[i].Loaded = false
		}
		r.Phase = protocol.RoomPhaseLoading
	}
	return true, nil
}

func (r *Room) minimumPlayersToStart() int {
	if r.Playtest || r.MaxSeats <= 1 {
		return 1
	}
	if r.Format == protocol.FormatEDH && r.MaxSeats >= 3 {
		return 3
	}
	return r.MaxSeats
}

func (r *Room) resetAfterGameSetupFailure() {
	r.Phase = protocol.RoomPhaseWaiting
	r.Game = nil
	for i := range r.Seats {
		r.Seats[i].Ready = false
		r.Seats[i].Loaded = false
	}
}

func (r *Room) cancelLoading() {
	if r.Phase != protocol.RoomPhaseLoading {
		return
	}
	r.Phase = protocol.RoomPhaseWaiting
	for i := range r.Seats {
		r.Seats[i].Loaded = false
	}
}

func (r *Room) loadRequiredEnvelope() protocol.Envelope {
	event, _ := protocol.NewEnvelope(protocol.TypeMatchLoadRequired,
		protocol.MatchLoadRequired{LoadID: r.LoadID, CardKeys: r.matchCardKeys()})
	event.SeqPtr = seqPtr(r.allocSeq())
	return event
}

// ResumeEnvelopes returns fresh authoritative state for exactly one resumed
// member. It never replays historical role projections, which prevents a
// spectator or opponent from receiving an earlier owner's hidden snapshot.
func (r *Room) ResumeEnvelopes(connID string) ([]protocol.Envelope, error) {
	if !r.Member(connID) {
		return nil, newError(protocol.ErrNotInRoom)
	}
	envelopes := []protocol.Envelope{r.snapshotEnvelope()}
	if r.Phase == protocol.RoomPhaseLoading ||
		(r.Phase == protocol.RoomPhaseStarted &&
			r.CardLoadMode == protocol.CardLoadBackground) {
		envelopes = append(envelopes, r.loadRequiredEnvelope())
	}
	if r.Phase == protocol.RoomPhaseStarted && r.Game != nil {
		snapshot, err := r.GameSnapshot(connID)
		if err != nil {
			return nil, err
		}
		envelope, _ := protocol.NewEnvelope(protocol.TypeGameSnapshot, snapshot)
		envelope.SeqPtr = seqPtr(r.allocSeq())
		envelopes = append(envelopes, envelope)
	}
	return envelopes, nil
}

func (r *Room) matchCardKeys() []protocol.CardKey {
	seen := make(map[string]bool)
	keys := make([]protocol.CardKey, 0)
	for _, seat := range r.Seats {
		if seat.Deck == nil {
			continue
		}
		for _, cards := range [][]protocol.DeckCard{seat.Deck.Mainboard, seat.Deck.Sideboard} {
			for _, card := range cards {
				key := strings.ToLower(strings.TrimSpace(card.Name)) + "|" +
					strings.ToUpper(strings.TrimSpace(card.SetCode)) + "|" +
					strings.TrimSpace(card.CollectorNumber)
				if seen[key] {
					continue
				}
				seen[key] = true
				keys = append(keys, protocol.CardKey{
					Name:            card.Name,
					SetCode:         card.SetCode,
					CollectorNumber: card.CollectorNumber,
				})
			}
		}
	}
	return keys
}

func secureRandomIndex(maximum int) (int, error) {
	if maximum <= 0 {
		return 0, errors.New("random index requires a positive bound")
	}
	value, err := rand.Int(rand.Reader, big.NewInt(int64(maximum)))
	if err != nil {
		return 0, err
	}
	return int(value.Int64()), nil
}

func (r *Room) shuffle(cards []protocol.GameCard) error {
	for i := len(cards) - 1; i > 0; i-- {
		j, err := r.randomIndex(i + 1)
		if err != nil {
			return err
		}
		cards[i], cards[j] = cards[j], cards[i]
	}
	return nil
}

func defaultPlayerCounters() []protocol.GamePlayerCounter {
	counters := make([]protocol.GamePlayerCounter, protocol.PlayerCounterSlotCount)
	for index := range counters {
		counters[index] = protocol.GamePlayerCounter{
			Key:   fmt.Sprintf("%s%d", protocol.PlayerCounterSlotPrefix, index+1),
			Label: "",
			Value: 0,
		}
	}
	return counters
}

func (r *Room) setupGame() error {
	return r.setupGameNumber(1, -1)
}

func (r *Room) setupGameNumber(gameNumber, fixedStartingSeat int) error {
	game := &GameState{
		Number:            gameNumber,
		StartingSeat:      -1,
		ActiveSeat:        -1,
		CurrentPhase:      protocol.GamePhaseUntap,
		LandPlaysThisTurn: 0,
		Seats:             make([]PlayerGameState, len(r.Seats)),
		Stack:             []protocol.GameSharedCard{},
		Revealed:          []protocol.GameSharedCard{},
		Arrows:            []protocol.GameArrow{},
		Attachments:       []protocol.GameAttachment{},
		CommanderDamage:   make(map[string]map[int]int),
		Log:               []protocol.GameLogEntry{},
		NextLogID:         1,
		NextTokenID:       1,
		NextCardCounterID: 1,
	}
	for seatIndex, seat := range r.Seats {
		if !seat.Occupied {
			game.Seats[seatIndex] = PlayerGameState{
				Seat: seatIndex, Eliminated: true,
			}
			continue
		}
		if seat.Deck == nil {
			return errors.New("occupied seat has no deck")
		}
		state := PlayerGameState{
			Seat:           seatIndex,
			DisplayName:    seat.DisplayName,
			Life:           20,
			Counters:       defaultPlayerCounters(),
			Library:        []protocol.GameCard{},
			Hand:           []protocol.GameCard{},
			Sideboard:      []protocol.GameCard{},
			Battlefield:    []protocol.GameCard{},
			Graveyard:      []protocol.GameCard{},
			Exile:          []protocol.GameCard{},
			CommandZone:    []protocol.GameCard{},
			CommanderTaxes: make(map[string]int),
		}
		if r.Format == protocol.FormatEDH {
			state.Life = 40
		}
		instance := 1
		for _, card := range seat.Deck.Mainboard {
			for copyIndex := 0; copyIndex < card.Count; copyIndex++ {
				state.Library = append(state.Library, protocol.GameCard{
					ID:              fmt.Sprintf("s%d-c%d", seatIndex, instance),
					Name:            card.Name,
					SetCode:         card.SetCode,
					CollectorNumber: card.CollectorNumber,
					TypeLine:        card.TypeLine,
					OwnerSeat:       seatIndex,
				})
				instance++
			}
		}
		for _, card := range seat.Deck.Sideboard {
			for copyIndex := 0; copyIndex < card.Count; copyIndex++ {
				state.Sideboard = append(state.Sideboard, protocol.GameCard{
					ID:              fmt.Sprintf("s%d-c%d", seatIndex, instance),
					Name:            card.Name,
					SetCode:         card.SetCode,
					CollectorNumber: card.CollectorNumber,
					TypeLine:        card.TypeLine,
					OwnerSeat:       seatIndex,
				})
				instance++
			}
		}
		if protocol.IsCommanderFormat(r.Format) {
			for _, commanderName := range deckCommanderNames(*seat.Deck) {
				commanderIndex := -1
				for index, card := range state.Library {
					if strings.EqualFold(strings.TrimSpace(card.Name),
						commanderName) {
						commanderIndex = index
						break
					}
				}
				if commanderIndex < 0 {
					return errors.New("commander missing from mainboard")
				}
				commander := state.Library[commanderIndex]
				commander.Commander = true
				state.CommandZone = append(state.CommandZone, commander)
				state.CommanderTaxes[commander.ID] = 0
				state.Library = append(state.Library[:commanderIndex],
					state.Library[commanderIndex+1:]...)
			}
		}
		if err := r.shuffle(state.Library); err != nil {
			return err
		}
		drawCards(&state, 7)
		game.Seats[seatIndex] = state
	}

	activeSeats := make([]int, 0, r.PlayerCount())
	for seatIndex, seat := range r.Seats {
		if seat.Occupied {
			activeSeats = append(activeSeats, seatIndex)
		}
	}
	if len(activeSeats) < r.minimumPlayersToStart() {
		return errors.New("not enough occupied seats")
	}

	randomStartingSeat := fixedStartingSeat < 0
	startingSeat := fixedStartingSeat
	if startingSeat < 0 {
		randomIndex, err := r.randomIndex(len(activeSeats))
		if err != nil {
			return err
		}
		startingSeat = activeSeats[randomIndex]
	}
	if startingSeat < 0 || startingSeat >= len(game.Seats) ||
		game.Seats[startingSeat].Eliminated {
		return errors.New("invalid starting seat")
	}
	game.StartingSeat = startingSeat
	game.ActiveSeat = startingSeat
	r.Game = game
	if gameNumber == 1 {
		r.appendGameLog("roll", startingSeat,
			fmt.Sprintf("%s won the opening roll.", game.Seats[startingSeat].DisplayName))
	} else if randomStartingSeat {
		r.appendGameLog("roll", startingSeat,
			fmt.Sprintf("%s won the roll for Game %d.",
				game.Seats[startingSeat].DisplayName, gameNumber))
	} else {
		r.appendGameLog("starting_player", startingSeat,
			fmt.Sprintf("%s goes first after losing Game %d.",
				game.Seats[startingSeat].DisplayName, gameNumber-1))
	}
	for _, seatIndex := range activeSeats {
		r.appendGameLog("opening_hand", seatIndex,
			fmt.Sprintf("%s drew an opening hand of %d cards.",
				game.Seats[seatIndex].DisplayName, len(game.Seats[seatIndex].Hand)))
	}
	return nil
}

func deckCommanderNames(deck protocol.DeckSelect) []string {
	rawNames := deck.Commanders
	if len(rawNames) == 0 && strings.TrimSpace(deck.Commander) != "" {
		rawNames = []string{deck.Commander}
	}
	names := make([]string, 0, len(rawNames))
	for _, rawName := range rawNames {
		name := strings.TrimSpace(rawName)
		if name == "" {
			continue
		}
		duplicate := false
		for _, existing := range names {
			if strings.EqualFold(existing, name) {
				duplicate = true
				break
			}
		}
		if !duplicate {
			names = append(names, name)
		}
	}
	return names
}

func (r *Room) validateDeck(deck protocol.DeckSelect) error {
	deckName := strings.TrimSpace(deck.Name)
	roomDeckFormat := r.DeckFormat
	if roomDeckFormat == "" {
		roomDeckFormat = protocol.DefaultDeckFormatForTableMode(r.Format)
	}
	deckFormat := strings.ToLower(strings.TrimSpace(deck.DeckFormat))
	if deckFormat == "" {
		deckFormat = protocol.DefaultDeckFormatForTableMode(deck.Format)
	}
	if deckName == "" || utf8.RuneCountInString(deckName) > protocol.MaxDeckNameRunes ||
		containsControlCharacters(deckName) ||
		deck.Format != r.Format || !protocol.ValidDeckFormat(deckFormat) ||
		protocol.TableModeForDeckFormat(deckFormat) != deck.Format ||
		deckFormat != roomDeckFormat || len(deck.Mainboard) == 0 ||
		len(deck.Mainboard)+len(deck.Sideboard) > protocol.MaxDeckEntries {
		return newError(protocol.ErrInvalidDeck)
	}
	commanders := deckCommanderNames(deck)
	if len(commanders) > protocol.MaxCommanders ||
		(protocol.IsCommanderFormat(r.Format) && len(commanders) == 0) {
		return newError(protocol.ErrInvalidDeck)
	}
	for _, commander := range commanders {
		if utf8.RuneCountInString(commander) > protocol.MaxCardNameRunes ||
			containsControlCharacters(commander) {
			return newError(protocol.ErrInvalidDeck)
		}
	}
	mainboardCards := 0
	totalCards := 0
	for boardIndex, cards := range [][]protocol.DeckCard{deck.Mainboard, deck.Sideboard} {
		for _, card := range cards {
			name := strings.TrimSpace(card.Name)
			setCode := strings.TrimSpace(card.SetCode)
			collectorNumber := strings.TrimSpace(card.CollectorNumber)
			typeLine := strings.TrimSpace(card.TypeLine)
			if name == "" || utf8.RuneCountInString(name) > protocol.MaxCardNameRunes ||
				containsControlCharacters(name) ||
				card.Count <= 0 || card.Count > protocol.MaxDeckCards-totalCards ||
				setCode == "" || utf8.RuneCountInString(setCode) > protocol.MaxSetCodeRunes ||
				containsControlCharacters(setCode) ||
				collectorNumber == "" || utf8.RuneCountInString(collectorNumber) > protocol.MaxCollectorNumberRunes ||
				containsControlCharacters(collectorNumber) ||
				utf8.RuneCountInString(typeLine) > protocol.MaxTypeLineRunes ||
				containsControlCharacters(typeLine) {
				return newError(protocol.ErrInvalidDeck)
			}
			totalCards += card.Count
			if boardIndex == 0 {
				mainboardCards += card.Count
			}
		}
	}
	if mainboardCards < protocol.MinMainboardCards {
		return newError(protocol.ErrInvalidDeck)
	}
	for _, commander := range commanders {
		commanderFound := false
		for _, card := range deck.Mainboard {
			if strings.EqualFold(strings.TrimSpace(card.Name), commander) {
				commanderFound = true
				break
			}
		}
		if !commanderFound {
			return newError(protocol.ErrInvalidDeck)
		}
	}
	return nil
}

func containsControlCharacters(value string) bool {
	for _, char := range value {
		if unicode.IsControl(char) {
			return true
		}
	}
	return false
}

func cloneDeck(deck protocol.DeckSelect) protocol.DeckSelect {
	deck.Name = strings.TrimSpace(deck.Name)
	deck.DeckFormat = strings.ToLower(strings.TrimSpace(deck.DeckFormat))
	if deck.DeckFormat == "" {
		deck.DeckFormat = protocol.DefaultDeckFormatForTableMode(deck.Format)
	}
	deck.Commanders = deckCommanderNames(deck)
	if len(deck.Commanders) > 0 {
		deck.Commander = deck.Commanders[0]
	} else {
		deck.Commander = ""
	}
	deck.Mainboard = cloneDeckCards(deck.Mainboard)
	deck.Sideboard = cloneDeckCards(deck.Sideboard)
	return deck
}
