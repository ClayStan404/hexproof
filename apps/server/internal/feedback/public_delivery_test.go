// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"errors"
	"strings"
	"testing"
)

func deliveryProjectionFixture(snapshot CaseSnapshot, state string, revision int64) ProjectionRequest {
	p := ProjectionRequest{ID: projectionID(bridgeTestBinding, snapshot.CaseID, revision), WorkflowRevision: revision, ExpectedInputRevision: snapshot.InputRevision, WorkState: state, Summary: "Verified public delivery update."}
	if state == "source-published-awaiting-release" {
		p.Outcome = &PublicOutcome{Kind: "source", Repository: "example/project", Commit: strings.Repeat("a", 40)}
	} else if state == "released" {
		p.Outcome = &PublicOutcome{Kind: "release", Repository: "example/project", Commit: strings.Repeat("a", 40), Tag: "v3.0.1", Version: "3.0.1"}
	}
	return p
}

func TestPublicDeliveryCommentRetainsDistinctHeading(t *testing.T) {
	for _, state := range []string{"merged-awaiting-release", "source-published-awaiting-release", "released"} {
		projection := deliveryProjectionFixture(CaseSnapshot{CaseID: projectionTestID, InputRevision: 1}, state, 1)
		publisher := &GitHubPublisher{}
		body := publisher.commentBody(PublicJob{ID: projectionTestID, Contribution: &publicContribution{ID: projection.ID, Digest: projectionDigest(projection)}, Payload: &publicContributionPayload{Projection: &projection}})
		if !strings.HasPrefix(body, "Official Hexproof delivery update.") || !strings.Contains(body, "State: `"+state+"`") || !strings.Contains(body, projection.Summary) {
			t.Fatal("public delivery comment omitted its phase or summary", state, body)
		}
	}
}

func TestPublicDeliveryStatesRequirePublicationAndCurrentInput(t *testing.T) {
	_, submission := publicFixture(t)
	store, _ := publicStoreTest(t)
	finishRoot(t, store, submission)
	snapshot, err := store.ExportCase(submission.Manifest.SubmissionID, bridgeTestBinding)
	if err != nil {
		t.Fatal(err)
	}
	previous := "new"
	var released ProjectionRequest
	for i, state := range []string{"merged-awaiting-release", "source-published-awaiting-release", "released"} {
		projection := deliveryProjectionFixture(snapshot, state, int64(i+1))
		if _, err = store.EnqueueProjection(submission.Manifest.SubmissionID, bridgeTestBinding, projection); err != nil {
			t.Fatal(err)
		}
		pending, err := store.Thread(submission.Manifest.SubmissionID, testSecret, "", 5)
		if err != nil || pending.WorkState != previous || pending.ProjectionState != "pending" {
			t.Fatal("unpublished delivery state became current", pending, err)
		}
		finishChild(t, store, projection.ID)
		published, err := store.Thread(submission.Manifest.SubmissionID, testSecret, "", 5)
		if err != nil || published.WorkState != state || published.Summary != projection.Summary || published.WorkflowRevision != int64(i+1) {
			t.Fatal("verified delivery was not projected", published, err)
		}
		previous, released = state, projection
	}
	if _, err = store.EnqueueProjection(submission.Manifest.SubmissionID, bridgeTestBinding, released); err != nil {
		t.Fatal("exact replay lost idempotency", err)
	}
	if job, err := store.Claim(); err != nil || job != nil {
		t.Fatal("release projection must not enqueue an issue close or duplicate comment", job, err)
	}
	if _, _, err = store.AcceptReply(submission.Manifest.SubmissionID, testSecret, replyFixture(t, submission, replyTestID)); err != nil {
		t.Fatal(err)
	}
	finishChild(t, store, replyTestID)
	thread, err := store.Thread(submission.Manifest.SubmissionID, testSecret, "", 5)
	if err != nil || thread.WorkState != "new" || thread.Summary != "" || thread.WorkflowRevision != 0 {
		t.Fatal("new public context retained stale current release status", thread, err)
	}
	if thread.Outcome != nil || len(thread.DeliveryHistory) != 2 || thread.DeliveryHistory[1].InputRevision != 1 || thread.DeliveryHistory[1].Outcome.Version != "3.0.1" {
		t.Fatal("new input erased delivery history or claimed the old release as current", thread)
	}
	snapshotAfter, err := store.ExportCase(submission.Manifest.SubmissionID, bridgeTestBinding)
	if err != nil || len(snapshotAfter.DeliveryHistory) != 2 || len(snapshotAfter.PublishedProjections) != 3 || snapshotAfter.Contributions[0].Description != submission.Manifest.Description || snapshotAfter.Contributions[0].Category != submission.Manifest.Category || snapshotAfter.Contributions[0].Context != submission.Manifest.Context {
		t.Fatal("structured conversation/history unavailable", snapshotAfter, err)
	}
	newProjection := deliveryProjectionFixture(snapshot, "released", 4)
	if _, err = store.EnqueueProjection(submission.Manifest.SubmissionID, bridgeTestBinding, newProjection); !errors.Is(err, ErrInvalid) {
		t.Fatal("stale delivery input was republished", err)
	}
	if err = store.Close(); err != nil {
		t.Fatal(err)
	}
	recovered, err := openPublicStore(store.dir, Limits{}, store.now, nil)
	if err != nil {
		t.Fatal("typed outcomes did not recover", err)
	}
	defer recovered.Close()
	if _, err = recovered.CloseCase(submission.Manifest.SubmissionID, testSecret); err != nil {
		t.Fatal(err)
	}
	thread, err = recovered.Thread(submission.Manifest.SubmissionID, testSecret, "", 5)
	if err != nil || thread.CaseState != "closed" || len(thread.DeliveryHistory) != 2 {
		t.Fatal("closure/recovery erased delivery history", thread, err)
	}
	if _, err = recovered.Remove(submission.Manifest.SubmissionID, testSecret); err != nil {
		t.Fatal(err)
	}
	thread, err = recovered.Thread(submission.Manifest.SubmissionID, testSecret, "", 5)
	if err != nil || len(thread.DeliveryHistory) != 0 || thread.Outcome != nil {
		t.Fatal("removed history remained visible", thread, err)
	}
	removed, err := recovered.ExportCase(submission.Manifest.SubmissionID, bridgeTestBinding)
	if err != nil || len(removed.DeliveryHistory) != 0 || len(removed.PublishedProjections) != 0 {
		t.Fatal("removed history exported", removed, err)
	}
}
