// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestTournamentCreateRejectsAmbiguousAndUnknownInput(t *testing.T) {
	for _, raw := range []string{
		`{"plan":{"products":[],"entries":[],"seed":1}}`,
		`{"product":null,"plan":null}`,
		`{"plan":{"products":[],"entries":[{"productId":"A","count":1,"count":2}]}}`,
		`{"plan":{"products":[],"entries":[{"productId":"A","count":1.5}]}}`,
		`{"plan":{"products":[],"entries":[{"productId":"A","count":1e50}]}}`,
		`{"plan":{"products":[{"sheets":[{"unknown":true}]}],"entries":[]}}`,
		`{"seed":1}`, `null`,
		`{"plan":{"products":[],"entries":[{"productId":"A","ProductId":"B","count":1}]}}`,
		`{"plan":{` + strings.Repeat(" ", 800*1024) + `"products":[],"entries":[]}}`,
	} {
		var c TournamentCreate
		if err := json.Unmarshal([]byte(raw), &c); err == nil {
			t.Fatalf("accepted %.120s", raw)
		}
	}
	var env Envelope
	if err := json.Unmarshal([]byte(`{"type":"tournament.create","payload":{},"payload":{"seed":1}}`), &env); err == nil {
		t.Fatal("duplicate envelope key accepted")
	}
	var start TournamentStart
	if err := json.Unmarshal([]byte(`{"operationId":"a","expectedStage":"registration","seed":1}`), &start); err == nil {
		t.Fatal("start seed accepted")
	}
}
