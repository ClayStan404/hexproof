// SPDX-License-Identifier: GPL-2.0-only
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
	MatchMode     string
	RoundMinutes  int
	MaxPlayers    int
	PlannedRounds int
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
	nextParticipant         int
	nextPairing             int
}

func New(id string, config Config, organizerName, organizerConnectionID string,
	organizerCredential [sha256.Size]byte, now time.Time) (*Tournament, error) {
	config.Name = strings.TrimSpace(config.Name)
	config.Format = strings.TrimSpace(config.Format)
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
		config.MaxPlayers = 64
	}
	if config.MaxPlayers < MinParticipants || config.MaxPlayers > MaxParticipants {
		return nil, fail(ErrInvalid, "participant capacity is outside the supported range")
	}
	if config.PlannedRounds < 0 || config.PlannedRounds > 20 {
		return nil, fail(ErrInvalid, "round count is outside the supported range")
	}
	return &Tournament{
		ID:                    id,
		Name:                  config.Name,
		Format:                config.Format,
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
	}, nil
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
	case players < MinParticipants:
		return 0
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
	if !t.actorIsCurrent(actor) || t.Status != StatusRunning {
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
	if len(competing) < MinParticipants {
		return fail(ErrNotReady, "at least four checked-in players are required")
	}
	if t.PlannedRounds == 0 {
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
	t.Rounds = append(t.Rounds, t.buildRound(competing, now.UTC()))
	return nil
}

func (t *Tournament) Cancel(actor Actor, now time.Time) error {
	if actor.Role != RoleOrganizer || !t.actorIsCurrent(actor) {
		return fail(ErrForbidden, "only the organizer can cancel the tournament")
	}
	if t.Status == StatusCompleted || t.Status == StatusCancelled {
		return fail(ErrInvalid, "tournament is already closed")
	}
	t.Status = StatusCancelled
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
	if t.Status != StatusRunning {
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
	if !t.RoundComplete() {
		return fail(ErrRoundIncomplete, "every pairing must have a confirmed result")
	}
	if len(t.Rounds) >= t.PlannedRounds {
		t.Status = StatusCompleted
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
		t.ClosedAt = now.UTC()
		return nil
	}
	t.Rounds = append(t.Rounds, t.buildRound(active, now.UTC()))
	return nil
}

func (t *Tournament) Pairing(pairingID string) (*Pairing, error) {
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

func (t *Tournament) Report(actor Actor, pairingID string, score MatchScore,
	now time.Time) error {
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
	if pairing.Bye() || pairing.Result != nil {
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
