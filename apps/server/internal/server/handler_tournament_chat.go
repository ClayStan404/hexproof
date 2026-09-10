// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"hexproof/server/internal/protocol"
	"hexproof/server/internal/tournament"
)

const tournamentChatHistoryLimit = 100

func (h *Handler) sendTournamentChatHistory(sess *Session) {
	binding := sess.Tournament()
	entry := h.tournaments.entry(binding.TournamentID)
	if entry == nil {
		return
	}
	entry.mu.Lock()
	messages := append([]protocol.TournamentChatMessage{}, entry.chat...)
	entry.mu.Unlock()
	envelope, _ := protocol.NewEnvelope(protocol.TypeTournamentChatHistory,
		protocol.TournamentChatHistory{TournamentID: binding.TournamentID, Messages: messages})
	h.send(sess, envelope)
}

func (h *Handler) handleTournamentChatSend(sess *Session, env protocol.Envelope) error {
	var request protocol.TournamentChatSend
	if err := env.DecodePayload(&request); err != nil {
		h.sendError(sess, env.ID, protocol.ErrInvalidMessage, err.Error())
		return nil
	}
	binding := sess.Tournament()
	if binding.TournamentID == "" || binding.TournamentID != request.TournamentID {
		h.sendError(sess, env.ID, protocol.ErrTournamentForbidden, "enter this tournament before chatting")
		return nil
	}
	request.Text = strings.TrimSpace(request.Text)
	invalidControl := strings.ContainsFunc(request.Text, func(r rune) bool {
		return unicode.IsControl(r) && r != '\n'
	})
	if request.Text == "" || utf8.RuneCountInString(request.Text) > 500 || invalidControl {
		h.sendError(sess, env.ID, protocol.ErrInvalidChat, "chat text must contain 1 to 500 characters")
		return nil
	}
	entry, err := h.tournaments.lockOperation(binding.TournamentID)
	if err != nil {
		sendTournamentError(h, sess, env.ID, err)
		return nil
	}
	defer entry.opMu.Unlock()
	entry.mu.Lock()
	name := sess.DisplayName
	allowed := binding.Role == tournament.RoleViewer
	if binding.Role == tournament.RoleOrganizer {
		allowed = entry.event.OrganizerConnectionID == sess.ConnectionID
		name = entry.event.OrganizerName
	} else if binding.Role == tournament.RoleParticipant {
		participant := entry.event.Participant(binding.ParticipantID)
		allowed = participant != nil && participant.ConnectionID == sess.ConnectionID
		if allowed {
			name = participant.DisplayName
		}
	}
	if !allowed {
		entry.mu.Unlock()
		h.sendError(sess, env.ID, protocol.ErrTournamentForbidden, "tournament identity is no longer current")
		return nil
	}
	now := time.Now().UTC()
	if !h.tournamentChatLimiter.allow(sess.RemoteIP, now, 30) {
		entry.mu.Unlock()
		h.sendError(sess, env.ID, protocol.ErrRateLimited, "tournament chat rate limit exceeded")
		return nil
	}
	entry.chatSequence++
	message := protocol.TournamentChatMessage{
		TournamentID: binding.TournamentID, Sequence: entry.chatSequence,
		DisplayName: name, Text: request.Text, SentAt: now.Format(time.RFC3339),
	}
	entry.chat = append(entry.chat, message)
	if len(entry.chat) > tournamentChatHistoryLimit {
		entry.chat = append([]protocol.TournamentChatMessage(nil),
			entry.chat[len(entry.chat)-tournamentChatHistoryLimit:]...)
	}
	entry.mu.Unlock()
	h.sessionsMu.RLock()
	members := make([]*Session, 0)
	for _, member := range h.sessions {
		if member.Tournament().TournamentID == binding.TournamentID {
			members = append(members, member)
		}
	}
	h.sessionsMu.RUnlock()
	for _, member := range members {
		envelope, _ := protocol.NewEnvelope(protocol.TypeTournamentChatMessage, message)
		if member == sess {
			envelope.ID = env.ID
		}
		h.send(member, envelope)
	}
	return nil
}
