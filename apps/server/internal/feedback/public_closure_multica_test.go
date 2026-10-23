// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"bytes"
	"errors"
	"strings"
	"testing"
	"time"
)

func TestPublicCloseNativeChangedWakeupSupersedesStalePending(t *testing.T) {
	s, now := publicStoreTest(t)
	sub := multicaSubmission(t, multicaTestPolicy)
	finishRoot(t, s, sub)
	id := sub.Manifest.SubmissionID
	old := multicaPrepare(t, s, id)
	oldRevision := old.Event.InputRevision
	if _, err := s.CloseCase(id, testSecret); err != nil {
		t.Fatal(err)
	}
	if err := s.RecordMulticaDelivery(id, bridgeTestBinding, old.Key, multicaResult("accepted")); !errors.Is(err, ErrConflict) {
		t.Fatal("late active response acknowledged closed input", err)
	}
	closed := multicaPrepare(t, s, id)
	if closed.Key == old.Key || closed.Event.Event != "hexproof.feedback.changed" || closed.Event.InputRevision != oldRevision+1 || closed.Event.RevocationRevision != 0 || closed.Attempts != 1 {
		t.Fatal("closure did not immediately supersede stale dispatch", closed)
	}
	r, _, _ := s.read(id)
	if !r.CoordinatorExported || r.CoordinatorBinding != bridgeTestBinding || r.RevocationRevision != 0 || r.RevocationAcknowledged || r.Receipt.RemovalState != "none" {
		t.Fatal("close altered purge/export obligations", r)
	}
	snapshot, err := s.ExportMulticaCase(id, bridgeTestBinding, "other-policy-v1")
	if err != nil || snapshot.State != "closed" || snapshot.InputRevision != closed.Event.InputRevision || snapshot.IssueURL != "" || len(snapshot.Contributions) != 0 || len(snapshot.Replies) != 0 || snapshot.QuestionPublication != nil || snapshot.LatestProjection != nil {
		t.Fatal("closed metadata snapshot exported history", snapshot, err)
	}
	h := multicaNativeHandler(s, bridgeTestBinding, multicaTestPolicy)
	request := MulticaNativeRequest{Action: "snapshot", CaseID: id, Binding: bridgeTestBinding}
	w := nativeRuntimeCall(t, h, request)
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"State":"closed"`) || bytes.Contains(w.Body.Bytes(), []byte(sub.Manifest.Description)) {
		t.Fatal(w.Code, w.Body.String())
	}
	p := deliveryProjectionFixture(snapshot, "ready", 1)
	request.Action, request.Projection = "project", &p
	if w = nativeRuntimeCall(t, h, request); w.Code != 410 {
		t.Fatal("closed native case accepted a projection", w.Code, w.Body.String())
	}
	request.Action, request.Projection = "ack-revocation", nil
	if w = nativeRuntimeCall(t, h, request); w.Code != 400 {
		t.Fatal("closure exposed cleanup acknowledgment", w.Code)
	}
	s = reopenMulticaStore(t, s, now)
	*now = now.Add(time.Minute)
	retry := multicaPrepare(t, s, id)
	if retry.Key != closed.Key || retry.Event != closed.Event || retry.Attempts != 2 {
		t.Fatal("restart replaced closure notification identity", retry)
	}
	if err := s.RecordMulticaDelivery(id, bridgeTestBinding, retry.Key, multicaResult("accepted")); err != nil {
		t.Fatal(err)
	}
	if next, err := s.PrepareMulticaDelivery(id, bridgeTestBinding, multicaTestPolicy); err != nil || next != nil {
		t.Fatal("unchanged closed case notified again", next, err)
	}
}

func TestPublicCloseUnexportedCaseDoesNotCreateProcessorObligation(t *testing.T) {
	s, _ := publicStoreTest(t)
	sub := multicaSubmission(t, multicaTestPolicy)
	if _, _, err := s.Accept(testSecret, sub); err != nil {
		t.Fatal(err)
	}
	id := sub.Manifest.SubmissionID
	if _, err := s.CloseCase(id, testSecret); err != nil {
		t.Fatal(err)
	}
	if d, err := s.PrepareMulticaDelivery(id, bridgeTestBinding, multicaTestPolicy); err != nil || d != nil {
		t.Fatal("unexported closed case created native work", d, err)
	}
	for _, export := range []func() (CaseSnapshot, error){
		func() (CaseSnapshot, error) { return s.ExportCase(id, bridgeTestBinding) },
		func() (CaseSnapshot, error) { return s.ExportMulticaCase(id, bridgeTestBinding, multicaTestPolicy) },
	} {
		snapshot, err := export()
		if err != nil || snapshot.State != "closed" || len(snapshot.Contributions) != 0 {
			t.Fatal(snapshot, err)
		}
	}
	r, _, _ := s.read(id)
	if r.CoordinatorExported || r.CoordinatorBinding != "" || r.MulticaDelivery != nil {
		t.Fatal("empty closed snapshot became a content export", r)
	}
}
