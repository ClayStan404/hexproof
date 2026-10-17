// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgediag

import (
	"encoding/json"
	"strings"
	"testing"
)

func diagnosticFixture() Capsule {
	return Capsule{SchemaVersion: 1, ProducerID: "producer-one", SessionID: "game-one", Sequence: 9,
		Kind: "engine_exception", Boundary: "effect", Attribution: "execution_site", SymbolIndexID: SymbolIndexID(),
		Causes: []Cause{{ClassName: "java.lang.IllegalStateException", Frames: []Frame{{ClassName: "org.hexproof.forge.NativeSession", MethodName: "fail", Line: 549}}}},
		Spans:  []Span{{ID: 2, ParentID: 1, Stage: "effect", API: "Draw", Source: &Source{ObjectID: "card-1", Incarnation: "card-1:2", ObservationSequence: 8, Zone: "stack", Disclosure: "public_zone", Card: &CardReference{Name: "Lightning Bolt"}}}}}
}

func TestCapsuleKeepsVerifiedSymbolsAndRejectsPrivateStrings(t *testing.T) {
	value := diagnosticFixture()
	clean := SanitizeCapsule(&value)
	if clean == nil || len(clean.Causes[0].Frames) != 1 || clean.Spans[0].Source.Card == nil {
		t.Fatalf("verified diagnostic lost: %+v", clean)
	}
	value.Causes[0].Frames = append(value.Causes[0].Frames, Frame{ClassName: "secret.hand.DemonicTutor", MethodName: "token_secret"})
	value.Spans[0].Source.Card.Name = "private-card-token"
	clean = SanitizeCapsule(&value)
	encoded, _ := json.Marshal(clean)
	if strings.Contains(string(encoded), "private-card-token") || strings.Contains(string(encoded), "token_secret") || clean.OmittedFrames != 1 || clean.Spans[0].Source.Card != nil {
		t.Fatalf("unverified evidence escaped: %s", encoded)
	}
	value = diagnosticFixture()
	value.Spans[0].Source.Zone = "hand"
	if SanitizeCapsule(&value).Spans[0].Source != nil {
		t.Fatal("hidden zone accepted as public observation")
	}
	value = diagnosticFixture()
	value.SymbolIndexID = strings.Repeat("0", 64)
	clean = SanitizeCapsule(&value)
	if len(clean.Causes[0].Frames) != 0 || clean.Spans[0].API != "" {
		t.Fatal("mismatched symbols index trusted")
	}
	raw, _ := json.Marshal(diagnosticFixture())
	raw = append(raw[:len(raw)-1], []byte(`,"message":"private hand secret"}`)...)
	if ParseCapsule(raw) != nil {
		t.Fatal("arbitrary exception message accepted")
	}
}

func TestCapsuleBoundsAndDetachedCopies(t *testing.T) {
	value := diagnosticFixture()
	frame := value.Causes[0].Frames[0]
	for i := 0; i < 50; i++ {
		value.Causes[0].Frames = append(value.Causes[0].Frames, frame)
	}
	for i := 0; i < 9; i++ {
		value.Spans = append(value.Spans, Span{ID: uint64(i + 3), Stage: "effect"})
	}
	clean := SanitizeCapsule(&value)
	if len(clean.Causes[0].Frames) != 32 || clean.OmittedFrames != 19 || len(clean.Spans) != 8 || clean.OmittedSpans != 2 {
		t.Fatalf("caps not applied: %+v", clean)
	}
	clean.Spans[0].Source.Card.Name = "changed"
	if value.Spans[0].Source.Card.Name != "Lightning Bolt" {
		t.Fatal("sanitizer returned mutable producer-owned memory")
	}
	if ParseCapsule([]byte(strings.Repeat(" ", MaxCapsuleBytes+1))) != nil {
		t.Fatal("oversized capsule accepted")
	}
	value = diagnosticFixture()
	value.Sequence = MaxSafeInteger + 1
	if SanitizeCapsule(&value) != nil {
		t.Fatal("unsafe JSON integer accepted")
	}
	value = diagnosticFixture()
	value.Spans[0].ID = MaxSafeInteger + 1
	if len(SanitizeCapsule(&value).Spans) != 0 {
		t.Fatal("unsafe span ID accepted")
	}
}
