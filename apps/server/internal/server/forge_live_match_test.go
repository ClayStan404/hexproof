//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"net/http/httptest"
	"testing"
	"time"

	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/protocol"
)

// Continue the actual WebSocket/Java burn match through private sideboarding,
// a host restart, and a natural first-to-two result. No manual game mutation or
// concession substitutes for actual damage resolution.
func liveForgeContinueBO3(t *testing.T, ctx context.Context, srv *httptest.Server, handler *Handler,
	players []*liveForgePeer, observer *liveForgePeer, roomID string, stats map[string]int) int {
	t.Helper()
	host, guest := players[0], players[1]
	all := append(players, observer)
	for gameNumber := 2; gameNumber <= 3; gameNumber++ {
		if host.metadata.Result == nil || host.metadata.Result.MatchFinished || host.metadata.Sideboard == nil {
			t.Fatal("BO3 ended instead of opening its five-minute private sideboard gate")
		}
		if handler.config.RetentionDir != "" {
			liveForgeReplayDenied(t, ctx, host)
		}
		previousLoser := 1 - *host.snapshot.WinnerSeat
		previousGameID := host.snapshot.GameID
		if gameNumber == 2 {
			host.command(t, ctx, protocol.TypeSideboardMove, "board-out-one", protocol.SideboardMove{
				FromZone: protocol.SideboardZoneMain, ToZone: protocol.SideboardZoneSide,
				Name: "Lightning Bolt", SetCode: "M11", CollectorNumber: "149",
			})
			host.until(t, ctx, protocol.TypeSideboardMoved)
			for _, peer := range all {
				peer.until(t, ctx, protocol.TypeGameSnapshot)
			}
			if len(host.metadata.Sideboard.Sideboard) != 1 || len(guest.metadata.Sideboard.Sideboard) != 0 ||
				host.metadata.Sideboard.Seats[0].SideboardCount != 1 {
				t.Fatal("pending sideboard did not remain owner-specific")
			}
			liveForgeResumeBetweenGames(t, ctx, srv, handler, host, roomID)
			if host.metadata.Sideboard == nil || len(host.metadata.Sideboard.Sideboard) != 1 {
				t.Fatal("sideboard reconnect lost the owner's pending partition")
			}
			liveForgeJoinFinishedGame(t, ctx, srv, roomID, false)
		}
		for _, player := range players {
			player.command(t, ctx, protocol.TypeSideboardReady, "sideboard-ready", protocol.SideboardReady{Ready: true})
			player.until(t, ctx, protocol.TypeSideboardReadyChanged)
		}
		for _, player := range players {
			player.until(t, ctx, protocol.TypeRulesPrompt)
			if player.snapshot.GameID == previousGameID || player.metadata.GameNumber != gameNumber ||
				player.metadata.StartingSeat != previousLoser || player.metadata.Sideboard != nil || player.metadata.Result != nil {
				t.Fatal("next game retained the old game/sideboard or did not give the loser the first turn")
			}
		}
		observer.until(t, ctx, protocol.TypeRulesSnapshot)
		observer.until(t, ctx, protocol.TypeGameSnapshot)
		if gameNumber == 2 {
			// The committed host deck contains 59 physical cards, and Java must
			// receive that partition rather than silently restoring the original.
			cards := 0
			for _, zone := range host.snapshot.Zones {
				if zone.OwnerSeat == 0 && (zone.Zone == "library" || zone.Zone == "hand") {
					cards += zone.Count
				}
			}
			if cards != 59 {
				t.Fatalf("Java next game used %d host cards, want the committed 59", cards)
			}
			oldPrompt := liveForgeActor(t, players).prompt.PromptID
			beforeRestart := host.snapshot.GameID
			host.command(t, ctx, protocol.TypeGameRestart, "restart-second", protocol.GameRestart{})
			host.until(t, ctx, protocol.TypeGameRestarted)
			for _, player := range players {
				player.until(t, ctx, protocol.TypeRulesPrompt)
				if player.snapshot.GameID == beforeRestart || player.metadata.GameNumber != 2 ||
					player.metadata.StartingSeat != previousLoser || player.metadata.Score[1-previousLoser] != 1 {
					t.Fatal("host restart lost the existing score, game number, or initial player")
				}
			}
			observer.until(t, ctx, protocol.TypeRulesSnapshot)
			observer.until(t, ctx, protocol.TypeGameSnapshot)
			actor := liveForgeActor(t, players)
			stale := liveForgeAnswer(t, actor, make(map[string]int))
			stale.PromptID = oldPrompt
			actor.command(t, ctx, protocol.TypeRulesRespond, "old-game-prompt", stale)
			rejected := actor.until(t, ctx, protocol.TypeError)
			var failure protocol.ErrorPayload
			if rejected.DecodePayload(&failure) != nil || failure.Code != protocol.ErrRulesActionRejected {
				t.Fatal("an old game's response answered the restarted game's new prompt")
			}
		}
		checkedFirst := false
		for decisions := 0; decisions < 1500 && !host.snapshot.GameOver; decisions++ {
			actor := liveForgeActor(t, players)
			if host.snapshot.Turn == 1 && actor.prompt.Kind == "chooseAction" && !checkedFirst {
				if host.snapshot.ActiveSeat != previousLoser {
					t.Fatal("Forge gave the first actual turn to the previous winner")
				}
				checkedFirst = true
			}
			kind := actor.prompt.Kind
			actor.command(t, ctx, protocol.TypeRulesRespond, "bo3-decision", liveForgeAnswer(t, actor, stats))
			actor.until(t, ctx, protocol.TypeRulesResponded)
			stats[kind]++
			for _, player := range players {
				player.until(t, ctx, protocol.TypeRulesPrompt)
			}
			observer.until(t, ctx, protocol.TypeRulesSnapshot)
		}
		if !checkedFirst || !host.snapshot.GameOver || host.snapshot.WinnerSeat == nil {
			t.Fatal("BO3 next game did not finish naturally with the promised starting player")
		}
		lethal := false
		for _, player := range host.snapshot.Players {
			if player.Seat != *host.snapshot.WinnerSeat && player.Life <= 0 {
				lethal = true
			}
		}
		if !lethal {
			t.Fatal("BO3 game ended without actual lethal damage")
		}
		for _, peer := range all {
			peer.until(t, ctx, protocol.TypeRoomSnapshot)
		}
		if _, alive := handler.forgeGame(roomID); alive {
			t.Fatal("completed BO3 game retained its runtime session")
		}
		if host.metadata.Result != nil && host.metadata.Result.MatchFinished {
			liveForgeResumeBetweenGames(t, ctx, srv, handler, host, roomID)
			liveForgeJoinFinishedGame(t, ctx, srv, roomID, true)
			return *host.snapshot.WinnerSeat
		}
	}
	t.Fatal("BO3 failed to finish after three non-drawn games")
	return -1
}

func liveForgeResumeBetweenGames(t *testing.T, ctx context.Context, srv *httptest.Server,
	handler *Handler, peer *liveForgePeer, roomID string) {
	t.Helper()
	token := peer.welcome.ResumeToken
	_ = peer.client.conn.CloseNow()
	waitCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	for {
		handler.resumeMu.Lock()
		_, held := handler.resumeHolds[token]
		handler.resumeMu.Unlock()
		if held {
			break
		}
		select {
		case <-waitCtx.Done():
			t.Fatal("between-game player was not held for reconnect")
		case <-time.After(5 * time.Millisecond):
		}
	}
	peer.client = dialLiveForge(t, srv)
	peer.command(t, ctx, protocol.TypeSessionHello, "resume-result", protocol.SessionHello{
		DisplayName: peer.name, ClientVersion: buildinfo.Version, Protocol: protocol.ProtocolVersion,
		ResumeToken: token,
	})
	welcome := peer.until(t, ctx, protocol.TypeSessionWelcome)
	if welcome.DecodePayload(&peer.welcome) != nil || !peer.welcome.Resumed || peer.welcome.RoomID != roomID {
		t.Fatal("between-game reconnect lost authenticated room membership")
	}
	peer.until(t, ctx, protocol.TypeGameSnapshot)
	if peer.metadata.Result == nil || peer.room.Phase != protocol.RoomPhaseStarted {
		t.Fatal("between-game reconnect aborted the match or lost its result")
	}
	if _, exists := handler.forgeGame(roomID); exists {
		t.Fatal("between-game reconnect resurrected a finished engine session")
	}
}

func liveForgeJoinFinishedGame(t *testing.T, ctx context.Context, srv *httptest.Server,
	roomID string, matchFinished bool) {
	t.Helper()
	peer := &liveForgePeer{client: dialLiveForge(t, srv), seat: -1, name: "Between-game spectator"}
	defer peer.client.conn.CloseNow()
	peer.command(t, ctx, protocol.TypeSessionHello, "hello-result", protocol.SessionHello{
		DisplayName: peer.name, ClientVersion: buildinfo.Version, Protocol: protocol.ProtocolVersion,
	})
	peer.until(t, ctx, protocol.TypeSessionWelcome)
	peer.command(t, ctx, protocol.TypeRoomJoin, "watch-result", protocol.RoomJoin{RoomID: roomID, AsSpectator: true, AcceptPlayerHost: true})
	peer.until(t, ctx, protocol.TypeGameSnapshot)
	if peer.room.Phase != protocol.RoomPhaseStarted || peer.metadata.Result == nil ||
		peer.metadata.Result.MatchFinished != matchFinished || (peer.metadata.Sideboard != nil) == matchFinished {
		t.Fatal("spectator joining a completed game changed its lifecycle or lost public metadata")
	}
}
