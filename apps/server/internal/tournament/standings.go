// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package tournament

import (
	"sort"

	"hexproof/server/internal/protocol"
)

const percentageFloor = 0.33

type Standing struct {
	Rank          int
	ParticipantID string
	DisplayName   string
	Wins          int
	Losses        int
	Draws         int
	MatchPoints   int
	OppMatchWin   float64
	GameWin       float64
	OppGameWin    float64
	Byes          int
	Dropped       bool
	InitialOrder  int
}

type playerStats struct {
	wins, losses, draws int
	matchPoints         int
	matchRounds         int
	gamePoints          int
	gamesPlayed         int
	opponents           []string
}

func flooredPercentage(points, possible int) float64 {
	if possible <= 0 {
		return percentageFloor
	}
	value := float64(points) / float64(possible)
	if value < percentageFloor {
		return percentageFloor
	}
	return value
}

func (t *Tournament) Standings() []Standing {
	if t.Coordinator != protocol.LimitedCoordinatorSwiss {
		return []Standing{}
	}
	stats := make(map[string]*playerStats, len(t.Participants))
	for _, participant := range t.Participants {
		if participant.Competing {
			stats[participant.ID] = &playerStats{}
		}
	}
	for _, round := range t.Rounds {
		for _, pairing := range round.Pairings {
			if pairing.Result == nil {
				continue
			}
			left := stats[pairing.PlayerAID]
			if left == nil {
				continue
			}
			score := pairing.Result.Score
			left.matchRounds++
			left.gamePoints += score.PlayerAWins*3 + score.DrawnGames
			left.gamesPlayed += score.PlayerAWins + score.PlayerBWins + score.DrawnGames
			if pairing.Bye() {
				left.wins++
				left.matchPoints += 3
				continue
			}
			right := stats[pairing.PlayerBID]
			if right == nil {
				continue
			}
			right.matchRounds++
			right.gamePoints += score.PlayerBWins*3 + score.DrawnGames
			right.gamesPlayed += score.PlayerAWins + score.PlayerBWins + score.DrawnGames
			left.opponents = append(left.opponents, pairing.PlayerBID)
			right.opponents = append(right.opponents, pairing.PlayerAID)
			switch {
			case score.PlayerAWins > score.PlayerBWins:
				left.wins++
				right.losses++
				left.matchPoints += 3
			case score.PlayerBWins > score.PlayerAWins:
				right.wins++
				left.losses++
				right.matchPoints += 3
			default:
				left.draws++
				right.draws++
				left.matchPoints++
				right.matchPoints++
			}
		}
	}

	matchWin := make(map[string]float64, len(stats))
	gameWin := make(map[string]float64, len(stats))
	for id, value := range stats {
		matchWin[id] = flooredPercentage(value.matchPoints, value.matchRounds*3)
		gameWin[id] = flooredPercentage(value.gamePoints, value.gamesPlayed*3)
	}

	standings := make([]Standing, 0, len(stats))
	for _, participant := range t.Participants {
		value := stats[participant.ID]
		if value == nil {
			continue
		}
		oppMatchWin := percentageFloor
		oppGameWin := percentageFloor
		if len(value.opponents) > 0 {
			oppMatchWin = 0
			oppGameWin = 0
			for _, opponentID := range value.opponents {
				oppMatchWin += matchWin[opponentID]
				oppGameWin += gameWin[opponentID]
			}
			oppMatchWin /= float64(len(value.opponents))
			oppGameWin /= float64(len(value.opponents))
		}
		standings = append(standings, Standing{
			ParticipantID: participant.ID,
			DisplayName:   participant.DisplayName,
			Wins:          value.wins, Losses: value.losses, Draws: value.draws,
			MatchPoints: value.matchPoints,
			OppMatchWin: oppMatchWin, GameWin: gameWin[participant.ID],
			OppGameWin: oppGameWin, Byes: participant.ByeCount,
			Dropped: participant.Dropped, InitialOrder: participant.InitialOrder,
		})
	}
	sort.SliceStable(standings, func(left, right int) bool {
		first, second := standings[left], standings[right]
		if first.MatchPoints != second.MatchPoints {
			return first.MatchPoints > second.MatchPoints
		}
		if first.OppMatchWin != second.OppMatchWin {
			return first.OppMatchWin > second.OppMatchWin
		}
		if first.GameWin != second.GameWin {
			return first.GameWin > second.GameWin
		}
		if first.OppGameWin != second.OppGameWin {
			return first.OppGameWin > second.OppGameWin
		}
		return first.InitialOrder < second.InitialOrder
	})
	for index := range standings {
		standings[index].Rank = index + 1
	}
	return standings
}
