// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package cluster

import (
	"context"
	"slices"
	"sort"
	"testing"

	"hexproof/server/internal/protocol"
)

func TestReportsReplaceDirectoryMetadataAcrossRefreshes(t *testing.T) {
	c, err := New(testConfig())
	if err != nil {
		t.Fatal(err)
	}
	generation := register(t, c, "N1", report())
	commander := protocol.RoomListEntry{
		RoomID: "CMD234", Name: "Commander", Format: protocol.FormatEDH,
		DeckFormat: protocol.DeckFormatCommander, RulesMode: protocol.RulesModeManual,
		MatchMode: protocol.MatchBO1, MaxSeats: 4, PlayerCount: 3,
		AllowSpectators: true, SpectatorJoinable: true, Phase: protocol.RoomPhaseStarted,
	}
	cube := commander
	cube.RoomID, cube.Name, cube.RoomKind, cube.DeckFormat = "CUBE12", "Commander Cube", "cube", protocol.DeckFormatCube
	ai := protocol.RoomListEntry{
		RoomID: "AI1234", Name: "Forge AI", Format: protocol.FormatModern,
		DeckFormat: protocol.DeckFormatModern, RulesMode: protocol.RulesModeForge,
		HostingMode: "server", AISource: protocol.AISourceForge, AIDifficulty: protocol.AIDifficultyNormal,
		MatchMode: protocol.MatchBO1, MaxSeats: 2, PlayerCount: 2,
	}
	hosted := ai
	hosted.RoomID, hosted.Name, hosted.HostingMode = "HOST12", "Player hosted", "player"
	hosted.AISource, hosted.AIDifficulty = "", ""
	second, third := commander, commander
	second.RoomID, third.RoomID = "CMD345", "CMD456"
	forgeCommander := commander
	forgeCommander.RoomID, forgeCommander.RulesMode, forgeCommander.HostingMode = "CMD567", protocol.RulesModeForge, "server"
	forgeEvent := protocol.TournamentListEntry{TournamentID: "EVENT1", Name: "Forge event", RulesMode: protocol.RulesModeForge}
	legacyEvent := protocol.TournamentListEntry{TournamentID: "EVENT2", Name: "Event without optional rules mode"}

	steps := []struct {
		name   string
		rooms  []protocol.RoomListEntry
		events []protocol.TournamentListEntry
	}{
		{"specialized", []protocol.RoomListEntry{cube, ai, hosted}, []protocol.TournamentListEntry{forgeEvent}},
		{"ordinary_replacement", []protocol.RoomListEntry{commander, second, third}, []protocol.TournamentListEntry{legacyEvent}},
		{"specialized_reordered", []protocol.RoomListEntry{hosted, cube, ai}, []protocol.TournamentListEntry{forgeEvent}},
		{"forge_commander_replacement", []protocol.RoomListEntry{commander, forgeCommander, third}, []protocol.TournamentListEntry{legacyEvent}},
		{"ordinary_shorter", []protocol.RoomListEntry{commander}, []protocol.TournamentListEntry{legacyEvent}},
		{"ordinary_expanded", []protocol.RoomListEntry{third, commander, second}, []protocol.TournamentListEntry{legacyEvent}},
		{"empty", []protocol.RoomListEntry{}, []protocol.TournamentListEntry{}},
		{"ordinary_after_empty", []protocol.RoomListEntry{commander}, []protocol.TournamentListEntry{legacyEvent}},
	}
	for index, step := range steps {
		t.Run(step.name, func(t *testing.T) {
			r := report()
			r.Rooms, r.Events = step.rooms, step.events
			_, err := c.Do(context.Background(), Request{
				Operation: "report", NodeID: "N1", Generation: generation,
				ReportSequence: uint64(index + 2), Report: &r,
			})
			if err != nil {
				t.Fatal(err)
			}
			view, err := c.Do(context.Background(), Request{Operation: "view", NodeID: "N1", Generation: generation})
			if err != nil {
				t.Fatal(err)
			}
			wantRooms := slices.Clone(step.rooms)
			for index := range wantRooms {
				wantRooms[index].RoomID = "N1:" + wantRooms[index].RoomID
				wantRooms[index].NodeName = "One"
			}
			sort.Slice(wantRooms, func(i, j int) bool { return wantRooms[i].RoomID < wantRooms[j].RoomID })
			if !slices.Equal(view.Rooms, wantRooms) {
				t.Errorf("directory retained previous room metadata:\n got %+v\nwant %+v", view.Rooms, wantRooms)
			}
			wantEvents := slices.Clone(step.events)
			for index := range wantEvents {
				wantEvents[index].TournamentID = "N1:" + wantEvents[index].TournamentID
				wantEvents[index].NodeName = "One"
			}
			if !slices.Equal(view.Events, wantEvents) {
				t.Errorf("directory retained previous event metadata:\n got %+v\nwant %+v", view.Events, wantEvents)
			}
		})
	}
}

func TestReportsRemoveAbsentAccountResources(t *testing.T) {
	c, err := New(testConfig())
	if err != nil {
		t.Fatal(err)
	}
	r := report()
	r.Resources["alice"] = []protocol.AccountResource{{Kind: "room", ID: "ROOM12", Name: "Previous room", Role: "player"}}
	generation := register(t, c, "N1", r)
	fresh := report()
	fresh.Resources["bob"] = []protocol.AccountResource{{Kind: "cube", ID: "CUBE12", Name: "Current Cube", Role: "player"}}
	_, err = c.Do(context.Background(), Request{
		Operation: "report", NodeID: "N1", Generation: generation, ReportSequence: 2, Report: &fresh,
	})
	if err != nil {
		t.Fatal(err)
	}
	view, err := c.Do(context.Background(), Request{Operation: "view", NodeID: "N1", Generation: generation, AccountID: "alice"})
	if err != nil {
		t.Fatal(err)
	}
	if len(view.Resources) != 0 {
		t.Fatalf("removed account resources remained discoverable: %+v", view.Resources)
	}
	view, err = c.Do(context.Background(), Request{Operation: "view", NodeID: "N1", Generation: generation, AccountID: "bob"})
	if err != nil || len(view.Resources) != 1 || view.Resources[0].ID != "N1:CUBE12" {
		t.Fatalf("replacement account resources = %+v, error = %v", view.Resources, err)
	}
}
