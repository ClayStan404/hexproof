//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"encoding/json"
	"os"
	"strings"
	"testing"

	"hexproof/server/internal/protocol"
)

func liveForgeReplayDenied(t *testing.T, ctx context.Context, peer *liveForgePeer) {
	t.Helper()
	if peer.replay.ReplayID == "" {
		t.Fatal("missing live replay grant")
	}
	peer.command(t, ctx, protocol.TypeForgeReplayGet, "early-replay", protocol.ForgeReplayGet{
		ReplayID: peer.replay.ReplayID, Token: peer.replay.Token,
	})
	rejected := peer.until(t, ctx, protocol.TypeError)
	var failure protocol.ErrorPayload
	if rejected.DecodePayload(&failure) != nil || failure.Code != protocol.ErrReplayNotFound {
		t.Fatal("early replay was not denied")
	}
}

func liveForgeVerifyReplay(t *testing.T, ctx context.Context, players []*liveForgePeer, observer *liveForgePeer, mode string) {
	t.Helper()
	for _, peer := range players {
		peer.command(t, ctx, protocol.TypeSessionPing, "replay-barrier", struct{}{})
		peer.until(t, ctx, protocol.TypeSessionPong)
		if !peer.replay.Finished || peer.replay.FrameCount == 0 || !peer.replay.Complete {
			t.Fatalf("recording was not completed: %+v", peer.replay)
		}
	}
	if players[0].replay.Token == players[1].replay.Token {
		t.Fatal("participants share a capability")
	}
	var frames []protocol.ForgeReplayFrame
	for _, peer := range players {
		offset := 0
		for {
			peer.command(t, ctx, protocol.TypeForgeReplayGet, "download", protocol.ForgeReplayGet{ReplayID: peer.replay.ReplayID, Token: peer.replay.Token, Offset: offset})
			result := peer.until(t, ctx, protocol.TypeForgeReplayPage)
			var page protocol.ForgeReplayPage
			if result.DecodePayload(&page) != nil || page.Offset != offset || !page.Complete || len(page.Frames) == 0 {
				t.Fatal("invalid replay page")
			}
			if peer.seat == 0 {
				frames = append(frames, page.Frames...)
			}
			offset += len(page.Frames)
			if offset == page.Total {
				break
			}
			if offset > page.Total {
				t.Fatal("replay pagination exceeded total")
			}
		}
	}
	observer.command(t, ctx, protocol.TypeForgeReplayGet, "forbidden-replay", protocol.ForgeReplayGet{ReplayID: players[0].replay.ReplayID, Token: strings.Repeat("0", 64)})
	observer.until(t, ctx, protocol.TypeError)
	hands := [2]bool{}
	games := map[int]bool{}
	resolved := 0
	for index, frame := range frames {
		if frame.Sequence != int64(index+1) {
			t.Fatal("noncontiguous replay sequence")
		}
		games[frame.GameNumber] = true
		if frame.Kind == "SpellResolved" {
			resolved++
		}
		for _, zone := range frame.Snapshot.Zones {
			if zone.Zone != "hand" || zone.OwnerSeat < 0 || zone.OwnerSeat > 1 {
				continue
			}
			for _, card := range zone.Cards {
				if card.Visible && card.Identity != nil {
					hands[zone.OwnerSeat] = true
				}
			}
		}
	}
	if !hands[0] || !hands[1] || resolved < 7 || (mode == protocol.MatchBO3 && len(games) < 2) {
		t.Fatalf("missing real game evidence: hands=%v resolutions=%d games=%v", hands, resolved, games)
	}
	// Optional synthetic artifact for the native UI check; contains no grants.
	if path := os.Getenv("HEXPROOF_REPLAY_TEST_OUTPUT"); path != "" {
		metadata := players[0].replay
		metadata.Token = ""
		raw, err := json.Marshal(map[string]any{"schemaVersion": 1, "metadata": metadata, "frames": frames})
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, raw, 0600); err != nil {
			t.Fatal(err)
		}
	}
	t.Logf("private replay verified: %d frames, %d games, %d resolutions, both hands, both participant downloads", len(frames), len(games), resolved)
}
