// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

// LimitedCardDefinition is one weighted printing in a product sheet. Weight
// is also the physical quantity when the product is a Cube.
type LimitedCardDefinition struct {
	Name            string `json:"name"`
	SetCode         string `json:"setCode"`
	CollectorNumber string `json:"collectorNumber"`
	TypeLine        string `json:"typeLine,omitempty"`
	Rarity          string `json:"rarity,omitempty"`
	Finish          string `json:"finish,omitempty"`
	Weight          int    `json:"weight"`
}

type LimitedSheetDefinition struct {
	Name            string                  `json:"name"`
	WithReplacement bool                    `json:"withReplacement"`
	Cards           []LimitedCardDefinition `json:"cards"`
}

type LimitedSlotDefinition struct {
	Sheet string `json:"sheet"`
	Count int    `json:"count"`
}

type LimitedPackVariantDefinition struct {
	Weight int                     `json:"weight"`
	Slots  []LimitedSlotDefinition `json:"slots"`
}

// LimitedProductDefinition is locked before an online limited event starts.
// Official definitions are generated data; custom Cube definitions are
// bounded organizer input and use productType "cube".
type LimitedProductDefinition struct {
	ID           string                         `json:"id"`
	Name         string                         `json:"name"`
	SetCode      string                         `json:"setCode,omitempty"`
	ProductType  string                         `json:"productType"`
	Authentic    bool                           `json:"authentic"`
	CardsPerPack int                            `json:"cardsPerPack"`
	Sheets       []LimitedSheetDefinition       `json:"sheets"`
	Variants     []LimitedPackVariantDefinition `json:"variants"`
}

type LimitedCardView struct {
	InstanceID      string `json:"instanceId"`
	Name            string `json:"name"`
	SetCode         string `json:"setCode"`
	CollectorNumber string `json:"collectorNumber"`
	TypeLine        string `json:"typeLine,omitempty"`
	Rarity          string `json:"rarity,omitempty"`
	Finish          string `json:"finish,omitempty"`
}

type LimitedProductView struct {
	ID           string `json:"id"`
	Name         string `json:"name"`
	SetCode      string `json:"setCode,omitempty"`
	ProductType  string `json:"productType"`
	Authentic    bool   `json:"authentic"`
	CardsPerPack int    `json:"cardsPerPack"`
	CardCount    int    `json:"cardCount"`
	ProductHash  string `json:"productHash"`
}

type LimitedParticipantView struct {
	ParticipantID string `json:"participantId"`
	DisplayName   string `json:"displayName"`
	Picked        int    `json:"picked"`
	PackCards     int    `json:"packCards"`
	QueuedPacks   int    `json:"queuedPacks"`
	DeckSubmitted bool   `json:"deckSubmitted"`
}

type LimitedBasicLand struct {
	Name            string `json:"name"`
	Count           int    `json:"count"`
	SetCode         string `json:"setCode,omitempty"`
	CollectorNumber string `json:"collectorNumber,omitempty"`
	TypeLine        string `json:"typeLine,omitempty"`
}

type LimitedPick struct {
	InstanceID string `json:"instanceId"`
}

type LimitedCreateCasualMatch struct {
	PlayerAID string `json:"playerAId"`
	PlayerBID string `json:"playerBId"`
}

type LimitedPicked struct {
	TournamentID string `json:"tournamentId"`
	Remaining    int    `json:"remaining"`
}

type LimitedSubmitDeck struct {
	Name                 string             `json:"name"`
	MainboardInstanceIDs []string           `json:"mainboardInstanceIds"`
	BasicLands           []LimitedBasicLand `json:"basicLands"`
}

type LimitedDeckSubmitted struct {
	TournamentID   string `json:"tournamentId"`
	MainboardCount int    `json:"mainboardCount"`
	SideboardCount int    `json:"sideboardCount"`
}

// LimitedSnapshot is role-specific. CurrentPack and Pool are empty unless the
// recipient owns the participant projection.
type LimitedSnapshot struct {
	TournamentID         string                   `json:"tournamentId"`
	EventType            string                   `json:"eventType"`
	Stage                string                   `json:"stage"`
	Product              LimitedProductView       `json:"product"`
	PackRound            int                      `json:"packRound"`
	Direction            int                      `json:"direction"`
	CurrentPack          []LimitedCardView        `json:"currentPack"`
	Pool                 []LimitedCardView        `json:"pool"`
	MainboardInstanceIDs []string                 `json:"mainboardInstanceIds"`
	BasicLands           []LimitedBasicLand       `json:"basicLands"`
	Participants         []LimitedParticipantView `json:"participants"`
	DeckSubmitted        bool                     `json:"deckSubmitted"`
	AllDecksSubmitted    bool                     `json:"allDecksSubmitted"`
}
