// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"fmt"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/room"
	"hexproof/server/internal/rulesengine/forge"
	"hexproof/server/internal/rulesinput"
)

// priorityPreference is the seat's published smart-pass choice. The hub uses
// it only for chooseAction prompts the engine marked auto-pass eligible.
// Yields and holding the next prompt stay on the client.
type priorityPreference struct {
	fullControl bool
	hold        bool
	stops       map[string]bool
}

func (h *Handler) handleRulesPriority(sess *Session, env protocol.Envelope) error {
	r := sess.Room()
	if r == nil {
		h.sendError(sess, env.ID, protocol.ErrNotInRoom, "not in a room")
		return nil
	}
	var request protocol.RulesPriority
	if err := env.DecodePayload(&request); err != nil || request.RoomID != r.ID {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, "invalid priority preference")
		return nil
	}
	seat, err := h.hub.RulesActorSeat(r, sess.ConnectionID)
	if err != nil {
		code, _ := ErrCode(err)
		h.sendError(sess, env.ID, code, err.Error())
		return nil
	}
	stops := make(map[string]bool, len(request.Stops))
	for _, stop := range request.Stops {
		if stop != "" {
			stops[stop] = true
		}
	}
	h.setPriorityPreference(r.ID, seat, priorityPreference{
		fullControl: request.FullControl,
		hold:        request.Hold,
		stops:       stops,
	})
	reply, err := protocol.NewEnvelope(protocol.TypeRulesPriority, request)
	if err != nil {
		return err
	}
	reply.ID = env.ID
	h.send(sess, reply)
	return nil
}

func (h *Handler) setPriorityPreference(roomID string, seat int, prefs priorityPreference) {
	h.priorityMu.Lock()
	defer h.priorityMu.Unlock()
	if h.priorityPrefs == nil {
		h.priorityPrefs = map[string]map[int]priorityPreference{}
	}
	seats := h.priorityPrefs[roomID]
	if seats == nil {
		seats = map[int]priorityPreference{}
		h.priorityPrefs[roomID] = seats
	}
	seats[seat] = prefs
}

func (h *Handler) priorityPreferenceFor(roomID string, seat int) (priorityPreference, bool) {
	h.priorityMu.Lock()
	defer h.priorityMu.Unlock()
	prefs, ok := h.priorityPrefs[roomID][seat]
	return prefs, ok
}

func shouldDelegatePriorityPass(prefs priorityPreference, known bool, view forge.PromptView, step string, ownTurn bool) bool {
	if !known || prefs.fullControl || prefs.hold || view.Kind != "chooseAction" || !view.Supported || !view.AutoPassEligible {
		return false
	}
	prefix := "other:"
	if ownTurn {
		prefix = "own:"
	}
	if prefs.stops[prefix+step] {
		return false
	}
	for _, option := range view.Options {
		if option.ResponseID == "$pass" {
			return true
		}
	}
	return false
}

// advanceRulesPriority runs at an explicit publication boundary while the
// caller holds opMu, before collecting any snapshots or terminal result.
// Read-only reconnects and receipt replays preserve the published position.
func (h *Handler) advanceRulesPriority(r *room.Room, game forgeRoomGame) error {
	ctx, cancel := context.WithTimeout(context.Background(), runtimeTimeout(game.client, forgePromptTimeout))
	gameOver, err := game.client.GameOver(ctx, game.sessionID)
	if err != nil || gameOver {
		cancel()
		return err
	}
	view, err := currentRulesPrompt(ctx, game)
	cancel()
	if err != nil {
		return err
	}
	_, err = h.delegatePriorityPasses(r, game, view)
	return err
}

// delegatePriorityPasses submits engine-eligible passes before the prompt is
// shown, up to eight in a row. A prompt the hub does not pass is returned for
// the client, which still applies its own yield and hold rules.
func (h *Handler) delegatePriorityPasses(r *room.Room, game forgeRoomGame, view *forge.PromptView) (*forge.PromptView, error) {
	for range 8 {
		if view == nil {
			return nil, nil
		}
		seat, ok := game.playerToSeat[view.PlayerIndex]
		if !ok {
			return view, nil
		}
		prefs, known := h.priorityPreferenceFor(r.ID, seat)
		if !shouldDelegatePriorityPass(prefs, known, *view, "", true) && len(prefs.stops) == 0 {
			return view, nil
		}
		step, ownTurn := "", true
		if len(prefs.stops) > 0 {
			ctx, cancel := context.WithTimeout(context.Background(), runtimeTimeout(game.client, forgeSnapshotTimeout))
			snapshot, err := game.client.SnapshotView(ctx, game.sessionID, view.PlayerIndex)
			cancel()
			if err != nil {
				return nil, err
			}
			step = normalizedRulesStep(snapshot.Step)
			ownTurn = snapshot.ActivePlayerID == fmt.Sprintf("player-%d", view.PlayerIndex)
		}
		if !shouldDelegatePriorityPass(prefs, known, *view, step, ownTurn) {
			return view, nil
		}
		ctx, cancel := context.WithTimeout(context.Background(), runtimeTimeout(game.client, forgePromptTimeout))
		raw, err := game.client.Prompt(ctx, game.sessionID, view.PlayerIndex)
		cancel()
		if err != nil {
			return nil, err
		}
		response, err := rulesinput.Build(protocol.RulesRespond{PromptID: view.PromptID, ResponseID: "$pass"}, raw, view.PlayerIndex)
		if err != nil {
			return nil, err
		}
		if !h.pauseActionClockLocked(r) {
			return nil, errActionClockFinished
		}
		ctx, cancel = context.WithTimeout(context.Background(), runtimeTimeout(game.client, forgePromptTimeout))
		game.diagnostics.action("chooseAction", seat, true)
		err = game.client.SubmitAction(ctx, game.sessionID, response)
		cancel()
		if err != nil {
			return nil, err
		}
		if err := waitForForgePromptChange(game, view.PromptID); err != nil {
			return nil, err
		}
		ctx, cancel = context.WithTimeout(context.Background(), runtimeTimeout(game.client, forgePromptTimeout))
		view, err = currentRulesPrompt(ctx, game)
		cancel()
		if err != nil {
			return nil, err
		}
	}
	return view, nil
}

// pairRulesPrompts marks a pending decision as following its snapshot so the
// client can apply both together. Every prompt, including a clear, carries its
// snapshot's publication sequence so delayed relay traffic cannot replace a
// newer direct-channel decision.
func pairRulesPrompts(projections, prompts map[string]protocol.Envelope) {
	for id, promptEnv := range prompts {
		var prompt protocol.RulesPrompt
		if promptEnv.DecodePayload(&prompt) != nil {
			continue
		}
		snapEnv, ok := projections[id]
		if !ok {
			continue
		}
		var snapshot protocol.RulesGameSnapshot
		if snapEnv.DecodePayload(&snapshot) != nil || snapshot.RoomID != prompt.RoomID ||
			snapshot.GameID != prompt.GameID {
			continue
		}
		if snapEnv.SeqPtr != nil {
			prompts[id] = promptEnv.WithSeq(snapEnv.SeqValue())
		}
		if !prompt.Pending || prompt.PromptID <= 0 {
			continue
		}
		snapshot.PromptFollows = true
		updated, err := protocol.NewEnvelope(protocol.TypeRulesSnapshot, snapshot)
		if err != nil {
			continue
		}
		updated.SeqPtr = snapEnv.SeqPtr
		updated.ID = snapEnv.ID
		projections[id] = updated
	}
}

func (h *Handler) sendRulesTable(projections, prompts map[string]protocol.Envelope) {
	pairRulesPrompts(projections, prompts)
	h.sendRulesProjections(projections)
	h.sendRulesPrompts(prompts)
}
