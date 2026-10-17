// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"testing"
	"time"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
	"hexproof/server/internal/tournament"
)

func TestRoomActionClockChoiceAndAdmission(t *testing.T) {
	for _, test := range []struct {
		name       string
		format     string
		rules      string
		hosting    string
		aiSource   string
		difficulty string
		playtest   bool
		enabled    bool
		invalid    bool
	}{
		{name: "ordinary default", format: protocol.FormatModern, rules: protocol.RulesModeForge},
		{name: "ordinary enabled", format: protocol.FormatModern, rules: protocol.RulesModeForge, enabled: true},
		{name: "Duel Commander", format: protocol.FormatDuel, rules: protocol.RulesModeForge, enabled: true},
		{name: "player hosted", format: protocol.FormatModern, rules: protocol.RulesModeForge, hosting: "player", enabled: true},
		{name: "native AI", format: protocol.FormatModern, rules: protocol.RulesModeForge, aiSource: protocol.AISourceForge, difficulty: "normal", enabled: true},
		{name: "model AI", format: protocol.FormatModern, rules: protocol.RulesModeForge, aiSource: protocol.AISourceLocal, enabled: true},
		{name: "manual rejected", format: protocol.FormatModern, rules: protocol.RulesModeManual, enabled: true, invalid: true},
		{name: "EDH rejected", format: protocol.FormatEDH, rules: protocol.RulesModeForge, enabled: true, invalid: true},
		{name: "Playtest rejected", format: protocol.FormatModern, rules: protocol.RulesModeManual, playtest: true, enabled: true, invalid: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			config := DefaultConfig()
			config.AllowPlayerHosting = true
			h := retentionHandler(t, config)
			h.forgeRuntime, h.forgeNativeAI = &forge.ProcessConfig{}, true
			host := retentionSession(h, "host")
			env, _ := protocol.NewEnvelope(protocol.TypeRoomCreate, protocol.RoomCreate{
				Name: "Clock choice", Format: test.format, MatchMode: protocol.MatchBO1,
				RulesMode: test.rules, HostingMode: test.hosting, Playtest: test.playtest,
				AISource: test.aiSource, AIDifficulty: test.difficulty, ActionClockEnabled: test.enabled,
			})
			if err := h.handleRoomCreate(host, env); err != nil {
				t.Fatal(err)
			}
			if test.invalid {
				if payload := readWireError(t, host); payload.Code != protocol.ErrInvalidMessage {
					t.Fatalf("unsupported action clock: %+v", payload)
				}
				if host.Room() != nil {
					t.Fatal("invalid configuration published a room")
				}
				return
			}
			if host.Room() == nil || host.Room().ActionClockEnabled != test.enabled {
				t.Fatalf("room lost clock choice: %+v", host.Room())
			}
			var created protocol.RoomCreated
			var snapshot protocol.RoomSnapshot
			foundCreated, foundSnapshot := false, false
			for len(host.Send) > 0 {
				wire := receiveEventEnvelope(t, host)
				switch wire.Type {
				case protocol.TypeRoomCreated:
					foundCreated = true
					if err := wire.DecodePayload(&created); err != nil {
						t.Fatal(err)
					}
				case protocol.TypeRoomSnapshot:
					foundSnapshot = true
					if err := wire.DecodePayload(&snapshot); err != nil {
						t.Fatal(err)
					}
				}
			}
			if !foundCreated || !foundSnapshot || created.Settings.ActionClockEnabled != test.enabled ||
				snapshot.ActionClockEnabled != test.enabled {
				t.Fatalf("clock choice missing from room entry: %+v %+v", created, snapshot)
			}
			if test.enabled && (len(snapshot.ActionClockMs) != 2 || snapshot.ActionClockMs[0] != 25*60*1000 || snapshot.ActionClockRunning != nil) {
				t.Fatalf("waiting clock was not paused at 25 minutes: %+v", snapshot)
			}
			if !test.enabled && len(snapshot.ActionClockMs) != 0 {
				t.Fatal("disabled room acquired a clock")
			}
		})
	}
}

func TestTournamentActionClockChoiceReachesProjectionAndPairedRoom(t *testing.T) {
	for _, enabled := range []bool{false, true} {
		t.Run(map[bool]string{false: "disabled", true: "enabled"}[enabled], func(t *testing.T) {
			h := retentionHandler(t, DefaultConfig())
			h.forgeRuntime = &forge.ProcessConfig{}
			host, guest := retentionSession(h, "host"), retentionSession(h, "guest")
			event, err := tournament.New("CLOCK", tournament.Config{
				Name: "Clock pairing", Format: "Modern", MatchMode: protocol.MatchBO3,
				RulesMode: protocol.RulesModeForge, ActionClockEnabled: &enabled,
			}, "Judge", "judge", tournament.CredentialHash("judge-token"), time.Now())
			if err != nil {
				t.Fatal(err)
			}
			ids := []string{}
			for _, sess := range []*Session{host, guest} {
				participant, err := event.Register(sess.DisplayName, sess.ConnectionID,
					tournament.CredentialHash(sess.ConnectionID), time.Now())
				if err != nil {
					t.Fatal(err)
				}
				ids = append(ids, participant.ID)
				sess.setTournament(tournamentBinding{TournamentID: event.ID,
					Role: tournament.RoleParticipant, ParticipantID: participant.ID})
			}
			event.Status, event.Stage = tournament.StatusRunning, protocol.LimitedStageCompetition
			event.Rounds = []tournament.Round{{Number: 1, Pairings: []tournament.Pairing{
				{ID: "pair", PlayerAID: ids[0], PlayerBID: ids[1]},
			}}}
			if _, err := h.tournaments.create(event); err != nil {
				t.Fatal(err)
			}
			if snapshot := tournamentSnapshot(event, host.Tournament()); snapshot.ActionClockEnabled != enabled {
				t.Fatal("event projection lost clock choice")
			}
			open, _ := protocol.NewEnvelope(protocol.TypeTournamentOpenMatch,
				protocol.TournamentPairingCommand{PairingID: "pair"})
			for _, sess := range []*Session{host, guest} {
				if err := h.handleTournamentOpenMatch(sess, open); err != nil {
					t.Fatal(err)
				}
			}
			if host.Room() == nil || host.Room() != guest.Room() || host.Room().ActionClockEnabled != enabled {
				t.Fatal("pairing lost clock choice")
			}
			clock := host.Room().Snapshot().ActionClockMs
			if (len(clock) == 2) != enabled {
				t.Fatalf("paired clock = %v, enabled = %v", clock, enabled)
			}
		})
	}
}

func TestActionClockTimeoutRecordsOnlySwissResult(t *testing.T) {
	for _, coordinator := range []string{protocol.LimitedCoordinatorSwiss, protocol.LimitedCoordinatorCasual} {
		t.Run(coordinator, func(t *testing.T) {
			h := retentionHandler(t, DefaultConfig())
			event := addLiveTournament(t, h, "RESULT", tournament.StatusRunning, time.Now())
			event.Coordinator = coordinator
			pair := tournament.Pairing{ID: "pair", PlayerAID: "left", PlayerBID: "right"}
			if coordinator == protocol.LimitedCoordinatorSwiss {
				event.Rounds = []tournament.Round{{Number: 1, Pairings: []tournament.Pairing{pair}}}
			} else {
				event.CasualPairings = []tournament.Pairing{pair}
			}
			h.applyActionClockTimeout(event.ID, pair.ID, pair.PlayerAID, 2, 0)
			actual, err := event.Pairing(pair.ID)
			if err != nil {
				t.Fatal(err)
			}
			if (actual.Result != nil) != (coordinator == protocol.LimitedCoordinatorSwiss) {
				t.Fatalf("timeout result = %+v for %s", actual.Result, coordinator)
			}
		})
	}
}
