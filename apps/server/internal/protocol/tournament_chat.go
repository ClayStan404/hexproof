// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

type TournamentChatSend struct {
	TournamentID string `json:"tournamentId"`
	Text         string `json:"text"`
}

type TournamentChatMessage struct {
	TournamentID string `json:"tournamentId"`
	Sequence     int    `json:"sequence"`
	DisplayName  string `json:"displayName"`
	Text         string `json:"text"`
	SentAt       string `json:"sentAt"`
}

type TournamentChatHistory struct {
	TournamentID string                  `json:"tournamentId"`
	Messages     []TournamentChatMessage `json:"messages"`
}
