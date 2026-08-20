// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

import (
	"encoding/json"
	"reflect"
	"testing"
)

func FuzzParseEnvelope(f *testing.F) {
	f.Add([]byte(`{"type":"session.hello","id":"seed","payload":{"displayName":"Alice"}}`))
	f.Add([]byte(`{"type":"room.snapshot","seq":1,"payload":{}}`))
	f.Add([]byte(`{"type":"error","payload":null}`))
	f.Add([]byte(`{}`))
	f.Add([]byte(`not-json`))

	f.Fuzz(func(t *testing.T, data []byte) {
		if len(data) > 1<<20 {
			t.Skip()
		}
		envelope, err := ParseEnvelope(data)
		if err != nil {
			return
		}
		encoded, err := envelope.Marshal()
		if err != nil {
			t.Fatalf("Marshal parsed envelope: %v", err)
		}
		if !json.Valid(encoded) {
			t.Fatalf("Marshal returned invalid JSON: %q", encoded)
		}
		roundTrip, err := ParseEnvelope(encoded)
		if err != nil {
			t.Fatalf("Parse marshaled envelope: %v", err)
		}
		if roundTrip.Type != envelope.Type || roundTrip.ID != envelope.ID ||
			roundTrip.HasSeq() != envelope.HasSeq() ||
			roundTrip.SeqValue() != envelope.SeqValue() {
			t.Fatalf("envelope metadata changed: before=%+v after=%+v", envelope, roundTrip)
		}
		if !jsonSemanticallyEqual(envelope.Payload, roundTrip.Payload) {
			t.Fatalf("payload changed: before=%s after=%s", envelope.Payload, roundTrip.Payload)
		}
	})
}

func jsonSemanticallyEqual(left, right json.RawMessage) bool {
	if len(left) == 0 || len(right) == 0 {
		return len(left) == len(right)
	}
	var leftValue any
	var rightValue any
	if json.Unmarshal(left, &leftValue) != nil || json.Unmarshal(right, &rightValue) != nil {
		return false
	}
	return reflect.DeepEqual(leftValue, rightValue)
}
