// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package tournament implements account-free individual Swiss tournament
// state. It deliberately manages organization and results, not Magic rules or
// deck legality.
package tournament

import (
	"crypto/sha256"
	"fmt"
	"math/rand"
	"sort"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"hexproof/server/internal/limited"
	"hexproof/server/internal/protocol"
)

const (
	StatusRegistration = "registration"
	StatusRunning      = "running"
	StatusCompleted    = "completed"
	StatusCancelled    = "cancelled"

	RoleViewer      = "viewer"
	RoleParticipant = "participant"
	RoleOrganizer   = "organizer"

	MaxNameRunes     = 128
	MaxFormatRunes   = 64
	MaxParticipants  = 512
	MinParticipants  = 4
	MinRoundMinutes  = 40
	MaxRoundMinutes  = 240
	MaxReportedGames = 20
)

// CredentialHash returns a non-reversible tournament-local credential digest.
func CredentialHash(token string) [sha256.Size]byte {
	return sha256.Sum256([]byte(token))
}

type Config struct {
	Name          string
	Format        string
	EventType     string
	Coordinator   string
	MatchMode     string
	RoundMinutes  int
	MaxPlayers    int
	PlannedRounds int
	Product       *protocol.LimitedProductDefinition
}

type Actor struct {
	ConnectionID  string
	Role          string
	ParticipantID string
}

type Participant struct {
	ID             string
	DisplayName    string
	CredentialHash [sha256.Size]byte
	ConnectionID   string
	RegisteredAt   time.Time
	CheckedIn      bool
	Competing      bool
	Dropped        bool
	ByeCount       int
	InitialOrder   int
	Deck           *protocol.DeckSelect
}

type MatchScore struct {
	PlayerAWins int
	PlayerBWins int
	DrawnGames  int
}

type PendingResult struct {
	Score      MatchScore
	ReporterID string
	ReportedAt time.Time
}

type ConfirmedResult struct {
	Score       MatchScore
	ConfirmedBy string
	ConfirmedAt time.Time
	Corrected   bool
}

type Pairing struct {
	ID        string
	Table     int
	PlayerAID string
	PlayerBID string
	RoomID    string
	Pending   *PendingResult
	Result    *ConfirmedResult
}

func (p Pairing) Bye() bool {
	return p.PlayerBID == ""
}

type Round struct {
	Number    int
	Pairings  []Pairing
	StartedAt time.Time
}

// Tournament is mutated only while its registry entry lock is held.
type Tournament struct {
	ID                      string
	Name                    string
	Format                  string
	EventType               string
	Coordinator             string
	Stage                   string
	MatchMode               string
	RoundMinutes            int
	MaxPlayers              int
	PlannedRounds           int
	Status                  string
	OrganizerName           string
	OrganizerConnectionID   string
	OrganizerCredential     [sha256.Size]byte
	OrganizerParticipantID  string
	CreatedAt               time.Time
	LastActivityAt          time.Time
	OrganizerDisconnectedAt time.Time
	ClosedAt                time.Time
	Participants            []*Participant
	participantByID         map[string]*Participant
	Rounds                  []Round
	CasualPairings          []Pairing
	nextParticipant         int
	nextPairing             int
	Limited                 *limited.Event
	limitedProduct          *protocol.LimitedProductDefinition
	limitedProductView      *protocol.LimitedProductView
}

func New(id string, config Config, organizerName, organizerConnectionID string,
	organizerCredential [sha256.Size]byte, now time.Time) (*Tournament, error) {
	config.Name = strings.TrimSpace(config.Name)
	config.Format = strings.TrimSpace(config.Format)
	config.EventType = strings.ToLower(strings.TrimSpace(config.EventType))
	config.Coordinator = strings.ToLower(strings.TrimSpace(config.Coordinator))
	if config.EventType == "" {
		config.EventType = protocol.LimitedEventConstructed
	}
	if config.Coordinator == "" {
		config.Coordinator = protocol.LimitedCoordinatorSwiss
	}
	if !validText(config.Name, MaxNameRunes) || !validText(config.Format, MaxFormatRunes) {
		return nil, fail(ErrInvalid, "invalid tournament name or format")
	}
	if config.MatchMode != "bo1" && config.MatchMode != "bo3" {
		return nil, fail(ErrInvalid, "match mode must be bo1 or bo3")
	}
	if config.RoundMinutes == 0 {
		config.RoundMinutes = 50
	}
	if config.RoundMinutes < MinRoundMinutes || config.RoundMinutes > MaxRoundMinutes {
		return nil, fail(ErrInvalid, "round time is outside the supported range")
	}
	if config.MaxPlayers == 0 {
		switch config.EventType {
		case protocol.LimitedEventSetDraft:
			config.MaxPlayers = limited.MaxSetDraftPlayers
		case protocol.LimitedEventCubeDraft:
			config.MaxPlayers = limited.MaxCubeDraftPlayers
		default:
			config.MaxPlayers = 64
		}
	}
	minimumCapacity := minimumPlayersFor(config.EventType, config.Coordinator)
	if config.MaxPlayers < minimumCapacity || config.MaxPlayers > MaxParticipants {
		return nil, fail(ErrInvalid, "participant capacity is outside the supported range")
	}
	if config.PlannedRounds < 0 || config.PlannedRounds > 20 {
		return nil, fail(ErrInvalid, "round count is outside the supported range")
	}
	if config.EventType != protocol.LimitedEventConstructed &&
		config.EventType != protocol.LimitedEventSetSealed &&
		config.EventType != protocol.LimitedEventSetDraft &&
		config.EventType != protocol.LimitedEventCubeDraft {
		return nil, fail(ErrInvalid, "unsupported tournament event type")
	}
	if config.Coordinator != protocol.LimitedCoordinatorSwiss &&
		config.Coordinator != protocol.LimitedCoordinatorCasual {
		return nil, fail(ErrInvalid, "unsupported event coordinator")
	}
	if config.EventType == protocol.LimitedEventConstructed {
		if config.Coordinator != protocol.LimitedCoordinatorSwiss {
			return nil, fail(ErrInvalid, "constructed events require Swiss coordination")
		}
		config.Product = nil
	} else if config.Product == nil {
		return nil, fail(ErrInvalid, "limited tournaments require a product")
	}
	if config.Coordinator == protocol.LimitedCoordinatorCasual {
		config.PlannedRounds = 0
	}
	if config.EventType != protocol.LimitedEventConstructed && config.MaxPlayers > 64 {
		return nil, fail(ErrInvalid, "limited tournaments support at most 64 players")
	}
	if config.EventType == protocol.LimitedEventSetDraft &&
		(config.MaxPlayers < limited.MinSetDraftPlayers ||
			config.MaxPlayers > limited.MaxSetDraftPlayers) {
		return nil, fail(ErrInvalid, "draft supports two to eight seats")
	}
	if config.EventType == protocol.LimitedEventCubeDraft &&
		(config.MaxPlayers < limited.MinCubeDraftPlayers ||
			config.MaxPlayers > limited.MaxCubeDraftPlayers) {
		return nil, fail(ErrInvalid, "Cube draft supports two to eight seats")
	}
	var product *protocol.LimitedProductDefinition
	var productView *protocol.LimitedProductView
	if config.Product != nil {
		cloned := cloneLimitedProduct(*config.Product)
		validated, validationErr := limited.NewProduct(cloned)
		if validationErr != nil {
			return nil, fail(ErrInvalid, validationErr.Error())
		}
		if config.EventType == protocol.LimitedEventCubeDraft {
			requiredCards := limited.CubeDraftCardsRequired(config.MaxPlayers)
			if validated.View().CardCount < requiredCards {
				return nil, fail(ErrInvalid, fmt.Sprintf(
					"Cube draft requires at least %d physical cards for %d seats",
					requiredCards, config.MaxPlayers))
			}
		}
		product = &cloned
		view := validated.View()
		productView = &view
	}
	return &Tournament{
		ID:                    id,
		Name:                  config.Name,
		Format:                config.Format,
		EventType:             config.EventType,
		Coordinator:           config.Coordinator,
		Stage:                 protocol.LimitedStageRegistration,
		MatchMode:             config.MatchMode,
		RoundMinutes:          config.RoundMinutes,
		MaxPlayers:            config.MaxPlayers,
		PlannedRounds:         config.PlannedRounds,
		Status:                StatusRegistration,
		OrganizerName:         organizerName,
		OrganizerConnectionID: organizerConnectionID,
		OrganizerCredential:   organizerCredential,
		CreatedAt:             now.UTC(),
		LastActivityAt:        now.UTC(),
		participantByID:       make(map[string]*Participant),
		limitedProduct:        product,
		limitedProductView:    productView,
	}, nil
}

// LimitedProductView exposes the immutable, public product summary without
// disclosing collation sheets before the event starts.
func (t *Tournament) LimitedProductView() *protocol.LimitedProductView {
	if t.limitedProductView == nil {
		return nil
	}
	view := *t.limitedProductView
	return &view
}

// minimumPlayersFor is the single source of truth for the checked-in count a
// tournament needs before it can start. New() enforces it as the capacity
// floor and Start() enforces it against checked-in players, so the two
// validations can never drift apart. Casual coordination always allows two.
func minimumPlayersFor(eventType, coordinator string) int {
	if coordinator == protocol.LimitedCoordinatorCasual {
		return 2
	}
	switch eventType {
	case protocol.LimitedEventSetSealed:
		return limited.MinSetSealedPlayers
	case protocol.LimitedEventSetDraft:
		return limited.MinSetDraftPlayers
	case protocol.LimitedEventCubeDraft:
		return limited.MinCubeDraftPlayers
	default:
		return MinParticipants
	}
}

// MinimumPlayers reports the checked-in count this tournament needs to start.
func (t *Tournament) MinimumPlayers() int {
	return minimumPlayersFor(t.EventType, t.Coordinator)
}

func validText(value string, maxRunes int) bool {
	if value == "" || utf8.RuneCountInString(value) > maxRunes {
		return false
	}
	for _, char := range value {
		if unicode.IsControl(char) {
			return false
		}
	}
	return true
}

func RecommendedRounds(players int) int {
	switch {
	case players < 2:
		return 0
	case players == 2:
		return 1
	case players <= 8:
		return 3
	case players <= 32:
		return 5
	case players <= 64:
		return 6
	case players <= 128:
		return 7
	case players <= 226:
		return 8
	case players <= 409:
		return 9
	default:
		return 10
	}
}

func (t *Tournament) Participant(id string) *Participant {
	return t.participantByID[id]
}

func (t *Tournament) Register(displayName, connectionID string,
	credential [sha256.Size]byte, now time.Time) (*Participant, error) {
	if t.Status != StatusRegistration {
		return nil, fail(ErrRegistrationClosed, "registration is closed")
	}
	displayName = strings.TrimSpace(displayName)
	if !validText(displayName, 64) {
		return nil, fail(ErrInvalid, "invalid participant name")
	}
	if len(t.Participants) >= t.MaxPlayers {
		return nil, fail(ErrFull, "tournament is full")
	}
	for _, participant := range t.Participants {
		if strings.EqualFold(participant.DisplayName, displayName) {
			return nil, fail(ErrAlreadyRegistered, "display name is already registered")
		}
	}
	t.nextParticipant++
	participant := &Participant{
		ID:             fmt.Sprintf("p-%d", t.nextParticipant),
		DisplayName:    displayName,
		CredentialHash: credential,
		ConnectionID:   connectionID,
		RegisteredAt:   now.UTC(),
		InitialOrder:   len(t.Participants),
	}
	t.Participants = append(t.Participants, participant)
	t.participantByID[participant.ID] = participant
	return participant, nil
}

func (t *Tournament) Unregister(actor Actor) error {
	if !t.actorIsCurrent(actor) {
		return fail(ErrForbidden, "tournament role is not owned by this session")
	}
	if t.Status != StatusRegistration {
		return fail(ErrRegistrationClosed, "registration is closed")
	}
	participant := t.participantByID[actor.ParticipantID]
	if participant == nil {
		return fail(ErrForbidden, "participant registration is not owned by this session")
	}
	delete(t.participantByID, participant.ID)
	for index, candidate := range t.Participants {
		if candidate == participant {
			t.Participants = append(t.Participants[:index], t.Participants[index+1:]...)
			break
		}
	}
	return nil
}

// RecordDeck retains the last deck selected by a participant in a private
// pairing room. It remains server-private until the tournament is complete.
func (t *Tournament) RecordDeck(actor Actor, deck protocol.DeckSelect) bool {
	if !t.actorIsCurrent(actor) || t.Status != StatusRunning || t.Limited != nil {
		return false
	}
	participant := t.participantByID[actor.ParticipantID]
	if participant == nil {
		return false
	}
	cloned := cloneDeck(deck)
	participant.Deck = &cloned
	return true
}

func cloneDeck(deck protocol.DeckSelect) protocol.DeckSelect {
	deck.Commanders = append([]string(nil), deck.Commanders...)
	deck.Mainboard = append([]protocol.DeckCard(nil), deck.Mainboard...)
	deck.Sideboard = append([]protocol.DeckCard(nil), deck.Sideboard...)
	return deck
}

func cloneLimitedProduct(product protocol.LimitedProductDefinition) protocol.LimitedProductDefinition {
	product.Sheets = append([]protocol.LimitedSheetDefinition(nil), product.Sheets...)
	for index := range product.Sheets {
		product.Sheets[index].Cards = append(
			[]protocol.LimitedCardDefinition(nil), product.Sheets[index].Cards...)
	}
	product.Variants = append([]protocol.LimitedPackVariantDefinition(nil), product.Variants...)
	for index := range product.Variants {
		product.Variants[index].Slots = append(
			[]protocol.LimitedSlotDefinition(nil), product.Variants[index].Slots...)
	}
	return product
}

// BindCredential resolves and rebinds an organizer or participant credential.
func (t *Tournament) BindCredential(credential [sha256.Size]byte,
	connectionID string, now time.Time) (role, participantID string, ok bool) {
	if credential == t.OrganizerCredential {
		t.OrganizerConnectionID = connectionID
		t.OrganizerDisconnectedAt = time.Time{}
		t.LastActivityAt = now.UTC()
		if participant := t.participantByID[t.OrganizerParticipantID]; participant != nil {
			participant.ConnectionID = connectionID
		}
		return RoleOrganizer, t.OrganizerParticipantID, true
	}
	for _, participant := range t.Participants {
		if credential == participant.CredentialHash {
			participant.ConnectionID = connectionID
			t.LastActivityAt = now.UTC()
			return RoleParticipant, participant.ID, true
		}
	}
	return "", "", false
}

func (t *Tournament) Disconnect(connectionID string, now time.Time) {
	changed := false
	if t.OrganizerConnectionID == connectionID {
		t.OrganizerConnectionID = ""
		t.OrganizerDisconnectedAt = now.UTC()
		changed = true
	}
	for _, participant := range t.Participants {
		if participant.ConnectionID == connectionID {
			participant.ConnectionID = ""
			changed = true
		}
	}
	if changed {
		t.LastActivityAt = now.UTC()
	}
}

// actorIsCurrent revalidates a cached session binding at every mutation
// boundary. BindCredential intentionally transfers a credential to the newest
// connection, so an older transport must immediately lose tournament authority.
func (t *Tournament) actorIsCurrent(actor Actor) bool {
	if strings.TrimSpace(actor.ConnectionID) == "" {
		return false
	}
	switch actor.Role {
	case RoleOrganizer:
		return t.OrganizerConnectionID == actor.ConnectionID
	case RoleParticipant:
		participant := t.participantByID[actor.ParticipantID]
		return participant != nil && participant.ConnectionID == actor.ConnectionID
	default:
		return false
	}
}

func (t *Tournament) SetCheckedIn(actor Actor, checkedIn bool) error {
	if !t.actorIsCurrent(actor) {
		return fail(ErrForbidden, "tournament role is not owned by this session")
	}
	if t.Status != StatusRegistration {
		return fail(ErrRegistrationClosed, "check-in is closed")
	}
	participant := t.participantByID[actor.ParticipantID]
	if participant == nil {
		return fail(ErrForbidden, "participant check-in is not owned by this session")
	}
	participant.CheckedIn = checkedIn
	return nil
}

func (t *Tournament) Start(actor Actor, seed int64, now time.Time) error {
	if actor.Role != RoleOrganizer || !t.actorIsCurrent(actor) {
		return fail(ErrForbidden, "only the organizer can start the tournament")
	}
	if t.Status == StatusRunning && t.Limited != nil &&
		t.Stage == protocol.LimitedStageDeckBuilding {
		if err := t.Limited.EnterCompetition(); err != nil {
			return fail(ErrNotReady, err.Error())
		}
		t.Stage = protocol.LimitedStageCompetition
		if t.Coordinator == protocol.LimitedCoordinatorSwiss {
			t.Rounds = append(t.Rounds, t.buildRound(t.activeParticipants(), now.UTC()))
		}
		return nil
	}
	if t.Status != StatusRegistration {
		return fail(ErrInvalid, "tournament has already started")
	}
	competing := make([]*Participant, 0, len(t.Participants))
	for _, participant := range t.Participants {
		participant.Competing = participant.CheckedIn
		if participant.Competing {
			competing = append(competing, participant)
		}
	}
	minimumPlayers := t.MinimumPlayers()
	if len(competing) < minimumPlayers {
		return failMinimumPlayers(minimumPlayers)
	}
	if t.Coordinator == protocol.LimitedCoordinatorSwiss && t.PlannedRounds == 0 {
		t.PlannedRounds = RecommendedRounds(len(competing))
	}
	random := rand.New(rand.NewSource(seed)) // #nosec G404 -- seed is generated cryptographically by the server.
	random.Shuffle(len(competing), func(left, right int) {
		competing[left], competing[right] = competing[right], competing[left]
	})
	for index, participant := range competing {
		participant.InitialOrder = index
	}
	t.Status = StatusRunning
	if t.EventType != protocol.LimitedEventConstructed {
		participants := make([]limited.Participant, 0, len(competing))
		for _, participant := range competing {
			participants = append(participants, limited.Participant{
				ID: participant.ID, DisplayName: participant.DisplayName,
			})
		}
		event, err := limited.New(limited.Config{
			TournamentID: t.ID, EventType: t.EventType,
			Product: *t.limitedProduct, Participants: participants,
		}, seed)
		if err != nil {
			t.Status = StatusRegistration
			for _, participant := range competing {
				participant.Competing = false
			}
			return fail(ErrInvalid, err.Error())
		}
		t.Limited = event
		t.Stage = event.Stage
		return nil
	}
	t.Stage = protocol.LimitedStageCompetition
	t.Rounds = append(t.Rounds, t.buildRound(competing, now.UTC()))
	return nil
}

func (t *Tournament) activeParticipants() []*Participant {
	active := make([]*Participant, 0, len(t.Participants))
	for _, participant := range t.Participants {
		if participant.Competing && !participant.Dropped {
			active = append(active, participant)
		}
	}
	sort.Slice(active, func(left, right int) bool {
		return active[left].InitialOrder < active[right].InitialOrder
	})
	return active
}

func (t *Tournament) PickLimited(actor Actor, instanceID string) (int, error) {
	if !t.actorIsCurrent(actor) || actor.ParticipantID == "" || t.Limited == nil {
		return 0, fail(ErrForbidden, "limited seat is not owned by this session")
	}
	remaining, err := t.Limited.Pick(actor.ParticipantID, instanceID)
	if err != nil {
		return 0, err
	}
	t.Stage = t.Limited.Stage
	return remaining, nil
}

func (t *Tournament) SubmitLimitedDeck(actor Actor,
	request protocol.LimitedSubmitDeck) (*protocol.DeckSelect, error) {
	if !t.actorIsCurrent(actor) || actor.ParticipantID == "" || t.Limited == nil {
		return nil, fail(ErrForbidden, "limited pool is not owned by this session")
	}
	deck, err := t.Limited.SubmitDeck(actor.ParticipantID, request)
	if err != nil {
		return nil, err
	}
	participant := t.participantByID[actor.ParticipantID]
	if participant == nil {
		return nil, fail(ErrForbidden, "limited participant was not found")
	}
	cloned := cloneDeck(*deck)
	participant.Deck = &cloned
	return &cloned, nil
}

func (t *Tournament) LimitedSnapshot(participantID string) *protocol.LimitedSnapshot {
	if t.Limited == nil {
		return nil
	}
	snapshot := t.Limited.Snapshot(participantID)
	return &snapshot
}

func (t *Tournament) Cancel(actor Actor, now time.Time) error {
	if actor.Role != RoleOrganizer || !t.actorIsCurrent(actor) {
		return fail(ErrForbidden, "only the organizer can cancel the tournament")
	}
	if t.Status == StatusCompleted || t.Status == StatusCancelled {
		return fail(ErrInvalid, "tournament is already closed")
	}
	t.Status = StatusCancelled
	t.Stage = protocol.LimitedStageCancelled
	if t.Limited != nil {
		t.Limited.Cancel()
	}
	t.ClosedAt = now.UTC()
	return nil
}

func (t *Tournament) IsTerminal() bool {
	return t.Status == StatusCompleted || t.Status == StatusCancelled
}

func (t *Tournament) Drop(actor Actor, participantID string) error {
	if !t.actorIsCurrent(actor) {
		return fail(ErrForbidden, "tournament role is not owned by this session")
	}
	if t.Status != StatusRunning || t.Stage != protocol.LimitedStageCompetition {
		return fail(ErrInvalid, "tournament is not running")
	}
	if participantID == "" {
		participantID = actor.ParticipantID
	}
	participant := t.participantByID[participantID]
	if participant == nil {
		return fail(ErrNotFound, "participant not found")
	}
	if !participant.Competing || participant.Dropped {
		return fail(ErrInvalid, "participant is not active")
	}
	if actor.Role != RoleOrganizer && actor.ParticipantID != participantID {
		return fail(ErrForbidden, "cannot drop another participant")
	}
	participant.Dropped = true
	return nil
}

func (t *Tournament) CurrentRound() *Round {
	if len(t.Rounds) == 0 {
		return nil
	}
	return &t.Rounds[len(t.Rounds)-1]
}

func (t *Tournament) RoundComplete() bool {
	if t.Coordinator != protocol.LimitedCoordinatorSwiss {
		return false
	}
	round := t.CurrentRound()
	if round == nil {
		return false
	}
	for index := range round.Pairings {
		if round.Pairings[index].Result == nil {
			return false
		}
	}
	return true
}

func (t *Tournament) Advance(actor Actor, now time.Time) error {
	if actor.Role != RoleOrganizer || !t.actorIsCurrent(actor) {
		return fail(ErrForbidden, "only the organizer can advance rounds")
	}
	if t.Status != StatusRunning {
		return fail(ErrInvalid, "tournament is not running")
	}
	if t.Coordinator != protocol.LimitedCoordinatorSwiss {
		return fail(ErrInvalid, "casual limited play has no rounds")
	}
	if !t.RoundComplete() {
		return fail(ErrRoundIncomplete, "every pairing must have a confirmed result")
	}
	if len(t.Rounds) >= t.PlannedRounds {
		t.Status = StatusCompleted
		t.Stage = protocol.LimitedStageCompleted
		if t.Limited != nil {
			t.Limited.Complete()
		}
		t.ClosedAt = now.UTC()
		return nil
	}
	standings := t.Standings()
	active := make([]*Participant, 0, len(standings))
	for _, standing := range standings {
		participant := t.participantByID[standing.ParticipantID]
		if participant != nil && participant.Competing && !participant.Dropped {
			active = append(active, participant)
		}
	}
	if len(active) < 2 {
		t.Status = StatusCompleted
		t.Stage = protocol.LimitedStageCompleted
		if t.Limited != nil {
			t.Limited.Complete()
		}
		t.ClosedAt = now.UTC()
		return nil
	}
	t.Rounds = append(t.Rounds, t.buildRound(active, now.UTC()))
	return nil
}

func (t *Tournament) Pairing(pairingID string) (*Pairing, error) {
	for index := range t.CasualPairings {
		pairing := &t.CasualPairings[index]
		if pairing.ID == pairingID {
			return pairing, nil
		}
	}
	for roundIndex := range t.Rounds {
		for pairingIndex := range t.Rounds[roundIndex].Pairings {
			pairing := &t.Rounds[roundIndex].Pairings[pairingIndex]
			if pairing.ID == pairingID {
				return pairing, nil
			}
		}
	}
	return nil, fail(ErrNotFound, "pairing not found")
}

func (t *Tournament) CurrentPairing(participantID string) *Pairing {
	if t.Coordinator == protocol.LimitedCoordinatorCasual {
		for index := len(t.CasualPairings) - 1; index >= 0; index-- {
			pairing := &t.CasualPairings[index]
			if pairing.PlayerAID == participantID || pairing.PlayerBID == participantID {
				return pairing
			}
		}
		return nil
	}
	round := t.CurrentRound()
	if round == nil {
		return nil
	}
	for index := range round.Pairings {
		pairing := &round.Pairings[index]
		if pairing.PlayerAID == participantID || pairing.PlayerBID == participantID {
			return pairing
		}
	}
	return nil
}

func (t *Tournament) CreateCasualMatch(actor Actor, playerAID, playerBID string) (*Pairing, error) {
	if actor.Role != RoleOrganizer || !t.actorIsCurrent(actor) {
		return nil, fail(ErrForbidden, "only the organizer can create a casual match")
	}
	if t.Coordinator != protocol.LimitedCoordinatorCasual || t.Status != StatusRunning ||
		t.Stage != protocol.LimitedStageCompetition {
		return nil, fail(ErrInvalid, "casual limited play is not ready")
	}
	if playerAID == "" || playerAID == playerBID {
		return nil, fail(ErrInvalid, "choose two different players")
	}
	for _, participantID := range []string{playerAID, playerBID} {
		participant := t.participantByID[participantID]
		if participant == nil || !participant.Competing || participant.Dropped ||
			participant.Deck == nil || participant.ConnectionID == "" {
			return nil, fail(ErrNotReady, "both players must be online with submitted decks")
		}
		for index := range t.CasualPairings {
			pairing := &t.CasualPairings[index]
			if pairing.RoomID != "" &&
				(pairing.PlayerAID == participantID || pairing.PlayerBID == participantID) {
				return nil, fail(ErrNotReady, "a selected player already has an open table")
			}
		}
	}
	t.nextPairing++
	t.CasualPairings = append(t.CasualPairings, Pairing{
		ID: fmt.Sprintf("casual-%d", t.nextPairing), Table: len(t.CasualPairings) + 1,
		PlayerAID: playerAID, PlayerBID: playerBID,
	})
	return &t.CasualPairings[len(t.CasualPairings)-1], nil
}

func (t *Tournament) VisiblePairings() []Pairing {
	if t.Coordinator == protocol.LimitedCoordinatorCasual {
		return append([]Pairing(nil), t.CasualPairings...)
	}
	if round := t.CurrentRound(); round != nil {
		return append([]Pairing(nil), round.Pairings...)
	}
	return nil
}

func (t *Tournament) Report(actor Actor, pairingID string, score MatchScore,
	now time.Time) error {
	if !t.actorIsCurrent(actor) {
		return fail(ErrForbidden, "tournament role is not owned by this session")
	}
	if t.Status != StatusRunning {
		return fail(ErrInvalid, "tournament is not running")
	}
	if t.Coordinator != protocol.LimitedCoordinatorSwiss {
		return fail(ErrInvalid, "casual matches do not report standings")
	}
	pairing, err := t.Pairing(pairingID)
	if err != nil {
		return err
	}
	if pairing.Bye() || pairing.Result != nil || pairing.Pending != nil {
		return fail(ErrResultInvalid, "pairing does not accept a report")
	}
	if actor.ParticipantID != pairing.PlayerAID && actor.ParticipantID != pairing.PlayerBID {
		return fail(ErrForbidden, "only paired players can report this result")
	}
	if err := t.validateScore(score); err != nil {
		return err
	}
	pairing.Pending = &PendingResult{
		Score: score, ReporterID: actor.ParticipantID, ReportedAt: now.UTC(),
	}
	return nil
}

func (t *Tournament) Confirm(actor Actor, pairingID string, now time.Time) error {
	if !t.actorIsCurrent(actor) {
		return fail(ErrForbidden, "tournament role is not owned by this session")
	}
	if t.Status != StatusRunning {
		return fail(ErrInvalid, "tournament is not running")
	}
	if t.Coordinator != protocol.LimitedCoordinatorSwiss {
		return fail(ErrInvalid, "casual matches do not report standings")
	}
	pairing, err := t.Pairing(pairingID)
	if err != nil {
		return err
	}
	if pairing.Pending == nil || pairing.Result != nil {
		return fail(ErrResultInvalid, "pairing has no pending result")
	}
	if actor.Role != RoleOrganizer {
		if actor.ParticipantID != pairing.PlayerAID && actor.ParticipantID != pairing.PlayerBID {
			return fail(ErrForbidden, "only paired players can confirm this result")
		}
		if actor.ParticipantID == pairing.Pending.ReporterID {
			return fail(ErrForbidden, "the reporting player cannot self-confirm")
		}
	}
	pairing.Result = &ConfirmedResult{
		Score: pairing.Pending.Score, ConfirmedBy: actor.ParticipantID,
		ConfirmedAt: now.UTC(),
	}
	pairing.Pending = nil
	return nil
}

func (t *Tournament) Reject(actor Actor, pairingID string) error {
	if !t.actorIsCurrent(actor) {
		return fail(ErrForbidden, "tournament role is not owned by this session")
	}
	if t.Status != StatusRunning {
		return fail(ErrInvalid, "tournament is not running")
	}
	if t.Coordinator != protocol.LimitedCoordinatorSwiss {
		return fail(ErrInvalid, "casual matches do not report standings")
	}
	pairing, err := t.Pairing(pairingID)
	if err != nil {
		return err
	}
	if pairing.Pending == nil || pairing.Result != nil {
		return fail(ErrResultInvalid, "pairing has no pending result")
	}
	if actor.Role != RoleOrganizer &&
		(actor.ParticipantID == pairing.Pending.ReporterID ||
			(actor.ParticipantID != pairing.PlayerAID && actor.ParticipantID != pairing.PlayerBID)) {
		return fail(ErrForbidden, "only the other player can reject this result")
	}
	pairing.Pending = nil
	return nil
}

func (t *Tournament) Correct(actor Actor, pairingID string, score MatchScore,
	now time.Time) error {
	if actor.Role != RoleOrganizer || !t.actorIsCurrent(actor) {
		return fail(ErrForbidden, "only the organizer can correct a result")
	}
	if t.Status != StatusRunning {
		return fail(ErrInvalid, "tournament is not running")
	}
	if t.Coordinator != protocol.LimitedCoordinatorSwiss {
		return fail(ErrInvalid, "casual matches do not report standings")
	}
	pairing, err := t.Pairing(pairingID)
	if err != nil {
		return err
	}
	if pairing.Bye() {
		return fail(ErrResultInvalid, "bye results cannot be corrected")
	}
	if err := t.validateScore(score); err != nil {
		return err
	}
	pairing.Pending = nil
	pairing.Result = &ConfirmedResult{
		Score: score, ConfirmedBy: "organizer", ConfirmedAt: now.UTC(), Corrected: true,
	}
	return nil
}

func (t *Tournament) validateScore(score MatchScore) error {
	if score.PlayerAWins < 0 || score.PlayerBWins < 0 || score.DrawnGames < 0 ||
		score.PlayerAWins+score.PlayerBWins+score.DrawnGames > MaxReportedGames {
		return fail(ErrResultInvalid, "invalid game score")
	}
	target := 1
	if t.MatchMode == "bo3" {
		target = 2
	}
	if score.PlayerAWins == score.PlayerBWins {
		if score.PlayerAWins < target {
			return nil
		}
		return fail(ErrResultInvalid, "game score exceeds the configured match")
	}
	winner, loser := score.PlayerAWins, score.PlayerBWins
	if winner < loser {
		winner, loser = loser, winner
	}
	if winner != target || loser >= target {
		return fail(ErrResultInvalid, "game score does not complete the configured match")
	}
	return nil
}

func (t *Tournament) SetPairingRoom(actor Actor, pairingID, roomID string) error {
	if !t.actorIsCurrent(actor) {
		return fail(ErrForbidden, "tournament role is not owned by this session")
	}
	if t.Status != StatusRunning {
		return fail(ErrInvalid, "tournament is not running")
	}
	pairing, err := t.Pairing(pairingID)
	if err != nil {
		return err
	}
	if actor.ParticipantID != pairing.PlayerAID && actor.ParticipantID != pairing.PlayerBID {
		return fail(ErrForbidden, "only paired players can open this table")
	}
	if pairing.Bye() || pairing.Result != nil {
		return fail(ErrInvalid, "pairing does not need a table")
	}
	pairing.RoomID = roomID
	return nil
}

func (t *Tournament) ClearRoom(roomID string) {
	for index := range t.CasualPairings {
		if t.CasualPairings[index].RoomID == roomID {
			t.CasualPairings[index].RoomID = ""
		}
	}
	for roundIndex := range t.Rounds {
		for pairingIndex := range t.Rounds[roundIndex].Pairings {
			pairing := &t.Rounds[roundIndex].Pairings[pairingIndex]
			if pairing.RoomID == roomID {
				pairing.RoomID = ""
			}
		}
	}
}

func (t *Tournament) buildRound(players []*Participant, now time.Time) Round {
	round := Round{Number: len(t.Rounds) + 1, StartedAt: now}
	ordered := append([]*Participant(nil), players...)
	if round.Number > 1 {
		standingRank := make(map[string]int)
		for index, standing := range t.Standings() {
			standingRank[standing.ParticipantID] = index
		}
		sort.SliceStable(ordered, func(left, right int) bool {
			return standingRank[ordered[left].ID] < standingRank[ordered[right].ID]
		})
	}

	var bye *Participant
	if len(ordered)%2 == 1 {
		minimumByes := ordered[0].ByeCount
		for _, participant := range ordered[1:] {
			if participant.ByeCount < minimumByes {
				minimumByes = participant.ByeCount
			}
		}
		for index := len(ordered) - 1; index >= 0; index-- {
			if ordered[index].ByeCount == minimumByes {
				bye = ordered[index]
				ordered = append(ordered[:index], ordered[index+1:]...)
				break
			}
		}
	}

	pairs := t.pairPlayers(ordered, round.Number)
	for _, pair := range pairs {
		t.nextPairing++
		round.Pairings = append(round.Pairings, Pairing{
			ID:        fmt.Sprintf("r%d-m%d", round.Number, t.nextPairing),
			Table:     len(round.Pairings) + 1,
			PlayerAID: pair[0].ID,
			PlayerBID: pair[1].ID,
		})
	}
	if bye != nil {
		t.nextPairing++
		bye.ByeCount++
		round.Pairings = append(round.Pairings, Pairing{
			ID:        fmt.Sprintf("r%d-m%d", round.Number, t.nextPairing),
			Table:     len(round.Pairings) + 1,
			PlayerAID: bye.ID,
			Result: &ConfirmedResult{
				Score: MatchScore{PlayerAWins: 2}, ConfirmedBy: "bye", ConfirmedAt: now,
			},
		})
	}
	return round
}
