// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"testing"
)

func FuzzDecodeRetainedRoom(f *testing.F) {
	f.Add([]byte(`{"schemaVersion":1,"roomId":"ABCDEF","savedAt":"2026-08-05T00:00:00Z","expiresAt":"2026-08-06T00:00:00Z","seats":[],"score":[],"game":{}}`))
	f.Add([]byte(`{}`))
	f.Add([]byte(`not-json`))

	f.Fuzz(func(t *testing.T, data []byte) {
		if len(data) > 1<<20 {
			t.Skip()
		}
		record, err := decodeRetainedRoom(data)
		if err != nil {
			return
		}
		encoded, err := json.Marshal(record)
		if err != nil {
			t.Fatalf("Marshal decoded retained room: %v", err)
		}
		if _, err := decodeRetainedRoom(encoded); err != nil {
			t.Fatalf("Decode marshaled retained room: %v", err)
		}
	})
}
