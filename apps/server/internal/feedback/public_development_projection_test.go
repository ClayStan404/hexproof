// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"encoding/json"
	"testing"
)

func TestPublicDevelopmentStatesPublishAndReachThread(t *testing.T) {
	config, submission := publicFixture(t)
	store, _ := publicStoreTest(t)
	finishRoot(t, store, submission)
	snapshot, err := store.ExportCase(submission.Manifest.SubmissionID, bridgeTestBinding)
	if err != nil {
		t.Fatal(err)
	}
	handler := NewPublicHandler(store, config, nil, Limits{}, nil)
	defer handler.Close()
	previous := "new"
	for index, state := range []string{"implementing", "verifying", "verified-awaiting-review", "reviewing", "verifying-integration", "merge-ready", "merging"} {
		t.Run(state, func(t *testing.T) {
			projection := ProjectionRequest{ID: projectionID(bridgeTestBinding, snapshot.CaseID, int64(index+1)), WorkflowRevision: int64(index + 1), ExpectedInputRevision: snapshot.InputRevision, WorkState: state, Summary: "Public development progress."}
			receipt, err := store.EnqueueProjection(submission.Manifest.SubmissionID, bridgeTestBinding, projection)
			if err != nil || receipt.PublicationState != "pending" {
				t.Fatal(receipt, err)
			}
			read := func() PublicThread {
				response := publicRequest(handler, "GET", submission.Manifest.SubmissionID+"/thread", submission, testSecret)
				var thread PublicThread
				if response.Code != 200 || json.Unmarshal(response.Body.Bytes(), &thread) != nil {
					t.Fatal(response.Code, response.Body.String())
				}
				return thread
			}
			pending := read()
			if pending.WorkState != previous || pending.ProjectionState != "pending" {
				t.Fatal("unverified projection became authoritative", pending)
			}
			finishChild(t, store, projection.ID)
			published := read()
			if published.WorkState != state || published.WorkflowRevision != int64(index+1) || published.ProjectionState != "published" {
				t.Fatal("published development phase was not delivered", published)
			}
			previous = state
		})
	}
}
