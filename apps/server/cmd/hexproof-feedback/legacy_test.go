// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package main

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"hexproof/server/internal/feedback"
)

func TestPublicStartupPreservesUnfinishedPrivateDelivery(t *testing.T) {
	config := feedback.Config{DataDir: t.TempDir(), Public: &feedback.PublicConfig{}}
	legacy, err := openLegacyCompatibility(config, nil)
	if err != nil {
		t.Fatal(err)
	}
	const id = "83bd35d6-dd11-4a73-9f35-4ed43b6ab8b1"
	secret := []byte(strings.Repeat("a", 32))
	manifest := feedback.Manifest{SchemaVersion: 1, SubmissionID: id,
		CreatedAt: time.Now().UTC().Format(time.RFC3339Nano), Category: "problem",
		Description: "Legacy private report", Attachments: []feedback.Attachment{}}
	raw, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	reservation, err := legacy.store.Reserve()
	if err != nil {
		t.Fatal(err)
	}
	receipt, created, err := legacy.store.Accept(context.Background(), reservation, secret,
		feedback.Submission{Manifest: manifest, Digest: feedback.Digest(raw), Blobs: []feedback.Blob{}})
	reservation.Release()
	if err != nil || !created {
		t.Fatalf("accept: created=%v error=%v", created, err)
	}
	if err := legacy.store.Close(); err != nil {
		t.Fatal(err)
	}
	if got, err := openLegacyCompatibility(config, nil); err == nil {
		got.store.Close()
		t.Fatal("public startup silently abandoned private delivery")
	}
	// Failed cutover releases its lock and preserves both the receipt and mail.
	store, err := feedback.OpenStore(config.DataDir, feedback.Limits{})
	if err != nil {
		t.Fatal(err)
	}
	got, err := store.Lookup(context.Background(), id, secret, "")
	if err != nil || got != receipt {
		t.Fatalf("private receipt changed: %#v %v", got, err)
	}
	job, err := store.Claim(context.Background())
	if err != nil || job == nil || job.Record.Submission.Manifest.Description != manifest.Description {
		t.Fatalf("private delivery lost: %#v %v", job, err)
	}
	if err = store.Finish(context.Background(), *job, feedback.MailResult{State: "handed_off"}); err != nil {
		t.Fatal(err)
	}
	if err = store.Close(); err != nil {
		t.Fatal(err)
	}
	// Drained private history can be retained by a public deployment without SMTP.
	legacy, err = openLegacyCompatibility(config, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer legacy.store.Close()
	got, err = legacy.store.Lookup(context.Background(), id, secret, "")
	if err != nil || got != receipt {
		t.Fatalf("drained receipt lost: %#v %v", got, err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	legacy.run(ctx)
}
