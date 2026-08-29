// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

// TournamentListEntry is public connected-hub discovery metadata. It never
// includes participant names, credentials, connection ids, or deck data.
type TournamentListEntry struct {
	TournamentID     string `json:"tournamentId"`
	Name             string `json:"name"`
	Format           string `json:"format"`
	EventType        string `json:"eventType"`
	Coordinator      string `json:"coordinator"`
	Stage            string `json:"stage"`
	MatchMode        string `json:"matchMode"`
	Status           string `json:"status"`
	Registered       int    `json:"registered"`
	CheckedIn        int    `json:"checkedIn"`
	MaxPlayers       int    `json:"maxPlayers"`
	CurrentRound     int    `json:"currentRound"`
	PlannedRounds    int    `json:"plannedRounds"`
	RegistrationOpen bool   `json:"registrationOpen"`
}

type TournamentListed struct {
	Tournaments []TournamentListEntry `json:"tournaments"`
}

type TournamentCreate struct {
	Name          string                    `json:"name"`
	Format        string                    `json:"format"`
	EventType     string                    `json:"eventType,omitempty"`
	Coordinator   string                    `json:"coordinator,omitempty"`
	MatchMode     string                    `json:"matchMode"`
	RoundMinutes  int                       `json:"roundMinutes"`
	MaxPlayers    int                       `json:"maxPlayers"`
	PlannedRounds int                       `json:"plannedRounds,omitempty"`
	Product       *LimitedProductDefinition `json:"product,omitempty"`
}

type TournamentCreated struct {
	TournamentID   string `json:"tournamentId"`
	OrganizerToken string `json:"organizerToken"`
}

type TournamentEnter struct {
	TournamentID string `json:"tournamentId"`
	Credential   string `json:"credential,omitempty"`
}

type TournamentEntered struct {
	TournamentID  string `json:"tournamentId"`
	Role          string `json:"role"`
	ParticipantID string `json:"participantId,omitempty"`
}

type TournamentLeft struct {
	TournamentID string `json:"tournamentId"`
}

type TournamentRegister struct {
	TournamentID string `json:"tournamentId"`
}

type TournamentRegistered struct {
	TournamentID     string `json:"tournamentId"`
	ParticipantID    string `json:"participantId"`
	ParticipantToken string `json:"participantToken"`
}

type TournamentParticipantCommand struct {
	ParticipantID string `json:"participantId,omitempty"`
}

type TournamentCheckIn struct {
	CheckedIn     bool   `json:"checkedIn"`
	ParticipantID string `json:"participantId,omitempty"`
}

type TournamentChanged struct {
	TournamentID string `json:"tournamentId"`
}

type TournamentResultCommand struct {
	PairingID   string `json:"pairingId"`
	PlayerAWins int    `json:"playerAWins"`
	PlayerBWins int    `json:"playerBWins"`
	DrawnGames  int    `json:"drawnGames"`
}

type TournamentPairingCommand struct {
	PairingID string `json:"pairingId"`
}

type TournamentMatchOpened struct {
	TournamentID string `json:"tournamentId"`
	PairingID    string `json:"pairingId"`
	RoomID       string `json:"roomId"`
}

type TournamentParticipantView struct {
	ParticipantID string              `json:"participantId"`
	DisplayName   string              `json:"displayName"`
	CheckedIn     bool                `json:"checkedIn"`
	Competing     bool                `json:"competing"`
	Dropped       bool                `json:"dropped"`
	Online        bool                `json:"online"`
	Deck          *TournamentDeckView `json:"deck,omitempty"`
}

// TournamentDeckView is published only after a tournament completes.
type TournamentDeckView struct {
	Name       string     `json:"name"`
	Format     string     `json:"format"`
	Commander  string     `json:"commander,omitempty"`
	Commanders []string   `json:"commanders,omitempty"`
	Mainboard  []DeckCard `json:"mainboard"`
	Sideboard  []DeckCard `json:"sideboard"`
}

type TournamentPairingView struct {
	PairingID   string `json:"pairingId"`
	Table       int    `json:"table"`
	PlayerAID   string `json:"playerAId"`
	PlayerAName string `json:"playerAName"`
	PlayerBID   string `json:"playerBId,omitempty"`
	PlayerBName string `json:"playerBName,omitempty"`
	Bye         bool   `json:"bye"`
	RoomID      string `json:"roomId,omitempty"`
	Status      string `json:"status"`
	PlayerAWins int    `json:"playerAWins"`
	PlayerBWins int    `json:"playerBWins"`
	DrawnGames  int    `json:"drawnGames"`
	ReporterID  string `json:"reporterId,omitempty"`
	Corrected   bool   `json:"corrected,omitempty"`
}

type TournamentStandingView struct {
	Rank          int     `json:"rank"`
	ParticipantID string  `json:"participantId"`
	DisplayName   string  `json:"displayName"`
	Wins          int     `json:"wins"`
	Losses        int     `json:"losses"`
	Draws         int     `json:"draws"`
	MatchPoints   int     `json:"matchPoints"`
	OppMatchWin   float64 `json:"oppMatchWin"`
	GameWin       float64 `json:"gameWin"`
	OppGameWin    float64 `json:"oppGameWin"`
	Byes          int     `json:"byes"`
	Dropped       bool    `json:"dropped"`
}

type TournamentSnapshot struct {
	TournamentID   string                      `json:"tournamentId"`
	Name           string                      `json:"name"`
	Format         string                      `json:"format"`
	EventType      string                      `json:"eventType"`
	Coordinator    string                      `json:"coordinator"`
	Stage          string                      `json:"stage"`
	MatchMode      string                      `json:"matchMode"`
	Status         string                      `json:"status"`
	RoundMinutes   int                         `json:"roundMinutes"`
	RoundStartedAt string                      `json:"roundStartedAt,omitempty"`
	MaxPlayers     int                         `json:"maxPlayers"`
	PlannedRounds  int                         `json:"plannedRounds"`
	CurrentRound   int                         `json:"currentRound"`
	Registered     int                         `json:"registered"`
	CheckedIn      int                         `json:"checkedIn"`
	RoundComplete  bool                        `json:"roundComplete"`
	OrganizerName  string                      `json:"organizerName"`
	Role           string                      `json:"role"`
	ParticipantID  string                      `json:"participantId,omitempty"`
	CanRegister    bool                        `json:"canRegister"`
	Participants   []TournamentParticipantView `json:"participants"`
	Pairings       []TournamentPairingView     `json:"pairings"`
	Standings      []TournamentStandingView    `json:"standings"`
}
