// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"bytes"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"
)

func TestManifestSharedContentBounds(t *testing.T) {
	publicConfig, public := publicFixture(t)
	publicNow := time.Date(2026, 10, 22, 12, 1, 0, 0, time.UTC)
	for _, version := range []struct {
		name     string
		raw      []byte
		now      time.Time
		validate func([]byte) error
	}{
		{"private", rawManifest(t), testNow, func(raw []byte) error {
			_, err := validateManifest(raw, testID, testNow)
			return err
		}},
		{"public", public.ManifestBytes, publicNow, func(raw []byte) error {
			_, err := validatePublicManifest(raw, testID, publicNow, publicConfig)
			return err
		}},
	} {
		t.Run(version.name, func(t *testing.T) {
			for _, test := range []struct {
				name   string
				change func(map[string]any)
				valid  bool
			}{
				{"description limit", func(m map[string]any) { m["description"] = strings.Repeat("x", 8192) }, true},
				{"description overflow", func(m map[string]any) { m["description"] = strings.Repeat("x", 8193) }, false},
				{"blank description", func(m map[string]any) { m["description"] = " \t\n" }, false},
				{"wrong identity", func(m map[string]any) { m["submissionId"] = "c8e836ba-c3d5-4623-8a4f-7ed9788b142c" }, false},
				{"unknown category", func(m map[string]any) { m["category"] = "support" }, false},
				{"oldest freeze", func(m map[string]any) { m["createdAt"] = version.now.Add(-7 * 24 * time.Hour).Format(time.RFC3339Nano) }, true},
				{"expired freeze", func(m map[string]any) {
					m["createdAt"] = version.now.Add(-7*24*time.Hour - time.Nanosecond).Format(time.RFC3339Nano)
				}, false},
				{"latest freeze", func(m map[string]any) { m["createdAt"] = version.now.Add(10 * time.Minute).Format(time.RFC3339Nano) }, true},
				{"future freeze", func(m map[string]any) {
					m["createdAt"] = version.now.Add(10*time.Minute + time.Nanosecond).Format(time.RFC3339Nano)
				}, false},
				{"missing context", func(m map[string]any) { delete(m, "context") }, false},
				{"null context", func(m map[string]any) { m["context"] = nil }, false},
				{"unknown game mode", func(m map[string]any) { m["context"].(map[string]any)["gameMode"] = "unknown" }, false},
				{"private context field", func(m map[string]any) { m["context"].(map[string]any)["roomId"] = "secret" }, false},
				{"null attachments", func(m map[string]any) { m["attachments"] = nil }, false},
				{"duplicate attachment", func(m map[string]any) {
					a := Attachment{ID: "screen", Kind: "screenshot", MediaType: "image/png", ByteLength: 1, SHA256: strings.Repeat("0", 64)}
					m["attachments"] = []Attachment{a, a}
				}, false},
				{"oversized attachment", func(m map[string]any) {
					m["attachments"] = []Attachment{{ID: "screen", Kind: "screenshot", MediaType: "image/png", ByteLength: MaxImage + 1, SHA256: strings.Repeat("0", 64)}}
				}, false},
			} {
				t.Run(test.name, func(t *testing.T) {
					var fields map[string]any
					if err := json.Unmarshal(version.raw, &fields); err != nil {
						t.Fatal(err)
					}
					test.change(fields)
					raw, err := json.Marshal(fields)
					if err != nil {
						t.Fatal(err)
					}
					err = version.validate(raw)
					if test.valid && err != nil || !test.valid && !errors.Is(err, ErrInvalid) {
						t.Fatalf("valid=%v, validation error=%v", test.valid, err)
					}
				})
			}
		})
	}
}

func TestPublicManifestRetainsEscapedContentLimit(t *testing.T) {
	config, sub := publicFixture(t)
	now := time.Date(2026, 10, 22, 12, 1, 0, 0, time.UTC)
	m := sub.Manifest
	legacy := Manifest{SchemaVersion: 1, SubmissionID: m.SubmissionID, CreatedAt: m.CreatedAt, Category: m.Category, Context: m.Context, Attachments: m.Attachments}
	base, err := json.Marshal(legacy)
	if err != nil {
		t.Fatal(err)
	}
	remaining := MaxManifest - len(base)
	// Each literal '<' occupies one submitted byte but six HTML-escaped bytes.
	m.Description = strings.Repeat("<", remaining/6) + strings.Repeat("x", remaining%6)
	for _, extra := range []int{0, 1} {
		candidate := m
		candidate.Description += strings.Repeat("x", extra)
		legacy.Description = candidate.Description
		encoded, err := json.Marshal(legacy)
		if err != nil || len(encoded) != MaxManifest+extra {
			t.Fatalf("invalid boundary fixture: size=%d err=%v", len(encoded), err)
		}
		var raw bytes.Buffer
		encoder := json.NewEncoder(&raw)
		encoder.SetEscapeHTML(false)
		if err := encoder.Encode(candidate); err != nil {
			t.Fatal(err)
		}
		if raw.Len() >= MaxManifest {
			t.Fatal("fixture must fit the raw public manifest limit")
		}
		_, err = validatePublicManifest(raw.Bytes(), m.SubmissionID, now, config)
		if extra == 0 && err != nil || extra == 1 && !errors.Is(err, ErrInvalid) {
			t.Fatalf("escaped content size=%d, validation error=%v", len(encoded), err)
		}
		// V1 bounds the uploaded bytes only; shared validation must not impose
		// the public path's compatibility encoding limit on private submissions.
		raw.Reset()
		if err := encoder.Encode(legacy); err != nil {
			t.Fatal(err)
		}
		if _, err := validateManifest(raw.Bytes(), m.SubmissionID, now); err != nil {
			t.Fatal("private raw-byte limit changed", err)
		}
	}
}
