// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package limited

import (
	"math/rand"
	"strings"

	"hexproof/server/internal/protocol"
)

type Participant struct {
	ID          string
	DisplayName string
}

type Config struct {
	TournamentID string
	EventType    string
	Product      protocol.LimitedProductDefinition
	Participants []Participant
}

type CardInstance struct {
	ID              string
	Name            string
	SetCode         string
	CollectorNumber string
	TypeLine        string
	Rarity          string
	Finish          string
}

type Pack struct {
	ID    string
	Cards []*CardInstance
}

type PlayerState struct {
	ID                   string
	DisplayName          string
	Pool                 []*CardInstance
	Inbox                []*Pack
	Deck                 *protocol.DeckSelect
	MainboardInstanceIDs []string
	BasicLands           []protocol.LimitedBasicLand
}

type Event struct {
	TournamentID string
	EventType    string
	Stage        string
	Product      *Product
	Players      []*PlayerState
	playerByID   map[string]*PlayerState
	random       *rand.Rand
	packCount    int
	packRound    int
	instanceSeq  int
	packSeq      int
	cubeStock    []*CardInstance
}

const (
	setSealedPacksPerPlayer = 6
	draftPacksPerPlayer     = 3
	draftSeats              = 8
	cubeDraftCardsPerPack   = 15

	MinCubeDraftPlayers = 4
	MaxCubeDraftPlayers = 8
)

func CubeDraftCardsRequired(players int) int {
	return players * draftPacksPerPlayer * cubeDraftCardsPerPack
}

func newCardInstance(id string, card protocol.LimitedCardDefinition) *CardInstance {
	return &CardInstance{
		ID: id, Name: card.Name, SetCode: card.SetCode,
		CollectorNumber: card.CollectorNumber, TypeLine: card.TypeLine,
		Rarity: card.Rarity, Finish: card.Finish,
	}
}

func New(config Config, seed int64) (*Event, error) {
	config.EventType = strings.ToLower(strings.TrimSpace(config.EventType))
	if config.EventType != protocol.LimitedEventSetSealed &&
		config.EventType != protocol.LimitedEventSetDraft &&
		config.EventType != protocol.LimitedEventCubeDraft {
		return nil, fail(ErrInvalid, "unsupported limited event type")
	}
	if len(config.Participants) < 2 || len(config.Participants) > 64 {
		return nil, fail(ErrInvalid, "invalid limited participant count")
	}
	if config.EventType == protocol.LimitedEventSetDraft &&
		len(config.Participants) != draftSeats {
		return nil, fail(ErrInvalid, "draft requires exactly eight players")
	}
	if config.EventType == protocol.LimitedEventCubeDraft &&
		(len(config.Participants) < MinCubeDraftPlayers ||
			len(config.Participants) > MaxCubeDraftPlayers) {
		return nil, fail(ErrInvalid, "Cube draft requires four to eight players")
	}
	product, err := NewProduct(config.Product)
	if err != nil {
		return nil, err
	}
	isCube := config.EventType == protocol.LimitedEventCubeDraft
	if isCube != (product.Definition.ProductType == ProductTypeCube) {
		return nil, fail(ErrInvalid, "limited event and product type do not match")
	}
	packCount := 0
	if config.EventType == protocol.LimitedEventSetSealed {
		packCount = setSealedPacksPerPlayer
	} else if config.EventType == protocol.LimitedEventSetDraft || isCube {
		packCount = draftPacksPerPlayer
	}

	event := &Event{
		TournamentID: config.TournamentID, EventType: config.EventType,
		Product: product, packCount: packCount,
		playerByID: make(map[string]*PlayerState, len(config.Participants)),
		random:     rand.New(rand.NewSource(seed)), // #nosec G404 -- the server supplies a cryptographic seed.
	}
	for _, participant := range config.Participants {
		if !validText(participant.ID, maxProductText) ||
			!validText(participant.DisplayName, protocol.MaxDisplayNameRunes) ||
			event.playerByID[participant.ID] != nil {
			return nil, fail(ErrInvalid, "invalid limited participant")
		}
		player := &PlayerState{ID: participant.ID, DisplayName: participant.DisplayName}
		event.Players = append(event.Players, player)
		event.playerByID[player.ID] = player
	}
	if isCube {
		event.cubeStock = product.cubeStock()
		required := CubeDraftCardsRequired(len(event.Players))
		if len(event.cubeStock) < required {
			return nil, fail(ErrInvalid, "Cube does not contain enough cards")
		}
		event.random.Shuffle(len(event.cubeStock), func(left, right int) {
			event.cubeStock[left], event.cubeStock[right] =
				event.cubeStock[right], event.cubeStock[left]
		})
	}
	if config.EventType == protocol.LimitedEventSetSealed {
		if err := event.dealSetSealed(); err != nil {
			return nil, err
		}
		event.Stage = protocol.LimitedStageDeckBuilding
	} else if config.EventType == protocol.LimitedEventSetDraft || isCube {
		event.Stage = protocol.LimitedStageDraft
		if err := event.startDraftRound(); err != nil {
			return nil, err
		}
	}
	return event, nil
}

func (e *Event) nextInstanceID() string {
	e.instanceSeq++
	return "limited-" + itoa(e.instanceSeq)
}

func (e *Event) nextPack() ([]*CardInstance, error) {
	if e.EventType == protocol.LimitedEventCubeDraft {
		if len(e.cubeStock) < cubeDraftCardsPerPack {
			return nil, fail(ErrInvalid, "Cube cannot fill another draft pack")
		}
		cards := append([]*CardInstance(nil), e.cubeStock[:cubeDraftCardsPerPack]...)
		e.cubeStock = e.cubeStock[cubeDraftCardsPerPack:]
		for _, card := range cards {
			card.ID = e.nextInstanceID()
		}
		return cards, nil
	}
	return e.Product.generatePack(e.random, e.nextInstanceID)
}

func (e *Event) dealSetSealed() error {
	for _, player := range e.Players {
		for packIndex := 0; packIndex < e.packCount; packIndex++ {
			cards, err := e.nextPack()
			if err != nil {
				return err
			}
			player.Pool = append(player.Pool, cards...)
		}
	}
	return nil
}

func (e *Event) Player(participantID string) *PlayerState {
	return e.playerByID[participantID]
}

func (e *Event) AllDecksSubmitted() bool {
	for _, player := range e.Players {
		if player.Deck == nil {
			return false
		}
	}
	return true
}

func (e *Event) EnterCompetition() error {
	if e.Stage != protocol.LimitedStageDeckBuilding || !e.AllDecksSubmitted() {
		return fail(ErrNotReady, "every limited deck must be submitted")
	}
	e.Stage = protocol.LimitedStageCompetition
	return nil
}

func (e *Event) Complete() {
	e.Stage = protocol.LimitedStageCompleted
}

func (e *Event) Cancel() {
	e.Stage = protocol.LimitedStageCancelled
}
