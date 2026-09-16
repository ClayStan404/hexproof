// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"errors"
	"strings"
	"unicode"
	"unicode/utf8"
)

// Card-name membership is checked by the native controller against the complete
// public candidate set supplied by Forge for this effect. Sending that set as
// ordinary menu options would exceed the bounded prompt protocol. The server
// validates the authenticated decision and text shape, never infers names from
// a player's deck or private zones.
func cardNameOutput(view PromptView, answer PromptResponse) (any, error) {
	otherSelections := answer
	otherSelections.Name = ""
	if !otherSelections.emptySelections() {
		return nil, errors.New("card-name response contains unexpected selections")
	}
	if answer.ResponseID == "$cancel" && answer.Name == "" && view.Cancellable {
		return map[string]any{"type": "cancel"}, nil
	}
	name := strings.TrimSpace(answer.Name)
	if answer.ResponseID != "$submit" || name == "" || !utf8.ValidString(name) ||
		utf8.RuneCountInString(name) > 256 || strings.ContainsFunc(name, unicode.IsControl) {
		return nil, errors.New("invalid card-name response")
	}
	return map[string]any{"type": "cardName", "name": name}, nil
}
